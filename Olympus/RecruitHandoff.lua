local _, ns = ...
local L, R = ns.L, ns.Recruit
local H = {}
R.Handoff = H

-- Private, in-memory referral. The offer and claim contain no applicant data. The
-- origin gives the applicant's name to one member only after that member claims.
local TTL, LIMIT, MAX_GUILD, MAX_NAME = 90, 6, 64, 100
local PROBE_TTL, AUTO_EVERY = 20, 8
local incoming, outgoing = {}, {}
local handed = {} -- [folded name] = true: a player this client gave to another member
local acceptingGuild, choosing, serial
local autoGuild, autoTimer, autoProbe, autoCursor
local repliedAt = -math.huge
local Notify
serial = 0

local function Field(s, limit)
	return type(s) == "string" and #s > 0 and #s <= limit and not s:find("[~|%c]")
end

local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and ns.Fold(a) == ns.Fold(b)
end

local function InScope(name)
	if not Field(name, MAX_NAME) or not ns.InGroup(ns.RealmOf(name)) then return false end
	local region = (ns.realm or ""):match("^CAMWOW(%u%u)")
	return not region or (ns.RealmOf(name) or ""):match("^CAMWOW(%u%u)") == region
end

local function SamePlayer(a, b)
	if Same(a, b) then return true end
	return ns.splitNames and InScope(a) and InScope(b) and Same(ns.ShortName(a), ns.ShortName(b))
end

-- What can be handed on: a JOIN request, or (1.5.8) an unguilded player the scan found (a row of
-- Candidates, `scanned`). Either one's name goes out the same way, only after a Claim.
local function NameOf(item) return item.scanned and item.full or item.name end
local function NameKey(name)
	local who = ns.FullName(name)
	return ns.Fold(ns.splitNames and ns.ShortName(who) or who)
end
local function Source(item, blocked)
	if type(item) ~= "table" then return false end
	if item.scanned then return R.Candidates ~= nil and R.Candidates.Passable(item) end
	return R.HandoffSource(item, blocked)
end
local function PromptOpen(item)
	if item.scanned then return R.CandidatePromptOpen(item) end
	return R.HandoffPromptOpen(item)
end

-- Who may give or take a handoff. Our own guild: any member on its complete native roster (1.5.8,
-- the author's: "o repasse tem que ir para qualquer pessoa que esteja com a feature ativa. Não
-- precisa ser só para officer"); the game's own invite permission is checked on each side by its
-- own client (LocalGuild). Other guilds need a fresh census and signed rank or two corroborating
-- census reports, never the packet's own claim.
local function Member(name, guild)
	if not InScope(name) or not Field(guild, MAX_GUILD) or not ns.IsFederation(guild) then return false end
	if ns.db and ns.db.blocked and ns.db.blocked[name:lower()] then return false end
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(name, guild, true) then return false end
	local rank, source, support
	if Same(GetGuildInfo("player"), guild) then
		if not ns.Roster.Fresh() then return false end
		rank = ns.Roster.RankOf(name)
	else
		if not ns.Data.CanRank(guild) then return false end
		rank, source, support = ns.Data.AuthorizedRank(name, guild)
		if source ~= "signed" and (source ~= "census" or (support or 0) < 2) then return false end
	end
	return type(rank) == "number" and rank >= 0
end

local function LocalGuild()
	local guild = ns.group and ns.faction and ns.IsMember() and GetGuildInfo("player") or nil
	if guild and R.CanInvite() and Member(ns.me, guild) then return guild end
end

local function Accepting()
	return acceptingGuild ~= nil and acceptingGuild == LocalGuild()
end

local function Changed()
	ns.Fire("DATA_CHANGED")
end

local function Prune(now)
	for id, r in pairs(incoming) do if r.expires <= now then incoming[id] = nil end end
	for id, r in pairs(outgoing) do if r.expires <= now then outgoing[id] = nil end end
end

local function Room(rows, limit)
	local n = 0
	for _ in pairs(rows) do n = n + 1 end
	return n < (limit or LIMIT)
end

local function Transmit(op, ref, peer, applicant, guard, done)
	local word = table.concat({ "J4", op, ref.id, ref.expires, ns.group, ns.faction, ref.from, ref.to, applicant or "" }, "~")
	if #word > 255 then return false end
	return ns.Comm.Whisper(peer, word, nil, false, false, done, { guard = guard })
end

function H.State(req)
	local ref = type(req) == "table" and req.handoff
	if not ref or (ref.state == "offered" and ref.expires <= ns.Now()) then return nil end
	return ref.state
end

-- One player is offered once (1.5.8): a name this client already gave away, or the same player
-- under way as another entry (a JOIN and a scan sighting), never goes out again. A scanned player
-- who also sent a JOIN is left to the JOIN.
local function Duplicate(item)
	local name = NameOf(item)
	if handed[NameKey(name)] then return true end
	for _, ref in pairs(outgoing) do
		if ref.request ~= item and H.State(ref.request) and SamePlayer(NameOf(ref.request), name) then return true end
	end
	if item.scanned then
		for _, req in ipairs(R.requests) do if SamePlayer(req.name, name) then return true end end
	end
	return false
end

local function NextOverflow()
	return R.OverflowRequest(Duplicate) or (R.Candidates and R.Candidates.Overflow(Duplicate)) or nil
end

function H.Toggle()
	if acceptingGuild then
		acceptingGuild = nil
		wipe(incoming)
	elseif LocalGuild() then
		acceptingGuild = LocalGuild()
	end
	Changed()
	return Accepting()
end

local function AvailableNow()
	return not ns.ChatLocked() and not ns.QuietPresence() and not (InCombatLockdown and InCombatLockdown())
end

local function AutoAllowed(own)
	return own ~= nil and autoGuild == own and AvailableNow()
end

local function SourceReady(ref)
	return Source(ref.request) and (not ref.automatic
		or (AutoAllowed(ref.from) and not PromptOpen(ref.request)))
end

local function NextID(now)
	serial = serial + 1
	return ("%d-%x-%d"):format(now, math.random(1, 1073741823), serial)
end

function H.Offer(req, peer, guild, automatic)
	local own, now = LocalGuild(), math.floor(ns.Now())
	Prune(now)
	if not own or not Source(req) or H.State(req) or not Room(outgoing) or Duplicate(req)
		or not Member(peer, guild) or SamePlayer(peer, ns.me)
		or (req.handoffIntent ~= "federation" and not Same(own, guild)) then return false end
	if automatic and (not AutoAllowed(own) or not Same(own, guild)
		or PromptOpen(req) or not Room(outgoing, LIMIT - 1)) then return false end
	local ref = {
		id = NextID(now), expires = now + TTL, from = own, to = guild, peer = peer,
		request = req, state = "offered", automatic = automatic,
	}
	req.handoff, outgoing[ref.id] = ref, ref
	local function Guard()
		return ref.expires > ns.Now() and ref.from == LocalGuild() and ref.state == "offered"
			and SourceReady(ref) and Member(peer, guild)
	end
	if not Transmit("O", ref, peer, nil, Guard) then
		req.handoff, outgoing[ref.id] = nil, nil
		return false
	end
	choosing = nil
	Changed()
	return true
end

function H.Claim(ref)
	if type(ref) ~= "table" or incoming[ref.id] ~= ref or ref.state ~= "offered"
		or ref.expires <= ns.Now() or not Accepting() or not Same(acceptingGuild, ref.to)
		or not Member(ref.peer, ref.from) then return false end
	ref.state = "claiming"
	local function Guard()
		return incoming[ref.id] == ref and ref.expires > ns.Now() and Accepting()
			and Same(acceptingGuild, ref.to) and Member(ref.peer, ref.from)
	end
	if not Transmit("C", ref, ref.peer, nil, Guard) then ref.state = "offered"; return false end
	Changed()
	return true
end

local function AutoStep()
	local own, now = LocalGuild(), math.floor(ns.Now())
	if not AutoAllowed(own) then autoProbe = nil; return end
	Prune(now)
	local req = Room(outgoing, LIMIT - 1) and NextOverflow()
	if not req then autoProbe = nil; return end
	if autoProbe and autoProbe.expires > now then
		if not autoProbe.available then return end
		local peer = autoProbe.peer
		autoProbe = nil
		H.Offer(req, peer, own, true)
		return
	end
	autoProbe = nil
	-- (1.5.8) Any member may take handoffs now, so in a large guild the probes go first, in turn, to
	-- the members this client knows run Olympus (their hello); the others only when it knows none.
	local roster, peer = ns.Roster.online or {}, nil
	local V = ns.Versions
	local known = V and V.HasOlympus
	for pass = known and 1 or 2, 2 do
		for offset = 1, #roster do
			local i = ((autoCursor or 0) + offset - 1) % #roster + 1
			local name = ns.FullName(roster[i].name)
			if (pass == 2 or known(name)) and not SamePlayer(name, ns.me) and Member(name, own) then
				autoCursor, peer = i, name
				break
			end
		end
		if peer then break end
	end
	if not peer then return end
	local ref = { id = NextID(now), expires = now + PROBE_TTL, from = own, to = own, peer = peer }
	autoProbe = ref
	local function Guard()
		return autoProbe == ref and ref.expires > ns.Now() and LocalGuild() == own
			and AutoAllowed(own) and Member(ref.peer, own) and NextOverflow() ~= nil
	end
	if not Transmit("P", ref, ref.peer, nil, Guard) then autoProbe = nil end
end

function H.ToggleAuto()
	if autoTimer then autoTimer.Cancel(); autoTimer = nil end
	autoGuild, autoProbe, autoCursor = not autoGuild and LocalGuild() or nil, nil, nil
	if autoGuild then autoTimer = ns.Every(AUTO_EVERY, "recruit overflow", AutoStep) end
	Changed()
	return autoGuild ~= nil
end

-- A JOIN (or a scanned player) this member can still hand on: its invite not prepared (or,
-- `blocked`, prepared and refused by the game, in his own words), and no handoff under way.
function H.CanPass(req, blocked)
	return type(req) == "table" and LocalGuild() ~= nil and not H.State(req)
		and Source(req, blocked) and not Duplicate(req) and true or false
end

function H.AutoOn()
	local own = LocalGuild()
	return own ~= nil and autoGuild == own
end

local function Want(item)
	item.passWanted = true
	if autoGuild ~= LocalGuild() then
		if autoGuild then H.ToggleAuto() end
		H.ToggleAuto()
	end
	ns.After(0, "recruit pass", AutoStep)
	Changed()
end

-- The member's click: this JOIN (`all`: and the ones waiting behind it) or scanned player goes
-- to the guild's members who accept handoffs, one at a time, through the same probe and claim as
-- the automatic overflow, which this turns on. Until one claims it, it stays in his queue.
function H.Pass(req, all)
	if not H.CanPass(req) then return false end
	if all and not req.scanned then
		for _, other in ipairs(R.requests) do
			if other ~= req and not other.passWanted and H.CanPass(other) then other.passWanted = true end
		end
	end
	Want(req)
	ns.Print(L.RECRUIT_HANDOFF_PASSING)
	return true
end

-- (1.5.8) At this player's invite limit, with the automatic offers on, a new JOIN or scanned player
-- goes to the other members instead of popping up here (Church > Invites still lists it).
function H.Overflow(item)
	if not H.AutoOn() or not H.CanPass(item) then return false end
	Want(item)
	return true
end

function H.PassBlocked(req)
	if not H.CanPass(req, true) then return false end
	req.invitePrepared = nil
	return H.Pass(req)
end

-- An offer for a member who accepts handoffs: a chat line, and a Claim question when nothing
-- else of the recruitment is on screen. The name still comes only after his Claim click.
local CLAIM_DIALOG = "OLYMPUS_RECRUIT_HANDOFF_CLAIM"
local busyDialogs = { CLAIM_DIALOG, "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_REPLY", "OLYMPUS_RECRUIT_NETOFF" }

Notify = function(ref)
	local who = ns.DisplayName(ref.peer) or ref.peer
	ns.Print(L.RECRUIT_HANDOFF_ARRIVED:format(who, ref.from))
	local D = ns.Dialog
	if not D or D.missing or not D.Show or not AvailableNow() then return end
	for _, which in ipairs(busyDialogs) do if D.Find(which) then return end end
	D.Show(CLAIM_DIALOG, L.RECRUIT_HANDOFF_CLAIM_PROMPT:format(who, ref.from), nil, ref)
end

function H.Receive(dist, sender, word)
	if dist ~= "WHISPER" or type(word) ~= "string" or #word > 255 or SamePlayer(sender, ns.me) then return false end
	local op, id, expires, group, faction, from, to, applicant =
		word:match("^J4~([OCNAPV])~([%d%x%-]+)~(%d+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]*)$")
	expires = tonumber(expires)
	local now, own = ns.Now(), LocalGuild()
	if not own or not expires or expires <= now or expires - now > TTL + 5 or #id > 40
		or group ~= ns.group or faction ~= ns.faction or not Field(from, MAX_GUILD) or not Field(to, MAX_GUILD)
		or (op ~= "N" and applicant ~= "") then return false end
	Prune(now)
	if op == "P" or op == "V" then
		if not AvailableNow() or expires - now > PROBE_TTL + 5 or not Same(own, from) or not Same(own, to)
			or not Member(sender, own) then return false end
		if op == "V" then
			local ref = autoProbe
			if not AutoAllowed(own) or not ref or ref.available or id ~= ref.id or expires ~= ref.expires
				or not SamePlayer(sender, ref.peer) then return false end
			ref.available = true
			return true
		end
		-- (1.5.8) A member at his own invite limit is not available for more names.
		if not Accepting() or not Room(incoming) or now - repliedAt < AUTO_EVERY or R.AtInviteLimit() then return false end
		local ref = { id = id, expires = expires, from = own, to = own }
		repliedAt = now
		return Transmit("V", ref, sender, nil, function()
			return expires > ns.Now() and acceptingGuild == own and Accepting() and AvailableNow()
				and Room(incoming) and Member(sender, own)
		end)
	end
	if op == "O" or op == "N" then
		if not Accepting() or not Same(own, to) or not Member(sender, from) then return false end
		if op == "O" then
			if incoming[id] or not Room(incoming) then return false end
			incoming[id] = { id = id, expires = expires, from = from, to = to, peer = sender, state = "offered" }
			Notify(incoming[id])
		else
			local ref = incoming[id]
			if not ref or ref.state ~= "claiming" or ref.expires ~= expires or not SamePlayer(ref.peer, sender)
				or ref.from ~= from or ref.to ~= to or not InScope(applicant) or SamePlayer(applicant, ns.me) then return false end
			for _, req in ipairs(R.requests) do
				if SamePlayer(applicant, req.name) then return false end
			end
			if not R.TakeHandoff(applicant, sender) then return false end
			ref.state = "received"
			Transmit("A", ref, sender, nil, function()
				return ref.expires > ns.Now() and Accepting() and Same(acceptingGuild, to) and Member(sender, from)
			end)
		end
	else
		local ref = outgoing[id]
		if not ref or ref.expires ~= expires or ref.from ~= from or ref.to ~= to or not SamePlayer(ref.peer, sender)
			or ref.from ~= own or not Member(sender, to) then return false end
		if op == "C" then
			if ref.state ~= "offered" or not SourceReady(ref) then return false end
			-- A queued or delivered name might have been acted on even without an
			-- acknowledgement, so the origin stays locked rather than retry elsewhere.
			ref.state = "assigning"
			local key = NameKey(NameOf(ref.request))
			handed[key] = true
			local function Guard()
				local ready = ref.expires > ns.Now() and ref.from == LocalGuild() and SourceReady(ref)
					and Member(sender, to) and ref.state == "assigning"
				return ready, "invalid"
			end
			local function Done(sent, why)
				-- Only a guard refusal proves the queued name never left. Retain the lock for
				-- an ambiguous transport result so a second member cannot receive that name.
				if not sent and why == "invalid" and ref.automatic and ref.request.handoff == ref then
					ref.request.handoff, outgoing[ref.id], handed[key] = nil, nil, nil
					Changed()
				end
			end
			if not Transmit("N", ref, sender, NameOf(ref.request), Guard, Done) then
				ref.state, handed[key] = "offered", nil
				return false
			end
		else
			if ref.state ~= "assigning" then return false end
			ref.state = "assigned"
		end
	end
	Changed()
	return true
end
ns.Comm.Handle("J4", H.Receive)

local function Contacts(req, own)
	local result, seen = {}, {}
	local function Add(name, guild)
		if #result >= LIMIT or not Field(name, MAX_NAME) then return end
		local who = ns.FullName(name)
		local key = ns.Fold(ns.splitNames and ns.ShortName(who) or who)
		if seen[key] or SamePlayer(who, ns.me) or not Member(who, guild) then return end
		seen[key] = true
		result[#result + 1] = { name = who, guild = guild }
	end
	local ownLimit = req.handoffIntent == "federation" and LIMIT / 2 or LIMIT
	for _, row in ipairs(ns.Roster.online or {}) do
		if #result >= ownLimit then break end
		Add(row.name, own)
	end
	if req.handoffIntent == "federation" then
		for _, entry in ipairs(R.OpenGuilds()) do
			local report = entry.e.g
			if not Same(entry.name, own) then
				if report.leaderOnline and report.leader then Add(ns.FullName(report.leader, report.realm), entry.name) end
				for _, row in ipairs(report.officers or {}) do
					if row.online then Add(ns.FullName(row.name, report.realm), entry.name) end
				end
			end
		end
	end
	return result
end

-- The two switches, as the member sets them, are saved with his recruiting choice (a Pass
-- click turns the overflow on for this session only).
local function Save(field, on)
	local saved = R.Preference and R.Preference(true)
	if saved then saved[field] = on or nil end
	return on
end
local function ToggleSaved() return Save("acceptHandoffs", H.Toggle()) end
local function ToggleAutoSaved() return Save("offerOverflow", H.ToggleAuto()) end

-- (Each use checks the guild against LocalGuild() again, so a roster still loading at login
-- leaves both switches idle until it confirms this member.)
function H.Restore(saved)
	if type(saved) ~= "table" or type(saved.guild) ~= "string" then return end
	if saved.acceptHandoffs == true and not acceptingGuild then
		acceptingGuild = saved.guild
		Changed()
	end
	if saved.offerOverflow == true and not autoGuild then
		autoGuild, autoProbe, autoCursor = saved.guild, nil, nil
		autoTimer = ns.Every(AUTO_EVERY, "recruit overflow", AutoStep)
		Changed()
	end
end

function H.Controls(lines, V)
	local own = LocalGuild()
	if not own then return end
	Prune(ns.Now())
	lines[#lines + 1] = { id = "recruit-handoff-accept",
		text = Accepting() and V.Green(L.RECRUIT_HANDOFF_ON) or V.Grey(L.RECRUIT_HANDOFF_OFF), onClick = ToggleSaved,
	}
	lines[#lines + 1] = { id = "recruit-handoff-overflow",
		text = autoGuild == own and V.Green(L.RECRUIT_OVERFLOW_ON) or V.Grey(L.RECRUIT_OVERFLOW_OFF),
		onClick = ToggleAutoSaved }
	if not Accepting() then return end
	for _, ref in pairs(incoming) do
		if Same(ref.to, own) and Member(ref.peer, ref.from) and ref.state ~= "received" then
			local label = ref.state == "offered" and L.RECRUIT_HANDOFF_CLAIM or L.RECRUIT_HANDOFF_WAITING
			lines[#lines + 1] = {
				indent = 1, text = V.Gold(label:format(ns.DisplayName(ref.peer), ref.from)),
				onClick = ref.state == "offered" and function() H.Claim(ref) end or nil,
			}
		end
	end
end

function H.RequestLines(lines, V, req)
	local state = H.State(req)
	if state then
		lines[#lines + 1] = { indent = 1, text = V.Grey((state == "assigned" and L.RECRUIT_HANDOFF_DONE
			or L.RECRUIT_HANDOFF_PENDING):format(ns.DisplayName(req.handoff.peer), req.handoff.to)) }
		return
	end
	local own = LocalGuild()
	if not own or not R.HandoffSource(req) then return end
	lines[#lines + 1] = { indent = 1, text = V.Gold(L.RECRUIT_HANDOFF_PICK),
		onClick = function() choosing = choosing ~= req and req or nil; Changed() end }
	if choosing ~= req then return end
	local contacts = Contacts(req, own)
	if #contacts == 0 then lines[#lines + 1] = { indent = 2, text = V.Grey(L.RECRUIT_HANDOFF_EMPTY) } end
	for _, contact in ipairs(contacts) do
		lines[#lines + 1] = { indent = 2, text = V.Gold(L.RECRUIT_HANDOFF_OFFER:format(ns.DisplayName(contact.name), contact.guild)),
			onClick = function() H.Offer(req, contact.name, contact.guild) end }
	end
end

StaticPopupDialogs[CLAIM_DIALOG] = {
	text = "%s",
	button1 = L.RECRUIT_HANDOFF_TAKE,
	button2 = L.RECRUIT_HANDOFF_SKIP,
	OnAccept = function(_, ref) H.Claim(ref) end,
	timeout = 60,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function H.Reset()
	acceptingGuild, choosing = nil, nil
	if autoTimer then autoTimer.Cancel(); autoTimer = nil end
	autoGuild, autoProbe, autoCursor, repliedAt = nil, nil, nil, -math.huge
	wipe(incoming)
	wipe(outgoing)
	wipe(handed)
end
