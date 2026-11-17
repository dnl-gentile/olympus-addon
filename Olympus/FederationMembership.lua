local _, ns = ...
local M = {}
ns.FederationMembership = M

-- Membership witnesses travel only by direct addon whisper. A viewer asks its own
-- caretaker; only a caretaker who can see the viewer in the native roster may relay
-- that query to the subject guild's caretaker. The reply goes straight to the viewer.
local FRESH, WAIT, RETRY = 90, 15, 8
local PENDING_MAX, PROOF_MAX, CALLBACKS_MAX = 24, 128, 2
local scope, serial, pending, proofs, budget = nil, 0, {}, {}, {}

local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and ns.Fold(a) == ns.Fold(b)
end

local function Context()
	local p = ns.FederationProgram
	local revision = p and p.EnrollmentRevision and p.EnrollmentRevision()
	local now = revision and ns.Data.ServerTime()
	if type(now) ~= "number" or ns.IsSecret(now) or now <= 0 or not ns.IsMember()
		or ns.QuietPresence() or ns.ChatLocked() then return end
	local own = p.LocalEnrollment(now)
	if not own then return end
	local current = ("%s~%s~%s~%s~%s"):format(ns.realm, ns.faction, ns.group, own, revision)
	if scope ~= current then
		scope, pending, proofs, budget = current, {}, {}, {}
	end
	return p, now, revision, own, current
end

local function Exact(name)
	if type(name) ~= "string" or ns.IsSecret(name) or #name > 96 or name:find("[~|%c]") then return false end
	local player, realm = name:match("^([^%-]+)%-([^%-]+)$")
	if not player or not ns.InGroup(realm) then return false end
	local region = (ns.realm or ""):match("^CAMWOW(%u%u)")
	return not region or realm:match("^CAMWOW(%u%u)") == region
end

local function Moderated(name, guild)
	return ns.Data.NetOff(guild) or (ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(name, guild))
end

local function NativeStamp(name, guild, now)
	local roster = ns.Roster.Fresh()
	local at = roster and roster.serverAt
	if roster and Same(roster.guild, guild) and type(at) == "number" and not ns.IsSecret(at)
		and at > 0 and at <= now and now - at < FRESH and ns.Roster.RankOf(name) ~= nil then return at end
end

local function Prune(rows, now)
	local n = 0
	for k, row in pairs(rows) do
		if row.untilAt <= now then rows[k] = nil else n = n + 1 end
	end
	return n
end

local function RequestKey(name, guild)
	return ns.Fold(name) .. "~" .. ns.Fold(guild)
end

-- A guild-less caller can reuse a live attestation from a prior exact-guild action.
function M.Guild(name)
	local p, now = Context()
	if not p or not Exact(name) then return nil end
	local row = proofs[ns.Fold(name)]
	if row and now < row.untilAt and p.Role(row.peer, row.guild, now) == "caretaker"
		and not Moderated(name, row.guild) then return row.guild end
end

function M.Allowed(name, guild)
	local witnessed = M.Guild(name)
	return witnessed ~= nil and (guild == nil or Same(guild, witnessed))
end

local function Budget(now, name)
	local n = Prune(budget, now)
	local key = ns.Fold(name)
	local row = budget[key]
	if not row then
		if n >= 32 then return false end
		row = { untilAt = now + 10, count = 0 }
		budget[key] = row
	end
	if row.count >= 6 then return false end
	row.count = row.count + 1
	return true
end

local function Forward(p, now, rev, own, current, requester, guild, name, nonce)
	if p.Role(ns.me, own, now) ~= "caretaker" or not p.IsEnrolled(guild, now) or Same(own, guild)
		or not NativeStamp(requester, own, now) or Moderated(requester, own) or Moderated(name, guild)
		or not Budget(now, requester) then return false end
	local other = p.Roleholders(guild)
	if not other then return false end
	local word = table.concat({ "FM", "V", rev, nonce, requester, name }, "~")
	return ns.Comm.Whisper(other, word, nil, false, false, nil, { guard = function()
		local policy, time, _, _, key = Context()
		return key == current and time - now < WAIT and policy.Role(ns.me, own, time) == "caretaker"
			and policy.Role(other, guild, time) == "caretaker" and NativeStamp(requester, own, time) ~= nil
			and not Moderated(requester, own) and not Moderated(name, guild)
	end })
end

-- One live nonce per observed exact identity/guild. Two in-memory callbacks let a
-- legitimate first packet survive the lookup; they are discarded after the deadline.
function M.Request(name, guild, callback)
	local p, now, revision, own, current = Context()
	if not p or not Exact(name) or type(guild) ~= "string" or ns.IsSecret(guild)
		or Same(own, guild) or not p.IsEnrolled(guild, now) or Moderated(name, guild) then return false end
	local key = RequestKey(name, guild)
	local first, peer = p.Roleholders(own), p.Roleholders(guild)
	if not first or not peer then return false end
	local found = pending[key]
	if found and found.untilAt > now then
		if type(callback) == "function" and #found.callbacks < CALLBACKS_MAX then
			found.callbacks[#found.callbacks + 1] = callback
		end
		return true
	end
	if Prune(pending, now) >= PENDING_MAX then return false end
	serial = serial % 65535 + 1
	local nonce = ("%x-%x-%x"):format(now, math.random(1, 1073741823), serial)
	local request = { untilAt = now + WAIT, peer = peer, name = name, guild = guild, nonce = nonce,
		callbacks = type(callback) == "function" and { callback } or {} }
	pending[key] = request
	ns.After(WAIT, "membership witness expiry", function()
		if pending[key] == request then pending[key] = nil end
	end)
	local sent
	if Same(ns.me, first) then
		sent = Forward(p, now, revision, own, current, ns.me, guild, name, nonce)
	else
		local word = table.concat({ "FM", "Q", revision, nonce, guild, name }, "~")
		sent = ns.Comm.Whisper(first, word, nil, false, false, nil, { guard = function()
			local policy, time, _, _, s = Context()
			return s == current and pending[key] == request and time < request.untilAt and not Moderated(name, guild)
				and policy.Role(first, own, time) == "caretaker" and policy.Role(peer, guild, time) == "caretaker"
		end })
	end
	if not sent then
		request.callbacks = {}
		request.untilAt = now + RETRY
		return false
	end
	return true
end

local function SendWitness(p, now, rev, own, current, sender, nonce, viewer, name)
	if not Exact(viewer) or p.Role(ns.me, own, now) ~= "caretaker" or Moderated(name, own) then return false end
	local origin
	for guild, caretaker in pairs(p.Caretakers()) do
		if Same(caretaker, sender) and not Same(guild, own) then origin = guild; break end
	end
	local at = origin and not Moderated(viewer, origin) and NativeStamp(name, own, now)
	if not at or not Budget(now, sender) then return false end
	local word = table.concat({ "FM", "P", rev, nonce, at, name }, "~")
	return ns.Comm.Whisper(viewer, word, nil, false, false, nil, { guard = function()
		local policy, time, _, _, key = Context()
		return key == current and time - now < WAIT and time - at <= FRESH
			and policy.Role(ns.me, own, time) == "caretaker" and policy.Role(sender, origin, time) == "caretaker"
			and NativeStamp(name, own, time) ~= nil and not Moderated(name, own) and not Moderated(viewer, origin)
	end })
end

local function ReceiveWitness(p, now, sender, nonce, at, name)
	at = tonumber(at)
	if not at or at > now or now - at >= FRESH then return false end
	for key, request in pairs(pending) do
		if request.untilAt > now and request.nonce == nonce and Same(sender, request.peer) and Same(name, request.name)
			and p.Role(sender, request.guild, now) == "caretaker" and not Moderated(name, request.guild) then
			pending[key] = nil
			local heldKey = ns.Fold(name)
			if not proofs[heldKey] and Prune(proofs, now) >= PROOF_MAX then return false end
			proofs[heldKey] = { guild = request.guild, peer = sender, untilAt = at + FRESH }
			for _, callback in ipairs(request.callbacks) do ns.SafeCall("federation membership replay", callback, request.guild) end
			return true
		end
	end
	return false
end

function M.Receive(dist, sender, text)
	if dist ~= "WHISPER" or not Exact(sender) or type(text) ~= "string" or ns.IsSecret(text) or #text > 255
		or (ns.Relay and ns.Relay.Hop and ns.Relay.Hop()) then return false end
	local op, rev, nonce, field, name = text:match("^FM~([QVP])~(%d+)~([%x%-]+)~([^~]+)~([^~]+)$")
	if not op or #nonce > 32 or not Exact(name) then return false end
	local p, now, revision, own, current = Context()
	if not p or tonumber(rev) ~= revision then return false end
	if op == "Q" then return Forward(p, now, revision, own, current, sender, field, name, nonce) end
	if op == "V" then return SendWitness(p, now, revision, own, current, sender, nonce, field, name) end
	return ReceiveWitness(p, now, sender, nonce, field, name)
end

ns.Comm.Handle("FM", M.Receive)


local function Forget()
	scope, pending, proofs, budget = nil, {}, {}, {}
end

ns.On("QUIET_PRESENCE_CHANGED", function(on) if on then Forget() end end)
ns.On("ACCORD_CHANGED", function(accepted) if not accepted then Forget() end end)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit) if not unit or unit == "player" then Forget() end end)
