local ADDON, ns = ...
local L = ns.L

-- The Olympus API for other addons (1.2.4, Daniel: an API inside the addon "for anyone to integrate
-- with what can be integrated, with what the permissions allow", each seeing only what that player
-- sees; his worry, someone using it to mine data). docs/API.md is its page for addon authors.
--
-- What it is, and what it never is:
--   - Read-only data. Nothing here sends a chat line, a decree, a whisper or any message for the
--     player, nor changes Olympus data. A registered addon may also contribute one page to the
--     Olympus window; Olympus still owns that window and the page's lifecycle.
--   - Only what this player already sees on Olympus's own pages, at no more detail: the Wanted list
--     and its bounties (the Wanted tab's rows), the public rankings (the Slayers boards of the Wanted
--     tab and the signed top three, the donors' top three while the King shows the army the
--     Treasury's ranking (Donors below), the Church's public top three, and each game's ranking the
--     King made public: never a staff view), the player's own frame and title, and his own Olympus
--     guild, rank and role. Never the census, another player's private data, a location (the
--     Wanted page's victims and sightings stay on the page), a GUID of an Olympus member, a
--     timestamp of anyone's activity, nor a secret (a key, the sealed channel's name, a signature,
--     a private list). Each row is built here field by field from those pages' own functions, so
--     what a module adds to its tables later never reaches an addon by itself.
--   - Asked, one addon at a time. OlympusAPI.Register("TheirAddon") gives that addon its handle and
--     a line of its own on the privacy page (Consent.lua): explicit, so nothing comes back before
--     its own Yes or the page's clearly labelled Authorize all. The page opens by itself for it once
--     (Consent.Ask). Nothing comes back before
--     the player's Yes, nor after his No; the answer is kept for the account (ns.db.apiAddons) and
--     asked again when what the API gives changes (API.CONSENT_VERSION). Outside an Olympus guild a
--     granted addon learns that the player is in none, and nothing else.
--   - Copies. Every table returned (and each callback's) is built fresh for that call: an addon that
--     changes it changes its own copy, never Olympus's state nor another addon's.
--   - Versioned and pushed: OlympusAPI.VERSION and OlympusAPI.Has(feature) say what this build gives;
--     handle:On(event, fn) tells of a change (WANTED_CHANGED, RANKINGS_CHANGED, PROFILE_CHANGED, and
--     PERMISSION_CHANGED when the player answers), once a burst of changes settles (DISPATCH_DELAY,
--     never in combat), and only when what that call would return changed: nobody needs to poll.
--   - Bounded. RATE_MAX data calls a RATE_WINDOW per addon, MAX_ADDONS addons a session, MAX_CALLBACKS
--     callbacks per event. A callback runs protected: its error is logged with the addon's name
--     (never Olympus's error report) and never stops Olympus or the other callbacks; one that keeps
--     failing (CALLBACK_FAILS) is dropped.
-- A handle is the addon's own: Register gives it once a session for a name, to the first caller
-- (a second Register for that name gets nil, "taken"), and only for an addon the game has installed
-- (its TOC's Title, which the privacy line shows). That is a courtesy boundary, not a lock: every
-- addon runs in the same Lua as Olympus and can read its saved variables directly. The API gives
-- honest addons a supported, consented path, so that Olympus itself never hands anything out
-- unasked.
-- Its own file, loaded after the boards it reads (the TOC): a file the TOC adds loads only once the
-- game restarts, so after the update to 1.2.4 OlympusAPI is nil until then (docs/API.md says to
-- check for it). No game event, no frame and no timer of its own while nobody listens.
-- The mods' OlympusBridge (Bridge.lua) is another door, for their companion: unchanged.

local API = {}
ns.API = API

API.VERSION = 1
API.CONSENT_VERSION = 1   -- a change in what a Yes lets an addon read asks every addon's line again
API.MAX_ADDONS = 16       -- addons registered in one session
API.SURFACE_LIMIT = 1     -- one client-owned page in the shared tab rail per session
API.RATE_MAX = 20         -- data calls one addon makes...
API.RATE_WINDOW = 10      -- ...in this many seconds
API.MAX_CALLBACKS = 4     -- one addon's callbacks for one event
API.CALLBACK_FAILS = 3    -- a callback that failed this many times is dropped
API.DISPATCH_DELAY = 2    -- a change is told this long after it, a burst of them once
API.COMBAT_RETRY = 5      -- in combat, looked at again this long after
API.MAX_ROWS = 50         -- rows of one Slayers board
API.MAX_WANTED = 200      -- Wanted rows (Wanted.MAX_TARGETS)
API.TITLE_MAX = 40        -- the addon's title on the privacy page
API.EVENTS = { "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED", "PERMISSION_CHANGED" }
API.DATA_EVENTS = { "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED" }
API.RANKINGS = { "slayers", "donors", "church", "games" }

local IS_EVENT = {}
for _, e in ipairs(API.EVENTS) do IS_EVENT[e] = true end

local clients = {} -- [folded addon name] = this session's client
local order = {}   -- the clients, in the order they registered
local pending = {} -- [event] = true: a change not looked at yet
local scheduled = false

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- A module of the addon this build has (not a stand-in for a file the game has not loaded yet,
-- Core.lua's StandIn), with that function.
local function Has(key, fn)
	local m = ns[key]
	return type(m) == "table" and not m.missing and type(m[fn]) == "function"
end

-- That module's function, protected: its results, or nothing when it is missing or failed.
local function Call(key, fn, ...)
	if not Has(key, fn) then return nil end
	local ok, a, b = pcall(ns[key][fn], ...)
	if not ok then return nil end
	return a, b
end

-- A plain string for another addon: no colour, texture, atlas or link codes, no control
-- characters, max bytes at most (never half a letter); nil when nothing is left.
local function Plain(v, max)
	if type(v) ~= "string" then return nil end
	v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if v == "" then return nil end
	return ns.Cut(v, max or 96)
end

-- A finite number, whole when whole is asked; nil otherwise.
local function Num(v, whole)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
	if whole then v = math.floor(v + 0.5) end
	return v
end

-- A fresh copy of plain data (strings, numbers, booleans and tables of them).
local function Copy(v, depth)
	if type(v) ~= "table" then
		if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return v end
		return nil
	end
	depth = depth or 0
	if depth > 6 then return nil end
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "string" or type(k) == "number" then out[k] = Copy(x, depth + 1) end
	end
	return out
end

-- The same text for the same data, whatever order pairs walks it in: what a callback was last told.
local function Signature(v)
	if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) < type(b) end
		return a < b
	end)
	local out = {}
	for i, k in ipairs(keys) do out[i] = tostring(k) .. "=" .. Signature(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

local function Member() return ns.IsMember and ns.IsMember() == true end

local function Busy() return InCombatLockdown and InCombatLockdown() and true or false end

---------------------------------------------------------------------------
-- What an addon may read: each built from the page's own functions, field by field
---------------------------------------------------------------------------

-- The Wanted tab's list: its entries in its order (Wanted.Targets, "listed": 1.2.4, a Horde player
-- with a bounty or a kill of ours, never one with 0 points and 0 kills), each with what its row
-- shows (the name, the bounty and the kills) and the cycle its page shows; the Horde player's GUID,
-- which is who he is on the list (Wanted.lua). Never the victims, the claims, the sightings, who
-- added or took off an entry, nor any time.
function API.Wanted()
	local out = {}
	for i, t in ipairs(Call("Wanted", "Targets", "listed") or {}) do
		if #out >= API.MAX_WANTED then break end
		if type(t) == "table" and t.active == true then
			out[#out + 1] = { place = i, name = Plain(t.name, 72), guid = Plain(t.guid, 64),
				bounty = Num(t.current, true) or 0, kills = Num(t.lifetimeKills, true) or 0, cycle = Num(t.cycle, true) or 1 }
		end
	end
	return out
end

-- A Slayers board as the Wanted tab lists it: place, name, points and claims.
local function SlayerRows(rows)
	local out = {}
	for i, r in ipairs(type(rows) == "table" and rows or {}) do
		if #out >= API.MAX_ROWS then break end
		if type(r) == "table" then
			out[#out + 1] = { place = Num(r.place, true) or i, name = Plain(r.name, 72),
				points = Num(r.points, true) or 0, claims = Num(r.claims, true) or 0 }
		end
	end
	return out
end

-- The Wanted tab's boards: this month's and all time's (what this client observed), and the
-- signed top three it holds, by the names its boards know for those GUIDs (the GUIDs stay here).
local function Slayers()
	if not Has("Wanted", "Rankings") then return nil end
	local rank = Call("Wanted", "Rankings")
	if type(rank) ~= "table" then return nil end
	local out = { month = SlayerRows(rank.month), all = SlayerRows(rank.all), signed = nil }
	local g = Call("Wanted", "GlobalSnapshot")
	if type(g) == "table" and type(g.rows) == "table" then
		local names = {}
		for _, r in ipairs(type(rank.all) == "table" and rank.all or {}) do
			if type(r) == "table" and type(r.guid) == "string" and type(r.name) == "string" then names[r.guid] = r.name end
		end
		out.signed = {}
		for i, r in ipairs(g.rows) do
			if type(r) == "table" and i <= 3 then
				out.signed[#out.signed + 1] = { place = i, name = Plain(names[r.guid], 72),
					points = Num(r.points, true) or 0, claims = Num(r.claims, true) or 0 }
			end
		end
	end
	return out
end

local function Names(list, max)
	local out = {}
	for _, n in ipairs(type(list) == "table" and list or {}) do
		if #out >= (max or 3) then break end
		local name = Plain(n, 72)
		if name then out[#out + 1] = name end
	end
	return out
end

-- The donors' top three, only where every member's own screen shows them (review of 1.2.4: they
-- came back whatever the King's switch, names no page showed). The names the Treasurer's word gives
-- every client (HonorsNet.Donors), names alone, as the word:
--   - nil unless the King shows the army the Treasury's ranking (Treasury.PublicShows("ranking"):
--     his own switch as every client keeps it, off by default; never the keepers' or the King's
--     own view, nor the author's preview, as the games are never a staff view). Off, no page lists
--     the donors, and a portrait's frame tells of one donor at a time, to whoever looks at him.
--   - all: the all-time top three, which head that ranking on the Treasury tab.
--   - month: the month's three only in a build that wears their koi frame (Honors.FrameShipped);
--     1.2.4 does (the borders lane released the koi); a build without it lists them nowhere: nil.
local function Donors()
	if not Has("HonorsNet", "Donors") then return nil end
	if Call("Treasury", "PublicShows", "ranking") ~= true then return nil end
	local d = Call("HonorsNet", "Donors")
	d = type(d) == "table" and d or {}
	local out = { all = Names(d.all) }
	if Call("Honors", "FrameShipped", { family = "donor-month" }) == true then out.month = Names(d.month) end
	return out
end

-- The Church's public top three (HonorsNet.ChurchTop: nil while its public ranking is closed).
local function Church()
	if not Has("HonorsNet", "ChurchTop") then return nil end
	local t = Call("HonorsNet", "ChurchTop")
	if type(t) ~= "table" then return nil end
	return { missionaries = Names(t.missionaries), apostles = Names(t.apostles) }
end

-- Each game's ranking the King made public (ArenaHome.RankingsPublic: the one everybody's Games tab
-- shows), as that tab shows it; a game kept to the staff is not there, whoever this player is.
local function Games()
	if not Has("ArenaHome", "RankingsPublic") then return nil end
	local out = {}
	if Call("ArenaHome", "RankingsPublic", "arena") == true then
		local rows = {}
		local view = Call("ArenaLedger", "RankingView", "all", "A", 1, { mode = "L" })
		for i, x in ipairs(type(view) == "table" and type(view.rows) == "table" and view.rows or {}) do
			if type(x) == "table" then
				rows[#rows + 1] = { place = Num(x.rank, true) or i, name = Plain(x.name, 72), rating = Num(x.rating, true),
					wins = Num(x.wins, true) or 0, losses = Num(x.losses, true) or 0 }
			end
		end
		out.arena = rows
	end
	if Call("ArenaHome", "RankingsPublic", "bones") == true then
		local rows = {}
		for i, x in ipairs(Call("FarkleTable", "Best", "L") or {}) do
			if i > 10 then break end
			if type(x) == "table" then
				rows[#rows + 1] = { place = Num(x.place, true) or i, name = Plain(x.name, 72),
					games = Num(x.games, true) or 0, won = Num(x.won, true) or 0 }
			end
		end
		out.bones = rows
	end
	-- Lottery's saved winners are private history, even with an older game's publish word.
	return out
end

local RANKING = { slayers = Slayers, donors = Donors, church = Church, games = Games }

-- Every public ranking (kind nil), or one: "slayers", "donors", "church" or "games". A kind this
-- build lacks (no arena: no games, no donors) is nil.
function API.Rankings(kind)
	if kind ~= nil then
		local fn = RANKING[kind]
		return fn and fn() or nil
	end
	local out = {}
	for _, k in ipairs(API.RANKINGS) do out[k] = RANKING[k]() end
	return out
end

-- The player's own role in Olympus, the highest he holds: "king", "councillor" (the signed High
-- Council), "steward", "treasurer" (his characters), "guildmaster", "officer" (his guild's officer
-- ranks) or "member".
local function Role(rankIndex)
	if Call("King", "IsKing") == true then return "king" end
	local me = ns.me
	if type(me) == "string" and me ~= "" then
		if type(ns.IsHighCouncillor) == "function" and select(2, pcall(ns.IsHighCouncillor, me)) == true then return "councillor" end
		if type(ns.IsSteward) == "function" and select(2, pcall(ns.IsSteward, me)) == true then return "steward" end
		if type(ns.IsTreasurerCharacter) == "function" and select(2, pcall(ns.IsTreasurerCharacter, me)) == true then return "treasurer" end
	end
	if rankIndex == 0 then return "guildmaster" end
	if Call("Roster", "IsOfficer") == true then return "officer" end
	return "member"
end

-- The player himself: whether he is in an Olympus guild, and there his guild, its rank's name and
-- index (0 its master), his role, and the frame and title his profile shows (HonorsNet.Verified:
-- the frame an honour key, "rank" his rank's or "none"; the title its words, or nil).
function API.Profile()
	if not Member() then return { member = false } end
	local guild, rankName, rankIndex
	if GetGuildInfo then guild, rankName, rankIndex = GetGuildInfo("player") end
	rankIndex = Num(rankIndex, true)
	local out = { member = true, name = Plain(ns.me, 72), guild = Plain(guild, 64), rank = Plain(rankName, 64), rankIndex = rankIndex,
		role = Role(rankIndex), frame = "rank", title = nil }
	local v = type(ns.me) == "string" and Call("HonorsNet", "Verified", ns.me) or nil
	if type(v) == "table" then
		out.frame = Plain(v.frame, 48) or "rank"
		if type(v.title) == "string" then out.title = Plain(Call("HonorsNet", "TitleText", v.title), 64) end
	end
	return out
end

-- What each data event's callback is given: what its call returns.
local BUILD = {
	WANTED_CHANGED = function() return Member() and API.Wanted() or nil end,
	RANKINGS_CHANGED = function() return Member() and API.Rankings() or nil end,
	PROFILE_CHANGED = function() return API.Profile() end,
}

---------------------------------------------------------------------------
-- The addons, their answers and their handles
---------------------------------------------------------------------------

local function Answers(make)
	if type(ns.db) ~= "table" then return nil end
	if type(ns.db.apiAddons) ~= "table" then
		if not make then return nil end
		ns.db.apiAddons = {}
	end
	return ns.db.apiAddons
end

-- The player's answer for this addon: true, false, or nil (never asked, or asked about less than
-- this version gives).
local function Answer(c)
	local all = Answers(false)
	local e = all and all[c.key]
	if type(e) ~= "table" or e.v ~= API.CONSENT_VERSION then return nil end
	if e.on == true then return true end
	if e.on == false then return false end
	return nil
end

local function Granted(c) return Answer(c) == true end

local function Status(c)
	local a = Answer(c)
	return a == true and "granted" or a == false and "refused" or "pending"
end

local function Listens(c, event)
	return type(c.callbacks[event]) == "table" and #c.callbacks[event] > 0
end

-- The addon's callbacks for the event, each protected; one that keeps failing goes.
local function Tell(c, event, payload)
	local list = c.callbacks[event]
	if type(list) ~= "table" then return end
	local now = {}
	for i, fn in ipairs(list) do now[i] = fn end
	for _, fn in ipairs(now) do
		local ok, err = pcall(fn, event, Copy(payload))
		if not ok then
			c.fails[fn] = (c.fails[fn] or 0) + 1
			ns.Log("api: %s's %s callback failed (%d): %s", c.name, event, c.fails[fn], ns.Cut(tostring(err), 200))
			if c.fails[fn] >= API.CALLBACK_FAILS then
				for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
				c.fails[fn] = nil
				ns.Log("api: %s's %s callback dropped after %d errors", c.name, event, API.CALLBACK_FAILS)
			end
		end
	end
end

-- What a data event would give this addon now becomes what it was last told (no call when it
-- listens to nothing: nothing is built).
local function Baseline(c, event)
	local build = BUILD[event]
	if not build or not Listens(c, event) or not Granted(c) then return end
	local data = build()
	if data ~= nil then c.told[event] = Signature(data) end
end

local Dispatch

local function Schedule(delay)
	if scheduled or not ns.After then return end
	scheduled = true
	ns.After(delay or API.DISPATCH_DELAY, "api dispatch", function() Dispatch() end)
end

-- A change Olympus saw: looked at once the burst settles, only for events a granted addon listens
-- to (nobody listening: nothing is built and no timer starts).
local function Mark(...)
	local any = false
	for i = 1, select("#", ...) do
		local event = select(i, ...)
		for _, c in ipairs(order) do
			if Listens(c, event) and Granted(c) then pending[event], any = true, true break end
		end
	end
	if any then Schedule() end
end

-- Builds each pending event's data once and tells each granted addon that listens, when it is not
-- what that addon was last told. In combat, waits.
Dispatch = function()
	scheduled = false
	if next(pending) == nil then return end
	if Busy() then Schedule(API.COMBAT_RETRY) return end
	local events = pending
	pending = {}
	for _, event in ipairs(API.DATA_EVENTS) do
		if events[event] then
			local data = BUILD[event]()
			if data ~= nil then
				local sig = Signature(data)
				for _, c in ipairs(order) do
					if Listens(c, event) and Granted(c) and c.told[event] ~= sig then
						c.told[event] = sig
						Tell(c, event, data)
					end
				end
			end
		end
	end
end

-- The player answered on the privacy page: kept for the account, the addon told (PERMISSION_CHANGED,
-- at once, protected) and, on a Yes, what it listens to now taken as what it was told.
local function SetAnswer(c, on)
	local all = Answers(true)
	if not all then return end
	all[c.key] = { on = on and true or false, v = API.CONSENT_VERSION, at = ns.Now and ns.Now() or 0 }
	c.told = {}
	if on then for _, event in ipairs(API.DATA_EVENTS) do Baseline(c, event) end end
	ns.Log("api: %s %s", c.name, on and "granted" or "refused")
	Tell(c, "PERMISSION_CHANGED", Status(c))
end

-- The addon's line on the privacy page (Consent.lua): its own Yes and No, or the page's deliberately
-- labelled Authorize all. A new
-- question, never one of the lines 1.2.1 and 1.2.2 showed at every login (adopt = false: review of
-- 1.2.4, an account updating from 1.2.2 straight to 1.2.4 had it taken as asked, and the page never
-- opened by itself for it).
local function Line(c)
	if not Has("Consent", "Register") then return false end
	return ns.Consent.Register({
		key = c.consentKey,
		label = function() return L.API_CONSENT_LABEL:format(c.title) end,
		text = "API_CONSENT_TEXT",
		explicit = true,
		adopt = false,
		version = API.CONSENT_VERSION,
		get = function() return Answer(c) end,
		set = function(on) SetAnswer(c, on) end,
	}) == true
end

-- The installed addon's title (its TOC's, plain), its name when it has none but the game has it
-- loaded, or nil: a name the game knows nothing of gets no line on the privacy page.
local function Installed(name)
	local AO = C_AddOns
	if type(AO) ~= "table" then return nil end
	local title, loaded
	if type(AO.GetAddOnMetadata) == "function" then
		local ok, t = pcall(AO.GetAddOnMetadata, name, "Title")
		if ok then title = Plain(t, API.TITLE_MAX) end
	end
	if not title and type(AO.IsAddOnLoaded) == "function" then
		local ok, yes = pcall(AO.IsAddOnLoaded, name)
		loaded = ok and yes and true or false
	end
	if title then return title end
	if loaded then return Plain(name, API.TITLE_MAX) end
	return nil
end

-- A method of the handle, for handle:Method(...) and handle.Method(...) alike.
local function Method(c, fn)
	return function(first, ...)
		if first == c.handle then return fn(c, ...) end
		return fn(c, first, ...)
	end
end

-- A data call: the player's Yes, an Olympus guild (where asked), and the addon within its rate.
-- Past it, said in the log once a session for that addon (review of 1.2.4: once a window filled the
-- log's ring, and the 25 lines /oly bug copies, with one addon polling).
local function Spend(c)
	local now = ns.Now and ns.Now() or 0
	local r = c.rate
	if now - r.at >= API.RATE_WINDOW or now < r.at then r.at, r.n = now, 0 end
	if r.n >= API.RATE_MAX then
		if not c.rateSaid then
			c.rateSaid = true
			ns.Log("api: %s asked more than %d times in %d s (said once a session)", c.name, API.RATE_MAX, API.RATE_WINDOW)
		end
		return false
	end
	r.n = r.n + 1
	return true
end
local function Read(c, needsGuild, build, ...)
	if not Granted(c) then return nil, Status(c) end
	if needsGuild and not Member() then return nil, "guild" end
	if not Spend(c) then return nil, "busy" end
	return build(...)
end

-- Surface ownership is deliberately separate from the addon's name and consent key. UI.lua sees
-- only this session-local slot, so its page context and lifecycle logs do not identify the caller.
local function SurfaceCall(fn, owner, ...)
	if not Has("UI", fn) then return false, "unavailable" end
	local ok, result, why = pcall(ns.UI[fn], owner, ...)
	if not ok then return false, "failed" end
	return result, why
end

local function RegisteredSurfaceCall(c, fn, ...)
	if not c.surfaceRegistered then return false, "unregistered" end
	return SurfaceCall(fn, c.surfaceOwner, ...)
end

local METHODS = {}
function METHODS.Status(c) return Status(c) end
function METHODS.Name(c) return c.name end
function METHODS.GetWanted(c) return Read(c, true, API.Wanted) end
function METHODS.GetRankings(c, kind)
	if kind ~= nil and not RANKING[kind] then return nil, "kind" end
	return Read(c, true, API.Rankings, kind)
end
function METHODS.GetProfile(c) return Read(c, false, API.Profile) end
function METHODS.RegisterSurface(c, spec)
	if c.surfaceRegistered then return false, "registered" end
	local ok, why = SurfaceCall("RegisterAPISurface", c.surfaceOwner, spec)
	if ok == true then c.surfaceRegistered = true end
	return ok, why
end
function METHODS.OpenSurface(c) return RegisteredSurfaceCall(c, "OpenAPISurface") end
function METHODS.ToggleSurface(c) return RegisteredSurfaceCall(c, "ToggleAPISurface") end
function METHODS.RefreshSurface(c) return RegisteredSurfaceCall(c, "RefreshAPISurface") end
function METHODS.IsSurfaceOpen(c) return RegisteredSurfaceCall(c, "IsAPISurfaceOpen") end
function METHODS.On(c, event, fn)
	if not IS_EVENT[event] or type(fn) ~= "function" then return false end
	local list = c.callbacks[event] or {}
	for _, f in ipairs(list) do if f == fn then return true end end
	if #list >= API.MAX_CALLBACKS then return false end
	list[#list + 1] = fn
	c.callbacks[event] = list
	if c.told[event] == nil then Baseline(c, event) end
	return true
end
function METHODS.Off(c, event, fn)
	local list = c.callbacks[event]
	if type(list) ~= "table" then return false end
	for i = #list, 1, -1 do
		if list[i] == fn or fn == nil then table.remove(list, i) end
	end
	return true
end

local function ReadOnly(_, k) error("OlympusAPI: read-only (" .. tostring(k) .. ")", 2) end

local function NewClient(name, key, title, slot)
	local c = { name = name, key = key, title = title, consentKey = "api:" .. key, callbacks = {}, told = {}, fails = {},
		rate = { at = -math.huge, n = 0 }, surfaceOwner = "api-surface:" .. tostring(slot) }
	local methods = {}
	for k, fn in pairs(METHODS) do methods[k] = Method(c, fn) end
	c.handle = setmetatable({}, { __index = methods, __newindex = ReadOnly, __metatable = false })
	return c
end

-- OlympusAPI.Register: the handle of a named, installed addon, once a session; nil and why else
-- ("name", "self", "taken", "full", "unknown", "consent").
function API.Register(name)
	if type(name) ~= "string" then return nil, "name" end
	name = name:match("^%s*(.-)%s*$")
	if name == "" or #name > 64 or name:find("[%c|]") then return nil, "name" end
	local key = ns.Fold(name)
	if key == "olympus" or key == "olympus_arena" then return nil, "self" end
	if clients[key] then return nil, "taken" end
	if #order >= API.MAX_ADDONS then return nil, "full" end
	local title = Installed(name)
	if not title then return nil, "unknown" end
	local c = NewClient(name, key, title, #order + 1)
	if not Line(c) then return nil, "consent" end
	clients[key] = c
	order[#order + 1] = c
	ns.Log("api: %s registered (%s)", name, Status(c))
	return c.handle
end

-- What this build gives: a feature ("wanted", "rankings", "rankings.<kind>", "profile",
-- "callbacks", "ui.surface") or an event's name.
local FEATURES = {
	wanted = function() return Has("Wanted", "Targets") end,
	rankings = function() return true end,
	["rankings.slayers"] = function() return Has("Wanted", "Rankings") end,
	["rankings.donors"] = function() return Has("HonorsNet", "Donors") end,
	["rankings.church"] = function() return Has("HonorsNet", "ChurchTop") end,
	["rankings.games"] = function() return Has("ArenaHome", "RankingsPublic") end,
	profile = function() return true end,
	callbacks = function() return true end,
	["ui.surface"] = function()
		for _, fn in ipairs({ "RegisterAPISurface", "OpenAPISurface", "ToggleAPISurface", "RefreshAPISurface", "IsAPISurfaceOpen" }) do
			if not Has("UI", fn) then return false end
		end
		return true
	end,
}
for _, e in ipairs(API.EVENTS) do FEATURES[e] = FEATURES.callbacks end
function API.Has(feature)
	local fn = type(feature) == "string" and FEATURES[feature]
	if not fn then return false end
	local ok, yes = pcall(fn)
	return ok and yes == true
end

---------------------------------------------------------------------------
-- The global other addons see: OlympusAPI.VERSION, .Has, .Register (read-only)
---------------------------------------------------------------------------

local public = { VERSION = API.VERSION, SURFACE_LIMIT = API.SURFACE_LIMIT, Has = API.Has, Register = API.Register }
OlympusAPI = setmetatable({}, { __index = public, __newindex = ReadOnly, __metatable = false })

---------------------------------------------------------------------------
-- What tells of a change (Olympus's own events: none of the game's)
---------------------------------------------------------------------------

-- Wanted's list and its Slayers boards (and the signed top three).
ns.On("WANTED_CHANGED", function() Mark("WANTED_CHANGED", "RANKINGS_CHANGED") end)
-- An honour, a pick (the profile's frame and title), the donors' word (HonorsNet).
ns.On("HONORS_CHANGED", function() Mark("RANKINGS_CHANGED", "PROFILE_CHANGED") end)
-- The Church's top three, or its public ranking's switch.
ns.On("CHURCH_TOP_CHANGED", function() Mark("RANKINGS_CHANGED") end)
ns.On("CHURCH_PUBLIC_CHANGED", function() Mark("RANKINGS_CHANGED") end)
-- The King's switch of the Treasury's ranking, which the donors' top three follow (looked at only
-- when it turned: the treasury changes often, and nothing else of it is read here).
local rankingShown
ns.On("TREASURY_CHANGED", function()
	local shown = Call("Treasury", "PublicShows", "ranking") == true
	if shown ~= rankingShown then
		rankingShown = shown
		Mark("RANKINGS_CHANGED")
	end
end)
-- The games: a result, a ranking made public or kept to the staff (ArenaRoles: Arena.Changed).
ns.On("ARENA_CHANGED", function() Mark("RANKINGS_CHANGED") end)
ns.On("LOTTERY_RESULT", function() Mark("RANKINGS_CHANGED") end)
-- A guild joined or left, a rank (Roster.lua: DATA_CHANGED), the signed lists (the role).
ns.On("DATA_CHANGED", function() Mark("PROFILE_CHANGED") end)
