local _, ns = ...
local Overflow = {}
ns.Recruit.VerifiedOverflow = Overflow

-- Expiring capacity evidence from the native roster, observed directly on our guild or
-- requested privately from one exact signed roleholder. It never carries an applicant.
local FRESH, QUERY_GAP, WAIT = 90, 12, 20
local identity
local pending, observations, replied = {}, {}, {}

local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and ns.Fold(a) == ns.Fold(b)
end

local function Context()
	local program = ns.FederationProgram
	local revision = program and program.EnrollmentRevision()
	local now = revision and ns.Data.ServerTime()
	local cap = ns.Codec.GUILD_CAP
	if type(now) ~= "number" or ns.IsSecret(now) or now <= 0 or not cap then return end
	local scope = ("%s:%s:%s:%s"):format(ns.group, ns.faction, ns.realm, revision)
	if identity ~= scope then
		identity = scope
		pending, observations, replied = {}, {}, {}
	end
	return program, now, revision, cap
end

local function LiveStamp(at, now)
	return type(at) == "number" and not ns.IsSecret(at) and at > 0 and at <= now and now - at <= FRESH
end

local function Snapshot(program, guild, now, cap)
	if not Same(program.LocalEnrollment(now), guild) then return end
	local roster = ns.Roster.Fresh()
	local stats = roster and roster.lastStats
	local total = stats and stats.numTotal
	if not roster or not roster.complete or not Same(roster.guild, guild) or not LiveStamp(roster.serverAt, now)
		or type(total) ~= "number" or ns.IsSecret(total) or total ~= math.floor(total) or total < 1 or total > cap
		or stats.seen ~= total then return end
	return total, roster.serverAt
end

local function Wire(op, revision, nonce, from, to, at, count)
	return table.concat({ "J7", op, ns.group, ns.faction, revision, nonce, from, to, at or "", count or "" }, "~")
end

local function Direct(dist)
	return dist == "WHISPER" and not (ns.Relay and ns.Relay.Hop and ns.Relay.Hop())
end

local function Ask(program, now, revision, guild, key)
	local own = program.LocalEnrollment(now)
	if not own or Same(own, guild) or not ns.IsMember() or ns.QuietPresence() or ns.ChatLocked() then return end
	local recent = pending[key]
	if recent and now - recent.asked < QUERY_GAP then return end
	local caretaker, official = program.Roleholders(guild)
	if not official and not caretaker then return end
	local peer = official or caretaker
	if recent and recent.nonce and recent.peer == peer and caretaker then peer = caretaker end
	local nonce = ("%x-%x"):format(now, math.random(1, 1073741823))
	local request = { asked = now, peer = peer, own = own, nonce = nonce }
	pending[key] = request
	ns.Comm.Whisper(peer, Wire("Q", revision, nonce, own, guild), "overflow seats " .. key, false, false, nil,
		{ guard = function()
			local p, current, rev = Context()
			return p ~= nil and rev == revision and pending[key] == request and current - now <= WAIT
				and ns.IsMember() and not ns.QuietPresence() and not ns.ChatLocked()
				and Same(p.LocalEnrollment(current), own) and p.Role(peer, guild, current) ~= nil
		end })
end

local function Capacity(program, now, revision, cap, guild, ask)
	if not program.IsEnrolled(guild, now) or ns.Data.NetOff(guild) then return end
	if Same(program.LocalEnrollment(now), guild) then return Snapshot(program, guild, now, cap) end
	local key = ns.Fold(guild)
	local estimate = observations[key]
	if estimate and LiveStamp(estimate.at, now) and program.Role(estimate.peer, guild, now) then
		return estimate.count, estimate.at, estimate.peer
	end
	if ask then Ask(program, now, revision, guild, key) end
end

local function Route(p, now, from, to)
	if not p.IsEnrolled(from, now) or not p.IsEnrolled(to, now) or ns.Data.NetOff(from) or ns.Data.NetOff(to) then return end
	local source, primaries = false, p.PrimaryGuilds()
	for guild in pairs(primaries) do
		if Same(guild, to) then return end
		if Same(guild, from) then source = true end
	end
	return source and primaries or nil
end

function Overflow.ScopeAllowed(from, to)
	local p, now = Context()
	return p ~= nil and Route(p, now, from, to) ~= nil
end

function Overflow.Allowed(from, to, ask)
	local p, now, revision, cap = Context()
	local primaries = p and Route(p, now, from, to)
	if not primaries then return false end
	local full = true
	for guild in pairs(primaries) do
		if Capacity(p, now, revision, cap, guild, ask) ~= cap then full = false end
	end
	if not full then return false end
	local count, _, peer = Capacity(p, now, revision, cap, to, ask)
	if count and count < cap then return true, peer end
	return false
end

function Overflow.Receive(dist, sender, text)
	if not Direct(dist) or type(text) ~= "string" or ns.IsSecret(text, sender) or #text > 255 then return false end
	local op, rules, faction, revisionText, nonce, from, to, at, count =
		text:match("^J7~([QF])~([^~]+)~(%a+)~(%d+)~([%x%-]+)~([^~]+)~([^~]+)~(%d*)~(%d*)$")
	local p, now, revision, cap = Context()
	if not p or not op or rules ~= ns.group or faction ~= ns.faction or tonumber(revisionText) ~= revision
		or #nonce > 32 or Same(from, to) or not ns.IsMember() or ns.QuietPresence() or ns.ChatLocked() then return false end
	local own = p.LocalEnrollment(now)
	if op == "Q" then
		if at ~= "" or count ~= "" or not Same(own, to) or not p.IsEnrolled(from, now) or not p.Role(ns.me, to, now)
			or not (p.Role(sender, from, now) or ns.SharedPeerAllowed(sender, from)) then return false end
		local key = ns.Fold(sender)
		for name, stamp in pairs(replied) do if now - stamp >= QUERY_GAP then replied[name] = nil end end
		if replied[key] then return false end
		local seats, recorded = Snapshot(p, to, now, cap)
		if not seats then return false end
		replied[key] = now
		return ns.Comm.Whisper(sender, Wire("F", revision, nonce, from, to, recorded, seats), nil, false, false, nil,
			{ guard = function()
				local program, current, rev = Context()
				return program ~= nil and rev == revision and LiveStamp(recorded, current)
					and ns.IsMember() and not ns.QuietPresence() and not ns.ChatLocked()
					and program.Role(ns.me, to, current) ~= nil and Snapshot(program, to, current, cap) == seats
					and program.IsEnrolled(from, current)
					and (program.Role(sender, from, current) ~= nil or ns.SharedPeerAllowed(sender, from))
			end })
	end
	local key = ns.Fold(to)
	local request = pending[key]
	at, count = tonumber(at), tonumber(count)
	if not request or request.nonce ~= nonce or request.own ~= own or not Same(own, from)
		or not Same(request.peer, sender) or now - request.asked > WAIT or not p.Role(sender, to, now)
		or not LiveStamp(at, now) or not count or count < 1 or count > cap then return false end
	observations[key] = { at = at, count = count, peer = sender }
	request.nonce = nil
	ns.Fire("DATA_CHANGED")
	return true
end

ns.Comm.Handle("J7", Overflow.Receive)

ns.On("VERIFY_CHANGED", function()
	identity, pending, observations, replied = nil, {}, {}, {}
end)
