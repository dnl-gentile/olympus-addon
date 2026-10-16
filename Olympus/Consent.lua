local ADDON, ns = ...
local L = ns.L

-- The first-open page (1.1, Fern's #11): one page, in plain words, of what leaves this client,
-- and the first question the addon asks: after login (LOGIN_WAIT, then on the minute until it
-- could), or when the Olympus window opens first, never in combat or an instance, while a line
-- waits for an answer it was never asked (once for each question, 1.2.1). The 1.0 questions (the
-- zone and layer's, a keeper's) open this page instead of their popups (Layers.AskChoice,
-- Treasury.AskConsent); their popups stay for a client without this file (updated without a
-- restart) and a keeper outside a guild.
-- It has a Yes and a No for each thing the addon would otherwise share or show on its own: the
-- zone and layer, layer help, a treasury keeper's book (keepers only), the Royal Inspection, the
-- author's roll call, the Olympus chats and an officer's patrol findings (officers only). Each
-- stays off until its Yes: nil, never answered, is off (Layers.Sharing, Hop.Helps,
-- Treasury.Consent, King's OnInspect, Workshop.Answers, Channels.ChatOn, Inspect.Sharing).
-- The page also says what always goes out while the player is in an Olympus
-- guild (the census the elected member sends, names included, and the hello), so it never
-- promises that nothing does. The window works whatever the answers: the census, the Realm and
-- the player's own guild roster need none of them, location included.
-- `/oly privacy` opens it again to change any answer; each answer also has its own command.
-- Olympus's own frame, never the game's popup: with Blizzard's gamepad UI the game's popups break
-- when an addon opens one (Dialog.lua). It has no edit box (nothing takes the keyboard), and it
-- has no X and never goes on the escape list: while a question waits, the player closes it only by
-- authorizing every visible unanswered line or keeping the choices already made. Once nothing
-- waits, that secondary action becomes the plain Done button.
-- The one place such a choice lives: later features that share something on their own (a group
-- board's raised flag, a camp pin...) add their line here with Consent.Register:
--   Consent.Register({ key = "camp", label = "L key or text", text = "L key, text or function",
--     shown = function() return true end, get = function() return true|false|nil end,
--     set = function(on) ... end, note = function() return "a line under it" or nil end,
--     pending = function() return true while it waits for an answer end })
-- (`get` is what goes out now, shown on the line; `pending`, when given, says whether the line
-- still waits for the player's answer: by default, while `get` is nil.)
-- A line with `explicit = true` (1.2.0: Most Wanted sightings, Wanted.lua) is off until a deliberate
-- answer: it is pending until answered, so the page opens by itself for it once (a member who
-- answered every other line before is shown it too). The page's clearly labelled Authorize all is
-- also a deliberate answer; Keep current choices leaves that line off and unanswered.
-- (1.2.4) Each other addon that asks to read through the Olympus API (API.lua, OlympusAPI.Register)
-- gets such a line of its own, "api:<its name>", once a session it registers: explicit, versioned
-- by what the API gives (API.CONSENT_VERSION), its answer kept for the account (ns.db.apiAddons),
-- and `adopt = false`: never taken as asked by 1.2.3's adoption of 1.2.1's lines (below).
-- (1.2.1, a player's report: "how many times do I need to update my settings?") A line the page
-- showed counts as asked for good, kept in the saved data (ns.db.consentAsked): the page opens by
-- itself once for each new question, never again for one closed unanswered or left off by Keep
-- current choices. `version` (a value or a function) makes a changed question a new one; `perCharacter` keeps
-- the record per character, for an answer kept per character (a keeper's book).
-- A focused status section may also register a `readonly` item with `section`, `status` and no
-- setter. It describes local/shared/derived/hidden/unknown/unavailable state and is never part of
-- first-open or bulk authorization.

local Consent = {}
ns.Consent = Consent

Consent.WIDTH = 940
Consent.SCREEN_MARGIN = 24
Consent.TWO_COLUMN_AT = 820
Consent.COLUMN_GAP = 24
Consent.TOP = -36 -- the first line, under the title bar (1.1.5: the page's title is in it)
Consent.LOGIN_WAIT = 45 -- after login (the realm key and the channel settle first)

local items, byKey = {}, {}
local asked = {}   -- [key] = true: on the page this session (and in ns.db.consentAsked for good)
local frame
local activeSection -- nil: every ordinary sharing choice; "profile": profile sources/visibility

local function Text(v)
	if type(v) == "function" then
		local ok, res = pcall(v)
		return ok and type(res) == "string" and res or ""
	end
	if type(v) ~= "string" then return "" end
	local s = rawget(L, v)
	return type(s) == "string" and s or v
end

-- A line of its own on the page. False when the key is taken or the item is not whole.
function Consent.Register(item)
	if type(item) ~= "table" or type(item.key) ~= "string" or byKey[item.key] then return false end
	if item.readonly == true then
		if type(item.status) ~= "function" then return false end
	elseif type(item.get) ~= "function" or type(item.set) ~= "function" then
		return false
	end
	items[#items + 1] = item
	byKey[item.key] = item
	if frame and frame:IsShown() then Consent.Refresh() end
	return true
end

local function Shown(item)
	if type(item.shown) ~= "function" then return true end
	local ok, yes = pcall(item.shown)
	return ok and yes == true
end

local function Get(item)
	if item.readonly == true then return nil end
	local ok, v = pcall(item.get)
	if not ok or (v ~= true and v ~= false) then return nil end
	return v
end

-- Whether a line still waits for the player's answer.
local function Waits(item)
	if item.readonly == true then return false end
	if type(item.pending) ~= "function" then return Get(item) == nil end
	local ok, yes = pcall(item.pending)
	return ok and yes == true
end

-- The lines this player gets, in the page's order.
function Consent.Items(section)
	local out = {}
	for _, item in ipairs(items) do
		local inSection = section and item.section == section
		local inOverview = not section and item.focusOnly ~= true
		if (inSection or inOverview) and Shown(item) then out[#out + 1] = item end
	end
	return out
end

-- An item's answer: true, false, or nil (never answered: off).
function Consent.Answer(key)
	local item = byKey[key]
	if not item then return nil end
	return Get(item)
end

-- The lines this player never answered.
function Consent.Pending(section)
	local out = {}
	for _, item in ipairs(Consent.Items(section)) do if Waits(item) then out[#out + 1] = item end end
	return out
end

local function Busy()
	return (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) and true or false
end

-- Lines the page showed, kept across sessions: [key] = the question's version (true without one).
local function AskedStore(make)
	if type(ns.db) ~= "table" then return nil end
	if type(ns.db.consentAsked) ~= "table" then
		if not make then return nil end
		ns.db.consentAsked = {}
	end
	return ns.db.consentAsked
end
local function AskedKey(item)
	if item.perCharacter == true and type(ns.me) == "string" and ns.me ~= "" then return item.key .. "@" .. ns.me:lower() end
	return item.key
end
local function Version(item)
	local v = item.version
	if type(v) == "function" then
		local ok, res = pcall(v)
		v = ok and res or nil
	end
	if type(v) == "number" or type(v) == "string" then return v end
	return true
end
local function WasAsked(item)
	if asked[item.key] then return true end
	local store = AskedStore(false)
	return store ~= nil and store[AskedKey(item)] == Version(item)
end
local function MarkAsked(item)
	asked[item.key] = true
	local store = AskedStore(true)
	if store then store[AskedKey(item)] = Version(item) end
end

-- (1.2.3, the King's stream: the page opened by itself again right after the update to 1.2.2,
-- though he had always closed it without answering.) Up to 1.2.1 the page kept the lines it showed for
-- the session alone (each login asked again), but its games notice for good (Consent.Show:
-- ns.db.consentNotices.games). An account with that notice and no record of the lines yet was
-- shown the page at every login and left its unanswered lines as they are: they count as asked,
-- as if the page had just shown them. Nothing is answered for him (unanswered stays off; /oly
-- privacy shows them).
-- Only the lines showing by the login check (LOGIN_WAIT, when 1.2.1's page opened): the first
-- check in an Olympus guild once that wait passed takes them, then the record is the only rule,
-- so a line that first shows later (a character named a keeper or a bank) is a new question,
-- asked once (review of 1.2.3).
-- And on each character the account had then (Treasury's ns.db.myCharacters), at its own first
-- session's check: its own lines (a keeper's, a bank's: perCharacter) and those it alone gets (an
-- officer's patrol line) were on its page at every login too (review of 1.2.3: a Treasurer's mail
-- character was asked its keeper line once more). The plan stays in ns.db.consentAdopt until each
-- character had its check: `lines`, the build's lines then (key = version), so a later build's
-- question is asked; `chars`, the characters still to come. A character made after the update
-- is asked as anyone.
local adoptAll = false -- this session: every line still waiting (the account's first with the record)
local adoptDone = false -- this session's check took them
local settled = false -- the login check's wait passed (Consent.OnLogin)

local function Character()
	if type(ns.me) ~= "string" or ns.me == "" then return nil end
	-- (As Treasury.lua keeps ns.db.myCharacters.)
	return tostring(ns.FullName(ns.Normal(ns.me)) or ns.me):lower()
end
local function Lines()
	local out = {}
	for _, item in ipairs(items) do if item.readonly ~= true then out[item.key] = Version(item) end end
	return out
end
local function Plan()
	local plan = type(ns.db) == "table" and ns.db.consentAdopt or nil
	if type(plan) ~= "table" or type(plan.lines) ~= "table" or type(plan.chars) ~= "table" then return nil end
	return plan
end

ns.On("INIT", function()
	adoptAll, adoptDone, settled = false, false, false
	if type(ns.db) ~= "table" or type(ns.db.consentAsked) == "table" then return end
	local seen = ns.db.consentNotices
	if type(seen) == "table" and seen.games == true then
		local chars = {}
		for name, on in pairs(type(ns.db.myCharacters) == "table" and ns.db.myCharacters or {}) do
			if on == true and type(name) == "string" then chars[name] = true end
		end
		ns.db.consentAdopt = { lines = Lines(), chars = chars }
		adoptAll = true
	end
	ns.db.consentAsked = {}
end)

-- Whether this session still takes a waiting line as asked, and that line.
local function Adopting()
	if adoptDone then return false end
	if adoptAll then return true end
	local plan, me = Plan(), Character()
	return plan ~= nil and me ~= nil and plan.chars[me] == true
end
-- (Review of 1.2.4) Never a line with adopt = false: a question no build before 1.2.3 asked (each
-- other addon's, API.lua), which an account updating from 1.2.2 straight to a later build was never
-- shown, so it stays a new question there too.
local function Adopts(item)
	if item.adopt == false then return false end
	if adoptAll then return true end
	local plan = Plan()
	return plan ~= nil and plan.lines[item.key] ~= nil and plan.lines[item.key] == Version(item)
end
local function AdoptDone()
	adoptDone = true
	local plan, me = Plan(), Character()
	if not plan then return end
	-- (The account's first session: every line it had, a test's or a late file's included.)
	if adoptAll then plan.lines = Lines() end
	if me then plan.chars[me] = nil end
	if next(plan.chars) == nil then ns.db.consentAdopt = nil end
end

-- A line waiting for its answer that the page never showed (a new question).
local function Fresh()
	local adopting = Adopting()
	local fresh = false
	for _, item in ipairs(Consent.Pending()) do
		if not WasAsked(item) then
			if not (adopting and Adopts(item)) then
				if not adopting then return true end
				fresh = true
			else
				MarkAsked(item)
			end
		end
	end
	if adopting and settled and ns.IsMember() then AdoptDone() end
	return fresh
end

-- The games' ledger's line (1.1.6, ArenaLedger.lua: Consent.Intro), where the build has the arena,
-- or nil. A notice with no answer to give (every game is recorded): the page opens by itself for
-- it once, a member who answered every line before included, and it counts as shown once the page
-- showed it (ns.db.consentNotices.games).
local function GamesLine()
	local games = ns.ArenaLedger ~= nil and rawget(L, "CONSENT_GAMES_RECORDED") or nil
	return type(games) == "string" and games ~= "" and games or nil
end
function Consent.NoticeDue()
	if not GamesLine() then return false end
	local seen = type(ns.db) == "table" and ns.db.consentNotices or nil
	return not (type(seen) == "table" and seen.games == true)
end

-- By itself, after login, when the window opens, when a 1.0 question would have been asked (the
-- zone and layer's, a keeper's) and when a player types in a chat still unanswered: only in an
-- Olympus guild, never in combat or an instance, and only for lines the page never showed (1.2.1:
-- not just this session) or a notice he was never shown. True when it showed.
function Consent.Ask(reason)
	if not ns.IsMember() or Busy() then return false end
	-- An automatic first-open question always concerns the ordinary sharing choices, even if the
	-- player last closed the focused Profile section.
	activeSection = nil
	if not (Fresh() or Consent.NoticeDue()) or (frame and frame:IsShown()) then return false end
	ns.Log("privacy page shown (%s)", tostring(reason or "?"))
	Consent.Show()
	return true
end

-- Whether the page still has a line it would ask this session by itself (Consent.Ask would show
-- it, out of combat): the version letter waits for it (1.1.5, Letters.lua). Outside an Olympus
-- guild it asks nothing.
function Consent.Waiting()
	if not ns.IsMember() then return false end
	return Fresh()
end

local function Apply(item, on)
	if item.readonly == true then return false end
	local value = on and true or false
	local ok, err = pcall(item.set, value)
	if not ok or Get(item) ~= value then
		ns.Log("privacy: %s %s failed%s", item.key, value and "yes" or "no",
			ok and "" or (": " .. tostring(err)))
		return false
	end
	ns.Log("privacy: %s %s", item.key, value and "yes" or "no")
	ns.Fire("CONSENT_CHANGED", item.key, value)
	return true
end

-- The player's individual answer: the item's own switch (which says so in chat), then the page
-- again. A broken or unavailable setter is not reported as a saved choice.
function Consent.Choose(key, on)
	local item = byKey[key]
	if not item or item.readonly == true or not Shown(item) then return false end
	local ok = Apply(item, on)
	Consent.Refresh()
	return ok
end

-- The visible lines which the main button may authorize. A prior No is never overridden, even
-- when a versioned item's pending function asks the page to describe a newer contract.
local function BulkPending()
	local out = {}
	for _, item in ipairs(Consent.Items(activeSection)) do
		if Waits(item) and Get(item) ~= false then out[#out + 1] = item end
	end
	return out
end

-- Use every item's real setter and event. Close only after every requested choice is observable;
-- on a partial failure the page stays open and the same button can retry what remains. Every
-- visible line still waiting counts as asked. A prior No stays No; every other visible pending line,
-- including an explicit permission, is authorized by this deliberately labelled action.
function Consent.AuthorizePending()
	for _, item in ipairs(Consent.Pending(activeSection)) do MarkAsked(item) end
	local targets = BulkPending()
	local all = true
	for _, item in ipairs(targets) do
		if not Apply(item, true) then all = false end
	end
	Consent.Refresh()
	if all and frame then frame:Hide() end
	return all
end

-- Close without broadening any permission. A line that appeared while the page was open is also
-- remembered as shown, so it does not interrupt every later login; nil remains off and may still
-- be answered from /oly privacy.
function Consent.KeepCurrent()
	for _, item in ipairs(Consent.Pending(activeSection)) do MarkAsked(item) end
	Consent.Refresh()
	if frame then frame:Hide() end
	return true
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function Height(fs, width)
	if fs.GetStringHeight then
		local h = fs:GetStringHeight()
		if type(h) == "number" and h > 0 then return h end
	end
	-- (No measure: about 6 pixels a letter, 14 a line.)
	local per = math.max(1, math.floor(width / 6))
	return math.ceil(#(fs:GetText() or "") / per) * 14
end

local function Button(parent, label, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 64, 20)
	b:SetText(label)
	return b
end

local function Row(i)
	local f = frame
	local r = f.rows[i]
	if r then return r end
	r = {}
	local parent = f.bodyChild
	r.label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	r.label:SetJustifyH("LEFT")
	r.state = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.state:SetJustifyH("RIGHT")
	r.text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.text:SetJustifyH("LEFT")
	if r.text.SetWordWrap then r.text:SetWordWrap(true) end
	r.no = Button(parent, L.CONSENT_NO)
	r.yes = Button(parent, L.CONSENT_YES)
	r.yes:SetScript("OnClick", function() ns.SafeCall("privacy page", Consent.Choose, r.key, true) end)
	r.no:SetScript("OnClick", function() ns.SafeCall("privacy page", Consent.Choose, r.key, false) end)
	f.rows[i] = r
	return r
end

-- (1.1.5) The Olympus window's metal without its portrait (ns.Window, Dialog.lua), the page's title in
-- its title bar. An opaque ground: the page is read line by line, and a dialog's lets the world
-- show through; the metal's rock and its inset box hide it (the plain frame's too).
-- No X and no Escape close: the two named actions below are the only close paths.
local function Make()
	local f = ns.Window("OlympusConsentFrame", UIParent, { title = L.CONSENT_TITLE, close = false, escape = false })
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f.intro = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.intro:SetJustifyH("LEFT")
	f.optional = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.optional:SetJustifyH("LEFT")
	f.footer = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.footer:SetJustifyH("LEFT")
	-- Rows live in one scrolling body. The ordinary desktop view fits as two columns; narrow or
	-- short viewports keep every line reachable instead of growing the dialog past the screen.
	f.body = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.bodyChild = CreateFrame("Frame", nil, f.body)
	f.body:SetScrollChild(f.bodyChild)
	if f.body.EnableMouseWheel then f.body:EnableMouseWheel(true) end
	f.body:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local current = self.GetVerticalScroll and self:GetVerticalScroll() or 0
		self:SetVerticalScroll(math.max(0, math.min(range, current - (delta or 0) * 36)))
	end)
	f.rows = {}
	f.close = f.CloseButton
	-- The profile's section (1.2): its button under the title bar, on the right.
	f.section = Button(f, L.CONSENT_PROFILE_SECTION, 120)
	f.section:SetPoint("TOPRIGHT", -12, Consent.TOP + 6)
	f.section:SetScript("OnClick", function()
		activeSection = activeSection == "profile" and nil or "profile"
		if f.body.SetVerticalScroll then f.body:SetVerticalScroll(0) end
		Consent.Refresh()
	end)
	-- The game's dialog pattern: equal-sized actions, conservative choice on the left and primary
	-- choice on the right. Keep current choices is muted, not disabled; it brightens on hover.
	f.all = Button(f, L.CONSENT_ACCEPT_ALL, 180)
	f.all:SetHeight(24)
	f.all:SetScript("OnClick", function() Consent.AuthorizePending() end)
	f.done = Button(f, L.CONSENT_KEEP_CURRENT, 180)
	f.done:SetHeight(24)
	f.done:SetScript("OnClick", function()
		if #BulkPending() > 0 then Consent.KeepCurrent() else f:Hide() end
	end)
	-- An answer given elsewhere meanwhile (a slash command): the page follows, once a second.
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 1 then return end
		elapsed = 0
		ns.SafeCall("privacy page", Consent.Refresh)
	end)
	f:Hide()
	-- Closed (one of its two actions), not hidden with the whole interface (Alt+Z: it still
	-- says shown): the version letter that waited for it comes a moment after (1.2.3, Letters.lua).
	f:HookScript("OnHide", function(self) if not self:IsShown() then ns.Fire("CONSENT_CLOSED") end end)
	return f
end

local function StateText(v, profile)
	if profile and v == true then return "|cff40ff40" .. L.CONSENT_STATE_SHARED .. "|r" end
	if profile and (v == false or v == nil) then return "|cff9d9d9d" .. L.CONSENT_STATE_HIDDEN .. "|r" end
	if v == true then return "|cff40ff40" .. L.CONSENT_STATE_YES .. "|r" end
	if v == false then return "|cffff4040" .. L.CONSENT_STATE_NO .. "|r" end
	local states = {
		local_ = "CONSENT_STATE_LOCAL", shared = "CONSENT_STATE_SHARED", derived = "CONSENT_STATE_DERIVED",
		hidden = "CONSENT_STATE_HIDDEN", unknown = "CONSENT_STATE_UNKNOWN", unavailable = "CONSENT_STATE_UNAVAILABLE",
	}
	local key = states[v == "local" and "local_" or v]
	if key then return "|cff9d9d9d" .. Text(key) .. "|r" end
	return "|cff9d9d9d" .. L.CONSENT_STATE_NONE .. "|r"
end

local function Status(item)
	if item.readonly ~= true then return Get(item) end
	local ok, state = pcall(item.status)
	if not ok then return "unknown" end
	if state ~= "local" and state ~= "shared" and state ~= "derived" and state ~= "hidden" and state ~= "unknown" and state ~= "unavailable" then
		return "unknown"
	end
	return state
end

-- 1.2.4: a line as this page words it, for the player's own page ("My profile", ProfileEdit.lua:
-- its Who sees what), so no other file repeats these rules: { key, label, text, state (its state's
-- words, as a Profile line's), on (true, false or nil: never answered), readonly }; nil for a key
-- no file registered.
function Consent.Describe(key)
	local item = byKey[key]
	if not item then return nil end
	local v = Status(item)
	return { key = key, label = Text(item.label), text = Text(item.text), state = StateText(v, item.section == "profile"),
		on = item.readonly ~= true and v or nil, readonly = item.readonly == true }
end

local function Viewport()
	local width = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1366
	local height = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
	if type(width) ~= "number" or width <= 0 then width = 1366 end
	if type(height) ~= "number" or height <= 0 then height = 768 end
	return width, height
end

-- The page's opening words: what always goes out, and (1.1.6, the games' ledger, ArenaLedger.lua)
-- in one line that game results are recorded and who sees them, where the build has the arena.
function Consent.Intro()
	local text = L.CONSENT_INTRO:format(ns.Comm and ns.Comm.Audience and ns.Comm.Audience() or "")
	local games = GamesLine()
	if games then text = text .. " " .. games end
	return text
end

-- Lays the page out again: its lines, each answer, the channel's audience.
function Consent.Refresh()
	local f = frame
	if not f then return end
	local screenW, screenH = Viewport()
	local W = math.min(Consent.WIDTH, math.max(1, screenW - Consent.SCREEN_MARGIN))
	local inner = W - 40
	f:SetWidth(W)
	local y = Consent.TOP
	ns.SetWindowTitle(f, activeSection == "profile" and L.CONSENT_PROFILE_TITLE or L.CONSENT_TITLE)
	local profileItems = Consent.Items("profile")
	f.section:SetShown(#profileItems > 0)
	f.section:SetText(activeSection == "profile" and L.CONSENT_ALL_SHARING or L.CONSENT_PROFILE_SECTION)
	-- (The page's lines start under the section's button where it shows.)
	if #profileItems > 0 then y = y - 26 end
	f.intro:ClearAllPoints()
	f.intro:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
	f.intro:SetWidth(inner)
	f.intro:SetText(activeSection == "profile" and L.CONSENT_PROFILE_INTRO or Consent.Intro())
	y = y - Height(f.intro, inner) - 10
	f.optional:ClearAllPoints()
	f.optional:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
	f.optional:SetWidth(inner)
	f.optional:SetText(activeSection == "profile" and L.CONSENT_PROFILE_OPTIONAL or L.CONSENT_OPTIONAL)
	y = y - Height(f.optional, inner) - 12
	local list = Consent.Items(activeSection)
	local columns = W >= Consent.TWO_COLUMN_AT and #list > 1 and 2 or 1
	local bodyWidth = inner - 20 -- room for the template's scrollbar
	local colWidth = columns == 2 and math.floor((bodyWidth - Consent.COLUMN_GAP) / 2) or bodyWidth
	local perColumn = math.ceil(#list / columns)
	local columnY = {}
	for c = 1, columns do columnY[c] = 0 end
	for i, item in ipairs(list) do
		local r = Row(i)
		r.key = item.key
		local column = math.min(columns, math.floor((i - 1) / math.max(1, perColumn)) + 1)
		local x = (column - 1) * (colWidth + Consent.COLUMN_GAP)
		local rowY = columnY[column]
		r.column = column
		local v = Status(item)
		r.label:ClearAllPoints()
		r.label:SetPoint("TOPLEFT", f.bodyChild, "TOPLEFT", x, rowY)
		local labelWidth = math.max(80, colWidth - (item.readonly == true and 105 or 235))
		r.label:SetWidth(labelWidth)
		r.label:SetText(Text(item.label))
		-- A label beside the buttons may take two lines: its text starts under it, not on it.
		local textTop = math.max(20, Height(r.label, labelWidth) + 6)
		r.state:ClearAllPoints()
		if item.readonly == true then
			r.state:SetPoint("TOPRIGHT", f.bodyChild, "TOPLEFT", x + colWidth, rowY)
		else
			r.no:ClearAllPoints()
			r.no:SetPoint("TOPRIGHT", f.bodyChild, "TOPLEFT", x + colWidth, rowY + 3)
			r.yes:ClearAllPoints()
			r.yes:SetPoint("RIGHT", r.no, "LEFT", -6, 0)
			r.state:SetPoint("RIGHT", r.yes, "LEFT", -10, 0)
		end
		r.state:SetText(StateText(v, activeSection == "profile"))
		-- The answer given stays lit.
		if item.readonly ~= true and v == true then r.yes:LockHighlight() else r.yes:UnlockHighlight() end
		if item.readonly ~= true and v == false then r.no:LockHighlight() else r.no:UnlockHighlight() end
		local text = Text(item.text)
		local note = item.note and Text(item.note) or ""
		if note ~= "" then text = text .. " |cffffd200" .. note .. "|r" end
		r.text:ClearAllPoints()
		r.text:SetPoint("TOPLEFT", f.bodyChild, "TOPLEFT", x + 8, rowY - textTop)
		r.text:SetWidth(colWidth - 8)
		r.text:SetText(text)
		for _, part in ipairs({ r.label, r.state, r.text }) do part:Show() end
		if item.readonly == true then r.yes:Hide(); r.no:Hide() else r.yes:Show(); r.no:Show() end
		columnY[column] = rowY - textTop - Height(r.text, colWidth - 8) - 12
	end
	for i = #list + 1, #f.rows do
		local r = f.rows[i]
		r.key, r.column = nil, nil
		for _, part in ipairs({ r.label, r.state, r.text, r.yes, r.no }) do part:Hide() end
	end
	local bodyHeight = 1
	for c = 1, columns do bodyHeight = math.max(bodyHeight, -columnY[c]) end
	f.bodyChild:SetSize(bodyWidth, bodyHeight)
	f.body:ClearAllPoints()
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
	f.body:SetWidth(bodyWidth)
	-- Footer text has not been assigned yet; measure the real value before choosing the body's
	-- visible height. Header, footer and action stay fixed while only the rows scroll.
	f.footer:SetWidth(inner)
	f.footer:SetText(L.CONSENT_FOOTER)
	local footerHeight = Height(f.footer, inner)
	local fixedHeight = -y + 10 + footerHeight + 10 + 20 + 38
	local maxHeight = math.max(1, screenH - Consent.SCREEN_MARGIN)
	local bodyVisible = math.min(bodyHeight, math.max(80, maxHeight - fixedHeight))
	f.body:SetHeight(bodyVisible)
	-- The page follows the answers once a second: the rows keep where the player scrolled them
	-- (1.1.6, the owner's report: every refresh put them back at the top, so the lines under the
	-- first screen could not be reached), within the rows' new reach. Opening it starts at the top.
	if f.body.SetVerticalScroll then
		local kept = f.body.GetVerticalScroll and f.body:GetVerticalScroll() or 0
		f.body:SetVerticalScroll(math.max(0, math.min(kept, bodyHeight - bodyVisible)))
	end
	y = y - bodyVisible - 10
	f.footer:ClearAllPoints()
	f.footer:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
	y = y - Height(f.footer, inner) - 10
	f.done:ClearAllPoints()
	f.all:ClearAllPoints()
	if #BulkPending() > 0 then
		f.all:SetText(L.CONSENT_ACCEPT_ALL)
		f.done:SetText(L.CONSENT_KEEP_CURRENT)
		if f.all.SetNormalFontObject then f.all:SetNormalFontObject("GameFontNormal") end
		if f.all.SetAlpha then f.all:SetAlpha(1) end
		if f.done.SetNormalFontObject then f.done:SetNormalFontObject("GameFontDisable") end
		if f.done.SetHighlightFontObject then f.done:SetHighlightFontObject("GameFontHighlight") end
		if f.done.SetAlpha then f.done:SetAlpha(0.8) end
		f.all:SetPoint("TOPRIGHT", f, "TOP", -6, y)
		f.done:SetPoint("TOPLEFT", f, "TOP", 6, y)
		f.all:Show()
	else
		f.done:SetText(L.CONSENT_DONE)
		if f.done.SetNormalFontObject then f.done:SetNormalFontObject("GameFontNormal") end
		if f.done.SetAlpha then f.done:SetAlpha(1) end
		f.done:SetPoint("TOP", f, "TOP", 0, y)
		f.all:Hide()
	end
	f:SetHeight(math.min(maxHeight, -y + 20 + 18))
end

-- The page, whatever was answered (/oly privacy, and Consent.Ask). Every line not answered yet
-- counts as asked, for good (1.2.1: it was for this session, so the page opened again at every
-- login for a line closed unanswered).
function Consent.Show(section)
	activeSection = section == "profile" and "profile" or nil
	for _, item in ipairs(Consent.Pending(activeSection)) do MarkAsked(item) end
	if not activeSection and GamesLine() and type(ns.db) == "table" then
		if type(ns.db.consentNotices) ~= "table" then ns.db.consentNotices = {} end
		ns.db.consentNotices.games = true
	end
	frame = frame or Make()
	if frame.body.SetVerticalScroll then frame.body:SetVerticalScroll(0) end
	Consent.Refresh()
	frame:Show()
	return frame
end

function Consent.Frame() return frame end
function Consent.Hide() if frame then frame:Hide() end end

-- Tests start from a clean state, as a fresh install (and a fresh frame when the toolkit was
-- rebuilt). (A new session keeps ns.db.consentAsked: only this file's state starts again.)
function Consent.Reset()
	wipe(asked)
	if type(ns.db) == "table" then ns.db.consentAsked, ns.db.consentAdopt = nil, nil end
	activeSection, adoptAll, adoptDone = nil, false, false
	if frame and rawget(_G, "OlympusConsentFrame") ~= frame then frame = nil elseif frame then frame:Hide() end
end

---------------------------------------------------------------------------
-- The lines of 1.1
---------------------------------------------------------------------------

local function IsKing() return ns.King ~= nil and ns.King.IsKing ~= nil and ns.King.IsKing() == true end

-- The King's zone and layer are his crown on the Throne, and he is never asked for layer help.
Consent.Register({
	key = "location", section = "profile", label = "CONSENT_LOCATION", text = "CONSENT_LOCATION_TEXT",
	shown = function() return not IsKing() end,
	get = function() return ns.db.shareLocation end,
	set = function(on) ns.Layers.SetSharing(on) end,
})
Consent.Register({
	key = "layerhelp", label = "CONSENT_LAYERHELP", text = "CONSENT_LAYERHELP_TEXT",
	shown = function() return not IsKing() end,
	get = function() return ns.db.layerHelp end,
	set = function(on) ns.Hop.SetHelp(on) end,
	note = function() return not ns.Layers.Sharing() and L.CONSENT_NEEDS_LOCATION or nil end,
})
-- A keeper's book. The line shows what goes out now (Treasury.Consent: the Treasurer's 0.9.3 yes
-- still sends his book, and the line says so), and waits for his answer to 1.0's question
-- (Treasury.ConsentAnswer), asked in 1.0's words: the Treasurer's character holding 0.9's book
-- is told that his yes also sends the early supporters' names to everyone on the channel
-- (Treasury.YesSendsEarly), as 1.0's question tells him (Konig's review of 1.0.0).
local function TreasuryHas(fn) return ns.Treasury ~= nil and type(ns.Treasury[fn]) == "function" end
Consent.Register({
	key = "treasurer", label = "CONSENT_TREASURER",
	text = function()
		local early = TreasuryHas("YesSendsEarly") and ns.Treasury.YesSendsEarly() == true
		return L.CONSENT_TREASURER_TEXT .. (early and (" " .. L.CONSENT_TREASURER_EARLY) or "")
	end,
	shown = function() return TreasuryHas("RealKeeper") and ns.Treasury.RealKeeper() == true end,
	get = function() return ns.Treasury.Consent() end,
	pending = function() return ns.Treasury.ConsentAnswer() == nil end,
	perCharacter = true, -- (his answer is his character's, Treasury.ConsentKey)
	set = function(on) ns.Treasury.SetConsent(on) end,
	note = function()
		if ns.Treasury.ConsentAnswer() == nil and ns.Treasury.Consent() == true then return L.CONSENT_TREASURER_OLD_YES end
		return nil
	end,
})
Consent.Register({
	key = "inspection", label = "CONSENT_INSPECTION", text = "CONSENT_INSPECTION_TEXT",
	get = function() return ns.db.royalInspection end,
	set = function(on)
		ns.db.royalInspection = on
		ns.Print(on and L.INSPECTION_OPT_ON or L.INSPECTION_OPT_OFF)
	end,
})
Consent.Register({
	key = "rollcall", label = "CONSENT_ROLLCALL", text = "CONSENT_ROLLCALL_TEXT",
	get = function() return ns.db.rollCall end,
	set = function(on) ns.Workshop.SetAnswers(on) end,
})
Consent.Register({
	key = "chat", label = "CONSENT_CHAT", text = "CONSENT_CHAT_TEXT",
	get = function() return ns.db.addonChat end,
	set = function(on) ns.Channels.SetChatOn(on) end,
})
-- An officer's patrol findings to his guild's officers (Inspect.lua, Fern's #29): officers alone
-- send and keep them, so only they are asked (Konig's review of 1.1: it was on by default and
-- missing from this page).
Consent.Register({
	key = "patrolshare", label = "CONSENT_PATROLSHARE", text = "CONSENT_PATROLSHARE_TEXT",
	shown = function() return ns.IsMember() == true and ns.Roster.IsOfficer() == true end,
	get = function() return ns.db.patrolShare end,
	set = function(on) ns.Inspect.SetSharing(on) end,
})

-- The first question after login: the page, once the login settled, then on the minute until it
-- could be asked (combat, an instance), once for each question (Consent.Ask).
function Consent.OnLogin()
	ns.After(Consent.LOGIN_WAIT, "privacy page", function()
		settled = true -- (the lines left from 1.2.1 are taken at this check: Fresh)
		Consent.Ask("login")
	end)
	ns.Every(60, "privacy page", function() Consent.Ask("login") end)
end
ns.On("LOGIN", function() Consent.OnLogin() end)
