local ADDON, ns = ...

-- 1.5.0 (2026-11-05, the dev's ask after the launch): the Olympus chats as the game's own text.
-- WoW: Forever delivers nothing an addon says on a chat channel (Relay.lua), but a line a player
-- types in a channel it delivers to everyone in it, across every sub-realm (measured on
-- 2026-11-05: a player-made channel, two sub-realms, the line arrived). So where names split
-- (Forever), a chat line leaves as the player's own text in the hidden Olympus channel Comm.lua
-- already joins (its lane, its key as the password when sealed), written exactly as the hidden
-- message would be (Codec.EncodeChat: M1~tier~guild~id~class~text), and every client reads the
-- channel's text and takes such a line as it takes the hidden one (Channels.Receive: the same
-- rooms, mutes, ids, our own echo once). The channel stays off the game's chat windows (Comm's
-- HideChannelFromChat), so nobody sees the raw lines. The send is the player's Enter in the
-- Olympus box (a hardware event): where the realm refuses it all the same, no echo comes back
-- within ECHO_WAIT and the line goes the hidden way, by the relay, as 1.4.x sent it. With the
-- gamepad UI nothing here runs (the chat box gate): the hidden way as before.
local Hall = {}
ns.ChatHall = Hall
local pending = {} -- msg -> when: sent as text, its echo counted
local stats = { sent = 0, echoed = 0, heard = 0, guid = 0 }
function Hall.Stats() return { sent = stats.sent, echoed = stats.echoed, heard = stats.heard, guid = stats.guid, on = Hall.On() } end

-- (1.5.9) The line being taken from the channel's text now (Hall.OnChannel, while Comm.Inject hands
-- it to Channels.Receive), with its sender's GUID: on Forever the channel names its sender bare
-- ("First Surname"), and his GUID's server id is what tells his sub-realm (Channels.lua, the picker's
-- rulesets). Nothing is kept past the line.
local taking, takingGuid = false, nil -- while a line of the channel's text is taken: true, its sender's GUID
function Hall.Taking() return taking, taking and takingGuid or nil end

function Hall.On() -- gp:chat-box
	if not ns.Gate.Allowed("chat-box") then return false end
	if ns.splitNames ~= true or not ns.Comm or type(ns.Comm.ChannelIndex) ~= "function" then return false end
	if (ns.Comm.ChannelIndex() or 0) <= 0 then return false end
	if type(ns.GamepadUI) == "function" and ns.GamepadUI() then return false end
	return type(SendChatMessage) == "function" -- gp:chat-box
end

-- A tier's chat line (M1, the hidden message's text) as the player's own text in the channel,
-- BESIDE the hidden way (Comm.SendChat sends both): clients on another lane of the channel (a
-- client moves lanes when the game refuses one: the dev's cousin sat on OlympusNet2, the dev on
-- OlympusNet1) hear the hidden copy by the relay, clients in the same channel hear the text at
-- once, and each takes the line once (Channels' sender#id#text within DEDUPE_WINDOW). True when
-- handed to the game. The role rooms' and the arena's kinds keep the hidden way alone (their
-- own dedupe is theirs).
function Hall.Send(msg) -- gp:chat-box
	if not ns.Gate.Allowed("chat-box") then return false end
	if not Hall.On() or type(msg) ~= "string" or msg:sub(1, 3) ~= "M1~" or #msg > 255 then return false end
	local index = ns.Comm.ChannelIndex()
	pending[msg] = ns.Now()
	local ok = pcall(SendChatMessage, msg, "CHANNEL", nil, index) -- gp:chat-box
	if not ok then pending[msg] = nil return false end
	stats.sent = stats.sent + 1
	return true
end

-- The channel's text heard (CHAT_MSG_CHANNEL): a chat line written as the hidden message, in
-- our channel, taken as the hidden one is; our own echo settles its send.
-- (1.5.4) Chat lines alone. 1.5.2 also sent a guild's census report as its reporter's own text in
-- the channel while no relay answered (Hall.Carry, from Relay.Out). That send runs from a timer, and
-- Forever's client blocks SendChatMessage outside a key press or click (ADDON_ACTION_BLOCKED,
-- ChatHall.lua:61 from Relay.lua:311 in the dev's error log of 2026-11-06; GitHub #79 and #85): it
-- never delivered a piece, and pcall counted every blocked call as sent. Report pieces typed into
-- the channel are not taken either: anyone in it could write one, without the addon.

-- (1.5.9) guid: CHAT_MSG_CHANNEL's twelfth value, the sender's GUID ("Player-<server id>-<hex>").
function Hall.OnChannel(text, sender, _, _, _, _, _, _, baseName, _, _, guid)
	-- (1.5.5) In a chat lockdown the line, its sender and the channel's name may be secret: none is
	-- read (ChatHall.lua:72 on 1.5.3 and :60 on 1.5.4 in the players' /oly bug).
	if ns.Secret("chat hall", text, sender, baseName) then return false end
	local joined = ns.Comm and ns.Comm.ChannelName and ns.Comm.ChannelName()
	if type(joined) ~= "string" or type(baseName) ~= "string" or baseName:lower() ~= joined:lower() then return false end
	if type(text) ~= "string" or #text > 255 or text:sub(1, 3) ~= "M1~" then return false end
	if pending[text] then
		pending[text] = nil
		stats.echoed = stats.echoed + 1
	end
	stats.heard = stats.heard + 1
	-- (A secret GUID is none: passed on as nothing, never read.)
	if ns.IsSecret(guid) or type(guid) ~= "string" or not guid:find("^Player%-%d+%-%x+$") then guid = false end
	if guid then stats.guid = stats.guid + 1 end
	if type(ns.Comm.Inject) == "function" then
		taking, takingGuid = true, guid or nil
		ns.SafeCall("chat hall line", ns.Comm.Inject, "CHANNEL", sender, text, true)
		taking, takingGuid = false, nil
	end
	return true
end

ns.On("LOGIN", function()
	if ns.splitNames ~= true then return end
	pcall(ns.RegisterEvent, "CHAT_MSG_CHANNEL", function(...) ns.SafeCall("chat hall", Hall.OnChannel, ...) end)
end)

function Hall.Reset() wipe(pending); taking, takingGuid = false, nil; for k in pairs(stats) do stats[k] = 0 end end
