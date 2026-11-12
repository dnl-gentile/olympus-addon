-- 1.5.4: the King's presence where he is no guild master of a guild named Olympus (WoW: Forever).
-- The dev's report of 2026-11-08: "além da localização do Asmon não tá funcionando, também não tá
-- mostrando quando ele tá online". His client's census of 2026-11-07 had the signed King online as a
-- Captain of OLYMPUS PRIME (whose master is someone else); no guild named Olympus reports there.
-- Before: the Realm's King line read /who alone and said "offline today" for the whole army,
-- Hop.King (the layer line on the Census and the Realm, the API's leader presence) looked for the
-- master of a guild named Olympus and never found him, the King's client sent no word of presence,
-- and a relay handed his words to other guilds' reporters only within its trickle. Invented names
-- but the King's, whom the signed list names.
local ns, test, eq, h = ...
local L = ns.L
local KING = "Asmongold Thereal-CAMWOWUS2Realm1PvE"

local function WithForever(guild, fn)
	local saved = { realm = ns.realm, group = ns.group, me = ns.me, faction = ns.faction, split = ns.splitNames,
		pins = ns.SignedPins, guild = GetGuildInfo, guilds = ns.rdb.guilds, seen = ns.rdb.seen, global = ns.rdb.censusGlobal,
		now = ns.Now, online = ns.Roster.online, member = ns.IsMember, sweep = ns.Who.sweep }
	local clock = math.floor(saved.now()) -- (the harness's own time: Data's module state outlives the test)
	local ok, err = pcall(function()
		ns.realm, ns.group, ns.faction, ns.splitNames = "CAMWOWUS2Realm1PvE", "ForeverPvE", "Alliance", true
		ns.me = "Some Body-CAMWOWUS2Realm1PvE"
		ns.SignedPins = function() return { king = { Alliance = { KING } } } end
		GetGuildInfo = function() return guild, "Member", 3 end
		ns.IsMember = function() return true end
		ns.Now = function() return clock end
		ns.rdb.guilds, ns.rdb.censusGlobal, ns.rdb.seen = {}, {}, {}
		ns.Roster.online, ns.Who.sweep = {}, nil
		ns.Hop.Reset(); ns.King.Reset()
		fn(function(seconds) clock = clock + seconds end, function() return clock end)
	end)
	ns.realm, ns.group, ns.me, ns.faction, ns.splitNames = saved.realm, saved.group, saved.me, saved.faction, saved.split
	ns.SignedPins, GetGuildInfo, ns.Now, ns.IsMember = saved.pins, saved.guild, saved.now, saved.member
	ns.rdb.guilds, ns.rdb.seen, ns.rdb.censusGlobal = saved.guilds, saved.seen, saved.global
	ns.Roster.online, ns.Who.sweep = saved.online, saved.sweep
	ns.Hop.Reset(); ns.King.Reset()
	if not ok then error(err, 0) end
end

-- The King's guild's report as the live census had it: its master someone else, the King a Captain.
local function PrimeReport(t, online, days)
	return { total = 916, online = 337, t = t, st = t, leader = "Guild Master", leaderOnline = true, leaderDays = 0,
		realm = "CAMWOWUS2Realm1PvE", from = "CAMWOWUS2Realm1PvE", zones = {},
		officers = { { name = "Asmongold Thereal", online = online, days = days or 0, zone = "m1439", class = "WA", level = 23 },
			{ name = "Other Captain", online = true, days = 0, class = "RO", level = 24 } } }
end

local function KingLine()
	for _, l in ipairs(ns.Views.RealmLines()) do
		if (l.text or ""):find(L.KING .. ": ", 1, true) then return l end
	end
end

test("1.5.4 the King's presence on Forever: the signed King, a Captain of another Olympus guild, is online on the Realm's King line and in Hop.King (the layer line, the API's leader presence) as his guild's fresh report says; offline as it says; nothing claimed with nothing known", function()
	WithForever("Olympus Faraway", function(advance, now)
		-- (1.5.5, the dev: "fern is the gm of the main guild") OLYMPUS PRIME is the King's main guild on Forever's live
		-- realms (ns.KING_GUILD_FOREVER); its master is not the King (ns.KingIsMaster), so what follows holds as before.
		eq(ns.IsKingGuild("OLYMPUS PRIME"), true, "the King's main guild on Forever")
		-- His guild's fresh report: a Captain online (it said "offline today").
		ns.rdb.guilds["OLYMPUS PRIME"] = PrimeReport(now(), true)
		local line = KingLine()
		assert(line and line.text:find("Asmongold Thereal", 1, true), "the signed King's line")
		assert(line.right and line.right:find(L.ONLINE_NOW, 1, true), "online, as his guild's report says: " .. tostring(line.right))
		local k = ns.Hop.King()
		assert(k, "Hop.King names him")
		eq(k.name, "Asmon"); eq(k.zoneUID, nil, "his layer only from his own messages")
		eq(ns.Hop.KingOtherRealm(k), false)
		local top = ns.Hop.KingLines()
		assert(#top >= 1 and top[1].text:find("Asmon", 1, true) and top[1].onClick, "the layer line tops the Census and the Realm")
		eq(ns.Hop.King(true), nil, "a report alone never confirms him (strict: his own word)")
		-- The same report saying he is offline, two days.
		ns.rdb.guilds["OLYMPUS PRIME"] = PrimeReport(now(), false, 2)
		line = KingLine()
		assert(line.right and line.right:find(L.OFFLINE_DAYS:format(2), 1, true), tostring(line.right))
		eq(ns.Hop.King(), nil)
		-- An old report (past Data.FRESH) says nothing of now; nothing known, nothing claimed.
		ns.rdb.guilds["OLYMPUS PRIME"] = PrimeReport(now() - ns.Data.FRESH - 1, true)
		eq(KingLine().right, nil); eq(ns.Hop.King(), nil)
		ns.rdb.guilds = {}
		eq(KingLine().right, nil, "no report at all: no word"); eq(ns.Hop.King(), nil)
		-- A namesake's report from another realm group names nobody's King.
		local far = PrimeReport(now(), true)
		far.realm, far.from = "CAMWOWUS1Realm8PvP", "CAMWOWUS1Realm8PvP"
		ns.rdb.guilds["OLYMPUS PRIME"] = far
		eq(ns.Hop.King(), nil, "a report of another realm group")
	end)
end)

test("1.5.4 the King's presence on Forever: his own word (T1~o, or his global census snapshot) says he is online, strict too, for Hop.KING_HEARD_FRESH, then 'online <age> ago'; a namesake's or anyone else's says nothing", function()
	WithForever("Olympus Faraway", function(advance, now)
		ns.King.HandleCommand("CHANNEL", "Other Captain-CAMWOWUS2Realm1PvE", "T1~o~3~OLYMPUS PRIME")
		ns.King.HandleCommand("CHANNEL", "Asmongold Thereal-CAMWOWUS1Realm8PvP", "T1~o~4~OLYMPUS PRIME")
		eq(ns.Hop.King(), nil, "neither a Captain of his guild nor a namesake on another realm group")
		ns.King.HandleCommand("CHANNEL", "Asmongold Thereal-CAMWOWUS1Realm5PvE", "T1~o~5~OLYMPUS PRIME")
		local k = ns.Hop.King(true)
		assert(k, "his own word confirms him, from any sub-realm of his family")
		eq(k.realm, "CAMWOWUS1Realm5PvE", "his realm from his own word, as before")
		eq(ns.Hop.KingOtherRealm(k), false, "a sub-realm of his family is no other realm (the review of the 1.5.4 candidate)")
		assert(KingLine().right:find(L.ONLINE_NOW, 1, true))
		advance(ns.Hop.KING_HEARD_FRESH + 1)
		eq(ns.Hop.King(), nil, "his word lapsed, as after a logout")
		local right = KingLine().right
		assert(right and right:find(L.ONLINE_AGO:format(""), 1, true), "when he was heard: " .. tostring(right))
		-- His relay's global census snapshot is his word too (held by his quiet presence).
		local saved = { trusted = ns.Church.IsLedgerRelay }
		local ok, err = pcall(function()
			ns.Church.IsLedgerRelay = function(name) return ns.IsKingCharacter(ns.FullName(name)) end
			eq(ns.Data.ReceiveGlobalCensus("CHANNEL", KING, ("CG~2~S~%d~ForeverPvE~Alliance~OLYMPUS PRIME,916,337,230,%d"):format(now(), now())), true)
			assert(ns.Hop.King(true), "his snapshot: online")
		end)
		ns.Church.IsLedgerRelay = saved.trusted
		if not ok then error(err, 0) end
	end)
end)

-- The review of the 1.5.4 candidate. On Forever every word of his a member hears came through a relay,
-- whose client stamps a whisper's bare sender with ITS OWN sub-realm (Comm.OnAddonMessage, Relay.HandleIn):
-- "Asmongold Thereal-<the relay's sub-realm>" is what Hop.HeardKing keeps, whatever sub-realm he plays
-- on. Fails before: Hop.KingOtherRealm compared that stamp with ns.realm as a plain string, so for every
-- member whose own sub-realm was not the relay's the King played "on another realm" (the relay's): the
-- layer line's click said so and sent no LQ, /oly bug said "(another realm)", the Companion was told
-- otherRealm. And Hop.King looked his layer up by that exact stamp, while his layer word reached his
-- guildmates under their own (his guild's copy over GUILD): "layer not known" with his layer known.
test("1.5.4 the King on Forever: his word stamped with the relay's sub-realm places him on no other realm, and his layer heard under the reader's stamp is his under the relay's", function()
	WithForever("Olympus Faraway", function()
		local saved = { print = ns.Print, relay = ns.Relay, ready = ns.Comm.ChannelReady, map = ns.Layers.CurrentMap }
		local printed, asked = {}, {}
		ns.Layers.Reset()
		local ok, err = pcall(function()
			ns.Print = function(msg) printed[#printed + 1] = tostring(msg) end
			-- His layer word as his guild's copy reached a guildmate: under the reader's own sub-realm.
			ns.Layers.Receive("Asmongold Thereal-CAMWOWUS2Realm1PvE", { mapID = 1453, zoneUID = 9, rank = 1, guild = "OLYMPUS PRIME" })
			-- His presence as the relay on Realm3 handed it on, stamped with the relay's sub-realm.
			ns.King.HandleCommand("CHANNEL", "Asmongold Thereal-CAMWOWUS2Realm3PvE", "T1~o~5~OLYMPUS PRIME")
			local k = assert(ns.Hop.King(true), "his own word confirms him")
			eq(k.realm, "CAMWOWUS2Realm3PvE", "the stamp is what his realm reads (the relay's sub-realm)")
			eq(ns.Hop.KingOtherRealm(k), false, "a sub-realm of our own family is ours, not another realm")
			eq(k.zoneUID, 9, "his layer, heard under the reader's stamp, is his under the relay's"); eq(k.mapID, 1453)
			local status = ns.Hop.KingStatusLine()
			assert(status:find("realm CAMWOWUS2Realm3PvE (ours)", 1, true), status)
			assert(status:find("layer map 1453 zone 9", 1, true), status)
			local other = L.HOP_KING_OTHER_REALM:format(k.name, k.realm)
			assert(ns.Hop.KingUnknownText(k) ~= other, "why his layer can't be asked for: never 'another realm' for a stamp of our family")
			-- (1.5.4, the layer hop marked experimental) The first ask of a session opens the window that
			-- tells the flow (tests/hop-forever.lua covers it); as the other hop tests do, it was answered.
			local confirmed = ns.Hop.confirmed and { same = ns.Hop.confirmed.same, other = ns.Hop.confirmed.other }
			if ns.Hop.confirmed then ns.Hop.confirmed.same, ns.Hop.confirmed.other = true, true end
			-- Model a ready relay with its result still pending. Native CHANNEL does not
			-- deliver this request on Forever and unrelated tests can leave it joined.
			ns.Comm.ChannelReady = function() return true end
			ns.Layers.CurrentMap = function() return k.mapID end
			ns.Relay = { On = function() return true end, Out = function(parts)
				for _, part in ipairs(parts) do asked[#asked + 1] = part end
				return true
			end }
			ns.Hop.AskKing()
			if confirmed then ns.Hop.confirmed.same, ns.Hop.confirmed.other = confirmed.same, confirmed.other end
			eq(#asked, 1, "the click queues a request for the King's layer through the relay")
			eq(asked[1]:match("^LQ~%d+~(.*)$"), "1453~9")
			eq(#printed <= 1, true)
			assert(printed[1] ~= other, "the click never refuses the hop for the relay's sub-realm: " .. tostring(printed[1]))
			local top = ns.Hop.KingLines()
			assert(#top >= 1 and top[1].onClick, "the layer line tops the Census and the Realm")
			-- A stamp of another family is another realm still, and off Forever a realm is one server.
			eq(ns.Hop.KingOtherRealm({ name = k.name, realm = "CAMWOWUS1Realm8PvP" }), true, "a PvP family's stamp")
			ns.splitNames = false
			eq(ns.Hop.KingOtherRealm({ name = k.name, realm = "CAMWOWUS2Realm3PvE" }), true, "off Forever another realm is another realm")
			ns.splitNames = true
		end)
		ns.Print, ns.Relay, ns.Comm.ChannelReady, ns.Layers.CurrentMap = saved.print, saved.relay, saved.ready, saved.map
		ns.Layers.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("1.5.4 the King's presence on Forever: his guildmates see him online from their roster, unless his private presence told their guild", function()
	WithForever("OLYMPUS PRIME", function()
		ns.Roster.online = { { name = "Asmongold Thereal", level = 23, class = "WA", rank = "Captain", rankIndex = 1 } }
		assert(KingLine().right:find(L.ONLINE_NOW, 1, true), "our roster has him")
		assert(ns.Hop.King(), "and the layer line")
		-- (PrivatePresence.Offline: his PP~1 heard over our guild; its own tests cover that.)
		local savedModule = ns.PrivatePresence
		local P = savedModule or {}
		local saved = P.Offline
		local ok, err = pcall(function()
			ns.PrivatePresence = P
			P.Offline = function(name) return ns.IsKingCharacter(name) end
			eq(KingLine().right, nil, "his private presence: our roster says nothing of him")
			eq(ns.Hop.King(), nil)
		end)
		P.Offline, ns.PrivatePresence = saved, savedModule
		if not ok then error(err, 0) end
	end)
end)

test("1.5.4 the King's presence: his client says T1~o at login and every King.PRESENCE_EVERY, held by quiet presence; nobody else's says it", function()
	WithForever("OLYMPUS PRIME", function(advance)
		local sent = {}
		local saved = { send = ns.Comm.Send, quiet = ns.QuietPresence }
		local ok, err = pcall(function()
			ns.Comm.Send = function(dist, msg, key, urgent)
				sent[#sent + 1] = dist .. " " .. msg
				eq(key, "kingpresence"); eq(urgent, true, "ahead of a busy relay's own queue")
				return true
			end
			ns.QuietPresence = function() return false end
			eq(ns.King.SendPresence(true), false, "not the King: nothing")
			ns.me = KING
			eq(ns.King.IsKing(), true)
			eq(ns.King.SendPresence(true), true)
			assert(sent[1]:match("^CHANNEL T1~o~%d+~OLYMPUS PRIME$"), sent[1])
			eq(ns.King.SendPresence(), false, "not again yet")
			advance(ns.King.PRESENCE_EVERY)
			eq(ns.King.SendPresence(), true); eq(#sent, 2)
			advance(ns.King.PRESENCE_EVERY)
			ns.QuietPresence = function() return true end
			eq(ns.King.SendPresence(true), false, "quiet presence: none"); eq(#sent, 2)
			eq(ns.Comm.QuietHolds("T1~o~7~OLYMPUS PRIME"), true, "and the transport holds it too")
			eq(ns.Comm.QuietHolds("RM~P~" .. KING .. "~T1~o~7~OLYMPUS PRIME"), false, "a relay still carries his word")
			-- (Every capital letter is a T1 kind already: T1~O is the Arena's settings, ArenaRoles.lua,
			-- which quiet presence does not hold; its authority is King.Authorized's as before.)
			eq(ns.Comm.QuietHolds("T1~O~7~OLYMPUS PRIME~1800000000~1~g~600~200"), false, "the Arena's settings are no presence word")
			eq(ns.King.Authorized("o", "Asmongold Thereal-CAMWOWUS2Realm1PvE", "OLYMPUS PRIME"), true, "his presence, whatever his guild")
			eq(ns.King.Authorized("o", "Other Captain-CAMWOWUS2Realm1PvE", "OLYMPUS PRIME"), false, "his presence is his alone")
		end)
		ns.Comm.Send, ns.QuietPresence = saved.send, saved.quiet
		if not ok then error(err, 0) end
	end)
end)

if h.RelayWorld then
	test("1.5.4 the relay: the King's presence (T1~o) reaches every reporter past the trickle, ahead of the queue, one per reporter whatever comes again; others' T1~o and his crown stay within the trickle", function()
		local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
		local ok, err = pcall(function()
			GetChannelName = function() return 0 end
			ns.IsMember = function() return true end
			IsInGuild = function() return true end
			GetGuildInfo = function() return "Olympus II", "Member", 3 end
			local R, deliver, sent, _, pump, sentOf = h.RelayWorld("Hildryn Payne-Realm", "Olympus II")
			R.KingCharacter = function() return "Asmongold Thereal" end
			R.IsKingCharacter = function(name) return type(name) == "string" and R.ShortName(name) == "Asmongold Thereal" end
			deliver("WHISPER", "Max Ran-Realm", "RY~") -- (another relay that answered...)
			deliver("WHISPER", "Max Ran-Realm", "RJ~1~0~0") -- (...and joined the mesh, 1.5.5)
			for i = 1, 6 do deliver("WHISPER", ("Rep Orter%d-Realm"):format(i), "RL~P~RR~Olympus G" .. i) end
			-- This minute's trickle spent on other guilds' reports.
			for i = 1, 4 do deliver("WHISPER", ("Guild Rep%d-Realm"):format(i), "RL~P~C" .. i .. "~report " .. i) end
			pump(200)
			local before = #sent
			local king = "Asmongold Thereal-Realm"
			deliver("WHISPER", king, "RL~P~T1~o~5~OLYMPUS PRIME")
			deliver("WHISPER", "Some One-Realm", "RL~P~T1~o~6~OLYMPUS PRIME")
			deliver("WHISPER", king, "RL~P~T1~P~1~OLYMPUS PRIME~1453~420~510")
			-- What the queue holds now: the King's presence first, one job per reporter.
			local first = {}
			for _ = 1, 3 do R.Comm.Pump() end
			for i = before + 1, #sent do first[#first + 1] = sent[i].msg end
			for i = 1, math.min(6, #first) do
				assert(first[i]:find("~T1~o~5~", 1, true), "the King's presence ahead of the queue: " .. tostring(first[i]))
			end
			pump(200)
			local reached = {}
			for _, x in ipairs(sentOf("RM~P~" .. king .. "~T1~o~5~")) do reached[x.target] = (reached[x.target] or 0) + 1 end
			for i = 1, 6 do eq(reached["Rep Orter" .. i], 1, "reporter " .. i .. " has his presence once") end
			-- (1.5.5) Not across: the King's client whispers his presence to every relay itself
			-- (CrownToRelays), and only a closed set crosses (tests/relay-mesh.lua).
			eq(#sentOf("RX~P~" .. king .. "~T1~o~5~"), 0, "not across to the other relay")
			eq(#sentOf("RM~P~Some One-Realm~T1~o~"), 0, "anyone else's T1~o: within the trickle (spent)")
			-- (With the crown's own 1.5.4 path, tests/king-crown-relay.lua: past the trickle on the relay's
			-- crown bucket, so each reporter has it too; this test was written before that path.)
			eq(#sentOf("RM~P~" .. king .. "~T1~P~"), 6, "his crown: past the trickle on its own bucket")
			deliver("WHISPER", king, "RL~P~T1~O~2~OLYMPUS PRIME~1800000000~1~g~600~200")
			pump(200)
			-- (1.5.5) The King's own words but his crown and presence are staff words (Relay.CROSS_KINDS):
			-- from a signed relay's character, past the trickle at every relay (tests/relay-mesh.lua).
			eq(#sentOf("RM~P~" .. king .. "~T1~O~"), 6, "the Arena's settings (T1~O): to every reporter, a staff word")
			-- Twice before the queue drains: each reporter is sent the latest alone.
			deliver("WHISPER", king, "RL~P~T1~o~7~OLYMPUS PRIME")
			deliver("WHISPER", king, "RL~P~T1~o~8~OLYMPUS PRIME")
			pump(200)
			eq(#sentOf("RM~P~" .. king .. "~T1~o~7~"), 0, "the newer took its place")
			eq(#sentOf("RM~P~" .. king .. "~T1~o~8~"), 6, "one per reporter")
			-- From another relay (RX: the King picked that one), the same.
			deliver("WHISPER", "Max Ran-Realm", "RX~P~" .. king .. "~T1~o~9~OLYMPUS PRIME")
			pump(200)
			eq(#sentOf("RM~P~" .. king .. "~T1~o~9~"), 6, "every reporter, from another relay's copy")
			eq(#sentOf("RX~P~" .. king .. "~T1~o~9~"), 0, "never sent across again")
		end)
		GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
		C_ChatInfo = saved.chat -- (RelayWorld replaced it: the next test finds the one it had)
		if not ok then error(err, 0) end
	end)
end
