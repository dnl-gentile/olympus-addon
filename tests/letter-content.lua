local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]letter%-content%.lua$") or "./"
local MARKS = { "dice", "team", "guild", "church", "craft", "crown", "watch", "wanted", "news" }

local function Language(locale)
	local saved = GetLocale
	local cns = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
	GetLocale = function() return locale end
	local ok, why = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", cns)
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
		eq(cns.Letters.Versions()[1], "1.3.3", locale .. ": current release first")
		eq(cns.Letters.Versions()[2], "1.3.2", locale .. ": previous release retained")
		eq(cns.Letters.Versions()[3], "1.3.0", locale .. ": the 1.3 line retained")
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
