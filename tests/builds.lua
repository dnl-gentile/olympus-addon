-- 1.5.4: modified builds (Builds.lua; the owner's call, 2026-11-08). A peer whose announced version
-- is no release form is marked, recorded, shared among the guild masters, the officers and the High
-- Council, shown (/oly builds, the right-click menu) and locked out (Comm's door, the relay, the
-- arena: its own test is tests/arena/builds-gate.lua). Every name here is invented. Loaded by
-- tests/run.lua with the relay's world (RelayWorld) and the addon's folder.
local ns, test, eq, extra = ...
local L = ns.L
local B, V = ns.Builds, ns.Versions
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"

local function ReadFile(path)
	local f = assert(io.open(path, "rb"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- fn(w) as `me` (opts.rank: our guild rank, 0 a guild master, 1 an officer, else a member): a fixed
-- clock, the sends and whispers recorded (a whisper's done told it left), the version checks' timers
-- in w.timers (w.Run()), a fixed check id, guild hellos as Comm.PeerVersion would give them
-- (w.hellos[short] = version), who is online (w.online), the ranks the roster and the census give
-- (w.ranks[full]), the copy windows opened (w.copies), the relay's registrations dropped
-- (w.dropped), the relay running (w.relayOn) and its relays (w.relays[short] = true); a record of its
-- own, nothing kept across tests.
local function WithBuilds(me, fn, opts)
	opts = opts or {}
	local saved = { me = ns.me, now = ns.Now, send = ns.Comm.Send, whisper = ns.Comm.Whisper, peer = ns.Comm.PeerVersion,
		peers = ns.Comm.Peers, print = ns.Print, after = V.after, random = V.random, ui = ns.UI, builds = ns.db.builds,
		blocked = ns.db.blocked, council = ns.rdb.council, roster = ns.Roster, guild = GetGuildInfo, inGuild = IsInGuild,
		friends = C_FriendList, authorized = ns.Data.AuthorizedRank, relay = rawget(ns, "Relay"), member = ns.IsMember, log = ns.Log }
	local w = { clock = 1800000000, sent = {}, whispered = {}, timers = {}, printed = {}, copies = {}, hellos = {}, online = {}, ranks = {}, dropped = {}, quieted = {} }
	local ok, err = pcall(function()
		B.Reset(); V.Reset()
		ns.me = me
		ns.db.builds, ns.db.blocked, ns.rdb.council = {}, {}, nil
		ns.Now = function() return w.clock end
		ns.Log = function() end
		ns.IsMember = function() return true end
		ns.Comm.Send = function(dist, msg, key) w.sent[#w.sent + 1] = { dist = dist, msg = msg, key = key } return true end
		ns.Comm.Whisper = function(to, msg, key, urgent, logged, done)
			w.whispered[#w.whispered + 1] = { to = to, msg = msg, key = key }
			if done then done(true) end
			return true
		end
		ns.Comm.PeerVersion = function(name)
			local v = w.hellos[ns.ShortName(ns.FullName(ns.Normal(name)))]
			if v then return v, w.clock - (w.helloAge or 0) end
		end
		ns.Comm.Peers = function() local out = {} for _, n in ipairs(w.online) do out[#out + 1] = n end return out end
		ns.Print = function(m) w.printed[#w.printed + 1] = m end
		V.after = function(_, _, f) w.timers[#w.timers + 1] = f end
		V.random = function(a) if a then return 4242 end return 0.5 end
		w.Run = function() local due = w.timers; w.timers = {}; for _, f in ipairs(due) do f() end end
		ns.UI = { ShowCopy = function(title, text, action, o) w.copies[#w.copies + 1] = { title = title, text = text, opts = o } end }
		GetGuildInfo = function() return "Olympus II", opts.rank == 0 and "Zeus" or "Member", opts.rank or 3 end
		IsInGuild = function() return true end
		C_FriendList = nil
		ns.Roster = setmetatable({ RankOf = function(name) return w.ranks[ns.FullName(ns.Normal(name))] end }, { __index = saved.roster })
		ns.Data.AuthorizedRank = function(name, guild)
			local r = w.ranks[ns.FullName(ns.Normal(name))]
			if r and guild ~= "" then return r, "census" end
		end
		-- (The relay as this client sees it: running when w.relayOn, its relays the short names in w.relays.)
		rawset(ns, "Relay", setmetatable({ DropReporter = function(name) w.dropped[#w.dropped + 1] = name return 0 end,
			On = function() return w.relayOn == true end,
			IsRelay = function(name) return w.relays ~= nil and w.relays[ns.ShortName(ns.FullName(ns.Normal(tostring(name))))] == true end,
			Quiet = function(name) w.quieted[#w.quieted + 1] = name end }, { __index = saved.relay or {} }))
		fn(w)
	end)
	ns.me, ns.Now, ns.Comm.Send, ns.Comm.Whisper, ns.Comm.PeerVersion, ns.Comm.Peers = saved.me, saved.now, saved.send, saved.whisper, saved.peer, saved.peers
	ns.Print, V.after, V.random, ns.UI, ns.db.builds, ns.db.blocked, ns.rdb.council = saved.print, saved.after, saved.random, saved.ui, saved.builds, saved.blocked, saved.council
	ns.Roster, GetGuildInfo, IsInGuild, C_FriendList, ns.Data.AuthorizedRank, ns.IsMember, ns.Log = saved.roster, saved.guild, saved.inGuild, saved.friends, saved.authorized, saved.member, saved.log
	rawset(ns, "Relay", saved.relay)
	B.Reset(); V.Reset()
	if not ok then error(err, 0) end
end

-- A menu that records its lines: Versions.MenuLines's `menu`.
local function Menu()
	local m = { items = {} }
	function m.Line(text) m.items[#m.items + 1] = { kind = "title", text = text } end
	function m.Button(text, fn, label, tip, enabled) m.items[#m.items + 1] = { kind = "button", text = text, tip = tip, enabled = enabled } end
	function m.Texts()
		local out = {}
		for _, d in ipairs(m.items) do out[#out + 1] = d.kind .. ":" .. tostring(d.text) end
		return table.concat(out, " | ")
	end
	function m.Find(text)
		for _, d in ipairs(m.items) do if d.text == text then return d end end
	end
	return m
end

local function Word(name, version, how, first, last, guild, their)
	return ("BD~1~%s~%s~%s~%s~%d~%d~%s"):format(guild or "Olympus Dawn", name, version, how or "h", first or 1800000000, last or 1800000000, their or "")
end

print("tests/builds.lua")

test("1.5.4 modified builds version: a release form (x.y.z, x.y.z.w) and the author's test build pass; a hello or a Check version answer naming anything else marks a modified build and locks it; a release heard later clears the lock and the sighting stays", function()
	for _, v in ipairs({ "1.5.4", "1.5.3", "0.9.10", "1.2.5.1", "1.5.4-test.3", "10.20.30.40" }) do eq(B.Release(v), true, v) end
	for _, v in ipairs({ "1.5.1-onn.12", "1.5.3-custom", "", "?", "abc", "1.5", "1.5.4-test", "1.5.4-test.x", "1.5.4.", "v1.5.4", "1.5.1-onn.12 " }) do eq(B.Release(v), false, v) end
	eq(B.Release(nil), false); eq(B.Release(154), false)
	WithBuilds("Tester-Realm", function(w)
		-- The hello, as Comm hands it over.
		B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock)
		eq(B.Quarantined("Ann Dark-Realm"), true, "a version that is no release: locked")
		eq(B.Quarantined("Ann Dark"), true, "by the short name too, as the menu gives it")
		eq(B.Quarantined("anN DARK-Realm"), true, "whatever the case")
		eq(B.Passes("H1~1.5.4~Realm~p"), true, "its hello still passes (it may clear the lock)")
		eq(B.Passes("V8~12~1.5.4"), true, "and its version answer")
		eq(B.Passes("X1~x"), false); eq(B.Passes("RL~P~RR~Guild"), false); eq(B.Passes("M1~a line"), false)
		eq(#w.dropped, 1); eq(w.dropped[1], "Ann Dark-Realm", "the relay drops a registration it holds from it")
		local e = B.Modified("Ann Dark-Realm")
		eq(e.version, "1.5.1-onn.12"); eq(e.how, "hello"); eq(e.first, w.clock); eq(e.last, w.clock); eq(e.by, nil)
		-- A release, the author's test build, or a plain version: never.
		B.Hello("Bob Light-Realm", "1.5.4", w.clock)
		B.Hello("Cid Grey-Realm", "1.5.4-test.3", w.clock)
		B.Hello("Dee Blue-Realm", "1.2.5.1", w.clock)
		for _, n in ipairs({ "Bob Light-Realm", "Cid Grey-Realm", "Dee Blue-Realm" }) do eq(B.Quarantined(n), false, n) end
		eq(B.Count(), 1, "no sighting of a release")
		-- An empty or a non-numeric version where the field is there: modified.
		B.Hello("Eve Red-Realm", "", w.clock)
		B.Hello("Fay Gold-Realm", "custom", w.clock)
		eq(B.Quarantined("Eve Red-Realm"), true); eq(B.Modified("Eve Red-Realm").version, "?", "an empty version is shown as ?")
		eq(B.Quarantined("Fay Gold-Realm"), true)
		-- A long or dirty version string is kept clean and cut.
		B.Hello("Gus Pale-Realm", ("1.5.1-" .. ("x"):rep(60)) .. "|cffff0000", w.clock)
		eq(#B.Modified("Gus Pale-Realm").version, B.VERSION_MAX); assert(not B.Modified("Gus Pale-Realm").version:find("|", 1, true))
		-- The answer to our Check version: the same mark, "check" as where from, and one line in chat.
		eq(V.Check("Hal Brown-Realm"), true)
		V.HandleAnswer("WHISPER", "Hal Brown-Realm", "V8~4242~1.5.3-custom")
		local state, version, how = V.Status("Hal Brown")
		eq(state, "modified"); eq(version, "1.5.3-custom"); eq(how, "check")
		eq(B.Quarantined("Hal Brown-Realm"), true)
		-- (Changed on purpose, the owner's call: the release it was made from, never the rest of its version.)
		eq(w.printed[#w.printed], "Hal Brown: " .. L.VERSION_LINE_MODIFIED:format("1.5.3"))
		eq(B.Modified("Hal Brown-Realm").how, "answer")
		-- Nothing of a check is read without the matching id, or from the channel.
		eq(V.Check("Ida Green-Realm"), true)
		V.HandleAnswer("WHISPER", "Ida Green-Realm", "V8~1~1.5.1-onn.12")
		V.HandleAnswer("CHANNEL", "Ida Green-Realm", "V8~4242~1.5.1-onn.12")
		eq(B.Quarantined("Ida Green-Realm"), false, "a stranger's word about a check never marks")
		-- The lock is reversible: a release announced clears it, the sighting stays with the release noted.
		w.clock = w.clock + 600
		B.Hello("Ann Dark-Realm", ns.VERSION, w.clock)
		eq(B.Quarantined("Ann Dark-Realm"), false, "a release clears the lock")
		local kept = B.Modified("Ann Dark-Realm")
		eq(kept.version, "1.5.1-onn.12", "the sighting stays"); eq(kept.locked, false); eq(kept.release, ns.VERSION); eq(kept.releaseAt, w.clock)
		w.hellos["Ann Dark"] = ns.VERSION
		eq((V.Status("Ann Dark-Realm")), "current", "the menu follows the hello again")
		-- Seen again on a modified build: locked again.
		B.Hello("Ann Dark-Realm", "1.5.1-onn.13", w.clock)
		eq(B.Quarantined("Ann Dark-Realm"), true); eq(B.Modified("Ann Dark-Realm").version, "1.5.1-onn.13"); eq(B.Modified("Ann Dark-Realm").release, nil)
		-- Our own client, whatever it is told about itself: never.
		B.Hello("Tester-Realm", "1.5.1-onn.12", w.clock)
		B.Answer("Tester-Realm", "1.5.1-onn.12")
		eq(B.Quarantined("Tester-Realm"), false, "never our own client"); eq(B.Modified("Tester-Realm"), nil)
	end)
end)

test("1.5.4 modified builds version: the silent mark needs three unanswered version checks over five minutes with a hello of theirs between each, never one check, never without the hellos, never from a version older than 1.1.2; an answer clears it; it is never a lock", function()
	WithBuilds("Tester-Realm", function(w)
		local t0 = w.clock
		w.hellos["Ann Dark"] = "1.5.3"
		B.Hello("Ann Dark-Realm", "1.5.3", w.clock)
		-- One check, no answer: nothing.
		eq(V.Check("Ann Dark-Realm"), true); w.Run()
		eq((V.Status("Ann Dark")), "outdated", "the hello's version stands: 1.5.3 behind ours"); eq(B.Silent("Ann Dark-Realm"), nil, "one check never marks")
		-- A hello between, a second check two minutes later: still nothing.
		w.clock = t0 + 60; B.Hello("Ann Dark-Realm", "1.5.3", w.clock)
		w.clock = t0 + V.PING_GAP; eq(V.Check("Ann Dark-Realm"), true); w.Run()
		eq(B.Silent("Ann Dark-Realm"), nil, "two checks never mark")
		-- A third without a hello since the second: the count starts again from it.
		w.clock = t0 + 2 * V.PING_GAP; eq(V.Check("Ann Dark-Realm"), true); w.Run()
		eq(B.Silent("Ann Dark-Realm"), nil, "no hello between the second and the third: in a dungeon, or gone")
		-- Hellos between each of three more checks, the first and the last five minutes apart: the mark.
		local t1 = w.clock
		w.clock = t1 + 60; B.Hello("Ann Dark-Realm", "1.5.3", w.clock)
		w.clock = t1 + V.PING_GAP; eq(V.Check("Ann Dark-Realm"), true); w.Run()
		eq(B.Silent("Ann Dark-Realm"), nil, "two since the restart")
		w.clock = t1 + V.PING_GAP + 60; B.Hello("Ann Dark-Realm", "1.5.3", w.clock)
		w.clock = t1 + 2 * V.PING_GAP; eq(V.Check("Ann Dark-Realm"), true); w.Run()
		eq(B.Silent("Ann Dark-Realm"), nil, "three, but four minutes apart")
		w.clock = t1 + 2 * V.PING_GAP + 60; B.Hello("Ann Dark-Realm", "1.5.3", w.clock)
		w.clock = t1 + 3 * V.PING_GAP; eq(V.Check("Ann Dark-Realm"), true); w.Run()
		local s = B.Silent("Ann Dark-Realm")
		assert(s, "the silent mark"); eq(s.n, 4); eq(s.at, w.clock)
		eq(B.Quarantined("Ann Dark-Realm"), false, "shown, never a lock")
		eq(B.Modified("Ann Dark-Realm"), nil, "not a sighting of a modified build")
		local root = Menu()
		V.MenuLines({ name = "Ann Dark-Realm" }, root)
		assert(root.Texts():find("title:|cff9d9d9d" .. L.VERSION_DETAIL_SILENT:format(4) .. "|r", 1, true), root.Texts())
		assert(B.Text():find(L.BUILDS_HOW_SILENT:format(4), 1, true), B.Text())
		-- A late answer: the mark goes, and nothing of it is kept.
		V.HandleAnswer("WHISPER", "Ann Dark-Realm", "V8~4242~1.5.3")
		eq(B.Silent("Ann Dark-Realm"), nil, "an answer clears the mark"); eq(B.Count(), 0)
		-- A guildmate older than 1.1.2 answers no check: never marked.
		w.hellos["Old Timer"] = "1.1.1"
		local t2 = w.clock + 1000
		for i = 0, 2 do
			w.clock = t2 + i * 150; B.Hello("Old Timer-Realm", "1.1.1", w.clock)
			w.clock = t2 + i * 150 + 10; eq(V.Check("Old Timer-Realm"), true); w.Run()
		end
		eq(B.Silent("Old Timer-Realm"), nil, "a version that cannot answer")
		-- Nobody whose hello was never heard (a stranger): never marked.
		local t3 = w.clock + 1000
		for i = 0, 2 do w.clock = t3 + i * 150; eq(V.Check("Stranger-Realm"), true); w.Run() end
		eq(B.Silent("Stranger-Realm"), nil, "no hello, no presence to hold against him")
	end)
end)

test("1.5.4 modified builds: the record keeps 400 sightings account-wide, the oldest out", function()
	WithBuilds("Tester-Realm", function(w)
		for i = 1, B.MAX + 5 do
			w.clock = w.clock + 1
			B.Hello(("Peer%d-Realm"):format(i), "1.5.1-onn." .. i, w.clock)
		end
		eq(B.Count(), B.MAX)
		for i = 1, 5 do eq(B.Modified(("Peer%d-Realm"):format(i)), nil, "the oldest out: Peer" .. i) end
		eq(B.Modified("Peer6-Realm").version, "1.5.1-onn.6"); eq(B.Modified(("Peer%d-Realm"):format(B.MAX + 5)).version, "1.5.1-onn." .. (B.MAX + 5))
		eq(B.Quarantined("Peer1-Realm"), false, "out of the record, out of the lock"); eq(B.Quarantined("Peer6-Realm"), true)
		-- Seen again, an old sighting is the newest, and stays.
		w.clock = w.clock + 1
		B.Hello("Peer6-Realm", "1.5.1-onn.6", w.clock)
		w.clock = w.clock + 1
		B.Hello("Peer999-Realm", "1.5.1-onn.999", w.clock)
		eq(B.Count(), B.MAX); eq(B.Modified("Peer6-Realm").last, w.clock - 1); eq(B.Modified("Peer7-Realm"), nil, "Peer7 was the oldest now")
	end)
end)

test("1.5.4 modified builds guild: a guild master's or officer's client shares a sighting of its own once an hour over GUILD and the channel, six a minute at most; a member's client shares nothing; the silent mark is never shared", function()
	WithBuilds("Tester-Realm", function(w)
		B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock)
		eq(#w.sent, 0, "a plain member shares nothing")
	end)
	for _, rank in ipairs({ 0, 1 }) do
		WithBuilds("Tester-Realm", function(w)
			B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock)
			eq(#w.sent, 2, "rank " .. rank .. ": over GUILD and on the channel")
			eq(w.sent[1].dist, "GUILD"); eq(w.sent[2].dist, "CHANNEL")
			local word = ("BD~1~Olympus II~Ann Dark-Realm~1.5.1-onn.12~h~%d~%d~"):format(w.clock, w.clock)
			eq(w.sent[1].msg, word); eq(w.sent[2].msg, word)
			assert(w.sent[1].key ~= w.sent[2].key, "a key each, or one would take the other's place in the queue")
			-- The same sighting again within the hour (its hello every minute): nothing more.
			for i = 1, 50 do w.clock = w.clock + 60; B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock) end
			eq(#w.sent, 2, "once an hour")
			w.clock = w.clock + 600
			B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock)
			eq(#w.sent, 4, "an hour on: again, with the sighting's first and last")
			eq(w.sent[3].msg, ("BD~1~Olympus II~Ann Dark-Realm~1.5.1-onn.12~h~%d~%d~"):format(w.clock - 3600, w.clock))
			-- Six a minute at most, whatever they name (the minute after the word above).
			w.clock = w.clock + 61
			w.sent = {}
			for i = 1, 9 do B.Hello(("Peer%d-Realm"):format(i), "1.5.1-onn.1", w.clock) end
			eq(#w.sent, 2 * B.SHARE_PER_MIN, "six sightings a minute, two words each")
			w.clock = w.clock + 61
			B.Hello("Peer9-Realm", "1.5.1-onn.1", w.clock)
			eq(#w.sent, 2 * B.SHARE_PER_MIN + 2, "the next minute")
			-- A Check version answer's sighting goes as "a"; the silent mark never goes.
			w.sent = {}
			eq(V.Check("Hal Brown-Realm"), true)
			V.HandleAnswer("WHISPER", "Hal Brown-Realm", "V8~4242~1.5.3-custom")
			eq(#w.sent, 2); assert(w.sent[1].msg:find("^BD~1~Olympus II~Hal Brown%-Realm~1.5.3%-custom~a~"), w.sent[1].msg)
			w.sent = {}
			w.hellos["Cid Grey"] = "1.5.3"
			local t1 = w.clock
			B.Hello("Cid Grey-Realm", "1.5.3", w.clock)
			for i = 0, 2 do
				w.clock = t1 + i * 150 + 10; eq(V.Check("Cid Grey-Realm"), true); w.Run()
				w.clock = t1 + i * 150 + 100; B.Hello("Cid Grey-Realm", "1.5.3", w.clock)
			end
			assert(B.Silent("Cid Grey-Realm"), "marked silent"); eq(#w.sent, 0, "the weak mark stays on this client")
		end, { rank = rank })
	end
end)

test("1.5.4 modified builds guild: a guild master's or officer's word (the roster over GUILD, the census on the channel), a councillor's, the King's or the author's is kept with the reporter's name; a member's is refused; a plain member keeps none; a word naming us or a release, or malformed, is dropped; a shared record never locks and ours stands over it", function()
	-- A plain member's client keeps no shared word.
	WithBuilds("Tester-Realm", function(w)
		w.ranks["Lord Hale-Realm"] = 0
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Ann Dark-Realm", "1.5.1-onn.12"))
		eq(B.Count(), 0, "plain members never receive the list")
	end)
	WithBuilds("Tester-Realm", function(w)
		w.ranks["Lord Hale-Realm"], w.ranks["Captain Rook-Realm"], w.ranks["Member Moss-Realm"] = 0, 1, 3
		-- Over GUILD: the roster's rank.
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Ann Dark-Realm", "1.5.1-onn.12", "h", w.clock - 7200, w.clock - 3600, "Olympus II", "Olympus II"))
		local e = B.Modified("Ann Dark-Realm")
		assert(e, "kept"); eq(e.by, "Lord Hale-Realm"); eq(e.version, "1.5.1-onn.12"); eq(e.how, "hello"); eq(e.first, w.clock - 7200); eq(e.last, w.clock - 3600); eq(e.guild, "Olympus II")
		eq(B.Quarantined("Ann Dark-Realm"), false, "a reporter's word never locks")
		B.HandleShare("GUILD", "Captain Rook-Realm", Word("Bob Light-Realm", "1.5.3-custom", "a"))
		eq(B.Modified("Bob Light-Realm").by, "Captain Rook-Realm"); eq(B.Modified("Bob Light-Realm").how, "answer")
		B.HandleShare("GUILD", "Member Moss-Realm", Word("Cid Grey-Realm", "1.5.1-onn.12"))
		eq(B.Modified("Cid Grey-Realm"), nil, "a member's word is refused")
		B.HandleShare("GUILD", "Nobody Known-Realm", Word("Cid Grey-Realm", "1.5.1-onn.12"))
		eq(B.Modified("Cid Grey-Realm"), nil, "a stranger's too")
		-- On the channel (by the relay): the census's rank for the guild the word names, else a councillor,
		-- the King or the author.
		B.HandleShare("CHANNEL", "Lord Hale-Realm", Word("Dee Blue-Realm", "1.5.1-onn.12", "h", nil, nil, "Olympus Dawn"))
		eq(B.Modified("Dee Blue-Realm").by, "Lord Hale-Realm", "the census makes him a guild master of the guild named")
		B.HandleShare("CHANNEL", "Lord Hale-Realm", Word("Eve Red-Realm", "1.5.1-onn.12", "h", nil, nil, ""))
		eq(B.Modified("Eve Red-Realm"), nil, "no guild named: no rank on the channel")
		ns.rdb.council = { at = 1, names = { ["max ran"] = "Max Ran" } }
		B.HandleShare("CHANNEL", "Max Ran-Realm", Word("Eve Red-Realm", "1.5.1-onn.12", "h", nil, nil, ""))
		eq(B.Modified("Eve Red-Realm").by, "Max Ran-Realm", "a councillor's word")
		B.HandleShare("CHANNEL", ns.KING_CHARACTER.Alliance .. "-Realm", Word("Fay Gold-Realm", "1.5.1-onn.12", "h", nil, nil, ""))
		eq(B.Modified("Fay Gold-Realm").by, ns.KING_CHARACTER.Alliance .. "-Realm", "the King's word")
		-- Dropped: a word naming us, a release version, a malformed one, a wrong version of the word.
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Tester-Realm", "1.5.1-onn.12"))
		eq(B.Modified("Tester-Realm"), nil, "never ourselves")
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Gus Pale-Realm", "1.5.4"))
		eq(B.Modified("Gus Pale-Realm"), nil, "no client shares a release: nothing to keep")
		B.HandleShare("GUILD", "Lord Hale-Realm", "BD~2~Olympus II~Gus Pale-Realm~1.5.1-onn.12~h~1~1~")
		B.HandleShare("GUILD", "Lord Hale-Realm", "BD~1~Olympus II~Gus Pale-Realm~1.5.1-onn.12~x~1~1~")
		B.HandleShare("GUILD", "Lord Hale-Realm", "BD~1~Olympus II~Gus Pale-Realm~1.5.1-onn.12~h~soon~1~")
		B.HandleShare("GUILD", "Lord Hale-Realm", "BD~1~Olympus II~" .. ("x"):rep(70) .. "~1.5.1-onn.12~h~1~1~")
		B.HandleShare("WHISPER", "Lord Hale-Realm", Word("Gus Pale-Realm", "1.5.1-onn.12"))
		eq(B.Modified("Gus Pale-Realm"), nil, "malformed, or by whisper")
		-- Times from the future or the far past are read as now.
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Hal Brown-Realm", "1.5.1-onn.12", "h", w.clock + 900, w.clock + 1000))
		eq(B.Modified("Hal Brown-Realm").last, w.clock); eq(B.Modified("Hal Brown-Realm").first, w.clock)
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Ida Green-Realm", "1.5.1-onn.12", "h", 1, 2))
		eq(B.Modified("Ida Green-Realm").last, w.clock)
		-- Our own observation stands over a reporter's word, and a reporter's never replaces ours.
		B.Hello("Ann Dark-Realm", "1.5.1-onn.14", w.clock)
		eq(B.Modified("Ann Dark-Realm").by, nil); eq(B.Modified("Ann Dark-Realm").version, "1.5.1-onn.14"); eq(B.Quarantined("Ann Dark-Realm"), true)
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Ann Dark-Realm", "1.5.1-onn.12"))
		eq(B.Modified("Ann Dark-Realm").by, nil, "ours stands"); eq(B.Modified("Ann Dark-Realm").version, "1.5.1-onn.14")
		-- A newer word of another reporter takes a shared record's place.
		B.HandleShare("GUILD", "Captain Rook-Realm", Word("Bob Light-Realm", "1.5.3-custom.2", "h", w.clock, w.clock))
		eq(B.Modified("Bob Light-Realm").version, "1.5.3-custom.2"); eq(B.Modified("Bob Light-Realm").by, "Captain Rook-Realm")
		-- A sanctioned reporter (WatchChat.Barred) has none of the powers.
		local WC = ns.WatchChat
		local savedBarred = WC and WC.Barred
		if WC and not WC.missing then
			WC.Barred = function(kind, who) return who == "Lord Hale-Realm" end
			B.HandleShare("GUILD", "Lord Hale-Realm", Word("Jon Teal-Realm", "1.5.1-onn.12"))
			WC.Barred = savedBarred
			eq(B.Modified("Jon Teal-Realm"), nil, "a sanctioned reporter's word is refused")
		end
	end, { rank = 0 })
end)

test("1.5.4 modified builds: /oly builds opens a copyable window: the sightings online now first, then the rest newest first, each with its version, where from, when and who reported it; a member sees his own client's and is told the shared list is the officers'", function()
	WithBuilds("Tester-Realm", function(w)
		B.Show()
		eq(#w.copies, 1); eq(w.copies[1].title, L.BUILDS_TITLE); eq(w.copies[1].opts.key, "builds")
		assert(w.copies[1].text:find(L.BUILDS_HEAD:format(0), 1, true), w.copies[1].text)
		assert(w.copies[1].text:find(L.BUILDS_NONE, 1, true), "nothing seen")
		assert(w.copies[1].text:find(L.BUILDS_MEMBERS_NOTE, 1, true), "a member: the shared list is the officers'")
		w.ranks["Lord Hale-Realm"] = 0
		B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock - 120)
		B.Hello("Bob Light-Realm", "1.5.3-custom", w.clock - 3600)
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Cid Grey-Realm", "1.5.1-onn.12"))
		w.online = { "Bob Light-Realm" }
		local text = B.Text()
		assert(text:find(L.BUILDS_HEAD:format(2), 1, true), text)
		assert(text:find(L.BUILDS_LOCK_NOTE, 1, true), "what the lock does")
		local online, seen = text:find(L.BUILDS_ONLINE, 1, true), text:find(L.BUILDS_SEEN, 1, true)
		assert(online and seen and online < seen, text)
		local bob = text:find("Bob Light  1.5.3  " .. L.BUILDS_HOW_HELLO .. ", " .. ns.Ago(w.clock - 3600) .. "  (" .. L.BUILDS_BY_YOU .. ")", 1, true)
		local ann = text:find("Ann Dark  1.5.1  " .. L.BUILDS_HOW_HELLO .. ", " .. ns.Ago(w.clock - 120) .. "  (" .. L.BUILDS_BY_YOU .. ")", 1, true)
		assert(bob and ann, text); assert(online < bob and bob < seen and seen < ann, "Bob online first, Ann seen before")
		eq(text:find("Cid Grey", 1, true), nil, "a member is not shown the shared list")
		assert(not text:find("-onn", 1, true) and not text:find("custom", 1, true), "never the rest of a version string: a modified build, plainly")
	end)
	WithBuilds("Tester-Realm", function(w)
		w.ranks["Lord Hale-Realm"] = 0
		B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock - 120)
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Cid Grey-Realm", "1.5.1-onn.12", "a", w.clock - 7200, w.clock - 7000, "Olympus II", "Olympus Dawn"))
		B.Hello("Ann Dark-Realm", "1.5.4", w.clock)
		local text = B.Text()
		assert(text:find(L.BUILDS_HEAD:format(2), 1, true), text)
		assert(text:find("Cid Grey <Olympus Dawn>  1.5.1  " .. L.BUILDS_HOW_ANSWER .. ", " .. ns.Ago(w.clock - 7000) .. "  (" .. L.BUILDS_BY:format("Lord Hale") .. ")", 1, true), text)
		assert(text:find("Ann Dark  1.5.1  " .. L.BUILDS_HOW_HELLO .. ", " .. ns.Ago(w.clock - 120) .. "  (" .. L.BUILDS_BY_YOU .. "); " .. L.BUILDS_CLEARED:format("1.5.4"), 1, true), text)
		eq(text:find(L.BUILDS_MEMBERS_NOTE, 1, true), nil, "a guild master: the whole list")
	end, { rank = 0 })
end)

test("1.5.4 modified builds menu: the right-click menu's version line says modified build with the release it was made from, under it where from and that it is locked; a reporter's record for a guild master, with his name; Ask to update greyed; the person card's line", function()
	WithBuilds("Tester-Realm", function(w)
		w.hellos["Ann Dark"] = "?" -- (Comm.PeerVersion: a version it cannot read)
		B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock - 90)
		local root = Menu()
		V.MenuLines({ name = "Ann Dark-Realm" }, root)
		local detail = L.VERSION_DETAIL_HELLO:format(ns.Ago(w.clock - 90)) .. "; " .. L.VERSION_DETAIL_LOCKED
		eq(root.Texts(), "title:" .. L.VERSION_LINE_MODIFIED:format("1.5.1") .. " | title:|cff9d9d9d" .. detail .. "|r | button:" .. L.VERSION_CHECK)
		eq(V.CardLine("Ann Dark-Realm"), L.VERSION_LINE_MODIFIED:format("1.5.1"), "the person card too")
		eq(V.HasOlympus("Ann Dark-Realm"), true)
		-- Nothing of a check: from the answer.
		V.Check("Bob Light-Realm")
		V.HandleAnswer("WHISPER", "Bob Light-Realm", "V8~4242~1.5.3-custom")
		root = Menu()
		V.MenuLines({ name = "Bob Light-Realm" }, root)
		assert(root.Texts():find("^title:" .. L.VERSION_LINE_MODIFIED:format("1.5.3"):gsub("%p", "%%%0") .. " | title:|cff9d9d9d" .. L.VERSION_DETAIL_CHECK:format(ns.Ago(w.clock)):gsub("%p", "%%%0") .. "; "), root.Texts())
		-- A member is shown nothing of a reporter's record.
		w.ranks["Lord Hale-Realm"] = 0
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Cid Grey-Realm", "1.5.1-onn.12"))
		root = Menu()
		V.MenuLines({ name = "Cid Grey-Realm" }, root)
		eq(root.Texts(), "title:" .. L.VERSION_LINE_UNKNOWN .. " | button:" .. L.VERSION_CHECK)
	end)
	-- A guild master: the reporter's record, with his name; as a councillor, Ask to update greyed.
	WithBuilds("Tester-Realm", function(w)
		w.ranks["Lord Hale-Realm"] = 0
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Cid Grey-Realm", "1.5.1-onn.12", "h", w.clock - 7200, w.clock - 3600))
		local root = Menu()
		V.MenuLines({ name = "Cid Grey-Realm" }, root)
		local detail = L.VERSION_DETAIL_SHARED:format("Lord Hale", ns.Ago(w.clock - 3600))
		eq(root.Texts(), "title:" .. L.VERSION_LINE_MODIFIED:format("1.5.1") .. " | title:|cff9d9d9d" .. detail .. "|r | button:" .. L.VERSION_CHECK)
		local state, version, how, at = V.Status("Cid Grey-Realm")
		eq(state, "modified"); eq(version, "1.5.1-onn.12"); eq(how, "shared"); eq(at, w.clock - 3600)
		ns.rdb.council = { at = 1, names = { tester = "Tester" } }
		root = Menu()
		V.MenuLines({ name = "Cid Grey-Realm" }, root)
		local ask = root.Find(L.VERSION_ASK)
		assert(ask, root.Texts()); eq(ask.enabled, false, "no release to update from"); eq(ask.tip, L.VERSION_ASK_MODIFIED_TIP)
		eq(V.AskUpdate("Cid Grey-Realm"), false, "and the click sends nothing"); eq(#w.whispered, 0)
	end, { rank = 0 })
end)

---------------------------------------------------------------------------
-- The lock: Comm's door and the relay (RelayWorld: Comm.lua and Relay.lua in a world of their own)
---------------------------------------------------------------------------

local function RelaySetup(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		fn()
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end
-- A client of the world with the builds' record of its own.
local function Relayed(me)
	local R, Deliver, sent, heard, Pump, Sent = extra.RelayWorld(me, "Olympus II")
	R.db = { blocked = {} }
	R.Log = function() end
	assert(loadfile(extra.addon .. "Builds.lua"))("Olympus", R)
	R.Builds.Reset()
	return R, Deliver, sent, heard, Pump, Sent
end
local RELAY, REALM7 = "Hildryn Payne-CAMWOWUS2Realm1PvE", "-CAMWOWUS2Realm7PvE"

test("1.5.4 modified builds relay: a marked client's registration (RR) is ignored and one the relay holds is dropped; nothing is forwarded to it; its RL words are dropped; a release announced takes it back", function()
	RelaySetup(function()
		local R, Deliver, sent, _, Pump = Relayed(RELAY)
		local one, two, origin = "Rep One" .. REALM7, "Rep Two" .. REALM7, "Some Origin" .. REALM7
		local function Reporters() return R.Relay.Stats().reporters end
		local function To(name, since)
			local n = 0
			for i = (since or 0) + 1, #sent do if sent[i].target == name and sent[i].msg:sub(1, 3) == "RM~" and sent[i].msg:find("~X1~", 1, true) then n = n + 1 end end
			return n
		end
		-- Two reporters registered; a word from a client goes to both.
		Deliver("WHISPER", one, "RL~P~RR~Guild One")
		Deliver("WHISPER", two, "RL~P~RR~Guild Two")
		eq(Reporters(), 2)
		Deliver("WHISPER", origin, "RL~P~X1~first")
		Pump(10)
		eq(To(one), 1); eq(To(two), 1)
		-- One's hello names a modified build: its registration goes at once.
		Deliver("GUILD", one, "H1~1.5.1-onn.12~CAMWOWUS2Realm7PvE~p~~~~R")
		eq(R.Builds.Quarantined(one), true)
		eq(Reporters(), 1, "the registration it held is dropped")
		-- Its registration again: ignored at the door.
		local before = R.Comm.Stats().quarantined
		Deliver("WHISPER", one, "RL~P~RR~Guild One")
		eq(Reporters(), 1, "RR ignored"); eq(R.Comm.Stats().quarantined, before + 1, "dropped at Comm's door")
		-- Its words: dropped, forwarded to nobody.
		Pump(20)
		local forwarded, n = R.Relay.Stats().forwarded, #sent
		Deliver("WHISPER", one, "RL~P~X1~from-one")
		Pump(10)
		eq(R.Relay.Stats().forwarded, forwarded, "an RL word of its is dropped"); eq(#sent, n, "nothing sent for it")
		-- Another client's word: to Two alone.
		n = #sent
		Deliver("WHISPER", origin, "RL~P~X1~second")
		Pump(10)
		eq(To(one, n), 0, "nothing forwarded to the marked client"); eq(To(two, n), 1)
		-- The other reporter marked too (another modified version): its registration goes with it.
		Deliver("GUILD", two, "H1~1.5.3-custom~CAMWOWUS2Realm7PvE~p~~~~R")
		Pump(20)
		n = #sent
		Deliver("WHISPER", origin, "RL~P~X1~third")
		Pump(10)
		eq(To(two, n), 0, "not forwarded to the newly marked reporter"); eq(Reporters(), 0, "its registration dropped")
		-- A release announced: taken back, registered again.
		Deliver("GUILD", one, "H1~1.5.4~CAMWOWUS2Realm7PvE~p~~~~R")
		eq(R.Builds.Quarantined(one), false)
		Deliver("WHISPER", one, "RL~P~RR~Guild One")
		eq(Reporters(), 1, "registered again")
		n = #sent
		Deliver("WHISPER", origin, "RL~P~X1~fourth")
		Pump(10)
		eq(To(one, n), 1, "forwarded to it again")
		eq(R.Builds.Count(), 2, "both sightings stay in the record"); eq(R.Builds.Modified(one).release, "1.5.4")
	end)
end)

test("1.5.4 modified builds guild: at Comm's door a marked guildmate's RG hand-over, guild words, channel words and census pieces are dropped; its hello and version answer pass; our own client is never marked; the election skips it; a release lets it back in", function()
	RelaySetup(function()
		local R, Deliver, _, heard = Relayed("Member One-Realm")
		local mate, other, origin = "Mate Two-Realm", "Mate Three-Realm", "Some Origin-Realm"
		R.clock = 1800000000
		-- Before any mark: a hand-over, a guild word and a channel word are heard.
		Deliver("GUILD", mate, "RG~P~" .. origin .. "~X1~handed")
		Deliver("GUILD", mate, "X1~guild-word")
		Deliver("CHANNEL", mate, "X1~channel-word")
		eq(#heard, 3); eq(heard[1].sender, origin); eq(heard[1].text, "X1~handed")
		-- Its hello names a modified build.
		Deliver("GUILD", mate, "H1~1.5.1-onn.12~Realm~p~~~~R")
		Deliver("GUILD", other, "H1~1.5.4~Realm~p~~~~R")
		eq(R.Builds.Quarantined(mate), true); eq(R.Builds.Quarantined(other), false)
		local before = R.Comm.Stats().quarantined
		Deliver("GUILD", mate, "RG~P~" .. origin .. "~X1~handed-again")
		Deliver("GUILD", mate, "X1~guild-word-again")
		Deliver("CHANNEL", mate, "X1~channel-word-again")
		local pieces = R.Codec.Chunk("R2~" .. ("Olympus II,1,2,3;"):rep(20), "41")
		assert(#pieces >= 2, "a census report in pieces")
		for _, c in ipairs(pieces) do Deliver("CHANNEL", mate, c) end
		eq(#heard, 3, "nothing of its is heard"); eq(R.Comm.Stats().quarantined, before + 3 + #pieces, "each dropped at the door")
		-- The other guildmate's words still come.
		Deliver("GUILD", other, "RG~P~" .. origin .. "~X1~handed-by-other")
		eq(#heard, 4)
		-- Its hello keeps counting it present (the lock may clear), and its version answer passes the door.
		eq(R.Comm.PeerVersion(mate), "?", "its version, as Comm shows one it cannot read")
		-- The election never picks it; the other is in the pool.
		local pool = R.Comm.Electable(R.clock)
		eq(pool[mate], nil, "a marked client is never elected"); assert(pool[other], "the other is")
		-- Our own client: never, whatever is said.
		R.Builds.Hello(R.me, "1.5.1-onn.12", R.clock)
		eq(R.Builds.Quarantined(R.me), false)
		-- A release announced: back in.
		Deliver("GUILD", mate, "H1~1.5.4~Realm~p~~~~R")
		eq(R.Builds.Quarantined(mate), false)
		Deliver("GUILD", mate, "X1~guild-word-back")
		eq(#heard, 5, "heard again"); assert(R.Comm.Electable(R.clock)[mate], "elected again")
	end)
end)

test("1.5.4 modified builds README privacy: both privacy tables name the sighting shared (what, with whom, how long kept) and what the client records and locks; the commands name /oly builds; the roadmap's 1.5.4 line names the lock", function()
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local doc = ReadFile(ROOT .. path)
		local privacy = assert(doc:match("\n## Privacy\n(.-)\n## "), path .. ": the privacy section")
		local shared, own
		for line in privacy:gmatch("[^\n]+") do
			if line:sub(1, 2) == "| " then
				if line:find("A modified-build sighting (1.5.4)", 1, true) then shared = line end
				if line:find("What your own addon saw of modified builds (1.5.4)", 1, true) then own = line end
			end
		end
		assert(shared, path .. ": the shared sighting's row")
		for _, must in ipairs({ "the version string its addon announced", "guild masters and officers of every Olympus guild, the High Council", "once an hour per character", "400 sightings at most, the oldest out", "with the reporter's name", "account-wide",
			"The relays pass it to one another and lock the character out as if they had seen it themselves, until it announces a release to one of them" }) do
			assert(shared:find(must, 1, true), path .. ": the shared row: " .. must)
		end
		assert(own, path .. ": the own record's row")
		for _, must in ipairs({ "silent to version checks", "locked out", "drops its words until it announces a release version", "`/oly builds`", "right-click menu" }) do
			assert(own:find(must, 1, true), path .. ": the own row: " .. must)
		end
		local ask
		for line in privacy:gmatch("[^\n]+") do
			if line:sub(1, 2) == "| " and line:find("The author's update ask to a modified build (1.5.4)", 1, true) then ask = line end
		end
		assert(ask, path .. ": the author's ask's row")
		for _, must in ipairs({ "that player alone (a whisper from the author's character)", "while it carries the relay", "every 30 minutes", "online (in his guild, or heard by his client in the last 5 minutes)", "20 every 30 minutes at most", "never to anyone else" }) do
			assert(ask:find(must, 1, true), path .. ": the author's ask's row: " .. must)
		end
		local commands = assert(doc:match("\n## Commands\n(.-)\n## "), path .. ": the commands")
		assert(commands:find("\n| `/oly builds` |", 1, true), path .. ": /oly builds among the commands")
	end
	local roadmap = ReadFile(ROOT .. "ROADMAP.md")
	local line = assert(roadmap:match("\n%- v1%.5%.4 ([^\n]+)"), "the 1.5.4 line")
	for _, must in ipairs({ "modified build", "`/oly builds`", "locked out", "The relays keep the shared list too", "The author's relay asks each locked client online to update every 30 minutes" }) do assert(line:find(must, 1, true), "ROADMAP 1.5.4: " .. must) end
end)

---------------------------------------------------------------------------
-- The relays keep the list and act on it (the owner's call, the same day)
---------------------------------------------------------------------------

-- A word of the relay world's sends that carries `needle` (plain), after the n-th send.
local function Carrying(sent, needle, n)
	local out = {}
	for i = (n or 0) + 1, #sent do if sent[i].msg:find(needle, 1, true) then out[#out + 1] = sent[i] end end
	return out
end
local OTHER = "Max Ran-CAMWOWUS2Realm1PvE" -- the world's other relay

test("1.5.4 modified builds relays: a relay's client keeps another relay's word and acts on a listed character as on its own: the registration it held dropped, its RR ignored, its RL words and its words across (RX) forwarded to nobody, nothing forwarded to it; a release it announces to the relay clears it there and the clear is shared, across to the other relay too; a keeper's clear lets a listed character back in, never one the relay marked itself", function()
	RelaySetup(function()
		local R, Deliver, sent, _, Pump = Relayed(RELAY)
		R.clock = 1800000000
		-- (1.5.4, with the relays' presentation) This world is dated past Relay.PRESENT_REQUIRED_AT and its
		-- clients hand their words in without presenting, which the relays refuse from that date on. The
		-- presentation has its own tests (tests/relay-admit.lua): here the deadline is moved past the
		-- world's date, as tests/verify-relay.lua does, so these stay about the modified builds.
		R.Relay.PRESENT_REQUIRED_AT = R.clock + 30 * 86400
		local one, two, origin = "Rep One" .. REALM7, "Rep Two" .. REALM7, "Some Origin" .. REALM7
		Deliver("WHISPER", one, "RL~P~RR~Guild One")
		Deliver("WHISPER", two, "RL~P~RR~Guild Two")
		eq(R.Relay.Stats().reporters, 2)
		-- The other relay's word about Rep One crosses to this relay (RW): kept, and acted on.
		local word = ("BD~1~Olympus Dawn~%s~1.5.1-onn.12~h~%d~%d~Guild One"):format(one, R.clock - 60, R.clock - 60)
		Deliver("WHISPER", OTHER, "RW~P~" .. OTHER .. "~" .. word)
		local e = R.Builds.Modified(one)
		assert(e, "a relay keeps the list"); eq(e.by, OTHER, "a relay's word, trusted as a guild master's")
		eq(R.Builds.Quarantined(one), true, "and acts on it")
		eq(R.Relay.Stats().reporters, 1, "the registration it held is dropped")
		Deliver("WHISPER", one, "RL~P~RR~Guild One")
		eq(R.Relay.Stats().reporters, 1, "its RR ignored")
		Pump(30)
		local n = #sent
		Deliver("WHISPER", one, "RL~P~X1~from-one")
		Deliver("WHISPER", OTHER, "RX~P~" .. one .. "~X1~from-one-across")
		Deliver("WHISPER", origin, "RL~P~X1~from-origin")
		Pump(30)
		eq(#Carrying(sent, "from-one", n), 0, "neither its RL word nor its word across is forwarded")
		local toOne, toTwo = 0, 0
		for _, s in ipairs(Carrying(sent, "from-origin", n)) do
			if s.target == one then toOne = toOne + 1 elseif s.target == two then toTwo = toTwo + 1 end
		end
		eq(toOne, 0, "nothing forwarded to the listed client"); eq(toTwo, 1, "the other reporter still gets it")
		-- Rep One announces a release to this relay (its hello): cleared here, back in, and the clear shared.
		n = #sent
		Deliver("GUILD", one, "H1~1.5.4~CAMWOWUS2Realm7PvE~p~~~~R")
		eq(R.Builds.Quarantined(one), false, "our own observation beats the list")
		Pump(30)
		local clear = ("BD~1~Olympus II~%s~1.5.4~c~%d~%d~Guild One"):format(one, R.clock - 60, R.clock)
		local guild, across = 0, 0
		for _, s in ipairs(Carrying(sent, clear, n)) do
			if s.dist == "GUILD" and s.msg == clear then guild = guild + 1 end
			-- (As RW from this relay, or as RL when Pick makes the other relay this guild's: it answered.)
			if (s.msg:find("^RW~P~") or s.msg:find("^RL~P~")) and tostring(s.target):find("^Max Ran") then across = across + 1 end
		end
		eq(guild, 1, "the clear over GUILD"); eq(across, 1, "and across to the other relay")
		Deliver("WHISPER", one, "RL~P~RR~Guild One")
		eq(R.Relay.Stats().reporters, 2, "registered again")
		-- A keeper's clear of a listed character lets it back in; a newer sighting marks it again.
		local w2 = ("BD~1~Olympus Dawn~%s~1.5.3-custom~h~%d~%d~"):format(two, R.clock - 30, R.clock - 30)
		Deliver("WHISPER", OTHER, "RW~P~" .. OTHER .. "~" .. w2)
		eq(R.Builds.Quarantined(two), true)
		Deliver("WHISPER", OTHER, "RW~P~" .. OTHER .. "~" .. ("BD~1~Olympus Dawn~%s~1.5.4~c~%d~%d~"):format(two, R.clock - 30, R.clock))
		eq(R.Builds.Quarantined(two), false, "a keeper's clear lets it back in")
		R.clock = R.clock + 60
		Deliver("WHISPER", OTHER, "RW~P~" .. OTHER .. "~" .. ("BD~1~Olympus Dawn~%s~1.5.3-custom~h~%d~%d~"):format(two, R.clock - 30, R.clock))
		eq(R.Builds.Quarantined(two), true, "seen on a modified build after the clear: locked again")
		-- A mark of the relay's own: a keeper's clear never lifts it.
		Deliver("GUILD", origin, "H1~1.5.1-onn.12~CAMWOWUS2Realm7PvE~p~~~~R")
		eq(R.Builds.Quarantined(origin), true)
		Deliver("WHISPER", OTHER, "RW~P~" .. OTHER .. "~" .. ("BD~1~Olympus Dawn~%s~1.5.4~c~%d~%d~"):format(origin, R.clock, R.clock))
		eq(R.Builds.Quarantined(origin), true, "only what the character says to us clears our own mark")
	end)
end)

test("1.5.4 modified builds relays: a sighting a relay hears from its clients crosses once to every other relay (RW) and goes to its reporters; it is kept where its origin may say it (a relay's, the author's), never from a plain client", function()
	RelaySetup(function()
		local R, Deliver, sent, _, Pump = Relayed(RELAY)
		R.clock = 1800000000
		-- (1.5.4, with the relays' presentation) This world is dated past Relay.PRESENT_REQUIRED_AT and its
		-- clients hand their words in without presenting, which the relays refuse from that date on. The
		-- presentation has its own tests (tests/relay-admit.lua): here the deadline is moved past the
		-- world's date, as tests/verify-relay.lua does, so these stay about the modified builds.
		R.Relay.PRESENT_REQUIRED_AT = R.clock + 30 * 86400
		local rep, client = "Rep One" .. REALM7, "Some Client" .. REALM7
		Deliver("WHISPER", rep, "RL~P~RR~Guild One")
		local word = ("BD~1~Olympus Dawn~%s~1.5.1-onn.12~h~%d~%d~"):format("Ann Dark" .. REALM7, R.clock, R.clock)
		Deliver("WHISPER", client, "RL~P~" .. word)
		Pump(30)
		local function Across()
			local k = 0
			for _, s in ipairs(sent) do
				if s.msg == "RW~P~" .. client .. "~" .. word then k = k + 1; assert(tostring(s.target):find("^Max Ran"), tostring(s.target)) end
			end
			return k
		end
		eq(Across(), 1, "once to the other relay")
		local toRep = 0
		for _, s in ipairs(sent) do if s.target == rep and s.msg == "RM~P~" .. client .. "~" .. word then toRep = toRep + 1 end end
		eq(toRep, 1, "and to its reporters")
		eq(R.Builds.Modified("Ann Dark" .. REALM7), nil, "a plain client's word is not kept")
		Deliver("WHISPER", client, "RL~P~" .. word)
		Pump(30)
		eq(Across(), 1, "the same word again: not across again")
		-- The author's word (by RL, as from any client): kept, and acted on by the relay.
		R.IsAuthorName = function(n) return ns.ShortName(n) == "Quill Author" end
		local w2 = ("BD~1~Olympus Dawn~%s~1.5.3-custom~a~%d~%d~"):format("Bob Light" .. REALM7, R.clock, R.clock)
		Deliver("WHISPER", "Quill Author" .. REALM7, "RL~P~" .. w2)
		eq(R.Builds.Modified("Bob Light" .. REALM7).by, "Quill Author" .. REALM7, "the author's word is kept")
		eq(R.Builds.Quarantined("Bob Light" .. REALM7), true, "and acted on")
		-- A relay's word that comes across is kept, and handed to its reporters (RM).
		local w3 = ("BD~1~Olympus Dawn~%s~1.5.1-onn.12~h~%d~%d~"):format("Cid Grey" .. REALM7, R.clock, R.clock)
		local n = #sent
		Deliver("WHISPER", OTHER, "RW~P~" .. OTHER .. "~" .. w3)
		Pump(30)
		eq(R.Builds.Modified("Cid Grey" .. REALM7).by, OTHER)
		toRep = 0
		for i = n + 1, #sent do if sent[i].target == rep and sent[i].msg == "RM~P~" .. OTHER .. "~" .. w3 then toRep = toRep + 1 end end
		eq(toRep, 1, "handed to its reporters")
	end)
end)

test("1.5.4 modified builds guild: a reporter neither hears nor hands to its guild a relayed word (RM) whose origin it marked as a modified build", function()
	RelaySetup(function()
		local R, Deliver, sent, heard, Pump = Relayed("Member One-Realm")
		local relay, marked, origin = "Max Ran-Realm", "Mate Two-Realm", "Some Origin-Realm"
		Deliver("GUILD", marked, "H1~1.5.1-onn.12~Realm~p~~~~R")
		eq(R.Builds.Quarantined(marked), true)
		Pump(20)
		local n = #sent
		Deliver("WHISPER", relay, "RM~P~" .. marked .. "~X1~relayed")
		Deliver("WHISPER", relay, "RM~P~" .. origin .. "~X1~relayed-other")
		Pump(20)
		local rg = {}
		for i = n + 1, #sent do if sent[i].msg:find("^RG~") then rg[#rg + 1] = sent[i].msg end end
		eq(#rg, 1, "only the other origin's word is handed to the guild"); assert(rg[1]:find("relayed-other", 1, true), rg[1])
		eq(#heard, 1); eq(heard[1].sender, origin)
	end)
end)

test("1.5.4 modified builds relays: a relay's character keeps the list and locks a listed character out only while the relay runs (Forever); off it, as any member, it keeps nothing", function()
	WithBuilds("Max Ran-Realm", function(w)
		w.relays = { ["Max Ran"] = true, ["Hildryn Payne"] = true }
		w.relayOn = false
		B.HandleShare("CHANNEL", "Hildryn Payne-Realm", Word("Ann Dark-Realm", "1.5.1-onn.12", "h", nil, nil, ""))
		eq(B.Count(), 0, "no relay running: a plain member's client keeps nothing")
		w.relayOn = true
		B.HandleShare("CHANNEL", "Hildryn Payne-Realm", Word("Ann Dark-Realm", "1.5.1-onn.12", "h", nil, nil, ""))
		eq(B.Modified("Ann Dark-Realm").by, "Hildryn Payne-Realm", "the relay keeps another relay's word")
		eq(B.Quarantined("Ann Dark-Realm"), true, "and locks the character out")
		eq(#w.dropped, 1, "the registration it may hold goes"); eq(w.dropped[1], "Ann Dark-Realm")
		w.relayOn = false
		eq(B.Quarantined("Ann Dark-Realm"), false, "the relay stopped: the list locks nobody here")
	end)
end)

---------------------------------------------------------------------------
-- The author's update ask to the locked clients online (his relay's client)
---------------------------------------------------------------------------

local AUTHOR = ns.AUTHOR .. "-" .. ns.AUTHOR_REALM -- (the code's author character, as tests/run.lua's AUTHOR_FULL)
-- fn(w, later) as the author's relay client: Workshop reset, his queue's room w.room (60), the
-- retries Builds.Prompt schedules in later[].
local function AsAuthorRelay(fn)
	WithBuilds(AUTHOR, function(w)
		local W = ns.Workshop
		local saved = { room = ns.Comm.QueueRoom, after = B.after }
		local later = {}
		local ok, err = pcall(function()
			W.Reset()
			w.relays, w.relayOn = { [ns.ShortName(AUTHOR)] = true }, true
			ns.Comm.QueueRoom = function() return w.room or 60 end
			B.after = function(s, where, f) later[#later + 1] = { s = s, fn = f } end
			fn(w, later)
		end)
		ns.Comm.QueueRoom, B.after = saved.room, saved.after
		W.Reset()
		if not ok then error(err, 0) end
	end)
end
local function AskedTo(w)
	local out = {}
	for _, x in ipairs(w.whispered) do
		if x.msg == "V3~" .. ns.VERSION then out[x.to] = (out[x.to] or 0) + 1 end
	end
	return out
end

test("1.5.4 modified builds prompt: every 30 minutes the author's relay client asks each locked client online to update with his own ask (V3 by whisper from his character), never an unmarked client or one offline, each once every 30 minutes; never from another client, nor from the author's while the relay does not run", function()
	AsAuthorRelay(function(w)
		-- A locked reporter heard at the door, a locked guildmate online by its hello, a locked one
		-- offline, an unmarked one online.
		B.Hello("Rep One-Realm", "1.5.1-onn.12", w.clock)
		B.Heard("Rep One-Realm")
		B.Hello("Mate Two-Realm", "1.5.3-custom", w.clock)
		B.Hello("Gone Four-Realm", "1.5.1-onn.12", w.clock - 3600)
		B.Hello("Clean Three-Realm", "1.5.4", w.clock)
		w.online = { "Mate Two-Realm", "Clean Three-Realm" }
		eq(B.Prompt(), 2)
		local asked = AskedTo(w)
		eq(asked["Rep One-Realm"], 1, "the locked reporter heard at the door"); eq(asked["Mate Two-Realm"], 1, "the locked guildmate online")
		eq(asked["Gone Four-Realm"], nil, "never one not online"); eq(asked["Clean Three-Realm"], nil, "never an unmarked one")
		eq(#w.whispered, 2, "nothing else")
		eq(w.whispered[1].key:sub(1, 10), "askupdate:", "his usual ask (Workshop.AskUpdate)")
		eq(#w.quieted, 2, "an offline answer kept out of his chat")
		-- Within the 30 minutes: nothing again, whoever is online.
		w.clock = w.clock + 600
		B.Heard("Rep One-Realm")
		eq(B.Prompt(), 0, "each once every 30 minutes"); eq(#w.whispered, 2)
		-- 30 minutes on: again.
		w.clock = w.clock + 1200
		B.Heard("Rep One-Realm")
		eq(B.Prompt(), 2)
		asked = AskedTo(w)
		eq(asked["Rep One-Realm"], 2); eq(asked["Mate Two-Realm"], 2); eq(asked["Clean Three-Realm"], nil)
		-- Heard no more (logged off): not asked.
		w.clock = w.clock + 1800
		w.online = {}
		eq(B.Prompt(), 0, "a locked client no longer heard is not asked")
		-- The relay stops (off Forever): nothing.
		B.Heard("Rep One-Realm")
		w.relayOn = false
		eq(B.Prompt(), 0, "the author's client while it carries no relay")
	end)
	WithBuilds("Hildryn Payne-Realm", function(w)
		w.relays, w.relayOn = { ["Hildryn Payne"] = true }, true
		B.Hello("Rep One-Realm", "1.5.1-onn.12", w.clock)
		B.Heard("Rep One-Realm")
		eq(B.Prompt(), 0, "another relay's client asks nobody"); eq(#w.whispered, 0)
	end)
end)

test("1.5.4 modified builds prompt: the author's asks are 20 at most each 30 minutes, the longest unasked first; while his queue keeps fewer than 20 places free beyond them they wait, tried again a minute later", function()
	AsAuthorRelay(function(w, later)
		for i = 1, 25 do
			local name = ("Peer%02d-Realm"):format(i)
			B.Hello(name, "1.5.1-onn.12", w.clock)
			w.online[#w.online + 1] = name
		end
		eq(B.Prompt(), B.PROMPT_MAX, "20 each 30 minutes")
		w.clock = w.clock + 600
		eq(B.Prompt(), 0, "the 5 left wait for the next 30 minutes"); eq(#later, 0, "no retry: the budget, not the queue")
		w.clock = w.clock + 1200
		w.whispered = {}
		eq(B.Prompt(), B.PROMPT_MAX)
		local asked = AskedTo(w)
		for i = 21, 25 do eq(asked[("Peer%02d-Realm"):format(i)], 1, "the ones left out last time first: Peer" .. i) end
		-- A busy queue: 25 places free, 20 kept for the relay's own words, so 5 asks now, the rest a minute later.
		w.clock = w.clock + 1800
		w.whispered = {}
		w.room = 25
		eq(B.Prompt(), 5, "never into the places the relay keeps")
		eq(#later, 1, "tried again"); eq(later[1].s, 60)
		w.room = 60
		w.clock = w.clock + 60
		later[1].fn()
		eq(#w.whispered, B.PROMPT_MAX, "the rest of the 20, a minute later")
		local seen, twice = {}, 0
		for _, x in ipairs(w.whispered) do if seen[x.to] then twice = twice + 1 end seen[x.to] = true end
		eq(twice, 0, "nobody twice")
	end)
end)

-- 1.5.9 (the census items left from 1.5.8: clients still on 1.5.4 showed 3 to 8 thousand characters on every
-- server). Fails before: the author's update notice (V3) reached an outdated client only where he clicked.
test("1.5.9 outdated clients: the author's relay client gives each client it serves on an older version than the one he marked as out his update notice (V3), once a day at most, a few each tick, never the up to date, never without a marked release, never in quiet presence", function()
	AsAuthorRelay(function(w)
		local W = ns.Workshop
		local saved = { asked = ns.db.outdatedAsked, released = ns.db.releasedVersion, quiet = ns.QuietPresence }
		local ok, err = pcall(function()
			ns.db.outdatedAsked, ns.QuietPresence = nil, function() return false end
			local R = rawget(ns, "Relay")
			-- What his relay holds: the version each client it serves presented, and when (Relay.Presentations).
			w.presented = { { name = "Old Four", v = "1.5.4", t = w.clock - 60 }, { name = "Old Six", v = "1.5.6", t = w.clock - 120 },
				{ name = "Up Todate", v = ns.VERSION, t = w.clock - 30 }, { name = "Test Build", v = ns.VERSION .. "-test.3", t = w.clock - 30 } }
			R.Presentations = function() return w.presented end
			ns.db.releasedVersion = nil
			eq(W.AskServedOutdated(), 0, "no version marked as out: nobody asked"); eq(#w.whispered, 0)
			ns.db.releasedVersion = ns.VERSION
			eq(W.AskServedOutdated(), 2)
			local asked = AskedTo(w)
			eq(asked[ns.FullName("Old Four")], 1, "the 1.5.4 client"); eq(asked[ns.FullName("Old Six")], 1, "the 1.5.6 one")
			eq(#w.whispered, 2, "never the up to date one, nor a test build")
			eq(w.whispered[1].key:sub(1, 10), "askupdate:", "his usual notice (Workshop.AskUpdate)")
			eq(#w.quieted, 2, "an offline answer kept out of his chat")
			-- Once a day at most, a /reload or a new session too (kept in ns.db.outdatedAsked).
			w.clock = w.clock + W.UPDATE_GAP + 1
			W.Reset()
			eq(W.AskServedOutdated(), 0, "not again the same day"); eq(#w.whispered, 2)
			w.clock = w.clock + W.OUTDATED_EVERY
			eq(W.AskServedOutdated(), 2, "the next day again, while still outdated")
			W.Reset() -- (a new session: its tick free)
			-- A few each tick, the latest word first; never into the places his queue keeps.
			w.whispered, ns.db.outdatedAsked = {}, nil
			w.presented = {}
			for i = 1, 8 do w.presented[i] = { name = ("Old%02d One"):format(i), v = "1.5.4", t = w.clock - i } end
			w.clock = w.clock + W.OUTDATED_TICK
			eq(W.AskServedOutdated(), W.OUTDATED_PER_TICK, "five a tick")
			eq(w.whispered[1].to, ns.FullName("Old01 One"), "the latest word first")
			eq(W.AskServedOutdated(), 0, "nothing more before the next tick")
			w.clock = w.clock + W.OUTDATED_TICK
			eq(W.AskServedOutdated(), 3, "the rest the next tick")
			w.whispered, ns.db.outdatedAsked, w.room = {}, nil, W.OUTDATED_ROOM
			w.clock = w.clock + W.OUTDATED_TICK
			eq(W.AskServedOutdated(), 0, "a busy queue: nothing now"); eq(#w.whispered, 0)
			w.room = nil
			-- Quiet presence: nothing.
			ns.QuietPresence = function() return true end
			eq(W.AskServedOutdated(), 0, "his presence quiet: no whisper gives him away")
		end)
		ns.db.outdatedAsked, ns.db.releasedVersion, ns.QuietPresence = saved.asked, saved.released, saved.quiet
		if not ok then error(err, 0) end
	end)
	-- Any other client, a relay's among them, asks nobody.
	WithBuilds("Other Relay-Realm", function(w)
		w.relays, w.relayOn = { ["Other Relay"] = true }, true
		rawget(ns, "Relay").Presentations = function() return { { name = "Old Four", v = "1.5.4", t = w.clock } } end
		eq(ns.Workshop.AskServedOutdated(), 0); eq(#w.whispered, 0)
	end)
end)

test("1.5.4 modified builds prompt: Comm's door counts a locked client as online while its words reach it (its refused registration among them), and no longer after five minutes", function()
	RelaySetup(function()
		local R, Deliver = Relayed(RELAY)
		R.clock = 1800000000
		local one = "Rep One" .. REALM7
		Deliver("GUILD", one, "H1~1.5.1-onn.12~CAMWOWUS2Realm7PvE~p~~~~R")
		eq(R.Builds.Quarantined(one), true)
		R.clock = R.clock + R.Builds.ONLINE_FOR + 1
		eq(R.Builds.Online(one), false, "its hello is old and nothing of it came since")
		local before = R.Comm.Stats().quarantined
		Deliver("WHISPER", one, "RL~P~RR~Guild One")
		eq(R.Comm.Stats().quarantined, before + 1, "its registration refused at the door")
		eq(R.Builds.Online(one), true, "and it is online")
		R.clock = R.clock + R.Builds.ONLINE_FOR + 1
		eq(R.Builds.Online(one), false, "five minutes on, no longer")
		eq(R.Builds.Online("Nobody Here" .. REALM7), false, "never one without a record")
	end)
end)

test("1.5.4 modified builds wording: the menu line, the person card, a check's line and /oly builds say modified build with the release the version starts from, never the rest of it (it may name its maker); a version with no release in it is Olympus (modified build); the record keeps the whole string", function()
	eq(B.Shown("1.5.1-onn.12"), "1.5.1"); eq(B.Shown("1.5.3-custom"), "1.5.3"); eq(B.Shown("1.2.5.1-x"), "1.2.5.1")
	eq(B.Shown("custom"), nil); eq(B.Shown("?"), nil); eq(B.Shown("1.5"), nil); eq(B.Shown(nil), nil)
	WithBuilds("Tester-Realm", function(w)
		w.hellos["Ann Dark"], w.hellos["Eve Red"] = "?", "?"
		B.Hello("Ann Dark-Realm", "1.5.1-onn.12", w.clock)
		B.Hello("Eve Red-Realm", "custom", w.clock)
		eq(V.Line(V.Status("Ann Dark-Realm")), L.VERSION_LINE_MODIFIED:format("1.5.1"), "the release it was made from")
		eq(V.CardLine("Eve Red-Realm"), L.VERSION_LINE_MODIFIED_ANY, "no release in it: no number at all")
		local text = B.Text()
		assert(text:find("Ann Dark  1.5.1  ", 1, true) and text:find("Eve Red  ?  ", 1, true), text)
		for _, part in ipairs({ "onn", "custom" }) do
			eq(text:find(part, 1, true), nil, "/oly builds never shows " .. part)
			for _, n in ipairs({ "Ann Dark-Realm", "Eve Red-Realm" }) do
				local root = Menu()
				V.MenuLines({ name = n }, root)
				eq(root.Texts():find(part, 1, true), nil, "the menu never shows " .. part)
			end
		end
		eq(B.Modified("Ann Dark-Realm").version, "1.5.1-onn.12", "the record keeps the whole string")
		for _, k in ipairs({ "VERSION_LINE_MODIFIED", "VERSION_LINE_MODIFIED_ANY", "BUILDS_TITLE", "BUILDS_HEAD" }) do
			assert(L[k]:lower():find("modified", 1, true), k .. " says modified, plainly")
		end
	end)
end)

test("1.5.4 modified builds guild: a silent mark never keeps out a guild master's sighting of the same character; on a relay, a reporter's sighting newer than the release a character announced to it locks it again, an older one does not", function()
	WithBuilds("Tester-Realm", function(w)
		w.ranks["Lord Hale-Realm"] = 0
		w.hellos["Ann Dark"] = "1.5.3"
		local t1 = w.clock
		B.Hello("Ann Dark-Realm", "1.5.3", w.clock)
		for i = 0, 2 do
			w.clock = t1 + i * 150 + 10; eq(V.Check("Ann Dark-Realm"), true); w.Run()
			w.clock = t1 + i * 150 + 100; B.Hello("Ann Dark-Realm", "1.5.3", w.clock)
		end
		assert(B.Silent("Ann Dark-Realm"), "the silent mark")
		B.HandleShare("GUILD", "Lord Hale-Realm", Word("Ann Dark-Realm", "1.5.1-onn.12", "h", w.clock, w.clock))
		local e = B.Modified("Ann Dark-Realm")
		assert(e, "the guild master's sighting is kept over the silent mark"); eq(e.by, "Lord Hale-Realm"); eq(e.version, "1.5.1-onn.12")
		assert(B.Silent("Ann Dark-Realm"), "the silent mark still shown")
	end, { rank = 0 })
	WithBuilds("Hildryn Payne-Realm", function(w)
		w.relays, w.relayOn = { ["Hildryn Payne"] = true, ["Max Ran"] = true }, true
		B.Hello("Bob Light-Realm", "1.5.1-onn.12", w.clock)
		eq(B.Quarantined("Bob Light-Realm"), true)
		w.clock = w.clock + 600
		B.Hello("Bob Light-Realm", "1.5.4", w.clock)
		eq(B.Quarantined("Bob Light-Realm"), false, "a release announced to us")
		local released = w.clock
		B.HandleShare("CHANNEL", "Max Ran-Realm", Word("Bob Light-Realm", "1.5.1-onn.12", "h", released - 300, released - 60, ""))
		eq(B.Quarantined("Bob Light-Realm"), false, "a sighting older than the release: ours stands")
		w.clock = w.clock + 600
		B.HandleShare("CHANNEL", "Max Ran-Realm", Word("Bob Light-Realm", "1.5.1-onn.12", "h", released + 300, w.clock, ""))
		eq(B.Quarantined("Bob Light-Realm"), true, "a newer sighting: back on a modified build, locked again")
		eq(B.Modified("Bob Light-Realm").by, "Max Ran-Realm")
	end)
end)
