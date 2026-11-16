-- The guild name rule as an Olympus 1.5.9 client reads it, for tests/federation-names.lua: copied
-- unchanged from Olympus/Core.lua at the 1.5.9 release (lines 1039, 2023-2194 and 2216-2223 of
-- `git show 88b6b67f:Olympus/Core.lua`; the 1.6.0 candidate, 76c0c57e, had the same lines): NO_PINS,
-- the name rule (ns.NamedOlympus, ns.IsFederation and what they read) and ns.InOlympusGuild and
-- ns.IsMember, which ask it. The rest it reads (ns.IsKingGuild, ns.IsApprovedGuild,
-- ns.IsRemovedGuild, ns.AccordAccepted, ns.faction) is 1.5.9's too and comes from the namespace the
-- tests hand it, a client's own (each a table whose __index is the addon's):
--   assert(loadfile("tests/fixtures/names-1.5.9.lua"))("Olympus", N)
local ADDON, ns = ...

local NO_PINS = {}

-- Fixed on purpose: only guilds with "Olympus" in their name belong to the realm, however
-- they spelled it. Guilds were made with the word misspelled (OLYMPVS the Roman way, Olimpvs,
-- Olmps, Olympuz...). Each word of the name is read the way it sounds (v as u, i as y, z as s,
-- 0 as o, a doubled letter once); then one slip anywhere in a word counts (a letter changed,
-- missing or added, or two swapped), and two at the start of a word that starts with an O
-- (Olmps, Olymp, Olympe, Oymps). Olimpo/Olympo/Olympos count the same way. Words are never
-- joined: "Holy Mpulse" is not Olympus. Olympia, Olympic, Olympian, Olympiad and the like in
-- other languages (Olympique, olympisch) are other words and are left out, and so is polyp.
-- The main guild itself (the King's, the Treasurer's) is still the exact name, see IsCrownRank.
local REALM_WORDS = { "olympus", "olympo" } -- as they sound: Olympus, Olympo, Olimpo, Olympos
local OTHER = { "olympy[aceoq]", "olympysch", "polyp" } -- as they sound: Olympia, Olympic...

-- How many slips from a to b (a letter changed, missing or added, or two neighbours
-- swapped), counted up to limit + 1.
local function Slips(a, b, limit)
	local la, lb = #a, #b
	if la - lb > limit or lb - la > limit then return limit + 1 end
	local prev2, prev, row = nil, {}, nil
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		row = { [0] = i }
		local best = i
		local ca = a:byte(i)
		for j = 1, lb do
			local cost = (ca == b:byte(j)) and 0 or 1
			local v = math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
			if prev2 and i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == b:byte(j) then
				v = math.min(v, prev2[j - 2] + 1)
			end
			row[j] = v
			if v < best then best = v end
		end
		if best > limit then return limit + 1 end
		prev2, prev = prev, row
	end
	return prev[lb]
end
ns.Slips = Slips -- tests

-- A word as it sounds: v as u, i as y, z as s, a doubled letter once.
local function Sounds(word)
	word = word:gsub("v", "u"):gsub("i", "y"):gsub("z", "s")
	local out, last = {}, nil
	for c in word:gmatch(".") do
		if c ~= last then out[#out + 1] = c end
		last = c
	end
	return table.concat(out)
end
ns.Sounds = function(guild) return Sounds(guild:lower():gsub("0", "o"):gsub("[^%a]", "")) end -- tests

local function OlympusWord(word)
	for _, other in ipairs(OTHER) do
		if word:find(other) then return false end
	end
	for _, target in ipairs(REALM_WORDS) do
		if word:find(target, 1, true) then return true end
		-- One slip anywhere in the word (Olympo's no shorter than itself: "olymo" is in polymorph).
		for len = target == "olympo" and #target or #target - 1, #target + 1 do
			for i = 1, #word - len + 1 do
				if Slips(word:sub(i, i + len - 1), target, 1) <= 1 then return true end
			end
		end
		-- Two at its start, if it starts with an O.
		if word:sub(1, 1) == "o" then
			for len = #target - 2, #target + 2 do
				if len >= 5 and len <= #word and Slips(word:sub(1, len), target, 2) <= 2 then return true end
			end
		end
	end
	return false
end

-- A guild against Olympus is none of it: "ANTI OLYMPUS", "Against Olympus", "Down with
-- Olympus", "AntiOlympus", "Olympus Haters". The word before (or the one before "with", "to",
-- "the", "of"), glued in front, or the word after.
local AGAINST = { anti = true, against = true, no = true, ["not"] = true, never = true, down = true,
	death = true, kill = true, hate = true, hates = true, haters = true, destroy = true,
	ruin = true, ruins = true, ruined = true, ruining = true, raze = true, burn = true, crush = true,
	doom = true, wreck = true } -- "Ruin Olympus", "Ruins of Olympus", "Burn Olympus" (1.0.1)
local LINKS = { with = true, to = true, the = true, of = true }
-- (1.5.4, the verifiers' ask: "Olympus is for Cucks" reached their list.) The insults that follow the
-- name, straight or after a linking verb or preposition ("is", "for"), are against it too.
local AGAINST_AFTER = { haters = true, hater = true, sucks = true, sux = true, ruined = true, burns = true, falls = true,
	cuck = true, cucks = true, cucked = true, loser = true, losers = true, trash = true, garbage = true, scam = true,
	scammers = true, cringe = true, dead = true, fail = true, fails = true, failed = true }
-- ...or after one or two linking words: "Olympus in Ruins", "Olympus in the Ruins" (1.1); "Olympus
-- is for Cucks", "Olympus is Trash" (1.5.4).
local LINKS_AFTER = { ["in"] = true, of = true, on = true, to = true, the = true, is = true, are = true, ["for"] = true, was = true, be = true }
local RUIN_AFTER = { ruin = true, ruins = true, ruined = true, ashes = true }

local function Against(words, i)
	if words[i]:find("^anti") then return true end -- glued: AntiOlympus
	local before, before2 = words[i - 1], words[i - 2]
	if before and AGAINST[before] then return true end
	if before and LINKS[before] and before2 and AGAINST[before2] then return true end
	local after = words[i + 1]
	if after ~= nil and AGAINST_AFTER[after] then return true end
	for j = i + 1, i + 2 do
		if not (words[j] and LINKS_AFTER[words[j]]) then break end
		local w = words[j + 1]
		if w and (RUIN_AFTER[w] or AGAINST_AFTER[w]) then return true end
	end
	return false
end

-- (1.5.4) On the Horde, a guild is Olympus's by its name's last word too: the banter words the
-- community calls the Horde's races by (the beta's King guild was <Mudhutters>, its master's
-- character Duskmonkey Boneback), beside the Olympus-word rule and the signed ^guilds^Horde^ list.
-- Each is WoW-lore banter about a Horde race (orc, troll, tauren, Forsaken, blood elf); the author
-- owns this list and edits it before a release. Read on the Horde alone, from the name's last word
-- (letters only, in lower case, a trailing s or es taken off), the whole name when it is one word;
-- a name against Olympus (Against) or a guild the High Council removed is still none.
ns.HORDE_NAME_WORDS = { "mudhutter", "greenskin", "peon", "grunt", "tusker", "cow", "bovine", "moo", "boneback",
	"rotter", "corpse", "zombie", "deader", "pointyear", "twig", "savage", "roach" }
-- [side][name] = true|false, asked often: kept (1.5.4: each side's own answers, the Horde's words
-- counting there alone).
local federation, federationSize = { Alliance = {}, Horde = {} }, { Alliance = 0, Horde = 0 }
local hordeWords -- { list = ns.HORDE_NAME_WORDS as read, set = { [word] = true } }
local function HordeWords()
	local list = type(ns.HORDE_NAME_WORDS) == "table" and ns.HORDE_NAME_WORDS or NO_PINS
	local m = hordeWords
	if not m or m.list ~= list then
		local set = {}
		for _, w in ipairs(list) do if type(w) == "string" then set[w:lower()] = true end end
		m = { list = list, set = set }
		hordeWords = m
		federation.Horde, federationSize.Horde = {}, 0 -- (the Horde's answers were the old list's)
	end
	return m.set
end
local function Federation(guild, horde)
	local words = {}
	for word in guild:lower():gsub("0", "o"):gsub("1", "l"):gmatch("%a+") do words[#words + 1] = word end
	for i, word in ipairs(words) do
		if (word:find("olympus", 1, true) or OlympusWord(Sounds(word))) and not Against(words, i) then return true end
	end
	if horde and #words > 0 and not Against(words, #words) then
		local set, last = HordeWords(), words[#words]
		return set[last] == true or set[last:match("^(.-)s$") or ""] == true or set[last:match("^(.-)es$") or ""] == true
	end
	return false
end
-- The name rule, cached, for our side.
local function Named(guild)
	local side = ns.faction == "Horde" and "Horde" or "Alliance"
	if side == "Horde" then HordeWords() end -- (a changed word list empties the Horde's answers)
	local known = federation[side][guild]
	if known == nil then
		known = Federation(guild, side == "Horde")
		if federationSize[side] >= 2000 then federation[side], federationSize[side] = {}, 0 end
		federation[side][guild], federationSize[side] = known, federationSize[side] + 1
	end
	return known
end

-- The name rule alone (cached): what IsFederation says without the King's guild or the signed list.
function ns.NamedOlympus(guild)
	if type(guild) ~= "string" or guild == "" then return false end
	return Named(guild)
end

function ns.IsFederation(guild)
	if type(guild) ~= "string" or guild == "" then return false end
	-- The King's own guild is Olympus whatever its name (the Horde's is <Mudhutters>, 0.9.4).
	if ns.IsKingGuild(guild) then return true end
	-- A guild the author's signed list approves (1.1), whatever its name.
	if ns.IsApprovedGuild(guild) then return true end
	-- A guild the High Council removed (1.1.5), whatever its name.
	if ns.IsRemovedGuild(guild) then return false end
	return Named(guild)
end

-- In an Olympus guild, Accord or not: where "not a member" meant "an outsider".
function ns.InOlympusGuild()
	return IsInGuild() and ns.IsFederation(GetGuildInfo("player"))
end
-- The addon only works for members of an Olympus guild who accepted the Olympus Accord.
function ns.IsMember()
	return ns.AccordAccepted() and ns.InOlympusGuild()
end
