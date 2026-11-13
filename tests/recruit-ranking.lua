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
	-- (Changed on purpose, review of 1.5.9: the inviter's own addon reports every join of his, not only a
	-- player another member passed him. The author's "O ranking para todo mundo" page tells each member how
	-- many of his recruits wait for another addon; his own word is that count. It confirms nothing and
	-- makes no record.)
	eq(#w:Sent(c.ivo, "NE", "WHISPER", "w"), 2, "the inviter's own report, to each keeper online")
	eq(State(w, c.a1, "New Guy", "Ivo Plain"), nil, "his word alone makes no record")
	eq(Row(w, c.a1, "Ivo Plain").pending, 1)
	eq(Score(w, c.a1, "Ivo Plain"), 0)
	eq(w:ReadLog(c.wes), true)
	eq(#w:Sent(c.wes, "NE", "WHISPER", "w"), 2, "a guildmate's read: to each keeper heard online")
	-- (Changed on purpose, review of 1.5.9: a guildmate's word is strong only for an invite the keeper's
	-- own read of the log saw; a guildmate's word alone named any inviter. Points only for a player really
	-- invited who joined, the author's "Se a pessoa for convidada e aceitar entrar na guilda". Aldric has
	-- not read his log here, so Wes's word is weak: it confirms the recruit beside Ivo's own report.)
	eq(State(w, c.a1, "New Guy", "Ivo Plain"), "credited", "his guild's keeper vouches for his guildmate who saw the join, beside the inviter's own word")
	eq(Rec(w, c.a1, "New Guy", "Ivo Plain").wk[1], Key("Wes Brook"))
	eq(Rec(w, c.a1, "New Guy", "Ivo Plain").s, 1)
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
	-- (Review of 1.5.9: Sid's own addon says so too, to the keepers, once Ivo took the name: RecruitHandoff's
	-- "A". The inviter's report alone no longer names a source.)
	eq(w:Act(c.sid, c.sid.RR.HandedOut, "New Guy-Realm", "Ivo Plain-Realm"), true)
	eq(#w:Sent(c.sid, "NE", "WHISPER", "h"), 2)
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
	-- (Changed on purpose, review of 1.5.9: the inviter's own report is kept apart from the ledger, so
	-- anyone's whispered "own reports" never fill it: no record yet, only his pending recruit. Nothing
	-- counts before the join is confirmed, the author's "Se a pessoa for convidada e aceitar entrar na guilda".)
	eq(State(w, c.a1, "New Guy", "Ivo Plain"), nil, "only the inviter's word: no record")
	eq(Score(w, c.a1, "Ivo Plain"), 0, "no points before another addon confirms the join")
	eq(Row(w, c.a1, "Ivo Plain").pending, 1)
	eq(Score(w, c.a1, "Sid Pass"), 0, "nor for the member who passed him")
	-- A guildmate's read confirms it: the inviter's 10, and 25% of them for the one who passed the player.
	w:ReadLog(c.wes)
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(State(w, k, "New Guy", "Ivo Plain"), "credited", k.name)
		eq(Rec(w, k, "New Guy", "Ivo Plain").src, "Sid Pass", k.name)
		eq(Rec(w, k, "New Guy", "Ivo Plain").s, 1, k.name)
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
	-- (Review of 1.5.9: Sid's own word on each, as RecruitHandoff gives it once Ivo took the name.)
	w:Act(c.sid, c.sid.RR.HandedOut, "Stays Long-Realm", "Ivo Plain-Realm")
	w:Act(c.sid, c.sid.RR.HandedOut, "Leaves Soon-Realm", "Ivo Plain-Realm")
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

test("1.5.9 recruiting ranking: who passed the player on counts only as the inviter's own report and his own word name him, and never as the inviter's own alt or the recruit", function()
	local w, c = Cast()
	w.alts[Key("Ivo Plain")] = { "Ivo Twink-Realm" }
	w:As(c.ivo, c.ivo.RR.HandedIn, "Alt Pal-Realm", "Ivo Twink-Realm")
	eq(w:As(c.ivo, c.ivo.RR.HandedIn, "Same Guy-Realm", "Same Guy-Realm"), false, "nobody passes himself on")
	-- (Review of 1.5.9: the passer's own word, needed now, is refused from the inviter's own alt.)
	eq(select(2, w:As(c.a1, c.a1.RR.TakeEvidence, "Ivo Twink-Realm", "NE~1~h~Alt Pal~Ivo Plain")), "self")
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
	-- (Changed on purpose, review of 1.5.9: Aldric's own log never showed this invite, so Wes's word is weak:
	-- the author's "Se a pessoa for convidada e aceitar entrar na guilda" needs the inviter's own word too.)
	eq(Rec(w, c.a1, "Other Pal", "Ivo Plain").wk[1], Key("Wes Brook"))
end)

test("1.5.9 recruiting ranking: one recruit counts once: invited again elsewhere after leaving, back in his old guild, an alt of the inviter", function()
	local w, c = Cast()
	-- Roamer joins Olympus Ember through Ivo, confirmed; he leaves and Vik invites him into Olympus Vale,
	-- where Bera (a keeper) reads it herself.
	Recruit(w, World.GUILD, "Ivo Plain", "Roamer", 1)
	-- (Review of 1.5.9: Ivo's own addon reads too; a guildmate's word whose invite Aldric's log did not see
	-- confirms only beside the inviter's own report.)
	w:ReadLog(c.ivo)
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
	w:ReadLog(c.ivo)
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
	-- (Review of 1.5.9: Sid's own word too, to the keeper online.)
	w:Act(c.sid, c.sid.RR.HandedOut, "Rec Aa-Realm", "Ivo Plain-Realm")
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
	-- (Review of 1.5.9: Ivo's own addon reads too; Aldric's log did not see this invite, so Wes's word
	-- confirms it beside Ivo's own report.)
	w:ReadLog(c.ivo)
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
	w:ReadLog(c.ivo)
	w:ReadLog(c.wes)
	eq(SentTo(w, c.wes, "Cato Old", "w"), 2)
	eq(Outbox(c.wes), 1)
	for _ = 1, 3 do
		w:Run(c.wes.RR.RESEND_GAP + 1)
		w:Presence()
		w:Tick({ c.wes, c.ivo })
	end
	eq(SentTo(w, c.wes, "Cato Old", "w"), 2, "once to a keeper not heard to take these")
	-- Aldric back: the report reaches him, his receipt empties the outbox.
	c.a1.online = true
	w:Presence()
	w:Tick({ c.wes, c.ivo })
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
	-- (Review of 1.5.9: this compared Aldric's number with itself. The guild master's client keeps the
	-- real draw too: the same number there.)
	eq(c.gm.RR.score("pair1:ivo plain", "Member aa"), c.a1.RR.score("pair1:ivo plain", "Member aa"), "the same number on every client")
	assert(c.gm.RR.score("pair1:ivo plain", "Member aa") ~= c.gm.RR.score("pair2:ivo plain", "Member aa"), "a number of the pair too")
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

test("1.5.9 recruiting ranking: every member's Ranking page: the rows, his own place past the top 10, what is pending, short lines", function()
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
	-- (Changed on purpose, review of 1.5.9: the top 10, not 25. "O ranking para todo mundo": every member's
	-- page asks a keeper, and 27 whispers an answer were about 32 seconds of a keeper's sending.)
	eq(rows, 11, "the top 10 and his own")
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
				-- (Review of 1.5.9: ChurchText.lua writes the English line into the same table before its pt-BR
				-- one, so for pt-BR the line must differ from the English.)
				assert(rawget(T, key) and (code ~= "ptBR" or T[key] ~= L[key]), code .. " translates " .. key)
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

-- Review of 1.5.9: the words the keepers weigh, the members' asks, who passed a player on.
local B36 = ns.Codec.Base36
-- A log pair as a report says it (hours).
local function W(inviter, recruit, guild, ti, tj, src)
	return ("NE~1~w~%s~%s~%s~%s~%s~%s"):format(inviter, recruit, guild, B36(ti), B36(tj), src or "-")
end
-- Two letters for the i-th made-up name: aa, ab, ... (names are letters only).
local function Two(i) return string.char(96 + math.floor((i - 1) / 26) + 1, 96 + (i - 1) % 26 + 1) end
local function Hour(w) return math.floor(w.clock / 3600) end
local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-- Review of 1.5.9 (P1-1): one officer as the census names him in a guild with no keeper (two characters
-- make one), or a guild's correspondent, made up confirmed recruits for any name, and every member's page
-- ranked a name nobody has first. Such a witness's word is weak now: it confirms a recruit only beside the
-- inviter's own report, and WEAK_DAY recruits of one join day at most.
test("1.5.9 recruiting ranking: an officer the census names confirms nothing alone: a made-up inviter never ranks; beside the inviter's own report it counts, WEAK_DAY a join day per witness", function()
	local w = World.New({ apostles = { A1 } })
	local c = { a1 = w:Client(A1, { view = true }), pia = w:Client("Pia Plain", { view = true }),
		ola = w:Client("Ola Officer", { guild = World.GUILD2, rank = 1 }), gus = w:Client("Gus Vale", { guild = World.GUILD2 }) }
	for _, cl in pairs(c) do Loud(cl) end
	w:Run(3600)
	w:Presence()
	-- Ola is Olympus Vale's officer as the census reads it (what Channels.VerifiedLevel gives for her there).
	c.a1.c.Channels.VerifiedLevel = function(n, g)
		if Key(n) == Key("Ola Officer") and g == World.GUILD2 then return 2, true, 1 end
		return 1, false
	end
	local hour, taken = Hour(w), 0
	for i = 1, 30 do
		if w:As(c.a1, c.a1.RR.TakeEvidence, "Ola Officer-Realm", W("Nobody Real", "Ghost " .. Two(i), World.GUILD2, hour - 1, hour)) then taken = taken + 1 end
	end
	eq(taken, 30, "her words are taken, as weak ones")
	eq(State(w, c.a1, "Ghost aa", "Nobody Real"), "pending")
	eq(Row(w, c.a1, "Nobody Real", "w"), nil, "no point for a name no addon of its own stands behind")
	-- A plain member's page: no such row.
	c.pia.View.page = "ranking"
	w:As(c.pia, c.pia.View.Build)
	w:Flush()
	for _, line in ipairs(w:As(c.pia, c.pia.View.Build)) do
		if line.cols then assert(not Plain(line.cols[1]):find("Nobody", 1, true), Plain(line.cols[1])) end
	end
	-- A real invite there: Gus's own addon reports it (kept apart: pending for him), Ola's word confirms it.
	w:Run(3600)
	w:Presence()
	hour = Hour(w)
	w:LogEvent(World.GUILD2, "invite", "Gus Vale", "Vale Kid", 0)
	w:LogEvent(World.GUILD2, "join", "Vale Kid", nil, 0)
	w:ReadLog(c.gus)
	eq(#w:Sent(c.gus, "NE", "WHISPER", "w"), 1, "his own report, to the keeper online")
	eq(State(w, c.a1, "Vale Kid", "Gus Vale"), nil, "the inviter's word alone makes no record")
	eq(Row(w, c.a1, "Gus Vale").pending, 1)
	eq(Score(w, c.a1, "Gus Vale"), 0)
	eq(w:As(c.a1, c.a1.RR.TakeEvidence, "Ola Officer-Realm", W("Gus Vale", "Vale Kid", World.GUILD2, hour, hour)), true)
	eq(State(w, c.a1, "Vale Kid", "Gus Vale"), "credited", "her word beside his own")
	eq(Score(w, c.a1, "Gus Vale"), 10)
	eq(Row(w, c.a1, "Gus Vale").pending, 0)
	-- One weak witness confirms WEAK_DAY recruits a join day; the rest of hers that day wait.
	c.a1.RR.WEAK_DAY = 3
	for i = 1, 5 do
		local kid = "Guskid " .. Two(i)
		w:As(c.a1, c.a1.RR.TakeEvidence, "Gus Vale-Realm", W("Gus Vale", kid, World.GUILD2, hour, hour))
		w:As(c.a1, c.a1.RR.TakeEvidence, "Ola Officer-Realm", W("Gus Vale", kid, World.GUILD2, hour, hour))
	end
	local gus = Row(w, c.a1, "Gus Vale")
	eq(gus.joins, 3, "three of her six that day")
	eq(gus.pending, 3)
	eq(Row(w, c.a1, "Nobody Real", "w"), nil)
end)

-- Review of 1.5.9 (P1-2): a plain member of a keeper's guild named another inviter for a recruit the
-- keeper's roster showed, an hour earlier, and took him from his real inviter. A guildmate's word is strong
-- only for an invite the keeper's own read of the log saw; a weak claim never displaces a strong one.
test("1.5.9 recruiting ranking: a guildmate's word naming another inviter, dated earlier, takes no recruit from the one the keeper's own log saw invite him", function()
	local w, c = Cast({ thief = { name = "Thief Pal" } })
	Recruit(w, World.GUILD, "Ivo Plain", "Real Kid", 1)
	w:ReadLog(c.a1)
	w:ReadLog(c.wes)
	eq(State(w, c.a1, "Real Kid", "Ivo Plain"), "credited")
	eq(Rec(w, c.a1, "Real Kid", "Ivo Plain").ws[1], Key(A1), "the keeper's own read")
	local hour = Hour(w) - 1
	-- Sid whispers an invite by Thief Pal five hours before Ivo's, and Thief Pal's own addon backs it.
	eq(w:As(c.a1, c.a1.RR.TakeEvidence, "Sid Pass-Realm", W("Thief Pal", "Real Kid", World.GUILD, hour - 5, hour)), true)
	eq(w:As(c.a1, c.a1.RR.TakeEvidence, "Thief Pal-Realm", W("Thief Pal", "Real Kid", World.GUILD, hour - 5, hour)), true)
	w:Flush()
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(State(w, k, "Real Kid", "Ivo Plain"), "credited", k.name)
		eq(Score(w, k, "Ivo Plain"), 10, k.name)
		eq(Score(w, k, "Thief Pal"), 0, k.name)
	end
	eq(State(w, c.a1, "Real Kid", "Thief Pal"), "taken")
	eq(Rec(w, c.a1, "Real Kid", "Thief Pal").wk[1], Key("Sid Pass"), "a weak word: the keeper's log never showed that invite")
	-- A guildmate's word for the invite the keeper's log did see is strong.
	eq(Rec(w, c.a1, "Real Kid", "Ivo Plain").ws[2], Key("Wes Brook"))
end)

-- Review of 1.5.9 (P1-3): any player's asks took most of a keeper's sending, and they filled the Church's
-- own line queue: its answer to the Church's audience came back "busy".
test("1.5.9 recruiting ranking: members' answers wait on the ranking's own queue: the Church's answer to its audience is never refused busy, and the Church's lines go first", function()
	local w = World.New({ apostles = { A1 } })
	local c = { a1 = w:Client(A1), mira = w:Client("Mira Wells") }
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	local members = {}
	for i = 1, 9 do members[i] = w:Client("Member " .. Two(i)) end
	for _, cl in pairs(c) do Loud(cl) end
	for _, cl in ipairs(members) do Loud(cl) end
	w:Run(8 * 3600)
	w:Presence()
	for i = 1, 12 do
		local by = "Inviter " .. Two(i)
		w:As(c.a1, c.a1.RR.MergeIn, Id("Kid " .. Two(i), by), { n = "Kid " .. Two(i), bn = by, g = World.GUILD, tc = w.clock - 7200,
			tj = w.clock - 3600, ws = { "wes brook" } }, false)
	end
	c.a1.RR.Settled = function() return true end
	-- Comm's queue is full (the keeper's whispers drain at the game's pace): nothing goes for now.
	w.room = c.a1.RR.SEND_ROOM
	for _, m in ipairs(members) do w:As(m, m.RR.Ask, "m") end
	w:Flush()
	-- The Church's own answer to its audience still takes a slot of its own queue.
	local ok, why = w:As(c.a1, c.a1.Count.Answer, "Mira Wells-Realm", "a", "m")
	eq(ok, true, tostring(why))
	eq(c.a1.Count.Stats().dropped.busy, nil, "the Church's answer is never refused busy")
	eq(w:As(c.a1, c.a1.RR.Queued), c.a1.RR.QUEUE_ASKS, "three answers wait, on the ranking's own queue")
	eq(w:As(c.a1, c.a1.RR.Stats).dropped.busy, #members - c.a1.RR.QUEUE_ASKS, "the others' asks are dropped: their pages ask again")
	-- Room for the Church's lines, none past them for the ranking's: the Church's go first.
	w.room = c.a1.RR.SEND_ROOM + 5
	w:Run(4)
	assert(#w:Sent(c.a1, "NR", "WHISPER") > 0, "the Church's answer went")
	eq(#w:Sent(c.a1, "NE", "WHISPER", "o"), 0, "nothing of the ranking's while the Church needs the room")
	-- Room again: the ranking's answers go.
	w.room = nil
	w:Run(4)
	eq(w:As(c.a1, c.a1.RR.Queued), 0)
	eq(#w:Sent(c.a1, "NE", "WHISPER", "n"), c.a1.RR.QUEUE_ASKS)
end)

test("1.5.9 recruiting ranking: a keeper answers an ask naming its asker's Olympus guild, the top 10 and his own row, two an asker and eight in all in 5 minutes; an ask naming none, or a guild its asker is known outside, gets nothing", function()
	local w = World.New({ apostles = { A1 } })
	local c = { a1 = w:Client(A1), mira = w:Client("Mira Wells"), out = w:Client("Out Sider", { guild = "Random Guild" }),
		vik = w:Client("Vik Stone", { guild = World.GUILD2 }) }
	for _, cl in pairs(c) do Loud(cl) end
	w:Run(3600)
	w:Presence()
	for i = 1, 14 do
		local by = "Inviter " .. Two(i)
		for j = 1, 15 - i do
			local kid = "Kid " .. Two(i) .. Two(j)
			w:As(c.a1, c.a1.RR.MergeIn, Id(kid, by), { n = kid, bn = by, g = World.GUILD, tc = w.clock - 7200, tj = w.clock - 3600,
				ws = { "wes brook" } }, false)
		end
	end
	w:As(c.a1, c.a1.RR.MergeIn, Id("Vik Kid", "Vik Stone"), { n = "Vik Kid", bn = "Vik Stone", g = World.GUILD2, tc = w.clock - 7200,
		tj = w.clock - 3600, ws = { "wes brook" } }, false)
	c.a1.RR.Settled = function() return true end
	local function To(name)
		local n = 0
		for _, e in ipairs(w:Sent(c.a1, "NE", "WHISPER")) do if Key(e.target) == Key(name) then n = n + 1 end end
		return n
	end
	-- An ask of the old shape, one naming a guild outside Olympus: nothing.
	w:Queue(c.out, "WHISPER", "NE~1~a~abc~m", A1)
	w:Queue(c.out, "WHISPER", "NE~1~a~abd~m~Random Guild", A1)
	-- One the keeper knows in Olympus Vale (his own Olympus words named it) naming Olympus Ember; a roster
	-- mate of the keeper naming another guild: nothing.
	c.a1.c.Data = setmetatable({ ClaimedGuild = function(n) if Key(n) == Key("Vik Stone") then return World.GUILD2 end end }, { __index = c.a1.c.Data })
	w:Queue(c.vik, "WHISPER", "NE~1~a~abe~m~" .. World.GUILD, A1)
	w:Queue(c.mira, "WHISPER", "NE~1~a~abf~m~" .. World.GUILD2, A1)
	w:Flush()
	eq(To("Out Sider"), 0); eq(To("Vik Stone"), 0); eq(To("Mira Wells"), 0)
	eq(w:As(c.a1, c.a1.RR.Stats).dropped.member, 3)
	-- Vik's own page asks (his own guild): the top 10 and his own row, then the end.
	eq(w:As(c.vik, c.vik.RR.Ask, "m"), true)
	w:Flush()
	eq(To("Vik Stone"), c.a1.RR.RANK_ROWS + 2, "ten rows, his own, the end")
	local rows, _, remote, _, _, mine = w:As(c.vik, c.vik.RR.RankingView, "m")
	eq(#rows, 11); eq(remote, true); eq(mine.rank, 15); eq(mine.score, 10)
	-- Two answers an asker in 5 minutes: his third window waits.
	w:As(c.vik, c.vik.RR.Ask, "a"); w:As(c.vik, c.vik.RR.Ask, "w")
	w:Flush()
	eq(w:As(c.a1, c.a1.RR.Stats).dropped["ask rate"], 1)
	-- Eight answers in all in 5 minutes, whoever asks.
	local others = {}
	for i = 1, 8 do others[i] = w:Client("Asker " .. Two(i)); Loud(others[i]) end
	w:Presence()
	for _, o in ipairs(others) do w:As(o, o.RR.Ask, "m") end
	w:Flush()
	eq(w:As(c.a1, c.a1.RR.Stats).answers, c.a1.RR.ANSWERS_ALL)
	eq(w:As(c.a1, c.a1.RR.Stats).dropped.busy, 2, "Vik's two and six of theirs; the last two wait for the window")
	-- Past the window, an asker's page asks again (a keeper that stayed silent: the next one, here the same).
	w:Run(c.a1.RR.ANSWER_WINDOW + 1)
	eq(w:As(others[8], others[8].RR.Ask, "m"), true)
	w:Flush()
	eq(w:As(c.a1, c.a1.RR.Stats).answers, c.a1.RR.ANSWERS_ALL + 1)
end)

test("1.5.9 recruiting ranking: members' asks spread over the keepers heard serving, each member's own start", function()
	local w = World.New({ apostles = { A1, A2 } })
	local c = { a1 = w:Client(A1), a2 = w:Client(A2) }
	local members = {}
	for i = 1, 20 do members[i] = w:Client("Member " .. Two(i)) end
	for _, cl in pairs(c) do Loud(cl) end
	for _, cl in ipairs(members) do Loud(cl) end
	w:Run(3600)
	w:Presence()
	for _, m in ipairs(members) do
		-- Both keepers were heard to take these (any NE word of theirs: a receipt here).
		w:As(m, m.RR.Receive, "WHISPER", A1, "NE~1~k~zz")
		w:As(m, m.RR.Receive, "WHISPER", A2, "NE~1~k~zz")
		w:As(m, m.RR.Ask, "m")
	end
	local first, second = 0, 0
	for _, e in ipairs(w:Sent(nil, "NE", "WHISPER", "a")) do
		if Key(e.target) == Key(A1) then first = first + 1 elseif Key(e.target) == Key(A2) then second = second + 1 end
	end
	eq(first + second, 20)
	assert(first >= 4 and second >= 4, ("spread: %d and %d"):format(first, second))
end)

-- Review of 1.5.9 (P1-4): the inviter's own report alone named who passed him the player (an unlinked alt
-- or a friend took 25% of his recruits), and anyone's own reports were ledger records.
test("1.5.9 recruiting ranking: who passed the player on counts only when his own addon said so too; an inviter's own report alone makes no record", function()
	local w, c = Cast()
	w:Run(600)
	w:Presence()
	local hour = Hour(w)
	Recruit(w, World.GUILD, "Ivo Plain", "Real Kid", 0)
	-- Ivo's own report names "Ivo Secondchar", a character nobody links to him, as the one who passed him the player.
	eq(w:As(c.a1, c.a1.RR.TakeEvidence, "Ivo Plain-Realm", W("Ivo Plain", "Real Kid", World.GUILD, hour, hour, "Ivo Secondchar")), true)
	eq(w:As(c.a1, c.a1.RR.Led).n, 0, "kept apart from the ledger")
	w:ReadLog(c.a1)
	eq(State(w, c.a1, "Real Kid", "Ivo Plain"), "credited")
	eq(Rec(w, c.a1, "Real Kid", "Ivo Plain").s, 1, "his own word marks the record a witness made")
	eq(Rec(w, c.a1, "Real Kid", "Ivo Plain").src, nil, "nobody's own word says he passed it")
	eq(Row(w, c.a1, "Ivo Secondchar"), nil)
	-- Sid passed Ivo the next one, and his addon said so when Ivo took the name (RecruitHandoff's "A").
	w:As(c.ivo, c.ivo.RR.HandedIn, "Kid Two-Realm", "Sid Pass-Realm")
	eq(w:Act(c.sid, c.sid.RR.HandedOut, "Kid Two-Realm", "Ivo Plain-Realm"), true)
	eq(#w:Sent(c.sid, "NE", "WHISPER", "h"), 2, "his word, to each keeper online")
	w:Run(600)
	w:Presence()
	Recruit(w, World.GUILD, "Ivo Plain", "Kid Two", 0)
	w:ReadLog(c.ivo)
	w:ReadLog(c.a1)
	for _, k in ipairs({ c.a1, c.a2 }) do
		eq(State(w, k, "Kid Two", "Ivo Plain"), "credited", k.name)
		eq(Rec(w, k, "Kid Two", "Ivo Plain").src, "Sid Pass", k.name)
		eq(Score(w, k, "Sid Pass"), 2.5, k.name)
	end
	-- Sid's word alone, for a player Ivo's report names nobody for: nothing for him.
	w:Act(c.sid, c.sid.RR.HandedOut, "Kid Three-Realm", "Ivo Plain-Realm")
	w:Run(600)
	w:Presence()
	Recruit(w, World.GUILD, "Ivo Plain", "Kid Three", 0)
	w:ReadLog(c.ivo)
	w:ReadLog(c.a1)
	eq(State(w, c.a1, "Kid Three", "Ivo Plain"), "credited")
	eq(Rec(w, c.a1, "Kid Three", "Ivo Plain").src, nil)
	eq(Score(w, c.a1, "Sid Pass"), 2.5)
	-- Nobody passes a player to himself, nor his own alt.
	w.alts[Key("Ivo Plain")] = { "Ivo Twink-Realm" }
	eq(select(2, w:As(c.a1, c.a1.RR.TakeEvidence, "Ivo Twink-Realm", "NE~1~h~Kid Four~Ivo Plain")), "self")
	-- Own reports of made-up recruits, from a player of another guild: never a record; the side table bounded.
	local before = w:As(c.a1, c.a1.RR.Led).n
	c.a1.RR.OWN_MAX = 20
	for i = 1, 40 do w:As(c.a1, c.a1.RR.TakeEvidence, "Fake Guy-Realm", W("Fake Guy", "Madeup " .. Two(i), World.GUILD2, Hour(w), Hour(w))) end
	eq(w:As(c.a1, c.a1.RR.Led).n, before, "no record")
	assert(Count(w:As(c.a1, c.a1.RR.Led).own) <= 20)
	eq(w:As(c.a1, c.a1.RR.Stats).dropped.budget, 10, "the smaller budget: 30 an hour")
	eq(Score(w, c.a1, "Fake Guy"), 0)
end)

-- Review of 1.5.9 (P2-2): the inviter's own client reported only a player another member passed him, so
-- the page's "N of yours wait for another addon" never showed for his own invites.
test("1.5.9 recruiting ranking: every join the inviter's own addon saw waits as his pending recruit; his addon reads its log a while after an invite command", function()
	local w, c = Cast({ pia = { name = "Pia Plain", view = true } })
	Recruit(w, World.GUILD, "Pia Plain", "Solo Kid", 0)
	w:ReadLog(c.pia)
	eq(#w:Sent(c.pia, "NE", "WHISPER", "w"), 2, "her own report, to each keeper online")
	eq(Row(w, c.a1, "Pia Plain").pending, 1)
	eq(Score(w, c.a1, "Pia Plain"), 0)
	-- Her page says so (asked of a keeper online).
	c.pia.View.page = "ranking"
	w:As(c.pia, c.pia.View.Build)
	w:Flush()
	local found = false
	for _, line in ipairs(w:As(c.pia, c.pia.View.Build)) do
		if line.text and line.text:find(L.CHURCH_EVERYONE_PENDING:format(1), 1, true) then found = true end
	end
	assert(found, "one of hers waits for another addon")
	-- The keeper's own read confirms it.
	w:ReadLog(c.a1)
	eq(Score(w, c.a1, "Pia Plain"), 10)
	eq(Row(w, c.a1, "Pia Plain").pending, 0)
	-- An invite command taken to chat (Recruit.LastInviteAt): her client reads its log for OWN_READ_HOURS.
	eq(w:As(c.wes, c.wes.RR.ReadWanted), "drawn")
	local at = w.clock
	c.wes.c.Recruit = { LastInviteAt = function() return at end }
	eq(w:As(c.wes, c.wes.RR.ReadWanted), "own")
	w:Run(c.wes.RR.OWN_READ_HOURS * 3600 + 1)
	eq(w:As(c.wes, c.wes.RR.ReadWanted), "drawn")
end)

-- Review of 1.5.9 (the review's experiment ZZR5): a guildmate's report that reached his keeper before its
-- roster showed the recruit was refused for now with no word back, and a reporter that had never heard
-- that keeper take these sent it once, never again. The keeper says "later" (NE l): it comes again.
test("1.5.9 recruiting ranking: a report a keeper refuses for now (its roster not showing the recruit yet) comes again later and is taken", function()
	local w = World.New({ apostles = { A1 } })
	local c = { a1 = w:Client(A1), wes = w:Client("Wes Brook") }
	for _, cl in pairs(c) do Loud(cl) end
	w:Run(3600)
	w:Presence()
	-- The log shows the invite and the join; the keeper's roster has not shown the recruit yet.
	w:LogEvent(World.GUILD, "invite", "Ivo Plain", "Late Kid", 0)
	w:LogEvent(World.GUILD, "join", "Late Kid", nil, 0)
	w:ReadLog(c.wes)
	eq(w:As(c.a1, c.a1.RR.Stats).dropped.roster, 1)
	eq(State(w, c.a1, "Late Kid", "Ivo Plain"), nil)
	w:Run(c.a1.RR.RECEIPT_GAP + 1)
	eq(SentTo(w, c.a1, "Wes Brook", "l"), 1, "the keeper's later")
	eq(Outbox(c.wes), 1, "the report waits")
	-- The recruit shows on the roster; the report goes again an hour later and is taken.
	Join(w, World.GUILD, "Late Kid")
	w:Run(c.wes.RR.RESEND_GAP + 1)
	w:Presence()
	w:Tick({ c.wes })
	w:Run(c.a1.RR.RECEIPT_GAP + 1)
	eq(#w:Sent(c.wes, "NE", "WHISPER", "w"), 2)
	eq(Rec(w, c.a1, "Late Kid", "Ivo Plain").wk[1], Key("Wes Brook"))
	eq(Outbox(c.wes), 0, "its receipt")
end)

-- The README and the CurseForge page tell of it in the same words, and its privacy rows say what goes where.
test("1.5.9 recruiting ranking: the README and the CurseForge page tell of the ranking for everyone; the privacy table names its words", function()
	local function Read(p) local f = assert(io.open(ROOT .. p)) local s = f:read("*a") f:close() return s end
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local doc = Read(path):gsub("%s+", " ")
		for _, phrase in ipairs({ "**The recruiting ranking for everyone (1.5.9).**", "25% of those points", "**Everyone**",
			"| The recruiting ranking for everyone (1.5.9): what your addon read in your guild's log",
			"| The recruiting ranking for everyone: its numbers",
			-- (Review of 1.5.9: the pages said a move between Olympus guilds never counted and that a recruit's
			-- mark kept him from counting twice "never"; the keepers catch a move only where their own addon saw
			-- the player, for 120 days. And the inviter's own report, the passer's word, the top 10.)
			"a move no keeper's addon saw is not caught", "so he does not count again in that time",
			"when his addon and yours both say so", "each inviter's own report and each passer's word",
			"the top 10 and his own place", "your own invites whose player joined, always" }) do
			assert(doc:find(phrase, 1, true), path .. ": " .. phrase)
		end
	end
end)

-- 1.5.9's letter (Locales.lua and each language's file) tells the ranking with numbers: the points for a
-- recruit and for his stay, the days of that stay, the passer's quarter and the rows the page shows. Each
-- as this file's ranking counts them, in every shipped language (tests/letter-content.lua checks the rest).
local LETTER_RANKING = {
	enUS = { "earns you %d points, and %d more if he is still there %d days later", "a quarter of those points", "The page shows the top %d and your place." },
	ptBR = { "vale %d pontos para você, e mais %d se ainda estiver nela %d dias depois", "um quarto desses pontos", "A página mostra os %d primeiros e a sua posição." },
	deDE = { "bringt dir %d Punkte, und %d mehr, wenn er %d Tage später noch dabei ist", "ein Viertel dieser Punkte", "Die Seite zeigt die ersten %d und deinen Platz." },
	esES = { "te da %d puntos, y %d más si sigue en ella %d días después", "una cuarta parte de esos puntos", "La página muestra los %d primeros y tu puesto." },
	frFR = { "te rapporte %d points, et %d de plus s'il y est encore %d jours plus tard", "un quart de ces points", "La page montre les %d premiers et ta place." },
	itIT = { "ti dà %d punti, e altri %d se è ancora lì %d giorni dopo", "un quarto di quei punti", "La pagina mostra i primi %d e il tuo posto." },
	ruRU = { "приносит вам %d очков и ещё %d, если через %d дней он всё ещё в гильдии", "четверть этих очков", "На странице видны первые %d и ваше место." },
}
test("1.5.9 recruiting ranking: the 1.5.9 letter tells the points, the stay, the passer's quarter and the rows the page shows as the ranking counts them, in every language", function()
	local w = World.New({ apostles = { A1 } })
	local K = w:Client(A1)
	local Count, RR = K.c.ChurchCount, K.RR
	eq(RR.SHARE, 0.25, "a quarter, as the letter says")
	for code, say in pairs(LETTER_RANKING) do
		local saved = GetLocale
		local lns = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", lns)
			if code ~= "enUS" and code ~= "ptBR" then assert(loadfile(ROOT .. "Olympus/Locales/" .. code .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		local letter = assert(rawget(lns.L, "LETTER_1_5_9"), code)
		assert(letter:find(say[1]:format(RR.POINTS_JOIN, RR.POINTS_STAY, RR.STAY_DAYS), 1, true), code .. ": the points and the stay")
		assert(letter:find(say[2], 1, true), code .. ": the passer's quarter")
		assert(letter:find(say[3]:format(RR.RANK_ROWS), 1, true), code .. ": the rows the page shows")
		eq(RR.POINTS_JOIN, Count.POINTS_JOIN, "the Church's points"); eq(RR.STAY_DAYS, Count.STAY_DAYS, "the Church's stay")
	end
end)
