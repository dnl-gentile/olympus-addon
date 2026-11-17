local ADDON, ns = ...

-- A read-only door for a companion addon the mods run (OfficerSpy). It answers "is this a High
-- Councillor?" from the signed list, hands out a copy of that list, and passes along each chat
-- line this client has already accepted (and, for the Olympus Companion's chat record, each line
-- it shows: RegisterChatRecorder). Nothing here sends, writes or changes anything in Olympus: a
-- companion only reads, and Olympus never learns what it does with what it read.

OlympusBridge = OlympusBridge or {}
OlympusBridge.API_VERSION = 1
OlympusBridge.CENSUS_CHECKPOINT_API_VERSION = 1

local COUNCIL_MAX = 64  -- a copy never grows past this (the signed list itself stops at 30)
local OBSERVERS_MAX = 8 -- one companion listens, realistically
local RECORDERS_MAX = 4 -- the Companion's chat record (RegisterChatRecorder): one, realistically
local CHECKPOINT_SCHEMA = "olympus-census-checkpoint"
local CHECKPOINT_VERSION = 1
local CHECKPOINT_MAX_GUILDS = 256
local CHECKPOINT_MAX_SEEN = 256
local CHECKPOINT_MAX_TIME = 9999999999

-- The private desktop bridge gets census aggregates through this separate contract. It never
-- receives OlympusDB (or a reference into it), chat, settings, keys, moderation records, member
-- names, officers, reporters or the High Council. Every call builds fresh plain tables so a
-- consumer can change its copy without changing Olympus. (The chat lines this client shows reach
-- a Companion only through RegisterChatRecorder, below, never through this contract.)
local function Whole(value, maximum)
	local n = tonumber(value)
	if not n or n ~= n then return 0 end
	n = math.floor(n)
	if n < 0 then return 0 end
	if maximum and n > maximum then return maximum end
	return n
end

local function Plain(value, maximum)
	if type(value) ~= "string" then return nil end
	local C = ns.Codec
	local s = C and C.Plain and C.Plain(value) or value:gsub("[|%c]", "")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if maximum and #s > maximum then s = ns.Cut(s, maximum) end
	return s ~= "" and s or nil
end

local function GuildKey(faction, realmGroup, name)
	return ("g1:%s:%s:%s"):format(faction:lower(), realmGroup:lower(), name:lower())
end

local function ReporterCount(vouch)
	local n = 0
	if type(vouch) == "table" then
		for _ in pairs(vouch) do
			n = n + 1
			if n >= 8 then break end
		end
	end
	return n
end

local function CensusScope()
	local realm = Plain(ns.realm or (ns.CurrentRealm and ns.CurrentRealm()), 80)
	local realmGroup = Plain(ns.group, 160) or realm
	local faction = ns.faction == "Alliance" and "Alliance" or ns.faction == "Horde" and "Horde" or nil
	if not realm or not realmGroup or not faction then return nil end
	return { realm = realm, realmGroup = realmGroup, faction = faction }
end

local function GuildEntry(source, scope, now)
	local g = type(source) == "table" and source.g
	local name = type(source) == "table" and Plain(source.name, 96)
	if type(g) ~= "table" or not name then return nil end

	local observedAt = Whole(g.t, CHECKPOINT_MAX_TIME)
	local members = Whole(g.total, ns.Codec and ns.Codec.GUILD_CAP or 1000)
	local counted = source.counted == true
	-- Data.Summary guarantees that a fresh guild is inside the longer counted window. Keep
	-- that invariant explicit at this narrow boundary too, so online can never exceed the
	-- exported character total even if an incomplete source slips through during startup.
	local fresh = source.fresh == true and counted
	local online = fresh and math.min(members, Whole(g.online, members)) or 0
	local dispute
	if ns.Data and type(ns.Data.Dispute) == "function" then
		local ok, result = pcall(ns.Data.Dispute, g, now)
		if ok and type(result) == "table" then dispute = result end
	end
	local provenance = {
		source = g.mine and "roster" or "relay",
		reporters = g.mine and 1 or ReporterCount(g.vouch),
		disputed = dispute and dispute.disputed == true or false,
		singleSource = dispute and dispute.single ~= nil or false,
	}
	provenance.realm = Plain(g.realm or g.from, 80)
	provenance.heardOn = Plain(g.heardOn, 80)

	local out = {
		key = GuildKey(scope.faction, scope.realmGroup, name),
		name = name,
		members = members,
		online = online,
		fresh = fresh,
		counted = counted,
		observedAt = observedAt,
		provenance = provenance,
	}
	local serverTime = Whole(g.st, CHECKPOINT_MAX_TIME)
	if serverTime > 0 then out.observedAtServer = serverTime end
	return out
end

local function SeenEntry(source, scope)
	if type(source) ~= "table" then return nil end
	local name = Plain(source.name, 96)
	if not name then return nil end
	return {
		key = GuildKey(scope.faction, scope.realmGroup, name),
		name = name,
		online = Whole(source.online, ns.Codec and ns.Codec.GUILD_CAP or 1000),
		capped = source.capped == true,
		observedAt = Whole(source.t, CHECKPOINT_MAX_TIME),
	}
end

local function SortAndBound(byKey, maximum)
	local out = {}
	for _, value in pairs(byKey) do out[#out + 1] = value end
	table.sort(out, function(a, b) return a.key < b.key end)
	while #out > maximum do out[#out] = nil end
	return out
end

local function Summary(guilds, seen, linkedAlts)
	local out = {
		members = 0,
		characters = 0,
		linkedAlts = 0,
		online = 0,
		guilds = #guilds,
		freshGuilds = 0,
		seenOnlyGuilds = #seen,
		newestObservedAt = 0,
	}
	for _, g in ipairs(guilds) do
		if g.counted then out.characters = out.characters + g.members end
		if g.fresh then
			out.freshGuilds = out.freshGuilds + 1
			out.online = out.online + g.online
		end
		if g.observedAt > out.newestObservedAt then out.newestObservedAt = g.observedAt end
	end
	out.linkedAlts = math.min(out.characters, Whole(linkedAlts, out.characters))
	out.members = out.characters - out.linkedAlts
	return out
end

-- Versioned, additive, read-only census checkpoint source for the private bridge addon. The
-- bridge addon adds checkpoint identity, previousKey and tombstones in its own SavedVariables;
-- Olympus deliberately knows nothing about that file.
function OlympusBridge.GetCensusCheckpoint()
	local D = ns.Data
	if type(D) ~= "table" or type(D.Summary) ~= "function" then return nil end
	local ok, source = pcall(D.Summary)
	if not ok or type(source) ~= "table" then return nil end

	local scope = CensusScope()
	if not scope then return nil end
	local now = Whole(ns.Now and ns.Now(), CHECKPOINT_MAX_TIME)
	local serverNow
	if type(D.ServerTime) == "function" then
		local serverOK, value = pcall(D.ServerTime)
		if serverOK then
			value = Whole(value, CHECKPOINT_MAX_TIME)
			if value > 0 then serverNow = value end
		end
	end

	local guildByKey = {}
	for _, candidate in ipairs(source.guilds or {}) do
		local entry = GuildEntry(candidate, scope, now)
		if entry then
			local old = guildByKey[entry.key]
			if not old or entry.observedAt > old.observedAt then guildByKey[entry.key] = entry end
		end
	end
	local guilds = SortAndBound(guildByKey, CHECKPOINT_MAX_GUILDS)

	local seenByKey = {}
	for _, candidate in ipairs(source.seen or {}) do
		local entry = SeenEntry(candidate, scope)
		if entry and not guildByKey[entry.key] then
			local old = seenByKey[entry.key]
			if not old or entry.observedAt > old.observedAt then seenByKey[entry.key] = entry end
		end
	end
	local seen = SortAndBound(seenByKey, CHECKPOINT_MAX_SEEN)

	local checkpoint = {
		schema = CHECKPOINT_SCHEMA,
		version = CHECKPOINT_VERSION,
		capturedAt = now,
		timeSource = serverNow and "server" or "local",
		scope = scope,
		guilds = guilds,
		seenOnly = seen,
		summary = Summary(guilds, seen, source.live and source.live.alts or source.alts),
	}
	-- A retained display total is separate from the detailed rows in this checkpoint. A desktop
	-- consumer can keep the dated number visible without inventing missing guilds or fresh data.
	local retained = source.snapshot or source.history
	if type(retained) == "table" then
		checkpoint.retained = { realmGroup = scope.realmGroup, faction = scope.faction,
			characters = Whole(retained.characters), people = Whole(retained.people), guilds = Whole(retained.guilds),
			observedAt = Whole(retained.observed, CHECKPOINT_MAX_TIME), source = Plain(retained.source, 16),
			counted = retained.counted == true, witnesses = Whole(retained.witnesses, 8) }
	end
	if serverNow then checkpoint.capturedAtServer = serverNow end
	return checkpoint
end

-- Sections: one versioned, read-only door per kind of data for the Companion (Daniel: more
-- "ports" than the census). A module's exporter returns only what this character's own client
-- already shows on Olympus's own pages, to the audience that page has: a staff-only section (The
-- Watch's, BridgeAffairs.lua) exists only on the clients whose page shows it (the whole Church ranking,
-- BridgePeople.lua's churchRanking, on the author's, the King's and a signed High Councillor's alone,
-- and the Companion keeps that one on their computer, never sending it), and personal rows
-- carry this character's own (his crafting deals, his letters from the King, and "self",
-- BridgeSections.lua: his character and BattleTag once his Olympus Accord is accepted). This
-- registry copies it into fresh plain tables, within fixed limits, and the private sidecar
-- (OlympusCompanionBridge) saves only the sections it knows at logout. Never another player's
-- BattleTag or private data, chat text or a chat-strike line, treasury items, or anything private
-- to an audience the player is not in: an exporter that would need one does not belong here.
OlympusBridge.SECTIONS_API_VERSION = 1
OlympusBridge.SECTION_LIMITS = { sections = 32, depth = 5, values = 1500, string = 120 }
-- (931) A section that needs more than the defaults (a whole roster, a room's chat lines, a decree's
-- text) asks for it when it registers, never past these ceilings.
OlympusBridge.SECTION_MAX = { values = 200000, string = 512 }

local sections, sectionNames = {}, {}

-- Registers `name` (a lowercase letter, then letters, digits or "_": "chatRooms", as the Companion
-- names that section); a name is taken once, by its first exporter.
-- `limits` (optional): { values = n, string = n } for this section, each at most SECTION_MAX's.
local function Limit(v, default, max)
	if v == nil then return default end
	if type(v) ~= "number" or v < 1 or v ~= math.floor(v) or v > max then return nil end
	return v
end
function OlympusBridge.RegisterSection(name, version, exporter, limits)
	if type(name) ~= "string" or not name:match("^[a-z][%w_]*$") or #name > 32 then return false, "name" end
	if type(version) ~= "number" or version < 1 or version ~= math.floor(version) then return false, "version" end
	if type(exporter) ~= "function" then return false, "exporter" end
	if limits ~= nil and type(limits) ~= "table" then return false, "limits" end
	local L, M = OlympusBridge.SECTION_LIMITS, OlympusBridge.SECTION_MAX
	local values = Limit(limits and limits.values, L.values, M.values)
	local str = Limit(limits and limits.string, L.string, M.string)
	if not values or not str then return false, "limits" end
	if sections[name] then return false, "taken" end
	if #sectionNames >= L.sections then return false, "full" end
	sections[name] = { version = version, exporter = exporter, values = values, string = str }
	sectionNames[#sectionNames + 1] = name
	table.sort(sectionNames)
	return true
end

-- The registered sections, by name: { { name = , version = }, ... } (a fresh list).
function OlympusBridge.Sections()
	local out = {}
	for i, name in ipairs(sectionNames) do out[i] = { name = name, version = sections[name].version } end
	return out
end

-- A plain copy within the limits: strings cut and cleaned, finite numbers, booleans, tables with
-- string or whole-number keys; anything else (functions, frames, cycles) is dropped. Past the value
-- budget the copy stops: a section is never half a secret, only shorter.
local function SectionCopy(value, depth, budget)
	local t = type(value)
	if t == "string" then
		budget.left = budget.left - 1
		return Plain(value, budget.string or OlympusBridge.SECTION_LIMITS.string)
	elseif t == "number" then
		budget.left = budget.left - 1
		if value ~= value or value == math.huge or value == -math.huge then return nil end
		return value
	elseif t == "boolean" then
		budget.left = budget.left - 1
		return value
	elseif t ~= "table" or depth >= OlympusBridge.SECTION_LIMITS.depth then
		return nil
	end
	local keys = {}
	for k in pairs(value) do
		local kt = type(k)
		if (kt == "string" and k:match("^[%a_][%w_]*$") and #k <= 32) or (kt == "number" and k >= 1 and k == math.floor(k)) then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) == "number" end
		return a < b
	end)
	local out = {}
	for _, k in ipairs(keys) do
		if budget.left <= 0 then break end
		local v = SectionCopy(value[k], depth + 1, budget)
		if v ~= nil then out[k] = v end
	end
	return out
end

-- One section now, as a fresh plain table: { name, version, data }; nil when unknown or when its
-- exporter has nothing or fails (logged nowhere: the Companion just shows nothing new).
function OlympusBridge.GetSection(name)
	local entry = type(name) == "string" and sections[name]
	if not entry then return nil end
	local ok, data = pcall(entry.exporter)
	if not ok or type(data) ~= "table" then return nil end
	return { name = name, version = entry.version,
		data = SectionCopy(data, 0, { left = entry.values, string = entry.string }) }
end

OlympusBridge.RegisterSection("census", 1, OlympusBridge.GetCensusCheckpoint)

-- The King's screen while the councillors' names are hidden there (his stream, ns.CouncilMasked,
-- 0.9.9): the chats put no mark on a councillor's line and /oly council cuts each name short, so
-- the bridge names nobody either, until he clicks the eye. An error there counts as hidden.
local function Masked()
	if type(ns.CouncilMasked) ~= "function" then return false end
	local ok, masked = pcall(ns.CouncilMasked)
	return not ok or masked == true
end

-- The same answer as the councillor mark in the Olympus chats (ns.IsHighCouncillor, not on the
-- King's screen while the names are hidden): a name on the signed list, on that list's realm
-- group. Anything else, or an error, is false.
function OlympusBridge.IsHighCouncillor(name)
	if type(name) ~= "string" or name == "" or type(ns.IsHighCouncillor) ~= "function" or Masked() then return false end
	local ok, yes = pcall(ns.IsHighCouncillor, name)
	return ok and yes == true
end

-- A fresh, sorted copy of the signed list's names (Workshop.CouncilNames, the names /oly council
-- prints), and the list's realm group ("A+B", or nil when it names none): the names count on
-- that group only, which OlympusBridge.IsHighCouncillor checks. Empty until a signed list has
-- been checked on this client, and on the King's screen while the names are hidden.
function OlympusBridge.GetCouncil()
	local c, W = ns.rdb and ns.rdb.council, ns.Workshop
	if type(c) ~= "table" or type(c.names) ~= "table" or type(W) ~= "table" or type(W.CouncilNames) ~= "function"
		or Masked() then
		return {}, nil
	end
	local ok, names = pcall(W.CouncilNames)
	if not ok or type(names) ~= "table" then return {}, nil end
	local out = {}
	for i = 1, math.min(#names, COUNCIL_MAX) do
		if type(names[i]) == "string" then out[#out + 1] = names[i] end
	end
	return out, type(c.realm) == "string" and c.realm or nil
end

-- Chat lines for a companion: fn(tier, sender, text) for each line from someone else that this
-- client accepted, after its checks (rank, blocked and ignored players, repeats, rate) and
-- Codec.SanitizeChat: the lines the history keeps and the Chat tab shows, our own left out. A
-- muted channel and a line the flood guard holds back pass on the same way, as those only decide
-- what this player's chat frame shows. Plain strings only, and an observer that errors is
-- skipped: it can never stop a line or the others.
local observers, recorders, companionConsentObservers = {}, {}, {}
function OlympusBridge.RegisterChatObserver(fn)
	if type(fn) ~= "function" or #observers >= OBSERVERS_MAX then return false end
	observers[#observers + 1] = fn
	return true
end

-- The private Companion Bridge uses a separate recorder contract. Unlike a generic observer it
-- fires only after the player explicitly accepted the Companion disclosure. The callback receives
-- only lines from other players because CHAT_LINE is the addon's already-accepted incoming lane;
-- the linking player never witnesses their own code.
function OlympusBridge.CompanionAccepted()
	local fn = ns.CompanionAccordAccepted
	if type(fn) ~= "function" then return false end
	local ok, accepted = pcall(fn)
	return ok and accepted == true
end

function OlympusBridge.RegisterChatRecorder(fn)
	if type(fn) ~= "function" or #recorders >= OBSERVERS_MAX then return false end
	recorders[#recorders + 1] = fn
	return true
end

-- The sidecar clears its in-memory record at the instant consent is withdrawn. This callback is
-- intentionally only a boolean transition; it carries no identity or chat content.
function OlympusBridge.RegisterCompanionConsentObserver(fn)
	if type(fn) ~= "function" or #companionConsentObservers >= OBSERVERS_MAX then return false end
	companionConsentObservers[#companionConsentObservers + 1] = fn
	return true
end

ns.On("COMPANION_ACCORD_CHANGED", function(accepted)
	for i = 1, #companionConsentObservers do pcall(companionConsentObservers[i], accepted == true) end
end)

ns.On("CHAT_LINE", function(tier, sender, text)
	if type(tier) ~= "string" or type(sender) ~= "string" or type(text) ~= "string" then return end
	if not ns.SharedToolsHere() then return end
	for i = 1, #observers do pcall(observers[i], tier, sender, text) end
	if OlympusBridge.CompanionAccepted() then
		for i = 1, #recorders do pcall(recorders[i], tier, sender, text, false) end
	end
end)

-- The Olympus Companion's chat record (the author, 2026-10-20: the Companion may record the chat
-- lines the player already sees and send them to the server, seen by the staff alone, so that
-- several players' Companions agreeing confirm what was said, and to moderate). fn(tier, sender,
-- text, isSelf) for every Olympus chat line this client shows, the player's own included (isSelf):
--   tier   the chat, as a moderator's deletion names it (WatchChat.lua): "A", "C" or "L" for
--          [Olympus], [Captains] and [Lords]; a room's id for the rooms this character is in
--          ("guild", a role room's, a squad's, a crafting deal's); a fight or Bones room's id.
--          (A pinned line is no chat's line: never here, as README's chat record row says.)
--   text   as Olympus keeps it, after its checks and Codec.SanitizeChat: a muted channel's lines,
--          the flood guard's and those the player's block terms grey out too (each still shows
--          in its tab). Never a line a chat warning refused (it never left), nor one Olympus kept
--          off for moderation (net-off, a timeout, a deleted line's late copy).
--   isSelf true for the player's own line, once one of its sends left (a line none of whose sends
--          left is never recorded, whether it goes from the view or, a squad leader's alone, stays);
--          false for everyone else's.
-- Nothing until the Olympus Accord is accepted at its current version. The Accord's letter
-- (ACCORD_T6_3), the privacy page (CONSENT_INTRO) and README's Privacy table say so: this
-- function's existence is what the private Companion bridge looks for, so it ships with them.
-- RECORDERS_MAX at most; a recorder that errors is skipped and stops nothing (nor does anything
-- here: ns.RecordChat throws nothing back). RegisterChatObserver above stays as it was.
-- (The slots are first come: other addons that took them all first leave the Companion's bridge a
-- false. The log says so, once a session, so /oly bug shows why its record stays empty.)
local recorders, recorderRefused = {}, false
function OlympusBridge.RegisterChatRecorder(fn)
	if type(fn) ~= "function" then return false end
	if #recorders >= RECORDERS_MAX then
		if not recorderRefused and ns.Log and ns.db then -- (before the saved log loads: next time)
			recorderRefused = true
			ns.Log("bridge: a chat recorder refused, all %d slots taken", RECORDERS_MAX)
		end
		return false
	end
	recorders[#recorders + 1] = fn
	return true
end

-- Every chat surface calls this where it keeps a line it shows (Channels.lua, ChatRooms.lua,
-- WarSquads.lua, CraftRequests.lua, ArenaChat.lua). Plain strings only; nothing ever thrown back.
function ns.RecordChat(tier, sender, text, isSelf)
	if #recorders == 0 or type(tier) ~= "string" or type(sender) ~= "string" or type(text) ~= "string" then return end
	if not ns.SharedToolsHere() then return end
	-- (Only once the Olympus Accord that says so is accepted, as the bridge's "self" section: the
	-- game's own guild chat reaches the Guild room without Olympus's channel. An error there: no.)
	if type(ns.AccordAccepted) ~= "function" then return end
	local okGate, accepted = pcall(ns.AccordAccepted)
	if not okGate or accepted ~= true then return end
	local C = ns.Codec
	if C and C.SanitizeChat then
		local ok, clean = pcall(C.SanitizeChat, text)
		text = ok and type(clean) == "string" and clean or ""
	end
	if text == "" or tier == "" or sender == "" then return end
	local own = isSelf == true
	for i = 1, #recorders do pcall(recorders[i], tier, sender, text, own) end
end
