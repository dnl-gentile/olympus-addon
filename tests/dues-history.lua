local ns, test, eq, H = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]dues%-history%.lua$") or "./"
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = ns })

local function Client(w, role, options)
	local c = w:Role(role, options)
	w:As(c, function()
		c.ns.splitNames = true -- this fixture models the supported surname client
		c.ns.L = setmetatable({}, { __index = ns.L })
		for _, file in ipairs({ "Roster", "Data", "Locales/DuesHistoryText", "DuesHistory" }) do
			assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c.ns)
		end
	end)
	c.ns.UI = { SelectTab = function(tab) c.tab = tab end }
	local C = c.ns.Comm
	C.Hash36 = ns.Comm.Hash36
	C.Cancel = function() end -- actual Treasury cancellation invalidates each piece's guard
	C.SendBatch = function(dist, pieces, _, target, urgent, done, options)
		w:Timer(c, 0, nil, function()
			if options and options.guard and not options.guard() then if done then done(false) end; return end
			local left, failed = #pieces, false
			for _, piece in ipairs(pieces) do
				C.Whisper(target, piece, nil, urgent, false, function(ok)
					failed, left = failed or not ok, left - 1
					if left == 0 and done then done(not failed) end
				end, options)
			end
		end, "private history batch")
		return true
	end
	return c
end
local function Scan(w)
	for _, c in ipairs(w.clients) do
		local peers = {}; for _, peer in ipairs(w.clients) do if peer.guild == c.guild then peers[#peers + 1] = peer end end
		c.globals.GetNumGuildMembers = function() return #peers, #peers end
		c.globals.GetGuildRosterInfo = function(i)
			local p = peers[i]; if p then return p.name, p.rankName, p.rank, 60, "Mage", "Stormwind", "", "", true, nil, "MAGE", nil, nil, nil, nil, nil, p.guid end
		end
		w:As(c, function() assert(c.ns.Roster.Scan()); assert(c.ns.Roster.Fresh()) end)
	end
end
local function Setup()
	local w = World.New({ council = false, arenaFiles = {}, compliance = "shipped" })
	local treasurer, king, steward = Client(w, "treasurer"), Client(w, "king"), Client(w, "steward")
	Scan(w)
	w:As(treasurer, function()
		treasurer.db.keeperShares = { [treasurer.name:lower()] = true }
		local T, D = treasurer.ns.Treasury, treasurer.ns.Dues
		for _, name in ipairs({ treasurer.name, World.NAMES.treasurerMail }) do
			local b = T.BookOf(name, true); b.opened, b.openedAt = D.WeekStart(D.Week() - 4), D.WeekStart(D.Week() - 4)
			b.opening = 0 -- an already opened book; Share must not open it again on the first receipt
		end
	end)
	return w, treasurer, king, steward
end

test("Dues history: actual King and pinned Treasurer only; previews, Steward, wrong faction and mail character have no historical view", function()
	local w, treasurer, king, steward = Setup()
	local mail = Client(w, "treasurerMail")
	w:As(mail, function() eq(mail.ns.DuesHistory.Sees(), false); eq(mail.ns.DuesHistory.Data(), nil) end)
	w:As(treasurer, function() eq(treasurer.ns.DuesHistory.Sees(), true); assert(treasurer.ns.DuesHistory.Link()) end)
	w:As(king, function() eq(king.ns.DuesHistory.Sees(), true) end)
	w:As(steward, function()
		steward.db.devKingView, steward.db.devTreasurerView = true, true
		eq(steward.ns.DuesHistory.Sees(), false); eq(steward.ns.DuesHistory.Ask(), false); eq(steward.ns.DuesHistory.Link(), nil)
		eq(#steward.ns.DuesHistory.Build(), 0)
	end)
	king.rank = 1
	w:As(king, function() eq(king.ns.DuesHistory.Sees(), false) end)
	treasurer.ns.faction = "Horde"
	w:As(treasurer, function() eq(treasurer.ns.DuesHistory.Sees(), false) end)
end)

test("Dues history: duplicate private wire reply preserves accepted history", function()
	local w, t, king = Setup()
	local query, message
	w:As(king, function()
		local private = king.ns.Treasury.Private
		king.ns.Treasury.Private = function(_, _, text) query = text; return true end
		assert(king.ns.DuesHistory.Ask()); king.ns.Treasury.Private = private
	end)
	w:As(t, function() message = t.ns.DuesHistory.Message(tonumber(query:match("Q~(%d+)"))) end)
	w:As(king, function()
		local pieces = king.ns.Codec.Chunk(message, "test1")
		for _, piece in ipairs(pieces) do king.ns.Treasury.HandlePrivate("WHISPER", t.name, "TW~DH~" .. piece) end
		local held = assert(king.ns.DuesHistory.Held())
		for _, piece in ipairs(pieces) do king.ns.Treasury.HandlePrivate("WHISPER", t.name, "TW~DH~" .. piece) end
		eq(king.ns.DuesHistory.Held(), held, "a replay has no pending request but does not erase a good answer")
	end)
end)

local function Boundary(w, c, gap)
	local D, DH = c.ns.Dues, c.ns.DuesHistory
	local week
	w:As(c, function() week = D.Week(); DH.Observe() end)
	w.clock = w.clock + (gap or 30)
	w:As(c, function() return DH.Observe() end)
	return week
end
local function BeforeReset(w, c)
	w:As(c, function() w.clock = c.ns.Dues.WeekStart(c.ns.Dues.Week() + 1) - 15 end)
	Scan(w)
end
local function Receipt(w, c, name, amount, guild, note)
	w:As(c, function() c.ns.Treasury.Record(name, amount, "trade", false, { guild = guild, note = note, quiet = true }) end)
end

test("Dues history: current receipts, observed opening denominator and frozen closing sums", function()
	local w, t = Setup()
	BeforeReset(w, t); local first = Boundary(w, t)
	Receipt(w, t, "Lida Fenn-Emberfall", 5000000, "Olympus Ember")
	Receipt(w, t, "Parric Stowe-Emberfall", 1, "Olympus Ember")
	w:As(t, function()
		local data = t.ns.DuesHistory.Data()
		assert(t.ns.DuesHistory.Raw(t.ns.Dues.Week()).complete, "both pinned books cover the week")
		local current = data.guilds["olympus ember"].weeks[1]
		eq(current.copper, 5000001); eq(current.payers, 2); eq(current.paid, 1)
		eq(data.guilds.olympus.weeks[1].members, 2)
		eq(data.guilds.olympus.weeks[1].paid, 0, "complete books and no own-guild receipts")
		eq(t.ns.rdb.duesHistory.weeks[first].members, nil, "first observed close has no invented opening")
	end)
	BeforeReset(w, t); local closed = Boundary(w, t)
	w:As(t, function()
		local data = t.ns.DuesHistory.Data()
		eq(data.guilds["olympus ember"].weeks[2].paid, 1)
		eq(data.guilds.olympus.weeks[2].members, 2)
		local saved = t.ns.rdb.duesHistory.weeks[closed].closed
		t.ns.rdb.duesAmount = { copper = 9000000, before = 9000000, at = w.clock, from = World.NAMES.king }
		eq(t.ns.DuesHistory.Data().guilds["olympus ember"].weeks[2].paid, 1)
		eq(t.ns.rdb.duesHistory.weeks[closed].closed.amount, saved.amount)
	end)
	Receipt(w, t, "Wenna Crale-Emberfall", 5000000, "Olympus Ember", "Olympus dues " .. tostring(closed))
	-- A verified old receipt changes the book digest; a closing paid count cannot be reinterpreted.
	w:As(t, function()
		local b = t.ns.Treasury.Book()
		b.lines[#b.lines].wk = closed; b.sums = nil
		eq(t.ns.DuesHistory.Data().guilds["olympus ember"].weeks[2].paid, nil)
	end)
end)

test("Dues history: missing, stale and interrupted reset observations never invent denominators", function()
	for _, mode in ipairs({ "late", "gap", "store", "roster", "login" }) do
		local w, t = Setup(); BeforeReset(w, t)
		w:As(t, function() t.ns.DuesHistory.Observe() end)
		if mode == "store" then t.ns.rdb = World.Copy(t.ns.rdb) end
		if mode == "roster" then w.clock = w.clock - 200; Scan(w); w.clock = w.clock + 200 end
		if mode == "login" then w:As(t, function() t.ns.DuesHistory.Reset() end) end
		w.clock = w.clock + ((mode == "late" or mode == "gap") and 120 or 30)
		w:As(t, function()
			local ok = t.ns.DuesHistory.Observe()
			if mode ~= "roster" then eq(ok, false, mode) end
			local data = t.ns.DuesHistory.Data()
			local g = data.guilds.olympus
			if mode == "roster" then assert(not g or g.weeks[1].members == nil) end
		end)
	end
end)

test("Dues history: an empty own roster never creates a zero denominator", function()
	local w, t = Setup(); BeforeReset(w, t)
	w:As(t, function() t.ns.DuesHistory.Observe() end)
	w.clock = w.clock + 30
	w:As(t, function()
		t.globals.GetNumGuildMembers = function() return 0, 0 end
		GetNumGuildMembers = t.globals.GetNumGuildMembers
		t.ns.Roster.Scan()
		assert(t.ns.DuesHistory.Observe())
		local members = t.ns.rdb.duesHistory.weeks[t.ns.Dues.Week()].members
		eq(members.olympus, nil)
	end)
end)

test("Dues history: private replies reject unknown rank sources, previews and public delivery", function()
	local w, t, king, steward = Setup()
	Receipt(w, t, "Lida Fenn-Emberfall", 5000000, "Olympus Ember")
	w:As(t, function()
		local DH = t.ns.DuesHistory
		local message = DH.Message(w.clock * 1000)
		assert(not message:find("Lida", 1, true), "history never serializes payer names")
		local q = ("DH~1~Q~%.0f~%d"):format(w.clock * 1000, t.ns.Dues.Week())
		eq(DH.Handle("CHANNEL", king.name, q), false)
		eq(DH.Handle("WHISPER", steward.name, q), false)
		local rank = t.ns.Data.AuthorizedRank
		for _, source in ipairs({ false, "unknown", "enforced" }) do
			t.ns.Data.AuthorizedRank = function() return 0, source or nil end
			eq(DH.Handle("WHISPER", king.name, q), false)
		end
		t.ns.Data.AuthorizedRank = rank
		eq(DH.Handle("WHISPER", king.name, q), true)
		eq(DH.Handle("WHISPER", king.name, q), false, "replay")
	end)
	w:Run(2)
	for _, item in ipairs(w:Sent({ type = "TW" })) do eq(item.dist, "WHISPER") end
end)

test("Dues history: chunk bounds reject oversized data before the shared assembler", function()
	local w, t, king = Setup()
	w:As(t, function()
		local feed, calls = t.ns.Codec.Feed, 0
		t.ns.Codec.Feed = function(...) calls = calls + 1; return feed(...) end
		for _, piece in ipairs({ "Cx:1:1:" .. string.rep("a", 221), "Cx:1:29:a", "Cx:0:1:a", "Ctoolongid:1:1:a" }) do
			t.ns.Treasury.HandlePrivate("WHISPER", king.name, "TW~DH~" .. piece)
		end
		eq(calls, 0)
		t.ns.Codec.Feed = feed
	end)
end)

test("Dues history: correlated replies expire, cannot replay and do not cross stores", function()
	for _, mode in ipairs({ "valid", "store", "faction", "realm", "guild", "stale", "wrong" }) do
		local w, t, king = Setup()
		local q
		w:As(king, function()
			local private = king.ns.Treasury.Private
			king.ns.Treasury.Private = function(_, _, text) q = text; return true end
			eq(king.ns.DuesHistory.Ask(), true)
			king.ns.Treasury.Private = private
		end)
		local id = tonumber(q:match("Q~(%d+)")); local msg
		w:As(t, function() msg = t.ns.DuesHistory.Message(id) end)
		if mode == "store" then king.ns.rdb = World.Copy(king.ns.rdb) end
		if mode == "faction" then king.ns.faction = "Horde" end
		if mode == "realm" then king.ns.realm = "Emberfall2" end
		if mode == "guild" then king.guild = "Olympus Ember" end
		if mode == "stale" then w.clock = w.clock + 181 end
		if mode == "wrong" then msg = msg:gsub("D~" .. tostring(id), "D~" .. tostring(id + 1), 1) end
		w:As(king, function()
			eq(king.ns.DuesHistory.Handle("WHISPER", t.name, msg), mode == "valid", mode)
			eq(king.ns.DuesHistory.Handle("WHISPER", t.name, msg), false, "cannot replay")
		end)
	end
end)

test("Dues history: historical census needs two independent fresh undisputed matching reporters", function()
	for _, mode in ipairs({ "two", "one", "stale", "disputed" }) do
		local w, t = Setup(); BeforeReset(w, t)
		w:As(t, function() t.ns.DuesHistory.Observe() end)
		w.clock = w.clock + 30
		w:As(t, function()
			local function Report(sender, total)
				local r = assert(t.ns.Codec.DecodeReport(t.ns.Codec.EncodeReport({ guild = "Olympus Ember", total = total,
					online = 1, leader = "Petra Wick", faction = "Alliance" })))
				t.ns.Data.Receive(r, sender)
			end
			if mode == "stale" then w.clock = w.clock - 100 end
			Report("Petra Wick-Emberfall", 20)
			if mode ~= "one" then Report("Lida Fenn-Emberfall", mode == "disputed" and 90 or 20) end
			if mode == "stale" then w.clock = w.clock + 100 end
			eq(t.ns.DuesHistory.Observe(), true)
			local g = t.ns.DuesHistory.Data().guilds["olympus ember"]
			if mode == "two" then eq(g.weeks[1].members, 20)
			else assert(not g or g.weeks[1].members == nil, mode) end
		end)
	end
end)

test("Dues history: queued private replies cancel after store or realm changes", function()
	for _, mode in ipairs({ "store", "realm", "faction", "guild", "role" }) do
		local w, t, king = Setup()
		w:As(t, function()
			local q = ("DH~1~Q~%.0f~%d"):format(w.clock * 1000, t.ns.Dues.Week())
			eq(t.ns.DuesHistory.Handle("WHISPER", king.name, q), true)
		end)
		if mode == "store" then t.ns.rdb = World.Copy(t.ns.rdb) end
		if mode == "realm" then t.ns.realm = "Emberfall2" end
		if mode == "faction" then t.ns.faction = "Horde" end
		if mode == "guild" then t.guild = "Olympus Ember" end
		if mode == "role" then t.ns.me = World.NAMES.treasurerMail end
		w:Run(2)
		eq(#w:Sent({ from = t, type = "TW" }), 0, mode)
	end
end)

test("Dues history: local and wire guild bounds disclose truncation and keep five cells", function()
	local w, t, king = Setup()
	local message, id
	w:As(t, function()
		local D, DH, b = t.ns.Dues, t.ns.DuesHistory, t.ns.Treasury.Book()
		for i = 151, 1, -1 do
			b.lines[#b.lines + 1] = { name = ("Soldier %03d"):format(i), money = 1, how = "trade",
				t = D.WeekStart(D.Week() - 4) + 60, wk = D.Week() - 4, guild = ("Olympus %03d"):format(i), gv = true }
		end
		b.sums = nil
		local data, count = DH.Data(), 0
		for _ in pairs(data.guilds) do count = count + 1 end
		eq(count, 150); eq(data.cut, true)
		assert(data.guilds["olympus 001"]); eq(data.guilds["olympus 151"], nil, "sorted deterministic boundary")
		local words = {}
		for _, line in ipairs(DH.Build()) do words[#words + 1] = line.text or "" end
		assert(table.concat(words, " "):find(t.ns.L.DUESHISTORY_CUT, 1, true), "local truncation is visible")
	end)
	w:As(king, function()
		local private = king.ns.Treasury.Private
		king.ns.Treasury.Private = function(_, _, q) id = tonumber(q:match("Q~(%d+)")); return true end
		assert(king.ns.DuesHistory.Ask()); king.ns.Treasury.Private = private
	end)
	w:As(t, function() message = t.ns.DuesHistory.Message(id) end)
	w:As(king, function()
		assert(king.ns.DuesHistory.Handle("WHISPER", t.name, message))
		local held, count = king.ns.DuesHistory.Held(), 0
		eq(held.cut, true)
		for _, g in pairs(held.guilds) do count = count + 1; eq(#g.weeks, 5) end
		eq(count, 30)
	end)
	local censusWorld, censusTreasurer = Setup()
	BeforeReset(censusWorld, censusTreasurer)
	censusWorld:As(censusTreasurer, function() censusTreasurer.ns.DuesHistory.Observe() end)
	censusWorld.clock = censusWorld.clock + 30
	censusWorld:As(censusTreasurer, function()
		local c = censusTreasurer.ns
		for i = 1, 151 do
			for j = 1, 2 do
				local r = assert(c.Codec.DecodeReport(c.Codec.EncodeReport({ guild = ("Olympus Census %03d"):format(i),
					total = 2, online = 1, leader = ("Lord %03d"):format(i), faction = "Alliance" })))
				assert(c.Data.Receive(r, ("Scout %03d %d-Emberfall"):format(i, j)))
			end
		end
		assert(c.DuesHistory.Observe())
		eq(c.rdb.duesHistory.weeks[c.Dues.Week()].cut, true)
		eq(c.DuesHistory.Data().cut, true, "snapshot truncation remains visible with no receipts")
	end)
end)

test("Dues history: reply parser rejects invalid cells, extra rows and oversize payloads", function()
	local w, t, king = Setup()
	w:As(king, function()
		local private, id = king.ns.Treasury.Private
		king.ns.Treasury.Private = function(_, _, q) id = tonumber(q:match("Q~(%d+)")); return true end
		assert(king.ns.DuesHistory.Ask()); king.ns.Treasury.Private = private
		local head = ("DH~1~D~%.0f~%d~%d~0~"):format(id, king.ns.Dues.Week(), w.clock)
		local cell = "-/-/0/0/-/p"
		local cells = table.concat({ cell, cell, cell, cell, cell }, ",")
		local invalid = { cells .. "," .. cell, table.concat({ cell, cell, cell, cell }, ","),
			cells:gsub("^%-/%-", "0/-"), cells:gsub("^%-/%-", "-/0"),
			cells:gsub("p", "s", 1), cells:gsub("p", "z", 1), cells:gsub("p", "l", 1),
			cells:gsub("/%-/p", "/0/p", 1), (cells:gsub("/0/0/", "/-1/0/", 1)) }
		for _, value in ipairs(invalid) do eq(king.ns.DuesHistory.Handle("WHISPER", t.name, head .. "Olympus=" .. value), false) end
		local rows = {}; for i = 1, 31 do rows[i] = "Olympus " .. i .. "=" .. cells end
		eq(king.ns.DuesHistory.Handle("WHISPER", t.name, head .. table.concat(rows, ";")), false)
		eq(king.ns.DuesHistory.Handle("WHISPER", t.name, head .. string.rep("x", 6001)), false)
		eq(king.ns.DuesHistory.Handle("WHISPER", t.name, head .. "Olympus=" .. cells .. ";Olympus=" .. cells), false)
		eq(king.ns.DuesHistory.Handle("WHISPER", t.name, head .. "Olympus=" .. cells), true, "invalid replies do not consume the pending request")
	end)
end)

test("Dues history: actual two-way Treasury private transport and shared Dues navigation in both input modes", function()
	for _, gamepad in ipairs({ false, true }) do
		H.WithUI(function()
			H.WithGamepadUI(gamepad, function()
				local w, t, king = Setup()
				Receipt(w, t, "Lida Fenn-Emberfall", 5000000, "Olympus Ember")
				w:As(king, function() assert(king.ns.DuesHistory.Ask()) end)
				w:Run(5)
				w:As(king, function()
					eq(king.ns.GamepadUI(), gamepad)
					local DH, D = king.ns.DuesHistory, king.ns.Dues
					local held = assert(DH.Held(), "the Treasurer answered through real TW handlers")
					eq(held.guilds["olympus ember"].weeks[1].copper, 5000000)
					D.Open(); eq(king.ns.Treasury.mode, "dues")
					local link
					for _, line in ipairs(D.Build()) do if line.text == king.ns.L.DUESHISTORY_LINK then link = line end end
					assert(link); link.onClick()
					eq(DH.shown, true)
					local lines = D.Build(); eq(lines[2].text, king.ns.L.DUESHISTORY_TITLE)
					lines[1].onClick(); eq(DH.shown, nil); eq(king.ns.Treasury.mode, "dues")
					DH.Open(); D.Back(); eq(DH.shown, nil); eq(king.ns.Treasury.mode, "dues")
					D.Back(); eq(king.ns.Treasury.mode, "summary")
				end)
				local messages = w:Sent({ type = "TW" }); assert(#messages >= 2)
				for _, s in ipairs(messages) do eq(s.dist, "WHISPER"); assert(not s.msg:find("Lida", 1, true)) end
			end)
		end)
	end
end)

test("Dues history: explanatory paragraphs render fully in mouse and gamepad rows", function()
	for _, gamepad in ipairs({ false, true }) do
		H.WithUI(function()
			H.WithGamepadUI(gamepad, function()
				local w, t = Setup()
				local lines, expected
				w:As(t, function()
					local DH, L = t.ns.DuesHistory, t.ns.L
					DH.Open(); lines = t.ns.Dues.Build()
					expected = L.DUESHISTORY_HINT .. " " .. L.DUESHISTORY_BOOKS .. " " .. L.DUESHISTORY_PARTIAL .. " " .. L.DUESHISTORY_NONE
				end)
				for _, style in ipairs({ "classic", "hd" }) do
					local content = CreateFrame("Frame", nil, UIParent)
					content.rect = { 0, 0, 400, 1000 } -- a positioned scroll child, so font anchors have real room
					content:SetWidth(400); content.style = style == "hd" and "hd" or nil
					ns.Views.Render(content, lines)
					local words = {}
					for i = 3, #lines do
						local row = content.rows[i]
						eq(row.left:IsTruncated(), false, "complete instruction: " .. row.left:GetText())
						words[#words + 1] = row.left:GetText()
					end
					eq(table.concat(words, " "), expected, "all paragraph words survive rendering")
				end
			end)
		end)
	end
end)
