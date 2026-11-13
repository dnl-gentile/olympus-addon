-- GitHub #76: a relay's snapshot in pieces must reach every registered reporter whole, without
-- pushing out the single words waiting beside it (a verifier's approval).
local ns, test, eq, extra = ...

test("relay fan-out (#76): with 46 guilds registered, the relay's own snapshot in pieces reaches every reporter whole, and a verifier's approval sent with it reaches every reporter too", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, fn) timers[#timers + 1] = fn end
		for i = 1, 46 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- An approval, then an 8-piece global census snapshot handed in as Relay.Out's own path does
		-- (1.5.4 review: the approval first, which 1.5.3's fan-out pushed out of the queue: 0 of 46).
		local approval = "GV~1~A~1794011276~Olympus Dawn~Some Master-CAMWOWUS2Realm7PvE"
		R.Relay.HandleIn("WHISPER", R.me, "RL~L~" .. approval)
		local snapshot = "CG~2~S~1~ForeverPvE~Alliance~" .. ("Olympus Dawn,640,40,300,1;"):rep(66)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "77")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		for _ = 1, 2000 do
			-- (1.5.5) One pump each SEND_INTERVAL, as in the game: the approval is a logged word (L), which
			-- the relay's chat lane hands on at CHAT_PER_MIN, so it waits for time to pass.
			R.clock = R.clock + 1.2
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end

		-- Each reporter puts back together what it was sent: the RM envelopes, then the snapshot.
		local whole, approved, fewest = 0, 0, 0
		-- The snapshot wrapped once for a reporter, cut into full whispers: the fewest it can take.
		local least = math.ceil(#("RM~P~" .. R.me .. "~" .. snapshot) / R.Codec.CHUNK)
		for i = 1, 46 do
			local outer, inner, prefix = R.Codec.NewAssembler(), R.Codec.NewAssembler(), ("Rep Number%d-"):format(i)
			local got, ok, whispers = false, false, 0
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					if s.msg:sub(1, 3) ~= "RM~" then whispers = whispers + 1 end
					if body == approval then ok = true
					elseif body and (body == snapshot or R.Codec.Feed(inner, "origin", body, 0) == snapshot) then got = true end
				end
			end
			if got then whole = whole + 1 end
			if ok then approved = approved + 1 end
			if whispers == least then fewest = fewest + 1 end
		end
		eq(whole, 46, "every reporter can put the whole snapshot together")
		eq(approved, 46, "the snapshot's batches never push the approval out of the queue")
		eq(fewest, 46, ("each reporter gets the snapshot in %d full whispers, not a piece and its label apart"):format(least))
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

-- 1.5.4 (the review of #81 and #82): a relay's own census report keeps its pieces (reports decode
-- from pieces alone, and a whole "R2~" word reached every reporter's Comm and went nowhere), and two
-- different words of one kind from one origin never take each other's place in the drip.
test("relay fan-out (1.5.4): the relay's own census report reaches each reporter in its pieces; two different words of one kind both reach every reporter", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, fn) timers[#timers + 1] = fn end
		for i = 1, 46 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		local report = "R2~" .. ("Olympus II,1,2,3;"):rep(30)
		local first, second = "T1~H~" .. ("a"):rep(400), "T1~N~" .. ("b"):rep(400)
		for _, word in ipairs({ { report, "91" }, { first, "92" }, { second, "93" } }) do
			for _, p in ipairs(R.Codec.Chunk(word[1], word[2])) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		end
		for _ = 1, 3000 do
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end
		local whole, pieced, both = 0, 0, 0
		for i = 1, 46 do
			local outer, prefix = R.Codec.NewAssembler(), ("Rep Number%d-"):format(i)
			local inner = R.Codec.NewAssembler()
			local got = {}
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					if body == report then got.whole = true end
					local assembled = body and (body:match("^C%w+:") and R.Codec.Feed(inner, "origin", body, 0) or body)
					if assembled then got[assembled] = true end
				end
			end
			if got.whole then whole = whole + 1 end
			if got[report] and not got.whole then pieced = pieced + 1 end
			if got[first] and got[second] then both = both + 1 end
		end
		eq(whole, 0, "no reporter is sent the report as one whole word")
		eq(pieced, 46, "every reporter can put the report together from its pieces")
		eq(both, 46, "neither word of the same kind takes the other's place")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

-- What each reporter could put together from what the relay sent it: the words, and how often each.
local function Assembled(R, sent, prefix)
	local outer, inner, got = R.Codec.NewAssembler(), R.Codec.NewAssembler(), {}
	for _, s in ipairs(sent) do
		if s.target and s.target:sub(1, #prefix) == prefix then
			local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
			local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
			local word = body and (body:match("^C%w+:%d+:%d+:") and R.Codec.Feed(inner, "origin", body, 0) or body)
			if word then got[word] = (got[word] or 0) + 1 end
		end
	end
	return got
end

local function Relayed(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(delay, _, f) timers[#timers + 1] = { at = R.clock + (tonumber(delay) or 0), f = f } end
		-- One pump each SEND_INTERVAL (1.2 s), the timers due by then first.
		local function Run(pumps)
			for _ = 1, pumps do
				R.clock = R.clock + 1.2
				local due, keep = {}, {}
				for _, t in ipairs(timers) do if t.at <= R.clock then due[#due + 1] = t else keep[#keep + 1] = t end end
				timers = keep
				for _, t in ipairs(due) do t.f() end
				R.Comm.Pump()
			end
		end
		fn(R, sent, Run)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end

-- The review of the 1.5.4 candidate: a reporter's batch the queue pushed out before it began (two
-- chat lines to every reporter arriving at once) goes back to the front while it is fresh, but its
-- time counted from when it was queued: a round of 35 reporters takes more than SET_WAIT, so past
-- the first minute no batch was ever put back and that reporter waited another whole round. Its
-- time counts from its own turn now. Fails before (one reporter without the snapshot).
test("relay fan-out (1.5.4): a snapshot batch pushed out of the queue before it began goes back to its reporter, SET_WAIT counted from its own turn", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 35
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		local raw, handed, start, burst = R.Comm.SendBatch, 0, R.clock, nil
		R.Comm.SendBatch = function(dist, pieces, key, target, urgent, done, options)
			local queued = raw(dist, pieces, key, target, urgent, done, options)
			if done and dist == "WHISPER" and tostring(target):find("^Rep Number") then
				handed = handed + 1
				if handed == 20 and not burst then
					-- Two chat lines arrive before the 20th reporter's batch began (a whisper to each reporter).
					burst = R.clock - start
					for line = 1, 2 do
						R.Relay.HandleIn("WHISPER", "Some Member-CAMWOWUS2Realm3PvE", ("RL~L~M1~W~Guild 7~%d~WA~hello there, line %d"):format(line, line))
					end
				end
			end
			return queued
		end
		local snapshot = ("CG~2~S~1~ForeverPvE~Alliance~" .. ("OLYMPUS GUILD NAME,640,40,300,1794011276;"):rep(108)):sub(1, 20 * 220 - 30)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "501")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		Run(3000)
		eq(burst ~= nil and burst > R.Relay.SET_WAIT, true, "the 20th reporter's turn came past SET_WAIT after the batches were queued")
		local whole = 0
		for i = 1, REPORTERS do
			if Assembled(R, sent, ("Rep Number%d-"):format(i))[snapshot] then whole = whole + 1 end
		end
		eq(whole, REPORTERS, "every reporter can put the snapshot together, the one whose batch was pushed out too")
	end)
end)

-- The review of the 1.5.4 candidate: a batch in flight is no longer in the drip, so a newer copy of
-- its word for that reporter was appended as an entry of its own, and when the queue pushed the batch
-- out it went back to the front with its older whispers: that reporter was sent the superseded
-- snapshot, and the newest one a whole round of reporters later. The put-back takes the newer copy's
-- whispers in its place. Fails before (the pushed-out reporter is sent both copies).
-- (1.5.9) A census snapshot's batch waits in the queue as an urgent job now, which no burst pushes out
-- (Relay.lua's CensusTransfer): the reporter whose batch of the older snapshot was in the queue gets that
-- copy whole and then the newer one, the others the newer alone. (1.5.9's review: the drip's pace) That
-- holds for every batch the drip hands over within its pace, census or not: an ordinary whisper waiting
-- in the queue when the older word came (busy). A batch handed past the pace, while nothing else waited
-- (idle), goes as an ordinary job instead, and a burst pushes it out before it begins: it goes back as the
-- newer copy, as in 1.5.4. Either way no reporter is sent the older copy unless its batch was in the
-- queue, and never halves of two copies.
test("relay fan-out (1.5.4): a batch pushed out of the queue while a newer copy of its word already waits goes back as the newer copy, never the older; (1.5.9) a drip batch handed over within the drip's pace, census or not, is never pushed out", function()
	local function Case(older, newer, census, busy)
		Relayed(function(R, sent, Run)
			local C = R.Comm
			local label = (census and "census snapshot" or "other word") .. (busy and ", busy" or ", idle")
			for i = 1, 3 do
				R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
			end
			-- A transfer to somebody else under way: the first reporter's batch waits in the queue behind it.
			local filler = {}
			for i = 1, 34 do filler[i] = ("C900:%d:34:"):format(i) .. ("f"):rep(200) end
			eq(C.SendBatch("WHISPER", filler, nil, "Filler Target-CAMWOWUS2Realm7PvE", false), true)
			C.Pump()
			eq(C.QueueSize(), 30, "the transfer began: four parts went")
			-- (busy) An ordinary whisper waiting: the batch goes within the pace, urgent.
			local waiting = busy and 1 or 0
			if busy then C.Whisper("Filler Target-CAMWOWUS2Realm7PvE", "X1~waiting", nil, false, false) end
			for _, p in ipairs(R.Codec.Chunk(older, "77")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
			local batch = C.QueueSize() - 30 - waiting
			eq(batch > 0, true, label .. ": the first reporter's batch of the older word waits in the queue, behind the transfer")
			for _, p in ipairs(R.Codec.Chunk(newer, "78")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
			eq(C.QueueSize(), 30 + waiting + batch, label .. ": the newer word waits in the drip, not in the queue")
			-- A burst of single whispers (two chat lines to every reporter): it pushes out the oldest
			-- ordinary jobs waiting, never an urgent one.
			for i = 1, 40 do C.Whisper("Filler Target-CAMWOWUS2Realm7PvE", "X1~burst " .. i, nil, false, false) end
			Run(3000)
			eq(C.QueueSize(), 0, label .. ": everything went out")
			local olderSent, newerSent = 0, 0
			for i = 1, 3 do
				local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
				if got[older] then olderSent = olderSent + 1 end
				if got[newer] then newerSent = newerSent + 1 end
			end
			eq(newerSent, 3, label .. ": every reporter gets the newer word")
			if busy then
				-- (Whichever reporter the relay handed its batch first: the others' waited in the drip.)
				eq(olderSent, 1, label .. ": the batch stayed in the queue: its reporter alone gets the older copy, whole")
			else
				eq(olderSent, 0, label .. ": the pushed-out batch went back as the newer copy: no reporter is sent the older")
			end
		end)
	end
	for _, busy in ipairs({ false, true }) do
		Case("T1~H~" .. ("a"):rep(400), "T1~H~" .. ("b"):rep(400), false, busy)
		Case("CG~2~S~1~ForeverPvE~Alliance~" .. ("Olympus Dawn,640,40,300,1;"):rep(66),
			"CG~2~S~2~ForeverPvE~Alliance~" .. ("Olympus Dawn,641,41,300,2;"):rep(66), true, busy)
	end
end)

-- The review of the 1.5.4 candidate: a batch waits a whole round of reporters, and Drip sent it to the
-- name DripSet stored without asking whether his guild still had that reporter: one it had replaced
-- (an older client's election churn, a logout) was sent up to 34 wasted whispers, and when he had
-- logged off the server's "No player named" line showed in the relay's chat, which QuietLine hides
-- for current reporters alone. A batch for a name no guild has as its reporter any more is left out.
-- Fails before (the whole batch goes to the replaced name).
test("relay fan-out (1.5.4): a drip batch waiting for a reporter his guild has since replaced is not sent to him; the other guild's reporter still gets the snapshot", function()
	Relayed(function(R, sent, Run)
		local C = R.Comm
		local old, new, other = "Rep Alpha-CAMWOWUS2Realm7PvE", "Rep Alphanew-CAMWOWUS2Realm7PvE", "Rep Beta-CAMWOWUS2Realm7PvE"
		R.Relay.HandleIn("WHISPER", old, "RL~P~RR~Guild Alpha")
		R.Relay.HandleIn("WHISPER", other, "RL~P~RR~Guild Beta")
		-- The queue nearly full with whispers to somebody else: both batches wait in the drip. (1.5.9:
		-- urgent ones, which Comm never drops: a census batch takes the place of ordinary whispers still
		-- waiting now, so only those keep it in the drip.)
		for i = 1, C.MAX_QUEUE - 4 do C.Whisper("Busy Target-CAMWOWUS2Realm7PvE", "X1~busy " .. i, nil, true, false) end
		local snapshot = "CG~2~S~1~ForeverPvE~Alliance~" .. ("Guild Row,640,40,300,1;"):rep(70)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "55")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		eq(C.QueueSize(), C.MAX_QUEUE - 4, "no batch was handed to the queue yet")
		-- Guild Alpha's new reporter registers before the old one's turn comes.
		R.Relay.HandleIn("WHISPER", new, "RL~P~RR~Guild Alpha")
		Run(500)
		eq(C.QueueSize(), 0, "everything went out")
		local toOld = 0
		for _, s in ipairs(sent) do if s.target == old or s.target == ns.ShortName(old) then toOld = toOld + 1 end end
		eq(toOld, 0, "nothing goes to the reporter his guild replaced")
		eq(Assembled(R, sent, "Rep Beta-")[snapshot], 1, "the other guild's reporter gets the whole snapshot once")
	end)
end)

test("relay fan-out (1.5.4): a drip batch waiting for a reporter whose registration lapsed is not sent to him", function()
	Relayed(function(R, sent, Run)
		local C = R.Comm
		local old, other = "Rep Alpha-CAMWOWUS2Realm7PvE", "Rep Beta-CAMWOWUS2Realm7PvE"
		R.Relay.HandleIn("WHISPER", old, "RL~P~RR~Guild Alpha")
		R.Relay.HandleIn("WHISPER", other, "RL~P~RR~Guild Beta")
		-- (1.5.9: urgent, as above: they keep the census batches waiting in the drip.)
		for i = 1, C.MAX_QUEUE - 4 do C.Whisper("Busy Target-CAMWOWUS2Realm7PvE", "X1~busy " .. i, nil, true, false) end
		local snapshot = "CG~2~S~1~ForeverPvE~Alliance~" .. ("Guild Row,640,40,300,1;"):rep(70)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "55")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		eq(C.QueueSize(), C.MAX_QUEUE - 4, "no batch was handed to the queue yet")
		-- Alpha never registers again; Beta does; another client's word prunes Alpha (ToReporters).
		R.clock = R.clock + R.Relay.REPORTER_FOR + 1
		R.Relay.HandleIn("WHISPER", other, "RL~P~RR~Guild Beta")
		R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm7PvE", "RL~P~X1~a word")
		eq(R.Relay.Stats().reporters, 1, "Alpha's lapsed registration is gone")
		Run(500)
		eq(C.QueueSize(), 0, "everything went out")
		local toOld = 0
		for _, s in ipairs(sent) do if s.target == old or s.target == ns.ShortName(old) then toOld = toOld + 1 end end
		eq(toOld, 0, "nothing goes to the reporter whose registration lapsed")
		eq(Assembled(R, sent, "Rep Beta-")[snapshot], 1, "the fresh reporter gets the whole snapshot once")
	end)
end)

-- 1.5.9: what /oly bug says of a relay's drip (Diagnostics.lua's "relay here" line): the transfers
-- waiting, the census ones among them, and the longest any of them, and any census one, has waited,
-- never a name.
test("relay fan-out (1.5.9): Relay.DripStats counts the transfers waiting in the drip, the census ones apart, and the longest any of them, and any census one, has waited; no name", function()
	Relayed(function(R, sent, Run)
		local C = R.Comm
		local D = R.Relay.DripStats
		eq(D().waiting, 0); eq(D().oldest, nil)
		R.Relay.HandleIn("WHISPER", "Rep Alpha-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild Alpha")
		R.Relay.HandleIn("WHISPER", "Rep Beta-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild Beta")
		-- Urgent whispers fill the queue but for one place: what the relay hands its reporters waits in the drip.
		for i = 1, C.MAX_QUEUE - 1 do C.Whisper("Busy Target-CAMWOWUS2Realm7PvE", "X1~busy " .. i, nil, true, false) end
		for _, p in ipairs(R.Codec.Chunk("T1~H~" .. ("a"):rep(400), "61")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		R.clock = R.clock + 30
		local snapshot = "CG~2~S~1~ForeverPvE~Alliance~" .. ("Guild Row,640,40,300,1;"):rep(70)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "62")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		R.clock = R.clock + 10
		local d = D()
		eq(d.waiting, 4, "the word and the snapshot to each of the two reporters")
		eq(d.census, 2, "the snapshots")
		eq(d.oldest, 40, "the word waited since it came, the longest")
		eq(d.oldestCensus, 10, "the snapshots since they came")
		for _, v in pairs(d) do eq(type(v), "number", "counts and ages alone") end
		Run(500)
		eq(D().waiting, 0, "everything went out")
	end)
end)

-- 1.5.9's review (D1): a begun transfer that is not a census one (the relay's own word one whisper past
-- MAX_CHUNKS once wrapped: two batches) waited for free room for its second batch for good, so under a
-- steady load of ordinary whispers it held every census transfer behind it, and its receiver dropped the
-- first batch's pieces after 60 s. A begun transfer's next batch makes room now as a census one does
-- (Relay.lua's pace of the drip). Fails before (the second batch never went, and neither reporter took the
-- census snapshot in five minutes).
test("relay fan-out (1.5.9's review): a begun transfer's next batch goes under a steady load of ordinary whispers: the word arrives whole, and the census snapshot behind it reaches both reporters", function()
	Relayed(function(R, sent, Run)
		local C = R.Comm
		local alpha, beta = "Rep Alpha-CAMWOWUS2Realm7PvE", "Rep Beta-CAMWOWUS2Realm7PvE"
		R.Relay.HandleIn("WHISPER", alpha, "RL~P~RR~Guild Alpha")
		R.Relay.HandleIn("WHISPER", beta, "RL~P~RR~Guild Beta")
		local label = #("RM~P~" .. R.me .. "~")
		local size = R.Codec.CHUNK * R.Codec.MAX_CHUNKS - label + 1 -- one whisper past MAX_CHUNKS once wrapped whole
		local word = (("T9~Olympus~%d~"):format(1794011276) .. ("w"):rep(size)):sub(1, size)
		-- In a lull: the word's first batch to the first reporter begins.
		for _, p in ipairs(R.Codec.Chunk(word, "71")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		Run(1)
		-- Then ordinary whispers faster than the relay sends them (six each pump, four go), and the
		-- relay's census snapshot.
		local busy = 0
		local function Pressed(pumps)
			for _ = 1, pumps do
				for _ = 1, 6 do busy = busy + 1; C.Whisper("Busy Target-CAMWOWUS2Realm7PvE", "X1~busy " .. busy, nil, false, false) end
				Run(1)
			end
		end
		Pressed(5)
		local snapshot = "CG~2~S~1~ForeverPvE~Alliance~" .. ("Guild Row,640,40,300,1;"):rep(70)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "72")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		Pressed(250) -- (five minutes)
		local wholeWord = 0
		for _, who in ipairs({ "Rep Alpha-", "Rep Beta-" }) do
			local got = Assembled(R, sent, who)
			eq(got[snapshot], 1, who .. " took the census snapshot within five minutes")
			if got[word] == 1 then wholeWord = wholeWord + 1 end
		end
		eq(wholeWord >= 1, true, "the word begun in the lull arrived whole")
	end)
end)

-- The review of the 1.5.4 candidate: the relay's own repeats in pieces (the King's Hands and the
-- Treasury's words every 300 s, a ranking's repeat) were keyed by their message id, so each repeat
-- waited in the drip as one more batch behind the rest: on a busy relay the drip grew without end
-- and the census snapshots waited behind it. Its newer word of one kind takes the waiting copy's
-- place now, as a newer snapshot does. Fails before (every reporter gets the older copy too).
test("relay fan-out (1.5.4): the relay's own newer word in pieces takes its waiting copy's place in the drip; a word of another kind keeps its own", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- The queue full: the batches wait in the drip for room (they never push out what waits there).
		for i = 1, R.Comm.MAX_QUEUE do R.Comm.Whisper("Filler Target-CAMWOWUS2Realm7PvE", "X1~filler " .. i, "filler " .. i, false, false) end
		eq(R.Comm.QueueRoom(), 0)
		local older, other, newer = "T1~H~" .. ("a"):rep(400), "T1~N~" .. ("c"):rep(400), "T1~H~" .. ("b"):rep(400)
		for _, word in ipairs({ { older, "61" }, { other, "62" }, { newer, "63" } }) do
			for _, p in ipairs(R.Codec.Chunk(word[1], word[2])) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		end
		Run(400)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local olderSent, newerOnce, otherSent = 0, 0, 0
		for i = 1, REPORTERS do
			local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
			if got[older] then olderSent = olderSent + 1 end
			if got[newer] == 1 then newerOnce = newerOnce + 1 end
			if got[other] then otherSent = otherSent + 1 end
		end
		eq(olderSent, 0, "no reporter is sent the copy the newer word replaced")
		eq(newerOnce, REPORTERS, "each reporter gets the newer word, once")
		eq(otherSent, REPORTERS, "the word of another kind keeps its own place")
	end)
end)

-- The load review of the 1.5.4 candidate: each reporter's trickle of other clients' words
-- (REPORTER_RATE a minute) grew with the reporters, 320 whispers a minute at 80 of them against the
-- relay's 200 in all, and the census snapshots never found room in its queue. The reporters now
-- share TRICKLE_PER_MIN a minute, REPORTER_RATE at most each. Fails before (each of 60 reporters
-- took REPORTER_RATE a minute).
test("relay trickle (1.5.4): many reporters share TRICKLE_PER_MIN a minute of other clients' words, the same share each; a few still get REPORTER_RATE each", function()
	Relayed(function(R)
		local function Trial(reporters, minutes)
			R.Relay.Reset()
			for i = 1, reporters do
				R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
			end
			local got, raw = {}, R.Comm.Whisper
			R.Comm.Whisper = function(target, msg, ...)
				if tostring(target):find("^Rep Number") and tostring(msg):find("^RM~P~Some Client") then got[target] = (got[target] or 0) + 1 end
				return raw(target, msg, ...)
			end
			for second = 1, minutes * 60 do
				R.clock = R.clock + 1
				R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", ("RL~P~X1~word %d"):format(second))
			end
			R.Comm.Whisper = raw
			local total, least, most = 0, math.huge, 0
			for i = 1, reporters do
				local n = got[("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i)] or 0
				total, least, most = total + n, math.min(least, n), math.max(most, n)
			end
			return total, least, most
		end
		local rate, all = R.Relay.REPORTER_RATE, R.Relay.TRICKLE_PER_MIN
		-- Many: the share is TRICKLE_PER_MIN among them (one whisper each a minute here), plus the
		-- allowance each starts with (a wrapped piece, two whispers).
		local total, least, most = Trial(60, 5)
		eq(total <= all * 5 + 60 * 2, true, ("60 reporters in 5 minutes: %d whispers, at most %d"):format(total, all * 5 + 60 * 2))
		eq(total >= all * 5 * 0.9, true, ("and the share is spent: %d whispers"):format(total))
		eq(most - least <= 1, true, ("the same share each: %d to %d"):format(least, most))
		-- A few: REPORTER_RATE a minute each, as before.
		total, least, most = Trial(10, 5)
		eq(least >= rate * 5 and most <= rate * 6, true, ("10 reporters: %d to %d whispers each in 5 minutes"):format(least, most))
	end)
end)

-- The review of the 1.5.4 candidate: a reporter's allowance refilled a fraction at a time went to the
-- first word that fitted one whisper, so a word in two whispers (a census look in one chunk, as
-- Data.CapturePortable builds it, once wrapped with its carrier's name; any full piece of a word in
-- pieces) never passed again beside one short word every few seconds, with 10 reporters (REPORTER_RATE
-- each, "as before") or with 35 (60 a minute shared). A whole allowance at a time, taken in the order
-- the words come, as 1.5.3 did. Fails before (no look reached any reporter after the first minute).
test("relay trickle (1.5.4): a word in two whispers still gets through beside short words, with a few reporters and with many", function()
	Relayed(function(R)
		local function Trial(reporters, seconds)
			R.Relay.Reset()
			for i = 1, reporters do
				R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
			end
			local wide, small = {}, {}
			local rawBatch, rawWhisper = R.Comm.SendBatch, R.Comm.Whisper
			R.Comm.SendBatch = function(dist, pieces, key, target, ...)
				if tostring(target):find("^Rep Number") then wide[target] = (wide[target] or 0) + #pieces end
				return rawBatch(dist, pieces, key, target, ...)
			end
			R.Comm.Whisper = function(target, msg, ...)
				if tostring(target):find("^Rep Number") and tostring(msg):find("^RM~P~") then small[target] = (small[target] or 0) + 1 end
				return rawWhisper(target, msg, ...)
			end
			local start = R.clock
			for second = 1, seconds do
				R.clock = start + second
				if second % 2 == 0 then
					-- A look as Data.CapturePortable builds it, whole rows within one chunk (219-220 bytes here).
					local carrier = ("Look Carrier%d-CAMWOWUS2Realm1PvE"):format(second % 40)
					local rows = {}
					for k = 1, 3 do rows[k] = ("OLYMPUS FORCES OF EVIL,%d,43,300,1794011276"):format(100 + k) end
					local look = ("CX~3~S~%s~ForeverPvP~Alliance~3626,2100,19,%d~"):format(carrier, 1794011276 + second)
						.. table.concat(rows, ";")
					assert(#look <= R.Codec.CHUNK, "one chunk")
					R.Relay.HandleIn("WHISPER", carrier, "RL~P~" .. R.Codec.Chunk(look, tostring(second % 1000))[1])
				end
				if second % 6 == 0 then
					R.Relay.HandleIn("WHISPER", ("Some Asker%d-CAMWOWUS2Realm1PvE"):format(second % 40), ("RL~P~T7~%d"):format(second))
				end
				if second % 3 == 0 then R.Comm.Pump() end
			end
			R.Comm.SendBatch, R.Comm.Whisper = rawBatch, rawWhisper
			local fewest, most = math.huge, 0
			for i = 1, reporters do
				local name = ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i)
				fewest = math.min(fewest, (wide[name] or 0) / 2)
				most = math.max(most, (wide[name] or 0) + (small[name] or 0))
			end
			return fewest, most
		end
		local rate, all = R.Relay.REPORTER_RATE, R.Relay.TRICKLE_PER_MIN
		local looks, most = Trial(10, 300)
		eq(looks >= 5, true, ("10 reporters: each is handed a look in two whispers each minute: at least %d in 5 minutes"):format(looks))
		eq(most <= rate * 6, true, ("and no more than REPORTER_RATE a minute: at most %d whispers"):format(most))
		-- (The review, mixed versions: an allowance holds three whispers at the least, a window of 105 s here.)
		looks, most = Trial(35, 300)
		eq(looks >= 2, true, ("35 reporters: each is handed one about every 105 s: at least %d in 5 minutes"):format(looks))
		eq(most <= 3 + all / 35 * 5 + 1, true, ("and no more than his share: at most %d whispers"):format(most))
	end)
end)

-- (The same review.) A clock set back (time() is the computer's) starts a new allowance: a window
-- measured from a later second never froze the trickle until the clock caught up.
test("relay trickle (1.5.4): a clock set back starts a reporter's new allowance", function()
	Relayed(function(R)
		R.Relay.Reset()
		R.Relay.HandleIn("WHISPER", "Rep Number1-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild 1")
		local got, raw = 0, R.Comm.Whisper
		R.Comm.Whisper = function(target, msg, ...)
			if tostring(msg):find("^RM~P~Some Client") then got = got + 1 end
			return raw(target, msg, ...)
		end
		for i = 1, R.Relay.REPORTER_RATE + 1 do R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", ("RL~P~X1~spent %d"):format(i)) end
		eq(got, R.Relay.REPORTER_RATE, "the allowance spent")
		R.clock = R.clock - 3600
		R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", "RL~P~X1~after the clock went back")
		R.Comm.Whisper = raw
		eq(got, R.Relay.REPORTER_RATE + 1, "a new allowance after the clock went back")
	end)
end)

-- The review of the 1.5.4 candidate: another client's word in pieces passes the trickle whole or not
-- at all. A census report in three pieces (its two full pieces with their RM labels are two whispers
-- each, its last one more: five) can never reach a reporter whole, yet its first piece took the
-- allowance and the single words after it went to nobody. A last piece alone (its first ones refused
-- before) took a single word's place the same way. Fails before. (The same review, mixed versions:
-- with more than 20 reporters an allowance held two whispers, so a report in two pieces, three
-- whispers, never passed either, and no other guild's full report reached any guild through a busy
-- relay, which 1.5.3 let through whenever the allowance was full. It holds three at the least now.
-- Fails before: the two-piece report reached nobody with 35 reporters.)
test("relay trickle (1.5.4): a word in pieces that can never pass whole spends nothing, and the single words after it still pass; a census report in two pieces passes whole with many reporters too", function()
	Relayed(function(R)
		R.Relay.Reset()
		for i = 1, 35 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		R.clock = R.clock + 120 -- (every allowance full)
		local pieces, words, raw, rawBatch = 0, {}, R.Comm.Whisper, R.Comm.SendBatch
		local function Note(msg)
			msg = tostring(msg)
			if msg:find("^RM~P~Census Guy%-") then pieces = pieces + 1 end
			local w = msg:match("^RM~P~Some Client%-[^~]+~X2~(%d)~")
			if w then words[w] = (words[w] or 0) + 1 end
		end
		local function Watch()
			R.Comm.Whisper = function(target, msg, ...) Note(msg); return raw(target, msg, ...) end
			R.Comm.SendBatch = function(dist, list, key, target, ...)
				-- (a wrapped piece goes as the relay's own envelope in pieces: the first carries the label)
				if dist == "WHISPER" and type(list) == "table" and list[1] then Note(tostring(list[1]):match("^C%w+:1:%d+:(.*)$")) end
				return rawBatch(dist, list, key, target, ...)
			end
		end
		Watch()
		local report = R.Codec.Chunk("R2~" .. ("r"):rep(600), "7")
		eq(#report, 3, "a 603-byte census report is three pieces")
		for _, p in ipairs(report) do R.Relay.HandleIn("WHISPER", "Census Guy-CAMWOWUS2Realm3PvE", "RL~P~" .. p) end
		R.Relay.HandleIn("WHISPER", "Census Guy-CAMWOWUS2Realm3PvE", "RL~P~C8:3:3:" .. ("x"):rep(40))
		R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", "RL~P~X2~1~a word")
		R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", "RL~P~X2~2~a word")
		R.Comm.Whisper, R.Comm.SendBatch = raw, rawBatch
		eq(pieces, 0, "no piece of a word that can never pass whole is sent")
		eq(words["1"] or 0, 35, "the first single word reaches every reporter")
		eq(words["2"] or 0, 35, "and so does the second")
		-- Every allowance full again: a report in two pieces (385 bytes, three whispers) passes whole.
		R.clock = R.clock + 120
		Watch()
		local two = R.Codec.Chunk("R2~" .. ("t"):rep(382), "8")
		eq(#two, 2, "a 385-byte census report is two pieces")
		for _, p in ipairs(two) do R.Relay.HandleIn("WHISPER", "Census Guy-CAMWOWUS2Realm3PvE", "RL~P~" .. p) end
		R.Comm.Whisper, R.Comm.SendBatch = raw, rawBatch
		eq(pieces, 70, "with 35 reporters both pieces of a two-piece report go to each")
		-- A few reporters (an allowance of REPORTER_RATE): the same report still passes whole.
		R.Relay.Reset()
		for i = 1, 10 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		R.clock = R.clock + 120
		pieces = 0
		Watch()
		for _, p in ipairs(R.Codec.Chunk("R2~" .. ("s"):rep(382), "9")) do R.Relay.HandleIn("WHISPER", "Census Guy-CAMWOWUS2Realm3PvE", "RL~P~" .. p) end
		R.Comm.Whisper, R.Comm.SendBatch = raw, rawBatch
		eq(pieces, 20, "with 10 reporters both pieces of the report go to each")
	end)
end)

-- The review of the 1.5.4 candidate: the trickle charged a word in pieces piece by piece, so with an
-- allowance partly spent by single words the full first piece (two whispers once wrapped) was refused
-- and the short last one passed alone, or the first passed and the last was refused: a whisper wasted
-- per reporter, the report never arriving, and at every receiver an assembly that never closed (/oly
-- bug's "incomplete reports"). A word in pieces is paid for whole at its first piece, or refused
-- there, and its later pieces pass free. Fails before (every reporter is sent one piece alone).
test("relay trickle (1.5.4): a census report in two pieces goes to a reporter whole or not at all when his allowance is partly spent, before its first piece or between its pieces", function()
	Relayed(function(R, sent, Run)
		local CENSUS, CLIENT, N = "Census Guy-CAMWOWUS2Realm3PvE", "Some Client-CAMWOWUS2Realm3PvE", 10
		-- How many reporters were sent the census client's word whole, none of it, or a piece alone,
		-- read back from the whispers that left (a full piece travels as the relay's own envelope, in two).
		local function Tally()
			local whole, none, alone = 0, 0, 0
			for i = 1, N do
				local name, outer, got, n = ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), R.Codec.NewAssembler(), 0, nil
				for _, s in ipairs(sent) do
					if s.target == name then
						local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
						local k, total = nil, nil
						if rm then k, total = rm:match("^RM~P~Census Guy%-[^~]+~C%w+:(%d+):(%d+):") end
						if k then got, n = got + 1, tonumber(total) end
					end
				end
				if got == 0 then none = none + 1 elseif got == n then whole = whole + 1 else alone = alone + 1 end
			end
			return whole, none, alone
		end
		local function Register()
			R.Relay.Reset(); wipe(sent)
			for i = 1, N do R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i)) end
			R.clock = R.clock + 120 -- (every allowance full: REPORTER_RATE, with ten reporters)
		end
		-- Three single words first, each allowance down to one whisper; then the report, piece by piece
		-- as the origin's pump sends it.
		Register()
		for k = 1, 3 do R.Relay.HandleIn("WHISPER", CLIENT, ("RL~P~X2~%d~a word"):format(k)); Run(2) end
		local report = R.Codec.Chunk("R2~" .. ("r"):rep(382), "7")
		eq(#report, 2, "a 385-byte census report is two pieces")
		for _, p in ipairs(report) do R.Relay.HandleIn("WHISPER", CENSUS, "RL~P~" .. p); Run(1) end
		Run(30)
		local whole, none, alone = Tally()
		eq(alone, 0, ("one whisper left: no reporter is sent a piece alone (whole %d, none %d, alone %d)"):format(whole, none, alone))
		eq(none, N, "the report is refused at its first piece for every reporter")
		-- The first piece on a full allowance, two single words, then the last piece.
		Register()
		R.Relay.HandleIn("WHISPER", CENSUS, "RL~P~" .. report[1]); Run(1)
		for k = 1, 2 do R.Relay.HandleIn("WHISPER", CLIENT, ("RL~P~X2~%d~a word"):format(k)); Run(1) end
		R.Relay.HandleIn("WHISPER", CENSUS, "RL~P~" .. report[2])
		Run(30)
		whole, none, alone = Tally()
		eq(alone, 0, ("spent between the pieces: no reporter is sent a piece alone (whole %d, none %d, alone %d)"):format(whole, none, alone))
		eq(whole, N, "the report, paid for at its first piece, reaches every reporter whole")
	end)
end)

-- The review of the 1.5.4 candidate: the relay's own word too long for one drip batch (wrapped whole
-- it is more than MAX_CHUNKS whispers, so each piece goes wrapped alone: two batches) was keyed by its
-- kind and replaced batch by batch. A newer copy that came while the older's first batch was already
-- in the queue replaced only its second: that reporter got half of each copy and could put the older
-- together never. Each copy of such a word goes whole now. Fails before (a reporter with half a copy).
test("relay fan-out (1.5.4): the relay's own word too long for one drip batch is never split by a newer copy: each reporter gets every piece of each copy it gets any of, and the newer copy whole", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 6
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		local label = #("RM~P~" .. R.me .. "~")
		local size = R.Codec.CHUNK * R.Codec.MAX_CHUNKS - label + 1 -- one whisper past MAX_CHUNKS once wrapped whole
		local function Word(stamp, fill) return (("T9~Olympus~%d~"):format(stamp) .. fill:rep(size)):sub(1, size) end
		local older, newer = Word(1794011276, "a"), Word(1794011400, "b")
		local first = R.Codec.Chunk(older, "61")
		eq(#first <= R.Codec.MAX_CHUNKS, true, "the word itself fits MAX_CHUNKS pieces")
		for _, p in ipairs(first) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		-- (The first reporter's first batch is in the queue already when the newer copy comes.)
		for _, p in ipairs(R.Codec.Chunk(newer, "62")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		Run(2000)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local half, newerWhole = 0, 0
		for i = 1, REPORTERS do
			local prefix = ("Rep Number%d-"):format(i)
			local outer, got, total = R.Codec.NewAssembler(), {}, {}
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					local id, k, n = nil, nil, nil
					if body then id, k, n = body:match("^C(%w+):(%d+):(%d+):") end
					if id then
						got[id] = got[id] or {}
						got[id][tonumber(k)] = true
						total[id] = tonumber(n)
					end
				end
			end
			for id, ks in pairs(got) do
				local c = 0
				for _ in pairs(ks) do c = c + 1 end
				if c ~= total[id] then half = half + 1 end
			end
			local c = 0
			for _ in pairs(got["62"] or {}) do c = c + 1 end
			if total["62"] and c == total["62"] then newerWhole = newerWhole + 1 end
		end
		eq(half, 0, "no reporter is sent part of a copy")
		eq(newerWhole, REPORTERS, "every reporter gets the newer copy whole")
	end)
end)

-- The review of the 1.5.4 candidate (its load): the relay's own word in pieces whose envelope needs
-- two drip batches was keyed by its message id, so no repeat ever took its waiting copy's place: on a
-- busy relay the drip grew without end (70 batches a repeat at 35 reporters, drained at about three a
-- minute) and the census snapshots waited behind it, hours stale. A repeat takes the waiting copy's
-- place while every batch of it still waits; with one in flight it takes the one "next" place, which
-- the repeat after it takes in turn. Fails before (every reporter is sent all four copies).
test("relay fan-out (1.5.4): the relay's own word too long for one drip batch, repeated: each reporter gets the newest copy whole and at most the one in flight before it, never a backlog", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 6
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		local label = #("RM~P~" .. R.me .. "~")
		local size = R.Codec.CHUNK * R.Codec.MAX_CHUNKS - label + 1 -- one whisper past MAX_CHUNKS once wrapped whole
		local function Word(stamp) return (("T9~Olympus~%d~"):format(stamp) .. ("a"):rep(size)):sub(1, size) end
		-- Four copies in a row (a bank changing: Bank.Share every SHARE_GAP), the first reporter's first
		-- batch of the first copy in the queue already when the others come.
		for c = 1, 4 do
			for _, p in ipairs(R.Codec.Chunk(Word(1794011276 + c), tostring(60 + c))) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		end
		Run(1500)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local most, least, newest, half = 0, math.huge, 0, 0
		for i = 1, REPORTERS do
			local prefix = ("Rep Number%d-"):format(i)
			local outer, got, total = R.Codec.NewAssembler(), {}, {}
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					local id, k, n = nil, nil, nil
					if body then id, k, n = body:match("^C(%w+):(%d+):(%d+):") end
					if id then
						got[id] = got[id] or {}
						got[id][tonumber(k)] = true
						total[id] = tonumber(n)
					end
				end
			end
			local whole = 0
			for id, ks in pairs(got) do
				local c = 0
				for _ in pairs(ks) do c = c + 1 end
				if c == total[id] then
					whole = whole + 1
					if id == "64" then newest = newest + 1 end
				else
					half = half + 1
				end
			end
			most, least = math.max(most, whole), math.min(least, whole)
		end
		eq(half, 0, "no reporter is sent part of a copy")
		eq(newest, REPORTERS, "every reporter gets the newest copy whole")
		eq(least, 1, "a reporter not yet served gets the newest copy alone")
		eq(most <= 2, true, ("the reporter whose first batch was in flight gets that copy and the newest, no more: %d"):format(most))
	end)
end)

-- The review of the 1.5.4 candidate: the Treasurer's client (a relay: Relay.Names takes his signed
-- pins) passes on each of his mail characters' books (TR~<name>~) in one tick (Treasury.Relay), each
-- as Treasury.Send sends it: in pieces above 250 bytes, else one channel message. Keyed "TR" alone,
-- the last book took the others' places for every reporter still waiting: in the drip for books in
-- pieces (one reporter of six had both), in Comm's keyed jobs for books in one whisper (none had
-- both). Each mail character's book keeps its own place now, and a newer copy of one character's
-- book still takes its waiting copy's place. Fails before (the first book at one reporter of six).
test("relay fan-out (1.5.4): the relay's own books of two mail characters (TR), sent in one tick, both reach every reporter, in pieces or in one whisper; a newer copy of one character's book still takes its waiting copy's place", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 6
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- As Treasury.Send sends each book: in pieces above 250 bytes, else one channel message.
		local options = { owner = "test treasury", guard = function() return true end }
		local function Send(book)
			if #book <= 250 then return R.Comm.Send("CHANNEL", book, nil, nil, nil, nil, options) end
			return R.Comm.SendChunked(book, nil, "CHANNEL", nil, options)
		end
		local function Both(a, b)
			local n = 0
			for i = 1, REPORTERS do
				local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
				if got[a] and got[b] then n = n + 1 end
			end
			return n
		end
		local big1 = "TR~Pyralis Andarai-Realm~1794011276~TB~" .. ("a"):rep(700)
		local big2 = "TR~Pyralis Thirdchar-Realm~1794011276~TB~" .. ("b"):rep(700)
		Send(big1); Send(big2)
		Run(400)
		eq(Both(big1, big2), REPORTERS, "each mail character's book in pieces reaches every reporter")
		local small1, small2 = "TR~Pyralis Andarai-Realm~1794011277~TB~a", "TR~Pyralis Thirdchar-Realm~1794011277~TB~b"
		Send(small1); Send(small2)
		Run(100)
		eq(Both(small1, small2), REPORTERS, "each mail character's book in one whisper reaches every reporter")
		-- Still: the queue full, a newer copy of one character's book takes its waiting copy's place.
		for i = 1, R.Comm.MAX_QUEUE do R.Comm.Whisper("Filler Target-CAMWOWUS2Realm7PvE", "X1~filler " .. i, "filler " .. i, false, false) end
		local older = "TR~Pyralis Andarai-Realm~1794011300~TB~" .. ("c"):rep(700)
		local newer = "TR~Pyralis Andarai-Realm~1794011301~TB~" .. ("d"):rep(700)
		Send(older); Send(newer)
		Run(400)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local olderSent, newerOnce = 0, 0
		for i = 1, REPORTERS do
			local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
			if got[older] then olderSent = olderSent + 1 end
			if got[newer] == 1 then newerOnce = newerOnce + 1 end
		end
		eq(olderSent, 0, "no reporter is sent the copy the newer one replaced")
		eq(newerOnce, REPORTERS, "each reporter gets the newer copy, once")
	end)
end)
