-- 1.6.4: retained /who contacts and open drafts must follow current local guild decisions.
-- J2 has no revocation proof. These tests deliver actual GV decisions from a known verifier;
-- unknown/pending guilds and clients with no such decision still use ordinary discovery.
local ns, test, eq = ...
local R, L = ns.Recruit, ns.L
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]recruit%-revoked%-destinations%.lua$")) or "./"
local TRUSTED = "Verified Councillor-Realm"
local OLD, GOOD = "Olympus Ash", "Olympus Brook"

local function Scene(fn)
	R.ResetForTests()
	local saved = {}
	local function Set(object, key, value)
		saved[#saved + 1] = { object, key, object[key] }
		object[key] = value
	end
	local w = { clock = 1800000000, said = {}, out = {}, shown = {}, jobs = {}, summary = { guilds = {} }, off = {} }
	Set(ns, "rdb", { guilds = {} })
	Set(ns, "db", {})
	Set(ns, "faction", "Alliance"); Set(ns, "group", "Realm"); Set(ns, "realm", "Realm")
	Set(ns, "GuildCharter", nil)
	Set(ns, "Now", function() return w.clock end)
	Set(ns, "Fire", function() end); Set(ns, "Print", function() end); Set(ns, "Log", function() end)
	Set(ns, "UI", { Refresh = function() end })
	Set(ns, "After", function(_, _, callback) w.jobs[#w.jobs + 1] = callback end)
	Set(ns, "IsHighCouncillor", function(name) return name == TRUSTED end)
	Set(ns, "REMOVED_BUILTIN", {})
	Set(ns.Moderation, "Guild", function(guild) return w.off[guild] end)
	Set(ns.Moderation, "Hidden", function() return nil end)
	Set(ns.Data, "ServerTime", function() return w.clock end)
	Set(ns.Data, "Summary", function() return w.summary end)
	Set(ns.Data, "Dispute", function() return nil end) -- the fixture's census rows are corroborated
	Set(ns.Who, "StatusLines", function() return {} end)
	Set(ns.Acts, "Gates", function() return w.gates end)
	Set(ns.Comm, "WhisperOutside", function(to, text) w.out[#w.out + 1] = { to = to, text = text }; return true end)
	Set(_G, "GetGuildInfo", function() return w.guild end)
	Set(_G, "IsInGuild", function() return w.guild ~= nil end)
	Set(_G, "GetTime", function() return w.clock end)
	Set(_G, "GetNumGuildMembers", function() return w.full and 1000 or 10 end)
	Set(_G, "UnitClass", function() return "Mage", "MAGE" end)
	Set(_G, "UnitLevel", function() return 12 end)
	Set(_G, "SendChatMessage", function(text, kind, _, to) w.said[#w.said + 1] = { text = text, kind = kind, to = to } end)
	Set(ns, "Dialog", {
		Show = function(which, _, _, data)
			local f = { which = which, data = data, open = true }; w.shown[#w.shown + 1] = f; return f
		end,
		Find = function(which, data)
			for _, f in ipairs(w.shown) do if f.open and f.which == which and (not data or data == f.data) then return f end end
		end,
		Hide = function(which, data)
			for _, f in ipairs(w.shown) do if f.which == which and (not data or data == f.data) then f.open = false end end
		end,
		CloseOnEscape = function() end,
	})
	-- Verify is not loaded into the main harness namespace here. Keep its listeners and
	-- popup declarations isolated, while it reads this scene's actual scoped state.
	Set(_G, "StaticPopupDialogs", {})
	local vns = setmetatable({ On = function() end, Comm = { Handle = function() end } }, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/Verify.lua"))("Olympus", vns)
	Set(ns, "Verify", vns.Verify)
	function w.Decide(guild, kind, sender)
		return ns.Verify.Handle("CHANNEL", sender or TRUSTED, ("GV~1~%s~%d~%s~Master-Realm"):format(kind or "R", w.clock, guild))
	end
	local ok, err = pcall(fn, w)
	R.ResetForTests()
	for i = #saved, 1, -1 do local s = saved[i]; s[1][s[2]] = s[3] end
	if not ok then error(err, 0) end
end
local function Member(name, guild) return { name = name .. "-Realm", guild = guild, class = "MAGE", level = 12 } end
local function Names(list)
	local names = {}; for _, e in ipairs(list) do names[#names + 1] = type(e) == "table" and e.name or e end
	return table.concat(names, ",")
end
local function Bare(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

test("recruit destinations: retained discovery follows trusted revocations, removals and net-off without excluding unknown guilds", function()
	Scene(function(w)
		local removed, hidden = "Olympus Cinder", "Olympus Dusk"
		R.found = { Member("Ash", OLD), Member("Brook", GOOD), Member("Cinder", removed), Member("Dusk", hidden) }
		eq(#R.Guilds(), 4)
		eq(w.Decide(OLD, "R", "Untrusted-Realm"), false, "a member's claim is not a verifier decision")
		eq(#R.Guilds(), 4)
		eq(w.Decide(OLD), true)
		local _, info = ns.Verify.Status(OLD); assert(info.revoked, "real Status exposes the retained revocation")
		ns.REMOVED_BUILTIN = { Alliance = { realm = "Realm", removed } }
		w.off[hidden] = { kind = "g", name = hidden }
		eq(Names(R.Guilds()), GOOD)
		eq(#R.found, 4, "original /who results are retained")
		eq(R.NextContact().guild, GOOD); eq(R.NextContact(OLD), nil); eq(R.NextContact(removed), nil)
		R.OnFound(R.found)
		eq(w.out[1].to, "Brook", "route discovery skips retained ineligible contacts")
		eq(ns.Verify.Status(GOOD) ~= nil, true, "a guild with no approval remains discoverable")
	end)
end)

test("recruit destinations: an open draft cannot send after revocation and a newer approval restores one-whisper clicks", function()
	Scene(function(w)
		local contact = Member("Ash", OLD)
		R.found = { contact, Member("Brook", GOOD) }
		assert(R.Prompt(contact)); eq(R.pending, contact)
		eq(w.Decide(OLD), true)
		eq(R.Prompt(contact), nil, "a cached row cannot reopen it")
		eq(R.Ask(contact, "May I join?"), false, "Send rechecks the already open draft")
		eq(#w.said, 0); eq(R.pending, nil)
		eq(R.NextContact().guild, GOOD)
		w.clock = w.clock + 1; eq(w.Decide(OLD, "A"), true)
		eq(R.Ask(contact, "My edited request"), true)
		eq(#w.said, 1); eq(w.said[1].text, "My edited request"); eq(w.said[1].kind, "WHISPER")
		eq(R.Ask(contact, "Again"), false); eq(#w.said, 1, "the original cooldown still applies")
		eq(w.out[#w.out].text, "J3~" .. OLD .. "~12~MAGE")
	end)
end)

test("recruit destinations: cached gates, route ordering and late replies follow current destination and reporter eligibility", function()
	Scene(function(w)
		local ash, first, second = Member("Ash", OLD), Member("Brook", GOOD), Member("Creek", GOOD)
		R.OnFound({ first, second, ash })
		local answer = "J2~y~" .. OLD .. "~600~" .. OLD .. "=900=Ash;" .. GOOD .. "=500=Brook"
		eq(R.OnRoute(first.name, answer), true); eq(R.OnRoute(second.name, answer), true)
		eq(R.Route().gates, OLD); eq(R.RouteOrder(R.Route())[1], OLD)
		eq(w.Decide(OLD), true)
		local route = R.Route()
		eq(route.gates, nil); eq(route.byName[OLD], nil); eq(Names(R.RouteOrder(route)), GOOD)
		eq(R.OnRoute(first.name, answer), true); eq(R.Route().byName[OLD], nil, "a late J2 cannot restore it")
		local parsed = assert(R.ParseRoute(answer)); eq(parsed.gates, nil); eq(parsed.byName[OLD], nil)
		w.clock = w.clock + 1; eq(w.Decide(OLD, "A"), true)
		eq(R.OnRoute(first.name, answer), true); eq(R.OnRoute(second.name, answer), true)
		eq(R.Route().gates, OLD, "eligible destinations can be advertised again")
		local held = R.Route()
		eq(w.Decide(GOOD), true)
		eq(R.OnRoute(first.name, answer), false, "a formerly eligible reporter cannot update routing")
		eq(R.Route(), nil, "its retained route cannot keep ordering contacts")
		eq(#R.RouteOrder(held), 0, "a previously retained route object gets the same check")
		R.found = { ash }
		eq(R.OnRoute(first.name, answer), false, "a later /who omitting the reporter cannot forget its revoked guild")
	end)
end)

test("recruit destinations: routing advertisements omit revoked and removed guilds including a full own guild", function()
	Scene(function(w)
		local removed = "Olympus Cinder"
		for _, guild in ipairs({ OLD, GOOD, removed }) do
			w.summary.guilds[#w.summary.guilds + 1] = { name = guild, fresh = true, g = { total = 10, officers = {} } }
		end
		eq(w.Decide(OLD), true)
		ns.REMOVED_BUILTIN = { Alliance = { realm = "Realm", removed } }
		w.gates = { guild = OLD, at = w.clock + 600 }
		eq(Names(R.OpenGuilds()), GOOD)
		local answer = R.RouteAnswer()
		eq(answer:find(OLD, 1, true), nil); eq(answer:find(removed, 1, true), nil)
		assert(answer:find(GOOD, 1, true), "pending/unknown eligible destinations are still advertised")
		w.guild, w.full = OLD, true
		eq(R.RouteAnswer():find(OLD, 1, true), nil, "the own-guild full marker cannot reinsert a revoked destination")
	end)
end)

test("recruit destinations: the same guild spelling on another faction or realm group has independent decisions", function()
	Scene(function(w)
		R.found = { Member("Ash", OLD) }
		eq(w.Decide(OLD), true); eq(#R.Guilds(), 0)
		local alliance = ns.rdb
		ns.faction, ns.rdb = "Horde", { guilds = {} }
		eq(#R.Guilds(), 1, "the Alliance's retained verification cannot revoke a Horde namesake")
		ns.faction, ns.group, ns.realm, ns.rdb = "Alliance", "OtherRealm", "OtherRealm", { guilds = {} }
		eq(#R.Guilds(), 1, "nor a namesake in another realm group")
		ns.group, ns.realm, ns.rdb = "Realm", "Realm", alliance
		eq(#R.Guilds(), 0, "returning to its store restores the local decision")
	end)
end)

test("recruit destinations: a large guild leaves the next guild visible while all discovered contacts remain selectable", function()
	Scene(function(w)
		for i = 1, 120 do R.found[#R.found + 1] = Member("Ash" .. i, OLD) end
		R.found[#R.found + 1] = Member("Brook", GOOD)
		local lines, second = ns.Views.RecruitLines(), nil
		for _, line in ipairs(lines) do if Bare(line.text) == "<" .. GOOD .. ">" then second = line end end
		assert(second and second.onClick, "the second guild retains its request action")
		eq(#lines, 13, "title, two guild headers, nine member rows and one remaining-count row (previously 124)")
		assert(Bare(lines[2].right):find(L.RECRUIT_ONLINE:format(120), 1, true), "the true online count is preserved")
		eq(Bare(lines[11].text), L.AND_MORE:format(112))
		eq(#R.found, 121); eq(#R.Guilds()[1].members, 120)
		for i = 1, 119 do R.asked[R.found[i].name] = w.clock end
		eq(R.NextContact(OLD).name, "Ash120-Realm", "the guild action still considers contacts beyond the eight displayed")
		second.onClick(); eq(assert(ns.Dialog.Find("OLYMPUS_RECRUIT")).data.guild, GOOD)
	end)
end)
