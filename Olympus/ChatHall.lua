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
local carryQueue, carryPending = {}, false
local stats = { sent = 0, echoed = 0, heard = 0 }
Hall.CARRY_GAP = 1.2
function Hall.Stats() return { sent = stats.sent, echoed = stats.echoed, heard = stats.heard, carried = stats.carried or 0, on = Hall.On() } end

function Hall.On() -- gp:chat-box
	if not ns.Gate.Allowed("chat-box") then return false end
	if ns.splitNames ~= true or not ns.Comm or type(ns.Comm.ChannelIndex) ~= "function" then return false end
	if (ns.Comm.ChannelIndex() or 0) <= 0 then return false end
	if type(ns.GamepadUI) == "function" and ns.GamepadUI() then return false end
	return type(SendChatMessage) == "function" -- gp:chat-box
end
local function Sent(ok, result)
	return ok and (result == nil or result == true or result == 0)
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
	local ok, result = pcall(SendChatMessage, msg, "CHANNEL", nil, index) -- gp:chat-box
	if not Sent(ok, result) then pending[msg] = nil return false end
	stats.sent = stats.sent + 1
	return true
end

-- The channel's text heard (CHAT_MSG_CHANNEL): a chat line written as the hidden message, in
-- our channel, taken as the hidden one is; our own echo settles its send.
-- (1.5.2, the dev: "deve ficar circulando esses dados... não deve parar enquanto eu estou fora":
-- the PvP family has no relay but his own characters) A guild's census report, a piece as the
-- hidden way chunks it ("C<id>:<i>:<n>:..."), goes as its reporter's own text in the joined
-- channel while no relay answers (Relay.Out), and is taken from it by everyone in the channel.
local function Report(text) return type(text) == "string" and #text <= 255 and text:find("^C%d+:%d+:%d+:") ~= nil end
local function PumpCarry()
	carryPending = false
	local item = table.remove(carryQueue, 1)
	if not item then return 0 end
	local sent = 0
	if Hall.On() then
		local ok, result = pcall(SendChatMessage, item, "CHANNEL", nil, ns.Comm.ChannelIndex()) -- gp:chat-box
		if Sent(ok, result) then stats.carried = (stats.carried or 0) + 1; sent = 1 end
	end
	if #carryQueue > 0 then
		carryPending = true
		ns.After(Hall.CARRY_GAP, "chat hall carry", PumpCarry)
	end
	return sent
end
function Hall.Carry(parts) -- gp:chat-box
	if not ns.Gate.Allowed("chat-box") then return 0 end
	if not Hall.On() or type(parts) ~= "table" then return 0 end
	for _, p in ipairs(parts) do
		if Report(p) then carryQueue[#carryQueue + 1] = p end
	end
	return not carryPending and PumpCarry() or 0
end

function Hall.OnChannel(text, sender, _, _, _, _, _, _, baseName)
	local joined = ns.Comm and ns.Comm.ChannelName and ns.Comm.ChannelName()
	if type(joined) ~= "string" or type(baseName) ~= "string" or baseName:lower() ~= joined:lower() then return false end
	if type(text) ~= "string" or #text > 255 or (text:sub(1, 3) ~= "M1~" and not Report(text)) then return false end
	if pending[text] then
		pending[text] = nil
		stats.echoed = stats.echoed + 1
	end
	stats.heard = stats.heard + 1
	if type(ns.Comm.Inject) == "function" then ns.SafeCall("chat hall line", ns.Comm.Inject, "CHANNEL", sender, text, true) end
	return true
end

ns.On("LOGIN", function()
	if ns.splitNames ~= true then return end
	pcall(ns.RegisterEvent, "CHAT_MSG_CHANNEL", function(...) ns.SafeCall("chat hall", Hall.OnChannel, ...) end)
end)

function Hall.Reset()
	wipe(pending); wipe(carryQueue); carryPending = false
	for k in pairs(stats) do stats[k] = 0 end
end
