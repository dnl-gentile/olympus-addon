-- Whole-transfer scheduling and callback lifetimes through the real Comm module.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]transport%.lua$")) or "./"

local function WithComm(fn)
	local names = { "GetTime", "GetGuildInfo", "IsInGuild", "GetChannelName", "JoinChannelByName",
		"LeaveChannelByName", "HideChannelFromChat", "C_ChatInfo" }
	local saved = {}
	for _, name in ipairs(names) do saved[name] = _G[name] end
	local w = { now = 1000, guild = "Olympus II", rank = 1, sharing = true,
		channels = { OlympusNet = 5 }, sent = {}, errors = {}, timers = {}, events = {}, listeners = {} }
	local ok, err = pcall(function()
		GetTime = function() return w.now end
		GetGuildInfo = function() return w.guild, "Member", 3 end
		IsInGuild = function() return w.guild ~= nil end
		GetChannelName = function(name) return w.channels[name] or 0, name end
		JoinChannelByName, LeaveChannelByName, HideChannelFromChat = function() end, function() end, function() end
		local function Send(_, msg, dist, target)
			local entry = { msg = msg, dist = dist, target = target, at = w.now }
			w.sent[#w.sent + 1] = entry
			-- (1.4.0: as newer clients answer, Enum.SendAddonMessageResult: 11 during a chat lockdown,
			-- else what w.result says for this send; 0 is success.)
			local res = w.locked and 11 or (w.result and w.result(entry))
			if res ~= nil then
				if res == 0 and w.receive then w.receive(entry) end
				return res
			end
			local success = not w.fail or not w.fail(entry)
			if success and w.receive then w.receive(entry) end
			return success
		end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = Send, SendAddonMessageLogged = Send,
			InChatMessagingLockdown = function() return w.locked == true end }
		local c = setmetatable({ db = { blocked = {} }, rdb = {}, realm = "Realm", me = "Tester-Realm", faction = "Alliance" }, { __index = ns })
		c.Now = function() return 1800000000 + w.now end
		c.On = function(name, call) w.listeners[name] = call end
		c.After = function(delay, label, call) w.timers[#w.timers + 1] = { at = w.now + delay, label = label, call = call } end
		c.RegisterEvent = function(name, call) w.events[name] = call end
		c.Every, c.Fire, c.Print, c.Log = function() end, function() end, function() end, function() end
		c.SafeCall = function(label, call, ...)
			local called, why = pcall(call, ...)
			if not called then w.errors[#w.errors + 1] = label .. ": " .. tostring(why) end
		end
		c.Data = {}
		c.Moderation = { Blocks = function() return false end, OwnGuildOff = function() return w.off == true end }
		c.Layers = { Sharing = function() return w.sharing end }
		c.Roster = { IsOfficer = function() return w.rank <= 1 end }
		c.Keys = { HandOutMessage = function() return "K8~fixture" end }
		assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", c)
		local C = c.Comm
		C.JoinChannel()
		function w.login()
			assert(w.listeners.LOGIN)()
			w.timers = {} -- Startup timers are unrelated to the lifecycle under test.
		end
		function w.message(msg, dist, sender)
			assert(w.events.CHAT_MSG_ADDON)(c.PREFIX, msg, dist or "GUILD", sender or "Peer-Realm")
		end
		function w.runTimers(label)
			local calls, kept = {}, {}
			for _, timer in ipairs(w.timers) do
				if timer.label == label then calls[#calls + 1] = timer else kept[#kept + 1] = timer end
			end
			w.timers = kept
			for _, timer in ipairs(calls) do w.now = math.max(w.now, timer.at); timer.call() end
			return #calls
		end
		function w.step(count)
			for _ = 1, count or 1 do
				w.now = w.now + 1.2
				local before = #w.sent
				C.Pump()
				assert(#w.sent - before <= 1, "at most one game send API per pump")
				assert(C.QueueSize() >= 0 and C.QueueSize() <= C.MAX_QUEUE, "bounded message count")
				eq(C.QueueRoom(), C.MAX_QUEUE - C.QueueSize(), "capacity counts unsent messages")
			end
		end
		function w.moveChannel(name, id)
			w.channels[name] = id
			c.rdb.realmKey = name
			-- Follow the actual channel-change path; the derived name is assigned its game ID.
			local derived = C.ChannelSpec()
			w.channels[derived] = id
			C.JoinChannel()
		end
		function w.messages(prefix)
			local out = {}
			for _, entry in ipairs(w.sent) do
				if not prefix or entry.msg:sub(1, #prefix) == prefix then out[#out + 1] = entry end
			end
			return out
		end
		fn(w, C, c)
		eq(#w.errors, 0, table.concat(w.errors, "\n"))
	end)
	for _, name in ipairs(names) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

local function Parts(count, id)
	return ns.Codec.Chunk(string.rep("x", (count - 1) * ns.Codec.CHUNK + 1), id)
end

test("transport: impossible batch admission preserves unrelated accepted work", function()
	WithComm(function(w, C)
		local finished, rejected = 0, 0
		for i = 1, 40 do assert(C.Whisper("Peer-Realm", "Q1~urgent" .. i, nil, true)) end
		for i = 1, 10 do
			assert(C.Whisper("Peer-Realm", "Q1~ordinary" .. i, nil, nil, nil, function(sent)
				assert(sent, "impossible admission must not evict unrelated ordinary work")
				finished = finished + 1
			end))
		end
		eq(C.SendBatch("WHISPER", Parts(30, "full"), nil, "Peer-Realm", nil, function(sent)
			eq(sent, false); rejected = rejected + 1
		end), false)
		eq(C.QueueSize(), 50); eq(finished, 0); eq(rejected, 1)
		w.step(50)
		eq(finished, 10); eq(#w.sent, 50); eq(C.QueueSize(), 0)
	end)
end)

test("transport: a lower trusted lane converges once and stale higher hellos cannot oscillate it", function()
	WithComm(function(w, C, c)
		c.rdb.channelLane = 3
		eq(C.Lane(), 3)
		assert(C.TakeLane(1, "Captain-Realm"))
		eq(C.Lane(), 1)
		eq(C.TakeLane(3, "Captain-Realm"), false, "a stale higher hello cannot undo convergence")
		assert(C.NextLane("refused"))
		eq(C.Lane(), 2, "a real channel refusal may move upward again")
	end)
end)

test("transport: a chunked signed-authority whisper is assembled privately and exactly once", function()
	WithComm(function(w, C, c)
		w.login()
		local got = {}
		C.Handle("H2", function(dist, sender, text) got[#got + 1] = { dist, sender, text } end)
		local payload = "H2~HA1~" .. string.rep("a", c.Codec.CHUNK * 3)
		local pieces = c.Codec.Chunk(payload, "auth")
		for _, piece in ipairs(pieces) do w.message(piece, "WHISPER", "Peer-Realm") end
		eq(#got, 1); eq(got[1][1], "WHISPER"); eq(got[1][2], "Peer-Realm"); eq(got[1][3], payload)
		for _, piece in ipairs(c.Codec.Chunk("Q1~" .. string.rep("x", 500), "other")) do
			w.message(piece, "WHISPER", "Peer-Realm")
		end
		eq(#got, 1, "no other long whisper type reaches the authority handler")
	end)
end)

test("transport: an ordinary message cannot evict any of sixty accepted urgent messages", function()
	WithComm(function(w, C)
		local delivered, dropped = 0, 0
		for i = 1, 60 do
			C.Whisper("Peer-Realm", "Q1~urgent" .. i, nil, true, nil, function(sent)
				if sent then delivered = delivered + 1 else dropped = dropped + 1 end
			end)
		end
		eq(C.QueueSize(), 60)
		C.Send("GUILD", "Q1~ordinary")
		eq(dropped, 0, "admission cannot displace an accepted urgent request")
		w.step(60)
		eq(delivered, 60); eq(dropped, 0); eq(#w.messages("Q1~ordinary"), 0)
		eq(C.QueueSize(), 0)
	end)
end)

test("transport: keyed coalescing keeps the newest callback and payload", function()
	WithComm(function(w, C)
		local calls = {}
		C.Whisper("Peer-Realm", "Q1~old", "same", nil, nil, function(sent)
			calls[#calls + 1] = "old:" .. tostring(sent)
		end)
		C.Whisper("Peer-Realm", "Q1~new", "same", nil, nil, function(sent)
			calls[#calls + 1] = "new:" .. tostring(sent)
		end)
		w.step(5)
		eq(table.concat(calls, ","), "new:true")
		eq(#w.sent, 1); eq(w.sent[1].msg, "Q1~new"); eq(C.QueueSize(), 0)
	end)
end)

test("transport: keyed coalescing replaces owner identity before cancellation", function()
	WithComm(function(w, C)
		local owner, calls = {}, {}
		assert(C.Whisper("Old-Realm", "Q1~old", "same", nil, nil, function(sent)
			calls[#calls + 1] = "old:" .. tostring(sent)
		end))
		assert(C.Whisper("New-Realm", "Q1~new", "same", true, nil, function(sent)
			calls[#calls + 1] = "new:" .. tostring(sent)
		end, { owner = owner }))
		eq(table.concat(calls, ","), "")
		eq(C.Cancel(owner), 1, "the replacement owns the one coalesced job")
		eq(table.concat(calls, ","), "new:false")
		eq(#w.sent, 0); eq(C.Cancel(owner), 0); eq(C.QueueSize(), 0)
	end)
end)

test("transport: an urgent batch waits for the active batch instead of orphaning it", function()
	WithComm(function(w, C)
		local completed = {}
		assert(C.SendBatch("WHISPER", Parts(6, "first"), nil, "Peer-Realm", nil, function(sent)
			assert(sent); completed[#completed + 1] = "first"
		end))
		w.step()
		assert(C.SendBatch("WHISPER", Parts(4, "second"), nil, "Peer-Realm", true, function(sent)
			assert(sent); completed[#completed + 1] = "second"
		end))
		w.step(20)
		eq(table.concat(completed, ","), "first,second"); eq(C.QueueSize(), 0)
		eq(#w.sent, 10)
		for i, entry in ipairs(w.sent) do
			assert(entry.msg:find(i <= 6 and "Cfirst:" or "Csecond:", 1, true) == 1, "whole transfers retain order")
		end
	end)
end)

test("transport: thirty fragments beat the old assembler deadline under sustained chat and urgent load", function()
	WithComm(function(w, C)
		local payload = "T9~" .. string.rep("x", ns.Codec.CHUNK * 30 - 3)
		local pieces, assembler = ns.Codec.Chunk(payload, "bank"), ns.Codec.NewAssembler()
		local complete, result, first, last, chatMax, chats, urgent = false, nil, nil, nil, 0, 0, 0
		w.receive = function(entry)
			eq(ns.Codec.Gc(assembler, entry.at), 0, "old 60-second receiver never discards the transfer")
			if entry.msg:sub(1, 6) == "Cbank:" then
				first, last = first or entry.at, entry.at
				result = ns.Codec.Feed(assembler, "Sender-Realm", entry.msg, entry.at) or result
			end
		end
		assert(C.SendBatch("WHISPER", pieces, nil, "Peer-Realm", nil, function(sent)
			assert(sent); complete = true
		end))
		w.step() -- Start the transfer before filling both competing lanes.
		local function Chat()
			local queued = w.now
			assert(C.SendChat("M1~A~Olympus II~1~~chat", function(sent)
				assert(sent, "a full chat lane must not time out during the transfer")
				chats, chatMax = chats + 1, math.max(chatMax, w.now - queued)
				if not complete then Chat() end
			end))
		end
		local function Urgent()
			assert(C.Whisper("Peer-Realm", "LQ~1~1453~7", nil, true, nil, function(sent)
				assert(sent); urgent = urgent + 1
				if not complete then Urgent() end
			end))
		end
		for _ = 1, 6 do Chat() end
		Urgent()
		w.step(46)
		assert(complete, "all thirty parts complete despite sustained competing traffic")
		eq(result, payload); eq(assembler.open, 0)
		assert(math.abs(last - first - 55.2) < 0.00001, "five of eight slots bound the transfer to 55.2 seconds")
		assert(chatMax <= 28.8 + 0.00001, "six-part chat queue is served within its thirty-second lifetime")
		assert(chats >= 10 and urgent >= 5, "both competing lanes made progress")
		w.step(20)
		eq(C.QueueSize(), 0); eq(C.Stats().chatQueue, 0)
	end)
end)

test("transport: a failed fragment aborts its tail and frees capacity once", function()
	WithComm(function(w, C)
		local calls = {}
		w.fail = function(entry) return entry.msg:find("Cfail:2:", 1, true) == 1 end
		assert(C.SendBatch("WHISPER", Parts(5, "fail"), nil, "Peer-Realm", nil, function(sent, why)
			calls[#calls + 1] = tostring(sent) .. ":" .. tostring(why)
		end))
		assert(C.Whisper("Peer-Realm", "Q1~after"))
		w.step(20)
		eq(table.concat(calls), "false:failed")
		eq(#w.messages("Cfail:"), 2, "failed attempt plus first piece; no unsent tail")
		eq(#w.messages("Q1~after"), 1); eq(C.QueueSize(), 0); eq(C.QueueRoom(), 60)
	end)
end)

test("transport: channel changes cancel started transfers and chat while unstarted army work follows", function()
	WithComm(function(w, C)
		local first, second, chat
		assert(C.SendBatch("CHANNEL", Parts(5, "old"), nil, nil, nil, function(sent, why) first = { sent, why } end))
		w.step()
		assert(C.SendBatch("CHANNEL", Parts(3, "new"), nil, nil, nil, function(sent) second = sent end))
		assert(C.SendChat("M1~A~Olympus II~1~~private audience", function(sent, why) chat = { sent, why } end))
		w.moveChannel("secret", 9)
		w.step(15)
		eq(first[1], false); eq(first[2], "moved"); eq(second, true)
		eq(chat[1], false); eq(chat[2], "moved")
		eq(#w.messages("Cold:"), 1); eq(#w.messages("Cnew:"), 3); eq(#w.messages("M1~"), 0)
		for _, entry in ipairs(w.messages("Cnew:")) do eq(entry.target, 9) end
		eq(C.QueueSize(), 0)
	end)
end)

test("transport: a renumbered channel preserves an active transfer's original audience", function()
	WithComm(function(w, C)
		local completed
		assert(C.SendBatch("CHANNEL", Parts(3, "number"), nil, nil, nil, function(sent) completed = sent end))
		w.step()
		w.channels.OlympusNet = 12
		w.step(5)
		eq(completed, true); eq(#w.sent, 3); eq(w.sent[1].target, 5)
		eq(w.sent[2].target, 12); eq(w.sent[3].target, 12)
	end)
end)

test("transport: a stalled active transfer expires rather than sending a stale tail", function()
	WithComm(function(w, C)
		local calls = {}
		assert(C.SendBatch("WHISPER", Parts(4, "stale"), nil, "Peer-Realm", nil, function(sent, why)
			calls[#calls + 1] = tostring(sent) .. ":" .. tostring(why)
		end))
		w.step()
		w.now = w.now + 60
		w.step(5)
		eq(#w.sent, 1); eq(table.concat(calls), "false:late"); eq(C.QueueSize(), 0)
	end)
end)

test("transport: a guard can cancel its active owner and enqueue replacement work", function()
	WithComm(function(w, C)
		local owner, revoke, calls = {}, false, 0
		assert(C.SendBatch("WHISPER", Parts(4, "guard"), nil, "Peer-Realm", nil, function(sent)
			eq(sent, false); calls = calls + 1
			assert(C.Whisper("Peer-Realm", "Q1~replacement"))
		end, { owner = owner, guard = function()
			if revoke then C.Cancel(owner); return false end
			return true
		end }))
		w.step(); revoke = true; w.step(5)
		eq(calls, 1); eq(#w.messages("Cguard:"), 1)
		eq(#w.messages("Q1~replacement"), 1); eq(C.QueueSize(), 0)
	end)
end)

test("transport: guild transitions cancel work once and distinguish a new Olympus guild from leaving", function()
	WithComm(function(w, C)
		local calls, chat = {}, 0
		local function Completed(label)
			return function(sent, why) calls[#calls + 1] = label .. ":" .. tostring(sent) .. ":" .. tostring(why) end
		end
		assert(C.SendBatch("GUILD", Parts(4, "guild"), nil, nil, nil, Completed("active")))
		w.step()
		assert(C.Send("GUILD", "H1~old", nil, true, nil, Completed("queued")))
		assert(C.SendChat("M1~A~Olympus II~1~~old guild", function(sent, why)
			eq(sent, false); eq(why, "left"); chat = chat + 1
		end))
		w.guild = "Olympus New"
		w.step(5)
		table.sort(calls)
		eq(table.concat(calls, ","), "active:false:guild,queued:false:guild")
		eq(chat, 1); eq(#w.sent, 1); eq(C.QueueSize(), 0)
		assert(C.Send("GUILD", "H1~new")); w.step()
		eq(w.sent[2].msg, "H1~new", "the new guild session remains usable")
		local left
		assert(C.Send("GUILD", "H1~leaving", nil, nil, nil, function(sent, why)
			left = tostring(sent) .. ":" .. tostring(why)
		end))
		w.guild = "Ordinary Guild"
		w.step()
		eq(left, "false:left", "leaving Olympus keeps the established completion reason")
		eq(#w.sent, 2); eq(C.QueueSize(), 0)
	end)
end)

test("transport: malformed single messages are refused once without retaining queue state", function()
	WithComm(function(w, C)
		local calls = 0
		local function Done(sent) eq(sent, false); calls = calls + 1 end
		eq(C.Send("GUILD", nil, "invalid", nil, nil, Done), false)
		eq(C.Send("GUILD", string.rep("x", 256), "invalid", nil, nil, Done), false)
		eq(C.Whisper("Peer-Realm", {}, "invalid", nil, nil, Done), false)
		eq(C.Whisper("Peer-Realm", string.rep("x", 256), "invalid", nil, nil, Done), false)
		eq(calls, 4); eq(C.QueueSize(), 0)
		assert(C.Send("GUILD", "Q1~valid", "invalid")); w.step(5)
		eq(#w.sent, 1); eq(w.sent[1].msg, "Q1~valid"); eq(calls, 4)
	end)
end)

test("transport: census fragments stop when location consent or network membership is revoked", function()
	for _, change in ipairs({ "sharing", "off" }) do
		WithComm(function(w, C, c)
			local report = { guild = w.guild, leader = c.me, total = 100, online = 30, zones = {}, officers = {} }
			for i = 1, 20 do report.zones["Zone " .. i] = 1 end
			assert(#ns.Codec.EncodeReport(report) > ns.Codec.CHUNK, "real report needs several fragments")
			C.Broadcast(report); w.step()
			eq(#w.sent, 1)
			if change == "sharing" then w.sharing = false else w.off = true end
			w.step(20)
			eq(#w.sent, 1, change .. ": pending fragments do not outlive the current permission")
			eq(C.QueueSize(), 0)
			if change == "sharing" then
				local received, assembler = nil, ns.Codec.NewAssembler()
				w.receive = function(entry) received = ns.Codec.Feed(assembler, "Sender-Realm", entry.msg, entry.at) or received end
				C.Broadcast(report); w.step(20)
				assert(received, "a new report without location remains allowed")
				eq(next(assert(ns.Codec.DecodeReport(received)).zones), nil)
			end
		end)
	end
end)

test("transport: delayed guild key replies recheck guild and officer authority before and after enqueue", function()
	for _, phase in ipairs({ "timer", "queue" }) do
		for _, change in ipairs({ "guild", "rank" }) do
			WithComm(function(w, C, c)
				w.login(); c.rdb.realmKey = "fixture-secret"
				w.message("K0~")
				if phase == "queue" then
					eq(w.runTimers("key answer"), 1); eq(C.QueueSize(), 1, "the current reply alone is queued (1.4.0: no plain K1)")
				end
				if change == "guild" then w.guild = "Olympus New" else w.rank = 3 end
				if phase == "timer" then eq(w.runTimers("key answer"), 1) end
				w.step(10)
				eq(#w.messages("K1~"), 0, phase .. ": " .. change)
				eq(#w.messages("K8~"), 0, phase .. ": " .. change)
				eq(C.QueueSize(), 0)
			end)
		end
	end
	WithComm(function(w, C, c)
		w.login(); c.rdb.realmKey = "fixture-secret"
		w.message("K0~"); eq(w.runTimers("key answer"), 1); w.step(5)
		eq(#w.messages("K1~"), 0, "1.4.0: no plain K1"); eq(#w.messages("K8~"), 1, "unchanged authorized guild replies still work")
	end)
end)

test("transport: guild assemblies and peer observations cannot cross a guild session", function()
	WithComm(function(w, C)
		w.login()
		local delivered, payload = 0, "HS~" .. string.rep("signed-list-fixture", 30)
		-- Transport invokes the registered handler only once all parts of this session arrive.
		C.Handle("HS", function(dist, _, text) eq(dist, "GUILD"); eq(text, payload); delivered = delivered + 1 end)
		local parts = ns.Codec.Chunk(payload, "oldguild")
		w.message("H1~1.1.2~Realm~p~z", "GUILD", "Old-Realm")
		eq(C.PeerCount(), 1); eq(C.PeerVersion("Old-Realm"), "1.1.2"); eq(C.SharesZone("Old-Realm"), true)
		w.message(parts[1])
		w.guild = "Olympus New"
		for i = 2, #parts do w.message(parts[i]) end
		eq(delivered, 0, "old first fragment cannot complete in the new guild")
		eq(C.PeerCount(), 0); eq(C.PeerVersion("Old-Realm"), nil); eq(C.SharesZone("Old-Realm"), false)
		for _, piece in ipairs(ns.Codec.Chunk(payload, "newguild")) do w.message(piece) end
		eq(delivered, 1, "a complete transfer in the current guild still reaches its handler")
	end)
end)

-- 1.4.0 (the queue's audit, scenarios S3 to S5): the game's "not now" holds the queue instead of
-- failing its jobs, and a keyed message re-sent on a timer keeps its place in line.
test("transport (1.4.0): a chat lockdown holds the forty waiting jobs instead of failing them, and all of them go once it lifts", function()
	WithComm(function(w, C)
		local done = {}
		for i = 1, 40 do
			assert(C.Whisper("Peer-Realm", "Q1~job" .. i, nil, i % 4 == 0, nil, function(sent, why)
				done[#done + 1] = tostring(sent) .. ":" .. tostring(why)
			end))
		end
		w.locked = true
		w.step(50) -- a minute in a dungeon
		eq(#done, 0, "no job ends during the lockdown")
		eq(#w.sent, 0, "nothing is handed to the game while it would refuse it")
		eq(C.QueueSize(), 40)
		eq(C.Stats().held, true, "/oly status says the queue is held")
		w.locked = false
		w.step(45)
		eq(#done, 40)
		for i, d in ipairs(done) do eq(d, "true:nil", "job " .. i) end
		eq(#w.messages("Q1~job"), 40, "each one once")
		eq(C.QueueSize(), 0); eq(C.Stats().held, false)
	end)
end)

test("transport (1.4.0): a throttled piece is tried again after a growing wait, and its transfer completes whole", function()
	WithComm(function(w, C)
		local calls, refused = {}, 0
		w.result = function(entry)
			if entry.msg:find("Cthrottle:2:", 1, true) == 1 and refused < 2 then refused = refused + 1; return refused == 1 and 3 or 8 end
			return 0
		end
		assert(C.SendBatch("WHISPER", Parts(5, "throttle"), nil, "Peer-Realm", nil, function(sent, why)
			calls[#calls + 1] = tostring(sent) .. ":" .. tostring(why)
		end))
		w.step(30)
		eq(table.concat(calls, ","), "true:nil", "the transfer is not ended by the game's throttle")
		eq(refused, 2)
		local tries = {}
		for _, entry in ipairs(w.messages("Cthrottle:2:")) do tries[#tries + 1] = entry.at end
		eq(#tries, 3, "refused twice, then sent")
		assert(tries[2] - tries[1] >= 2 and tries[3] - tries[2] >= 4, "the pump waits 2 s, then 4 s: " .. table.concat(tries, ", "))
		eq(#w.messages("Cthrottle:"), 7, "five pieces, two of them refused once more")
		eq(C.QueueSize(), 0); eq(C.Stats().retried, 2)
	end)
end)

test("transport (1.4.0): a job the game keeps throttling ends after RETRY_MAX tries; a lockdown's refusal never counts", function()
	WithComm(function(w, C)
		local stuck, held
		w.result = function(entry)
			if entry.msg == "Q1~stuck" then return 8 end
			-- An old-style lockdown refusal (no lockdown query on that client): six of them in a row.
			if entry.msg == "Q1~held" and #w.messages("Q1~held") <= 6 then return 11 end
			return 0
		end
		assert(C.Whisper("Peer-Realm", "Q1~stuck", nil, nil, nil, function(sent, why) stuck = tostring(sent) .. ":" .. tostring(why) end))
		assert(C.Whisper("Peer-Realm", "Q1~held", nil, nil, nil, function(sent, why) held = tostring(sent) .. ":" .. tostring(why) end))
		assert(C.Whisper("Peer-Realm", "Q1~after"))
		w.step(300) -- (eleven refusals in a row: the pump waits 2, 4, 8, 15, then 30 s each)
		eq(stuck, "false:8", "given up, with the game's answer")
		eq(#w.messages("Q1~stuck"), 5)
		eq(held, "true:nil", "held through more refusals than RETRY_MAX, then sent")
		eq(#w.messages("Q1~held"), 7)
		eq(#w.messages("Q1~after"), 1, "the rest of the queue goes on")
		eq(C.QueueSize(), 0)
	end)
end)

test("transport (1.4.0): a keyed message re-sent every 15 s behind a busy queue keeps its place and goes out", function()
	WithComm(function(w, C)
		local filler, asks, positions = 0, 0, {}
		-- Twenty-one other messages always wait (the audit's S3: from thirteen, none went out).
		local function TopUp()
			while C.QueueSize() < 21 do
				filler = filler + 1
				assert(C.Whisper("Peer-Realm", "Q1~filler" .. filler))
			end
		end
		TopUp()
		local start, nextAt, newest = w.now, w.now, nil
		while w.now - start < 600 do
			if w.now >= nextAt then
				newest = "P1~position~" .. asks
				asks, nextAt = asks + 1, nextAt + 15
				assert(C.Send("GUILD", newest, "position"))
			end
			local before = #w.sent
			w.step()
			for i = before + 1, #w.sent do
				if w.sent[i].msg:find("^P1~position~") then
					eq(w.sent[i].msg, newest, "the newest position, never an older one")
					positions[#positions + 1] = w.sent[i].msg
				end
			end
			TopUp()
		end
		eq(asks, 40)
		assert(#positions >= 15, "the position keeps going out: " .. #positions .. " of " .. asks)
	end)
end)

test("transport (1.4.0): after a lockdown longer than HOLD_MAX the work that waited all along is dropped, newer work goes", function()
	WithComm(function(w, C)
		local old, new
		assert(C.Whisper("Peer-Realm", "Q1~before", nil, nil, nil, function(sent, why) old = tostring(sent) .. ":" .. tostring(why) end))
		w.locked = true
		w.step()
		w.now = w.now + 660 -- eleven minutes in a raid
		assert(C.Whisper("Peer-Realm", "Q1~recent", nil, nil, nil, function(sent, why) new = tostring(sent) .. ":" .. tostring(why) end))
		w.step()
		w.locked = false
		w.step(5)
		eq(old, "false:dropped", "no longer news; a must-deliver module offers it again (as for a full queue)")
		eq(new, "true:nil")
		eq(#w.messages("Q1~before"), 0); eq(#w.messages("Q1~recent"), 1)
		eq(C.QueueSize(), 0)
	end)
end)

test("transport (1.4.0): a replaced keyed message keeps its seat at the lane's end, in the middle or in another lane, and the queue drains in order", function()
	WithComm(function(w, C)
		local function Order()
			local out = {}
			for _, entry in ipairs(w.sent) do out[#out + 1] = entry.msg:match("^Q1~(.+)$") end
			return table.concat(out, ",")
		end
		-- At the end of its lane, with work ahead of it and none after.
		assert(C.Whisper("Peer-Realm", "Q1~a")); assert(C.Whisper("Peer-Realm", "Q1~b"))
		assert(C.Whisper("Peer-Realm", "Q1~k1", "k")); assert(C.Whisper("Peer-Realm", "Q1~k2", "k"))
		assert(C.Whisper("Peer-Realm", "Q1~c"))
		w.step(10)
		eq(Order(), "a,b,k2,c"); eq(C.QueueSize(), 0)
		-- In the middle, then moved to the urgent lane: ahead of every urgent job queued after its seat.
		w.sent = {}
		assert(C.Whisper("Peer-Realm", "Q1~d")); assert(C.Whisper("Peer-Realm", "Q1~m1", "m"))
		assert(C.Whisper("Peer-Realm", "Q1~e")); assert(C.Whisper("Peer-Realm", "Q1~u", nil, true))
		assert(C.Whisper("Peer-Realm", "Q1~m2", "m", true))
		w.step(10)
		eq(Order(), "m2,u,d,e"); eq(C.QueueSize(), 0); eq(C.QueueRoom(), 60)
	end)
end)
