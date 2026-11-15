local ADDON, ns = ...
local L = ns.L

-- 1.2.5.1: the Olympus Accord, Olympus's terms of use (its name in one place: L.ACCORD_NAME). A
-- letter on parchment, in Olympus's own window, that every account accepts once before Olympus
-- works: until then ns.IsMember is false (Core.lua), so this client sends nothing and hears nothing
-- of the army, and the Olympus window shows the Accord's page alone (UI.lua). The privacy page
-- (Consent.lua) comes after it, as before.
--
-- When it asks: LOGIN_WAIT after login, then every RETRY until it could (never in combat or an
-- instance, as the privacy page); when the window opens, when the author's signed list makes our
-- guild an Olympus guild, when this account's BattleTag changed and on /oly privacy (each of these
-- a deliberate ask: Not now at login is for the login's tries alone). Not now saves nothing: the
-- next login asks again. Accepted: ns.db.accord, for the game account (its alts are not asked
-- again): the version, when, and 8 bits of the BattleTag's hash (fp), enough to see it changed
-- (one change in 256 goes unseen until the next version), never the tag itself: with 16 a known
-- name's digits came back from the file almost alone. A higher ns.ACCORD_VERSION asks again.
--
-- The BattleTag. Only the player's own, read from his own game (BNGetInfo, as Blizzard's own
-- FriendsFrame reads it once Battle.net is connected, on every supported client); I accept is
-- enabled only while it can be read. An account that accepted is never locked out by a Battle.net
-- outage: the gate (ns.AccordAccepted) reads saved data alone, and Check acts only on a tag it read.
-- It shows masked on the letter (its digits; Show reveals them for REVEAL seconds), and on the
-- King's screen (Stream: his character, any character of his game account once it was seen
-- there, his preview) no part of it, with no Show (he streams).
--
-- Who gets it in game: the moderation team alone (WatchChat.InRoom: the author, the King, the High
-- Council and the Olympus moderators they named). A team member's client asks on the Olympus
-- channel (BQ, ASK_FIRST after login, then every ASK_EVERY); each player's client that accepted
-- answers that one asker by a logged whisper (BT), after a random delay, at most once every
-- TELL_EVERY from each character to each asker, and only to an asker of the team level of its own
-- or higher (WatchChat.ActorLevel): an ordinary player's goes to any team member, a moderator's to
-- the moderators and above, a councillor's to the council, the King and the author, the King's to
-- the author alone. Nothing goes to a team member who did not just show he is online; the
-- server's "No player named..." for one who left meanwhile drops what waits for him and, with
-- mouse and keyboard (the gamepad gate's system-filters), stays out of the chat for QUIET seconds
-- after our whisper. Nothing ever goes on the channel or GUILD, and no other player's client keeps
-- or shows one. The team's clients keep them (ns.rdb.battletags, KEEP after the last one) while
-- they are on the team (Guard: wiped at once on its own sanction or a lost seat, else TEAM_GRACE
-- off the team), and The Watch shows them, grouped by tag (the characters one player plays), the
-- digits hidden until the page's Show (REVEAL seconds), and on the King's screen no part of a tag,
-- his eye button included. `/oly accord forget <name>` drops that player's tag on a team client (a
-- removal asked for). A tag is what that player's own addon read and sent: a modified addon can
-- send someone else's. Its one automatic use: a sanction follows the BattleTag (TagFollow.lua), a
-- code of it reaching every client, each applying it to its own player alone; nothing goes out by
-- name on a match alone, and a wrong follow is stopped from The Watch (`/oly accord unfollow <name>`).
-- That code is made of the tag and this game account's follow key (AccountKey: 16 random hex digits
-- made once, at the first accept, kept through later ones, and sent with the tag in BT alone), so
-- only the team can tell whose BattleTag a code is, and a copied tag gives a code no other account
-- has. The King's game account (ns.db.kingAccount) answers the King and the author alone, as his
-- own character does.
--
-- The Olympus Companion app (the letter's ACCORD_T5_3): once accepted, the bridge's "self" section
-- (BridgeSections.lua) hands this character's name and own tag, read here (ReadTag), to the private
-- sidecar a Companion user installed, which saves it in its own file at logout or /reload; the
-- Companion takes it to Olympus's online census, where only its staff see BattleTags. Nothing is
-- sent in game for it, and the tags a team client keeps of others never go there (nor the follow
-- key: it goes in BT alone).
--
--   BQ~1                                                a team member's ask (the channel, not logged)
--   BT~1~<version>~<accepted at>~<guild>~<tag>~<key>    a player's answer (a logged whisper to the asker)

local Accord = {}
ns.Accord = Accord

Accord.LOGIN_WAIT = 30      -- after login (before the privacy page's 45)
Accord.RETRY = 60           -- then on the minute until it could ask
Accord.READ_GAP = 2         -- seconds between Battle.net reads while the letter shows
Accord.HANDOFF = 1.5        -- accepted: the privacy page a moment after
Accord.REVEAL = 10          -- seconds Show reveals the tag's digits
Accord.TAG_MAX = 64
Accord.ASK_FIRST = 90       -- a team member's first ask after login
Accord.ASK_EVERY = 1800     -- and then
Accord.TELL_EVERY = 72000   -- each character to each asker at most once in 20 hours
Accord.DELAY_MIN, Accord.DELAY_MAX = 5, 240 -- an answer's random delay
Accord.TAKE_WINDOW = 4200   -- a team client keeps answers this long after its own last ask
Accord.TAKE_GAP = 600       -- the same character and tag kept again at most this often
Accord.KEEP = 180 * 86400   -- a kept tag, after it was last received
Accord.ROWS_MAX = 3000
Accord.QUIET = 10           -- the server's "No player named" for an asker we just whispered: out of chat this long
Accord.RETELL_WINDOW = 600  -- I accept tells the askers heard this recently (an older one may have left)
Accord.TEAM_GRACE = 2 * 86400 -- a client off the team this long drops its BattleTags (a namer's list may lapse a while)
Accord.GUARD_FIRST, Accord.GUARD_EVERY = 300, 600
Accord.ASKERS_MAX = 40
Accord.TOLD_MAX = 400
Accord.SHOWN_MAX = 150
Accord.WIDTH = 560
Accord.HEIGHT = 680
Accord.SCREEN_MARGIN = 48
-- The letter's topics: { n, bullets }, keys ACCORD_T<n>_HEAD and ACCORD_T<n>_<i> (AccordText.lua),
-- each bullet one short sentence. BOLD: the bullets in heavier ink (a font string has no inline
-- bold: the whole line, its shadow one pixel to the right in the ink's own colour).
Accord.TOPICS = { { 1, 2 }, { 2, 2 }, { 3, 6 }, { 4, 7 }, { 5, 6 }, { 6, 4 }, { 7, 1 }, { 8, 2 }, { 9, 2 } }
Accord.BOLD = { ["2_1"] = true, ["5_2"] = true, ["5_3"] = true, ["5_4"] = true }
-- A BattleTag as Battle.net writes one: a name, "#", digits. Never "~", "|" or a control byte.
Accord.TAG_SHAPE = "^[^#~|%c]+#%d+$"
-- A game account's follow key (TagFollow.lua's code): 16 lowercase hex digits.
Accord.KEY_SHAPE = "^[0-9a-f]+$"
Accord.KEY_LEN = 16
Accord.random = math.random -- (swappable in tests)

local frame
local session = { declined = false, newSaid = false, revealUntil = 0, teamRevealUntil = 0, lastRead = -math.huge }
local askers = {}  -- [Fold(name)] = { name, at }: team members whose ask was heard this session
local pending = {} -- [Fold(name)] = { name }: an answer waiting for its delay (NotFound takes it away)
-- [lower(name as the server writes it)] = { untilAt (GetTime), left }: the not-found lines our
-- whispers to him may still cause (1.6.0: one each, Accord.Tried); his name's forms share one.
local quiet = {}
local lastLine = { key = false, hide = false } -- the line the chat windows are asking about now
local watchingNotFound, filtering = false, false
local stats = { asks = 0, heard = 0, told = 0, kept = 0, refused = 0, askNotTeam = 0, lower = 0, gone = 0, wiped = 0,
	quieted = 0, passed = 0 }

local function Mono() return type(GetTime) == "function" and GetTime() or 0 end
-- A sanction that follows the BattleTag (TagFollow.lua, loaded after this file): its calls, guarded.
local function TF()
	local t = ns.TagFollow
	return type(t) == "table" and not t.missing and t or nil
end
local function Grey(s) return "|cff9d9d9d" .. tostring(s) .. "|r" end

-- Values the client hides from addons (secret values): never compared, never read.
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function Call(fn)
	local ok, v = pcall(fn)
	return ok and not Secret(v) and v == true
end

-- The player's own BattleTag, or nil and why: "api" (no BNGetInfo), "offline" (Battle.net down,
-- its features off, a secret or no value), "shape" (not Name#digits).
function Accord.ReadTag()
	if type(BNGetInfo) ~= "function" then return nil, "api" end
	local up
	if type(BNFeaturesEnabledAndConnected) == "function" then up = Call(BNFeaturesEnabledAndConnected)
	elseif type(BNConnected) == "function" then up = Call(BNConnected) else up = true end
	if not up then return nil, "offline" end
	local ok, _, tag = pcall(BNGetInfo)
	if not ok or Secret(tag) or type(tag) ~= "string" or tag == "" then return nil, "offline" end
	if #tag > Accord.TAG_MAX or not tag:match(Accord.TAG_SHAPE) then return nil, "shape" end
	return tag
end

-- 8 bits of the tag's hash: a changed tag shows (but one in 256), and a known name leaves dozens
-- to hundreds of digit strings that fit it, not one (the salt is in the public source).
function Accord.Fp(tag)
	local h = ns.Sign.SHA256("OlympusAccord\0" .. ns.Fold(tag))
	return ("%02x"):format(h:byte(1))
end
-- A saved fp as Fp writes it (a 1.2.5.1 test build kept two bytes: the first is the same one).
local function SavedFp(a)
	return type(a) == "table" and type(a.fp) == "string" and a.fp:sub(1, 2) or nil
end

local function Saved()
	local a = type(ns.db) == "table" and ns.db.accord or nil
	return type(a) == "table" and a or nil
end

-- This game account's follow key (see the top), or nil. make: one is made now for an account that
-- accepted without one (an earlier build). From this computer's clocks, the game's generator and
-- the entropy sample (Sign.EntropySample), through SHA-256, as Keys.NewKey: no game source is cryptographic, and nobody
-- but the moderation team ever receives it.
function Accord.IsKey(k) return type(k) == "string" and #k == Accord.KEY_LEN and k:find(Accord.KEY_SHAPE) ~= nil end
local function NewKey()
	local parts = { tostring(ns.me), tostring(time and time()), tostring(GetTime and GetTime()), tostring(math.random()),
		tostring(math.random()), tostring({}), tostring(debugprofilestop and debugprofilestop() or 0) }
	parts[#parts + 1] = tostring(ns.Sign.EntropySample())
	local raw = ns.Sign.SHA256("OlympusAccordKey\0" .. table.concat(parts, "|"))
	local hex = {}
	for i = 1, Accord.KEY_LEN / 2 do hex[i] = ("%02x"):format(raw:byte(i)) end
	return table.concat(hex)
end
function Accord.AccountKey(make)
	local a = Saved()
	if not a then return nil end
	if Accord.IsKey(a.key) then return a.key end
	if not make or a.yes ~= true then return nil end
	a.key = NewKey()
	return a.key
end

local function Busy()
	return (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) and true or false
end

---------------------------------------------------------------------------
-- The moderation team (WatchChat.lua's room: InRoom)
---------------------------------------------------------------------------

local function WC()
	local w = ns.WatchChat
	return type(w) == "table" and not w.missing and type(w.InRoom) == "function" and w or nil
end
local function TeamName(name)
	local w = WC()
	return w ~= nil and type(name) == "string" and name ~= "" and w.InRoom(name) == true
end
function Accord.TeamMember()
	return ns.IsMember() == true and type(ns.me) == "string" and TeamName(ns.me)
end
local function Previewing()
	local V = ns.ViewAs
	return type(V) == "table" and not V.missing and type(V.Available) == "function" and V.Available() == true
		and type(V.Role) == "function" and V.Role() ~= "my"
end
-- The team's page and lines show: a team member's client, never in the author's role preview.
function Accord.TeamShown() return Accord.TeamMember() and not Previewing() end

-- Whether our tag may go to `name`: a team member whose level is ours or higher (WatchChat's
-- ActorLevel: 0 an ordinary player, 3 a moderator, 4 a councillor, 6 the King, 7 the author), so a
-- team member's own tag never goes down to those he outranks (one councillor's list names up to ten).
-- Any character of the King's game account (ns.db.kingAccount) stands as the King: his alts' tag
-- goes to the King and the author alone, so no other team client holds a row of his account (a
-- sanction never follows it, TagFollow.lua).
local function MayTell(name)
	if not TeamName(name) then return false end
	local w = WC()
	if type(w.ActorLevel) ~= "function" then return true end
	local mine = tonumber(w.ActorLevel(ns.me)) or 0
	if type(ns.db) == "table" and ns.db.kingAccount == true then
		mine = math.max(mine, type(w.LEVEL) == "table" and tonumber(w.LEVEL.king) or 6)
	end
	return (tonumber(w.ActorLevel(name)) or 0) >= mine
end
Accord.MayTell = MayTell

-- The King's stream: his character, the author's preview of his screen, and any character of his
-- game account once his own was seen on it (ns.db.kingAccount: an alt's letter shows nothing either).
local function Stream()
	if type(ns.db) == "table" and ns.db.kingAccount == true then return true end
	return (ns.IsKingCharacter and ns.IsKingCharacter(ns.me) == true) or ns.KingsScreen() == true
end
Accord.Stream = Stream

-- A tag as this screen shows it: its name and "#****" until the page's Show (REVEAL seconds); on
-- the King's screen no part of it ("BattleTag <n>" for the n-th group), whatever his eye button
-- says (ns.CouncilNamesShown is not asked).
function Accord.ShownTag(tag, n)
	tag = tostring(tag or "")
	if Stream() then return n and L.ACCORD_TEAM_HIDDEN:format(n) or L.ACCORD_TAG_HIDDEN_STREAM end
	if session.teamRevealUntil > Mono() then return tag end
	return (tag:match("^(.-)#") or tag) .. "#****"
end
function Accord.TeamRevealed() return not Stream() and session.teamRevealUntil > Mono() end
-- The page's Show / Hide: the digits for REVEAL seconds, never on the King's screen; the page
-- follows (ACCORD_TEAM_CHANGED, UI.lua), and again when they hide by themselves.
function Accord.RevealTeam()
	if Stream() or not Accord.TeamShown() then return false end
	session.teamRevealUntil = Accord.TeamRevealed() and 0 or Mono() + Accord.REVEAL
	ns.Fire("ACCORD_TEAM_CHANGED")
	if session.teamRevealUntil > 0 then
		ns.After(Accord.REVEAL + 0.2, "olympus accord hide", function() ns.Fire("ACCORD_TEAM_CHANGED") end)
	end
	return true
end
local function ShownName(name)
	local shown = ns.DisplayName(name) or tostring(name)
	if ns.CouncilMasked() then return ns.MaskName(shown) end
	return shown
end

---------------------------------------------------------------------------
-- Accepting
---------------------------------------------------------------------------

-- The addon starts or stops as when one joins or leaves an Olympus guild (Roster.lua's guild
-- change): the roster, the channel (left now, or joined and the census asked for), the realm key,
-- the hello, and every page.
local function Changed(on)
	ns.Fire("ACCORD_CHANGED", on)
	local R, C = ns.Roster, ns.Comm
	if R and R.RequestScan then ns.SafeCall("accord roster", R.RequestScan, true) end
	if C and C.CheckMembership then ns.SafeCall("accord membership", C.CheckMembership) end
	if on and C then
		if C.JoinSoon then ns.SafeCall("accord channel", C.JoinSoon, math.huge) end
		if C.RequestKey then ns.SafeCall("accord key", C.RequestKey) end
		if C.Hello then ns.SafeCall("accord hello", C.Hello, true) end
		-- (1.4.0) The login's ask for the army's guilds (Data.AskGlobalCensus, 20 s after INIT) was
		-- refused while the Accord waited: a member now, ask again once the channel is joined.
		local D = ns.Data
		if D and D.AskGlobalCensus and ns.After then ns.After(30, "accord census", function() ns.SafeCall("accord census", D.AskGlobalCensus) end) end
	end
	-- The login's own asks that waited for a member and found none (the letter shows LOGIN_WAIT
	-- after login, after most of them): the guild's newer realm key (Keys, K5), the War page's
	-- recovery, an officer's loot book and patrol findings, the team's BattleTag ask. Each keeps its
	-- own once-a-session or spacing rule.
	if on then
		local function Live(t) return type(t) == "table" and not t.missing and t or nil end
		local K, Wr, Lo, I = Live(ns.Keys), Live(ns.War), Live(ns.Loot), Live(ns.Inspect)
		if K and K.Ask then ns.SafeCall("accord key epoch", K.Ask) end
		if Wr and Wr.Ask then ns.SafeCall("accord war", Wr.Ask) end
		if Lo and Lo.Ask and Lo.IsOfficer and Lo.IsOfficer() then ns.SafeCall("accord loot", Lo.Ask) end
		if I and I.AskShared then ns.SafeCall("accord patrol", I.AskShared) end
		ns.SafeCall("accord team", Accord.AskTeam)
	end
	ns.Fire("DATA_CHANGED")
end

local Tell -- (below)

-- I accept: the tag read again at the click (never the one the letter showed). True when taken;
-- false and "tag" when no tag can be read now (the letter says why).
function Accord.Accept()
	if type(ns.db) ~= "table" then return false, "db" end
	local tag = Accord.ReadTag()
	if not tag then
		if frame and frame:IsShown() then Accord.Refresh(true) end
		return false, "tag"
	end
	local old, v, fp = Saved(), ns.ACCORD_VERSION, Accord.Fp(tag)
	-- (Another tag: the team is told again, whenever it last was.)
	local told = old and type(old.told) == "table" and SavedFp(old) == fp and old.told or {}
	-- (The follow key stays through a new version or another tag: TagFollow.lua's code follows the
	-- account, never a moment.)
	local key = old and Accord.IsKey(old.key) and old.key or NewKey()
	ns.db.accord = { v = v, yes = true, at = ns.Now(), fp = fp, told = told, key = key }
	ns.Log("olympus accord accepted (v%d)", v)
	Changed(true)
	ns.Print(L.ACCORD_ACCEPTED:format(v))
	if frame then frame:Hide() end
	-- Team members heard asking lately (an account asked again: a new version, another tag), within
	-- RETELL_WINDOW: one heard longer ago may have left, and asks again within ASK_EVERY anyway.
	local now = Mono()
	for _, e in pairs(askers) do
		if now - e.at <= Accord.RETELL_WINDOW then Tell(e.name, true) end
	end
	ns.After(Accord.HANDOFF, "olympus accord", function()
		local C = ns.Consent
		if C and not C.missing and C.Ask then C.Ask("accord") end
	end)
	return true
end

-- Not now: Olympus stays off, nothing saved; the login's tries leave it until the next login.
function Accord.NotNow()
	session.declined = true
	if frame then frame:Hide() end
	if not ns.AccordAccepted() then ns.Print(L.ACCORD_DECLINED) end
	return true
end

-- The letter by itself: in an Olympus guild, not accepted, not shown already, not in combat or an
-- instance, and at login only while Not now was not said this session. True when it showed.
function Accord.Ask(reason)
	if not ns.InOlympusGuild() or ns.AccordAccepted() then return false end
	if frame and frame:IsShown() then return false end
	if Busy() then return false end
	if reason == "login" and session.declined then return false end
	ns.Log("olympus accord shown (%s)", tostring(reason or "?"))
	Accord.Show(reason)
	return true
end

-- At login, on each loading screen and when Battle.net comes or goes: an accepted account whose
-- tag is read and differs is asked again; one accepted for an older version is told once; an
-- unreadable tag changes nothing.
function Accord.Check()
	local a = Saved()
	local tag = Accord.ReadTag()
	if type(ns.db) == "table" and ns.IsKingCharacter and ns.IsKingCharacter(ns.me) == true then ns.db.kingAccount = true end
	local changed = a and ns.AccordAccepted() and tag and SavedFp(a) and SavedFp(a) ~= Accord.Fp(tag) or false
	if changed then
		a.yes, a.why = false, "tag"
		ns.Log("olympus accord: this account's BattleTag changed, asked again")
		Changed(false)
		ns.Print(L.ACCORD_TAG_CHANGED)
		Accord.Ask("tag")
	elseif a and a.yes == true and (tonumber(a.v) or 0) < ns.ACCORD_VERSION and not session.newSaid then
		session.newSaid = true
		ns.Print(L.ACCORD_NEW_VERSION:format(ns.ACCORD_VERSION))
	end
	if frame and frame:IsShown() then Accord.Refresh(true) end
	-- (This account's own BattleTag's code, for the follows: read again; another tag drops its own.)
	local T = TF()
	if T and T.Refresh then ns.SafeCall("tag follow refresh", T.Refresh, changed == true) end
end

---------------------------------------------------------------------------
-- The player's side: answering the team's ask
---------------------------------------------------------------------------

local function ToldKey(name) return ns.Fold(ns.me or "") .. ">" .. ns.Fold(name) end
local function PruneTold(t)
	local now, list = ns.Now(), {}
	for k, at in pairs(t) do
		if type(at) ~= "number" or now - at > 2 * Accord.TELL_EVERY or at > now + 86400 then t[k] = nil
		else list[#list + 1] = { k = k, at = at } end
	end
	if #list <= Accord.TOLD_MAX then return end
	table.sort(list, function(x, y) return x.at < y.at end)
	for i = 1, #list - Accord.TOLD_MAX do t[list[i].k] = nil end
end
local function Told()
	local a = Saved()
	if not a then return nil end
	if type(a.told) ~= "table" then a.told = {} end
	return a.told
end
local function RecordTold(name)
	local t = Told()
	if not t then return end
	t[ToldKey(name)] = ns.Now()
	PruneTold(t)
	stats.told = stats.told + 1
end

-- The answer: the accepted version and time, our guild (as Watch.OwnGuild has it), the tag, and
-- this game account's follow key last.
local function Wire(tag)
	local a = Saved()
	local guild = GetGuildInfo and GetGuildInfo("player")
	if not a or type(guild) ~= "string" or guild == "" or guild:find("[~|%c]") then return nil end
	local key = Accord.AccountKey(true)
	if not key then return nil end
	local msg = ("BT~1~%d~%d~%s~%s~%s"):format(tonumber(a.v) or 0, math.floor(tonumber(a.at) or 0), ns.Cut(guild, 72), tag, key)
	return #msg <= 255 and msg or nil
end

-- The server's "No player named <name> is currently playing" (ERR_CHAT_PLAYER_NOT_FOUND_S, its
-- pattern as Treasury reads it): who it names, lower case, or nil (a secret value: never read).
local function NotFoundName(text)
	if type(text) ~= "string" or Secret(text) then return nil end
	local T = ns.Treasury
	local pattern = type(T) == "table" and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and text:match(pattern)
	if type(who) ~= "string" then return nil end
	who = who:gsub("^'", ""):gsub("'$", "")
	return ((ns.splitNames and ns.Normal(who)) or who):lower()
end
local function NamedAs(name, who)
	return (ns.TellName(name) or ""):lower() == who or (ns.DisplayName(name) or ""):lower() == who
end

-- That line for a team member we told or were about to tell: he left, so the answer still
-- waiting for its delay is dropped, and I accept no longer tells him (his next ask, when he is
-- back, is answered as any). True when it named one.
function Accord.NotFound(text)
	local who = NotFoundName(text)
	if not who then return false end
	local hit = false
	for key, p in pairs(pending) do
		if NamedAs(p.name, who) then pending[key] = nil; hit = true end
	end
	for key, e in pairs(askers) do
		if NamedAs(e.name, who) then askers[key] = nil; hit = true end
	end
	if hit then stats.gone = stats.gone + 1 end
	return hit
end
-- (Registered the first time an answer waits, as the Arena's and the sightings' whispers do.)
local function WatchNotFound()
	if watchingNotFound then return end
	watchingNotFound = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("olympus accord not found", Accord.NotFound, text) end)
end

-- The same line, kept out of the chat frames QUIET seconds after our whisper to him went (the
-- player typed nothing: a line naming a moderator out of nowhere says nothing to him). With the
-- gamepad UI (the gate's system-filters) none is registered, and one registered before does
-- nothing from its first line: the line shows, as the game's own would.
-- (1.6.0) One line for each whisper of ours (Accord.Tried, from Comm.SendNow): the server answers
-- every whisper to a player who is not online with one line, so as many of his lines stay out as
-- whispers of ours went to him in those seconds, and the next one shows. The player's own whisper
-- to him still says he is gone: Join Olympus's request, sent beside our J3 to the same member
-- (Recruit.Ask), or one typed to a High Councillor whose relay we just pinged. 1.6.0's first build
-- hid every line naming him in those seconds. Each chat window that shows system lines runs the
-- filter for the same line, and the relay's filter asks this one: one answer per line (lastLine).
-- A line is told by its lineID (CHAT_MSG_SYSTEM's eleventh value), else by its text and the frame's
-- time (GetTime is one value through a frame): there two such lines in one frame get one answer,
-- the first one's, which keeps them both out.
function Accord.QuietLine(_, _, text, ...)
	if not ns.Gate.Allowed("system-filters") then return false end
	if next(quiet) == nil then return false end
	local who = NotFoundName(text)
	local q = who and quiet[who]
	if not q then return false end
	local now = Mono()
	local lineID = select(10, ...)
	if Secret(lineID) or type(lineID) ~= "number" or lineID <= 0 then lineID = nil end
	local key = lineID and ("#" .. lineID) or (text .. "\n" .. tostring(now))
	if lastLine.key == key then return lastLine.hide end
	local live = now <= q.untilAt
	local hide = live and q.left > 0
	if hide then
		q.left = q.left - 1
		stats.quieted = stats.quieted + 1
	elseif live then
		stats.passed = stats.passed + 1
	end
	lastLine.key, lastLine.hide = key, hide
	return hide
end
-- (1.6.0) A whisper to `name` the game is being handed now (Comm.SendNow, before its call: a refused
-- whisper's line comes during it): one more of his lines kept out, QUIET seconds from now. n = -1:
-- the call sent nothing after all (a throttle, an error), and that line never comes.
function Accord.Tried(name, n)
	if type(name) ~= "string" or name == "" then return end
	n = n or 1
	local now = Mono()
	local tell, shown = ns.TellName(name), ns.DisplayName(name)
	tell = type(tell) == "string" and tell ~= "" and tell:lower() or nil
	shown = type(shown) == "string" and shown ~= "" and shown:lower() or nil
	local q = (tell and quiet[tell]) or (shown and quiet[shown])
	if q and q.untilAt < now then q = nil end -- (an old mark's whispers are long answered)
	if n < 0 then
		if q then q.left = math.max(0, q.left + n) end
		return
	end
	if not (tell or shown) then return end
	q = q or { left = 0 }
	q.left, q.untilAt = q.left + n, now + Accord.QUIET
	if tell then quiet[tell] = q end
	if shown then quiet[shown] = q end
	Accord.Quiet(name) -- (the old marks go, and the filter is registered the first time)
end
-- The filter, registered the first time a whisper may need it (1.6.0: it opens no window itself;
-- Comm.SendNow counts the whisper when the game is handed it, Accord.Tried).
function Accord.Quiet(name)
	local now = Mono()
	for who, q in pairs(quiet) do if q.untilAt < now then quiet[who] = nil end end
	if filtering or not ns.Gate.Allowed("system-filters") then return end
	-- (The global, as FarkleTable's filter: every supported client has it, and Forever's
	-- ChatFrameUtil has no AddMessageEventFilter; that one only where the global is gone.)
	local add = rawget(_G, "ChatFrame_AddMessageEventFilter") -- gp:system-filters
	if type(add) ~= "function" then
		local U = rawget(_G, "ChatFrameUtil") -- gp:system-filters
		add = type(U) == "table" and rawget(U, "AddMessageEventFilter") or nil -- gp:system-filters
	end
	if type(add) ~= "function" then return end
	filtering = true
	pcall(add, "CHAT_MSG_SYSTEM", Accord.QuietLine) -- gp:system-filters
end

-- Our tag to one team member, now: only while we are a member, he is still in the team (at our
-- level or higher, MayTell) and our tag reads the same at the game's send (the permit), logged
-- (the server keeps it).
function Accord.SendTag(name)
	local tag = Accord.ReadTag()
	if not tag or not ns.IsMember() or not MayTell(name) then return false end
	local C = ns.Comm
	if not (C and C.Whisper) or (C.QueueRoom and C.QueueRoom() < 1) then return false end
	local msg = Wire(tag)
	if not msg then return false end
	local guardKey = "accord-tag:" .. ns.Fold(name)
	Accord.Quiet(name) -- (the filter; 1.6.0: Comm.SendNow counts the whisper when it really goes)
	return C.Whisper(name, msg, guardKey, false, true, function(sent)
		if sent then RecordTold(name) end
	end,
		{ owner = Accord, key = guardKey, permit = function(owner, key, dist, to, payload)
			if owner ~= Accord or key ~= guardKey or dist ~= "WHISPER" or payload ~= msg or ns.Fold(ns.FullName(ns.Normal(to))) ~= ns.Fold(name) then
				return false, "guard"
			end
			if not ns.IsMember() or not MayTell(name) or Accord.ReadTag() ~= tag then return false, "revoked" end
			return true
		end }) ~= false
end

-- After a random delay, unless this character told him within TELL_EVERY (force: whenever), one
-- already waits, or no tag can be read. The server saying meanwhile that he is not online drops
-- it (NotFound).
Tell = function(name, force)
	if type(name) ~= "string" or name == "" or not ns.IsMember() then return false end
	local key = ns.Fold(name)
	if pending[key] then return false end
	local t = Told()
	if not force and t and ns.Now() - (tonumber(t[ToldKey(name)]) or -math.huge) < Accord.TELL_EVERY then return false end
	if not Accord.ReadTag() then return false end
	local entry = { name = name }
	pending[key] = entry
	WatchNotFound()
	ns.After(Accord.random(Accord.DELAY_MIN, Accord.DELAY_MAX), "olympus accord tell", function()
		if pending[key] ~= entry then return end
		pending[key] = nil
		Accord.SendTag(name)
	end)
	return true
end
Accord.Tell = function(name, force) return Tell(name, force) end

local function Remember(name)
	askers[ns.Fold(name)] = { name = name, at = Mono() }
	local n, oldest, oldAt = 0, nil, nil
	for k, e in pairs(askers) do
		n = n + 1
		if not oldAt or e.at < oldAt then oldest, oldAt = k, e.at end
	end
	if n > Accord.ASKERS_MAX and oldest then askers[oldest] = nil end
end

-- BQ, heard on the channel (Comm dispatches it to members alone): from a team member, answered.
function Accord.HandleAsk(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or not (text == "BQ~1" or text:match("^BQ~1~")) then
		stats.refused = stats.refused + 1
		return false, "shape"
	end
	sender = ns.FullName(ns.Normal(sender))
	if not TeamName(sender) then
		stats.askNotTeam = stats.askNotTeam + 1
		return false, "team"
	end
	if not MayTell(sender) then
		stats.lower = stats.lower + 1
		return false, "level"
	end
	stats.heard = stats.heard + 1
	Remember(sender)
	Tell(sender, false)
	return true
end

---------------------------------------------------------------------------
-- The team's side: asking, and keeping what comes back
---------------------------------------------------------------------------

local function Store(make)
	local r = ns.rdb
	if type(r) ~= "table" then return nil end
	local s = r.battletags
	if type(s) ~= "table" or type(s.rows) ~= "table" then
		if not make then return nil end
		s = { v = 1, rows = {} }
		r.battletags = s
	end
	return s
end

-- A team member's client keeps when it was last on the team, as whom, and whether that one named
-- moderators (the author, the King, a councillor): Guard's facts.
local function OnTeam(s)
	s.teamAt, s.teamChar = ns.Now(), ns.Fold(ns.me or "")
	local w = WC()
	s.namer = w ~= nil and type(w.NamerLevel) == "function" and (tonumber(w.NamerLevel(ns.me)) or 0) > 0 or nil
end

-- The ask, on the channel. Its time is saved (s.asked, the server's clock), so the answers to it
-- are still taken after a /reload (they come up to DELAY_MAX later).
function Accord.AskTeam()
	if not Accord.TeamMember() then return false end
	local C = ns.Comm
	if not (C and C.ChannelName and C.ChannelName()) then return false end
	local s = Store(true)
	if not s then return false end
	OnTeam(s)
	s.asked = ns.Now()
	stats.asks = stats.asks + 1
	return C.Send("CHANNEL", "BQ~1", "accord ask") ~= false
end

-- Drops what is past KEEP, then the oldest over ROWS_MAX.
function Accord.Prune()
	local s = Store(false)
	if not s then return end
	local now, list = ns.Now(), {}
	for k, r in pairs(s.rows) do
		if type(r) ~= "table" or type(r.tag) ~= "string" or type(r.name) ~= "string" or now - (tonumber(r.last) or 0) > Accord.KEEP then
			s.rows[k] = nil
		else
			-- (Its code for the follows, TagFollow.lua: made again from the tag and key when it is not
			-- one; a key not of the shape is no key. r.h was a test build's code without a key.)
			r.h = nil
			if r.key ~= nil and not Accord.IsKey(r.key) then r.key = nil end
			if r.key == nil then r.code = nil end
			if r.code ~= nil and not (type(r.code) == "string" and #r.code == 16 and r.code:find("^[0-9a-f]+$")) then r.code = nil end
			if r.pcode ~= nil and not (type(r.pcode) == "string" and #r.pcode == 16 and r.pcode:find("^[0-9a-f]+$")) then r.pcode = nil end
			list[#list + 1] = { k = k, last = tonumber(r.last) or 0 }
		end
	end
	local T = TF()
	if T and T.Bump then T.Bump() end
	if #list <= Accord.ROWS_MAX then return end
	table.sort(list, function(x, y) return x.last < y.last end)
	for i = 1, #list - Accord.ROWS_MAX do s.rows[list[i].k] = nil end
end

-- (TagFollow.lua) A row's code: its tag and its game account's follow key (none without a key),
-- kept with it (row.code) once made.
local function RowOf(name)
	local s = Store(false)
	if not s or type(name) ~= "string" or name == "" then return nil end
	local row = s.rows[ns.Fold(ns.FullName(ns.Normal(name)))]
	return type(row) == "table" and type(row.tag) == "string" and row or nil
end
local function RowHash(row)
	if not Accord.IsKey(row.key) then return nil end
	if type(row.code) == "string" and #row.code == 16 and row.code:find("^[0-9a-f]+$") then return row.code end
	local T = TF()
	row.code = T and T.Hash and T.Hash(row.tag, row.key) or nil
	return row.code
end

-- How the sender's guild is known: "roster" (ours: the server's roster), "claim" (his own Olympus
-- messages spoke for it, Data.ClaimGuild), "self" (his word alone), as Watch's council reports.
local function Via(sender, guild)
	local R = ns.Roster
	if R and R.RankOf and R.RankOf(sender) ~= nil then return "roster", GetGuildInfo("player") or guild end
	local D = ns.Data
	local claimed = D and D.ClaimedGuild and D.ClaimedGuild(sender)
	if type(claimed) == "string" and claimed:lower() == guild:lower() then return "claim", guild end
	return "self", guild
end

-- BT, a logged whisper: kept on a team member's client that asked lately. True when kept; false
-- and why not.
function Accord.HandleTag(dist, sender, text)
	local function No(why)
		stats.refused = stats.refused + 1
		return false, why
	end
	if dist ~= "WHISPER" then return No("dist") end
	local C = ns.Comm
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and C and C.DeliveredLogged and not C.DeliveredLogged() then return No("unlogged") end
	if not Accord.TeamMember() then return No("team") end
	local asked = Store(false)
	asked = asked and tonumber(asked.asked)
	if not asked or ns.Now() - asked > Accord.TAKE_WINDOW or asked > ns.Now() + 60 then return No("unasked") end
	if type(text) ~= "string" or #text > 255 then return No("shape") end
	-- (The follow key last; an answer of an earlier build has none: kept, and nothing follows it.)
	local av, aat, guild, tag, fkey = text:match("^BT~1~(%d+)~(%d+)~([^~]*)~([^~]+)~([^~]+)$")
	if not av then av, aat, guild, tag = text:match("^BT~1~(%d+)~(%d+)~([^~]*)~([^~]+)$") end
	if not av or #tag > Accord.TAG_MAX or not tag:match(Accord.TAG_SHAPE) then return No("shape") end
	if fkey ~= nil and not Accord.IsKey(fkey) then return No("shape") end
	if not ns.IsFederation(guild) then return No("guild") end
	sender = ns.FullName(ns.Normal(sender))
	if type(sender) ~= "string" or sender == "" then return No("shape") end
	local s = Store(true)
	if not s then return No("store") end
	OnTeam(s)
	local rk, now = ns.Fold(sender), ns.Now()
	local row = s.rows[rk]
	local same = type(row) == "table" and type(row.tag) == "string" and ns.Fold(row.tag) == ns.Fold(tag)
	if same and row.key == fkey and now - (tonumber(row.last) or 0) < Accord.TAKE_GAP then return No("rate") end
	local via, shownGuild = Via(sender, guild)
	local prev = type(row) == "table" and (same and row.prev or row.tag) or nil
	-- (TagFollow.lua: the code he had before, while his tag or key changed: its follows go to the new one.)
	local old = type(row) == "table" and RowHash(row) or nil
	local new = { name = sender, tag = tag, key = fkey, guild = shownGuild, first = type(row) == "table" and row.first or now, last = now,
		av = tonumber(av), aat = tonumber(aat), via = via, prev = prev }
	local code = RowHash(new)
	new.pcode = old and old ~= code and old or (type(row) == "table" and row.pcode or nil)
	if new.pcode == code then new.pcode = nil end
	s.rows[rk] = new
	Accord.Prune()
	stats.kept = stats.kept + 1
	ns.Log("olympus accord: a BattleTag from %s kept (%s)", sender, via) -- (never the tag)
	-- (TagFollow.lua: its code kept with it; a sanction on him, or on the tag he had before, follows it.)
	local T = TF()
	if T and T.OnTag and s.rows[rk] then ns.SafeCall("tag follow", T.OnTag, sender, s.rows[rk]) end
	ns.Fire("ACCORD_TEAM_CHANGED")
	return true
end

-- Off the moderation team, this client's BattleTags go (the whole store): at once when the
-- character that was on it now has its powers barred by a sanction (WatchChat.Barred) or, one that
-- named moderators, lost that seat (a signed list without him); else once no character of this
-- account was on the team for TEAM_GRACE (a namer's list lapses after LIST_FRESH unheard, and an
-- alt is played a while). At login (GUARD_FIRST later) and every GUARD_EVERY. True when wiped.
function Accord.Guard()
	local s = Store(false)
	if not s then return false end
	if Accord.TeamMember() then
		OnTeam(s)
		return false
	end
	local now, w = ns.Now(), WC()
	if tonumber(s.teamAt) == nil then s.teamAt = now end
	local same = type(s.teamChar) == "string" and s.teamChar == ns.Fold(ns.me or "")
	local barred = same and w ~= nil and type(w.Barred) == "function" and w.Barred("powers") ~= nil
	local unseated = same and s.namer == true and w ~= nil and type(w.NamerLevel) == "function" and (tonumber(w.NamerLevel(ns.me)) or 0) == 0
	local why = barred and "sanction" or unseated and "seat" or now - s.teamAt > Accord.TEAM_GRACE and "lapsed" or nil
	if not why then return false end
	-- (TagFollow.lua: only this account's own follows stay, without their code.)
	local T = TF()
	if T and T.DropTeam then ns.SafeCall("tag follow", T.DropTeam) end
	ns.rdb.battletags = nil
	stats.wiped = stats.wiped + 1
	ns.Log("olympus accord: off the moderation team (%s), its BattleTags dropped", why)
	ns.Fire("ACCORD_TEAM_CHANGED")
	return true
end

-- `/oly accord forget <name>` on a team client: that player's BattleTag (every character sharing
-- it, and where it was the one before) dropped here, as its player asked. True and how many.
function Accord.Forget(name)
	if not Accord.TeamShown() then return false, "team" end
	local s = Store(false)
	local row = s and type(name) == "string" and name:match("%S") and s.rows[ns.Fold(ns.FullName(ns.Normal(name)))]
	if type(row) ~= "table" or type(row.tag) ~= "string" then return false, "none" end
	local tag, n, codes = ns.Fold(row.tag), 0, {}
	for k, r in pairs(s.rows) do
		if type(r) == "table" and type(r.tag) == "string" and ns.Fold(r.tag) == tag then
			local code = RowHash(r)
			if code then codes[code] = true end
			if type(r.pcode) == "string" then codes[r.pcode] = true end
			s.rows[k] = nil
			n = n + 1
		elseif type(r) == "table" and type(r.prev) == "string" and ns.Fold(r.prev) == tag then
			if type(r.pcode) == "string" then codes[r.pcode] = true end
			r.prev, r.pcode = nil, nil
		end
	end
	ns.Log("olympus accord: a BattleTag dropped on request (%d characters)", n) -- (never the tag)
	-- (TagFollow.lua: the follows that carry its code go too, so this client stops repeating it.)
	local T = TF()
	if T and T.Forget then ns.SafeCall("tag follow forget", T.Forget, codes) end
	if T and T.Bump then T.Bump() end
	ns.Fire("ACCORD_TEAM_CHANGED")
	return true, n
end

-- (TagFollow.lua) A team client's kept BattleTag for `name`, its code, and the rows of one code:
-- the characters of one game account, as this client knows them. Nothing on any other client.
-- Read from the store itself, never through TeamMember (WatchChat asks TagFollow, which asks this).
function Accord.TagOf(name)
	local row = RowOf(name)
	return row and row.tag or nil
end
function Accord.HashOf(name)
	local row = RowOf(name)
	return row and RowHash(row) or nil
end
function Accord.Rows(hash)
	local s, out = Store(false), {}
	if not s or type(hash) ~= "string" then return out end
	for _, r in pairs(s.rows) do
		if type(r) == "table" and type(r.tag) == "string" and type(r.name) == "string" and RowHash(r) == hash then out[#out + 1] = r end
	end
	table.sort(out, function(x, y) return tostring(x.name) < tostring(y.name) end)
	return out
end
-- The code `name` had before his tag or key changed, or nil.
function Accord.PrevHashOf(name)
	local row = RowOf(name)
	return row and type(row.pcode) == "string" and row.pcode or nil
end
-- Every code made of `tag` here (one per game account that sent it), sorted.
function Accord.CodesOf(tag)
	local s, out, seen = Store(false), {}, {}
	if not s or type(tag) ~= "string" then return out end
	local want = ns.Fold(tag)
	for _, r in pairs(s.rows) do
		if type(r) == "table" and type(r.tag) == "string" and type(r.name) == "string" and ns.Fold(r.tag) == want then
			local code = RowHash(r)
			if code and not seen[code] then seen[code], out[#out + 1] = true, code end
		end
	end
	table.sort(out)
	return out
end

function Accord.Count()
	local s, n = Store(false), 0
	if s then for _ in pairs(s.rows) do n = n + 1 end end
	return n
end

-- The validated sample of the census (CensusStats.PeopleEstimate): of the rows whose guild is one
-- of `counted` ({ [guild lower case] = true }), how many characters and how many distinct
-- BattleTags (accounts). Two numbers, never a tag or a name; nothing off the team's page.
function Accord.Sample(counted)
	local s, characters, accounts, seen = Store(false), 0, 0, {}
	if not s or not Accord.TeamShown() or type(counted) ~= "table" then return 0, 0 end
	for _, r in pairs(s.rows) do
		if type(r) == "table" and type(r.tag) == "string" and type(r.guild) == "string" and counted[r.guild:lower()] then
			characters = characters + 1
			local k = ns.Fold(r.tag)
			if not seen[k] then seen[k], accounts = true, accounts + 1 end
		end
	end
	return characters, accounts
end

-- The rows grouped by tag (one player's characters), the most characters first, then the newest.
function Accord.Groups()
	local s, groups, byTag = Store(false), {}, {}
	if not s then return groups end
	for _, r in pairs(s.rows) do
		if type(r) == "table" and type(r.tag) == "string" then
			local k = ns.Fold(r.tag)
			local g = byTag[k]
			if not g then
				g = { tag = r.tag, rows = {}, last = 0 }
				byTag[k], groups[#groups + 1] = g, g
			end
			g.rows[#g.rows + 1] = r
			g.last = math.max(g.last, tonumber(r.last) or 0)
		end
	end
	for _, g in ipairs(groups) do
		table.sort(g.rows, function(x, y)
			if (x.last or 0) ~= (y.last or 0) then return (x.last or 0) > (y.last or 0) end
			return tostring(x.name) < tostring(y.name)
		end)
	end
	table.sort(groups, function(x, y)
		if #x.rows ~= #y.rows then return #x.rows > #y.rows end
		if x.last ~= y.last then return x.last > y.last end
		return ns.Fold(x.tag) < ns.Fold(y.tag)
	end)
	return groups
end

local VIA = { roster = "ACCORD_TEAM_VIA_ROSTER", claim = "ACCORD_TEAM_VIA_CLAIM", self = "ACCORD_TEAM_UNVERIFIED" }

-- The Watch's BattleTags page (Watch.lua): nothing on a client that is not the team's.
function Accord.TeamLines()
	if not Accord.TeamShown() then return {} end
	local groups = Accord.Groups()
	local lines = {
		{ id = "accord-team", header = true, text = L.ACCORD_TEAM_TITLE, right = Grey(Accord.Count()) },
		{ text = Grey(L.ACCORD_TEAM_SCOPE), wrap = true, gapAfter = #groups == 0 or Stream() },
	}
	if #groups == 0 then
		lines[#lines + 1] = { text = Grey(L.ACCORD_TEAM_EMPTY), wrap = true }
		return lines
	end
	-- The digits, for REVEAL seconds (never on the King's screen).
	if not Stream() then
		lines[#lines + 1] = { id = "accord-team-reveal", text = "|cffffd200" .. (Accord.TeamRevealed() and L.ACCORD_TEAM_HIDE or L.ACCORD_TEAM_SHOW) .. "|r",
			onClick = function() Accord.RevealTeam() end, gapAfter = true }
	end
	local masked = ns.CouncilMasked()
	local W = ns.Watch
	local T = TF()
	for i, g in ipairs(groups) do
		if i > Accord.SHOWN_MAX then break end
		local n = #g.rows
		lines[#lines + 1] = { text = Accord.ShownTag(g.tag, i), right = Grey(n == 1 and L.ACCORD_TEAM_ONE or L.ACCORD_TEAM_SHARED:format(n)) }
		-- (TagFollow.lua: the sanctions that follow this BattleTag, a click stops one; on a disputed one,
		-- each sanction not followed, a click follows it.)
		for _, l in ipairs(T and T.GroupLines and T.GroupLines(g, ShownName) or {}) do lines[#lines + 1] = l end
		for _, r in ipairs(g.rows) do
			local name = r.name
			local open = type(W) == "table" and not W.missing and type(W.CanRead) == "function" and W.CanRead() == true
				and type(W.OpenMember) == "function"
			local note, noteTip
			if T and T.RowNote then note, noteTip = T.RowNote(name) end
			lines[#lines + 1] = {
				indent = 1, text = L.ACCORD_TEAM_ROW:format(ShownName(name), masked and "?" or tostring(r.guild or "?")) .. (note or ""),
				right = Grey(L.ACCORD_TEAM_LAST:format(ns.Ago(r.last))),
				tooltip = function(tt)
					tt:AddLine(ShownName(name), 1, 0.82, 0)
					tt:AddLine(rawget(L, VIA[r.via] or "") or L.ACCORD_TEAM_UNVERIFIED, 1, 1, 1, true)
					tt:AddLine(L.ACCORD_TEAM_ACCORD:format(tonumber(r.av) or 0, date("%Y-%m-%d", tonumber(r.aat) or 0)), 0.7, 0.7, 0.7)
					if type(r.prev) == "string" then tt:AddLine(L.ACCORD_TEAM_PREV:format(Accord.ShownTag(r.prev)), 0.7, 0.7, 0.7) end
					if noteTip then tt:AddLine(noteTip, 1, 0.4, 0.4, true) end
				end,
				onClick = open and function() W.OpenMember(name) end or nil,
			}
		end
		lines[#lines].gapAfter = true
	end
	return lines
end

-- The person page's lines in The Watch (Watch.lua's ProfileLines): his tag, the others sharing it.
function Accord.ProfileLines(target)
	if not Accord.TeamShown() or type(target) ~= "string" then return {} end
	local s = Store(false)
	local row = s and s.rows[ns.Fold(ns.FullName(target))]
	if type(row) ~= "table" or type(row.tag) ~= "string" then
		return { { id = "watch-profile-battletag", text = Grey(L.ACCORD_TEAM_PROFILE_NONE) } }
	end
	-- (A click shows the digits a moment, as the BattleTags page's Show; never on the King's screen.)
	local out = { { id = "watch-profile-battletag", text = L.ACCORD_TEAM_PROFILE:format(Accord.ShownTag(row.tag)),
		onClick = not Stream() and function() Accord.RevealTeam() end or nil } }
	local others = {}
	for _, r in pairs(s.rows) do
		if r ~= row and type(r) == "table" and type(r.tag) == "string" and ns.Fold(r.tag) == ns.Fold(row.tag) then others[#others + 1] = ShownName(r.name) end
	end
	table.sort(others)
	if #others > 0 then
		out[#out + 1] = { id = "watch-profile-battletag-also", text = L.ACCORD_TEAM_PROFILE_ALSO:format(table.concat(others, ", ")), wrap = true }
	end
	-- (TagFollow.lua: reached by another character's sanction, or his own follows his BattleTag.)
	local T = TF()
	for _, l in ipairs(T and T.ProfileLines and T.ProfileLines(target, ShownName) or {}) do out[#out + 1] = l end
	return out
end

---------------------------------------------------------------------------
-- The letter
---------------------------------------------------------------------------

local INK = { 0.18, 0.10, 0.02 }
local TITLE_INK = { 0.24, 0.12, 0.03 }
local SUB_INK = { 0.35, 0.25, 0.12 }
local HEAD_INK = { 0.40, 0.12, 0.04 }
local BOLD_INK = { 0.36, 0.06, 0.02 }
local WARN = "|cff8c1a0a"

local function Font(title)
	if title then return _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge" end
	return _G.QuestFont and "QuestFont" or "GameFontHighlight"
end
-- A font string's size: px exactly (exact), or at least px.
local function Px(fs, px, exact)
	if not (fs and fs.GetFont and fs.SetFont) then return end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and type(path) == "string" and type(size) == "number" and (size < px or (exact and size ~= px)) then fs:SetFont(path, px, flags) end
end
local function Ink(fs, c) if fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end end
-- Bold on parchment: a deep red ink, and its shadow one pixel to the right in the same ink (the
-- strokes doubled; the game's fonts have no bold face an addon can pick).
local function Bold(fs)
	Ink(fs, BOLD_INK)
	if fs.SetShadowColor then fs:SetShadowColor(BOLD_INK[1], BOLD_INK[2], BOLD_INK[3], 1) end
	if fs.SetShadowOffset then fs:SetShadowOffset(1, 0) end
end
local function Text(parent, title, px, exact, color)
	local fs = parent:CreateFontString(nil, "ARTWORK", Font(title))
	Px(fs, px, exact)
	Ink(fs, color or INK)
	fs:SetJustifyH("LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(true) end
	return fs
end
local function Height(fs, width)
	if fs.GetStringHeight then
		local h = fs:GetStringHeight()
		if type(h) == "number" and h > 0 then return h end
	end
	-- (No measure: about 6 pixels a letter, 15 a line.)
	local per = math.max(1, math.floor(width / 6))
	return math.max(1, math.ceil(#(fs:GetText() or "") / per)) * 15
end
local function Button(parent, label, w, h, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, h)
	b:SetText(label)
	b:SetScript("OnClick", function() ns.SafeCall("olympus accord", fn) end)
	return b
end

local PAGE_W, TEXT_X = 484, 16
-- The bottom: the footer's lowest line FOOTER_Y up; the band BAND_GAP above the footer's top (at
-- least BAND_Y), BAND_H tall at least and taller for a note of two lines; the words above it.
local FOOTER_Y, FOOTER_W, BAND_Y, BAND_GAP, BAND_H, NOTE_W = 62, Accord.WIDTH - 80, 86, 10, 44, Accord.WIDTH - 56 - 46 - 110

-- The body's words, in the topics' order (built once): the opening, then each topic's heading
-- and its bullets (a dot, its text beside it).
local function Body(f)
	local child = f.bodyChild
	f.parts = {}
	local function Add(kind, fs, x, gap, width, bold) f.parts[#f.parts + 1] = { kind = kind, fs = fs, x = x, gap = gap, width = width, bold = bold } end
	local opening = Text(child, false, 13)
	opening:SetText(L.ACCORD_OPENING)
	Add("block", opening, 0, 0, PAGE_W)
	for _, t in ipairs(Accord.TOPICS) do
		local head = Text(child, true, 15, true, HEAD_INK)
		head:SetText(L["ACCORD_T" .. t[1] .. "_HEAD"])
		Add("block", head, 0, 10, PAGE_W)
		for i = 1, t[2] do
			local dot = Text(child, false, 13)
			dot:SetText("·")
			Add("dot", dot, 4, 4, 10)
			local line = Text(child, false, 13)
			line:SetText(L["ACCORD_T" .. t[1] .. "_" .. i])
			local bold = Accord.BOLD[t[1] .. "_" .. i] == true
			if bold then Bold(line); Bold(dot) end
			Add("bullet", line, TEXT_X, 0, PAGE_W - TEXT_X, bold or nil)
		end
	end
end

-- Lays the body out: each part under the one before, a bullet's text beside its dot.
local function LayoutBody(f)
	local y, top = 0, 0
	for _, p in ipairs(f.parts) do
		p.fs:ClearAllPoints()
		p.fs:SetWidth(p.width)
		if p.kind ~= "bullet" then top = y + (p.gap or 0) end
		p.fs:SetPoint("TOPLEFT", f.bodyChild, "TOPLEFT", p.x, -top)
		if p.kind ~= "dot" then y = top + Height(p.fs, p.width) end
	end
	f.bodyChild:SetSize(PAGE_W, math.max(1, y + 4))
end

-- The tag as the letter shows it: its digits hidden unless revealed; on the King's screen no part
-- of it (a short name cut to four letters is still the whole name), never revealed.
function Accord.LetterTag(tag, revealed)
	if type(tag) ~= "string" then return nil end
	local name = tag:match("^(.-)#%d+$") or tag
	if Stream() then return "****#****" end
	if revealed then return tag end
	return name .. "#****"
end

local function Make()
	local f = ns.Window("OlympusAccordFrame", UIParent, { title = L.TITLE, inset = false, close = false, escape = false })
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetWidth(Accord.WIDTH)
	-- The parchment over the inside (the writ's own ground, Acts.lua).
	local paper = f:CreateTexture(nil, "BACKGROUND")
	paper:SetPoint("TOPLEFT", f.inner[1], f.inner[2])
	paper:SetPoint("BOTTOMRIGHT", f.inner[3], f.inner[4])
	local UI = ns.UI
	local function First(paths) return UI and UI.FirstTexture and UI.FirstTexture(paths) or paths[#paths] end
	local file = First(UI and UI.PARCHMENTS or { "Interface\\QuestFrame\\QuestBG" })
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		paper:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		paper:SetTexture(file)
		if file:find("QuestBG", 1, true) then paper:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	f.paper = paper
	f.title = f:CreateFontString(nil, "ARTWORK", Font(true))
	Px(f.title, 24)
	Ink(f.title, TITLE_INK)
	f.title:SetPoint("TOP", 0, -38)
	f.title:SetText(L.ACCORD_NAME)
	f.sub = f:CreateFontString(nil, "ARTWORK", Font(false))
	Ink(f.sub, SUB_INK)
	f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetColorTexture(0.25, 0.13, 0.04, 0.45)
	rule:SetPoint("TOPLEFT", 40, -96)
	rule:SetPoint("TOPRIGHT", -40, -96)
	rule:SetHeight(1)
	-- The words scroll (with the mouse wheel too); everything else stays where it is.
	f.body = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.body:SetPoint("TOPLEFT", 28, -104)
	f.body:SetPoint("BOTTOMRIGHT", -40, 134)
	f.bodyChild = CreateFrame("Frame", nil, f.body)
	f.bodyChild:SetSize(PAGE_W, 1)
	f.body:SetScrollChild(f.bodyChild)
	if f.body.EnableMouseWheel then f.body:EnableMouseWheel(true) end
	f.body:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local current = self.GetVerticalScroll and self:GetVerticalScroll() or 0
		self:SetVerticalScroll(math.max(0, math.min(range, current - (delta or 0) * 36)))
	end)
	Body(f)
	-- The BattleTag's band, always in sight.
	f.band = f:CreateTexture(nil, "BORDER")
	f.band:SetColorTexture(0.55, 0.42, 0.25, 0.18)
	f.band:SetPoint("BOTTOMLEFT", 28, 86)
	f.band:SetPoint("BOTTOMRIGHT", -28, 86)
	f.band:SetHeight(44)
	f.seal = f:CreateTexture(nil, "ARTWORK")
	f.seal:SetSize(32, 32)
	f.seal:SetPoint("BOTTOMLEFT", 34, 92)
	f.seal:SetTexture(First({ "Interface\\Icons\\Spell_Holy_SealOfWrath", "Interface\\Icons\\Spell_Holy_SealOfMight" }))
	f.tagLabel = Text(f, false, 13)
	f.tagLabel:SetPoint("TOPLEFT", f.band, "TOPLEFT", 46, -5)
	f.tagLabel:SetText(L.ACCORD_TAG_LABEL)
	f.tag = Text(f, true, 15, true, TITLE_INK)
	f.tag:SetPoint("LEFT", f.tagLabel, "RIGHT", 6, 0)
	-- (Under the label, its own lines: the band grows with it, Accord.Refresh.)
	f.tagNote = Text(f, false, 12, true)
	f.tagNote:SetPoint("TOPLEFT", f.tagLabel, "BOTTOMLEFT", 0, -3)
	f.tagNote:SetWidth(NOTE_W)
	f.reveal = Button(f, L.ACCORD_TAG_SHOW, 70, 20, function()
		session.revealUntil = session.revealUntil > Mono() and 0 or Mono() + Accord.REVEAL
		Accord.Refresh(false)
	end)
	f.reveal:SetPoint("RIGHT", f.band, "RIGHT", -8, 0)
	f.retry = Button(f, L.ACCORD_TAG_RETRY, 100, 20, function() Accord.Refresh(true) end)
	f.retry:SetPoint("RIGHT", f.band, "RIGHT", -8, 0)
	-- The version and its date, a line, then the two answers (the conservative one on the left).
	f.footer = Text(f, false, 12, true, SUB_INK)
	f.footer:SetJustifyH("CENTER")
	f.footer:SetPoint("BOTTOM", 0, FOOTER_Y)
	f.footer:SetWidth(FOOTER_W)
	local low = f:CreateTexture(nil, "BORDER")
	low:SetColorTexture(0.25, 0.13, 0.04, 0.45)
	low:SetPoint("BOTTOMLEFT", 40, 54)
	low:SetPoint("BOTTOMRIGHT", -40, 54)
	low:SetHeight(1)
	f.notNow = Button(f, L.ACCORD_NOT_NOW, 170, 26, function() Accord.NotNow() end)
	f.notNow:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 18)
	f.accept = Button(f, L.ACCORD_ACCEPT, 170, 26, function()
		if not f.acceptEnabled then return end
		Accord.Accept()
	end)
	f.accept:SetPoint("BOTTOMLEFT", f, "BOTTOM", 8, 18)
	f.close = Button(f, L.ACCORD_CLOSE, 170, 26, function() f:Hide() end)
	f.close:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
	-- Battle.net coming back, a reveal running out: the letter follows, once a second.
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 1 then return end
		elapsed = 0
		ns.SafeCall("olympus accord", Accord.Refresh, false)
	end)
	f:Hide()
	-- Closed (Accept, Not now, Close), not hidden with the whole interface (Alt+Z: it still says
	-- shown): the privacy page and the version letter may come after (Consent.lua's rule).
	f:HookScript("OnHide", function(self) if not self:IsShown() then ns.Fire("ACCORD_CLOSED") end end)
	return f
end

-- Lays the letter out again: its size for the screen, the tag (read again every READ_GAP, or now
-- when `read`), the answers.
function Accord.Refresh(read)
	local f = frame
	if not f then return end
	local now = Mono()
	if read or now - session.lastRead >= Accord.READ_GAP then
		session.lastRead = now
		f.tagValue, f.tagWhy = Accord.ReadTag()
	end
	local screenH = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
	if type(screenH) ~= "number" or screenH <= 0 then screenH = 768 end
	f:SetSize(Accord.WIDTH, math.max(320, math.min(Accord.HEIGHT, screenH - Accord.SCREEN_MARGIN)))
	f.sub:SetText(L.ACCORD_SUBTITLE:format(ns.ACCORD_VERSION))
	LayoutBody(f)
	local accepted = ns.AccordAccepted()
	local tag, why = f.tagValue, f.tagWhy
	local stream = Stream()
	local revealed = not stream and session.revealUntil > now
	f.tag:SetText(tag and Accord.LetterTag(tag, revealed) or "-")
	if tag then
		f.tagNote:SetText(stream and L.ACCORD_TAG_HIDDEN_STREAM or L.ACCORD_TAG_TO)
		Ink(f.tagNote, INK)
	else
		f.tagNote:SetText(WARN .. (why == "offline" and L.ACCORD_TAG_WAIT or L.ACCORD_TAG_NONE) .. "|r")
	end
	f.reveal:SetText(revealed and L.ACCORD_TAG_HIDE or L.ACCORD_TAG_SHOW)
	f.reveal:SetShown(tag ~= nil and not stream)
	f.retry:SetShown(tag == nil and why == "offline")
	local a = Saved()
	local footer = L.ACCORD_FOOTER:format(ns.ACCORD_VERSION, L.ACCORD_DATE)
	if accepted and a and tonumber(a.at) then footer = footer .. "  ·  " .. L.ACCORD_ACCEPTED_ON:format(date("%Y-%m-%d", a.at)) end
	f.acceptEnabled = not accepted and tag ~= nil
	if not accepted and not tag then footer = footer .. "  ·  " .. WARN .. L.ACCORD_ACCEPT_WAIT_TIP .. "|r" end
	f.footer:SetText(footer)
	Accord.LayoutBottom(f)
	f.accept:SetEnabled(f.acceptEnabled)
	f.accept:SetShown(not accepted)
	f.notNow:SetShown(not accepted)
	f.close:SetShown(accepted)
end

-- The band and the words' bottom edge for what they hold now: a two-line note or footer never
-- runs over the label, the band or the last words.
function Accord.LayoutBottom(f)
	local footerTop = FOOTER_Y + Height(f.footer, FOOTER_W)
	local bandY = math.max(BAND_Y, math.ceil(footerTop + BAND_GAP))
	local bandH = math.max(BAND_H, math.ceil(5 + Height(f.tagLabel, 120) + 3 + Height(f.tagNote, NOTE_W) + 5))
	f.band:ClearAllPoints()
	f.band:SetPoint("BOTTOMLEFT", 28, bandY)
	f.band:SetPoint("BOTTOMRIGHT", -28, bandY)
	f.band:SetHeight(bandH)
	f.seal:ClearAllPoints()
	f.seal:SetPoint("BOTTOMLEFT", 34, bandY + math.floor((bandH - 32) / 2))
	f.body:ClearAllPoints()
	f.body:SetPoint("TOPLEFT", 28, -104)
	f.body:SetPoint("BOTTOMRIGHT", -40, bandY + bandH + 4)
	f.bandY, f.bandH = bandY, bandH
end

-- The letter, accepted or not (/oly accord, and Ask).
function Accord.Show(reason)
	frame = frame or Make()
	session.revealUntil = 0
	frame.reason = reason
	if frame.body.SetVerticalScroll then frame.body:SetVerticalScroll(0) end
	Accord.Refresh(true)
	frame:Show()
	local AH = ns.ArenaHome
	if type(AH) == "table" and not AH.missing and type(AH.FadeIn) == "function" then ns.SafeCall("olympus accord fade", AH.FadeIn, frame) end
	return frame
end
-- /oly accord: the letter; /oly accord forget <name> (a team client): that player's BattleTag
-- dropped here, as he asked; /oly accord follow|unfollow <name> (a team client): that player's
-- sanction follows his BattleTag, or no longer does (TagFollow.lua).
function Accord.Slash(rest)
	local name = type(rest) == "string" and rest:match("^%s*forget%s+(.-)%s*$")
	if name then
		local ok, n = Accord.Forget(name)
		if ok then ns.Print(L.ACCORD_FORGOT:format(n))
		else ns.Print(n == "team" and L.ACCORD_FORGET_TEAM or L.ACCORD_FORGET_NONE:format(name)) end
		return ok
	end
	local verb, who = (type(rest) == "string" and rest or ""):match("^%s*(%a+)%s*(.-)%s*$")
	verb = verb and verb:lower()
	if verb == "follow" or verb == "unfollow" then
		local T = TF()
		if not (T and T.Slash) then ns.Print(L.RESTART_NEEDED) return false end
		return T.Slash(verb, who)
	end
	return Accord.Show("slash")
end
function Accord.Frame() return frame end
function Accord.Hide() if frame then frame:Hide() end end

-- The Olympus window's page while the Accord waits (UI.lua): what is off, and the letter again.
function Accord.LockedLines()
	return {
		{ header = true, text = L.ACCORD_NAME },
		{ text = L.ACCORD_LOCKED_HINT, wrap = true, gapAfter = true },
		{ text = "|cffffd200" .. L.ACCORD_LOCKED_OPEN .. "|r", onClick = function() Accord.Show("window") end },
	}
end

-- For /oly status: never a tag.
function Accord.StatusLine()
	local a = Saved()
	local state
	if ns.AccordAccepted() then state = ("v%d accepted %s"):format(a.v, date("%m-%d %H:%M", tonumber(a.at) or 0))
	elseif a and a.why == "tag" then state = ("v%s asked again (another BattleTag)"):format(tostring(a.v))
	elseif a and a.yes == true then state = ("v%s accepted, v%d waits"):format(tostring(a.v), ns.ACCORD_VERSION)
	else state = ("v%d not accepted%s"):format(ns.ACCORD_VERSION, session.declined and " (not now)" or "") end
	local _, why = Accord.ReadTag()
	local team = Accord.TeamMember() and (" | team: %d characters, %d BattleTags"):format(Accord.Count(), #Accord.Groups()) or ""
	local T = TF()
	local follows = T and T.StatusLine and (" | " .. T.StatusLine()) or ""
	return ("%s | battletag %s%s | asks %d, heard %d, told %d, kept %d, refused %d, not team %d, below %d, gone %d, wiped %d | no-player lines hidden %d, shown %d%s"):format(state,
		why or "readable", team, stats.asks, stats.heard, stats.told, stats.kept, stats.refused, stats.askNotTeam, stats.lower, stats.gone, stats.wiped,
		stats.quieted, stats.passed, follows)
end
function Accord.Stats() return stats end

-- Tests start from a clean session (ns.db.accord, the account's, is theirs to set).
function Accord.Reset()
	session.declined, session.newSaid, session.revealUntil, session.teamRevealUntil, session.lastRead = false, false, 0, 0, -math.huge
	wipe(askers); wipe(pending); wipe(quiet)
	lastLine.key, lastLine.hide = false, false
	watchingNotFound = false -- (each test's own events; the game never resets it)
	for k in pairs(stats) do stats[k] = 0 end
	if frame and rawget(_G, "OlympusAccordFrame") ~= frame then frame = nil elseif frame then frame:Hide() end
end

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------

ns.Comm.Handle("BQ", function(...) Accord.HandleAsk(...) end)
ns.Comm.Handle("BT", function(...) Accord.HandleTag(...) end)

function Accord.OnLogin()
	-- (Each through pcall: a client without one of these events refuses to register it.)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BN_CONNECTED", "BN_DISCONNECTED", "BN_INFO_CHANGED" }) do
		pcall(ns.RegisterEvent, event, function() Accord.Check() end)
	end
	-- (A 1.2.5.1 test build's two-byte fp: its first byte kept, the other one dropped from the file.)
	local a = Saved()
	if a and type(a.fp) == "string" and #a.fp > 2 then a.fp = SavedFp(a) end
	if type(ns.db) == "table" and ns.IsKingCharacter and ns.IsKingCharacter(ns.me) == true then ns.db.kingAccount = true end
	Accord.Prune()
	ns.After(Accord.GUARD_FIRST, "olympus accord guard", Accord.Guard)
	ns.Every(Accord.GUARD_EVERY, "olympus accord guard", Accord.Guard)
	ns.After(Accord.LOGIN_WAIT, "olympus accord", function() Accord.Ask("login") end)
	ns.Every(Accord.RETRY, "olympus accord", function() Accord.Ask("login") end)
	ns.After(Accord.ASK_FIRST, "olympus accord team", Accord.AskTeam)
	ns.Every(Accord.ASK_EVERY, "olympus accord team", Accord.AskTeam)
end
ns.On("LOGIN", function() Accord.OnLogin() end)
