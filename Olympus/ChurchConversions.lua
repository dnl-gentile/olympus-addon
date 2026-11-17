local ADDON, ns = ...
local Church, Count = ns.Church, ns.ChurchCount

-- Signed federation enrollment can follow an offline Discord review of the guild.
-- It covers guild eligibility, never the identity or verification of a recruit.
-- The recruiting ledger does not retain regional provenance for its wire records,
-- so the trusted reviewer must bind the exact recruit, invite, join and two-sided
-- handoff to the scope in the query. The offline review receipt can bind that
-- information for a new candidate observed during a native recruiting handoff.
local Conversions = {}
ns.ChurchConversions = Conversions

local verify
local MAX = 50000
local refs, refStore, refCount
local CHANGED = "VERIFIED_CONVERSIONS_CHANGED"
local REVIEW_DAYS, MAX_PASTE = 14, 1200

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

local function Member()
	if not ns.rdb or not ns.IsMember() or Church.IsKing(ns.me) then return false end
	local M, program = ns.Moderation, ns.FederationProgram
	if M and M.SelfOff and M.SelfOff() then return false end
	return Scope() ~= nil and type(program) == "table"
end

function Conversions.Available()
	if not Member() or not Church.IsKeeper(ns.me) then return false end
	local scope = Scope()
	local c = ns.rdb.church
	local reviewed = type(c) == "table" and type(c.reviewedConversionScopes) == "table" and c.reviewedConversionScopes[scope]
	return reviewed == true or (verify ~= nil and (ns.FederationProgram.Active() or Store(scope, false) ~= nil))
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

local function Digest(value)
	return (ns.Sign.SHA256(value):gsub(".", function(byte) return ("%02x"):format(byte:byte()) end))
end

local function Field(value, max)
	return type(value) == "string" and #value > 0 and #value <= max and not value:find("[~|%c]")
end

local function ExactName(value, region)
	if not Field(value, 72) then return nil end
	local normalized = ns.Normal(value)
	local realm = ns.RealmOf(normalized)
	if not realm or not ns.InGroup(realm) or (realm:match("^CAMWOW(%u%u)%d+Realm%d+%a+$") or "-") ~= region then return nil end
	return Church.WireName(normalized)
end

local function Same(a, b)
	return a and b and ns.Fold(a) == ns.Fold(b)
end

local function Candidates(write)
	local scope = Scope()
	if not scope then return nil end
	local c = write and Church.Store() or ns.rdb and ns.rdb.church
	if not c then return nil end
	if write and c.conversionCandidates == nil then c.conversionCandidates = {} end
	local store = c.conversionCandidates
	if type(store) ~= "table" then return nil end
	if write and store[scope] == nil then store[scope] = {} end
	return type(store[scope]) == "table" and store[scope] or nil
end

local function CandidateKey(inviter, recruit)
	local key = Church.Key(recruit)
	return key and ns.Fold(inviter) .. ":" .. key or nil
end

local function PruneCandidates(rows, now)
	local count = 0
	for key, entry in pairs(rows) do
		if type(entry) ~= "table" or not Time(entry.accepted, now) or now - entry.accepted > REVIEW_DAYS * 86400 then
			rows[key] = nil
		else
			count = count + 1
		end
	end
	return count
end

ns.On("RECRUIT_HANDOFF_ACCEPTED", function(recruit, source, inviter, from, to, id)
	if not Member() then return end
	local _, region = Scope()
	recruit, source, inviter = ExactName(recruit, region), ExactName(source, region), ExactName(inviter, region)
	if not recruit or not source or not inviter or not Same(inviter, ns.me)
		or Same(recruit, source) or Same(recruit, inviter) or Same(source, inviter)
		or not Field(from, 72) or not Field(to, 72) or not Field(id, 40) or not id:match("^%d+%-%x+%-%d+$")
		or not ns.FederationProgram.IsEnrolled(to) then return end
	local rows, now = Candidates(true), Church.Clock()
	if not rows then return end
	local key = CandidateKey(inviter, recruit)
	local count = PruneCandidates(rows, now)
	if rows[key] or count >= 96 then return end
	rows[key] = { recruit = recruit, source = source, inviter = inviter, from = from, guild = to, id = id, accepted = now }
end)

-- Both native events were observed in the current guild and local realm.
function Conversions.ObserveNativePair(inviter, recruit, guild, invited, joined)
	local rows = Candidates(false)
	if not rows or not Member() or Church.Key(inviter) ~= Church.Key(ns.me) then return false end
	local entry = rows[CandidateKey(ns.me, recruit)]
	if not entry or entry.joined or not Same(entry.guild, guild)
		or not Time(invited, joined) or not Time(joined, Church.Clock())
		or invited + 3600 <= entry.accepted or invited - entry.accepted > 12 * 3600
		or not ns.FederationProgram.IsEnrolled(guild, joined) then return false end
	entry.invited, entry.joined = invited, joined
	return true
end

function Conversions.ReviewCandidates()
	local result, rows = {}, Candidates(false)
	if not rows or not Member() then return result end
	local guild = ns.FederationProgram.LocalEnrollment()
	local roster = guild and ns.Roster.Fresh()
	if not roster or not Same(roster.guild, guild) or type(roster.members) ~= "table" then return result end
	local names = {}
	for _, row in ipairs(roster.members) do
		local key = Church.Key(row.full)
		if key then
			if names[key] == nil then names[key] = row.full else names[key] = false end
		end
	end
	PruneCandidates(rows, Church.Clock())
	local _, region = Scope()
	for _, entry in pairs(rows) do
		if entry.joined and Same(entry.inviter, ns.me) and Same(entry.guild, guild)
			and Same(names[Church.Key(entry.recruit)], entry.recruit) then
			result[#result + 1] = table.concat({ "OCJ1", ns.group, ns.faction, region, entry.from, entry.guild, entry.recruit,
				entry.source, entry.inviter, entry.id, entry.accepted, entry.invited, entry.joined }, "~")
		end
	end
	table.sort(result)
	return result
end

ns.On("LOGIN", function()
	local rows = Candidates(false)
	if rows then PruneCandidates(rows, Church.Clock()) end
end)

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

local function Record(recruit, evidence, verifier)
	if not verifier or not Member() or not Church.IsKeeper(ns.me) then return false, "unavailable" end
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
	if Scope() ~= scope or not Member() or not Church.IsKeeper(ns.me) then return false, "unavailable" end
	if not program.IsEnrolled(guild, attestation.joinedAt) then return false, "enrollment" end
	if attestation.manual == true then
		local source = ExactName(attestation.source, region)
		local appointed = source and (Count.RecruitMain(source) or source)
		if not appointed or not Same(ExactName(appointed, region), ExactName(place.n, region)) then return false, "role" end
	end
	local character = Digest("church conversion\0" .. scope .. "\0" .. recruitKey)
	local store = Store(scope, true)
	if not store then return false, "unavailable" end
	Index(store)
	local handoffKey, proofKey, characterKey = "h:" .. handoff, "v:" .. proof, "c:" .. character
	if store[member] or refs[handoffKey] or refs[proofKey] or refs[characterKey] then return false, "duplicate" end
	if refCount >= MAX then return false, "full" end
	store[member] = { recruiter = place.n, role = role, joinedAt = attestation.joinedAt,
		verifiedAt = attestation.verifiedAt, handoff = handoff, verification = proof, character = character }
	refs[handoffKey], refs[proofKey], refs[characterKey], refCount = true, true, true, refCount + 1
	if attestation.manual == true then
		local c = Church.Store()
		if type(c.reviewedConversionScopes) ~= "table" then c.reviewedConversionScopes = {} end
		c.reviewedConversionScopes[scope] = true
	end
	ns.Fire(CHANGED)
	return true
end

function Conversions.Record(recruit, evidence)
	return Record(recruit, evidence, verify)
end

function Conversions.ImportReview(blob)
	if not Member() or not Church.IsKeeper(ns.me) then return false, "unavailable" end
	if type(blob) ~= "string" or #blob > MAX_PASTE then return false, "proof" end
	blob = blob:match("^%s*(.-)%s*$")
	local text, checked, candidate, sig = blob:match("^(OCV1~(%d+)~(OCJ1~[^\r\n]+))~(%x+)$")
	if not text or #sig ~= 512 then return false, "proof" end
	local group, faction, region, from, guild, recruit, source, inviter, id, accepted, invited, joined =
		candidate:match("^OCJ1~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~(%d+)~(%d+)~(%d+)$")
	local _, ownRegion = Scope()
	if group ~= ns.group or faction ~= ns.faction or region ~= ownRegion then return false, "scope" end
	if not Field(from, 72) or not Field(guild, 72) or not Field(id, 40) or not id:match("^%d+%-%x+%-%d+$")
		or not ExactName(recruit, region) or not ExactName(source, region) or not ExactName(inviter, region) then return false, "proof" end
	checked, accepted, invited, joined = tonumber(checked), tonumber(accepted), tonumber(invited), tonumber(joined)
	local now = Church.Clock()
	if not Time(checked, now) or not Time(joined, checked) or not Time(invited, joined) or not Time(accepted, checked)
		or now - accepted > REVIEW_DAYS * 86400 or invited + 3600 <= accepted or invited - accepted > 12 * 3600
		or invited % 3600 ~= 0 or joined % 3600 ~= 0 or not ns.Sign.Plausible(sig) or not ns.Sign.Verify(text, sig) then return false, "proof" end
	return Record(recruit, nil, function(_, join)
		if not Same(guild, join.guild) or Church.Key(recruit) ~= Church.Key(join.recruit) or Church.Key(source) ~= Church.Key(join.source)
			or Church.Key(inviter) ~= Church.Key(join.inviter) or invited ~= join.invitedAt or joined ~= join.joinedAt then return nil end
		local scope = Scope()
		return { group = group, faction = faction, region = region, guild = join.guild, joinedAt = joined, verifiedAt = checked,
			manual = true, source = source,
			member = Digest("reviewed character\0" .. scope .. "\0" .. Church.Key(recruit)),
			handoff = Digest("reviewed handoff\0" .. source .. "\0" .. inviter .. "\0" .. id), verification = Digest(text) }
	end)
end

StaticPopupDialogs["OLYMPUS_CONVERSION_REVIEW"] = {
	text = ns.L.CHURCH_CONVERSION_IMPORT, button1 = ns.L.OK or "OK", button2 = ns.L.CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 320, maxLetters = MAX_PASTE,
	OnShow = function(self)
		local box = self.editBox or self.EditBox
		if box then box:SetText("") end
	end,
	OnAccept = function(self)
		local box = self.editBox or self.EditBox
		local ok = box and Conversions.ImportReview(box:GetText())
		ns.Print(ok and ns.L.CHURCH_CONVERSION_IMPORTED or ns.L.CHURCH_CONVERSION_REJECTED)
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function Conversions.Slash(action)
	if action == "review" then
		local rows = Conversions.ReviewCandidates()
		if #rows > 0 and ns.UI and ns.UI.ShowCopy then
			return ns.UI.ShowCopy(ns.L.CHURCH_CONVERSION_REVIEW, table.concat(rows, "\n"), nil, { key = "conversion-review", big = true })
		end
		return ns.Print(ns.L.CHURCH_CONVERSION_NO_REVIEW)
	elseif action == "import" and Member() and Church.IsKeeper(ns.me) and ns.FederationProgram.Active() then
		return ns.ShowDialog("OLYMPUS_CONVERSION_REVIEW")
	end
	return ns.Print(ns.L.CHURCH_CONVERSION_USAGE)
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
