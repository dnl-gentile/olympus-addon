-- 1.2.1 (a player's report: "The popups are becoming annoying. How many times do I need to update my
-- settings?"): the privacy page (Consent.lua) opens by itself once for each question, never at every
-- login for a line left unanswered. A line the page showed counts as asked in the saved data, so a
-- new session (the world's Logout and Login: the files load again, OlympusDB kept) does not open it
-- again; the Most Wanted sightings line included. /oly
-- privacy still shows every line. Every name is invented.
local H = ...
local test, eq, World = H.test, H.eq, H.World

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end

-- The real Most Wanted sightings line (Wanted.lua registers it on the page as it loads), loaded
-- into the client after the world's modules, as the TOC has it after Consent.lua.
local function LoadWanted(w, c)
	w:As(c, function() assert(loadfile(H.ADDON_DIR .. "Wanted.lua"))("Olympus", c.ns) end)
end
local function Relog(w, c)
	w:Logout(c)
	w:Login(c)
	LoadWanted(w, c)
end
local function Keys(list)
	local out = {}
	for _, item in ipairs(list) do out[#out + 1] = item.key end
	table.sort(out)
	return table.concat(out, ",")
end

test("1.2.1 privacy page: closed with lines unanswered, it never opens by itself again at the next logins; /oly privacy still shows them, off", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Lida Fenn")
	LoadWanted(w, a)
	local C = a.Consent
	assert(C.Pending()[1], "lines wait for an answer on a fresh install")
	eq(C.Waiting(), true)
	w:Run(C.LOGIN_WAIT + 1)
	local page = C.Frame()
	assert(page and page:IsShown(), "the first login: the page asks")
	page:Hide() -- (the X: nothing answered)
	local waiting = Keys(C.Pending())
	assert(waiting:find("wantedsightings", 1, true), "the sightings line among them: " .. waiting)
	eq(C.Ask("window"), false, "this session: not again")
	for session = 2, 4 do
		Relog(w, a)
		C = a.Consent
		eq(Keys(C.Pending()), waiting, "session " .. session .. ": the same lines still unanswered")
		eq(C.Waiting(), false, "session " .. session .. ": nothing new to ask (the version letter need not wait)")
		w:Run(C.LOGIN_WAIT + 125)
		eq(C.Frame(), nil, "session " .. session .. ": the page does not open by itself")
		eq(C.Ask("window"), false, "nor when the window opens")
		eq(C.Ask("location"), false, "nor for the 1.0 location question")
	end
	-- Unanswered stays off; the player opens the page when he wants.
	eq(C.Answer("inspection"), nil)
	page = C.Show()
	eq(page:IsShown(), true, "/oly privacy: the page, every line on it")
	page:Hide()
	NoErrors(w)
end)

test("1.2.5 privacy page: Authorize all includes the visible pending Most Wanted sightings line, and the page does not ask again", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Parric Stowe")
	LoadWanted(w, a)
	local C = a.Consent
	-- (The zone and layer's lines: their modules are not in the test world; his answers of 1.1.)
	a.db.shareLocation, a.db.layerHelp = false, false
	eq(C.Ask("login"), true, "the page asks")
	eq(C.AuthorizePending(), true, "Authorize all")
	eq(C.Frame():IsShown(), false, "closed")
	eq(a.db.wantedSightings, true, "the visible pending sightings line is authorized")
	eq(Keys(C.Pending()), "", "nothing still waits")
	for session = 2, 3 do
		Relog(w, a)
		C = a.Consent
		eq(Keys(C.Pending()), "")
		eq(C.Waiting(), false, "session " .. session)
		w:Run(C.LOGIN_WAIT + 125)
		eq(C.Frame(), nil, "session " .. session .. ": the page does not open by itself for it")
		eq(a.db.wantedSightings, true, "still authorized")
	end
	NoErrors(w)
end)

test("1.2.1 privacy page: a question the page never showed still opens it once (a member who answered every line before), then never again", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Wenna Crale")
	LoadWanted(w, a)
	local C = a.Consent
	-- Every line answered, as a member before the sightings line came (1.2.0).
	for _, item in ipairs(C.Pending()) do
		if item.key ~= "wantedsightings" then C.Choose(item.key, false) end
	end
	a.db.shareLocation, a.db.layerHelp = false, false
	eq(Keys(C.Pending()), "wantedsightings", "only the new line waits")
	eq(C.Ask("login"), true, "a new question: the page, once")
	C.Frame():Hide()
	Relog(w, a)
	C = a.Consent
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "asked once: not at the next login")
	-- A changed question (its version) is a new one: asked once more.
	local version = 1
	assert(C.Register({ key = "test-versioned", label = "A test line", text = "A versioned question.",
		get = function() return nil end, set = function() end, version = function() return version end }))
	eq(C.Ask("login"), true, "the new line: asked")
	C.Frame():Hide()
	eq(C.Ask("login"), false)
	version = 2
	eq(C.Ask("login"), false, "this session it was on the page")
	Relog(w, a)
	C = a.Consent
	assert(C.Register({ key = "test-versioned", label = "A test line", text = "A versioned question.",
		get = function() return nil end, set = function() end, version = function() return version end }))
	eq(C.Ask("login"), true, "its new version: asked once")
	C.Frame():Hide()
	Relog(w, a)
	C = a.Consent
	assert(C.Register({ key = "test-versioned", label = "A test line", text = "A versioned question.",
		get = function() return nil end, set = function() end, version = function() return version end }))
	eq(C.Ask("login"), false, "then never again")
	-- An answer kept per character (a keeper's book): asked once for each character of the account.
	assert(C.Register({ key = "test-own", label = "A test line", text = "A character's own question.",
		get = function() return nil end, set = function() end, perCharacter = true }))
	eq(C.Ask("login"), true, "this character: asked")
	C.Frame():Hide()
	Relog(w, a)
	C = a.Consent
	local function Own()
		return C.Register({ key = "test-own", label = "A test line", text = "A character's own question.",
			get = function() return nil end, set = function() end, perCharacter = true })
	end
	assert(Own())
	eq(C.Ask("login"), false, "this character, the next login: not again")
	local me = a.ns.me
	a.ns.me = "Wenna Alt-Emberfall" -- (another character on the same saved data)
	eq(C.Ask("login"), true, "another character: his own question, once")
	C.Frame():Hide()
	a.ns.me = me
	NoErrors(w)
end)

-- (Review: the arena bank's yes is kept per character, but the page's record of asking it was the
-- account's: one bank character asked, the account's others never were by themselves.)
test("1.2.1 privacy page: the arena bank's line is asked once on each bank character of the account", function()
	local w = World.New()
	local king = w:Role("king")
	local bank = w:Role("bank")
	LoadWanted(w, bank)
	local other = "Coffrey Strongbox-Emberfall" -- (another bank character on the same saved data)
	w:As(king, function()
		assert(king.ns.ArenaRoles.SetSettings({ live = 1 }))
		assert(king.ns.ArenaRoles.SetBanks({ World.NAMES.bank, other }))
	end)
	w:Run(0)
	-- (A third character of the account answered before: Wallet.lua's book of the bank's yeses.)
	bank.db.arenaBankYes = { ["coffrey hoard-emberfall"] = true }
	local C = bank.Consent
	local function Waits()
		for _, item in ipairs(C.Pending()) do if item.key == "arenabank" then return true end end
		return false
	end
	eq(Waits(), true, "the bank's line waits for this character's answer")
	eq(C.Ask("login"), true, "this bank character: the page asks")
	C.Frame():Hide()
	Relog(w, bank)
	C = bank.Consent
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "the next login: not again")
	bank.ns.me = other
	eq(Waits(), true, "the other bank character's own answer waits")
	eq(C.Ask("login"), true, "the other bank character: asked once")
	eq(C.Choose("arenabank", false), true)
	C.Frame():Hide()
	eq(bank.db.arenaBankYes[World.NAMES.bank:lower()], nil, "the first one's: still unanswered, off")
	eq(C.Ask("login"), false)
	NoErrors(w)
end)

-- (Review: a new tabard contract drops both answers, but with the page's record kept for good the
-- lines were never asked again by themselves: off, unseen.)
test("1.2.1 privacy page: a new tabard contract asks its two lines once more", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Lida Fenn")
	local function LoadTabards(contract)
		w:As(a, function()
			assert(loadfile(H.ADDON_DIR .. "TabardsV2.lua"))("Olympus", a.ns)
			if contract then a.ns.TabardsV2.CONTRACT = contract end
		end)
	end
	LoadTabards()
	local C = a.Consent
	a.db.shareLocation, a.db.layerHelp = false, false
	eq(C.Ask("login"), true, "the first login: the page")
	for _, item in ipairs(C.Pending()) do C.Choose(item.key, true) end
	C.Frame():Hide()
	eq(a.ns.TabardsV2.Consent("self"), true); eq(a.ns.TabardsV2.Consent("nearby"), true)
	eq(Keys(C.Pending()), "", "every line answered")
	-- A later build with a new contract: its lines lose their answer.
	local contract = a.ns.TabardsV2.CONTRACT + 1
	w:Logout(a); w:Login(a); LoadTabards(contract)
	C = a.Consent
	eq(Keys(C.Pending()), "tabardnearbyv2,tabardselfv2", "the new contract's lines wait")
	eq(C.Waiting(), true)
	eq(C.Ask("login"), true, "asked once more")
	C.Frame():Hide()
	w:Logout(a); w:Login(a); LoadTabards(contract)
	C = a.Consent
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "then not again for that contract")
	NoErrors(w)
end)

-- (1.2.3, the King's stream right after the update to 1.2.2: the page opened by itself again,
-- though he had always closed it with its X.) Up to 1.2.1 the page kept the lines it showed for the
-- session alone and its games notice for good; 1.2.2's record of the lines started empty, so every
-- line he had left unanswered was taken for a question never asked.
test("1.2.3 privacy page: an account whose page 1.2.1 showed and was closed unanswered is not asked again by itself after the update; nothing answered, every line off; a later question still asks once", function()
	local w = World.New({ compliance = "shipped" })
	local king = w:Role("king")
	LoadWanted(w, king)
	if king.Consent.Frame() then king.Consent.Frame():Hide() end
	-- 1.2.1's saved data: its games notice shown, the lines never answered, no record of them.
	king.db.consentNotices, king.db.consentAsked = { games = true }, nil
	king.db.royalInspection, king.db.wantedSightings = nil, nil
	Relog(w, king)
	local C = king.Consent
	local waiting = Keys(C.Pending())
	for _, key in ipairs({ "inspection", "wantedsightings" }) do
		assert(waiting:find(key, 1, true), key .. " still waits for his answer: " .. waiting)
	end
	eq(C.Waiting(), false, "nothing new to ask (the version letter need not wait)")
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "the first session with the record: the page does not open by itself")
	eq(C.Ask("window"), false, "nor when the window opens")
	eq(C.Ask("chat"), false, "nor when he types in a chat still unanswered")
	eq(Keys(C.Pending()), waiting, "nothing answered for him")
	eq(C.Answer("inspection"), nil); eq(king.db.wantedSightings, nil)
	for session = 2, 3 do
		Relog(w, king)
		C = king.Consent
		w:Run(C.LOGIN_WAIT + 125)
		eq(C.Frame(), nil, "session " .. session .. ": not by itself either")
	end
	-- /oly privacy: every line on the page, Authorize all with them.
	local page = C.Show()
	eq(page:IsShown(), true); eq(page.all:IsShown(), true)
	page:Hide()
	-- A later build's question the page never showed: asked once, then never again.
	local function Later()
		return C.Register({ key = "test-later", label = "A test line", text = "A later build's question.",
			get = function() return nil end, set = function() end })
	end
	Relog(w, king)
	C = king.Consent
	assert(Later())
	eq(C.Ask("login"), true, "a new question: the page, once")
	C.Frame():Hide()
	Relog(w, king)
	C = king.Consent
	assert(Later())
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "then never again")
	NoErrors(w)
end)

-- (The same report: his X is kept for good.) An account the page was never shown (no games notice:
-- a fresh install, or 1.1.5 and before) is asked once; the X (it hides the page) answers nothing,
-- and no later login or /reload opens it by itself.
test("1.2.3 privacy page: the King's first page closed with its X leaves every line as it is, and no later session opens it by itself", function()
	local w = World.New({ compliance = "shipped" })
	local king = w:Role("king")
	LoadWanted(w, king)
	if king.Consent.Frame() then king.Consent.Frame():Hide() end
	king.db.consentNotices, king.db.consentAsked = nil, nil
	king.db.royalInspection, king.db.wantedSightings = nil, nil
	Relog(w, king)
	local C = king.Consent
	eq(C.Waiting(), true)
	w:Run(C.LOGIN_WAIT + 1)
	local page = C.Frame()
	assert(page and page:IsShown(), "never shown on this account: the page asks once")
	page:Hide() -- (the X)
	eq(C.Answer("inspection"), nil, "the X answers nothing"); eq(king.db.wantedSightings, nil)
	eq(C.Ask("window"), false, "this session: not again")
	for session = 2, 3 do
		Relog(w, king)
		C = king.Consent
		eq(C.Waiting(), false, "session " .. session)
		w:Run(C.LOGIN_WAIT + 125)
		eq(C.Frame(), nil, "session " .. session .. ": the page does not open by itself")
		eq(C.Ask("window"), false)
	end
	NoErrors(w)
end)

-- (Review of the fix above: the whole first session took every line still waiting as asked, so a
-- line that first showed later in it, a character named an arena bank after the login check, was
-- recorded as asked and never shown.) The lines 1.2.1's page showed are the ones showing by its
-- login check: those count as asked, and only those; a line that shows after it is a new question.
test("1.2.3 privacy page: in the first session with the record, a line that first shows after the login check is asked once (a character named an arena bank then)", function()
	local w = World.New()
	local king = w:Role("king")
	local bank = w:Role("bank")
	LoadWanted(w, bank)
	w:As(king, function() assert(king.ns.ArenaRoles.SetSettings({ live = 1 })) end)
	w:Run(0)
	if bank.Consent.Frame() then bank.Consent.Frame():Hide() end
	-- 1.2.1's saved data: its games notice shown, the lines never answered, no record of them.
	bank.db.consentNotices, bank.db.consentAsked = { games = true }, nil
	bank.db.royalInspection, bank.db.wantedSightings = nil, nil
	-- (Wallet.lua's book of the bank's yeses, another character of the account's in it: this one's
	-- answer unknown.)
	bank.db.arenaBankYes = { ["coffrey hoard-emberfall"] = true }
	Relog(w, bank)
	local C = bank.Consent
	local function Waits(key)
		for _, item in ipairs(C.Pending()) do if item.key == key then return true end end
		return false
	end
	-- A line that shows a moment after login, before the login check (1.2.1's page had it by then).
	local early = false
	assert(C.Register({ key = "test-early", label = "A test line", text = "A line showing a moment after login.",
		shown = function() return early end, get = function() return nil end, set = function() end }))
	eq(C.Ask("window"), false, "the window opened at once: nothing new to ask")
	w:Run(5)
	early = true
	eq(Waits("test-early"), true)
	eq(Waits("arenabank"), false, "not a bank yet")
	w:Run(C.LOGIN_WAIT)
	eq(C.Frame(), nil, "the login check: the lines left from 1.2.1 count as asked, no page")
	eq(C.Waiting(), false)
	-- Later in the session the King names him a bank: a question 1.2.1's page never showed him.
	w:As(king, function() assert(king.ns.ArenaRoles.SetBanks({ World.NAMES.bank })) end)
	w:Run(0)
	eq(Waits("arenabank"), true, "his bank line waits for his answer")
	eq(C.Waiting(), true, "a new question to ask")
	eq(C.Ask("window"), true, "the page, once")
	C.Frame():Hide()
	eq(C.Ask("window"), false, "not again this session")
	w:Run(125)
	eq(C.Frame():IsShown(), false)
	eq(bank.db.arenaBankYes[World.NAMES.bank:lower()], nil, "nothing answered for him")
	for session = 2, 3 do
		Relog(w, bank)
		C = bank.Consent
		assert(C.Register({ key = "test-early", label = "A test line", text = "A line showing a moment after login.",
			shown = function() return true end, get = function() return nil end, set = function() end }))
		eq(Waits("arenabank"), true, "session " .. session .. ": still unanswered")
		w:Run(C.LOGIN_WAIT + 125)
		eq(C.Frame(), nil, "session " .. session .. ": the page does not open by itself")
	end
	NoErrors(w)
end)

-- (Review: the record of the lines 1.2.1's page showed began on the character of the account's first
-- 1.2.3 session alone. A Treasurer's mail character, shown the page with its keeper line at every
-- login of 1.2.1 and always closed with its X, had it open by itself once more at its own first
-- login after the update.) Every character the account had then counts its lines as asked once, at
-- its own first session's login check, for the lines of the build that began the record; a
-- character made after the update, and a later build's question, are still asked once.
local function OnAccount(w, c, db)
	w:Logout(c)
	c.saved = { db = World.Copy(db) }
	w:Login(c)
	LoadWanted(w, c)
	return c.Consent
end
local function OldAccount(main, characters)
	if main.Consent.Frame() then main.Consent.Frame():Hide() end
	local db = World.Copy(main.db)
	-- 1.2.1's saved data: its games notice shown, nothing answered, no record of the lines.
	db.consentNotices, db.consentAsked, db.consentAdopt = { games = true }, nil, nil
	db.keeperShares, db.treasurerShares, db.royalInspection, db.wantedSightings = nil, nil, nil, nil
	db.shareLocation, db.layerHelp = false, false
	db.myCharacters = {} -- (Treasury.lua's list of the account's characters, kept since 0.8.4)
	for _, name in ipairs(characters) do db.myCharacters[name:lower()] = true end
	return db
end
local function KeeperLine(C)
	for _, item in ipairs(C.Pending()) do if item.key == "treasurer" then return true end end
	return false
end

test("1.2.3 privacy page: after the update each character the account had is not asked again by itself, its keeper line included (a Treasurer's mail character); a character made later and a later build's question are asked once", function()
	local w = World.New({ compliance = "shipped" })
	local main = w:Role("treasurer")
	local mail = w:Role("treasurerMail")
	local both = OldAccount(main, { World.NAMES.treasurer, World.NAMES.treasurerMail })
	-- The first session after the update, on the Treasurer: nothing asked by itself.
	local C = OnAccount(w, main, both)
	assert(KeeperLine(C), "the Treasurer's keeper line waits")
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "the Treasurer's first session: no page")
	w:Logout(main)
	local account = main.saved.db
	-- The next day, his mail character: its own keeper line, unanswered under 1.2.1.
	C = OnAccount(w, mail, account)
	assert(KeeperLine(C), "the mail character's own keeper line waits")
	eq(C.Waiting(), false, "nothing new to ask")
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "the mail character's first session: the page does not open by itself")
	eq(mail.Treasury.ConsentAnswer(), nil, "nothing answered for him"); eq(mail.Treasury.Consent(), nil, "off")
	w:Logout(mail)
	C = OnAccount(w, mail, mail.saved.db)
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "nor at its next login")
	assert(KeeperLine(C), "still unanswered")
	local page = C.Show()
	eq(page:IsShown(), true, "/oly privacy: the line on the page")
	page:Hide()
	-- A later build's question, at the mail character's first login since the update.
	C = OnAccount(w, mail, account)
	assert(C.Register({ key = "test-later", label = "A test line", text = "A later build's question.",
		get = function() return nil end, set = function() end }))
	eq(C.Waiting(), true, "a later build's question: still new")
	w:Run(C.LOGIN_WAIT + 1)
	local shown = C.Frame()
	assert(shown and shown:IsShown(), "the page asks it once")
	shown:Hide()
	-- A character made after the update (it never logged in before it): its keeper line, once.
	local mainOnly = OldAccount(main, { World.NAMES.treasurer })
	C = OnAccount(w, main, mainOnly)
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "the Treasurer's first session: no page")
	w:Logout(main)
	C = OnAccount(w, mail, main.saved.db)
	eq(C.Waiting(), true, "a new character's keeper line: a new question")
	w:Run(C.LOGIN_WAIT + 1)
	shown = C.Frame()
	assert(shown and shown:IsShown(), "the page asks it once")
	shown:Hide()
	w:Logout(mail)
	C = OnAccount(w, mail, mail.saved.db)
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "then never again")
	NoErrors(w)
end)
