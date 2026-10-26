-- Deliberate, one-file own-guild aggregate for the Olympus website reporter.
-- This addon reads only OlympusBridge.GetCensusCheckpoint(). It never reads OlympusDB, chat,
-- keys, member rows, character identity, GUIDs or linked-alt estimates, and it never uploads.
-- Fixed by the accepted .198 reporter contract. Changing this or the root keys below requires a
-- coordinated website parser release; an additive field is deliberately not compatible there.
local PRODUCER = "1.3.2-site.1"
local CHECKPOINT_MAX_AGE = 60
local OBSERVATION_MAX_AGE = 15 * 60

local NAMES = { ["Olympus"] = true, ["Olympus I"] = true, ["Olympus II"] = true,
	["Olympus III"] = true, ["Olympus IV"] = true, ["Olympus V"] = true,
	["Olympus VI"] = true, ["Olympus VII"] = true, ["Olympus VIII"] = true,
	["Olympus IX"] = true, ["Olympus X"] = true }
local CANON = {}
for name in pairs(NAMES) do CANON[name:upper()] = name end

local function GuildName(name)
	return type(name) == "string" and CANON[name:upper()] or nil
end

local function Whole(n, minimum, maximum)
	return type(n) == "number" and n == math.floor(n) and n >= minimum and n <= maximum
end

local function Text(s)
	return type(s) == "string" and #s > 0 and #s <= 96 and not s:find("[%c|]")
end

local function Say(s)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Olympus site export: " .. s) end
end

local function CurrentGuild()
	if type(IsInGuild) ~= "function" or not IsInGuild() or type(GetGuildInfo) ~= "function" then return nil end
	return GuildName(GetGuildInfo("player"))
end

local function ServerNow()
	if type(GetServerTime) ~= "function" then return nil end
	local ok, now = pcall(GetServerTime)
	return ok and Whole(now, 1, 4102444800) and now or nil
end

local function Age(now, thenAt, maximum)
	return Whole(thenAt, 1, 4102444800) and thenAt <= now and now - thenAt <= maximum
end

local function MaskedCounts(members, online)
	if members < 5 then return "few", "unavailable" end
	local offline = members - online
	if offline > 0 and offline < 5 then return members, "unavailable" end
	if online > 0 and online < 5 then return members, "few" end
	return members, online
end

local function Prepare()
	-- Refusals always withdraw the in-memory value. The game writes that withdrawal on the next
	-- logout/reload; the website separately enforces its source-age and short review windows.
	OlympusSiteAggregate = nil
	local own = CurrentGuild()
	if not own then
		return false, "Only your current Olympus or Olympus I-X roster can be exported. Alt coverage is unavailable."
	end
	local now = ServerNow()
	if not now then return false, "The game server clock is unavailable; no export was prepared." end

	local b = rawget(_G, "OlympusBridge")
	if type(b) ~= "table" or b.CENSUS_CHECKPOINT_API_VERSION ~= 1 or type(b.GetCensusCheckpoint) ~= "function" then
		return false, "Olympus 1.3.2 census checkpoint API v1 is required."
	end
	local ok, c = pcall(b.GetCensusCheckpoint)
	if ok and type(c) == "table" and type(c.scope) == "table" and c.scope.faction ~= nil and c.scope.faction ~= "Alliance" then
		return false, "Only the Alliance Olympus and Olympus I-X guilds can be exported; no export was prepared."
	end
	if not ok or type(c) ~= "table" or c.schema ~= "olympus-census-checkpoint" or c.version ~= 1
		or c.timeSource ~= "server" or not Age(now, c.capturedAtServer, CHECKPOINT_MAX_AGE)
		or type(c.scope) ~= "table" or not Text(c.scope.realmGroup) or c.scope.faction ~= "Alliance"
		or type(c.guilds) ~= "table" or #c.guilds > 256 then
		return false, "A current checkpoint on the game server clock is required; no export was prepared."
	end

	local selected
	for _, g in ipairs(c.guilds) do
		if type(g) == "table" and GuildName(g.name) == own then
			if selected then return false, "Ambiguous own-guild checkpoint refused; no export was prepared." end
			selected = g
		end
	end
	local g = selected
	if not g or type(g.provenance) ~= "table" or g.provenance.source ~= "roster"
		or g.provenance.disputed ~= false or g.fresh ~= true or g.counted ~= true
		or not Age(now, g.observedAtServer, OBSERVATION_MAX_AGE)
		or g.observedAtServer > c.capturedAtServer
		or not Whole(g.members, 1, 1000) or not Whole(g.online, 0, g.members) then
		return false, "A fresh, undisputed own-roster observation is required; relayed or seen-only rows are refused."
	end

	local characters, online = MaskedCounts(g.members, g.online)
	local capturedAt = c.capturedAtServer
	OlympusSiteAggregate = {
		schema = "olympus-site-aggregate", version = 1, producer = PRODUCER,
		capturedAt = capturedAt,
		realmGroup = c.scope.realmGroup, faction = "Alliance",
		guild = { name = own, observedAt = g.observedAtServer, characters = characters, online = online },
	}
	return true, "Fresh masked aggregate prepared for " .. own .. ". Type /reload now, then, with the game still open, review ONLY SavedVariables/OlympusSiteAggregate.lua in the attended reporter: your next logout or /reload empties it. Nothing was uploaded."
end

-- Olympus Core owns both /oly site and the /olysite compatibility alias so they follow its
-- gamepad slash gate. Prepare stays local and no event, timer, roster request or upload invokes it.
-- WoW addons share a Lua environment, so this is a deliberate product flow rather than a
-- cryptographic assertion about other installed code.
OlympusSiteAggregateCommand = function(msg)
	msg = type(msg) == "string" and msg:lower():match("^%s*(.-)%s*$") or ""
	if msg == "clear" then
		OlympusSiteAggregate = nil
		Say("Dedicated export cleared; /reload writes the cleared state.")
		return
	end
	if msg ~= "export" then
		Say("Use /oly site export or /oly site clear (/olysite is a compatibility alias). Only the dedicated export file is safe for the site.")
		return
	end
	local _, why = Prepare()
	Say(why)
end

-- The client restores SavedVariables after this file runs, then fires ADDON_LOADED for this
-- addon. Withdraw any previous session's value there; only this session's deliberate
-- /oly site export can arm the next /reload write.
-- If guild membership changes after export but before /reload, withdraw it. A routine roster
-- refresh for the same guild keeps it armed.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name == "OlympusSiteAggregate" then
			OlympusSiteAggregate = nil
			self:UnregisterEvent("ADDON_LOADED")
		end
		return
	end
	local export = OlympusSiteAggregate
	if type(export) == "table" and type(export.guild) == "table" and CurrentGuild() ~= export.guild.name then
		OlympusSiteAggregate = nil
		Say("Dedicated export withdrawn because this character's guild changed.")
	end
end)
