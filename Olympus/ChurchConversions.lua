local ADDON, ns = ...
local Church, Count = ns.Church, ns.ChurchCount

-- Verified conversions live separately from points and historical recruitment totals.
-- The eventual verification integration must validate the supplied proof against
-- the exact realm group, faction, observed invite, join, and handoff in the query.
-- It must attest guild opt-in at the join and verify the recruit's membership.
-- No provider is installed by the public addon alone.
local Conversions = {}
ns.ChurchConversions = Conversions

local verify
local MAX = 50000
local refs, refStore, refCount

function Conversions.SetVerifier(fn)
	if fn ~= nil and type(fn) ~= "function" then return false end
	verify = fn
	ns.Fire("CHURCH_CONVERSIONS_CHANGED")
	return true
end

function Conversions.Available()
	local M = ns.Moderation
	return verify ~= nil and ns.IsMember() == true and Church.IsKeeper(ns.me)
		and not Church.IsKing(ns.me) and not (M and M.SelfOff and M.SelfOff())
end

local function Store(write)
	if not write then
		local c = ns.rdb and ns.rdb.church
		return type(c) == "table" and type(c.conversions) == "table" and c.conversions or nil
	end
	local c = Church.Store()
	if not c then return nil end
	if type(c.conversions) ~= "table" then c.conversions = {} end
	return c.conversions
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
			end
		end
	end
end

function Conversions.Record(recruit, evidence)
	if not Conversions.Available() then return false, "unavailable" end
	local RR = ns.RecruitRanking
	local join = RR and RR.ConfirmedHandoff and RR.ConfirmedHandoff(recruit)
	if not join or not join.guild then return false, "handoff" end
	local name = Count.RecruitMain(join.source) or join.source
	local place = Church.Place(name)
	local role = Church.Role(name)
	if not place or (role ~= "A" and role ~= "M")
		or (not place.signed and (place.since or place.at or 0) > join.invitedAt) then
		return false, "role"
	end
	join.group, join.faction = ns.group, ns.faction
	join.recruiter = name
	local called, attestation = pcall(verify, evidence, join)
	if not called or type(attestation) ~= "table" then return false, "proof" end
	local now = Church.Clock()
	local member, handoff, proof = attestation.member, attestation.handoff, attestation.verification
	if attestation.optedIn ~= true or not Ref(member) or not Ref(handoff) or not Ref(proof)
		or not Time(attestation.verifiedAt, now) or not Time(attestation.joinedAt, now)
		or attestation.verifiedAt < attestation.joinedAt
		or attestation.joinedAt < join.joinedAt or attestation.joinedAt >= join.joinedAt + 3600 then
		return false, "proof"
	end
	local store = Store(true)
	if not store then return false, "unavailable" end
	Index(store)
	local handoffKey, proofKey = "h:" .. handoff, "v:" .. proof
	if store[member] or refs[handoffKey] or refs[proofKey] then return false, "duplicate" end
	if refCount >= MAX then return false, "full" end
	store[member] = { recruiter = place.n, role = role, joinedAt = attestation.joinedAt,
		verifiedAt = attestation.verifiedAt, handoff = handoff, verification = proof }
	refs[handoffKey], refs[proofKey], refCount = true, true, refCount + 1
	ns.Fire("CHURCH_CONVERSIONS_CHANGED")
	return true
end

function Conversions.Ranking(window)
	if not Conversions.Available() or (window ~= "w" and window ~= "a") then return {} end
	local now = Church.Clock()
	local since = Count.WindowFrom(window, now)
	local totals, rows = {}, {}
	for member, entry in pairs(Store(false) or {}) do
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
