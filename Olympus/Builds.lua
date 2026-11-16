local ADDON, ns = ...
local L = ns.L

-- 1.5.4, modified builds (the owner's call, 2026-11-08: "se a versão for modificada ele trava, a
-- comunicação com ela"). A build of Olympus changed by a third party is handed around (made from
-- 1.5.1; its version string is no release form, "1.5.1-<suffix>"): it never checks for newer
-- versions, answers no version check, keeps its own terms, and its users count in the army like
-- anyone else. What this client can see of such a build it marks, records, shares among the guild
-- masters, the officers and the High Council, and locks out; what it shows says "modified build",
-- plainly, and names no third party. A careful fork can lie about all of it; this bites what is
-- observable today.
--   * Detection. A peer's announced version (its hello over GUILD, Comm.lua's H1; its answer to a
--     version check, Versions.lua's V8) that is no release form marks a modified build: a release
--     is x.y.z or x.y.z.w, and the author's own arena test builds say x.y.z-test.N (never modified;
--     their hello says the base version anyway). Anything else ("1.5.1-<suffix>", "1.5.3-custom",
--     an empty or non-numeric version where the field is there) is modified.
--   * A weaker mark, "silent to version checks" (shown, never a lock): a guildmate whose hello names
--     a release that answers version checks (1.1.2 and newer), and who answered none of SILENT_ASKS
--     checks of this client spread over SILENT_SPAN at least, with a hello of his heard between each
--     check and the next. The hello is the proof his client was sending addon messages in each
--     interval: in a dungeon, a raid or a match the game holds every addon message (the hello too,
--     Comm's queue), so a client that could not answer sends no hello either, and one check can
--     never do it. Quiet presence sends no hello (no mark); an idle 1.5.3 client answers every check
--     by itself within seconds (Versions.HandlePing). What is left: a client that blocks or ignores
--     the asker answers nothing and keeps saying hello, so the mark is only ever a hint to look.
--   * Records. ns.db.builds (account-wide): MAX sightings at most, the oldest out; each the character,
--     the version string, how (the hello, an answer, the silent mark), first and last seen, who
--     reported it (this client, or a guild master's, an officer's or a councillor's shared word).
--   * Sharing. A guild master or officer of an Olympus guild, a High Councillor, the King or the
--     author tells the others of a sighting of his own: one word (BD) over GUILD and on the channel
--     (so it travels by the relay), once an hour per sighting, SHARE_PER_MIN a minute at most. Taken
--     only from a sender the roster (over GUILD) or the census (Data.AuthorizedRank, on the channel)
--     makes a guild master or an officer, or a councillor, the King or the author; kept with the
--     reporter's name; never a lock. A plain member's client sends none and keeps none.
--   * The lock. A client this one saw announce a modified build (the strong mark alone: never a
--     shared word but on a relay's client, below; never the silent mark, never our own client) is
--     locked out at Comm's door:
--     nothing it says reaches a handler, the census or a relay here, but its hello and its version
--     answer, which clear the mark when they name a release (the sighting stays in the record). A
--     relay takes no registration from it and drops one it holds (Relay.lua); the arena's words
--     from it are refused (ArenaNet.lua). Its lines in the Olympus chat go the way of /oly block's:
--     dropped at the same door. What it sees of us is unchanged (the owner's call: nothing hidden
--     from them, nothing but the code).
--   * The relays (the owner's call, the same day). A relay's client (Relay.IsRelay(ns.me)) keeps the
--     reporters' records as a guild master does, and acts on a listed character as on one it saw
--     itself: no registration taken, one held dropped, nothing forwarded, its RL words dropped. The
--     records cross between the relays as the guild verifications do (RW, Relay.lua): a word a
--     relay hears from its clients goes once to every other relay, which hands it to its reporters;
--     a word from a relay or the author is trusted as a guild master's. Our own observation beats
--     the list: a listed character that says a release to us directly is cleared here, and that
--     clearing is shared (a "c" word) so the other keepers' lists clear too; a keeper's clear never
--     lifts a mark this client made itself.
--   * The author's ask (the owner's call, the same day). Every PROMPT_EVERY the author's relay client
--     asks each character it holds as a modified build (its own marks and, being a relay, the list's)
--     that is online (its hello in his guild, or a word of its that reached his client, refused at
--     the door, in the last ONLINE_FOR: a locked reporter's registrations every 170 s among them) to
--     update, with his standard ask: V3 by whisper from his own character (Workshop.AskUpdate), which
--     every version shows as his update window. Not wrapped in a relay's RM: a reporter delivers an
--     RM's word as a channel word (Relay.lua's Deliver, Comm.Inject("CHANNEL")) and hands it to its
--     guild, and Workshop.HandleUpdate drops a V3 that did not come by whisper from the author, on
--     1.5.1 as here. Once per character a PROMPT_EVERY, PROMPT_MAX a PROMPT_EVERY in all, the longest
--     unasked first, never while his queue has fewer than PROMPT_ROOM places free (the relay's own
--     words first; tried again a minute later), never to a character not marked.
--   * The view: /oly builds, a copyable window (the owner cannot copy chat lines); the right-click
--     menu's version line, "Olympus <release it was made from> (modified build)" (Versions.lua,
--     Builds.Shown: never the rest of the version string).
--   BD~1~<reporter's guild>~<name>~<version>~h|a|c~<first>~<last>~<their guild>   GUILD and CHANNEL
--   (h the hello, a a version answer, c the character announced the release <version> to the sender)

local Builds = {}
ns.Builds = Builds

Builds.MAX = 400            -- sightings kept, account-wide (the oldest out)
Builds.VERSION_MAX = 24     -- bytes of a version string kept, shown or sent
Builds.NAME_MAX = 64        -- bytes of a name in a shared word
Builds.SILENT_ASKS = 3      -- unanswered version checks before the weak mark...
Builds.SILENT_SPAN = 300    -- ...the first and the last at least this far apart (Versions.PING_GAP keeps them 120 s apart)
Builds.SHARE_GAP = 3600     -- a sighting shared again at most this often
Builds.SHARE_PER_MIN = 6    -- shared words a minute at most, whatever they name
Builds.KEEP_AT_MOST = 365 * 86400 -- a shared word's times older than this count as now
Builds.PROMPT_EVERY = 1800  -- the author's update ask to each marked client online at most this often...
Builds.PROMPT_MAX = 20      -- ...and this many asks in all each PROMPT_EVERY
Builds.PROMPT_ROOM = 20     -- places his send queue keeps free for the relay's own words (Comm.QueueRoom)
Builds.ONLINE_FOR = 300     -- a locked client heard at the door this recently counts as online

-- Swappable in tests.
Builds.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local heard = {}       -- record key -> when a word of that locked client last reached the door (session)
local prompted = {}    -- record key -> when the author's update ask last went to that character
local promptTimes = {} -- when each update ask of the last PROMPT_EVERY went
local retrying = false -- a retry of Builds.Prompt waits (the queue had no room)
local lastHello = {}   -- key -> { t, version }: a guild peer's last hello this session (the silent mark's presence)
local asks = {}        -- key -> { t1, t2, ... }: this client's version checks a peer left unanswered
local shared = {}      -- key (or "c:" .. key, a clear) -> when this client last shared that
local shareTimes = {}  -- this client's shared words in the last minute
local indexed, byKey, byShort -- the store the index was built for, and the index

local function Full(name) return ns.FullName(ns.Normal(tostring(name or ""))) end
local function Key(full) return full:lower() end
local function ShortKey(full) return ns.Fold(ns.ShortName(full)) end
local function Release(v)
	return type(v) == "string" and (v:match("^%d+%.%d+%.%d+$") or v:match("^%d+%.%d+%.%d+%.%d+$") or v:match("^%d+%.%d+%.%d+%-test%.%d+$")) ~= nil
end
Builds.Release = Release

-- What the menu and /oly builds show of a modified build's version (the owner's call: "modified
-- build", plainly, no third party named): the release it was made from, its leading x.y.z or
-- x.y.z.w, never the rest, which may carry its maker's name ("1.5.1-<suffix>" shows as 1.5.1); nil
-- when it starts with none. The whole string stays in the record and the shared word.
function Builds.Shown(v)
	if type(v) ~= "string" then return nil end
	return v:match("^(%d+%.%d+%.%d+%.%d+)") or v:match("^(%d+%.%d+%.%d+)")
end

-- A version string as it is kept and sent: no escape code, control byte or separator, at most
-- VERSION_MAX bytes; "?" for none (an empty field, as Comm shows an unreadable version).
function Builds.Clean(v)
	v = tostring(v or ""):gsub("[|~%c]", "")
	v = ns.Cut(v, Builds.VERSION_MAX)
	return v ~= "" and v or "?"
end

local function Recent(list, span, now)
	for i = #list, 1, -1 do if now - list[i] > span then table.remove(list, i) end end
	return #list
end

---------------------------------------------------------------------------
-- The record (ns.db.builds)
---------------------------------------------------------------------------

local function Store()
	if type(ns.db) ~= "table" then return nil end
	if type(ns.db.builds) ~= "table" then ns.db.builds = {} end
	local list = ns.db.builds
	if indexed ~= list then
		indexed, byKey, byShort = list, {}, {}
		for i = #list, 1, -1 do
			local e = list[i]
			if type(e) ~= "table" or type(e.name) ~= "string" or e.name == "" then
				table.remove(list, i)
			else
				e.key = Key(e.name)
				byKey[e.key] = e
				byShort[ShortKey(e.name)] = e
			end
		end
	end
	return list
end

local function Find(full)
	local list = Store()
	if not list then return nil end
	local e = byKey[Key(full)]
	-- (Forever: a name is one across a realm family, and the server stamps a guildmate's whispers
	-- with his own sub-realm; the roster and the hello file him under ours. Comm.PeerVersion reads
	-- the short name the same way.)
	if not e and ns.splitNames then e = byShort[ShortKey(full)] end
	return e
end

local function Remove(e)
	local list = Store()
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == e then table.remove(list, i) end
	end
	if byKey[e.key] == e then byKey[e.key] = nil end
	local short = ShortKey(e.name)
	if byShort[short] == e then byShort[short] = nil end
end

-- The oldest sightings (last seen) out past MAX.
local function Trim(list)
	while #list > Builds.MAX do
		local oldest, at = nil, math.huge
		for i, e in ipairs(list) do
			if (e.last or 0) < at then oldest, at = i, e.last or 0 end
		end
		Remove(list[oldest])
	end
end

local function Add(full, now)
	local list = Store()
	if not list then return nil end
	local e = { name = full, key = Key(full), first = now, last = now }
	list[#list + 1] = e
	byKey[e.key] = e
	byShort[ShortKey(full)] = e
	Trim(list)
	return e
end

---------------------------------------------------------------------------
-- Sightings and the lock
---------------------------------------------------------------------------

-- This client is a relay's (Relay.lua: a signed councillor's, the author's, the King's or the
-- Treasurer's character) while the relay runs (Forever): it keeps the list and acts on it.
local function RelayClient()
	local R = ns.Relay
	return type(R) == "table" and not R.missing and type(R.On) == "function" and R.On() == true
		and type(R.IsRelay) == "function" and R.IsRelay(ns.me) == true
end
Builds.RelayClient = RelayClient
local function IsRelayName(name)
	local R = ns.Relay
	return type(R) == "table" and not R.missing and type(R.IsRelay) == "function" and R.IsRelay(name) == true
end

local function Privy()
	if type(ns.me) ~= "string" then return false end
	if ns.Roster and ns.Roster.IsOfficer and ns.Roster.IsOfficer() then return true end
	return (ns.IsHighCouncillor ~= nil and ns.IsHighCouncillor(ns.me) == true)
		or (ns.IsAuthorName ~= nil and ns.IsAuthorName(ns.me) == true)
		or (ns.IsKingCharacter ~= nil and ns.IsKingCharacter(ns.me) == true)
		or RelayClient()
end
-- Who sends and keeps the shared list: a guild master or an officer (our own rank, the server's),
-- a councillor, the author, the King, and a relay's client. Plain members neither.
Builds.Privy = Privy

local Share, ShareClear

-- A sighting of this client's own (by nil), or a reporter's shared one (by: his name).
local function Observe(full, version, how, now, by, first, guild)
	if full == ns.me then return nil end
	local e = Find(full)
	-- Ours stands (what we saw ourselves) while it locks; the silent mark never blocks a sighting, and
	-- once the character announced a release to us, a reporter's sighting newer than that is taken (it
	-- went back to a modified build).
	if by ~= nil and e and e.by == nil and e.how ~= "silent" and (e.locked ~= false or now <= (e.releaseAt or 0)) then return e end
	if not e then e = Add(full, now) end
	if not e then return nil end
	local was = e.locked
	e.name, e.version, e.how, e.last = full, Builds.Clean(version), how, now
	if first and first < (e.first or now) then e.first = first end
	e.first = e.first or now
	if guild and guild ~= "" then e.guild = guild end
	e.by = by
	e.release, e.releaseAt = nil, nil
	if by == nil then
		e.cleared = nil
		e.locked = true
		if was ~= true then
			ns.Log("modified build: %s runs %s (%s): locked out", full, e.version, how)
			local R = ns.Relay
			if type(R) == "table" and type(R.DropReporter) == "function" then R.DropReporter(full) end
		end
		Share(e, now)
	else
		e.locked = nil
		-- (A reporter saw it on a modified build again after a clear: the clear is over.)
		if e.cleared and now > (e.cleared.at or 0) then e.cleared = nil end
		-- A relay's client acts on the list: a registration it holds from the character goes.
		if RelayClient() and e.cleared == nil then
			local R = ns.Relay
			if type(R.DropReporter) == "function" then R.DropReporter(full) end
		end
	end
	return e
end

-- A release announced to us by a client we hold locked, or one the list names: the lock goes, the
-- sighting stays (ours: release noted; a reporter's: cleared, until a reporter sees it again), and
-- the keepers of the list are told (ShareClear). Our own observation beats the list.
local function Cleared(full, version, now)
	local e = Find(full)
	if not e or e.how == "silent" then return end
	if e.by == nil then
		if e.locked ~= true then return end
		e.locked, e.release, e.releaseAt = false, Builds.Clean(version), now
	else
		if e.cleared then return end
		e.cleared = { version = Builds.Clean(version), at = now }
	end
	ns.Log("modified build: %s now says %s: unlocked", full, Builds.Clean(version))
	ShareClear(e, version, now)
end

-- A guild peer's hello (Comm.lua, H1): version as it says it ("" for none).
function Builds.Hello(sender, version, now)
	local full = Full(sender)
	if full == "" or full == ns.me then return end
	now = now or ns.Now()
	lastHello[Key(full)] = { t = now, version = version }
	if Release(version) then Cleared(full, version, now) else Observe(full, version, "hello", now) end
end

-- Their answer to our version check (Versions.lua, V8).
function Builds.Answer(sender, version)
	local full = Full(sender)
	if full == "" or full == ns.me then return end
	local now = ns.Now()
	if Release(version) then
		Cleared(full, version, now)
		Builds.Answered(full)
	else
		Observe(full, version, "answer", now)
	end
end

-- The strong mark: this client saw `name` announce a modified build and heard no release since.
-- Never our own client, never from the silent mark, never from a shared word but on a relay's
-- client (below). (Asked of every word at Comm's door: nothing to do while the record is empty.)
function Builds.Quarantined(name)
	if type(name) ~= "string" or name == "" then return false end
	local list = Store()
	if not list or not list[1] then return false end
	local full = Full(name)
	if full == ns.me then return false end
	local e = Find(full)
	if not e or e.how == nil or e.how == "silent" then return false end
	if e.by == nil then return e.locked == true end
	-- A reporter's record: a relay's client acts on it as on its own (the owner's call), until the
	-- character announces a release, here or to a keeper who said so.
	return RelayClient() and e.cleared == nil
end

-- What a locked client may still say to us: its hello and its version answer (either may name a
-- release and clear the lock).
function Builds.Passes(text)
	local head = type(text) == "string" and text:sub(1, 3)
	return head == "H1~" or head == "V8~"
end

-- The sighting shown for `name`: ours, or (for those who keep the list) a reporter's; nil for none
-- or for the silent mark alone.
function Builds.Modified(name)
	if type(name) ~= "string" or name == "" then return nil end
	local e = Find(Full(name))
	if not e or e.how == "silent" or e.how == nil then return nil end
	if e.by ~= nil and not Privy() then return nil end
	return e
end

---------------------------------------------------------------------------
-- Silent to version checks (the weak mark)
---------------------------------------------------------------------------

-- Our check of `name` got no answer (Versions.lua's NoAnswer, PING_WAIT after it left at sentAt).
function Builds.Unanswered(name, sentAt)
	local full = Full(name)
	if full == "" or full == ns.me then return end
	local key, now = Key(full), ns.Now()
	local h = lastHello[key]
	-- No hello this session: not a guildmate announcing a version, nothing to hold against him.
	if not h then return end
	-- A version that is no release carries the strong mark already; one before 1.1.2 answers no check.
	if not Release(h.version) then return end
	local V, W = ns.Versions, ns.Workshop
	if V and W and type(W.Newer) == "function" and W.Newer(V.FIRST or "1.1.2", h.version) == true then return end
	local list = asks[key]
	-- A hello since the check before this one: his client was sending between the two. None: the
	-- count starts again from this check.
	if not list or #list == 0 or h.t <= list[#list] then list = {} end
	list[#list + 1] = sentAt or now
	asks[key] = list
	local fresh = V and V.HELLO_FRESH or 720
	if #list < Builds.SILENT_ASKS or list[#list] - list[1] < Builds.SILENT_SPAN or now - h.t > fresh then return end
	local e = Find(full) or Add(full, now)
	if not e then return end
	if e.how == nil or e.how == "silent" then
		e.how, e.version, e.by, e.locked = "silent", Builds.Clean(h.version), nil, nil
	end
	e.last = now
	e.silent = { n = #list, at = now }
	ns.Log("modified build: %s silent to %d version checks", full, #list)
end

-- `name` answered a check (any version): the count starts again, and the silent mark goes.
function Builds.Answered(name)
	local full = Full(name)
	if full == "" then return end
	asks[Key(full)] = nil
	local e = Find(full)
	if not e or not e.silent then return end
	e.silent = nil
	if e.how == "silent" then Remove(e) end
end

-- The weak mark on `name`: { n, at }, or nil.
function Builds.Silent(name)
	if type(name) ~= "string" or name == "" then return nil end
	local e = Find(Full(name))
	return e and e.silent or nil
end

---------------------------------------------------------------------------
-- Sharing (BD)
---------------------------------------------------------------------------

Share = function(e, now)
	if e.by ~= nil or e.how == "silent" or not Privy() then return false end
	local C = ns.Comm
	if not (C and C.Send) or (ns.IsMember ~= nil and not ns.IsMember()) then return false end
	if now - (shared[e.key] or -math.huge) < Builds.SHARE_GAP then return false end
	if Recent(shareTimes, 60, now) >= Builds.SHARE_PER_MIN then return false end
	local mine = GetGuildInfo and GetGuildInfo("player")
	if type(mine) ~= "string" or mine == "" then return false end
	local word = ("BD~1~%s~%s~%s~%s~%d~%d~%s"):format(mine, e.name, e.version, e.how == "answer" and "a" or "h",
		e.first or now, e.last or now, e.guild or "")
	if #word > 255 then return false end
	shared[e.key] = now
	shareTimes[#shareTimes + 1] = now
	C.Send("GUILD", word, "build:" .. e.key)
	C.Send("CHANNEL", word, "buildch:" .. e.key)
	return true
end

-- The character announced the release `version` to us: the keepers of the list are told (a "c"
-- word), once an hour per character at most, within the same minute's budget.
ShareClear = function(e, version, now)
	if not Privy() then return false end
	local C = ns.Comm
	if not (C and C.Send) or (ns.IsMember ~= nil and not ns.IsMember()) then return false end
	local key = "c:" .. e.key
	if now - (shared[key] or -math.huge) < Builds.SHARE_GAP then return false end
	if Recent(shareTimes, 60, now) >= Builds.SHARE_PER_MIN then return false end
	local mine = GetGuildInfo and GetGuildInfo("player")
	if type(mine) ~= "string" or mine == "" then return false end
	local word = ("BD~1~%s~%s~%s~c~%d~%d~%s"):format(mine, e.name, Builds.Clean(version), e.first or now, now, e.guild or "")
	if #word > 255 then return false end
	shared[key] = now
	shareTimes[#shareTimes + 1] = now
	C.Send("GUILD", word, "buildc:" .. e.key)
	C.Send("CHANNEL", word, "buildcch:" .. e.key)
	return true
end

-- A reporter's word heard: from a guild master or officer (the roster over GUILD, the census on
-- the channel), a councillor, the King or the author; kept by those who keep the list alone.
function Builds.HandleShare(dist, sender, text)
	if dist ~= "GUILD" and dist ~= "CHANNEL" then return end
	if not Privy() then return end
	local v, guild, name, version, how, first, last, their =
		tostring(text or ""):match("^BD~(%d+)~([^~]*)~([^~]+)~([^~]*)~([hac])~(%d+)~(%d+)~?([^~]*)$")
	if v ~= "1" or #name > Builds.NAME_MAX or not name:find("%a") or #guild > 48 or #their > 48 then return end
	-- A sighting names no release (no client shares one); a clear names the release announced.
	if Release(version) ~= (how == "c") then return end
	local full = Full(name)
	if full == "" or full == ns.me then return end
	local who = Full(sender)
	local WC = ns.WatchChat
	if WC and not WC.missing and type(WC.Barred) == "function" and WC.Barred("powers", who) then return end
	local rank
	if dist == "GUILD" then
		rank = ns.Roster and ns.Roster.RankOf and ns.Roster.RankOf(who)
	elseif ns.Data and ns.Data.AuthorizedRank and guild ~= "" then
		rank = ns.Data.AuthorizedRank(who, guild)
	end
	local officer = type(rank) == "number" and rank <= (ns.CAPTAIN_RANK or 1)
	-- (A relay's word is trusted as a guild master's: the owner's call.)
	if not (officer or (ns.IsHighCouncillor ~= nil and ns.IsHighCouncillor(who) == true)
		or (ns.IsAuthorName ~= nil and ns.IsAuthorName(who) == true)
		or (ns.IsKingCharacter ~= nil and ns.IsKingCharacter(who) == true)
		or IsRelayName(who)) then return end
	local now = ns.Now()
	last = math.min(tonumber(last) or now, now)
	if now - last > Builds.KEEP_AT_MOST then last = now end
	first = math.min(tonumber(first) or last, last)
	if now - first > Builds.KEEP_AT_MOST then first = last end
	if how == "c" then
		-- A keeper heard the character announce a release: a reporter's record is cleared (a relay's
		-- client lets the character back in); a mark this client made itself stands until the
		-- character says so to us; a sighting newer than the clear stands too.
		local e = Find(full)
		if not e or e.by == nil or e.how == "silent" or last < (e.last or 0) then return end
		if not e.cleared or last > (e.cleared.at or 0) then e.cleared = { version = Builds.Clean(version), at = last, by = who } end
		return
	end
	Observe(full, version, how == "a" and "answer" or "hello", last, who, first, their ~= "" and their or nil)
end

---------------------------------------------------------------------------
-- The view (/oly builds; the menu's detail line, Versions.lua)
---------------------------------------------------------------------------

local function How(e)
	if e.how == "silent" then return L.BUILDS_HOW_SILENT:format(e.silent and e.silent.n or Builds.SILENT_ASKS) end
	return e.how == "answer" and L.BUILDS_HOW_ANSWER or L.BUILDS_HOW_HELLO
end
local function By(e)
	return e.by and L.BUILDS_BY:format(ns.DisplayName(e.by)) or L.BUILDS_BY_YOU
end
local function Line(e)
	local name = ns.DisplayName(e.name) .. (e.guild and (" <" .. e.guild .. ">") or "")
	local text = ("%s  %s  %s, %s  (%s)"):format(name, Builds.Shown(e.version) or "?", How(e), ns.Ago(e.last or 0), By(e))
	if e.by == nil and e.how ~= "silent" and e.locked == false and e.release then
		text = text .. "; " .. L.BUILDS_CLEARED:format(e.release)
	elseif e.by ~= nil and e.cleared then
		text = text .. "; " .. L.BUILDS_CLEARED:format(tostring(e.cleared.version or "?"))
	elseif e.silent and e.how ~= "silent" then
		text = text .. "; " .. L.BUILDS_HOW_SILENT:format(e.silent.n)
	end
	return text
end

-- Every sighting this client may show: ours always, the reporters' for those who keep the list;
-- the ones online now (a hello in Comm's window) first, then the rest, newest first.
function Builds.Text()
	local list = Store() or {}
	local online = {}
	local C = ns.Comm
	if C and type(C.Peers) == "function" then
		for _, n in ipairs(C.Peers()) do online[Key(Full(n))] = true end
	end
	local privy = Privy()
	local on, off = {}, {}
	for _, e in ipairs(list) do
		if e.by == nil or privy then
			local t = online[e.key] and on or off
			t[#t + 1] = e
		end
	end
	table.sort(on, function(a, b) return a.name < b.name end)
	table.sort(off, function(a, b)
		if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
		return a.name < b.name
	end)
	local out = { L.BUILDS_HEAD:format(#on + #off), L.BUILDS_LOCK_NOTE, "" }
	if #on + #off == 0 then out[#out + 1] = L.BUILDS_NONE end
	if #on > 0 then
		out[#out + 1] = L.BUILDS_ONLINE
		for _, e in ipairs(on) do out[#out + 1] = "  " .. Line(e) end
	end
	if #off > 0 then
		if #on > 0 then out[#out + 1] = "" end
		out[#out + 1] = L.BUILDS_SEEN
		for _, e in ipairs(off) do out[#out + 1] = "  " .. Line(e) end
	end
	if not privy then
		out[#out + 1] = ""
		out[#out + 1] = L.BUILDS_MEMBERS_NOTE
	end
	return table.concat(out, "\n")
end

-- The copyable window (UI.ShowCopy), as every report of Olympus's: the owner cannot copy a chat line.
function Builds.Show()
	local UI = ns.UI
	if not (UI and UI.ShowCopy) then
		ns.Print(Builds.Text())
		return false
	end
	UI.ShowCopy(L.BUILDS_TITLE, Builds.Text(), nil, { key = "builds" })
	return true
end
function Builds.Slash() return Builds.Show() end

-- The menu's grey line under "Olympus <version> (modified build)" (Versions.MenuLines): where the
-- sighting came from and when, and that the client is locked out; a reporter's: his name.
function Builds.Detail(name)
	local e = Builds.Modified(name)
	if not e then return nil end
	local text
	if e.by ~= nil then text = L.VERSION_DETAIL_SHARED:format(ns.DisplayName(e.by), ns.Ago(e.last or 0))
	else text = (e.how == "answer" and L.VERSION_DETAIL_CHECK or L.VERSION_DETAIL_HELLO):format(ns.Ago(e.last or 0)) end
	-- (Locked: ours, or on a relay's client the list's too.)
	if Builds.Quarantined(e.name) then text = text .. "; " .. L.VERSION_DETAIL_LOCKED end
	return text
end

-- The sightings kept, for the tests and /oly status.
function Builds.Count()
	return #(Store() or {})
end

---------------------------------------------------------------------------
-- The author's ask to the locked clients online (his relay's client alone)
---------------------------------------------------------------------------

-- A word of a locked client reached Comm's door (dropped there, or its hello or version answer let
-- through): it is online now.
function Builds.Heard(sender)
	local e = Find(Full(sender))
	if e then heard[e.key] = ns.Now() end
end

-- Online, as this client can tell: its hello in our guild lately (Comm.Peers), or a word of its at
-- the door within ONLINE_FOR.
function Builds.Online(name, now)
	local e = type(name) == "string" and Find(Full(name))
	if not e then return false end
	now = now or ns.Now()
	if now - (heard[e.key] or -math.huge) <= Builds.ONLINE_FOR then return true end
	local C = ns.Comm
	if C and type(C.Peers) == "function" then
		for _, n in ipairs(C.Peers()) do
			local p = Find(Full(n))
			if p == e then return true end
		end
	end
	return false
end

-- Every PROMPT_EVERY on the author's relay client (see the top): his update ask to the locked
-- characters online. How many went.
function Builds.Prompt(now)
	now = now or ns.Now()
	if not (ns.IsAuthorName ~= nil and ns.IsAuthorName(ns.me) == true) or not RelayClient() then return 0 end
	local W = ns.Workshop
	if type(W) ~= "table" or W.missing or type(W.AskUpdate) ~= "function" or type(W.Latest) ~= "function" or not W.Latest() then return 0 end
	local list = Store()
	if not list then return 0 end
	for i = #promptTimes, 1, -1 do if now - promptTimes[i] >= Builds.PROMPT_EVERY then table.remove(promptTimes, i) end end
	local due = {}
	for _, e in ipairs(list) do
		if Builds.Quarantined(e.name) and now - (prompted[e.key] or -math.huge) >= Builds.PROMPT_EVERY and Builds.Online(e.name, now) then
			due[#due + 1] = e
		end
	end
	table.sort(due, function(a, b)
		local x, y = prompted[a.key] or -math.huge, prompted[b.key] or -math.huge
		if x ~= y then return x < y end
		return a.key < b.key
	end)
	local C, R, n = ns.Comm, ns.Relay, 0
	local room = C and type(C.QueueRoom) == "function" and C.QueueRoom() or (Builds.PROMPT_ROOM + Builds.PROMPT_MAX)
	local budget = math.min(Builds.PROMPT_MAX - #promptTimes, room - Builds.PROMPT_ROOM)
	for _, e in ipairs(due) do
		if n >= budget then break end
		prompted[e.key] = now
		promptTimes[#promptTimes + 1] = now
		-- (Gone offline since: the server's "No player named" stays out of his chat, as the relay's:
		-- 1.6.0, Comm.SendNow's Accord.Tried marks the ask when it goes; R.Quiet registers the filter.)
		if type(R) == "table" and type(R.Quiet) == "function" then R.Quiet(e.name) end
		if W.AskUpdate(e.name) then n = n + 1 end
	end
	-- Some waited for room in the queue, not for the hour's budget: once more in a minute.
	if #due > n and n >= budget and #promptTimes < Builds.PROMPT_MAX and not retrying then
		retrying = true
		Builds.after(60, "modified build prompts", function() retrying = false; Builds.Prompt() end)
	end
	if n > 0 then ns.Log("modified builds: the author's update ask to %d locked client(s)", n) end
	return n
end

function Builds.Reset() -- (tests)
	for k in pairs(heard) do heard[k] = nil end
	for k in pairs(prompted) do prompted[k] = nil end
	for i = #promptTimes, 1, -1 do promptTimes[i] = nil end
	retrying = false
	for k in pairs(lastHello) do lastHello[k] = nil end
	for k in pairs(asks) do asks[k] = nil end
	for k in pairs(shared) do shared[k] = nil end
	for i = #shareTimes, 1, -1 do shareTimes[i] = nil end
	indexed, byKey, byShort = nil, nil, nil
end

ns.Comm.Handle("BD", function(...) Builds.HandleShare(...) end)
ns.On("LOGIN", function()
	-- (Every client's ticker; Builds.Prompt does something on the author's relay client alone.)
	ns.Every(Builds.PROMPT_EVERY, "modified build prompts", function() Builds.Prompt() end)
end)
