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
