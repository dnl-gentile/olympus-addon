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
local autoGuild, autoTimer, autoProbe
-- (1.5.9) The guild whose players this member passed by hand (Pass), whatever the automatic offers'
-- switch: they go through the same probes, and the switch stays as he left it. (Review of the 1.5.9
-- release: a Pass made with the switch on set none, and the switch then turned off left what he passed
-- with no probe until it expired.)
local passGuild
-- The probes' rotation (NextPeer): per tier, the roster index asked last, and how many of its
-- members were asked since one below it was.
local cursor, turn = {}, {}
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
local function Source(item, blocked, claimed)
	if type(item) ~= "table" then return false end
	if item.scanned then
		-- (Review of 1.5.8) Once the same player whispers JOIN, the JOIN is his entry: a claim of the
		-- sighting's offer no longer gets his name, so two members never invite him. (`claimed`, 1.6.0:
		-- SourceReady's, a claim under way that a fight no longer holds.)
		if not (R.Candidates ~= nil and R.Candidates.Passable(item, claimed)) then return false end
		for _, req in ipairs(R.requests) do if SamePlayer(req.name, item.full) then return false end end
		return true
	end
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
	if not ns.SharedGuildAllowed(guild) then return false end
	if ns.db and ns.db.blocked and ns.db.blocked[name:lower()] then return false end
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(name, guild, true) then return false end
	local rank, source, support
	if Same(GetGuildInfo("player"), guild) then
		if not ns.Roster.Fresh() then return false end
		rank = ns.Roster.RankOf(name)
	else
		local program = ns.FederationProgram
		if program and program.Role and program.Role(name, guild) then return true end
		if not ns.Data.CanRank(guild) then return false end
		rank, source, support = ns.Data.AuthorizedRank(name, guild)
		if source ~= "signed" and (source ~= "census" or (support or 0) < 2) then return false end
	end
	return type(rank) == "number" and rank >= 0
end

local function LocalGuild()
	local guild = ns.group and ns.faction and ns.IsMember() and GetGuildInfo("player") or nil
	if guild and ns.SharedToolsHere() and R.CanInvite() and Member(ns.me, guild) then return guild end
end

local function Accepting()
	return acceptingGuild ~= nil and acceptingGuild == LocalGuild()
end

local function Changed()
	ns.Fire("DATA_CHANGED")
end

local Unclaimed = { offered = true, claiming = true, assigning = true } -- (the log's EXPIRED lines)
local function Prune(now)
	for id, r in pairs(incoming) do
		if r.expires <= now then
			if Unclaimed[r.state] then H.Log("EXPIRED", ("%s < %s"):format(r.state, ns.ShortName(r.peer) or "?")) end
			-- (1.6.0) His claim that no name answered in time is said, not left silent (a Horde recruiter's
			-- report of 11-14: "and then nothing happens"): the member who passed the player keeps him.
			if r.state == "claiming" and not r.named then ns.Print(L.RECRUIT_HANDOFF_NO_NAME:format(ns.DisplayName(r.peer) or r.peer)) end
			incoming[id] = nil
		end
	end
	for id, r in pairs(outgoing) do
		if r.expires <= now then
			if Unclaimed[r.state] then H.LogItem("EXPIRED", r.request, ("%s > %s"):format(r.state, ns.ShortName(r.peer) or "?")) end
			outgoing[id] = nil
		end
	end
end

local function Room(rows, limit)
	local n = 0
	for _ in pairs(rows) do n = n + 1 end
	return n < (limit or LIMIT)
end

local function Transmit(op, ref, peer, applicant, guard, done)
	local word = table.concat({ ref.verified and "J6" or "J4", op, ref.id, ref.expires, ns.group, ns.faction, ref.from, ref.to, applicant or "" }, "~")
	if #word > 255 then return false end
	-- (1.5.8) The recruiting log: each packet sent, and its check refusing it at the send, once.
	local refused
	local function Checked(...)
		local ok, why = guard(...)
		if not ok and not refused then
			refused = true
			H.LogPacket("GUARD", op, peer, applicant)
		end
		return ok, why
	end
	local sent = ns.Comm.Whisper(peer, word, nil, false, false, done, { guard = guard and Checked })
	H.LogPacket(sent and "TX" or "TXFAIL", op, peer, applicant)
	return sent
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
	-- (1.5.9) A player who declined this client's invite is not offered to other members either.
	if R.Declined and R.Declined(name) then return true end
	for _, ref in pairs(outgoing) do
		if ref.request ~= item and H.State(ref.request) and SamePlayer(NameOf(ref.request), name) then return true end
	end
	if item.scanned then
		for _, req in ipairs(R.requests) do if SamePlayer(req.name, name) then return true end end
	end
	return false
end

-- (Review of 1.5.8) This client already gave this player's name to a member (say, a sighting before
-- his JOIN): a popup of his own here would be a second invite.
function H.Taken(item)
	return type(item) == "table" and handed[NameKey(NameOf(item))] == true
end

local function NextOverflow()
	-- (1.5.9) With the automatic offers off, only what the member passed by hand goes.
	return R.OverflowRequest(Duplicate, autoGuild == nil or autoGuild ~= LocalGuild())
		or (R.Candidates and R.Candidates.Overflow(Duplicate)) or nil
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
	return own ~= nil and (autoGuild == own or passGuild == own) and AvailableNow()
end

-- Once signed enrollment is active, only the upgraded offer protocol can cross guilds.
-- Recheck capacity without starting new network queries in transport guards.
local function Route(from, to, verified, ask)
	if Same(from, to) then return not verified end
	if verified ~= ns.SharedToolsActive() then return false end
	if not verified then return true end
	local overflow = R.VerifiedOverflow
	return overflow ~= nil and not ns.ChatLocked() and not ns.QuietPresence() and overflow.Allowed(from, to, ask)
end

function H.OverflowAllowed(from, to, ask)
	return Route(from, to, true, ask)
end

local function SamePeer(a, b, verified)
	if verified then return Same(a, b) end
	return SamePlayer(a, b)
end

-- `claimed` (1.6.0): a member's claim of the offer, and the name it sends back. Combat no longer holds
-- these: the name is one addon whisper, which a fight does not stop. 1.5.8 and 1.5.9 refused the claim,
-- or dropped the name waiting to leave, while the member who passed the player was fighting, and the
-- one who claimed heard nothing (a Horde recruiter's report of 11-14: "and then nothing happens"). The
-- probes and offers still wait for the end of a fight; a chat lockdown and quiet presence hold all of it.
local function SourceReady(ref, claimed)
	if ref.verified and (ref.request.scanned or ref.request.handoffIntent ~= "federation") then return false end
	if not Source(ref.request, nil, claimed) or not Route(ref.from, ref.to, ref.verified) then return false end
	if not R.FederationInviteAllowed(NameOf(ref.request), ref.to) then return false end
	if not ref.automatic then return true end
	local own, allowed = ref.from, nil
	if claimed then
		allowed = own ~= nil and (autoGuild == own or passGuild == own) and not ns.ChatLocked() and not ns.QuietPresence()
	else
		allowed = AutoAllowed(own)
	end
	return allowed and not PromptOpen(ref.request)
end

local function NextID(now)
	serial = serial + 1
	return ("%d-%x-%d"):format(now, math.random(1, 1073741823), serial)
end

-- (Review of 1.5.9) A scanned player's offer carries a fourth part in its id, "0", so the member who
-- takes it tells a sighting from a JOIN (R.TakeHandoff: one who declined his invite is refused only
-- as a sighting). A 1.5.8 member keeps the id whole; a 1.5.8 offer, three parts, reads as a JOIN.
local SIGHTING = "-0"
local function Sighting(id)
	return type(id) == "string" and id:find("^%d+%-%x+%-%d+%-0$") ~= nil
end

function H.Offer(req, peer, guild, automatic)
	local own, now = LocalGuild(), math.floor(ns.Now())
	Prune(now)
	if not own or not Source(req) or H.State(req) or not Room(outgoing) or Duplicate(req)
		or not Member(peer, guild) or SamePlayer(peer, ns.me)
		or (req.handoffIntent ~= "federation" and not Same(own, guild)) then return false end
	local verified = not Same(own, guild) and ns.SharedToolsActive()
	if not Route(own, guild, verified, true) or not R.FederationInviteAllowed(NameOf(req), guild) then return false end
	if automatic and (not AutoAllowed(own) or not Same(own, guild)
		or PromptOpen(req) or not Room(outgoing, LIMIT - 1)) then return false end
	local ref = {
		id = NextID(now) .. (req.scanned and SIGHTING or ""), expires = now + TTL, from = own, to = guild, peer = peer,
		request = req, state = "offered", automatic = automatic, verified = verified,
	}
	req.handoff, outgoing[ref.id] = ref, ref
	local function Guard()
		local allowed = ref.expires > ns.Now() and ref.from == LocalGuild() and ref.state == "offered"
			and SourceReady(ref) and Member(peer, guild)
		return allowed, "invalid"
	end
	local function Done(sent, why)
		if verified and not sent and why == "invalid" and req.handoff == ref and ref.state == "offered" then
			req.handoff, outgoing[ref.id] = nil, nil
			Changed()
		end
	end
	if not Transmit("O", ref, peer, nil, Guard, Done) then
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
		or not Member(ref.peer, ref.from) or not Route(ref.from, ref.to, ref.verified, true) then return false end
	ref.state = "claiming"
	local function Guard()
		return incoming[ref.id] == ref and ref.expires > ns.Now() and Accepting()
			and Same(acceptingGuild, ref.to) and Member(ref.peer, ref.from) and Route(ref.from, ref.to, ref.verified)
	end
	if not Transmit("C", ref, ref.peer, nil, Guard) then ref.state = "offered"; return false end
	-- (1.6.0) Once its time is out, a claim no name answered is said (Prune).
	ns.After(math.max(1, ref.expires - ns.Now()) + 1, "recruit claim expiry", function() Prune(ns.Now()) end)
	Changed()
	return true
end

-- (1.5.9) What a guildmate's hello says of handoffs (Comm.HandoffPeers, Comm.Hello's "J" or "j"), for
-- the probes and the Offer picker. Tiers:
--   1 his hello says he takes them ("J");
--   2 he runs Olympus as far as this client knows and may take them: a hello without the flag (a
--     1.5.8 client: it had none yet), or one whose version can't be read; for the probes also what
--     `known` (Versions.HasOlympus) knows besides: a stale hello or a version check's answer;
--   3 never heard from: his hello may not have reached this client (review of 1.5.8);
--   nil: his hello says he takes none ("j"), or names a version before handoffs: asked, he would
--     answer no, or nothing at all.
-- (Review of 1.5.9: the flag says it, never the version. A version cutoff read a test build of
-- 1.5.9, which still names 1.5.8, as a 1.5.8 client; and had this shipped after a 1.5.9 without it,
-- it would have read every such client, which takes handoffs as 1.5.8 does, as taking none.)
H.HANDOFFS_SINCE = "1.5.8"
local function Before(version, since)
	local W = ns.Workshop
	return type(version) == "string" and type(W) == "table" and type(W.Newer) == "function" and W.Newer(since, version) == true
end
local function HandoffIndex()
	local C = ns.Comm
	return C and type(C.HandoffPeers) == "function" and C.HandoffPeers() or nil
end
local function Tier(name, index, known)
	local full = ns.FullName(name)
	local e = index and (index.full[full] or index.short[ns.Fold(ns.ShortName(full))])
	if e then
		if e.takes == true then return 1 end
		if e.takes == false then return nil end
		if type(e.version) == "string" and e.version ~= "?" and Before(e.version, H.HANDOFFS_SINCE) then return nil end
		return 2
	end
	if known and known(full) then return 2 end
	return 3
end

-- (1.5.9, review: Church > Invites' rows do not wrap) A member as a handoff's row names him: his
-- name, and his guild only when it is not this player's own (a sister guild's, JOIN OLYMPUS).
local function Who(name, guild)
	local who = ns.DisplayName(name) or name
	if type(guild) == "string" and not Same(guild, GetGuildInfo("player")) then who = who .. " <" .. guild .. ">" end
	return who
end
H.Who = Who

-- The next member of `list` (roster indices of one tier, in order) after the one this tier asked
-- last, going round; tier 3's members are checked here, as they come.
local function Pick(tier, list, roster, own)
	local start = 1
	for k, i in ipairs(list) do
		if i > (cursor[tier] or 0) then start = k; break end
	end
	for step = 0, #list - 1 do
		local i = list[(start + step - 1) % #list + 1]
		local name = ns.FullName(roster[i].name)
		if tier < 3 or Member(name, own) then
			cursor[tier] = i
			return name
		end
	end
end

-- (1.5.9) The member the next probe goes to: those whose hello says they take handoffs first, in
-- turn; after each turn over them, one probe to the next of tier 2; after each turn over tier 2,
-- one to the next of tier 3. A tier with nobody is passed over, and whoever's hello says he takes
-- none is never asked: a member without Olympus never answers a probe, and it waits PROBE_TTL.
local function NextPeer(own)
	local roster = ns.Roster.online or {}
	local V = ns.Versions
	local known, index = V and V.HasOlympus, HandoffIndex()
	local tiers = { {}, {}, {} }
	for i, row in ipairs(roster) do
		local name = ns.FullName(row.name)
		if not SamePlayer(name, ns.me) then
			local tier = Tier(name, index, known)
			-- (Tiers 1 and 2 are the members heard to run Olympus, few: checked now, so that a turn
			-- counts only those who may be asked.)
			if tier and (tier == 3 or Member(name, own)) then tiers[tier][#tiers[tier] + 1] = i end
		end
	end
	for _ = 1, 2 do
		for t = 1, 3 do
			local list = tiers[t]
			if #list > 0 and (t == 3 or (turn[t] or 0) < #list) then
				local peer = Pick(t, list, roster, own)
				if peer then
					if t < 3 then turn[t] = (turn[t] or 0) + 1 end
					for above = 1, t - 1 do turn[above] = 0 end
					return peer
				end
			end
		end
		-- Nobody below the turns that are over: the lowest tier with members starts its turn again.
		for t = 2, 1, -1 do
			if #tiers[t] > 0 then turn[t] = 0; break end
		end
	end
end

local function ResetTurns()
	wipe(cursor)
	wipe(turn)
end

local function AutoStep()
	-- (1.5.8, review) What the invite limit sent on and no member claimed comes back once it clears.
	if R.ReleaseLimited then R.ReleaseLimited() end
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
	if autoProbe then H.Log("EXPIRED", "probe > " .. (ns.ShortName(autoProbe.peer) or "?")) end
	autoProbe = nil
	-- (1.5.8) Any member may take handoffs, so in a large guild the probes must not wait on members
	-- without Olympus: NextPeer's order (1.5.9: who says he takes them first).
	local peer = NextPeer(own)
	if not peer then return end
	local ref = { id = NextID(now), expires = now + PROBE_TTL, from = own, to = own, peer = peer }
	autoProbe = ref
	local function Guard()
		return autoProbe == ref and ref.expires > ns.Now() and LocalGuild() == own
			and AutoAllowed(own) and Member(ref.peer, own) and NextOverflow() ~= nil
	end
	if not Transmit("P", ref, ref.peer, nil, Guard) then autoProbe = nil end
end

-- The probes' timer, while the automatic offers or this session's passes need it.
local function Ticking()
	if (autoGuild or passGuild) and not autoTimer then
		autoTimer = ns.Every(AUTO_EVERY, "recruit overflow", AutoStep)
	elseif not (autoGuild or passGuild) and autoTimer then
		autoTimer.Cancel()
		autoTimer = nil
	end
end

function H.ToggleAuto()
	if autoTimer then autoTimer.Cancel(); autoTimer = nil end
	autoGuild, autoProbe = not autoGuild and LocalGuild() or nil, nil
	ResetTurns()
	Ticking() -- (off, it still runs for what he passed by hand)
	-- With the offers off, what the invite limit sent on comes back to his popups.
	if not autoGuild and R.ReleaseLimited then ns.After(0, "recruit limit release", R.ReleaseLimited) end
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

-- `limit`: the invite limit sent it on, not his click, so it comes back when the limit clears.
local function Want(item, limit)
	item.passWanted, item.limitPassed = true, limit or nil
	-- (1.5.9, the author's report, 11-12: "Ele tem que ficar desativado se ele estava desativado") With
	-- the automatic offers off, what he passed goes through their probes all the same, and the switch
	-- stays as he left it: 1.5.8 turned it on here for the session, and the next login turned it off.
	local own = LocalGuild()
	if own and not limit then
		passGuild = own
		Ticking()
	end
	ns.After(0, "recruit pass", AutoStep)
	Changed()
end

-- The member's click: this JOIN (`all`: and the ones waiting behind it) or scanned player goes
-- to the guild's members who accept handoffs, one at a time, through the same probe and claim as
-- the automatic overflow (whose switch it leaves as it was, 1.5.9). Until one claims it, it stays
-- in his queue.
function H.Pass(req, all)
	if not H.CanPass(req) then return false end
	if all and not req.scanned then
		for _, other in ipairs(R.requests) do
			if other ~= req and not other.passWanted and H.CanPass(other) then other.passWanted = true end
		end
	end
	Want(req)
	H.LogItem("PASS", req, all and not req.scanned and "and waiting" or nil)
	ns.Print(L.RECRUIT_HANDOFF_PASSING)
	return true
end

-- At the invite limit, automatically hand off only requests with explicit JOIN intent.
function H.Overflow(item)
	if type(item) ~= "table" or item.scanned or not H.AutoOn() or not H.CanPass(item) then return false end
	Want(item, true)
	H.LogItem("OVERFLOW", item)
	return true
end

function H.PassBlocked(req)
	if not H.CanPass(req, true) then return false end
	req.invitePrepared = nil
	return H.Pass(req)
end

-- An offer for a member who accepts handoffs: a chat line, and a Claim question when nothing
-- else of the recruitment is on screen. The name still comes only after his Claim click.
-- (1.6.0, a Horde recruiter's report of 11-14 on 1.5.9: "I get a ton of [these lines] and then nothing
-- happens".) The question waits for every recruiting popup the invite command waits for after it (an
-- ad's draft and a scanned player's whisper review too: once claimed, the name came and no command
-- opened while one of them stayed up), and for what holds the automatic popups (Recruit.PopupsWait,
-- the interval). What holds it back says no to the probes too (Receive), so offers go to a member who
-- can answer. An offer that came while it could not be asked is asked once it can, while it lasts;
-- 1.5.9 printed the line and never asked. A question still up when its offer expires closes.
local CLAIM_DIALOG = "OLYMPUS_RECRUIT_HANDOFF_CLAIM"
local busyDialogs = { CLAIM_DIALOG, "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_REPLY", "OLYMPUS_RECRUIT_NETOFF",
	"OLYMPUS_RECRUIT_OUTREACH", "OLYMPUS_RECRUIT_ANNOUNCEMENT", "OLYMPUS_RECRUIT_PAUSE", "OLYMPUS_RECRUIT_TURN_OFF" }
H.ASK_RETRY = 2 -- seconds between looks while an offer waits for its question

-- Whether the Claim question can be on his screen now.
local function CanAsk()
	local D = ns.Dialog
	if not D or D.missing or not D.Show or not D.Find or R.PopupsWait() or R.PopupWait() > 0 then return false end
	for _, which in ipairs(busyDialogs) do if D.Find(which) then return false end end
	return true
end

-- The offer to ask about next: still to claim, its question not shown yet, the one ending first.
local function Unasked(now)
	local nextRef, waiting
	for _, ref in pairs(incoming) do
		if ref.state == "offered" and not ref.asked and ref.expires > now and Same(ref.to, acceptingGuild) then
			if Route(ref.from, ref.to, ref.verified, true) then
				if not nextRef or ref.expires < nextRef.expires then nextRef = ref end
			else
				waiting = true
			end
		end
	end
	return nextRef, waiting
end

local looking -- a look due in ASK_RETRY seconds
local Ask
local function AskLater()
	if looking then return end
	looking = true
	ns.After(H.ASK_RETRY, "recruit claim question", function()
		looking = nil
		Ask()
	end)
end

Ask = function()
	local now = ns.Now()
	Prune(now)
	if not Accepting() then return end
	local ref, waiting = Unasked(now)
	if not ref then if waiting then AskLater() end; return end
	if not ref.notified then Notify(ref, true) end
	if not CanAsk() then return AskLater() end
	ref.asked = true
	local D = ns.Dialog
	local prompt = Sighting(ref.id) and L.RECRUIT_HANDOFF_CLAIM_PROMPT_SCAN or L.RECRUIT_HANDOFF_CLAIM_PROMPT
	if D.Show(CLAIM_DIALOG, prompt:format(ns.DisplayName(ref.peer) or ref.peer, ref.from), nil, ref) then
		R.PopupShown()
		ns.After(math.max(1, ref.expires - now), "recruit claim expiry", function()
			local open = D.Find(CLAIM_DIALOG, ref)
			if open then open:Hide() end
			Ask()
		end)
	end
	local more, pending = Unasked(now)
	if more or pending then AskLater() end
end

Notify = function(ref, withoutAsk)
	ref.notified = true
	local who = ns.DisplayName(ref.peer) or ref.peer
	local scan = Sighting(ref.id)
	ns.Print((scan and L.RECRUIT_HANDOFF_ARRIVED_SCAN or L.RECRUIT_HANDOFF_ARRIVED):format(who, ref.from))
	if not withoutAsk then Ask() end
end

function H.Receive(dist, sender, word)
	if dist ~= "WHISPER" or type(word) ~= "string" or #word > 255 or SamePlayer(sender, ns.me) then return false end
	local protocol, op, id, expires, group, faction, from, to, applicant =
		word:match("^(J[46])~([OCNAPVD])~([%d%x%-]+)~(%d+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]*)$")
	expires = tonumber(expires)
	local verified = protocol == "J6"
	if verified and (Same(from, to) or Sighting(id) or (ns.Relay and ns.Relay.Hop and ns.Relay.Hop())) then return false end
	local now, own = ns.Now(), LocalGuild()
	-- (Review of 1.5.8) A member who may not invite still answers a probe, with a no (below).
	if not own and op == "P" then
		local guild = ns.group and ns.faction and ns.IsMember() and GetGuildInfo("player") or nil
		if guild and Member(ns.me, guild) then own = guild end
	end
	if not own or not expires or expires <= now or expires - now > TTL + 5 or #id > 40
		or group ~= ns.group or faction ~= ns.faction or not Field(from, MAX_GUILD) or not Field(to, MAX_GUILD)
		or (op ~= "N" and applicant ~= "") then return false end
	Prune(now)
	if op == "P" or op == "V" or op == "D" then
		if verified or not AvailableNow() or expires - now > PROBE_TTL + 5 or not Same(own, from) or not Same(own, to)
			or not Member(sender, own) then return false end
		if op == "V" or op == "D" then
			local ref = autoProbe
			if not AutoAllowed(own) or not ref or ref.available or id ~= ref.id or expires ~= ref.expires
				or not SamePlayer(sender, ref.peer) then return false end
			if op == "D" then
				-- (Review of 1.5.8) He takes no names now: the next member is asked in a second, not
				-- once the probe's PROBE_TTL is over.
				autoProbe = nil
				ns.After(1, "recruit probe declined", AutoStep)
				return true
			end
			ref.available = true
			return true
		end
		if now - repliedAt < AUTO_EVERY then return false end
		local ref = { id = id, expires = expires, from = own, to = own }
		repliedAt = now
		-- (1.5.8) A member at his own invite limit is not available for more names. (Review of 1.5.8)
		-- He, and a member who takes no handoffs or may not invite, says so at once ("D"): a probe
		-- nobody answered held the busy recruiter's next one back PROBE_TTL seconds. (1.6.0) So does one
		-- whose screen cannot show the Claim question now (CanAsk): he said yes, and the offer that came
		-- was a chat line and nothing else.
		if not Accepting() or not Room(incoming) or R.AtInviteLimit() or not CanAsk() then
			return Transmit("D", ref, sender, nil, function()
				return expires > ns.Now() and AvailableNow() and Member(sender, own)
			end)
		end
		return Transmit("V", ref, sender, nil, function()
			return expires > ns.Now() and acceptingGuild == own and Accepting() and AvailableNow()
				and Room(incoming) and Member(sender, own)
		end)
	end
	if op == "O" or op == "N" then
		if not Accepting() or not Same(own, to) or not Member(sender, from)
			or (not Same(from, to) and verified ~= ns.SharedToolsActive()) then return false end
		if op == "O" then
			if incoming[id] or not Room(incoming) then return false end
			local overflow = R.VerifiedOverflow
			if verified and not (overflow and overflow.ScopeAllowed(from, to)) then return false end
			incoming[id] = { id = id, expires = expires, from = from, to = to, peer = sender, state = "offered", verified = verified }
			if Route(from, to, verified, true) then Notify(incoming[id])
			elseif verified then AskLater() end
		else
			local ref = incoming[id]
			if not ref or ref.state ~= "claiming" or ref.expires ~= expires or ref.verified ~= verified or not SamePeer(ref.peer, sender, verified)
				or ref.from ~= from or ref.to ~= to or not Route(from, to, verified) or not InScope(applicant)
				or SamePlayer(applicant, ns.me) then return false end
			ref.named = true -- (a name came: whatever this client does with it, no "no name" line, Prune)
			if not R.FederationInviteAllowed(applicant, own) then return false end
			for _, req in ipairs(R.requests) do
				if SamePlayer(applicant, req.name) then return false end
			end
			if not R.TakeHandoff(applicant, sender, Sighting(id), verified and ref.from or nil) then return false end
			ref.state = "received"
			ns.Fire("RECRUIT_HANDOFF_ACCEPTED", applicant, sender, ns.me, ref.from, ref.to, ref.id)
			Transmit("A", ref, sender, nil, function()
				return ref.expires > ns.Now() and Accepting() and Same(acceptingGuild, to) and Member(sender, from)
			end)
		end
	else
		local ref = outgoing[id]
		if not ref or ref.expires ~= expires or ref.verified ~= verified or ref.from ~= from or ref.to ~= to
			or not SamePeer(ref.peer, sender, verified)
			or ref.from ~= own or not Member(sender, to) then return false end
		if op == "C" then
			if ref.state ~= "offered" or not SourceReady(ref, true) then return false end
			-- A queued or delivered name might have been acted on even without an
			-- acknowledgement, so the origin stays locked rather than retry elsewhere.
			ref.state = "assigning"
			local key = NameKey(NameOf(ref.request))
			handed[key] = true
			local function Guard()
				local ready = ref.expires > ns.Now() and ref.from == LocalGuild() and SourceReady(ref, true)
					and Member(sender, to) and ref.state == "assigning"
				return ready, "invalid"
			end
			local function Done(sent, why)
				-- Only a guard refusal proves the queued name never left. Retain the lock for
				-- an ambiguous transport result so a second member cannot receive that name.
				if not sent and why == "invalid" and (ref.automatic or ref.verified) and ref.request.handoff == ref then
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
			H.LogItem("HANDED", ref.request, "> " .. (ns.ShortName(sender) or "?"))
			-- (Review of 1.5.9) The member who passed a player on says so himself to the Church's keepers:
			-- his share in the recruiting ranking for everyone counts only when the inviter's own report
			-- names him too (RecruitRanking.HandedOut).
			local ranking = ns.RecruitRanking
			if ranking and ranking.HandedOut and not ref.request.scanned then
				ns.SafeCall("recruit ranking handed out", ranking.HandedOut, NameOf(ref.request), sender)
			end
			if not ref.request.scanned then
				ns.Fire("RECRUIT_HANDOFF_ACKNOWLEDGED", NameOf(ref.request), ns.me, sender, ref.to, ref.id)
			end
		end
	end
	Changed()
	return true
end
-- (The handler is bound late: H.Receive is wrapped below by the recruiting log, one registration.)
ns.Comm.Handle("J4", function(...) return H.Receive(...) end)
ns.Comm.Handle("J6", function(...) return H.Receive(...) end)

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
	-- (1.5.9, the review of 1.5.8: the first members online by rank were listed, so a plain member who
	-- takes handoffs, any rank since 1.5.8, was never there.) Those whose hello says they take them
	-- first, then those whose hello says they run Olympus, then the rest, each in the roster's order
	-- (Tier); never one whose hello says he takes none, whose client would let the offer expire
	-- unanswered. (Review of 1.5.9: from the hellos alone, read once. Versions.HasOlympus for each
	-- member online went through every hello heard for each one it did not find, and the page took
	-- about 150 ms a redraw with 400 online.)
	local index, ranked = HandoffIndex(), {}
	for i, row in ipairs(ns.Roster.online or {}) do
		local tier = Tier(row.name, index)
		if tier then ranked[#ranked + 1] = { name = row.name, tier = tier, i = i } end
	end
	table.sort(ranked, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		return a.i < b.i
	end)
	for _, entry in ipairs(ranked) do
		if #result >= ownLimit then break end
		Add(entry.name, own)
	end
	if req.handoffIntent == "federation" and ns.SharedToolsActive() then
		local program, overflow = ns.FederationProgram, R.VerifiedOverflow
		for guild in pairs(program and program.Caretakers and program.Caretakers() or {}) do
			if #result >= LIMIT then break end
			if overflow and not Same(own, guild) then
				local eligible, peer = overflow.Allowed(own, guild, true)
				if eligible then Add(peer, guild) end
			end
		end
	elseif req.handoffIntent == "federation" then
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
-- click leaves them as they are, 1.5.9).
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
		autoGuild, autoProbe = saved.guild, nil
		ResetTurns()
		Ticking()
		Changed()
	end
end

-- Church > Invites' Handoffs section (Recruit.WhisperLines). (1.5.8, the author's ask: "botar
-- experimental nessa feature": since 1.5.9 its heading says it, not each switch, which it cut off.)
-- `hint`: the section's grey line, under its switches as every section has it (review of 1.5.9).
function H.Controls(lines, V, hint)
	local own = LocalGuild()
	if not own then return end
	Prune(ns.Now())
	lines[#lines + 1] = { id = "recruit-handoff-accept",
		text = Accepting() and V.Green(L.RECRUIT_HANDOFF_ON) or V.Grey(L.RECRUIT_HANDOFF_OFF), onClick = ToggleSaved,
	}
	lines[#lines + 1] = { id = "recruit-handoff-overflow",
		text = autoGuild == own and V.Green(L.RECRUIT_OVERFLOW_ON) or V.Grey(L.RECRUIT_OVERFLOW_OFF),
		onClick = ToggleAutoSaved }
	if hint then lines[#lines + 1] = { indent = 1, text = V.Grey(hint) } end
	if not Accepting() then return end
	for _, ref in pairs(incoming) do
		if Same(ref.to, own) and Member(ref.peer, ref.from) and ref.state ~= "received" and Route(ref.from, ref.to, ref.verified) then
			local scan = Sighting(ref.id)
			local label = ref.state == "offered" and (scan and L.RECRUIT_HANDOFF_CLAIM_SCAN or L.RECRUIT_HANDOFF_CLAIM)
				or (scan and L.RECRUIT_HANDOFF_WAITING_SCAN or L.RECRUIT_HANDOFF_WAITING)
			lines[#lines + 1] = {
				indent = 1, text = V.Gold(label:format(Who(ref.peer, ref.from))),
				onClick = ref.state == "offered" and function() H.Claim(ref) end or nil,
			}
		end
	end
end

function H.RequestLines(lines, V, req)
	local state = H.State(req)
	if state then
		lines[#lines + 1] = { indent = 1, text = V.Grey((state == "assigned" and L.RECRUIT_HANDOFF_DONE
			or L.RECRUIT_HANDOFF_PENDING):format(Who(req.handoff.peer, req.handoff.to))) }
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
		lines[#lines + 1] = { indent = 2, text = V.Gold(L.RECRUIT_HANDOFF_OFFER:format(Who(contact.name, contact.guild))),
			onClick = function() H.Offer(req, contact.name, contact.guild) end }
	end
end

StaticPopupDialogs[CLAIM_DIALOG] = {
	text = "%s",
	button1 = L.RECRUIT_HANDOFF_TAKE,
	button2 = L.RECRUIT_HANDOFF_SKIP,
	OnAccept = function(_, ref) H.Claim(ref) end,
	-- (1.6.0) It opens by itself alone (Ask): Pause recruiting and Turn off recruiting under it (Recruit.StopRow).
	more = function() return R.StopRow("handoffs") end,
	timeout = 60,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function H.Reset()
	acceptingGuild, choosing, looking = nil, nil, nil
	if autoTimer then autoTimer.Cancel(); autoTimer = nil end
	autoGuild, passGuild, autoProbe, repliedAt = nil, nil, nil, -math.huge
	ResetTurns()
	wipe(incoming)
	wipe(outgoing)
	wipe(handed)
end

-- 1.5.8 (the author's ask, 11-12: "esse negócio de oferecer para entrar, players escaneados para
-- outros membros, deveria ser ativar automático também... quando você ativa, deveria ativar tudo"):
-- the Census offer turns the automatic offers on with recruiting and off with it, saved as the
-- Church's own switch saves them. As SetAccepting below, kept for the guild this character recruits
-- for while the roster cannot confirm the player yet (each step checks LocalGuild() again).
-- Returns whether the offers run now.
function H.SetAuto(on)
	local saved = R.Preference and R.Preference(true)
	local guild = on and (LocalGuild() or (R.IsWhisperRecruiting() and saved and saved.guild)) or nil
	if autoGuild and autoGuild ~= guild then H.ToggleAuto() end -- (off, or another guild's leftover off first)
	if guild and not autoGuild then
		if LocalGuild() == guild then
			H.ToggleAuto()
		else
			autoGuild, autoProbe = guild, nil
			ResetTurns()
			Ticking()
			Changed()
		end
	end
	Save("offerOverflow", guild ~= nil)
	return H.AutoOn()
end

-- 1.5.8 (the author's ask): the Census offer turns accepting handoffs on with its JOIN and scan
-- switches, saved as the Church's own switch saves it. Turned on, it is kept for the guild this
-- character recruits for even while the roster cannot confirm the player yet (right after a login,
-- or a roster gone stale): as after a login (H.Restore), each use checks LocalGuild() again, so
-- handoffs are taken once the roster does. Returns whether it accepts now.
function H.SetAccepting(on)
	local saved = R.Preference and R.Preference(true)
	local guild = on and (LocalGuild() or (R.IsWhisperRecruiting() and saved and saved.guild)) or nil
	if acceptingGuild and acceptingGuild ~= guild then H.Toggle() end -- (off, or another guild's leftover off first)
	if guild and not acceptingGuild then
		acceptingGuild = guild
		Changed()
	end
	Save("acceptHandoffs", guild ~= nil)
	return Accepting()
end

function H.Accepting() return Accepting() end

-- 1.5.8 (the author's ask: "que vai mostrar pra gente que ele recebeu"): the recruiting event log,
-- a bounded ring in the account's saved variables (OlympusDB.recruitLog, LOG_MAX lines, the oldest
-- dropped), read by /oly bug and /oly recruit log after a /reload. Each line: epoch seconds, a short
-- code, a short detail. Applicants and scanned strangers appear only as a tag (their first two
-- letters and four hex digits of a hash of the full name), never by name; members by character.
H.LOG_MAX, H.SEEN_PER_MINUTE = 200, 6
local PACKET = { P = "probe", V = "available", D = "declined", O = "offer", C = "claim", N = "name", A = "ack" }
local seenTags, seenAt = {}, {}

function H.Tag(name)
	if type(name) ~= "string" or name == "" then return "?" end
	local key, h = NameKey(name), 5381
	for i = 1, #key do h = (h * 33 + key:byte(i)) % 65536 end
	local letters, n = {}, 0
	for ch in (ns.ShortName(name) or name):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		letters[n] = ch
		if n == 2 then break end
	end
	return ("%s%04x"):format(table.concat(letters), h)
end

local function MemberShort(name)
	return type(name) == "string" and (ns.ShortName(name) or name) or "?"
end

function H.Log(code, detail)
	local db = ns.db
	if type(db) ~= "table" or type(code) ~= "string" then return end
	local log = db.recruitLog
	if type(log) ~= "table" then
		log = {}
		db.recruitLog = log
	end
	local t = (GetServerTime and GetServerTime()) or (time and time()) or 0
	detail = ns.Cut(tostring(detail or ""):gsub("[%c|]", ""), 120)
	log[#log + 1] = ("%d %s %s"):format(t, code, detail)
	while #log > H.LOG_MAX do table.remove(log, 1) end
end

-- A handoff packet sent (`kind` "TX", or "GUARD" when its check refused it at the send) or heard
-- ("RX", or "REFUSED"), with the member and, for a name, the applicant's tag.
function H.LogPacket(kind, op, peer, applicant)
	local name = applicant and applicant ~= "" and (" " .. H.Tag(applicant)) or ""
	local arrow = (kind == "RX" or kind == "REFUSED") and "<" or ">"
	H.Log(kind, ("%s%s %s %s"):format(PACKET[op] or tostring(op), name, arrow, MemberShort(peer)))
end

-- A scanned player seen (`source`: target, nameplate, who, mouseover): once a session per player
-- and SEEN_PER_MINUTE a minute at most, so a crowded city does not push the handoffs out.
function H.LogSeen(source, name)
	local tag = H.Tag(name)
	if seenTags[tag] then return end
	local now = ns.Now()
	for i = #seenAt, 1, -1 do if now - seenAt[i] >= 60 then table.remove(seenAt, i) end end
	if #seenAt >= H.SEEN_PER_MINUTE then return end
	seenAt[#seenAt + 1] = now
	seenTags[tag] = true
	H.Log("SEEN", ("%s %s"):format(tostring(source), tag))
end

function H.LogItem(code, item, extra)
	if type(item) ~= "table" then return end
	H.Log(code, ("%s%s%s"):format(item.scanned and "scan " or "", H.Tag(NameOf(item)), extra and (" " .. extra) or ""))
end

-- Every handoff packet heard, accepted or refused (the transport's handler is this one).
local ReceivePacket = H.Receive
function H.Receive(dist, sender, word)
	local ok = ReceivePacket(dist, sender, word)
	local op = dist == "WHISPER" and type(word) == "string" and #word <= 255 and word:match("^J[46]~(%u)~") or nil
	if op then H.LogPacket(ok and "RX" or "REFUSED", op, sender, op == "N" and word:match("~([^~]*)$") or nil) end
	return ok
end

local function Stamp(t)
	return date and date("%H:%M:%S", t) or tostring(t)
end

-- The newest `max` lines (all with none), newest last, each "hh:mm:ss CODE detail".
function H.LogLines(max)
	local log = type(ns.db) == "table" and type(ns.db.recruitLog) == "table" and ns.db.recruitLog or {}
	local out = {}
	for i = math.max(1, #log - (max or #log) + 1), #log do
		local t, rest = tostring(log[i]):match("^(%d+) (.*)$")
		if t then out[#out + 1] = Stamp(tonumber(t)) .. " " .. rest end
	end
	return out
end

-- One line of where this client stands: recruiting, accepting, offering, scanning, the invites
-- taken this minute, and the members online this client heard run Olympus.
function H.Summary()
	local known, online = 0, 0
	local V = ns.Versions
	for _, row in ipairs(ns.Roster and ns.Roster.online or {}) do
		online = online + 1
		if V and V.HasOlympus and V.HasOlympus(ns.FullName(row.name)) then known = known + 1 end
	end
	local function On(v) return v and "on" or "off" end
	local scan = R.Candidates and R.Candidates.Enabled and R.Candidates.Enabled()
	return ("recruiting %s, can invite %s, accepting handoffs %s, automatic offers %s, scan %s, invites this minute %d/%d, members with Olympus %d of %d online"):format(
		On(R.IsWhisperRecruiting and R.IsWhisperRecruiting()), On(R.CanInvite and R.CanInvite()), On(Accepting()),
		On(H.AutoOn()), On(scan), R.InvitesTaken and R.InvitesTaken() or 0, R.INVITES_PER_MINUTE or 0, known, online)
end

-- /oly bug's section: the summary and the newest `max` lines.
function H.BugLines(max)
	local out = { "Recruiting: " .. H.Summary() }
	local lines = H.LogLines(max or 40)
	if #lines == 0 then out[#out + 1] = "  (no recruiting events yet)" end
	for _, line in ipairs(lines) do out[#out + 1] = "  " .. line end
	return out
end

-- Review of 1.5.8: a bug report sent in game stops at Workshop.BUG_MAX bytes, and its recruiting
-- section comes last, past the status, debug and log sections: what another member sent back lost
-- the lines that show he received a player. /oly recruit send sends the log alone instead: who sent
-- it, the summary and the newest lines that fit, newest last.
function H.SendText()
	local W = ns.Workshop
	local budget = (W and W.BUG_MAX or 4800) - 16
	local head = ("Recruiting log of %s (Olympus %s)\n%s"):format(MemberShort(ns.me), tostring(ns.VERSION), H.Summary())
	local lines, picked, size = H.LogLines(), {}, #head + 2
	for i = #lines, 1, -1 do
		size = size + #lines[i] + 2 -- (a line break travels as two bytes)
		if size > budget then break end
		table.insert(picked, 1, lines[i])
	end
	return head .. "\n" .. (#picked > 0 and table.concat(picked, "\n") or L.RECRUIT_LOG_EMPTY)
end

local testSerial = 0
-- /oly recruit: `log` opens the whole log in the copy window; `testjoin [Name]`, on a test build
-- only, feeds a JOIN whisper from that name (or a made-up one with digits, never a real character)
-- to the same handler the game's whisper reaches.
function H.Slash(rest)
	local word, arg = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
	word = (word or ""):lower()
	if word == "log" or word == "registro" then
		local lines = H.LogLines()
		local text = H.Summary() .. "\n\n" .. (#lines > 0 and table.concat(lines, "\n") or L.RECRUIT_LOG_EMPTY)
		if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy("/oly recruit log", text, nil, { key = "recruitlog", big = true }) end
		return true
	elseif word == "send" or word == "enviar" then
		local W = ns.Workshop
		if not (W and W.AuthorOnline and W.AuthorOnline()) then
			ns.Print(L.RECRUIT_SEND_OFFLINE)
			return false
		end
		return W.SendBug(H.SendText()) and true or false
	elseif word == "testjoin" then
		if not rawget(ns, "TEST_BUILD") then
			ns.Print(L.RECRUIT_TESTJOIN_OFF)
			return false
		end
		local name = arg
		if name == "" then
			testSerial = testSerial + 1
			local t = (time and time()) or 0
			name = ("Olytest%d%d"):format(t % 100000, testSerial)
		end
		H.Log("TESTJOIN", H.Tag(ns.FullName(name)))
		ns.Print(L.RECRUIT_TESTJOIN_SENT:format(name))
		R.OnWhisper("JOIN", name)
		return true
	end
	ns.Print(L.RECRUIT_LOG_USAGE)
	return false
end

function H.ResetLogForTests()
	wipe(seenTags)
	wipe(seenAt)
	testSerial = 0
end
