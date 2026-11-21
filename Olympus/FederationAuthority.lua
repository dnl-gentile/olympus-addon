local _, ns = ...

-- Decisions carry their own signature, not the name written by a relay. An author
-- certificate grants one scoped capability to an account public key. A council
-- caretaker may give its native rank-1 operator a short, guild-only delegation.
-- Neither a certificate nor a received decision grants guild participation.
local A = {}
ns.FederationAuthority = A
local DAY, MAX_WIRE, MAX_RECORDS = 86400, 7000, 512
local handlers, checked, pending, incoming = {}, {}, {}, 0
local serial = 0
local limits = {}
local hashes, hashCount = {}, 0
local function Digest(wire)
	local hash = hashes[wire]
	if not hash then
		if hashCount >= 128 then hashes, hashCount = {}, 0 end
		hash = ns.Debts.Hex(ns.Sign.SHA256(wire))
		hashes[wire], hashCount = hash, hashCount + 1
	end
	return hash
end

local function Clock() return math.floor(ns.Data.ServerTime() or ns.Now()) end
local function Field(s, max)
	return type(s) == "string" and not ns.Secret(nil, s) and #s > 0 and #s <= max and not s:find("[~|%c]")
end
local function Wire(s, max)
	return type(s) == "string" and not ns.Secret(nil, s) and #s > 0 and #s <= max and not s:find("[|%c]")
end
local function Scope()
	local region = type(ns.realm) == "string" and ns.realm:match("^CAMWOW(%u%u)%d+Realm%d+%a+$")
	if region and ns.ForeverFamily(ns.realm) == ns.group and (ns.faction == "Alliance" or ns.faction == "Horde") then
		return table.concat({ region, ns.group, ns.faction }, ":"), region
	end
end
local function Person(s)
	if not Field(s, 100) then return nil end
	local short, realm = s:match("^([%a\128-\255]+ ?[%a\128-\255]*)%-([%w]+)$")
	local _, region = Scope()
	return short and ns.ForeverFamily(realm) == ns.group and realm:match("^CAMWOW(%u%u)") == region and ns.Fold(s) or nil
end
local function Decode(s, max)
	if not Field(s, math.ceil(max * 4 / 3) + 4) then return nil end
	local value = ns.Ed25519.FromB64(s)
	return value and #value <= max and value or nil
end
local function Encode(s) return ns.Ed25519.ToB64(s) end
local function Number(s)
	local n = type(s) == "string" and #s <= 10 and tonumber(s)
	return n and n == math.floor(n) and n >= 1577836800 and n <= 9999999999 and n or nil
end
local function Store()
	if not ns.db or not Scope() then return nil end
	local s = ns.db.federationAuthority
	if type(s) ~= "table" or s.version ~= 1 then s = { version = 1 }; ns.db.federationAuthority = s end
	for _, key in ipairs({ "certificates", "revocations", "records", "floors" }) do
		if type(s[key]) ~= "table" then s[key] = {} end
	end
	return s
end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.Fold(a) == ns.Fold(b) end
local function Rate(key, maximum, window)
	local now, count = Clock(), 0
	for k, v in pairs(limits) do if v.untilAt <= now then limits[k] = nil else count = count + 1 end end
	local row = limits[key]
	if not row then
		if count >= 512 then return false end
		row = { n = 0, untilAt = now + window }; limits[key] = row
	end
	if row.n >= maximum then return false end
	row.n = row.n + 1
	return true
end
local function Role(role, name, guild)
	if role == "council" then return ns.IsHighCouncillor(name) == true or ns.IsAuthorName(name) == true end
	if role == "treasurer" then
		local names, signed = ns.TreasurerPins()
		return signed == true and names and Same(names[1], name)
	end
	if role ~= "operator" or guild == "-" or not (ns.FederationProgram.BaseEnrolled or ns.FederationProgram.IsEnrolled)(guild) then return false end
	local roster = ns.Roster.Fresh()
	-- The signed grant itself attests rank 1 to another guild. Generic remote
	-- census officer rows cannot establish it. Our own native roster can revoke it.
	return not roster or not Same(roster.guild, guild) or ns.Roster.RankOf(name) == 1
end
local Certificate
Certificate = function(wire, at, depth)
	if not Wire(wire, 3000) or type(at) ~= "number" or (depth or 0) > 1 then return nil end
	local body, signature = wire:match("^(FK1~.+)~(%x+)$")
	local scope, name, guild, role, issued, expires, key
	if body then
		scope, name, guild, role, issued, expires, key = body:match("^FK1~([^~]+)~([^~]+)~([^~]+)~(%a+)~(%d+)~(%d+)~([^~]+)$")
		issued, expires, key = Number(issued), Number(expires), key and Decode(key, 32)
		if scope ~= Scope() or not Person(name) or not Field(guild, 72) or not issued or not expires or #tostring(signature) ~= 512
			or not key or #key ~= 32 or expires <= issued or expires - issued > 31 * DAY or at < issued or at >= expires
			or not Role(role, name, guild) then return nil end
		local hash = Digest(wire)
		local s = Store()
		if not s or s.revocations[hash] then return nil end
		if checked[hash] ~= true then
			if not ns.Sign.Verify(body, signature) or not ns.Ed25519.ValidPublicKey(key) then return nil end
			if next(checked) and A.cacheCount and A.cacheCount >= 128 then checked = {}; A.cacheCount = 0 end
			checked[hash], A.cacheCount = true, (A.cacheCount or 0) + 1
		end
		return { issuer = name, guild = guild, role = role, issued = issued, expires = expires, key = key, scope = scope, id = hash }
	end
	-- The complete root certificate is embedded. A collector cannot substitute a
	-- different parent, name, guild, role, time or key under the caretaker's signature.
	body, signature = wire:match("^(FK2~.+)~([^~]+)$")
	if not body then return nil end
	local parent
	scope, name, guild, issued, expires, key, parent = body:match("^FK2~([^~]+)~([^~]+)~([^~]+)~(%d+)~(%d+)~([^~]+)~([^~]+)$")
	issued, expires, key, parent = Number(issued), Number(expires), key and Decode(key, 32), parent and Decode(parent, 1800)
	local cert = parent and issued and Certificate(parent, issued, (depth or 0) + 1)
	local sig = signature and Decode(signature, 64)
	if scope ~= Scope() or not Person(name) or not Field(guild, 72) or not issued or not expires or not key or #key ~= 32
		or not sig or #sig ~= 64 or not cert or cert.role ~= "council" or expires <= issued or expires - issued > 1800
		or at < issued or at >= expires or expires > cert.expires or not (ns.FederationProgram.BaseEnrolled or ns.FederationProgram.IsEnrolled)(guild)
		or ns.FederationProgram.Role(cert.issuer, guild) ~= "caretaker" or not Role("operator", name, guild) then return nil end
	local hash = Digest(wire)
	if Store().revocations[hash] or Store().revocations[cert.id] then return nil end
	if not checked[hash] then
		if not ns.Ed25519.Verify(cert.key, body, sig) then return nil end
		if (A.cacheCount or 0) >= 128 then checked = {}; A.cacheCount = 0 end
		checked[hash], A.cacheCount = true, (A.cacheCount or 0) + 1
	end
	return { issuer = name, guild = guild, role = "operator", issued = issued, expires = expires, key = key, scope = scope, id = hash }
end
A.Certificate = Certificate

function A.ImportCertificate(wire)
	local s, now = Store(), Clock()
	local cert = s and Certificate(wire, now)
	if not cert then return false, "certificate" end
	local count = 0
	for k, value in pairs(s.certificates) do
		if not Certificate(value, now) then s.certificates[k] = nil else count = count + 1 end
	end
	if count >= 128 and not s.certificates[cert.id] then return false, "capacity" end
	s.certificates[cert.id] = wire
	ns.Fire("FEDERATION_AUTHORITY_CHANGED")
	return true
end

local function ControlHere()
	return ns.IsMember() and (ns.FederationProgram.BaseEnrolled or ns.FederationProgram.IsEnrolled)(GetGuildInfo("player"))
end
local function Own(kind, guild)
	if not ControlHere() or ns.QuietPresence() or ns.ChatLocked() then return nil, "access" end
	local s = Store()
	if not s or not next(s.certificates) then return nil, "certificate" end
	local gk, key = ns.Debts.MyKey()
	if not s or not gk or not key then return nil, "identity" end
	local now = Clock()
	for _, wire in pairs(s.certificates) do
		local cert = Certificate(wire, now)
		if cert and Same(cert.issuer, ns.me) and cert.key == key then
			local permitted = kind == "milestones" and cert.role == "treasurer"
				or kind == "fugitive" and (cert.role == "council" or cert.role == "operator")
				or (kind == "appeal" or kind == "suspension") and cert.role == "council"
			if permitted and (cert.guild == "-" or Same(cert.guild, guild)) then return wire, cert end
		end
	end
	return nil, "certificate"
end
function A.Ready(kind, guild) local wire, why = Own(kind, guild or GetGuildInfo("player")); return wire ~= nil, why end
function A.Register(kind, validate, apply)
	assert(kind == "milestones" or kind == "fugitive" or kind == "appeal" or kind == "suspension", "known capability")
	assert(type(validate) == "function" and type(apply) == "function", "handlers")
	handlers[kind] = { validate = validate, apply = apply }
end

local function Parse(kind, wire)
	if not Wire(wire, MAX_WIRE) then return nil end
	local body, sig = wire:match("^(FA1~.+)~([^~]+)$")
	if not body then return nil end
	local scope, what, issuer, guild, issued, expires, id, certificate, content = body:match("^FA1~([^~]+)~(%a+)~([^~]+)~([^~]+)~(%d+)~(%d+)~(%x+)~([^~]+)~([^~]+)$")
	issued, expires, certificate, content, sig = Number(issued), Number(expires), certificate and Decode(certificate, 3000), content and Decode(content, 1800), Decode(sig, 64)
	local now, h = Clock(), handlers[kind]
	if scope ~= Scope() or what ~= kind or not h or not Person(issuer) or not Field(guild, 72) or not issued or not expires
		or issued > now or expires <= now or expires <= issued or expires - issued > 7 * DAY or not id or #id ~= 32
		or not certificate or not content or not sig or #sig ~= 64 then return nil end
	local cert = Certificate(certificate, now)
	if not cert or not Same(cert.issuer, issuer) or (cert.guild ~= "-" and not Same(cert.guild, guild))
		or issued < cert.issued or expires > cert.expires
		or (kind == "milestones" and cert.role ~= "treasurer")
		or (kind ~= "milestones" and cert.role ~= "council" and cert.role ~= "operator")
		or ((kind == "suspension" or kind == "appeal") and cert.role ~= "council")
		or not (ns.FederationProgram.BaseEnrolled or ns.FederationProgram.IsEnrolled)(guild, issued) then return nil end
	if not ns.Ed25519.Verify(cert.key, body, sig) then return nil end
	local r = { kind = kind, scope = scope, issuer = issuer, guild = guild, issued = issued, expires = expires, id = id, content = content, wire = wire, certificate = certificate }
	local parsed, key = h.validate(content, r)
	if not parsed or not Field(key, 200) then return nil end
	r.key, r.parsed = key, parsed
	return r
end

local function Live(r)
	return type(r) == "table" and r.scope == Scope() and type(r.expires) == "number" and r.expires > Clock()
		and type(r.issued) == "number" and Certificate(r.certificate, Clock()) ~= nil
		and (ns.FederationProgram.BaseEnrolled or ns.FederationProgram.IsEnrolled)(r.guild)
end
function A.Accept(kind, wire, guard)
	local s = Store()
	if not s or not ControlHere() then return nil, "access" end
	local r = Parse(kind, wire)
	if not r then return nil, "invalid" end
	if guard and not guard() then return nil, "changed" end
	local k = r.scope .. "|" .. kind .. "|" .. r.key
	local old, floor = s.records[k], s.floors[k]
	if type(floor) ~= "table" or type(floor.at) ~= "number" or type(floor.id) ~= "string" then floor = nil end
	-- A deterministic tie break converges independently of packet order. Retain the
	-- floor after expiry, so a later pardon/withdrawal never resurrects an old word.
	if floor and (r.issued < floor.at or (r.issued == floor.at and r.id <= floor.id)) then return nil, "older" end
	local n, floors = 0, 0
	for key, value in pairs(s.records) do if not Live(value) then s.records[key] = nil else n = n + 1 end end
	for key, value in pairs(s.floors) do
		if type(value) ~= "table" or (tonumber(value.untilAt) or 0) <= Clock() then s.floors[key] = nil else floors = floors + 1 end
	end
	if not old and n >= MAX_RECORDS then return nil, "capacity" end
	if not floor and floors >= 4096 then return nil, "capacity" end
	s.records[k] = r
	s.floors[k] = { at = r.issued, id = r.id, untilAt = r.issued + (kind == "appeal" and 31 or 7) * DAY,
		clear = kind == "appeal" or nil, certificate = kind == "appeal" and Digest(r.certificate) or nil }
	for key, value in pairs(s.floors) do if type(value) ~= "table" or (value.untilAt or 0) <= Clock() then s.floors[key] = nil end end
	handlers[kind].apply(r, r.parsed)
	ns.Fire("FEDERATION_DECISION_CHANGED", kind, r.key)
	return r
end
-- A received pardon is also a replay floor against older complete FUG1 lists.
-- It grants no new authority after expiry and cannot clear a later dated list.
function A.SuppressesOlder(kind, key, issued)
	local s, scope = Store(), Scope()
	local floor = s and scope and s.floors[scope .. "|" .. kind .. "|" .. key]
	return type(floor) == "table" and floor.clear == true and type(floor.at) == "number"
		and type(issued) == "number" and floor.at >= issued and (tonumber(floor.untilAt) or 0) > Clock()
		and type(floor.certificate) == "string" and not s.revocations[floor.certificate] or false
end
function A.Records(kind)
	local s, out = Store(), {}
	for _, r in pairs(s and s.records or {}) do if r.kind == kind and Live(r) then out[#out + 1] = r end end
	table.sort(out, function(a, b) return a.issued == b.issued and a.id < b.id or a.issued < b.issued end)
	return out
end
function A.Current(kind, key)
	if key then
		local s, scope = Store(), Scope()
		local r = s and scope and s.records[scope .. "|" .. kind .. "|" .. key]
		return r and Live(r) and r or nil
	end
	local best
	for _, r in ipairs(A.Records(kind)) do
		if (not key or r.key == key) and (not best or r.issued > best.issued or (r.issued == best.issued and r.id > best.id)) then best = r end
	end
	return best
end

function A.Make(kind, content, guild)
	guild = guild or GetGuildInfo("player")
	if not handlers[kind] or not Wire(content, 1800) or not Field(guild, 72) or not (ns.FederationProgram.BaseEnrolled or ns.FederationProgram.IsEnrolled)(guild) then return nil, "content" end
	local wire, cert = Own(kind, guild)
	if not wire then return nil, cert end
	if kind ~= "milestones" and not ns.FederationProgram.Role(ns.me, guild) and not ns.IsHighCouncillor(ns.me) and not ns.IsAuthorName(ns.me) then return nil, "role" end
	if kind == "suspension" then
		local roster = ns.Roster.Fresh()
		if not roster or not Same(roster.guild, guild) or ns.Roster.RankOf(ns.me) ~= 0 then return nil, "roster" end
	end
	local now, s = Clock(), Store()
	s.sequence = math.max(0, tonumber(s.sequence) or 0) + 1
	local id = ns.Debts.Hex(ns.Sign.SHA256(table.concat({ ns.me, now, s.sequence, kind, content }, "\0"))):sub(1, 32)
	local body = table.concat({ "FA1", Scope(), kind, ns.me, guild, now, math.min(now + 7 * DAY, cert.expires), id, Encode(wire), Encode(content) }, "~")
	local sig = ns.Debts.Sign(body)
	if not sig then return nil, "signing" end
	return body .. "~" .. Encode(sig)
end

local function Peers()
	local out, seen = {}, {}
	local function Add(name)
		if Person(name) and not Same(name, ns.me) and not seen[ns.Fold(name)] and #out < 64 then seen[ns.Fold(name)] = true; out[#out + 1] = name end
	end
	for _, name in ipairs(ns.Comm.Peers()) do Add(name) end
	for _, name in pairs(ns.FederationProgram.Caretakers()) do Add(name) end
	local relay = ns.Relay
	if relay and relay.Names then for _, name in ipairs(relay.Names(true, true)) do Add(ns.FullName(name)) end end
	table.sort(out)
	return out
end
local function Send(to, word, key)
	if not Person(to) or not Wire(word, MAX_WIRE + 16) then return false end
	serial = (serial + 1) % 10000
	return ns.Comm.SendBatch("WHISPER", ns.Codec.Chunk(word, "A" .. serial), key, to, false, nil,
		{ guard = function() return ControlHere() and not ns.QuietPresence() and not ns.ChatLocked() end })
end
function A.Publish(kind, content, guild, guard)
	local wire, why = A.Make(kind, content, guild)
	if not wire then return false, why end
	if guard and not guard() then return false, "changed" end
	local r = A.Accept(kind, wire, guard)
	if not r then return false, "invalid" end
	-- Private anti-entropy pulls move decisions onward; publishing sends at most
	-- four copies now, leaving the census lane and normal chat ahead of recovery.
	for i, name in ipairs(Peers()) do if i <= 4 then Send(name, "F8~1~S~" .. wire, "federation publish " .. kind .. " " .. name) end end
	return true, r
end

local publishing = 0
function A.PublishAsync(kind, content, guild, done, guard)
	if publishing >= 4 then return false, "busy" end
	publishing = publishing + 1
	local accepted, reason
	local queued = ns.Ed25519.Run(function()
		if guard and not guard() then reason = "changed"; return end
		accepted, reason = A.Publish(kind, content, guild, guard)
	end, function(ok)
		publishing = math.max(0, publishing - 1)
		if done then done(ok and accepted == true, reason) end
	end)
	if not queued then publishing = math.max(0, publishing - 1) end
	return queued, queued and "queued" or "busy"
end

local cursor = 0
function A.Sync()
	if not ControlHere() or ns.QuietPresence() or ns.ChatLocked() then return false end
	local peers = Peers()
	if #peers == 0 then return false end
	cursor = cursor % #peers + 1
	local to = peers[cursor]
	return ns.Comm.Whisper(to, "F8~1~Q~" .. Scope(), "federation decision ask", false, false, nil,
		{ guard = function() return ControlHere() and not ns.QuietPresence() end })
end
function A.Receive(dist, sender, word)
	if dist ~= "WHISPER" or not Person(sender) or not Wire(word, MAX_WIRE + 16) or not ControlHere() then return false end
	local now, key = Clock(), ns.Fold(sender)
	if word:sub(1, 7) == "F8~1~D~" then
		if incoming >= 8 or not Rate("delegate:" .. key, 1, 60) or not Rate("crypto:*", 32, 60) then return false end
		local pk, sig = word:match("^F8~1~D~([^~]+)~([^~]+)$")
		pk, sig = pk and Decode(pk, 32), sig and Decode(sig, 64)
		local guild = GetGuildInfo("player")
		local roster = ns.Roster.Fresh()
		if not pk or #pk ~= 32 or not sig or #sig ~= 64 or not roster or not Same(roster.guild, guild)
			or ns.Roster.RankOf(sender) ~= 1 or ns.Roster.RankOf(ns.me) ~= 0
			or ns.FederationProgram.Role(ns.me, guild) ~= "caretaker" then return false end
		local body = table.concat({ "FKD1", Scope(), sender, guild, Encode(pk) }, "~")
		incoming = incoming + 1
		local ok = ns.Ed25519.Run(function()
			if not ns.Ed25519.Verify(pk, body, sig) then return nil end
			return A.Delegate(sender, pk, guild)
		end, function(okJob, certificate)
			incoming = math.max(0, incoming - 1)
			if okJob and certificate and ns.Roster.Fresh() and ns.Roster.RankOf(sender) == 1 then
				Send(sender, "F8~1~C~" .. Encode(certificate), "federation operator grant " .. key)
			end
		end)
		if not ok then incoming = incoming - 1 end
		return ok
	elseif word:sub(1, 7) == "F8~1~C~" then
		local wire = Decode(word:sub(8), 3000)
		if not wire or incoming >= 8 or not Rate("grant:" .. key, 2, 60) or not Rate("crypto:*", 32, 60) then return false end
		incoming = incoming + 1
		local ok = ns.Ed25519.Run(function()
			local cert = Certificate(wire, Clock())
			local _, ownKey = ns.Debts.MyKey()
			if cert and Same(cert.issuer, ns.me) and cert.key == ownKey then return A.ImportCertificate(wire) end
		end, function() incoming = math.max(0, incoming - 1) end)
		if not ok then incoming = incoming - 1 end
		return ok
	elseif word:sub(1, 7) == "F8~1~R~" then
		local wire = word:sub(8)
		if #wire > 900 or incoming >= 8 or not Rate("revoke:" .. key, 4, 60) or not Rate("crypto:*", 32, 60) then return false end
		incoming = incoming + 1
		local ok = ns.Ed25519.Run(function() return A.ImportRevocation(wire) end,
			function() incoming = math.max(0, incoming - 1) end)
		if not ok then incoming = incoming - 1 end
		return ok
	end
	if word == "F8~1~Q~" .. (Scope() or "") then
		if ns.QuietPresence() or ns.ChatLocked() then return false end
		local eligible = false
		for _, name in ipairs(Peers()) do if Same(name, sender) then eligible = true break end end
		if not eligible then return false end
		if not Rate("reply:" .. key, 1, 120) or not Rate("reply:*", 4, 60) then return false end
		local records = {}
		for id, r in pairs(Store().revocations) do
			if type(r) == "table" and type(r.wire) == "string" and (r.at or 0) >= now - 31 * DAY then
				records[#records + 1] = { id = "0" .. id, wire = "F8~1~R~" .. r.wire }
			end
		end
		for kind in pairs(handlers) do for _, r in ipairs(A.Records(kind)) do
			records[#records + 1] = { id = "1" .. r.id, wire = "F8~1~S~" .. r.wire }
		end end
		table.sort(records, function(a, b) return a.id < b.id end)
		for who, row in pairs(pending) do if row.untilAt <= now then pending[who] = nil end end
		local start = (pending[key] and pending[key].cursor or 0) + 1
		for i = start, math.min(start + 3, #records) do Send(sender, records[i].wire, "federation recovery " .. key .. " " .. records[i].id) end
		pending[key] = { cursor = start + 3 >= #records and 0 or start + 3, untilAt = now + 3600 }
		return true
	end
	local wire = word:match("^F8~1~S~(.+)$")
	if not wire or incoming >= 8 then return false end
	local kind = wire:match("^FA1~[^~]+~(%a+)~")
	if not handlers[kind] then return false end
	if not Rate("receive:" .. key, 8, 60) or not Rate("crypto:*", 32, 60) then return false end
	-- Signed publication may arrive unsolicited. It grants nothing until both the
	-- root certificate and message verify, in the existing Ed25519 frame budget.
	incoming = incoming + 1
	local ok = ns.Ed25519.Run(function() return A.Accept(kind, wire) end, function() incoming = math.max(0, incoming - 1) end)
	if not ok then incoming = incoming - 1 end
	return ok
end

function A.Delegate(name, key, guild)
	local parent, cert = Own("fugitive", guild)
	local roster = ns.Roster.Fresh()
	if not parent or cert.role ~= "council" or not Person(name) or type(key) ~= "string" or #key ~= 32
		or not roster or not Same(roster.guild, guild) or ns.FederationProgram.Role(ns.me, guild) ~= "caretaker"
		or ns.Roster.RankOf(ns.me) ~= 0 or ns.Roster.RankOf(name) ~= 1 or not ns.Ed25519.ValidPublicKey(key) then return nil end
	local now = Clock()
	local body = table.concat({ "FK2", Scope(), name, guild, now, math.min(now + 1800, cert.expires), Encode(key), Encode(parent) }, "~")
	return body .. "~" .. Encode(ns.Debts.Sign(body))
end

local lastDelegationAsk = -math.huge
function A.RequestDelegation()
	local guild, now = GetGuildInfo("player"), Clock()
	local roster = ns.Roster.Fresh()
	if now - lastDelegationAsk < 60 or not roster or not Same(roster.guild, guild) or ns.Roster.RankOf(ns.me) ~= 1
		or not ControlHere() or ns.QuietPresence() then return false end
	local who = ns.FederationProgram.Caretakers()[guild]
	local _, key = ns.Debts.MyKey()
	if not Person(who) or Same(who, ns.me) or not key then return false end
	local body = table.concat({ "FKD1", Scope(), ns.me, guild, Encode(key) }, "~")
	lastDelegationAsk = now
	return ns.Comm.Whisper(who, "F8~1~D~" .. Encode(key) .. "~" .. Encode(ns.Debts.Sign(body)), "federation operator request", false, false, nil,
		{ guard = function() return ControlHere() and ns.Roster.Fresh() and ns.Roster.RankOf(ns.me) == 1 end })
end

function A.ImportRevocation(wire)
	if not Wire(wire, 900) then return false end
	local body, sig = wire:match("^(FKR1~.+)~(%x+)$")
	local scope, at, id
	if body then scope, at, id = body:match("^FKR1~([^~]+)~(%d+)~(%x+)$") end
	at = Number(at)
	if scope ~= Scope() or not at or at > Clock() or Clock() - at > 31 * DAY or not id or #id ~= 64
		or not sig or #sig ~= 512 or not ns.Sign.Verify(body, sig) then return false end
	local s, n = Store(), 0
	for key, value in pairs(s.revocations) do
		if type(value) ~= "table" or (value.at or 0) < Clock() - 31 * DAY then s.revocations[key] = nil else n = n + 1 end
	end
	if not s.revocations[id] and n >= 512 then return false end
	if s.revocations[id] then return false end
	s.revocations[id] = { at = at, wire = wire }
	s.certificates[id] = nil
	ns.Fire("FEDERATION_AUTHORITY_CHANGED")
	return true
end

function A.KeyRequest()
	local _, key = ns.Debts.MyKey()
	local scope = Scope()
	if not key or not scope or not Person(ns.me) then return nil end
	return table.concat({ "FKQ1", scope, ns.me, Encode(key) }, "~")
end
function A.Slash(rest)
	if rest == "key" then
		local text = A.KeyRequest()
		if text then ns.UI.ShowCopy(ns.L.FEDERATION_KEY_TITLE, text) else ns.Print(ns.L.FEDERATION_KEY_UNAVAILABLE) end
	elseif rest == "certificate" then ns.Dialog.Show("OLYMPUS_FEDERATION_CERTIFICATE")
	elseif rest == "sync" then ns.Print(A.Sync() and ns.L.FEDERATION_SYNC_STARTED or ns.L.FEDERATION_SYNC_WAIT)
	else ns.Print(ns.L.FEDERATION_KEY_HELP) end
end

StaticPopupDialogs.OLYMPUS_FEDERATION_CERTIFICATE = {
	text = ns.L.FEDERATION_CERTIFICATE_PROMPT, button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 320, maxLetters = 3000, timeout = 0, hideOnEscape = true,
	OnAccept = function(frame) -- gp:popup-focus
		if not ns.Gate.Allowed("popup-focus") then return end
		local box = frame.editBox or frame.EditBox
		local text = box and box:GetText()
		local ok = text and (A.ImportCertificate(text) or A.ImportRevocation(text))
		ns.Print(ok and ns.L.FEDERATION_CERTIFICATE_ACCEPTED or ns.L.FEDERATION_CERTIFICATE_REFUSED)
	end,
}
ns.Comm.RelayPieces({ F8 = true })
ns.Comm.Handle("F8", A.Receive)
ns.On("LOGIN", function()
	ns.After(35, "federation decisions", A.Sync)
	ns.Every(60, "federation decisions", function()
		A.Sync()
		if not A.Ready("fugitive") then A.RequestDelegation() end
	end)
end)
