-- The actual slash route, authorization, solo table and shared chat renderer. All names are
-- invented by World; no permission function is replaced to admit an ordinary client.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)

local function Setup(w, name, options)
	local c = w:Player(name, options or { companion = {} })
	c.K = BoardUI.New(function() return w.clock end)
	c.K.Install(c.globals)
	w:As(c, function()
		assert(loadfile(H.ADDON_DIR .. "Filter.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "Views.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "ChatWindow.lua"))("Olympus", c.ns)
	end)
	return c
end
local function Command(w, c, tail)
	return w:As(c, function() return c.slashes.OLYMPUS("arena sim " .. tail) end)
end
local function Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}; for key, v in pairs(value) do out[key] = Copy(v) end
	return out
end
local function Unchanged(before, after, path)
	eq(type(after), type(before), path)
	if type(before) ~= "table" then eq(after, before, path); return end
	for key, value in pairs(before) do Unchanged(value, after[key], path .. "." .. tostring(key)) end
	for key in pairs(after) do assert(before[key] ~= nil, path .. ": unexpected saved key " .. tostring(key)) end
end
local function Clean(w)
	for _, c in ipairs(w.clients) do
		eq(#c.errors, 0, table.concat(c.errors, "\n"))
		eq(#c.K.errors, 0, table.concat(c.K.errors, "\n"))
	end
end

for _, role in ipairs({ "author", "test" }) do
	test("Bones chat simulation: actual " .. role .. " command opens a local solo table, never a live game or send, and cleans on move or exit", function()
		local w = FW.New({ compliance = "shipped" })
		local options = { companion = {} }
		if role == "test" then options.testBuild = { n = 2, base = H.ns.VERSION, built = w.clock - 100,
			expires = w.clock + 86400, commit = "abc1234", lane = "group" } end
		local c = Setup(w, role == "author" and H.World.NAMES.author or "Tamsin Ledger", options)
		eq(w:As(c, c.Arena.MaySim), true, "real author identity or valid build metadata")
		assert(w:As(c, c.Arena.LoadUI))
		local db, rdb, sent = Copy(c.db), Copy(c.rdb), #w:Sent()
		Command(w, c, "boneschat")
		local ui = c.ns.Arena.ui
		eq(c.Arena.Sim(), true)
		eq(ui.SimModule.SCENES[ui.SimModule.scene][1], "BONE", "existing solo-table scene")
		eq(ui.FarkleBoard.Window():IsShown(), true)
		eq(ui.FarkleBoard._.S.mode, "setup", "no invented match or opponent")
		eq(w:As(c, c.ns.FarkleTable.Live), nil)
		local panel = assert(ui.BonesChat.Frame(), "actual local preview chat")
		eq(panel:IsShown(), true)
		eq(panel.strip.nav[1].label:GetText(), "Players"); eq(panel.strip.nav[2].label:GetText(), "Everyone")
		local input = panel.conversation.input
		w:As(c, function()
			input:SetText("A local draft, not a message")
			input:GetScript("OnEnterPressed")(input)
		end)
		eq(input:GetText(), "A local draft, not a message", "an unsent preview draft is not discarded")
		w:Run(2)
		eq(#w:Sent(), sent, "no remote chat, whisper, invitation or game traffic")
		Unchanged(db, c.db, "account"); Unchanged(rdb, c.rdb, "character")
		Command(w, c, "next")
		eq(panel:IsShown(), false, "moving scenes cleans the preview")
		Command(w, c, "boneschat")
		eq(panel:IsShown(), true, "the command can reopen it")
		Command(w, c, "off")
		-- The existing sim-off route coalesces ARENA_CHANGED; its handler closes the scenes.
		w:Run(c.Arena.CHANGED_GAP + 0.1)
		eq(c.Arena.Sim(), false); eq(panel:IsShown(), false, "leaving the sim cleans the preview")
		Unchanged(db, c.db, "account"); Unchanged(rdb, c.rdb, "character")
		Clean(w)
	end)
end

test("Bones chat simulation: actual command denies an ordinary release before any companion, live game or send", function()
	local w = FW.New({ compliance = "shipped" })
	local c = Setup(w, "Dorian Pine", { companion = {} })
	eq(w:As(c, c.Arena.MaySim), false)
	Command(w, c, "boneschat")
	eq(c.Arena.Sim(), false); eq(c.companion.loaded, nil, "denied before loading the companion")
	eq(#w:Sent(), 0)
	Clean(w)
end)
