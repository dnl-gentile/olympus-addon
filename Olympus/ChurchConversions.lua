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

local function InScope()
	if not ns.rdb or not ns.IsMember() then return false end
	local M, program = ns.Moderation, ns.FederationProgram
	if M and M.SelfOff and M.SelfOff() then return false end
	return Scope() ~= nil and type(program) == "table"
end

local function Member()
	return InScope() and not Church.IsKing(ns.me)
end

local function Reviewed(scope)
	local c = ns.rdb.church
	return type(c) == "table" and type(c.reviewedConversionScopes) == "table" and c.reviewedConversionScopes[scope] == true
end

local function LocalAvailable()
	if not Member() or not Church.IsKeeper(ns.me) then return false end
	local scope = Scope()
	return Reviewed(scope) or (verify ~= nil and (ns.FederationProgram.Active() or Store(scope, false) ~= nil))
end

function Conversions.Available()
	return LocalAvailable() or (InScope() and Church.InAudience(ns.me) and ns.FederationProgram.Active())
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

local function ActorKey(name)
	local _, region = Scope()
	local exact = ExactName(name, region)
	if not exact then return nil end
	-- The Forever server sometimes supplies same-region whisper senders bare.
	return ns.Fold(region ~= "-" and ns.ShortName(exact) or exact)
end

local function ScopeTable(field, write)
	local scope = Scope()
	if not scope then return nil end
	local c = write and Church.Store() or ns.rdb and ns.rdb.church
	if not c then return nil end
	if write and c[field] == nil then c[field] = {} end
	local store = c[field]
	if type(store) ~= "table" then return nil end
	if write and store[scope] == nil then store[scope] = {} end
	return type(store[scope]) == "table" and store[scope] or nil
end

local function Candidates(write) return ScopeTable("conversionCandidates", write) end

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
function Conversions.ObserveNativePair(inviter, recruit, guild, invited, joined, absentSince)
	if Conversions.ReportRosterWitness then Conversions.ReportRosterWitness(inviter, recruit, guild, invited, joined, absentSince) end
	local rows = Candidates(false)
	if not rows or not Member() or Church.Key(inviter) ~= Church.Key(ns.me) then return false end
	local entry = rows[CandidateKey(ns.me, recruit)]
	if not entry or entry.joined or not Same(entry.guild, guild)
		or not Time(invited, joined) or not Time(joined, Church.Clock())
		or invited + 3600 <= entry.accepted or invited - entry.accepted > 12 * 3600
		or not ns.FederationProgram.IsEnrolled(guild, math.max(joined, entry.accepted)) then return false end
	entry.invited, entry.joined = invited, joined
	if Conversions.FlushAutomatic then Conversions.FlushAutomatic() end
	return true
end

local function ReadyCandidates()
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
	for _, entry in pairs(rows) do
		if entry.joined and Same(entry.inviter, ns.me) and Same(entry.guild, guild)
			and ActorKey(names[Church.Key(entry.recruit)]) == ActorKey(entry.recruit) then result[#result + 1] = entry end
	end
	return result
end

function Conversions.ReviewCandidates()
	local result = {}
	local _, region = Scope()
	for _, entry in ipairs(ReadyCandidates()) do
		result[#result + 1] = table.concat({ "OCJ1", ns.group, ns.faction, region, entry.from, entry.guild, entry.recruit,
			entry.source, entry.inviter, entry.id, entry.accepted, entry.invited, entry.joined }, "~")
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

local function Record(recruit, evidence, verifier, scopedJoin)
	if not verifier or not Member() or not Church.IsKeeper(ns.me) then return false, "unavailable" end
	local RR = ns.RecruitRanking
	local join = scopedJoin or (RR and RR.ConfirmedHandoff and RR.ConfirmedHandoff(recruit))
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
	if attestation.manual == true or attestation.automatic == true then
		local source = ExactName(attestation.source, region)
		local appointed = source and (Count.RecruitMain(source) or source)
		if not appointed or not ActorKey(appointed) or ActorKey(appointed) ~= ActorKey(place.n) then return false, "role" end
	end
	local character = Digest("church conversion\0" .. scope .. "\0" .. recruitKey)
	local store = Store(scope, true)
	if not store then return false, "unavailable" end
	Index(store)
	local handoffKey, proofKey, characterKey = "h:" .. handoff, "v:" .. proof, "c:" .. character
	if store[member] or refs[handoffKey] or refs[proofKey] or refs[characterKey] then return false, "duplicate" end
	if refCount >= MAX then return false, "full" end
	store[member] = { recruiter = place.n, role = role, joinedAt = attestation.joinedAt,
		verifiedAt = attestation.verifiedAt, handoff = handoff, verification = proof, character = character,
		reviewed = (attestation.manual == true or attestation.automatic == true) or nil }
	refs[handoffKey], refs[proofKey], refs[characterKey], refCount = true, true, true, refCount + 1
	if attestation.manual == true or attestation.automatic == true then
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

function Conversions.Ranking(window, reviewedOnly, at)
	if not LocalAvailable() or (window ~= "w" and window ~= "a") then return {} end
	local now = at or Church.Clock()
	local since = Count.WindowFrom(window, now)
	local totals, rows = {}, {}
	-- Eligibility was checked when recorded. A later enrollment update does not change the tally.
	for member, entry in pairs(Store(Scope(), false) or {}) do
		if Ref(member) and type(entry) == "table" and (entry.role == "A" or entry.role == "M")
			and (not reviewedOnly or entry.reviewed == true)
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

-- One keeper's capped aggregate, requested only while the Church page is open. Separate
-- from the recruiting evidence protocols: a response never contains a recruit or proof.
local asks, pages, served = {}, {}, {}
local requestSerial = 0
local ASK_GAP, REPLY_TTL, REFRESH, REPLY_BUDGET = 30, 90, 5 * 60, 8

local function Audience(name)
	local key = ActorKey(name)
	local M = ns.Moderation
	return key and Church.InAudience(name) and not (M and M.Hides and M.Hides(name, nil)) and key or nil
end

local function Keeper(name)
	local key = Audience(name)
	if not key or not Church.IsKeeper(name) or Church.IsKing(name) then return nil end
	local role = Church.Role(name)
	if role == "A" then
		local place = Church.Place(name)
		if not place or ActorKey(place.n) ~= key then return nil end
	elseif role == "H" and ActorKey(Church.HeadName()) ~= key then
		return nil
	end
	return key
end

local function BoardScope()
	local scope = Scope()
	return Field(scope, 120) and scope or nil
end

local function Identity(scope)
	return scope .. "~" .. ns.me
end

local function Window(window)
	return window == "w" or window == "a"
end

local function ShareScope()
	return InScope() and not (ns.QuietPresence and ns.QuietPresence()) and ns.FederationProgram.Active()
end

-- Conversion evidence is private to the keepers. The receiver's accepted transaction and native
-- join, the sender's acknowledgement of the same transaction, and a direct strong native witness
-- are all required. Old recruiting ledger pages cannot supply any missing part.
local AUTO_LIMIT, AUTO_GAP, AUTO_AGE = 256, 180, REVIEW_DAYS * 86400
local autoAt, autoIdentity, flushActive

local function TxId(id)
	return Field(id, 40) and id:match("^%d+%-%x+%-%d+$") ~= nil
end

local function TxKey(source, inviter, recruit, guild, id)
	local from, to, key = ActorKey(source), ActorKey(inviter), ActorKey(recruit)
	if not from or not to or not key or from == to or from == key or to == key then return nil end
	return Digest(table.concat({ from, to, key, ns.Fold(guild), id }, "\0"))
end

local function PairKey(inviter, recruit, guild, invited, joined)
	local a, b = Church.Key(inviter), Church.Key(recruit)
	if not a or not b then return nil end
	return Digest(table.concat({ a, b, ns.Fold(guild), invited, joined }, "\0"))
end

local function Note(field, key, now)
	local rows = ScopeTable(field, true)
	if not rows then return nil end
	local n, oldest, first = 0
	for k, row in pairs(rows) do
		if type(row) ~= "table" or not Time(row.at, now) or now - row.at > AUTO_AGE then
			rows[k] = nil
		else
			n = n + 1
			if not first or row.at < first then oldest, first = k, row.at end
		end
	end
	if rows[key] then return rows[key] end
	if n >= AUTO_LIMIT then rows[oldest] = nil end
	local row = { at = now }
	rows[key] = row
	return row
end

local function Ack(who, scope, key)
	if ActorKey(who) == ActorKey(ns.me) then return end
	ns.Comm.Whisper(who, ("NY~1~k~%s~%s"):format(scope, key), nil, false, false, nil, {
		owner = Conversions, guard = function() return ShareScope() and Keeper(ns.me) ~= nil and BoardScope() == scope end,
	})
end

local function FinishAutomatic(scope, key, entry)
	if not scope then return false end
	local c, h = entry.c, entry.h
	if not c or not h or math.abs(c.accepted - h.accepted) > 120 then return false end
	local paired = ScopeTable("conversionWitnesses", false)
	local evidence = paired and paired[c.pair]
	if not evidence or type(evidence.observers) ~= "table" then return false end
	local function Independent(name)
		return ActorKey(name) ~= ActorKey(c.source) and ActorKey(name) ~= ActorKey(c.inviter)
			and ActorKey(name) ~= ActorKey(c.recruit) and not Count.Linked(name, c.source)
			and not Count.Linked(name, c.inviter) and not Count.Linked(name, c.recruit)
	end
	local eligibleAt, rosterProof
	for _, observer in pairs(evidence.observers) do
		if Independent(observer.name) then
			if observer.roster and observer.inviter == ActorKey(c.inviter) and observer.recruit == ActorKey(c.recruit)
				and ns.FederationProgram.Role(observer.name, c.guild, observer.joinedAt) then
				eligibleAt, rosterProof = observer.joinedAt, true
				break
			elseif not observer.roster then
				eligibleAt = c.joined
			end
		end
	end
	if not eligibleAt then return false end
	if Count.Linked(c.inviter, c.recruit) or Count.Linked(c.source, c.recruit) then return false end
	local scopedJoin = rosterProof and { recruit = c.recruit, inviter = c.inviter, source = c.source, guild = c.guild,
		invitedAt = c.invited, joinedAt = c.joined } or nil
	local now = Church.Clock()
	local ok, why = Record(c.recruit, nil, function(_, join)
		if join.invitedAt ~= c.invited or join.joinedAt ~= c.joined or not Same(join.guild, c.guild)
			or Church.Key(join.source) ~= Church.Key(c.source) or Church.Key(join.inviter) ~= Church.Key(c.inviter) then return nil end
		local _, region = Scope()
		return { group = ns.group, region = region, faction = ns.faction, guild = join.guild, source = c.source,
			automatic = true, member = Digest("conversion character\0" .. ActorKey(c.recruit)),
			handoff = key, verification = Digest(key .. c.pair), joinedAt = eligibleAt, verifiedAt = now }
	end, scopedJoin)
	if not ok and why ~= "duplicate" then return false end
	Ack(c.inviter, scope, key)
	Ack(c.source, scope, key)
	-- Retain only the completed receipt key for retries during its window.
	entry.c, entry.h, entry.done = nil, nil, true
	return true
end

local function StoreWitness(sender, inviter, recruit, guild, invited, joined, eligibleAt, roster)
	local actor = ActorKey(sender)
	if not ShareScope() or not Keeper(ns.me) or not actor or not ns.FederationProgram.IsEnrolled(guild, eligibleAt) then return false end
	local now, key = Church.Clock(), PairKey(inviter, recruit, guild, invited, joined)
	if not key or not Time(invited, joined) or not Time(joined, now) then return false end
	local row = Note("conversionWitnesses", key, now)
	if not row then return false end
	row.observers = row.observers or {}
	local count = 0
	for _ in pairs(row.observers) do count = count + 1 end
	if count >= 4 and not row.observers[actor] then return false end
	if not row.observers[actor] or roster then
		row.observers[actor] = { name = sender, joinedAt = eligibleAt, roster = roster,
			inviter = roster and ActorKey(inviter) or nil, recruit = roster and ActorKey(recruit) or nil }
	end
	local inbox, scope = ScopeTable("conversionInbox", false), BoardScope()
	for tx, row in pairs(inbox or {}) do
		if row.c and row.c.pair == key then FinishAutomatic(scope, tx, row) end
	end
	return true
end

function Conversions.NoteStrongWitness(sender, inviter, recruit, guild, invited, joined)
	return StoreWitness(sender, inviter, recruit, guild, invited, joined, joined, false)
end

-- A roster read before the recruit appeared gives a real lower bound for the join
-- even when the native log rounds back to an hour before the signed grant began.
local rosterRows, rosterGeneration, present
function Conversions.ObserveAbsence(recruit, guild)
	local program = ns.FederationProgram
	if not Member() or not program.Role(ns.me, guild) then return nil end
	local roster = ns.Roster.Fresh()
	local at, key = roster and roster.serverAt, Church.Key(recruit)
	if not key or not Time(at, Church.Clock()) or not Same(program.LocalEnrollment(at), guild)
		or type(roster.members) ~= "table" then return nil end
	if rosterRows ~= roster.members or rosterGeneration ~= roster.generation then
		rosterRows, rosterGeneration, present = roster.members, roster.generation, {}
		for _, row in ipairs(rosterRows) do
			local name = Church.Key(row.full)
			if name then present[name] = true end
		end
	end
	return not present[key] and at or nil
end

function Conversions.ReportRosterWitness(inviter, recruit, guild, invited, joined, absentSince)
	local scope, program = BoardScope(), ns.FederationProgram
	if not scope or not ShareScope() or not ActorKey(inviter) or not ActorKey(recruit)
		or ActorKey(ns.me) == ActorKey(inviter) or ActorKey(ns.me) == ActorKey(recruit)
		or Count.Linked(ns.me, inviter) or Count.Linked(ns.me, recruit)
		or not program.Role(ns.me, guild) or not Same(program.LocalEnrollment(), guild) then return false end
	local absent = Time(absentSince, Church.Clock()) and absentSince < joined + 3600
	local eligibleAt = absent and math.max(joined, absentSince) or joined
	if not program.Role(ns.me, guild, eligibleAt) then return false end
	local text = ("NE~1~v~%s~%s~%s~%s~%d~%d~%d"):format(scope, guild, inviter, recruit, invited, joined, eligibleAt)
	if #text > 255 then return false end
	return ns.RecruitRanking.Report(text)
end

function Conversions.TakeRosterWitness(sender, text)
	local scope, guild, inviter, recruit, invited, joined, eligibleAt =
		text:match("^NE~1~v~([^~]+)~([^~]+)~([^~]+)~([^~]+)~(%d+)~(%d+)~(%d+)$")
	invited, joined, eligibleAt = tonumber(invited), tonumber(joined), tonumber(eligibleAt)
	local actor, program, now = ActorKey(sender), ns.FederationProgram, Church.Clock()
	if not scope or scope ~= BoardScope() or not ShareScope() or not actor
		or not ActorKey(inviter) or not ActorKey(recruit) or actor == ActorKey(inviter) or actor == ActorKey(recruit)
		or Count.Linked(sender, inviter) or Count.Linked(sender, recruit)
		or not Time(eligibleAt, now) or not Time(joined, eligibleAt) or eligibleAt >= joined + 3600
		or not Time(invited, joined) or invited % 3600 ~= 0 or joined % 3600 ~= 0
		or not program.Role(sender, guild, eligibleAt) then return false end
	return StoreWitness(sender, inviter, recruit, guild, invited, joined, eligibleAt, true)
end

local function ReceiveAutomatic(sender, scope, kind, body)
	local peer = ActorKey(sender)
	local M = ns.Moderation
	if not peer or (M and M.Hides and M.Hides(sender, nil)) then return false end
	if kind == "k" then
		if not Keeper(sender) or #body ~= 64 or not body:match("^%x+$") then return false end
		for _, field in ipairs({ "conversionCandidates", "conversionSources" }) do
			for _, entry in pairs(ScopeTable(field, false) or {}) do
				if entry.key == body and ActorKey(entry.owner) == ActorKey(ns.me) then entry.acked = true end
			end
		end
		return true
	end
	if not Keeper(ns.me) then return false end
	local id, guild, recruit, other, accepted, invited, joined =
		body:match("^([^~]+)~([^~]+)~([^~]+)~([^~]+)~(%d+)~(%d+)~(%d+)$")
	accepted, invited, joined = tonumber(accepted), tonumber(invited), tonumber(joined)
	local now = Church.Clock()
	if not TxId(id) or not Field(guild, 72) or not Time(accepted, now + 60) or now - accepted > AUTO_AGE then return false end
	local source, inviter = kind == "h" and sender or other, kind == "h" and other or sender
	local key = TxKey(source, inviter, recruit, guild, id)
	if not key or not ns.FederationProgram.IsEnrolled(guild) then return false end
	if kind == "c" and (not Time(invited, joined) or not Time(joined, now) or invited % 3600 ~= 0 or joined % 3600 ~= 0
		or invited + 3600 <= accepted or invited - accepted > 12 * 3600
		or not ns.FederationProgram.IsEnrolled(guild, math.max(joined, accepted))) then return false end
	if kind == "h" and (invited ~= 0 or joined ~= 0) then return false end
	local entry = Note("conversionInbox", key, now)
	if not entry then return false end
	if entry.done then Ack(sender, scope, key); return true end
	if kind == "h" then
		if not entry.h then entry.h = { accepted = accepted } end
	else
		entry.c = entry.c or { accepted = accepted, invited = invited, joined = joined, guild = guild, source = source,
			inviter = inviter, recruit = recruit, pair = PairKey(inviter, recruit, guild, invited, joined) }
	end
	FinishAutomatic(scope, key, entry)
	return true
end

ns.On("RECRUIT_HANDOFF_ACKNOWLEDGED", function(recruit, source, inviter, guild, id)
	if not Member() or ActorKey(source) ~= ActorKey(ns.me) or not TxId(id) or not Field(guild, 72)
		or not ns.FederationProgram.IsEnrolled(guild) then return end
	local key = TxKey(source, inviter, recruit, guild, id)
	local now = Church.Clock()
	local row = key and Note("conversionSources", key, now)
	if not row or row.owner then return end
	row.owner, row.key, row.id, row.guild, row.recruit, row.other, row.accepted = source, key, id, guild, recruit, inviter, now
	Conversions.FlushAutomatic()
end)

function Conversions.FlushAutomatic()
	if not ShareScope() or flushActive then return end
	local scope, now = BoardScope(), Church.Clock()
	if not scope then return end
	local candidates = Candidates(false)
	local sources = ScopeTable("conversionSources", false)
	local inbox = Keeper(ns.me) and ScopeTable("conversionInbox", false) or nil
	if not candidates and not sources and not inbox then return end
	local identity = Identity(scope)
	if autoIdentity == identity and autoAt and now - autoAt < 15 then return end
	autoIdentity, autoAt, flushActive = identity, now, true
	for key, row in pairs(inbox or {}) do
		if not Time(row.at, now) or now - row.at > AUTO_AGE then inbox[key] = nil
		elseif not row.done then FinishAutomatic(scope, key, row) end
	end
	local me, destinations = ActorKey(ns.me), {}
	for _, keeper in ipairs(Church.KeepersOnline(true)) do
		local key = Keeper(keeper.name)
		if key then destinations[#destinations + 1] = { name = keeper.name, key = key } end
		if #destinations >= 4 then break end
	end
	local budget = 8
	local function Send(row, kind, other)
		if budget <= 0 or row.acked or ActorKey(row.owner) ~= me or now - row.accepted > AUTO_AGE
			or (row.sent and now - row.sent < AUTO_GAP) then return end
		local body = table.concat({ row.id, row.guild, row.recruit, other, row.accepted, row.invited or 0, row.joined or 0 }, "~")
		local text = ("NY~1~%s~%s~%s"):format(kind, scope, body)
		if #text > 255 then return end
		for _, keeper in ipairs(destinations) do
			if budget <= 0 then break end
			if keeper.key == me then ReceiveAutomatic(ns.me, scope, kind, body)
			else
				ns.Comm.Whisper(keeper.name, text, nil, false, false, nil, {
					owner = Conversions,
					guard = function() return ShareScope() and BoardScope() == scope and Identity(scope) == identity and Keeper(keeper.name) == keeper.key end,
				})
			end
			row.sent, budget = now, budget - 1
		end
	end
	for key, row in pairs(sources or {}) do
		if not Time(row.at, now) or now - row.at > AUTO_AGE then sources[key] = nil
		elseif row.owner then Send(row, "h", row.other) end
	end
	local pending
	for _, row in pairs(candidates or {}) do
		if row.joined and not row.acked and (not row.sent or now - row.sent >= AUTO_GAP) then pending = true break end
	end
	if pending then
		for _, row in ipairs(ReadyCandidates()) do
			row.owner = row.inviter
			row.key = TxKey(row.source, row.inviter, row.recruit, row.guild, row.id)
			if row.key then Send(row, "c", row.source) end
		end
	end
	flushActive = false
end

function Conversions.Ask(window, force)
	if not Window(window) or not ShareScope() or not Audience(ns.me) or LocalAvailable() then return false end
	local scope = BoardScope()
	if not scope then return false end
	local now, identity = ns.Now(), Identity(scope)
	local last = asks[window]
	if last and last.identity == identity then
		if now < last.t + ASK_GAP or (last.open and now < last.expires) then return false end
		if last.complete and not force and now < last.t + REFRESH then return false end
	else
		last = nil
	end
	local keepers = {}
	for _, candidate in ipairs(Church.KeepersOnline(false)) do
		local key = Keeper(candidate.name)
		if key then keepers[#keepers + 1] = { key = key, name = candidate.name } end
	end
	if #keepers == 0 then Church.FindKeeper(); return false end
	local selected = keepers[1]
	for i, current in ipairs(keepers) do
		if last and current.key == last.source then
			selected = keepers[last.complete and i or i % #keepers + 1]
			break
		end
	end
	requestSerial = (requestSerial + 1) % 65536
	local token = ("%x-%x-%x"):format(math.floor(now), math.random(1, 1073741823), requestSerial)
	local request = { identity = identity, source = selected.key, token = token, t = now, open = true,
		expires = now + REPLY_TTL, rows = {}, count = 0 }
	asks[window] = request
	local sent = ns.Comm.Whisper(selected.name, ("NY~1~q~%s~%s~%s~-"):format(scope, window, token),
		nil, false, false, function(ok) if not ok then request.open = false end end, {
			owner = Conversions,
			guard = function()
				return asks[window] == request and request.open and ns.Now() < request.expires
					and ShareScope() and BoardScope() == scope and Identity(scope) == identity and Audience(ns.me) ~= nil
					and Keeper(selected.name) == selected.key
			end,
		})
	if not sent then request.open = false end
	return sent
end

local function Answer(sender, scope, window, token)
	local asker, keeper = Audience(sender), Keeper(ns.me)
	-- Only a keeper with imported rows can publish. A zero this week is valid for
	-- such a keeper. An uninitialized ledger has no coverage to publish.
	if not asker or not keeper or not Reviewed(scope) then return false end
	local now, query = ns.Now(), asker .. ":" .. window
	for i = #served, 1, -1 do
		if now - served[i].time >= REFRESH then table.remove(served, i) end
	end
	if #served >= REPLY_BUDGET then return false end
	for _, reply in ipairs(served) do
		if reply.query == query and (reply.token == token or now - reply.time < ASK_GAP) then return false end
	end
	local asOf = Church.Clock()
	local RR, lines, rows = ns.RecruitRanking, {}, Conversions.Ranking(window, true, asOf)
	for i = 1, math.min(#rows, RR.RANK_ROWS) do
		local row = rows[i]
		local name = Church.WireName(row.name)
		if not name then return false end
		lines[i] = ("NY~1~r~%s~%s~%s~%d~%s~%d"):format(scope, window, token, i, name, row.count)
	end
	lines[#lines + 1] = ("NY~1~e~%s~%s~%s~%d~%d~%d"):format(scope, window, token, #lines, #rows, asOf)
	for _, line in ipairs(lines) do if #line > 255 then return false end end
	local identity = Identity(scope)
	if not RR.SendLines(sender, lines, nil, function()
		return ShareScope() and BoardScope() == scope and Identity(scope) == identity and Keeper(ns.me) == keeper
			and Audience(sender) == asker
	end, RR.QUEUE_ASKS) then return false end
	served[#served + 1] = { time = now, query = query, token = token }
	return true
end

local function TakeAnswer(sender, scope, window, token, kind, body)
	local a = asks[window]
	local key = Keeper(sender)
	if not a or not a.open or not key or key ~= a.source or token ~= a.token or a.identity ~= Identity(scope) or ns.Now() >= a.expires then return false end
	local limit = ns.RecruitRanking.RANK_ROWS
	if kind == "r" then
		local rank, name, count = body:match("^(%d+)~([^~]+)~(%d+)$")
		rank, count = tonumber(rank), tonumber(count)
		local exact, rowKey = Church.WireName(name), Church.Key(name)
		if not rank or rank < 1 or rank > limit or not exact or not rowKey or not count or count < 1 or count > MAX
			or a.rows[rank] or (a.size and rank > a.size) then return false end
		a.rows[rank], a.count = { name = exact, key = rowKey, count = count }, a.count + 1
	elseif kind == "e" then
		local size, ranked, asOf = body:match("^(%d+)~(%d+)~(%d+)$")
		size, ranked, asOf = tonumber(size), tonumber(ranked), tonumber(asOf)
		if a.size or not ranked or ranked > MAX or size ~= math.min(ranked, limit) or not Time(asOf, Church.Clock() + 60)
			or asOf < Church.Clock() - REPLY_TTL then return false end
		a.size, a.ranked, a.asOf = size, ranked, asOf
	else
		return false
	end
	if a.count ~= a.size then return true end
	local seen, total = {}, 0
	for i = 1, a.size do
		local row = a.rows[i]
		if not row or seen[row.key] or (i > 1 and row.count > a.rows[i-1].count) then a.open = false; return false end
		seen[row.key], total = true, total + row.count
	end
	if total > MAX then a.open = false; return false end
	a.open, a.complete = false, true
	local old = pages[window]
	if old and old.identity == a.identity and old.key == key and old.asOf > a.asOf then return false end
	pages[window] = { identity = a.identity, key = key, from = sender, asOf = a.asOf, ranked = a.ranked, rows = a.rows }
	ns.Fire(CHANGED)
	return true
end

ns.Comm.Handle("NY", function(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 255 or not ShareScope() then return false end
	local evidence, proofScope, proof = text:match("^NY~1~([hck])~([^~]+)~(.+)$")
	if evidence then return proofScope == BoardScope() and ReceiveAutomatic(sender, proofScope, evidence, proof) end
	local kind, scope, window, token, body = text:match("^NY~1~([qre])~([^~]+)~([wa])~([0-9a-f%-]+)~(.+)$")
	if not token or #token > 32 or scope ~= BoardScope() then return false end
	if kind == "q" then return body == "-" and Answer(sender, scope, window, token) end
	if not Audience(ns.me) then return false end
	return TakeAnswer(sender, scope, window, token, kind, body)
end)

function Conversions.RankingView(window)
	if not Window(window) or not Conversions.Available() then return {}, nil, false, 0 end
	if LocalAvailable() then
		local rows = Conversions.Ranking(window)
		return rows, ns.me, false, #rows
	end
	local scope, page, ask = BoardScope(), pages[window], asks[window]
	if not scope or not Audience(ns.me) then return {}, nil, false, 0 end
	local identity = Identity(scope)
	local waiting = ask and ask.identity == identity and ask.open and ns.Now() < ask.expires
	if not page or page.identity ~= identity or Keeper(page.from) ~= page.key then return {}, nil, waiting == true, 0 end
	if window == "w" and Count.WindowFrom(window, page.asOf) ~= Count.WindowFrom(window, Church.Clock()) then
		return {}, nil, waiting == true, 0
	end
	return page.rows, page.from, waiting == true, page.ranked, page.asOf
end
