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
local function Live(screen, guild, renderer)
	local files = {}
	for _, file in ipairs(H.World.ARENA_FILES) do
		if file == "ArenaChat" then files[#files + 1] = "WatchChat" end
		files[#files + 1] = file
	end
	local w = FW.New({ arenaFiles = files })
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

test("Bones table chat: ending the actual table hides both panels and retained lines cannot become a History chat", function()
	local w, a, b, s, id = Live()
	local rooms = w:As(a, a.ns.ArenaChat.TableRooms, id)
	Send(w, a, "A last private line")
	assert(w:As(a, a.ns.FarkleTable.Concede, id)); w:Run(3)
	for _, c in ipairs({ a, b, s }) do
		eq(Frame(c):IsShown(), false, c.name)
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
	local second = NewTable("Jora Pine", "Daren Slate")
	eq(Frame(s).conversation.input:GetText(), "")
	w:As(s, function() Frame(s).conversation.input:SetText("Second table draft") end)
	w:As(s, s.ns.FarkleTable.ShowUI, "board", first)
	eq(Frame(s).conversation.input:GetText(), "First table draft", "returning loads this table's actual draft")
	w:As(s, s.ns.FarkleTable.ShowUI, "board", second)
	eq(Frame(s).conversation.input:GetText(), "Second table draft")
	local third = NewTable("Elin Vale", "Orrin Brook")
	eq(Frame(s).conversation.input:GetText(), "")
	w:As(s, function() Frame(s).conversation.input:SetText("Current table draft") end)
	w:As(s, s.ns.FarkleTable.ShowUI, "board", first)
	eq(Frame(s).conversation.input:GetText(), "", "oldest inactive table draft was evicted")
	w:As(s, s.ns.FarkleTable.ShowUI, "board", third)
	eq(Frame(s).conversation.input:GetText(), "Current table draft", "the current table survives the cap")
	Clean(w)
end)
