-- 1.4.0 (the author, 11-03: "Vamos traduzir o aplicativo para todos eles. Garantir que esteja tudo
-- funcionando em todos eles para o lançamento"): the language files translate every line of the
-- addon, Spanish (esES and esMX), German, French, Italian and Russian, besides English and
-- Portuguese. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")
local ADDON = ROOT .. "Olympus/"

local LANGS = { deDE = "deDE", esES = "esES", esMX = "esES", frFR = "frFR", itIT = "itIT", ruRU = "ruRU" }
-- Lines whispered to another player stay English, the network's own language: the one who reads
-- them may not share the sender's. Every language file leaves them out.
local WHISPERS = { MENTOR_TO_CAPTAIN = true, MENTOR_TO_RECRUIT = true, JOIN_POINT_TEXT = true,
	CHARTER_LETTER_TEXT = true, VERSION_ASK_WHISPER = true, WANTED_THANK_TEXT = true, RECRUIT_WHISPER_MESSAGE = true,
	-- (1.4.0, the guild verification: the guild master's whisper to a verifier, the ask to the High
	-- Council and a verifier's nudge to a guild master.)
	VERIFY_WHISPER_TEXT = true, VERIFY_ASK_TEXT = true, VERIFY_NUDGE_TEXT = true,
	-- Public drafts are also meant for players who may not share the sender's client language.
	RECRUIT_ANNOUNCE_OPENING = true, RECRUIT_ANNOUNCE_OPENING_NAMED = true, RECRUIT_ANNOUNCE_OPENING_PLAY = true,
	RECRUIT_ANNOUNCE_COUNT_GROUPS = true, RECRUIT_ANNOUNCE_COUNT_LOCAL = true, RECRUIT_ANNOUNCE_JOIN = true }
local function Whisper(k) return WHISPERS[k] or k:match("^MATCH_SAY_") ~= nil end

-- Every locale file in the TOC's order, as a game in `code` loads them: the namespace.
local function Load(code)
	local lns = {}
	local saved = GetLocale
	GetLocale = function() return code end
	local ok, err = pcall(function()
		for line in io.lines(ADDON .. "Olympus.toc") do
			local f = line:match("^%s*(Locales%.lua)%s*$") or line:match("^%s*(Locales[\\/].-%.lua)%s*$")
			if f then assert(loadfile(ADDON .. f:gsub("\\", "/")))("Olympus", lns) end
		end
	end)
	GetLocale = saved
	if not ok then error(err, 0) end
	return lns
end

local english = Load("enUS")
test("map names languages: Cyrillic labels are selected only for the Russian client's fonts", function()
	local expected = 0
	for key in pairs(english.L) do if key:match("^MAPNAME_") then expected = expected + 1 end end
	assert(expected >= 17, "the map-name interface loaded")
	for _, code in ipairs({ "enUS", "enGB", "ptBR", "deDE", "esES", "esMX", "frFR", "itIT", "ruRU" }) do
		local L = Load(code).L
		local count = 0
		for key, value in pairs(L) do
			if key:match("^MAPNAME_") then
				count = count + 1
				local cyrillic = value:find("[\208-\211][\128-\191]") ~= nil
				eq(cyrillic, code == "ruRU", code .. " " .. key .. " uses its supported font range")
			end
		end
		eq(count, expected, "the complete map-name interface")
	end
end)

local function EnglishKeys()
	local n = 0
	for k, v in pairs(english.L) do if type(v) == "string" and not Whisper(k) then n = n + 1 end end
	return n
end

test("languages (1.4.0): each language file takes every line it carries, nearly every English line, and leaves none out", function()
	local total = EnglishKeys()
	for code, file in pairs(LANGS) do
		local lns = Load(code)
		local report = lns.LocaleReport()
		assert(not report:find("left out", 1, true), file .. ": " .. report)
		local taken = tonumber(report:match("^" .. code .. ", (%d+) of %d+ lines$"))
		assert(taken, file .. ": " .. report)
		assert(taken >= math.floor(total * 0.99), ("%s: %d of %d English lines"):format(file, taken, total))
		-- Lines a member reads first are in the language.
		for _, k in ipairs({ "TAB_CENSUS", "ARMS", "ARMY_PEOPLE", "CENSUS_STATS_SERVERS", "CENSUS_STATS_KIND_WAIT",
			"CENSUS_STATS_REGION_UNAVAILABLE", "CONSENT_TITLE", "ACCORD_ACCEPT" }) do
			assert(lns.L[k] ~= english.L[k], file .. " translates " .. k)
		end
	end
end)

test("languages (1.4.0): lines whispered to another player stay English in every language", function()
	local n = 0
	for k, v in pairs(english.L) do
		if type(v) == "string" and Whisper(k) then
			n = n + 1
			for code, file in pairs(LANGS) do eq(Load(code).L[k], v, file .. " " .. k) end
		end
	end
	assert(n >= 10, "whispered lines: " .. n)
end)

test("languages (1.4.0): an English or Portuguese game builds no other language's table", function()
	for _, code in ipairs({ "enUS", "enGB", "ptBR" }) do
		local calls = 0
		local lns = {}
		local saved = GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(ADDON .. "Locales.lua"))("Olympus", lns)
			lns.Locale = function() calls = calls + 1 return 0 end
			for _, file in ipairs({ "deDE", "esES", "frFR", "itIT", "ruRU" }) do
				assert(loadfile(ADDON .. "Locales/" .. file .. ".lua"))("Olympus", lns)
			end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		eq(calls, 0, code .. ": every language file stops at its first line")
	end
end)

test("languages (1.4.0): the Agenda reads a day or today/tomorrow in each language", function()
	local W = assert(ns.Week, "Week.lua")
	local saved = W.RealmNow
	W.RealmNow = function() return { year = 2026, month = 11, monthDay = 5, hour = 8, minute = 0, second = 0 } end
	local ok, err = pcall(function()
		for _, input in ipairs({ "lun 20:00 Banda", "mié 21:00 Mazmorra", "mañana 19h Corte", "hoy 22:30 Raid",
			"Do 20:00 Schlachtzug", "morgen 20h Rat", "sam 20:00 Raid", "demain 21:30 Cour", "aujourd'hui 22:00 Raid",
			"gio 20:00 Incursione", "domani 21:00 Corte", "Пт 20:00 Рейд", "завтра 21:00 Совет", "сб 20:00 Рейд",
			"Sat 20:00 Raid night", "amanhã 20h Corte" }) do
			local at, title = W.Parse(input)
			assert(at and title and title ~= "", "parsed: " .. input)
		end
		eq(W.Parse("xyz 20:00 Raid"), nil, "an unknown word is no day")
	end)
	W.RealmNow = saved
	if not ok then error(err, 0) end
end)

test("languages (1.4.0): the lists (places, weekdays, months, class and race names, honours, the King's letters, the nickname words) are each language's own, every key the English one's", function()
	for code, file in pairs(LANGS) do
		local L = Load(code).L
		for name, en in pairs(english.L) do
			if type(en) == "table" then
				local t = L[name]
				assert(type(t) == "table" and t ~= en, file .. " " .. name .. ": its own list")
				for k, v in pairs(en) do
					assert(type(t[k]) == "string" and t[k] ~= "", file .. " " .. name .. "[" .. tostring(k) .. "]")
					eq(ns.LocaleCodes(t[k]), ns.LocaleCodes(v), file .. " " .. name .. "[" .. tostring(k) .. "] codes")
				end
				for k in pairs(t) do assert(en[k] ~= nil, file .. " " .. name .. ": no key the English lacks: " .. tostring(k)) end
			end
		end
		assert(L.WEEK_WEEKDAYS[1] ~= english.L.WEEK_WEEKDAYS[1], file .. ": its own Sunday")
	end
end)

-- Contract 11 adds the signed Queen's exact identity to authorized addons only. Every language's
-- full privacy line names that addition; the basic line for ordinary addons deliberately does not.
local CONTRACT_11 = { "API_CONSENT_TEXT", "API_CONSENT_TEXT_BASIC" }
local QUEEN_WORD = { deDE = "Königin", esES = "Reina", esMX = "Reina", frFR = "Reine", itIT = "Regina", ruRU = "Королевы" }
test("languages: the API's contract 11 privacy lines, including the reserved Queen identity, in every language", function()
	assert(english.L.API_CONSENT_TEXT:find("signed Queen's exact character name and realm", 1, true), "the English full line names the Queen identity")
	assert(not english.L.API_CONSENT_TEXT_BASIC:find("Queen", 1, true), "the ordinary addon's line does not offer the reserved identity")
	assert(english.L.API_CONSENT_TEXT:find("Board's group listings", 1, true), "the English line names the groups")
	assert(english.L.API_CONSENT_TEXT:find("is in an Olympus guild", 1, true), "and the unit check")
	for code, file in pairs(LANGS) do
		local L = Load(code).L
		for _, k in ipairs(CONTRACT_11) do
			assert(type(L[k]) == "string" and L[k] ~= english.L[k], file .. " " .. k .. ": its own words")
			eq(ns.LocaleCodes(L[k]), ns.LocaleCodes(english.L[k]), file .. " " .. k .. " codes")
			assert(#L[k] > #english.L[k] * 0.6, file .. " " .. k .. ": the whole contract, not an earlier shorter line")
		end
		assert(L.API_CONSENT_TEXT:find(QUEEN_WORD[code], 1, true), file .. ": its full line names the Queen identity")
		assert(not L.API_CONSENT_TEXT_BASIC:find(QUEEN_WORD[code], 1, true), file .. ": its basic line does not offer it")
	end
end)

-- 2026-11-09 (the author: "Pode abrir"): members of the Olympus Discord who sign in to the Companion
-- read the census, the public rankings and the Most Wanted list from Olympus's server without a
-- character link. The privacy page's opening words (CONSENT_INTRO, not versioned: nobody is asked
-- again) say so in every language, right before the channel's audience (its one %s). The Olympus
-- Accord's letter is left as accepted: a new version of it would turn Olympus off for every account
-- until it accepted again, the author's call.
local DISCORD_READS = {
	enUS = "On Olympus's server, members of the Olympus Discord signed in to the Companion can see the census, the public rankings (with character names) and the Most Wanted list.",
	ptBR = "No servidor do Olympus, membros do Discord do Olympus conectados ao Companion podem ver o censo, os rankings públicos (com nomes de personagens) e a lista de Mais Procurados.",
	deDE = "Auf dem Server von Olympus können Mitglieder des Olympus-Discords, die im Companion angemeldet sind, den Zensus, die öffentlichen Ranglisten (mit Charakternamen) und die Meistgesucht-Liste sehen.",
	esES = "En el servidor de Olympus, los miembros del Discord de Olympus con sesión iniciada en el Companion pueden ver el censo, las clasificaciones públicas (con nombres de personajes) y la lista de Los más buscados.",
	esMX = "En el servidor de Olympus, los miembros del Discord de Olympus con sesión iniciada en el Companion pueden ver el censo, las clasificaciones públicas (con nombres de personajes) y la lista de Los más buscados.",
	frFR = "Sur le serveur d'Olympus, les membres du Discord d'Olympus connectés au Companion peuvent voir le recensement, les classements publics (avec les noms des personnages) et la liste des plus recherchés.",
	itIT = "Sul server di Olympus, i membri del Discord di Olympus collegati al Companion possono vedere il censimento, le classifiche pubbliche (con i nomi dei personaggi) e la lista dei più ricercati.",
	ruRU = "На сервере Olympus участники Discord Olympus, вошедшие в Companion, могут видеть перепись, публичные рейтинги (с именами персонажей) и список «Самые разыскиваемые».",
}
test("languages: the privacy page says in every language that Olympus Discord members signed in to the Companion can see the census, the public rankings with character names and the Most Wanted list on Olympus's server", function()
	for code, sentence in pairs(DISCORD_READS) do
		local intro = Load(code).L.CONSENT_INTRO
		assert(intro:find(sentence .. " %s", 1, true), code .. ": its own words, right before the channel's audience: " .. intro)
		eq(select(2, intro:gsub("%%s", "")), 1, code .. ": its one %s")
	end
	eq(english.L.ACCORD_DATE, "21 October 2026", "the Olympus Accord's letter as accepted")
	eq(ns.ACCORD_VERSION, 1, "no new version: nobody is asked to accept again")
end)
