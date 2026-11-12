local _, ns = ...
local L, R = ns.L, ns.Recruit
local H = {}
R.Handoff = H

-- Private, in-memory referral. The offer and claim contain no applicant data. The
-- origin gives the applicant's name to one officer only after that officer claims.
local TTL, LIMIT, MAX_GUILD, MAX_NAME = 90, 6, 64, 100
local PROBE_TTL, AUTO_EVERY = 20, 8
local incoming, outgoing = {}, {}
local acceptingGuild, choosing, serial
local autoGuild, autoTimer, autoProbe, autoCursor
local repliedAt = -math.huge
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

-- Our own guild uses its complete native roster. Other guilds need a fresh census
-- and signed rank or two corroborating census reports, never the packet's own claim.
local function Officer(name, guild)
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
	return type(rank) == "number" and rank >= 0 and rank <= ns.CAPTAIN_RANK
end

local function LocalGuild()
	local guild = ns.group and ns.faction and ns.IsMember() and GetGuildInfo("player") or nil
	if guild and R.CanInvite() and Officer(ns.me, guild) then return guild end
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
	return R.HandoffSource(ref.request) and (not ref.automatic
		or (AutoAllowed(ref.from) and not R.HandoffPromptOpen(ref.request)))
end

local function NextID(now)
	serial = serial + 1
	return ("%d-%x-%d"):format(now, math.random(1, 1073741823), serial)
end

function H.Offer(req, peer, guild, automatic)
	local own, now = LocalGuild(), math.floor(ns.Now())
	Prune(now)
	if not own or not R.HandoffSource(req) or H.State(req) or not Room(outgoing)
		or not Officer(peer, guild) or SamePlayer(peer, ns.me)
		or (req.handoffIntent ~= "federation" and not Same(own, guild)) then return false end
	if automatic and (not AutoAllowed(own) or not Same(own, guild)
		or R.HandoffPromptOpen(req) or not Room(outgoing, LIMIT - 1)) then return false end
	local ref = {
		id = NextID(now), expires = now + TTL, from = own, to = guild, peer = peer,
		request = req, state = "offered", automatic = automatic,
	}
	req.handoff, outgoing[ref.id] = ref, ref
	local function Guard()
		return ref.expires > ns.Now() and ref.from == LocalGuild() and ref.state == "offered"
			and SourceReady(ref) and Officer(peer, guild)
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
		or not Officer(ref.peer, ref.from) then return false end
	ref.state = "claiming"
	local function Guard()
		return incoming[ref.id] == ref and ref.expires > ns.Now() and Accepting()
			and Same(acceptingGuild, ref.to) and Officer(ref.peer, ref.from)
	end
	if not Transmit("C", ref, ref.peer, nil, Guard) then ref.state = "offered"; return false end
	Changed()
	return true
end

local function AutoStep()
	local own, now = LocalGuild(), math.floor(ns.Now())
	if not AutoAllowed(own) then autoProbe = nil; return end
	Prune(now)
	local req = Room(outgoing, LIMIT - 1) and R.OverflowRequest()
	if not req then autoProbe = nil; return end
	if autoProbe and autoProbe.expires > now then
		if not autoProbe.available then return end
		local peer = autoProbe.peer
		autoProbe = nil
		H.Offer(req, peer, own, true)
		return
	end
	autoProbe = nil
	local roster, peer = ns.Roster.online or {}, nil
	for offset = 1, #roster do
		local i = ((autoCursor or 0) + offset - 1) % #roster + 1
		local name = ns.FullName(roster[i].name)
		if not SamePlayer(name, ns.me) and Officer(name, own) then
			autoCursor, peer = i, name
			break
		end
	end
	if not peer then return end
	local ref = { id = NextID(now), expires = now + PROBE_TTL, from = own, to = own, peer = peer }
	autoProbe = ref
	local function Guard()
		return autoProbe == ref and ref.expires > ns.Now() and LocalGuild() == own
			and AutoAllowed(own) and Officer(ref.peer, own) and R.OverflowRequest() ~= nil
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
			or not Officer(sender, own) then return false end
		if op == "V" then
			local ref = autoProbe
			if not AutoAllowed(own) or not ref or ref.available or id ~= ref.id or expires ~= ref.expires
				or not SamePlayer(sender, ref.peer) then return false end
			ref.available = true
			return true
		end
		if not Accepting() or not Room(incoming) or now - repliedAt < AUTO_EVERY then return false end
		local ref = { id = id, expires = expires, from = own, to = own }
		repliedAt = now
		return Transmit("V", ref, sender, nil, function()
			return expires > ns.Now() and acceptingGuild == own and Accepting() and AvailableNow()
				and Room(incoming) and Officer(sender, own)
		end)
	end
	if op == "O" or op == "N" then
		if not Accepting() or not Same(own, to) or not Officer(sender, from) then return false end
		if op == "O" then
			if incoming[id] or not Room(incoming) then return false end
			incoming[id] = { id = id, expires = expires, from = from, to = to, peer = sender, state = "offered" }
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
				return ref.expires > ns.Now() and Accepting() and Same(acceptingGuild, to) and Officer(sender, from)
			end)
		end
	else
		local ref = outgoing[id]
		if not ref or ref.expires ~= expires or ref.from ~= from or ref.to ~= to or not SamePlayer(ref.peer, sender)
			or ref.from ~= own or not Officer(sender, to) then return false end
		if op == "C" then
			if ref.state ~= "offered" or not SourceReady(ref) then return false end
			-- A queued or delivered name might have been acted on even without an
			-- acknowledgement, so the origin stays locked rather than retry elsewhere.
			ref.state = "assigning"
			local function Guard()
				local ready = ref.expires > ns.Now() and ref.from == LocalGuild() and SourceReady(ref)
					and Officer(sender, to) and ref.state == "assigning"
				return ready, "invalid"
			end
			local function Done(sent, why)
				-- Only a guard refusal proves the queued name never left. Retain the lock for
				-- an ambiguous transport result so a second officer cannot receive that name.
				if not sent and why == "invalid" and ref.automatic and ref.request.handoff == ref then
					ref.request.handoff, outgoing[ref.id] = nil, nil
					Changed()
				end
			end
			if not Transmit("N", ref, sender, ref.request.name, Guard, Done) then
				ref.state = "offered"
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
		if seen[key] or SamePlayer(who, ns.me) or not Officer(who, guild) then return end
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

function H.Controls(lines, V)
	local own = LocalGuild()
	if not own then return end
	Prune(ns.Now())
	lines[#lines + 1] = {
		text = Accepting() and V.Green(L.RECRUIT_HANDOFF_ON) or V.Grey(L.RECRUIT_HANDOFF_OFF), onClick = H.Toggle,
	}
	lines[#lines + 1] = { text = autoGuild == own and V.Green(L.RECRUIT_OVERFLOW_ON) or V.Grey(L.RECRUIT_OVERFLOW_OFF),
		onClick = H.ToggleAuto }
	if not Accepting() then return end
	for _, ref in pairs(incoming) do
		if Same(ref.to, own) and Officer(ref.peer, ref.from) and ref.state ~= "received" then
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

function H.Reset()
	acceptingGuild, choosing = nil, nil
	if autoTimer then autoTimer.Cancel(); autoTimer = nil end
	autoGuild, autoProbe, autoCursor, repliedAt = nil, nil, nil, -math.huge
	wipe(incoming)
	wipe(outgoing)
end
