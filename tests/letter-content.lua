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

test("Version letter content: both languages explain the guild, 99 soldiers, Church and free games with supported role markers", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		for _, version in ipairs({ "1.2.0", "1.2.1" }) do
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
		assert(cns.L.LETTER_1_2_1:find("Players", 1, true) and cns.L.LETTER_1_2_1:find("Everyone", 1, true), locale .. ": actual table audiences")
	end
end)

test("Version letter content: English and Portuguese preserve the same role marker order and payment/privacy limitations", function()
	local en, pt = Language("enUS"), Language("ptBR")
	local function Order(text)
		local out = {}
		for mark in text:gmatch("{(%a+)}") do out[#out + 1] = mark end
		return table.concat(out, ",")
	end
	for _, key in ipairs({ "LETTER_1_2_0", "LETTER_1_2_1" }) do
		eq(Order(en.L[key]), Order(pt.L[key]), key .. ": same sections and bullet icons")
	end
	assert(en.L.LETTER_1_2_1:find("no local send record or confirmed receipt held", 1, true))
	assert(pt.L.LETTER_1_2_1:find("Sem registro local de envio nem recibo confirmado guardado", 1, true))
	assert(en.L.LETTER_1_2_1:find("not anonymity on the network", 1, true))
	assert(pt.L.LETTER_1_2_1:find("não anonimato na rede", 1, true))
	assert(en.L.LETTER_1_2_1:find("excluded from test and release packages", 1, true))
	assert(pt.L.LETTER_1_2_1:find("fora dos pacotes de teste e de release", 1, true))
end)

test("Version letter content: the actual letters limit level bands to duels and place the King's note in the recipient's local Chronicle", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local _, before = cns.Letters.Text("1.2.0")
		local _, now = cns.Letters.Text("1.2.1")
		assert(before:find(locale == "enUS" and "duels only" or "somente para duelos", 1, true), locale .. ": the original Bones level-filter claim is corrected")
		assert(now:find(locale == "enUS" and "The recipient keeps the note in their local Chronicle with the King's authorship"
			or "Quem recebe guarda a nota em seu Chronicle local, com a autoria do Rei", 1, true), locale .. ": recipient-local record, not a persistent King's ledger")
	end
end)
