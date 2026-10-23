-- Optional dedicated site aggregate module; publisher adoption is tracked separately.
-- Target: dnl-gentile/olympus-addon d03ea8a9ce8d6d933dde9ce0f0ec7faa866a2df2.
-- Package as OlympusSiteAggregate beside Olympus; Dependencies: Olympus orders the public bridge first.
-- It reads the public checkpoint, never OlympusDB, chat, keys or member records.
local PRODUCER = "1.3.2-site.1"
local NAMES = { ["Olympus"] = true, ["Olympus I"] = true, ["Olympus II"] = true,
  ["Olympus III"] = true, ["Olympus IV"] = true, ["Olympus V"] = true,
  ["Olympus VI"] = true, ["Olympus VII"] = true, ["Olympus VIII"] = true,
  ["Olympus IX"] = true, ["Olympus X"] = true }
-- ASCII names have one canonical published spelling; native guild names may be uppercase.
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
local function Prepare()
  -- Clear a previous export before any refusal, so an old file is never presented as new.
  OlympusSiteAggregate = nil
  local b = rawget(_G, "OlympusBridge")
  if type(b) ~= "table" or b.CENSUS_CHECKPOINT_API_VERSION ~= 1 or type(b.GetCensusCheckpoint) ~= "function" then
    return false, "Olympus 1.3.2 census checkpoint API v1 is required."
  end
  if type(GetGuildInfo) ~= "function" or type(IsInGuild) ~= "function" or not IsInGuild() then
    return false, "Join and open your current guild roster first."
  end
  local own = GuildName(GetGuildInfo("player"))
  if not own then return false, "Only your own Olympus or Olympus I-X roster can be exported. Alt coverage is unavailable." end
  local ok, c = pcall(b.GetCensusCheckpoint)
  local now = type(time) == "function" and time() or nil
  if not ok or type(c) ~= "table" or c.schema ~= "olympus-census-checkpoint" or c.version ~= 1
    or not Whole(now, 1, 4102444800) or not Whole(c.capturedAt, 1, now) or now - c.capturedAt > 60
    or type(c.scope) ~= "table" or not Text(c.scope.realmGroup) or c.scope.faction ~= "Alliance"
    or type(c.guilds) ~= "table" or #c.guilds > 256 then return false, "The current checkpoint or source clock is unavailable." end
  local selected
  for _, g in ipairs(c.guilds) do
    if type(g) == "table" and GuildName(g.name) == own then
      if selected then return false, "Ambiguous own-guild checkpoint refused." end
      selected = g
    end
  end
  local g = selected
  if not g or type(g.provenance) ~= "table" or g.provenance.source ~= "roster"
    or g.provenance.disputed ~= false or g.fresh ~= true or g.counted ~= true
    or not Whole(g.observedAt, 1, c.capturedAt) or now - g.observedAt > 86400
    or not Whole(g.members, 0, 1000) or not Whole(g.online, 0, g.members) then
    return false, "A fresh, undisputed own-roster observation is required; relayed or seen-only rows are refused."
  end
  local total = g.members < 5 and "few" or g.members
  local online = "unavailable"
  if total ~= "few" and now - g.observedAt <= 900 then
    if g.online > 0 and g.online < 5 then
      -- The complementary offline bucket must also remain protected.
      if g.members - g.online >= 5 then online = "few" end
    elseif g.members - g.online > 0 and g.members - g.online < 5 then online = "unavailable"
    else online = g.online end
  end
  -- The entire dedicated variable is an allowlisted aggregate. No reporter/player/linked-alt identity,
  -- guild keys, relays, chat, signatures, secrets or raw source table is copied into it.
  OlympusSiteAggregate = { schema = "olympus-site-aggregate", version = 1, producer = PRODUCER,
    capturedAt = c.capturedAt, realmGroup = c.scope.realmGroup, faction = "Alliance",
    guild = { name = own, observedAt = g.observedAt, characters = total, online = online } }
  return true, "Aggregate prepared locally. /reload writes OlympusSiteAggregate.lua. Select ONLY that dedicated file on /army/report. No identity verification or upload occurred."
end
-- Deliberate slash action only. No event, timer, network, roster request, invite or message send.
SLASH_OLYMPUSSITEAGGREGATE1 = "/olysite"
SlashCmdList.OLYMPUSSITEAGGREGATE = function(msg)
  if msg == "clear" then OlympusSiteAggregate = nil; Say("Dedicated export cleared; /reload writes the cleared state."); return end
  if msg ~= "export" then Say("Use /olysite export or /olysite clear. Only the dedicated export file is safe for the site."); return end
  local _, why = Prepare(); Say(why)
end
OlympusSiteAggregateCompatibility196 = { Prepare = Prepare, producer = PRODUCER }
