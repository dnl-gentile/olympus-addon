local ns, test, eq, X = ...
local Codec = ns.Codec
local ROOT = debug.getinfo(1, "S").source:match("^@(.*/)tests/[^/]+$") or ""
local Secret = assert(loadfile(ROOT .. "tests/arena/lib/secret.lua"))()
local WithWindow, WithGamepadUI, RelayWorld = X.WithWindow, X.WithGamepadUI, X.RelayWorld
local Line, BubbleWith, T0, KeepSendGap = X.Line, X.BubbleWith, X.T0, X.KeepSendGap

-- 1.5.4 (the dev, 2026-11-08: "os itens aparecerem corretamente, porque tá aparecendo quebrado...
-- no chat da nossa janela. Não tá aparecendo certinho com o texto em highlight, clicável, com hover
-- que aparece os detalhes do item"; Fernmelder saw the same). On Forever a chat line travels
-- inside the relay's envelopes (RL, RM, RG: Relay.lua), which Comm strips of every "|" before
-- anything reads them (Codec.Plain, 0.9.2: only a bare M1 line kept its links), so a link arrived
-- as "cff1eff00Hitem:14342...h[Mooncloth]hr". The links a line may carry now travel as tokens
-- with no "|" (Codec.PackLinks, in EncodeChat) and are links again at the receiver
-- (Codec.UnpackLinks, in DecodeChat); the Chat tab shows an item with the name and colour this
-- client's item data gives it, and a left click on a link opens the game's link window as a click
-- in the game's chat does (SetItemRef), never with the gamepad UI. Invented names throughout.
local GUILD = "Olympus II"
local LINK = "item:14342::::::::60:::::"
local ITEM = "|cff1eff00|H" .. LINK .. "|h[Mooncloth]|h|r"
local SPELL = "|cff71d5ff|Hspell:8690|h[Hearthstone]|h|r"
local ENCHANT = "|cffffd000|Henchant:7420|h[Enchant Chest - Minor Health]|h|r"
local QUEST = "|cffffff00|Hquest:1234:60|h[The Defias Brotherhood]|h|r"
local BARE = "|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h"
local NAMED = "|cnIQ4:|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h|r"
local TORCH_DATA = "item:1172::::::::25:1490::11::::::::"
local TORCH = "|cnIQ3:|H" .. TORCH_DATA .. "|h[Graysons Torch]|h|r"
local TORCH_HEX = "|cff0070dd|H" .. TORCH_DATA .. "|h[Grayson's Torch]|h|r"

local function Links(text)
	local out = {}
	for kind in text:gmatch("|H(%a+):") do out[#out + 1] = kind end
	return table.concat(out, ",")
end

test("recruit call-out link: exact name survives M1 packing; fallback is readable and forged labels stay text", function()
	for _, name in ipairs({ "New Recruit", "Realm Recruit-OtherRealm", "Zoë Fírè-OtherRealm" }) do
		local link = assert(Codec.RecruitLink(name), name)
		local data = assert(link:match("|H([^|]+)|h"))
		eq(Codec.RecruitLinkName(data), name)
		eq(Codec.SanitizeChat(link), link, "the exact recruit link alone is admitted")
		local packed = Codec.PackLinks(link)
		assert(not packed:find("|", 1, true), packed)
		assert(packed:find("^%[" .. name:gsub("(%W)", "%%%1") .. "%]%("), "old clients see the name first: " .. packed)
		local msg = assert(Codec.EncodeChat("A", GUILD, 77, "PA", "Recruit " .. link))
		assert(not msg:find("|", 1, true), "existing M1 packed transport only")
		eq(Codec.DecodeChat(msg).text, "Recruit " .. link, "remote recipient reconstructs the exact link")
	end

	local savedSplit = ns.splitNames
	ns.splitNames = true
	local noncanonical = "[First-Surname](addon:Olympus:recruit:Rmlyc3QtU3VybmFtZQ/)"
	local decoded = assert(Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 76, "PA", noncanonical))).text
	ns.splitNames = savedSplit
	assert(not decoded:find("|H", 1, true),
		"a payload that is not this client's exact command spelling stays readable text: " .. decoded)

	local good = assert(Codec.RecruitLink("New Recruit"))
	local packed = Codec.PackLinks(good)
	local wrong = packed:gsub("^%[New Recruit%]", "[Other Recruit]")
	local shown = assert(Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 78, "PA", wrong))).text
	assert(not shown:find("|H", 1, true), "a forged visible name never becomes a link: " .. shown)
	for _, token in ipairs({
		"[New Recruit](addon:Olympus:recruit:not_base64! /)",
		"[New Recruit](addon:Other:recruit:TmV3IFJlY3J1aXQ/)",
		"[New Recruit](player:New Recruit/)",
		"[New Recruit](addon:Olympus:other:TmV3IFJlY3J1aXQ/)",
	}) do
		local decoded = assert(Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 79, "PA", token))).text
		assert(not decoded:find("|H", 1, true), "malformed/foreign token stays readable text: " .. token)
	end
end)
test("1.5.4 chat links on the wire: a line's links leave as tokens without a pipe, so Codec.Plain leaves them whole, and come back as the same links", function()
	for _, link in ipairs({ ITEM, SPELL, ENCHANT, QUEST, BARE, NAMED }) do
		local text = "look " .. link .. " cheap, ~2g: a=b"
		eq(Codec.SanitizeChat(text), text, "a link a line may carry")
		local msg = Codec.EncodeChat("A", GUILD, 7, "WA", text)
		assert(msg, "encoded")
		assert(not msg:find("|", 1, true), "no pipe on the wire: " .. msg)
		eq(Codec.Plain(msg), msg, "the relay's envelopes lose nothing of it")
		local d = Codec.DecodeChat(msg)
		eq(d.text, text, "the same link at the receiver")
		eq(d.tier, "A"); eq(d.guild, GUILD); eq(d.id, 7); eq(d.class, "WA")
		assert(#Codec.PackLinks(link) < #link, "a token is never longer than its link: " .. Codec.PackLinks(link))
		-- The token is text to a client before 1.5.4: the name first, readable.
		assert(Codec.PackLinks(link):find("^%[[^%]]+%]%(") , "the name first: " .. Codec.PackLinks(link))
	end
	-- Pack and unpack are each other's inverse and idempotent; a "||" typed stays one.
	local text = "a||b " .. ITEM .. " " .. SPELL .. " c"
	local packed = Codec.PackLinks(text)
	eq(Codec.PackLinks(packed), packed, "pack twice")
	eq(Codec.UnpackLinks(packed), text, "unpack")
	eq(Codec.UnpackLinks(text), text, "unpack of links: as they are")
	eq(Codec.UnpackLinks(Codec.UnpackLinks(packed)), text, "unpack twice")
	-- A long line of links: each part fits one message and decodes to itself.
	local long = Codec.SanitizeChat((ITEM .. " "):rep(4) .. ("word "):rep(30) .. SPELL .. " " .. QUEST)
	local parts, cut = Codec.SplitChat(long, Codec.ChatBudget(GUILD, "WA"), Codec.CHAT_PARTS)
	eq(cut, false); assert(#parts >= 2, "split")
	for _, p in ipairs(parts) do
		local m = Codec.EncodeChat("C", GUILD, 9999, "WA", p)
		assert(m and #m <= 255, "fits")
		eq(Codec.DecodeChat(m).text, p, "a part with its links")
	end
	-- A line without a link: the wire is the text itself, as before.
	eq(Codec.EncodeChat("A", GUILD, 1, "", "hello there"), "M1~A~Olympus II~1~~hello there")
end)

test("1.5.4 chat link tokens: only item, spell, enchant and quest links with sound data become links again; anything else typed, and every escape code, stays text", function()
	local function Shown(text) return Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 1, "", text)).text end
	for _, typed in ipairs({
		"[Someone](player:Someone/ff00ff00)",             -- a player link would open the game's chat box
		"[click](url:evil/ff00ff00)",                      -- a foreign link type
		"[Mooncloth](item:abc/ff1eff00)",                   -- letters in the data
		"[Mooncloth](item:/ff1eff00)",                      -- no id
		"[Mooncloth](item:0/ff1eff00)",                     -- a zero id
		"[Mooncloth](item:14342/zz1eff00)",                 -- a colour that is none
		"[Mooncloth](item:14342/ff1eff00ff)",               -- a colour too long
		"[](item:14342/ff1eff00)",                          -- no name
		"[" .. ("x"):rep(101) .. "](item:14342/ff1eff00)",  -- a name past 100 bytes
		"[Mooncloth](item:" .. ("1:"):rep(33) .. "1/)",     -- 34 fields
		"[Mooncloth](item:" .. ("9"):rep(121) .. "/)",      -- data past 120 bytes
		"[Mooncloth](achievement:1/ff1eff00)",              -- not one of the four
	}) do
		local shown = Shown(typed)
		eq(Links(shown), "", "no link from: " .. typed)
		assert(not shown:find("|", 1, true), "no escape from: " .. typed .. " -> " .. shown)
	end
	-- A pipe or a texture inside a token's name: the name may not hold one, and the pipe shows escaped.
	local piped = Shown("[Moon|cffff0000cloth](item:14342/ff1eff00)")
	eq(Links(piped), ""); eq(piped, "[Moon||cffff0000cloth](item:14342/ff1eff00)")
	eq(Links(Shown("[|TInterface\\Icons\\x:16|t](item:14342/ff1eff00)")), "")
	-- Escape codes typed raw are neutralised as ever (SanitizeChat), beside a real link.
	eq(Shown("|cffff0000red|r " .. ITEM .. " |TInterface\\Icons\\x:16|t |Hplayer:Someone|h[Someone]|h"),
		"||cffff0000red||r " .. ITEM .. " ||TInterface\\Icons\\x:16||t ||Hplayer:Someone||h[Someone]||h")
	-- A sound token typed by hand is a link, as a raw link typed into an addon message was: the
	-- four kinds, with or without a colour, a Mainline colour name too.
	eq(Shown("[Mooncloth](item:14342::::::::60:::::/ff1eff00)"), ITEM)
	eq(Shown("[Thunderfury](item:19019::::::::60:::::::::/)"), BARE)
	eq(Shown("[Thunderfury](item:19019::::::::60:::::::::/nIQ4:)"), NAMED)
	eq(Links(Shown("[a](spell:1/) [b](enchant:2/) [c](quest:3:60/)")), "spell,enchant,quest")
	-- What comes out is what SanitizeChat lets through, and nothing more.
	for _, typed in ipairs({ "[x](item:1/)", "[Someone](player:Someone/)", "a [b](c) d", "[](x)" }) do
		local shown = Shown(typed)
		eq(Codec.SanitizeChat(shown), shown, "clean: " .. typed)
	end
end)

test("1.5.4 chat links by the relay: a line's link reaches a guildmate whole through the relay's hop to the guild (RG), the relay's hop to the reporters (RM), and the channel's own text, each the same text", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return GUILD, "Member", 3 end
		local R, Deliver, _, heard, Pump, Sent = RelayWorld("Hildryn Payne-Realm", GUILD)
		local text = "look " .. ITEM .. " cheap"
		local msg = R.Codec.EncodeChat("A", GUILD, 7, "WA", text)
		-- Hop 3: a reporter's hand-over to the guild, as every guildmate hears a line on Forever.
		Deliver("GUILD", "Guild Rep-Realm", "RG~L~Orig Inal-Realm~" .. msg)
		eq(#heard, 1, "the line heard"); eq(heard[1].sender, "Orig Inal-Realm")
		local got = R.Codec.DecodeChat(heard[1].text)
		assert(got, "a chat line: " .. tostring(heard[1].text))
		eq(got.text, text, "the link whole, by the guild")
		-- The channel's own text (ChatHall.OnChannel hands it to Comm.Inject): the same text.
		R.Comm.Inject("CHANNEL", "Orig Inal-Realm", msg, true)
		eq(#heard, 2); eq(heard[2].text, heard[1].text, "one text on both ways: each client takes the line once")
		-- Hop 1 at a relay's client: a reporter registered, the line forwarded to him with its link.
		Deliver("WHISPER", "Zed Far-Realm", "RL~P~RR~Olympus Zeus")
		Deliver("WHISPER", "Orig Inal-Realm", "RL~L~" .. msg)
		Pump()
		local rm = Sent("RM~L~")
		eq(#rm, 1, "forwarded once")
		local body = rm[1].msg:match("^RM~L~[^~]+~(.*)$")
		eq(R.Codec.DecodeChat(body).text, text, "the link whole, to the reporter")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

test("1.5.4 chat links at the sender: a line with a link leaves without a pipe, the sender's own line and echo are the link, and the history (what moderation reads) holds the link", function()
	local C = ns.Channels
	local saved = { me = ns.me, split = ns.splitNames, ready = ns.Comm.ChannelReady, room = ns.Comm.ChatRoom, send = ns.Comm.SendChat,
		guild = GetGuildInfo, realm = ns.realm }
	local ok, err = pcall(KeepSendGap, function()
		ns.me, ns.splitNames, ns.realm = "Tester Surname-Realm", true, "Realm"
		GetGuildInfo = function() return GUILD, "Member", 3 end
		ns.Comm.ChannelReady = function() return true end
		ns.Comm.ChatRoom = function() return 3 end
		local sent
		ns.Comm.SendChat = function(msg, done) sent = msg; done(true); return true end
		local t = 2000000
		local text = "wts " .. ITEM .. " 5g"
		assert(C.Send("A", text, t))
		assert(sent, "sent")
		assert(not sent:find("|", 1, true), "no pipe on the wire: " .. sent)
		eq(Codec.DecodeChat(sent).text, text, "the others read the link")
		local list = C.History("A")
		eq(list[#list].text, text, "our own line kept as the link")
		eq(list[#list].mine, true)
		-- Our own echo, however the server writes our name: ours, not shown again.
		local shown, why = C.Receive("CHANNEL", "Tester-Surname", sent, t + 1)
		eq(shown, false); eq(why, "own")
		-- A token typed by hand goes out as the link it names, so what we keep is what the others see.
		sent = nil
		assert(C.Send("A", "see [Hearthstone](spell:8690/ff71d5ff) now", t + 10))
		eq(Codec.DecodeChat(sent).text, "see " .. SPELL .. " now")
		list = C.History("A")
		eq(list[#list].text, "see " .. SPELL .. " now")
	end)
	ns.me, ns.splitNames, ns.Comm.ChannelReady, ns.Comm.ChatRoom, ns.Comm.SendChat = saved.me, saved.split, saved.ready, saved.room, saved.send
	GetGuildInfo, ns.realm = saved.guild, saved.realm
	if not ok then error(err, 0) end
end)

test("recruit call-out link: Channels.Send A and remote Receive use the existing public M1 route", function()
	local C = ns.Channels
	local saved = { me = ns.me, split = ns.splitNames, ready = ns.Comm.ChannelReady, room = ns.Comm.ChatRoom,
		send = ns.Comm.SendChat, guild = GetGuildInfo, realm = ns.realm }
	local ok, err = pcall(KeepSendGap, function()
		ns.me, ns.splitNames, ns.realm = "Caller Member-Realm", false, "Realm"
		GetGuildInfo = function() return GUILD, "Member", 3 end
		ns.Comm.ChannelReady = function() return true end
		ns.Comm.ChatRoom = function() return 3 end
		local sent
		ns.Comm.SendChat = function(msg, done) sent = msg; done(true); return true end
		local name = "Realm Recruit-OtherRealm"
		local line = ns.L.RECRUIT_CALLOUT_TEXT:format(assert(Codec.RecruitLink(name)))
		assert(C.Send("A", line, 3000000))
		assert(sent and sent:find("^M1~A~"), tostring(sent))
		assert(not sent:find("|", 1, true), "the M1 wire uses the existing packed textual fallback")
		assert(sent:find("[Realm Recruit-OtherRealm](addon:Olympus:recruit:", 1, true), "old clients see the exact readable name first")
		eq(Codec.DecodeChat(sent).text, line)
		-- A roster-backed remote member: Receive must exercise its real public-room admission too.
		local heard, why = C.Receive("CHANNEL", "Member2-Realm", sent, 3000001)
		eq(heard, true, why)
		local history = C.History("A")
		eq(history[#history].text, line, "the remote public room retains the reconstructed exact link")
	end)
	ns.me, ns.splitNames, ns.Comm.ChannelReady, ns.Comm.ChatRoom, ns.Comm.SendChat = saved.me, saved.split, saved.ready, saved.room, saved.send
	GetGuildInfo, ns.realm = saved.guild, saved.realm
	if not ok then error(err, 0) end
end)
-- The Chat tab's stand-ins for the client's item data and link window.
local function WithItemData(fn)
	local savedItem, savedRef, savedInfo, savedShift = rawget(_G, "C_Item"), rawget(_G, "SetItemRef"), rawget(_G, "GetItemInfo"), IsShiftKeyDown
	local savedColours = rawget(_G, "ITEM_QUALITY_COLORS")
	local ok, err = pcall(function()
		local known = { [14342] = { "Mooncloth", ITEM, 2 },
			-- Forever returns a named quality colour; its cached link need not have the sender's payload.
			[1172] = { "Grayson's Torch", "|cnIQ3:|Hitem:1172::::::::60:::::|h[Grayson's Torch]|h|r", 3 } }
		-- Exact normalized bytes for the expected green/blue, without rounding the fixture's RGB.
		ITEM_QUALITY_COLORS = { [2] = { r = 30 / 255, g = 1, b = 0 }, [3] = { r = 0, g = 112 / 255, b = 221 / 255 } }
		local asked, refs = {}, {}
		GetItemInfo = nil
		C_Item = {
			GetItemInfo = function(id) local k = known[tonumber(id)] if k then return k[1], k[2], k[3] end end,
			IsItemDataCachedByID = function(id) return known[tonumber(id)] ~= nil end,
			RequestLoadItemDataByID = function(id) asked[#asked + 1] = tonumber(id) end,
		}
		SetItemRef = function(link, text, button) refs[#refs + 1] = { link = link, text = text, button = button } end
		IsShiftKeyDown = function() return false end
		fn(known, asked, refs)
	end)
	C_Item, SetItemRef, GetItemInfo, IsShiftKeyDown = savedItem, savedRef, savedInfo, savedShift
	ITEM_QUALITY_COLORS = savedColours
	if not ok then error(err, 0) end
end

test("1.5.4 Chat tab items: a line's item link shows highlighted with the name and colour the client's item data gives it, whatever the line said; an item unknown to the client shows as sent, is asked for once, and the tab redraws when its data arrives; the history keeps the line as sent", function()
	WithWindow(function(w)
		WithItemData(function(known, asked, refs)
			-- A line whose link lies about the item (a modified client): the real name and colour
			-- show, the link's own data stays (the item the hover and the click open).
			local lying = "|cffff0000|H" .. LINK .. "|h[Free Gold]|h|r"
			local unknown = "|cffa335ee|Hitem:77777::::::::60:::::|h[Mystery Blade]|h|r"
			ns.rdb.chat = { A = {
				Line(T0, "Aa Bb-Realm", "look " .. ITEM .. " cheap"),
				Line(T0 + 400, "Cc Dd-Realm", "take " .. lying),
				Line(T0 + 800, "Ee Ff-Realm", "found " .. unknown),
				Line(T0 + 1200, "Gg Hh-Realm", "cast " .. SPELL),
				Line(T0 + 1600, "Ii Jj-Realm", "torch " .. TORCH),
			} }
			local f = w.CW.Open()
			assert(f, "open")
			local b = BubbleWith(f, "[Mooncloth]")
			assert(b, "the link in its bubble")
			eq(b.body:GetText(), "look " .. ITEM .. " cheap", "the link as sent: highlighted, its colour")
			eq(b.hyperlinks, true, "the bubble answers its links"); eq(b.mouse, true)
			eq(BubbleWith(f, "take ").body:GetText(), "take " .. ITEM, "the client's name and colour, not the sender's words")
			assert(BubbleWith(f, "[Mystery Blade]"), "an item the client has no data of: as sent, until it comes")
			eq(#asked, 1); eq(asked[1], 77777, "asked the client for it once")
			eq(BubbleWith(f, "cast ").body:GetText(), "cast " .. SPELL, "a spell link as sent")
			local torch = assert(BubbleWith(f, "torch "), "Forever's named-colour link in its bubble")
			eq(torch.body:GetText(), "torch " .. TORCH_HEX, "a renderable hex colour, the original payload and the client-known name")
			assert(not torch.body:GetText():find("|cn", 1, true), "no named colour escape in the FontString")
			eq(torch.hyperlinks, true); eq(torch.mouse, true)
			local rendered = torch.body:GetText():sub(7)
			eq(Codec.LinkAt(rendered, 1), #rendered, "still a complete WoW hyperlink")
			local payload = rendered:match("|H([^|]+)|h")
			torch:Fire("OnHyperlinkClick", payload, rendered, "LeftButton")
			eq(#refs, 1); eq(refs[1].link, TORCH_DATA); eq(refs[1].text, TORCH_HEX)
			local hovered
			GameTooltip.SetHyperlink = function(_, link) hovered = link end
			torch:Fire("OnHyperlinkEnter", payload, rendered)
			eq(hovered, TORCH_DATA); eq(GameTooltip:IsShown(), true)
			torch:Fire("OnHyperlinkLeave")
			eq(GameTooltip:IsShown(), false)
			-- The data arrives: the tab redraws with its name and colour.
			known[77777] = { "Mystery Blade of the Deep", "|cff0070dd|Hitem:77777::::::::60:::::|h[Mystery Blade of the Deep]|h|r" }
			w.event("GET_ITEM_INFO_RECEIVED", 77777, true)
			f:Fire("OnUpdate", 0.3)
			eq(BubbleWith(f, "found ").body:GetText(), "found |cff0070dd|Hitem:77777::::::::60:::::|h[Mystery Blade of the Deep]|h|r")
			f:Fire("OnUpdate", 0.3)
			eq(#asked, 1, "asked once, for good")
			-- The history, what moderation and the companion read, holds the lines as sent.
			eq(ns.rdb.chat.A[2].text, "take " .. lying); eq(ns.rdb.chat.A[3].text, "found " .. unknown)
			eq(ns.rdb.chat.A[5].text, "torch " .. TORCH, "the named-colour history stays intact")
		end)
	end)
end)

-- Exercise the presentation boundary through real bubbles, including incomplete client data.
for _, case in ipairs({
	{ label = "quality zero", quality = 0, colours = { [0] = { r = 0.5, g = 0.5, b = 0.5 } }, hex = "|cff808080" },
	{ label = "client quality, not the colour name", quality = 42, colours = { [42] = { r = 1, g = 0, b = 1 } }, hex = "|cffff00ff" },
	{ label = "finite RGB clamped and rounded", quality = 3, colours = { [3] = { r = -1, g = 0.5, b = 2 } }, hex = "|cff0080ff" },
	{ label = "missing quality", colours = { [3] = { r = 0, g = 0.44, b = 0.87 } } },
	{ label = "string quality", quality = "3", colours = { ["3"] = { r = 1, g = 0, b = 0 } } },
	{ label = "fractional quality", quality = 3.5, colours = { [3.5] = { r = 1, g = 0, b = 0 } } },
	{ label = "negative quality", quality = -1, colours = { [-1] = { r = 1, g = 0, b = 0 } } },
	{ label = "infinite quality", quality = math.huge, colours = { [math.huge] = { r = 1, g = 0, b = 0 } } },
	{ label = "NaN quality", quality = 0 / 0, colours = {} },
	{ label = "missing colour table", quality = 3 },
	{ label = "invalid colour table", quality = 3, colours = false },
	{ label = "missing quality entry", quality = 3, colours = {} },
	{ label = "invalid quality entry", quality = 3, colours = { [3] = "|cnIQ3:" } },
	{ label = "incomplete RGB", quality = 3, colours = { [3] = { r = 0, g = 0.44, hex = "|cnIQ3:" } } },
	{ label = "non-numeric RGB", quality = 3, colours = { [3] = { r = "0", g = 0.44, b = 0.87 } } },
	{ label = "NaN RGB", quality = 3, colours = { [3] = { r = 0, g = 0 / 0, b = 0.87 } } },
	{ label = "infinite RGB", quality = 3, colours = { [3] = { r = 0, g = 0.44, b = math.huge } } },
	{ label = "negative infinite RGB", quality = 3, colours = { [3] = { r = -math.huge, g = 0.44, b = 0.87 } } },
	{ label = "sender hex fallback", quality = 3, sent = "|cff123456|H" .. TORCH_DATA .. "|h[Sender Name]|h|r", hex = "|cff123456" },
	{ label = "legacy GetItemInfo", quality = 3, colours = { [3] = { r = 0, g = 112 / 255, b = 221 / 255 } }, hex = "|cff0070dd", legacy = true },
}) do
	test("1.5.4 Chat tab item colours: " .. case.label, function()
		WithWindow(function(w)
			WithItemData(function(known, asked)
				known[1172][3] = case.quality
				ITEM_QUALITY_COLORS = case.colours
				if case.legacy then GetItemInfo, C_Item = C_Item.GetItemInfo, nil end
				local sent = case.sent or TORCH
				ns.rdb.chat = { A = { Line(T0, "Aa Bb-Realm", sent) } }
				local f = w.CW.Open()
				local body = assert(BubbleWith(f, "[Grayson's Torch]"), "client name retained").body:GetText()
				local expected = "|H" .. TORCH_DATA .. "|h[Grayson's Torch]|h"
				if case.hex then expected = case.hex .. expected .. "|r" end
				eq(body, expected, case.label)
				eq(Codec.LinkAt(body, 1), #body, "complete renderable item hyperlink")
				eq(ns.rdb.chat.A[1].text, sent, "history unchanged")
				eq(#asked, 0, "the item is already known")
			end)
		end)
	end)
end

test("1.5.4 Chat tab item colours: unknown named item keeps its payload and name without an unsupported colour, requests once, and redraws on arrival", function()
	WithWindow(function(w)
		WithItemData(function(known, asked)
			known[1172] = nil
			ns.rdb.chat = { A = { Line(T0, "Aa Bb-Realm", TORCH) } }
			local f = w.CW.Open()
			local b = assert(BubbleWith(f, "[Graysons Torch]"))
			eq(b.body:GetText(), "|H" .. TORCH_DATA .. "|h[Graysons Torch]|h", "unknown name and payload, no named colour")
			eq(b.hyperlinks, true)
			w.CW.Changed(); w.CW.Render()
			eq(#asked, 1); eq(asked[1], 1172)
			known[1172] = { "Grayson's Torch", TORCH, 3 }
			w.event("GET_ITEM_INFO_RECEIVED", 1172, true)
			f:Fire("OnUpdate", 0.3)
			eq(BubbleWith(f, "[Grayson's Torch]").body:GetText(), TORCH_HEX)
			eq(#asked, 1, "still asked only once")
			eq(ns.rdb.chat.A[1].text, TORCH)
		end)
	end)
end)

test("1.5.4 Chat tab links: a left click on a link opens the game's link window (SetItemRef) with mouse and keyboard and nothing with the gamepad UI; never a player link or a right click; Shift puts it in our box; the hover tooltip in both modes", function()
	WithWindow(function(w)
		WithItemData(function(_, _, refs)
			ns.rdb.chat = { A = { Line(T0, "Aa Bb-Realm", "look " .. ITEM .. " cheap") } }
			local f = w.CW.Open()
			assert(f, "open")
			local b = BubbleWith(f, "[Mooncloth]")
			assert(b, "the link in its bubble")
			-- A left click: the game's link window, as the game's chat (SetItemRef), with the link's data.
			b:Fire("OnHyperlinkClick", LINK, ITEM, "LeftButton")
			eq(#refs, 1, "SetItemRef once"); eq(refs[1].link, LINK); eq(refs[1].text, ITEM); eq(refs[1].button, "LeftButton")
			b:Fire("OnHyperlinkClick", "player:Someone", "[Someone]", "LeftButton")
			eq(#refs, 1, "never a player link: the game's chat box")
			b:Fire("OnHyperlinkClick", LINK, ITEM, "RightButton")
			eq(#refs, 1, "a right click: nothing")
			-- Shift: into Olympus's own box, no game window.
			IsShiftKeyDown = function() return true end
			f.input:SetText("wts ")
			b:Fire("OnHyperlinkClick", LINK, ITEM, "LeftButton")
			eq(f.input:GetText(), "wts " .. ITEM); eq(#refs, 1)
			IsShiftKeyDown = function() return false end
			-- The hover tooltip, in both modes; the click opens nothing of the game's with the gamepad UI.
			for _, pad in ipairs({ false, true }) do
				WithGamepadUI(pad, function()
					local shown
					GameTooltip.SetHyperlink = function(_, link) shown = link end
					b:Fire("OnHyperlinkEnter", LINK, ITEM)
					eq(shown, LINK, "the tooltip, gamepad UI " .. tostring(pad)); eq(GameTooltip:IsShown(), true)
					b:Fire("OnHyperlinkLeave")
					local before = #refs
					b:Fire("OnHyperlinkClick", LINK, ITEM, "LeftButton")
					eq(#refs, pad and before or before + 1, "the game's link window only with mouse and keyboard")
				end)
			end
		end)
	end)
end)

test("recruit call-out link: Olympus Chat tab accepts complete rendered hyperlink text and keeps Shift, right, gates inert", function()
	WithWindow(function(w)
		local C = ns.Channels
		local saved = {
			open = C.OpenLinkChat, shift = IsShiftKeyDown, locked = ns.ChatLocked,
			combat = rawget(_G, "InCombatLockdown"), send = rawget(_G, "SendChatMessage"),
			guild = rawget(_G, "GuildInvite"), info = rawget(_G, "C_GuildInfo"),
			canInvite = rawget(_G, "CanGuildInvite"),
		}
		local opened, sent, invited = {}, 0, 0
		C.OpenLinkChat = function(command, frame)
			opened[#opened + 1] = { command = command, frame = frame }
			return true
		end
		IsShiftKeyDown = function() return false end
		CanGuildInvite = function() return true end
		ns.ChatLocked = function() return false end
		InCombatLockdown = function() return false end
		SendChatMessage = function() sent = sent + 1 end
		GuildInvite = function() invited = invited + 1 end
		C_GuildInfo = { Invite = function() invited = invited + 1 end }
		local ok, err = pcall(function()
			local shown = assert(Codec.RecruitLink("New Recruit"))
			local link = assert(shown:match("|H([^|]+)|h"))
			ns.rdb.chat = { A = { Line(T0, "Caller Member-Realm", ns.L.RECRUIT_CALLOUT_TEXT:format(shown)) } }
			local f = w.CW.Open()
			local b = assert(BubbleWith(f, "[New Recruit]"), "the public call-out bubble")
			b:Fire("OnHyperlinkClick", link, shown, "LeftButton")
			eq(opened[1].command, "/ginvite New Recruit")
			eq(opened[1].frame, nil, "the Chat tab lets the game choose its chat edit box")
			b:Fire("OnHyperlinkClick", link, shown, "RightButton")
			eq(#opened, 1, "right-click is inert")
			IsShiftKeyDown = function() return true end
			f.input:SetText("keep ")
			b:Fire("OnHyperlinkClick", link, shown, "LeftButton")
			eq(#opened, 1, "Shift-click is inert"); eq(f.input:GetText(), "keep ", "and inserts no forged draft")
			IsShiftKeyDown = function() return false end
			b:Fire("OnHyperlinkClick", link, shown:gsub("%[New Recruit%]", "[Other Recruit]"), "LeftButton")
			eq(#opened, 1, "a mismatched visible label is inert")
			ns.ChatLocked = function() return true end
			b:Fire("OnHyperlinkClick", link, shown, "LeftButton")
			eq(#opened, 1, "chat lockdown")
			ns.ChatLocked = function() return false end
			InCombatLockdown = function() return true end
			b:Fire("OnHyperlinkClick", link, shown, "LeftButton")
			eq(#opened, 1, "combat")
			InCombatLockdown = function() return false end
			WithGamepadUI(true, function()
				b:Fire("OnHyperlinkClick", link, shown, "LeftButton")
				eq(#opened, 1, "gamepad UI")
			end)
			eq(sent, 0, "no chat submitted"); eq(invited, 0, "no invite API")
		end)
		C.OpenLinkChat, IsShiftKeyDown, ns.ChatLocked = saved.open, saved.shift, saved.locked
		InCombatLockdown, SendChatMessage = saved.combat, saved.send
		GuildInvite, C_GuildInfo, CanGuildInvite = saved.guild, saved.info, saved.canInvite
		if not ok then error(err, 0) end
	end)
end)

test("recruit call-out link: Olympus Chat tab rejects secret arguments before decode", function()
	WithWindow(function(w)
		local C = ns.Channels
		local saved = {
			open = C.OpenLinkChat, secret = rawget(_G, "issecretvalue"),
			send = rawget(_G, "SendChatMessage"), guild = rawget(_G, "GuildInvite"),
			info = rawget(_G, "C_GuildInfo"),
		}
		local shown = assert(Codec.RecruitLink("New Recruit"))
		local link = assert(shown:match("|H([^|]+)|h"))
		ns.rdb.chat = { A = { Line(T0, "Caller Member-Realm", ns.L.RECRUIT_CALLOUT_TEXT:format(shown)) } }
		local f = w.CW.Open()
		local b = assert(BubbleWith(f, "[New Recruit]"), "the public call-out bubble")
		local original = Codec.RecruitLinkName
		local decoded, opened, sent, invited = 0, 0, 0, 0
		issecretvalue = Secret.Is
		C.OpenLinkChat = function()
			opened = opened + 1
			return true
		end
		SendChatMessage = function() sent = sent + 1 end
		GuildInvite = function() invited = invited + 1 end
		C_GuildInfo = { Invite = function() invited = invited + 1 end }
		Codec.RecruitLinkName = function(value)
			decoded = decoded + 1
			if Secret.Is(value) then error("secret link reached recruit decoder") end
			return original(value)
		end
		local results = {}
		for i, field in ipairs({ "link", "text", "button" }) do
			local args = { link, shown, "LeftButton" }
			args[i] = Secret.New()
			decoded, opened = 0, 0
			local ok, err = pcall(function()
				b:Fire("OnHyperlinkClick", args[1], args[2], args[3])
			end)
			results[i] = {
				field = field, ok = ok, err = err, decoded = decoded, opened = opened,
				sent = sent, invited = invited,
			}
		end
		Codec.RecruitLinkName = original
		C.OpenLinkChat, issecretvalue = saved.open, saved.secret
		SendChatMessage, GuildInvite, C_GuildInfo = saved.send, saved.guild, saved.info
		for _, result in ipairs(results) do
			eq(result.ok, true, "secret " .. result.field .. " raises no callback fault: " .. tostring(result.err))
			eq(result.decoded, 0, "secret " .. result.field .. " is rejected before recruit decode")
			eq(result.opened, 0, "secret " .. result.field .. " opens no chat box")
			eq(result.sent, 0, "secret " .. result.field .. " sends no chat")
			eq(result.invited, 0, "secret " .. result.field .. " invokes no invite API")
		end
	end)
end)

-- 1.6.0 (GitHub issue #110, "Addon prevents working link of all professions"): a profession link
-- sent in the Olympus chat was usable by nobody. Codec let only item, spell, enchant and quest links
-- through, so the profession link, and an item link carrying its crafter's GUID, reached every reader
-- as text. Pull request #109 lets Forever's profession link through exactly as the game writes it
-- (trade:<Player GUID>:<spell id>:<skill line id>), and an item link with one crafter GUID. Here one
-- player types both, the line leaves on the wire, and another player gets it in the game's chat and
-- in the Chat tab, where both links hover and open. A malformed profession link stays text on both
-- sides, as every malformed link always has. Fails before the merge: both links arrive as text, with
-- no tooltip and no link window. Invented GUIDs.
local GUID = "Player-4701-0A1B2C3D"
local TRADE_DATA = "trade:" .. GUID .. ":3100:164"
local TRADE = "|cffffd000|H" .. TRADE_DATA .. "|h[Blacksmithing]|h|r"
local CRAFTED_DATA = "item:5765::::::::22:1490::::::::" .. GUID .. ":"
local CRAFTED = "|cnIQ1:|H" .. CRAFTED_DATA .. "|h[Black Silk Pack]|h|r"
local CRAFTED_HEX = "|cffffffff|H" .. CRAFTED_DATA .. "|h[Black Silk Pack]|h|r"
local BAD_DATA = "trade:Player-4701-0a1b2c3d:3100:164" -- (a lowercase player id: no GUID the game writes)
local BAD = "|cffffd000|H" .. BAD_DATA .. "|h[Tailoring]|h|r"

test("1.6.0 issue #110: a profession link and a crafted item's link one player types reach another player live, in the game's chat and in the Chat tab, where both hover and open; a malformed profession link is text on both sides", function()
	WithWindow(function(w)
		WithItemData(function(known, _, refs)
			known[5765] = { "Black Silk Pack", CRAFTED, 1 }
			ITEM_QUALITY_COLORS[1] = { r = 1, g = 1, b = 1 }
			local C = ns.Channels
			local saved = { me = ns.me, split = ns.splitNames, realm = ns.realm, ready = ns.Comm.ChannelReady, room = ns.Comm.ChatRoom,
				send = ns.Comm.SendChat, guild = GetGuildInfo, frame = DEFAULT_CHAT_FRAME, windows = ns.db.chatWindows,
				warned = ns.db.chatWarned, looks = C.itemLooks, asked = C.itemsAsked, tip = GameTooltip.SetHyperlink,
				roster = ns.Roster.byName }
			local ok, err = pcall(KeepSendGap, function()
				ns.me, ns.splitNames, ns.realm = "Tester Surname-Realm", true, "Realm"
				GetGuildInfo = function() return GUILD, "Member", 3 end
				ns.Comm.ChannelReady = function() return true end
				ns.Comm.ChatRoom = function() return 3 end
				local sent = {}
				ns.Comm.SendChat = function(msg, done) sent[#sent + 1] = msg; done(true); return true end
				ns.db.addonChat, ns.db.chatMute, ns.db.chatWindows, ns.db.chatWarned = true, {}, nil, { A = true }
				C.itemLooks, C.itemsAsked = {}, {} -- (the game chat's own item data, fresh)
				-- The other player, a guildmate in this client's roster (a line for our guild comes from our roster,
				-- Channels.VerifiedLevel).
				ns.Roster.byName = { [ns.FullName("Gg Hh-Realm")] = 3 }
				local game = { lines = {} }
				function game.AddMessage(self, text) self.lines[#self.lines + 1] = text end
				DEFAULT_CHAT_FRAME = game
				local function Said(i) return assert(game.lines[i], "game chat line " .. i):match(": (.*)$") end
				-- The sender types both links in one line, and the malformed one in the next.
				local t = 3000000
				local line, badLine = "lf " .. TRADE .. " for " .. CRAFTED, "not " .. BAD
				local shown, badShown = "lf " .. TRADE .. " for " .. CRAFTED_HEX, "not " .. (BAD:gsub("|", "||"))
				assert(C.Send("A", line, t)); assert(C.Send("A", badLine, t + 10))
				eq(#sent, 2, "both lines left")
				assert(not sent[1]:find("|", 1, true), "no pipe on the wire: " .. sent[1])
				eq(Codec.Plain(sent[1]), sent[1], "the relay's envelopes keep it whole")
				eq(Codec.DecodeChat(sent[1]).text, line, "both links as typed, for every reader")
				eq(Codec.DecodeChat(sent[2]).text, badShown, "the malformed link as text")
				eq(#game.lines, 2, "the sender's own two lines in his game chat")
				eq(Said(1), shown, "his own line: the links live, the item as his client has it")
				eq(Said(2), badShown, "his own malformed link: text")
				-- The other player: his game chat shows both links whole and live, the malformed one as text.
				local got1, why1 = C.Receive("CHANNEL", "Gg Hh-Realm", sent[1], t + 20)
				eq(got1, true, "shown: " .. tostring(why1))
				local got2, why2 = C.Receive("CHANNEL", "Gg Hh-Realm", sent[2], t + 30)
				eq(got2, true, "shown: " .. tostring(why2))
				local heard = Said(3)
				eq(heard, shown, "the profession link byte for byte, the item with its crafter and this client's name and colour")
				for _, link in ipairs({ TRADE, CRAFTED_HEX }) do
					eq(Codec.LinkAt(heard, heard:find(link, 1, true)), #link, "a live link in the game's chat: " .. link)
				end
				eq(Said(4), badShown, "the malformed link as text in the game's chat")
				-- His Chat tab: the same lines; both links hover and open the game's link window, the
				-- malformed one does neither.
				local f = assert(w.CW.Open("A"), "open")
				local b, bad
				for _, x in ipairs(f.bubbles) do
					local body = x:IsShown() and not x.mine and x.body:GetText() or ""
					if body:find("[Blacksmithing]", 1, true) then b = x elseif body:find("[Tailoring]", 1, true) then bad = x end
				end
				assert(b and bad, "the other player's two lines in the Chat tab")
				eq(b.body:GetText(), shown); eq(bad.body:GetText(), badShown)
				eq(b.hyperlinks, true, "the bubble answers its links")
				local hovered = {}
				GameTooltip.SetHyperlink = function(_, link) hovered[#hovered + 1] = link end
				for _, x in ipairs({ { TRADE_DATA, TRADE }, { CRAFTED_DATA, CRAFTED_HEX } }) do
					b:Fire("OnHyperlinkEnter", x[1], x[2])
					eq(hovered[#hovered], x[1], "the hover tooltip: " .. x[1])
					b:Fire("OnHyperlinkLeave")
					b:Fire("OnHyperlinkClick", x[1], x[2], "LeftButton")
					eq(refs[#refs] and refs[#refs].link, x[1], "the game's link window: " .. x[1])
				end
				eq(#hovered, 2); eq(#refs, 2)
				bad:Fire("OnHyperlinkEnter", BAD_DATA, BAD)
				bad:Fire("OnHyperlinkClick", BAD_DATA, BAD, "LeftButton")
				eq(#hovered, 2, "no tooltip for the malformed link"); eq(#refs, 2, "nor the game's link window")
			end)
			ns.me, ns.splitNames, ns.realm, ns.Comm.ChannelReady, ns.Comm.ChatRoom = saved.me, saved.split, saved.realm, saved.ready, saved.room
			ns.Comm.SendChat, GetGuildInfo, DEFAULT_CHAT_FRAME, ns.db.chatWindows = saved.send, saved.guild, saved.frame, saved.windows
			ns.db.chatWarned, C.itemLooks, C.itemsAsked, GameTooltip.SetHyperlink = saved.warned, saved.looks, saved.asked, saved.tip
			ns.Roster.byName = saved.roster
			if not ok then error(err, 0) end
		end)
	end)
end)
