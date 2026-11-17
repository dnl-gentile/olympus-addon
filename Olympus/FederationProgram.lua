local _, ns = ...

-- Guild program enrollment, separate from the player's Accord and the guild's ordinary verification.
-- Only the author-signed HT1 extension can name a guild, its native GM and its designated operator.
-- An explicit signed rollout stays active after expiry or omission from a newer titles list.
-- Lists without a current grant then allow no guild. A newer signed "off" entry ends the rollout.
local Program, L = {}, ns.L
ns.FederationProgram = Program

local MAX_BLOB, MAX_GUILDS = 3000, 20
local MIN_TIME, MAX_LIFETIME = 1577836800, 31 * 86400
local enrollment = { field = "federationProgramPolicies", key = "program", current = {}, retained = {} }
local contributions = { field = "federationContributionPolicies", key = "contributions", current = {}, retained = {} }

local function Region(realm)
	return type(realm) == "string" and realm:match("^CAMWOW(%u%u)%d+Realm%d+%a+$") or "-"
end

local function Scope()
	local group, faction, region = ns.group, ns.faction, Region(ns.realm)
	if type(group) ~= "string" or group == "" or (faction ~= "Alliance" and faction ~= "Horde") then return end
	return group, faction, region, group .. "^" .. faction .. "^" .. region
end

local function Character(name, group, region)
	local short, realm = name:match("^([%a\128-\255 ]+)%-([%w\128-\255']+)$")
	if not realm or #short > 48 or #realm > 40 or not short:match("^[^ ]+ ?[^ ]*$")
		or not ns.InGroup(realm) or Region(realm) ~= region then return nil end
	local family = ns.ForeverFamily(realm)
	if family and family ~= group then return nil end
	return ns.Fold(name)
end

local function Entries(body, group, region)
	local out, people, count = {}, {}, 0
	if body == "-" then return out end
	if body == "" or body:find("^!") or body:find("!$") or body:find("!!", 1, true) then return nil end
	for item in body:gmatch("[^!]+") do
		local guild, caretaker, official, primary = item:match("^([^=]+)=([^,]+),([^,]+),1(p?)$")
		if not guild or #guild > 72 or not guild:match("^[%a\128-\255][%a\128-\255 ]*$")
			or guild:find(" $") or select(2, guild:gsub("[^\128-\191]", "")) > 24 then return nil end
		local key = ns.Fold(guild)
		local owner, gm = Character(caretaker, group, region), Character(official, group, region)
		count = count + 1
		if count > MAX_GUILDS or out[key] or not owner or not gm or owner == gm or people[owner] or people[gm] then return nil end
		people[owner], people[gm] = true, true
		out[key] = { guild = guild, caretaker = caretaker, official = official, primary = primary == "p" }
	end
	return out
end

local function Read(blob, group, faction, region, kind)
	if type(blob) ~= "string" or #blob > MAX_BLOB or (kind == contributions and region == "-") then return nil end
	local text, revision, signedGroup, body, sig = blob:match("^(HT1~(%d+)~([^~]+)~[01]~([^~]*))~(%x+)$")
	revision = tonumber(revision)
	if signedGroup ~= group or not revision or revision < MIN_TIME or revision > 9999999999 then return nil end
	local policy
	for entry in body:gmatch("[^;]+") do
		local side, place, mode, start, finish, rows = entry:match("^%^" .. kind.key .. "%^([^%^]+)%^([^%^]+)%^([^%^]+)%^(%d+)%^(%d+)%^([^%^]*)$")
		if side == faction and place == region then
			start, finish = tonumber(start), tonumber(finish)
			if policy or (mode ~= "enforce" and mode ~= "off") or ((mode == "off" or kind == contributions) and rows ~= "-")
				or not start or not finish or start < MIN_TIME or finish <= start or finish - start > MAX_LIFETIME then return nil end
			policy = { revision = revision, mode = mode, start = start, finish = finish, guilds = Entries(rows, group, region) }
		end
	end
	if policy and ns.Sign and ns.Sign.Verify(text, sig) then return policy end
end

local function Cached(slot, blob, group, faction, region, scope, kind)
	if slot.blob ~= blob or slot.scope ~= scope then
		slot.blob, slot.scope = blob, scope
		slot.policy = Read(blob, group, faction, region, kind)
	end
	return slot.policy
end

local function Clock()
	local view = ns.Data and ns.Data.ServerTime and ns.Data.ServerTime()
	return view or ns.Now()
end

local function State(kind, at)
	local group, faction, region, scope = Scope()
	local db = ns.rdb
	if not scope or type(db) ~= "table" then return nil end
	local titles = db.councilTitles
	local blob = type(titles) == "table" and titles.blob or nil
	local current, retained, policies = kind.current, kind.retained, db[kind.field]
	local last = Cached(retained, type(policies) == "table" and policies[scope], group, faction, region, scope, kind)
	local policy = Cached(current, blob, group, faction, region, scope, kind)
	local now = Clock()
	-- Use the actual clock for saved activation. An optional time filters a grant, never promotes one.
	if policy and policy.start <= now and (not last or last.revision < policy.revision) then
		if type(policies) ~= "table" then policies = {}; db[kind.field] = policies end
		policies[scope] = blob
		retained.blob, retained.scope, retained.policy, last = blob, scope, policy, policy
	end
	if not last or last.mode ~= "enforce" then return false, nil end
	at = type(at) == "number" and at or now
	if not policy or blob ~= retained.blob or policy.mode ~= "enforce"
		or not policy.guilds or now >= policy.finish or not (policy.start <= at and at < policy.finish) then return true, nil end
	return true, policy.guilds, policy.revision
end

-- Workshop calls this on each side of replacing a signed titles list, including on first receipt.
function Program.RememberPolicy()
	State(enrollment)
	State(contributions)
end

function Program.Active()
	return State(enrollment) == true
end

-- Returns rollout-active, followed by whether the current signed policy enables new contributions.
-- Expiry or omission suspends the CTA but cannot silently restore mandatory dues outside Prime.
function Program.ContributionsPolicy()
	local active, grant = State(contributions)
	return active == true, grant ~= nil
end

local function Enrollment(guild, at)
	if type(guild) ~= "string" or ns.Secret(nil, guild) or guild == "" then return nil end
	local _, guilds = State(enrollment, at)
	if not guilds then return nil end
	if ns.IsRemovedGuild(guild) then return nil end
	return guilds[ns.Fold(guild)]
end

function Program.IsEnrolled(guild, at)
	return Enrollment(guild, at) ~= nil
end

function Program.Caretakers()
	local out = {}
	local _, guilds = State(enrollment)
	for _, record in pairs(guilds or {}) do
		if not ns.IsRemovedGuild(record.guild) then out[record.guild] = record.caretaker end
	end
	return out
end

function Program.Roleholders(guild)
	local record = Enrollment(guild)
	if record then return record.caretaker, record.official end
end

function Program.PrimaryGuilds()
	local out = {}
	local _, guilds = State(enrollment)
	for _, record in pairs(guilds or {}) do
		if record.primary then out[record.guild] = true end
	end
	return out
end

function Program.EnrollmentRevision()
	local _, _, revision = State(enrollment)
	return revision
end

-- Exact signed game identities; these roles confer no native permissions.
function Program.Role(name, guild, at)
	if type(name) ~= "string" or ns.Secret(nil, name) then return nil end
	local enrolled = Enrollment(guild, at)
	if not enrolled then return nil end
	local key = ns.Fold(name)
	if key == ns.Fold(enrolled.caretaker) then return "caretaker" end
	if key == ns.Fold(enrolled.official) then return "official" end
end

-- Our roster is stronger evidence for our own guild. Incomplete, stale or contradictory native
-- ranks deny local access even when another guild still holds its signed program record.
local function LocalEnrollment(at)
	local r = ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh()
	local enrolled = r and Enrollment(r.guild, at)
	if enrolled and ns.Roster.RankOf(enrolled.caretaker) == 0 and ns.Roster.RankOf(enrolled.official) == 1 then
		return r.guild, enrolled
	end
end


function Program.LocalEnrollment(at)
	local guild = LocalEnrollment(at)
	return guild
end

function Program.ShowCaretaker()
	local _, enrolled = LocalEnrollment()
	ns.Print(enrolled and L.FEDERATION_CARETAKER:format(enrolled.caretaker) or L.FEDERATION_CARETAKER_UNAVAILABLE)
end
