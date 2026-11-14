-- The Watch's chat moderation (1.1.6, WatchChat.lua): deleted lines, timeouts, the guild master's
-- Watchers, the Olympus moderators, the audit, a sanction's bars. A small world of clients, each
-- with the real Watch.lua, Channels.lua, ChatRooms.lua and WatchChat.lua loaded into a namespace
-- of its own, talks through a stand-in transport: the server stamps the sender, GUILD reaches the
-- sender's guild, CHANNEL everyone, a queued message's permit or guard runs when it "leaves".
-- Every test name starts with "watch: chat moderation:", so
--   OLYMPUS_TEST_WATCH_ONLY=1 luajit tests/run.lua "chat moderation"
-- runs them alone.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]watch%-chat%.lua$")) or "./"

local GLOBALS = { "GetGuildInfo", "IsInGuild", "UnitIsPlayer", "C_ChatInfo", "GetTime", "GetChannelName", "DEFAULT_CHAT_FRAME", "IsCombatLog",
	"issecretvalue", "UnitClass", "C_FriendList", "SLASH_OLYMPUSALL1", "SLASH_OLYMPUSCAPTAINS1", "SLASH_OLYMPUSLORDS1" }

local function Fold(s) return ns.Fold(tostring(s or "")) end

-- ChatWindow's own reply codec (a quote of another's line before the words typed), the file loaded
-- once into a namespace of its own: the chat warnings read a reply's words apart from its quote.
local replyCodec
local function ReplyCodec()
	if replyCodec then return replyCodec end
	local cns = setmetatable({}, { __index = ns })
	cns.On, cns.RegisterEvent = function() end, function() end
	assert(loadfile(ROOT .. "Olympus/GamepadRegistry.lua"))("Olympus", cns)
	assert(loadfile(ROOT .. "Olympus/Gamepad.lua"))("Olympus", cns)
	assert(loadfile(ROOT .. "Olympus/ChatWindow.lua"))("Olympus", cns)
	replyCodec = { DecodeReply = cns.ChatWindow.DecodeReply, EncodeReply = cns.ChatWindow.EncodeReply }
	return replyCodec
end

-- The chat warnings' list of a client (ChatStrikes.LIST): these synthetic words, each by its real
-- digest (no real word of the list is ever written in this repository).
local function List(S, words)
	for _, word in ipairs(words or {}) do
		local form = assert(S.Canon(word), word)
		S.LIST[S.Digest(form)] = #form
	end
	S.Index()
end
local function Full(name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" or name:find("-", 1, true) then return name end
	return name .. "-Realm"
end

-- A chat window of the game's: AddMessage keeps each line; TransformMessages calls the predicate
-- and the transform with (message, r, g, b) as Forever's CircularBuffer does
-- (Blizzard_SharedXML/ScrollingMessageFrame.lua, CircularBuffer.lua's TransformIf).
local function Frame(opts)
	local f = { lines = {}, calls = 0, combat = opts and opts.combat or nil }
	function f:AddMessage(text, r, g, b) self.lines[#self.lines + 1] = { message = text, r = r, g = g, b = b } end
	function f:TransformMessages(predicate, transform)
		self.calls = self.calls + 1
		for i, e in ipairs(self.lines) do
			if predicate(e.message, e.r, e.g, e.b) then
				local m, r, g, b = transform(e.message, e.r, e.g, e.b)
				self.lines[i] = { message = m, r = r, g = g, b = b }
			end
		end
	end
	return f
end

local function World(fn)
	local saved, dialogs, slash = {}, {}, {}
	for _, k in ipairs(GLOBALS) do saved[k] = rawget(_G, k) end
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	for k, v in pairs(SlashCmdList) do slash[k] = v end
	local w = { epoch = 1800000000, clients = {}, wire = {}, sent = {}, guilds = {}, council = {}, stewards = {}, hands = {},
		off = {}, links = {}, logged = true, census = {} }
	local ok, err = pcall(function()
		GetGuildInfo = function(unit)
			local c = w.current
			if c and (unit == nil or unit == "player") and c.guild then return c.guild, "Rank", c.rank end
		end
		IsInGuild = function() return w.current ~= nil and w.current.guild ~= nil end
		UnitIsPlayer = function() return false end
		C_ChatInfo = { SendAddonMessageLogged = function() return true end }
		GetTime = function() return w.epoch end
		IsCombatLog = function(f) return type(f) == "table" and f.combat == true end
		issecretvalue = function(v) return w.secret ~= nil and v == w.secret end
		UnitClass = function() return "Warrior", "WARRIOR" end
		C_FriendList = nil

		-- Runs fn as client cl: its guild for GetGuildInfo, its chat window for DEFAULT_CHAT_FRAME.
		function w.As(cl, f, ...)
			local was, frame = w.current, DEFAULT_CHAT_FRAME
			w.current, DEFAULT_CHAT_FRAME = cl, cl.frame
			local res = { pcall(f, ...) }
			w.current, DEFAULT_CHAT_FRAME = was, frame
			if not res[1] then error(res[2], 0) end
			return unpack(res, 2, table.maxn(res))
		end

		-- The server's roster of each guild: [guild][Name-Realm] = rank.
		function w.SetRank(name, guild, rank)
			name = Full(name)
			for g, list in pairs(w.guilds) do if g ~= guild then list[name] = nil end end
			if guild then
				w.guilds[guild] = w.guilds[guild] or {}
				w.guilds[guild][name] = rank
			end
			for _, cl in ipairs(w.clients) do if cl.name == name then cl.guild, cl.rank = guild, rank end end
		end

		function w.Client(short, guild, rank, opts)
			opts = opts or {}
			local name = Full(short)
			local cl = { name = name, short = short, guild = guild, rank = rank, handlers = {}, events = {}, listeners = {},
				dialogs = {}, prints = {}, timers = {}, frame = Frame(), online = true }
			w.SetRank(name, guild, rank)
			local c = setmetatable({}, { __index = ns })
			cl.ns = c
			c.L = ns.L
			c.me, c.realm, c.group, c.faction = name, "Realm", "RealmGroup", "Alliance"
			c.CAPTAIN_RANK = 1
			c.db = { addonChat = true, chatRooms = true, chatWarned = { A = true, C = true, L = true }, blocked = {} }
			c.rdb = { guilds = {} }
			c.Now = function() return w.epoch end
			-- The scene's known guild identities: its own server roster, or signed identities of
			-- the other guilds. Adversarial cases explicitly label a rank as census-only.
			c.Data = { ServerTime = function() return w.epoch end, ClaimGuild = function() return true end,
				AuthorizedRank = function(n, g)
					local list = g and w.guilds[g]
					local rank = list and list[c.FullName(n)]
					return rank, rank ~= nil and (g == cl.guild and "roster" or (w.census[g] and "census" or "signed")) or nil
				end, FRESH = 900 }
			c.FullName = function(n, realm)
				n = tostring(n or ""):gsub("^%s+", ""):gsub("%s+$", "")
				if n == "" or n:find("-", 1, true) then return n end
				return n .. "-" .. (realm or "Realm")
			end
			c.DisplayName = function(n) return (tostring(n or ""):gsub("%-Realm$", "")) end
			c.IsMember = function() return cl.guild ~= nil and ns.IsFederation(cl.guild) end
			c.CouncilMasked = function() return cl.masked == true end
			c.GamepadUI = function() return w.gamepad == true end
			c.IsKingCharacter = function(n) return w.king ~= nil and type(n) == "string" and Fold(c.FullName(n)) == Fold(w.king) end
			c.KingCharacter = function() return w.king and (w.king:gsub("%-.*$", "")) or nil end
			c.IsHighCouncillor = function(n) return type(n) == "string" and w.council[Fold(c.FullName(n))] == true end
			c.IsSteward = function(n) return type(n) == "string" and w.stewards[Fold(c.FullName(n))] == true end
			c.Workshop = { IsAuthorName = function(n) return w.author ~= nil and type(n) == "string" and Fold(c.FullName(n)) == Fold(w.author) end }
			c.King = { IsHandName = function(n) return type(n) == "string" and w.hands[Fold(c.FullName(n))] == true end,
				IsStewardName = function(n) return c.IsSteward(n) end, IsKing = function() return c.IsKingCharacter(name) end,
				IsSteward = function() return false end, IsHand = function() return false end, Preview = function() return false end }
			local function CharName(input, target)
				local n = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
				if n == "" and target then n = tostring(cl.target or "") end
				if n == "" or n:find("[~|%c]") then return nil end
				return c.FullName(n)
			end
			c.Moderation = {
				CharName = CharName,
				Hidden = function(n) return w.off[Fold(c.FullName(n))] end,
				Hides = function(n) return w.off[Fold(c.FullName(n))] end,
				SelfOff = function() return w.off[Fold(name)] end,
				IsKing = function(n) return c.IsKingCharacter(n) end,
				GuildOf = function(n)
					for g, list in pairs(w.guilds) do if list[c.FullName(n)] ~= nil then return g end end
				end,
				Rank = function() return 0 end, TargetRank = function() return 0 end, IsIssuer = function() return false end,
				YouText = function() return "net-off" end, Any = function() return next(w.off) ~= nil end,
			}
			c.Alts = { Linked = function(n) return w.links[Fold(c.FullName(n))] or {} end }
			c.ChatWindow = ReplyCodec()
			local roster = { byName = {}, complete = true, generation = 1, group = c.group, faction = c.faction, online = {} }
			setmetatable(roster, { __index = function(_, k)
				if k == "guild" then return cl.guild end
				if k == "snapshotAt" then return w.epoch end
			end })
			roster.RankOf = function(n) local list = cl.guild and w.guilds[cl.guild] return list and list[c.FullName(n)] or nil end
			roster.MyRank = function() return cl.rank end
			roster.IsOfficer = function() return cl.rank ~= nil and cl.rank <= 1 end
			roster.ClassCode = ns.Roster.ClassCode
			c.Roster = roster
			c.Fire = function(event, ...)
				cl.events[#cl.events + 1] = { event, ... }
				for _, f in ipairs(cl.listeners[event] or {}) do f(...) end
			end
			c.On = function(event, f) cl.listeners[event] = cl.listeners[event] or {}; table.insert(cl.listeners[event], f) end
			c.RegisterEvent = function() end
			c.Print = function(text) cl.prints[#cl.prints + 1] = tostring(text) end
			c.Log = function() end
			c.PlayAlert = function() end
			c.SafeCall = function(_, f, ...) return f(...) end
			c.After = function(seconds, _, f) cl.timers[#cl.timers + 1] = { at = w.epoch + (tonumber(seconds) or 0), fn = f } end
			c.Every = function() end
			c.ShowDialog = function(which, a, b, data) cl.dialogs[#cl.dialogs + 1] = { which = which, a = a, b = b, data = data } return true end
			c.UI = { TABS = {}, AddTab = function() return true end, SelectTab = function() end, ShowCopy = function() end }
			c.PlayerMenu = { Add = function() return true end }
			c.Court = { HomeLines = function() return {} end, Holding = function() return false end }
			c.Filter = { Hides = function(t) return w.filterWord ~= nil and tostring(t):find(w.filterWord, 1, true) ~= nil end,
				Hit = function() return nil end, SharedOn = function() return true end, WordsOf = ns.Filter.WordsOf }
			c.Authority = { Enforced = function() return false end }
			c.TabardsV2 = { SurfaceVisible = function() return false end }
			c.ViewAs = { Available = function() return false end }
			c.Consent = { Register = function() end, Ask = function() end }
			c.Comm = {
				Handle = function(kind, f) cl.handlers[kind] = f end,
				DeliveredLogged = function() return w.deliveredLogged ~= false end,
				QueueRoom = function() return 60 end, ChannelReady = function() return true end, ChatRoom = function() return 10 end,
				ChannelName = function() return "OlympusChannel" end, Audience = function() return "everyone" end,
				IsPublic = function() return true end, DropLine = function() end, PeerCount = function() return 1 end,
				CancelQueued = function() return 0 end,
				Send = function(dist, msg, key, plain, logged, done, options)
					w.wire[#w.wire + 1] = { from = cl, dist = dist, msg = msg, key = key, logged = logged, done = done, options = options }
					return true
				end,
				SendChat = function(msg, done, line, guard)
					w.wire[#w.wire + 1] = { from = cl, dist = "CHANNEL", msg = msg, logged = true, done = done, guard = guard }
					return true
				end,
				Whisper = function(target, msg, key, plain, logged, done, options)
					w.wire[#w.wire + 1] = { from = cl, dist = "WHISPER", target = target, msg = msg, key = key, logged = logged, done = done, options = options }
					return true
				end,
			}
			w.clients[#w.clients + 1] = cl
			w.As(cl, function()
				assert(loadfile(ROOT .. "Olympus/Watch.lua"))("Olympus", c)
				assert(loadfile(ROOT .. "Olympus/Channels.lua"))("Olympus", c)
				assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", c)
				assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", c)
				assert(loadfile(ROOT .. "Olympus/ChatStrikes.lua"))("Olympus", c)
			end)
			cl.W, cl.C, cl.R, cl.WC, cl.S = c.Watch, c.Channels, c.ChatRooms, c.WatchChat, c.ChatStrikes
			c.Watch.ResetForTests()
			c.WatchChat.ResetForTests()
			c.ChatStrikes.ResetForTests()
			List(c.ChatStrikes, w.words) -- (the scene's list: the same on every client, as it ships)
			c.WatchChat.random = function() return 0 end
			return cl
		end

		-- The prefix a client's handler answers to ("MD", "M1", "M2").
		local function Deliver(r, job)
			local kind = job.msg:match("^(%w%w)~")
			local h = kind and r.handlers[kind]
			if not h or not r.online then return end
			w.deliveredLogged = job.logged == true
			w.As(r, h, job.dist, job.from.name, job.msg)
			w.deliveredLogged = nil
		end

		-- Everything queued leaves, in order (what it queues on the way too), and timers due run.
		function w.Run()
			local guard = 0
			while true do
				for _, cl in ipairs(w.clients) do
					for i = #cl.timers, 1, -1 do
						local t = cl.timers[i]
						if t.at <= w.epoch then table.remove(cl.timers, i); w.As(cl, t.fn) end
					end
				end
				local job = table.remove(w.wire, 1)
				if not job then return end
				guard = guard + 1
				assert(guard < 2000, "the world's wire never empties")
				local allowed = true
				if job.guard then allowed = w.As(job.from, job.guard) and true or false end
				if allowed and job.options and job.options.permit then
					allowed = w.As(job.from, job.options.permit, job.options.owner, job.options.key, job.dist, job.target, job.msg) == true
				end
				if job.done then w.As(job.from, job.done, allowed, allowed and nil or "guard") end
				if allowed then
					w.sent[#w.sent + 1] = { from = job.from.name, dist = job.dist, msg = job.msg, target = job.target }
					for _, r in ipairs(w.clients) do
						if r ~= job.from and ((job.dist == "CHANNEL")
							or (job.dist == "GUILD" and r.guild ~= nil and r.guild == job.from.guild)
							or (job.dist == "WHISPER" and Fold(r.name) == Fold(Full(job.target)))) then
							Deliver(r, job)
						end
					end
				end
			end
		end

		-- A message written by hand, as the server stamps `from` on it.
		function w.Inject(dist, from, to, msg, logged)
			w.deliveredLogged = logged ~= false
			-- (The module's own receiver, for its answer: the registered handler returns nothing.)
			local kind = msg:match("^(%w%w)~")
			local h = kind == "MD" and to.WC.Handle or kind == "M1" and to.C.Receive or kind == "M2" and to.R.Receive
				or kind == "MS" and to.S.Handle or to.handlers[kind or ""]
			local res = { w.As(to, h, dist, from, msg) }
			w.deliveredLogged = nil
			return unpack(res)
		end

		-- A line said in an Olympus chat, sent and delivered; returns the id it went with.
		function w.Say(cl, tier, text)
			w.epoch = w.epoch + 2
			local ok, why = w.As(cl, cl.C.Send, tier, text)
			assert(ok, "sent: " .. tostring(why))
			local msg = w.wire[#w.wire] and w.wire[#w.wire].msg
			w.Run()
			return tonumber(msg and msg:match("^M1~%a~[^~]*~(%d+)~"))
		end
		function w.Room(cl, text)
			w.epoch = w.epoch + 6
			local ok, why = w.As(cl, cl.R.Send, "guild", text)
			assert(ok, "sent to the room: " .. tostring(why))
			w.Run()
		end

		-- The line of `sender` with these words in a client's history of `tier` (nil when none).
		function w.Line(cl, tier, sender, text)
			for _, e in ipairs(cl.C.RawHistory(tier)) do
				if Fold(e.sender) == Fold(Full(sender)) and (text == nil or e.text == text) then return e end
			end
		end
		function w.Lines(cl, tier, sender)
			local out = {}
			for _, e in ipairs(cl.C.RawHistory(tier)) do if Fold(e.sender) == Fold(Full(sender)) then out[#out + 1] = e end end
			return out
		end
		function w.Dialog(cl, which)
			for i = #cl.dialogs, 1, -1 do if cl.dialogs[i].which == which then return cl.dialogs[i] end end
		end
		function w.Printed(cl, needle)
			for _, p in ipairs(cl.prints) do if p:find(needle, 1, true) then return p end end
		end
		function w.Sent(prefix)
			local out = {}
			for _, s in ipairs(w.sent) do if s.msg:sub(1, #prefix) == prefix then out[#out + 1] = s end end
			return out
		end

		fn(w)
	end)
	for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = nil end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	for k in pairs(SlashCmdList) do SlashCmdList[k] = nil end
	for k, v in pairs(slash) do SlashCmdList[k] = v end
	if not ok then error(err, 0) end
end

-- Guild X: an officer (A), a member (B), another member (D) and its guild master (G); guild Y: a
-- member (Y1). The author, the King and a councillor are named but play only where a test says.
local X, Y = "Olympus II", "Olympus of Ash"
local function Standard(w)
	local G = w.Client("Grandmaster", X, 0)
	local A = w.Client("Officer", X, 1)
	local B = w.Client("Member", X, 3)
	local D = w.Client("Other", X, 3)
	local Y1 = w.Client("Stranger", Y, 3)
	return G, A, B, D, Y1
end

---------------------------------------------------------------------------
-- Deleting
---------------------------------------------------------------------------

test("watch: chat moderation: one line is deleted on every client: the Chat tab's history, the target's own, abroad through his own word; never relayed again", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local id = w.Say(B, "A", "first rude line")
		w.Say(B, "A", "a fine line")
		for _, cl in ipairs({ G, A, B, D, Y1 }) do assert(w.Line(cl, "A", B.name, "first rude line"), "kept on " .. cl.short) end
		local lineOnA = w.Line(A, "A", B.name, "first rude line")
		eq(lineOnA.id, id, "the line's id is kept with it (1.1.6)")
		-- A, an officer of B's guild, deletes it from his Chat tab.
		eq(w.As(A, A.WC.CanModerateEntry, lineOnA), true, "A may act on B's line")
		eq(w.As(A, A.WC.CanModerateEntry, lineOnA, "A"), true, "in an army chat")
		eq(w.As(A, A.WC.CanModerateEntry, lineOnA, "craft:abc123"), false, "a provider's room is the seam: not yet")
		local ok, scope = w.As(A, A.WC.Delete, "A", lineOnA, "rude")
		eq(ok, true); eq(scope, "G", "a Watcher acts in his guild's scope")
		local beforeLines = 0
		for _, cl in ipairs({ D, Y1 }) do for _, e in ipairs(cl.events) do if e[1] == "CHAT_LINE" then beforeLines = beforeLines + 1 end end end
		w.Run()
		-- Over GUILD to X; the target's own client withdraws it on the channel (S): Y1 too.
		eq(#w.Sent("MD~1~D~G~"), 1, "one action, over guild")
		eq(w.Sent("MD~1~D~G~")[1].dist, "GUILD")
		local s = w.Sent("MD~1~S~D~")
		eq(#s, 1, "the target's own word"); eq(s[1].from, B.name); eq(s[1].dist, "CHANNEL")
		for _, cl in ipairs({ G, A, B, D, Y1 }) do
			local e
			for _, x in ipairs(cl.C.RawHistory("A")) do if x.id == id and Fold(x.sender) == Fold(B.name) then e = x end end
			assert(e, "still there, as a deleted line, on " .. cl.short)
			eq(e.del, true, "deleted on " .. cl.short); eq(e.text, "", "its words gone on " .. cl.short)
			assert(w.Line(cl, "A", B.name, "a fine line"), "his other line stays on " .. cl.short)
		end
		-- Not relayed again: no new CHAT_LINE anywhere (a companion hears nothing more), and a late
		-- copy of it is dropped.
		local after = 0
		for _, cl in ipairs({ D, Y1 }) do for _, e in ipairs(cl.events) do if e[1] == "CHAT_LINE" then after = after + 1 end end end
		eq(after, beforeLines, "nothing more to a companion")
		local late = ns.Codec.EncodeChat("A", X, id, "", "first rude line")
		local shown, why = w.Inject("CHANNEL", B.name, D, late)
		eq(why, "dup", "heard twice within two minutes: the duplicate check drops it first")
		w.epoch = w.epoch + 121 -- (past Channels' DEDUPE_WINDOW: only the tombstone knows it now)
		shown, why = w.Inject("CHANNEL", B.name, D, late)
		eq(shown, false); eq(why, "deleted", "a late copy is dropped")
		shown, why = w.Inject("CHANNEL", B.name, Y1, late)
		eq(why, "deleted", "abroad too")
		-- B was told, by role, never the officer's name.
		local told = w.Printed(B, ns.L.WATCHCHAT_ROLE_ANY)
		assert(told and not told:find("Officer", 1, true), tostring(told))
	end)
end)

test("watch: chat moderation: a long line's parts go together, another sender's look-alike stays", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		-- A line longer than one message goes in two parts (Codec.SplitChat), each with its id.
		local long = string.rep("word ", 60) .. "end"
		w.Say(B, "A", long)
		local parts = w.Lines(A, "A", B.name)
		eq(#parts, 2, "two parts")
		w.Say(B, "A", "a short one after")
		w.Say(D, "A", parts[1].text)
		local refs = w.As(A, A.WC.RefsFor, "A", parts[2])
		eq(#refs, 2, "from its last part: both parts, not the short line after")
		assert(w.As(A, A.WC.Delete, "A", parts[2], ""))
		w.Run()
		local onD = w.Lines(D, "A", B.name)
		eq(onD[1].del, true); eq(onD[2].del, true)
		eq(onD[3].del, nil, "his next short line stays")
		eq(w.Line(D, "A", D.name).del, nil, "D's own line with the same words stays")
	end)
end)

-- 1.5.9: on Forever an [Olympus] line's id names its ruleset and keeps two digits of the writer's count
-- ("0899": an RP-PvP player's line for everyone, "0499" one for RP-PvP alone; Codec.EncodeChat). The
-- review of 1.5.9's first build: a long line whose count crossed a hundred went as 499 then 400, which
-- no client reads as one line's parts (WatchChat.RefsFor), so a moderator's delete left its first part
-- on every client. A line's parts stay within one hundred.
test("watch: chat moderation (1.5.9): a long [Olympus] line of a Forever writer, its count at the end of a hundred: its parts' ids stay consecutive, and a moderator's delete from its last part takes both, for everyone and for his own ruleset alone", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		-- B plays on an RP-PvP sub-realm of Forever, his picker on his own ruleset.
		B.ns.realm, B.ns.splitNames = "CAMWOWUS2Realm1RPPvP", true
		B.ns.Data.RULES_KIND = ns.Data.RULES_KIND
		B.ns.db.chatGroups = { [B.name] = "rppvp" }
		eq(w.As(B, B.C.MyKind), "rppvp")
		local function Send(text, to)
			w.epoch = w.epoch + 7 -- (spaced: no flood guard on the readers)
			local before = #w.wire
			assert(w.As(B, B.C.Send, "A", text, nil, nil, to), "sent: " .. text)
			local ids = {}
			for i = before + 1, #w.wire do ids[#ids + 1] = tonumber(w.wire[i].msg:match("^M1~A~[^~]*~(%d+)~")) end
			w.Run()
			return ids
		end
		local long = string.rep("word ", 60) .. "end"
		for _, case in ipairs({ { to = "rppvp", digit = 4 }, { to = nil, digit = 8 } }) do
			-- Short lines until his count's last two digits are 98: the long line's parts would be 99 and 00.
			local n = 0
			repeat
				n = n + 1
				local ids = Send("tick " .. n, case.to)
				assert(n < 150, "his count never came to 98")
			until ids[1] % 100 == 98
			local ids = Send(long, case.to)
			eq(#ids, 2, "two parts")
			eq(ids[2], ids[1] + 1, "consecutive ids, within one hundred: " .. ids[1] .. ", " .. ids[2])
			eq(math.floor(ids[1] / 100), case.digit, "the ruleset's digit: " .. ids[1])
			local parts = {}
			for _, e in ipairs(w.Lines(A, "A", B.name)) do if e.id == ids[1] or e.id == ids[2] then parts[#parts + 1] = e end end
			eq(#parts, 2, "both parts kept on A")
			local refs = w.As(A, A.WC.RefsFor, "A", parts[2])
			eq(#refs, 2, "from its last part: both parts")
			assert(w.As(A, A.WC.Delete, "A", parts[2], ""))
			w.Run()
			for _, e in ipairs(w.Lines(D, "A", B.name)) do
				if e.id == ids[1] or e.id == ids[2] then eq(e.del, true, "deleted on D: part " .. e.id) end
			end
		end
	end)
end)

test("watch: chat moderation: his recent lines go on every surface (the three chats; the guild room is the game's own guild chat since 1.2.0); one heard later never takes a newer line", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "old one")
		local oldLine = w.Line(A, "A", B.name, "old one")
		for _, cl in ipairs({ G, A, D }) do local e = w.Line(cl, "A", B.name, "old one") e.t = e.t - 2 * 86400 end
		w.Say(B, "A", "recent one")
		w.Say(B, "A", "recent two")
		w.Say(D, "A", "someone else")
		assert(w.As(A, A.WC.Purge, B.name, "spam"))
		w.Run()
		for _, cl in ipairs({ G, A, D }) do
			eq(w.Line(cl, "A", B.name, "old one") ~= nil, true, "older than a day: stays on " .. cl.short)
			for _, e in ipairs(w.Lines(cl, "A", B.name)) do
				if e ~= w.Line(cl, "A", B.name, "old one") then eq(e.del, true, "deleted on " .. cl.short) end
			end
			eq(w.Line(cl, "A", D.name, "someone else").del, nil, "another sender's stays on " .. cl.short)
		end
		-- A line of his still in flight (sent before, heard within the grace) is dropped; one after shows.
		local inFlight = ns.Codec.EncodeChat("A", X, 4321, "", "sent before the purge")
		local _, why = w.Inject("CHANNEL", B.name, D, inFlight)
		eq(why, "deleted", "in flight")
		w.epoch = w.epoch + 31
		w.Say(B, "A", "after the purge")
		eq(w.Line(D, "A", B.name, "after the purge").del, nil, "his next line shows")
		-- The officer's client repeats it for clients that were away: one heard now takes only what
		-- was written before it.
		local P = w.Sent("MD~1~P~G~")[1].msg
		local late = w.Client("Late", X, 3)
		local list = w.As(late, late.C.RawHistory, "A")
		list[#list + 1] = { t = w.epoch - 40, sender = B.name, guild = X, text = "kept while away", id = 77 }
		list[#list + 1] = { t = w.epoch, sender = B.name, guild = X, text = "after the purge", id = 78 }
		w.Inject("GUILD", A.name, late, P)
		eq(w.Line(late, "A", B.name, "kept while away"), nil, "the line it kept while away is deleted")
		assert(w.Line(late, "A", B.name, "after the purge"), "his later line is not")
		eq(oldLine.del, nil)
	end)
end)

test("watch: chat moderation: late joiners never get the words; one away within two hours gets the repeat, after that its copy stays (the stated limit)", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "say it once")
		D.online = false
		local e = w.Line(A, "A", B.name, "say it once")
		assert(w.As(A, A.WC.Delete, "A", e, ""))
		w.Run()
		eq(w.Line(D, "A", B.name, "say it once").del, nil, "away: not yet")
		-- A new client: there is no backlog in Olympus, nothing to receive.
		local new = w.Client("Newcomer", X, 3)
		eq(#w.As(new, new.C.RawHistory, "A"), 0, "a late joiner has no copy of it")
		-- D back within the repeat window: the officer's client repeats it (DELETE_REPEAT_EVERY).
		D.online = true
		w.epoch = w.epoch + A.WC.DELETE_REPEAT_EVERY
		w.As(A, A.WC.Tick)
		w.Run()
		eq(w.Line(D, "A", B.name).del, true, "replaced in the history D kept")
		-- Past DELETE_REPEAT_FOR the actor's client stops repeating it.
		w.epoch = w.epoch + A.WC.DELETE_REPEAT_FOR + 1
		local before = #w.Sent("MD~1~D~")
		w.As(A, A.WC.Tick)
		w.Run()
		eq(#w.Sent("MD~1~D~"), before, "no repeat past two hours")
	end)
end)

test("watch: chat moderation: from a report: a case's evidence line is found by its words on clients that never shared an id", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "reported words here")
		-- (History saved before 1.1.6 has no ids: D's copy loses its id.)
		w.Line(D, "A", B.name, "reported words here").id = nil
		local evidence = w.As(A, A.W.Evidence, B.name)
		eq(#evidence, 1)
		assert(w.As(A, A.WC.DeleteReported, B.name, evidence, "reported"))
		w.Run()
		eq(w.Line(D, "A", B.name).del, true, "deleted by its words")
		eq(#w.As(A, A.W.Evidence, B.name), 0, "a deleted line is never evidence again")
	end)
end)

test("watch: chat moderation: the game's chat window: the printed line replaced on its frame, never a look-alike, the combat log, Chattynator, a secret, with the switch off or under the gamepad UI", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "printed line")
		w.Say(D, "A", "printed line")
		local function Text(cl, i) return cl.frame.lines[i] and cl.frame.lines[i].message end
		local n = #Y1.frame.lines
		assert(Text(Y1, n - 1):find("printed line", 1, true))
		assert(w.As(A, A.WC.Delete, "A", w.Line(A, "A", B.name, "printed line"), ""))
		w.Run()
		assert(Text(Y1, n - 1):find(ns.L.WATCHCHAT_DELETED, 1, true), Text(Y1, n - 1))
		assert(not Text(Y1, n - 1):find("printed line", 1, true), "the words are gone from the game's window")
		assert(Text(Y1, n - 1):find("|Hplayer:", 1, true), "the name stays a player link")
		assert(Text(Y1, n):find("printed line", 1, true), "D's look-alike stays")
		-- The combat log, a Chattynator tab: never asked.
		local combat = Frame({ combat = true })
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 900, "x", combat, "line", "gone")
		w.As(D, D.WC.ReplacePrinted, "A", B.name, 900, D.WC.Hash("x"))
		eq(combat.calls, 0, "never the combat log")
		-- A secret value is skipped without error.
		local f = Frame()
		f:AddMessage("secret", 1, 1, 1)
		w.secret = "secret"
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 901, "y", f, "secret", "gone")
		w.As(D, D.WC.ReplacePrinted, "A", B.name, 901, D.WC.Hash("y"))
		eq(f.lines[1].message, "secret", "a secret is never compared or changed")
		w.secret = nil
		-- The kill switch and the gamepad UI: nothing of the game's is touched.
		local g = Frame()
		g:AddMessage("line", 1, 1, 1)
		D.WC.GAME_CHAT = false
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 902, "z", g, "line", "gone")
		eq(w.As(D, D.WC.ReplacePrinted, "A", B.name, 902, D.WC.Hash("z")), 0)
		D.WC.GAME_CHAT = true
		w.gamepad = true
		w.As(D, D.WC.NotePrinted, "A", B.name, X, 903, "z", g, "line", "gone")
		eq(w.As(D, D.WC.ReplacePrinted, "A", B.name, 903, D.WC.Hash("z")), 0)
		eq(g.calls, 0, "under the gamepad UI, never")
		w.gamepad = nil
		-- The code says so where it is read.
		local src = assert(io.open(ROOT .. "Olympus/WatchChat.lua", "rb")):read("*a")
		assert(src:find("the game's chat window keeps what it already showed", 1, true))
		assert(not src:find("StaticPopup_Show", 1, true), "every dialog goes through ns.ShowDialog")
	end)
end)

---------------------------------------------------------------------------
-- Timeouts
---------------------------------------------------------------------------

test("watch: chat moderation: a timeout drops his lines on every client; his own client refuses and tells him the role, until when and why, once a minute", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local ok, scope = w.As(A, A.WC.Timeout, B.name, 1800, "spam")
		eq(ok, true); eq(scope, "G")
		w.Run()
		-- B's own client: the pop-up names the role, never the officer.
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT")
		assert(d, "told in an Olympus pop-up")
		assert(d.a:find(ns.L.WATCHCHAT_ROLE_ANY, 1, true), d.a)
		assert(d.a:find("spam", 1, true) and d.a:find(date("%H:%M", w.epoch + 1800), 1, true), d.a)
		assert(not d.a:find("Officer", 1, true), "never the name")
		-- He cannot send: Channels and the rooms refuse, nothing is queued.
		local dialogs = #B.dialogs
		local wire = #w.wire
		eq(select(2, w.As(B, B.C.Send, "A", "let me talk")), "timeout")
		eq(select(2, w.As(B, B.R.Send, "guild", "let me talk")), "timeout")
		eq(#w.wire, wire, "nothing queued")
		eq(#B.dialogs, dialogs, "the pop-up again only once a minute: a line in between")
		assert(w.Printed(B, date("%H:%M", w.epoch + 1800)))
		w.epoch = w.epoch + 61
		w.As(B, B.C.Send, "A", "again")
		eq(#B.dialogs, dialogs + 1, "a minute later, the pop-up again")
		-- Abroad (Y1) through his own word on the channel; his guildmates through the action.
		local line = ns.Codec.EncodeChat("A", X, 55, "", "a line from a modified client")
		for _, cl in ipairs({ G, A, D, Y1 }) do
			local _, why = w.Inject("CHANNEL", B.name, cl, line)
			eq(why, "timeout", "dropped on " .. cl.short)
		end
		local room = ("M2~1~guild~12~~%s~in the room"):format(X)
		local _, why = w.Inject("GUILD", B.name, D, room)
		eq(why, "timeout", "a room's line too")
		-- Others still show.
		w.Say(D, "A", "still here")
		assert(w.Line(Y1, "A", D.name, "still here"))
	end)
end)

test("watch: chat moderation: a part still queued when the timeout comes never leaves; a linked alt is covered", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.epoch = w.epoch + 2
		assert(w.As(B, B.C.Send, "A", "queued before"))
		local queued = table.remove(w.wire) -- held back: the timeout comes first
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		w.wire[#w.wire + 1] = queued
		w.Run()
		eq(#w.Sent("M1~"), 0, "the part never left")
		-- A name his player linked (confirmed on both): covered too.
		w.links[Fold(B.name)] = { "Memberalt-Realm" }
		w.links[Fold("Memberalt-Realm")] = { B.name }
		w.SetRank("Memberalt", Y, 3)
		local _, why = w.Inject("CHANNEL", "Memberalt-Realm", D, ns.Codec.EncodeChat("A", Y, 66, "", "from the alt"))
		eq(why, "timeout")
	end)
end)

test("watch: chat moderation: expiry and early lift; a Watcher's lift never lifts a council timeout; a late repeat of a lifted one stays lifted; until-lifted lapses after 30 days", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		local T = w.Sent("MD~1~T~G~")[1].msg
		eq(w.As(D, D.WC.Silenced, B.name), true)
		w.epoch = w.epoch + 301
		eq(w.As(D, D.WC.Silenced, B.name), false, "a second after its end")
		eq(w.As(B, B.WC.SelfTimeout), nil)
		-- An early lift by another Watcher of the guild (G).
		assert(w.As(A, A.WC.Timeout, B.name, 1800, ""))
		w.Run()
		local T2 = w.Sent("MD~1~T~G~")
		T2 = T2[#T2].msg
		eq(w.As(B, B.WC.SelfTimeout) ~= nil, true)
		w.epoch = w.epoch + 5
		assert(w.As(G, G.WC.Lift, B.name, "sorry"))
		w.Run()
		eq(w.As(B, B.WC.SelfTimeout), nil, "lifted")
		eq(w.As(D, D.WC.Silenced, B.name), false)
		assert(w.Printed(B, ns.L.WATCHCHAT_LIFTED_YOU:format(ns.L.WATCHCHAT_ROLE_ANY)))
		-- A late repeat of the lifted one does not bring it back.
		w.Inject("GUILD", A.name, D, T2)
		eq(w.As(D, D.WC.Silenced, B.name), false, "a late repeat stays lifted")
		-- The author's timeout, and a Watcher's lift.
		w.author = "Author-Realm"
		local Au = w.Client("Author", Y, 3)
		assert(w.As(Au, Au.WC.Timeout, B.name, 0, "while his case is decided"))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true)
		local okLift, whyLift = w.As(A, A.WC.Lift, B.name, "")
		eq(okLift, false); eq(whyLift, "rank", "a Watcher never lifts the author's")
		eq(w.As(B, B.WC.SelfTimeout).untilAt, 0, "until lifted")
		w.epoch = w.epoch + B.WC.HOLD_MAX + 1
		eq(w.As(B, B.WC.SelfTimeout), nil, "until lifted lapses after 30 days")
		eq(T ~= nil, true)
	end)
end)

test("watch: chat moderation: the giver repeats a timeout for late logins; another Watcher passes it on while both qualify, never once the giver is demoted", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, ""))
		w.Run()
		local n = #w.Sent("MD~1~T~G~")
		w.epoch = w.epoch + A.WC.REPEAT
		w.As(A, A.WC.Tick)
		w.Run()
		eq(#w.Sent("MD~1~T~G~"), n + 1, "repeated every REPEAT (plus its own jitter)")
		-- A goes quiet; G (a Watcher too) passes it on with by = A.
		A.online = false
		w.epoch = w.epoch + G.WC.PASS_ON_AFTER + 1
		w.As(G, G.WC.Tick)
		w.Run()
		local passed = w.Sent("MD~1~T~G~")
		passed = passed[#passed]
		eq(passed.from, G.name)
		assert(passed.msg:find("~" .. A.name .. "~", 1, true), "by: the original actor")
		-- A late login hears it.
		local late = w.Client("Latecomer", X, 3)
		w.Inject("GUILD", G.name, late, passed.msg)
		eq(w.As(late, late.WC.Silenced, B.name), true)
		-- A demoted: G's pass-on is refused.
		local later = w.Client("Later", X, 3)
		w.SetRank(A.name, X, 3)
		local ok, why = w.Inject("GUILD", G.name, later, passed.msg)
		eq(ok, false); eq(why, "actor", "the original actor no longer qualifies")
	end)
end)

---------------------------------------------------------------------------
-- Who may act
---------------------------------------------------------------------------

test("watch: chat moderation: a Watcher only in his own guild: over GUILD, on a member of the receiver's roster, the guild named his own", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local okY, whyY = w.As(A, A.WC.Timeout, Y1.name, 300, "")
		eq(okY, false, "a Watcher never acts on another guild's member")
		-- Forged by hand.
		local function Wire(scope, guild, target)
			return ("MD~1~T~%s~%d~%d~%s~%s~%d~-~-~"):format(scope, 900, w.epoch, guild, target, w.epoch + 300)
		end
		local ok, why = w.Inject("CHANNEL", A.name, Y1, Wire("G", X, Y1.name))
		eq(why, "lane", "a guild action never on the channel")
		ok, why = w.Inject("GUILD", A.name, D, Wire("G", Y, B.name))
		eq(why, "guild", "not the receiver's guild")
		ok, why = w.Inject("GUILD", A.name, D, Wire("G", X, "Nobody-Realm"))
		eq(why, "member", "not in the receiver's roster")
		ok, why = w.Inject("GUILD", A.name, D, Wire("O", X, B.name))
		eq(why, "lane", "an Olympus action never over guild")
		ok = w.Inject("GUILD", A.name, D, Wire("G", X, B.name))
		eq(ok, true, "his own guild's member")
	end)
end)

test("watch: chat moderation: the council, the King and the author anywhere; never upward, never on himself, never through a linked alt, never while sanctioned", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.author, w.king = "Author-Realm", "Kingly-Realm"
		w.council[Fold("Councillor-Realm")] = true
		w.council[Fold("Peer-Realm")] = true
		w.stewards[Fold("Steward-Realm")] = true
		w.hands[Fold("Hand-Realm")] = true
		local K = w.Client("Kingly", "Olympus", 0)
		local Co = w.Client("Councillor", Y, 3)
		local Au = w.Client("Author", Y, 2)
		local Pe = w.Client("Peer", X, 3)
		local St = w.Client("Steward", "Olympus", 2)
		local Ha = w.Client("Hand", Y, 3)
		local function May(actor, target)
			local scope = w.As(actor, actor.WC.CanModerate, target)
			return scope
		end
		-- Anywhere: the councillor (guild Y) on B (guild X), the King, the author.
		eq(May(Co, B.name), "O"); eq(May(K, B.name), "O"); eq(May(Au, B.name), "O")
		eq(May(Co, G.name), "O", "a councillor on a guild master")
		-- Never upward or across.
		eq(May(Co, Pe.name), nil, "councillor on councillor")
		eq(May(Co, Ha.name), nil, "councillor on a Hand")
		eq(May(Co, St.name), nil, "councillor on a Steward")
		eq(May(Co, K.name), nil, "councillor on the King")
		eq(May(K, Au.name), nil, "the King on the author")
		eq(May(Au, K.name), "O", "the author on the King")
		eq(May(Co, Co.name), nil, "on himself")
		eq(May(A, G.name), nil, "a Watcher on the guild master")
		w.SetRank("Officer2", X, 1)
		eq(May(A, "Officer2-Realm"), nil, "an officer on an officer of his rank")
		-- Through a linked alt: B's alt is a councillor.
		w.links[Fold(D.name)] = { "Peer-Realm" }
		eq(May(A, D.name), nil, "a protected player through his linked alt")
		w.links[Fold(D.name)] = nil
		-- Sanctioned: a net-off'd councillor gives nothing, and his client sends no MD (BLOCKED).
		w.off[Fold(Co.name)] = { by = "x" }
		eq(May(Co, B.name), nil)
		w.off[Fold(Co.name)] = nil
		local src = assert(io.open(ROOT .. "Olympus/Moderation.lua", "rb")):read("*a")
		assert(src:find("MW = true, MR = true, MD = true", 1, true), "Moderation.BLOCKED.MD")
		-- An Olympus-scope action by the councillor reaches every guild.
		assert(w.As(Co, Co.WC.Timeout, B.name, 300, "flood"))
		w.Run()
		for _, cl in ipairs({ G, A, D, Y1 }) do eq(w.As(cl, cl.WC.Silenced, B.name), true, "on " .. cl.short) end
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT")
		assert(d.a:find(ns.L.WATCHCHAT_ROLE_ANY, 1, true), d.a)
	end)
end)

test("watch: chat moderation: forged and malformed actions are refused; a replay is applied once; a flood is cut", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local function Wire(op, arg, refs, by, at, reason)
			return ("MD~1~%s~G~%d~%d~%s~%s~%s~%s~%s~%s"):format(op, 777, at or w.epoch, X, B.name, arg or "-", refs or "-", by or "-", reason or "")
		end
		-- The stamped sender is no Watcher.
		local ok, why = w.Inject("GUILD", D.name, G, Wire("T", w.epoch + 300))
		eq(why, "actor")
		-- by names someone who could not give it.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300, "-", D.name))
		eq(why, "actor", "the original actor no Watcher")
		ok, why = w.Inject("GUILD", A.name, G, Wire("D", "-", "A.1." .. G.WC.Hash("x"), D.name))
		eq(why, "by", "a deletion is never passed on")
		-- Unlogged; oversized; malformed refs; more than 3 refs.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300), false)
		eq(why, "unlogged")
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300) .. string.rep("x", 255))
		eq(why, "size")
		ok, why = w.Inject("GUILD", A.name, G, Wire("D", "-", "A.1.zz"))
		eq(why, "refs")
		local h = G.WC.Hash("x")
		ok, why = w.Inject("GUILD", A.name, G, Wire("D", "-", ("A.1.%s,A.2.%s,A.3.%s,A.4.%s"):format(h, h, h, h)))
		eq(why, "refs", "4 refs")
		-- Durations: untilAt at or before at, past the 7 days; at more than 60 s ahead.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch))
		eq(why, "duration")
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + G.WC.MAX_TIMEOUT + 1))
		eq(why, "duration", "past the ladder's 7 days")
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 400, "-", "-", w.epoch + 61))
		eq(why, "time")
		-- A reason that is not clean.
		ok, why = w.Inject("GUILD", A.name, G, Wire("T", w.epoch + 300, "-", "-", nil, "a|cffff0000red"))
		eq(why, "reason")
		-- A target's own word naming someone else's line touches his own lines alone.
		w.Say(D, "A", "D's own words")
		local S = ("MD~1~S~D~5~%d~%s~%s~-~A.-.%s~"):format(w.epoch, X, A.name, G.WC.Hash("D's own words"))
		w.Inject("CHANNEL", B.name, Y1, S)
		eq(w.Line(Y1, "A", D.name, "D's own words").del, nil, "B can never withdraw D's line")
		-- A replay applies once.
		local good = Wire("T", w.epoch + 300)
		eq(w.Inject("GUILD", A.name, G, good), true)
		local _, again = w.Inject("GUILD", A.name, G, good)
		eq(again, "repeat")
		-- More than 10 a minute from one sender: dropped.
		local dropped = 0
		for i = 1, 12 do
			local _, r = w.Inject("GUILD", A.name, D, ("MD~1~T~G~%d~%d~%s~%s~%d~-~-~"):format(1000 + i, w.epoch, X, B.name, w.epoch + 300))
			if r == "rate" then dropped = dropped + 1 end
		end
		assert(dropped >= 1, "rate-limited")
	end)
end)

---------------------------------------------------------------------------
-- Watchers and Olympus moderators
---------------------------------------------------------------------------

test("watch: chat moderation (1.2.1): a full action replay history makes room: the actor's own oldest floor goes under a watermark, its replay stays refused, and moderation never stops", function()
	World(function(w)
		local G, A, B, D = Standard(w)
		A.WC.APPLIED_MAX = 2
		assert(w.As(A, A.WC.Purge, B.name, "first")); w.Run()
		w.epoch = w.epoch + 61
		assert(w.As(A, A.WC.Purge, B.name, "second")); w.Run()
		local s = A.WC.Store()
		w.epoch = w.epoch + 61
		local ok, why = w.As(A, A.WC.Purge, B.name, "third")
		eq(ok, true, "a full history no longer refuses a new action: " .. tostring(why)); w.Run()
		local n = 0
		for _ in pairs(s.applied) do n = n + 1 end
		eq(n, 2, "still within the cap")
		D.WC.APPLIED_MAX = 1
		local function Wire(seq, at)
			return ("MD~1~P~G~%d~%d~%s~%s~60~-~-~"):format(seq, at, X, B.name)
		end
		w.epoch = w.epoch + 61
		local newer = w.epoch
		eq(w.Inject("GUILD", A.name, D, Wire(900, newer)), true, "a newer action is taken on a full history")
		w.epoch = w.epoch + 61
		eq(w.Inject("GUILD", A.name, D, Wire(901, w.epoch)), true, "and the next one")
		eq(select(2, w.Inject("GUILD", A.name, D, Wire(900, newer))), "old", "the forgotten one's replay is refused")
	end)
end)

test("watch: chat moderation: self testimony has a separate bounded replay history and cannot crowd moderator actions", function()
	World(function(w)
		local G, A, B, D = Standard(w)
		D.WC.SELF_APPLIED_MAX, D.WC.APPLIED_MAX = 2, 1
		local function Word(seq)
			return ("MD~1~S~U~%d~%d~%s~%s~-~-~"):format(seq, w.epoch, X, A.name)
		end
		local first = Word(901)
		eq(w.Inject("CHANNEL", B.name, D, first), true)
		w.epoch = w.epoch + 61
		eq(w.Inject("CHANNEL", B.name, D, Word(902)), true)
		w.epoch = w.epoch + 61
		local before = #D.WC.Store().audit
		eq(select(2, w.Inject("CHANNEL", B.name, D, Word(903))), "full")
		eq(#D.WC.Store().audit, before)
		w.epoch = w.epoch + 61
		eq(select(2, w.Inject("CHANNEL", B.name, D, first)), "repeat")
		local timeout = ("MD~1~T~G~%d~%d~%s~%s~%d~-~-~"):format(904, w.epoch, X, B.name, w.epoch + 300)
		eq(w.Inject("GUILD", A.name, D, timeout), true, "self messages did not consume the moderator's room")
		eq(w.As(D, D.WC.Silenced, B.name), true)
		local n = 0; for _ in pairs(D.WC.Store().selfApplied) do n = n + 1 end
		eq(n, 2)
		w.epoch = w.epoch + D.WC.KEEP + 1
		w.As(D, D.WC.Prune)
		eq(next(D.WC.Store().selfApplied), nil); eq(next(D.WC.Store().applied), nil)
		eq(select(2, w.Inject("CHANNEL", B.name, D, first)), "time", "expired packets cannot reuse released space")
		w.epoch = w.epoch + 61
		eq(w.Inject("CHANNEL", B.name, D, Word(905)), true)
	end)
end)

test("watch: chat moderation: legacy mixed replay history migrates without forgetting self floors, including an already oversized saved map", function()
	World(function(w)
		local G, A, B, D = Standard(w)
		local s = D.WC.Store()
		local key1 = "S#" .. Fold(B.name) .. "#" .. Fold(A.name) .. "#906"
		local key2 = "S#" .. Fold(B.name) .. "#" .. Fold(A.name) .. "#907"
		s.applied, s.selfApplied, s.replaySplit = { [key1] = w.epoch, [key2] = w.epoch, ["moderator#1"] = w.epoch }, nil, nil
		w.As(D, function() assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", D.ns) end)
		D.WC = D.ns.WatchChat
		D.WC.SELF_APPLIED_MAX = 1
		s = D.WC.Store()
		eq(s.applied[key1], nil); eq(s.applied["moderator#1"], w.epoch)
		eq(s.selfApplied[key1], w.epoch); eq(s.selfApplied[key2], w.epoch, "live legacy floors are retained, not truncated")
		local function Word(seq)
			return ("MD~1~S~U~%d~%d~%s~%s~-~-~"):format(seq, w.epoch, X, A.name)
		end
		eq(select(2, w.Inject("CHANNEL", B.name, D, Word(906))), "repeat")
		w.epoch = w.epoch + 61
		eq(select(2, w.Inject("CHANNEL", B.name, D, Word(908))), "full")
		D.ns.rdb = { guilds = {} }
		eq(w.Inject("CHANNEL", B.name, D, Word(908)), true, "a different realm's store initializes its own migration")
	end)
end)

test("watch: chat moderation: the guild master names and removes Watchers; only his list counts, while he is the guild master", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(w.As(D, D.W.IsAuthorized, B.name), false, "a member is no Watcher")
		local ok, why = w.As(A, A.WC.SetWatcher, B.name, true)
		eq(ok, false); eq(why, "gm", "an officer names nobody")
		assert(w.As(G, G.WC.SetWatcher, B.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		local Wmsg = w.Sent("MD~1~W~")
		eq(#Wmsg, 1); eq(Wmsg[1].dist, "GUILD")
		eq(w.As(D, D.W.IsAuthorized, B.name), true, "a named Watcher has The Watch")
		eq(w.As(D, D.WC.IsNamedWatcher, B.name), true)
		-- He acts on a member below him, never on an officer.
		eq(w.As(B, B.WC.CanModerate, D.name), "G")
		eq(w.As(B, B.WC.CanModerate, A.name), nil, "a named Watcher never on an officer")
		-- An officer relaying the list: refused.
		local relay = Wmsg[1].msg
		local _, rwhy = w.Inject("GUILD", A.name, D, relay)
		eq(rwhy, "rank", "only the guild master's own client")
		-- More than 10: refused.
		local names = {}
		for i = 1, 11 do names[i] = "Name" .. i .. "-Realm" end
		local _, fwhy = w.Inject("GUILD", G.name, D, ("MD~1~W~%d~%s~1~1~-~%s"):format(w.epoch + 1, X, table.concat(names, ",")))
		eq(fwhy, "full")
		-- Removed: the newer list without him.
		assert(w.As(G, G.WC.SetWatcher, B.name, false))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(D, D.W.IsAuthorized, B.name), false, "removed")
		-- A new guild master: the old list counts for nobody.
		assert(w.As(G, G.WC.SetWatcher, B.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(D, D.WC.IsNamedWatcher, B.name), true)
		w.SetRank(G.name, X, 1); w.SetRank(A.name, X, 0)
		eq(w.As(D, D.WC.IsNamedWatcher, B.name), false, "rank 0 is another character now")
		w.SetRank(A.name, X, 1); w.SetRank(G.name, X, 0)
		-- He leaves the guild: no Watcher.
		w.SetRank(B.name, Y, 3)
		eq(w.As(D, D.WC.CanModerate, D.name), nil)
		eq(w.As(D, D.W.IsAuthorized, B.name), false, "out of the roster")
		-- The Justice correspondent counts as a Watcher, and applies the King's judgment.
		w.SetRank(B.name, X, 3)
		assert(w.As(G, G.WC.SetWatcher, D.name, true, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(A, A.WC.Justice), D.name)
		eq(w.As(A, A.W.IsAuthorized, D.name), true)
		eq(w.As(D, D.WC.MayApplyJudgment), true)
		eq(w.As(A, A.WC.MayApplyJudgment), false, "another officer does not")
	end)
end)

test("watch: chat moderation: Olympus moderators: a councillor's list counts while fresh and while he is a councillor; never another's list", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local Mo = w.Client("Modder", Y, 3)
		assert(w.As(Co, Co.WC.SetMod, Mo.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(#w.Sent("MD~1~O~"), 1)
		eq(w.As(D, D.WC.IsMod, Mo.name), true)
		eq(w.As(Mo, Mo.WC.CanModerate, B.name), "O", "anywhere")
		-- (1.2.3) On another guild's master too: no guild master stands above the Olympus moderators
		-- now but the King's guild's (tested below).
		eq(w.As(Mo, Mo.WC.CanModerate, G.name), "O", "on another guild's master")
		eq(w.As(Mo, Mo.WC.CanModerate, Co.name), nil, "never on his namer")
		-- A namer never changes another's list: Y1's word for Mo's list is not a namer's.
		local _, why = w.Inject("CHANNEL", Y1.name, D, ("MD~1~O~%d~1~1~"):format(w.epoch + 5))
		eq(why, "namer")
		eq(w.As(D, D.WC.IsMod, Mo.name), true)
		-- Lapses 20 minutes after its last repeat.
		w.epoch = w.epoch + D.WC.LIST_FRESH + 1
		eq(w.As(D, D.WC.IsMod, Mo.name), false, "stale")
		w.As(Co, Co.WC.SendMods, true)
		w.Run()
		eq(w.As(D, D.WC.IsMod, Mo.name), true, "repeated")
		-- At once when the namer leaves the council.
		w.council[Fold(Co.name)] = nil
		eq(w.As(D, D.WC.IsMod, Mo.name), false, "his title gone")
	end)
end)

-- (1.2.3, Daniel: a guild master has nothing at the level of the whole army.) Every guild master
-- the client could name, from its roster, the signed list or the census, stood with the Olympus
-- moderators (WatchChat.ProtectLevel 3): no moderator could delete his lines or time him out
-- anywhere, and two cooperating characters could make one of theirs the census guild master of an
-- invented guild to shield him. Now only the King's guild's master stands there.
test("watch: chat moderation: Olympus moderators act on another guild's master (our roster's, signed or a census one) since 1.2.3, never on the King's guild's master; his own guild's Watchers still never act on him", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local Mo = w.Client("Modder", Y, 3)
		local KM = w.Client("Throne Master", "Olympus", 0)
		local KO = w.Client("Throne Knight", "Olympus", 3)
		local Fake = w.Client("Madeup Master", "Olympus Madeup", 0)
		w.census["Olympus Madeup"] = true -- (its rank is the census's word alone)
		assert(w.As(Co, Co.WC.SetMod, Mo.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(Mo, Mo.WC.IsMod, Mo.name), true)
		local LEVEL = Mo.WC.LEVEL
		-- Another guild's master: protected as his members are, on every client.
		for _, cl in ipairs({ Mo, D, Y1, KO }) do
			eq(w.As(cl, cl.WC.ProtectLevel, G.name), 0, "<" .. G.guild .. ">'s master on " .. cl.short)
			eq(w.As(cl, cl.WC.ProtectLevel, Fake.name), 0, "a census guild master on " .. cl.short)
		end
		eq(w.As(G, G.WC.ProtectLevel, G.name), 0, "on his own client too")
		eq(w.As(Mo, Mo.WC.CanModerate, G.name), "O", "a moderator acts on him")
		eq(w.As(Mo, Mo.WC.CanModerate, Fake.name), "O", "and on a census guild master of an invented guild")
		-- The King's guild's master: as before, on its own members' clients (our roster) and on
		-- every other client.
		eq(w.As(KO, KO.WC.ProtectLevel, KM.name), LEVEL.mod, "on <Olympus>'s own client")
		eq(w.As(Mo, Mo.WC.ProtectLevel, KM.name), LEVEL.mod, "on another guild's client")
		eq(w.As(Mo, Mo.WC.CanModerate, KM.name), nil, "a moderator never acts on him")
		eq(w.As(Co, Co.WC.CanModerate, KM.name), "O", "a councillor does, as before")
		-- His own guild's Watchers never act on another guild's master: its rank order.
		eq(w.As(A, A.WC.CanModerate, G.name), nil, "a Watcher on the guild master")
	end)
	-- The moderators' list says so (English and pt-BR).
	assert(ns.L.WATCHCHAT_MODS_TIP:find("another guild's master included", 1, true), ns.L.WATCHCHAT_MODS_TIP)
	local pt = { L = setmetatable({}, { __index = ns.L }) }
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", pt) end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	assert(rawget(pt.L, "WATCHCHAT_MODS_TIP"):find("no líder de outra guilda também", 1, true), rawget(pt.L, "WATCHCHAT_MODS_TIP"))
end)

---------------------------------------------------------------------------
-- Audit and records
---------------------------------------------------------------------------

test("watch: chat moderation: the audit's audience: the guild's Watch (with the words), the council's page (Olympus actions and confirmed guild ones), the player's own record by role only, nobody else", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		w.Say(B, "A", "the rude words")
		assert(w.As(A, A.WC.Delete, "A", w.Line(A, "A", B.name, "the rude words"), "insult"))
		w.Run()
		-- The guild's Watch (G): its audit, who, whom, what, why, when, and the words.
		local found
		for _, e in ipairs(w.As(G, G.W.Audit)) do if e.op == "D" then found = e end end
		assert(found, "in The Watch's audit")
		eq(found.by, A.name); eq(found.name, B.name); eq(found.reason, "insult"); eq(found.text, "the rude words")
		-- A plain member keeps nothing of it but the deleted line.
		eq(#w.As(D, D.W.Audit), 0, "a member has no audit")
		eq(#D.WC.Store().audit, 0)
		-- The council's client: the guild action his own client confirmed (S).
		local s = Co.WC.Store()
		eq(#s.audit, 1); eq(s.audit[1].scope, "S"); eq(s.audit[1].by, A.name)
		-- The player: his own record, the role only (no name shown).
		local rec = B.WC.Store().record
		eq(#rec, 1); eq(rec[1].role, "G"); eq(rec[1].words, "the rude words")
		local lines = w.As(B, B.WC.RecordLines)
		local text = ""
		for _, l in ipairs(lines) do text = text .. l.text .. "\n" end
		assert(text:find(ns.L.WATCHCHAT_ROLE_ANY, 1, true) and not text:find("Officer", 1, true), text)
		-- Y1 (another guild, no council) keeps no reason.
		eq(#Y1.WC.Store().audit, 0)
		-- On the King's stream (masked) the page hides reasons and words.
		Co.masked = true
		local page = w.As(Co, Co.WC.PageLines)
		for _, l in ipairs(page) do
			if l.tooltip then
				local tt = { lines = {} }
				function tt:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
				l.tooltip(tt)
				local all = table.concat(tt.lines, "\n")
				assert(not all:find("insult", 1, true) and not all:find("the rude words", 1, true), all)
			end
		end
	end)
end)

test("watch: chat moderation: public stream masks timeout targets and moderator names even without the Watch display helper", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.council[Fold("Streamreviewer-Realm")] = true
		local Co = w.Client("Streamreviewer", Y, 3)
		assert(w.As(Co, Co.WC.Timeout, B.name, 300, "private reason")); w.Run()
		local function Render()
			local text = ""
			for _, row in ipairs(w.As(Co, Co.WC.PageLines)) do
				text = text .. (row.text or "") .. "\n"
				if row.tooltip then
					local tt = { AddLine = function(_, line) text = text .. tostring(line) .. "\n" end }
					w.As(Co, row.tooltip, tt)
				end
			end
			return text
		end
		local internal = Render()
		assert(internal:find(Co.short, 1, true) and internal:find(B.short, 1, true), "staff retains provenance")
		Co.masked = true
		local masked = Render()
		assert(not masked:find(B.short, 1, true), "timeout target must be masked on stream: " .. masked)
		Co.W.ShownBy = nil -- partial module/display helper unavailable
		masked = Render()
		assert(not masked:find(Co.short, 1, true) and not masked:find(B.short, 1, true), "fallback must retain masking: " .. masked)
		assert(not masked:find("private reason", 1, true), masked)
	end)
end)

test("watch: chat moderation: affected-player notices use only a generic moderator while staff keeps the actor", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.author = "Author-Realm"
		local Au = w.Client("Author", Y, 3)
		assert(w.As(Au, Au.WC.Timeout, B.name, 300, "please pause")); w.Run()
		local timeout = w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT")
		assert(timeout.a:find(ns.L.WATCHCHAT_ROLE_ANY, 1, true), timeout.a)
		assert(not timeout.a:find(ns.L.WATCHCHAT_ROLE_7, 1, true) and not timeout.a:find("Author", 1, true), timeout.a)
		for _, row in ipairs(w.As(B, B.WC.RecordLines)) do
			assert(not row.text:find(ns.L.WATCHCHAT_ROLE_7, 1, true), row.text)
			if row.tooltip then
				local tt = { AddLine = function(_, line)
					assert(not tostring(line):find("Author", 1, true) and not tostring(line):find(ns.L.WATCHCHAT_ROLE_7, 1, true), line)
				end }
				w.As(B, row.tooltip, tt)
			end
		end
		local record = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, record.by, record.seq, "please review")); w.Run()
		local key = next(Au.WC.Store().appeals)
		assert(key and w.As(Au, Au.WC.Answer, key, "K", "reviewed")); w.Run()
		local decision = w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION")
		assert(decision.a:find(ns.L.WATCHCHAT_ROLE_ANY, 1, true) and not decision.a:find(ns.L.WATCHCHAT_ROLE_7, 1, true), decision.a)
		eq(Au.WC.Store().audit[1].by, Au.name, "staff audit keeps real actor")
		eq(record.by, Au.name, "appeal linkage retains actor privately")
	end)
end)

test("watch: chat moderation: an appeal goes to the High Council; its answer lifts or keeps, and the player is told in a pop-up", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "insult"))
		w.Run()
		local r = B.WC.Store().record[1]
		-- The member's Watch page exposes only their record and its real appeal dialog.
		w.As(B, B.W.Show, "member")
		local rows = w.As(B, B.W.Build)
		local appealRow
		for _, row in ipairs(rows) do if row.tooltip and row.onClick then appealRow = row end end
		assert(appealRow, "own record has an appeal")
		w.As(B, appealRow.onClick)
		local dialog = w.Dialog(B, "OLYMPUS_WATCHCHAT_APPEAL")
		eq(dialog.data.by, r.by); eq(dialog.data.seq, r.seq)
		w.As(D, D.W.Show, "member")
		for _, row in ipairs(w.As(D, D.W.Build)) do
			assert(not (row.tooltip and row.onClick), "another member sees none of this record")
		end
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "I was quoting him"))
		w.Run()
		local key
		for k in pairs(Co.WC.Store().appeals) do key = k end
		assert(key, "kept on the councillor's client")
		eq(next(D.WC.Store().appeals), nil, "never on a member's")
		assert(w.As(Co, Co.WC.Answer, key, "L", "fair"))
		w.Run()
		eq(w.As(B, B.WC.SelfTimeout), nil, "lifted on appeal")
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION")
		assert(d and d.a:find(ns.L.WATCHCHAT_ROLE_ANY, 1, true), d and d.a)
	end)
end)

test("watch: chat moderation: a refused appeal queue admission keeps the player's retry available", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.author = "Author-Realm"
		local Au = w.Client("Author", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 300, "")); w.Run()
		local record = B.WC.Store().record[1]
		local send = B.ns.Comm.Send
		B.ns.Comm.Send = function() return false end
		local ok, why = w.As(B, B.WC.Appeal, record.by, record.seq, "please review")
		eq(ok, false, "a rejected queue is not reported as sent"); eq(why, "queue")
		eq(record.appealed, nil, "a rejected queue does not lock the appeal")
		eq(next(Au.WC.Store().appeals), nil)
		B.ns.Comm.Send = send
		assert(w.As(B, B.WC.Appeal, record.by, record.seq, "please review")); w.Run()
		assert(record.appealed and next(Au.WC.Store().appeals), "retry reaches the real author without ViewAs")
		eq(select(2, w.As(B, B.WC.Appeal, record.by, record.seq, "again")), "already", "an admitted appeal remains single-send")
	end)
end)

test("watch: chat moderation: a real late author gets current target testimony and the player's bounded appeal retry", function()
	World(function(w)
		local G, A, B = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "")); w.Run()
		local record = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, record.by, record.seq, "please review")); w.Run()
		w.author = "Lateauthor-Realm"
		local Au = w.Client("Lateauthor", Y, 3)
		eq(w.As(Au, Au.WC.NamerLevel, Au.name), 7)
		eq(w.As(Au, Au.WC.CouncilSide), true, "real author entitlement does not depend on ViewAs")
		eq(#Au.WC.Store().audit, 0); eq(next(Au.WC.Store().appeals), nil)
		Au.ns.ViewAs = { Available = function() return true end, Role = function() return "king" end,
			Allows = function() return true end, Inert = function(rows) return rows end }
		w.As(Au, Au.WC.PageLines)
		eq(next(Au.WC.Store().appeals), nil, "preview cannot invent a missed appeal")
		w.As(B, B.WC.Tick); w.Run()
		eq(#Au.WC.Store().audit, 1); eq(Au.WC.Store().audit[1].scope, "S", "target's session announcement reaches late author")
		eq(#w.As(Au, Au.W.Audit), 0, "self testimony is not an authenticated guild Watch audit")
		eq(next(Au.WC.Store().appeals), nil, "no retry before the interval")
		w.epoch = w.epoch + 300
		w.As(B, B.WC.Tick); w.Run()
		assert(next(Au.WC.Store().appeals), "own pending appeal reaches a reviewer who logged in later")
	end)
end)

test("watch: chat moderation: pending appeal retry survives reload, keeps its original timestamp and stops on the authenticated answer", function()
	World(function(w)
		local G, A, B = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "")); w.Run()
		local record = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, record.by, record.seq, "please review")); w.Run()
		local at = record.appealed
		w.author = "Lateauthor-Realm"
		local Au = w.Client("Lateauthor", Y, 3)
		w.As(B, function() assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", B.ns) end)
		B.WC = B.ns.WatchChat
		local send = B.ns.Comm.Send
		B.ns.Comm.Send = function(dist, msg, ...) if msg:find("MD~1~A~", 1, true) == 1 then return false end return send(dist, msg, ...) end
		w.epoch = w.epoch + 300
		w.As(B, B.WC.Tick); w.Run()
		eq(next(Au.WC.Store().appeals), nil, "queue rejection did not consume the retry")
		B.ns.Comm.Send = send
		w.As(B, B.WC.Tick); w.Run()
		local key, appeal = next(Au.WC.Store().appeals)
		assert(key, "accepted retry reaches the late author after reload")
		eq(appeal.at, at); eq(appeal.seq, record.seq); eq(appeal.actor, record.by); eq(appeal.text, "please review")
		w.As(B, B.WC.Tick); w.Run()
		local pending = record.pendingAppeal
		assert(pending, "still unanswered")
		eq(select(2, w.Inject("CHANNEL", A.name, B, ("MD~1~R~%d~%s~%s~%d~K~forged"):format(w.epoch, B.name, record.by, record.seq))), "namer")
		eq(record.pendingAppeal, pending, "an unauthorized answer cannot cancel the retry")
		assert(w.As(Au, Au.WC.Answer, key, "K", "reviewed")); w.Run()
		eq(record.pendingAppeal, nil, "authenticated answer clears persisted retry")
		local sent = #w.sent
		w.epoch = w.epoch + 300; w.As(B, B.WC.Tick); w.Run()
		for i = sent + 1, #w.sent do assert(not w.sent[i].msg:find("MD~1~A~", 1, true), "answered appeal never repeated") end
	end)
end)

test("watch: chat moderation: own pending appeals cap at three and replay one per five minutes, never malformed or another character's saved entry", function()
	World(function(w)
		local G, A, B = Standard(w)
		for i = 1, 4 do
			w.Say(B, "A", "line" .. i)
			assert(w.As(A, A.WC.Delete, "A", w.Line(A, "A", B.name, "line" .. i), "")); w.Run()
		end
		local s = B.WC.Store()
		for i = 1, 3 do assert(w.As(B, B.WC.Appeal, s.record[i].by, s.record[i].seq, "review " .. i)) end
		eq(select(2, w.As(B, B.WC.Appeal, s.record[4].by, s.record[4].seq, "review 4")), "full")
		w.Run()
		w.epoch = w.epoch + 300
		w.As(B, B.WC.Tick)
		local n = 0
		for _, job in ipairs(w.wire) do if job.msg:find("MD~1~A~", 1, true) then n = n + 1 end end
		eq(n, 1, "one retry, not the whole inbox")
		w.As(B, B.WC.Tick)
		local nextN = 0
		for _, job in ipairs(w.wire) do if job.msg:find("MD~1~A~", 1, true) then nextN = nextN + 1 end end
		eq(nextN, n, "global five-minute retry limit")
		w.Run()
		w.epoch = w.epoch + 300
		w.As(B, B.WC.Tick)
		local replay
		for _, job in ipairs(w.wire) do if job.msg:find("MD~1~A~", 1, true) then replay = job.msg end end
		assert(replay and replay:find("~" .. s.record[2].seq .. "~D~review 2", 1, true), "the next pending appeal gets its turn")
		w.Run()
		s.record[1].pendingAppeal.name = A.name
		s.record[2].pendingAppeal.text = "bad~wire"
		s.record[3].pendingAppeal.at = w.epoch + B.WC.DATE_AHEAD + 1
		w.epoch = w.epoch + 300
		-- Keep the persisted malformed future value ahead even after the time step.
		s.record[3].pendingAppeal.at = w.epoch + B.WC.DATE_AHEAD + 1
		w.As(B, B.WC.Tick)
		for _, job in ipairs(w.wire) do assert(not job.msg:find("MD~1~A~", 1, true), "invalid saved retry must not leave") end
	end)
end)

test("watch: chat moderation: current own guild timeout testimony repeats for a late council client without its reason, survives reload and retries queue refusal", function()
	World(function(w)
		local G, A, B = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "private guild reason")); w.Run()
		w.As(B, B.WC.Tick); w.Run() -- the old once-session announcement already left
		w.council[Fold("Latecouncil-Realm")] = true
		local Co = w.Client("Latecouncil", Y, 3)
		local timeout = w.As(B, B.WC.SelfTimeout)
		w.epoch = w.epoch + 299; w.As(B, B.WC.Tick); w.Run()
		eq(#Co.WC.Store().audit, 0, "no repeat before five minutes")
		local send = B.ns.Comm.Send
		B.ns.Comm.Send = function(dist, msg, ...) if msg:find("MD~1~S~", 1, true) == 1 then return false end return send(dist, msg, ...) end
		w.epoch = w.epoch + 1; w.As(B, B.WC.Tick); w.Run()
		eq(#Co.WC.Store().audit, 0, "rejected queue did not reach the late reviewer")
		B.ns.Comm.Send = send
		w.As(B, B.WC.Tick)
		local repeated
		for _, job in ipairs(w.wire) do if job.msg:find("MD~1~S~", 1, true) then repeated = job.msg end end
		assert(repeated, "a queue refusal keeps the current timeout announcement retryable")
		assert(not repeated:find("private guild reason", 1, true), "no guild reason on the public lane")
		assert(repeated:find(("MD~1~S~T~%d~%d~"):format(timeout.seq, timeout.at), 1, true), "original sanction identity and date")
		w.Run()
		eq(#Co.WC.Store().audit, 1); eq(Co.WC.Store().audit[1].scope, "S")
		eq(#w.As(Co, Co.W.Audit), 0, "no authenticated Watcher audit is invented")
		w.As(B, function() assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", B.ns) end)
		B.WC = B.ns.WatchChat
		w.As(B, B.WC.Tick)
		for _, job in ipairs(w.wire) do assert(not job.msg:find("MD~1~S~", 1, true), "persisted interval survives reload") end
		-- A second reviewer still rejects unknown/census identity rather than granting it.
		w.council[Fold("Unprovedreviewer-Realm")] = true
		local Un = w.Client("Unprovedreviewer", Y, 3)
		Un.C.VerifiedLevel = function() return 1, false end
		w.epoch = w.epoch + 300; w.As(B, B.WC.Tick); w.Run()
		eq(#Un.WC.Store().audit, 0, "replay does not bypass membership admission")
		assert(w.As(A, A.WC.Lift, B.name, "")); w.Run()
		w.epoch = w.epoch + 300; w.As(B, B.WC.Tick)
		for _, job in ipairs(w.wire) do assert(not job.msg:find("MD~1~S~T~", 1, true), "lifted timeout is not reannounced") end
	end)
end)

test("watch: chat moderation: real paced Comm drops queued own timeout testimony after lift, expiry, replacement, guild or character change", function()
	for _, change in ipairs({ "current", "lift", "expiry", "replacement", "guild", "character" }) do
		World(function(w)
			local _, A, B = Standard(w)
			assert(w.As(A, A.WC.Timeout, B.name, 600, "private guild reason")); w.Run()
			local timeout = w.As(B, B.WC.SelfTimeout)
			local prefix = ("MD~1~S~T~%d~%d~"):format(timeout.seq, timeout.at)
			local native, events, login = {}, {}, nil
			GetChannelName = function() return 7, "OlympusChannel" end
			C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
				SendAddonMessageLogged = function(_, msg, dist)
					native[#native + 1] = { msg = msg, dist = dist }
					return 0
				end }
			w.As(B, function()
				local on, after, register = B.ns.On, B.ns.After, B.ns.RegisterEvent
				B.ns.On = function(event, fn) if event == "LOGIN" then login = fn end end
				B.ns.RegisterEvent = function(event, fn) events[event] = fn end
				B.ns.Moderation.Blocks = function() return false end
				assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", B.ns)
				for kind, handler in pairs(B.handlers) do B.ns.Comm.Handle(kind, handler) end
				B.ns.On, B.ns.After = on, function() end
				assert(login); login(); B.ns.Comm.JoinChannel()
				B.ns.After, B.ns.RegisterEvent = after, register
				-- A later real guild action must arrive through Comm's logged event, not through
				-- the world's old stub flag: the actual receiver owns its logged delivery context.
				B.handlers.MD = function(dist, sender, msg)
					return events.CHAT_MSG_ADDON_LOGGED(B.ns.PREFIX, msg, dist, sender)
				end
			end)
			w.As(B, B.WC.Tick)
			assert(B.ns.Comm.QueueSize() > 0, "actual paced queue admitted the current testimony")
			eq(#native, 0, "not yet a native send")
			if change == "lift" then assert(w.As(A, A.WC.Lift, B.name, "")); w.Run()
			elseif change == "expiry" then w.epoch = w.epoch + 601
			elseif change == "replacement" then
				w.epoch = w.epoch + 1
				assert(w.As(A, A.WC.Timeout, B.name, 900, "new private reason")); w.Run()
			elseif change == "guild" then w.SetRank(B.name, Y, 3)
			elseif change == "character" then B.ns.me = "Anothermember-Realm" end
			for _ = 1, 20 do
				if B.ns.Comm.QueueSize() == 0 then break end
				w.epoch = w.epoch + 2; w.As(B, B.ns.Comm.Pump)
			end
			eq(B.ns.Comm.QueueSize(), 0)
			local sent = 0
			for _, message in ipairs(native) do
				if message.msg:sub(1, #prefix) == prefix then
					sent = sent + 1; eq(message.dist, "CHANNEL")
					assert(not message.msg:find("private guild reason", 1, true), "no private reason in self testimony")
				end
			end
			eq(sent, change == "current" and 1 or 0, change .. ": only the still-current timeout may leave")
		end)
	end
end)

test("watch: chat moderation: the King's word on a case reaches its player in a pop-up, over his guild, once", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.TellCase, B.name, 42, "U"))
		w.Run()
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION")
		assert(d and d.a == ns.L.WATCHCHAT_DECISION_UP, d and d.a)
		eq(w.Dialog(D, "OLYMPUS_WATCHCHAT_DECISION"), nil, "only he is told")
		local n = #B.dialogs
		w.epoch = w.epoch + A.WC.DECISION_EVERY
		w.As(A, A.WC.Tick)
		w.Run()
		eq(#B.dialogs, n, "once")
		local _, why = w.Inject("GUILD", D.name, B, ("MD~1~J~%d~%s~%s~43~D"):format(w.epoch, X, B.name))
		eq(why, "sender", "a member cannot tell him a decision")
	end)
end)

---------------------------------------------------------------------------
-- A sanction is more than the chat
---------------------------------------------------------------------------

test("watch: chat moderation: a sanction bars powers, games, locations and crafting for its window; the wallet only during a hold", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(w.As(B, B.WC.Barred, "games"), nil)
		assert(w.As(A, A.WC.Timeout, B.name, 3600, ""))
		w.Run()
		for _, what in ipairs({ "powers", "games", "locations", "crafting" }) do
			eq(w.As(B, B.WC.Barred, what) ~= nil, true, "his own client: " .. what)
			eq(w.As(D, D.WC.Barred, what, B.name) ~= nil, true, "another's client: " .. what)
		end
		eq(w.As(B, B.WC.Barred, "wallet"), nil, "a timeout freezes no wallet")
		-- A sanctioned officer loses The Watch while it lasts.
		w.author = "Author-Realm"
		local Au = w.Client("Author", Y, 3)
		assert(w.As(Au, Au.WC.Timeout, A.name, 0, "his case"))
		w.Run()
		eq(w.As(A, A.W.IsAuthorized, A.name), false, "no powers")
		eq(w.As(G, G.W.IsAuthorized, A.name), false, "on the others' clients too")
		eq(w.As(A, A.WC.Barred, "wallet") ~= nil, true, "a hold freezes the wallet")
		eq(w.As(A, A.WC.Timeout, D.name, 300, ""), false, "a sanctioned officer moderates nobody")
		-- The other modules ask the same: the King's position, a crafting card, a guildmate's dot.
		local saved = { WatchChat = rawget(ns, "WatchChat"), me = ns.me }
		local ok, err = pcall(function()
			rawset(ns, "WatchChat", D.WC)
			local s = w.As(D, ns.CraftRequests.Barred, B.name)
			eq(s ~= nil, true, "Crafting: his cards and words are dropped")
			eq(select(2, w.As(D, ns.CraftRequests.ReceiveSnapshot, "CHANNEL", B.name, "CQ~2" .. string.rep("~x", 16))), "sanction")
			eq(ns.Positions.Sanctioned(B.name), true, "his position is dropped")
		end)
		rawset(ns, "WatchChat", saved.WatchChat)
		if not ok then error(err, 0) end
		-- A net-off word counts as a sanction too (exile from the addon).
		w.off[Fold(Y1.name)] = { by = "x" }
		eq(w.As(D, D.WC.Barred, "games", Y1.name).kind, "netoff")
	end)
end)

-- (Changed on purpose, the author's decision of 2026-10-19, the chat warnings: the list is
-- ChatStrikes.LIST now (digests, ChatStrikes.lua), and a refused line is a warning: the first pauses
-- his chats 5 minutes, so the room's line right after it is refused as paused, before its words are
-- read (one counted, not two). The counts still keep no words; his own client now keeps the line it
-- refused, 30 days, for the moderation team.)
test("watch: chat moderation: the severe-insult block: nothing is blocked while its approved list is empty; a listed word is refused at send and counted, never in the counts; the sender's own client keeps his struck line 30 days", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(next(B.S.LIST), nil, "shipped empty")
		w.Say(B, "A", "a plainword here")
		assert(w.Line(D, "A", B.name, "a plainword here"))
		w.words = { "plainword" }
		for _, cl in ipairs(w.clients) do List(cl.S, w.words) end
		w.epoch = w.epoch + 2
		eq(select(2, w.As(B, B.C.Send, "A", "a plainword again")), "severe")
		eq(select(2, w.As(B, B.R.Send, "guild", "a plainword again")), "paused", "the first warning pauses his chats")
		eq(#w.wire, 0, "nothing queued")
		local counts, total = w.As(B, B.WC.BlockedCounts, B.name)
		eq(counts.severe, 1); eq(total, 1)
		for _, e in pairs(B.WC.Store().blocked) do eq(e.text, nil, "never the words") end
		local mine = B.S.Store().mine
		eq(#mine, 1); eq(mine[1].text, "a plainword again", "his own client keeps the line it refused")
		eq(w.As(B, B.S.Prune, B.S.Store()), nil)
		w.epoch = w.epoch + B.S.KEEP + 1
		w.As(B, B.S.Prune, B.S.Store())
		eq(#B.S.Store().mine, 0, "for 30 days")
	end)
end)

test("watch: chat moderation: the High Council's ladder: warn, 1 hour, 24 hours, 7 days; a warning's step is a real timeout", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		eq(table.concat(A.W.TIMEOUTS, ","), "0,3600,86400,604800")
		eq(A.W.MAX_TIMEOUT, 604800)
		eq(A.WC.MAX_TIMEOUT, 604800)
		assert(w.As(A, A.W.Warn, B.name, "one"))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), false, "a first warning is a warning")
		w.epoch = w.epoch + 5
		assert(w.As(A, A.W.Warn, B.name, "two"))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true, "the second: a real timeout")
		eq(w.As(B, B.WC.SelfTimeout).untilAt - w.As(B, B.WC.SelfTimeout).at, 3600)
	end)
end)

---------------------------------------------------------------------------
-- The review's findings (2026-10-05): each test fails on the code before its fix
---------------------------------------------------------------------------

test("watch: chat moderation: a timeout passed on weighs its actor's: a moderator never carries, shortens or replaces the King's, and no councillor lifts it anywhere", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.king, w.author = "Kingly-Realm", "Author-Realm"
		w.council[Fold("Councillor-Realm")] = true
		local K = w.Client("Kingly", "Olympus", 0)
		local Co = w.Client("Councillor", Y, 3)
		local Mo = w.Client("Modder", Y, 3)
		local Au = w.Client("Author", Y, 2)
		assert(w.As(Co, Co.WC.SetMod, Mo.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(D, D.WC.IsMod, Mo.name), true, "an Olympus moderator")
		assert(w.As(K, K.WC.Timeout, B.name, 604800, ""))
		w.Run()
		local T = w.Sent("MD~1~T~O~")[1].msg
		local seq = tonumber(T:match("^MD~1~T~O~(%d+)~"))
		eq(select(2, w.As(Mo, Mo.WC.Lift, B.name, "")), "rank", "the moderator may not lift the King's")
		-- His pass-on made up in the King's name: a newer sequence, a minute's end.
		local forged = ("MD~1~T~O~%d~%d~%s~%s~%d~-~%s~"):format(seq + 1, w.epoch, X, B.name, w.epoch + 60, K.name)
		for _, cl in ipairs({ G, D, Y1 }) do
			local ok, why = w.Inject("CHANNEL", Mo.name, cl, forged)
			eq(ok, false, "refused on " .. cl.short); eq(why, "rank", "on " .. cl.short)
		end
		w.epoch = w.epoch + 61
		for _, cl in ipairs({ G, D, Y1 }) do eq(w.As(cl, cl.WC.Silenced, B.name), true, "the King's 7 days stand on " .. cl.short) end
		local _, again = w.Inject("CHANNEL", K.name, D, T)
		eq(again, "repeat", "the King's own repeat is never refused as older")
		-- The King goes quiet: the moderator's client never passes his word on; the author's does.
		K.online = false
		w.epoch = w.epoch + Mo.WC.PASS_ON_AFTER + 1
		local before = #w.sent
		w.As(Mo, Mo.WC.Tick)
		w.Run()
		for i = before + 1, #w.sent do
			assert(not (w.sent[i].from == Mo.name and w.sent[i].msg:find("^MD~1~T~")), "the moderator carried it: " .. w.sent[i].msg)
		end
		w.As(Au, Au.WC.Tick)
		w.Run()
		local passed
		for i = before + 1, #w.sent do
			if w.sent[i].from == Au.name and w.sent[i].msg:find("^MD~1~T~O~") then passed = w.sent[i].msg end
		end
		assert(passed and passed:find("~" .. K.name .. "~", 1, true), "the author carries the King's word")
		-- A councillor whose client hears it only that way holds it with the King's weight: his lift
		-- is refused there as everywhere.
		local Late = w.Client("Latecouncil", Y, 3)
		w.council[Fold(Late.name)] = true
		eq(w.Inject("CHANNEL", Au.name, Late, passed), true)
		eq(w.As(Late, Late.WC.TimeoutOf, B.name).weight, 6, "the King's weight, however it came")
		eq(select(2, w.As(Late, Late.WC.Lift, B.name, "")), "rank")
	end)
end)

test("watch: chat moderation: an appeal's lift reaches a timeout the councillor's client never held; the player is never told lifted while still timed out", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "insult"))
		w.Run()
		-- The councillor logs in later: his client never heard it (B's own word went once).
		local Co = w.Client("Councillor", Y, 3)
		eq(w.As(Co, Co.WC.TimeoutOf, B.name), nil)
		local r = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "I was quoting him"))
		w.Run()
		local key
		for k in pairs(Co.WC.Store().appeals) do key = k end
		assert(key, "the appeal reached him")
		local lifts = #w.Sent("MD~1~U~O~")
		assert(w.As(Co, Co.WC.Answer, key, "L", "fair"))
		w.Run()
		eq(#w.Sent("MD~1~U~O~"), lifts + 1, "his lift went out")
		eq(w.As(B, B.WC.SelfTimeout), nil, "lifted on the player's own client")
		eq(w.As(D, D.WC.Silenced, B.name), false, "and on his guildmates'")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a,
			ns.L.WATCHCHAT_APPEAL_LIFTED_YOU:format(ns.L.WATCHCHAT_ROLE_ANY, ns.L.WATCHCHAT_REASON_PART:format("fair")))
		-- One from higher up (the King's, which the councillor's client never heard): his lift
		-- does not reach it, and the player is told so.
		w.king = "Kingly-Realm"
		local K = w.Client("Kingly", "Olympus", 0)
		Co.online = false
		w.epoch = w.epoch + 5
		assert(w.As(K, K.WC.Timeout, B.name, 3600, ""))
		w.Run()
		Co.online = true
		local rec = B.WC.Store().record
		local r2 = rec[#rec]
		eq(r2.by, K.name)
		assert(w.As(B, B.WC.Appeal, r2.by, r2.seq, "again"))
		w.Run()
		local key2
		for k, e in pairs(Co.WC.Store().appeals) do if e.seq == r2.seq then key2 = k end end
		assert(w.As(Co, Co.WC.Answer, key2, "L", ""))
		w.Run()
		local still = w.As(B, B.WC.SelfTimeout)
		assert(still and still.by == K.name, "still timed out by the King")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a,
			ns.L.WATCHCHAT_APPEAL_LIFTED_STILL:format(ns.L.WATCHCHAT_ROLE_ANY, "", w.As(B, B.WC.TimeoutText, still)))
		-- An appeal on a deleted line: "found for him", never a lift of anything.
		assert(w.As(K, K.WC.Lift, B.name, ""))
		w.Run()
		w.Say(B, "A", "a deleted one")
		assert(w.As(A, A.WC.Delete, "A", w.Line(A, "A", B.name, "a deleted one"), ""))
		w.Run()
		local r3 = rec[#rec]
		eq(r3.op, "D")
		w.epoch = w.epoch + 61 -- (two appeals a minute from one player at most)
		assert(w.As(B, B.WC.Appeal, r3.by, r3.seq, "it was a joke"))
		w.Run()
		local key3
		for k, e in pairs(Co.WC.Store().appeals) do if e.seq == r3.seq then key3 = k end end
		local n = #w.Sent("MD~1~U~")
		assert(w.As(Co, Co.WC.Answer, key3, "L", ""))
		w.Run()
		eq(#w.Sent("MD~1~U~"), n, "no lift for a deleted line")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a, ns.L.WATCHCHAT_APPEAL_GRANTED_YOU:format(ns.L.WATCHCHAT_ROLE_ANY, ""))
	end)
end)

test("watch: chat moderation: the desk's reason stays the desk's: the ladder's timeout goes without it, and the player's own word on the channel never carries a reason", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local private = "reported by Other for harassment"
		assert(w.As(A, A.W.Warn, B.name, private))
		w.Run()
		w.epoch = w.epoch + 5
		assert(w.As(A, A.W.Warn, B.name, private))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true, "the step's timeout")
		eq(w.As(Y1, Y1.WC.Silenced, B.name), true, "abroad too, through his own word")
		for _, s in ipairs(w.sent) do
			if s.dist == "GUILD" or s.dist == "CHANNEL" then assert(not s.msg:find("harassment", 1, true), s.dist .. ": " .. s.msg) end
		end
		-- A chat moderator's own reason: to the guild's clients and the player, never on the channel.
		w.epoch = w.epoch + 5
		assert(w.As(A, A.WC.Timeout, D.name, 300, "spam"))
		w.Run()
		local S = w.Sent("MD~1~S~T~")
		eq(S[#S].from, D.name)
		eq(S[#S].msg:match("~([^~]*)$"), "", "no reason on the channel")
		assert(w.Dialog(D, "OLYMPUS_WATCHCHAT_TIMED_OUT").a:find("spam", 1, true), "the player is told it")
	end)
end)

test("watch: chat moderation: a player's own word never writes his guild's audit: the officer it names is only his claim", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local forged = ("MD~1~S~T~12345~%d~%s~%s~%d~-~forged reason"):format(w.epoch, X, A.name, w.epoch + 600)
		for _, cl in ipairs({ G, D, Co, Y1 }) do w.Inject("CHANNEL", B.name, cl, forged) end
		for _, e in ipairs(w.As(G, G.W.Audit)) do
			assert(not (e.op == "T" and e.by == A.name), "in the guild's audit: " .. tostring(e.reason))
		end
		eq(#w.As(G, G.W.Audit), 0, "the guild master's audit holds nothing")
		-- The council keeps it as his own client's word, marked so; it restricts only him.
		local s = Co.WC.Store()
		eq(#s.audit, 1); eq(s.audit[1].scope, "S")
		eq(w.As(Y1, Y1.WC.Silenced, B.name), true)
	end)
end)

test("watch: chat moderation: a player's own word (S) counts only from a member of the guild it names, a few each in the council's audit; others never spend its shared budget", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local function Word(seq, guild) return ("MD~1~S~T~%d~%d~%s~%s~%d~-~"):format(seq, w.epoch, guild, A.name, w.epoch + 600) end
		-- Y1 is no member of X: his word framing X's officer is refused on X's own clients (the roster).
		local ok, why = w.Inject("CHANNEL", Y1.name, D, Word(1, X))
		eq(ok, false); eq(why, "guild")
		eq(w.As(D, D.WC.Silenced, Y1.name), false)
		-- Many senders with no standing: the shared budget is left for B's real word.
		for i = 1, 30 do
			for j = 1, 3 do w.Inject("CHANNEL", "Junk" .. i .. "-Realm", D, Word(100 + j, X)) end
		end
		eq(w.Inject("CHANNEL", B.name, D, Word(2, X)), true, "B's own word, after the junk")
		-- One player's own words: five each in the council's audit, nobody else's pushed out.
		eq(w.Inject("CHANNEL", D.name, Co, Word(3, X)), true)
		for i = 1, 8 do w.epoch = w.epoch + 61 w.Inject("CHANNEL", B.name, Co, Word(10 + i, X)) end
		local mine, other = 0, 0
		for _, e in ipairs(Co.WC.Store().audit) do
			if e.scope == "S" and e.name == B.name then mine = mine + 1 elseif e.scope == "S" and e.name == D.name then other = other + 1 end
		end
		eq(mine, Co.WC.SELF_AUDIT_MAX); eq(other, 1, "D's entry stays")
	end)
end)

test("watch: chat moderation: appeals: three open from one player at most; one about a sanction the councillor's client holds is never pushed out by others", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "insult"))
		w.Run()
		local r = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "I was quoting him"))
		w.Run()
		local s = Co.WC.Store()
		local real
		for k, e in pairs(s.appeals) do if e.name == B.name then real = k end end
		assert(real and s.appeals[real].held, "his appeal, about a sanction held here")
		local function Appeal(from, seq)
			return w.Inject("CHANNEL", from, Co, ("MD~1~A~%d~%s~%d~T~please"):format(w.epoch, A.name, seq))
		end
		for i = 1, 3 do w.epoch = w.epoch + 61 eq(Appeal(Y1.name, i), true) end
		w.epoch = w.epoch + 61
		eq(select(2, Appeal(Y1.name, 4)), "full", "a fourth from the same player")
		-- Fifty players with appeals about nothing held here: the real one stays.
		for i = 1, 60 do w.epoch = w.epoch + 1 Appeal("Filer" .. i .. "-Realm", 1) end
		assert(s.appeals[real], "the real appeal is kept")
		local n = 0
		for _ in pairs(s.appeals) do n = n + 1 end
		eq(n, Co.WC.APPEALS_MAX)
	end)
end)

test("watch: chat moderation: appeal admission counts only unresolved requests against a player's quota", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		for i = 1, Co.WC.APPEALS_EACH do
			w.epoch = w.epoch + 61
			assert(w.Inject("CHANNEL", B.name, Co, ("MD~1~A~%d~%s~%d~D~review"):format(w.epoch, A.name, i)))
			local key = B.name:lower() .. "#" .. A.name:lower() .. "#" .. i
			assert(w.As(Co, Co.WC.Answer, key, "K", "reviewed")); w.Run()
		end
		w.epoch = w.epoch + 61
		eq(w.Inject("CHANNEL", B.name, Co, ("MD~1~A~%d~%s~%d~D~another"):format(w.epoch, A.name, 99)), true,
			"answered requests do not block a new unresolved appeal")
	end)
end)

test("watch: chat moderation: appeal admission never evicts another unresolved held appeal or churns unverified requests", function()
	for _, held in ipairs({ false, true }) do World(function(w)
		local G, A, B = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local s = Co.WC.Store()
		for i = 1, Co.WC.APPEALS_MAX do
			s.appeals["retained" .. i] = { name = "Filer" .. i .. "-Realm", actor = A.name, seq = i, op = "T", at = w.epoch - i,
				text = "review", held = held or nil }
		end
		if held then s.audit[1] = { name = B.name, by = A.name, seq = 999, op = "T" } end
		local ok, why = w.Inject("CHANNEL", B.name, Co, ("MD~1~A~%d~%s~999~T~review"):format(w.epoch, A.name))
		eq(ok, false); eq(why, "full", "a full unresolved queue stays retryable")
		assert(s.appeals["retained" .. Co.WC.APPEALS_MAX], "the oldest unresolved request survives")
	end) end
end)

test("watch: chat moderation: appeal answers validate time and correlation before the shared quota", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "")); w.Run()
		local r = B.WC.Store().record[1]
		local unsolicited = ("MD~1~R~%d~%s~%s~%d~K~reviewed"):format(w.epoch, B.name, A.name, r.seq)
		eq(select(2, w.Inject("CHANNEL", Co.name, B, unsolicited)), "appeal", "a matching sanction alone is not a pending appeal")
		eq(r.appeal, nil)
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "review")); w.Run()
		local function Word(at, seq) return ("MD~1~R~%s~%s~%s~%d~K~reviewed"):format(at, B.name, A.name, seq or r.seq) end
		for _, at in ipairs({ w.epoch + B.WC.DATE_AHEAD + 1, w.epoch - B.WC.KEEP - 1 }) do
			eq(select(2, w.Inject("CHANNEL", Co.name, B, Word(at))), "time")
		end
		eq(select(2, w.Inject("CHANNEL", Co.name, B, Word(w.epoch, r.seq + 99))), "appeal", "an unrelated decision is not a popup")
		eq(select(2, w.Inject("CHANNEL", Co.name, B, Word(r.appealed - 1))), "older", "a decision cannot precede its request")
		for i = 1, 6 do
			local from = "Reviewer" .. i .. "-Realm"
			w.council[Fold(from)] = true
			for _ = 1, B.WC.RATE do eq(select(2, w.Inject("CHANNEL", from, B, Word("bad"))), "shape") end
		end
		eq(w.Inject("CHANNEL", Co.name, B, Word(w.epoch)), true, "malformed authorized words did not exhaust the shared budget")
		eq(r.appeal, "K")
	end)
end)

test("watch: chat moderation: appeal admission may replace an unverified request only with a held matching sanction", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local s = Co.WC.Store()
		for i = 1, Co.WC.APPEALS_MAX do
			s.appeals["retained" .. i] = { name = "Filer" .. i .. "-Realm", actor = A.name, seq = i, op = "T", at = w.epoch - i, text = "review" }
		end
		s.audit[1] = { name = B.name, by = A.name, seq = 999, op = "D" }
		local function Request() return w.Inject("CHANNEL", B.name, Co, ("MD~1~A~%d~%s~999~T~review"):format(w.epoch, A.name)) end
		eq(select(2, Request()), "full", "a different kind of sanction grants no queue priority")
		w.epoch = w.epoch + 61
		s.audit[1].op = "T"
		eq(Request(), true, "a held matching sanction may replace the oldest unverified request")
		eq(s.appeals["retained" .. Co.WC.APPEALS_MAX], nil)
		local key = B.name:lower() .. "#" .. A.name:lower() .. "#999"
		eq(s.appeals[key].held, true)
	end)
end)

test("watch: chat moderation: appeal answers refuse overflow without forgetting live replay floors and reclaim only expired history", function()
	World(function(w)
		local G, A, B, D, Stranger = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "")); w.Run()
		local r = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "review")); w.Run()
		local key = next(Co.WC.Store().appeals)
		local targetStore, councilStore = B.WC.Store(), Co.WC.Store()
		local max = B.WC.APPEAL_ANSWERS_MAX or 1000
		-- Seed full persisted histories, then exercise admission through the actual receiver and sender.
		for _, s in ipairs({ targetStore, councilStore }) do
			s.appealAnswers = {}
			for i = 1, max do s.appealAnswers["retained" .. i] = w.epoch end
		end
		local response = ("MD~1~R~%d~%s~%s~%d~K~reviewed"):format(w.epoch, B.name, A.name, r.seq)
		eq(select(2, w.Inject("CHANNEL", Stranger.name, B, response)), "namer", "a stranger cannot consume answer history")
		eq(select(2, w.Inject("CHANNEL", Co.name, B, response)), "full")
		eq(r.appeal, nil); assert(r.pendingAppeal, "refused decisions leave the pending request retryable")
		eq(select(2, w.As(Co, Co.WC.Answer, key, "K", "reviewed")), "full")
		eq(councilStore.appeals[key].answer, nil)
		for _, s in ipairs({ targetStore, councilStore }) do
			local count = 0
			for _ in pairs(s.appealAnswers) do count = count + 1 end
			eq(count, max); assert(s.appealAnswers.retained1, "a live floor is never evicted")
		end
		w.epoch = w.epoch + B.WC.KEEP + 1
		w.As(B, B.WC.Prune); w.As(Co, Co.WC.Prune)
		eq(next(targetStore.appealAnswers), nil); eq(next(councilStore.appealAnswers), nil)
		eq(select(2, w.Inject("CHANNEL", Co.name, B, response)), "time", "an expired payload cannot become valid when its floor expires")
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "new")); w.Run()
		local latest = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, latest.by, latest.seq, "another")); w.Run()
		assert(w.As(Co, Co.WC.Answer, next(councilStore.appeals), "K", "reviewed")); w.Run()
		eq(latest.appeal, "K", "expired floors free room for a fresh correlated decision")
	end)
end)

test("watch: chat moderation: appeal answers retain replay floors after reload and allow a newer staff correction", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "")); w.Run()
		local r = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "review")); w.Run()
		local key = next(Co.WC.Store().appeals)
		assert(w.As(Co, Co.WC.Answer, key, "K", "first")); w.Run()
		local first = w.Sent("MD~1~R~")[1].msg
		local function Decisions()
			local n = 0
			for _, d in ipairs(B.dialogs) do if d.which == "OLYMPUS_WATCHCHAT_DECISION" then n = n + 1 end end
			return n
		end
		local n = Decisions()
		w.As(B, function() assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", B.ns); B.WC = B.ns.WatchChat end)
		eq(select(2, w.Inject("CHANNEL", Co.name, B, first)), "repeat")
		eq(Decisions(), n, "the persisted answer does not show again after reload")
		for i = 1, 6 do
			local from = "Reviewer" .. i .. "-Realm"
			w.council[Fold(from)] = true
			for _ = 1, B.WC.RATE do eq(select(2, w.Inject("CHANNEL", from, B, first)), "repeat") end
		end
		assert(w.As(Co, Co.WC.Answer, key, "L", "corrected")); w.Run()
		eq(r.appeal, "L", "replayed answers spend no shared budget; a newer authenticated staff decision may correct the first")
		eq(Decisions(), n + 1)
		eq(select(2, w.Inject("CHANNEL", Co.name, B, first)), "older")
		eq(r.appeal, "L", "an old keep cannot reverse the newer lift")
		eq(Decisions(), n + 1)
	end)
end)

test("watch: chat moderation: appeal answers survive answered-row eviction and refused sends remain answerable", function()
	World(function(w)
		local G, A, B = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		assert(w.As(A, A.WC.Timeout, B.name, 86400, "")); w.Run()
		local r = B.WC.Store().record[1]
		assert(w.As(B, B.WC.Appeal, r.by, r.seq, "review")); w.Run()
		local request = w.Sent("MD~1~A~")[1].msg
		local s, key = Co.WC.Store(), next(Co.WC.Store().appeals)
		local send = Co.ns.Comm.Send
		Co.ns.Comm.Send = function() return false end
		local ok, why = w.As(Co, Co.WC.Answer, key, "K", "reviewed")
		eq(ok, false); eq(why, "queue"); eq(s.appeals[key].answer, nil)
		Co.ns.Comm.Send = send
		assert(w.As(Co, Co.WC.Answer, key, "K", "reviewed")); w.Run()
		for i = 1, Co.WC.APPEALS_MAX do
			w.epoch = w.epoch + 1
			assert(w.Inject("CHANNEL", "Filer" .. i .. "-Realm", Co, ("MD~1~A~%d~%s~1~D~review"):format(w.epoch, A.name)))
		end
		eq(s.appeals[key], nil, "answered rows can make room")
		eq(select(2, w.Inject("CHANNEL", B.name, Co, request)), "answered")
		eq(s.appeals[key], nil, "an old request cannot reopen its evicted answered row")
	end)
end)

test("watch: chat moderation: S testimony needs verified membership and a fresh own roster before shared admission", function()
	World(function(w)
		local G, A, B, D = Standard(w)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local function Word(seq, guild) return ("MD~1~S~T~%d~%d~%s~%s~%d~-~"):format(seq, w.epoch, guild, A.name, w.epoch + 600) end
		-- Channels.lua really returns 1,false for a new claim with no verified identity.
		for i = 1, Co.WC.RATE_SELF_ALL + 5 do
			eq(select(2, w.Inject("CHANNEL", "Claim" .. i .. "-Realm", Co, Word(i, "Olympus Ghosts"))), "guild")
		end
		eq(#Co.WC.Store().audit, 0, "unknown claims do not frame the named Watcher")
		w.census[X] = true
		eq(select(2, w.Inject("CHANNEL", B.name, Co, Word(100, X))), "guild", "a census rank grants no admission")
		w.census[X] = nil
		eq(w.Inject("CHANNEL", B.name, Co, Word(101, X)), true, "a verified member still reports testimony after the hostile flood")
		local fresh = D.W.FreshRoster
		D.W.FreshRoster = function() return false end
		eq(select(2, w.Inject("CHANNEL", B.name, D, Word(102, X))), "guild", "the old own roster grants nothing")
		D.W.FreshRoster = fresh
		eq(w.Inject("CHANNEL", B.name, D, Word(103, X)), true, "fresh own-roster membership works")
	end)
end)

test("watch: chat moderation: a line deleted from a report without its id: that line alone goes, the same words said later still show", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.Say(B, "A", "lol")
		-- A was away when it was said: his client has no copy of it, so no id.
		local list = w.As(A, A.C.RawHistory, "A")
		for i = #list, 1, -1 do if list[i].text == "lol" then table.remove(list, i) end end
		assert(w.As(A, A.WC.DeleteReported, B.name, { { tier = "A", text = "lol" } }, ""))
		w.Run()
		eq(w.Lines(D, "A", B.name)[1].del, true, "deleted where it was kept")
		eq(w.Lines(Y1, "A", B.name)[1].del, true, "abroad too")
		w.epoch = w.epoch + 3600
		w.Say(B, "A", "lol")
		for _, cl in ipairs({ G, A, D, Y1 }) do assert(w.Line(cl, "A", B.name, "lol"), "his new 'lol' shows on " .. cl.short) end
	end)
end)

test("watch: chat moderation: a guild master's Watchers lapse on a client 3 days after it last heard his list: a removal it missed counts no longer", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(G, G.WC.SetWatcher, B.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(A, A.W.IsAuthorized, B.name), true)
		-- He is removed while A is away, and the guild master plays no more.
		A.online = false
		assert(w.As(G, G.WC.SetWatcher, B.name, false))
		w.epoch = w.epoch + 3
		w.Run()
		G.online, A.online = false, true
		eq(w.As(A, A.W.IsAuthorized, B.name), true, "A missed the removal: a Watcher there for now")
		w.epoch = w.epoch + 3 * 86400 + 1
		eq(w.As(A, A.W.IsAuthorized, B.name), false, "lapsed after 3 days")
		eq(A.WC.WATCHERS_FRESH, 3 * 86400)
		local ok = w.Inject("GUILD", B.name, A, ("MD~1~T~G~%d~%d~%s~%s~%d~-~-~"):format(5000, w.epoch, X, D.name, w.epoch + 300))
		eq(ok, false, "his timeout is refused there")
		-- While the guild master plays, his client's repeats keep his list alive.
		G.online = true
		assert(w.As(G, G.WC.SetWatcher, D.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		for _ = 1, 3 do
			w.epoch = w.epoch + 86400
			w.As(G, G.WC.Tick)
			w.Run()
		end
		eq(w.As(A, A.W.IsAuthorized, D.name), true, "repeated: fresh")
	end)
end)

test("watch: chat moderation: two Watchers' timeouts: the longer binds on every client, abroad too, and the player is told its end", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		assert(w.As(A, A.WC.Timeout, B.name, 604800, ""))
		w.Run()
		w.epoch = w.epoch + 5
		assert(w.As(G, G.WC.Timeout, B.name, 300, ""))
		w.Run()
		assert(w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT").a:find(ns.L.WATCHCHAT_SPAN_DAYS:format(7), 1, true),
			"told the 7 days, never the 5 minutes given after: " .. w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT").a)
		w.epoch = w.epoch + 301
		for _, cl in ipairs({ B, D, Y1 }) do eq(w.As(cl, cl.WC.Barred, "games", cl == B and nil or B.name) ~= nil, true, "the 7 days on " .. cl.short) end
		eq(w.As(Y1, Y1.WC.Silenced, B.name), true, "abroad, his lines still dropped")
	end)
end)

test("watch: chat moderation: the King is never given a timeout (no client would hold it); the author may still delete his line", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.author, w.king = "Author-Realm", "Kingly-Realm"
		local K = w.Client("Kingly", "Olympus", 0)
		local Au = w.Client("Author", Y, 2)
		local ok, why = w.As(Au, Au.WC.Timeout, K.name, 300, "")
		eq(ok, false); eq(why, "king")
		eq(#w.wire, 0, "nothing sent")
		local _, fwhy = w.Inject("CHANNEL", Au.name, D, ("MD~1~T~O~%d~%d~Olympus~%s~%d~-~-~"):format(900, w.epoch, K.name, w.epoch + 300))
		eq(fwhy, "king", "nor taken")
		w.Say(K, "A", "a royal line")
		assert(w.As(Au, Au.WC.Delete, "A", w.Line(Au, "A", K.name, "a royal line"), ""))
		w.Run()
		eq(w.Line(D, "A", K.name).del, true, "his line deleted")
	end)
end)

test("watch: chat moderation: junk from players with no standing never spends the moderators' shared budget", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		for i = 1, 6 do
			local junk = "Junk" .. i .. "-Realm"
			for _ = 1, 10 do w.Inject("CHANNEL", junk, D, "MD~1~X~junk") end
			for j = 1, 10 do w.Inject("CHANNEL", junk, D, ("MD~1~T~O~%d~%d~%s~%s~%d~-~-~"):format(100 + j, w.epoch, X, B.name, w.epoch + 300)) end
			for j = 1, 10 do w.Inject("CHANNEL", junk, D, ("MD~1~S~T~%d~%d~%s~%s~%d~-~"):format(100 + j, w.epoch, X, A.name, w.epoch + 300)) end
		end
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		eq(w.As(D, D.WC.Silenced, B.name), true, "the officer's timeout is taken")
	end)
end)

test("watch: chat moderation: the King's upheld word reaches the guild's Justice correspondent and its guild master, not only the officer who sent the case; a warning applies it", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local P = w.Client("Plain", X, 3)
		assert(w.As(G, G.WC.SetWatcher, D.name, true, true)) -- D: the Justice correspondent
		w.epoch = w.epoch + 3
		w.Run()
		-- The King's final word reached A's client, the officer who sent the case (Judgment.lua).
		assert(w.As(A, A.WC.TellCase, B.name, 42, "U"))
		w.Run()
		eq(w.As(D, D.WC.KingUpheld, B.name).jid, 42, "the Justice correspondent has it")
		eq(w.As(G, G.WC.KingUpheld, B.name) ~= nil, true, "the guild master too")
		eq(w.As(A, A.WC.KingUpheld, B.name) ~= nil, true, "the officer who sent it")
		eq(w.As(P, P.WC.KingUpheld, B.name), nil, "a member keeps nothing")
		eq(w.As(B, B.WC.KingUpheld, B.name), nil, "nor the player")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a, ns.L.WATCHCHAT_DECISION_UP, "the player is told")
		eq(w.As(D, D.WC.MayApplyJudgment), true)
		-- A warning from him applies it: it leaves his case's page.
		assert(w.As(D, D.W.Warn, B.name, "the King's judgment"))
		w.Run()
		eq(w.As(D, D.WC.KingUpheld, B.name), nil, "applied")
		-- The case's page offers it while it waits (Watch.lua reads WatchChat.KingUpheld).
		local src = assert(io.open(ROOT .. "Olympus/Watch.lua", "rb")):read("*a")
		assert(src:find("WC.KingUpheld(target)", 1, true))
	end)
end)

---------------------------------------------------------------------------
-- Old clients, the gamepad UI, strings
---------------------------------------------------------------------------

test("watch: chat moderation: old clients: 1.1.4's Comm runs no handler for MD, without error; MD is in Comm.lua's list", function()
	local saved = rawget(_G, "C_ChatInfo")
	local ok, err = pcall(function()
		local events, login = {}, {}
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns.On = function(name, fn) if name == "LOGIN" then login[#login + 1] = fn end end
		cns.After, cns.Every = function() end, function() end
		cns.Now = function() return 100000 end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		assert(loadfile(ROOT .. "tests/fixtures/comm-1.1.4.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		local heard = 0
		for _, kind in ipairs({ "M1", "M2", "MW", "T1" }) do cns.Comm.Handle(kind, function() heard = heard + 1 end) end
		local function Deliver(dist, sender, text)
			for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, text, dist, sender) end
		end
		Deliver("GUILD", "Officer-Realm", "MD~1~T~G~900~1800000000~Olympus II~Member-Realm~1800000300~-~-~spam")
		Deliver("CHANNEL", "Member-Realm", "MD~1~S~D~900~1800000000~Olympus II~Officer-Realm~-~A.12.abcdef~")
		Deliver("GUILD", "Grandmaster-Realm", "MD~1~W~1800000000~Olympus II~1~1~-~Member-Realm")
		eq(heard, 0, "no handler runs")
		eq(cns.Comm.Stats().bad, 0, "none misread")
	end)
	C_ChatInfo = saved
	if not ok then error(err, 0) end
	local src = assert(io.open(ROOT .. "Olympus/Comm.lua", "rb")):read("*a")
	assert(src:find("WatchChat MD", 1, true))
end)

test("watch: chat moderation: under the gamepad UI every dialog is Olympus's own, the game's chat is left alone, and the line's button is a child of Olympus's bubble", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.gamepad = true
		w.Say(B, "A", "under the gamepad")
		local e = w.Line(A, "A", B.name, "under the gamepad")
		eq(w.As(A, A.WC.AskEntry, e, "A"), true)
		eq(A.dialogs[#A.dialogs].which, "OLYMPUS_WATCHCHAT_ACT", "ns.ShowDialog: Olympus's own window there")
		for _, which in ipairs({ "OLYMPUS_WATCHCHAT_ACT", "OLYMPUS_WATCHCHAT_MORE", "OLYMPUS_WATCHCHAT_TIME", "OLYMPUS_WATCHCHAT_TIME2",
			"OLYMPUS_WATCHCHAT_TIME3", "OLYMPUS_WATCHCHAT_WHY", "OLYMPUS_WATCHCHAT_TIMED_OUT", "OLYMPUS_WATCHCHAT_APPEAL",
			"OLYMPUS_WATCHCHAT_ANSWER", "OLYMPUS_WATCHCHAT_DECISION", "OLYMPUS_WATCHCHAT_NAME", "OLYMPUS_WATCHCHAT_REMOVE" }) do
			assert(StaticPopupDialogs[which], which)
		end
		local frames = #Y1.frame.lines
		assert(w.As(A, A.WC.Delete, "A", e, ""))
		w.Run()
		assert(Y1.frame.lines[frames].message:find("under the gamepad", 1, true), "the game's window keeps what it showed")
		eq(Y1.frame.calls, 0, "TransformMessages never called")
		eq(w.Line(Y1, "A", B.name).del, true, "the Chat tab's history is replaced all the same")
		assert(w.As(A, A.WC.Timeout, B.name, 300, ""))
		w.Run()
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_TIMED_OUT") ~= nil, true, "the pop-up through ns.ShowDialog")
		local cw = assert(io.open(ROOT .. "Olympus/ChatWindow.lua", "rb")):read("*a")
		assert(cw:find('b.mod = CreateFrame("Button", nil, b)', 1, true), "the button's parent is Olympus's bubble")
		assert(not cw:find("Menu.ModifyMenu", 1, true), "no game menu entry")
	end)
end)

test("watch: chat moderation: its strings in English and pt-BR, with the same placeholders", function()
	local oldLocale = GetLocale
	local pt = {}
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(assert(loadfile(ROOT .. "Olympus/Locales.lua")), "Olympus", pt)
	GetLocale = oldLocale
	if not ok then error(err, 0) end
	local n = 0
	for k, v in pairs(ns.L) do
		if type(k) == "string" and (k:find("^WATCHCHAT_") or k == "WALLET_WHY_FROZEN" or k:find("_SANCTION$")) then
			n = n + 1
			local p = rawget(pt.L, k)
			assert(p and p ~= v, "pt-BR: " .. k)
			local a, b = {}, {}
			for x in v:gmatch("%%%d*[sd]") do a[#a + 1] = x end
			for x in p:gmatch("%%%d*[sd]") do b[#b + 1] = x end
			eq(table.concat(b, ","), table.concat(a, ","), "the same placeholders: " .. k)
		end
	end
	assert(n >= 150, "the strings: " .. n)
	-- Every key the code reads is there.
	-- (The chat warnings' file too, ChatStrikes.lua; and its keys outside WATCHCHAT_, in both languages.)
	for _, file in ipairs({ "WatchChat.lua", "ChatStrikes.lua" }) do
		local src = assert(io.open(ROOT .. "Olympus/" .. file, "rb")):read("*a")
		for key in src:gmatch("L%.(WATCHCHAT_[%w_]+)") do assert(rawget(ns.L, key), "missing: " .. key) end
	end
	for _, k in ipairs({ "CHATWIN_WHY_PAUSED", "ARENA_CHAT_WHY_PAUSED" }) do
		assert(rawget(ns.L, k) and rawget(pt.L, k) and rawget(pt.L, k) ~= rawget(ns.L, k), "both languages: " .. k)
	end
	eq(ns.L.WATCHCHAT_DELETED, "[deleted by a moderator]")
	eq(pt.L.WATCHCHAT_DELETED, "[apagada por um moderador]")
	-- The README says what the game's chat window keeps.
	local readme = assert(io.open(ROOT .. "README.md", "rb")):read("*a")
	assert(readme:find("Chat moderation (1.1.6)", 1, true) and readme:find("keep what they already showed", 1, true))
end)

-- 1.2.4, the author: "Precisam de uma sala para as pessoas que estão na The Watch ... Teria que serem
-- as pessoas nomeadas, mais o High Council ali que está na The Watch, para os moderadores poderem
-- conversar entre si." The Watch's room on the Chat tab: whoever acts in Olympus scope (an Olympus
-- moderator's level or above, WatchChat.ActorLevel): the author, the King, every councillor, the
-- moderators a fresh list names. Not a guild's own Watchers, nor anyone sanctioned.
test("watch: chat moderation (1.2.4): The Watch's room: the author, the King, every councillor and the Olympus moderators named talk there; a lapsed list, a sanction and a guild's own Watcher keep one out", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		w.author, w.king = "Quill Wright-Realm", "Crown Rook-Realm"
		local Au = w.Client("Quill Wright", Y, 3)
		local K = w.Client("Crown Rook", Y, 3)
		w.council[Fold("Councillor-Realm")] = true
		local Co = w.Client("Councillor", Y, 3)
		local Mo = w.Client("Modder", Y, 3)
		assert(w.As(Co, Co.WC.SetMod, Mo.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		-- A guild master's own Watcher (and his officers): his guild's, not Olympus's.
		assert(w.As(G, G.WC.SetWatcher, B.name, true))
		w.epoch = w.epoch + 3
		w.Run()
		eq(w.As(D, D.WC.IsNamedWatcher, B.name), true)
		local function In(cl, name) return w.As(cl, cl.R.CanAccess, "watch", name) end
		for _, who in ipairs({ Au.name, K.name, Co.name, Mo.name }) do eq(In(D, who), true, who) end
		for _, who in ipairs({ B.name, A.name, G.name, Y1.name }) do eq(In(D, who), false, who) end
		eq(w.As(D, D.R.Info, "watch").label, "The Watch")
		local function Listed(cl)
			for _, o in ipairs(w.As(cl, cl.R.Options, "role")) do if o.id == "watch" then return true end end
			return false
		end
		eq(Listed(Mo), true); eq(Listed(Co), true); eq(Listed(B), false, "a guild's Watcher"); eq(Listed(D), false)
		-- A councillor's line: one logged whisper to each member he knows of (the author while his
		-- presence is heard, the King, the High Council's signed names, the moderators named), heard there.
		Co.ns.Workshop.AuthorOnline = function() return true end
		Co.ns.Workshop.AuthorName = function() return w.author end
		Co.ns.rdb.council = { names = { [Fold("Councillor")] = "Councillor" } }
		w.wire = {}
		assert(w.As(Co, Co.R.Send, "watch", "a word among the moderators"))
		local targets = {}
		for _, job in ipairs(w.wire) do eq(job.dist, "WHISPER"); eq(job.logged, true); targets[#targets + 1] = Fold(Full(job.target)) end
		table.sort(targets)
		eq(table.concat(targets, ","), table.concat({ Fold(K.name), Fold(Mo.name), Fold(Au.name) }, ","))
		w.Run()
		for _, cl in ipairs({ Au, K, Mo }) do
			local h = cl.R.RawHistory("watch")
			eq(#h, 1, cl.short); eq(h[1].text, "a word among the moderators")
		end
		-- A guild's Watcher's line is not heard there.
		local msg = "M2~1~watch~9~~" .. X .. "~let me in"
		eq(w.Inject("WHISPER", B.name, Mo, msg), false)
		-- The moderators' list lapses LIST_FRESH after it was last heard: out of the room.
		w.epoch = w.epoch + D.WC.LIST_FRESH + 1
		eq(In(D, Mo.name), false, "a list not heard lately")
		w.As(Co, Co.WC.SendMods, true)
		w.Run()
		eq(In(D, Mo.name), true, "heard again")
		-- Sanctioned: out, whatever his place.
		w.off[Fold(Mo.name)] = true
		eq(In(D, Mo.name), false, "a moderator taken off")
		w.off[Fold(Co.name)] = true
		eq(In(D, Co.name), false, "a councillor taken off")
		eq(In(D, K.name), true, "never the King")
		-- The King's and a councillor's previews list it (View as), inert; a guild master's does not.
		for role, want in pairs({ king = true, councillor = true, gm = false, officer = false }) do
			D.ns.ViewAs = { Previewing = function() return true end, Role = function() return role end }
			eq(Listed(D), want, role)
		end
		eq(w.As(D, D.R.Select, "watch"), false, "a preview opens nothing")
	end)
end)

---------------------------------------------------------------------------
-- The chat warnings (ChatStrikes.lua). The author, 2026-10-19: "Vamos fazer a cada 24 horas e vamos
-- fazer três mesmo. É, primeiro avisa e bota um bloqueio de 5 minutos ... e apaga e esconde a
-- mensagem que a pessoa mandou. Segundo, esconde, bloqueio de 30, avisa ... Terceiro, avisa a equipe
-- de moderação, bloqueia o uso do chat da pessoa até a equipe de moderação decidir e assim por diante
-- ... A equipe de moderação precisa ver o que ele digitou ... quais foram as palavras que ele usou".
-- Synthetic words only ("plainword").
---------------------------------------------------------------------------

local WORD = "plainword"
local function Words(w, ...)
	w.words = w.words or {}
	for i = 1, select("#", ...) do w.words[#w.words + 1] = select(i, ...) end
	for _, cl in ipairs(w.clients) do List(cl.S, w.words) end
end
-- The chat warnings' team: the author (online), the King, a councillor and the Olympus moderator he
-- names; every client knows the council's signed names and that the author is online.
local function Team(w)
	w.author, w.king = "Quill Wright-Realm", "Crown Rook-Realm"
	w.council[Fold("Councillor-Realm")] = true
	local Au = w.Client("Quill Wright", Y, 3)
	local K = w.Client("Crown Rook", Y, 3)
	local Co = w.Client("Councillor", Y, 3)
	local Mo = w.Client("Modder", Y, 3)
	for _, cl in ipairs(w.clients) do
		cl.ns.rdb.council = { names = { [Fold("Councillor")] = "Councillor" } }
		cl.ns.Workshop.AuthorOnline = function() return true end
		cl.ns.Workshop.AuthorName = function() return w.author end
	end
	assert(w.As(Co, Co.WC.SetMod, Mo.name, true))
	w.epoch = w.epoch + 3
	w.Run()
	w.namer = Co
	return Au, K, Co, Mo
end
-- The councillor's list of moderators again, as his client repeats it while he plays (it lapses on
-- the others' clients 20 minutes after it was last heard: these scenes span hours).
local function Refresh(w)
	if w.namer then w.As(w.namer, w.namer.WC.SendMods, true) w.Run() end
end
-- A minute (or `seconds`) on: the striker's client's tick, and everything it queued delivered.
local function Tick(w, cl, seconds)
	w.epoch = w.epoch + (seconds or 60)
	Refresh(w)
	w.As(cl, cl.S.Tick)
	w.Run()
end
-- A line with a listed word from cl: refused before anything is queued; its kept entry.
local function Strike(w, cl, text, tier)
	w.epoch = w.epoch + 2
	local queued = #w.wire
	local ok, why = w.As(cl, cl.C.Send, tier or "A", text or ("a " .. WORD .. " here"))
	eq(ok, false, "struck"); eq(why, "severe", "struck")
	for i = queued + 1, #w.wire do assert(w.wire[i].msg:sub(1, 3) == "MS~", "only the team's report: " .. w.wire[i].msg) end
	local mine = cl.S.Store().mine
	return mine[#mine]
end
local function Past(w, e)
	w.epoch = math.max(w.epoch, (tonumber(e.untilAt) or 0) + 1)
	Refresh(w)
end
-- Three warnings in a row (each after the last one's pause): the third's entry, held.
local function Held(w, cl)
	local e1 = Strike(w, cl, "first " .. WORD); Past(w, e1)
	local e2 = Strike(w, cl, "second " .. WORD); Past(w, e2)
	return Strike(w, cl, "third " .. WORD), e1, e2
end
local function CaseKey(cl, e) return Fold(cl.name) .. "#" .. e.at end
-- The client as rebuilt by a /reload (or another login) on the same saved store: a new client of
-- that name, the old one gone.
local function Rebuild(w, cl)
	for i, x in ipairs(w.clients) do if x == cl then table.remove(w.clients, i) break end end
	local fresh = w.Client(cl.short, cl.guild, cl.rank)
	fresh.ns.rdb = cl.ns.rdb
	fresh.ns.Workshop.AuthorOnline, fresh.ns.Workshop.AuthorName = cl.ns.Workshop.AuthorOnline, cl.ns.Workshop.AuthorName
	return fresh
end

test("watch: chat moderation: strikes: the first warning: not sent (nothing queued), a pop-up saying why with 5 minutes, the line kept with its words; his chats paused: a pop-up then a red line, and open again after 5 minutes", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		Words(w, WORD)
		local e = Strike(w, B, "well this is a " .. WORD .. " for you")
		eq(#w.wire, 0, "nothing queued")
		eq(e.n, 1); eq(e.untilAt - e.at, B.WC.DURATIONS[1]); eq(e.untilAt - e.at, 300)
		eq(e.words, WORD); eq(e.text, "well this is a " .. WORD .. " for you"); eq(e.where, "A"); eq(e.char, B.name)
		local d = w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION")
		eq(d.a, B.ns.L.WATCHCHAT_STRIKE_1:format(B.WC.Span(300)))
		for _, part in ipairs({ "5 minutes", "verify anyone's age", "Blizzard's Terms of Service", "screenshots", "Asmongold's team" }) do
			assert(d.a:find(part, 1, true), "the first pop-up says: " .. part)
		end
		assert(w.Printed(B, B.ns.L.WATCHCHAT_SEVERE_REFUSED), "the red line too")
		eq(w.Line(D, "A", B.name), nil, "nobody saw it")
		-- Paused: a clean line is refused before its words are read, a pop-up first, then a red line.
		w.epoch = e.at + 299
		local dialogs = #B.dialogs
		eq(select(2, w.As(B, B.C.Send, "A", "a clean line")), "paused")
		eq(#B.dialogs, dialogs + 1, "a pop-up")
		eq(B.dialogs[#B.dialogs].a, B.ns.L.WATCHCHAT_STRIKE_PAUSED:format(date("%H:%M", e.untilAt)))
		eq(select(2, w.As(B, B.R.Send, "guild", "a clean line")), "paused")
		eq(#B.dialogs, dialogs + 1, "within a minute: a red line, not another pop-up")
		assert(w.Printed(B, B.ns.L.WATCHCHAT_STRIKE_PAUSED:format(date("%H:%M", e.untilAt))))
		eq(#w.wire, 0)
		eq(w.As(B, B.WC.StripText), B.ns.L.WATCHCHAT_STRIP_STRIKE:format(date("%H:%M", e.untilAt)), "the Chat tab's strip")
		w.epoch = e.at + 301
		w.Say(B, "A", "a clean line after")
		assert(w.Line(D, "A", B.name, "a clean line after"), "open again")
		eq(w.As(B, B.WC.StripText), nil)
	end)
end)

test("watch: chat moderation: strikes: the second warning pauses 30 minutes; the 24 hours roll by the clock, not by the day (a midnight between two warnings)", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		Words(w, WORD)
		local t = w.epoch
		local e1 = Strike(w, B)
		-- (The regression: WatchChat.CountBlocked's day, UTC, would start the count again at midnight.)
		assert(math.floor((e1.at + 23 * 3600) / 86400) > math.floor(e1.at / 86400), "a UTC midnight falls in between")
		w.epoch = e1.at + 23 * 3600
		local e2 = Strike(w, B)
		eq(e2.n, 2); eq(e2.untilAt - e2.at, 1800)
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a, B.ns.L.WATCHCHAT_STRIKE_2:format(B.WC.Span(1800)))
		assert(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a:find("doing it again", 1, true))
		w.epoch = e1.at + 25 * 3600
		local e3 = Strike(w, B)
		eq(e3.n, 2, "the first is more than 24 hours old: this is the second again")
		eq(e3.untilAt - e3.at, 1800)
		eq(#w.wire, 0, "no report: nothing leaves at the first two")
		eq(t <= e1.at, true)
	end)
end)

test("watch: chat moderation: strikes: the third warning in 24 hours: held until the team decides; its report (head and lines, logged whispers of at most 255 bytes) reaches the author online, the King, a councillor and an Olympus moderator, two a minute, nobody else, never on the channel or over guild; they keep his words exactly and say so", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		eq(e3.n, 3); eq(e3.untilAt, 0)
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a, B.ns.L.WATCHCHAT_STRIKE_3)
		eq(w.As(B, B.S.Block).kind, "hold")
		eq(w.As(B, B.WC.StripText), B.ns.L.WATCHCHAT_STRIP_STRIKE_HOLD)
		local queued = {}
		for _, job in ipairs(w.wire) do queued[#queued + 1] = job end
		eq(#queued, 2 * 4, "two of the team a minute: a head and three lines each")
		for _, job in ipairs(queued) do
			eq(job.dist, "WHISPER"); eq(job.logged, true, "logged"); assert(#job.msg <= 255, job.msg)
			assert(job.options and job.options.permit, "checked again at the send")
		end
		w.Run()
		Tick(w, B)
		local key = CaseKey(B, e3)
		for _, cl in ipairs({ Au, K, Co, Mo }) do
			local c = cl.S.Store().cases[key]
			assert(c, "the team keeps it: " .. cl.short)
			eq(c.name, B.name); eq(c.guild, X); eq(c.n, 3); eq(c.c24, 3); eq(#c.lines, 3)
			eq(c.lines[1].text, "first " .. WORD); eq(c.lines[3].text, "third " .. WORD, "exactly what he typed")
			eq(c.lines[3].words, WORD, "and the words")
			eq(c.lines[3].where, "A")
			eq(B.S.Store().out.to[Fold(cl.name)].acked, true, "said so: " .. cl.short)
		end
		assert(w.Printed(Mo, Mo.ns.L.WATCHCHAT_STRIKE_IN:format("Member", 3)), "the team is told, in gold")
		for _, cl in ipairs({ G, A, D, Y1 }) do eq(next(cl.S.Store().cases), nil, "nobody else: " .. cl.short) end
		for _, sent in ipairs(w.sent) do
			if sent.dist ~= "WHISPER" then assert(not sent.msg:find(WORD, 1, true), "never on " .. sent.dist .. ": " .. sent.msg) end
			if sent.msg:find(WORD, 1, true) then
				eq(sent.msg:sub(1, 7), "MS~1~L~")
				local to = Fold(Full(sent.target))
				assert(to == Fold(Au.name) or to == Fold(K.name) or to == Fold(Co.name) or to == Fold(Mo.name), "to the team only: " .. to)
			end
		end
		-- The author while his presence is heard: not otherwise.
		B.ns.Workshop.AuthorOnline = function() return false end
		local names = {}
		for _, n in ipairs((w.As(B, B.R.Recipients, "watch"))) do names[#names + 1] = Fold(n) end
		table.sort(names)
		eq(table.concat(names, ","), table.concat({ Fold(Co.name), Fold(K.name), Fold(Mo.name) }, ","))
		-- Acknowledged: never sent again.
		local heads = #w.Sent("MS~1~H~")
		Tick(w, B, 2000)
		eq(#w.Sent("MS~1~H~"), heads, "acknowledged: not again")
		-- While held, every chat refuses before reading.
		eq(select(2, w.As(B, B.C.Send, "A", "a clean line")), "paused")
		eq(select(2, w.As(B, B.R.Send, "guild", "a clean line")), "paused")
		assert(w.Printed(B, B.ns.L.WATCHCHAT_STRIKE_HELD))
		eq(#B.S.Store().mine, 3, "not counted")
	end)
end)

test("watch: chat moderation: strikes: a team member who never acknowledges is sent it again every 15 minutes, three times at most, the tries kept across a rebuilt client", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		Mo.online = false
		local e3 = Held(w, B)
		w.Run()
		Tick(w, B)
		local function Tries() return B.S.Store().out.to[Fold(Mo.name)].tries end
		eq(Tries(), 1); eq(B.S.Store().out.to[Fold(Mo.name)].acked, nil)
		Tick(w, B)
		eq(Tries(), 1, "not before 15 minutes")
		Tick(w, B, B.S.RETRY)
		eq(Tries(), 2)
		B = Rebuild(w, B)
		Tick(w, B, B.S.RETRY)
		eq(Tries(), 3, "the tries were saved")
		local heads = #w.Sent("MS~1~H~")
		Tick(w, B, B.S.RETRY)
		eq(Tries(), 3); eq(#w.Sent("MS~1~H~"), heads, "three at most")
		eq(next(Mo.S.Store().cases), nil)
		eq(e3.n, 3)
	end)
end)

test("watch: chat moderation: strikes: \"Let them chat\": the hold ends on his client and on an alt of his account, the team's other clients mark it decided; never from a guild's Watcher, a member or for an older hold; a replay changes nothing; and it never ends a guild timeout of his", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local Alt = w.Client("Alternate", X, 3)
		Alt.ns.rdb = B.ns.rdb -- (the account's other character, the same saved store)
		Alt.ns.rdb.council = B.ns.rdb.council
		local e1, e2
		local e3
		e3, e1, e2 = Held(w, B)
		w.Run(); Tick(w, B)
		local key = CaseKey(B, e3)
		eq(select(2, w.As(Alt, Alt.C.Send, "A", "from the alt")), "paused", "the account is held")
		-- A guild's own Watcher (his officer) gives him a guild timeout meanwhile.
		assert(w.As(A, A.WC.Timeout, B.name, 604800, "guild matter"))
		w.Run()
		eq(w.As(B, B.WC.SelfTimeout).scope, "G")
		-- Refused: the officer (no Olympus authority), an ordinary member, an older hold's id.
		local forged = ("MS~1~D~%s~%d~R~%d"):format(B.name, e3.at, w.epoch)
		for _, who in ipairs({ A, D }) do
			local ok, why = w.Inject("WHISPER", who.name, B, forged)
			eq(ok, false, who.short); eq(why, "actor", who.short)
		end
		local older = ("MS~1~D~%s~%d~R~%d"):format(B.name, e1.at, w.epoch)
		eq(w.Inject("WHISPER", Mo.name, B, older), false, "a struck line that was never a hold")
		A.S.Store().cases[key] = { name = B.name, id = e3.at, n = 3, heard = w.epoch, lines = {} }
		eq(w.As(A, A.S.Release, key), false, "the officer's client may not")
		eq(w.As(B, B.S.Block).kind, "hold")
		-- The moderator lets him chat.
		w.epoch = w.epoch + 5
		assert(w.As(Mo, Mo.S.Release, key))
		w.Run()
		eq(w.As(B, B.S.Block), nil, "the hold is over")
		eq(B.S.Store().mine[3].decided.op, "R"); eq(Fold(B.S.Store().mine[3].decided.by), Fold(Mo.name))
		assert(w.Printed(B, B.ns.L.WATCHCHAT_STRIKE_RELEASED))
		for _, cl in ipairs({ Au, K, Co, Mo }) do eq(cl.S.Store().cases[key].decided.op, "R", "decided on " .. cl.short) end
		eq(w.As(Alt, Alt.S.Block), nil, "the alt's chats with it")
		-- A replay changes nothing.
		local again = ("MS~1~D~%s~%d~R~%d"):format(B.name, e3.at, w.epoch)
		local ok, why = w.Inject("WHISPER", Mo.name, B, again)
		eq(ok, true); eq(why, "repeat")
		eq(Fold(B.S.Store().mine[3].decided.by), Fold(Mo.name))
		-- (The regression: a lift, U, would have ended the guild's timeout too.)
		eq(w.As(B, B.WC.SelfTimeout).scope, "G", "his guild's timeout stands")
		eq(select(2, w.As(B, B.C.Send, "A", "still timed out")), "timeout")
		eq(#w.Sent("MD~1~U~"), 0, "no lift sent")
		w.Say(Alt, "A", "the alt chats again")
		assert(w.Line(D, "A", Alt.name, "the alt chats again"))
		eq(e2.n, 2)
	end)
end)

test("watch: chat moderation: strikes: an Olympus moderator's timeout decides the case instead: the chats open when it ends; a guild's timeout leaves the hold", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		local key = CaseKey(B, e3)
		assert(w.As(A, A.WC.Timeout, B.name, 300, "guild"))
		w.Run()
		eq(w.As(B, B.S.Block).kind, "hold", "a guild's timeout decides nothing")
		eq(Co.S.Store().cases[key].decided, nil)
		w.epoch = w.epoch + 301
		Refresh(w)
		assert(w.As(Mo, Mo.WC.Timeout, B.name, 3600, "the team's call"))
		w.Run()
		eq(w.As(B, B.S.Block), nil, "decided by the timeout")
		eq(B.S.Store().mine[3].decided.op, "T")
		for _, cl in ipairs({ Au, K, Co, Mo }) do eq(cl.S.Store().cases[key].decided.op, "T", cl.short) end
		eq(select(2, w.As(B, B.C.Send, "A", "during the hour")), "timeout", "the timeout in force")
		w.epoch = w.epoch + 3601
		w.Say(B, "A", "after the hour")
		assert(w.Line(D, "A", B.name, "after the hour"))
	end)
end)

test("watch: chat moderation: strikes: let chat while he was away: back, his client asks one of the team and the answer ends the hold", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		B.online = false
		assert(w.As(Mo, Mo.S.Release, CaseKey(B, e3)))
		w.Run()
		eq(w.As(B, B.S.Block).kind, "hold", "away: not heard")
		B = Rebuild(w, B) -- (his next login)
		w.epoch = w.epoch + B.S.PING
		Refresh(w)
		w.As(B, B.S.Tick)
		eq(#w.wire, 1); eq(w.wire[1].msg, ("MS~1~P~%d"):format(e3.at)); eq(w.wire[1].dist, "WHISPER")
		w.Run()
		eq(w.As(B, B.S.Block), nil, "the team's answer ended it")
		eq(B.S.Store().mine[3].decided.op, "R")
	end)
end)

test("watch: chat moderation: strikes: \"e assim por diante\": a fourth warning the same day after a release holds again with a new report; a day later the count starts over; a hold nobody decides lapses in 30 days", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		assert(w.As(Mo, Mo.S.Release, CaseKey(B, e3)))
		w.Run()
		local e4 = Strike(w, B, "fourth " .. WORD)
		eq(e4.n, 4); eq(e4.untilAt, 0); assert(e4.at > e3.at, "a new id")
		eq(w.Dialog(B, "OLYMPUS_WATCHCHAT_DECISION").a, B.ns.L.WATCHCHAT_STRIKE_MORE:format(4))
		w.Run(); Tick(w, B)
		local c = Mo.S.Store().cases[CaseKey(B, e4)]
		assert(c, "a new case"); eq(c.n, 4); eq(c.lines[#c.lines].text, "fourth " .. WORD); eq(#c.lines, 3, "the last three of the window")
		assert(w.As(Mo, Mo.S.Release, CaseKey(B, e4)))
		w.Run()
		w.epoch = e4.at + 86401
		Refresh(w)
		local e5 = Strike(w, B, "a day later " .. WORD)
		eq(e5.n, 1); eq(e5.untilAt - e5.at, 300)
		Past(w, e5)
		local e6 = Strike(w, B); Past(w, e6)
		local e7 = Strike(w, B)
		eq(e7.n, 3)
		w.Run(); Tick(w, B)
		eq(#Mo.S.Store().cases[CaseKey(B, e7)].lines, 5, "three of the window and two earlier, from the 30 days")
		w.epoch = e7.at + B.S.HOLD_MAX
		eq(w.As(B, B.S.Block), nil, "lapsed")
		w.Say(B, "A", "free again")
	end)
end)

test("watch: chat moderation: strikes: the King and the author have the line refused and counted, nothing more; The Watch's room is not read; a line during a pause is not counted", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		for _, cl in ipairs({ K, Au }) do
			for i = 1, 4 do
				w.epoch = w.epoch + 2
				eq(select(2, w.As(cl, cl.C.Send, "A", "a " .. WORD)), "severe", cl.short)
			end
			eq(#cl.S.Store().mine, 0, "no warning kept: " .. cl.short)
			eq(w.Dialog(cl, "OLYMPUS_WATCHCHAT_DECISION"), nil, "no pop-up: " .. cl.short)
			assert(w.Printed(cl, cl.ns.L.WATCHCHAT_SEVERE_REFUSED), "the red line: " .. cl.short)
			eq((w.As(cl, cl.WC.BlockedCounts, cl.name)).severe, 4)
			eq(w.As(cl, cl.S.Block), nil)
			w.Say(cl, "A", "a clean line from " .. cl.short)
		end
		eq(#w.Sent("MS~"), 0, "no report")
		-- The Watch's room: its staff quote what was said.
		w.epoch = w.epoch + 10
		assert(w.As(Co, Co.R.Send, "watch", "he wrote " .. WORD .. " in the chat"))
		w.Run()
		eq(Mo.R.RawHistory("watch")[1].text, "he wrote " .. WORD .. " in the chat")
		eq(#Co.S.Store().mine, 0)
		-- A pause: the next line is not read.
		local e = Strike(w, B)
		eq(select(2, w.As(B, B.C.Send, "A", "another " .. WORD)), "paused")
		eq(#B.S.Store().mine, 1); eq((w.As(B, B.WC.BlockedCounts, B.name)).severe, 1)
		eq(e.n, 1)
	end)
end)

test("watch: chat moderation: strikes: chats only: during a pause no power, game or wallet is barred, a paused moderator keeps his level, and no other client silences him", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		Strike(w, B)
		for _, what in ipairs({ "powers", "games", "locations", "crafting", "wallet" }) do eq(w.As(B, B.WC.Barred, what), nil, what) end
		eq(w.As(B, B.WC.SelfTimeout), nil, "never a moderator's timeout")
		eq(next(B.WC.Store().timeouts), nil)
		eq(w.As(D, D.WC.Silenced, B.name), false)
		Strike(w, Mo)
		eq(w.As(Mo, Mo.WC.ActorLevel, Mo.name), Mo.WC.LEVEL.mod, "his level, on his client")
		eq(w.As(D, D.WC.ActorLevel, Mo.name), D.WC.LEVEL.mod, "and on the others'")
		eq(w.As(Mo, Mo.WC.CanModerate, D.name), "O", "he still moderates")
		eq(select(2, w.As(Mo, Mo.C.Send, "A", "a clean line")), "paused", "but his chats are paused")
	end)
end)

test("watch: chat moderation: strikes: every way a line leaves is covered: the three chats, the privacy warning's Send, the Guild room (the game's send never called), a role room, a Church room, a provider's room (its send never called), a pin; a reply's quote alone goes without it; CanWrite while paused", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local function Fresh(cl) cl.ns.rdb.chatStrikes = nil end
		local function Refused(cl, fn, ...)
			Fresh(cl)
			w.epoch = w.epoch + 2
			local queued = #w.wire
			local ok, why = w.As(cl, fn, ...)
			eq(ok, false); eq(why, "severe")
			eq(#w.wire, queued, "nothing queued")
			eq(#cl.S.Store().mine, 1, "a warning")
			return cl.S.Store().mine[1]
		end
		eq(Refused(B, B.C.Send, "A", "a " .. WORD).where, "A")
		eq(Refused(A, A.C.Send, "C", "a " .. WORD).where, "C")
		eq(Refused(G, G.C.Send, "L", "a " .. WORD).where, "L")
		-- The privacy warning: a struck line never reaches it; its Send runs every check again.
		Fresh(B)
		B.ns.db.chatWarned = {}
		local dialogs = #B.dialogs
		eq(select(2, w.As(B, B.C.Send, "A", "a " .. WORD)), "severe")
		for i = dialogs + 1, #B.dialogs do assert(B.dialogs[i].which ~= "OLYMPUS_CHAT_PRIVACY", "the privacy warning shown") end
		Fresh(B)
		eq(select(2, w.As(B, B.C.Confirm, { tier = "A", text = "a " .. WORD, channel = "OlympusChannel" }, true)), "severe")
		eq(#w.wire, 0)
		B.ns.db.chatWarned = { A = true, C = true, L = true }
		-- Guild: the game's own send.
		local native = 0
		C_ChatInfo.SendChatMessage = function() native = native + 1 end
		eq(Refused(B, B.R.Send, "guild", "a " .. WORD).where, "R:guild")
		eq(native, 0, "the game's send never called")
		Fresh(B); w.epoch = w.epoch + 10
		assert(w.As(B, B.R.Send, "guild", "a clean guild line")); eq(native, 1)
		C_ChatInfo.SendChatMessage = nil
		-- A role room (the High Council's) and a Church room (an audience another file keeps).
		eq(Refused(Co, Co.R.Send, "council", "a " .. WORD).where, "R:council")
		w.As(D, D.R.RegisterAudience, "church", { CanAccess = function() return true end, Recipients = function() return { B.name } end })
		eq(Refused(D, D.R.Send, "church", "a " .. WORD).where, "R:church")
		-- A provider's room (a squad's, a craft deal's): its send never called.
		local provided = 0
		w.As(D, D.R.RegisterProvider, { Info = function(id) if id == "sq:test" then return { label = "squad" } end end,
			CanAccess = function() return true end, History = function() return {} end, Send = function() provided = provided + 1 return true end })
		eq(Refused(D, D.R.Send, "sq:test", "a " .. WORD).where, "R:sq:test")
		eq(provided, 0)
		Fresh(D); w.epoch = w.epoch + 10
		assert(w.As(D, D.R.Send, "sq:test", "a clean squad line")); eq(provided, 1)
		-- A pin (a guild master's for his guild): refused, nothing queued; paused, refused before it is read.
		eq(Refused(G, G.C.SetPin, "pinned " .. WORD .. " for all").where, "P")
		eq(select(2, w.As(G, G.C.SetPin, "a clean pin")), "paused")
		-- CanWrite (the channel's link in the game's chat) while paused.
		Fresh(B); Strike(w, B)
		eq(w.As(B, B.C.CanWrite, "A"), false)
		eq(w.As(B, B.C.CanWrite, "A", true), false)
		Fresh(B)
		eq(w.As(B, B.C.CanWrite, "A"), true)
		-- A reply: what he typed, apart from his quote of another's line.
		local codec = ReplyCodec()
		w.epoch = w.epoch + 5
		w.wire = {}
		assert(w.As(B, B.C.Send, "A", codec.EncodeReply({ who = D.name, text = "their " .. WORD .. " line" }, "my clean answer")))
		eq(#w.wire, 1); assert(not w.wire[1].msg:find(WORD, 1, true), "the quote dropped: " .. w.wire[1].msg)
		assert(w.wire[1].msg:find("my clean answer", 1, true))
		w.Run()
		eq(#B.S.Store().mine, 0, "no warning for the quote")
		w.epoch = w.epoch + 5
		eq(select(2, w.As(B, B.C.Send, "A", codec.EncodeReply({ who = D.name, text = "a clean line" }, "my " .. WORD))), "severe")
		eq(B.S.Store().mine[1].text, "my " .. WORD)
	end)
end)

test("watch: chat moderation: strikes: the team's side takes MS only as a logged whisper of 255 bytes at most, from his own name, on a team member's client, within its counts, rates and order; the net-off backstop leaves it alone", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		local id = w.epoch
		local head = ("MS~1~H~%d~3~3~3~1~%s"):format(id, X)
		local line = ("MS~1~L~%d~1~%d~3~A~%s~a %s"):format(id, id, WORD, WORD)
		local function Refused(why, dist, to, msg, logged, from)
			local ok, got = w.Inject(dist, from or B.name, to, msg, logged)
			eq(ok, false, why); eq(got, why, why)
		end
		Refused("lane", "CHANNEL", Co, head)
		Refused("lane", "GUILD", Co, head)
		Refused("unlogged", "WHISPER", Co, head, false)
		Refused("audience", "WHISPER", D, head)
		Refused("size", "WHISPER", Co, head .. string.rep("x", 255))
		Refused("count", "WHISPER", Co, ("MS~1~H~%d~3~3~3~6~%s"):format(id, X))
		Refused("count", "WHISPER", Co, ("MS~1~H~%d~2~3~3~1~%s"):format(id, X))
		Refused("guild", "WHISPER", Co, ("MS~1~H~%d~3~3~3~1~%s"):format(id, "Some Other Guild"))
		Refused("time", "WHISPER", Co, ("MS~1~H~%d~3~3~3~1~%s"):format(id + 3600, X))
		Refused("head", "WHISPER", Co, line)
		Refused("self", "WHISPER", Co, head, true, Co.name)
		-- The real one: kept under the server's name for its sender.
		eq(w.Inject("WHISPER", B.name, Co, head), true)
		eq(w.Inject("WHISPER", B.name, Co, line), true)
		local c = Co.S.Store().cases[Fold(B.name) .. "#" .. id]
		assert(c); eq(c.lines[1].text, "a " .. WORD); eq(c.name, B.name)
		-- Again: kept already (acknowledged quietly); an older id from him: refused.
		local ok, why = w.Inject("WHISPER", B.name, Co, head)
		eq(ok, true); eq(why, "repeat")
		Refused("old", "WHISPER", Co, ("MS~1~H~%d~3~3~3~1~%s"):format(id - 10, X))
		-- At most six heads an hour from one sender.
		for i = 1, 6 do w.Inject("WHISPER", Y1.name, Co, ("MS~1~H~%d~3~3~3~1~%s"):format(id + i, Y)) end
		Refused("rate", "WHISPER", Co, ("MS~1~H~%d~3~3~3~1~%s"):format(id + 7, Y), true, Y1.name)
		-- A line whose fields are not clean.
		eq(w.Inject("WHISPER", D.name, Co, ("MS~1~H~%d~3~3~3~1~%s"):format(id, X)), true)
		Refused("field", "WHISPER", Co, ("MS~1~L~%d~1~%d~3~A~%s~ two  spaces"):format(id, id, WORD), true, D.name)
		-- A ping or a decision about a case this client never had.
		Refused("case", "WHISPER", Co, ("MS~1~P~%d"):format(id + 99))
		-- (Never in Moderation's net-off backstop: the player's own obligation, as a result or a receipt.)
		eq(ns.Moderation.BLOCKED.MS, nil)
		eq(ns.Moderation.BLOCKED.MD, true)
	end)
end)

test("watch: chat moderation: strikes: in a lockdown a struck line is still struck, and the report waits for it to end", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local locked = true
		C_ChatInfo.InChatMessagingLockdown = function() return locked end
		local e3 = Held(w, B)
		eq(e3.n, 3)
		eq(#w.wire, 0, "no report in a lockdown")
		w.epoch = w.epoch + 60; Refresh(w); w.As(B, B.S.Tick)
		eq(#w.wire, 0)
		locked = false
		w.epoch = w.epoch + 60; Refresh(w); w.As(B, B.S.Tick)
		eq(w.wire[1].msg:sub(1, 7), "MS~1~H~", "sent once it ends")
		w.Run()
		C_ChatInfo.InChatMessagingLockdown = nil
	end)
end)

test("watch: chat moderation: strikes: the team's page and dialog: named moderators see it, open cases first; the dialog lets him chat, times him out or shows every line; on the King's stream the words are hidden", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		local key = CaseKey(B, e3)
		eq(w.As(Mo, Mo.WC.PageShown), true, "an Olympus moderator sees the Chat moderation page")
		eq(w.As(D, D.WC.PageShown), false)
		local function PageText(cl)
			local out = {}
			for _, l in ipairs(w.As(cl, cl.WC.PageLines)) do out[#out + 1] = tostring(l.text) end
			return table.concat(out, "\n"), w.As(cl, cl.WC.PageLines)
		end
		local text, lines = PageText(Mo)
		assert(text:find(Mo.ns.L.WATCHCHAT_STRIKES_TITLE, 1, true), "the cases")
		assert(text:find(Mo.ns.L.WATCHCHAT_STRIKE_OPEN, 1, true))
		assert(not text:find(WORD, 1, true), "the words only in the tooltip, the dialog, the copy")
		local row
		for _, l in ipairs(lines) do if l.onClick and tostring(l.text):find("Member", 1, true) then row = l end end
		assert(row, "the case's row")
		local said = {}
		local tt = { AddLine = function(_, s) said[#said + 1] = s end }
		row.tooltip(tt)
		assert(table.concat(said, "\n"):find(WORD, 1, true), "his words in the tooltip")
		w.As(Mo, row.onClick)
		local d = w.Dialog(Mo, "OLYMPUS_WATCHCHAT_STRIKE")
		eq(d.a, Mo.ns.L.WATCHCHAT_STRIKE_ASK:format("Member", 3, WORD)); eq(d.data.key, key)
		-- Show all: the copy pop-up, each line with its words, and the note.
		local copied
		Mo.ns.UI.ShowCopy = function(title, body, _, opts) copied = { title = title, body = body, key = opts and opts.key } end
		w.As(Mo, StaticPopupDialogs.OLYMPUS_WATCHCHAT_STRIKE.OnAlt, nil, d.data)
		eq(copied.title, Mo.ns.L.WATCHCHAT_STRIKES_TITLE); eq(copied.key, "watch-strike")
		for _, part in ipairs({ "first " .. WORD, "second " .. WORD, "third " .. WORD, Mo.ns.L.WATCHCHAT_STRIKE_COPY_NOTE, X }) do
			assert(copied.body:find(part, 1, true), "the copy holds: " .. part)
		end
		-- Time out...: WatchChat's own timeout dialogs.
		w.As(Mo, StaticPopupDialogs.OLYMPUS_WATCHCHAT_STRIKE.OnCancel, nil, d.data, "clicked")
		eq(w.Dialog(Mo, "OLYMPUS_WATCHCHAT_TIME").data.name, B.name)
		-- /oly watch strikes: the open cases in the copy pop-up.
		copied = nil
		w.As(Mo, Mo.S.Slash, "strikes", "")
		assert(copied and copied.body:find("third " .. WORD, 1, true))
		-- On the King's stream: names cut, words and lines hidden.
		Mo.masked = true
		copied = nil
		w.As(Mo, Mo.S.Slash, "strikes", "")
		assert(not copied.body:find(WORD, 1, true), "hidden on the stream")
		assert(copied.body:find(Mo.ns.L.NETOFF_REASON_HIDDEN, 1, true))
		assert(not w.As(Mo, Mo.S.AskText, Mo.S.Store().cases[key]):find(WORD, 1, true))
		said = {}
		row.tooltip(tt)
		assert(not table.concat(said, "\n"):find(WORD, 1, true), "the tooltip too")
		Mo.masked = false
		-- Let them chat: from the dialog; then /oly watch release finds nothing open.
		w.As(Mo, StaticPopupDialogs.OLYMPUS_WATCHCHAT_STRIKE.OnAccept, nil, d.data)
		w.Run()
		eq(w.As(B, B.S.Block), nil)
		assert(w.Printed(Mo, Mo.ns.L.WATCHCHAT_STRIKE_DONE:format("Member")))
		eq(w.As(Mo, Mo.S.Slash, "release", "Member"), false)
		assert(w.Printed(Mo, Mo.ns.L.WATCHCHAT_STRIKE_NOT_FOUND:format("Member")))
		text = PageText(Mo)
		assert(text:find(Mo.ns.L.WATCHCHAT_STRIKE_LET_BY:format("Modder"), 1, true), "decided, and by whom")
		-- Not a moderator: no command.
		eq(w.As(D, D.S.Slash, "strikes", ""), nil)
		assert(w.Printed(D, D.ns.L.WATCH_NO_ACCESS))
	end)
end)

test("watch: chat moderation: strikes: /oly watch release <name> lets the newest open case of that name chat; a client rebuilt from the same saved store keeps the count and the hold", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e1 = Strike(w, B); Past(w, e1)
		B = Rebuild(w, B)
		local e2 = Strike(w, B)
		eq(e2.n, 2, "the count kept")
		Past(w, e2)
		local e3 = Strike(w, B)
		w.Run(); Tick(w, B)
		B = Rebuild(w, B)
		eq(w.As(B, B.S.Block).kind, "hold", "the hold kept")
		eq(select(2, w.As(B, B.C.Send, "A", "after a reload")), "paused")
		assert(w.As(Co, Co.S.Slash, "release", "Member"))
		w.Run()
		eq(w.As(B, B.S.Block), nil)
		eq(Co.S.Store().cases[CaseKey(B, e3)].decided.op, "R")
	end)
end)

-- (The review: "decided?" always went to the first of the team who kept the report, and a "Let them
-- chat" reached only who was online then. One who missed it kept the case open on his page, and the
-- player asked him alone every 10 minutes for 30 days: held, though the team had decided.)
test("watch: chat moderation: strikes: \"Let them chat\" reaches whoever missed it: a team member away at the decision is told when back; and the held player's \"decided?\" goes round the team in turn, so one who knows answers", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		local key = CaseKey(B, e3)
		for _, cl in ipairs({ Au, K, Co, Mo }) do eq(B.S.Store().out.to[Fold(cl.name)].acked, true, cl.short) end
		-- The author and the player away; the moderator lets him chat.
		Au.online, B.online = false, false
		w.epoch = w.epoch + 5
		assert(w.As(Mo, Mo.S.Release, key))
		w.Run()
		for _, cl in ipairs({ K, Co, Mo }) do eq(cl.S.Store().cases[key].decided.op, "R", cl.short) end
		eq(Au.S.Store().cases[key].decided, nil, "away: not heard")
		local tell = Mo.S.Store().cases[key].tell
		eq(tell[Fold(K.name)].acked, true, "the King's client said it keeps it"); eq(tell[Fold(Au.name)].acked, nil)
		-- Back within the tries: the moderator's client tells him again, and only him and the player.
		Au.online = true
		Tick(w, Mo, Mo.S.RETRY)
		eq(Au.S.Store().cases[key].decided.op, "R", "told when back")
		eq(Fold(Au.S.Store().cases[key].decided.by), Fold(Mo.name))
		eq(tell[Fold(Au.name)].acked, true)
		local function ToAuthor()
			local n = 0
			for _, s in ipairs(w.Sent("MS~1~D~")) do if Fold(Full(s.target)) == Fold(Au.name) then n = n + 1 end end
			return n
		end
		local before = ToAuthor()
		Tick(w, Mo, Mo.S.RETRY)
		eq(ToAuthor(), before, "kept: not told again")
		Tick(w, Mo, Mo.S.RETRY)
		eq(tell[Fold(B.name)].tries, 3, "the player away: three times at most")
		-- Back, the player asks; the author's client knows it now.
		B.online = true
		B = Rebuild(w, B)
		w.epoch = w.epoch + B.S.PING
		Refresh(w)
		w.As(B, B.S.Tick)
		w.Run()
		eq(w.As(B, B.S.Block), nil)
		-- The next hold the same day; this time the author misses the decision entirely (away through
		-- every try). Back, the player's "decided?" asks the author first, then the next of the team.
		local e4 = Strike(w, B, "fourth " .. WORD)
		w.Run(); Tick(w, B)
		local key4 = CaseKey(B, e4)
		for _, cl in ipairs({ Au, K, Co, Mo }) do eq(B.S.Store().out.to[Fold(cl.name)].acked, true, cl.short) end
		Au.online, B.online = false, false
		w.epoch = w.epoch + 5
		assert(w.As(Mo, Mo.S.Release, key4))
		w.Run()
		Tick(w, Mo, Mo.S.RETRY); Tick(w, Mo, Mo.S.RETRY)
		Au.online = true
		B = Rebuild(w, B) -- (his next login)
		eq(w.As(B, B.S.Block).kind, "hold", "away through every try: not heard")
		local asked = {}
		for _ = 1, 2 do
			w.epoch = w.epoch + B.S.PING
			Refresh(w)
			w.As(B, B.S.Tick)
			for _, job in ipairs(w.wire) do if job.msg == ("MS~1~P~%d"):format(e4.at) then asked[#asked + 1] = Fold(Full(job.target)) end end
			w.Run()
		end
		eq(asked[1], Fold(Au.name), "the first of the team who kept it")
		eq(asked[2], Fold(K.name), "then the next one, not the same again")
		eq(w.As(B, B.S.Block), nil, "the King's client knew it: the hold is over")
		eq(B.S.Store().mine[#B.S.Store().mine].decided.op, "R")
		eq(Au.S.Store().cases[key4].decided, nil, "(the author's page: told no more after three tries)")
	end)
end)

-- (The review: the hold is the account's, but "Let them chat" was whispered only to the character
-- that typed the line, and another character of his never asked: it stayed blocked.)
test("watch: chat moderation: strikes: \"Let them chat\" while he plays another character of his account: that character, linked, is told; away then, it asks when back", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local Alt = w.Client("Alternate", X, 3)
		Alt.ns.rdb = B.ns.rdb -- (the account's other character, the same saved store)
		Alt.ns.Workshop.AuthorOnline, Alt.ns.Workshop.AuthorName = B.ns.Workshop.AuthorOnline, B.ns.Workshop.AuthorName
		w.links[Fold(B.name)], w.links[Fold(Alt.name)] = { Alt.name }, { B.name }
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		B.online = false -- (he logs out, and plays the alt)
		eq(select(2, w.As(Alt, Alt.C.Send, "A", "from the alt")), "paused", "the account is held")
		w.epoch = w.epoch + 5
		assert(w.As(Mo, Mo.S.Release, CaseKey(B, e3)))
		w.Run()
		eq(w.As(Alt, Alt.S.Block), nil, "told on the alt")
		assert(w.Printed(Alt, Alt.ns.L.WATCHCHAT_STRIKE_RELEASED))
		w.Say(Alt, "A", "the alt chats")
		assert(w.Line(D, "A", Alt.name, "the alt chats"))
		-- Again, both characters away at the decision and through its tries: back on the alt, it asks.
		B.online = true
		local e4 = Strike(w, B, "fourth " .. WORD)
		w.Run(); Tick(w, B)
		B.online, Alt.online = false, false
		w.epoch = w.epoch + 5
		assert(w.As(Mo, Mo.S.Release, CaseKey(B, e4)))
		w.Run()
		Tick(w, Mo, Mo.S.RETRY); Tick(w, Mo, Mo.S.RETRY)
		Alt.online = true
		eq(w.As(Alt, Alt.S.Block).kind, "hold")
		local heads = #w.Sent("MS~1~H~")
		w.epoch = w.epoch + Alt.S.PING
		Refresh(w)
		w.As(Alt, Alt.S.Tick)
		eq(#w.wire, 1); eq(w.wire[1].msg, ("MS~1~P~%d"):format(e4.at)); eq(w.wire[1].from, Alt, "the alt asks")
		w.Run()
		eq(#w.Sent("MS~1~H~"), heads, "it never reports: the character that typed it does")
		eq(w.As(Alt, Alt.S.Block), nil, "the team's answer ended it")
		eq((w.As(Alt, Alt.C.Send, "A", "free again")), true)
	end)
end)

-- (The review: SamePerson's links and the receiver's limits had no test of their own.)
test("watch: chat moderation: strikes: an Olympus moderator's timeout on a character his player linked decides the hold too, on his client and on the team's", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local Alt = w.Client("Alternate", X, 3) -- (a saved store of its own here: only the links tie them)
		w.links[Fold(B.name)], w.links[Fold(Alt.name)] = { Alt.name }, { B.name }
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		local key = CaseKey(B, e3)
		w.epoch = w.epoch + 5
		Refresh(w)
		assert(w.As(Mo, Mo.WC.Timeout, Alt.name, 3600, "the team's call"))
		w.Run()
		eq(B.S.Store().mine[3].decided.op, "T", "decided by the alt's timeout")
		eq(w.As(B, B.S.Block), nil)
		for _, cl in ipairs({ Au, K, Co, Mo }) do eq(cl.S.Store().cases[key].decided.op, "T", cl.short) end
	end)
end)

test("watch: chat moderation: strikes: the team's side keeps its limits: 30 reports in ten minutes from everyone, 20 still coming, 6 \"decided?\" an hour from one name, one notice a name in ten minutes and one open case; a report heard after the team's timeout comes decided; his client sends nothing while Comm's queue is short", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		local id = w.epoch
		local function Head(n) return ("MS~1~H~%d~3~3~3~1~%s"):format(n, X) end
		local function Line(n) return ("MS~1~L~%d~1~%d~3~A~%s~a %s"):format(n, n, WORD, WORD) end
		-- 30 reports from 30 names in ten minutes: the 31st is refused.
		for i = 1, 30 do
			local who = "Sender" .. i .. "-Realm"
			eq(w.Inject("WHISPER", who, Co, Head(id)), true, who)
			eq(w.Inject("WHISPER", who, Co, Line(id)), true, who)
		end
		local ok, why = w.Inject("WHISPER", "Sender31-Realm", Co, Head(id))
		eq(ok, false); eq(why, "rate", "all senders' budget")
		-- 20 reports whose lines are still coming: the 21st is refused until a slot frees.
		w.epoch = w.epoch + 601
		for i = 1, 20 do eq(w.Inject("WHISPER", "Waiter" .. i .. "-Realm", Co, Head(id)), true) end
		ok, why = w.Inject("WHISPER", "Waiter21-Realm", Co, Head(id))
		eq(ok, false); eq(why, "busy")
		w.epoch = w.epoch + Co.S.PENDING_FOR + 1
		eq(w.Inject("WHISPER", "Waiter21-Realm", Co, Head(id)), true, "two minutes on: the slots free")
		-- "Decided?": 6 an hour from one name.
		for i = 1, 6 do eq(w.Inject("WHISPER", "Sender1-Realm", Co, ("MS~1~P~%d"):format(id)), true, "ping " .. i) end
		ok, why = w.Inject("WHISPER", "Sender1-Realm", Co, ("MS~1~P~%d"):format(id))
		eq(ok, false); eq(why, "rate")
		-- One notice a name in ten minutes; his newer report replaces his open one.
		w.epoch = w.epoch + 601
		local function Notices(name)
			local n = 0
			for _, p in ipairs(Co.prints) do if p:find(Co.ns.L.WATCHCHAT_STRIKE_IN:format(name, 3), 1, true) then n = n + 1 end end
			return n
		end
		local t = w.epoch
		for i = 0, 1 do
			eq(w.Inject("WHISPER", "Twice-Realm", Co, Head(t + i)), true)
			eq(w.Inject("WHISPER", "Twice-Realm", Co, Line(t + i)), true)
		end
		eq(Notices("Twice"), 1, "one notice for two reports within ten minutes")
		eq(Co.S.Store().cases[Fold("Twice-Realm") .. "#" .. t], nil, "one open case a name: the newer one")
		assert(Co.S.Store().cases[Fold("Twice-Realm") .. "#" .. (t + 1)])
		w.epoch = w.epoch + 601
		eq(w.Inject("WHISPER", "Twice-Realm", Co, Head(w.epoch)), true)
		eq(w.Inject("WHISPER", "Twice-Realm", Co, Line(w.epoch)), true)
		eq(Notices("Twice"), 2, "ten minutes on: told again")
		-- An Olympus moderator's timeout on him heard before his report: the case comes decided.
		local before = w.epoch
		Refresh(w)
		assert(w.As(Mo, Mo.WC.Timeout, B.name, 3600, "the team's call"))
		w.Run()
		eq(w.Inject("WHISPER", B.name, Co, Head(before - 10)), true)
		eq(w.Inject("WHISPER", B.name, Co, Line(before - 10)), true)
		eq(Co.S.Store().cases[Fold(B.name) .. "#" .. (before - 10)].decided.op, "T", "decided by the timeout heard first")
		-- His client, held: nothing while Comm's queue has less room than the report and its spare.
		Words(w, WORD)
		local room = 3 + 1 + D.S.QUEUE_SPARE - 1
		D.ns.Comm.QueueRoom = function() return room end
		Held(w, D)
		eq(#w.wire, 0, "nothing queued")
		Tick(w, D)
		eq(#w.wire, 0)
		room = room + 1
		w.epoch = w.epoch + 60
		w.As(D, D.S.Tick)
		eq(#w.wire, 2 * 4, "room enough: the report goes")
		w.Run()
	end)
end)

-- (The review: one name's made-up reports, within the rates, could push a real case off a team
-- member's client: the oldest open case went first once there were more than 100.)
test("watch: chat moderation: strikes: a name's flood of made-up reports pushes out no one else's case: his own open one stays and is let chat; a team member who no longer keeps it says so and is sent it again", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		local key = CaseKey(B, e3)
		-- Six an hour (the most one name gets in) for 18 hours: 108 reports from Y1.
		for _ = 1, 18 do
			for i = 1, 6 do
				local id = w.epoch + i
				eq(w.Inject("WHISPER", Y1.name, Co, ("MS~1~H~%d~3~3~3~1~%s"):format(id, Y)), true)
				eq(w.Inject("WHISPER", Y1.name, Co, ("MS~1~L~%d~1~%d~3~A~%s~a %s"):format(id, id, WORD, WORD)), true)
			end
			w.epoch = w.epoch + 3600
		end
		assert(Co.S.Store().cases[key], "his case kept")
		local his = 0
		for _, c in pairs(Co.S.Store().cases) do if Fold(c.name) == Fold(Y1.name) then his = his + 1 end end
		eq(his, 1, "one open case a name")
		-- Past the cap, the name with the most cases goes first (here a hundred open ones of one name,
		-- all newer than his: the oldest open one went first before).
		local s = Mo.S.Store()
		for i = 1, 100 do s.cases["flood#" .. i] = { name = "Flood-Realm", id = w.epoch - 1000 + i, n = 3, heard = w.epoch, lines = {} } end
		w.As(Mo, Mo.S.Prune, s)
		assert(s.cases[key], "a flood of one name's cases goes before his")
		-- A team member who no longer keeps it (lost from his saved store): asked, he says so; sent again.
		Au.S.Store().cases[key] = nil
		w.epoch = w.epoch + B.S.PING
		Refresh(w)
		w.As(B, B.S.Tick)
		eq(w.wire[#w.wire].msg, ("MS~1~P~%d"):format(e3.at)); eq(Fold(Full(w.wire[#w.wire].target)), Fold(Au.name))
		w.Run()
		eq(B.S.Store().out.to[Fold(Au.name)].acked, nil, "not kept there: to send again")
		Tick(w, B)
		assert(Au.S.Store().cases[key], "sent again, kept")
		eq(B.S.Store().out.to[Fold(Au.name)].acked, true)
		assert(w.As(Co, Co.S.Slash, "release", "Member"))
		w.Run()
		eq(w.As(B, B.S.Block), nil)
	end)
end)

-- (The review: the login's notice, The Watch's commands and CanWrite's telling had no test.)
test("watch: chat moderation: strikes: at login a held player is told why in a pop-up, even right after another; CanWrite says why; the team's commands go through /oly watch", function()
	World(function(w)
		local G, A, B, D, Y1 = Standard(w)
		local Au, K, Co, Mo = Team(w)
		Words(w, WORD)
		local e3 = Held(w, B)
		w.Run(); Tick(w, B)
		B = Rebuild(w, B) -- (his next login)
		eq(select(2, w.As(B, B.C.Send, "A", "a clean line")), "paused")
		local dialogs = #B.dialogs
		eq(B.dialogs[dialogs].a, B.ns.L.WATCHCHAT_STRIKE_HELD, "a pop-up a moment ago")
		local printed = #B.prints
		eq(w.As(B, B.C.CanWrite, "A", true), false)
		eq(#B.prints, printed + 1, "CanWrite says why (a red line within the minute)")
		assert(B.prints[#B.prints]:find(B.ns.L.WATCHCHAT_STRIKE_HELD, 1, true), B.prints[#B.prints])
		eq(#B.dialogs, dialogs)
		for _, f in ipairs(B.listeners.LOGIN or {}) do w.As(B, f) end
		w.epoch = w.epoch + 30
		w.Run()
		eq(#B.dialogs, dialogs + 1, "the login's pop-up, though one was shown a moment ago")
		eq(B.dialogs[#B.dialogs].which, "OLYMPUS_WATCHCHAT_DECISION"); eq(B.dialogs[#B.dialogs].a, B.ns.L.WATCHCHAT_STRIKE_HELD)
		-- /oly watch strikes and /oly watch release <name>: The Watch's own command.
		local copied
		Mo.ns.UI.ShowCopy = function(_, body) copied = body end
		w.As(Mo, Mo.W.Slash, "strikes")
		assert(copied and copied:find("third " .. WORD, 1, true), "the open cases to copy")
		assert(w.As(Co, Co.W.Slash, "release Member"))
		w.Run()
		eq(w.As(B, B.S.Block), nil)
		eq(Co.S.Store().cases[CaseKey(B, e3)].decided.op, "R")
	end)
end)
