-- 1.1.6, the Missionary Church of Olympus: the guild log, the evidence, the keepers' ledger, the
-- points and rankings, registrations, transfers, the public view and the top 3.
-- Run alone: luajit tests/run.lua "1.1.6 Church"
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-count%.lua$")) or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local Key = World.Key
local DAY = 86400

local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"

-- Two guilds: Aldric (an Apostle, the desk) and his missionary Mira in Olympus Ember with Wes (a
-- plain member, a witness); Bera (an Apostle) and Vik (a plain member) in Olympus Vale. The Head,
-- the King and the author are offline unless a test brings them in.
local function Cast()
	local w = World.New({ apostles = { A1, A2 } })
	local c = {
		head = w:Client(World.HEAD), king = w:Client(World.KING), author = w:Client(World.AUTHOR),
		a1 = w:Client(A1), a2 = w:Client(A2, { guild = World.GUILD2 }),
		m1 = w:Client("Mira Wells"), m2 = w:Client("Nils Ford"),
		wes = w:Client("Wes Brook"), vik = w:Client("Vik Stone", { guild = World.GUILD2 }),
	}
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Act(c.m1, c.m1.Church.NameMissionary, "Nils Ford")
	c.head.online, c.king.online, c.author.online = false, false, false
	-- (Invites before a naming don't count: the log's events below are some hours after it.)
	w:Run(8 * 3600)
	w:Presence()
	return w, c
end

-- A player joins a guild in this world (no addon): its members' rosters show him.
local function Join(w, guild, name)
	w.members[guild] = w.members[guild] or {}
	table.insert(w.members[guild], name)
	w:RefreshRosters()
end
local function Leave(w, guild, name)
	local list = w.members[guild] or {}
	for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
	w:RefreshRosters()
end
-- Every client's tick, then `seconds` on the clock (seen-check answers, closes).
local function Settle(w, seconds)
	w:Tick()
	w:Run(seconds or 2)
	w:Tick()
	w:Run(2)
end
local function StateOf(w, keeper, recruit, by)
	return w:As(keeper, keeper.Count.StateOf, Key(recruit) .. ":" .. Key(by))
end
local function Rec(w, keeper, recruit, by)
	return w:As(keeper, keeper.Count.Led).r[Key(recruit) .. ":" .. Key(by)]
end

test("1.1.6 Church: the guild log: an invite by a missionary then the join is a pair; the recruiter's own report is pending, a guildmate's confirms it", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "New Guy", 3)
	w:LogEvent(World.GUILD, "join", "New Guy", nil, 2)
	Join(w, World.GUILD, "New Guy")
	-- Mira's own read: a pair reported to the keepers online (Aldric, Bera), pending.
	eq(w:ReadLog(c.m1), true)
	eq(#w:Sent(c.m1, "NV", "WHISPER", "w"), 2, "to each keeper heard online")
	eq(StateOf(w, c.a1, "New Guy", "Mira Wells"), "pending")
	eq(Rec(w, c.a1, "New Guy", "Mira Wells").s, 1, "the recruiter's own report")
	-- Wes's client read it too (Mira's presence over GUILD made it worth reading): confirmed.
	eq(w:ReadLog(c.wes), true)
	eq(StateOf(w, c.a1, "New Guy", "Mira Wells"), "credited")
	eq(StateOf(w, c.a2, "New Guy", "Mira Wells"), "credited", "every keeper took it")
	eq(Rec(w, c.a1, "New Guy", "Mira Wells").ws[1], Key("Wes Brook"))
	-- Read again: nothing sent twice; the ledger has one record.
	w:ClearSent()
	w:Run(61)
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	-- (1.2.1: the keepers' receipts are NV too, NV k.)
	eq(#w:Sent(nil, "NV", nil, "w"), 0, "duplicates are not sent again")
	local n = 0
	for _ in pairs(w:As(c.a1, c.a1.Count.Led).r) do n = n + 1 end
	eq(n, 1)
end)

test("1.1.6 Church: not a pair: a join without a Church person's invite, a join past 48 hours, a join before the invite", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Wes Brook", "Plain Recruit", 5)
	w:LogEvent(World.GUILD, "join", "Plain Recruit", nil, 4)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Slow Joiner", 60)
	w:LogEvent(World.GUILD, "join", "Slow Joiner", nil, 2)
	w:LogEvent(World.GUILD, "join", "Early Bird", nil, 10)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Early Bird", 5)
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	eq(#w:Sent(nil, "NV", "WHISPER", "w"), 0)
	eq(next(w:As(c.a1, c.a1.Count.Led).r), nil)
end)

test("1.1.6 Church: evidence the keeper refuses: a recruiter with no place, invited before his naming, a non-Olympus guild, bad times, over budget, net-off", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	local function Ev(inviter, invitee, guild, ti, tj)
		return ("NV~1~w~%s~%s~%s~%s~%s"):format(inviter, invitee, guild, B(ti), B(tj))
	end
	local function Take(from, text) return select(2, w:As(c.a1, c.a1.Count.TakeEvidence, from, text)) end
	eq(Take("Wes Brook-Realm", Ev("Wes Brook-Realm", "Some One-Realm", World.GUILD, hour - 2, hour - 1)), "recruiter")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour - 30, hour - 29)), "recruiter", "before his naming")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", "Horde Rivals", hour, hour)), "guild")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour, hour + 3)), "times", "a join in the future")
	eq(Take("Wes Brook-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour, hour - 5)), "times", "a join before the invite")
	eq(Take("Some One-Realm", Ev("Mira Wells-Realm", "Some One-Realm", World.GUILD, hour, hour)), "recruit", "the recruit himself is no source")
	-- A linked alt's report is the recruiter's: it confirms nothing.
	w.alts[Key("Mira Wells")] = { "Mira Alt-Realm" }
	eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Alt-Realm", Ev("Mira Wells-Realm", "Alt Pal-Realm", World.GUILD, hour, hour)), true)
	eq(StateOf(w, c.a1, "Alt Pal", "Mira Wells"), "pending")
	-- Over budget: past VERIFIED_HOUR from one sender, refused for the hour (1.2.1: every report counts
	-- against the larger budget; one only the recruiter's alt stands behind against EVIDENCE_HOUR too).
	for i = 1, c.a1.Count.VERIFIED_HOUR do w:As(c.a1, c.a1.Count.TakeEvidence, "Spam Mer-Realm", "NV~1~q~" .. i) end
	eq(Take("Spam Mer-Realm", Ev("Mira Wells-Realm", "Late Pal-Realm", World.GUILD, hour, hour)), "budget")
	local function Pal(i) return "Alt Pal" .. string.char(97 + i % 26, 97 + math.floor(i / 26)) .. "-Realm" end
	for i = 2, c.a1.Count.EVIDENCE_HOUR do eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Alt-Realm", Ev("Mira Wells-Realm", Pal(i), World.GUILD, hour, hour)), true) end
	eq(Take("Mira Alt-Realm", Ev("Mira Wells-Realm", "Alt Palz-Realm", World.GUILD, hour, hour)), "budget")
	-- A net-off sender.
	w.off[Key("Off Man")] = { off = true }
	eq(Take("Off Man-Realm", Ev("Mira Wells-Realm", "Off Pal-Realm", World.GUILD, hour, hour)), "netoff")
	-- Not a keeper: a plain member's client takes no evidence.
	eq(select(2, w:As(c.wes, c.wes.Count.TakeEvidence, "Wes Brook-Realm", Ev("Mira Wells-Realm", "X Y-Realm", World.GUILD, hour, hour))), "not keeper")
end)

test("1.1.6 Church: new to Olympus: a seen-check from another Olympus guild within 90 days makes a transfer, never credited", function()
	local w, c = Cast()
	-- Mover was in Olympus Vale until 20 days ago (Vik's roster memory saw him there).
	Join(w, World.GUILD2, "Mover Man")
	w:Tick()
	w:Run(DAY)
	Leave(w, World.GUILD2, "Mover Man")
	w:Run(20 * DAY)
	w:Presence()
	-- Mira invites him into Olympus Ember; Wes confirms the join.
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Mover Man", 3)
	w:LogEvent(World.GUILD, "join", "Mover Man", nil, 2)
	Join(w, World.GUILD, "Mover Man")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	eq(StateOf(w, c.a1, "Mover Man", "Mira Wells"), "credited", "confirmed, until the check")
	-- The desk asks the channel; Vik's client knew him in another Olympus guild.
	Settle(w, 700)
	eq(#w:Sent(c.a1, "NS", "CHANNEL", "q") >= 1, true, "the desk's seen-check")
	eq(#w:Sent(c.vik, "NS", "WHISPER", "a") >= 1, true, "the answer from roster memory")
	eq(StateOf(w, c.a1, "Mover Man", "Mira Wells"), "transfer")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
	-- A brand-new recruit: the same check makes no transfer, and a guildmate's answer confirms him.
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Brand New", 3)
	w:LogEvent(World.GUILD, "join", "Brand New", nil, 2)
	Join(w, World.GUILD, "Brand New")
	w:Tick()
	w:ReadLog(c.m1)
	eq(StateOf(w, c.a1, "Brand New", "Mira Wells"), "pending")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Brand New", "Mira Wells"), "credited", "Wes's client read the same pair in the guild's log")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 10)
end)

test("1.1.6 Church: alts are never credited: the recruiter's own linked character, or a recruit whose linked character was in Olympus", function()
	local w, c = Cast()
	w.alts[Key("Mira Wells")] = { "Mira Second-Realm" }
	w.alts[Key("Mira Second")] = { "Mira Wells-Realm" }
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Mira Second", 3)
	w:LogEvent(World.GUILD, "join", "Mira Second", nil, 2)
	-- Old Main played in Olympus Ember last month; his new character joins through Mira.
	Join(w, World.GUILD, "Old Main")
	w:Tick()
	w:Run(DAY)
	Leave(w, World.GUILD, "Old Main")
	w:Run(20 * DAY)
	w:Presence()
	w.alts[Key("New Alt")] = { "Old Main-Realm" }
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "New Alt", 3)
	w:LogEvent(World.GUILD, "join", "New Alt", nil, 2)
	Join(w, World.GUILD, "Mira Second"); Join(w, World.GUILD, "New Alt")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	eq(StateOf(w, c.a1, "Mira Second", "Mira Wells"), "alt", "her own other character")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "New Alt", "Mira Wells"), "alt", "a linked character of his was in Olympus")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
end)

test("1.1.6 Church: a seen-check only from a keeper, answered only with a fact, once per client, at most eight answers", function()
	local w, c = Cast()
	Join(w, World.GUILD, "Known Guy")
	w:Tick()
	-- From a plain member: no answer.
	eq(select(2, w:As(c.wes, c.wes.Count.TakeCheck, "Vik Stone-Realm", "NS~1~q~1~Known Guy~j")), "keeper")
	-- From the desk, about a name nobody knows: no answer.
	eq(select(2, w:As(c.wes, c.wes.Count.TakeCheck, A1, "NS~1~q~1~Never Seen~j")), "unknown")
	-- Unknown check ids, a second answer from one client, more than eight: dropped.
	eq(select(2, w:As(c.a1, c.a1.Count.TakeAnswer, "Wes Brook-Realm", "NS~1~a~zz~Olympus Ember~1~1~1")), "no check")
	local expected = { [Key(c.wes.name)] = "roster" }
	local responders = {}
	for i = 2, 8 do
		responders[i] = w:Client("Answer Er" .. ("x"):rep(i))
		expected[responders[i].key] = "roster"
	end
	local checks = w:As(c.a1, c.a1.Count.OpenChecks)
	checks.q1 = { cid = "q1", rid = "x:y", why = "j", sent = w.clock, answers = {}, from = {}, expected = expected }
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, "Wes Brook-Realm", "NS~1~a~q1~Olympus Ember~1~1~1"), true)
	eq(select(2, w:As(c.a1, c.a1.Count.TakeAnswer, "Wes Brook-Realm", "NS~1~a~q1~Olympus Ember~1~1~1")), "twice")
	for i = 2, 8 do w:As(c.a1, c.a1.Count.TakeAnswer, responders[i].name, "NS~1~a~q1~Olympus Ember~1~1~1") end
	eq(checks.q1, nil, "closed at eight answers")
	-- The King's client answers no check.
	eq(select(2, w:As(c.king, c.king.Count.TakeCheck, A1, "NS~1~q~2~Known Guy~j")), "king")
end)

local function SeenCheck(w, c)
	local id = Key("Checked Recruit") .. ":" .. Key("Mira Wells")
	w:As(c.a1, c.a1.Count.MergeIn, id, { n = "Checked Recruit", bn = "Mira Wells", kind = "g", tc = w.clock }, false)
	w:As(c.a1, c.a1.Count.QueueCheck, id, "r")
	w:As(c.a1, c.a1.Count.DeskTick, w.clock)
	local checks = w:As(c.a1, c.a1.Count.OpenChecks)
	local cid, check = next(checks)
	assert(cid and check, "the real desk opened a check")
	local day = ns.Codec.Base36(math.floor(w.clock / DAY))
	return ("NS~1~a~%s~%s~%s~%s~1"):format(cid, World.GUILD2, day, day), check
end

test("Church seen-check recipients: an outsider knowing the broadcast id cannot consume answers, and a member arriving after the query was not asked", function()
	local w, c = Cast()
	local outsider = w:Client("Uninvited Sender", { guild = false })
	local text, check = SeenCheck(w, c)
	eq(w:As(c.a1, c.a1.Count.Receive, "NS", "WHISPER", outsider.name, text), false, "an open id grants no reply authority")
	eq(#check.answers, 0); eq(check.from[outsider.key], nil)
	local late = w:Client("Late Responder")
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, late.name, text), false, "new membership does not add someone to an outstanding query")
	eq(#check.answers, 0)
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, c.wes.name, text), true, "an expected ordinary roster member may answer")
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, c.a2.name, text), true, "the known signed keeper of another guild may relay its roster facts")
	eq(#check.answers, 2)
end)

test("Church seen-check recipients: roster membership and signed keeper or council authority are rechecked when the answer arrives", function()
	local w, c = Cast()
	local council = w:Client(World.COUNCILLOR)
	w:Presence()
	local text, check = SeenCheck(w, c)
	c.wes.guild = nil
	w:RefreshRosters()
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, c.wes.name, text), false, "a departed guildmate loses its expected reply authority")
	w:SignedList({ A1 }, false, w.clock + 1)
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, c.a2.name, text), false, "a revoked keeper of another guild cannot use an old query")
	eq(#check.answers, 0)
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, council.name, text), true, "a known signed councillor remains an expected source")
	w.council[council.key] = nil
	w:As(c.a1, c.a1.Count.CloseCheck, check)
	local another, nextCheck = SeenCheck(w, c)
	eq(w:As(c.a1, c.a1.Count.TakeAnswer, council.name, another), true, "after losing council rank, an actual roster member may still answer a new query")
	eq(#nextCheck.answers, 1)
end)

test("1.1.6 Church: registrations: counted when the player arrives in an Olympus guild within 14 days; not for one already in Olympus; expired after", function()
	local w, c = Cast()
	-- Mira registers a player she brought; another guild's officer invites him (no Church person).
	eq(w:Act(c.m1, c.m1.Count.Register, "Far Guy"), true)
	eq(StateOf(w, c.a1, "Far Guy", "Mira Wells"), "open")
	w:Run(DAY)
	Join(w, World.GUILD2, "Far Guy")
	w:Tick()
	w:Run(DAY * 2)
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Far Guy", "Mira Wells"), "credited", "Vik's client places him in Olympus Vale since the registration")
	eq(Rec(w, c.a1, "Far Guy", "Mira Wells").g, World.GUILD2)
	-- Already in Olympus when registered: refused at the check.
	Join(w, World.GUILD2, "Old Hand")
	w:Tick()
	w:Run(10 * DAY)
	w:Presence()
	w:Act(c.m1, c.m1.Count.Register, "Old Hand")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Old Hand", "Mira Wells"), "transfer")
	-- Nobody shows up for 14 days: expired, never counted.
	w:Act(c.m1, c.m1.Count.Register, "No Show")
	w:Run(15 * DAY)
	w:Presence()
	eq(StateOf(w, c.a1, "No Show", "Mira Wells"), "expired")
	-- Limits: fifteen open at once.
	for i = 1, 16 do w:As(c.m1, c.m1.Count.Register, "Reg Number" .. ("q"):rep(i)) end
	eq(w:Printed(c.m1), ns.L.CHURCH_REG_FULL:format(15), "the sixteenth")
	-- Withdrawn by its registrant.
	w:Act(c.m1, c.m1.Count.Withdraw, "Reg Numberq")
	eq(StateOf(w, c.a1, "Reg Numberq", "Mira Wells"), "withdrawn")
	-- A plain member registers nothing.
	eq(w:Act(c.wes, c.wes.Count.Register, "Some Body"), nil)
	eq(w:Printed(c.wes), ns.L.CHURCH_NO_RIGHTS)
end)

test("1.1.6 Church: exclusive: one recruit counts for one person only, the earliest invite or registration", function()
	local w, c = Cast()
	-- Nils registers Dual Guy first; Mira's invite comes later: Nils's.
	w:Act(c.m2, c.m2.Count.Register, "Dual Guy")
	w:Run(3600 * 3)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Dual Guy", 1)
	w:LogEvent(World.GUILD, "join", "Dual Guy", nil, 0)
	Join(w, World.GUILD, "Dual Guy")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Dual Guy", "Nils Ford"), "credited")
	eq(StateOf(w, c.a1, "Dual Guy", "Mira Wells"), "taken")
	-- An invite earlier than a registration wins over it.
	w:Run(120)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "First Come", 2)
	w:LogEvent(World.GUILD, "join", "First Come", nil, 1)
	Join(w, World.GUILD, "First Come")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	w:Act(c.m2, c.m2.Count.Register, "First Come")
	eq(StateOf(w, c.a1, "First Come", "Mira Wells"), "credited")
	eq(StateOf(w, c.a1, "First Come", "Nils Ford"), nil, "refused at once: already credited")
end)

test("1.1.6 Church: points: own work counts most: a missionary with five recruits outscores his Apostle with two, and the one he named the same way", function()
	local w, c = Cast()
	local K = c.a1
	local now = w.clock
	local n = 0
	-- Confirmed records straight into Aldric's ledger (what the log and the witnesses make).
	local function Recruits(by, count)
		for _ = 1, count do
			n = n + 1
			local recruit = "Recruit " .. string.char(65 + math.floor(n / 26)) .. string.char(97 + n % 26)
			w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = ns.ShortName(by), g = World.GUILD, kind = "i",
				tc = now - 7200, tj = now - 3600, ws = { "wes brook" }, c = 1 }, false)
		end
	end
	Recruits(A1, 2)
	Recruits("Mira Wells", 5)
	local score, own, share, levels = w:As(K, K.Count.Score, Key(A1), "a")
	eq(own, 20); eq(share, 12.5); eq(score, 32.5); eq(levels[1], 12.5)
	local mScore, mOwn = w:As(K, K.Count.Score, Key("Mira Wells"), "a")
	eq(mOwn, 50); eq(mScore, 50, "no one under Mira has points yet")
	eq(mScore > score, true, "the missionary below outscores the Apostle above")
	-- Between a missionary and the one he named: Nils with 5, Mira with 2 of her own.
	w:As(K, K.Count.Led).r = {}
	K.Count.Changed()
	Recruits("Mira Wells", 2)
	Recruits("Nils Ford", 5)
	local nScore = w:As(K, K.Count.Score, Key("Nils Ford"), "a")
	local mScore2, mOwn2, mShare2 = w:As(K, K.Count.Score, Key("Mira Wells"), "a")
	eq(nScore, 50); eq(mOwn2, 20); eq(mShare2, 12.5); eq(nScore > mScore2, true)
	-- Aldric's network score: 25% of Mira's own, 10% of Nils's (level 2), nothing compounded.
	local aScore, aOwn, aShare, aLevels, aNet = w:As(K, K.Count.Score, Key(A1), "a")
	eq(aOwn, 0); eq(aLevels[1], 5); eq(aLevels[2], 5); eq(aShare, 10); eq(aScore, 10); eq(aNet, 7)
	-- Three levels at most: a fourth level's points give the Apostle nothing.
	local lv3, lv4 = w:Client("Third Level"), w:Client("Fourth Level")
	w:Act(c.m2, c.m2.Church.NameMissionary, "Third Level")
	w:Act(lv3, lv3.Church.NameMissionary, "Fourth Level")
	Recruits("Third Level", 2)
	Recruits("Fourth Level", 10)
	local _, _, _, levels4 = w:As(K, K.Count.Score, Key(A1), "a")
	eq(levels4[3], 1, "5% of the third level's 20")
	eq(w:As(K, K.Count.Score, Key(A1), "a"), 11, "the fourth level's 100 count nothing for the Apostle")
	_ = lv4
end)

test("1.1.6 Church: still in after 7 days: +5 then; one who left before keeps the 10, never the 5; the windows", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Stay Er", 3)
	w:LogEvent(World.GUILD, "join", "Stay Er", nil, 2)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Quit Ter", 3)
	w:LogEvent(World.GUILD, "join", "Quit Ter", nil, 2)
	Join(w, World.GUILD, "Stay Er"); Join(w, World.GUILD, "Quit Ter")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	Settle(w, 700)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 20)
	w:Run(3 * DAY)
	Leave(w, World.GUILD, "Quit Ter")
	w:Tick()
	-- Seven days after the join: the desk asks again (three tries for one nobody places now).
	for _ = 1, 7 do
		w:Run(DAY)
		w:Presence()
		Settle(w, 700)
	end
	eq(Rec(w, c.a1, "Stay Er", "Mira Wells").y, 1)
	eq(Rec(w, c.a1, "Quit Ter", "Mira Wells").y, 0, "left before: no 5")
	local own = w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a")
	eq(own.points, 25); eq(own.joins, 2); eq(own.stays, 1)
	-- This week holds the +5 (dated at join + 7 days); a window 30 days on holds nothing.
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "m").points, 25)
	w:Run(31 * DAY)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "m").points, 0)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 25, "all time keeps them")
end)

test("1.1.6 Church: the numbers follow the person across Olympus guilds", function()
	local w, c = Cast()
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Ember Kid", 3)
	w:LogEvent(World.GUILD, "join", "Ember Kid", nil, 2)
	Join(w, World.GUILD, "Ember Kid")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	-- Mira moves to Olympus Vale and recruits there; Vik witnesses.
	c.m1.guild = World.GUILD2
	w:RefreshRosters()
	w:Run(120)
	w:Presence()
	w:LogEvent(World.GUILD2, "invite", "Mira Wells", "Vale Kid", 1)
	w:LogEvent(World.GUILD2, "join", "Vale Kid", nil, 0)
	Join(w, World.GUILD2, "Vale Kid")
	w:Tick()
	w:ReadLog(c.m1); w:ReadLog(c.vik)
	local own = w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a")
	eq(own.joins, 2); eq(own.points, 20)
	eq(own.guilds[World.GUILD].joins, 1); eq(own.guilds[World.GUILD2].joins, 1)
end)

test("1.1.6 Church: the rankings: Apostles by network score, missionaries by own plus shares; the numbers only to the audience; a person's detail to whom D4 says", function()
	local w, c = Cast()
	local K = c.a1
	local function Give(by, recruit)
		w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = ns.ShortName(by), g = World.GUILD, kind = "i",
			tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" }, c = 1 }, false)
	end
	Give("Mira Wells", "R Aa"); Give("Mira Wells", "R Ab"); Give("Nils Ford", "R Ac"); Give(A2, "R Ad")
	local apostles = w:As(K, K.Count.Ranking, "a", "w")
	eq(#apostles, 3, "the Head is one of the Apostles")
	eq(apostles[1].key, Key(A2)); eq(apostles[1].score, 10)
	eq(apostles[2].key, Key(A1)); eq(apostles[2].score, 6, "25% of Mira's 20 + 10% of Nils's 10"); eq(apostles[2].net, 3)
	eq(apostles[3].key, Key(World.HEAD)); eq(apostles[3].score, 0)
	local missionaries = w:As(K, K.Count.Ranking, "m", "w")
	eq(missionaries[1].key, Key("Mira Wells")); eq(missionaries[1].score, 22.5); eq(missionaries[2].score, 10)
	-- A missionary asks the desk; the rows come back by whisper, his own breakdown with them.
	w:ClearSent()
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "w"), true)
	w:Run(30)
	local rows = w:As(c.m2, c.m2.Count.RankingView, "m", "w")
	eq(#rows, 2); eq(rows[1].score, 22.5); eq(rows[1].name, "Mira Wells")
	-- A plain member's ask is refused.
	eq(select(2, w:As(K, K.Count.Answer, "Wes Brook-Realm", "m", "w")), "audience")
	-- Detail: the person himself, the Head, the Apostles, the council, the King, the author; not another missionary.
	eq(w:As(K, K.Count.MaySeeDetail, "Nils Ford-Realm", "Mira Wells-Realm"), false)
	eq(w:As(K, K.Count.MaySeeDetail, "Mira Wells-Realm", "Mira Wells-Realm"), true)
	eq(w:As(K, K.Count.MaySeeDetail, A2, "Mira Wells-Realm"), true)
	eq(w:As(K, K.Count.MaySeeDetail, World.COUNCILLOR, "Mira Wells-Realm"), true)
	eq(w:As(K, K.Count.MaySeeDetail, "Wes Brook-Realm", "Mira Wells-Realm"), false)
	eq(select(2, w:As(K, K.Count.Answer, "Nils Ford-Realm", "p", "w", "Mira Wells")), "detail")
	w:As(c.m1, c.m1.Count.Ask, "me", "a")
	w:Run(30)
	local lines = w:As(c.m1, c.m1.Count.DetailView, "Mira Wells-Realm", "a")
	eq(lines[1][1], "s"); eq(lines[1][2], 20); eq(lines[1][3], 2.5, "her own breakdown: own 20, level 1 2.5")
end)

test("1.1.6 Church: the public view: nothing while closed; switch requires a publisher; only rows people chose to show", function()
	local w, c = Cast()
	c.author.online = true
	local K = c.a1
	w:As(K, K.Count.MergeIn, "r aa:mira wells", { n = "R Aa", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:As(K, K.Count.MergeIn, "r ab:nils ford", { n = "R Ab", bn = "Nils Ford", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:As(c.author, c.author.Count.MergeIn, "r aa:mira wells", { n = "R Aa", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:Presence()
	w:Tick()
	eq(#w:Sent(nil, "NR", "CHANNEL", "p"), 0, "closed: nothing broadcast")
	-- Somebody else's switch is refused.
	w:As(c.wes, c.wes.Church.Receive, "CHANNEL", A1, "NB~1~s~1~" .. ns.Codec.Base36(w.clock))
	eq((w:As(c.wes, c.wes.Church.Public)), false)
	-- The author opens it; Mira shows her row, Nils doesn't (off by default).
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	eq((w:As(c.wes, c.wes.Church.Public)), true)
	w:Tick()
	local rows = w:Sent(nil, "NR", "CHANNEL", "p")
	eq(#rows, 1, "one opted-in row")
	assert(rows[1].msg:find("Mira Wells", 1, true))
	local v = w:As(c.wes, c.wes.Count.PublicView)
	eq(v.m[1].name, "Mira Wells")
	eq(v.m[2], nil, "Nils's row never left the desk")
	-- Closing: every member drops it (in the same second too: a newer word).
	w:Act(c.author, c.author.Church.SetPublic, false)
	eq(w:As(c.wes, c.wes.Count.PublicView), nil)
end)

test("1.1.6 Church: the top 3 of each ranking: from the Head's, the King's or the author's client only, opted-in people, while the ranking is open", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	local A = c.author
	for i, by in ipairs({ "Mira Wells", "Nils Ford" }) do
		for j = 1, i do
			w:As(A, A.Count.MergeIn, "r " .. i .. j .. ":" .. Key(by), { n = "R B" .. i .. j, bn = by, g = World.GUILD, kind = "i",
				tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
		end
	end
	eq(w:As(c.wes, c.wes.Church.Top3), nil, "nothing while closed")
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.m2, c.m2.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick({ c.author })
	local top = w:As(c.wes, c.wes.Church.Top3)
	eq(top.missionaries[1], "Nils Ford"); eq(top.missionaries[2], "Mira Wells")
	eq(#top.apostles, 0, "no Apostle chose to show his row")
	-- From an Apostle's client (a keeper, not a root): refused.
	local forged = "NR~1~t~" .. ns.Codec.Base36(w.clock + 5) .. "~Aldric Vane~Mira Wells"
	eq(select(2, w:As(c.wes, c.wes.Count.TakeTop, A1, forged)), "root")
	eq(w:As(c.wes, c.wes.Church.Top3).missionaries[1], "Nils Ford")
	-- From the King's: taken.
	eq(w:As(c.wes, c.wes.Count.TakeTop, World.KING, forged), true)
	eq(w:As(c.wes, c.wes.Church.Top3).apostles[1], "Aldric Vane")
end)

test("1.1.6 Church: the outbox: evidence waits while no keeper is online, goes on the first keeper's presence, is dropped after 7 days", function()
	local w, c = Cast()
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Quiet Guy", 3)
	w:LogEvent(World.GUILD, "join", "Quiet Guy", nil, 2)
	w:Tick({ c.m1 })
	w:ReadLog(c.m1)
	eq(#w:As(c.m1, function() return c.m1.Count.Led and c.m1.Church.Store().out end), 1, "held")
	c.a1.online = true
	w:Presence({ c.a1 })
	w:Run(15)
	eq(#w:As(c.m1, function() return c.m1.Church.Store().out end), 0)
	eq(StateOf(w, c.a1, "Quiet Guy", "Mira Wells"), "pending")
	-- Past 7 days in the outbox: dropped.
	c.a1.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Stale Guy", 3)
	w:LogEvent(World.GUILD, "join", "Stale Guy", nil, 2)
	w:Run(61)
	w:ReadLog(c.m1)
	w:Run(8 * DAY)
	c.a1.online = true
	w:Presence({ c.a1 })
	w:Run(15)
	eq(StateOf(w, c.a1, "Stale Guy", "Mira Wells"), nil)
end)

test("1.1.6 Church: the keepers' ledger: a keeper catches up from another; the merge is the same in any order and taken twice changes nothing", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	local e1 = ("NV~1~w~Mira Wells-Realm~Merge Guy-Realm~%s~%s~%s"):format(World.GUILD, B(hour - 2), B(hour - 1))
	local e2 = ("NV~1~w~Mira Wells-Realm~Merge Guy-Realm~%s~%s~%s"):format(World.GUILD, B(hour - 3), B(hour - 1))
	Join(w, World.GUILD, "Merge Guy") -- (1.2.1: a guildmate confirms only a recruit Aldric's roster shows)
	w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Wells-Realm", e1)
	w:As(c.a1, c.a1.Count.TakeEvidence, "Wes Brook-Realm", e2)
	-- (1.2.1: Bera, in Olympus Vale, can't vouch for Wes of Olympus Ember: she takes his word from Aldric's
	-- ledger, which did, Count.Push.)
	eq(select(2, w:As(c.a2, c.a2.Count.TakeEvidence, "Wes Brook-Realm", e2)), "unverified")
	w:As(c.a2, c.a2.Count.TakeEvidence, "Mira Wells-Realm", e1)
	w:As(c.a2, c.a2.Count.TakeEvidence, "Mira Wells-Realm", e1)
	w:Flush()
	local r1, r2 = Rec(w, c.a1, "Merge Guy", "Mira Wells"), Rec(w, c.a2, "Merge Guy", "Mira Wells")
	eq(r1.tc, r2.tc); eq(r1.tc, (hour - 3) * 3600, "the earliest invite"); eq(r1.s, r2.s); eq(r1.ws[1], r2.ws[1])
	-- The Head comes online with nothing: he catches up from the desk.
	c.head.online = true
	w:Presence()
	eq(w:As(c.head, c.head.Count.CatchUp, true), true)
	w:Run(30)
	local r3 = Rec(w, c.head, "Merge Guy", "Mira Wells")
	eq(r3 and r3.tc, r1.tc)
	eq(w:As(c.head, c.head.Count.StateOf, Key("Merge Guy") .. ":" .. Key("Mira Wells")), "credited")
	-- A line from a non-keeper is refused.
	local line = w:As(c.a1, c.a1.Count.RecordLine, "x", r1)
	eq(select(2, w:As(c.head, c.head.Count.TakeLine, "Wes Brook-Realm", line)), "relay")
end)

test("global Church ledger: signed council preserves verified rankings after the source Apostle goes offline: another council client recovers them; a keeper takes none of them from a council relay (1.2.5.1)", function()
	local w, c = Cast()
	local council = w:Client(World.COUNCILLOR)
	local other = w:Client("Dela Moss-Realm")
	c.a2.online = false
	w:Presence({ c.a1, council, other })
	w:Run(30) -- (the book, from the desk: Church.TakePresence asks a keeper whose book differs)
	other.online = false -- (away while the record goes out)
	local id = Key("Relay Recruit") .. ":" .. Key("Mira Wells")
	local rec = { n = "Relay Recruit", bn = "Mira Wells", g = World.GUILD, kind = "i",
		tc = w.clock - 7200, tj = w.clock - 3600, ws = { Key("Wes Brook") }, c = 1 }
	eq(w:As(c.a1, c.a1.Count.MergeIn, id, rec, true), true)
	w:Run(20)
	assert(Rec(w, council, "Relay Recruit", "Mira Wells"), "signed council retained the verified ledger line")
	eq(Rec(w, other, "Relay Recruit", "Mira Wells"), nil)

	-- The only Apostle holding the record leaves. Another council client, with no keeper online,
	-- recovers it from the council relay, not waiting for the original observer to return.
	c.a1.online = false
	other.online = true
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence({ council, other })
	eq(w:As(other, other.Count.CatchUp, true), true)
	w:Run(30)
	assert(Rec(w, other, "Relay Recruit", "Mira Wells"), "late council client recovered it while the source was offline")
	local found
	for _, row in ipairs((w:As(other, other.Count.RankingView, "m", "a"))) do
		if row.key == Key("Mira Wells") then found = row break end
	end
	assert(found and found.joins == 1, "its page, with no keeper online, shows the verified recruit")

	-- A keeper takes no ledger line from a council relay: the author's client asks it for no catch-up,
	-- and the council's record line changes nothing there. (Changed from a test that had the author
	-- recover the record from the council relay: the lead restored the 1.2.5.1 rule, 2026-10-19.)
	c.author.online = true
	w:Presence({ council, other, c.author })
	eq(w:As(c.author, c.author.Count.CatchUp, true), false, "no keeper online to ask")
	local line = w:As(council, council.Count.RecordLine, id, Rec(w, council, "Relay Recruit", "Mira Wells"))
	eq(w:As(c.author, c.author.Count.TakeLine, World.COUNCILLOR, line), false)
	eq(Rec(w, c.author, "Relay Recruit", "Mira Wells"), nil, "not from a council relay")
end)

test("1.1.6 Church: reading the log: never in combat, at most every minute, drawn among guildmates, never on the King's client; the event registered once, on first use", function()
	local w, c = Cast()
	-- ChatRooms independently registers CHAT_MSG_GUILD. Count only this module's log event;
	-- Cast has already run eight hours, so test load on a genuinely fresh world.
	local function LogRegistrations(cl)
		local n = 0
		for _, event in ipairs(cl.registered) do if event == "GUILD_EVENT_LOG_UPDATE" then n = n + 1 end end
		return n
	end
	local fresh = World.New({ head = false }):Client("Fresh Witness")
	eq(LogRegistrations(fresh), 0, "no log event registered at load")
	c.m1.combat = true
	eq(select(2, w:As(c.m1, c.m1.Count.Read)), "combat")
	c.m1.combat = false
	eq(w:As(c.m1, c.m1.Count.Read), true)
	eq(select(2, w:As(c.m1, c.m1.Count.Read)), "gap")
	w:Run(61)
	eq(w:As(c.m1, c.m1.Count.Read), true)
	eq(LogRegistrations(c.m1), 1, "log event registered exactly once, independently of chat's event")
	eq(c.m1.queries, 2)
	eq(select(2, w:As(c.king, c.king.Count.Read)), "king")
	-- A plain member reads only where a Church person was heard over GUILD, and then with a chance
	-- of 2 / his guild's addon users.
	local lone = w:Client("Lone Wolf", { guild = "Olympus Lone" })
	eq(w:As(lone, lone.Count.MaybeRead, w.clock + 400), false, "no Church person heard in his guild")
	c.wes.peers = 20
	c.wes.Count.chance = function() return 0.5 end
	eq(w:As(c.wes, c.wes.Count.MaybeRead, w.clock + 400), false, "0.5 > 2/20: not drawn")
	c.wes.Count.chance = function() return 0.05 end
	eq(w:As(c.wes, c.wes.Count.MaybeRead, w.clock + 800), true, "drawn")
	-- The fill: a correspondent's own client counts its guild's joins and leaves (never sent).
	w:Act(c.head, c.head.Church.NameCorrespondent, "Wes Brook", World.GUILD)
	w:LogEvent(World.GUILD, "join", "Filler One", nil, 1)
	w:LogEvent(World.GUILD, "quit", "Filler Two", nil, 1)
	w:Run(61)
	w:ClearSent()
	w:ReadLog(c.wes)
	local loc = w:As(c.wes, c.wes.Count.Local)
	eq(loc.joins >= 1, true); eq(loc.leaves, 1)
	eq(#w:Sent(c.wes, "NV"), 0, "the fill stays on his client")
end)

test("1.1.6 Church: saved data: a malformed ledger or book is dropped at load; the roster memory is bounded", function()
	local w = World.New({ apostles = { A1 } })
	local rdb = { church = { led = { v = 1, r = { ["x|y"] = { n = "Bad|Name", tc = "soon" } }, p = {}, from = {} },
		book = { v = 1, p = { bad = { role = "M", n = 7, at = "x" } }, x = {}, c = {}, cx = {} } } }
	local cl = w:Client("Saved One", { rdb = rdb })
	w:As(cl, cl.Church.CheckSaved)
	w:As(cl, cl.Count.CheckSaved)
	eq(next(rdb.church), nil, "a value with an escape code: the whole store goes")
	local rdb2 = { church = { led = { v = 1, r = { ["x:y"] = { n = "Fine Name", tc = "soon" } }, p = {}, from = {} },
		book = { v = 1, p = { bad = { role = "M", n = "Who Ever-Realm", at = "x" } }, x = {}, c = {}, cx = {} } } }
	local cl2 = w:Client("Saved Two", { rdb = rdb2 })
	w:As(cl2, cl2.Church.CheckSaved)
	w:As(cl2, cl2.Count.CheckSaved)
	-- (1.2.1: the malformed record goes, the ledger itself stays for its good ones.)
	eq(next(rdb2.church.led.r), nil); eq(rdb2.church.book, nil)
	-- A real ledger and book survive the load's check whole (their keys and lines carry no escape code).
	local w3, c3 = Cast()
	w3:LogEvent(World.GUILD, "invite", "Mira Wells", "Kept Guy", 3)
	w3:LogEvent(World.GUILD, "join", "Kept Guy", nil, 2)
	Join(w3, World.GUILD, "Kept Guy")
	w3:ReadLog(c3.m1); w3:ReadLog(c3.wes)
	local store = w3:As(c3.a1, c3.a1.Church.Store)
	w3:As(c3.a1, c3.a1.Church.CheckSaved)
	w3:As(c3.a1, c3.a1.Count.CheckSaved)
	eq(StateOf(w3, c3.a1, "Kept Guy", "Mira Wells"), "credited", "the ledger kept")
	eq(store.book ~= nil and next(store.book.p) ~= nil, true, "the book kept")
	-- Memory: past MEMORY_MAX names the oldest go.
	cl2.Count.MEMORY_MAX = 5
	w.members[World.GUILD] = {}
	for i = 1, 8 do table.insert(w.members[World.GUILD], "Mem Ber" .. ("m"):rep(i)) end
	w:RefreshRosters()
	w:As(cl2, cl2.Count.Remember, true)
	cl2.Count.random = function() return 1 end
	w:Run(DAY)
	w.members[World.GUILD] = { "Mem Berm" }
	w:RefreshRosters()
	w:As(cl2, cl2.Count.Remember, true)
	local mem = w:As(cl2, cl2.Church.Store).mem
	local n = 0
	for _ in pairs(mem.n) do n = n + 1 end
	eq(n <= 5, true, n)
	eq(mem.n[Key("Mem Berm")] ~= nil, true, "the newest kept")
end)

test("1.1.6 Church: the counting's messages fit one message each at their worst (the longest names, realm and guild)", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local name = "Abcdefghijklmno Pqrstuvwxyzabc" -- 30 bytes, one space
	local full = name .. "-" .. ("R"):rep(40)
	local guild = ("G"):rep(48)
	local big = B(4 * 10 ^ 12 / 3600)
	eq(#name, 30)
	local ev = ("NV~1~w~%s~%s~%s~%s~%s"):format(full, full, guild, big, big)
	assert(#ev <= 255, #ev)
	-- (A guild's name is 24 letters at most in game; 48 bytes covers accented ones: an Olympus one reads back.)
	local rec = { n = name, bn = name, g = ("Olympus " .. ("\195\161"):rep(20)), kind = "g", tc = 4 * 10 ^ 9, tj = 4 * 10 ^ 9, s = 1, t = 1, a = 1, x = 1, c = 1, y = 1, q7 = 3, rq = 4,
		ws = { Key(name), Key("Bbcdefghijklmno Pqrstuvwxyzabc") }, u = 4 * 10 ^ 9 }
	local line = w:As(c.a1, c.a1.Count.RecordLine, "x", rec)
	assert(#line <= 255, #line)
	local id, back = w:As(c.a1, c.a1.Count.ParseRecord, line)
	assert(id and back, "it reads back")
	eq(back.tj, rec.tj); eq(back.y, 1); eq(back.q7, 3); eq(back.rq, 4)
	-- (1.2.1: an archived record, its keys for its names.)
	local z = w:As(c.a1, c.a1.Count.ArchiveLine, Key(name), Key("Bbcdefghijklmno Pqrstuvwxyzabc"), { h = 4 * 10 ^ 9, y = 1, t = 4 * 10 ^ 9 })
	assert(#z <= 255, #z)
	local answer = ("NS~1~a~%s~%s~%s~%s~1"):format(B(1679615), guild, B(99999), B(99999))
	assert(#answer <= 255, #answer)
	local row = ("NR~1~r~m~a~%d~%s~%d~%d~%d~%d~%d~%d~1"):format(300, name, 999999, 999999, 999999, 9999, 9999, 9999)
	assert(#row <= 255, #row)
	local top = ("NR~1~t~%s~%s~%s"):format(big, table.concat({ name, name, name }, ","), table.concat({ name, name, name }, ","))
	assert(#top <= 255, #top)
	-- (A kept missionary's entry: its since and its time, in seconds, the year 2096's.)
	local entry = ("NB~1~p~M~%s~%s~%s~M~%s~%s"):format(full, full, full, B(4 * 10 ^ 9), B(4 * 10 ^ 9))
	assert(#entry <= 255, #entry)
end)

-- Review (lane-church): what the first build lost or let through, each test failing on that build.

-- A new session for a client of this world (the game's LOGIN event, as Church.lua listens to it).
local function Login(w, cl)
	for _, fn in ipairs(cl.listeners.LOGIN or {}) do w:As(cl, fn) end
end
local function Records(w, cl)
	local n = 0
	for _ in pairs(w:As(cl, cl.Count.Led).r) do n = n + 1 end
	return n
end
-- Letters for made-up names: 1 -> "b", 26 -> "ba", ...
local function Letters(n)
	local s = ""
	repeat s = string.char(97 + n % 26) .. s; n = math.floor(n / 26) until n == 0
	return s
end

test("1.1.6 Church: a recruiter's own made-up pair stays pending whoever's roster places the recruit, and takes no recruit from the inviter the log shows", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	-- Mira's modified client whispers pairs nobody's log has, dated before the real invite.
	local function Forged(recruit, ago)
		local hour = math.floor(w.clock / 3600)
		local text = ("NV~1~w~Mira Wells-Realm~%s-Realm~%s~%s~%s"):format(recruit, World.GUILD, B(hour - ago), B(hour - 2))
		for _, k in ipairs({ c.a1, c.a2 }) do eq(w:As(k, k.Count.TakeEvidence, "Mira Wells-Realm", text), true) end
	end
	-- Wes (no place in the Church) invited Real Newbie; Mira says she did.
	w:LogEvent(World.GUILD, "invite", "Wes Brook", "Real Newbie", 3)
	w:LogEvent(World.GUILD, "join", "Real Newbie", nil, 2)
	Join(w, World.GUILD, "Real Newbie")
	Forged("Real Newbie", 4)
	w:Tick()
	w:ReadLog(c.wes); w:ReadLog(c.m2)
	Settle(w, 700)
	eq(#w:Sent(c.a1, "NS", "CHANNEL", "q") >= 1, true, "the desk's seen-check ran")
	eq(StateOf(w, c.a1, "Real Newbie", "Mira Wells"), "pending", "a roster shows he is in the guild, not who invited him")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
	-- Nils really invited Contested Kid (the log, and Wes's read of it); Mira claims an earlier invite.
	w:LogEvent(World.GUILD, "invite", "Nils Ford", "Contested Kid", 3)
	w:LogEvent(World.GUILD, "join", "Contested Kid", nil, 2)
	Join(w, World.GUILD, "Contested Kid")
	Forged("Contested Kid", 5)
	w:Tick()
	w:ReadLog(c.m2); w:ReadLog(c.wes)
	eq(StateOf(w, c.a1, "Contested Kid", "Nils Ford"), "credited", "the confirmed claim before an earlier unconfirmed one")
	eq(StateOf(w, c.a1, "Contested Kid", "Mira Wells"), "taken")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Contested Kid", "Nils Ford"), "credited", "and still after the seen-check")
	eq(StateOf(w, c.a2, "Contested Kid", "Nils Ford"), "credited", "on every keeper")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Nils Ford"), "a").points, 10)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
end)

test("1.1.6 Church: a registration's last check runs even when the desk missed its day: one who arrived on day 10 is credited on day 15", function()
	local w, c = Cast()
	eq(w:Act(c.m1, c.m1.Count.Register, "Late Arriver"), true)
	Settle(w, 700)
	-- The checks of days 1, 3 and 7 find nobody.
	for _, days in ipairs({ 1, 2, 4 }) do
		w:Run(days * DAY)
		w:Presence()
		Settle(w, 700)
	end
	eq(Rec(w, c.a1, "Late Arriver", "Mira Wells").rq, 4, "four checks so far")
	-- He joins Olympus Vale on day 10; nobody's desk ticks on day 14.
	w:Run(3 * DAY)
	Join(w, World.GUILD2, "Late Arriver")
	w:Tick()
	w:Run(5 * DAY)
	eq(StateOf(w, c.a1, "Late Arriver", "Mira Wells"), "expired", "past 14 days with no answer yet")
	w:Presence()
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Late Arriver", "Mira Wells"), "credited", "Vik's client placed him in Olympus Vale since day 10")
	eq(Rec(w, c.a1, "Late Arriver", "Mira Wells").g, World.GUILD2)
	-- Never one who arrives after the 14 days, nor a check past REG_LATE.
	eq(w:Act(c.m1, c.m1.Count.Register, "Too Late"), true)
	Settle(w, 700)
	w:Run(16 * DAY)
	Join(w, World.GUILD2, "Too Late")
	w:Tick()
	w:Presence()
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Too Late", "Mira Wells"), "expired")
	w:Run((c.a1.Count.REG_LATE + 1) * DAY)
	w:Presence()
	w:ClearSent()
	Settle(w, 700)
	for _, e in ipairs(w:Sent(c.a1, "NS", "CHANNEL", "q")) do eq(e.msg:find("Too Late", 1, true), nil, "no check past REG_LATE") end
end)

test("1.1.6 Church: a registration made while no keeper is online waits in the outbox and is taken a day later", function()
	local w, c = Cast()
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	eq(w:Act(c.m1, c.m1.Count.Register, "Waiting Guy"), true)
	eq(#w:As(c.m1, function() return c.m1.Church.Store().out end), 1, "held")
	w:Run(25 * 3600)
	c.a1.online = true
	w:Presence({ c.a1 })
	w:Run(15)
	eq(#w:As(c.m1, function() return c.m1.Church.Store().out end), 0)
	eq(StateOf(w, c.a1, "Waiting Guy", "Mira Wells"), "open")
	-- Older than the outbox keeps one: refused.
	local B = ns.Codec.Base36
	eq(select(2, w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Wells-Realm", "NV~1~g~Too Late-Realm~" .. B(w.clock - 8 * DAY))), "times")
end)

test("1.1.6 Church: a catch-up over several rounds carries every record and every person's line (a public choice), records of one second too", function()
	local w, c = Cast()
	c.a2.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence({ c.a1, c.m1 })
	-- Mira shows her row while only Aldric is online; then Aldric takes 160 records, a second apart.
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	eq(w:As(c.a1, c.a1.Count.Led).p[Key("Mira Wells")].pub, true)
	local K, n = c.a1, 0
	local function Take(count, sameSecond)
		for _ = 1, count do
			n = n + 1
			if not sameSecond then w.clock = w.clock + 1 end
			local recruit = "Rec " .. Letters(n)
			w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key("Mira Wells"), { n = recruit, bn = "Mira Wells", g = World.GUILD, kind = "i",
				tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" }, c = 1 }, false)
		end
	end
	Take(160)
	-- Bera comes online and catches up from him: two rounds.
	c.a2.online = true
	w:Presence({ c.a1, c.a2 })
	w:ClearSent()
	eq(w:As(c.a2, c.a2.Count.CatchUp, true), true)
	w:Run(120)
	eq(#w:Sent(c.a2, "NL", "WHISPER", "q"), 2, "two rounds")
	eq(Records(w, c.a2), 160)
	local p = w:As(c.a2, c.a2.Count.Led).p[Key("Mira Wells")]
	eq(p and p.pub, true, "her choice came with them")
	-- 155 more in one second: a round never ends inside a second, so none is left behind.
	Take(155, true)
	eq(w:As(c.a2, c.a2.Count.CatchUp, true), true)
	w:Run(120)
	eq(Records(w, c.a2), 315)
end)

test("1.1.6 Church: the author's close reaches a desk and a member who missed it, from a keeper's presence, before the desk speaks for its saved switch", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	local K = c.a1
	w:As(K, K.Count.MergeIn, "r aa:mira wells", { n = "R Aa", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	eq(w:As(c.wes, c.wes.Count.PublicView).m[1].name, "Mira Wells")
	-- The desk and Wes log off; the author closes (Bera, a keeper, hears it) and logs off too.
	c.a1.online, c.wes.online = false, false
	w:Run(60)
	w:Act(c.author, c.author.Church.SetPublic, false)
	eq((w:As(c.a2, c.a2.Church.Public)), false)
	c.author.online = false
	w:Run(c.a1.Count.PUBLIC_EVERY + 1)
	-- They come back in a new session: Aldric holds the open switch he saved.
	c.a1.online, c.wes.online = true, true
	Login(w, c.a1); Login(w, c.wes)
	eq((w:As(c.a1, c.a1.Church.Public)), true, "his saved switch")
	w:ClearSent()
	w:Tick({ c.a1 })
	eq(#w:Sent(c.a1, "NR", "CHANNEL", "p"), 0, "the desk waits after a login before it speaks for it")
	-- Bera's presence carries the close: both take it.
	w:Presence({ c.a2 })
	eq((w:As(c.a1, c.a1.Church.Public)), false)
	eq((w:As(c.wes, c.wes.Church.Public)), false)
	eq(w:As(c.wes, c.wes.Count.PublicView), nil)
	w:Run(700)
	w:Tick()
	eq(#w:Sent(c.a1, "NR", "CHANNEL", "p"), 0, "nothing broadcast after the close")
	-- A keeper's presence never opens it; the author's does. A plain member's close is nobody's.
	local B = ns.Codec.Base36
	w:As(c.wes, c.wes.Church.TakePresence, "CHANNEL", A2, "NK~1~p~A~-~Olympus Vale~1" .. B(w.clock))
	eq((w:As(c.wes, c.wes.Church.Public)), false, "an Apostle's open is not the author's")
	w:As(c.wes, c.wes.Church.TakePresence, "CHANNEL", World.AUTHOR, "NK~1~p~W~-~Olympus Ember~1" .. B(w.clock))
	eq((w:As(c.wes, c.wes.Church.Public)), true)
	w:As(c.wes, c.wes.Church.TakePresence, "CHANNEL", "Vik Stone-Realm", "NK~1~p~A~-~Olympus Vale~0" .. B(w.clock + 1))
	eq((w:As(c.wes, c.wes.Church.Public)), true)
end)

test("Church public rows retry without spending the publication interval when the relay refuses the list", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	local desk = c.a1
	local sendList, attempts = desk.c.Comm.SendList, 0
	desk.c.Comm.SendList = function(kind, words, ...)
		if kind == "NR" then
			attempts = attempts + 1
			if attempts == 1 then return false end
		end
		return sendList(kind, words, ...)
	end

	eq(w:As(desk, desk.Count.SendPublic), false, "the publisher sees the refusal")
	eq(w:As(c.wes, c.wes.Count.PublicView), nil)
	w:Run(desk.Church.TICK)
	eq(w:Act(desk, desk.Count.SendPublic), true, "the next tick can publish the list")
	eq(attempts, 2)
	assert(w:As(c.wes, c.wes.Count.PublicView), "the eligible public view was delivered")
	eq(w:As(desk, desk.Count.SendPublic), false, "a successful publication still spends the interval")
end)

test("1.1.6 Church: the public view drops the row of one who hides it, an emptied list too (each list's rows end with their count)", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	local K = c.a1
	w:As(K, K.Count.MergeIn, "r ab:" .. Key(A1), { n = "R Ab", bn = "Aldric Vane", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:As(K, K.Count.MergeIn, "r ac:nils ford", { n = "R Ac", bn = "Nils Ford", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w:Act(c.a1, c.a1.Count.SetPublicRow, true)
	w:Act(c.m2, c.m2.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	local v = w:As(c.wes, c.wes.Count.PublicView)
	eq(v.a[1].name, "Aldric Vane"); eq(v.m[1].name, "Nils Ford", "the only one in the missionaries' list")
	-- Nils hides his row: the next round has none in that list.
	w:Run(5)
	w:Act(c.m2, c.m2.Count.SetPublicRow, false)
	w:Run(c.a1.Count.PUBLIC_EVERY + 1)
	w:Tick()
	v = w:As(c.wes, c.wes.Count.PublicView)
	eq(v.a[1].name, "Aldric Vane"); eq(v.m[1], nil, "his row went with his choice")
	-- A count line from a plain member, or for another switch, changes nothing.
	eq(select(2, w:As(c.wes, c.wes.Count.TakePublicCount, "Vik Stone-Realm", "NR~1~n~" .. ns.Codec.Base36(v.at) .. "~a~0")), "keeper")
	eq(w:As(c.wes, c.wes.Count.PublicView).a[1].name, "Aldric Vane")
end)

test("1.1.6 Church: a full ledger archives the credited record it lets go, and never takes it back", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 3
	local ok, err = pcall(function()
		local function Give(recruit, by, ago)
			return w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = by, g = World.GUILD, kind = "i",
				tc = w.clock - ago - 3600, tj = w.clock - ago, ws = { "wes brook" }, c = 1 }, false)
		end
		Give("Old Recruit", "Mira Wells", 50 * DAY)
		Give("R Ba", "Nils Ford", 3600); Give("R Bb", "Nils Ford", 3600)
		eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 10)
		-- The fourth: the oldest goes, its 10 points into Mira's archive.
		Give("R Bc", "Nils Ford", 3600)
		eq(Rec(w, K, "Old Recruit", "Mira Wells"), nil, "let go")
		eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 10, "her all-time points kept")
		local _, _, _, levels = w:As(K, K.Count.Score, Key(A1), "a")
		eq(levels[1], 2.5, "and her Apostle's share of them")
		eq(Give("Old Recruit", "Mira Wells", 50 * DAY), false, "never taken back: it would count twice")
		eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 10)
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)

-- 1.2.1 (a Church Apostle: "i went from 1300 invites to 893, even though i invited 400 players
-- today"). The keeper's ledger was full: each new record let the oldest go into an all-time archive
-- the "Last 30 days" and "This week" windows never read, so every invite of the day took one of his
-- confirmed recruits off the ranking. Each test below fails on that build.

-- A record straight into a keeper's ledger (as evidence or a catch-up line merges it): a recruit of
-- `by`, joined `hoursAgo` hours ago (the hour the log gives), confirmed by a witness unless `pending`.
local function Give(w, K, recruit, by, hoursAgo, pending, extra)
	local tj = (math.floor(w.clock / 3600) - hoursAgo) * 3600
	local rec = { n = recruit, bn = by, g = World.GUILD, kind = "i", tc = tj - 3600, tj = tj,
		ws = not pending and { "wes brook" } or nil, s = pending and 1 or nil }
	for k, v in pairs(extra or {}) do rec[k] = v end
	return w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key(by), rec, false)
end
local function Joins(w, K, by, window) return w:As(K, K.Count.Own, Key(by), window).joins end

test("1.2.1 Church: a full ledger takes no recruit off a count: 1316 credited this week, 423 invites more today, still 1316 (not 893), and the next confirmation counts", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 2000 -- (the ledger's size when the Apostle saw it)
	local ok, err = pcall(function()
		-- Aldric's 1316 confirmed recruits of the last five days, the ledger's oldest records (many in
		-- one hour, as the log dates them), then 684 of Nils's: the ledger is full.
		for i = 1, 1316 do Give(w, K, "Ald Rec" .. Letters(i), A1, 120 - (i % 72)) end
		for i = 1, 684 do Give(w, K, "Nil Rec" .. Letters(i), "Nils Ford", 47 - (i % 24)) end
		eq(Records(w, K), 2000)
		local week = Joins(w, K, A1, "w")
		eq(Joins(w, K, A1, "m"), 1316)
		local function Row()
			for _, r in ipairs(w:As(K, K.Count.Ranking, "a", "m")) do if r.key == Key(A1) then return r end end
		end
		local before = Row()
		eq(before.own, 13160)
		-- Today's invites, his own client's reports (pending until a witness's read confirms them).
		for i = 1, 423 do Give(w, K, "New Rec" .. Letters(i), A1, 1, true) end
		assert(Records(w, K) <= 2000, "the ledger stays bounded")
		eq(Joins(w, K, A1, "m"), 1316, "the last 30 days: 1316, not 893")
		eq(Joins(w, K, A1, "w"), week, "this week unchanged")
		eq(Joins(w, K, A1, "a"), 1316, "all time")
		eq(Joins(w, K, "Nils Ford", "m"), 684, "nobody else's either")
		local row = Row()
		eq(row.own, 13160); eq(row.joins, 1316)
		eq(row.score, before.score, "his score (his own and his network's share: Nils is under Mira, under him) unchanged")
		-- A witness confirms the first of today's invites, which had to make room: it counts.
		eq(Give(w, K, "New Rec" .. Letters(1), A1, 1), true)
		eq(Joins(w, K, A1, "m"), 1317, "and the count still rises")
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)

test("1.2.1 Church: keepers holding the same records show the same numbers in every window, whatever order they came in, full ledgers included", function()
	local w, c = Cast()
	local K1, K2, truth = c.a1, c.a2, c.head
	local saved = K1.Count.RECORDS_MAX
	K1.Count.RECORDS_MAX, K2.Count.RECORDS_MAX = 60, 60
	local ok, err = pcall(function()
		-- 200 records: Aldric's and Nils's recruits, four to an hour, every fifth one pending and every
		-- seventh a transfer; one keeper takes them oldest first, the other newest first.
		local specs = {}
		for i = 1, 200 do
			specs[i] = { "Con Rec" .. Letters(i), i % 2 == 0 and A1 or "Nils Ford", math.floor((200 - i) / 4), i % 5 == 0,
				i % 7 == 0 and { t = 1 } or nil }
		end
		for i = 1, 200 do
			local s = specs[i]
			Give(w, K1, s[1], s[2], s[3], s[4], s[5])
			Give(w, truth, s[1], s[2], s[3], s[4], s[5])
			local r = specs[201 - i]
			Give(w, K2, r[1], r[2], r[3], r[4], r[5])
		end
		assert(Records(w, K1) <= 60 and Records(w, K2) <= 60, "both ledgers stayed bounded")
		eq(Records(w, truth), 200, "the third keeper's ledger had room for all")
		for _, by in ipairs({ A1, "Nils Ford" }) do
			for _, window in ipairs({ "w", "m", "a" }) do
				local want = w:As(truth, truth.Count.Own, Key(by), window)
				for _, K in ipairs({ K1, K2 }) do
					local got = w:As(K, K.Count.Own, Key(by), window)
					eq(got.joins, want.joins, by .. " " .. window .. " joins")
					eq(got.points, want.points, by .. " " .. window .. " points")
				end
			end
		end
		-- (Each recruit once: the second claim on a recruit whose credited claim went to the archive is
		-- not taken, so he can never count for two people.)
		eq(Rec(w, K1, specs[2][1], A1), nil, "(Aldric's recruit went to the archive)")
		eq(Give(w, K1, specs[2][1], "Nils Ford", 1), false)
		eq(Joins(w, K1, "Nils Ford", "a"), w:As(truth, truth.Count.Own, Key("Nils Ford"), "a").joins)
	end)
	K1.Count.RECORDS_MAX, K2.Count.RECORDS_MAX = saved, saved
	if not ok then error(err, 0) end
end)

test("1.2.1 Church: a reload keeps the ledger when one saved record fails the load's check: only that record goes", function()
	local w, c = Cast()
	local K = c.a1
	for i = 1, 5 do Give(w, K, "Kept Rec" .. Letters(i), "Mira Wells", 3) end
	-- A record of a guild this build no longer counts as Olympus (the council's removed list, the
	-- signed approved list).
	w:As(K, K.Count.Led).r["odd guy:mira wells"] = { n = "Odd Guy", bn = "Mira Wells", g = "Plain Guild", kind = "i",
		tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" }, u = w.clock }
	w:As(K, K.Count.CheckSaved)
	eq(w:As(K, K.Count.Led).r["odd guy:mira wells"], nil, "the record that fails goes")
	eq(Records(w, K), 5, "the others stay")
	eq(Joins(w, K, "Mira Wells", "m"), 5)
end)

test("1.2.1 Church: a ledger the old build had cut back counts its own let-go recruits again in the windows, once (893 live and 423 let go today: 1316)", function()
	local w, c = Cast()
	local K = c.a1
	for i = 1, 893 do Give(w, K, "Ald Rec" .. Letters(i), A1, 30 + (i % 48)) end
	-- What 1.2.0 left of the 423 it let go today: their Gone marks and the all-time archive, no join hours.
	local l = w:As(K, K.Count.Led)
	l.wv, l.gone = nil, {}
	for i = 1, 423 do l.gone[Key("Lost Rec" .. Letters(i)) .. ":" .. Key(A1)] = w.clock - 3600 * (i % 10) end
	l.gone[Key("Older Rec") .. ":" .. Key(A1)] = w.clock - 40 * DAY -- (let go before any window began)
	l.gone[Key("Lost Reca") .. ":"] = w.clock -- (a recruit's own mark is no record)
	l.p[Key(A1)] = { n = "Aldric Vane", ap = 4240, aj = 424, ay = 0, u = w.clock }
	eq(Joins(w, K, A1, "m"), 893, "what the Apostle saw")
	w:As(K, K.Count.CheckSaved)
	eq(Joins(w, K, A1, "m"), 1316, "the last 30 days again")
	eq(Joins(w, K, A1, "a"), 893 + 424, "all time as it was")
	w:As(K, K.Count.CheckSaved)
	eq(Joins(w, K, A1, "m"), 1316, "once")
	-- (The marks became its recruits' marks: no other claim on them is taken.)
	eq(l.gone[Key("Lost Recb") .. ":" .. Key(A1)], nil); eq(type(l.gone[Key("Lost Recb") .. ":"]), "number")
	eq(Give(w, K, "Lost Recb", "Mira Wells", 2), false)
	-- A ledger this build began has nothing to restore: its archive keeps each record itself. (Its
	-- marks of a record are what counted for nothing, never a recruit to count again.)
	local K2 = c.a2
	local l2 = w:As(K2, K2.Count.Led)
	eq(l2.wv, 2)
	l2.gone = { [Key("Some Rec") .. ":" .. Key(A2)] = w.clock }
	l2.arc = { [Key(A2)] = { [Key("Kept Rec")] = { h = w.clock - 3600, t = w.clock, l = 1 } } }
	l2.p[Key(A2)] = { n = "Bera Stone", ap = 10, aj = 1, ay = 0, u = w.clock }
	w:As(K2, K2.Count.CheckSaved)
	eq(Joins(w, K2, A2, "m"), 1)
	-- One of 1.2.1's first builds (wv 1) kept the archive's joins by the hour: they still count.
	l2.wv, l2.arc = 1, {}
	l2.p[Key(A2)].wj = { [math.floor(w.clock / 3600) * 3600] = 1 }
	w:As(K2, K2.Count.CheckSaved)
	eq(Joins(w, K2, A2, "m"), 1); eq(l2.wv, 2)
end)

-- 1.2.1 review: the counts must converge on every keeper, whichever let a record go, and no recruit
-- may count twice. Each test below fails on the first 1.2.1 build (f0778c4, 939ad78).

local function Numbers(w, K, by)
	local out = {}
	for _, win in ipairs({ "w", "m", "a" }) do
		local o = w:As(K, K.Count.Own, Key(by), win)
		out[win] = { joins = o.joins, points = o.points, stays = o.stays }
	end
	return out
end
local function SameNumbers(got, want, who)
	for _, win in ipairs({ "w", "m", "a" }) do
		eq(got[win].joins, want[win].joins, who .. ", " .. win .. " joins")
		eq(got[win].points, want[win].points, who .. ", " .. win .. " points")
		eq(got[win].stays, want[win].stays, who .. ", " .. win .. " stays")
	end
end

test("1.2.1 Church: a keeper catching up from a full ledger shows its week, 30 days and all time: the archive travels by record, and one held live counts once", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 60
	local ok, err = pcall(function()
		c.a2.online = false
		w:Run(K.Church.KEEPER_EVERY * 3)
		w:Presence()
		-- 100 confirmed recruits of Mira's, one an hour back to 99 hours ago (the oldest still in after 7
		-- days); Aldric's ledger holds 60 of them, the rest went into his archive. Bera's holds the 30
		-- oldest live: she took them before her ledger filled.
		for i = 1, 100 do Give(w, K, "Arc Rec" .. Letters(i), "Mira Wells", 100 - i, false, i <= 10 and { y = 1, c = 1 } or nil) end
		for i = 1, 30 do Give(w, c.a2, "Arc Rec" .. Letters(i), "Mira Wells", 100 - i, false, i <= 10 and { y = 1, c = 1 } or nil) end
		assert(Records(w, K) <= 60, "Aldric's ledger is full")
		local want = Numbers(w, K, "Mira Wells")
		eq(want.m.joins, 100); eq(want.a.joins, 100); eq(want.m.stays, 10)
		-- Bera comes online and catches up from him: his archive comes as records, and the 30 she held
		-- live go into her own archive, each counted once.
		c.a2.online = true
		w:Presence()
		eq(w:As(c.a2, c.a2.Count.CatchUp, true), true)
		w:Run(600)
		SameNumbers(Numbers(w, c.a2, "Mira Wells"), want, "Bera")
		eq(Rec(w, c.a2, "Arc Recb", "Mira Wells"), nil, "the record she held went into her archive")
		-- The Head comes online with an empty ledger and catches up from Aldric: the same numbers.
		c.head.online = true
		w:Presence()
		eq(w:As(c.head, c.head.Count.CatchUp, true), true)
		w:Run(600)
		SameNumbers(Numbers(w, c.head, "Mira Wells"), want, "the Head")
		-- Their rankings agree too, whichever keeper an audience client asks.
		local function Row(K2)
			for _, r in ipairs(w:As(K2, K2.Count.Ranking, "a", "m")) do if r.key == Key(A1) then return r end end
		end
		eq(Row(c.head).score, Row(K).score); eq(Row(c.a2).score, Row(K).score)
		-- Taken again (a second catch-up, the same records once more): nothing changes.
		w:As(c.head, c.head.Count.Led).from = {}
		eq(w:As(c.head, c.head.Count.CatchUp, true), true)
		w:Run(600)
		SameNumbers(Numbers(w, c.head, "Mira Wells"), want, "the Head again")
		-- A week later the Head's numbers move with the windows as Aldric's do.
		w:Run(7 * DAY)
		SameNumbers(Numbers(w, c.head, "Mira Wells"), Numbers(w, K, "Mira Wells"), "a week later")
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)

test("1.2.1 Church: catch-ups go round every keeper online: records only the last keeper in the list holds reach the others", function()
	local Z = "Zed Last-Realm"
	local w = World.New({ apostles = { A1, A2, Z }, head = false })
	local c = { a1 = w:Client(A1), a2 = w:Client(A2, { guild = World.GUILD2 }), z = w:Client(Z), m1 = w:Client("Mira Wells"), wes = w:Client("Wes Brook") }
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Run(8 * 3600)
	-- Only Zed is online when ten of Mira's recruits are confirmed.
	c.a1.online, c.a2.online = false, false
	w:Run(c.z.Church.KEEPER_EVERY * 3)
	w:Presence()
	for i = 1, 10 do Give(w, c.z, "Solo Rec" .. Letters(i), "Mira Wells", 2) end
	eq(Joins(w, c.z, "Mira Wells", "m"), 10)
	-- Aldric and Bera come back; every keeper catches up every half hour.
	c.a1.online, c.a2.online = true, true
	for _ = 1, 3 do
		w:Presence()
		for _, K in ipairs({ c.a1, c.a2, c.z }) do w:As(K, K.Count.CatchUp, false) end
		w:Run(c.a1.Count.CATCHUP_EVERY + 100)
	end
	eq(Joins(w, c.a1, "Mira Wells", "m"), 10, "Aldric")
	eq(Joins(w, c.a2, "Mira Wells", "m"), 10, "Bera")
end)

test("1.2.1 Church: a transfer a full ledger let go stays a transfer: a witness's later report or a keeper's line without the word is not a new recruit", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 60
	local ok, err = pcall(function()
		Give(w, K, "Moved Guy", "Mira Wells", 3, false, { t = 1, c = 1 })
		eq(StateOf(w, K, "Moved Guy", "Mira Wells"), "transfer")
		for i = 1, 60 do Give(w, K, "Nil Rec" .. Letters(i), "Nils Ford", 5) end
		eq(Rec(w, K, "Moved Guy", "Mira Wells"), nil, "let go first: it counted for nothing")
		-- Wes's client reads the pair again (its memory of what it sent was wiped past ATT_MAX); Moved Guy is
		-- still on Aldric's roster.
		Join(w, World.GUILD, "Moved Guy")
		local B = ns.Codec.Base36
		local hour = math.floor(w.clock / 3600) - 3
		w:As(K, K.Count.TakeEvidence, "Wes Brook-Realm", ("NV~1~w~Mira Wells-Realm~Moved Guy-Realm~%s~%s~%s"):format(World.GUILD, B(hour - 1), B(hour)))
		-- And a keeper's line that never had the word.
		local line = w:As(K, K.Count.RecordLine, "x", { n = "Moved Guy", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = (hour - 1) * 3600,
			tj = hour * 3600, ws = { "vik stone" }, u = w.clock })
		w:As(K, K.Count.TakeLine, A2, line)
		eq(StateOf(w, K, "Moved Guy", "Mira Wells"), nil)
		eq(Joins(w, K, "Mira Wells", "m"), 0)
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)

test("1.2.1 Church: what a full ledger let go is remembered by time, not by count: a recruit archived weeks ago is never taken again", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 60
	local ok, err = pcall(function()
		-- 250 of Mira's recruits from 40 days ago (all time only), then today's: about 190 went into the
		-- archive, more than the old build's 2 * RECORDS_MAX marks kept.
		for i = 1, 250 do Give(w, K, "Old Rec" .. Letters(i), "Mira Wells", 40 * 24 + 250 - i) end
		eq(Joins(w, K, "Mira Wells", "a"), 250)
		eq(Rec(w, K, "Old Recb", "Mira Wells"), nil, "the oldest went into the archive")
		-- Another keeper still holding the oldest sends it in a catch-up: not taken, not counted twice.
		local tj = (math.floor(w.clock / 3600) - (40 * 24 + 249)) * 3600
		local line = w:As(K, K.Count.RecordLine, "x", { n = "Old Recb", bn = "Mira Wells", g = World.GUILD, kind = "i", tc = tj - 3600, tj = tj,
			ws = { "wes brook" }, u = w.clock })
		eq(w:As(K, K.Count.TakeLine, A2, line), false)
		eq(Joins(w, K, "Mira Wells", "a"), 250)
		-- The hourly upkeep keeps the marks while a line could bring one back (RECORDS_DAYS)...
		w:As(K, K.Count.Prune)
		eq(w:As(K, K.Count.TakeLine, A2, line), false)
		-- ...and lets them go after, when every keeper refuses such a record as too old anyway.
		w:Run((K.Count.RECORDS_DAYS + 1) * DAY)
		w:As(K, K.Count.Prune)
		eq(next(w:As(K, K.Count.Led).gone), nil)
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)

test("1.2.1 Church: a person's detail adds up: the archive's recruits have their own line next to the guilds'", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 60
	local ok, err = pcall(function()
		for i = 1, 100 do Give(w, K, "Det Rec" .. Letters(i), "Mira Wells", 100 - i) end
		for _, win in ipairs({ "m", "a" }) do
			local lines = w:As(K, K.Count.DetailLines, Key("Mira Wells"), win)
			local joins, sum, archived = nil, 0, nil
			for _, d in ipairs(lines) do
				if d[1] == "j" then joins = d[2] end
				if d[1] == "g" then
					sum = sum + d[3]
					if d[2] == "-" then archived = d[3] end
				end
			end
			eq(joins, 100, win); eq(sum, joins, win .. ": the lines add up")
			assert(archived and archived > 0, "the archive's own line, " .. win)
		end
		eq(type(ns.L.CHURCH_GUILD_ARCHIVED), "string")
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)

test("1.2.1 Church: an archived recruit later proven a transfer leaves the count, on every keeper; one still in after 7 days counts his stay", function()
	local w, c = Cast()
	local K = c.a1
	local saved = K.Count.RECORDS_MAX
	K.Count.RECORDS_MAX = 60
	local ok, err = pcall(function()
		Give(w, K, "Late Mover", "Mira Wells", 30); Give(w, c.a2, "Late Mover", "Mira Wells", 30)
		Give(w, K, "Late Stayer", "Mira Wells", 29); Give(w, c.a2, "Late Stayer", "Mira Wells", 29)
		for i = 1, 60 do Give(w, K, "Fill Rec" .. Letters(i), "Nils Ford", 5) end
		eq(Rec(w, K, "Late Mover", "Mira Wells"), nil, "archived"); eq(Rec(w, K, "Late Stayer", "Mira Wells"), nil, "archived")
		eq(Joins(w, K, "Mira Wells", "m"), 2)
		-- The desk's new-to-Olympus check finds him in another Olympus guild: a transfer, on Bera's too.
		eq(w:As(K, K.Count.MergeIn, Key("Late Mover") .. ":" .. Key("Mira Wells"), { c = 1, t = 1 }, true), true)
		w:Run(5)
		eq(Joins(w, K, "Mira Wells", "m"), 1); eq(Joins(w, K, "Mira Wells", "a"), 1, "all time too")
		eq(StateOf(w, c.a2, "Late Mover", "Mira Wells"), "transfer")
		-- Bera's check finds the other still in after 7 days: her line brings his stay to Aldric's archive.
		local id = Key("Late Stayer") .. ":" .. Key("Mira Wells")
		local r = Rec(w, c.a2, "Late Stayer", "Mira Wells")
		r.y, r.u = 1, w.clock
		eq(w:As(K, K.Count.TakeLine, A2, w:As(c.a2, c.a2.Count.RecordLine, id, r)), true)
		local o = w:As(K, K.Count.Own, Key("Mira Wells"), "m")
		eq(o.stays, 1); eq(o.points, 15)
		eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 15)
	end)
	K.Count.RECORDS_MAX = saved
	if not ok then error(err, 0) end
end)

test("1.2.1 Church: a keeper just logged in answers no ask before its catch-up: an audience page keeps its numbers instead of a ledger's that is behind", function()
	local w, c = Cast()
	-- Aldric is away while Bera, the only keeper online, takes five of Mira's recruits; Nils's page asks her.
	c.a1.online = false
	w:Run(c.a2.Church.KEEPER_EVERY * 3)
	w:Presence()
	for i = 1, 5 do Give(w, c.a2, "Away Rec" .. Letters(i), "Mira Wells", 2) end
	local function MiraJoins()
		for _, r in ipairs((w:As(c.m2, c.m2.Count.RankingView, "m", "m"))) do if r.key == Key("Mira Wells") then return r.joins end end
	end
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "m", nil, true), true)
	w:Run(30)
	eq(MiraJoins(), 5)
	-- Aldric logs in: the desk again (his name first), his ledger without those five.
	c.a1.online = true
	Login(w, c.a1)
	w:Presence()
	eq(w:As(c.a1, c.a1.Church.Desk), A1)
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "m", nil, true), true)
	w:Run(30)
	eq(MiraJoins(), 5, "not 0: the page kept its numbers")
	-- Caught up from Bera, he answers, with them.
	eq(w:As(c.a1, c.a1.Count.CatchUp, true), true)
	w:Run(60)
	eq(w:As(c.a1, c.a1.Count.Settled), true)
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "m", nil, true), true)
	w:Run(30)
	eq(MiraJoins(), 5)
end)

-- 1.2.1, the security review: what a keeper takes from whom.

-- A log pair as a reporter's client whispers it: invite and join `ago` hours ago, in Olympus Ember.
local function PairText(w, inviter, recruit, ago, guild)
	local B, hour = ns.Codec.Base36, math.floor(w.clock / 3600)
	return ("NV~1~w~%s-Realm~%s-Realm~%s~%s~%s"):format(inviter, recruit, guild or World.GUILD, B(hour - ago), B(hour - ago))
end

test("1.2.1 Church: a witness is one the keeper can vouch for in the pair's guild: an outsider's whisper confirms nothing and takes no recruit from his recruiter", function()
	local w, c = Cast()
	local function Take(k, from, text) return select(2, w:As(k, k.Count.TakeEvidence, from, text)) end
	-- Mira's own report leaves her pair pending; a stranger's whisper of the same pair, to every keeper, changes nothing.
	eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Wells-Realm", PairText(w, "Mira Wells", "Made Up", 2)), true)
	for _, k in ipairs({ c.a1, c.a2 }) do eq(Take(k, "Stray Whisper-Realm", PairText(w, "Mira Wells", "Made Up", 2)), "unverified") end
	w:Flush()
	eq(StateOf(w, c.a1, "Made Up", "Mira Wells"), "pending")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "a").points, 0)
	-- A member of another guild is no witness to an Olympus Ember pair, nor one of the recruit's own characters.
	eq(Take(c.a1, "Vik Stone-Realm", PairText(w, "Mira Wells", "Made Up", 2)), "unverified")
	w.alts[Key("Wes Kid")] = { "Wes Brook-Realm" }
	eq(Take(c.a1, "Wes Brook-Realm", PairText(w, "Mira Wells", "Wes Kid", 2)), "recruit")
	-- Nils's real recruit, confirmed by Wes (Aldric's roster, which shows Real Kid): a stranger's earlier-dated
	-- pair for Mira takes nothing.
	Join(w, World.GUILD, "Real Kid")
	eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Nils Ford-Realm", PairText(w, "Nils Ford", "Real Kid", 2)), true)
	eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Wes Brook-Realm", PairText(w, "Nils Ford", "Real Kid", 2)), true)
	eq(Take(c.a1, "Stray Whisper-Realm", PairText(w, "Mira Wells", "Real Kid", 5)), "unverified")
	eq(StateOf(w, c.a1, "Real Kid", "Nils Ford"), "credited", "not taken from his recruiter")
	eq(StateOf(w, c.a1, "Real Kid", "Mira Wells"), nil)
	w:Flush()
	eq(StateOf(w, c.a2, "Real Kid", "Nils Ford"), "credited", "Aldric, who vouched for Wes, told Bera")
	-- Bera, in Olympus Vale, vouches for the signed (a High Councillor), Olympus Ember's correspondent and an
	-- officer the Olympus chats verify there; not for a member they could not.
	eq(w:As(c.a2, c.a2.Count.TakeEvidence, World.COUNCILLOR, PairText(w, "Mira Wells", "Sig Ned", 2)), true)
	eq(StateOf(w, c.a2, "Sig Ned", "Mira Wells"), "credited")
	eq(w:Act(c.king, c.king.Church.NameCorrespondent, "Cora Penn", World.GUILD), true)
	eq(w:As(c.a2, c.a2.Count.TakeEvidence, "Cora Penn-Realm", PairText(w, "Mira Wells", "Cor Ned", 2)), true)
	eq(StateOf(w, c.a2, "Cor Ned", "Mira Wells"), "credited")
	c.a2.c.Channels.VerifiedLevel = function(n, g)
		if Key(n) == Key("Ola Officer") and g == World.GUILD then return 2, true, 1 end
		return 1, false
	end
	eq(w:As(c.a2, c.a2.Count.TakeEvidence, "Ola Officer-Realm", PairText(w, "Mira Wells", "Off Ned", 2)), true)
	eq(StateOf(w, c.a2, "Off Ned", "Mira Wells"), "credited")
	eq(Take(c.a2, "Plain Ember-Realm", PairText(w, "Mira Wells", "Plain Ned", 2)), "unverified", "a claimed member the chats could not verify")
end)

test("1.2.1 Church: a keeper's lines are checked again: no recruit his own recruiter, nothing dated ahead, no recruiter or recruit as witness, archive totals that add up, rows only from the keeper asked", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local K, from = c.a2, A1
	local function Line(recruit, by, extra)
		local rec = { n = recruit, bn = by, g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, u = w.clock }
		for k, v in pairs(extra or {}) do rec[k] = v end
		return w:As(c.a1, c.a1.Count.RecordLine, "x", rec)
	end
	local function Take(text) return w:As(K, K.Count.TakeLine, from, text) end
	-- The recruiter, the recruit or the recruiter's linked character named as the witness: pending.
	w.alts[Key("Mira Wells")] = { "Mira Alt-Realm" }
	eq(Take(Line("Wit Selfa", "Mira Wells", { ws = { Key("Mira Wells") } })), true)
	eq(Take(Line("Wit Selfb", "Mira Wells", { ws = { Key("Wit Selfb") } })), true)
	eq(Take(Line("Wit Selfc", "Mira Wells", { ws = { Key("Mira Alt") } })), true)
	for _, n in ipairs({ "Wit Selfa", "Wit Selfb", "Wit Selfc" }) do eq(StateOf(w, K, n, "Mira Wells"), "pending", n) end
	eq(Take(Line("Wit Good", "Mira Wells", { ws = { Key("Wes Brook") } })), true)
	eq(StateOf(w, K, "Wit Good", "Mira Wells"), "credited", "a witness the line vouches for")
	-- A recruit his own recruiter; an invite dated ahead.
	eq(select(2, Take(Line("Mira Wells", "Mira Wells", { ws = { Key("Wes Brook") } }))), "self")
	eq(select(2, Take(Line("Far Ahead", "Mira Wells", { kind = "g", tc = w.clock + 2 * DAY, tj = false }))), "ahead")
	eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").joins, 1)
	-- Person lines: a choice dated ahead would outlast her own later one; totals that don't add up; no place.
	local function P(name, at, ap, aj, ay) return ("NL~1~p~%s~1~%s~%d~%d~%d~%s"):format(name, B(at), ap, aj, ay, B(w.clock)) end
	eq(select(2, Take(P("Mira Wells", w.clock + 30 * DAY, 0, 0, 0))), "ahead")
	eq(select(2, Take(P("Mira Wells", 0, 99990, 1, 0))), "totals")
	eq(select(2, Take(P("Mira Wells", 0, 15, 1, 2))), "totals", "more stays than joins")
	eq(select(2, Take(P("Nobody Here", 0, 10, 1, 0))), "person")
	eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 10)
	eq(Take(P("Mira Wells", w.clock, 30, 3, 0)), true, "one that adds up")
	eq(w:As(K, K.Count.Own, Key("Mira Wells"), "a").points, 40, "her live record and the archive's three")
	-- Rows nobody asked for, or from a keeper not asked, leave an audience page as it was.
	local view = function() return (w:As(c.m2, c.m2.Count.RankingView, "m", "m")) end
	local rows = { ("NR~1~r~m~m~1~Mira Wells~9999990~9999990~0~999~0~999~1"), ("NR~1~e~m~m~-~1~%s"):format(B(w.clock)) }
	for _, l in ipairs(rows) do eq(select(2, w:As(c.m2, c.m2.Count.TakeAnswerLine, A2, l)), "unasked") end
	eq(#view(), 0)
	Give(w, c.a1, "Desk Rec", "Mira Wells", 2)
	eq(w:As(c.m2, c.m2.Church.KeepersOnline, false)[1].name, A1, "the desk is asked")
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "m", nil, true), true)
	for _, l in ipairs(rows) do eq(select(2, w:As(c.m2, c.m2.Count.TakeAnswerLine, A2, l)), "unasked", "another keeper's") end
	w:Run(30)
	eq(#view(), 1)
	eq(view()[1].name, "Mira Wells"); eq(view()[1].score, 10, "the asked keeper's own rows")
end)

-- One hour of Mira's: `n` players invited and joined, the log read by her client and Wes's, then the hour.
local function InviteHour(w, c, n, first, prefix)
	w:Presence()
	for i = 1, n do
		local name = (prefix or "Day Rec") .. Letters(first + i)
		w:LogEvent(World.GUILD, "invite", "Mira Wells", name, 0)
		w:LogEvent(World.GUILD, "join", name, nil, 0)
		w.members[World.GUILD] = w.members[World.GUILD] or {}
		table.insert(w.members[World.GUILD], name)
	end
	w:RefreshRosters()
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	w.log[World.GUILD] = {} -- (the game's log keeps its newest events only)
	w:Run(3600)
end
local function Outbox(w, cl) return #(w:As(cl, function() return cl.Church.Store().out or {} end)) end

test("1.2.1 Church: 400 players invited in a day are 400 confirmed recruits on every keeper (not 100 a day: the old budget per witness)", function()
	local w, c = Cast()
	for h = 0, 19 do InviteHour(w, c, 20, h * 20) end
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(w:As(k, k.Count.Own, Key("Mira Wells"), "m").joins, 400, k.name)
		eq(w:As(k, k.Count.Own, Key("Mira Wells"), "a").points, 4000, k.name)
	end
	eq(Outbox(w, c.wes), 0, "every report had its receipt"); eq(Outbox(w, c.m1), 0)
end)

test("1.2.1 Church: a report no keeper took waits and goes again: to a keeper heard later, and an hour after one over its budget refused it", function()
	local w, c = Cast()
	-- Aldric, the only keeper who can vouch for Wes, is away; Bera takes Mira's own reports, not Wes's.
	c.a1.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	InviteHour(w, c, 10, 0, "Away Rec")
	eq(w:As(c.a2, c.a2.Count.Own, Key("Mira Wells"), "m").pending, 10)
	eq(Outbox(w, c.wes), 10, "Wes's reports wait"); eq(Outbox(w, c.m1), 0, "Bera's receipts for Mira's")
	c.a1.online = true
	w:Presence()
	w:Run(15)
	for _, k in ipairs({ c.a1, c.a2 }) do eq(w:As(k, k.Count.Own, Key("Mira Wells"), "m").joins, 10, k.name) end
	eq(Outbox(w, c.wes), 0)
	-- Over Aldric's budget for the hour, five of fifteen are refused; the next hour's round brings them.
	c.a1.Count.EVIDENCE_HOUR, c.a1.Count.VERIFIED_HOUR = 10, 10
	w:Run(3600)
	InviteHour(w, c, 15, 100, "Busy Rec")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "m").joins, 20)
	eq(Outbox(w, c.wes), 5)
	w:Presence()
	w:Tick()
	w:Run(30)
	for _, k in ipairs({ c.a1, c.a2 }) do eq(w:As(k, k.Count.Own, Key("Mira Wells"), "m").joins, 25, k.name) end
	eq(Outbox(w, c.wes), 0); eq(Outbox(w, c.m1), 0)
	-- (A receipt's line fits one message at its fullest.)
	local full = "NV~1~k~" .. table.concat((function() local t = {} for i = 1, c.a1.Count.RECEIPT_IDS do t[i] = ns.Comm.Hash36("r" .. i) end return t end)(), ",")
	assert(#full <= 255, #full)
end)

test("1.2.1 Church: a busy guild's invites wait for their joins: 320 invited in one read, joined by the next, are 320 pairs (the invites past 300 all went)", function()
	local w, c = Cast()
	w:Presence()
	local names = {}
	for i = 1, 320 do
		names[i] = "Wait Rec" .. Letters(i)
		w:LogEvent(World.GUILD, "invite", "Mira Wells", names[i], 1)
	end
	w:ReadLog(c.m1)
	w.log[World.GUILD] = {}
	for i = 1, 320 do w:LogEvent(World.GUILD, "join", names[i], nil, 0) end
	w:ReadLog(c.m1)
	eq(w:As(c.m1, c.m1.Count.Stats).pairs, 320)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "m").pending, c.a1.Count.VERIFIED_HOUR, "the hour's budget")
	-- (The rest an hour later, the outbox's next round.)
	w:Run(3600)
	w:Presence(); w:Tick(); w:Run(30)
	eq(w:As(c.a1, c.a1.Count.Own, Key("Mira Wells"), "m").pending, 320)
	-- Bounded: past INV_MAX, the oldest invites go first.
	local inv = w:As(c.m1, function() return c.m1.Church.Store().inv end)
	for i = 1, c.m1.Count.INV_MAX + 10 do inv["x" .. i] = { by = "Mira Wells-Realm", h = math.floor(w.clock / 3600) - (i % 40) } end
	w:As(c.m1, c.m1.Count.Process, {})
	local n = 0
	for _ in pairs(inv) do n = n + 1 end
	eq(n, c.m1.Count.INV_MAX)
end)

-- 1.2.1, the review of the fix: re-sends that converge, witnesses that can't mint, registrations dated when heard,
-- receipts never to keepers.

-- Sent from one client to another: NV messages of kind `sub` naming `name` (nil: any).
local function SentTo(w, from, to, sub, name)
	local n = 0
	for _, e in ipairs(w:Sent(from, "NV", "WHISPER", sub)) do
		if Key(e.target) == to.key and (not name or e.msg:find(name, 1, true)) then n = n + 1 end
	end
	return n
end

local function WitnessInvite(w, c, recruit)
	Join(w, World.GUILD, recruit)
	w:LogEvent(World.GUILD, "invite", "Mira Wells", recruit, 0)
	w:LogEvent(World.GUILD, "join", recruit, nil, 0)
	w:ReadLog(c.wes)
	w.log[World.GUILD] = {}
end

-- Old channel presence has expired, and the two guilds now use distinct relay islands.
local function KeeperProbeWorld()
	local w, c = Cast()
	w:SignedList({ A1, A2 }, false, w.titles.at + 1)
	for _, cl in pairs(c) do
		cl.c.group = "ForeverPvE"
		cl.c.Relay = { On = function() return true end }
		cl.c.ForeverFamily = function(realm) return realm == "Realm" and "ForeverPvE" or ns.ForeverFamily(realm) end
		cl.Church.random = function(a) return a end
	end
	c.a2.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:ClearSent()
	return w, c
end

test("Church keeper discovery: a guild witness delivers verified evidence without channel presence", function()
	local w, c = KeeperProbeWorld()
	eq(#w:As(c.wes, c.wes.Church.KeepersOnline, false), 0)
	WitnessInvite(w, c, "Across Rec")
	local queries = w:Sent(c.wes, "NK", "WHISPER", "q")
	eq(#queries, 1)
	eq(queries[1].target, A1, "the signed Apostle is tried by direct whisper")
	assert(not queries[1].msg:find("Across Rec", 1, true), "discovery contains no evidence")
	w:Run(15)
	eq(SentTo(w, c.wes, c.a1, "w"), 1)
	eq(Joins(w, c.a1, "Mira Wells", "m"), 1)
	eq(Outbox(w, c.wes), 0)
end)

test("Church keeper discovery: a ranking ask accepts only its own signed and scoped direct reply", function()
	local w, c = KeeperProbeWorld()
	Give(w, c.a1, "Desk Rec", "Mira Wells", 2)
	local ask = function() return w:As(c.m1, c.m1.Count.Ask, "m", "m", nil, true) end
	eq(select(2, ask()), "no keeper")
	for _ = 1, 4 do ask() end
	local queries = w:Sent(c.m1, "NK", "WHISPER", "q")
	eq(#queries, 1, "refreshing the tab cannot fan out discovery")
	local nonce = assert(queries[1].msg:match("^NK~1~q~(%w+)~"))
	local reply = "NK~1~a~" .. nonce .. "~ForeverPvE:Alliance"
	local function Take(dist, sender, text) return w:As(c.m1, c.m1.Church.ReceivePresence, dist, sender, text) end
	eq(Take("WHISPER", A2, reply), false, "another signed Apostle did not get this request")
	eq(Take("WHISPER", A1, reply:gsub("ForeverPvE", "ForeverPvP")), false)
	eq(Take("WHISPER", "Aldric Vane-CAMWOWUS1Realm1PvP", reply), false)
	eq(Take("WHISPER", A1, reply:gsub(nonce, nonce .. "z")), false)
	eq(Take("CHANNEL", A1, reply), false)
	eq(#w:As(c.m1, c.m1.Church.KeepersOnline, false), 0)
	w:Flush()
	eq(#w:Sent(c.a1, "NK", "WHISPER", "a"), 1)
	eq(ask(), true)
	w:Run(30)
	local rows = w:As(c.m1, c.m1.Count.RankingView, "m", "m")
	eq(rows[1].name, "Mira Wells")
	eq(rows[1].score, 10)
	eq(Take("WHISPER", A1, reply), false, "the completed request cannot be replayed")
end)

test("Church keeper discovery: quiet keepers and unverified requesters receive no presence", function()
	local w, c = KeeperProbeWorld()
	c.a1.c.QuietPresence = function() return true end
	WitnessInvite(w, c, "Quiet Rec")
	eq(#w:Sent(c.wes, "NK", "WHISPER", "q"), 1)
	eq(#w:Sent(c.a1, "NK", "WHISPER", "a"), 0)
	eq(SentTo(w, c.wes, c.a1, "w"), 0)
	eq(Outbox(w, c.wes), 1)
	c.a1.c.QuietPresence = function() return false end
	local noted
	local hides = c.a1.c.Moderation.Hides
	c.a1.c.Moderation.Hides = function(sender, guild, readOnly)
		if not readOnly then noted = guild end
		return hides(sender)
	end
	local outside = "NK~1~q~f123~ForeverPvE:Alliance~" .. World.GUILD2
	eq(w:As(c.a1, c.a1.Church.ReceivePresence, "WHISPER", c.vik.name, outside), false)
	eq(noted, nil, "an unverified probe never updates the sender's guild in moderation")
	eq(#w:Sent(c.a1, "NK", "WHISPER", "a"), 0, "a guild claim alone discloses no presence")
	w.off[c.wes.key] = true
	local sameGuild = "NK~1~q~f124~ForeverPvE:Alliance~" .. World.GUILD
	eq(w:As(c.a1, c.a1.Church.ReceivePresence, "WHISPER", c.wes.name, sameGuild), false)
	eq(#w:Sent(c.a1, "NK", "WHISPER", "a"), 0, "moderation still applies to a known guildmate")
end)

test("Church keeper discovery: an unreachable signed Apostle yields to the next one on the bounded cadence", function()
	local w, c = KeeperProbeWorld()
	c.a1.online, c.a2.online = false, true
	local ask = function() return w:Act(c.m1, c.m1.Count.Ask, "m", "m", nil, true) end
	eq(select(2, ask()), "no keeper")
	w:Run(c.m1.Church.PROBE_GAP - 1)
	eq(select(2, ask()), "no keeper")
	eq(#w:Sent(c.m1, "NK", "WHISPER", "q"), 1)
	w:Run(1)
	eq(select(2, ask()), "no keeper")
	local queries = w:Sent(c.m1, "NK", "WHISPER", "q")
	eq(#queries, 2)
	eq(queries[2].target, A2)
	eq(w:As(c.m1, c.m1.Church.KeepersOnline, false)[1].name, A2)
end)

test("Church evidence retries: a delayed whisper is not repeated while queued and a failed send reaches the same keeper", function()
	local w, c = Cast()
	c.a2.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence()
	local recruit = "Delayed Rec"
	local whisper, complete, attempts = c.wes.c.Comm.Whisper, nil, 0
	c.wes.c.Comm.Whisper = function(target, msg, key, urgent, logged, done, options)
		if target == A1 and msg:sub(1, 7) == "NV~1~w~" then
			attempts = attempts + 1
			if attempts == 1 then complete = done; return true end
		end
		return whisper(target, msg, key, urgent, logged, done, options)
	end

	WitnessInvite(w, c, recruit)
	eq(attempts, 1)
	w:Run(c.wes.Count.RESEND_GAP); w:Presence(); w:Tick(); w:Run(15)
	eq(attempts, 1, "a pending send already occupies a queue slot")
	eq(Joins(w, c.a1, "Mira Wells", "m"), 0)
	assert(complete, "the native queue must report completion")
	w:As(c.wes, complete, false, "full")
	w:As(c.wes, c.wes.Count.Flush)
	eq(attempts, 1, "the retry backs off from the real failure")

	w:Run(c.wes.Count.RESEND_GAP); w:Presence(); w:Tick(); w:Run(30)
	eq(attempts, 2)
	eq(Joins(w, c.a1, "Mira Wells", "m"), 1)
	eq(Outbox(w, c.wes), 0, "the keeper's receipt retires the evidence")
end)

test("Church evidence retries: a lost receipt can be recovered without awarding points twice", function()
	local w, c = Cast()
	c.a2.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence()
	local whisper, receipts = c.a1.c.Comm.Whisper, 0
	c.a1.c.Comm.Whisper = function(target, msg, key, urgent, logged, done, options)
		if target == c.wes.name and msg:sub(1, 7) == "NV~1~k~" then
			receipts = receipts + 1
			if receipts == 1 then return true end -- Native send succeeds, but the recipient never hears it.
		end
		return whisper(target, msg, key, urgent, logged, done, options)
	end

	WitnessInvite(w, c, "Unacked Rec")
	w:Run(c.a1.Count.RECEIPT_GAP + 1)
	eq(receipts, 1)
	eq(Joins(w, c.a1, "Mira Wells", "m"), 1)
	eq(Outbox(w, c.wes), 1)

	w:Run(c.wes.Count.RESEND_GAP); w:Presence(); w:Tick(); w:Run(30)
	eq(receipts, 2)
	eq(Joins(w, c.a1, "Mira Wells", "m"), 1, "the same evidence is idempotent")
	eq(Outbox(w, c.wes), 0)
end)

test("1.2.1 Church: a report the keeper who can vouch refused for now goes to him again, however long he was away: a missionary named while he was away has every recruit confirmed on every keeper", function()
	local w, c = Cast()
	-- Aldric, the only keeper who can vouch for Wes, is away; Mira names Nova then (Bera's book and Wes's have her).
	c.a1.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence()
	eq(w:Act(c.m1, c.m1.Church.NameMissionary, "Nova Miss"), true)
	w:Run(2 * 3600)
	w:Presence()
	w.members[World.GUILD] = w.members[World.GUILD] or {}
	for i = 1, 5 do
		local name = "Nova Rec" .. Letters(i)
		w:LogEvent(World.GUILD, "invite", "Nova Miss", name, 0)
		w:LogEvent(World.GUILD, "join", name, nil, 0)
		table.insert(w.members[World.GUILD], name)
	end
	w:RefreshRosters()
	w:ReadLog(c.wes)
	w.log[World.GUILD] = {} -- (a busy guild's log: gone before Aldric could read it himself)
	eq(Outbox(w, c.wes), 5, "Bera can't vouch for Wes: his reports wait")
	-- Five hours, Bera online all along: no round of Wes's is spent on Aldric, who has none of them.
	for _ = 1, 5 do w:Run(3600); w:Presence(); w:Tick() end
	eq(SentTo(w, c.wes, c.a1, "w"), 0)
	-- Aldric is back while Mira is away: Wes's reports reach him before his book has Nova.
	c.m1.online = false
	c.a1.online = true
	w:Presence()
	w:Run(15)
	eq(w:As(c.a1, c.a1.Church.IsPerson, "Nova Miss"), true, "his book has her now")
	eq(Joins(w, c.a1, "Nova Miss", "m"), 0, "refused while his book had not placed her")
	eq(w:As(c.a1, c.a1.Count.Stats).dropped.recruiter, 5)
	-- The next round brings them, to him and from him to Bera.
	w:Run(3600); w:Presence(); w:Tick(); w:Run(30)
	for _, k in ipairs({ c.a1, c.a2 }) do eq(Joins(w, k, "Nova Miss", "m"), 5, k.name) end
	eq(Outbox(w, c.wes), 0)
	-- Bounded: a report a keeper keeps refusing for now goes to him RESEND_TRIES times, then waits for another.
	c.a1.Count.VERIFIED_HOUR = 0
	w:ClearSent()
	w:LogEvent(World.GUILD, "invite", "Nova Miss", "Nova Last", 0)
	w:LogEvent(World.GUILD, "join", "Nova Last", nil, 0)
	table.insert(w.members[World.GUILD], "Nova Last")
	w:RefreshRosters()
	w:ReadLog(c.wes)
	w.log[World.GUILD] = {}
	for _ = 1, 8 do w:Run(3600); w:Presence(); w:Tick() end
	eq(SentTo(w, c.wes, c.a1, "w", "Nova Last"), c.wes.Count.RESEND_TRIES)
	eq(Outbox(w, c.wes), 1)
end)

test("1.2.1 Church: a guildmate's word confirms only a recruit the keeper's own roster or log saw in the guild: 300 made-up names are no recruits; a census-only witness has the smaller budget", function()
	local w, c = Cast()
	for i = 1, 300 do
		eq(select(2, w:As(c.a1, c.a1.Count.TakeEvidence, "Wes Brook-Realm", PairText(w, "Mira Wells", "Ghost Rec" .. Letters(i), 2))), "roster")
	end
	Settle(w)
	for _, k in ipairs({ c.a1, c.a2 }) do eq(Joins(w, k, "Mira Wells", "m"), 0, k.name) end
	-- One the roster shows: confirmed, and told to Bera (the next hour: the made-up ones spent Wes's budget).
	w:Run(3600); w:Presence()
	Join(w, World.GUILD, "Real Rec")
	eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Wes Brook-Realm", PairText(w, "Mira Wells", "Real Rec", 2)), true)
	w:Flush()
	for _, k in ipairs({ c.a1, c.a2 }) do eq(StateOf(w, k, "Real Rec", "Mira Wells"), "credited", k.name) end
	-- One the roster no longer shows (he left at once), whose join Aldric's own read of the log saw: confirmed.
	w:LogEvent(World.GUILD, "join", "Quick Leaver", nil, 2)
	w:ReadLog(c.a1)
	eq(w:As(c.a1, c.a1.Count.TakeEvidence, "Wes Brook-Realm", PairText(w, "Mira Wells", "Quick Leaver", 2)), true)
	eq(StateOf(w, c.a1, "Quick Leaver", "Mira Wells"), "credited")
	-- An officer of Olympus Ember the chats verify only through the census, at Bera's: EVIDENCE_HOUR, not VERIFIED_HOUR.
	c.a2.c.Channels.VerifiedLevel = function(n, g)
		if Key(n) == Key("Ola Officer") and g == World.GUILD then return 2, true, 1 end
		return 1, false
	end
	for i = 1, c.a2.Count.EVIDENCE_HOUR do
		eq(w:As(c.a2, c.a2.Count.TakeEvidence, "Ola Officer-Realm", PairText(w, "Mira Wells", "Cen Rec" .. Letters(i), 2)), true)
	end
	eq(select(2, w:As(c.a2, c.a2.Count.TakeEvidence, "Ola Officer-Realm", PairText(w, "Mira Wells", "Cen Over", 2))), "budget")
	eq(w:As(c.a2, c.a2.Count.TakeEvidence, World.COUNCILLOR, PairText(w, "Mira Wells", "Sig Rec", 2)), true, "the signed keep the larger one")
end)

test("1.2.1 Church: a registration is dated when a keeper hears it and takes no recruit a live invite holds: one whispered six days back after the invite is refused, one for a recent arrival is no recruit", function()
	local w, c = Cast()
	local B = ns.Codec.Base36
	local function Reg(k, name, ago) return w:As(k, k.Count.TakeEvidence, "Nils Ford-Realm", ("NV~1~g~%s-Realm~%s"):format(name, B(w.clock - ago))) end
	-- Mira invites Stolen Kid; only her client has read the log yet: pending. Nils's registration "six days ago" is refused.
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Stolen Kid", 1)
	w:LogEvent(World.GUILD, "join", "Stolen Kid", nil, 0)
	Join(w, World.GUILD, "Stolen Kid")
	w:ReadLog(c.m1)
	eq(StateOf(w, c.a1, "Stolen Kid", "Mira Wells"), "pending")
	for _, k in ipairs({ c.a1, c.a2 }) do eq(select(2, Reg(k, "Stolen Kid", 6 * DAY)), "taken", k.name) end
	w:ReadLog(c.wes)
	Settle(w, 700); Settle(w, 700)
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(StateOf(w, k, "Stolen Kid", "Mira Wells"), "credited", k.name)
		eq(StateOf(w, k, "Stolen Kid", "Nils Ford"), nil, k.name)
	end
	-- Recent Arrival joined Olympus Vale three days ago, no Church person's invite: registered "six days ago", he is no recruit.
	Join(w, World.GUILD2, "Recent Arrival")
	w:Tick()
	w:Run(3 * DAY)
	w:Presence()
	eq(Reg(c.a1, "Recent Arrival", 6 * DAY), true)
	eq(Rec(w, c.a1, "Recent Arrival", "Nils Ford").tc, w.clock, "dated when Aldric heard it")
	Settle(w, 700)
	eq(StateOf(w, c.a1, "Recent Arrival", "Nils Ford"), "transfer")
	eq(w:As(c.a1, c.a1.Count.Own, Key("Nils Ford"), "a").points, 0)
end)

test("1.2.1 Church: no receipt goes to a keeper (one before 1.2.1 counts each line against its budget for him); a keeper's report its own ledger refused is tried again there, then goes to the others", function()
	local w, c = Cast()
	w:Presence()
	-- Bera invites in Olympus Vale; her client reports, Aldric takes it: Mira gets receipts, Bera none.
	w:LogEvent(World.GUILD2, "invite", "Bera Stone", "Vale Rec", 1)
	w:LogEvent(World.GUILD2, "join", "Vale Rec", nil, 0)
	Join(w, World.GUILD2, "Vale Rec")
	w:LogEvent(World.GUILD, "invite", "Mira Wells", "Ember Rec", 1)
	w:LogEvent(World.GUILD, "join", "Ember Rec", nil, 0)
	Join(w, World.GUILD, "Ember Rec")
	w:ClearSent()
	w:ReadLog(c.a2); w:ReadLog(c.m1)
	w:Run(30)
	eq(StateOf(w, c.a1, "Vale Rec", "Bera Stone"), "pending")
	eq(SentTo(w, c.a1, c.a2, "k"), 0, "no receipt to a keeper")
	eq(SentTo(w, c.a1, c.m1, "k") >= 1, true, "a missionary's")
	eq(Outbox(w, c.a2), 0)
	-- Her own ledger refuses her next report (her budget for herself spent): it goes to Aldric, and an hour later her
	-- own ledger takes it and she sends it once more.
	local budget = c.a2.Count.VERIFIED_HOUR
	c.a2.Count.VERIFIED_HOUR = 0
	w:LogEvent(World.GUILD2, "invite", "Bera Stone", "Vale Late", 0)
	w:LogEvent(World.GUILD2, "join", "Vale Late", nil, 0)
	Join(w, World.GUILD2, "Vale Late")
	w:ReadLog(c.a2)
	w:Run(30)
	eq(StateOf(w, c.a2, "Vale Late", "Bera Stone"), nil)
	eq(StateOf(w, c.a1, "Vale Late", "Bera Stone"), "pending")
	eq(Outbox(w, c.a2), 1)
	eq(SentTo(w, c.a2, c.a1, "w", "Vale Late"), 1)
	c.a2.Count.VERIFIED_HOUR = budget
	w:Run(3600); w:Presence(); w:Tick(); w:Run(30)
	eq(Rec(w, c.a2, "Vale Late", "Bera Stone").s, 1, "her own ledger took her report")
	eq(Outbox(w, c.a2), 0)
	eq(SentTo(w, c.a2, c.a1, "w", "Vale Late"), 2, "and it went once more")
	eq(SentTo(w, c.a1, c.a2, "k"), 0)
end)

-- 1.2.3 (the Church keeper's spikes on the author's laptop, a desk with 1,932 records in a 1,000-member
-- guild): the credits kept while the ledger stays the same, the desk's checks a few a tick, the roster
-- memory written once a day, names' keys kept, the top 3 and the due checks worked out when something
-- changed, the ledger's first upkeep after the login's other work.

-- A fixture ledger with every kind of claim (every name invented), straight into a keeper's saved ledger:
-- credited and pending invites over 80 days and both guilds, stays, tries, transfers, alts; registrations
-- open, expired, withdrawn, arrived and arrived late; two or three claims on one recruit (a confirmed one
-- first, then the earliest, then the smaller id); an archived recruit; the archive's records and the
-- person lines. "Fix Reg Cross" reaches its REG_DAYS 90 seconds after the fixture's time.
local FIX_PEOPLE = { A1, A2, "Mira Wells", "Nils Ford", "Out Sider" }
local function FixtureLedger(w, K)
	local now, H, W = w.clock, 3600, { "wes brook" }
	local l = w:As(K, K.Count.Led)
	l.wv, l.gone = 2, l.gone or {}
	local function Put(recruit, by, rec)
		rec.n, rec.bn, rec.u, rec.kind = recruit, ns.ShortName(by), now, rec.kind or "i"
		l.r[Key(recruit) .. ":" .. Key(by)] = rec
	end
	for i = 1, 60 do
		local tj = now - ((i * 37) % (80 * 24)) * H
		Put("Fix Rec" .. Letters(i), FIX_PEOPLE[i % 5 + 1], { g = i % 3 == 0 and World.GUILD2 or World.GUILD, tc = tj - (i % 4) * H, tj = tj,
			ws = i % 4 ~= 0 and W or nil, s = i % 4 == 0 and 1 or nil, c = i % 2 == 0 and 1 or nil,
			y = (i % 6 == 0 and 1) or (i % 11 == 0 and 0) or nil, q7 = i % 7 == 0 and 2 or nil, t = i % 13 == 0 and 1 or nil,
			a = i % 17 == 0 and 1 or nil })
	end
	local function Dup(j, by, rec) Put("Fix Dup" .. Letters(j), by, rec) end
	Dup(1, A1, { g = World.GUILD, tc = now - 50 * H, tj = now - 49 * H, ws = W })
	Dup(1, "Mira Wells", { g = World.GUILD, tc = now - 60 * H, tj = now - 59 * H, s = 1 })
	Dup(2, A2, { g = World.GUILD2, tc = now - 40 * H, tj = now - 39 * H, ws = W })
	Dup(2, "Nils Ford", { g = World.GUILD, tc = now - 30 * H, tj = now - 29 * H, ws = W })
	Dup(3, A1, { g = World.GUILD, tc = now - 20 * H, tj = now - 19 * H, ws = W })
	Dup(3, A2, { g = World.GUILD, tc = now - 20 * H, tj = now - 19 * H, ws = W })
	Dup(4, "Mira Wells", { kind = "g", tc = now - 5 * DAY })
	Dup(4, "Nils Ford", { g = World.GUILD, tc = now - 2 * DAY, tj = now - 2 * DAY + H, s = 1 })
	Dup(5, A1, { kind = "g", tc = now - 20 * DAY })
	Dup(5, A2, { g = World.GUILD2, tc = now - 3 * DAY, tj = now - 3 * DAY + H, ws = W })
	Dup(6, "Nils Ford", { kind = "g", tc = now - 4 * DAY, x = 1 })
	Dup(6, "Mira Wells", { g = World.GUILD, tc = now - 3 * DAY, tj = now - 3 * DAY + H, ws = W })
	Dup(7, A1, { g = World.GUILD, tc = now - 6 * DAY, tj = now - 6 * DAY + H, ws = W })
	Dup(7, "Mira Wells", { g = World.GUILD, tc = now - 5 * DAY, tj = now - 5 * DAY + H, ws = W })
	Dup(8, A1, { g = World.GUILD, tc = now - 9 * DAY, tj = now - 9 * DAY + H, ws = W, t = 1 })
	Dup(8, "Mira Wells", { g = World.GUILD, tc = now - 10 * DAY, tj = now - 10 * DAY + H, s = 1 })
	Dup(8, "Nils Ford", { g = World.GUILD, tc = now - 8 * DAY, tj = now - 8 * DAY + H, ws = W })
	l.gone[Key("Fix Dup" .. Letters(7)) .. ":"] = now - DAY
	Put("Fix Reg Open", "Nils Ford", { kind = "g", tc = now - 3 * DAY })
	Put("Fix Reg Cross", "Mira Wells", { kind = "g", tc = now - K.Count.REG_DAYS * DAY + 90 })
	Put("Fix Reg Arrived", A2, { kind = "g", tc = now - 10 * DAY, tj = now - 4 * DAY, g = World.GUILD2, ws = W, c = 1 })
	Put("Fix Reg Late", A1, { kind = "g", tc = now - 30 * DAY, tj = now - 2 * DAY, g = World.GUILD })
	Put("Fix Reg Old", "Mira Wells", { kind = "g", tc = now - 20 * DAY - 7 * H })
	l.p[Key(A1)] = { n = "Aldric Vane", pub = true, pat = now - DAY, ap = 45, aj = 4, ay = 1, u = now }
	l.p[Key("Mira Wells")] = { n = "Mira Wells", pub = true, pat = now - DAY, ap = 15, aj = 1, ay = 1, u = now }
	l.p[Key("Nils Ford")] = { n = "Nils Ford", pub = true, pat = now - DAY, u = now }
	l.p[Key(A2)] = { n = "Bera Stone", pub = false, pat = now - DAY, u = now }
	l.arc = { [Key(A1)] = { [Key("Fix Arc A")] = { h = now - 3 * DAY, t = now - DAY, y = 1, l = 1 }, [Key("Fix Arc B")] = { h = now - 20 * DAY, t = now, l = 1 } },
		[Key("Mira Wells")] = { [Key("Fix Arc C")] = { h = now - 33 * DAY, t = now, l = 1 } } }
	for _, n in ipairs({ "Fix Arc A", "Fix Arc B", "Fix Arc C" }) do l.gone[Key(n) .. ":"] = now - DAY end
	w:As(K, K.Count.Changed)
	return l
end

-- What a keeper shows of its ledger, one line each: every ranking (list and window), every person's detail
-- (a registration's time from `base`), every record's state, every recruit's claim, the top 3.
local function CountResults(w, K, base)
	local out = {}
	local function N(v) return type(v) == "number" and ("%.17g"):format(v) or tostring(v) end
	for _, list in ipairs({ "a", "m", "c" }) do
		for _, window in ipairs({ "w", "m", "a" }) do
			for _, r in ipairs(w:As(K, K.Count.Ranking, list, window)) do
				out[#out + 1] = table.concat({ "rank", list, window, N(r.rank), r.key, r.name, r.role, N(r.score), N(r.own), N(r.share), N(r.levels[1]),
					N(r.levels[2]), N(r.levels[3]), N(r.joins), N(r.stays), N(r.net), tostring(r.pub) }, " ")
			end
		end
	end
	for _, who in ipairs({ A1, A2, "Mira Wells", "Nils Ford", "Out Sider", World.HEAD }) do
		for _, window in ipairs({ "w", "m", "a" }) do
			local lines, share = w:As(K, K.Count.DetailLines, Key(who), window)
			for i, d in ipairs(lines) do
				out[#out + 1] = table.concat({ "detail", Key(who), window, N(i), d[1], N(d[2]), N(d[1] == "r" and d[3] - base or d[3]), N(d[4]), N(d[5]) }, " ")
			end
			out[#out + 1] = table.concat({ "share", Key(who), window, N(share) }, " ")
		end
	end
	local recs, ids, seen = w:As(K, K.Count.Led).r, {}, {}
	for id in pairs(recs) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		out[#out + 1] = "state " .. id .. " " .. tostring(w:As(K, K.Count.StateOf, id))
		local xk = id:match("^([^:]+):")
		if not seen[xk] then
			seen[xk] = true
			local cr = w:As(K, K.Count.CreditOf, xk)
			out[#out + 1] = table.concat({ "credit", xk, cr and cr.id or "-", cr and cr.state or "-", tostring(cr ~= nil and cr.r == recs[cr.id]) }, " ")
		end
	end
	local top = w:As(K, K.Count.ComputeTop3)
	out[#out + 1] = "top a " .. table.concat(top.a, ",")
	out[#out + 1] = "top m " .. table.concat(top.m, ",")
	return out
end
local function SameLines(got, want, label)
	for i = 1, math.max(#got, #want) do
		if got[i] ~= want[i] then error(("%s, line %d: expected %s, got %s"):format(label, i, tostring(want[i]), tostring(got[i])), 2) end
	end
end

test("1.2.3 Church: the credits are what 1.2.2 worked out: every ranking, detail, state and claim of a fixture ledger, before and after a registration reaches its 14 days", function()
	local w, c = Cast()
	local K = c.a1
	FixtureLedger(w, K)
	local t0 = w.clock
	-- (The published 1.2.2's own results on this fixture, run on its code: tests/fixtures/church-credits-1.2.2.lua.)
	local want = assert(loadfile(ROOT .. "tests/fixtures/church-credits-1.2.2.lua"))()
	local before = CountResults(w, K, t0)
	SameLines(before, want.before, "90 s before Fix Reg Cross's 14 days")
	w.clock = t0 + 120
	local after = CountResults(w, K, t0)
	SameLines(after, want.after, "30 s after")
	-- (What the fixture holds: every state, and the registration that crossed.)
	local states = {}
	for _, line in ipairs(after) do local s = line:match("^state .* (%a+)$") if s then states[s] = true end end
	for _, s in ipairs({ "credited", "pending", "open", "taken", "transfer", "alt", "withdrawn", "expired" }) do eq(states[s], true, s) end
	local cross = "state " .. Key("Fix Reg Cross") .. ":" .. Key("Mira Wells")
	local was, now
	for _, line in ipairs(before) do if line:find(cross, 1, true) == 1 then was = line end end
	for _, line in ipairs(after) do if line:find(cross, 1, true) == 1 then now = line end end
	eq(was, cross .. " open"); eq(now, cross .. " expired")
end)

test("1.2.3 Church: the credits are kept while the ledger stays the same, through public rows and an upkeep that lets nothing go; worked out again when the ledger changes, when a registration reaches its 14 days, CREDITS_KEEP at most", function()
	local w, c = Cast()
	local K = c.a1
	FixtureLedger(w, K)
	local t0 = w.clock
	local cross = Key("Fix Reg Cross") .. ":" .. Key("Mira Wells")
	local C1 = w:As(K, K.Count.Credits)
	eq(C1.states[cross], "open")
	w.clock = t0 + 60
	eq(w:As(K, K.Count.Credits), C1, "a minute later, the same (1.2.2 worked them out again every minute)")
	-- The public rows a desk broadcasts are the tab's: the ledger did not change.
	c.author.online = true
	w:Presence()
	w:Act(c.author, c.author.Church.SetPublic, true)
	local _, at = w:As(K, K.Church.Public)
	local B = ns.Codec.Base36
	eq(w:As(K, K.Count.TakePublicRow, A2, ("NR~1~p~%s~m~1~Mira Wells~100~200"):format(B(at))), true)
	eq(w:As(K, K.Count.TakePublicCount, A2, ("NR~1~n~%s~m~1"):format(B(at))), true)
	eq(w:As(K, K.Count.Credits), C1, "public rows kept")
	local fired = #K.fired
	eq(w:As(K, K.Count.Prune), false, "nothing to let go")
	eq(#K.fired, fired, "nothing changed, nothing to redraw")
	eq(w:As(K, K.Count.Credits), C1, "an upkeep that let nothing go kept them")
	-- Fix Reg Cross reaches its 14 days.
	w.clock = t0 + 90
	eq(w:As(K, K.Count.Credits), C1, "its last second open")
	w.clock = t0 + 91
	local C2 = w:As(K, K.Count.Credits)
	eq(C2 ~= C1, true); eq(C2.states[cross], "expired")
	-- CREDITS_KEEP at most.
	w.clock = t0 + 91 + K.Count.CREDITS_KEEP
	eq(w:As(K, K.Count.Credits), C2)
	w.clock = w.clock + 1
	local C3 = w:As(K, K.Count.Credits)
	eq(C3 ~= C2, true)
	-- A ledger change: at once.
	local id = Key("Fix New") .. ":" .. Key("Nils Ford")
	w:As(K, K.Count.MergeIn, id, { n = "Fix New", bn = "Nils Ford", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	local C4 = w:As(K, K.Count.Credits)
	eq(C4 ~= C3, true); eq(C4.states[id], "credited")
	local cr = w:As(K, K.Count.CreditOf, Key("Fix New"))
	eq(cr.id, id); eq(cr.state, "credited"); eq(cr.r, w:As(K, K.Count.Led).r[id])
	eq(w:As(K, K.Count.CreditOf, Key("Nobody Here")), nil)
	-- A new ledger (a malformed one replaced, another realm group's): never the old one's credits.
	w:As(K, K.Church.Store).led = { v = 1, wv = 2, r = {}, p = {}, from = {} }
	eq(w:As(K, K.Count.StateOf, id), nil)
end)

test("1.2.3 Church: the desk sends CHECKS_TICK seen-checks a tick, the checks of one tick sharing one list of who may answer; the hour's CHECKS_HOUR still go within minutes", function()
	local w, c = Cast()
	local K = c.a1
	for i = 1, 40 do
		local recruit = "Desk Rec" .. Letters(i)
		w:As(K, K.Count.MergeIn, Key(recruit) .. ":" .. Key("Mira Wells"), { n = recruit, bn = "Mira Wells", g = World.GUILD, kind = "i",
			tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	end
	w:ClearSent()
	local function Sent() return #w:Sent(K, "NS", "CHANNEL", "q") end
	local function Lists()
		local out, n = {}, 0
		for _, ch in pairs(w:As(K, K.Count.OpenChecks)) do
			if not out[ch.expected] then out[ch.expected], n = true, n + 1 end
		end
		return out, n
	end
	w:As(K, K.Count.DeskTick, w.clock)
	eq(Sent(), K.Count.CHECKS_TICK, "three in the first tick, not the hour's thirty")
	local first, n = Lists()
	eq(n, 1, "one list for the tick's checks")
	local list = next(first)
	eq(list[Key("Wes Brook")], "roster", "a guildmate on our roster may answer")
	eq(list[Key(A2)], "keeper", "a keeper heard may relay his roster's")
	-- A guildmate who arrived after the first tick is on the next tick's list only.
	Join(w, World.GUILD, "Late Mate")
	w:Run(30)
	w:As(K, K.Count.DeskTick, w.clock)
	eq(Sent(), 2 * K.Count.CHECKS_TICK)
	local lists, n2 = Lists()
	eq(n2, 2)
	eq(list[Key("Late Mate")], nil, "not asked by the first tick's checks")
	for l in pairs(lists) do if l ~= list then eq(l[Key("Late Mate")], "roster") end end
	-- The rest of the hour's thirty within minutes, then nothing more that hour.
	for _ = 1, 12 do w:Run(30); w:As(K, K.Count.DeskTick, w.clock) end
	eq(Sent(), K.Count.CHECKS_HOUR, "thirty within seven minutes")
	w:Run(3600)
	w:As(K, K.Count.DeskTick, w.clock)
	eq(Sent(), K.Count.CHECKS_HOUR + K.Count.CHECKS_TICK, "the next hour's")
end)

test("1.2.3 Church: the desk looks for due checks when its ledger changes, else every DUE_EVERY; a record a keeper's line brought without its join stops no check", function()
	local w, c = Cast()
	local K = c.a1
	local B = ns.Codec.Base36
	-- (An invite's line whose join is "-": its record has no stay to check.)
	local line = ("NL~1~r~No Join~Mira Wells~-~i~%s~-~s00~wes brook~%s"):format(B(w.clock - DAY), B(w.clock))
	eq(w:As(K, K.Count.TakeLine, A2, line), true)
	-- A registration whose day-1 check is due 100 seconds from now (its day-0 check done).
	local id = Key("Reg Due") .. ":" .. Key("Mira Wells")
	w:As(K, K.Count.MergeIn, id, { n = "Reg Due", bn = "Mira Wells", kind = "g", tc = w.clock - DAY + 100, rq = 1 }, false)
	w:ClearSent()
	local function Checks(name)
		local n = 0
		for _, e in ipairs(w:Sent(K, "NS", "CHANNEL", "q")) do if e.msg:find("~" .. name .. "~", 1, true) then n = n + 1 end end
		return n
	end
	w:As(K, K.Count.DeskTick, w.clock)
	eq(Checks("Reg Due"), 0, "not due yet")
	w.clock = w.clock + 200
	w:As(K, K.Count.DeskTick, w.clock)
	eq(Checks("Reg Due"), 0, "due now, the ledger unchanged: looked for again DUE_EVERY after the last time")
	w.clock = w.clock + K.Count.DUE_EVERY - 200
	w:As(K, K.Count.DeskTick, w.clock)
	eq(Checks("Reg Due"), 1, "DUE_EVERY later")
	-- A new record: its check is looked for at the desk's next tick.
	w:As(K, K.Count.MergeIn, Key("Fresh One") .. ":" .. Key("Mira Wells"), { n = "Fresh One", bn = "Mira Wells", g = World.GUILD, kind = "i",
		tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	w.clock = w.clock + 30
	w:As(K, K.Count.DeskTick, w.clock)
	eq(Checks("Fresh One"), 1, "the ledger changed: at once")
end)

test("1.2.3 Church: the roster memory, scanned again the same day, writes no name again and holds what writing them all would; a new day, another guild, a name the bounding let go: written again", function()
	local w, c = Cast()
	local cl = c.wes
	cl.Count.random = function(a, b) if b == 50 then return 2 end return a end -- (the bounding only past MEMORY_MAX)
	local writes = 0
	cl.ns.Codec = setmetatable({ Base36 = function(n) writes = writes + 1 return ns.Codec.Base36(n) end }, { __index = ns.Codec })
	w.members[World.GUILD] = {}
	for i = 1, 30 do table.insert(w.members[World.GUILD], "Mem Row" .. Letters(i)) end
	w:RefreshRosters()
	local rows = #cl.c.Roster.members
	local function Remember() writes = 0; return w:As(cl, cl.Count.Remember, false) end
	local function Fact(name) return w:As(cl, cl.Count.Fact, name) end
	local day0 = math.floor(w.clock / DAY)
	eq(Remember(), true)
	eq(writes, 2 * rows, "each name written once (its first and last day)")
	local saved = World.Copy(w:As(cl, cl.Church.Store).mem.n)
	-- The next scan the same day: nothing written, the memory as it was.
	w.clock = w.clock + 60
	w:RefreshRosters()
	eq(Remember(), true)
	eq(writes, 0, "nothing written again")
	local mem = w:As(cl, cl.Church.Store).mem
	for k, v in pairs(saved) do eq(mem.n[k], v, k) end
	-- A name new today is written.
	Join(w, World.GUILD, "Mem Late")
	eq(Remember(), true)
	eq(writes, 2)
	eq(Fact("Mem Late").first, day0)
	-- The next day: every name's last day.
	w.clock = (day0 + 1) * DAY + 10
	w:RefreshRosters()
	Remember()
	eq(writes, 2 * (rows + 1))
	local f = Fact("Mem Rowb")
	eq(f.first, day0); eq(f.last, day0 + 1); eq(f.guild, World.GUILD); eq(f.now, true)
	-- The bounding lets one go: written again when next seen.
	cl.Count.MEMORY_MAX = rows
	w:RefreshRosters()
	Remember()
	local gone
	for _, row in ipairs(cl.c.Roster.members) do if not mem.n[Key(row.full)] then gone = row.full end end
	assert(gone, "one name let go")
	cl.Count.MEMORY_MAX = 2500
	w:RefreshRosters()
	Remember()
	eq(writes, 2, "only the one let go")
	eq(Fact(gone).last, day0 + 1)
	-- Another guild: written there from its first day.
	cl.guild = World.GUILD2
	w:RefreshRosters()
	Remember()
	eq(writes, 2 * #cl.c.Roster.members)
	eq(Fact("Wes Brook").guild, World.GUILD2); eq(Fact("Wes Brook").first, day0 + 1)
end)

test("1.2.3 Church: a name's key is kept when no realm group can change it (\"First Surname-Realm\", or no realm), KEY_MEMO_MAX names at most; a \"First-Surname\" one is worked out every time", function()
	local w = World.New({})
	local cl = w:Client("Key Keeper")
	local folds = 0
	cl.ns.Fold = function(s) folds = folds + 1 return ns.Fold(s) end
	local function K(name) return w:As(cl, cl.Church.Key, name) end
	local split = ns.splitNames
	local ok, err = pcall(function()
		ns.splitNames = true
		eq(K("Ann Bell-Realm"), "ann bell"); eq(K("Ann Bell-Realm"), "ann bell"); eq(K("Ann Bell"), "ann bell")
		eq(folds, 2, "each name folded its first time only")
		-- "Ann-Bell", as the game's unit functions give it: its key depends on whether "Bell" is a realm here.
		eq(K("Ann-Bell"), "ann bell")
		ns.splitNames = nil
		eq(K("Ann-Bell"), "ann", "never kept: a client that splits no names reads Bell as a realm")
		eq(K("Ann Bell-Realm"), "ann bell")
		eq(folds, 4)
		eq(K(""), nil); eq(K("-"), nil); eq(K(7), nil); eq(K("-Realm"), nil)
		-- Bounded: the memory starts over past KEY_MEMO_MAX, every key still right.
		cl.Church.KEY_MEMO_MAX = 3
		for i = 1, 10 do eq(K("Memo Name" .. Letters(i) .. "-Realm"), "memo name" .. Letters(i)) end
		eq(K("Ann Bell-Realm"), "ann bell")
		eq(K("\195\137lan Vert-Realm"), "\195\169lan vert", "a capital accented letter folded")
	end)
	ns.splitNames = split
	if not ok then error(err, 0) end
end)

test("1.2.3 Church: the top 3 is worked out again only when the ledger, the book, the hour or the top 3 held changed, and when TOP_EVERY sends it", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	local A = c.author
	local function Give(by, recruit)
		w:As(A, A.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = by, g = World.GUILD, kind = "i", tc = w.clock - 7200,
			tj = w.clock - 3600, ws = { "wes brook" } }, false)
	end
	-- (Two hundred seconds before an hour: the new hour below comes well within TOP_EVERY of the last send.)
	local hour = (math.floor(w.clock / 3600) + 1) * 3600
	w.clock = hour - 200
	w:Presence()
	Give("Mira Wells", "Top Reca")
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.m2, c.m2.Count.SetPublicRow, true)
	w:Act(A, A.Church.SetPublic, true)
	local computed, real = 0, A.Count.ComputeTop3
	A.Count.ComputeTop3 = function(...) computed = computed + 1 return real(...) end
	local function Send() local sent = w:As(A, A.Count.SendTop, w.clock); w:Flush() return sent end
	local function Top() return table.concat(w:As(c.wes, c.wes.Church.Top3).missionaries, ",") end
	eq(Send(), true); eq(computed, 1); eq(Top(), "Mira Wells")
	w.clock = w.clock + 30
	eq(Send(), false); eq(computed, 1, "nothing changed: not worked out again")
	-- The ledger changed: worked out again, and a new top goes at once.
	Give("Nils Ford", "Top Recb"); Give("Nils Ford", "Top Recc")
	w.clock = w.clock + 30
	eq(Send(), true); eq(computed, 2); eq(Top(), "Nils Ford,Mira Wells")
	w.clock = w.clock + 30
	eq(Send(), false); eq(computed, 2)
	-- The book changed (a missionary named): worked out again; the same top stays unsent.
	w:Act(c.m1, c.m1.Church.NameMissionary, "Wes Brook")
	w.clock = w.clock + 30
	eq(Send(), false); eq(computed, 3)
	-- A new hour (the last 30 days moved on).
	w.clock = hour + 10
	eq(Send(), false); eq(computed, 4)
	-- TOP_EVERY: worked out again and sent.
	w.clock = w.clock + A.Count.TOP_EVERY
	eq(Send(), true); eq(computed, 5)
	-- Another root's top 3 held here: ours, which differs, goes at once.
	eq(w:As(A, A.Count.TakeTop, World.KING, "NR~1~t~" .. ns.Codec.Base36(w.clock + 1) .. "~Aldric Vane~Mira Wells"), true)
	w.clock = w.clock + 30
	eq(Send(), true); eq(computed, 6); eq(Top(), "Nils Ford,Mira Wells")
end)

-- 1.2.3, after review: the missionaries' crook comes of this top 3, and the comments (and the handoff)
-- said the Head's or the King's client sends it too. SendTop takes a keeper whose root is H or W, but
-- the Head is the King (Church.IsHead), whose root is K, and the King is no keeper (Count.Tick leaves
-- him out): only the author's client sends it, while it is online with the ranking open. A word from
-- the King's is still taken (the 1.1.6 test above). Whether the King's client should send it too is
-- the owner's call (the King's screen's weight), not this test's.
test("1.2.3 Church: the top 3 goes out from the author's client alone: the King's, online with the ranking open, sends none (root K, no keeper; the Head is the King); the author's sends it, and the King's client takes it", function()
	local w, c = Cast()
	c.author.online, c.king.online = true, true
	w:Presence()
	local A, K = c.author, c.king
	for i, by in ipairs({ "Mira Wells", "Nils Ford" }) do
		for j = 1, i do
			w:As(A, A.Count.MergeIn, "r " .. i .. j .. ":" .. Key(by), { n = "R B" .. i .. j, bn = by, g = World.GUILD, kind = "i",
				tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
		end
	end
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.m2, c.m2.Count.SetPublicRow, true)
	w:Act(A, A.Church.SetPublic, true)
	eq(w:As(K, K.Church.IsHead, World.KING), true, "the Head is the King")
	eq(w:As(K, K.Church.RootCode, World.KING), "K", "his root: K, never H")
	eq(w:As(K, K.Church.IsKeeper, World.KING), false, "no keeper")
	eq(w:As(A, A.Church.RootCode, World.AUTHOR), "W")
	w:ClearSent()
	-- The King's client: its ticks, past TOP_EVERY, send none; SendTop itself refuses.
	w:Tick({ K })
	w:Run(K.Count.TOP_EVERY + 1)
	w:Tick({ K })
	eq(w:As(K, K.Count.SendTop, w.clock), false, "the King's client sends no top 3")
	eq(#w:Sent(K, "NR", nil, "t"), 0)
	eq(w:As(c.wes, c.wes.Church.Top3), nil, "nobody holds one yet")
	-- The author's: sent on CHANNEL, and taken everywhere, the King's client too.
	w:Tick({ A })
	eq(#w:Sent(A, "NR", "CHANNEL", "t"), 1, "the author's client sends it")
	eq(w:As(K, K.Church.Top3).missionaries[1], "Nils Ford", "the King's client holds it")
	eq(w:As(c.wes, c.wes.Church.Top3).missionaries[1], "Nils Ford")
end)

test("1.2.3 Church: a keeper's first upkeep of its ledger comes PRUNE_AFTER after its first tick, then hourly; marks past GONE_MAX go, the oldest first", function()
	local w, c = Cast()
	local K = c.a1
	local l = w:As(K, K.Count.Led)
	local function Old(recruit)
		local id = Key(recruit) .. ":" .. Key("Mira Wells")
		l.r[id] = { n = recruit, bn = "Mira Wells", g = World.GUILD, kind = "i", tc = w.clock - 130 * DAY, tj = w.clock - 130 * DAY + 3600,
			ws = { "wes brook" }, u = w.clock }
		w:As(K, K.Count.Changed)
		return id
	end
	local id = Old("Very Old")
	w:Tick({ K })
	eq(l.r[id] ~= nil, true, "not with the login's first tick")
	w:Run(K.Count.PRUNE_AFTER - 1); w:Tick({ K })
	eq(l.r[id] ~= nil, true)
	w:Run(1); w:Tick({ K })
	eq(l.r[id], nil, "PRUNE_AFTER later: let go")
	eq(l.p[Key("Mira Wells")].aj, 1, "into her archive")
	local id2 = Old("Older Still")
	w:Run(1800); w:Tick({ K })
	eq(l.r[id2] ~= nil, true, "then hourly")
	w:Run(1800); w:Tick({ K })
	eq(l.r[id2], nil)
	-- Marks of what the ledger let go: GONE_MAX at most, the oldest go first.
	local saved = K.Count.GONE_MAX
	K.Count.GONE_MAX = 3
	local ok, err = pcall(function()
		local g = {}
		for i = 1, 5 do g["mark " .. Letters(i) .. ":"] = w.clock - 10 + i end
		l.gone = g
		eq(w:As(K, K.Count.Prune), true)
		eq(g["mark b:"], nil); eq(g["mark c:"], nil)
		eq(g["mark d:"] ~= nil and g["mark e:"] ~= nil and g["mark f:"] ~= nil, true)
	end)
	K.Count.GONE_MAX = saved
	if not ok then error(err, 0) end
end)

-- The global ledger's relays (the keepers, the King, the signed High Council): what a relay's pages
-- show, whom a catch-up asks, and where a keeper's verified word goes.

-- A /reload, or a login the next day: the same character's saved data (its SavedVariables), nothing
-- of the session (its memory, whom it asked), the files loaded again (INIT). (As tests/church.lua's.)
local function Reload(w, cl)
	cl.online = false
	-- A real /reload discards that Lua session and its timers, including a scheduled sweep.
	for i = #w.timers, 1, -1 do if w.timers[i].cl == cl then table.remove(w.timers, i) end end
	local again = w:Client(cl.name, { guild = cl.guild or false, rank = cl.rank, rdb = cl.ns.rdb })
	w:As(again, again.ns.Fire, "INIT")
	return again
end
-- Whether a client's page shows another client's numbers (RankingView's third value).
local function Remote(w, cl, list, window)
	return w:As(cl, function() return select(3, cl.Count.RankingView(list, window)) end)
end
local function JoinsOn(w, cl, by, list, window)
	for _, r in ipairs((w:As(cl, cl.Count.RankingView, list or "m", window or "m"))) do
		if r.key == Key(by) then return r.joins end
	end
end

test("global Church ledger: a council relay whose copy is behind shows a keeper's numbers, not its own smaller copy; its own copy only with nothing kept and no keeper online", function()
	local w, c = Cast()
	local council = w:Client(World.COUNCILLOR)
	w:Presence()
	-- Aldric credits three of Mira's recruits; nothing reaches the council's copy (no push, no catch-up).
	for i = 1, 3 do Give(w, c.a1, "Behind Rec" .. Letters(i), "Mira Wells", 2) end
	eq(JoinsOn(w, c.a1, "Mira Wells"), 3, "the keeper's own page")
	eq(Rec(w, council, "Behind Recb", "Mira Wells"), nil, "the council's copy is behind")
	-- Its page asks a keeper, as every audience page does (a 1.2.5.1 keeper answers that ask; it drops
	-- the council's catch-up), and shows that keeper's numbers.
	eq(Remote(w, council, "m", "m"), true, "not its own copy while a keeper is online")
	local ok, why = w:As(council, council.Count.Ask, "m", "m", nil, true)
	eq(ok, true, "asked a keeper (" .. tostring(why) .. ")")
	local q = w:Sent(council, "NR", "WHISPER", "q")
	eq(Key(q[#q].target), Key(A1), "the desk")
	w:Run(30)
	eq(JoinsOn(w, council, "Mira Wells"), 3, "the keeper's numbers")
	-- Only a keeper answers a page, and only a keeper's rows are taken.
	eq(select(2, w:As(council, council.Count.Answer, "Nils Ford-Realm", "m", "m")), "not keeper")
	eq(select(2, w:As(c.m2, c.m2.Count.TakeAnswerLine, World.COUNCILLOR, "NR~1~e~m~m~-~0~0")), "keeper")
	-- Every keeper offline: the page keeps that answer, not the smaller copy.
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence()
	eq(Rec(w, council, "Behind Recb", "Mira Wells"), nil, "still behind")
	eq(JoinsOn(w, council, "Mira Wells"), 3, "kept while no keeper is online")
	-- A page it never had an answer for, with no keeper online: its own copy, shown as its own.
	eq(Remote(w, council, "m", "a"), false, "nothing kept, no keeper online")
end)

test("global Church ledger: an audience page asks in the desk's order, the Apostles before the author: not the author's client while an Apostle is online", function()
	local Z = "Zed Last-Realm"
	local w = World.New({ apostles = { A1, A2, Z }, head = false })
	local c = { a1 = w:Client(A1), a2 = w:Client(A2, { guild = World.GUILD2 }), z = w:Client(Z), author = w:Client(World.AUTHOR),
		m1 = w:Client("Mira Wells"), wes = w:Client("Wes Brook") }
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Run(8 * 3600)
	c.a1.online, c.a2.online = false, false
	w:Run(c.z.Church.KEEPER_EVERY * 3)
	w:Presence()
	eq(w:As(c.m1, c.m1.Count.Ask, "m", "m", nil, true), true)
	local q = w:Sent(c.m1, "NR", "WHISPER", "q")
	eq(#q, 1)
	eq(Key(q[1].target), Key(Z), "the Apostle, the desk, not the author whose name sorts first")
end)

test("1.5.6 Church rank recovery: a partial or repeated page cannot replace the last complete page", function()
	local w, c = Cast()
	local reader = c.m2
	-- Deliver replies explicitly so the model can drop one row and duplicate another.
	c.a1.handlers.NR, c.a2.handlers.NR = nil, nil
	local function Ask() return w:As(reader, reader.Count.Ask, "m", "m", nil, true) end
	local function Answer(from, text) return w:As(reader, reader.Count.TakeAnswerLine, from, text) end
	local function Row(rank, name, score)
		return ("NR~1~r~m~m~%d~%s~%d~%d~0~1~0~1~1"):format(rank, name, score, score)
	end
	local function End(n)
		return ("NR~1~e~m~m~-~%d~%s"):format(n, ns.Codec.Base36(w.clock))
	end
	local function View() return w:As(reader, reader.Count.RankingView, "m", "m") end
	eq(Ask(), true)
	eq(Answer(A1, Row(1, "Mira Wells", 100)), true)
	eq(Answer(A1, End(1)), true)
	local rows, savedAt = View()
	eq(rows[1].score, 10)
	w:Run(reader.Count.ASK_GAP)
	eq(Ask(), true)
	eq(Answer(A1, Row(1, "Mira Wells", 300)), true)
	Answer(A1, Row(1, "Mira Wells", 300))
	eq(Answer(A1, End(2)), false, "two delivered packets with one rank do not make a complete two-row page")
	local kept, at = View()
	eq(kept[1].score, 10)
	eq(at, savedAt, "incomplete replies do not make the old page appear newer")
	w:Run(reader.Count.ASK_GAP)
	eq(Ask(), true)
	eq(Answer(A1, End(0)), false, "the previous keeper's late reply is unasked")
	eq(Answer(A2, End(0)), true, "a complete empty result from the new keeper still replaces the old page")
	eq(#View(), 0)
end)

test("Church rank timing: a queued request and a reply still making progress are not replaced", function()
	local w, c = Cast()
	local reader, sendDone, sends = c.m2, nil, 0
	reader.ns.Comm.Whisper = function(_, msg, _, _, _, done)
		assert(msg:find("NR~1~q~", 1, true) == 1)
		sends, sendDone = sends + 1, done
		return true
	end
	local function Ask() return w:As(reader, reader.Count.Ask, "m", "m") end
	local function Answer(text) return w:As(reader, reader.Count.TakeAnswerLine, A1, text) end
	local gap = reader.Count.ASK_GAP
	eq(Ask(), true)
	w:Run(gap + 1)
	eq(Ask(), false, "a request waiting to be sent does not start the response timeout")
	eq(sends, 1)
	w:As(reader, assert(sendDone), true)
	w:Run(gap - 1)
	eq(Answer("NR~1~r~m~m~1~Mira Wells~200~200~0~2~0~1~1"), true)
	w:Run(2)
	eq(Ask(), false, "a response that is still making progress keeps its receiver")
	eq(Answer("NR~1~r~m~m~2~Nils Ford~100~100~0~1~0~1~1"), true)
	eq(Answer(("NR~1~e~m~m~-~2~%s"):format(ns.Codec.Base36(w.clock))), true)
	local rows = w:As(reader, reader.Count.RankingView, "m", "m")
	eq(#rows, 2)
	eq(rows[1].score, 20)
end)

test("Church rank timing: duplicate rows cannot delay fallback or reopen an unfinished keeper", function()
	local w, c = Cast()
	local reader = c.m2
	c.a1.handlers.NR, c.a2.handlers.NR = nil, nil
	local function Ask() return w:As(reader, reader.Count.Ask, "m", "m") end
	local function LastTarget()
		local sent = w:Sent(reader, "NR", "WHISPER", "q")
		return sent[#sent].target
	end
	local row = "NR~1~r~m~m~1~Mira Wells~200~200~0~2~0~1~1"
	local gap = reader.Count.ASK_GAP
	eq(Ask(), true)
	eq(LastTarget(), A1)
	eq(w:As(reader, reader.Count.TakeAnswerLine, A1, row), true)
	w:Run(gap - 1)
	eq(w:As(reader, reader.Count.TakeAnswerLine, A1, row), false)
	w:Run(1)
	eq(Ask(), true, "a repeated packet is not progress")
	eq(LastTarget(), A2)
	w:Run(gap)
	eq(Ask(), false, "both keepers have unanswered requests for this page")
	w:Run(reader.Church.ASKED_WINDOW - 2 * gap)
	w:Presence()
	eq(Ask(), true, "the previous request's answer lifetime is bounded")
	eq(LastTarget(), A1)
end)

test("global Church ledger: after a reload a keeper first asks the keeper it never completed a catch-up from: not the first by name again, and one a reload cut short before one it completed later", function()
	local w, c = Cast()
	Give(w, c.a1, "Rot Recb", "Mira Wells", 2)
	Give(w, c.a2, "Rot Recc", "Mira Wells", 2)
	-- (Seconds before the catch-ups below. A catch-up now ends a second before the one it is answered
	-- in, and a record of that second goes again in the next: changed in the same second as the first
	-- one, Rot Recb would be the first round of the two-round catch-up below, not Rot Recd.)
	w:Run(2)
	c.author.online = true
	w:Presence()
	local function Asks(cl)
		w:ClearSent()
		eq(w:As(cl, cl.Count.CatchUp, true), true)
		local q = w:Sent(cl, "NL", "WHISPER", "q")
		eq(#q, 1)
		return Key(q[1].target)
	end
	eq(Asks(c.author), Key(A1))
	w:Run(0) -- reload after the first completion, before the one-second sweep
	assert(Rec(w, c.author, "Rot Recb", "Mira Wells"), "caught up from the first keeper asked")
	local author = Reload(w, c.author)
	w:Presence()
	eq(Asks(author), Key(A2), "the keeper never caught up from")
	w:Run(60)
	assert(Rec(w, author, "Rot Recc", "Mira Wells"), "and its records")
	-- Aldric's next catch-up takes two rounds, and a reload comes after the first: the next session
	-- asks him first again, from where it stopped, not Bera, caught up from since.
	Give(w, c.a1, "Rot Recd", "Mira Wells", 2)
	w:Run(10)
	Give(w, c.a1, "Rot Rece", "Mira Wells", 2)
	c.a1.Count.CATCHUP_LINES = 1
	eq(Asks(author), Key(A1), "the one caught up from longest ago")
	w:Run(1)
	assert(Rec(w, author, "Rot Recd", "Mira Wells"), "the first round")
	eq(Rec(w, author, "Rot Rece", "Mira Wells"), nil, "not the second yet")
	local again = Reload(w, author)
	w:Presence()
	eq(Asks(again), Key(A1), "the catch-up cut short")
end)

test("global Church ledger: a keeper asks only keepers for a catch-up: never a council relay, while a keeper is online or while none is", function()
	local w, c = Cast()
	local council = w:Client(World.COUNCILLOR)
	c.author.online = true
	w:Presence()
	-- A 1.2.5.1 councillor's client answers no catch-up: it is no keeper (that release's Count.TakeLine
	-- drops every ledger line on a client that is not one, "keeper").
	council.Count.TakeLine = function() return false, "keeper" end
	local function Asks()
		w:ClearSent()
		eq(w:As(c.author, c.author.Count.CatchUp, true), true)
		local q = w:Sent(c.author, "NL", "WHISPER", "q")
		eq(#q, 1)
		w:Run(0) -- test explicit rotation before the newly scheduled sweep
		return Key(q[1].target)
	end
	eq(Asks(), Key(A1))
	eq(Asks(), Key(A2))
	eq(Asks(), Key(A1), "a keeper again, not the silent council relay")

	-- With no keeper online, the council relay online is not asked either: a keeper takes no ledger
	-- line from it (Count.TakeLine, 1.2.5.1). (Changed from a test that had the author complete a
	-- catch-up from the council relay and ask it in its turn: the lead restored that rule, 2026-10-19.)
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence({ council, c.author })
	w:ClearSent()
	eq(w:As(c.author, c.author.Count.CatchUp, true), false)
	eq(#w:Sent(c.author, "NL", "WHISPER", "q"), 0, "nobody asked")
end)

test("global Church ledger: a keeper's verified word goes to the keepers online, a relay online costing them nothing; to the other relays only while the queue has room", function()
	local w, c = Cast()
	w:Client(World.COUNCILLOR)
	w:Presence()
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	local own = ("NV~1~w~Mira Wells-Realm~Push Guy-Realm~%s~%s~%s"):format(World.GUILD, B(hour - 2), B(hour - 1))
	Join(w, World.GUILD, "Push Guy")
	w:As(c.a2, c.a2.Count.TakeEvidence, "Mira Wells-Realm", own)
	w:As(c.a1, c.a1.Count.TakeEvidence, "Mira Wells-Realm", own)
	eq(StateOf(w, c.a2, "Push Guy", "Mira Wells"), "pending")
	-- Room for one line to each keeper online (Bera), not for one to each relay (Bera and the council).
	w.room = c.a1.Count.SEND_ROOM + 2
	w:As(c.a1, c.a1.Count.TakeEvidence, "Wes Brook-Realm", own)
	w:Flush()
	eq(StateOf(w, c.a2, "Push Guy", "Mira Wells"), "credited", "Bera has Wes's word from Aldric")
	-- With no room past SEND_ROOM, the keepers still have it; the council's copy waits for its catch-up.
	w.room = c.a1.Count.SEND_ROOM
	w:ClearSent()
	local line = w:As(c.a1, c.a1.Count.RecordLine, Key("Push Guy") .. ":" .. Key("Mira Wells"), Rec(w, c.a1, "Push Guy", "Mira Wells"))
	w:As(c.a1, c.a1.Count.ToRelays, line)
	local to = {}
	for _, e in ipairs(w:Sent(c.a1, "NL", "WHISPER", "r")) do to[Key(e.target)] = true end
	eq(to[Key(A2)], true, "the keeper")
	eq(to[Key(World.COUNCILLOR)], nil, "not the council, with no room")
end)

-- The review of the relays' catch-up (2026-10-19): when a session's first catch-up goes, whom a
-- keeper that never answers leaves first, what a keeper takes from a council or King client, and the
-- King's client, which does no background Church work.

test("global Church ledger: just logged in, a keeper's first catch-up waits until every keeper online has been heard: not the one heard first, the one it never caught up from", function()
	local w, c = Cast()
	Give(w, c.a1, "Race Recb", "Mira Wells", 2)
	Give(w, c.a2, "Race Recc", "Mira Wells", 2)
	c.author.online = true
	w:Presence()
	-- A first session completes a catch-up from Aldric only.
	w:ClearSent()
	eq(w:As(c.author, c.author.Count.CatchUp, true), true)
	eq(Key(w:Sent(c.author, "NL", "WHISPER", "q")[1].target), Key(A1))
	w:Run(0) -- close this session before its automatic next-source sweep
	-- A login: Bera, never caught up from, is the one to ask, and Aldric's presence comes in first (a
	-- keeper's presence is KEEPER_EVERY apart, the Church tick every 30 seconds).
	local again = Reload(w, c.author)
	Login(w, again)
	w:Presence({ c.a1, again })
	local function Ticked()
		w:ClearSent()
		w:Tick({ again })
		local q = w:Sent(again, "NL", "WHISPER", "q")
		eq(#q <= 1, true)
		return q[1] and Key(q[1].target) or "nobody"
	end
	eq(Ticked(), "nobody", "only Aldric heard yet")
	w:Run(240)
	w:Presence({ c.a2 })
	eq(Ticked(), "nobody", "both heard, but a keeper whose presence was lost may be online too")
	local settle = again.Church.KEEPER_EVERY * again.Church.FRESH_FACTOR
	assert(settle < again.Count.SETTLE_MAX, "inside the time a desk waits for its catch-up before it answers pages")
	w:Run(settle - 240 + 1)
	w:Presence({ c.a1, c.a2 })
	eq(Ticked(), Key(A2), "the keeper never caught up from")
	w:Run(60)
	assert(Rec(w, again, "Race Recc", "Mira Wells"), "and its records")
	eq(w:As(again, again.Count.Settled), true)
end)

test("global Church ledger: a keeper that never answers a catch-up is not asked first in every session: asked, it goes behind the others", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	-- Aldric (first by name) drops every ask, as a desk too busy to answer does.
	c.a1.Count.TakeLine = function() return false, "busy" end
	local author, asked = c.author, {}
	for _ = 1, 4 do
		w:ClearSent()
		eq(w:As(author, author.Count.CatchUp, true), true)
		local q = w:Sent(author, "NL", "WHISPER", "q")
		eq(#q, 1)
		asked[#asked + 1] = Key(q[1].target)
		w:Run(60)
		author = Reload(w, author)
		w:Presence()
	end
	eq(table.concat(asked, ", "), table.concat({ Key(A1), Key(A2), Key(A1), Key(A2) }, ", "), "each in turn, not Aldric first every session")
end)

test("global Church ledger: on a keeper, record, person and archive lines only from a keeper: a council or King client adds no recruit and raises no count (1.2.5.1)", function()
	local w, c = Cast()
	w:Client(World.COUNCILLOR)
	c.king.online = true
	w:Presence()
	local K, B = c.a1, c.a1.Church.B36
	local u, hour = B(w.clock), B(math.floor(w.clock / 3600) * 3600 - 3600)
	local lines = {
		w:As(K, K.Count.RecordLine, Key("Made Recb") .. ":" .. Key("Mira Wells"), { n = "Made Recb", bn = "Mira Wells", g = World.GUILD,
			kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { Key("Wes Brook") }, c = 1, u = w.clock }),
		("NL~1~p~Mira Wells-Realm~0~0~50000~5000~0~%s"):format(u),
		("NL~1~z~Made Recc-Realm~Mira Wells-Realm~%s~1~%s"):format(hour, u),
	}
	local function Counts() return Joins(w, K, "Mira Wells", "m") .. " in 30 days, " .. Joins(w, K, "Mira Wells", "a") .. " all time" end
	eq(Counts(), "0 in 30 days, 0 all time")
	for _, from in ipairs({ World.COUNCILLOR, World.KING }) do
		for _, line in ipairs(lines) do eq(w:As(K, K.Count.TakeLine, from, line), false, from .. ": " .. line) end
	end
	eq(Counts(), "0 in 30 days, 0 all time", "nothing added, nothing raised")
	eq(Rec(w, K, "Made Recb", "Mira Wells"), nil)
	-- The same lines from a keeper are taken.
	for _, line in ipairs(lines) do eq(w:As(K, K.Count.TakeLine, A2, line), true, line) end
	eq(Counts(), "2 in 30 days, 5001 all time")
end)

test("global Church ledger: the King's client does no background Church work: it asks for no catch-up, a keeper answers none of its asks and pushes nothing to it", function()
	local w, c = Cast()
	c.king.online = true
	w:Presence()
	local id = Key("King Recb") .. ":" .. Key("Mira Wells")
	Give(w, c.a1, "King Recb", "Mira Wells", 2)
	w:ClearSent()
	-- No catch-up from the King's client, on its tick or asked for.
	w:Tick({ c.king })
	eq(#w:Sent(c.king, "NL"), 0, "nothing on its tick")
	eq(w:As(c.king, c.king.Count.CatchUp, true), false)
	-- An ask in the King's name: Aldric answers none of it.
	w:As(c.a1, c.a1.Count.TakeLine, World.KING, "NL~1~q~0")
	w:Run(60)
	local n = 0
	for _, e in ipairs(w:Sent(c.a1, "NL", "WHISPER")) do if Key(e.target) == Key(World.KING) then n = n + 1 end end
	eq(n, 0, "no ledger line to the King")
	-- A keeper's verified word goes to the keepers, not to the King's client.
	w:ClearSent()
	w:As(c.a1, c.a1.Count.Push, id)
	local to = {}
	for _, e in ipairs(w:Sent(c.a1, "NL", "WHISPER", "r")) do to[Key(e.target)] = true end
	eq(to[Key(A2)], true, "Bera")
	eq(to[Key(World.KING)], nil, "not the King")
	-- A ledger line whispered to the King's client anyway is not kept there, and its page shows no
	-- copy of its own (with no keeper online and no answer kept, nothing).
	local line = w:As(c.a1, c.a1.Count.RecordLine, id, Rec(w, c.a1, "King Recb", "Mira Wells"))
	eq(w:As(c.king, c.king.Count.TakeLine, A1, line), false)
	eq(Rec(w, c.king, "King Recb", "Mira Wells"), nil)
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence()
	eq(#(w:As(c.king, c.king.Count.RankingView, "m", "a")), 0)
end)

test("global Church ledger: a council client catches up only while no keeper is online, from a council relay, never the King's client", function()
	local w, c = Cast()
	w:Client(World.COUNCILLOR)
	local other = w:Client("Dela Moss-Realm")
	c.king.online = true
	w:Presence()
	-- Keepers online: its pages ask them (Count.Ask); no catch-up.
	w:ClearSent()
	eq(w:As(other, other.Count.CatchUp, true), false)
	w:Tick({ other })
	eq(#w:Sent(other, "NL", "WHISPER", "q"), 0, "none on its tick")
	-- Every keeper offline: it asks the council relay online, not the King's client (sorted first).
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence()
	w:ClearSent()
	eq(w:As(other, other.Count.CatchUp, true), true)
	local q = w:Sent(other, "NL", "WHISPER", "q")
	eq(#q, 1)
	eq(Key(q[1].target), Key(World.COUNCILLOR))
end)

-- The review of the Church's count (2026-10-19, "numbers still much smaller than the prints"): a desk
-- just logged in answering pages and sending the public rows from a ledger behind the others', a
-- keeper answering a council client's catch-up, and one account's council character's copy read as
-- its Apostle character's ledger. Each test below fails on the build before it.

test("global Church ledger: a desk just logged in sends the public rows only once its first catch-up ended: its first rows carry the recruits it missed", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	c.author.online = false
	w:Run(5) -- (the records below come seconds after that tick's catch-ups ended)
	-- Bera takes five of Mira's recruits while Aldric (the desk) is away.
	c.a1.online = false
	for i = 1, 5 do Give(w, c.a2, "Pub Rec" .. Letters(i), "Mira Wells", 2); w:Run(1) end
	local again = Reload(w, c.a1)
	Login(w, again)
	w:Presence()
	local t0, first = w.clock, nil
	while w.clock - t0 < 1000 and not first do
		w:ClearSent()
		w:Tick()
		local sent = w:Sent(again, "NR", "CHANNEL")
		if #sent > 0 then first = sent end
		w:Run(30)
	end
	assert(first, "the desk sent its public rows")
	eq(w:As(again, again.Count.Settled), true, "after its first catch-up")
	eq(Joins(w, again, "Mira Wells", "m"), 5)
	local s30
	for _, e in ipairs(first) do s30 = s30 or e.msg:match("^NR~1~p~[0-9a-z]+~m~1~Mira Wells~(%d+)~%d+$") end
	eq(s30, "500", "Mira first, her five recruits' 50 points (not her row missing: the ledger before the catch-up had none)")
	local v = w:As(c.wes, c.wes.Count.PublicView)
	eq(v and v.m[1] and v.m[1].name, "Mira Wells")
	eq(v.m[1].s30, 50)
end)

test("global Church ledger: a desk just logged in answers no page while its first catch-up goes on, SETTLE_MAX counted from the end of its wait to hear the keepers", function()
	local w, c = Cast()
	-- Bera holds 80 records Aldric (the desk) lacks, one a round (about 5 s a round: as 150 lines take in game).
	for i = 1, 80 do Give(w, c.a2, "Long Rec" .. Letters(i), "Mira Wells", 2); w:Run(1) end
	c.a2.Count.CATCHUP_LINES = 1
	local again = Reload(w, c.a1)
	Login(w, again)
	w:Presence()
	local t0 = w.clock
	local cap = again.Church.KEEPER_EVERY * again.Church.FRESH_FACTOR + again.Count.SETTLE_MAX
	while w.clock - t0 < again.Count.SETTLE_MAX + 5 do w:Tick(); w:Run(30) end
	local behind = Joins(w, again, "Mira Wells", "a")
	assert(behind < 80, "still catching up: " .. behind)
	eq(w:As(again, again.Count.Settled), false, "SETTLE_MAX after the login is not yet SETTLE_MAX after the wait")
	eq(select(2, w:As(again, again.Count.Answer, "Nils Ford-Realm", "m", "a")), "catching up")
	-- Its catch-up ends inside the cap: it answers, with Bera's numbers.
	while not w:As(again, again.Count.Settled) and w.clock - t0 < cap do w:Tick(); w:Run(30) end
	assert(w.clock - t0 < cap, "caught up before the cap")
	eq(Joins(w, again, "Mira Wells", "a"), 80)
	eq(w:As(again, again.Count.Answer, "Nils Ford-Realm", "m", "a"), true)
end)

test("global Church ledger: a keeper just logged in that has heard no other keeper yet is not settled: an audience page keeps its numbers until the wait to hear them ends", function()
	local w, c = Cast()
	for i = 1, 3 do Give(w, c.a2, "Login Rec" .. Letters(i), "Mira Wells", 2); w:Run(1) end
	-- Nils's page has Bera's numbers, asked while Aldric (the desk, first by name) was away.
	c.a1.online = false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence()
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "a", nil, true), true)
	w:Run(30)
	eq(JoinsOn(w, c.m2, "Mira Wells", "m", "a"), 3)
	-- Aldric logs in: his presence goes out at once, the others' on their next one.
	local again = Reload(w, c.a1)
	Login(w, again)
	w:Presence({ again })
	w:Run(10)
	eq(#w:As(again, again.Church.KeepersOnline, false), 0, "no keeper heard yet")
	eq(w:As(again, again.Count.Settled), false, "no keeper heard is not no keeper online")
	-- Nils's page asks him: unanswered, it keeps Bera's numbers.
	w:ClearSent()
	eq(w:As(c.m2, c.m2.Count.Ask, "m", "a", nil, true), true)
	eq(Key(w:Sent(c.m2, "NR", "WHISPER", "q")[1].target), Key(A1))
	w:Run(30)
	eq(JoinsOn(w, c.m2, "Mira Wells", "m", "a"), 3, "not a ledger without them")
	-- No keeper heard by the end of that wait (Bera gone): its ledger is the one there is.
	c.a2.online = false
	w:Run(again.Church.KEEPER_EVERY * again.Church.FRESH_FACTOR)
	eq(w:As(again, again.Count.Settled), true)
end)

test("global Church ledger: a keeper answers no council client's catch-up ask, a keeper's only (1.2.5.1)", function()
	local w, c = Cast()
	w:Client(World.COUNCILLOR)
	w:Presence()
	for i = 1, 5 do Give(w, c.a1, "Ask Rec" .. Letters(i), "Mira Wells", 2); w:Run(1) end
	local function LinesTo(name)
		local n = 0
		for _, e in ipairs(w:Sent(c.a1, "NL", "WHISPER")) do if Key(e.target) == Key(name) then n = n + 1 end end
		return n
	end
	w:ClearSent()
	for _ = 1, 8 do eq(select(2, w:As(c.a1, c.a1.Count.TakeLine, World.COUNCILLOR, "NL~1~q~0")), "keeper") end
	eq(select(2, w:As(c.a1, c.a1.Count.AnswerCatchUp, World.COUNCILLOR, 0)), "keeper")
	w:Run(60)
	eq(LinesTo(World.COUNCILLOR), 0, "no round to the council (it was 6 lines an ask)")
	-- Bera's ask is answered: the five records and the end.
	w:ClearSent()
	eq(w:As(c.a1, c.a1.Count.TakeLine, A2, "NL~1~q~0"), true)
	w:Run(60)
	eq(LinesTo(A2), 6)
end)

test("global Church ledger: one account with a council and an Apostle character: the council's copy is saved apart, and a line it took reaches neither the Apostle's ledger nor another keeper's", function()
	local w, c = Cast()
	local council = w:Client(World.COUNCILLOR)
	local dela = w:Client("Dela Moss-Realm")
	w:Presence()
	w:Run(30) -- (the book, from the desk)
	-- Every keeper away: the council character takes another council relay's line no keeper sent.
	c.a1.online, c.a2.online = false, false
	w:Run(c.a1.Church.KEEPER_EVERY * 3)
	w:Presence({ council, dela })
	local line = ("NL~1~p~Mira Wells-Realm~0~0~50000~5000~0~%s"):format(c.a1.Church.B36(w.clock))
	eq(w:As(council, council.Count.TakeLine, "Dela Moss-Realm", line), true, "a council client keeps its copy")
	eq(Joins(w, council, "Mira Wells", "a"), 5000, "in its copy")
	-- The same account's Apostle character logs in (OlympusDB is account-wide; ns.rdb, one realm group's).
	council.online = false
	local alt = w:Client(A2, { guild = World.GUILD2, rdb = council.ns.rdb })
	w:As(alt, alt.ns.Fire, "INIT")
	eq(Joins(w, alt, "Mira Wells", "a"), 0, "not in the Apostle's ledger")
	-- Aldric catches up from it: nothing of the council's line.
	c.a1.online = true
	w:Presence({ c.a1, alt })
	w:ClearSent()
	eq(w:As(c.a1, c.a1.Count.CatchUp, true), true)
	eq(Key(w:Sent(c.a1, "NL", "WHISPER", "q")[1].target), Key(A2))
	w:Run(60)
	eq(Joins(w, c.a1, "Mira Wells", "a"), 0, "no keeper's count raised")
	-- The Apostle catches up from Aldric: its cursor goes in its own ledger.
	eq(w:As(alt, alt.Count.CatchUp, true), true)
	w:Run(60)
	-- The council character back: its copy as it left it, and the Apostle's catch-up cursor not in it.
	alt.online = false
	local back = Reload(w, council)
	eq(Joins(w, back, "Mira Wells", "a"), 5000, "its copy kept")
	eq(w:As(back, back.Count.Led).from[Key(A1)], nil, "the Apostle's own cursor stays in its ledger")
	eq(w:As(back, back.Church.Store).led.from[Key(A1)] ~= nil, true)
	-- The load's check takes the copy as it takes the ledger: a saved record that fails goes alone, a
	-- malformed copy whole.
	local store = w:As(back, back.Church.Store)
	store.copy.r["odd guy:mira wells"] = { n = "Odd Guy", bn = "Mira Wells", g = "Plain Guild", kind = "i", tc = w.clock - 7200, tj = w.clock - 3600 }
	w:As(back, back.Count.CheckSaved)
	eq(store.copy.r["odd guy:mira wells"], nil, "the record that fails goes")
	eq(Joins(w, back, "Mira Wells", "a"), 5000, "the rest kept")
	store.copy = { v = 1, r = "x" }
	w:As(back, back.Count.CheckSaved)
	eq(store.copy, nil)
	eq(store.led ~= nil, true, "the Apostle's ledger untouched")
end)

-- The third review of the Church's count (2026-10-19): a first catch-up asked once and never again
-- before the cap, a desk caught up from a keeper itself catching up, the ledger's choice looked for
-- for each person of a ranking, a record of the second a catch-up ended never sent, and a keeper's
-- own tab showing the ledger it had before as live. Each test below fails on the build before it (the
-- one about many rounds only for want of CATCHUP_RETRY: it keeps the retry from cutting a catch-up short).

test("global Church ledger: a desk just logged in whose first catch-up ask goes unanswered asks the next keeper CATCHUP_RETRY later, and is caught up long before the cap", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	-- Bera and the author take five of Mira's recruits while Aldric (the desk) is away.
	c.a1.online = false
	for i = 1, 5 do
		Give(w, c.a2, "Unans Rec" .. Letters(i), "Mira Wells", 2)
		Give(w, c.author, "Unans Rec" .. Letters(i), "Mira Wells", 2)
		w:Run(1)
	end
	w:Run(10)
	-- Bera's sends are full: eight transfers queued, no room in her Comm queue. An ask is dropped.
	c.a2.ns.Comm.QueueRoom = function() return 0 end
	for i = 1, 8 do eq(w:As(c.a2, c.a2.Count.SendLines, "Some One" .. Letters(i) .. "-Realm", { "NL~1~e~0~0" }), true) end
	local again = Reload(w, c.a1)
	Login(w, again)
	w:Presence()
	local t0 = w.clock
	local cap = again.Church.KEEPER_EVERY * again.Church.FRESH_FACTOR + again.Count.SETTLE_MAX
	w:ClearSent()
	while w.clock - t0 < cap and not w:As(again, again.Count.Settled) do w:Tick(); w:Run(30) end
	local q = w:Sent(again, "NL", "WHISPER", "q")
	assert(#q >= 2, "asked again before the cap: " .. #q .. " ask(s)")
	eq(Key(q[1].target), Key(A2), "Bera first")
	eq(Key(q[2].target), Key(World.AUTHOR), "then the next keeper, not Bera again")
	assert(q[2].at - q[1].at <= again.Count.CATCHUP_RETRY + 30, "CATCHUP_RETRY after the first: " .. (q[2].at - q[1].at))
	assert((w:As(c.a2, c.a2.Count.Stats).dropped.busy or 0) >= 1, "Bera's client dropped the ask")
	assert(w.clock - t0 < cap, "caught up before the cap")
	eq(Joins(w, again, "Mira Wells", "a"), 5)
	eq(w:As(again, again.Count.Answer, "Nils Ford-Realm", "m", "a"), true)
end)

test("global Church ledger: a first catch-up in many rounds is not cut short by the retry: while its keeper's lines come, no other keeper is asked", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	c.a1.online = false
	for i = 1, 40 do Give(w, c.a2, "Round Rec" .. Letters(i), "Mira Wells", 2); w:Run(1) end
	-- (One record a round, about 5 s a round: the 40 take longer than CATCHUP_RETRY.)
	c.a2.Count.CATCHUP_LINES = 1
	local again = Reload(w, c.a1)
	Login(w, again)
	w:Presence()
	local t0 = w.clock
	w:ClearSent()
	while w.clock - t0 < 1500 and not w:As(again, again.Count.Settled) do w:Tick(); w:Run(30) end
	local q = w:Sent(again, "NL", "WHISPER", "q")
	assert(#q >= 40 and q[#q].at - q[1].at > again.Count.CATCHUP_RETRY, "a catch-up of many rounds: " .. #q)
	local moved = false
	for _, e in ipairs(q) do
		if Key(e.target) == Key(A2) then
			eq(moved, false, "no other keeper was asked between Bera's pages")
		else
			moved = true
			eq(Key(e.target), Key(World.AUTHOR), "the next source is allowed only after completion")
		end
	end
	eq(Joins(w, again, "Mira Wells", "a"), 40)
end)

test("global Church ledger: a keeper whose own first catch-up goes on answers no catch-up: the desk asking it asks the next keeper, and has the third keeper's records once caught up", function()
	local w, c = Cast()
	c.author.online = true
	w:Presence()
	-- Aldric (the desk) and Bera away; the author takes five of Mira's recruits.
	c.a1.online, c.a2.online = false, false
	for i = 1, 5 do Give(w, c.author, "Third Rec" .. Letters(i), "Mira Wells", 2); w:Run(1) end
	w:Run(10)
	-- Bera logs in, Aldric a minute later: each one's ledger lacks the five.
	local bera = Reload(w, c.a2)
	Login(w, bera)
	w:Presence()
	w:Run(60)
	local ald = Reload(w, c.a1)
	Login(w, ald)
	w:Presence()
	local t0 = w.clock
	w:ClearSent()
	while w.clock - t0 < 1500 and not w:As(ald, ald.Count.Settled) do w:Tick(); w:Run(30) end
	assert(w.clock - t0 < ald.Church.KEEPER_EVERY * ald.Church.FRESH_FACTOR + ald.Count.SETTLE_MAX, "caught up before the cap")
	eq(Joins(w, ald, "Mira Wells", "a"), 5, "the author's five, not Bera's ledger as behind as his")
	eq(Joins(w, bera, "Mira Wells", "a"), 5, "Bera's too")
	eq(w:As(bera, bera.Count.Settled), true)
	assert((w:As(ald, ald.Count.Stats).dropped["catching up"] or 0) >= 1, "Aldric answered no catch-up while his went on")
	assert((w:As(bera, bera.Count.Stats).dropped["catching up"] or 0) >= 1, "nor Bera")
	eq(select(2, w:As(ald, ald.Count.AnswerCatchUp, World.AUTHOR, 0)), nil, "caught up, he answers")
	eq(w:As(ald, ald.Count.Answer, "Nils Ford-Realm", "m", "a"), true)
end)

test("global Church ledger: two keepers just logged in together are no catch-up for each other: settled only at the cap, and each has the other's records the next ask after it", function()
	local w, c = Cast()
	for i = 1, 3 do Give(w, c.a1, "Ald Own" .. Letters(i), "Mira Wells", 2) end
	for i = 1, 4 do Give(w, c.a2, "Ber Own" .. Letters(i), "Mira Wells", 2) end
	w:Run(10)
	local ald, bera = Reload(w, c.a1), Reload(w, c.a2)
	Login(w, ald); Login(w, bera)
	w:Presence()
	local t0 = w.clock
	local cap = ald.Church.KEEPER_EVERY * ald.Church.FRESH_FACTOR + ald.Count.SETTLE_MAX
	while w.clock - t0 < cap - 30 do w:Tick(); w:Run(30) end
	eq(w:As(ald, ald.Count.Settled), false, "not from Bera's ledger, itself catching up")
	eq(w:As(bera, bera.Count.Settled), false)
	while w.clock - t0 < cap + ald.Count.CATCHUP_REASK + 60 and (Joins(w, ald, "Mira Wells", "a") < 7 or Joins(w, bera, "Mira Wells", "a") < 7) do
		w:Tick(); w:Run(30)
	end
	eq(Joins(w, ald, "Mira Wells", "a"), 7)
	eq(Joins(w, bera, "Mira Wells", "a"), 7)
end)

test("global Church ledger: which ledger a client reads is looked for once a second, not for each person of a ranking; at once again when the Church's state or the data changed", function()
	local w, c = Cast()
	local K = c.a1
	for i = 1, 200 do Give(w, K, "Perf Rec" .. Letters(i), (i % 2 == 0) and "Mira Wells" or "Nils Ford", 2) end
	local n, orig = 0, K.Church.IsKeeper
	K.Church.IsKeeper = function(name, ...)
		if name == nil or Key(name) == Key(K.ns.me) then n = n + 1 end
		return orig(name, ...)
	end
	w:Run(1)
	w:As(K, function()
		for _ = 1, 2000 do K.Count.Own(Key("Mira Wells"), "a") end
	end)
	assert(n <= 1, "this client's role asked " .. n .. " times for 2000 Own (3 each before)")
	eq(Joins(w, K, "Mira Wells", "a"), 100)
	-- Aldric's Apostle role ends with a newer signed list: his copy the next second.
	local store = w:As(K, K.Church.Store)
	w:SignedList({ A2 }, true, w.clock + 1)
	w:Run(1)
	eq(w:As(K, K.Count.Led) == store.copy, true, "no keeper reads the copy")
	-- Signed again, the data changed (as Authority's saved bundle fires): his ledger in the same second.
	w:SignedList({ A1, A2 }, true, w.clock + 2)
	w:As(K, K.ns.Fire, "DATA_CHANGED")
	eq(w:As(K, K.Count.Led) == store.led, true, "his ledger again at once")
	eq(Joins(w, K, "Mira Wells", "a"), 100)
	K.Church.IsKeeper = orig
end)

local function LedgerPageWorld()
	local w, c = KeeperProbeWorld()
	c.a2.online = true
	w:Presence()
	w:ClearSent()
	return w, c
end

local function LedgerMessages(w, cl, version, subtype)
	local out = {}
	local prefix = "NL~" .. version .. "~" .. subtype .. "~"
	for _, e in ipairs(w:Sent(cl, "NL", "WHISPER")) do
		if e.msg:sub(1, #prefix) == prefix then out[#out + 1] = e end
	end
	return out
end

test("Church ledger v2 proves every distinct row before moving past a silently lost packet", function()
	local w, c = LedgerPageWorld()
	Give(w, c.a2, "Silent Reca", "Mira Wells", 2)
	Give(w, c.a2, "Silent Recb", "Mira Wells", 2)
	w:Run(2)
	local whisper, lost = c.a2.c.Comm.Whisper, false
	c.a2.c.Comm.Whisper = function(target, msg, key, urgent, logged, done, options)
		if target == A1 and msg:match("^NL~2~d~%w+~2~") and not lost then
			lost = true
			done(true) -- The sender's game API accepts it, but no network packet reaches the recipient.
			return true
		end
		return whisper(target, msg, key, urgent, logged, done, options)
	end
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	assert(lost, "the simulated connection swallowed a modern page row")
	local rows, ends = LedgerMessages(w, c.a2, 2, "d"), LedgerMessages(w, c.a2, 2, "e")
	eq(#rows, 1); eq(#ends, 1)
	local from = w:As(c.a1, c.a1.Count.Led).from
	eq(from[Key(A2)], nil)
	local function Take(sender, text) return w:As(c.a1, c.a1.Count.Receive, "NL", "WHISPER", sender, text) end
	eq(select(2, Take(A2, rows[1].msg:gsub("^(NL~2~d~%w+~)1~", "%12~"))), "duplicate", "a repeated record cannot stand in for slot 2")
	eq(Take("Bera Stone-CAMWOWUS1Realm1PvP", ends[1].msg), false, "a matching name on another ruleset")
	eq(Take(A2, "NL~1~e~0~" .. c.a1.Church.B36(w.clock)), false, "a legacy terminal cannot finish this modern request")
	w:Run(c.a1.Count.CATCHUP_RETRY + 1)
	eq(#LedgerMessages(w, c.a1, 1, "q"), 0, "the acknowledged modern keeper never falls back")
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	assert(from[Key(A2)], "the complete response can commit")
	eq(Joins(w, c.a1, "Mira Wells", "a"), 2, "both records converge without a duplicate")
	eq(Take(A2, ends[1].msg), false, "the stale terminal cannot affect the next request")
end)

test("Church ledger v2 paginates timestamp ties while keeping the original source cutoff", function()
	local w, c = LedgerPageWorld()
	c.a2.Count.CATCHUP_LINES = 1
	Give(w, c.a2, "Tied Reca", "Mira Wells", 2)
	Give(w, c.a2, "Tied Recb", "Mira Wells", 2)
	local stamp = w.clock
	w:Run(1)
	Give(w, c.a2, "Older Rec", "Mira Wells", 2)
	w:Run(2)
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	local from = w:As(c.a1, c.a1.Count.Led).from
	eq(from[Key(A2)], stamp - 1, "the persisted checkpoint cannot cross a split second")
	eq(Joins(w, c.a1, "Mira Wells", "a"), 1)
	w:Run(1)
	Give(w, c.a2, "Later Rec", "Mira Wells", 2)
	w:Run(12)
	eq(Joins(w, c.a1, "Mira Wells", "a"), 3, "the tied and older rows arrived within the frozen cutoff")
	eq(from[Key(A2)], stamp + 1)
	local q = LedgerMessages(w, c.a1, 2, "q")
	eq(#q, 3, "a distinct bounded request carried each continuation")
	assert(q[1].msg:match("^NL~2~q~([^~]+)") ~= q[2].msg:match("^NL~2~q~([^~]+)"))
	w:Run(4)
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	eq(Joins(w, c.a1, "Mira Wells", "a"), 4, "newer records stay available to the next sweep")
end)

test("Church ledger v2 fits maximal canonical records within native whisper and refuses an oversized page", function()
	local w, c = LedgerPageWorld()
	local recruit, recruiter = ("A"):rep(30), ("B"):rep(30)
	local guild = "Olympus " .. ("C"):rep(40)
	local id = Key(recruit) .. ":" .. Key(recruiter)
	w:As(c.a2, c.a2.Count.MergeIn, id, { n = recruit .. "-" .. ("R"):rep(20), bn = recruiter .. "-" .. ("R"):rep(20),
		g = guild, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { ("d"):rep(30), ("e"):rep(30) },
		s = 1, t = 1, a = 1, x = 1, c = 1, y = 1, q7 = 9, rq = 9 }, false)
	local held = w:As(c.a2, c.a2.Count.Led).r[id]
	local old = w:As(c.a2, c.a2.Count.RecordLine, id, held)
	assert(#old <= 255 and #old > 240, "a wide but legal older record")
	w:Run(2)
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	local rows = LedgerMessages(w, c.a2, 2, "d")
	eq(#rows, 1)
	assert(#rows[1].msg <= 255 and #rows[1].msg > 220, "the full canonical row passes the native boundary")
	assert(w:As(c.a1, c.a1.Count.Led).r[id], "the maximal row reached the ledger")

	w:Run(5)
	Give(w, c.a2, "Too Big", "Mira Wells", 2)
	local damaged = w:As(c.a2, c.a2.Count.Led).r[Key("Too Big") .. ":" .. Key("Mira Wells")]
	damaged.ws = { ("z"):rep(260) }
	local from = w:As(c.a1, c.a1.Count.Led).from
	local before = from[Key(A2)]
	w:Run(2)
	w:ClearSent()
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	eq(#LedgerMessages(w, c.a2, 2, "d"), 0)
	eq(#LedgerMessages(w, c.a2, 2, "e"), 0)
	eq(w:As(c.a2, c.a2.Count.Stats).dropped["wire size"], 1)
	eq(from[Key(A2)], before, "refusal kept the previous cursor")
	damaged.ws = { Key(c.a2.name) }
	w:Run(c.a1.Count.CATCHUP_RETRY + 1)
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	assert(from[Key(A2)] > before, "a subsequent complete page can recover")
end)

test("Church ledger v2 falls back once for an older keeper and keeps the existing cursor", function()
	local w, c = LedgerPageWorld()
	local before = w.clock - 100
	local from = w:As(c.a1, c.a1.Count.Led).from
	from[Key(A2)] = before
	Give(w, c.a2, "Legacy Rec", "Mira Wells", 2)
	w:Run(2)
	local receive = c.a2.handlers.NL
	c.a2.handlers.NL = function(dist, sender, text)
		if text:sub(1, 5) == "NL~1~" then return receive(dist, sender, text) end
	end
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	w:Run(c.a1.Count.CATCHUP_LEGACY_WAIT - 1)
	eq(#LedgerMessages(w, c.a1, 1, "q"), 0)
	eq(from[Key(A2)], before)
	w:Run(10)
	local q = LedgerMessages(w, c.a1, 1, "q")
	eq(#q, 1)
	eq(q[1].msg, "NL~1~q~" .. c.a1.Church.B36(before))
	eq(Joins(w, c.a1, "Mira Wells", "a"), 1)
	assert(from[Key(A2)] > before)
end)

test("Church ledger v2 cannot move a pending keeper page into a council copy", function()
	local w, c = LedgerPageWorld()
	Give(w, c.a2, "Delayed Rec", "Mira Wells", 2)
	w:Run(2)
	local whisper, delayed = c.a2.c.Comm.Whisper, {}
	c.a2.c.Comm.Whisper = function(target, msg, key, urgent, logged, done, options)
		if target == A1 and msg:match("^NL~2~[de]~") then
			delayed[#delayed + 1] = msg
			if done then done(true) end
			return true
		end
		return whisper(target, msg, key, urgent, logged, done, options)
	end
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	eq(#delayed, 2)
	local kept = w:As(c.a1, c.a1.Count.Led)
	local isKeeper = c.a1.Church.IsKeeper
	c.a1.Church.IsKeeper = function(name) return Key(name or A1) ~= Key(A1) and isKeeper(name) end
	c.a1.c.IsHighCouncillor = function(name) return Key(name) == Key(A1) end
	w:Run(1)
	local copy = w:As(c.a1, c.a1.Count.Led)
	assert(copy ~= kept, "the client has switched to the separate council copy")
	for _, msg in ipairs(delayed) do
		eq(select(2, w:As(c.a1, c.a1.Count.Receive, "NL", "WHISPER", A2, msg)), "unasked")
	end
	eq(kept.from[Key(A2)], nil); eq(copy.from[Key(A2)], nil)
	eq(Joins(w, c.a1, "Mira Wells", "a"), 0)
end)

test("Church ledger v2 rechecks queued private rows when the recipient loses its role", function()
	local w, c = LedgerPageWorld()
	Give(w, c.a2, "Queued Rec", "Mira Wells", 2)
	w:Run(2)
	local whisper, offered = c.a2.c.Comm.Whisper, nil
	c.a2.c.Comm.Whisper = function(target, msg, key, urgent, logged, done, options)
		if target == A1 and msg:match("^NL~2~d~") then
			offered = { done = done, guard = options.guard }
			return true
		end
		return whisper(target, msg, key, urgent, logged, done, options)
	end
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	assert(offered and type(offered.guard) == "function", "queued row has an authority guard")
	eq(w:As(c.a2, offered.guard), true)
	local isRelay = c.a2.Church.IsLedgerRelay
	c.a2.Church.IsLedgerRelay = function(name) return Key(name or A2) ~= Key(A1) and isRelay(name) end
	eq(w:As(c.a2, offered.guard), false)
	w:As(c.a2, offered.done, false, "guard")
	eq(#LedgerMessages(w, c.a2, 2, "e"), 0, "the cancelled row cannot emit its terminal")
end)

test("Church ledger retains a deferred person row with its original ledger when roles change", function()
	local w, c = LedgerPageWorld()
	local c1 = c.a1
	local original, isPerson, isKeeper = w:As(c1, c1.Count.Led), c1.Church.IsPerson, c1.Church.IsKeeper
	local line = ("NL~1~p~Mira Wells~0~0~10~1~0~%s"):format(c1.Church.B36(w.clock))
	c1.Church.IsPerson = function(name) return Key(name) ~= Key("Mira Wells") and isPerson(name) end
	eq(select(2, w:As(c1, c1.Count.Receive, "NL", "WHISPER", A2, line)), "person")
	eq(#c1.Count.LaterLines(), 1)
	c1.Church.IsKeeper = function(name) return Key(name or A1) ~= Key(A1) and isKeeper(name) end
	c1.c.IsHighCouncillor = function(name) return Key(name) == Key(A1) end
	c1.Church.IsPerson = isPerson
	w:Run(1)
	eq(w:As(c1, c1.Count.RetryLater), 0)
	eq(Joins(w, c1, "Mira Wells", "a"), 0)
	eq(#c1.Count.LaterLines(), 1)
	c1.Church.IsKeeper = isKeeper
	w:Run(1)
	eq(w:As(c1, c1.Count.Led), original)
	eq(w:As(c1, c1.Count.RetryLater), 1)
	eq(Joins(w, c1, "Mira Wells", "a"), 1)
end)

test("Church ledger recovery replays verified recent records without advancing a saved cursor", function()
	local w, c = LedgerPageWorld()
	Give(w, c.a2, "Earlier Rec", "Mira Wells", 200)
	Rec(w, c.a2, "Earlier Rec", "Mira Wells").u = w.clock - 8 * DAY
	Give(w, c.a2, "Missed Reca", "Mira Wells", 2)
	Give(w, c.a2, "Missed Recb", "Mira Wells", 2)
	w:Run(2)
	local peer, saved = Key(A2), w.clock - 1
	local ledger = w:As(c.a1, c.a1.Count.Led)
	ledger.from[peer] = saved
	eq(w:Act(c.a1, c.a1.Church.Slash, "recover"), false, "the peer has not proved v2 support")
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	eq(ledger.nl2[peer], true)
	eq(Joins(w, c.a1, "Mira Wells", "a"), 0, "ordinary catch-up cannot see rows behind the old cursor")
	c.a2.Count.CATCHUP_LINES = 1
	w:Run(6) -- beyond the source's minimum request spacing
	local caught = ledger.caught[peer]
	eq(w:Act(c.wes, c.wes.Church.Slash, "recover"), false, "only keepers can request recovery")
	eq(w:Act(c.a1, c.a1.Church.Slash, "recover"), true)
	eq(w:Act(c.a1, c.a1.Church.Slash, "recover"), false, "one transfer at a time")
	w:Run(6)
	eq(Joins(w, c.a1, "Mira Wells", "a"), 2, "both recent pages merged")
	eq(Rec(w, c.a1, "Earlier Rec", "Mira Wells"), nil, "outside the seven-day recovery window")
	eq(ledger.from[peer], saved); eq(ledger.caught[peer], caught)
	assert(table.concat(w:As(c.a1, c.a1.Count.StatusLines), "\n"):find("complete (2 complete pages)", 1, true))
	eq(w:Act(c.a1, c.a1.Church.Slash, "recover"), false, "a completed replay still observes the cooldown")
end)

test("Church ledger catch-up withholds its terminal on a failed queued row and recovers without skipping it", function()
	local w, c = Cast()
	Give(w, c.a2, "Lost Reca", "Mira Wells", 2)
	Give(w, c.a2, "Lost Recb", "Mira Wells", 2)
	w:Run(2) -- Both source changes are before the terminal's cursor.
	w:ClearSent()
	local whisper, complete, interrupted = c.a2.c.Comm.Whisper, nil, false
	c.a2.c.Comm.Whisper = function(target, msg, key, urgent, logged, done, options)
		if target == A1 and msg:match("^NL~1~r~Lost Recb~") and not interrupted then
			interrupted, complete = true, done
			return true -- The native queue will evict this accepted row before sending it.
		end
		return whisper(target, msg, key, urgent, logged, done, options)
	end
	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	eq(#w:Sent(c.a2, "NL", "WHISPER", "e"), 0, "the last row is still in the native queue")
	assert(interrupted and complete)
	assert(Rec(w, c.a1, "Lost Reca", "Mira Wells"))
	eq(Rec(w, c.a1, "Lost Recb", "Mira Wells"), nil)
	w:As(c.a2, complete, false, "dropped")
	w:Run(5)
	eq(#w:Sent(c.a2, "NL", "WHISPER", "e"), 0, "the first round never completed")
	eq(w:As(c.a1, c.a1.Count.Led).from[Key(A2)], nil, "the cursor did not advance")

	eq(w:Act(c.a1, c.a1.Count.CatchUp, true), true)
	eq(#w:Sent(c.a2, "NL", "WHISPER", "e"), 1)
	eq(Joins(w, c.a1, "Mira Wells", "a"), 2, "both source records converge once")
end)

test("global Church ledger: a record changed in the second a catch-up ended comes with the next catch-up", function()
	local w, c = Cast()
	Give(w, c.a2, "Gap Reca", "Mira Wells", 2)
	w:ClearSent()
	eq(w:As(c.a1, c.a1.Count.CatchUp, true), true)
	w:Flush()
	assert(Rec(w, c.a1, "Gap Reca", "Mira Wells"), "the first catch-up")
	local e = w:Sent(c.a2, "NL", "WHISPER", "e")
	local u, at = e[#e] and c.a1.Church.UnB36(e[#e].msg:match("^NL~1~e~0~([0-9a-z]+)$")), w.clock
	-- Later in that same second, Bera takes another record.
	Give(w, c.a2, "Gap Recb", "Mira Wells", 2)
	eq(Rec(w, c.a1, "Gap Recb", "Mira Wells"), nil)
	w:Run(3600)
	w:Presence()
	eq(w:As(c.a1, c.a1.Count.CatchUp, true), true)
	w:Run(60)
	assert(Rec(w, c.a1, "Gap Recb", "Mira Wells"), "not left behind by the cursor")
	assert(Rec(w, c.a1, "Gap Reca", "Mira Wells"), "the one of that second, merged again, still there")
	assert(u and u < at, "the first ended a second before the one it was answered in")
end)

test("global Church ledger: a keeper's own tab says it is catching up while its first catch-up goes on, and is live once it ended", function()
	local w, c = Cast()
	c.a1.online = false
	for i = 1, 5 do Give(w, c.a2, "Own Rec" .. Letters(i), "Mira Wells", 2); w:Run(1) end
	-- Aldric logs in again, with the tab (ChurchView.lua).
	local again = w:Client(c.a1.name, { guild = c.a1.guild, rank = c.a1.rank, rdb = c.a1.ns.rdb, view = true })
	w:As(again, again.ns.Fire, "INIT")
	Login(w, again)
	w:Presence()
	w:Run(30)
	local L = ns.L
	local function Line()
		again.View.page, again.View.list, again.View.window = "ranking", "m", "a"
		local lines = w:As(again, again.View.Build)
		local all = {}
		for _, line in ipairs(lines) do all[#all + 1] = line.text or "" end
		return table.concat(all, "\n")
	end
	local _, _, remote, catching = w:As(again, again.Count.RankingView, "m", "a")
	eq(remote, false, "his own ledger")
	eq(catching, true, "still catching up")
	eq(select(4, w:As(again, again.Count.DetailView, "Mira Wells", "a")), true)
	assert(Line():find(L.CHURCH_ASOF_CATCHING, 1, true), "the tab says so")
	assert(not Line():find(L.CHURCH_ASOF_LIVE, 1, true), "not live")
	-- Caught up from Bera: live, with her five.
	local t0 = w.clock
	while w.clock - t0 < 1500 and not w:As(again, again.Count.Settled) do w:Tick(); w:Run(30) end
	eq(select(4, w:As(again, again.Count.RankingView, "m", "a")), false)
	eq(JoinsOn(w, again, "Mira Wells", "m", "a"), 5)
	assert(Line():find(L.CHURCH_ASOF_LIVE, 1, true), "live")
	-- Settled with no catch-up (no other keeper heard by the end of the wait to hear them): the tick
	-- that settles it tells the tab, which said it was catching up.
	c.a2.online = false
	local alone = Reload(w, again)
	Login(w, alone)
	w:Presence({ alone })
	local wait = alone.Church.KEEPER_EVERY * alone.Church.FRESH_FACTOR
	local function Told(seconds)
		w:Run(seconds)
		alone.fired = {}
		w:As(alone, alone.Count.Tick)
		for _, event in ipairs(alone.fired) do if event == "CHURCH_COUNT_CHANGED" then return true end end
		return false
	end
	eq(Told(0), false)
	Told(wait - 60) -- (the ledger's first upkeep, Count.Prune, a change of its own)
	eq(Told(30), false, "still waiting")
	eq(select(4, w:As(alone, alone.Count.RankingView, "m", "a")), true)
	eq(Told(30), true, "settled")
	eq(select(4, w:As(alone, alone.Count.RankingView, "m", "a")), false)
end)

-- Three actual Apostles: council relays intentionally cannot pull a keeper's private ledger.
local function Catchup152World()
	local Z = "Zed Last-Realm"
	local w = World.New({ apostles = { A1, A2, Z }, head = false })
	local c = { a1 = w:Client(A1), a2 = w:Client(A2, { guild = World.GUILD2 }), recv = w:Client(Z), m1 = w:Client("Mira Wells") }
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Run(8 * 3600)
	w:Presence()
	return w, c
end

test("1.5.2 Church catch-up: a completed source promptly sweeps other keepers' missing records", function()
	local w, c = Catchup152World()
	for i = 1, 3 do Give(w, c.a1, "Sweep Ald" .. Letters(i), "Mira Wells", 2) end
	for i = 1, 4 do Give(w, c.a2, "Sweep Ber" .. Letters(i), "Mira Wells", 2) end
	w:ClearSent()
	eq(w:As(c.recv, c.recv.Count.CatchUp, true), true)
	w:Run(10)
	local q = w:Sent(c.recv, "NL", "WHISPER", "q")
	eq(#q, 2, "one bounded request to each visible keeper")
	eq(Key(q[1].target), Key(A1)); eq(Key(q[2].target), Key(A2))
	eq(Joins(w, c.recv, "Mira Wells", "a"), 7, "both fragments before the half-hour rotation")
end)

test("1.5.2 Church catch-up: silence after an earlier completion retries another keeper", function()
	local w, c = Catchup152World()
	eq(w:As(c.recv, c.recv.Count.CatchUp, true), true)
	w:Run(10)
	eq(w:As(c.recv, c.recv.Count.Settled), true)
	Give(w, c.a2, "Retry Recruit", "Mira Wells", 2)
	c.a1.Count.TakeLine = function() return false, "busy" end
	w:Run(c.recv.Count.CATCHUP_EVERY)
	w:Presence(); w:ClearSent()
	eq(w:As(c.recv, c.recv.Count.CatchUp, false), true)
	eq(Key(w:Sent(c.recv, "NL", "WHISPER", "q")[1].target), Key(A1))
	w:Run(c.recv.Count.CATCHUP_RETRY)
	eq(w:As(c.recv, c.recv.Count.CatchUp, false), true, "retry remains active after first completion")
	w:Run(10)
	assert(Rec(w, c.recv, "Retry Recruit", "Mira Wells"), "record held only by the responsive keeper arrived")
end)

test("1.5.2 Church catch-up: a vanished source does not block a newly available keeper", function()
	local w, c = Catchup152World()
	c.a1.Count.TakeLine = function() return false, "busy" end
	eq(w:As(c.recv, c.recv.Count.CatchUp, true), true)
	c.a1.online, c.a2.online = false, false
	w:Run(c.recv.Church.KEEPER_EVERY * c.recv.Church.FRESH_FACTOR + 1)
	eq(w:As(c.recv, c.recv.Count.CatchUp, false), false)
	c.a2.online = true
	w:Presence({ c.a2 }); w:ClearSent()
	eq(w:As(c.recv, c.recv.Count.CatchUp, false), true)
	eq(Key(w:Sent(c.recv, "NL", "WHISPER", "q")[1].target), Key(A2))
end)

test("1.5.2 Church catch-up: one silent keeper is bounded by the per-source reask interval", function()
	local w, c = Catchup152World()
	c.a2.online = false
	w:Run(c.recv.Church.KEEPER_EVERY * c.recv.Church.FRESH_FACTOR + 1)
	w:Presence({ c.a1, c.recv })
	c.a1.Count.TakeLine = function() return false, "busy" end
	w:ClearSent()
	eq(w:As(c.recv, c.recv.Count.CatchUp, true), true)
	w:Run(c.recv.Count.CATCHUP_RETRY)
	for _ = 1, 10 do
		eq(w:As(c.recv, c.recv.Count.CatchUp, false), false)
		w:Run(1)
	end
	eq(#w:Sent(c.recv, "NL", "WHISPER", "q"), 1)
	w:Run(c.recv.Count.CATCHUP_REASK - c.recv.Count.CATCHUP_RETRY - 10)
	eq(w:As(c.recv, c.recv.Count.CatchUp, false), true)
	eq(#w:Sent(c.recv, "NL", "WHISPER", "q"), 2)
end)

---------------------------------------------------------------------------
-- 1.5.5 (the author, 2026-11-10: "continua sem contar nenhuma pontuação para mim. Dos membros da igreja"):
-- his client held the signed titles list that names the Twelve Apostles (pasted on 11-09); the relay took it
-- to almost nobody, so the Apostles' own clients and their guildmates' still held the launch list, which names
-- none. An Apostle whose own client does not know he is one says nothing over GUILD, so no guildmate read
-- the guild's log (a Church person's presence heard, Count.HeardPresence, was the only reason); and the
-- author's client, a keeper but no Church person, never read its own guild's either. Nothing was counted
-- anywhere: every Apostle at 0 on his Church tab, five of them in his own guild.
---------------------------------------------------------------------------

-- The list a client held before the Apostles were signed: this world's, an hour older, no ^apostles^ entry.
local function ListWithoutApostles(w)
	local t = w.titles
	local at = t.at - 3600
	local blob = t.blob:gsub(";%^apostles%^[^;~]*", ""):gsub("^HT1~%d+~", "HT1~" .. at .. "~")
	return { at = at, depts = t.depts, blob = blob }
end

-- The author, an Apostle (Aldric) and a plain member (Wes) in one guild; the King away. `launch` names the
-- clients that still hold the launch list (no Apostle in it); the others hold the one that names Aldric. The
-- author's client is away while `away` says so. Aldric invites a player, who joins an hour later and stays.
local function OneGuild(launch, away)
	local w = World.New({ apostles = { A1 }, head = false })
	local old = ListWithoutApostles(w)
	local c = { author = w:Client(World.AUTHOR), a1 = w:Client(A1), wes = w:Client("Wes Brook"), king = w:Client(World.KING) }
	for name in pairs(launch) do c[name].c.CouncilTitles = function() return old end end
	c.king.online, c.author.online = false, not away
	w:Run(3600)
	w:Presence()
	w:LogEvent(World.GUILD, "invite", A1, "New Guy", 3)
	w:LogEvent(World.GUILD, "join", "New Guy", nil, 2)
	Join(w, World.GUILD, "New Guy")
	return w, c
end
-- An hour of the clients' ticks: a read is due each READ_EVERY.
local function AnHour(w) for _ = 1, 13 do w:Tick(); w:Run(300) end end
local function ApostleRow(w, cl)
	for _, row in ipairs(w:As(cl, cl.Count.Ranking, "a", "m")) do
		if row.key == Key(A1) then return row end
	end
end

test("1.5.5 Church (regression): a keeper's client reads its own guild's log, as a Church person's does: the author's alone counts his guild's Apostle's recruit", function()
	local w, c = OneGuild({ a1 = true, wes = true })
	-- His guild's three hundred addon users online: a member's draw (2 in 300) would almost never pick him.
	c.author.peers = 300
	c.author.Count.chance = function() return 0.5 end
	AnHour(w)
	eq(w:As(c.a1, c.a1.Church.Role, A1), nil, "the Apostle's own client does not know he is one")
	eq(#w:Sent(c.a1, "NK"), 0, "so it says nothing over GUILD")
	eq(c.a1.queries, 0, "nor reads the log")
	-- (Failed before: the author is a keeper, W, but no Church person, and no Church person was heard in his
	-- guild: his client never read its log, and his ledger stayed empty.)
	eq(c.author.queries > 0, true, "the author's client read its guild's log on its own")
	eq(StateOf(w, c.author, "New Guy", A1), "credited", "his own read of the log: a keeper is a witness he vouches for")
	eq(Records(w, c.author), 1)
	eq(ApostleRow(w, c.author).score, c.author.Count.POINTS_JOIN, "his Church tab: the Apostle's ten points")
	eq(c.wes.queries, 0, "a member whose list names no Church person, and who heard none, still does not read")
end)

test("1.5.5 Church (regression): a member whose own list names a Church person of his guild reads its log (drawn) though that person's client never said so; his report waits for a keeper", function()
	-- Aldric's client still holds the launch list; Wes's names him (the list the release carries); the author,
	-- a keeper of this guild, is away.
	local w, c = OneGuild({ a1 = true }, true)
	AnHour(w)
	eq(#w:Sent(c.a1, "NK"), 0, "no Church presence from the Apostle")
	eq(w:As(c.wes, c.wes.Count.Claimed, A1), false, "nor heard by Wes")
	-- (Failed before: no presence heard, no read.)
	eq(c.wes.queries > 0, true, "Wes's client read the log: its roster holds an Apostle of its own list")
	eq(w:As(c.wes, c.wes.Count.Stats).pairs, 1, "the Apostle's invite and the join: one pair")
	eq(c.a1.queries, 0, "the Apostle's own client still reads nothing: its list names nobody")
	-- The game keeps the newest events only: they are gone from the log when the author logs in. Wes's report,
	-- kept in his outbox, reaches him; his roster saw the recruit join, so he vouches for his guildmate.
	w.log[World.GUILD] = {}
	c.author.online = true
	w:Presence({ c.author })
	Settle(w, 30)
	eq(StateOf(w, c.author, "New Guy", A1), "credited", "Wes's read, vouched for in the author's own guild")
	eq(ApostleRow(w, c.author).score, c.author.Count.POINTS_JOIN)
	-- A member of a guild where his list names nobody and nobody was heard: no read, as before.
	local lone = w:Client("Lone Wolf", { guild = "Olympus Lone" })
	eq(w:As(lone, lone.Count.MaybeRead, w.clock + 400), false, "no Church person in his guild")
	eq(lone.queries, 0)
end)
