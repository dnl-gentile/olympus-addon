local ns, test, eq, WithWindow = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-guild%-labels%.lua$") or "./"

local function Choice(fn)
	local saved = ns.db.chatHideGuildNames
	local savedWatch = ns.WatchChat
	-- This scene runs before the global moderation scene. Load the real renderer, rather than
	-- treating the login stand-in as a live deletion module or copying its body into the test.
	local cns = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", cns)
	ns.WatchChat = cns.WatchChat
	local ok, err = pcall(fn)
	ns.db.chatHideGuildNames = saved
	ns.WatchChat = savedWatch
	if not ok then error(err, 0) end
end

test("Chat guild labels: visible by default, explicitly hidden locally, restored without changing the name link or message", function()
	Choice(function()
		local C = ns.Channels
		local function Line() return C.FormatLine("A", "Test Speaker-" .. ns.realm, "Olympus Fixture", "MA", "hello |cffff0000world", true) end
		for _, value in ipairs({ false, "not a boolean", 1 }) do
			ns.db.chatHideGuildNames = value
			eq(C.ShowGuildNames(), true)
			assert(Line():find("<Olympus Fixture>", 1, true), "malformed choices do not hide names")
		end
		ns.db.chatHideGuildNames = nil
		local original = Line()
		eq(C.ShowGuildNames(), true, "an existing account keeps its display")
		eq(C.SetGuildNamesShown(false), true)
		eq(ns.db.chatHideGuildNames, true)
		eq(C.ShowGuildNames(), false)
		eq(Line(), (original:gsub(" <Olympus Fixture>", "", 1)), "only the adjacent label changes")
		assert(Line():find("|Hplayer:", 1, true), "the real sender link remains")
		assert(Line():find("hello ||cffff0000world", 1, true), "the existing sanitizer remains")
		-- Reformatting saved history follows the account choice without mutating that history.
		local entry = { tier = "A", sender = "Test Speaker-" .. ns.realm, guild = "Olympus Fixture", text = "saved" }
		C.FormatLine(entry.tier, entry.sender, entry.guild, nil, entry.text)
		eq(entry.guild, "Olympus Fixture"); eq(entry.sender, "Test Speaker-" .. ns.realm); eq(entry.text, "saved")
		eq(C.SetGuildNamesShown(true), true)
		eq(ns.db.chatHideGuildNames, nil)
		eq(Line(), original)
	end)
end)

test("Chat guild sender colours: stable by native identity and confined to sender names", function()
	WithWindow(function(w)
		local rooms = ns.ChatRooms
		local alder, bram = "Alder-" .. ns.realm, "Bram-" .. ns.realm
		local sparrow, moved = "Sparrow Vale-CAMWOWUS2Realm1PvE", "Sparrow Vale-CAMWOWUS2Realm5PvE"
		local classColours, isCovered, coverSwap = RAID_CLASS_COLORS, ns.IsCovered, ns.CoverSwap
		local classColour = "ffc79c6e"
		RAID_CLASS_COLORS = { [ns.CLASS_FILES.WA] = { colorStr = classColour } }
		local ok, err = pcall(function()
			ns.db.chatRooms, ns.db.addonChat = true, true
			local covered = "Covered-" .. ns.realm
			ns.IsCovered = function(who) return who == covered end
			ns.CoverSwap = function(name) return name == "Covered" and "Alias" or name end
			assert(rooms.ReceiveGuild("Alder first", alder))
			assert(rooms.ReceiveGuild("Original sub-realm", sparrow))
			assert(rooms.ReceiveGuild("Bram speaks", bram))
			assert(rooms.ReceiveGuild("Alder again", alder:upper()))
			assert(rooms.ReceiveGuild("New sub-realm", moved))
			assert(rooms.ReceiveGuild("Cover line", covered))
			assert(rooms.ReceiveGuild("My own line", ns.me))
			for _, line in ipairs(rooms.RawHistory("guild")) do line.class = "WA" end
			ns.rdb.chat = { A = { { t = ns.Now(), sender = alder, guild = GetGuildInfo("player"),
				text = "Public line", class = "WA" } } }
			local frame = w.CW.Open("A")
			local function Bubble(words)
				for _, bubble in ipairs(frame.bubbles) do
					if bubble:IsShown() and bubble.entry and bubble.entry.text == words then return bubble end
				end
				error("missing bubble: " .. words)
			end
			local function Colour(words, name)
				local text = Bubble(words).who:GetText()
				local colour, label = text:match("|c(%x%x%x%x%x%x%x%x)(.-)|r")
				eq(label, name, text)
				return colour
			end
			eq(Colour("Public line", "Alder"), classColour, "public Olympus keeps its class colours")
			assert(w.CW.SelectLogical("guild"))
			local first, second = Colour("Alder first", "Alder"), Colour("Bram speaks", "Bram")
			assert(first ~= second, "two members of the same class have distinct name colours")
			eq(Colour("Alder again", ns.DisplayName(alder:upper())), first, "case in the server's name does not change identity")
			eq(Colour("Original sub-realm", ns.DisplayName(sparrow)), Colour("New sub-realm", ns.DisplayName(moved)),
				"a new sub-realm stamp on Forever does not change identity")
			assert(Bubble("Cover line").who:GetText():find("^Alias "), "a cover alias does not reveal the real sender colour")
			eq(Bubble("Alder first").body:GetText(), "Alder first", "only the sender name changes")
			eq(Bubble("My own line").who:GetText(), ns.L.CHATWIN_YOU)
			w.CW.Changed()
			w.CW.Render()
			eq(Colour("Alder first", "Alder"), first, "the colour does not depend on render state")
			w.CW.SelectLegacy("A")
			eq(Colour("Public line", "Alder"), classColour, "the guild colour cannot enter the public header cache")
		end)
		RAID_CLASS_COLORS, ns.IsCovered, ns.CoverSwap = classColours, isCovered, coverSwap
		if not ok then error(err, 0) end
	end)
end)

test("Chat guild labels: the actual gear changes normal and deleted headers while retaining search, tooltip identity and the draft", function()
	WithWindow(function(w)
		Choice(function()
			local C, entry = ns.Channels, { t = 100, sender = "Test Speaker-" .. ns.realm, guild = "Olympus Fixture", text = "fixture line" }
			ns.db.chatHideGuildNames = nil
			ns.rdb.chat = { A = { entry } }
			local f = w.CW.Open("A")
			local function Bubble()
				for _, b in ipairs(f.bubbles) do if b:IsShown() and b.entry == entry then return b end end
				error("the actual sender bubble is absent")
			end
			assert(Bubble().who:GetText():find("<Olympus Fixture>", 1, true))
			f.input:SetText("draft still here")
			local function Setting(label)
				for _, row in ipairs(w.CW.SettingsLines()) do if row.text:find(label, 1, true) then return assert(row.onClick) end end
				error("missing guild-label setting: " .. tostring(label))
			end
			Setting(ns.L.CHATSET_GUILDS_SHOWN)()
			eq(C.ShowGuildNames(), false)
			eq(Bubble().who:GetText():find("<Olympus Fixture>", 1, true), nil)
			assert(Bubble().who:GetText():find("Test Speaker", 1, true), "the sender remains")
			assert(Bubble().header.full:find("<Olympus Fixture>", 1, true), "the tooltip retains identity context")
			eq(f.input:GetText(), "draft still here")
			f.search:SetText("Olympus Fixture")
			eq(Bubble().entry, entry, "search still knows the actual guild")
			entry.del = true; w.CW.Render()
			eq(Bubble().who:GetText():find("<Olympus Fixture>", 1, true), nil, "deleted headers obey the same choice")
			eq(Bubble().body:GetText(), ns.WatchChat.DeletedBody())
			Setting(ns.L.CHATSET_GUILDS_HIDDEN)()
			assert(Bubble().who:GetText():find("<Olympus Fixture>", 1, true))
			eq(entry.guild, "Olympus Fixture", "never edit source evidence")
		end)
	end)
end)
