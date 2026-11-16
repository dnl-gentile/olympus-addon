-- Taking a guild's verified check away (1.6.0, a player's report of 11-15: a guild the staff
-- excommunicated still wore its check in the Census, and "addons broken" said the others). Real
-- Comm + Relay + Verify path, as tests/verify-mesh.lua: only Blizzard's wire and timers are
-- simulated. Both relays are verifiers here (two High Councillors). A client still on 1.5.9 runs
-- Verify.lua as that release ships it (tests/fixtures/verify-1.5.9.lua: `git show
-- 88b6b67f:Olympus/Verify.lua` under a three-line note). Every name is invented.
--   luajit tests/run.lua "verify revoke:"
-- runs them alone.
local ns, test, eq, RelayWorld, ADDON_DIR = ...
local FIXTURES = (ADDON_DIR:match("^(.*)Olympus/$") or "./") .. "tests/fixtures/"
local T0 = 1800000000
local DAY = 86400
local GUILD, OTHER, THIRD = "Olympus Vanguard", "Olympus Embers", "Olympus Wardens"
local MASTER = "Guild Master-Realm"
local HC, HUB = "Max Ran-Realm", "Hildryn Payne-Realm" -- both on the signed list: relays, and verifiers here

local function World(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo }
	local dialogs = {}; for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local nodes, timers, now = {}, {}, T0
	GetChannelName = function() return 0 end
	ns.IsMember = function() return true end
	IsInGuild = function() return true end
	local function As(n, f, ...)
		C_ChatInfo = n.chat
		GetGuildInfo = function() return n.guild, "Member", 3 end
		return f(...)
	end
	-- opts.old: a client still on 1.5.9 (its Verify.lua as that release ships it).
	local function Node(name, guild, opts)
		opts = opts or {}
		local c, deliver, sent, _, pump, sentOf = RelayWorld(name, guild)
		local n = { c = c, deliver = deliver, sent = sent, pump = pump, sentOf = sentOf,
			guild = guild, chat = C_ChatInfo, cursor = 0, printed = {} }
		c.clock, c.realm, c.RealmPages = now, "Realm", {}
		c.Relay.PRESENT_REQUIRED_AT = T0 + 60 * DAY -- (tests/relay-admit.lua has the presentation)
		c.rdb.guilds = { [GUILD] = { leader = MASTER, realm = "Realm", total = 990 },
			[OTHER] = { leader = MASTER, realm = "Realm", total = 400 }, [THIRD] = { leader = MASTER, realm = "Realm", total = 200 } }
		c.IsHighCouncillor = function(who)
			local full = c.FullName(who)
			return full == HC or full == HUB
		end
		c.IsKingCharacter = function() return false end
		c.Workshop = { IsAuthorName = function() return false end }
		c.Fire, c.On = function() end, function() end
		c.UI = { Refresh = function() end }
		c.Print = function(m) n.printed[#n.printed + 1] = tostring(m) end
		c.After = function(delay, _, f) timers[#timers + 1] = { at = now + delay, n = n, f = f } end
		c.Every = function() end
		c.L = setmetatable({}, { __index = ns.L })
		As(n, function()
			assert(loadfile(ADDON_DIR .. "Locales/VerifyText.lua"))("Olympus", c)
			assert(loadfile(opts.old and (FIXTURES .. "verify-1.5.9.lua") or (ADDON_DIR .. "Verify.lua")))("Olympus", c)
		end)
		c.Verify.Clock = function() return now end
		c.Verify.random = function(a) return a end
		nodes[#nodes + 1] = n
		return n
	end
	local function Flush()
		for _ = 1, 80 do
			local moved = false
			for _, n in ipairs(nodes) do
				As(n, n.pump, 60)
				while n.cursor < #n.sent do
					n.cursor = n.cursor + 1
					local p = n.sent[n.cursor]
					for _, to in ipairs(nodes) do
						if to ~= n and ((p.dist == "WHISPER" and ns.ShortName(to.c.me) == ns.ShortName(p.target))
							or (p.dist == "GUILD" and to.guild == n.guild)) then
							As(to, to.deliver, p.dist, n.c.me, p.msg); moved = true
						end
					end
				end
			end
			if not moved then return end
		end
		error("verification wire did not settle")
	end
	local function Advance(seconds)
		now = now + seconds
		for _, n in ipairs(nodes) do n.c.clock = now end
		local due = timers; timers = {}
		for _, t in ipairs(due) do
			if t.at <= now then As(t.n, t.f) else timers[#timers + 1] = t end
		end
		Flush()
	end
	local ok, err = pcall(fn, Node, As, Flush, Advance, function() return now end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(err, 0) end
end

-- A client of `guild` whose sweep its relay answered and whose guild registered there (the last of a
-- guild to register is its reporter, which hands the relay's words to its guildmates over GUILD).
local function Register(As, relay, m)
	As(m, m.deliver, "WHISPER", relay.c.me, "RY~")
	As(relay, relay.deliver, "WHISPER", m.c.me, "RL~P~RR~" .. m.guild)
end
local function Member(Node, As, name, guild, relay, opts)
	local m = Node(name, guild, opts)
	Register(As, relay, m)
	return m
end

-- The mark the Census draws before the guild's name on that client (Views.lua's VerifyMark).
local function Checked(As, n, guild) return As(n, n.c.Verify.Mark, guild) == n.c.Verify.MARK_OK end
local function CountChecked(As, list, guild)
	local k = 0
	for _, n in ipairs(list) do if Checked(As, n, guild) then k = k + 1 end end
	return k
end
local function Printed(n, text)
	for _, line in ipairs(n.printed) do if line == text then return true end end
	return false
end

-- Approvals a verifier's client holds besides the guild's (a realm group's store held 132 words by
-- 11-13): each with a guild master of another realm, as on Forever's sub-realms, so its row in an answer
-- is nearly as long as a real one. An answer carries what fits in Verify.MAX_BYTES, the newest first.
-- (kind: "R" for revocations; first: the first guild's number, 1 by default.)
local function Fill(As, n, from, count, kind, first)
	for i = 1, count do
		local at, g = from + i, (first or 1) + i - 1
		As(n, n.c.Verify.Handle, "CHANNEL", HC, ("GV~1~%s~%d~Olympus Legion %d~Legion Master%d-CAMWOWUS1Realm1PvE"):format(kind or "A", at, g, g))
	end
end
local function Words(n)
	local k = 0
	for _ in pairs(n.c.rdb.verify.list) do k = k + 1 end
	return k
end

test("verify revoke: a verifier whose client never held a guild's old approval revokes it, and every client drops the check, 1.5.9 and 1.6.0 alike", function()
	World(function(Node, As, Flush, Advance)
		local approver = Node(HC, "Olympus Crown")
		-- Two of the guild's members and four players of two other guilds (one who left it since), half on
		-- 1.5.9; the last of each guild to register is its reporter (on 1.5.9 here, but the third guild's).
		local clients = {
			Member(Node, As, "Vanguard Ally-Realm", GUILD, approver),
			Member(Node, As, "Vanguard Elder-Realm", GUILD, approver, { old = true }),
			Member(Node, As, "Embers Ally-Realm", OTHER, approver),
			Member(Node, As, "Embers Elder-Realm", OTHER, approver, { old = true }),
			Member(Node, As, "Wardens Elder-Realm", THIRD, approver, { old = true }),
			Member(Node, As, "Wardens Ally-Realm", THIRD, approver),
		}
		eq(As(approver, approver.c.Verify.Approve, GUILD, MASTER), true)
		eq(As(approver, approver.c.Verify.Approve, OTHER, MASTER), true)
		Flush(); Advance(10)
		eq(CountChecked(As, clients, GUILD), 6, "the approval reached every client: the check")
		eq(CountChecked(As, clients, OTHER), 6)
		-- The approvals of the days after: an answer carries the newest words a store holds.
		Fill(As, approver, T0 + 60, 150)
		Advance(DAY)
		-- Another councillor's client, away when the guild was approved, asks: its answer is full of newer words.
		local other = Node(HUB, "Olympus Hearth")
		eq(As(other, other.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		assert(other.c.Verify.Digest() >= 60, "the other councillor's client took an answer")
		assert(As(other, other.c.Verify.Status, GUILD) ~= "verified", "the guild's old approval was not in it")
		-- (The reporters registered again since, as they do every Relay.REGISTER_EVERY; the third guild
		-- with the other councillor's relay now, so the revocation reaches guilds of both relays.)
		for i, n in ipairs(clients) do Register(As, i <= 4 and approver or other, n) end
		-- The staff excommunicate the guild: this councillor revokes its verification.
		As(other, other.c.Verify.RevokeInput, GUILD)
		Flush(); Advance(10)
		eq(CountChecked(As, clients, GUILD), 0, "clients still showing the check (of 6)")
		eq(Checked(As, approver, GUILD), false, "nor the verifier who approved it")
		assert(not Printed(other, other.c.L.VERIFY_NOTHING:format(GUILD)), "not refused for an approval this client never held")
		assert(Printed(other, other.c.L.VERIFY_REVOKED:format(GUILD)), "the revocation was given")
		for _, n in ipairs(clients) do
			local e = n.c.rdb.verify.list[ns.Fold(GUILD)]
			eq(e.k, "R", n.c.me .. " holds the revocation")
			eq(e.by, HUB, n.c.me .. ": by the councillor who gave it")
			assert(e.at > T0, n.c.me .. ": newer than the approval")
			eq(As(n, n.c.Verify.Status, GUILD) ~= "verified", true, n.c.me .. " no longer verified")
		end
		eq(CountChecked(As, clients, OTHER), 6, "the other guild keeps its check")
	end)
end)

-- The staff's way on 1.5.9 (which cannot change): a councillor whose client holds no approval of the
-- guild approves it and revokes it at once; the revocation, newer, stands over every approval. This pins
-- what a 1.5.9 councillor's two commands do on clients of both versions.
test("verify revoke: on 1.5.9 a councillor holding no approval of the guild approves and revokes it at once, and every client drops the check", function()
	World(function(Node, As, Flush, Advance)
		local approver = Node(HC, "Olympus Crown")
		local clients = {
			Member(Node, As, "Vanguard Ally-Realm", GUILD, approver),
			Member(Node, As, "Embers Elder-Realm", OTHER, approver, { old = true }),
		}
		eq(As(approver, approver.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(DAY)
		for _, n in ipairs(clients) do Register(As, approver, n) end
		local old = Node(HUB, "Olympus Hearth", { old = true })
		As(old, old.c.Verify.RevokeInput, GUILD)
		assert(Printed(old, old.c.L.VERIFY_NOTHING:format(GUILD)), "1.5.9 refuses the revocation alone")
		eq(CountChecked(As, clients, GUILD), 2)
		As(old, old.c.Verify.ApproveInput, GUILD)
		As(old, old.c.Verify.RevokeInput, GUILD)
		Flush(); Advance(10)
		assert(Printed(old, old.c.L.VERIFY_REVOKED:format(GUILD)))
		eq(CountChecked(As, clients, GUILD), 0, "clients still showing the check (of 2)")
		eq(Checked(As, approver, GUILD), false)
		for _, n in ipairs(clients) do eq(n.c.rdb.verify.list[ns.Fold(GUILD)].k, "R", n.c.me) end
	end)
end)

test("verify revoke: an answer carries the revocations first, so a client back days later drops the check of a guild revoked meanwhile", function()
	World(function(Node, As, Flush, Advance, Now)
		local verifier = Node(HC, "Olympus Crown")
		As(verifier, verifier.c.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(T0, GUILD, MASTER))
		Fill(As, verifier, T0 + 10, 40)
		As(verifier, verifier.c.Verify.Handle, "CHANNEL", HC, ("GV~1~R~%d~%s~%s"):format(T0 + 100, GUILD, MASTER))
		-- Five days of approvals after the revocation: more than one answer carries.
		Advance(5 * DAY)
		Fill(As, verifier, Now() - 1000, 150)
		local _, rows = As(verifier, verifier.c.Verify.Payload)
		assert(rows < 151, "an answer is bounded: " .. rows .. " of 151 words")
		Advance(DAY)
		-- Two players back after six days away, who heard the approval before: one on 1.6.0, one on 1.5.9.
		local back = {
			Member(Node, As, "Vanguard Ally-Realm", GUILD, verifier),
			Member(Node, As, "Embers Elder-Realm", OTHER, verifier, { old = true }),
		}
		for _, n in ipairs(back) do
			As(n, n.c.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(T0, GUILD, MASTER))
		end
		eq(CountChecked(As, back, GUILD), 2, "each still shows the check it heard")
		for _, n in ipairs(back) do
			eq(As(n, n.c.Verify.Ask), true)
			Flush(); Advance(10); Advance(10)
			Advance(verifier.c.Verify.ANSWER_GAP) -- (one answer each ANSWER_GAP)
		end
		eq(CountChecked(As, back, GUILD), 0, "clients back still showing the revoked guild's check (of 2)")
		for _, n in ipairs(back) do eq(n.c.rdb.verify.list[ns.Fold(GUILD)].k, "R", n.c.me) end
		assert(back[1].c.Verify.Digest() >= 60, "the answers still carried the newest approvals")
		eq(Checked(As, back[1], "Olympus Legion 150"), true)
	end)
end)

test("verify revoke: a verifier still on 1.5.9 answers the newest words alone (a revocation older than they are stays behind)", function()
	World(function(Node, As, Flush, Advance, Now)
		local old = Node(HC, "Olympus Crown", { old = true })
		As(old, old.c.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(T0, GUILD, MASTER))
		Fill(As, old, T0 + 10, 40)
		As(old, old.c.Verify.Handle, "CHANNEL", HC, ("GV~1~R~%d~%s~%s"):format(T0 + 100, GUILD, MASTER))
		Advance(5 * DAY)
		Fill(As, old, Now() - 1000, 150)
		Advance(DAY)
		local back = Member(Node, As, "Vanguard Ally-Realm", GUILD, old)
		As(back, back.c.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(T0, GUILD, MASTER))
		eq(As(back, back.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		-- (1.5.9 cannot change: a councillor on 1.6.0 online, or a new revocation, gives it.)
		eq(Checked(As, back, GUILD), true, "the 1.5.9 verifier's answer left the revocation out")
		eq(back.c.rdb.verify.list[ns.Fold(GUILD)].k, "A")
	end)
end)

-- 1.6.0 (the review of these fixes: a store at Verify.MAX words). Past the cap the oldest approvals go
-- before any revocation: Prune trimmed the revocations first, so a revocation an hour old went at the
-- next approval's tick, the relay held no word on the guild, and a client back the next day kept the
-- check (a realm group's store held 132 words by 11-13, some 13 more a day: 400 by early December).
-- Fails before: the revocation was gone, and both clients back kept the check.
test("verify revoke: past the store's cap the oldest approvals go before a revocation, so clients back the next day still drop the check", function()
	World(function(Node, As, Flush, Advance, Now)
		local verifier = Node(HC, "Olympus Crown")
		local V = verifier.c.Verify
		-- The store at its cap: the guild's approval, and MAX - 1 older ones.
		Fill(As, verifier, T0 - 5000, V.MAX - 1)
		As(verifier, V.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(T0, GUILD, MASTER))
		eq(Words(verifier), V.MAX, "(the store at its cap)")
		local list = verifier.c.rdb.verify.list
		Advance(DAY)
		-- The other councillor revoked the guild an hour ago; then a new guild is approved, one word over
		-- the cap, and the minute's tick trims the store.
		As(verifier, V.Handle, "CHANNEL", HUB, ("GV~1~R~%d~%s~%s"):format(Now() - 3600, GUILD, MASTER))
		As(verifier, V.Tick)
		As(verifier, V.Handle, "CHANNEL", HC, ("GV~1~A~%d~Olympus Fresh~Fresh Master-Realm"):format(Now()))
		As(verifier, V.Tick)
		eq(Words(verifier), V.MAX, "the store back at its cap")
		eq(list[ns.Fold(GUILD)] and list[ns.Fold(GUILD)].k, "R", "the revocation an hour old is still held")
		eq(list[ns.Fold("Olympus Legion 1")], nil, "the oldest approval went instead")
		eq(list[ns.Fold("Olympus Legion 2")].k, "A", "(only the oldest)")
		Advance(DAY)
		-- Two players back the next day, who heard the approval before: one on 1.6.0, one on 1.5.9.
		local back = {
			Member(Node, As, "Vanguard Ally-Realm", GUILD, verifier),
			Member(Node, As, "Embers Elder-Realm", OTHER, verifier, { old = true }),
		}
		for _, n in ipairs(back) do
			As(n, n.c.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(T0, GUILD, MASTER))
		end
		eq(CountChecked(As, back, GUILD), 2, "each still shows the check it heard")
		for _, n in ipairs(back) do
			eq(As(n, n.c.Verify.Ask), true)
			Flush(); Advance(10); Advance(10)
			Advance(V.ANSWER_GAP) -- (one answer each ANSWER_GAP)
		end
		eq(CountChecked(As, back, GUILD), 0, "clients back still showing the revoked guild's check (of 2)")
		for _, n in ipairs(back) do eq(n.c.rdb.verify.list[ns.Fold(GUILD)].k, "R", n.c.me) end
		eq(Checked(As, back[1], "Olympus Fresh"), true, "(the answer carried the newest approval too)")
		-- The cap still holds when the revocations alone pass it: then the oldest revocations go.
		Fill(As, verifier, Now() - 2 * V.MAX, V.MAX + 1, "R", 1001)
		As(verifier, V.Tick)
		eq(Words(verifier), V.MAX, "never more than MAX words")
		eq(list[ns.Fold(GUILD)], nil, "the oldest revocation went")
		eq(list[ns.Fold("Olympus Legion 1001")], nil, "and the next oldest")
		eq(list[ns.Fold("Olympus Legion 1002")].k, "R", "the newer ones stay")
		eq(list[ns.Fold("Olympus Fresh")], nil, "(every approval went before them)")
	end)
end)

-- 1.6.0 (the review of these fixes: a purge). An answer carries the newest revocations first, in
-- Verify.REVOKE_BYTES of it at most, then every other word, the newest first. With every revocation
-- first, a purge of some 50 guilds or more within REVOKE_KEEP filled an answer (some 98 rows of
-- Forever's names) and it carried no approval given since; with the newest first alone (1.5.9), a
-- revocation behind some 98 newer approvals reached no client back after them. Fails before: on the
-- lane's first fix none of the 100 new approvals arrived; on 76c0c57e none of the 130 revocations.
test("verify revoke: after a purge an answer still carries the newest approvals: the revocations go first in half of it at most", function()
	World(function(Node, As, Flush, Advance, Now)
		local verifier = Node(HC, "Olympus Crown")
		local V = verifier.c.Verify
		Fill(As, verifier, T0, 200) -- 200 guilds approved
		Advance(DAY)
		Fill(As, verifier, Now() - 500, 130, "R") -- a purge: 130 of them revoked
		for d = 1, 4 do -- then 100 new guilds approved, over four days
			Advance(DAY)
			Fill(As, verifier, Now() - 2000, 25, "A", 476 + 25 * d)
		end
		-- Two players back after the purge, who heard the 200 approvals before: one on 1.6.0, one on 1.5.9.
		local back = {
			Member(Node, As, "Embers Ally-Realm", OTHER, verifier),
			Member(Node, As, "Wardens Elder-Realm", THIRD, verifier, { old = true }),
		}
		for _, n in ipairs(back) do Fill(As, n, T0, 200) end
		eq(CountChecked(As, back, "Olympus Legion 130"), 2, "(each shows the check it heard)")
		for _, n in ipairs(back) do
			eq(As(n, n.c.Verify.Ask), true)
			Flush(); Advance(10); Advance(10)
			Advance(V.ANSWER_GAP) -- (one answer each ANSWER_GAP)
		end
		eq(CountChecked(As, back, "Olympus Legion 130"), 0, "the newest revocation: clients back still checked (of 2)")
		eq(CountChecked(As, back, "Olympus Legion 600"), 2, "the newest approval: clients back checked (of 2)")
		for _, n in ipairs(back) do
			local fresh, gone = 0, 0
			for g = 501, 600 do if Checked(As, n, "Olympus Legion " .. g) then fresh = fresh + 1 end end
			for g = 1, 130 do
				local e = n.c.rdb.verify.list[ns.Fold("Olympus Legion " .. g)]
				if e and e.k == "R" then gone = gone + 1 end
			end
			assert(fresh >= 30 and gone >= 30, ("%s: %d of the 100 new approvals, %d of the 130 revocations"):format(n.c.me, fresh, gone))
		end
		-- What an answer carries: the revocations' block first, then the newest approvals.
		local payload = As(verifier, V.Payload)
		local head, body = payload:match("^(GV~1~S~%d+~)(.*)$")
		local block, revoked, approved = {}, 0, 0
		for row in body:gmatch("[^;]+") do
			if row:sub(1, 2) == "R," then
				revoked = revoked + 1
				if approved == 0 then block[#block + 1] = row end
			else
				approved = approved + (row:sub(1, 2) == "A," and 1 or 0)
			end
		end
		assert(revoked >= 30 and approved >= 30, ("an answer of both kinds: %d revocations, %d approvals"):format(revoked, approved))
		assert(#head + #table.concat(block, ";") <= V.REVOKE_BYTES, "the revocations' block within REVOKE_BYTES")
	end)
end)
