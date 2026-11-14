-- 1.5.4: the King's crown (King.lua: T1~P where he is, T1~Q hidden again) on Forever's relays.
-- 1.5.3 carried it to almost nobody: the King's client, a relay itself, always took its own words to
-- its own reporters alone, and the relays never ping one another, so nothing went across; any other
-- relay held it inside the four-piece trickle behind the guilds' census; and the same crown again
-- (him standing still) was swallowed for five minutes as a second copy. Each test fails on 1.5.3.
local ns, test, eq, extra = ...
local RelayWorld = extra.RelayWorld

local KING = "Asmongold Thereal"
local function KingWorld(me)
	local w = { RelayWorld(me, "Olympus Prime", nil, "Harbor Warden") }
	local cns = w[1]
	cns.IsKingCharacter = function(name) return type(name) == "string" and ns.ShortName(name) == KING end
	return unpack(w)
end

local function Guarded(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus Prime", "Officer", 1 end
		fn()
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end

local function Count(sent, fn) local n = 0 for _, s in ipairs(sent) do if fn(s) then n = n + 1 end end return n end

test("1.5.4 the King's crown: his own client, a relay, whispers each crown to every other relay not left out, once each KING_GAP at most, his hidden word at once; his other words keep their single route", function()
	Guarded(function()
		local K, deliver, sent, _, pump = KingWorld(KING .. "-Realm")
		K.KingCharacter = function() return KING end -- (a relay by the signed list, as on the live realms)
		eq((K.Relay.Pick()), KING, "the King's client picks itself")
		local function To(who, prefix)
			return Count(sent, function(s) return s.dist == "WHISPER" and s.target == who and s.msg:sub(1, #prefix) == prefix end)
		end
		K.Comm.Send("CHANNEL", "T1~P~3~Olympus Prime~1453~420~510", "kinglocation")
		pump(50)
		eq(To("Max Ran", "RL~P~T1~P~3~"), 1, "to one relay"); eq(To("Harbor Warden", "RL~P~T1~P~3~"), 1, "and the other")
		K.clock = K.clock + 5
		K.Comm.Send("CHANNEL", "T1~P~3~Olympus Prime~1453~430~510", "kinglocation")
		pump(50)
		eq(To("Max Ran", "RL~P~T1~P~3~"), 1, "not again within KING_GAP")
		K.clock = K.clock + K.Relay.KING_GAP
		K.Comm.Send("CHANNEL", "T1~P~3~Olympus Prime~1453~440~510", "kinglocation")
		pump(50)
		eq(To("Max Ran", "RL~P~T1~P~3~"), 2, "the next one after KING_GAP"); eq(To("Harbor Warden", "RL~P~T1~P~3~"), 2)
		K.Comm.Send("CHANNEL", "T1~Q~3~Olympus Prime", "kinglocation")
		pump(50)
		eq(To("Max Ran", "RL~P~T1~Q~3~"), 1, "hidden goes at once"); eq(To("Harbor Warden", "RL~P~T1~Q~3~"), 1)
		K.Comm.Send("CHANNEL", "X1~another word of his")
		pump(50)
		eq(To("Max Ran", "RL~P~X1~"), 0, "his other words: the usual single route")
		-- An offline relay is left out for DEAD_FOR (the server's "No player named"): no crown to it meanwhile.
		K.Relay.LeaveOut("Max Ran", "offline")
		K.clock = K.clock + K.Relay.KING_GAP
		K.Comm.Send("CHANNEL", "T1~P~3~Olympus Prime~1453~450~510", "kinglocation")
		pump(50)
		eq(To("Max Ran", "RL~P~T1~P~3~"), 2, "left out: nothing"); eq(To("Harbor Warden", "RL~P~T1~P~3~"), 3)
	end)
	Guarded(function()
		local O, _, sent, _, pump = KingWorld("Some Body-Realm")
		local relay = O.Relay.Pick()
		O.Comm.Send("CHANNEL", "T1~P~3~Olympus Prime~1453~420~510")
		pump(50)
		eq(Count(sent, function(s) return s.msg:find("T1~P~", 1, true) ~= nil end) <= 1, true, "anyone else's words never fan out to every relay")
		assert(relay)
	end)
end)

test("1.5.4 the King's crown: a relay hands it to its reporters outside the trickle and ahead in the queue, each once a KING_GAP at most, the longest waiting first, KING_PER_MIN a minute in all; his hidden word at once; anyone else's T1~P stays in the trickle", function()
	Guarded(function()
		local H, deliver, sent, _, pump = KingWorld("Harbor Warden-Realm")
		for i = 1, 3 do deliver("WHISPER", "Reporter" .. i .. "-Realm", "RL~P~RR~Olympus R" .. i) end
		-- Another guild's census, four one-whisper pieces, first in the minute: each reporter's trickle is spent.
		for i = 1, 4 do deliver("WHISPER", "Census Guy-Realm", ("RL~P~C7:%d:4:%s"):format(i, ("x"):rep(i < 4 and 200 or 10))) end
		local function Crowns(prefix)
			return Count(sent, function(s) return s.dist == "WHISPER" and s.msg:sub(1, 3) == "RM~" and s.msg:find(prefix, 1, true) ~= nil end)
		end
		deliver("WHISPER", KING .. "-Realm", "RL~P~T1~P~3~Olympus Prime~1453~420~510")
		pump(100)
		eq(Crowns("~T1~P~3~"), 3, "one to each reporter, the trickle spent")
		H.clock = H.clock + 5
		deliver("WHISPER", KING .. "-Realm", "RL~P~T1~P~3~Olympus Prime~1453~430~510")
		pump(100)
		eq(Crowns("~T1~P~3~"), 3, "not again within the gap")
		H.clock = H.clock + H.Relay.KING_GAP
		deliver("WHISPER", KING .. "-Realm", "RL~P~T1~P~3~Olympus Prime~1453~440~510")
		pump(100)
		eq(Crowns("~T1~P~3~"), 6, "the newest after the gap")
		deliver("WHISPER", KING .. "-Realm", "RL~P~T1~Q~3~Olympus Prime")
		pump(100)
		eq(Crowns("~T1~Q~3~"), 3, "hidden at once")
		-- (The review of the 1.5.4 candidate.) Past KING_GAP, so a crown would go to every reporter now,
		-- and past each reporter's allowance window, so it is whole again: spent first, the word not his
		-- must find none and stay in the trickle, never take the crown's way. Before, it came at the
		-- second of the hidden word, when no crown was due: it passed whichever way it went.
		H.clock = H.clock + H.Relay.KING_GAP
		for i = 1, 4 do deliver("WHISPER", "Census Guy-Realm", ("RL~P~C8:%d:4:%s"):format(i, ("x"):rep(i < 4 and 200 or 10))) end
		local trickled = H.Relay.Stats().trickled or 0
		deliver("WHISPER", "Some Body-Realm", "RL~P~T1~P~9~Olympus Prime~1453~100~100")
		pump(100)
		eq(Crowns("~T1~P~9~"), 0, "a T1~P not his: in the trickle, spent, though a crown would go now")
		eq((H.Relay.Stats().trickled or 0) - trickled, 3, "held back by each reporter's trickle")
	end)
	Guarded(function()
		-- Sixty reporters, the King's crown every 5 s for ten minutes: KING_PER_MIN a minute in all
		-- (KING_BURST at once), shared fairly, each reporter's crown renewed well inside the clients' lease.
		local H, deliver, sent, _, pump = KingWorld("Harbor Warden-Realm")
		local start = H.clock
		for i = 1, 60 do deliver("WHISPER", "Reporter" .. i .. "-Realm", "RL~P~RR~Olympus R" .. i) end
		local last, worst, got = {}, 0, {}
		local stamped = 0
		for t = 0, 600, 5 do
			H.clock = start + t
			H.Comm.ResetAdmission() -- (the admission budget runs on GetTime, which this loop does not advance)
			if t % 170 == 0 then for i = 1, 60 do deliver("WHISPER", "Reporter" .. i .. "-Realm", "RL~P~RR~Olympus R" .. i) end end
			deliver("WHISPER", KING .. "-Realm", ("RL~P~T1~P~3~Olympus Prime~1453~%d~510"):format(100 + t))
			pump(200)
			for i = stamped + 1, #sent do
				local s = sent[i]
				if s.msg:sub(1, 3) == "RM~" and s.msg:find("~T1~P~3~", 1, true) then
					got[s.target] = (got[s.target] or 0) + 1
					if last[s.target] then worst = math.max(worst, t - last[s.target]) end
					last[s.target] = t
				end
			end
			stamped = #sent
		end
		local n, fewest = 0, math.huge
		for i = 1, 60 do local c = got["Reporter" .. i] or 0; n = n + c; fewest = math.min(fewest, c) end
		if os.getenv("KL_PRINT") then print(("       60 reporters, 600 s: %d crowns, fewest %d per reporter, longest wait %d s"):format(n, fewest, worst)) end
		eq(n <= H.Relay.KING_BURST + H.Relay.KING_PER_MIN * 10, true, "at most KING_PER_MIN a minute after one burst: " .. n)
		eq(n >= H.Relay.KING_PER_MIN * 10, true, "and the whole of it used: " .. n)
		eq(fewest >= 6, true, "every reporter in turn: " .. fewest)
		eq(worst <= 120, true, "no reporter waits past two minutes (the clients keep it three): " .. worst)
	end)
end)

test("1.5.4 the King's crown: the same crown again (him standing still) renews it where it arrives and goes on to the guild; any other word again is still one copy", function()
	Guarded(function()
		local P, deliver, sent, _, pump = KingWorld("Reporter One-Realm")
		local heard = {}
		P.Comm.Handle("T1", function(dist, sender, text) heard[#heard + 1] = text end)
		P.Comm.Handle("X1", function(dist, sender, text) heard[#heard + 1] = text end)
		for i = 0, 2 do
			P.clock = 100000 + i * 20
			deliver("WHISPER", "Max Ran-Realm", "RM~P~" .. KING .. "-Realm~T1~P~3~Olympus Prime~1453~420~510")
			deliver("WHISPER", "Max Ran-Realm", "RM~P~Some Body-Realm~X1~same words")
			pump(20)
		end
		eq(#heard, 4, "three crowns and one copy of the other word")
		eq(Count(sent, function(s) return s.dist == "GUILD" and s.msg:find("T1~P~3~", 1, true) ~= nil end), 3, "each crown to the guild")
		eq(Count(sent, function(s) return s.dist == "GUILD" and s.msg:find("X1~", 1, true) ~= nil end), 1)
	end)
end)

test("1.5.4 the King's crown: in a relay's queue his newest crown never takes the place of his waiting call (T1 kinds keyed apart)", function()
	Guarded(function()
		local H, deliver, sent, _, pump = KingWorld("Harbor Warden-Realm")
		deliver("WHISPER", "Reporter1-Realm", "RL~P~RR~Olympus R1")
		deliver("WHISPER", KING .. "-Realm", "RL~P~T1~S~7~Olympus Prime")
		deliver("WHISPER", KING .. "-Realm", "RL~P~T1~P~3~Olympus Prime~1453~420~510")
		pump(100)
		eq(Count(sent, function(s) return s.target == "Reporter1" and s.msg:find("~T1~S~7~", 1, true) ~= nil end), 1, "the summons still goes")
		eq(Count(sent, function(s) return s.target == "Reporter1" and s.msg:find("~T1~P~3~", 1, true) ~= nil end), 1, "and the crown")
	end)
end)

-- 1.5.4: the King's presence (T1~o) reaches the other relays the same way: his client, a relay,
-- never pinged one, so only the guilds registered at his own client heard he was online.
test("1.5.4 the King's presence: his own client whispers it to every other relay not left out, whatever crown went just before; anyone else's never fans out", function()
	Guarded(function()
		local K, _, sent, _, pump = KingWorld(KING .. "-Realm")
		K.KingCharacter = function() return KING end
		local function To(who, prefix)
			return Count(sent, function(s) return s.dist == "WHISPER" and s.target == who and s.msg:sub(1, #prefix) == prefix end)
		end
		K.Comm.Send("CHANNEL", "T1~P~3~Olympus Prime~1453~420~510", "kinglocation")
		pump(50)
		K.Comm.Send("CHANNEL", "T1~o~7~Olympus Prime", "king presence", true)
		pump(50)
		eq(To("Max Ran", "RL~P~T1~o~7~"), 1, "to one relay, a crown just before notwithstanding")
		eq(To("Harbor Warden", "RL~P~T1~o~7~"), 1, "and the other")
		K.Relay.LeaveOut("Max Ran", "offline")
		K.clock = K.clock + 300
		K.Comm.Send("CHANNEL", "T1~o~8~Olympus Prime", "king presence", true)
		pump(50)
		eq(To("Max Ran", "RL~P~T1~o~8~"), 0, "left out: nothing"); eq(To("Harbor Warden", "RL~P~T1~o~8~"), 1)
	end)
	Guarded(function()
		local O, _, sent, _, pump = KingWorld("Some Body-Realm")
		O.Comm.Send("CHANNEL", "T1~o~7~Olympus Prime", "king presence", true)
		pump(50)
		eq(Count(sent, function(s) return s.msg:find("T1~o~", 1, true) ~= nil end) <= 1, true, "anyone else's presence never fans out to every relay")
	end)
end)

-- 1.5.4: the King's layer word (L1, L0) too: when it changes, else once each KING_REFRESH, to every
-- other relay, so their guilds learn where to ask for his layer (the arrow's exact mark, the hop).
test("1.5.4 the King's layer: his own client whispers it to every other relay when it changes, else once each KING_REFRESH", function()
	Guarded(function()
		local K, _, sent, _, pump = KingWorld(KING .. "-Realm")
		K.KingCharacter = function() return KING end
		local function To(who, prefix)
			return Count(sent, function(s) return s.dist == "WHISPER" and s.target == who and s.msg:sub(1, #prefix) == prefix end)
		end
		K.Comm.Send("CHANNEL", "L1~1429~3~0~Olympus Prime")
		pump(50)
		eq(To("Max Ran", "RL~P~L1~1429~3~"), 1, "to one relay"); eq(To("Harbor Warden", "RL~P~L1~1429~3~"), 1, "and the other")
		K.clock = K.clock + 60
		K.Comm.Send("CHANNEL", "L1~1429~3~0~Olympus Prime")
		pump(50)
		eq(To("Max Ran", "RL~P~L1~1429~3~"), 1, "the same layer again within KING_REFRESH: not again")
		K.Comm.Send("CHANNEL", "L1~1429~6~0~Olympus Prime")
		pump(50)
		eq(To("Max Ran", "RL~P~L1~1429~6~"), 1, "a new layer at once")
		K.clock = K.clock + K.Relay.KING_REFRESH
		K.Comm.Send("CHANNEL", "L1~1429~6~0~Olympus Prime")
		pump(50)
		eq(To("Max Ran", "RL~P~L1~1429~6~"), 2, "the same layer after KING_REFRESH")
	end)
end)
