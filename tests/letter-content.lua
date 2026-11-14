local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]letter%-content%.lua$") or "./"
local MARKS = { "dice", "team", "guild", "church", "craft", "crown", "watch", "wanted", "news" }

-- A client in `locale`: Locales.lua, then (file) that language's file as the TOC loads it, then Letters.lua.
local function Language(locale, file)
	local saved = GetLocale
	local cns = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
	GetLocale = function() return locale end
	local ok, why = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", cns)
		if file then assert(loadfile(ROOT .. "Olympus/Locales/" .. file .. ".lua"))("Olympus", cns) end
		assert(loadfile(ROOT .. "Olympus/Letters.lua"))("Olympus", cns)
	end)
	GetLocale = saved
	if not ok then error(why, 0) end
	return cns
end

test("1.2.5 letter content: both languages describe only the shipped reply, office, Wanted and relay follow-ups", function()
	local order
	local expected = {
		enUS = {
			"Right-click a saved line in Olympus Chat and choose Reply",
			"Legates now use the chosen Legate shield",
			"High Council decision",
			"normalized visible sizes and centering",
			"/oly borders test role-legate",
			"Leaving Most Wanted collapses all three back to five",
			"Only rows with independent membership evidence",
			"deterministic across clients",
			"fair per-sender limit",
			"Unverified public-channel strangers cannot create layer-hop demand",
		},
		ptBR = {
			"Clique com o botão direito numa linha salva do Chat do Olympus e escolha Responder",
			"Legates agora usam o badge escolhido de Legate",
			"decisão do High Council",
			"tamanhos visíveis e centralização normalizados",
			"/oly borders test role-legate",
			"Sair de Most Wanted recolhe as três listas para cinco",
			"Somente linhas com prova independente de filiação",
			"determinística entre clientes",
			"limite justo por remetente",
			"Estranhos não verificados no canal público não podem criar demanda de troca de layer",
		},
	}
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local title, body = cns.Letters.Text("1.2.5")
		assert(type(title) == "string" and title ~= "", locale .. ": title")
		assert(type(body) == "string" and #body > 2000 and body:find("1.2.5", 1, true), locale .. ": detailed current letter")
		local raw, marks = cns.L.LETTER_1_2_5, {}
		for mark in raw:gmatch("{(%a+)}") do marks[#marks + 1] = mark end
		local sequence = table.concat(marks, ",")
		if order then eq(sequence, order, "same sections and icon order") else order = sequence end
		assert(not body:find("{[%a]+}"), locale .. ": all icons render or have text fallback")
		local previous
		for _, phrase in ipairs(expected[locale]) do
			local at = assert(raw:find(phrase, 1, true), locale .. ": " .. phrase)
			assert(not previous or at > previous, locale .. ": release points stay ordered")
			previous = at
		end
		local versions = cns.Letters.Versions()
		eq(table.concat(versions, " ", 1, 19),
			"1.5.9 1.5.8 1.5.7 1.5.6 1.5.5 1.5.4 1.5.3 1.5.2 1.5.1 1.5.0 1.4.6 1.4.5 1.4.4 1.4.3 1.4.2 1.4.1 1.4.0 1.3.3 1.3.2",
			locale .. ": latest releases and earlier letters in order")
	end
end)

-- The localized letter describes the work shipped in this part and introduces the next one.
local LETTER_1_5_5 = {
	enUS = {
		"I split this update in two.", "This first part improves chat and census delivery.",
		"The second part, 1.5.6, will build on how relays share census data.",
		"\n\nWhat version 1.5.5 changes:\n\n- {guild} ",
		"\n- {star} The level race is paused. Existing race records are kept.",
		"\n\nClose and reopen the game after the update.\n\n",
	},
	ptBR = {
		"Separei esta atualização em duas partes.", "Esta primeira melhora a entrega do chat e do censo.",
		"A segunda, a 1.5.6, vai melhorar como os relays compartilham os dados do censo.",
		"\n\nO que muda na versão 1.5.5:\n\n- {guild} ",
		"\n- {star} A corrida de level está pausada. Os registros já coletados ficam guardados.",
		"\n\nFeche e abra o jogo de novo depois da atualização.\n\n",
	},
}
local function Marks(text)
	local out = {}
	for mark in text:gmatch("{(%a+)}") do out[#out + 1] = mark end
	return table.concat(out, ",")
end

test("1.5.5 letter content: in every language the split comes first, then eleven bullets with the same marks, then the restart, in that language's 1.5.4 frame, under its own title and the dev's signature in that language, no typeset dash; English and Portuguese word for word", function()
	local english, order
	for _, run in ipairs({ { "enUS" }, { "ptBR" }, { "deDE", "deDE" }, { "esES", "esES" }, { "esMX", "esES" },
		{ "frFR", "frFR" }, { "itIT", "itIT" }, { "ruRU", "ruRU" } }) do
		local locale = run[1]
		local cns = Language(locale, run[2])
		local L = cns.L
		local raw, before = rawget(L, "LETTER_1_5_5"), rawget(L, "LETTER_1_5_4")
		local title, body = cns.Letters.Text("1.5.5")
		assert(type(raw) == "string" and type(title) == "string" and title ~= "" and type(body) == "string", locale .. ": the letter")
		eq(title, rawget(L, "LETTER_1_5_5_HEAD"), locale .. ": its window names it by its title")
		eq(rawget(L, "LETTER_1_5_5_SIGNED"), rawget(L, "LETTER_1_5_4_SIGNED"), locale .. ": the dev's signature, as 1.5.4's")
		eq(rawget(L, "LETTER_1_5_5_LINK"), rawget(L, "LETTER_1_5_4_LINK"), locale .. ": the site's link, as 1.5.4's")
		-- The 1.5.4 letter's frame in this language: its first line and its last.
		local opening, closing = before:match("^[^\n]+\n\n"), before:match("\n\n[^\n]+$")
		eq(raw:sub(1, #opening), opening, locale .. ": the frame's opening")
		eq(raw:sub(-#closing), closing, locale .. ": the frame's close, last")
		local restart = raw:sub(1, -#closing - 1):match("\n\n([^\n]+)$")
		assert(restart and not restart:find("^%- "), locale .. ": the restart, a line of its own right before the close")
		-- The split, before the first bullet: the version and the next one named there.
		local first = raw:find("\n- ", 1, true)
		assert(first and raw:find("1.5.5", 1, true) < first and raw:find("1.5.6", 1, true) < first, locale .. ": the split before the bullets")
		local previous = #opening
		for _, phrase in ipairs(LETTER_1_5_5[locale] or {}) do
			local at = raw:find(phrase, 1, true)
			assert(at, locale .. ": " .. phrase)
			assert(at > previous, locale .. ": in its place: " .. phrase)
			previous = at
		end
		local _, bullets = raw:gsub("\n%- {%a+} ", "")
		eq(bullets, 11, locale .. ": what 1.5.5 changes, a bullet each")
		if order then eq(Marks(raw), order, locale .. ": the same marks in the same order") else order = Marks(raw) end
		assert(not body:find("{%a+}"), locale .. ": every mark drawn or in words")
		for _, dash in ipairs({ "\226\128\148", "\226\128\147", " -- " }) do
			eq(raw:find(dash, 1, true), nil, locale .. ": no typeset dash")
			eq(title:find(dash, 1, true), nil, locale .. ": no typeset dash in the title")
		end
		if english then
			assert(title ~= english.title and raw ~= english.raw, locale .. ": in its own language")
			assert(rawget(L, "LETTER_1_5_5_SIGNED") ~= english.sign, locale .. ": signed in its own language")
		else
			english = { title = title, raw = raw, sign = rawget(L, "LETTER_1_5_5_SIGNED") }
		end
	end
end)

test("1.3.3 letter content: both languages explain the deliberate site export, that nothing is uploaded, and the login clear", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local title, body = cns.Letters.Text("1.3.3")
		assert(type(title) == "string" and title ~= "", locale .. ": title")
		assert(type(body) == "string" and body:find("1.3.3", 1, true), locale .. ": current letter")
		assert(body:find("/oly site export", 1, true) and body:find("/reload", 1, true), locale .. ": the two steps")
		assert(body:find(locale == "ptBR" and "Nada é enviado" or "Nothing is uploaded", 1, true), locale .. ": stays local")
		assert(body:find(locale == "ptBR" and "o próximo logout ou /reload o esvazia" or "your next logout or /reload empties it", 1, true), locale .. ": when the file is emptied")
		assert(body:find(locale == "ptBR" and "guilda da Aliança chamada Olympus ou Olympus I a X" or "Alliance guild named Olympus or Olympus I to X", 1, true), locale .. ": who can export")
		assert(not body:find("{[%a]+}"), locale .. ": all icons render or have text fallback")
	end
end)

test("1.3.2 letter content: both languages explain the approximate people count and the correction scope", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local title, body = cns.Letters.Text("1.3.2")
		assert(type(title) == "string" and title ~= "", locale .. ": title")
		assert(type(body) == "string" and body:find("1.3.2", 1, true), locale .. ": current letter")
		assert(body:find(locale == "ptBR" and "estimativa" or "estimate", 1, true), locale .. ": estimate explained")
	end
end)

test("1.3.0 letter content: both languages explain the durable relay, rankings, moderation and live-test boundary", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local title, body = cns.Letters.Text("1.3.0")
		assert(type(title) == "string" and title ~= "", locale .. ": title")
		assert(type(body) == "string" and #body > 1800 and body:find("1.3.0", 1, true), locale .. ": detailed letter")
		local raw = cns.L.LETTER_1_3_0
		for _, phrase in ipairs(locale == "ptBR" and {
			"estado perene", "Most Wanted e Slayers", "High Council", "equipe pode ver", "Testes offline"
		} or {
			"durable state", "Most Wanted and Slayers", "High Council", "Staff may see", "Offline tests"
		}) do assert(raw:find(phrase, 1, true), locale .. ": " .. phrase) end
	end
end)

test("1.2.4 letter content: both languages describe verified records and retain privacy, free-game and live-test limits", function()
	local order
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local title, body = cns.Letters.Text("1.2.4")
		assert(title and #body > 3500, locale .. ": detailed correction letter")
		assert(body:find("1.2.4", 1, true), locale .. ": consolidated version")
		local raw, marks = cns.L.LETTER_1_2_4, {}
		for mark in raw:gmatch("{(%a+)}") do marks[#marks + 1] = mark end
		local sequence = table.concat(marks, ",")
		if order then eq(sequence, order, "same sections and icon order") else order = sequence end
		assert(not body:find("{[%a]+}"), locale .. ": all icons have a supported text fallback")
		for _, phrase in ipairs(locale == "enUS" and { "unknown keys", "not server-certified proof", "no bets", "Offline tests cannot", "not advertised as finished" }
			or { "chaves desconhecidas", "não são prova certificada pelo servidor", "sem apostas", "Testes offline não", "não são anunciadas como rankings prontos" }) do
			assert(raw:find(phrase, 1, true), locale .. ": " .. phrase)
		end
	end
end)

test("1.2.4 letter content: Wanted pagination, sightings, score migration and gated rules are explained in both languages", function()
	local expected = {
		enUS = {
			"Wanted and Slayers lists start with their top five entries",
			"Each list expands independently by ten at a time",
			"Relayed rows carry no zone",
			"stores no exact coordinates",
			"the sighting is client evidence, not server-certified",
			"one base point for every ten levels of the Horde target, rounded up",
			"full current bounty",
			"100 points for an eligible revenge",
			"Migration replays only provable history",
			"one personal explanation, once",
			"guild Treasury, Church service and fullness, Arena, Bones, and realm level and race rankings",
			"private crafting-fee collection order",
			"not an honour ranking",
			"Existing access gates still decide who may see each page",
			"Lottery and safe limits",
		},
		ptBR = {
			"As listas de Wanted e Slayers começam pelos cinco primeiros",
			"Cada lista expande separadamente de dez em dez",
			"Linhas repassadas não levam zona",
			"não guarda coordenadas exatas",
			"não certificada pelo servidor",
			"um ponto base a cada dez níveis do alvo da Horda, arredondado para cima",
			"recompensa atual inteira",
			"100 pontos por uma vingança elegível",
			"A migração refaz apenas o histórico comprovável",
			"uma explicação pessoal uma única vez",
			"Tesouro das guildas, serviço e lotação da Igreja, Arena, Bones e rankings de nível e raça do reino",
			"ordem privada de cobrança de taxas de crafting",
			"não é ranking de honraria",
			"As permissões existentes continuam decidindo quem pode ver cada página",
			"Loteria e limites seguros",
		},
	}
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local raw = Language(locale).L.LETTER_1_2_4
		assert(raw:find(locale == "enUS" and "A distinct Legate badge still awaits its chosen artwork"
			or "O distintivo próprio dos Legates ainda aguarda a arte escolhida", 1, true),
			locale .. ": deferred Legate badge is stated honestly")
		local previous
		for _, phrase in ipairs(expected[locale]) do
			local position = assert(raw:find(phrase, 1, true), locale .. ": " .. phrase)
			assert(not previous or position > previous, locale .. ": release points stay in their intended order")
			previous = position
		end
		assert(raw:find(locale == "enUS" and "entries with both zero points and zero counted kills remain hidden"
			or "entradas com zero pontos e zero abates contados continuam ocultas", 1, true), locale .. ": zero entries stay hidden")
		assert(raw:find(locale == "enUS" and "unresolved old totals are archived rather than guessed"
			or "totais antigos sem resolução ficam arquivados, não estimados", 1, true), locale .. ": unresolved totals are not invented")
	end
end)

test("1.2.4 Legate wording: current duty and letter replace the old council century rules in both locales", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local c = Language(locale)
		local L = c.L
		assert(L.NOMINEES_MAIN_TITLE:find("Legates", 1, true))
		assert(L.NOMINEES_MAIN_HINT:find("25", 1, true), "manual appointment capacity is visible")
		assert(L.NOMINEES_LEGATE_DUTY:find("39", 1, true) and L.NOMINEES_LEGATE_DUTY:find("40", 1, true))
		local phrases = locale == "enUS" and { "optional", "offline", "events, raids and wars" }
			or { "opcionais", "offline", "eventos, raides e guerras" }
		for _, phrase in ipairs(phrases) do assert(L.NOMINEES_LEGATE_DUTY:find(phrase, 1, true), phrase) end
		local notice = L.NOMINEES_LEGATE_APPOINTED:format("Issuer", "Olympus", L.NOMINEES_LEGATE_DUTY, L.NOMINEES_BADGE_DECISION)
		assert(notice:find("Issuer", 1, true) and notice:find("Olympus", 1, true) and notice:find("39", 1, true))
		assert(notice:find(locale == "enUS" and "High Council" or "High Council", 1, true))
		local correspondent = L.NOMINEES_CORRESPONDENT_APPOINTED:format("Issuer", "Department of War", "Olympus", L.NOMINEES_CORRESPONDENT_DUTY, L.NOMINEES_BADGE_DECISION)
		assert(correspondent:find("Department of War", 1, true) and correspondent:find("Issuer", 1, true))
		eq(L.SQUAD_TOTAL:format(40), locale == "enUS" and "40/40 members" or "40/40 membros")
		assert(not L.NOMINEES_NOTE:find("30", 1, true), "offline duration is no longer appointment revocation")
		assert(not L.BORDERS_WHO_BRONZE:lower():find("legate", 1, true), "Legate office does not award the correspondent's border")
		assert(L.LETTER_1_2_4:find("Legates", 1, true))
		assert(L.LETTER_1_2_4:find(locale == "enUS" and "High Council membership alone does not appoint one" or "pertencer ao High Council não nomeia ninguém sozinho", 1, true))
	end
end)

test("Version letter content: both languages explain the guild, 99 soldiers, Church and free games with supported role markers", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		for _, version in ipairs({ "1.2.0", "1.2.1", "1.2.2" }) do
			local key = "LETTER_" .. version:gsub("%.", "_")
			local raw = assert(rawget(cns.L, key))
			local title, body = cns.Letters.Text(version)
			assert(type(title) == "string" and title ~= "", locale .. ": title")
			assert(type(body) == "string" and #body > 3500, locale .. ": detailed body")
			for _, mark in ipairs(MARKS) do
				assert(raw:find("- {" .. mark .. "}", 1, true), locale .. ": readable " .. mark .. " bullets")
				assert(type(rawget(cns.L, "LETTER_MARK_" .. mark:upper())) == "string", locale .. ": fallback " .. mark)
			end
			assert(not body:find("{[%a]+}"), locale .. ": known marker rendered or expressed in words")
			assert(raw:find(version, 1, true), locale .. ": explicit version")
		end
		local old = cns.L.LETTER_1_2_0
		assert(old:find("99", 1, true) and old:find("High Council", 1, true), locale .. ": actual squad leaders and cap")
		assert(old:find("Vox Populi", 1, true) and old:find("30", 1, true), locale .. ": retained polls")
		assert(old:find(locale == "enUS" and "duels only" or "somente para duelos", 1, true), locale .. ": level band does not apply to Bones")
		assert(old:find(locale == "enUS" and "not a finished new departmental workflow" or "não a um novo fluxo departamental pronto", 1, true), locale .. ": limited departments not advertised as finished")
		assert(cns.L.LETTER_1_2_2:find("Players", 1, true) and cns.L.LETTER_1_2_2:find("Everyone", 1, true), locale .. ": actual table audiences")
	end
end)

test("Version letter content: English and Portuguese preserve the same role marker order and payment/privacy limitations", function()
	local en, pt = Language("enUS"), Language("ptBR")
	local function Order(text)
		local out = {}
		for mark in text:gmatch("{(%a+)}") do out[#out + 1] = mark end
		return table.concat(out, ",")
	end
	for _, key in ipairs({ "LETTER_1_2_0", "LETTER_1_2_1", "LETTER_1_2_2" }) do
		eq(Order(en.L[key]), Order(pt.L[key]), key .. ": same sections and bullet icons")
	end
	assert(en.L.LETTER_1_2_2:find("no local send record or confirmed receipt held", 1, true))
	assert(pt.L.LETTER_1_2_2:find("Sem registro local de envio nem recibo confirmado guardado", 1, true))
	assert(en.L.LETTER_1_2_2:find("not anonymity on the network", 1, true))
	assert(pt.L.LETTER_1_2_2:find("não anonimato na rede", 1, true))
	assert(en.L.LETTER_1_2_2:find("excluded from test and release packages", 1, true))
	assert(pt.L.LETTER_1_2_2:find("fora dos pacotes de teste e de release", 1, true))
	-- 1.2.1 takes Ask to update away from ordinary members: the letter says who keeps it.
	assert(en.L.LETTER_1_2_2:find("Ask to update, in a player's right-click menu, is now only for the King, the High Council and the addon's author", 1, true))
	assert(pt.L.LETTER_1_2_2:find("Pedir para atualizar, no menu do botão direito de um jogador, agora é só para o Rei, o High Council e o autor do addon", 1, true))
end)

test("Version letter content: the actual letters limit level bands to duels and place the King's note in the recipient's local Chronicle", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local _, before = cns.Letters.Text("1.2.0")
		local _, now = cns.Letters.Text("1.2.2")
		assert(before:find(locale == "enUS" and "duels only" or "somente para duelos", 1, true), locale .. ": the original Bones level-filter claim is corrected")
		assert(now:find(locale == "enUS" and "The recipient keeps the note in their local Chronicle with the King's authorship"
			or "Quem recebe guarda a nota em seu Chronicle local, com a autoria do Rei", 1, true), locale .. ": recipient-local record, not a persistent King's ledger")
		assert(now:find(locale == "enUS" and "main window's Realm tab, available to every member"
			or "aba O Reino da janela principal, disponível para todos os membros", 1, true), locale .. ": personal brief belongs to the ordinary member's main window")
		-- (1.2.2: the popup never reached a release, so the letter no longer says it is gone.)
		eq(now:find(locale == "enUS" and "surprise popup" or "popup inesperado", 1, true), nil, locale .. ": no fix claimed for a popup players never had")
	end
end)


test("1.5.6 letter content: both languages explain peer updates, saved coverage and restarting WoW", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local key = "LETTER_1_5_6"
		local raw = assert(cns.L[key])
		local title, body = cns.Letters.Text("1.5.6")
		eq(cns.Letters.Versions()[4], "1.5.6")
		eq(title, cns.L[key .. "_HEAD"])
		assert(title ~= cns.L.LETTER_1_5_5_HEAD, "the update has its own title")
		assert(type(body) == "string" and #body > 0)
		local marks = {}
		for mark in raw:gmatch("\n- {([%a]+)}") do marks[#marks + 1] = mark end
		eq(table.concat(marks, ","), "guild,guild,watch,crown,news,church,crown,team")
		local phrases = locale == "ptBR" and {
			"também precisam atualizar", "cobertura estiver incompleta", "Feche e abra o WoW", "/oly bug",
		} or {
			"need this version too", "coverage is incomplete", "Close and reopen WoW", "/oly bug",
		}
		for _, phrase in ipairs(phrases) do assert(raw:find(phrase, 1, true), locale .. ": " .. phrase) end
	end
end)

test("1.5.7 letter content: each locale explains census progress, relay availability and the planned recruitment ranking", function()
	local english = Language("enUS").L.LETTER_1_5_7
	local previous
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "itIT", "ruRU" }) do
		local file = code == "esMX" and "esES" or code ~= "enUS" and code ~= "ptBR" and code or nil
		local cns = Language(code, file)
		local raw = assert(cns.L.LETTER_1_5_7)
		local title, body = cns.Letters.Text("1.5.7")
		eq(cns.Letters.Versions()[3], "1.5.7", code)
		eq(cns.Letters.Versions()[4], "1.5.6", code)
		eq(title, cns.L.LETTER_1_5_7_HEAD, code)
		assert(title ~= cns.L.LETTER_1_5_6_HEAD, code .. ": distinct release title")
		assert(type(body) == "string" and body:find("/oly bug", 1, true), code .. ": rendered bug report instructions")
		if code == "esMX" then eq(raw, previous, code .. ": Spanish translation")
		elseif code ~= "enUS" then assert(raw ~= english, code .. ": translation loaded") end
		local marks = {}
		for mark in raw:gmatch("\n- {([%a]+)}") do marks[#marks + 1] = mark end
		eq(table.concat(marks, ","), "guild,guild,church", code .. ": release topics")
		previous = raw
	end
	assert(english:find("original date", 1, true) and english:find("since login", 1, true))
	assert(english:find("depends on which relays are reachable", 1, true))
	assert(english:find("A recruitment ranking for all guild members is planned for a future update.", 1, true))
end)

-- 1.5.8: the letter tells the shipped recruiting (JOIN, the copied /ginvite the player sends,
-- Church > Invites, announcements, the unguilded scan, the Join page) and the census, relay and
-- Church fixes, in every shipped language. Each letter names the pages by the labels that
-- language's player sees (the Church's Invites, the Join page), so it loads the Church's and
-- Verify's words as the TOC does, before the language's own file. Discord verification is held
-- out of 1.5.8 for its own review, so the letter does not describe it.
test("1.5.8 letter content: each locale explains recruiting, the Join page and the census fixes with the labels the player sees", function()
	local function Client(locale, file)
		local saved = GetLocale
		local cns = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
		GetLocale = function() return locale end
		local ok, why = pcall(function()
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", cns)
			assert(loadfile(ROOT .. "Olympus/Locales/ChurchText.lua"))("Olympus", cns)
			assert(loadfile(ROOT .. "Olympus/Locales/VerifyText.lua"))("Olympus", cns)
			if file then assert(loadfile(ROOT .. "Olympus/Locales/" .. file .. ".lua"))("Olympus", cns) end
			assert(loadfile(ROOT .. "Olympus/Letters.lua"))("Olympus", cns)
		end)
		GetLocale = saved
		if not ok then error(why, 0) end
		return cns
	end
	local english = Client("enUS").L.LETTER_1_5_8
	local previous
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "itIT", "ruRU" }) do
		local file = code == "esMX" and "esES" or code ~= "enUS" and code ~= "ptBR" and code or nil
		local cns = Client(code, file)
		local L = cns.L
		local raw = assert(L.LETTER_1_5_8)
		local title, body = cns.Letters.Text("1.5.8")
		eq(cns.Letters.Versions()[2], "1.5.8", code)
		eq(cns.Letters.Versions()[3], "1.5.7", code)
		eq(title, L.LETTER_1_5_8_HEAD, code)
		assert(title ~= L.LETTER_1_5_7_HEAD, code .. ": distinct release title")
		assert(type(body) == "string" and not body:find("{[%a]+}"), code .. ": every mark renders or has its words")
		if code == "esMX" then eq(raw, previous, code .. ": Spanish translation")
		elseif code ~= "enUS" then assert(raw ~= english, code .. ": translation loaded") end
		local marks = {}
		for mark in raw:gmatch("\n- {([%a]+)}") do marks[#marks + 1] = mark end
		eq(table.concat(marks, ","), "church,church,guild,guild,news,watch", code .. ": release topics")
		for _, word in ipairs({ "JOIN", "/ginvite", code == "deDE" and "Strg+C" or "Ctrl+C", "/who", "/oly recent", "/oly bug", "45", "24" }) do
			assert(raw:find(word, 1, true), code .. ": " .. word)
		end
		-- The pages as this language's player sees them named.
		for _, key in ipairs({ "CHURCH_NAV_INVITES", "TAB_CHURCH", "RECRUIT_JOIN_TITLE", "RECRUIT_JOIN_REQUEST" }) do
			local label = assert(rawget(L, key), code .. ": " .. key)
			assert(raw:find(label, 1, true), code .. ": the letter names " .. key .. " as shown: " .. label)
		end
		-- 1.5.8 (the author's ask, 11-12): the opening says the King asked, the game's ten invites a
		-- minute and the army's forty thousand, and that more comes next; the bullets name the paste,
		-- Whisper them first and the experimental handoffs as this language shows them.
		assert(raw:find("10", 1, true) and raw:find("40", 1, true), code .. ": the invite math")
		for _, word in ipairs({ code == "deDE" and "Strg+V" or "Ctrl+V", L.RECRUIT_CANDIDATE_WHISPER_FIRST, L.RECRUIT_EXPERIMENTAL }) do
			assert(raw:find(word, 1, true), code .. ": " .. word)
		end
		local scan = L.RECRUIT_CANDIDATES_ON:match("^(.-)%s*:")
		assert(scan and raw:find(scan, 1, true), code .. ": the unguilded scan as shown: " .. tostring(scan))
		-- One reminder takes the public channels in turn (Recruit.lua), in every language.
		local turn = ({ enUS = "taking your public channels in turn", ptBR = "canais públicos em rodízio",
			deDE = "reihum durch deine öffentlichen Kanäle", esES = "por turnos tus canales públicos", esMX = "por turnos tus canales públicos",
			frFR = "tour à tour par tes canaux publics", itIT = "a turno per i tuoi canali pubblici", ruRU = "по очереди в ваших публичных каналах" })[code]
		assert(raw:find(turn, 1, true), code .. ": the reminder takes the public channels in turn")
		previous = raw
	end
	-- What the game decides stays plain: the invite is the player's own command, and verification
	-- requests access or a role rather than promising one.
	assert(english:find("The game does not let addons send guild invites, so that step stays yours.", 1, true))
	assert(english:find("Anyone can whisper you JOIN, even without Olympus.", 1, true))
	assert(english:find("with 4,000 of us online, that is 40,000 invites a minute", 1, true))
	assert(english:find("Passing requests between members is still experimental", 1, true))
	-- (The author's ask, 11-12: the thanks at the end, naming who helped most.)
	assert(english:find("To everyone who sent ideas, bug reports and fixes: thank you.", 1, true))
	-- (Changed on purpose after review: the letter said reminders were timed separately for each
	-- channel, but Recruit.lua runs one reminder timer that takes the joined public channels in
	-- turn; what each channel keeps is its own wait after a post.)
	assert(english:find("A reminder can open one every 2 to 30 minutes, taking your public channels in turn; each channel keeps its own wait after a post.", 1, true))
	assert(not english:find("timed separately", 1, true), "no reminder interval per channel is promised")
	assert(english:find("The Watch can resend a guild approval", 1, true))
end)

-- 1.5.9 (the author, 11-12: "Você pode, por favor, finalizar 1.5.9?"): the rest the 1.5.8 letter
-- promised, in every shipped language: the ranking for everyone (its numbers are checked against the
-- ranking's own in tests/recruit-ranking.lua, where the Church's files load), Church > Invites in its
-- four sections, a declined invite kept for Recruit.DECLINE_DAYS, the switches kept, the Join page's
-- request taken as a JOIN, the census for the guilds that saw too few of us, the chat by ruleset and
-- the King's guild's mark. Each page is named as that language's player sees it: every language file
-- loads as the TOC loads them. Plain text in the game's fonts: no typeset dash (Russian's fonts lack
-- it), no escape or format code.
local DECLINED_1_5_9 = { enUS = "is not offered to you again for %d days", ptBR = "não é oferecido a você de novo por %d dias",
	deDE = "wird dir %d Tage lang nicht mehr angeboten", esES = "no se te vuelve a ofrecer durante %d días",
	esMX = "no se te vuelve a ofrecer durante %d días", frFR = "ne t'est plus proposé pendant %d jours",
	itIT = "non ti viene riproposto per %d giorni", ruRU = "не предлагается вам снова %d дней" }
-- (1.5.9, with the one-channel work merged) On WoW: Forever nothing is sealed: the guilds holding a realm key
-- join the public channel too, and the key only keeps their typed chat lines out of it (Comm.ChannelSpec,
-- ChatHall.On). Each letter names the key as that language's own texts do (KEY_SET_FOREVER), and no
-- sealed guilds.
local KEYED_1_5_9 = { enUS = { "guilds with a realm key too", "sealed" }, ptBR = { "chave de reino", "seladas" },
	deDE = { "Reichsschlüssel", "versiegelt" }, esES = { "clave de reino", "selladas" }, esMX = { "clave de reino", "selladas" },
	frFR = { "clé de royaume", "scellées" }, itIT = { "chiave del reame", "sigillate" }, ruRU = { "ключом мира", "закрытые" } }

test("1.5.9 letter content: each locale tells the ranking for everyone, Church > Invites in its sections, the declined invite, the census for every guild, the chat by ruleset and the King's guild's mark, each page named as shown", function()
	local function Client(locale)
		local saved = GetLocale
		local cns = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
		GetLocale = function() return locale end
		local ok, why = pcall(function()
			for line in io.lines(ROOT .. "Olympus/Olympus.toc") do
				local f = line:match("^%s*(Locales%.lua)%s*$") or line:match("^%s*(Locales[\\/].-%.lua)%s*$")
				if f then assert(loadfile(ROOT .. "Olympus/" .. f:gsub("\\", "/")))("Olympus", cns) end
			end
			assert(loadfile(ROOT .. "Olympus/Letters.lua"))("Olympus", cns)
		end)
		GetLocale = saved
		if not ok then error(why, 0) end
		return cns
	end
	local Recruit = assert(ns.Recruit)
	local en = Client("enUS").L
	local english = en.LETTER_1_5_9
	local previous
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "itIT", "ruRU" }) do
		local cns = Client(code)
		local L = cns.L
		local raw = assert(rawget(L, "LETTER_1_5_9"), code)
		local title, body = cns.Letters.Text("1.5.9")
		eq(cns.Letters.Versions()[1], "1.5.9", code .. ": the newest letter first")
		eq(cns.Letters.Versions()[2], "1.5.8", code)
		eq(title, rawget(L, "LETTER_1_5_9_HEAD"), code .. ": its window names it by its title")
		assert(title ~= rawget(L, "LETTER_1_5_8_HEAD"), code .. ": distinct release title")
		eq(rawget(L, "LETTER_1_5_9_SIGNED"), rawget(L, "LETTER_1_5_8_SIGNED"), code .. ": the dev's signature in this language, as 1.5.8's")
		eq(rawget(L, "LETTER_1_5_9_LINK"), rawget(L, "LETTER_1_5_8_LINK"), code .. ": the site's link, as 1.5.8's")
		assert(type(body) == "string" and not body:find("{[%a]+}"), code .. ": every mark renders or has its words")
		if code == "esMX" then eq(raw, previous, code .. ": Spanish translation")
		elseif code ~= "enUS" then assert(raw ~= english, code .. ": translation loaded") end
		local marks = {}
		for mark in raw:gmatch("\n- {([%a]+)}") do marks[#marks + 1] = mark end
		eq(table.concat(marks, ","), "church,church,church,guild,guild,guild,news,crown", code .. ": release topics")
		for _, text in ipairs({ raw, title }) do
			for _, dash in ipairs({ "\226\128\148", "\226\128\147", " -- " }) do
				eq(text:find(dash, 1, true), nil, code .. ": no typeset dash")
			end
			assert(not text:find("|", 1, true) and not text:find("%", 1, true), code .. ": plain text, no escape or format code")
		end
		-- The pages and buttons as this language's player sees them named. (Changed on purpose, review of the
		-- 1.5.9 release: the letter sent readers to Church > Ranking > Everyone, and a member outside the
		-- Church's audience, most readers, has no Who filter there: his page is that list alone.)
		local ranking = L.TAB_CHURCH .. " > " .. L.CHURCH_NAV_RANKING
		assert(raw:find(ranking .. ".", 1, true), code .. ": the ranking as shown: " .. ranking)
		eq(raw:find(ranking .. " > ", 1, true), nil, code .. ": no list a plain member never sees")
		local invites = L.TAB_CHURCH .. " > " .. L.CHURCH_NAV_INVITES
		local at = raw:find(invites, 1, true)
		assert(at, code .. ": Church > Invites as shown: " .. invites)
		for _, key in ipairs({ "RECRUIT_SECTION_RECRUITING", "RECRUIT_ANNOUNCE_OPEN", "RECRUIT_CENSUS_SCAN", "RECRUIT_SECTION_HANDOFFS" }) do
			local found = raw:find(L[key], at + 1, true)
			assert(found, code .. ": the Invites section as shown, in its order: " .. L[key])
			at = found
		end
		for _, key in ipairs({ "RECRUIT_HANDOFF_PICK", "RECRUIT_JOIN_TITLE" }) do
			assert(raw:find(L[key], 1, true), code .. ": " .. key .. " as shown: " .. L[key])
		end
		for _, word in ipairs({ "JOIN", "/reload", "WoW: Forever", "/oly bug" }) do
			assert(raw:find(word, 1, true), code .. ": " .. word)
		end
		assert(raw:find(DECLINED_1_5_9[code]:format(Recruit.DECLINE_DAYS), 1, true), code .. ": a declined invite's days, as Recruit.lua keeps him")
		local keyed, sealed = KEYED_1_5_9[code][1], KEYED_1_5_9[code][2]
		assert(raw:find(keyed, 1, true), code .. ": the guilds with a realm key join the same channel: " .. keyed)
		eq(raw:find(sealed, 1, true), nil, code .. ": no sealed guilds on Forever")
		previous = raw
	end
	-- What a recruit needs before it counts, in the page's own words (CHURCH_EVERYONE_PENDING_TIP).
	-- (Changed on purpose, review of the 1.5.9 release: both said any other member's addon confirms a
	-- recruit, and the keepers refuse a plain member of another guild, RecruitRanking.TakeEvidence.)
	assert(en.CHURCH_EVERYONE_PENDING_TIP:find("once an officer's addon in your guild, your Church correspondent's or a Church keeper's sees it too", 1, true))
	assert(english:find("A recruit counts once an officer's addon, your guild's Church correspondent's or a Church keeper's sees him join too.", 1, true))
	-- (Review of the 1.5.9 release: the letter said a line written under one's own ruleset goes to it
	-- alone; it goes on the shared channel, another ruleset's 1.5.9 player sees it by choosing that ruleset,
	-- and an older client shows it to everyone.)
	assert(english:find("what you write there shows under your ruleset alone; versions before 1.5.9 still show every line to everyone.", 1, true))
	assert(english:find("As promised, here is the rest.", 1, true), "the rest the 1.5.8 letter promised")
	-- The census for the guilds that saw too few of us: one channel a faction, the guilds with a realm key too.
	-- (Changed on purpose, with the one-channel work merged: on Forever a key seals no channel, it keeps the
	-- guild's typed chat lines out of the public one, Comm.ChannelSpec and ChatHall.On.)
	assert(english:find("on WoW: Forever every Olympus guild of your faction now joins the same channel, guilds with a realm key too (the key now only keeps their typed chat lines out of it), and the relays pass the whole census on again", 1, true))
	assert(english:find("The King's guild wears the verified check mark in the Census.", 1, true))
end)
