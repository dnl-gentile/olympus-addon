-- The actual table, transport and embedded chat on separate clients. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local N = H.World.NAMES
local function Setup(w, c, screen, renderer)
	c.K = BoardUI.New(function() return w.clock end, { screen = screen })
	c.K.Install(c.globals)
	local function Members()
		local out = {}; for _, peer in ipairs(w.clients) do if peer.guild == c.guild then out[#out + 1] = peer end end
		return out
	end
	c.globals.GetNumGuildMembers = function() local list = Members(); return #list, #list end
	c.globals.GetGuildRosterInfo = function(index)
		local peer = Members()[index]
		if peer then return peer.name, peer.rankName, peer.rank, peer.level, "Warrior", "Elwynn Forest", "", "", peer.online, nil, "WARRIOR", nil, nil, nil, nil, nil, peer.guid end
	end
	w:As(c, function()
		assert(loadfile(H.ADDON_DIR .. "Roster.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "Filter.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "Views.lua"))("Olympus", c.ns)
		if renderer ~= "missing" then
			assert(loadfile(H.ADDON_DIR .. "ChatWindow.lua"))("Olympus", c.ns)
			if renderer == "nil" then
				-- A failed optional factory must not publish a partly built panel. Authority and all
				-- game/transport functions remain real; restore this actual factory for the retry.
				c.embeddedFactory = c.ns.ChatWindow.CreateEmbedded
				c.ns.ChatWindow.CreateEmbedded = function() return nil end
			end
		end
	end)
	return c
end
local function Seat(w, name, screen, guild, renderer) return Setup(w, w:Player(name, { guild = guild, companion = {} }), screen, renderer) end
local function Live(screen, guild, renderer, compliance)
	local files = {}
	for _, file in ipairs(H.World.ARENA_FILES) do
		if file == "ArenaChat" then files[#files + 1] = "WatchChat" end
		files[#files + 1] = file
	end
	local w = FW.New({ arenaFiles = files, compliance = compliance })
	local king = Setup(w, w:Player(N.king, { guild = H.World.KING_GUILD, rank = 0, companion = {} }), screen)
	local a, b, s = Seat(w, N.fighterA, screen, guild, renderer), Seat(w, N.fighterB, screen, guild), Seat(w, N.bettor1, screen, guild)
	for _, c in ipairs({ king, a, b, s }) do assert(w:As(c, c.ns.Roster.Scan)) end
	assert(king.Roles.SetSettings({ live = 1 })); w:Run(0)
	a.Arena.SetRules(true); b.Arena.SetRules(true); s.Arena.SetRules(true)
	w:Group({ a, b }); w:AtInn(a.name, b.name)
	local id = assert(w:As(a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000, secs = 120 }))
	w:Run(0); assert(w:As(b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	w:As(a, a.ns.FarkleTable.Roll, id); w:As(b, b.ns.FarkleTable.Roll, id); w:Run(0)
	eq(w:As(a, a.ns.FarkleTable.View, id).state, "play")
	assert(w:As(s, s.ns.FarkleTable.Watch, id)); w:Run(0)
	for _, c in ipairs({ a, b, s }) do
		assert(w:As(c, c.ns.FarkleTable.ShowUI, "board", id), table.concat(c.errors, "\n") .. " " .. table.concat(c.printed, "\n"))
	end
	return w, a, b, s, id, king
end
local function UI(c) return c.ns.Arena.ui.BonesChat end
local function Frame(c) return assert(UI(c).Frame(), "actual embedded panel") end
local function Click(w, c, b) return w:As(c, c.K.UserClick, b) end
local function Send(w, c, text)
	w:As(c, function()
		local input = Frame(c).conversation.input
		input:SetText(text); input:SetFocus(); input:GetScript("OnEnterPressed")(input)
	end)
	w:Run(0)
end
local function Clean(w)
	for _, c in ipairs(w.clients) do
		eq(#c.errors, 0, table.concat(c.errors, "\n"))
		if c.K then eq(#c.K.errors, 0, table.concat(c.K.errors, "\n")) end
	end
end

test("Bones table chat: idle companion has no polling timer; visible, collapsed, hidden and reopened panels follow their own lifecycle", function()
	local function ChatTimers(w, c)
		local n = 0
		for _, timer in ipairs(w:Timers(c, true)) do
			if timer.where == "bones chat" or debug.getinfo(timer.fn, "S").source:find("BonesChat.lua", 1, true) then n = n + 1 end
		end
		return n
	end
	local idle = H.World.New()
	local quiet = idle:Client("Tamsin Ledger", { companion = {} })
	assert(idle:As(quiet, quiet.Arena.LoadUI))
	idle:Run(5)
	eq(UI(quiet).Frame(), nil, "idle loading constructs no chat panel")
	-- This module's cost at a first load. The unchanged net.lua foundation case also checks
	-- total companion cost is zero after reload, independently of other modules' startup jobs.
	eq(ChatTimers(idle, quiet), 0, "idle companion starts no chat polling timer")
	Clean(idle)
	local w, a, _, _, id = Live()
	local chat, refresh, polls = UI(a), UI(a).Refresh, 0
	chat.Refresh = function(...)
		polls = polls + 1
		return refresh(...)
	end
	eq(ChatTimers(w, a), 1, "one visible panel owns one refresh timer")
	w:Run(1); eq(polls > 0, true, "actual Refresh still polls permissions while visible")
	Click(w, a, Frame(a).toggle)
	eq(Frame(a).conversation:IsShown(), false)
	local before = polls
	w:Run(1); eq(polls > before, true, "collapsed toggle still revalidates the actual room")
	w:As(a, a.ns.Arena.ui.FarkleBoard.Close)
	eq(Frame(a):IsShown(), false)
	eq(ChatTimers(w, a), 0, "hiding cancels polling immediately")
	before = polls; w:Run(2); eq(polls, before, "hidden panel is dormant")
	w:As(a, a.ns.FarkleTable.ShowUI, "board", id)
	eq(Frame(a):IsShown(), true)
	eq(ChatTimers(w, a), 1, "reopening restarts exactly one timer")
	w:As(a, chat.Refresh); w:As(a, chat.Refresh)
	eq(ChatTimers(w, a), 1, "repeated render does not accumulate timers")
	w:As(a, chat.Hide); eq(ChatTimers(w, a), 0)
	Clean(w)
end)

test("Bones table chat: Core's actual missing-module stand-in leaves the game usable and retries when the real chat loads", function()
	local w, a, b, _, id = Live(nil, nil, "missing")
	eq(a.ns.ChatWindow.missing, true, "the real Core stand-in, not a replacement authorization mock")
	eq(type(a.ns.ChatWindow.CreateEmbedded), "function", "the stand-in's metatable supplies callable no-ops")
	eq(UI(a).Frame(), nil, "no incomplete conversation is exposed")
	eq(a.ns.Arena.ui.FarkleBoard._.parts().win:IsShown(), true, "the actual game board still renders")
	eq(w:As(a, a.ns.FarkleTable.View, id).state, "play")
	w:Run(2); Clean(w)
	w:As(a, function() assert(loadfile(H.ADDON_DIR .. "ChatWindow.lua"))("Olympus", a.ns) end)
	assert(w:As(a, a.ns.FarkleTable.ShowUI, "board", id))
	eq(Frame(a):IsShown(), true)
	Send(w, a, "The real chat is ready")
	eq(Frame(b).conversation.bubbles[1].body:GetText(), "The real chat is ready")
	Clean(w)
end)

test("Bones table chat: a nil optional factory stays hidden and bounded, then recovers without a poisoned panel", function()
	local w, a, b, _, id = Live(nil, nil, "nil")
	local board = a.ns.Arena.ui.FarkleBoard
	eq(UI(a).Frame(), nil)
	for _ = 1, 3 do assert(w:As(a, a.ns.FarkleTable.ShowUI, "board", id)) end
	local count = 0
	for _, frame in ipairs(a.K.frames) do
		if frame:GetName() == "OlympusArenaBonesChat" then count = count + 1; eq(frame:IsShown(), false) end
	end
	eq(count, 1, "retry reuses one hidden candidate instead of accumulating named frames")
	eq(board._.parts().win:IsShown(), true)
	w:Run(2); Clean(w)
	a.ns.ChatWindow.CreateEmbedded = a.embeddedFactory
	assert(w:As(a, a.ns.FarkleTable.ShowUI, "board", id))
	eq(Frame(a):IsShown(), true)
	Send(w, a, "The retried conversation works")
	eq(Frame(b).conversation.bubbles[1].body:GetText(), "The retried conversation works")
	Clean(w)
end)

test("Bones table chat: two real players exchange private and Everyone lines, a spectator has no Players tab or cached access", function()
	local w, a, b, s, id = Live()
	local rooms = w:As(a, a.ns.ArenaChat.TableRooms, id)
	eq(Frame(a):IsShown(), true); eq(Frame(a).strip.nav[1].label:GetText(), "Players")
	eq(Frame(s).strip.nav[1].label:GetText(), "Everyone"); eq(#Frame(s).strip.nav, 1)
	eq(w:As(s, UI(s).Select, "players"), false)
	Send(w, a, "Only our table players")
	eq(Frame(a).conversation.input:GetText(), "", table.concat(a.printed, "\n"))
	eq(#w:As(b, b.ns.ArenaChat.Lines, rooms.players), 1)
	eq(#w:As(s, s.ns.ArenaChat.Lines, rooms.players), 0)
	eq(Frame(b).conversation.bubbles[1].body:GetText(), "Only our table players")
	w:As(a, UI(a).Select, "everyone"); w:As(b, UI(b).Select, "everyone")
	local allowed, why = w:As(s, s.ns.ArenaChat.MaySend, rooms.everyone)
	eq(allowed, true, why)
	Send(w, s, "A spectator cheers")
	eq(Frame(s).conversation.input:GetText(), "", table.concat(s.printed, "\n"))
	for _, c in ipairs({ a, b, s }) do
		eq(#w:As(c, c.ns.ArenaChat.Lines, rooms.everyone), 1, c.name)
		eq(Frame(c).conversation.bubbles[1].body:GetText(), "A spectator cheers")
	end
	Clean(w)
end)

test("Bones table chat: the shared bubble renderer keeps filter reveal and actual royal moderation on a registered Everyone surface", function()
	local w, a, b, _, id, king = Live(nil, H.World.KING_GUILD)
	w:As(b, b.ns.Filter.Add, "veiled")
	Send(w, a, "A veiled remark")
	local hidden = Frame(b).conversation.bubbles[1]
	eq(hidden.hidden, true); eq(hidden.body:GetText():find("A veiled remark", 1, true), nil)
	w:As(b, function() hidden:GetScript("OnMouseUp")(hidden, "LeftButton") end)
	eq(hidden.hidden, false); eq(hidden.body:GetText():find("A veiled remark", 1, true) ~= nil, true)
	assert(w:As(king, king.ns.FarkleTable.Watch, id)); w:Run(0)
	assert(w:As(king, king.ns.FarkleTable.ShowUI, "board", id), table.concat(king.errors, "\n") .. " " .. table.concat(king.printed, "\n"))
	w:As(a, UI(a).Select, "everyone"); w:As(b, UI(b).Select, "everyone")
	Send(w, a, "A public table remark")
	local bubble = Frame(king).conversation.bubbles[1]
	assert(bubble and bubble.entry, "royal spectator received actual public line")
	eq(w:As(king, king.ns.WatchChat.HoldsChat, bubble.chat), true, "actual core registered the table surface")
	eq(w:As(king, king.ns.ChatWindow.ModerateLine, bubble), true)
	eq(Frame(king).conversation.modMenu:IsShown(), true)
	w:Run(1)
	eq(Frame(king).conversation.modMenu:IsShown(), true, "permission polling does not dismiss the menu")
	local entry = bubble.entry
	assert(w:As(king, king.ns.WatchChat.Delete, bubble.chat, entry, "Table conduct"))
	w:Run(0)
	eq(entry.del, true)
	eq(bubble:IsShown(), false, "ArenaChat.Lines omits deleted table lines, so the actual bubble is not drawn")
	eq(Frame(king).conversation.modMenu:IsShown(), false, "deleted target invalidates the menu")
	Clean(w)
end)

test("Bones table chat: collapse and tab drafts stay independent of the main chat, the combined table fits small screens and practice has no chat", function()
	local w, a, b, s, id = Live({ 1024, 768 })
	local main = a.ns.ChatWindow
	main.drafts.A = "Main unfinished words"
	local mainTier, mainFrame = main.Tier(), main.Frame()
	w:As(a, function() Frame(a).conversation.input:SetText("Private unfinished words") end)
	w:As(a, UI(a).Select, "everyone")
	w:As(a, function() Frame(a).conversation.input:SetText("Public unfinished words") end)
	w:As(a, UI(a).Select, "players")
	eq(Frame(a).conversation.input:GetText(), "Private unfinished words")
	Click(w, a, Frame(a).toggle); eq(Frame(a).conversation:IsShown(), false)
	eq(Frame(a).conversation.input:HasFocus(), false)
	Click(w, a, Frame(a).toggle); eq(Frame(a).conversation:IsShown(), true)
	w:As(a, UI(a).Select, "everyone"); eq(Frame(a).conversation.input:GetText(), "Public unfinished words")
	eq(main.drafts.A, "Main unfinished words"); eq(main.Tier(), mainTier); eq(main.Frame(), mainFrame)
	local board = a.ns.Arena.ui.FarkleBoard.Window()
	local shell = board:GetParent()
	eq(shell:GetWidth() * shell:GetEffectiveScale() <= 1024, true, "full table plus chat fit the viewport")
	local x = a.K.Within(Frame(a), board); eq(x >= board:GetWidth(), true, "chat is right of the actual table")
	w:As(a, a.ns.Arena.ui.FarkleBoard.Close)
	w:As(a, a.ns.FarkleTable.ShowUI, "practice")
	eq(Frame(a):IsShown(), false, "no pretend innkeeper conversation")
	Clean(w)
end)

test("Bones table chat: collapse removes the whole side extension rather than retaining a 98px bar", function()
	local w, a = Live({ 1024, 768 }, nil, nil, "shipped")
	local board = a.ns.Arena.ui.FarkleBoard.Window()
	Click(w, a, Frame(a).toggle)
	local normal = board:GetWidth() * board:GetScale() + 24
	assert(math.abs(board:GetParent():GetWidth() - normal) < 1e-8, "collapsed shell must have the original no-chat table width")
	Clean(w)
end)

test("Bones table chat: native chat components fill the table height and collapsing restores the exact normal table width", function()
	local function Run()
	local w, a = Live({ 1024, 768 }, nil, nil, "shipped")
	local board = a.ns.Arena.ui.FarkleBoard.Window()
	local shell, p = board:GetParent(), Frame(a)
	local chat = p.conversation
	assert(type(chat.search) == "table", "the actual embedded chat has the main ChatWindow search")
	eq(chat.search.template, "InputBoxTemplate", "Search uses the existing textured native template")
	eq(chat.searchLabel:GetText(), a.ns.L.SEARCH)
	eq(chat.bodyInset.template, "InsetFrameTemplate", "conversation uses the same native inset as main chat")
	eq(p.ground.template, "InsetFrameTemplate", "header and footer have native backing, never transparent world")
	assert(chat.search:GetFrameLevel() > chat.bodyInset:GetFrameLevel(), "Search is above the inset, never painted over")
	eq(chat:GetHeight(), board:GetHeight(), "chat includes the full footer, no transparent dead gap")
	local sx, sy, sw, sh = a.K.Within(chat.search, board)
	local cx, cy, cw, ch = a.K.Within(board.close, board)
	assert(sx + sw <= cx or cx + cw <= sx or sy + sh <= cy or cy + ch <= sy, "Search stays clear of the original window X")
	local _, navY = a.K.Within(p.strip, board)
	assert(sy + sh <= navY, "Search remains above Players/Everyone")
	assert(type(chat.input.label) == "table" and type(chat.input.hint) == "table", "the shared chat input label and placeholder are present")
	eq(#p.strip.nav, 2); eq(p.strip.nav[1].label:GetText(), "Players"); eq(p.strip.nav[2].label:GetText(), "Everyone")
	local normalWidth = board:GetWidth() * board:GetScale() + 24
	w:As(a, chat.search.SetFocus, chat.search)
	Click(w, a, p.toggle)
	eq(chat.search:HasFocus(), false, "collapse releases the embedded Search focus")
	assert(math.abs(shell:GetWidth() - normalWidth) < 1e-8, "no 98px collapsed side bar remains (native UI units)")
	local x, y, width, height = a.K.Within(p.toggle, board)
	assert(x >= 0 and x + width <= board:GetWidth() and y >= 0 and y + height <= board:GetHeight(), "Show chat stays inside the normal table")
	assert(p.toggle:IsVisible(), "the original table can reopen its chat")
	for _, button in ipairs({ board.helpButton, a.ns.Arena.ui.FarkleBoard._.parts().extra,
		a.ns.Arena.ui.FarkleBoard._.parts().bank, a.ns.Arena.ui.FarkleBoard._.parts().primary }) do
		if button:IsVisible() then
			local bx, by, bw, bh = a.K.Within(button, board)
			assert(x + width <= bx or bx + bw <= x or y + height <= by or by + bh <= y,
				("Show chat cannot cover %s: toggle %.1f/%.1f/%.1f/%.1f action %.1f/%.1f/%.1f/%.1f"):format(button:GetText(), x, y, width, height, bx, by, bw, bh))
		end
	end
	Click(w, a, p.toggle); assert(chat:IsVisible())
	Clean(w)
	end
	H.WithGamepadUI(false, Run); H.WithGamepadUI(true, Run)
end)

test("Bones table chat: actual pane search filters its own bubbles without changing main chat or leaking hidden words", function()
	local w, a, b = Live()
	Send(w, a, "One ordinary line"); w:Run(2); Send(w, a, "Another matching line")
	local pane = Frame(b).conversation
	assert(type(pane.search) == "table", "embedded Search exists")
	local before = b.ns.Views.Filter("chat")
	w:As(b, function() pane.search:SetText("MATCHING") end)
	w:As(b, UI(b).Select, "everyone"); eq(pane.search:GetText(), "", "tabs have independent search")
	w:As(b, function() pane.search:SetText("Public search") end)
	w:As(b, UI(b).Select, "players"); eq(pane.search:GetText(), "MATCHING", "Players search restores")
	eq(pane.bubbles[1].body:GetText(), "Another matching line", table.concat(b.errors, "; "))
	eq(pane.bubbles[2]:IsShown(), false)
	eq(b.ns.Views.Filter("chat"), before, "embedded search is independent of the main chat filter")
	w:As(b, b.ns.Filter.Add, "veiled")
	w:Run(2)
	Send(w, a, "A veiled secret")
	w:As(b, function() pane.search:SetText("secret") end)
	for _, bubble in ipairs(pane.bubbles) do eq(bubble:IsShown(), false, "hidden words cannot be found through Search") end
	Click(w, b, pane.search.clear)
	eq(pane.search:GetText(), ""); eq(pane.search:HasFocus(), false)
	eq(pane.bubbles[1]:IsShown(), true)
	Clean(w)
end)

test("Bones table chat: gamepad login and both switches use only the actual own input and Enter relinquishes focus", function()
	H.WithGamepadUI(true, function()
		local w, a = Live()
		local input = Frame(a).conversation.input
		eq(input.olympusBox, true); eq(input.autoFocus, false); eq(input:HasFocus(), false)
		eq(input.maxBytes, a.ns.ArenaChat.TEXT_MAX)
		Send(w, a, "Own gamepad input")
		eq(input:HasFocus(), false)
		H.WithGamepadUI(false, function()
			w:As(a, input.SetFocus, input); w:Fire(a, "INPUT_DEVICE_INTERFACE_TRANSITION", 0)
			eq(input:HasFocus(), false, "switch to mouse relinquishes this own box")
			w:As(a, function() input:SetText(""); input:SetFocus(); input:GetScript("OnEnterPressed")(input) end)
			eq(input:HasFocus(), false)
		end)
		w:As(a, input.SetFocus, input); w:Fire(a, "INPUT_DEVICE_INTERFACE_TRANSITION", 1)
		eq(input:HasFocus(), false, "switch to gamepad relinquishes this own box")
		Click(w, a, Frame(a).toggle); Click(w, a, Frame(a).toggle)
		eq(input:HasFocus(), false)
		Clean(w)
	end)
end)

test("Bones table chat: gated empty local preview uses real controls without invoking real room methods or sending", function()
	local w = FW.New({ compliance = "shipped" })
	local a = Setup(w, w:Player(N.fighterA, { testBuild = { n = 3, base = "1.2.1", built = w.clock, expires = w.clock + 86400 }, companion = {} }), { 1024, 768 })
	local chat, board
	w:As(a, function()
		assert(a.ns.FarkleTable.ShowUI("practice"))
		chat, board = UI(a), a.ns.Arena.ui.FarkleBoard
		eq(chat.Preview(board.Window(), board.ChatLayout), false, "test build alone is not an active simulation")
		assert(a.ns.Arena.SetSim(true))
		local methods, originals = { "TableRooms", "MayRead", "MaySend", "Open", "IsOpen", "Lines", "Send" }, {}
		for _, key in ipairs(methods) do
			originals[key] = a.ns.ArenaChat[key]
			a.ns.ArenaChat[key] = function() error("preview invoked real ArenaChat." .. key) end
		end
		local ok, why = pcall(function()
			assert(chat.Preview(board.Window(), board.ChatLayout))
			local p = Frame(a); eq(p:IsShown(), true); eq(#p.conversation.bubbles, 0)
			eq(#p.strip.nav, 2); assert(p.conversation.input:IsShown())
			p.conversation.input:SetText("Local preview draft")
			p.conversation.input:GetScript("OnEnterPressed")(p.conversation.input)
			eq(p.conversation.input:GetText(), "Local preview draft", "Enter never sends or erases the local draft")
			p.conversation.search:SetText("Private filter")
			assert(chat.Select("everyone")); eq(p.conversation.input:GetText(), ""); eq(p.conversation.search:GetText(), "")
			p.conversation.input:SetText("Everyone draft")
			assert(chat.Select("players")); eq(p.conversation.input:GetText(), "Local preview draft"); eq(p.conversation.search:GetText(), "Private filter")
			chat.Attach(board.Window(), nil, false, board.ChatLayout)
			assert(p:IsShown(), "normal simulation practice refresh does not erase the preview")
			Click(w, a, p.toggle); eq(p.conversation:IsShown(), false)
			Click(w, a, p.toggle); eq(p.conversation:IsShown(), true)
			chat.Hide(); eq(p:IsShown(), false); eq(p.refreshTicker, nil)
			eq(chat.HidePreview(), false, "Hide already cleared the local provider")
		end)
		for _, key in ipairs(methods) do a.ns.ArenaChat[key] = originals[key] end
		assert(ok, why)
		a.ns.Arena.SetSim(false)
	end)
	eq(#w:Sent{ from = a, type = "EC" }, 0, "empty preview emits no chat word")
	Clean(w)
end)

test("Bones table chat: ending the actual table hides both panels and retained lines cannot become a History chat", function()
	local w, a, b, s, id = Live()
	local rooms = w:As(a, a.ns.ArenaChat.TableRooms, id)
	Send(w, a, "A last private line")
	assert(w:As(a, a.ns.FarkleTable.Concede, id)); w:Run(3)
	for _, c in ipairs({ a, b, s }) do
		eq(Frame(c):IsShown(), false, c.name)
		eq(Frame(c).refreshTicker, nil, "ended table releases its panel's polling timer")
		eq(#w:As(c, c.ns.ArenaChat.Lines, rooms.players), 0)
		eq(#w:As(c, c.ns.ArenaChat.Lines, rooms.everyone), 0)
		eq(w:As(c, c.ns.ArenaChat.TableRooms, id), nil)
	end
	Clean(w)
end)

test("Bones table chat: actual successive tables keep only the bounded most recent independent drafts, preserving the current table", function()
	local w, _, _, s, first = Live()
	s.ns.ArenaChat.ROOMS_MAX = 2 -- a small per-client fixture cap exercises eviction with real tables
	local function NewTable(one, two)
		local a, b = Seat(w, one), Seat(w, two)
		for _, c in ipairs({ a, b, s }) do assert(w:As(c, c.ns.Roster.Scan)) end
		a.Arena.SetRules(true); b.Arena.SetRules(true); w:Group({ a, b }); w:AtInn(a.name, b.name)
		local id = assert(w:As(a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000, secs = 120 }))
		w:Run(0); assert(w:As(b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
		w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
		w:As(a, a.ns.FarkleTable.Roll, id); w:As(b, b.ns.FarkleTable.Roll, id); w:Run(0)
		assert(w:As(s, s.ns.FarkleTable.Watch, id)); w:Run(0)
		w:As(s, s.ns.FarkleTable.ShowUI, "board", id)
		return id
	end
	w:As(s, function() Frame(s).conversation.input:SetText("First table draft") end)
	w:As(s, function() Frame(s).conversation.search:SetText("First table search") end)
	local second = NewTable("Jora Pine", "Daren Slate")
	eq(Frame(s).conversation.input:GetText(), "")
	eq(Frame(s).conversation.search:GetText(), "", "a new table never inherits the previous table's search")
	w:As(s, function() Frame(s).conversation.input:SetText("Second table draft") end)
	w:As(s, function() Frame(s).conversation.search:SetText("Second table search") end)
	w:As(s, s.ns.FarkleTable.ShowUI, "board", first)
	eq(Frame(s).conversation.input:GetText(), "First table draft", "returning loads this table's actual draft")
	eq(Frame(s).conversation.search:GetText(), "First table search")
	w:As(s, s.ns.FarkleTable.ShowUI, "board", second)
	eq(Frame(s).conversation.input:GetText(), "Second table draft")
	eq(Frame(s).conversation.search:GetText(), "Second table search")
	local third = NewTable("Elin Vale", "Orrin Brook")
	eq(Frame(s).conversation.input:GetText(), "")
	w:As(s, function() Frame(s).conversation.input:SetText("Current table draft") end)
	w:As(s, s.ns.FarkleTable.ShowUI, "board", first)
	eq(Frame(s).conversation.input:GetText(), "", "oldest inactive table draft was evicted")
	w:As(s, s.ns.FarkleTable.ShowUI, "board", third)
	eq(Frame(s).conversation.input:GetText(), "Current table draft", "the current table survives the cap")
	Clean(w)
end)
