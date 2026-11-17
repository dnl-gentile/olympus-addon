local ADDON, ns = ...
local Church, Count = ns.Church, ns.ChurchCount

-- Signed federation enrollment can follow an offline Discord review of the guild.
-- It covers guild eligibility, never the identity or verification of a recruit.
-- The recruiting ledger does not retain regional provenance for its wire records,
-- so the trusted reviewer must bind the exact recruit, invite, join and two-sided
-- handoff to the scope in the query. There is no such provider in this addon.
local Conversions = {}
ns.ChurchConversions = Conversions

local verify
local MAX = 50000
local refs, refStore, refCount
local CHANGED = "VERIFIED_CONVERSIONS_CHANGED"

function Conversions.SetVerifier(fn)
	if fn ~= nil and type(fn) ~= "function" then return false end
	verify = fn
	ns.Fire(CHANGED)
	return true
end

local function Scope()
	local group, faction = ns.group, ns.faction
	if type(group) ~= "string" or group == "" or (faction ~= "Alliance" and faction ~= "Horde") then return end
	local realm = ns.realm
	if type(realm) ~= "string" or realm == "" or realm == "?" then return end
	local region = realm:match("^CAMWOW(%u%u)%d+Realm%d+%a+$") or "-"
	return group .. ":" .. faction .. ":" .. region, region
end

local function Store(scope, write)
	if not write then
		local c = ns.rdb and ns.rdb.church
		local stores = type(c) == "table" and c.conversions
		local rows = type(stores) == "table" and stores[scope]
		return type(rows) == "table" and rows or nil
	end
	local c = Church.Store()
	if not c then return nil end
	if type(c.conversions) ~= "table" then c.conversions = {} end
	if type(c.conversions[scope]) ~= "table" then c.conversions[scope] = {} end
	return c.conversions[scope]
end

function Conversions.Available()
	if not verify or not ns.rdb or not ns.IsMember() or not Church.IsKeeper(ns.me) or Church.IsKing(ns.me) then return false end
	local M, program = ns.Moderation, ns.FederationProgram
	if M and M.SelfOff and M.SelfOff() then return false end
	local scope = Scope()
	return scope ~= nil and type(program) == "table" and (program.Active() or Store(scope, false) ~= nil)
end

-- Identifiers are opaque, scoped tokens from the verified integration. Keep only
-- references, never a proof payload, a recruit's character name, or a Discord ID.
local function Ref(value)
	return type(value) == "string" and #value >= 24 and #value <= 96
		and value:match("^[%w_%-]+$") ~= nil and value:match("^%d+$") == nil
end

local function Time(value, latest)
	return type(value) == "number" and value > 0 and value <= latest and value == math.floor(value)
end

local function Index(store)
	if store ~= refStore then
		refs, refStore, refCount = {}, store, 0
		for _, row in pairs(store) do
			refCount = refCount + 1
			if type(row) == "table" then
				if Ref(row.handoff) then refs["h:" .. row.handoff] = true end
				if Ref(row.verification) then refs["v:" .. row.verification] = true end
				if Ref(row.character) then refs["c:" .. row.character] = true end
			end
		end
	end
end

function Conversions.Record(recruit, evidence)
	if not Conversions.Available() then return false, "unavailable" end
	local RR = ns.RecruitRanking
	local join = RR and RR.ConfirmedHandoff and RR.ConfirmedHandoff(recruit)
	if not join or not join.guild then return false, "handoff" end
	local guild, program = join.guild, ns.FederationProgram
	if not program.IsEnrolled(guild) then return false, "enrollment" end
	local name = Count.RecruitMain(join.source) or join.source
	local place = Church.Place(name)
	local role = Church.Role(name)
	if not place or (role ~= "A" and role ~= "M")
		or (not place.signed and (place.since or place.at or 0) > join.invitedAt) then
		return false, "role"
	end
	local scope, region = Scope()
	local group, faction = ns.group, ns.faction
	local recruitKey = Church.Key(join.recruit)
	if not (scope and recruitKey) then return false, "proof" end
	local joinHour = join.joinedAt
	join.group, join.faction, join.region, join.recruiter = group, faction, region, name
	local verifier = verify
	local called, attestation = pcall(verifier, evidence, join)
	if not called or type(attestation) ~= "table" then return false, "proof" end
	local now = Church.Clock()
	local member, handoff, proof = attestation.member, attestation.handoff, attestation.verification
	if attestation.group ~= group or attestation.faction ~= faction or attestation.region ~= region
		or attestation.guild ~= guild or not Ref(member) or not Ref(handoff) or not Ref(proof)
		or not Time(attestation.verifiedAt, now) or not Time(attestation.joinedAt, now)
		or attestation.verifiedAt < attestation.joinedAt
		or attestation.joinedAt < joinHour or attestation.joinedAt >= joinHour + 3600 then
		return false, "proof"
	end
	if Scope() ~= scope or verify ~= verifier or not Conversions.Available() then return false, "unavailable" end
	if not program.IsEnrolled(guild, attestation.joinedAt) then return false, "enrollment" end
	local character = ns.Sign.SHA256("church conversion\0" .. scope .. "\0" .. recruitKey)
		:gsub(".", function(byte) return ("%02x"):format(byte:byte()) end)
	local store = Store(scope, true)
	if not store then return false, "unavailable" end
	Index(store)
	local handoffKey, proofKey, characterKey = "h:" .. handoff, "v:" .. proof, "c:" .. character
	if store[member] or refs[handoffKey] or refs[proofKey] or refs[characterKey] then return false, "duplicate" end
	if refCount >= MAX then return false, "full" end
	store[member] = { recruiter = place.n, role = role, joinedAt = attestation.joinedAt,
		verifiedAt = attestation.verifiedAt, handoff = handoff, verification = proof, character = character }
	refs[handoffKey], refs[proofKey], refs[characterKey], refCount = true, true, true, refCount + 1
	ns.Fire(CHANGED)
	return true
end

function Conversions.Ranking(window)
	if not Conversions.Available() or (window ~= "w" and window ~= "a") then return {} end
	local now = Church.Clock()
	local since = Count.WindowFrom(window, now)
	local totals, rows = {}, {}
	-- Eligibility was checked when recorded. A later enrollment update does not change the tally.
	for member, entry in pairs(Store(Scope(), false) or {}) do
		if Ref(member) and type(entry) == "table" and (entry.role == "A" or entry.role == "M")
			and Ref(entry.handoff) and Ref(entry.verification) and Time(entry.verifiedAt, now)
			and Time(entry.joinedAt, now) and entry.verifiedAt >= entry.joinedAt and entry.joinedAt >= since then
			local key = type(entry.recruiter) == "string" and Church.Key(entry.recruiter)
			if key then
				local row = totals[key]
				if not row then
					row = { key = key, name = entry.recruiter, count = 0 }
					totals[key] = row
					rows[#rows + 1] = row
				end
				row.count = row.count + 1
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.key < b.key
	end)
	return rows
end
