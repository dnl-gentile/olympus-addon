local ns, test, eq, H = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-tab%-access%.lua$") or "./"
local AT, REALM, GUILD = 1795000000, "CAMWOWUS1Realm2PvE", "Olympus Azure"
local SELF, GM = "Test Member-" .. REALM, "Guild Master-" .. REALM

local function World(run)
	H.WithUI(function()
		local saved = { db = ns.db, rdb = ns.rdb, realm = ns.realm, group = ns.group, me = ns.me, faction = ns.faction,
			now = ns.Now, serverTime = ns.Data.ServerTime, verify = ns.Verify, chat = ns.ChatWindow,
			guildInfo = GetGuildInfo, inGuild = IsInGuild, fugitives = ns.FederationFugitives, netOff = ns.Data.NetOff }
		local roster, rosterSaved = ns.Roster, {}
		for _, key in ipairs({ "guild", "group", "faction", "generation", "snapshotAt", "complete", "byName", "members" }) do rosterSaved[key] = roster[key] end
		local attached, calls = false, 0
		local ok, err = pcall(function()
			ns.db = { accord = { v = ns.ACCORD_VERSION, yes = true }, addonChat = true,
				log = {}, errors = {}, blocked = {}, chatWarned = { A = true } }
			ns.realm, ns.group, ns.me, ns.faction = REALM, "ForeverPvE", SELF, "Alliance"
			ns.Now, ns.Data.ServerTime = function() return AT end, function() return AT end
			GetGuildInfo, IsInGuild = function() return GUILD, "Member", 4 end, function() return true end
			ns.rdb = { guilds = { [GUILD] = { total = 2, online = 2, t = AT, leader = "Guild Master", realm = REALM, officers = {}, zones = {}, mine = true } } }
			ns.Data.NetOff = function() return false end
			ns.FederationFugitives = { Suspended = function() return false end }
			roster.guild, roster.group, roster.faction, roster.generation = GUILD, ns.group, ns.faction, 1
			roster.snapshotAt, roster.complete = AT, true
			roster.byName = { [SELF] = 4, [GM] = 0 }
			roster.members = { { full = SELF, rankIndex = 4 }, { full = GM, rankIndex = 0 } }
			local vns = setmetatable({ On = function() end, RegisterEvent = function() end,
				Comm = { Handle = function() end } }, { __index = ns })
			assert(loadfile(ROOT .. "Olympus/Verify.lua"))("Olympus", vns)
			ns.Verify = vns.Verify
			ns.ChatWindow = { Attach = function() attached, calls = true, calls + 1 end,
				Detach = function() attached = false end }
			local UI = H.LoadUI()
			local function Approve()
				local entry = { k = "A", at = AT - 5, guild = GUILD, gm = GM, by = "Council Witness-" .. REALM }
				ns.rdb.verify = { list = { [ns.Fold(GUILD)] = entry } }
				return entry
			end
			local function View(reason)
				UI.SelectTab("chat"); UI.Refresh()
				local shown, tab = UI.SelfTestView()
				eq(shown.tab, "chat", "the reason remains reachable on Chat")
				for _, button in ipairs(shown.frame.tabs) do if button.key == "chat" then tab = button end end
				assert(tab and tab:IsShown(), "a member never loses the Chat navigation route")
				if reason then
					local notice
					for _, line in ipairs(shown.lines) do if line.id == "chat-access" then notice = line end end
					assert(notice, "the actual UI renders the reason")
					eq(notice.chatAccess, reason); assert(type(notice.text) == "string" and notice.text ~= "")
					eq(shown.frame.scroll:IsShown(), true, "the explanatory list is visible")
					eq(attached, false, "no chat history or composer is attached while authorization waits")
				end
				return shown
			end
			local function Denied()
				eq(ns.Channels.CanUse("A"), false)
				eq(ns.Channels.CanUse("C"), false); eq(ns.Channels.CanUse("L"), false)
				local sent, why = ns.Channels.Send("A", "a blocked line")
				eq(sent, false); eq(why, "federation")
				local got, reason = ns.Channels.Receive("CHANNEL", GM, ns.Codec.EncodeChat("A", GUILD, 1, "MA", "a blocked line"))
				eq(got, false); eq(reason, "federation")
			end
			run(UI, Approve, View, Denied, function() return attached, calls end)
		end)
		for _, key in ipairs({ "guild", "group", "faction", "generation", "snapshotAt", "complete", "byName", "members" }) do roster[key] = rosterSaved[key] end
		ns.db, ns.rdb, ns.realm, ns.group, ns.me, ns.faction = saved.db, saved.rdb, saved.realm, saved.group, saved.me, saved.faction
		ns.Now, ns.Data.ServerTime, ns.Verify, ns.ChatWindow = saved.now, saved.serverTime, saved.verify, saved.chat
		GetGuildInfo, IsInGuild, ns.FederationFugitives, ns.Data.NetOff = saved.guildInfo, saved.inGuild, saved.fugitives, saved.netOff
		if not ok then error(err, 0) end
	end)
end

test("chat tab access: pending approval keeps a visible read-only route without channel capabilities", function()
	World(function(UI, _, View, Denied)
		local shown = {}; for _, key in ipairs(UI.CompanionTabs()) do shown[key] = true end
		eq(shown.chat, true)
		for _, key in ipairs({ "throne", "vox", "treasury", "workshop" }) do eq(shown[key], nil, "no added officer power") end
		View("pending"); Denied()
		local old = rawget(ns.L, "CHAT_ACCESS_PENDING")
		ns.L.CHAT_ACCESS_PENDING = nil
		local _, missingText = UI.ChatAccess()
		ns.L.CHAT_ACCESS_PENDING = old
		eq(missingText, ns.L.RESTART_NEEDED, "an old TOC never displays a missing locale key")
	end)
end)

test("chat tab access: missing chat module keeps the restart notice first and restores the authorized pane when loaded", function()
	World(function(UI, Approve, _, _, Pane)
		Approve()
		local ready = ns.ChatWindow
		for _, module in ipairs({ { missing = true }, { Attach = ready.Attach }, false }) do
			ns.ChatWindow = module or nil
			UI.SelectTab("chat"); UI.Refresh()
			local view = UI.SelfTestView()
			eq(view.tab, "chat")
			eq(UI.ChatAccess(), "restart")
			eq(#view.lines, 1, "the legacy restart notice has no extra header before it")
			eq(view.frame.views.chat.rows[1].left:GetText(), ns.Views.Grey(ns.L.RESTART_NEEDED),
				"the first rendered row tells the player to restart")
			eq(view.frame.scroll:IsShown(), true, "the restart notice stays visible")
			eq(Pane(), false)
			eq(select(2, Pane()), 0, "the unavailable module is never attached")
		end
		ns.ChatWindow = ready
		UI.Refresh()
		eq(UI.ChatAccess(), nil)
		eq(Pane(), true, "the authorized loaded module still restores the conversation")
	end)
end)

test("chat tab access: an existing approval waits for current native roster and resumes without reapproval", function()
	World(function(UI, Approve, View, Denied, Pane)
		local entry = Approve()
		ns.Roster.complete = false
		View("roster"); Denied()
		eq(select(2, UI.ChatAccess()), ns.L.CHAT_ACCESS_ROSTER)
		ns.Roster.complete = true
		UI.Refresh()
		eq(UI.ChatAccess(), nil); eq(Pane(), true)
		eq(ns.Channels.CanUse("A"), true)
		eq(ns.Channels.CanUse("C"), false); eq(ns.Channels.CanUse("L"), false)
		eq(ns.rdb.verify.list[ns.Fold(GUILD)], entry, "the original approval remains unchanged")
		ns.Roster.snapshotAt = AT - ns.Roster.AUTHORITY_FRESH - 1
		View("roster"); Denied()
	end)
end)

test("chat tab access: revoked or contradictory leadership stays explained and authorization still denies", function()
	World(function(_, Approve, View, Denied)
		local entry = Approve()
		entry.k = "R"
		View("revoked"); Denied()
		entry.k = "A"
		ns.rdb.guilds[GUILD].leader = "Different Master"
		ns.Roster.complete = false
		View("roster"); Denied()
		ns.Roster.complete = true
		View("leadership"); Denied()
		ns.rdb.guilds[GUILD].leader = "Guild Master"
		ns.Roster.byName[GM] = 2
		View("leadership"); Denied()
	end)
end)

test("chat tab access: suspended participation stays visible and every shipped language explains the wait", function()
	World(function(_, Approve, View, Denied)
		Approve()
		ns.FederationFugitives.Suspended = function() return true end
		View("suspended"); Denied()
	end)
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "itIT", "ruRU" }) do
		local other = { On = function() end }
		local env = setmetatable({ GetLocale = function() return code end }, { __index = _G })
		local function Load(path)
			local chunk = assert(loadfile(ROOT .. "Olympus/" .. path .. ".lua"))
			setfenv(chunk, env)
			chunk("Olympus", other)
		end
		-- Match the TOC: English keys first, then the guarded Russian-only file.
		Load("Locales")
		Load("Locales/ChatAccessText")
		local english = other.L.CHAT_ACCESS_IDENTITY
		Load("Locales/ruRU")
		if code == "ruRU" then
			assert(other.L.CHAT_ACCESS_IDENTITY ~= english, "the Russian-only file supplies the translation")
		else
			eq(other.L.CHAT_ACCESS_IDENTITY, english, "the Russian-only file leaves other clients unchanged")
		end
		for _, reason in ipairs({ "IDENTITY", "ROSTER", "PENDING", "REVOKED", "LEADERSHIP", "POLICY", "SUSPENDED" }) do
			local text = other.L["CHAT_ACCESS_" .. reason]
			assert(type(text) == "string" and text ~= "", code .. ": " .. reason)
		end
	end
end)
