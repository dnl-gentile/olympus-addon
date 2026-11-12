-- 1.5.9, the recruiting ranking for everyone (Olympus/RecruitRanking.lua). The author, 2026-11-12:
-- "O ranking para todo mundo", and on the handoffs: "devia contar menos pontos, tipo os pontos da
-- rede... Se a pessoa for convidada e aceitar entrar na guilda". Any member's confirmed recruit counts,
-- the member who passed that player on gets 25% of it, nothing counts before the join is confirmed, a
-- recruit counts once, the keepers' records are kept, relayed and recovered, and every member sees the
-- ranking with his own place. Its records never enter the Church's own ledger.
-- Run alone: luajit tests/run.lua "1.5.9 recruiting ranking"
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]recruit%-ranking%.lua$")) or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local Key = World.Key
local L = ns.L
local DAY = 86400

local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"

-- An error in the ranking's code fails the test: the clients' SafeCall rethrows (the game's logs it).
local function Loud(cl) cl.c.SafeCall = function(_, fn, ...) fn(...) return true end end

-- Two guilds: Aldric (an Apostle, a keeper) with Ivo (a plain member who invites), Wes (a plain member,
-- a witness) and Sid (a plain member who passes players on) in Olympus Ember; Bera (an Apostle) and Vik (a
-- plain member) in Olympus Vale. The Head, the King and the author are offline unless a test brings them.
local function Cast(more)
	local w = World.New({ apostles = { A1, A2 } })
	local c = {
		head = w:Client(World.HEAD), king = w:Client(World.KING), author = w:Client(World.AUTHOR),
		a1 = w:Client(A1), a2 = w:Client(A2, { guild = World.GUILD2 }),
		ivo = w:Client("Ivo Plain"), wes = w:Client("Wes Brook"), sid = w:Client("Sid Pass"),
		vik = w:Client("Vik Stone", { guild = World.GUILD2 }),
	}
	for name, opts in pairs(more or {}) do c[name] = w:Client(opts.name, opts) end
	for _, cl in pairs(c) do Loud(cl) end
	c.head.online, c.king.online, c.author.online = false, false, false
	w:Run(3600)
	w:Presence()
	return w, c
end

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
-- `inviter` invites `recruit` into `guild`, who joins in the same hour, `hoursAgo` hours ago.
local function Recruit(w, guild, inviter, recruit, hoursAgo)
	w:LogEvent(guild, "invite", inviter, recruit, hoursAgo or 0)
	w:LogEvent(guild, "join", recruit, nil, hoursAgo or 0)
	Join(w, guild, recruit)
end
local function Id(recruit, by) return Key(recruit) .. ":" .. Key(by) end
local function State(w, k, recruit, by) return w:As(k, k.RR.StateOf, Id(recruit, by)) end
local function Rec(w, k, recruit, by) return w:As(k, k.RR.Led).r[Id(recruit, by)] end
-- A person's row in a keeper's own ranking (nil: no row at all).
local function Row(w, k, name, window)
	local _, byKey = w:As(k, k.RR.Ranking, window or "m")
	return byKey[Key(name)]
end
local function Score(w, k, name, window)
	local row = Row(w, k, name, window)
	return row and row.score or 0
end
local function Outbox(cl) return #((cl.c.rdb.recruits or {}).out or {}) end
local function SentTo(w, from, to, sub)
	local n = 0
	for _, e in ipairs(w:Sent(from, "NE", "WHISPER", sub)) do if Key(e.target) == Key(to) then n = n + 1 end end
	return n
end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- Letters, not bytes: a Cyrillic or accented letter is one on screen.
local function Letters(s) local _, n = Plain(s):gsub("[^\128-\191]", "") return n end

test("1.5.9 recruiting ranking: any member's invite and the join, confirmed by a guildmate's addon, earn the inviter 10; the Church's ledger takes none of it", function()
	local w, c = Cast()
	Recruit(w, World.GUILD, "Ivo Plain", "New Guy", 1)
	eq(w:ReadLog(c.ivo), true)
	eq(#w:Sent(c.ivo, "NE"), 0, "the inviter's own read, nobody having passed him the player: his word confirms nothing, so it goes nowhere")
	eq(w:ReadLog(c.wes), true)
	eq(#w:Sent(c.wes, "NE", "WHISPER", "w"), 2, "a guildmate's read: to each keeper heard online")
	eq(State(w, c.a1, "New Guy", "Ivo Plain"), "credited", "his guild's keeper vouches for his guildmate who saw the join")
	eq(Rec(w, c.a1, "New Guy", "Ivo Plain").ws[1], Key("Wes Brook"))
	eq(State(w, c.a2, "New Guy", "Ivo Plain"), "credited", "the other guild's keeper took it from the one that vouched")
	local row = Row(w, c.a1, "Ivo Plain")
	eq(row.score, 10); eq(row.own, 10); eq(row.share, 0); eq(row.joins, 1); eq(row.stays, 0); eq(row.rank, 1)
	eq(Score(w, c.a2, "Ivo Plain"), 10)
	for _, window in ipairs({ "w", "a" }) do eq(Score(w, c.a1, "Ivo Plain", window), 10, window) end
	-- No Church mix-up: Ivo holds no place, so neither keeper's Church ledger or recruiters list has him,
	-- and no Church evidence went anywhere.
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(next(w:As(k, k.Count.Led).r), nil, k.name .. ": the Church's ledger")
		eq(#w:As(k, k.Count.Ranking, "u", "a"), 0, k.name .. ": the Church's recruiters")
	end
	eq(#w:Sent(nil, "NV"), 0, "no Church evidence for a member's invite")
	-- Wes's report leaves his outbox with the vouching keeper's receipt; Bera, who can't vouch for him in
	-- another guild, says so (a refusal, not a receipt).
	w:Run(6)
	eq(SentTo(w, c.a1, "Wes Brook", "k"), 1)
	eq(SentTo(w, c.a2, "Wes Brook", "x"), 1)
	eq(Outbox(c.wes), 0)
	-- Read again: nothing twice.
	w:ClearSent()
	w:ReadLog(c.wes)
	eq(#w:Sent(nil, "NE", nil, "w"), 0)
end)

test("1.5.9 recruiting ranking: a player another member passed on: pending on the inviter's own word, nothing for anyone; confirmed, the inviter 10 and the member who passed him 2.5", function()
	local w, c = Cast()
	-- Sid passed Ivo a JOIN (RecruitHandoff's name, Recruit.TakeHandoff): Ivo's client keeps who did.
	eq(w:As(c.ivo, c.ivo.RR.HandedIn, "New Guy-Realm", "Sid Pass-Realm"), true)
	eq(w:As(c.ivo, c.ivo.RR.ReadWanted), "own", "his client reads its log as a Church person's does, to name him")
	eq(w:As(c.wes, c.wes.RR.ReadWanted), "drawn", "any other member's: drawn")
	-- (Read every READ_EVERY, whatever the draw: his guild's 300 addon users would almost never draw him.)
	c.ivo.peers, c.ivo.Count.chance = 300, function() return 0.9 end
	eq(w:As(c.ivo, c.ivo.Count.MaybeRead, w.clock + 1000), true)
	w:Run(1800)
	w:Presence()
	Recruit(w, World.GUILD, "Ivo Plain", "New Guy", 0)
	w:ReadLog(c.ivo)
	local sent = w:Sent(c.ivo, "NE", "WHISPER", "w")
	eq(#sent, 2, "his own report, to each keeper online")
	assert(sent[1].msg:match("~Sid Pass$"), sent[1].msg)
	eq(State(w, c.a1, "New Guy", "Ivo Plain"), "pending", "only the inviter's word")
	eq(Rec(w, c.a1, "New Guy", "Ivo Plain").src, "Sid Pass")
	eq(Rec(w, c.a1, "New Guy", "Ivo Plain").s, 1)
	eq(Score(w, c.a1, "Ivo Plain"), 0, "no points before another addon confirms the join")
	eq(Row(w, c.a1, "Ivo Plain").pending, 1)
	eq(Score(w, c.a1, "Sid Pass"), 0, "nor for the member who passed him")
	-- A guildmate's read confirms it: the inviter's 10, and 25% of them for the one who passed the player.
	w:ReadLog(c.wes)
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(State(w, k, "New Guy", "Ivo Plain"), "credited", k.name)
		eq(Score(w, k, "Ivo Plain"), 10, k.name)
		local sid = Row(w, k, "Sid Pass")
		eq(sid.score, 2.5, k.name); eq(sid.share, 2.5); eq(sid.own, 0); eq(sid.passed, 1); eq(sid.joins, 0)
	end
	local rows = w:As(c.a1, c.a1.RR.Ranking, "m")
	eq(rows[1].name, "Ivo Plain"); eq(rows[2].name, "Sid Pass")
	-- Past the handoff's hours his client reads as any other member's again.
	w:Run((c.ivo.RR.PAIR_HOURS + 3) * 3600)
	eq(w:As(c.ivo, c.ivo.RR.ReadWanted), "drawn")
end)

test("1.5.9 recruiting ranking: still in the guild 7 days after joining: 5 more for the inviter, 25% of them for the member who passed him; gone by then: nothing more", function()
	local w, c = Cast()
	w:As(c.ivo, c.ivo.RR.HandedIn, "Stays Long-Realm", "Sid Pass-Realm")
	w:As(c.ivo, c.ivo.RR.HandedIn, "Leaves Soon-Realm", "Sid Pass-Realm")
	w:Run(600)
	w:Presence()
	Recruit(w, World.GUILD, "Ivo Plain", "Stays Long", 0)
	Recruit(w, World.GUILD, "Ivo Plain", "Leaves Soon", 0)
	w:ReadLog(c.ivo); w:ReadLog(c.wes)
	eq(Score(w, c.a1, "Ivo Plain"), 20)
	eq(Score(w, c.a1, "Sid Pass"), 5)
	-- One leaves on his fourth day; the other stays. A keeper of another guild takes the witness's word.
	w:Run(4 * DAY)
	Leave(w, World.GUILD, "Leaves Soon")
	w:Tick()
	w:Run(3 * DAY + 3600)
	w:Presence()
	w:Tick()
	w:Run(10)
	eq(#w:Sent(c.wes, "NE", "WHISPER", "y") >= 2, true, "the witness told both stays")
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(Rec(w, k, "Stays Long", "Ivo Plain").y, 1, k.name)
		eq(Rec(w, k, "Leaves Soon", "Ivo Plain").y, 0, k.name)
		local ivo = Row(w, k, "Ivo Plain", "a")
		eq(ivo.score, 25, k.name); eq(ivo.stays, 1); eq(ivo.joins, 2)
		eq(Score(w, k, "Sid Pass", "a"), 6.25, k.name .. ": 25% of 10 + 5 + 10")
	end
end)

test("1.5.9 recruiting ranking: who passed the player on counts only as the inviter's own report names him, and never as his own alt or the recruit", function()
	local w, c = Cast()
	w.alts[Key("Ivo Plain")] = { "Ivo Twink-Realm" }
	w:As(c.ivo, c.ivo.RR.HandedIn, "Alt Pal-Realm", "Ivo Twink-Realm")
	eq(w:As(c.ivo, c.ivo.RR.HandedIn, "Same Guy-Realm", "Same Guy-Realm"), false, "nobody passes himself on")
	w:Run(600)
	w:Presence()
	Recruit(w, World.GUILD, "Ivo Plain", "Alt Pal", 0)
	w:ReadLog(c.ivo); w:ReadLog(c.wes)
	eq(State(w, c.a1, "Alt Pal", "Ivo Plain"), "credited")
	eq(Rec(w, c.a1, "Alt Pal", "Ivo Plain").src, nil, "the inviter's own alt is no source")
	eq(Row(w, c.a1, "Ivo Twink"), nil)
	eq(Score(w, c.a1, "Ivo Plain"), 10)
	-- A witness's report naming a source is not the inviter's word: the keeper takes no source from it.
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	local text = ("NE~1~w~Ivo Plain~Other Pal~%s~%s~%s~Wes Brook"):format(World.GUILD, B(hour), B(hour))
	Join(w, World.GUILD, "Other Pal")
	eq(w:As(c.a1, c.a1.RR.TakeEvidence, "Wes Brook-Realm", text), true)
	eq(Rec(w, c.a1, "Other Pal", "Ivo Plain").src, nil)
	eq(Rec(w, c.a1, "Other Pal", "Ivo Plain").ws[1], Key("Wes Brook"))
end)

test("1.5.9 recruiting ranking: one recruit counts once: invited again elsewhere after leaving, back in his old guild, an alt of the inviter", function()
	local w, c = Cast()
	-- Roamer joins Olympus Ember through Ivo, confirmed; he leaves and Vik invites him into Olympus Vale,
	-- where Bera (a keeper) reads it herself.
	Recruit(w, World.GUILD, "Ivo Plain", "Roamer", 1)
	w:ReadLog(c.wes)
	eq(Score(w, c.a1, "Ivo Plain"), 10)
	w:Tick()
	w:Run(DAY)
	Leave(w, World.GUILD, "Roamer")
	w:Tick()
	w:Run(2 * DAY)
	w:Presence()
	Recruit(w, World.GUILD2, "Vik Stone", "Roamer", 0)
	w:ReadLog(c.a2)
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(Score(w, k, "Vik Stone"), 0, k.name .. ": no second count for the same player")
		eq(Score(w, k, "Ivo Plain", "a"), 10, k.name)
	end
	-- Aldric's roster memory saw him in Olympus Ember three days ago: a move between Olympus guilds, which
	-- he tells Bera.
	eq(State(w, c.a1, "Roamer", "Vik Stone"), "transfer")
	eq(State(w, c.a2, "Roamer", "Vik Stone"), "transfer")
	-- Old Timer was in Olympus Ember for weeks, left, and comes back through Ivo: a return, not a recruit.
	Join(w, World.GUILD, "Old Timer")
	w:Tick()
	w:Run(20 * DAY)
	w:Tick()
	Leave(w, World.GUILD, "Old Timer")
	w:Tick()
	w:Run(3 * DAY)
	w:Presence()
	Recruit(w, World.GUILD, "Ivo Plain", "Old Timer", 0)
	w:ReadLog(c.wes)
	eq(State(w, c.a1, "Old Timer", "Ivo Plain"), "transfer")
	eq(State(w, c.a2, "Old Timer", "Ivo Plain"), "transfer", "the keeper that knew tells the other")
	-- An alt of the inviter's, invited by him: never.
	w.alts[Key("Ivo Plain")] = { "Ivo Twin-Realm" }
	Recruit(w, World.GUILD, "Ivo Plain", "Ivo Twin", 0)
	w:Run(61)
	w:ReadLog(c.wes)
	eq(State(w, c.a1, "Ivo Twin", "Ivo Plain"), "alt")
	-- The same invite and join read twice, or a second invite by the same member: one record.
	Recruit(w, World.GUILD, "Ivo Plain", "Twice Guy", 0)
	w:Run(61)
	w:ReadLog(c.wes)
	w:Run(3 * 3600)
	w:Presence()
	w:LogEvent(World.GUILD, "invite", "Ivo Plain", "Twice Guy", 0)
	w:LogEvent(World.GUILD, "join", "Twice Guy", nil, 0)
	w:Run(61)
	w:ReadLog(c.wes)
	eq(Row(w, c.a1, "Ivo Plain", "a").joins, 2, "Roamer and Twice Guy, each once")
	eq(Score(w, c.a1, "Ivo Plain", "a"), 20)
end)

test("1.5.9 recruiting ranking: the keepers' records: a keeper away catches up in whole pages, a lost row asked again, and folded totals and marks come with them", function()
	local w, c = Cast()
	c.a2.online = false
	w:As(c.ivo, c.ivo.RR.HandedIn, "Rec Aa-Realm", "Sid Pass-Realm")
	w:Run(600)
	w:Presence()
	for _, name in ipairs({ "Rec Aa", "Rec Bb", "Rec Cc", "Rec Dd" }) do Recruit(w, World.GUILD, "Ivo Plain", name, 0) end
	w:ReadLog(c.ivo); w:ReadLog(c.wes)
	eq(Row(w, c.a1, "Ivo Plain").joins, 4)
	eq(next(w:As(c.a2, c.a2.RR.Led).r), nil, "Bera was away")
	-- Bera comes back; pages of two rows; the first page loses a row on the way.
	c.a1.RR.CATCHUP_LINES, c.a2.RR.CATCHUP_LINES = 2, 2
	c.a2.online = true
	w:Presence()
	w:ClearSent()
	w:As(c.a2, c.a2.RR.CatchUp, true)
	eq(#w:Sent(c.a2, "NE", "WHISPER", "q"), 1)
	w:Flush(1)
	local lost
	for i, e in ipairs(w.pending) do
		if e.msg:match("^NE~1~d~") then lost = table.remove(w.pending, i) break end
	end
	assert(lost, "a row on its way")
	w:Flush()
	eq(w:As(c.a2, c.a2.RR.Led).from[Key(A1)], nil, "a page with a row missing moves no cursor")
	eq(w:As(c.a2, c.a2.RR.Stats).dropped["incomplete page"], 1)
	-- Its next try asks the same rows again, page after page, to the end.
	w:Run(c.a2.RR.CATCHUP_RETRY + 1)
	w:Tick({ c.a2 })
	w:Run(30)
	eq(Row(w, c.a2, "Ivo Plain").joins, 4)
	eq(Score(w, c.a2, "Sid Pass"), 2.5)
	eq(w:As(c.a2, c.a2.RR.Settled), true)
	assert(w:As(c.a2, c.a2.RR.Led).caught[Key(A1)], "a whole catch-up")
	-- Folded totals (past RECORDS_DAYS) and the marks of folded recruits come with a later catch-up.
	c.a2.online = false
	w:Run((c.a1.RR.RECORDS_DAYS + 1) * DAY)
	w:As(c.a1, c.a1.RR.Prune)
	eq(next(w:As(c.a1, c.a1.RR.Led).r), nil, "every record folded")
	eq(Score(w, c.a1, "Ivo Plain", "a"), 40, "all time keeps them")
	eq(Score(w, c.a1, "Ivo Plain", "m"), 0, "the last 30 days no longer")
	eq(Score(w, c.a1, "Sid Pass", "a"), 2.5)
	c.a2.online = true
	w:Presence()
	w:As(c.a2, c.a2.RR.CatchUp, true)
	w:Run(30)
	eq(Score(w, c.a2, "Ivo Plain", "a"), 40, "Bera's all time: Aldric's folds, once")
	eq(Score(w, c.a2, "Sid Pass", "a"), 2.5)
	eq(next(w:As(c.a2, c.a2.RR.Led).r), nil, "her own copies folded too, never counted twice")
	-- A folded recruit claimed again (another member's invite) counts no more: its mark, on a keeper whose
	-- own roster never saw him. (Aldric's saw him there all along: a return, as the test above shows.)
	w:As(c.a2, c.a2.RR.MergeIn, Id("Rec Aa", "Wes Brook"), { n = "Rec Aa", bn = "Wes Brook", g = World.GUILD, tc = w.clock - 3600,
		tj = w.clock - 3600, ws = { "vik stone" } }, false)
	eq(State(w, c.a2, "Rec Aa", "Wes Brook"), "taken")
	eq(Score(w, c.a2, "Wes Brook", "a"), 0)
	-- The folded claim itself never comes back from a keeper still holding it.
	eq(w:As(c.a2, c.a2.RR.MergeIn, Id("Rec Aa", "Ivo Plain"), { n = "Rec Aa", bn = "Ivo Plain", g = World.GUILD, tc = w.clock - 3600,
		tj = w.clock - 3600, ws = { "wes brook" } }, false), false)
	eq(Score(w, c.a2, "Ivo Plain", "a"), 40)
end)

test("1.5.9 recruiting ranking: a full ledger lets go of what counts for nothing first, then folds its oldest credited claims: all time loses nothing", function()
	local w, c = Cast()
	local K = c.a1
	K.RR.RECORDS_MAX = 6
	local function Give(recruit, by, hoursAgo, confirmed)
		w:As(K, K.RR.MergeIn, Id(recruit, by), { n = recruit, bn = by, g = World.GUILD, tc = w.clock - hoursAgo * 3600,
			tj = w.clock - hoursAgo * 3600, ws = confirmed and { "wes brook" } or nil }, false)
	end
	Give("Rec Aa", "Ivo Plain", 50, true); Give("Rec Bb", "Ivo Plain", 40, true); Give("Rec Cc", "Ivo Plain", 30, true)
	Give("Rec Dd", "Ivo Plain", 20, true); Give("Rec Ee", "Ivo Plain", 10, false); Give("Rec Aa", "Sid Pass", 5, true)
	eq(w:As(K, K.RR.Led).n, 6)
	eq(State(w, K, "Rec Aa", "Sid Pass"), "taken")
	eq(Score(w, K, "Ivo Plain", "a"), 40)
	Give("Rec Ff", "Ivo Plain", 1, true)
	local l = w:As(K, K.RR.Led)
	eq(l.n, 6)
	eq(l.r[Id("Rec Aa", "Sid Pass")], nil, "the claim that counted for nothing went first")
	eq(Score(w, K, "Ivo Plain", "a"), 50)
	Give("Rec Gg", "Ivo Plain", 1, true)
	eq(l.r[Id("Rec Ee", "Ivo Plain")], nil, "then the pending one")
	Give("Rec Hh", "Ivo Plain", 1, true)
	eq(l.r[Id("Rec Aa", "Ivo Plain")], nil, "then the oldest credited one, folded")
	eq(Score(w, K, "Ivo Plain", "a"), 70, "all time: seven confirmed recruits")
	eq(w:As(K, K.RR.Totals, l.p[Key("Ivo Plain")]), 1)
	-- Its recruit counts no more for anyone.
	Give("Rec Aa", "Wes Brook", 0, true)
	eq(State(w, K, "Rec Aa", "Wes Brook"), "taken")
end)

test("1.5.9 recruiting ranking: older clients: a 1.5.8 keeper drops these words unread and its Church ledger stays as it was; a report goes to it once", function()
	local w = World.New({ apostles = { A1, "Cato Old-Realm" } })
	local c = { a1 = w:Client(A1), cato = w:Client("Cato Old-Realm", { release158 = true }), ivo = w:Client("Ivo Plain"),
		wes = w:Client("Wes Brook"), old = w:Client("Olda Member", { release158 = true }) }
	for _, cl in pairs(c) do Loud(cl) end
	w:Run(3600)
	w:Presence()
	eq(c.cato.handlers.NE, nil, "no handler: Comm drops NE unread")
	Recruit(w, World.GUILD, "Ivo Plain", "New Guy", 0)
	w:ReadLog(c.old)
	eq(#w:Sent(c.old, "NE"), 0, "a 1.5.8 member reports nothing of it")
	w:ReadLog(c.wes)
	eq(SentTo(w, c.wes, "Cato Old", "w"), 1)
	eq(State(w, c.a1, "New Guy", "Ivo Plain"), "credited")
	eq(next(w:As(c.cato, c.cato.Count.Led).r), nil, "the old keeper's Church ledger: nothing")
	eq(#w:As(c.cato, c.cato.Count.Ranking, "u", "a"), 0, "nor its recruiters list")
	eq(next(w:As(c.a1, c.a1.Count.Led).r), nil, "nor the new keeper's Church ledger")
	-- With no 1.5.9 keeper online, a report waits; the old keeper gets it once, never again.
	c.a1.online = false
	Recruit(w, World.GUILD, "Ivo Plain", "Later Guy", 0)
	w:Run(61)
	w:ReadLog(c.wes)
	eq(SentTo(w, c.wes, "Cato Old", "w"), 2)
	eq(Outbox(c.wes), 1)
	for _ = 1, 3 do
		w:Run(c.wes.RR.RESEND_GAP + 1)
		w:Presence()
		w:Tick({ c.wes })
	end
	eq(SentTo(w, c.wes, "Cato Old", "w"), 2, "once to a keeper not heard to take these")
	-- Aldric back: the report reaches him, his receipt empties the outbox.
	c.a1.online = true
	w:Presence()
	w:Tick({ c.wes })
	w:Run(6)
	eq(State(w, c.a1, "Later Guy", "Ivo Plain"), "credited")
	eq(Outbox(c.wes), 0)
end)

test("1.5.9 recruiting ranking: who reports a pair: about two members drawn on the pair, the keepers and the guild's correspondent always", function()
	local w = World.New({ apostles = { A1 } })
	local c = { a1 = w:Client(A1), lucky = w:Client("Lucky Draw"), plain = w:Client("Plain Draw"), corr = w:Client("Corr Esp"),
		gm = w:Client("Ember Master", { rank = 0 }) }
	for _, cl in pairs(c) do Loud(cl) end
	w:Act(c.gm, c.gm.Church.NameCorrespondent, "Corr Esp", World.GUILD)
	w:Run(3600)
	w:Presence()
	for _, cl in ipairs({ c.lucky, c.plain, c.corr }) do
		cl.peers = 20
		-- The draw is a number from the pair and the name, the same on every client.
		cl.RR.score = function(_, name) return Key(name) == Key("Lucky Draw") and 0.05 or 0.5 end
	end
	eq(w:As(c.lucky, c.lucky.RR.Reporter, "x:y", World.GUILD), "drawn", "0.05 < 2/20")
	eq(w:As(c.plain, c.plain.RR.Reporter, "x:y", World.GUILD), nil, "0.5 > 2/20")
	eq(w:As(c.corr, c.corr.RR.Reporter, "x:y", World.GUILD), "correspondent")
	eq(w:As(c.a1, c.a1.RR.Reporter, "x:y", World.GUILD), "keeper")
	Recruit(w, World.GUILD, "Ivo Plain", "New Guy", 0)
	for _, cl in ipairs({ c.lucky, c.plain, c.corr, c.a1 }) do w:ReadLog(cl) end
	eq(#w:Sent(c.lucky, "NE", "WHISPER", "w"), 1)
	eq(#w:Sent(c.plain, "NE", "WHISPER", "w"), 0)
	eq(#w:Sent(c.corr, "NE", "WHISPER", "w"), 1)
	eq(State(w, c.a1, "New Guy", "Ivo Plain"), "credited")
	-- The real draw (Aldric's client keeps it): about one in ten under 2/20, across names and pairs.
	local drawn, n = 0, 0
	for i = 1, 20 do
		for j = 1, 10 do
			n = n + 1
			local v = c.a1.RR.score("pair" .. j .. ":ivo plain", "Member " .. string.char(96 + i, 96 + j))
			assert(v >= 0 and v < 1, v)
			if v < 0.1 then drawn = drawn + 1 end
		end
	end
	assert(drawn >= n * 0.04 and drawn <= n * 0.2, "about a tenth drawn: " .. drawn .. " of " .. n)
	eq(c.a1.RR.score("pair1:ivo plain", "Member aa"), c.lucky.RR.score ~= nil and c.a1.RR.score("pair1:ivo plain", "Member aa"), "the same number on every client")
end)

test("1.5.9 recruiting ranking: a Church missionary's recruit counts in the Church's rankings and in this one, each on its own ledger", function()
	local w, c = Cast()
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	c.m1 = w:Client("Mira Wells")
	Loud(c.m1)
	w:Run(8 * 3600)
	w:Presence()
	Recruit(w, World.GUILD, "Mira Wells", "Church Kid", 0)
	w:ReadLog(c.m1); w:ReadLog(c.wes)
	-- The Church's: Mira's 10 and Aldric's 25% of them, on the Church's ledger.
	local apostle
	for _, row in ipairs(w:As(c.a1, c.a1.Count.Ranking, "a", "m")) do if row.key == Key(A1) then apostle = row end end
	eq(apostle.share, 2.5)
	eq(w:As(c.a1, c.a1.Count.StateOf, Id("Church Kid", "Mira Wells")), "credited")
	-- This ranking's: Mira's 10, no Church share (only a member who passed the player on gets one).
	eq(Score(w, c.a1, "Mira Wells"), 10)
	eq(Row(w, c.a1, "Aldric Vane"), nil)
	eq(w:As(c.a1, c.a1.RR.Led).r[Id("Church Kid", "Mira Wells")] ~= nil, true)
end)

test("1.5.9 recruiting ranking: every member's Ranking page: the rows, his own place past the top 25, what is pending, short lines", function()
	local w = World.New({ apostles = { A1 } })
	local c = { a1 = w:Client(A1, { view = true }), pia = w:Client("Pia Plain", { view = true }) }
	for _, cl in pairs(c) do Loud(cl) end
	w:Run(3600)
	w:Presence()
	local K = c.a1
	-- Thirty members with two recruits each; Pia with one, and one only her own addon saw.
	local function Give(recruit, by, confirmed)
		w:As(K, K.RR.MergeIn, Id(recruit, by), { n = recruit, bn = by, g = World.GUILD, tc = w.clock - 7200, tj = w.clock - 3600,
			ws = confirmed and { "wes brook" } or nil, s = (not confirmed) and 1 or nil }, false)
	end
	for i = 1, 30 do
		local by = "Inviter " .. string.char(96 + math.floor((i - 1) / 26) + 1, 96 + (i - 1) % 26 + 1)
		Give("Kid " .. string.char(96 + math.floor((i - 1) / 26) + 1, 96 + (i - 1) % 26 + 1, 97), by, true)
		Give("Kid " .. string.char(96 + math.floor((i - 1) / 26) + 1, 96 + (i - 1) % 26 + 1, 98), by, true)
	end
	Give("Pia Kid", "Pia Plain", true)
	Give("Pia Wait", "Pia Plain", false)
	local P = c.pia
	eq(table.concat(w:As(P, P.View.Pages), ","), "invites,ranking,people", "every member has the Ranking page")
	P.View.page = "ranking"
	local lines = w:As(P, P.View.Build)
	eq(P.View.list, "e", "a member outside the Church's audience: the ranking for everyone")
	eq(#lines[2].filters, 1, "no Who filter for him: one list")
	eq(#w:Sent(P, "NE", "WHISPER", "a"), 1, "his page asks a keeper online")
	w:Flush()
	lines = w:As(P, P.View.Build)
	local rows, mine, dots, standing, pending = 0, nil, false, nil, nil
	for _, line in ipairs(lines) do
		if line.cols then
			rows = rows + 1
			if line.key == Key("Pia Plain") then mine = line end
		end
		if line.text == "|cff9d9d9d...|r" then dots = true end
		if line.text and line.text:find(L.CHURCH_EVERYONE_YOU:format(31, 31, "10"), 1, true) then standing = line end
		if line.text and line.text:find(L.CHURCH_EVERYONE_PENDING:format(1), 1, true) then pending = line end
	end
	eq(rows, 26, "the top 25 and his own")
	assert(mine and mine.cols[1]:find("31.  Pia Plain", 1, true), "his own row, in gold")
	eq(mine.cols[2], "10"); eq(mine.cols[3], L.CHURCH_SPLIT:format("10", "0")); eq(mine.cols[4], L.CHURCH_RECRUITS:format(1, 0))
	assert(dots, "a gap before his row")
	assert(standing, "his place: 31st of 31")
	assert(pending, "the one only his addon saw")
	-- Every line of the page is short (the rows don't wrap), in English and in the other languages.
	for _, line in ipairs(lines) do
		if line.text then assert(Letters(line.text) <= 60 or line.id, Plain(line.text)) end
	end
	local keys = { CHURCH_EVERYONE_POINTS = { 10, 5, 7 }, CHURCH_EVERYONE_SHARE = { 25 }, CHURCH_EVERYONE_YOU = { 999, 9999, "99.25" },
		CHURCH_EVERYONE_YOU_NONE = {}, CHURCH_EVERYONE_PENDING = { 99 }, CHURCH_RANKING_E = {}, CHURCH_LIST_EVERYONE = {} }
	local function Each(code, fn)
		local saved = GetLocale
		GetLocale = function() return code end
		local lns = { L = setmetatable({}, { __index = L }) }
		lns.Locale = function(_, t) for k, v in pairs(t) do if type(v) == "string" then lns.L[k] = v end end end
		local ok, err = pcall(function()
			if code == "ptBR" then assert(loadfile(ROOT .. "Olympus/Locales/ChurchText.lua"))("Olympus", lns)
			else assert(loadfile(ROOT .. "Olympus/Locales/" .. code .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		fn(lns.L)
	end
	for _, code in ipairs({ "ptBR", "deDE", "esES", "frFR", "itIT", "ruRU" }) do
		Each(code, function(T)
			for key, args in pairs(keys) do
				assert(rawget(T, key), code .. " translates " .. key)
				local text = T[key]:format(unpack(args))
				assert(Letters(text) <= 55, code .. " " .. key .. ": " .. text)
				if code == "ruRU" then assert(not text:find("\226\128\148", 1, true), "no em dash in ruRU") end
			end
		end)
	end
	-- The keeper's own page shows his own ledger, with the Everyone list beside the Church's.
	K.View.page, K.View.list = "ranking", "e"
	lines = w:As(K, K.View.Build)
	local options = {}
	for _, o in ipairs(lines[2].filters[1].options) do options[#options + 1] = o.text end
	assert(table.concat(options, ","):find(L.CHURCH_LIST_EVERYONE, 1, true))
end)

test("1.5.9 recruiting ranking: the King's client reads and reports nothing and asks only while his page shows it; a member the moderators took off is not heard", function()
	local w = World.New({ apostles = { A1 } })
	local c = { a1 = w:Client(A1), king = w:Client(World.KING, { view = true }), wes = w:Client("Wes Brook") }
	for _, cl in pairs(c) do Loud(cl) end
	w:Run(3600)
	w:Presence()
	Recruit(w, World.GUILD, "Ivo Plain", "New Guy", 0)
	local K = c.king
	eq(w:As(K, K.RR.ReadWanted), nil, "no background ledger work on the King's client")
	eq(select(2, w:As(K, K.Count.Read)), "king")
	w:Tick({ K })
	eq(#w:Sent(K, "NE"), 0)
	-- His Ranking page asks only while it shows (ChurchView.PollRanking), as the Church's pages do.
	K.View.page, K.View.list, K.View.window = "ranking", "e", "m"
	local page, shown = "church/", false
	K.c.UI.IsShown = function() return shown end
	K.c.UI.PageId = function() return page end
	w:Tick({ K })
	eq(#w:Sent(K, "NE", "WHISPER", "a"), 0, "the window closed: no ask")
	shown = true
	w:Tick({ K })
	eq(#w:Sent(K, "NE", "WHISPER", "a"), 1, "his page shows it: one ask")
	w:Flush()
	w:Run(K.RR.ASK_GAP + 1)
	w:Tick({ K })
	eq(#w:Sent(K, "NE", "WHISPER", "a"), 1, "a complete answer is asked again only after RANK_REFRESH")
	-- A member the moderators took off: his report is refused, and his own client sends none.
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	w.off[Key("Wes Brook")] = { off = true }
	eq(select(2, w:As(c.a1, c.a1.RR.TakeEvidence, "Wes Brook-Realm",
		("NE~1~w~Ivo Plain~New Guy~%s~%s~%s~-"):format(World.GUILD, B(hour), B(hour)))), "netoff")
	w:ReadLog(c.wes)
	eq(#w:Sent(c.wes, "NE"), 0)
	eq(w:As(c.a1, c.a1.RR.StateOf, Id("New Guy", "Ivo Plain")), nil)
end)

test("1.5.9 recruiting ranking: the wire: every word fits a whisper at its longest and reads back; a malformed one is refused", function()
	local w, c = Cast()
	local K = c.a1
	local long = "Abcdefghijklmn Opqrstuvwxyzabcd" -- 30 letters and a space
	local guild = "Olympus " .. ("G"):rep(40)
	local rec = { n = long:sub(1, 30), bn = "Zyxwvutsrqponm Lkjihgfedcbazy", g = guild, tc = w.clock - 7200, tj = w.clock - 3600,
		s = 1, ws = { "abcdefghijklmn opqrstuvwxyzab", "bcdefghijklmn opqrstuvwxyzabc" }, src = "Mnopqrstuvwxyz Abcdefghijklmn", y = 1, u = w.clock }
	local line = w:As(K, K.RR.RecordLine, Id(rec.n, rec.bn), rec)
	assert(#line <= 255, #line .. " " .. line)
	local id, back = w:As(K, K.RR.ParseRecord, line)
	eq(id, Id(rec.n, rec.bn))
	eq(back.src, rec.src); eq(back.y, 1); eq(back.s, 1); eq(#back.ws, 2); eq(back.g, guild)
	assert(#("NE~1~d~zzzzzzzz~120~" .. line:sub(6)) <= 255, "as a catch-up row")
	local B = ns.Codec.Base36
	local hour = math.floor(w.clock / 3600)
	local text = ("NE~1~w~%s~%s~%s~%s~%s~%s"):format(rec.bn, rec.n, guild, B(hour), B(hour), rec.src)
	assert(#text <= 255, #text)
	for _, bad in ipairs({ "NE~1~w~Ivo Plain~New Guy~" .. World.GUILD .. "~zz~zz", "NE~1~w~Ivo Plain~Ivo Plain~" .. World.GUILD .. "~" .. B(hour) .. "~" .. B(hour) .. "~-",
		"NE~1~w~Ivo Plain~New Guy~Horde Rivals~" .. B(hour) .. "~" .. B(hour) .. "~-", "NE~1~w~Ivo Plain~New Guy~" .. World.GUILD .. "~" .. B(hour) .. "~" .. B(hour + 5) .. "~-" }) do
		local ok, why = w:As(K, K.RR.TakeEvidence, "Wes Brook-Realm", bad)
		eq(ok, false, bad)
		assert(why == "shape" or why == "self" or why == "guild" or why == "times", tostring(why))
	end
	-- Not a keeper: a plain member's client takes no evidence; a line from a plain member is no keeper's.
	eq(select(2, w:As(c.wes, c.wes.RR.TakeEvidence, "Ivo Plain-Realm", text)), "not keeper")
	eq(select(2, w:As(K, K.RR.TakeLine, "Wes Brook-Realm", line)), "keeper")
	-- Saved data: a record that does not read back goes alone at load, the count made again.
	local l = w:As(K, K.RR.Led)
	l.r["bad:record"] = { n = "Bad", bn = "Record", tc = "x" }
	l.r[Id(rec.n, rec.bn)] = rec
	l.n = 99
	w:As(K, K.RR.CheckSaved)
	eq(l.r["bad:record"], nil)
	eq(l.n, 1)
end)

-- The README and the CurseForge page tell of it in the same words, and its privacy rows say what goes where.
test("1.5.9 recruiting ranking: the README and the CurseForge page tell of the ranking for everyone; the privacy table names its words", function()
	local function Read(p) local f = assert(io.open(ROOT .. p)) local s = f:read("*a") f:close() return s end
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local doc = Read(path):gsub("%s+", " ")
		for _, phrase in ipairs({ "**The recruiting ranking for everyone (1.5.9).**", "25% of those points", "**Everyone**",
			"| The recruiting ranking for everyone (1.5.9): what your addon read in your guild's log",
			"| The recruiting ranking for everyone: its numbers" }) do
			assert(doc:find(phrase, 1, true), path .. ": " .. phrase)
		end
	end
end)
