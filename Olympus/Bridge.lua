local ADDON, ns = ...

-- A read-only door for a companion addon the mods run (OfficerSpy). It answers "is this a High
-- Councillor?" from the signed list, hands out a copy of that list, and passes along each chat
-- line this client has already accepted. Nothing here sends, writes or changes anything in
-- Olympus: a companion only reads, and Olympus never learns what it does with what it read.

OlympusBridge = OlympusBridge or {}
OlympusBridge.API_VERSION = 1

local COUNCIL_MAX = 64  -- a copy never grows past this (the signed list itself stops at 30)
local OBSERVERS_MAX = 8 -- one companion listens, realistically

-- The same answer as the councillor mark in the Olympus chats (ns.IsHighCouncillor): a name on
-- the signed list, on that list's realm group. Anything else, or an error, is false.
function OlympusBridge.IsHighCouncillor(name)
	if type(name) ~= "string" or name == "" or type(ns.IsHighCouncillor) ~= "function" then return false end
	local ok, yes = pcall(ns.IsHighCouncillor, name)
	return ok and yes == true
end

-- A fresh, sorted copy of the signed list's names, and the list's realm group ("A+B", or nil
-- when it names none). The list keeps each name under its lowercase form (Workshop.TakeCouncil),
-- so it is walked with pairs. Empty until a signed list has been checked on this client.
function OlympusBridge.GetCouncil()
	local out = {}
	local c = ns.rdb and ns.rdb.council
	if type(c) ~= "table" or type(c.names) ~= "table" then return out, nil end
	for _, display in pairs(c.names) do
		if type(display) == "string" and #out < COUNCIL_MAX then out[#out + 1] = display end
	end
	table.sort(out)
	return out, c.realm
end

-- Chat lines for a companion: fn(tier, sender, text) for each line from someone else that this
-- client accepted, after its checks (rank, blocked players, repeats, rate) and Codec.SanitizeChat.
-- A muted channel still passes its lines on; a line the flood guard holds back does not. Plain
-- strings only, and an observer that errors is skipped: it can never stop a line or the others.
local observers = {}
function OlympusBridge.RegisterChatObserver(fn)
	if type(fn) ~= "function" or #observers >= OBSERVERS_MAX then return false end
	observers[#observers + 1] = fn
	return true
end

ns.On("CHAT_LINE", function(tier, sender, text)
	if type(tier) ~= "string" or type(sender) ~= "string" or type(text) ~= "string" then return end
	for i = 1, #observers do pcall(observers[i], tier, sender, text) end
end)
