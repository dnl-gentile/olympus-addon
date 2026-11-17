local ns, test, eq = ...
local P, D, T = ns.FederationProgram, ns.Dues, ns.Treasury

local AT = 1795000000
local REALM, GROUP, SIDE = "CAMWOWUS1Realm2PvE", "ForeverPvE", "Alliance"
local PRIME, GUILD = "Olympus Prime", "Olympus Azure"
local PIN = "Silver Rock-" .. REALM
local PROGRAM = "^program^Alliance^US^enforce^1794999998^1795000010^Olympus Azure=" .. PIN .. ",Amber Vale-" .. REALM .. ",1"
local POLICY = "^contributions^Alliance^US^enforce^1794999998^1795000010^-"

local function World(run)
	local old = { ns.rdb, ns.db, ns.realm, ns.group, ns.faction, ns.IsMember, ns.TreasurerRealm, ns.IsTreasurer, T.IsKeeper,
		ns.Data.ServerTime, ns.Sign.Verify, GetGuildInfo, IsInGuild, CanGuildRemove, D.TreasurerOnline, ns.Comm.Whisper, ns.splitNames }
	local guild, time = GUILD, AT
	ns.rdb, ns.db, ns.realm, ns.group, ns.faction, ns.splitNames = {}, {}, REALM, GROUP, SIDE, true
	ns.IsMember = function() return true end
	ns.TreasurerRealm = function() return REALM end
	ns.IsTreasurer, T.IsKeeper = function() return false end, function() return false end
	ns.Data.ServerTime = function() return time end
	GetGuildInfo, IsInGuild, CanGuildRemove = function() return guild end, function() return true end, function() return true end
	D.TreasurerOnline = function() return true, PIN end
	local signed = {}
	ns.Sign.Verify = function(text, sig) return signed[text] == sig end
	local function Install(offset, body, good)
		local text = ("HT1~%d~%s~0~%s"):format(AT + offset, GROUP, body)
		local sig = string.rep("d", 512)
		if good ~= false then signed[text] = sig end
		P.RememberPolicy()
		ns.rdb.councilTitles = { blob = text .. "~" .. sig }
		P.RememberPolicy()
	end
	local ok, err = pcall(run, Install, function(name) guild = name end, function(now) time = now end)
	ns.rdb, ns.db, ns.realm, ns.group, ns.faction, ns.IsMember, ns.TreasurerRealm, ns.IsTreasurer, T.IsKeeper,
		ns.Data.ServerTime, ns.Sign.Verify, GetGuildInfo, IsInGuild, CanGuildRemove, D.TreasurerOnline, ns.Comm.Whisper, ns.splitNames = unpack(old, 1, 17)
	if not ok then error(err, 0) end
end

local function RealmPage()
	for _, page in ipairs(ns.RealmPages) do if page.key == "contributions" then return page end end
end

test("federation contributions: Phase 1 and forged or outside-region Phase 2 cannot switch dues", function()
	World(function(Install)
		Install(1, PROGRAM)
		eq(P.IsEnrolled(GUILD), true)
		eq(P.ContributionsPolicy(), false)
		eq(D.Pays(), true, "phase 1 enrolment alone preserves the legacy behavior")
		eq(RealmPage().Link(), nil)
		Install(2, PROGRAM .. ";" .. POLICY, false)
		eq(D.Pays(), true, "a forged activation fails")
		Install(3, PROGRAM .. ";" .. POLICY:gsub("%^US%^", "^EU^"))
		eq(D.Pays(), true, "a signed policy from another region cannot switch dues")
		Install(4, PROGRAM .. ";" .. POLICY)
		eq(D.Pays(), false)
	end)
end)

test("federation contributions: enrolled guild sees voluntary CTA, Prime alone retains native dues", function()
	World(function(Install, Guild)
		Install(1, PROGRAM .. ";" .. POLICY)
		eq(D.Pays(), false)
		eq(D.CanRemove(), false)
		eq(D.SendDues(), false)
		eq(D.PayerReminder("mail"), false)
		eq(D.ContributionGuild(), GUILD)
		local page = RealmPage()
		assert(page.Link().text:find(ns.L.CONTRIBUTIONS_TITLE, 1, true))
		eq(page.Lines()[2].right, GUILD)
		local rows = {}; D.SummaryLines(rows); eq(#rows, 0)
		Guild(GUILD .. " Two")
		eq(D.Pays(), false, "non-Prime guilds may not inherit Prime's mandate")
		eq(page.Link(), nil, "an unlisted guild cannot show the voluntary program")
		Guild(PRIME)
		eq(D.Pays(), true)
		eq(D.CanRemove(), true, "existing native permission remains required")
		eq(page.Link(), nil)
		local prime = {}; D.SummaryLines(prime); assert(#prime > 0)
		Guild("Olympus Prime Two")
		eq(D.Pays(), false, "a similar guild name cannot inherit the mandate")
	end)
end)

test("federation contributions: a previously queued network ask is barred by activation", function()
	World(function(Install, Guild)
		local sent = {}
		ns.Comm.Whisper = function(_, _, _, _, _, _, data) sent[#sent + 1] = data.guard end
		Install(1, PROGRAM)
		assert(D.Ask(GUILD, true))
		eq(sent[1](), true)
		Install(2, PROGRAM .. ";" .. POLICY)
		eq(sent[1](), false, "queued traffic must recheck the policy at actual send")
		eq(D.Ask(GUILD, true), false)
		Guild(PRIME)
		eq(D.Ask(GUILD, true), false, "Prime clients must not query voluntary guilds")
		eq(D.Ask("*", true), false, "legacy all-guild requests are disabled in the phase")
		assert(D.Ask(PRIME, true))
		eq(sent[2](), true)
	end)
end)

test("federation contributions: expiry and omission cannot make non-Prime dues mandatory again", function()
	World(function(Install, _, Clock)
		Install(1, PROGRAM .. ";" .. POLICY)
		eq(D.ContributionGuild(), GUILD)
		Clock(AT + 10)
		eq(D.ContributionGuild(), nil, "no CTA after expiry")
		eq(D.Pays(), false, "expiry cannot restore a weekly payment")
		Clock(AT + 1)
		Install(2, PROGRAM)
		eq(D.ContributionGuild(), nil, "no CTA if the new signed list omits phase 2")
		eq(D.Pays(), false, "omission cannot restore a weekly payment")
		local off = POLICY:gsub("%^enforce%^", "^off^")
		Install(0, PROGRAM .. ";" .. off)
		eq(D.Pays(), false, "a stale signed off cannot override")
		Install(3, PROGRAM .. ";" .. off)
		eq(D.Pays(), true, "a newer signed off returns to legacy behavior")
	end)
end)
