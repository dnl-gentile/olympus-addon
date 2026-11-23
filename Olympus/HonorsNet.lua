local ADDON, ns = ...

-- 1.2, the Blood Arena: HonorsNet.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Level-race claims (IL), the donor holders' word (ID, also on GUILD from the Treasurer's own
-- client), the Oracle's (IO), the belt podium, and verification of a pick for any viewer through
-- Honors. Registers IL ID IO (sent in L whatever the live switch: Arena.LIVE_EXEMPT, but IL only
-- after a level-race launch). The honours
-- exemption of the weight rule: PLAYER_LEVEL_UP (acting at a multiple of 10) and one AP timer while
-- the pick is not the default, through ns.On/ns.Every.
-- API (the design): Verified(name) -> { frame, title, mark, chat }, Holdings(name), FrameTexture(key),
--   MarkTexture(key), ChatMark(key), TitleText(key), Levels(), Donors(), Oracle(), Podium(cat),
--   ChurchTop() (1.2.3: the Church's top 3 as ChurchCount.Top3 holds it, or nil);
--   NewPortrait(parent, size) and DressPortrait(rig, key): the player's own portrait with a frame;
--   (1.2.4) PickKnown(name), Standing(), Tell(held, known, told), Notices(), NoticeFrames().
-- The King's letter (the design) when an honour is earned: a popup of Olympus's own, queued.
-- (1.2.4) Once per place of each list per cycle; any other move a small notice (below). In an
-- instance or Busy one that would open by itself waits as Olympus's other popups do (ns.Alert's held
-- list), opened once he is out or by his own click.
local HonorsNet = {}
ns.HonorsNet = HonorsNet

-- One honours system for frames, nameplate marks, chat marks and titles (the design).
-- Every viewer works out what a player holds from his own facts (Honors.Holdings over the belts
-- and podium words, the level race's book, the Treasurer's donor word, a bank's Oracle word and the
-- census's best guild) and shows a player's pick only when it holds (Honors.Shown), else the rank's
-- frame: nobody can make another client show an honour he does not hold.
--
-- The words (the design, with its later changes):
--   IL gk~level~t                 the character itself, at PLAYER_LEVEL_UP to 20, 40 or 60 (the
--                                 design's level race: the FIRST to each), again 10 minutes and an
--                                 hour later, never once that milestone's place is known here. Each
--                                 client keeps the claim (timed when it first heard it) and counts it
--                                 vouched once it is a verified member's (H.Vouched, 1.2.1: our own
--                                 guild's roster, the server's, at or above that level, with his own
--                                 GUID; another guild's census, two of its senders other than him
--                                 listing him there, within 24 hours; never one census row) and (1.4.0,
--                                 the review's High 7) this client saw him cross it: below it first,
--                                 since the race's start, then there (our roster or his unit; or each
--                                 of those two senders' own reports), the last sighting below it at most
--                                 VOUCH_WINDOW before the claim (its from and since); only
--                                 vouched claims take the place, which stays unless the server's word
--                                 shows it false (H.CheckPlaces: his unit or our roster below it, or
--                                 the GUID not his; then it goes, and he never takes it again here,
--                                 by that GUID or by his name).
--   ID t~monthKey~m1,m2,m3~a1,a2,a3   names only: the month's top 3 donors and all time's (the
--                                 the design dropped the week's), from the Treasurer's characters'
--                                 client (or the King's), on the channel and on GUILD; the newest
--                                 wins; sent whatever the Treasury's ranking switches say. (1.3.4) The
--                                 King's client works out none where a Treasurer's word of the last
--                                 DONOR_TREASURER_DAYS is known (his book is not the treasury's); his
--                                 client and a signed High Councillor's say the Treasurer's last word
--                                 again as it is (H.RelayDonors), taken from them too.
--   IO monthKey~t~n1,n2,n3        the Oracle's gold, silver and bronze for that month, from a bank of
--                                 this realm's T1~B (the first open bank by sorted name); IO R~month~
--                                 rows by whisper: another bank's top 10 for it (name:profit:staked:
--                                 markets:first;...). The newest word for a month wins.
-- The podium (the belts' silver and bronze) is the clerk's AV 2 and 3 (ArenaLedger); the best guild
-- is the census's (Honors.GuildTop, its leader vouched by two senders). (1.2.3) The missionaries'
-- top 3 (the crook) is the Church's: ChurchCount.Top3, the newest NR~1~t word taken from the Head's,
-- the King's or the author's client (the server stamps its sender; ChurchCount.TakeTop refuses anyone
-- else's), held while the Church's public ranking is open and the word no older than
-- Honors.CHURCH_MAX_AGE. In this version only the author's client works it out (ChurchCount.SendTop: a
-- keeper whose root is W or H; the King's client is no keeper, and the Head is the King, root K), so
-- the crooks move only while the author's client is online with the ranking open, and every client
-- shows none 30 days after his last word. (1.3.4: the King's and the High Council's clients say his
-- last word again, ChurchCount.RelayTop, taken from them too: a client never online with his gets it.)
-- No word of its own here: the Church's comes on CHANNEL and
-- GUILD, and CHURCH_TOP_CHANGED (or the ranking's switch, CHURCH_PUBLIC_CHANGED) looks at the
-- honours again. (1.2.4) The same word's Apostles hold the cross. The Bones' charm is the last
-- month's top 3 of FarkleTable.Best (the games both players' halves agree on, as this client holds
-- them: no word of its own; kept in the honours store as it stood, never recounted from what its
-- store's cap left of that month); the slayers' skeletal horse the signed Slayers top 3
-- (Wanted.GlobalSnapshot, by GUID), looked at again when that word changes (WANTED_CHANGED); the
-- owl's guild master's own honours again when the census changes its first (DATA_CHANGED).
--
-- A newly earned honour switches on by itself (Honors.Update, unless the player locked his pick; 1.2.3:
-- only when told for the first time, so an honour earned again, its letter told already, leaves his
-- pick as it is), and the King's letter tells him: a parchment in a window of Olympus's own naming the
-- honour and its title, the new frame on his own portrait, "Wear it" and "Later"; queued when several come,
-- re-readable from the profile's Edit (ProfileEdit); once per honour per character (a month's honour:
-- once per month), never by itself where the save did not come back, and never to the King himself
-- (1.2.1). Honours count only in the live arena (Arena.Counts).
-- (1.2.4, the owner: "they must get the letter the first time they get it, and then smaller
-- notices ... less intrusive, a notice on the screen, not a pop-up, saying he dropped to second, that
-- he lost it because he left the list, that he is back on the list, that he regained it ... but only
-- the first time he reaches each level ... for something with a cycle, the monthly rankings, it is
-- the first time in the month, not the first time in his life"): the letter comes the first time a
-- character reaches each place of each list, per cycle (Honors.CYCLE: a closed month's list once a
-- month it ranks, so the same place two months running is two letters; a rolling one once per
-- calendar month; the others once in his life); every other move (down a place, off the list, back
-- on it, a place won back) is a notice: a strip of Olympus's own at the top of the screen, no
-- button, no mouse, no keyboard, gone in a few seconds, and a line in chat (H.Tell).

local L = ns.L
local H = HonorsNet
local Arena = ns.Arena
local B36, N = Arena.B36, Arena.N

H.MEDIA = "Interface\\AddOns\\Olympus\\media\\honors\\"
H.IL_AFTER = { 60, 600, 3600 }  -- IL this long after the level-up (and on AQ~H)
H.VOUCH_WINDOW = 86400          -- a census report this close to the claim vouches for it
H.VOUCHERS = 2                  -- census senders of one guild, not him, who must list him (1.2.1)
H.VOUCH_RULE = 3                -- the rule claims were vouched under (1.2.1: claims vouched before are looked at again;
                                -- 1.4.0: and again, his crossing seen here asked too)
H.CROSS_SLACK = 300             -- a sighting below the milestone this long after the claim still shows the crossing
                                -- (a report or a roster read a moment behind his level-up)
H.LAST_MAX = 20000              -- characters (and census senders' words on them) whose last level is kept this session
H.STRIKE_AFTER = 3600           -- a roster read this long after a place's time shows the level-up, or a lie
H.STRUCK_MAX = 20               -- places found false kept per milestone (the oldest goes)
H.CLAIMS_MAX = 200
H.CLAIM_DAYS = 7
H.DONOR_EVERY = 1800            -- the Treasurer's client says the donors again every 30 minutes
-- (1.3.4) The relays of his word (H.RelayDonors): the first DONOR_FIRST after the login (or the first word
-- held), then DONOR_EVERY + DONOR_GRACE after the last word heard (the same or a newer one) or said,
-- DONOR_JITTER at random more, the King's DONOR_KING_AFTER more again (his goes last; DONOR_GRACE: the
-- Treasurer's client, saying it every DONOR_EVERY, speaks first). The King works out no word of his own
-- where the Treasurer's of the last DONOR_TREASURER_DAYS is known.
H.DONOR_FIRST, H.DONOR_GRACE, H.DONOR_JITTER, H.DONOR_KING_AFTER = 300, 120, 300, 480
H.DONOR_TREASURER_DAYS = 30
H.random = function(a, b) return math.random(a, b) end
H.ORACLE_EVERY = 1800
H.LETTERS_MAX = 20
H.LETTER_PORTRAIT = 60          -- the letter's portrait: the size of his own on his unit frame
H.LETTER_W = 440                -- the letter's window across (its height follows its words)
H.LETTER_PAD = 16               -- the parchment's margin
H.SEAL_RED = { 0.78, 0.13, 0.11 } -- the King's wax seal, red (1.2.4, the author's ask)
-- (1.2.4, the author's ask: "use vermelho no selo de cera do rei": red wax, whatever the faction's
-- seal's own colour; its drawing kept, greyed, then tinted.)
function H.TintSeal(tex)
	if type(tex) ~= "table" then return end
	if tex.SetDesaturated then tex:SetDesaturated(true) end
	if tex.SetVertexColor then tex:SetVertexColor(H.SEAL_RED[1], H.SEAL_RED[2], H.SEAL_RED[3]) end
end
H.LETTER_FONT = 15              -- its words' size at least
H.LETTER_BUTTON = 120
H.REFRESH_DELAY = 60            -- after login, the own honours looked at once the words came in
-- (1.4.0, the owner's call) The level race runs from the launch of the new realms, on them alone: this
-- release switches it on, and it counts only where the author's signed list names this realm as a
-- launch realm and it is none of the beta's (ns.LaunchRealm). Elsewhere (the beta, a realm the list does
-- not name, a client that holds no list yet) it stays as 1.2.4 left it: nothing collected, sent,
-- relayed or worn, the old book kept untouched. A saved book, a timestamp, a wire word or the games'
-- live switch never starts it; no runtime setting either.
-- (1.5.5, the owner's call) Off again, everywhere: in its first days not everyone could be witnessed and
-- a bug showed comets nobody won. Its code and the saved book stay, dormant (nothing collected, sent,
-- relayed or awarded); the gold comet is the Olympus Speedrunner's alone (H.Holdings), the bronze and
-- silver ones are retired (Honors.RETIRED_LEVELS), and whoever was told or wore one gets the apology
-- once (H.ApologyDue).
H.LEVEL_RACE_LAUNCHED = false
function H.LevelRaceActive() return H.LEVEL_RACE_LAUNCHED == true and ns.LaunchRealm() == true end
-- The race's start (server time): 2026-11-04 00:00:00 UTC, the first second of launch day (the
-- realms' opening hour was not known for sure: about 23:00 UTC). On a launch realm nobody can have
-- levelled before it opened, so no real claim is ever older; the start is the second guard after the
-- realm's: a place, claim or clerk's record timed before it (a pre-launch book, saved data from a realm
-- of the same name) is never a launch place (H.Store drops them once, TakeRecords refuses them).
H.RACE_START = 1793750400

local stats = { refused = {}, claims = 0, vouched = 0, places = 0 }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function H.Stats() return stats end

local function Now() return Arena.Now() end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Short(name) return type(name) == "string" and ns.ShortName(ns.FullName(ns.Normal and ns.Normal(name) or name)):lower() or nil end
local function Gk(s)
	if type(s) ~= "string" or s == "-" or s == "" or #s > 24 then return nil end
	return Arena.GuidOf(s) and s or nil
end
-- A GUID as Honors compares it: the game's form (a gk turned back).
local function GameGuid(g)
	if type(g) ~= "string" then return nil end
	if g:find("^Player%-") then return g end
	return Arena.GuidOf(g)
end
H.GameGuid = GameGuid

---------------------------------------------------------------------------
-- The core's honours store (this realm's live store: honours count only in L)
---------------------------------------------------------------------------

-- (1.4.0) What a store kept from before the race's start (a pre-launch book or its claims, saved data
-- of a realm of the same name) is never a launch place: once the race runs here, its places and
-- claims timed before RACE_START (or untimed) go, with the sightings (h.lows), the first time the store
-- is opened for that start (h.raceStart). Where the race does not run, nothing is touched.
local function Launch(h)
	if h.raceStart == H.RACE_START or not H.LevelRaceActive() then return end
	local start = H.RACE_START
	for m, list in pairs(type(h.levels) == "table" and h.levels or {}) do
		local kept = {}
		for _, p in ipairs(type(list) == "table" and list or {}) do
			if type(p) == "table" and tonumber(p.t) and p.t >= start then kept[#kept + 1] = p end
		end
		h.levels[m] = kept[1] and kept or nil
	end
	for key, c in pairs(type(h.claims) == "table" and h.claims or {}) do
		if not (type(c) == "table" and tonumber(c.t) and c.t >= start) then h.claims[key] = nil end
	end
	h.lows = nil
	h.raceStart = start
end

function H.Store(make)
	local s = Arena.Store("L")
	if not s then return nil end
	if type(s.honors) ~= "table" then
		if not make then return nil end
		s.honors = {}
	end
	local h = s.honors
	if make then
		h.levels = type(h.levels) == "table" and h.levels or {}
		h.claims = type(h.claims) == "table" and h.claims or {}
		h.oracle = type(h.oracle) == "table" and h.oracle or {}
	end
	if h.raceStart ~= H.RACE_START then Launch(h) end
	return h
end

local gen = 0
local function Changed(name)
	gen = gen + 1
	ns.Fire("HONORS_CHANGED", name)
	Arena.Changed()
end
H.Changed = Changed
ns.On("DATA_CHANGED", function() gen = gen + 1 end)
ns.On("HONORS_CHANGED", function() gen = gen + 1 end)
-- (1.2.3) The Church's top 3 (a newer trusted word) or its public ranking's switch: the
-- missionaries' crooks, everyone's frames and our own honours looked at again.
ns.On("CHURCH_TOP_CHANGED", function() Changed() end)
ns.On("CHURCH_PUBLIC_CHANGED", function() Changed() end)

---------------------------------------------------------------------------
-- What a player holds, and what his pick shows
---------------------------------------------------------------------------

-- Contest counts come from the same scoped, merged rows the Census displays. A snapshot
-- supplies counts alone: it cannot appoint a guild master or rewrite a retained direct report.
local function CensusGuildRows()
	local D = ns.Data
	if type(D) ~= "table" or type(D.Summary) ~= "function" then return ns.rdb and ns.rdb.guilds or {} end
	local summary, rows = D.Summary(), {}
	for _, e in ipairs(type(summary) == "table" and summary.guilds or {}) do
		local g = e.g
		if type(g) == "table" then
			rows[#rows + 1] = { guild = e.name, total = g.total, avgLevel = g.avgLevel,
				t = tonumber(g.st) or g.t, faction = g.faction or (g.relayed and (ns.faction or "Alliance")) or "Alliance", off = g.off }
		end
	end
	return rows
end

-- Select the winning guild before resolving its leader from independent rank evidence.
-- An unknown winner withholds the owl; it never promotes a lower guild with a known leader.
local function BestGuild()
	local rows = CensusGuildRows()
	local M = ns.Moderation
	local top = ns.Honors.GuildTop(rows, { faction = ns.faction or "Alliance", now = ns.Now(), allowUnknownLeader = true, skip = function(guild)
		if not ns.IsFederation(guild) then return true end
		return type(M) == "table" and not M.missing and M.Guild and M.Guild(guild) ~= nil
	end })
	if not top then return nil end
	local D = ns.Data
	if type(D) ~= "table" or type(D.Guild) ~= "function" or type(D.KnownRank) ~= "function" then return nil end
	local source = D.Guild(top.guild)
	if type(source) ~= "table" or type(source.leader) ~= "string" or source.leader == "" then return nil end
	if ns.ReportInGroup and not ns.ReportInGroup(source, ns.group) then return nil end
	local leader = ns.FullName(source.leader, source.realm)
	local ok, rank, named = pcall(D.KnownRank, leader, top.guild)
	local mine = GetGuildInfo and GetGuildInfo("player")
	if not ok or rank ~= 0 or ((named or 0) < 2 and (not mine or top.guild:lower() ~= mine:lower())) then return nil end
	top.leader = source.leader
	return top
end

-- (1.2.3) The Church's top 3 as a trusted client published it (ChurchCount.Top3: nil while the
-- public ranking is closed or none was heard), or nil.
local function ChurchTop()
	local C = ns.ChurchCount
	if type(C) ~= "table" or C.missing or type(C.Top3) ~= "function" then return nil end
	local ok, top = pcall(C.Top3)
	if not ok or type(top) ~= "table" or type(top.missionaries) ~= "table" then return nil end
	return top
end
H.ChurchTop = ChurchTop

-- (1.2.4) A closed month's Bone Throw list (the charm's, held through the month after it) as this
-- client last worked it out, kept in the honours store: bones = { side, monthNo, n, names }, n the
-- games that list read then (FarkleTable.Best's second value: the month's, and the days before it
-- the pair cap counts). FarkleTable keeps HALVES_MAX games, the oldest going first past it, and the
-- oldest are those: holding fewer of them now (pruned here), the list kept stands, the same all
-- month; as many or more (a game heard late; a player hidden here, the same games), worked out
-- again and kept. (Recounted from what was left, the charm went to another top 3 partway through
-- the month it is held in, each client at its own prune: "out" for its holder, a letter for a place
-- nobody held when the month closed.)
local function KeptBones(month, names, n)
	local side = tostring(ns.faction or "Alliance")
	local s = H.Store(n > 0)
	local kept = s and type(s.bones) == "table" and s.bones or nil
	local same = kept ~= nil and kept.side == side and tonumber(kept.monthNo) == month and type(kept.names) == "table"
	if same and n < (tonumber(kept.n) or 0) then
		local out = {}
		for _, name in ipairs(kept.names) do
			if #out >= ns.Honors.BONES_PLACES then break end
			if type(name) == "string" then out[#out + 1] = name end
		end
		return out
	end
	if s and n > 0 and not (same and kept.n == n and table.concat(kept.names, "\n") == table.concat(names, "\n")) then
		s.bones = { side = side, monthNo = month, n = n, names = names }
	end
	return names
end

-- (1.2.4) Bone Throw's top 3 of a month as this client counts it (FarkleTable.Best: the games both
-- players' halves agree on), with at least one win; nil where the build has no Bones table. A month
-- closed: as it stood before this client pruned its games (KeptBones).
local function BonesTop(month)
	local FT = ns.FarkleTable
	if type(FT) ~= "table" or FT.missing or type(FT.Best) ~= "function" then return nil end
	local ok, rows, held = pcall(FT.Best, "L", { month = month })
	if not ok or type(rows) ~= "table" then return nil end
	local names = {}
	for _, r in ipairs(rows) do
		if #names >= ns.Honors.BONES_PLACES then break end
		if type(r) == "table" and type(r.name) == "string" and (tonumber(r.won) or 0) >= 1 then names[#names + 1] = r.name end
	end
	if month < ns.Honors.MonthOf(Now()) then names = KeptBones(month, names, tonumber(held) or 0) end
	local out = {}
	for i, name in ipairs(names) do out[i] = { name = name, place = i } end
	return { month = out, monthNo = month }
end
H.BonesTop = BonesTop
-- (1.2.4) FarkleTable about to prune agreed games past its cap (the oldest first, the last month's):
-- that month's list kept first, as it stands now, on every client (no look may have asked yet).
ns.On("BONES_PRUNING", function() BonesTop(ns.Honors.MonthOf(Now()) - 1) end)

-- (1.2.4) The Slayers' signed top 3 this client shows now (Wanted.GlobalSnapshot: an authenticated,
-- unexpired word of a role holder), or nil.
local function WantedTop()
	local W = ns.Wanted
	if type(W) ~= "table" or W.missing or W.GLOBAL_BORDERS_ACTIVE ~= true or type(W.GlobalSnapshot) ~= "function" then return nil end
	local ok, g = pcall(W.GlobalSnapshot)
	if not ok or type(g) ~= "table" or type(g.rows) ~= "table" then return nil end
	return g
end
H.WantedTop = WantedTop
-- (1.2.4) That word changed (a newer one, its expiry, its issuer's role gone): the horses, everyone's
-- frames and our own honours looked at again. WANTED_CHANGED comes with every kill shared too: only a
-- change of the word itself counts.
local wantedWord
ns.On("WANTED_CHANGED", function()
	local g = WantedTop()
	local word = g and table.concat({ tostring(g.issuer), tostring(g.epoch), tostring(g.seq), tostring(g.issued) }, "|") or ""
	if word == wantedWord then return end
	local had = wantedWord
	wantedWord = word
	if had ~= nil or word ~= "" then Changed() end
end)
-- A different guild can win while the target's own report stays unchanged. Every viewer
-- invalidates drawn honours when the winner changes, once BEST_SOON after a burst of reports.
H.BEST_SOON = 5
local bestKey, bestDue = nil, false
ns.On("DATA_CHANGED", function()
	if bestDue then return end
	bestDue = true
	ns.After(H.BEST_SOON, "arena best guild", function()
		bestDue = false
		local top = BestGuild()
		local key = top and (top.guild .. "|" .. top.leader) or ""
		if key == bestKey then return end
		local had = bestKey
		bestKey = key
		if had ~= nil or key ~= "" then Changed() end
	end)
end)

local inputs, inputsGen, inputsAt, inputsRace
-- The facts every Holdings call takes (kept while nothing changed, a minute at most).
function H.Inputs()
	local now = Now()
	local race = H.LevelRaceActive()
	if inputs and inputsGen == gen and inputsAt == math.floor(now / 60) and inputsRace == race then return inputs end
	local LG = ns.ArenaLedger
	local store = H.Store()
	local donors = store and store.donors
	local oracle = store and store.oracle
	local lastMonth = ns.Honors.MonthOf(now) - 1
	local ow = oracle and oracle[lastMonth]
	local function Places(names)
		local out = {}
		for i, name in ipairs(names or {}) do out[i] = { name = name, place = i } end
		return out
	end
	local tiers = {}
	for gk, tier in pairs(LG and LG.Tiers and LG.Tiers("L") or {}) do
		tiers[gk] = tier
		local g = Arena.GuidOf(gk)
		if g then tiers[g] = tier end
	end
	local church = ChurchTop()
	local guild = BestGuild()
	-- A frame may be drawn before the first coalesced census look. Remember that first
	-- observed winner so its removal still redraws it; an initially empty contest stays quiet.
	if bestKey == nil then bestKey = guild and (guild.guild .. "|" .. guild.leader) or "" end
	inputs = {
		belts = LG and LG.Holders and LG.Holders("L") or {},
		podium = LG and LG.PodiumWords and LG.PodiumWords("L") or {},
		tiers = tiers,
		donors = donors and { all = Places(donors.all), month = Places(donors.month), monthNo = donors.monthNo } or nil,
		-- Retain the historical book, but it awards no title, frame, mark or letter before launch.
		levels = race and store and store.levels or {},
		guild = guild,
		oracle = ow and { month = Places(ow.names), monthNo = lastMonth } or nil,
		church = church and { missionaries = Places(church.missionaries), apostles = Places(church.apostles), at = church.at } or nil,
		bones = BonesTop(lastMonth),
		wanted = WantedTop(),
		now = now,
	}
	inputsGen, inputsAt, inputsRace = gen, math.floor(now / 60), race
	return inputs
end

-- The player's guild as this client knows it: his unit's, our own's, the census's word on him.
local function GuildOf(name)
	if Same(name, ns.me) then return GetGuildInfo and GetGuildInfo("player") or nil end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.GuildOf then
		local ok, g = pcall(M.GuildOf, name)
		if ok and type(g) == "string" then return g end
	end
	return nil
end

-- Every honour `name` holds as this client sees it (guid: the game's or the arena's form, only
-- when known for sure: a unit's, or a verified profile's).
function H.Holdings(name, guid)
	if type(name) ~= "string" then return {} end
	-- (The dev's own character, as the core's borders know him: no arena file names the author.)
	local B = ns.Borders
	local author = type(B) == "table" and type(B.IsDevName) == "function" and B.IsDevName(ns.FullName(name)) == true
	-- (1.5.5) The Olympus Speedrunner, as the author's signed list names him (ns.IsSpeedrunnerName).
	local speedrunner = type(ns.IsSpeedrunnerName) == "function" and ns.IsSpeedrunnerName(ns.FullName(name)) == true
	return ns.Honors.Holdings({ name = name, guid = GameGuid(guid), guild = GuildOf(name), author = author, speedrunner = speedrunner },
		H.Inputs())
end

-- A player's pick as heard (or ours), and a GUID for him we are sure of.
local function PickOf(name)
	local P = ns.ArenaProfile
	if Same(name, ns.me) then return P.Pick(), P.MyGk() end
	local p = P.Of(name)
	if not p then return nil, nil end
	return { frame = p.frame or "rank", title = p.title }, p.verified and p.gk or nil
end

-- (1.2.4) This client knows the player's pick: ours, or a profile heard (Wanted.GlobalBorder then
-- leaves the slayers' frame to it, Verified: "none", another frame he holds, the horse he picked).
function H.PickKnown(name)
	if type(name) ~= "string" or name == "" then return false end
	if Same(name, ns.me) then return true end
	local P = ns.ArenaProfile
	if type(P) ~= "table" or P.missing or type(P.Of) ~= "function" then return false end
	local ok, p = pcall(P.Of, name)
	return ok and type(p) == "table"
end

local cache, cacheGen, cacheHour, cacheRace = {}, -1, -1, nil
-- What a player's pick shows to this client (the design): { frame (an honour key, "rank" or "none"),
-- title (an honour key or nil), mark (the honour's art, or "rank"), chat (the honour's art for a
-- chat mark, or nil), honour (the honour shown), art, shape, metal, milestone }.
-- guid: a unit's GUID (the Borders' and Nameplates'), which beats a profile's.
function H.Verified(name, guid)
	if type(name) ~= "string" or name == "" then return { frame = "rank", mark = "rank" } end
	local key = ns.FullName(name):lower() .. "|" .. tostring(guid)
	-- Kept while nothing changed, and never past the hour: the month's koi and ravens turn over with
	-- the clock alone (no word comes when a month ends).
	local hour = math.floor(Now() / 3600)
	local race = H.LevelRaceActive()
	if cacheGen ~= gen or cacheHour ~= hour or cacheRace ~= race then cache, cacheGen, cacheHour, cacheRace = {}, gen, hour, race end
	if cache[key] then return cache[key] end
	local pick, known = PickOf(name)
	local v = { frame = "rank", mark = "rank" }
	if pick then
		local held = H.Holdings(name, guid or known)
		local frame, mark, title, h = ns.Honors.Shown(pick, held)
		v.frame, v.mark, v.title, v.honour = frame, mark, title, h
		if h then v.art, v.shape, v.metal, v.milestone, v.chat = h.art, h.shape, h.metal, h.milestone, h.art end
	end
	cache[key] = v
	return v
end

-- The textures: a frame's (its shape too), its nameplate mark, its chat mark ("|T...|t", never a %).
function H.FrameTexture(key)
	local art, shape = ns.Honors.ArtOf(key)
	if not art then return nil end
	return H.MEDIA .. art, shape
end
function H.MarkTexture(key)
	local art = ns.Honors.ArtOf(key) or (type(key) == "string" and key:match("^[%l%-]+%-%l+$") and key) or nil
	if not art then return nil end
	return H.MEDIA .. art .. "-mark"
end
function H.ChatMark(key)
	local tex = H.MarkTexture(key)
	if not tex or tex:find("%", 1, true) then return nil end
	return "|T" .. tex .. ":0|t"
end

-- The player's own portrait with a frame on it, in the core's windows (the King's letter, the
-- profile's Edit, the Arena's own letter): Borders.NewPortrait, the builder of the Arena's
-- portraits too (1.2, the owner's ask: every Olympus portrait identical to his own on his unit
-- frame: the same picture, mask and ring, and the same art at the same offsets, turned round as
-- his own). `size` across; its slot is the square the window places, its reach how far its art
-- may reach past it (Borders.SizePortrait), for the window's words to keep clear. Where
-- Borders.lua is the core's stand-in, the picture alone, square, and no frame.
function H.NewPortrait(parent, size)
	local B = ns.Borders
	local rig = B.missing ~= true and B.NewPortrait(parent, size) or nil
	if type(rig) == "table" then return rig end
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetSize(size, size)
	return { slot = tex, portrait = tex, plain = true, reach = { left = 0, right = 0, top = 0, bottom = 0 } }
end
-- It filled: his live picture (square, as his unit frame asks SetPortraitTexture for it: the
-- rig's mask rounds it) and the frame `key` names: an honour's (its art, as round his own
-- portrait, Borders.ShowHonour; none where this client has no art for it), "rank" his rank's
-- border as his own frame works it out (Borders.TierOf), "none" or nil none. What shows:
-- "honour", "rank" or nil.
function H.DressPortrait(rig, key)
	if SetPortraitTexture then pcall(SetPortraitTexture, rig.portrait, "player", not rig.plain) end
	if rig.plain then return nil end
	local B = ns.Borders
	if type(key) == "string" and key ~= "rank" and key ~= "none" then
		if B.ShowHonour(rig, key) then return "honour" end
		B.ShowTier(rig, nil)
		return nil
	end
	local tier = key == "rank" and B.TierOf("player") or nil
	B.ShowTier(rig, tier)
	return tier and "rank" or nil
end
-- The arena division's crossed swords (a tier's badge): the game's icon and the metal's colour.
H.BADGE_ICONS = { "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\INV_Sword_27" }
H.METAL_COLOR = { gold = { 1, 0.82, 0 }, silver = { 0.78, 0.8, 0.85 }, bronze = { 0.62, 0.46, 0.34 } }
function H.BadgeTexture(tier)
	local UI = ns.UI
	local tex = type(UI) == "table" and UI.FirstTexture and UI.FirstTexture(H.BADGE_ICONS) or H.BADGE_ICONS[1]
	return tex, H.METAL_COLOR[tier]
end

-- A title's words (the design; one locale table so the moderators can edit them).
local CLASS_FILE = { warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST", shaman = "SHAMAN",
	mage = "MAGE", warlock = "WARLOCK", druid = "DRUID" }
local RACE_ID = { human = 1, orc = 2, dwarf = 3, nightelf = 4, undead = 5, tauren = 6, gnome = 7, troll = 8 }
-- (1.5.5, the independent check) A retired comet of the level race (bronze and silver:
-- Honors.RETIRED_LEVELS). A letter of one kept from the race (a character the apology has not reached
-- yet, a non-member, the Speedrunner himself) showed the gold comet's words with its raw key for a
-- title: it reads as retired, in words of its own (L.HONOR_LETTER["level-retired"],
-- L.HONOR_RETIRED_TITLE), with nothing to wear.
local function RetiredKey(key)
	local m = type(key) == "string" and tonumber(key:match("^level%-race%-(%d+)$")) or nil
	local R = type(ns.Honors) == "table" and ns.Honors.RETIRED_LEVELS or nil
	return m ~= nil and type(R) == "table" and R[m] == true
end
H.RetiredKey = RetiredKey
function H.TitleText(key)
	if type(key) ~= "string" then return nil end
	-- (1.5.5: the level race's apology names no honour: its line's name in the lists; so a retired comet's.)
	if key == H.APOLOGY_KEY then return L.HONOR_APOLOGY_TITLE end
	if RetiredKey(key) then return L.HONOR_RETIRED_TITLE end
	-- (1.2.4: the Most Wanted Slayer letter's family, "wanted@": its title is Wanted.lua's, read
	-- from its key alone, Wanted.LetterTitle.)
	if key:find("^wanted@") then
		local W = ns.Wanted
		return type(W) == "table" and not W.missing and type(W.LetterTitle) == "function" and W.LetterTitle(key) or nil
	end
	local fixed = L.HONOR_TITLES and L.HONOR_TITLES[key]
	if fixed then return fixed end
	local base, place = key:match("^(.-)%-([23])$")
	if not base then base, place = key, "1" end
	place = tonumber(place)
	local class = base:match("^arena%-class%-(%l+)$")
	if class then
		local names = LOCALIZED_CLASS_NAMES_MALE
		local name = (type(names) == "table" and names[CLASS_FILE[class] or ""]) or (L.HONOR_CLASS_NAMES and L.HONOR_CLASS_NAMES[class]) or class
		return (L.HONOR_CLASS_TITLE[place] or L.HONOR_CLASS_TITLE[1]):format(name)
	end
	local race = base:match("^arena%-race%-(%l+)$")
	if race then
		local name = L.HONOR_RACE_NAMES and L.HONOR_RACE_NAMES[race] or race
		local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
		if type(info) == "function" and RACE_ID[race] then
			local ok, r = pcall(info, RACE_ID[race])
			if ok and type(r) == "table" and type(r.raceName) == "string" then name = r.raceName end
		end
		return (L.HONOR_RACE_TITLE[place] or L.HONOR_RACE_TITLE[1]):format(name)
	end
	return nil
end
-- The honour's name in the list (the title, with its metal and what it is for).
function H.Label(key)
	local title = H.TitleText(key)
	local _, _, metal = ns.Honors.ArtOf(key)
	return title, metal
end

function H.Levels()
	-- The historical book remains readable; live award inputs are separately gated in Inputs.
	local s = H.Store()
	return s and s.levels or {}
end
function H.Donors()
	local s = H.Store()
	return s and s.donors or nil
end
function H.Oracle(month)
	local s = H.Store()
	month = month or (ns.Honors.MonthOf(Now()) - 1)
	return s and s.oracle and s.oracle[month] or nil
end
-- A belt category's podium as this client holds it: { [2] = { gk, name }, [3] = ... }.
function H.Podium(cat)
	local out = {}
	local LG = ns.ArenaLedger
	for _, p in ipairs(LG and LG.PodiumWords and LG.PodiumWords("L") or {}) do
		if p.cat == cat then out[p.place] = { gk = p.gk, name = p.name } end
	end
	return out
end

---------------------------------------------------------------------------
-- The level race (IL, and the clerk's AB~H)
---------------------------------------------------------------------------

local function Placed(m)
	local s = H.Store()
	local list = s and s.levels and s.levels[m]
	return type(list) == "table" and list[1] ~= nil
end
H.Placed = Placed

-- Our own claim: sent at the level-up's moments, never once the place is known.
local claimed = {} -- [level] = t
function H.SendClaim(level)
	if not H.LevelRaceActive() then return false, "level-race-off" end
	if Placed(level) then return false, "placed" end
	local gk = ns.ArenaProfile.MyGk()
	if not gk then return false, "gk" end
	local t = claimed[level] or Now()
	claimed[level] = t
	return Arena.Send("IL", "L", table.concat({ gk, B36(level), B36(t) }, "~"))
end
function H.OnLevelUp(level)
	if not H.LevelRaceActive() then return false, "level-race-off" end
	level = tonumber(level)
	if not level or not ns.Honors.LEVEL_METAL[level] or Placed(level) then return end
	claimed[level] = claimed[level] or Now()
	for _, after in ipairs(H.IL_AFTER) do
		ns.After(after, "arena level claim", function() H.SendClaim(level) end)
	end
end

-- The honours exemption (the design): PLAYER_LEVEL_UP only on a character that can still
-- reach a milestone whose place is not known here.
local levelHooked = false
function H.WatchLevels()
	if not H.LevelRaceActive() then return false end
	if levelHooked then return true end
	local level = UnitLevel and tonumber(UnitLevel("player")) or 60
	local open = false
	for _, m in ipairs(ns.Honors.MILESTONES) do if m > level and not Placed(m) then open = true end end
	if not open then return false end
	levelHooked = true
	ns.RegisterEvent("PLAYER_LEVEL_UP", function(newLevel) ns.SafeCall("arena level up", H.OnLevelUp, newLevel) end)
	return true
end

-- A value the client hides from addons counts as none.
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- Our own guild's roster as the server gives it (Roster.Fresh: a whole, recent read of our guild):
-- a member's level, by name; nil, true for a fresh roster without him; nil, false for none fresh.
local rosterOf, rosterLevels
-- Every member's level by his full name (lower case), worked out once per read; nil with none fresh.
local function RosterRead()
	local R = ns.Roster
	local fresh = type(R) == "table" and type(R.Fresh) == "function" and R.Fresh() or nil
	if type(fresh) ~= "table" or type(fresh.members) ~= "table" then return nil end
	if rosterOf ~= fresh.members then
		rosterOf, rosterLevels = fresh.members, {}
		for _, m in ipairs(fresh.members) do
			if type(m) == "table" and type(m.full) == "string" and tonumber(m.level) then rosterLevels[m.full:lower()] = tonumber(m.level) end
		end
	end
	return rosterLevels
end
local function RosterLevel(name)
	local levels = type(name) == "string" and RosterRead() or nil
	if not levels then return nil, false end
	return levels[ns.FullName(name):lower()], true
end
-- In our guild by our roster (fresh or not): the server's word on him, never another guild's census.
local function Guildmate(name)
	local R = ns.Roster
	return type(R) == "table" and type(R.RankOf) == "function" and R.RankOf(name) ~= nil
end
-- A character's level as the game gives it for a unit it knows by his GUID (a party, a target, a
-- nameplate), or nil.
local function UnitLevelOf(guid)
	if type(guid) ~= "string" or type(UnitTokenFromGUID) ~= "function" or type(UnitLevel) ~= "function" then return nil end
	local ok, token = pcall(UnitTokenFromGUID, guid)
	if not ok or type(token) ~= "string" or Secret(token) then return nil end
	local okL, level = pcall(UnitLevel, token)
	if not okL or Secret(level) or type(level) ~= "number" or level < 1 then return nil end
	return level
end
-- The players this client has in view now, by their full names (a forged claim's GUID may be one
-- the game never gives, so his unit is found by his name, which the server sets): { [name, lower
-- case] = { guid, level (nil: not given) } }.
H.SEEN_UNITS = { "target", "focus", "mouseover", "party1", "party2", "party3", "party4" }
local function SeenUnits()
	local out = {}
	if type(UnitExists) ~= "function" or type(UnitGUID) ~= "function" then return out end
	for _, token in ipairs(H.SEEN_UNITS) do
		local ok, exists = pcall(UnitExists, token)
		local okP, player = true, true
		if type(UnitIsPlayer) == "function" then okP, player = pcall(UnitIsPlayer, token) end
		if ok and not Secret(exists) and exists and okP and not Secret(player) and player then
			local name = ns.UnitFullName(token)
			local okG, guid = pcall(UnitGUID, token)
			if type(name) == "string" and okG and type(guid) == "string" and not Secret(guid) then
				local okL, level = true, nil
				if type(UnitLevel) == "function" then okL, level = pcall(UnitLevel, token) end
				if not okL or Secret(level) or type(level) ~= "number" or level < 1 then level = nil end
				out[ns.FullName(name):lower()] = { guid = guid, level = level }
			end
		end
	end
	return out
end

-- Short names as H.Vouched compares them (Short), kept once worked out (1.2.1, the stutter players
-- reported: every census report heard made the race work out again every name of every report for
-- every claim waiting, a fifth of a second and more on a release client). Kept only for a name whose
-- short form can't change with what this client learns of realms: one without "-", one whose first
-- part has a space (Forever's "First Surname-Realm"), or any while names are not split (ns.Normal
-- leaves them be). Returns the short name and whether it is such a name.
H.SHORTS_MAX = 5000
local shorts, shortsCount, shortsSplit = {}, 0, false
local function ShortOf(name)
	if type(name) ~= "string" then return nil, true end
	local split = ns.splitNames and true or false
	if split ~= shortsSplit then shorts, shortsCount, shortsSplit = {}, 0, split end
	local v = shorts[name]
	if v then return v, true end
	v = Short(name)
	local dash = name:find("-", 1, true)
	local space = dash and name:find(" ", 1, true)
	if split and dash and not (space and space < dash) then return v, false end
	if shortsCount >= H.SHORTS_MAX then shorts, shortsCount = {}, 0 end
	shorts[name], shortsCount = v, shortsCount + 1
	return v, true
end

-- (1.4.0, the review's High 7: a player already at or above an open milestone took it with one IL,
-- since nothing showed when he got there.) The crossings this client saw: each character's level as
-- last seen here this session (lastLv, lastAt: local time) and, where a later sighting puts him at or
-- above an open milestone, the last time he was seen below it (s.lows[m][key], kept in the store). Only
-- the server's word and each census sender's own word count, never one mixed into another: key is his
-- full name in lower case for our roster's reads and the players in view (the server's), and
-- "sender>name" (short names) for what one census sender's own reports said of him. A sighting below
-- one already heard from the same source is a word behind it (levels never go down): nothing learnt.
-- Taken once the race has started, while a milestone is open.
local lastLv, lastAt, lastN = {}, {}, 0
local seenRoster, lowsPruned = nil, 0
local walked = setmetatable({}, { __mode = "k" }) -- [a census row] = its time when it was taken here
local walkedSplit = false -- (names split or not when they were: ShortOf's names change with it)
local function Saw(open, key, level, t, touched, who)
	local was = lastLv[key]
	if was ~= nil and level < was then return end
	if was == nil then
		if lastN >= H.LAST_MAX then lastLv, lastAt, lastN = {}, {}, 0 end
		lastN = lastN + 1
	elseif level > was then
		for m, list in pairs(open) do
			if was < m and m <= level then
				list[key] = lastAt[key]
				touched[who] = true
			end
		end
	end
	if was == nil or level > was or t > (lastAt[key] or 0) then lastAt[key] = t end
	lastLv[key] = level
end
-- What this client sees now: our roster (once per read: a new Roster.members), the players in view,
-- and each census row once (once more when its time changes: the same report again; all of them again
-- when this client starts or stops splitting names), as it is taken (a row is seen before another
-- report replaces it, Data.ChangedSoon). Returns the names seen anew or seen crossing (short, from the
-- census; full in lower case, the server's word), with ["#roster"] when our roster was read anew; nil
-- where nothing is taken (the race not running here or not started, every milestone placed).
local ROSTER = "#roster"
local function Sightings(s)
	if type(s) ~= "table" or not H.LevelRaceActive() or Now() < H.RACE_START then return nil end
	local lows = type(s.lows) == "table" and s.lows or {}
	local open, any = {}, false
	for _, m in ipairs(ns.Honors.MILESTONES) do
		if Placed(m) then lows[m] = nil
		else
			lows[m] = type(lows[m]) == "table" and lows[m] or {}
			open[m], any = lows[m], true
		end
	end
	if not any then return nil end
	s.lows = lows
	local now, touched = ns.Now(), {}
	-- (A crossing older than any claim it could still show: gone, once an hour.)
	if now - lowsPruned >= 3600 then
		lowsPruned = now
		for _, list in pairs(open) do
			for key, t in pairs(list) do
				if now - (tonumber(t) or 0) > 2 * H.VOUCH_WINDOW + H.CROSS_SLACK then list[key] = nil end
			end
		end
	end
	local levels = RosterRead()
	if levels and rosterOf ~= seenRoster then
		seenRoster, touched[ROSTER] = rosterOf, true
		for full, level in pairs(levels) do Saw(open, full, level, now, touched, full) end
	end
	for full, u in pairs(SeenUnits()) do
		if u.level then Saw(open, full, u.level, now, touched, full) end
	end
	local rows = ns.rdb and ns.rdb.guilds
	if (ns.splitNames and true or false) ~= walkedSplit then
		walked, walkedSplit = setmetatable({}, { __mode = "k" }), ns.splitNames and true or false
	end
	for _, r in pairs(type(rows) == "table" and rows or {}) do
		local t = type(r) == "table" and tonumber(r.t) or nil
		if t and walked[r] ~= t and not r.mine and type(r.reporterFull) == "string" and type(r.top) == "table" then
			walked[r] = t
			local k = ShortOf(r.reporterFull)
			for _, x in ipairs(r.top) do
				local who = type(x) == "table" and ShortOf(x.name) or nil
				local level = type(x) == "table" and tonumber(x.level) or nil
				if k and who and level and who ~= k then
					touched[who] = true
					Saw(open, k .. ">" .. who, level, t, touched, who)
				end
			end
		end
	end
	return touched
end
-- When `key` was last seen below the claim's milestone before a sighting at or above it, where that is
-- the claim's crossing: at most VOUCH_WINDOW before the claim was heard (or CROSS_SLACK after it: a
-- report or a roster read a moment behind his level-up); else nil.
local function Crossing(c, key)
	local s = H.Store()
	local list = s and type(s.lows) == "table" and s.lows[c.level] or nil
	local low = type(list) == "table" and tonumber(list[key]) or nil
	local heard = tonumber(c.heardLocal)
	if not (low and heard) or low > heard + H.CROSS_SLACK or heard - low > H.VOUCH_WINDOW then return nil end
	return low
end
-- A claim shown crossing at `low`: its from (below the milestone: the level less one, all a sighting
-- below it says) and since (that sighting, on the claim's clock: never after its t), for Honors.LevelRace.
local function Proven(c, low)
	if not low then return false end
	local heard = tonumber(c.heardLocal) or low
	c.from = c.level - 1
	c.since = (tonumber(c.t) or Now()) - math.max(0, heard - low)
	return true
end

-- The census's tops by the short name of each player they list (1.2.1): the rows listing him, in
-- the order pairs gives the rows (the order H.Vouched always went through them), each with the
-- highest level it lists him at (by[short]: { r, guild, level, nxt }, a chain). Worked out again
-- only when the rows changed: Data.Revision where the census has one, and in any case another row
-- in a place, another top, or another name or level in one, or a name whose short form hangs on the
-- realms this client knows (ShortOf: worked out again each time) that now reads otherwise. What a
-- row says beside its top (its sender, its time, our own) is read from the row itself when it is
-- looked at.
local listing = { by = {}, tails = {}, pool = {}, used = 0, keys = {}, refs = {}, tops = {}, xs = {}, xn = {}, xl = {}, n = 0, m = 0,
	loose = {}, looseShort = {}, nLoose = 0, builds = 0 }
local function Revision()
	local D = ns.Data
	if type(D) ~= "table" or type(D.Revision) ~= "function" then return nil end
	local ok, rev = pcall(D.Revision)
	return ok and rev or nil
end
local function ListingHolds(rows)
	local T = listing
	if T.rows ~= rows or T.split ~= (ns.splitNames and true or false) or T.rev ~= Revision() then return false end
	local keys, refs, tops, xs, xn, xl = T.keys, T.refs, T.tops, T.xs, T.xn, T.xl
	local i, j = 0, 0
	for guild, r in pairs(rows) do
		i = i + 1
		if keys[i] ~= guild or refs[i] ~= r then return false end
		local top = type(r) == "table" and r.top or nil
		if tops[i] ~= top then return false end
		if type(top) == "table" then
			for _, x in ipairs(top) do
				j = j + 1
				if xs[j] ~= x or (type(x) == "table" and (xn[j] ~= x.name or xl[j] ~= x.level)) then return false end
			end
		end
	end
	if i ~= T.n or j ~= T.m then return false end
	for k = 1, T.nLoose do
		local at = T.loose[k]
		if ShortOf(xn[at]) ~= T.looseShort[at] then return false end
	end
	return true
end
local function ListingBuild(rows)
	local T = listing
	local by, tails, pool = T.by, T.tails, T.pool
	for k in pairs(by) do by[k] = nil end
	for k in pairs(tails) do tails[k] = nil end
	local keys, refs, tops, xs, xn, xl = T.keys, T.refs, T.tops, T.xs, T.xn, T.xl
	local i, j, used, nLoose = 0, 0, 0, 0
	local loose, looseShort = T.loose, T.looseShort
	for k = 1, T.nLoose do
		looseShort[loose[k]] = nil
		loose[k] = nil
	end
	for guild, r in pairs(rows) do
		i = i + 1
		local top = type(r) == "table" and r.top or nil
		keys[i], refs[i], tops[i] = guild, r, top
		if type(top) == "table" then
			for _, x in ipairs(top) do
				j = j + 1
				xs[j], xn[j], xl[j] = x, nil, nil
				if type(x) == "table" then
					xn[j], xl[j] = x.name, x.level
					local who, fixed = ShortOf(x.name)
					if not fixed then
						nLoose = nLoose + 1
						loose[nLoose], looseShort[j] = j, who
					end
					if who then
						local level, last = tonumber(x.level) or 0, tails[who]
						if last and last.i == i then
							if level > last.level then last.level = level end
						else
							used = used + 1
							local e = pool[used] or {}
							pool[used] = e
							e.i, e.r, e.guild, e.level, e.nxt = i, r, guild, level, nil
							if last then last.nxt = e else by[who] = e end
							tails[who] = e
						end
					end
				end
			end
		end
	end
	for k = i + 1, T.n do keys[k], refs[k], tops[k] = nil, nil, nil end
	for k = j + 1, T.m do xs[k], xn[k], xl[k] = nil, nil, nil end
	for k = used + 1, T.used do pool[k].r, pool[k].guild, pool[k].nxt = nil, nil, nil end
	T.n, T.m, T.used, T.nLoose = i, j, used, nLoose
	T.rows, T.split, T.rev = rows, ns.splitNames and true or false, Revision()
	T.builds = T.builds + 1
	return by
end
-- The listing for the census as it stands (nil without one).
local function Listing()
	local rows = ns.rdb and ns.rdb.guilds
	if type(rows) ~= "table" then return nil end
	if ListingHolds(rows) then return listing.by end
	return ListingBuild(rows)
end
function H.ListingBuilds() return listing.builds end

-- Vouched (1.2.1, the security review: one census row of anyone else's was proof, so a forged
-- report won the place): the claim is a verified member's, at or above that level.
--   Our guildmate: our fresh roster, the server's, at or above it (another guild's rows say nothing
--   of one of ours), and the claim's GUID his as the game gives it (VerifyGk: a guildmate's
--   resolves; a made-up one never does, and his claim waits).
--   Anyone else: census reports (Data.Receive keeps one guild per sender) of an Olympus guild not
--   netted off, heard within VOUCH_WINDOW of the claim, listing him at or above it, from VOUCHERS
--   senders of that one guild, none of them him (by his name alone, as Data.KnownRank asks). A
--   guild's row is its newest report, so each sender seen is kept on the claim (c.by: guild ->
--   senders) as his turn comes (the reporter every 3 minutes, its runner-up every 10).
--   This is the census's own trust bar (Data.KnownRank's two senders), not the server's word:
--   nothing proves a sender is in the guild he reports, nor that the guild exists (any name the
--   Olympus rule takes), so three characters acting together can still forge a place here. Such a
--   place goes once the server's word shows it false (CheckPlaces). A claimant who is one of his
--   guild's two census senders (or whose guild has one other sender) is vouched here only by our
--   roster, when he is our guildmate.
-- (1.4.0, the review's High 7) And his crossing seen here (Crossing: below the milestone, then at or
-- above it, the last sighting below it near the claim), never his level alone: a player long past an
-- open milestone took it with one IL, his place timed when it was heard. Our guildmate: the server's
-- word saw it (our roster's reads, his unit). Anyone else: each sender counted saw it in his own
-- reports (or the server's word did here). The claim keeps the newest such sighting (c.low) for its
-- from and since (Proven). The bar against a forged place stays the census's own: two senders of a
-- guild acting with him can still say he went up, as they can say he is there.
-- (1.2.1) by: the census's Listing, worked out once for all the claims looked at together: the
-- rows that list him are found by his name, the rest never looked at.
local function VouchedBy(c, by)
	if type(c) ~= "table" or type(c.name) ~= "string" or not tonumber(c.level) then return false end
	local own = Crossing(c, ns.FullName(c.name):lower())
	if Guildmate(c.name) then
		-- (His own GUID, as the game gives a guildmate's: never a made-up one beside our roster's level.)
		local P = ns.ArenaProfile
		if not (type(P) == "table" and type(P.VerifyGk) == "function" and P.VerifyGk(c.name, c.gk) == true) then return false end
		local level, fresh = RosterLevel(c.name)
		if not (fresh and level ~= nil and level >= c.level) then return false end
		return Proven(c, own)
	end
	if not by then return false end
	local who = ShortOf(c.name)
	local D = ns.Data
	c.by = type(c.by) == "table" and c.by or {}
	local e = by[who]
	while e do
		local r, guild = e.r, e.guild
		local k = type(r.reporterFull) == "string" and ShortOf(r.reporterFull) or nil
		local low = k and k ~= who and (own or Crossing(c, k .. ">" .. tostring(who))) or nil
		if low and not r.mine and type(guild) == "string" and math.abs((r.t or 0) - (c.heardLocal or 0)) <= H.VOUCH_WINDOW
			and ns.IsFederation(guild) and not (type(D) == "table" and type(D.NetOff) == "function" and D.NetOff(guild))
			and e.level >= c.level then
			local g = guild:lower()
			local n = 0
			for _ in pairs(c.by) do n = n + 1 end
			if c.by[g] or n < 4 then
				local senders = c.by[g] or {}
				c.by[g] = senders
				local m = 0
				for _ in pairs(senders) do m = m + 1 end
				if senders[k] or m < 4 then
					senders[k] = true
					if not tonumber(c.low) or low > c.low then c.low = low end
				end
			end
		end
		e = e.nxt
	end
	for _, senders in pairs(c.by) do
		local n = 0
		for _ in pairs(senders) do n = n + 1 end
		if n >= H.VOUCHERS then return Proven(c, tonumber(c.low)) end
	end
	return false
end
-- (1.4.0: what this client sees now taken first, as a census change takes it.)
function H.Vouched(c)
	Sightings(H.Store(H.LevelRaceActive()))
	return VouchedBy(c, Listing())
end

-- A place found false (1.2.1, the security review: a place stayed forever whatever came to light):
-- the server's word puts its holder below its milestone, his unit's level (by his GUID), or our
-- guild's fresh roster read STRIKE_AFTER past the place's time (so it had his level-up). Levels
-- never go down: the claim was false. Its GUID is his word too (a made-up one is never resolved):
-- the game giving that GUID another character's name (ArenaProfile.VerifyGk), or his own unit in
-- view (by his name: H.SEEN_UNITS) with another GUID, or below the milestone, shows it false too.
-- seen: SeenUnits(), when the caller has it.
function H.Falsified(p, m, gk, seen)
	if type(p) ~= "table" or not tonumber(m) then return false end
	local guid = GameGuid(p.guid)
	local level = UnitLevelOf(guid)
	if level and level < m then return true end
	gk = gk or Arena.GK(guid)
	local P = ns.ArenaProfile
	if gk and type(p.name) == "string" and type(P) == "table" and type(P.VerifyGk) == "function" and P.VerifyGk(p.name, gk) == false then return true end
	local unit = type(p.name) == "string" and (seen or SeenUnits())[ns.FullName(p.name):lower()] or nil
	if unit then
		local seenGk = Arena.GK(unit.guid)
		if gk and seenGk and seenGk ~= gk then return true end
		if unit.level and unit.level < m then return true end
	end
	if type(p.name) == "string" and Guildmate(p.name) and Now() - (tonumber(p.t) or Now()) >= H.STRIKE_AFTER then
		local rl, fresh = RosterLevel(p.name)
		if fresh and rl and rl < m then return true end
	end
	return false
end
-- Struck for that milestone here: by his gk, or by his name (s.struckNames: a forger's next claim
-- may give another gk; his name is the server's).
local function NameKey(name) return type(name) == "string" and ns.FullName(name):lower() or nil end
local function Struck(s, m, gk, name)
	if gk ~= nil and type(s.struck) == "table" and type(s.struck[m]) == "table" and s.struck[m][gk] ~= nil then return true end
	local key = NameKey(name)
	return key ~= nil and type(s.struckNames) == "table" and type(s.struckNames[m]) == "table" and s.struckNames[m][key] ~= nil
end
-- One more key kept for milestone m in store[m] (STRUCK_MAX each, the oldest goes).
local function Remember(store, m, key)
	if not key then return end
	local list = type(store[m]) == "table" and store[m] or {}
	store[m] = list
	list[key] = Now()
	local n, oldest = 0, nil
	for k, t in pairs(list) do
		n = n + 1
		if k ~= key and (not oldest or t < list[oldest]) then oldest = k end
	end
	if n > H.STRUCK_MAX and oldest then list[oldest] = nil end
end
-- The places found false go: from the book, with the claims that made them (his gk's or his
-- name's), and their holder is kept as struck for that milestone by gk and by name (no claim of
-- his nor a clerk's record takes it again here). Once gone, the place is open here again: the
-- next vouched claim this client holds or hears for it takes it (one heard before the false place
-- was recorded, kept CLAIM_DAYS, or a new level-up to it); a player who reached it while the false
-- place stood sent no claim then (SendClaim), so he is not among them. Returns the places struck
-- ({ milestone, gk, name }).
function H.CheckPlaces()
	if not H.LevelRaceActive() then return {} end
	local s = H.Store()
	local out = {}
	if not s or type(s.levels) ~= "table" then return out end
	local seen
	for _, m in ipairs(ns.Honors.MILESTONES) do
		local p = type(s.levels[m]) == "table" and s.levels[m][1] or nil
		local gk = type(p) == "table" and Arena.GK(GameGuid(p.guid)) or nil
		if gk then seen = seen or SeenUnits() end
		if gk and H.Falsified(p, m, gk, seen) then
			s.struck = type(s.struck) == "table" and s.struck or {}
			s.struckNames = type(s.struckNames) == "table" and s.struckNames or {}
			Remember(s.struck, m, gk)
			Remember(s.struckNames, m, NameKey(p.name))
			s.levels[m] = nil
			for key, c in pairs(type(s.claims) == "table" and s.claims or {}) do
				if type(c) == "table" and c.level == m and (c.gk == gk or (NameKey(c.name) ~= nil and NameKey(c.name) == NameKey(p.name))) then
					s.claims[key] = nil
				end
			end
			out[#out + 1] = { milestone = m, gk = gk, name = p.name }
			stats.struck = (stats.struck or 0) + 1
		end
	end
	for _, x in ipairs(out) do Changed(x.name) end
	return out
end

-- (1.4.0, the review's High 8: every census report looked at every unvouched claim kept, up to 200 for
-- 7 days, against the whole census.) A claim still to look at: not vouched, heard within VOUCH_WINDOW
-- (no report after that vouches it), for a milestone whose place is not known here.
local function Waiting(c, nowLocal)
	return type(c) == "table" and not c.vouched and tonumber(c.level) ~= nil and not Placed(c.level)
		and nowLocal - (tonumber(c.heardLocal) or 0) <= H.VOUCH_WINDOW
end

-- The claims against what this client knows now, the race's first half: the places held against
-- the server's word, the claims past CLAIM_DAYS gone, and every one still waiting against the census
-- (H.Vouched). A census change that lists a waiting claimant, or reads our roster anew, asks this at
-- once (a guild's row is its newest report: a sender's report is seen now or may never be); the race
-- itself waits RACE_SOON (H.RaceSoon, 1.2.1). seen: the sightings already taken (Sightings).
local function Look(s, now, seen)
	if not H.LevelRaceActive() then return end
	-- (1.2.1: a claim vouched under the old rule, one census row, is vouched again under this one;
	-- 1.4.0: the senders it kept too, none of them asked to have seen him cross.)
	if s.vouchRule ~= H.VOUCH_RULE then
		for _, c in pairs(s.claims) do
			if type(c) == "table" then c.vouched, c.by, c.low, c.from, c.since = false, nil, nil, nil, nil end
		end
		s.vouchRule = H.VOUCH_RULE
	end
	H.CheckPlaces()
	if not seen then Sightings(s) end
	local by, listed = nil, false
	local nowLocal = ns.Now()
	for key, c in pairs(s.claims) do
		if now - (c.t or 0) > H.CLAIM_DAYS * 86400 then s.claims[key] = nil
		elseif Waiting(c, nowLocal) then
			if not listed then by, listed = Listing(), true end
			if VouchedBy(c, by) then c.vouched = true stats.vouched = stats.vouched + 1 end
		end
	end
end

-- The one race waiting to run (1.2.1, the stutter players reported): a census change and an IL
-- look at the claims at once (Look) and leave the race to RACE_SOON later, once for a burst, never
-- inside the game's message event; a vouched claim waiting CONFIRM_AFTER has one re-check, at the
-- moment the first of them is old enough (each race used to start one more, 601 s on).
H.RACE_SOON = 5
local raceSoon = false
function H.RaceSoon()
	if not H.LevelRaceActive() then return false end
	if raceSoon then return false end
	raceSoon = true
	ns.After(H.RACE_SOON, "arena level race soon", function() raceSoon = false H.RunRace() end)
	return true
end
local recheckAt, recheckSeq = nil, 0
local function Recheck(at)
	if recheckAt and recheckAt <= at then return end
	recheckSeq = recheckSeq + 1
	local seq = recheckSeq
	recheckAt = at
	ns.After(math.max(1, at - Now()), "arena level race", function()
		if seq ~= recheckSeq then return end -- (an earlier one took its place)
		recheckAt = nil
		H.RunRace()
	end)
end

-- The book again: the claims (vouched where they are) through Honors.LevelRace; a new place said.
-- A claim that can no longer be vouched (unvouched past VOUCH_WINDOW) stops holding the race up
-- (it stays until CLAIM_DAYS, so its sender can't claim that milestone again meanwhile); a gk that
-- several senders claim counts only for the one the game pairs it with (VerifyGk), else only
-- vouched claims of it count.
function H.RunRace()
	if not H.LevelRaceActive() then return {} end
	local s = H.Store(true)
	local now = Now()
	Look(s, now)
	local claims = {}
	local P = ns.ArenaProfile
	local senders = {}
	for _, c in pairs(s.claims) do
		if c.vouched or ns.Now() - (c.heardLocal or 0) <= H.VOUCH_WINDOW then
			-- (1.4.0: a vouched claim with the crossing seen, its from and since: the race's start is
			-- asked of since too.)
			claims[#claims + 1] = { name = c.name, gk = c.gk, guid = GameGuid(c.gk), level = c.level, t = c.t, vouched = c.vouched,
				from = c.vouched and c.from or nil, since = c.vouched and c.since or nil }
			senders[c.gk] = senders[c.gk] or {}
			senders[c.gk][ns.FullName(c.name):lower()] = true
		end
	end
	local kept = {}
	for _, c in ipairs(claims) do
		local n = 0
		for _ in pairs(senders[c.gk] or {}) do n = n + 1 end
		local ok = n <= 1
		if not ok then
			local verified = P and P.VerifyGk and P.VerifyGk(c.name, c.gk)
			if verified == true then ok = true
			elseif verified == nil then
				ok = c.vouched == true
				for other in pairs(senders[c.gk]) do
					if other ~= ns.FullName(c.name):lower() and P and P.VerifyGk and P.VerifyGk(other, c.gk) == true then ok = false end
				end
			end
		end
		if ok then kept[#kept + 1] = c end
	end
	claims = kept
	local book, fresh, pending = ns.Honors.LevelRace(s.levels, claims, now, { start = H.RACE_START })
	s.levels = book
	for _, p in ipairs(fresh) do
		stats.places = stats.places + 1
		Changed(p.name)
	end
	-- (1.4.0) The author's client says a new place at once: the one book every client keeps.
	if fresh[1] and H.AuthorSays then H.AuthorSays(true) end
	-- A vouched claim waits CONFIRM_AFTER: looked at again once the first of them is old enough.
	local due
	for _, list in pairs(pending or {}) do
		for _, c in ipairs(list) do
			if c.vouched then
				local at = (tonumber(c.t) or now) + ns.Honors.CONFIRM_AFTER + 1
				if not due or at < due then due = at end
			end
		end
	end
	if due then Recheck(due) end
	return fresh
end

local function OnLevel(dist, sender, mode, body)
	if not H.LevelRaceActive() then return Count("level-race-off") end
	if mode ~= "L" then return Count("mode") end
	local gk, level, t = Arena.Fields(body, 3)
	if not t then return Count("shape") end
	gk, level = Gk(gk), N(level, 1, 60)
	if not gk or not level or not ns.Honors.LEVEL_METAL[level] then return Count("level") end
	if Placed(level) then return Count("placed") end
	local P = ns.ArenaProfile
	local ok = P.VerifyGk(sender, gk)
	if ok == false then return Count("gk") end
	local s = H.Store(true)
	-- (1.2.1: a character whose place at that milestone was found false never claims it again here.)
	if Struck(s, level, gk, sender) then return Count("struck") end
	-- One claim per sender and milestone, in his own name (never another's slot, nor a book filled
	-- by one sender); the book full, its oldest unvouched claim goes.
	local key = ns.FullName(sender):lower() .. ":" .. level
	local c = s.claims[key]
	if not c then
		local n, oldest = 0, nil
		for k, x in pairs(s.claims) do
			n = n + 1
			if not x.vouched and (not oldest or (x.t or 0) < (s.claims[oldest].t or 0)) then oldest = k end
		end
		if n >= H.CLAIMS_MAX then
			if not oldest then return Count("full") end
			s.claims[oldest] = nil
			Count("evicted")
		end
		-- Timed when this client first heard it (its clock, never the player's word).
		c = { gk = gk, name = ns.FullName(sender), level = level, t = Now(), heardLocal = ns.Now(), vouched = false }
		s.claims[key] = c
		stats.claims = stats.claims + 1
	end
	-- (1.2.1) The claims against the census at once, the race RACE_SOON later.
	Look(s, Now())
	H.RaceSoon()
end
ns.Comm.Handle("IL", ns.Arena.Handle("IL", OnLevel))

-- A census report came in, or our roster: what this client sees is taken (1.4.0: the crossings,
-- Sightings), the claims waiting whose claimant it lists, or every guildmate's on a new read of our
-- roster, are looked at again (1.4.0, the review's High 8: the others never: nothing new about them),
-- and (1.2.1) the places held (three at most: lookups alone) against the server's word, at once; the
-- race RACE_SOON later (H.RaceSoon), once for a burst of reports. (1.4.0) The signed list that names
-- this realm a launch realm comes as a census change too: the level-ups are watched from then on.
ns.On("DATA_CHANGED", function()
	if not H.LevelRaceActive() then return end
	if not levelHooked then H.WatchLevels() end
	-- (1.4.0) The author's client says its places again each AUTHOR_RESEND while online: a client
	-- that logged in after a crossing (and could never see it) gets the network's one winner.
	if H.AuthorHere and H.AuthorHere() then ns.SafeCall("arena level author", H.AuthorSays) end
	local s = H.Store(Now() >= H.RACE_START)
	local touched = s and Sightings(s)
	local nowLocal = ns.Now()
	if touched and type(s.claims) == "table" then
		for _, c in pairs(s.claims) do
			if Waiting(c, nowLocal) and type(c.name) == "string" and (touched[ShortOf(c.name)] or touched[ns.FullName(c.name):lower()]
				or (touched[ROSTER] and Guildmate(c.name))) then
				ns.SafeCall("arena level vouch", Look, s, Now(), true)
				H.RaceSoon()
				return
			end
		end
	end
	if s and type(s.levels) == "table" and next(s.levels) then
		ns.SafeCall("arena level places", function()
			if #H.CheckPlaces() > 0 then H.RaceSoon() end
		end)
	end
end)

-- The clerk's AB~H: the places this clerk holds (m:gk:name:t), taken for a milestone with no
-- place here (a place never changes once recorded).
function H.RecordsBody()
	if not H.LevelRaceActive() then return nil end
	local s = H.Store()
	local parts = {}
	for _, m in ipairs(ns.Honors.MILESTONES) do
		local p = s and s.levels and s.levels[m] and s.levels[m][1]
		local gk = p and Arena.GK(p.guid)
		if gk then parts[#parts + 1] = table.concat({ B36(m), gk, ns.ArenaFights.Wire(p.name), B36(p.t or 0) }, ":") end
	end
	return #parts > 0 and ("H~" .. table.concat(parts, ",")) or nil
end
function H.SendRecords()
	if not H.LevelRaceActive() then return false, "level-race-off" end
	local body = H.RecordsBody()
	if body then Arena.Send("AB", "L", body, { key = "ab h", low = true }) end
end
-- (1.4.0, the owner's ask: the level race runs once, and the whole network keeps one winner, decided
-- by the author's client, the King's or a High Councillor's: "se eu nao tiver logado o tempo todo")
-- Each client still works the race out itself (RunRace), but what each of them saw differs (who was
-- online, which census reports reached it), so its places could differ from another's forever. A
-- record from an authority replaces a place this client worked out itself; a higher authority's
-- replaces a lower one's (the author 3, the King 2, a High Councillor 1); between two of the same,
-- the earlier crossing stays. The server stamps every sender, so nobody else can speak as them. Any
-- other clerk's record (an arbiter's) still only fills a milestone with no place here.
local function Authority(name)
	if type(name) ~= "string" or name == "" then return 0 end
	local full = ns.FullName(name)
	local B = ns.Borders -- (the dev, as the core says it: Borders.IsDevName, never naming him here)
	if type(B) == "table" and type(B.IsDevName) == "function" and B.IsDevName(full) == true then return 3 end
	local R = ns.ArenaRoles
	if type(R) == "table" and type(R.IsKing) == "function" and R.IsKing(full) == true then return 2 end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(full) == true then return 1 end
	return 0
end
H.Authority = Authority
function H.TakeRecords(sender, mode, rest)
	if not H.LevelRaceActive() then return false, "level-race-off" end
	if mode ~= "L" then return end
	local rank = Authority(sender)
	local s = H.Store(true)
	local any = false
	for part in tostring(rest):gmatch("[^,]+") do
		local m, gk, name, t = part:match("^([0-9a-z]+):([^:]+):([^:]+):([0-9a-z]+)$")
		m, t = N(m, 1, 60), N(t, 0, 4294967295)
		local placed = m ~= nil and Placed(m)
		-- (1.4.0) A place timed before the race's start (a pre-launch book a clerk kept) or ahead of
		-- the clock is never a launch place.
		if m and ns.Honors.LEVEL_METAL[m] and Gk(gk) and (rank > 0 or not placed) and t and t >= H.RACE_START and t <= Now() + ns.Honors.SKEW then
			local full = ns.ArenaFights.Unwire(name, sender)
			local held = placed and s.levels[m][1] or nil
			local heldBy = held and tonumber(held.by) or 0
			if held and Arena.GK(held.guid) == gk then
				if rank > heldBy then held.by = rank end -- (the same winner, now an authority's)
			elseif full and not Struck(s, m, gk, full) and (not held or rank > heldBy
				or (rank == heldBy and t < (tonumber(held.t) or math.huge))) then
				s.levels[m] = { { guid = Arena.GuidOf(gk), name = full, t = t, place = 1, by = rank > 0 and rank or nil } }
				any = true
				if held and type(held.name) == "string" then Changed(held.name) end
				Changed(full)
			end
		end
	end
	return any
end
-- An authority's own client (never a preview of another's view): it says its places when it records
-- one (RunRace), when asked (AQ~H), and again each AUTHOR_RESEND while online.
H.AUTHOR_RESEND = 900
local authorSent
local function AuthorHere()
	if Authority(ns.me) <= 0 then return false end
	if ns.King and ns.King.Preview and ns.King.Preview() then return false end
	local V = ns.ViewAs
	return not (type(V) == "table" and type(V.Previewing) == "function" and V.Previewing() == true)
end
H.AuthorHere = AuthorHere
function H.AuthorSays(force)
	if not H.LevelRaceActive() or not AuthorHere() then return false end
	local now = Now()
	if not force and authorSent and now - authorSent < H.AUTHOR_RESEND then return false end
	authorSent = now
	return H.SendRecords() ~= false
end
-- AQ~H: the clerk (or an authority) says the places; a claimant says his claim again.
function H.Answer(sender)
	if not H.LevelRaceActive() then return false end
	local LG = ns.ArenaLedger
	if (LG and LG.IsClerk and LG.IsClerk()) or AuthorHere() then H.SendRecords() return true end
	for level in pairs(claimed) do if not Placed(level) then H.SendClaim(level) return true end end
	return false
end

---------------------------------------------------------------------------
-- The donors (ID)
---------------------------------------------------------------------------

-- The Treasurer's client works the donors out of his book (Treasury.DonationRecords, the money part's), by
-- Honors.Donors, and says the names.
function H.DonorWord()
	local T = ns.Treasury
	if type(T) ~= "table" or T.missing or type(T.DonationRecords) ~= "function" then return nil end
	local ok, records = pcall(T.DonationRecords)
	if not ok or type(records) ~= "table" then return nil end
	local s = H.Store(true)
	local D = ns.Dues
	local opts = { kept = s.donorsKept }
	if type(D) == "table" and not D.missing and type(D.Anchor) == "function" then
		local okA, a = pcall(D.Anchor)
		if okA then opts.anchor = a end
	end
	local r = ns.Honors.Donors(records, Now(), opts)
	s.donorsKept = { monthNo = r.monthNo, month = r.month, weekNo = r.weekNo, week = r.week }
	local function Names(list)
		local out = {}
		for i, d in ipairs(list or {}) do out[i] = ns.ArenaFights.Wire(d.name) end
		return out
	end
	return { monthNo = r.monthNo, month = Names(r.month), all = Names(r.all) }
end
local function IdBody(w, t)
	return table.concat({ B36(t), B36(w.monthNo), #w.month > 0 and table.concat(w.month, ",") or "-", #w.all > 0 and table.concat(w.all, ",") or "-" }, "~")
end
-- (1.3.4) Who says the Treasurer's word again, as it is: the King's character and the signed High
-- Council, never one of the Treasurer's characters (his own client says it, SendDonors).
local function IsCouncillor(name) return ns.IsHighCouncillor ~= nil and ns.IsHighCouncillor(name) == true end
function H.IsDonorRelay(name)
	if type(name) ~= "string" or name == "" then return false end
	local full = ns.FullName(name)
	if ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(full) then return false end
	return ns.ArenaRoles.IsKing(full) or IsCouncillor(full)
end
-- A word as the Treasurer worked it out: his characters' own, or a High Councillor's relay of it (the
-- Council works out none). The King's may be his own (where no Treasurer's is known): not that.
local function TreasurerWord(from)
	if type(from) ~= "string" or from == "" then return false end
	local full = ns.FullName(from)
	if ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(full) then return true end
	return IsCouncillor(full) and not ns.ArenaRoles.IsKing(full)
end
-- The time of the newest word of the Treasurer's this client heard (his own, or relayed by the Council),
-- or nil.
function H.TreasurerHeard()
	local s = H.Store()
	if not s then return nil end
	local t = tonumber(s.donorsTr)
	local d = s.donors
	if type(d) == "table" and TreasurerWord(d.from) and tonumber(d.t) and (not t or d.t > t) then t = d.t end
	return t
end

local lastId
function H.SendDonors(force)
	local treasurer = ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(ns.me)
	if not treasurer and not ns.ArenaRoles.IsKing(ns.me) then return false, "who" end
	-- (1.3.4) The King's book is not the treasury's: where the Treasurer's own word of the last
	-- DONOR_TREASURER_DAYS is known, the King's client works out none (it only says his again,
	-- RelayDonors); his newer word put another top 3 on every client that heard him last.
	local heard = not treasurer and H.TreasurerHeard()
	if heard and Now() - heard <= H.DONOR_TREASURER_DAYS * 86400 then return false, "treasurer" end
	local w = H.DonorWord()
	if not w then return false, "book" end
	local sig = w.monthNo .. "|" .. table.concat(w.month, ",") .. "|" .. table.concat(w.all, ",")
	if sig == lastId and not force then return false, "same" end
	lastId = sig
	local body = IdBody(w, Now())
	H.TakeDonors(ns.me, body)
	Arena.Send("ID", "L", body, { key = "id" })
	if GetGuildInfo and GetGuildInfo("player") then Arena.Send("ID", "L", body, { dist = "GUILD", key = "id guild" }) end
	return true
end
local donorDue, donorTimer = nil, false -- (1.3.4) our relay's next turn; its timer waiting
-- (1.3.4) A relay's wait from now: the King's DONOR_KING_AFTER, and DONOR_JITTER at random.
local function DonorWait() return (ns.ArenaRoles.IsKing(ns.me) and H.DONOR_KING_AFTER or 0) + H.random(0, H.DONOR_JITTER) end
function H.TakeDonors(sender, body)
	-- (1.3.4: a signed High Councillor's too, a relay's: the Council works out none of its own.)
	if not (ns.IsTreasurerCharacter(ns.FullName(sender)) or ns.ArenaRoles.IsKing(sender) or IsCouncillor(ns.FullName(sender))) then
		return Count("sender")
	end
	local t, month, m, a = Arena.Fields(body, 4)
	if not a then return Count("shape") end
	t, month = N(t, 0, 4294967295), N(month, 0, 99999)
	if not t or not month or t > Now() + 60 then return Count("time") end
	local s = H.Store(true)
	local mine = Same(sender, ns.me)
	if TreasurerWord(sender) and t > (tonumber(s.donorsTr) or 0) then s.donorsTr = t end
	-- (1.3.4) The same word or a newer one from another client: our relay waits again (H.RelayDonors).
	if not mine and (not s.donors or t >= (s.donors.t or 0)) and H.IsDonorRelay(ns.me) then
		donorDue = Now() + H.DONOR_EVERY + H.DONOR_GRACE + DonorWait()
	end
	if s.donors and (s.donors.t or 0) >= t and not mine then return Count("older") end
	local function Names(list)
		local out = {}
		if list ~= "-" then
			for name in list:gmatch("[^,]+") do
				local full = ns.ArenaFights.Unwire(name, sender)
				if full and #out < 3 then out[#out + 1] = full end
			end
		end
		return out
	end
	-- (from: who it came from, a relay's name for a relayed word; shown, never trusted further.)
	s.donors = { t = t, monthNo = month, month = Names(m), all = Names(a), from = ns.FullName(sender) }
	Changed()
	H.WatchDonorRelay()
	return true
end

-- (1.3.4) A relay's client (H.IsDonorRelay): the Treasurer's last word it holds (TreasurerWord: never
-- the King's own), as it is (its time, its month, its names, each wired for our realm as Wire does), on
-- the channel and GUILD, DONOR_EVERY + DONOR_GRACE after the last word heard (the same or a newer one) or
-- said, DONOR_JITTER at random more (the King's DONOR_KING_AFTER later still). A word heard meanwhile
-- starts its wait again: no relay speaks while the Treasurer's client says it, and the relays online say
-- it about once a DONOR_EVERY between them, the King's only when none of the Council's did. A relay never
-- makes a word newer (TakeDonors keeps the newest time).
function H.RelayDonors()
	if not H.IsDonorRelay(ns.me) then return false, "who" end
	local s = H.Store()
	local d = s and s.donors
	if type(d) ~= "table" or not tonumber(d.t) or not tonumber(d.monthNo) or not TreasurerWord(d.from) or Same(d.from, ns.me) then
		return false, "none"
	end
	local function Names(list)
		local out = {}
		for i, name in ipairs(type(list) == "table" and list or {}) do
			if i > 3 or type(name) ~= "string" then break end
			out[i] = ns.ArenaFights.Wire(name)
		end
		return out
	end
	local body = IdBody({ monthNo = d.monthNo, month = Names(d.month), all = Names(d.all) }, d.t)
	Arena.Send("ID", "L", body, { key = "id" })
	if GetGuildInfo and GetGuildInfo("player") then Arena.Send("ID", "L", body, { dist = "GUILD", key = "id guild" }) end
	return true
end
local function DonorRelayTick()
	donorTimer = false
	if not H.IsDonorRelay(ns.me) then return end
	local t = Now()
	-- (A word heard since put its turn later: it waits on.)
	if not donorDue or t >= donorDue then
		H.RelayDonors()
		donorDue = t + H.DONOR_EVERY + H.DONOR_GRACE + DonorWait()
	end
	H.WatchDonorRelay()
end
-- The relay's timer, to its next turn (the first DONOR_FIRST and its wait from now); one waits at most.
function H.WatchDonorRelay()
	if donorTimer or not H.IsDonorRelay(ns.me) then return false end
	donorDue = donorDue or (Now() + H.DONOR_FIRST + DonorWait())
	donorTimer = true
	ns.After(math.max(1, donorDue - Now()), "arena donors relay", DonorRelayTick)
	return true
end
local function OnDonors(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	H.TakeDonors(sender, body)
end
ns.Comm.Handle("ID", ns.Arena.Handle("ID", OnDonors))

---------------------------------------------------------------------------
-- The Oracle (IO)
---------------------------------------------------------------------------

-- A bank's rows for a month (the markets' markets over its ledger: Honors.OracleScores' rows): a hook the
-- markets fill; none, and a bank says nothing.
H.oracleSource = function() return nil end
local whispered = {} -- [month] = { [bank] = rows }

function H.OracleBanks()
	local out = {}
	for _, b in ipairs(ns.ArenaRoles.Banks("L")) do if b.state == "o" then out[#out + 1] = b.name end end
	table.sort(out, function(x, y) return x:lower() < y:lower() end)
	return out
end

local function RowsText(rows)
	local out = {}
	for i, r in ipairs(rows) do
		if i > 10 then break end
		out[#out + 1] = table.concat({ ns.ArenaFights.Wire(r.name), tostring(r.profit), tostring(r.staked), tostring(r.markets), B36(r.first or 0) }, ":")
	end
	return table.concat(out, ";")
end

-- On a bank's client at the month's end: the first open bank publishes; the others whisper it
-- their top 10.
function H.OracleTick()
	if not ns.ArenaRoles.IsBank(ns.me, "L") then return false end
	local month = ns.Honors.MonthOf(Now()) - 1
	local ok, rows = pcall(H.oracleSource, month)
	if not ok or type(rows) ~= "table" then return false end
	local banks = H.OracleBanks()
	local first = banks[1]
	if not first then return false end
	local cur = ns.ArenaRoles.Currency()
	if not Same(first, ns.me) then
		local _, ranked = ns.Honors.Oracle(rows, { cur = cur })
		Arena.Send("IO", "L", "R~" .. B36(month) .. "~" .. RowsText(ranked or {}), { to = first })
		return true
	end
	local all = {}
	for _, r in ipairs(rows) do r.bank = ns.me all[#all + 1] = r end
	for bank, list in pairs(whispered[month] or {}) do
		for _, r in ipairs(list) do r.bank = bank all[#all + 1] = r end
	end
	local top = ns.Honors.Oracle(all, { cur = cur })
	local names = {}
	for i, r in ipairs(top) do names[i] = ns.ArenaFights.Wire(r.name) end
	local body = table.concat({ B36(month), B36(Now()), #names > 0 and table.concat(names, ",") or "-" }, "~")
	H.TakeOracle(ns.me, "CHANNEL", body)
	Arena.Send("IO", "L", body, { key = "io" })
	return true
end

function H.TakeOracle(sender, dist, body)
	if not ns.ArenaRoles.IsBank(sender, "L") then return Count("sender") end
	if dist == "WHISPER" then
		local kind, month, rows = Arena.Fields(body, 3)
		if kind ~= "R" or not rows then return Count("shape") end
		month = N(month, 0, 99999)
		if not month or not ns.ArenaRoles.IsBank(ns.me, "L") then return Count("bank") end
		local list = {}
		for part in rows:gmatch("[^;]+") do
			local name, profit, staked, markets, first = part:match("^([^:]+):(%-?%d+):(%d+):(%d+):([0-9a-z]+)$")
			local full = name and ns.ArenaFights.Unwire(name, sender)
			if full and #list < 10 then
				list[#list + 1] = { name = full, profit = tonumber(profit), staked = tonumber(staked), markets = tonumber(markets), first = N(first, 0, 4294967295) }
			end
		end
		whispered[month] = whispered[month] or {}
		whispered[month][ns.FullName(sender)] = list
		return true
	end
	local month, t, names = Arena.Fields(body, 3)
	if not names then return Count("shape") end
	month, t = N(month, 0, 99999), N(t, 0, 4294967295)
	if not month or not t or t > Now() + 60 then return Count("time") end
	local s = H.Store(true)
	local had = s.oracle[month]
	if had and (had.t or 0) >= t and not Same(sender, ns.me) then return Count("older") end
	local list = {}
	if names ~= "-" then
		for name in names:gmatch("[^,]+") do
			local full = ns.ArenaFights.Unwire(name, sender)
			if full and #list < 3 then list[#list + 1] = full end
		end
	end
	s.oracle[month] = { t = t, names = list, from = ns.FullName(sender) }
	-- Two months kept.
	for m in pairs(s.oracle) do if type(m) == "number" and m < month - 1 then s.oracle[m] = nil end end
	Changed()
	return true
end
local function OnOracle(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	H.TakeOracle(sender, dist, body)
end
ns.Comm.Handle("IO", ns.Arena.Handle("IO", OnOracle))

---------------------------------------------------------------------------
-- Our own honours: the automatic switch-on and the King's letter
---------------------------------------------------------------------------

-- The sources loaded (Honors.Update's known): a family is forgotten only once its source is here.
function H.Known()
	local LG = ns.ArenaLedger
	local s = H.Store()
	local titles = LG and LG.CoreT and LG.CoreT("L", "titles")
	local words = LG and LG.CoreT and LG.CoreT("L", "beltWords")
	local guilds = CensusGuildRows()
	local fresh = false
	for _, r in pairs(type(guilds) == "table" and guilds or {}) do
		if type(r) == "table" and r.t and ns.Now() - r.t <= ns.Honors.GUILD_MAX_AGE then fresh = true break end
	end
	-- (1.2.3: the Church's top 3 while it is shown and fresh; closed, unheard or stale it is not
	-- known, so a missionary's crook is remembered as it was: never "lost", nor "new" when it is back.)
	local church = ChurchTop()
	-- (1.2.4: the Apostles' the same; the Bones' wherever the build has its table, its ranking this
	-- client's own count; the slayers' while a signed word shows, so an expired or revoked one is not
	-- known, and nobody is "lost" for it.)
	local FT = ns.FarkleTable
	local fresh3 = church ~= nil and ns.Honors.ChurchFresh(church, Now())
	return {
		belt = (titles and next(titles) ~= nil) or (words and next(words) ~= nil) or Arena.Heavy("L") ~= nil,
		tier = Arena.Heavy("L") ~= nil,
		donor = s ~= nil and s.donors ~= nil,
		-- OFF is a known-disabled source, not an unheard ranking: no old derived honour is
		-- remembered as wearable while waiting for a relay. The historical book stays intact.
		level = not H.LevelRaceActive() or (s ~= nil and s.levels ~= nil and next(s.levels) ~= nil),
		guild = fresh,
		oracle = s ~= nil and s.oracle ~= nil and next(s.oracle) ~= nil,
		missionary = fresh3,
		apostle = fresh3,
		bones = type(FT) == "table" and not FT.missing and type(FT.Best) == "function",
		wanted = WantedTop() ~= nil,
	}
end

-- (1.2.6, the owner's rule of 10-19) The red cross is its wearer's own look, on his own screen alone
-- (Borders.OwnLook): every other client shows him with the Apostles' cross he holds in the Church's
-- ranking (apostle-1/2/3, the best one held, gold, silver or bronze). So while he wears it, the pick
-- his profile's word carries is that cross; with none held, his pick as it is. Nil: no change.
function H.OwnLookFrame(held)
	local B = ns.Borders
	if type(B) ~= "table" or B.missing or type(B.OwnLook) ~= "function" or B.OwnLook() == nil then return nil end
	local best
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and h.family == "apostle" and type(h.frame) == "string" and type(h.place) == "number"
			and ns.Honors.FrameShipped(h) and (not best or h.place < best.place) then best = h end
	end
	return best and best.frame or nil
end

local refreshing = false
local letters = {} -- the queue shown now: { key, t }
-- Our honours looked at again: what is new switches on (unless locked) and gets its letter.
function H.Refresh()
	if refreshing or not ns.db or not ns.IsMember() then return end
	refreshing = true
	local P = ns.ArenaProfile
	local ok, err = pcall(function()
		-- (1.5.5) The level race's apology, worked out before this look stands his comet in; and the
		-- Speedrunner named after it went out to him, his gold comet told anew (H.SpeedrunnerAnew).
		local sorry, anew = H.ApologyDue(), H.SpeedrunnerAnew()
		local held = H.Holdings(ns.me, P.MyGk())
		local before = P.Pick()
		local first = before.seen == nil
		-- (1.2.3) Only an honour told for the first time switches on by itself (its letter comes with
		-- it): back the same month to a place of the Church's 30-day ranking already told, his own
		-- pick since stays. What was told before a 1.2.0 profile's first look (FirstLook counts what
		-- it holds as told for the letters alone, on the safe side: those still switch on, as in 1.2.1).
		local told = H.Lettered()
		if P.Mine().letterLook then
			local copy = {}
			for mark, v in pairs(told) do copy[mark] = v end
			told = copy
		end
		H.FirstLook(held)
		local known = H.Known()
		-- (1.2.4: now, so a closed month's list over is remembered where it ended, not lost: the next
		-- month's list naming him there switches nothing on, Honors.Update's opts.)
		local pick, earned, lost = ns.Honors.Update(before, held, known, function(h)
			if anew and h.key == H.SPEEDRUNNER_KEY then return false end
			return told[H.LetterMark(h.key, h.period)] == true
		end, { now = H.Inputs().now })
		-- (1.2.6) The red cross worn here: the cross he holds is what everyone else sees, whatever
		-- else switched on (H.OwnLookFrame).
		local cross = H.OwnLookFrame(held)
		if cross then pick.frame = cross end
		-- Kept only when something is to remember (an idle client writes no profile).
		local same = pick.frame == before.frame and pick.title == before.title and #earned == 0 and #lost == 0
		if not same or (first and next(pick.seen or {}) ~= nil) then P.SavePick(pick) end
		local sent = false
		if pick.frame ~= before.frame or pick.title ~= before.title then
			P.Send(true)
			sent = true
		end
		-- (1.2.4) Each place against what he was last told: the King's letter the first time he reaches
		-- it in its cycle, a notice for any other move (H.Tell); then, as before, a letter for anything
		-- newly earned that has none yet (QueueLetter: once per mark).
		H.Tell(held, known, H.Lettered())
		for _, h in ipairs(earned) do
			if (h.frame or h.title) and not h.noLetter then H.QueueLetter(h.key, h.period) end
		end
		if sorry then H.Apologize(true) end
		if anew then H.SpeedrunnerLetter(held) end
		if sent or #earned > 0 then
			gen = gen + 1
			ns.Fire("HONORS_CHANGED", ns.me)
		end
		return first
	end)
	refreshing = false
	if not ok then error(err, 0) end
end

-- The letter is the King's (L.HONOR_LETTER_SIGN): never to the King himself (1.2.1, the owner's
-- ask, after the King's stream: a letter from himself about a frame he holds). The King is his
-- character (ns.IsKingCharacter) or, where none is pinned by name, the guild master of his guild
-- (King.IsKing). His honours switch on as anyone's; no letter comes, none is kept to read again.
-- (1.2.3: each is marked told all the same, QueueLetter, so they switch on once, as anyone's.)
function H.LetterToSender()
	if ns.IsKingCharacter(ns.me) then return true end
	local K = ns.King
	return type(K) == "table" and not K.missing and type(K.IsKing) == "function" and K.IsKing() == true
end

-- Each honour's letter comes once per character, ever (1.2.1, the owner's ask: never again after
-- a reload, a relog or an update, nor when an honour comes back after a gap in its source, or a
-- place lost and won back): the profile's lettered = { [mark] = true }, the honours told. A
-- month's honour (the month's donors, the Oracle: keys that name only the place) is told for its
-- month (H.LetterMark): won again another month, it is a new award, with its letter. (1.2.3: so is
-- the missionaries' crook, told for the calendar month he reaches its place in.)
-- The profiles 1.2.0 kept are read once, at the account's first login under 1.2.1 (ns.db's
-- honorLetters, set then: every profile kept before it is 1.2.0's, one made after it starts with
-- nothing told): every letter it queued (its letters, read or not) and every honour its pick
-- remembered held (its seen) count as told; and, on the safe side (a letter that has left the
-- list of 20), every honour held at that character's first look (H.FirstLook).
H.LETTERS_RULE = 1
function H.LetterMark(key, period)
	period = tonumber(period)
	return period and (key .. "@" .. period) or key
end
-- A 1.2.0 letter's or pick's mark: a month's honour for the month closed before t (the one it was
-- held for then, as Honors.Holdings counts it).
local function OldMark(key, t)
	local family = H.LetterFamily(key)
	if family ~= "donor-month" and family ~= "oracle" then return key end
	return H.LetterMark(key, ns.Honors.MonthOf(tonumber(t) or Now()) - 1)
end
function H.ReadOldLetters()
	local db = ns.db
	if type(db) ~= "table" or db.honorLetters ~= nil then return end
	for _, m in pairs(type(db.arenaProfile) == "table" and db.arenaProfile or {}) do
		if type(m) == "table" and m.lettered == nil and (type(m.letters) == "table" or type(m.seen) == "table") then
			local told = {}
			for _, x in ipairs(type(m.letters) == "table" and m.letters or {}) do
				if type(x) == "table" and type(x.key) == "string" then told[OldMark(x.key, x.t)] = true end
			end
			for _, s in pairs(type(m.seen) == "table" and m.seen or {}) do
				if type(s) == "table" then
					if type(s.frame) == "string" then told[OldMark(s.frame, m.at)] = true end
					if type(s.title) == "string" then told[OldMark(s.title, m.at)] = true end
				end
			end
			m.lettered, m.letterLook = told, true
		end
	end
	db.honorLetters = H.LETTERS_RULE
end
-- The honours told to this character (a table to read; QueueLetter keeps it).
function H.Lettered()
	H.ReadOldLetters()
	local m = ns.ArenaProfile.Mine()
	return type(m.lettered) == "table" and m.lettered or {}
end
-- A 1.2.0 profile's first look under 1.2.1 (H.Refresh's, before anything is earned): what it
-- holds then counts as told.
function H.FirstLook(held)
	H.ReadOldLetters()
	local m = ns.ArenaProfile.Mine()
	if not m.letterLook then return end
	m.lettered = type(m.lettered) == "table" and m.lettered or {}
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and type(h.key) == "string" then m.lettered[H.LetterMark(h.key, h.period)] = true end
	end
	m.letterLook = nil
end

-- (1.5.5, the owner's call) The level race's apology: once, to every character whose profile shows a
-- comet of the race told (lettered), remembered (seen) or worn (its pick's frame or title), never to the
-- Olympus Speedrunner (his gold comet is his). Its words (L.HONOR_LETTER.apology): in the race's first
-- days not everyone could be witnessed, the comet he saw came from a bug, the race is off, sorry, new
-- things will come. A letter like the King's others (QueueLetter: told once per character, kept to read
-- again), with no honour to wear; the race's own letters it leaves are let go from his list, so none is
-- read again in the gold comet's words.
H.APOLOGY_KEY = "apology@level-race"
local function RaceKey(v) return type(v) == "string" and v:find("^level%-race%-%d+$") ~= nil end
local function RaceTrace(m)
	if type(m) ~= "table" then return false end
	if RaceKey(m.frame) or RaceKey(m.title) then return true end
	for mark, v in pairs(type(m.lettered) == "table" and m.lettered or {}) do
		if v and RaceKey(mark) then return true end
	end
	for family, x in pairs(type(m.seen) == "table" and m.seen or {}) do
		if type(family) == "string" and family:find("^level%-%d+$") then return true end
		if type(x) == "table" and (RaceKey(x.frame) or RaceKey(x.title)) then return true end
	end
	return false
end
-- (1.5.5, the independent check) Whether the signed titles list this client holds, its realm group's
-- (ns.SignedPins), names an Olympus Speedrunner, either side's. Until one does, nobody here can tell whose
-- the gold comet is: the apology waits (H.ApologyDue), so the Speedrunner's first look under 1.5.5, run
-- before his list reached him (titles lists travel over the guild and the channel alone), never sends it
-- to him nor lets his race letters go. The release carries the list (Workshop.TakeShipped): normally at
-- once.
function H.SpeedrunnerNamed()
	local p = type(ns.SignedPins) == "function" and ns.SignedPins() or nil
	local s = type(p) == "table" and p.speedrunner or nil
	return type(s) == "table" and (s.Alliance ~= nil or s.Horde ~= nil)
end
-- This character is the Speedrunner the list held names (ns.IsSpeedrunnerName).
local function Speedrunner() return type(ns.IsSpeedrunnerName) == "function" and ns.IsSpeedrunnerName(ns.me) == true end
function H.ApologyDue()
	local P = ns.ArenaProfile
	if not ns.db or type(P) ~= "table" or P.missing or type(P.Mine) ~= "function" then return false end
	if H.Lettered()[H.APOLOGY_KEY] then return false end
	if not H.SpeedrunnerNamed() or Speedrunner() then return false end
	return RaceTrace(P.Mine())
end
-- due: H.ApologyDue's answer from before a look stood his comet in (H.Refresh), else asked now. Never to the
-- Speedrunner the list held names, nor before a list names one: his race letters are his.
function H.Apologize(due)
	if due == nil then due = H.ApologyDue() end
	if not due or H.Lettered()[H.APOLOGY_KEY] then return false end
	if not H.SpeedrunnerNamed() or Speedrunner() then return false end
	local m = ns.ArenaProfile.Mine(true)
	if type(m.letters) == "table" then
		for i = #m.letters, 1, -1 do
			local x = m.letters[i]
			if type(x) == "table" and RaceKey(x.key) then table.remove(m.letters, i) end
		end
	end
	H.QueueLetter(H.APOLOGY_KEY)
	return true
end
-- (1.5.5, the independent check) The Speedrunner named after the apology went out to this character (a
-- newer list names him: the one held then named another): the apology let his race letters go, and the
-- race's own mark of the gold comet (lettered["level-race-60"]) may say he was told of it long ago, so its
-- letter would never come. The gold comet is told anew under a mark of its own: it switches on as a new
-- honour does (H.Refresh), and the Speedrunner's letter comes once (H.SpeedrunnerLetter).
H.SPEEDRUNNER_KEY = "level-race-60"
H.SPEEDRUNNER_MARK = "speedrunner@level-race-60"
function H.SpeedrunnerAnew()
	if not ns.db or not Speedrunner() then return false end
	local told = H.Lettered()
	return told[H.APOLOGY_KEY] == true and not told[H.SPEEDRUNNER_MARK]
end
-- held: the look's (H.Refresh). His letter of the gold comet under its own mark; one listed already (queued
-- since the apology let the race's go: the race's mark was untold) is that letter, and is only marked.
function H.SpeedrunnerLetter(held)
	if not H.SpeedrunnerAnew() then return false end
	local gold = false
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and h.key == H.SPEEDRUNNER_KEY then gold = true break end
	end
	if not gold then return false end
	for _, x in ipairs(H.Letters()) do
		if type(x) == "table" and x.key == H.SPEEDRUNNER_KEY then
			local m = ns.ArenaProfile.Mine(true)
			m.lettered = H.Lettered()
			m.lettered[H.SPEEDRUNNER_MARK] = true
			return false
		end
	end
	H.QueueLetter(H.SPEEDRUNNER_KEY, nil, nil, H.SPEEDRUNNER_MARK)
	return true
end

-- A letter queued (and kept, re-readable): shown now, or after the one open; never twice (period:
-- a month's honour's month).
-- Where the save did not come back (Arena.Persists: the Forever beta loads an empty one at each
-- login; a first session) nothing told is known: every honour held looks new at each login. The
-- letter is kept in the profile's list, unread, to open from the Edit, and never opens by itself
-- (1.2.1, the owner's ask: never again at each update; as the update letter, Letters.lua).
-- (1.2.4 repair: a Slayer letter, Wanted's "wanted@" family, one a kill, is never marked in
-- lettered: its own queue in Wanted.lua shows it once, and a mark a kill grew the account's saved
-- data without end. It is kept in the list like any letter, once (the same key listed already
-- queues nothing), and marks an earlier build left are let go. now: its caller found nothing in
-- the way and, with the gamepad UI, the Olympus window open: it shows now, as the window's own
-- opening shows a letter waiting, H.WindowShown.)
-- (1.5.5: as, the mark it is told under where not its own: the Speedrunner's, H.SpeedrunnerLetter.)
function H.QueueLetter(key, period, now, as)
	if type(key) ~= "string" then return end
	local told = H.Lettered()
	local slayer = H.LetterFamily(key) == "wanted"
	local mark = type(as) == "string" and as or H.LetterMark(key, period)
	if not slayer and told[mark] then return end
	local P = ns.ArenaProfile
	local m = P.Mine(true)
	m.lettered = told
	if slayer then
		for k in pairs(told) do if type(k) == "string" and k:find("^wanted@") then told[k] = nil end end
		for _, x in ipairs(type(m.letters) == "table" and m.letters or {}) do if type(x) == "table" and x.key == key then return end end
	else
		told[mark] = true
	end
	-- (1.2.3: the King's honours are told too, with no letter, so they switch on as anyone's: once.)
	if H.LetterToSender() then return end
	m.letters = type(m.letters) == "table" and m.letters or {}
	m.letters[#m.letters + 1] = { key = key, t = Now() }
	while #m.letters > H.LETTERS_MAX do table.remove(m.letters, 1) end
	if not Arena.Persists() then return end
	letters[#letters + 1] = { key = key, t = Now() }
	H.ShowLetter(nil, now == true)
end
function H.Letters()
	if H.LetterToSender() then return {} end
	local m = ns.ArenaProfile.Mine()
	return type(m.letters) == "table" and m.letters or {}
end

-- The family a letter speaks for (its text in L.HONOR_LETTER).
function H.LetterFamily(key)
	if type(key) ~= "string" then return nil end
	-- (1.5.5: the level race's apology, a letter with no honour: H.ApologyDue.)
	if key == H.APOLOGY_KEY then return "apology" end
	if key:find("^arena%-champion") then return "arena" end
	if key:find("^arena%-class%-") then return "class" end
	if key:find("^arena%-race%-") then return "race" end
	if key:find("^donor%-top%-") then return "donor-top" end
	if key:find("^donor%-month%-") then return "donor-month" end
	-- (1.5.5: a retired comet's letter, its words of its own: RetiredKey.)
	if RetiredKey(key) then return "level-retired" end
	if key:find("^level%-race%-") then return "level" end
	if key:find("^oracle%-") then return "oracle" end
	if key == "guild-top-leader" then return "guild" end
	if key:find("^missionary%-") then return "missionary" end
	-- (1.2.4: Most Wanted's Slayer letter, its words Wanted.lua's: H.LetterText.)
	if key:find("^wanted@") then return "wanted" end
	-- (1.2.4)
	if key:find("^apostle%-[123]$") then return "apostle" end
	if key:find("^bones%-") then return "bones" end
	if key:find("^wanted%-slayer%-") then return "wanted-slayer" end
	return nil
end
-- The letter's words: the King's, naming the honour and its title (never a real name).
function H.LetterText(key)
	-- (1.2.4: the Slayer letter's words, and its title, are Wanted.lua's, from its key alone:
	-- Wanted.LetterText. It is queued, shown once and kept to read again as every letter is.)
	if type(key) == "string" and key:find("^wanted@") then
		local W = ns.Wanted
		if type(W) == "table" and not W.missing and type(W.LetterText) == "function" then return W.LetterText(key) end
		return nil
	end
	local family = H.LetterFamily(key)
	local fmt = family and L.HONOR_LETTER and L.HONOR_LETTER[family]
	if not fmt then return nil end
	local title = H.TitleText(key) or key
	local _, _, metal = ns.Honors.ArtOf(key)
	local milestone = tonumber(key:match("^level%-race%-(%d+)$"))
	return fmt:format(title, milestone or (metal and L["HONOR_METAL_" .. metal:upper()] or "")), title
end

-- Under the gamepad UI nothing of Olympus opens by itself (the design: focus only on a
-- click): a letter waits for the player's own click, the next time the Olympus window
-- (H.WindowShown) or his profile's Edit opens (ProfileEdit.Open), and chat says once that one is
-- waiting.
function H.WaitForWindow()
	if not H.toldWaiting then
		H.toldWaiting = true
		ns.Print(L.HONOR_LETTER_WAITING)
	end
end
-- The Olympus window opened (UI.lua, its OnShow: the window is made on its first open, in either
-- look and either template, so nothing here can hook it beforehand): the letter waiting shows.
function H.WindowShown()
	if letters[1] then return H.ShowLetter(nil, true) end
	return false
end

local frame
local INK_R, INK_G, INK_B = 0.18, 0.10, 0.02
-- The game's letter font (its mail's), else its quest font: dark ink on the parchment.
local function LetterFont()
	if _G.MailTextFontNormal then return "MailTextFontNormal" end
	return _G.QuestFont and "QuestFont" or "GameFontHighlight"
end
-- A font string at px at least (the client's own font, only bigger).
local function AtLeast(fs, px)
	if not (fs and fs.GetFont and fs.SetFont) then return end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and type(path) == "string" and type(size) == "number" and size < px then fs:SetFont(path, px, flags) end
end
local function Ink(fs, wrap)
	fs:SetTextColor(INK_R, INK_G, INK_B)
	if fs.SetJustifyV then fs:SetJustifyV("TOP") end
	if wrap and fs.SetWordWrap then fs:SetWordWrap(true) end
	if wrap and fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
	AtLeast(fs, H.LETTER_FONT)
end
-- A text's height at `width`: the client's measure, else about 7 px a letter and 18 a line.
local function TextHeight(fs, width)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	if type(h) == "number" and h > 0 then return h end
	local lines = 0
	for line in ((fs:GetText() or "") .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + math.max(1, math.ceil(#line / math.max(1, math.floor(width / 7))))
	end
	return lines * 18
end

-- The letter (1.2.1, the owner's ask after the King's stream: its words ran off the paper and its
-- buttons under it, no window round it): a window of Olympus's own (ns.Window: the Olympus
-- window's bronze metal without its portrait or logo, as the update letter), the head in its
-- title bar, the parchment (the game's QuestBG, its paper's part alone) inside it, his own
-- portrait with the new frame in its top left corner, the King's words right of it in the game's
-- letter font (15 px at least), wrapped inside the paper; the wax seal and the signature under
-- both, "Wear it" and "Later" at its foot. Its height follows the words. Never the game's popups.
local function Build()
	local f = ns.Window("OlympusKingsLetter", UIParent, { title = L.HONOR_LETTER_HEAD, inset = false, close = false })
	f:SetSize(H.LETTER_W, 300)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.head = f.TitleText
	local inner, pad = f.inner, H.LETTER_PAD
	f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.bg:SetPoint("TOPLEFT", inner[1], inner[2])
	f.bg:SetPoint("BOTTOMRIGHT", inner[3], inner[4])
	local UI = ns.UI
	local file = type(UI) == "table" and UI.FirstTexture and UI.FirstTexture(UI.PARCHMENTS or { "Interface\\QuestFrame\\QuestBG" })
		or "Interface\\QuestFrame\\QuestBG"
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		f.bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		f.bg:SetTexture(file)
		if file:find("QuestBG", 1, true) then f.bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	-- His own portrait with the honour's frame, as round his unit frame's (H.NewPortrait: 60, his
	-- frame's own size), its art clear of the paper's edge and the title bar.
	local rig = H.NewPortrait(f, H.LETTER_PORTRAIT)
	local reach = rig.reach
	f.paperTop = -inner[2] + pad
	rig.slot:SetPoint("TOPLEFT", inner[1] + pad + reach.left, -(f.paperTop + reach.top))
	f.rig, f.portrait = rig, rig.portrait
	-- The words right of the art, to the paper's right margin.
	local x = inner[1] + pad + reach.left + H.LETTER_PORTRAIT + reach.right + 12
	f.bodyWidth = H.LETTER_W + inner[3] - pad - x
	f.body = f:CreateFontString(nil, "ARTWORK", LetterFont())
	f.body:SetPoint("TOPLEFT", x, -f.paperTop)
	f.body:SetWidth(f.bodyWidth)
	f.body:SetJustifyH("LEFT")
	Ink(f.body, true)
	f.sign = f:CreateFontString(nil, "ARTWORK", LetterFont())
	f.sign:SetJustifyH("RIGHT")
	Ink(f.sign)
	f.sign:SetText(L.HONOR_LETTER_SIGN)
	f.seal = f:CreateTexture(nil, "ARTWORK")
	f.seal:SetSize(40, 40)
	-- The game's own wax seal (its quest letters from the King, QuestInfo.lua), the faction's.
	local atlas = ns.faction == "Horde" and "Quest-Horde-WaxSeal" or "Quest-Alliance-WaxSeal"
	local info = C_Texture and C_Texture.GetAtlasInfo
	local okA, has = false, nil
	if type(info) == "function" then okA, has = pcall(info, atlas) end
	if okA and has then f.seal:SetAtlas(atlas) else f.seal:SetTexture("Interface\\Icons\\Spell_Holy_SealOfSacrifice") end
	H.TintSeal(f.seal)
	local function Btn(label, dx, fn)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(H.LETTER_BUTTON, 24)
		b:SetPoint("BOTTOM", dx, inner[4] + 12)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	f.wear = Btn(L.HONOR_LETTER_WEAR, -(H.LETTER_BUTTON / 2 + 6), function() H.CloseLetter(true) end)
	f.later = Btn(L.HONOR_LETTER_LATER, H.LETTER_BUTTON / 2 + 6, function() H.CloseLetter(false) end)
	-- Hidden another way (Escape, the game's window sweep): as "Later", so it never comes back by
	-- itself with the next letter or the Olympus window's open. The whole interface hidden (Alt+Z, a
	-- cinematic: still shown itself, as Dialog.lua's) is no answer: it is there again with it.
	f:SetScript("OnHide", function()
		if f:IsShown() then return end
		if f.key ~= nil then ns.SafeCall("kings letter", H.CloseLetter, false) end
	end)
	return f
end
-- Placed for the words it shows: the body's height measured, the seal and the signature under
-- the words and the art, the window as tall as that and its buttons.
local function Place(f)
	local inner, reach, top = f.inner, f.rig.reach, f.paperTop
	f.body:SetHeight(0) -- (a font string 0 tall is as tall as its words: measured whole)
	local h = math.ceil(TextHeight(f.body, f.bodyWidth)) + 2
	f.body:SetHeight(h)
	local y = math.max(top + h, top + reach.top + H.LETTER_PORTRAIT + reach.bottom) + 10
	f.sign:SetPoint("TOPRIGHT", inner[3] - H.LETTER_PAD - 8, -(y + 12))
	-- (1.2.4, the author's ask: the wax seal just before the signature, on the right, not at the
	-- paper's left edge.)
	f.seal:ClearAllPoints()
	f.seal:SetPoint("RIGHT", f.sign, "LEFT", -6, 0)
	f:SetHeight(y + 40 + 12 + 24 + inner[4] + 12)
end

-- (1.2.4) In an instance or Busy (ns.Quiet) a letter that would open by itself waits as every popup
-- of Olympus's does (the held alerts, ns.Alert): a chat line now, its line on the Decrees tab, and
-- opened once he is out (ns.ReleaseHeld: a new zone, a change of his flags, or within 10 seconds).
-- His own click opens it at once (the Olympus window, H.WindowShown; his profile's Edit; the
-- Decrees tab's line). One held line for every letter waiting. (1.2.4's first cut opened it over a
-- dungeon or a raid between pulls: the month's turn, 00:01 UTC, is 21:01 in Brazil.)
H.LETTER_HELD = "honors letter"
local function HoldLetter()
	for _, x in ipairs(ns.Held()) do if x.key == H.LETTER_HELD then return end end
	ns.Alert("arena", "soft", { what = L.HELD_HONOR_LETTER, key = H.LETTER_HELD,
		open = function() return letters[1] ~= nil end,
		-- (still held: the Decrees tab's line, his own click; out: ReleaseHeld's, by itself)
		show = function() H.ShowLetter(nil, ns.Quiet() ~= nil) end })
	ns.Print("|cffffd200" .. L.HONOR_LETTER_HELD .. "|r")
end

-- A Slayer receipt never interrupts a fight or an instance, even when the Olympus window
-- opens or alerts are set to always. Read only the same client APIs Wanted's notices use;
-- an unreadable state waits too. Unlike an answer, parking must not consume or mark the receipt.
local function SlayerStateBlocked(api)
	if type(api) ~= "function" then return false end
	local ok, yes = pcall(api)
	return not ok or (issecretvalue and issecretvalue(yes)) or yes == true
end
local function SlayerBlocked()
	return SlayerStateBlocked(InCombatLockdown) or SlayerStateBlocked(IsInInstance)
end
local function ParkSlayerLetter()
	if not frame or frame.preview or H.LetterFamily(frame.key) ~= "wanted" then return end
	frame.key = nil -- OnHide is Later only for a letter the player actually closes.
	frame:Hide()
end

local function SlayerPending()
	for _, letter in ipairs(letters) do if H.LetterFamily(letter.key) == "wanted" then return true end end
	return false
end
-- An idle client has no letter-state listeners. The shared event bus has no per-callback
-- unregister operation, so install these once, only after a real Slayer receipt is queued;
-- after it is answered they return without reading client state or scheduling anything.
local slayerWatching = false
local function SlayerLetterState()
	if not SlayerPending() then return end
	if SlayerBlocked() then ParkSlayerLetter() return end
	-- A state event carries no prior click: gamepad and Busy keep their ordinary waits.
	if letters[1] and H.LetterFamily(letters[1].key) == "wanted" then H.ShowLetter() end
end
local function WatchSlayerLetters()
	if slayerWatching or not SlayerPending() then return end
	slayerWatching = true
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
		ns.RegisterEvent(event, SlayerLetterState)
	end
end

-- key: a letter asked for (a click: shown at once); prompted: the player's click opened it.
function H.ShowLetter(key, prompted)
	if H.LetterToSender() then return false end
	if key then letters[#letters + 1] = { key = key, t = Now() } end
	local nextLetter = letters[1]
	if not nextLetter then return false end
	WatchSlayerLetters()
	if H.LetterFamily(nextLetter.key) == "wanted" and SlayerBlocked() then
		ParkSlayerLetter()
		return false
	end
	if frame and frame:IsShown() then return true end
	if not key and not prompted and ns.GamepadUI() then
		H.WaitForWindow()
		return false
	end
	if not key and not prompted and ns.Quiet() then
		HoldLetter()
		return false
	end
	H.toldWaiting = nil
	if InCombatLockdown and InCombatLockdown() then
		ns.After(5, "kings letter", function() H.ShowLetter(nil, prompted) end)
		return false
	end
	frame = frame or Build()
	local text = H.LetterText(nextLetter.key)
	frame.key = nextLetter.key
	frame.preview = false
	frame.head:SetText(L.HONOR_LETTER_HEAD)
	frame.wear:SetEnabled(true)
	frame.later:SetText(L.HONOR_LETTER_LATER)
	frame.body:SetText(text or "")
	Place(frame)
	-- (1.2.4 repair: a Slayer letter has no honour to wear: its first button opens the Slayers, the
	-- Wanted tab, and his portrait wears his rank's frame, as his own does.)
	local slayer = H.LetterFamily(nextLetter.key) == "wanted"
	-- (1.5.5: the level race's apology has nothing to wear either, nor a retired comet's letter
	-- (RetiredKey): its first button closes it, and his portrait wears his rank's frame.)
	local apology = nextLetter.key == H.APOLOGY_KEY or RetiredKey(nextLetter.key)
	frame.wear:SetText(slayer and L.HONOR_LETTER_SLAYERS or apology and L.LETTERS_CLOSE or L.HONOR_LETTER_WEAR)
	H.DressPortrait(frame.rig, (slayer or apology) and "rank" or nextLetter.key)
	frame:Show()
	return true
end
-- "Wear it" (its frame and title picked) or "Later"; the next letter after it. (1.2.4: a Slayer
-- letter's first button, Slayers: the Olympus window on the Wanted tab, the player's own click.)
function H.CloseLetter(wear)
	-- A development preview is not an award, nor an answer to a real waiting letter.
	if frame and frame.preview == true then
		frame.key, frame.preview = nil, false
		frame:Hide()
		if letters[1] then H.ShowLetter(nil, true) end
		return true
	end
	local cur = table.remove(letters, 1)
	if frame then
		frame.key = nil
		frame:Hide()
	end
	if cur then
		for _, x in ipairs(H.Letters()) do if x.key == cur.key then x.read = true end end
		if wear and H.LetterFamily(cur.key) == "wanted" then
			local UI = ns.UI
			if type(UI) == "table" and type(UI.SelectTab) == "function" then ns.SafeCall("slayer letter", UI.SelectTab, "wanted") end
		elseif wear then
			local held = H.Holdings(ns.me, ns.ArenaProfile.MyGk())
			local frameKey, titleKey
			for _, h in ipairs(held) do
				-- (1.2.3: a frame this version does not wear yet, its title alone: Honors.Choose refused
				-- the pair, and "Wear it" did nothing.)
				if h.key == cur.key then frameKey, titleKey = ns.Honors.FrameShipped(h) and h.frame or nil, h.title end
			end
			if frameKey or titleKey then ns.ArenaProfile.SetPick(frameKey or ns.ArenaProfile.Pick().frame, titleKey) end
		end
	end
	-- (The next one after this click: the player's own.)
	if letters[1] then H.ShowLetter(nil, true) end
	return true
end
function H.LetterFrame() return frame end
function H.QueuedLetters() return letters end

-- All existing letter families on the same real framed parchment. The Workshop gate is
-- actual author/dev access, never View as. Nothing is queued, awarded, worn or broadcast.
function H.PreviewKeys()
	local W = ns.Workshop
	if not (W and W.Visible and W.Visible() == true) then return {} end
	local out = { "arena-champion", "arena-champion-2", "arena-champion-3", "guild-top-leader" }
	for _, family in ipairs({ "donor-top", "donor-month", "oracle", "missionary", "apostle", "bones", "wanted-slayer" }) do
		for i = 1, 3 do out[#out + 1] = family .. "-" .. i end
	end
	-- (1.5.5: the gold comet's alone, the Olympus Speedrunner's, and the level race's apology; bronze and
	-- silver are retired.)
	for _, milestone in ipairs(ns.Honors.MILESTONES) do
		if not ns.Honors.RETIRED_LEVELS[milestone] then out[#out + 1] = "level-race-" .. milestone end
	end
	out[#out + 1] = H.APOLOGY_KEY
	for _, pair in ipairs({ { "class", ns.Honors.CLASS_ART }, { "race", ns.Honors.RACE_ART } }) do
		local words = {}; for word in pairs(pair[2]) do words[#words + 1] = word end; table.sort(words)
		for _, word in ipairs(words) do
			local key = "arena-" .. pair[1] .. "-" .. word
			out[#out + 1], out[#out + 2], out[#out + 3] = key, key .. "-2", key .. "-3"
		end
	end
	-- A fictional example of the separately retained Slayer receipt letter; not a Wanted entry.
	out[#out + 1] = "wanted@0123456789abcdef~238~120~18~100~1~60~Horde Wanderer"
	return out
end
function H.PreviewLetter(key)
	local valid = false
	for _, k in ipairs(H.PreviewKeys()) do if k == key then valid = true; break end end
	if not valid or (InCombatLockdown and InCombatLockdown()) or (frame and frame:IsShown() and frame.preview ~= true) then return false end
	local text = H.LetterText(key)
	if not text then return false end
	frame = frame or Build()
	frame.preview, frame.key = true, key
	frame.head:SetText(L.HONOR_LETTER_PREVIEW_HEAD)
	frame.body:SetText(text)
	frame.wear:SetEnabled(false)
	frame.wear:SetText(L.HONOR_LETTER_PREVIEW_ONLY)
	frame.later:SetText(CLOSE or L.HONOR_LETTER_LATER)
	Place(frame)
	H.DressPortrait(frame.rig, (H.LetterFamily(key) == "wanted" or key == H.APOLOGY_KEY) and "rank" or key)
	frame:Show()
	return true
end
-- The page of the previews lies on the Olympus window's parchment (its Realm page, parchment =
-- true): its words in the game's quest fonts, the dark ink of the Throne's and "Your week"'s pages
-- (line.font), never the list's white. (2026-10-19, the author: "as letras brancas em cima do
-- parchment, não dá para ler direito".) A row never wraps: the note in rows short enough for it.
local PAGE_INK, PAGE_TITLE = "QuestFont", "QuestTitleFont"
H.PAGE_WRAP = 44
local function PageLine(text, font, extra)
	local line = { text = text, font = font or PAGE_INK }
	for k, v in pairs(extra or {}) do line[k] = v end
	return line
end
local function PageParagraph(lines, text, extra)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > H.PAGE_WRAP then
			lines[#lines + 1] = PageLine(row)
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = PageLine(row, nil, extra) end
end
function H.PreviewLines()
	local keys = H.PreviewKeys()
	if #keys == 0 then return {} end
	-- Its first row, Back: the Realm again, as the Realm's other pages (2026-10-19, the author: the
	-- page had none, he went to Classes and back to leave it).
	local lines = { PageLine(L.HONOR_LETTER_PREVIEW_BACK, PAGE_INK, { gapAfter = true, onClick = function() ns.Views.ShowPage(nil) end }),
		PageLine(L.HONOR_LETTER_PREVIEW_HEAD, PAGE_TITLE, { header = true }) }
	PageParagraph(lines, L.HONOR_LETTER_PREVIEW_NOTE, { gapAfter = true })
	for _, key in ipairs(keys) do
		local k = key
		lines[#lines + 1] = PageLine("> " .. (H.TitleText(k) or k), nil, { onClick = function() H.PreviewLetter(k) end })
	end
	return lines
end
function H.PreviewSlash(rest)
	if #H.PreviewKeys() == 0 then return false end
	local key = tostring(rest or ""):gsub("^%s*preview%s*", ""):gsub("%s+$", "")
	if key ~= "" then return H.PreviewLetter(key) end
	ns.UI.SelectTab("realm")
	ns.Views.ShowPage("honorletters")
	return true
end
ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "honorletters", parchment = true, Lines = H.PreviewLines,
	Link = function() if #H.PreviewKeys() > 0 then return { text = "> " .. L.HONOR_LETTER_PREVIEW_HEAD, onClick = function() H.PreviewSlash("") end } end end })

---------------------------------------------------------------------------
-- (1.2.4) The places told: the King's letter the first time, a notice after
---------------------------------------------------------------------------

H.NOTICE_SETTLE = 120  -- a move is said once it held this long (a swap back meanwhile says nothing)
H.NOTICE_GAP = 900     -- one family's notices this far apart at least (what moved meanwhile: where it ended, once)
H.NOTICE_SHOW = 8      -- a notice's strip stays this long on screen
H.NOTICE_EVERY = 2     -- a new strip this often at most...
H.NOTICE_STACK = 3     -- ...this many at once...
H.NOTICE_SESSION = 10  -- ...and this many a session; the rest in chat alone
H.NOTICE_PARTS = 3     -- the families one "since your last visit" strip names (the rest counted)
H.NOTICES_KEPT = 20    -- this session's notices kept to read (H.Notices)
H.NOTICE_W, H.NOTICE_H, H.NOTICE_TOP = 440, 44, 260

-- What this character was last told of each family (Honors.Moves' standing, with t: when it was
-- said), kept in his profile beside lettered.
function H.Standing()
	local P = ns.ArenaProfile
	local m = type(P) == "table" and type(P.Mine) == "function" and P.Mine() or {}
	local standing = type(m.standing) == "table" and m.standing or {}
	if H.LevelRaceActive() then return standing end
	-- Old notice standings are historical too: retain the saved facts, but expose no live place
	-- in an unlaunched race (and do not announce that an old recorded place was newly lost).
	local out = {}
	for family, v in pairs(standing) do
		if type(family) ~= "string" or not family:match("^level%-%d+$") then out[family] = v end
	end
	return out
end

-- A family's list as the notices name it (L.HONOR_RANKING), for a family whose frame this version
-- wears alone (the level race's comet is never taken back; the Arena's and the Oracle's wait).
local function Ranking(family)
	local names = L.HONOR_RANKING
	if type(names) ~= "table" or type(names[family]) ~= "string" then return nil end
	return ns.Honors.FrameShipped({ family = family }) and names[family] or nil
end
-- A move's honour (its mark on the strip): the one held, else the place he left.
local function MoveKey(m)
	if m.honour then return m.honour.key end
	if m.family == "guild" then return "guild-top-leader" end
	return m.family .. "-" .. m.from
end
local function PlaceText(p) return type(L.HONOR_PLACE) == "table" and L.HONOR_PLACE[p] or tostring(p) end
-- A notice's words: its own line, and its part of a "since your last visit".
local function NoticeText(m)
	local name = Ranking(m.family)
	if m.kind == "out" then
		return m.family == "guild" and L.HONOR_NOTICE_GUILD_OUT or L.HONOR_NOTICE_OUT:format(name), L.HONOR_NOTICE_PART_OUT:format(name)
	end
	local place = PlaceText(m.to)
	local part = L.HONOR_NOTICE_PART_PLACE:format(name, place)
	if m.family == "guild" then return L.HONOR_NOTICE_GUILD_BACK, part end
	if m.kind == "down" then return L.HONOR_NOTICE_DOWN:format(name, place), part end
	if m.kind == "back" then return L.HONOR_NOTICE_BACK:format(name, place), part end
	return L.HONOR_NOTICE_UP:format(name, place), part
end

-- A family's source loaded (as Honors.Update asks it): the families looked at this session.
local function Loaded(known, family)
	if known == true then return true end
	local source = type(family) == "string" and family:match("^(%a+)") or nil
	return type(known) == "table" and source ~= nil and known[source] == true
end

local pendingMoves, looked = {}, {} -- [family] = { p, c, since, away }; [family] = true once loaded this session
local notices, strips, stripQueue = {}, {}, {}
local stripsShown, lastStrip, pumping = 0, nil, false
local lookAt
-- One look of our honours at `at` (the earliest asked; a later one waits for the look before it).
local function LookAt(at)
	if lookAt and lookAt <= at then return end
	lookAt = at
	ns.After(math.max(1, at - Now()), "arena honours look", function()
		if lookAt ~= at then return end
		lookAt = nil
		H.Refresh()
	end)
end
-- The next calendar month's first second (the honours' clock, Honors.MonthOf).
local function NextMonth(now)
	local Hs = ns.Honors
	local m = Hs.MonthOf(now)
	local t = (math.floor(now / 86400) + 1) * 86400
	while Hs.MonthOf(t) == m do t = t + 86400 end
	return t
end

-- A strip of Olympus's own at the top of the screen (OlympusHonourNotice1-3): the honour's mark and
-- one line. No title, no button, no mouse, no keyboard, never on the escape list (no pop-up: the
-- gamepad UI's cursor never stops on it, and it takes no click or key from the game), gone after
-- NOTICE_SHOW.
local function Strip(i)
	local f = CreateFrame("Frame", "OlympusHonourNotice" .. i, UIParent)
	f:SetSize(H.NOTICE_W, H.NOTICE_H)
	f:SetPoint("TOP", UIParent, "TOP", 0, -(H.NOTICE_TOP + (i - 1) * (H.NOTICE_H + 4)))
	f:SetFrameStrata("HIGH")
	f:EnableMouse(false)
	f:EnableKeyboard(false)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints(f)
	f.bg:SetColorTexture(0.06, 0.04, 0.02, 0.8)
	-- (a bronze line at its foot, the Olympus window's metal)
	f.edge = f:CreateTexture(nil, "BORDER")
	f.edge:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	f.edge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.edge:SetHeight(2)
	f.edge:SetColorTexture(0.62, 0.46, 0.34, 0.9)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(H.NOTICE_H - 8, H.NOTICE_H - 8)
	f.icon:SetPoint("LEFT", f, "LEFT", 6, 0)
	f.text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
	f.text:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	f.text:SetJustifyH("LEFT")
	if f.text.SetWordWrap then f.text:SetWordWrap(true) end
	f:Hide()
	return f
end
-- The strips waiting, NOTICE_EVERY apart, NOTICE_STACK at once.
local function Pump()
	if not stripQueue[1] then return end
	local now = Now()
	local free
	for i = 1, H.NOTICE_STACK do
		if not strips[i] or not strips[i]:IsShown() then free = i break end
	end
	local wait = lastStrip and lastStrip + H.NOTICE_EVERY - now or 0
	if wait > 0 or not free then
		if not pumping then
			pumping = true
			ns.After(math.max(1, wait), "arena honours notice", function() pumping = false Pump() end)
		end
		return
	end
	local x = table.remove(stripQueue, 1)
	local f = strips[free] or Strip(free)
	strips[free] = f
	f.text:SetText(x.text)
	local tex = H.MarkTexture(x.key)
	if tex then f.icon:SetTexture(tex) f.icon:Show() else f.icon:Hide() end
	f.key, f.at = x.key, now
	f:Show()
	lastStrip = now
	ns.After(H.NOTICE_SHOW, "arena honours notice", function()
		if f.at == now then f:Hide() end
		Pump()
	end)
	Pump()
end
-- A notice: its line in chat, and its strip (none while the alerts are held, ns.Quiet: an instance,
-- Busy; none past NOTICE_SESSION). key: the honour whose mark it carries.
function H.Notice(text, key)
	if type(text) ~= "string" or text == "" then return false end
	local mark = H.ChatMark(key)
	ns.Print((mark and (mark .. " ") or "") .. text)
	notices[#notices + 1] = { text = text, key = key, t = Now() }
	while #notices > H.NOTICES_KEPT do table.remove(notices, 1) end
	if ns.Quiet() or stripsShown >= H.NOTICE_SESSION then return false end
	stripsShown = stripsShown + 1
	stripQueue[#stripQueue + 1] = { text = text, key = key }
	Pump()
	return true
end
function H.Notices() return notices end
function H.NoticeFrames() return strips end

-- What is said at once: the moves found at a family's first look this session (away: they
-- happened while he was away) in one "since your last visit", the others each its own.
local function Say(said)
	local away, parts = {}, {}
	for _, x in ipairs(said) do
		if x.away then
			away[#away + 1] = x.move
		else
			H.Notice((NoticeText(x.move)), MoveKey(x.move))
		end
	end
	if #away == 0 then return end
	for i, m in ipairs(away) do
		if i > H.NOTICE_PARTS then
			parts[#parts + 1] = L.HONOR_NOTICE_MORE:format(#away - H.NOTICE_PARTS)
			break
		end
		parts[#parts + 1] = select(2, NoticeText(m))
	end
	H.Notice(L.HONOR_NOTICE_SINCE:format(table.concat(parts, "; ")), MoveKey(away[1]))
end

-- After a look at our honours (H.Refresh): each family where he stands against what he was last
-- told (Honors.Moves). The first time he reaches a place in its cycle (a first look, a new cycle, a
-- place up or back, its mark not in told: H.Lettered), the King's letter, at once (QueueLetter's
-- rules). A first look or a new cycle at a place told before, a closed month's end, a family the
-- notices don't name: nothing, his standing kept as it is now. Anything else (down a place, off the
-- list, back on it or a place won back, told before) is a notice once it held NOTICE_SETTLE and
-- NOTICE_GAP after his family's last (moving back before that: nothing at all). A family whose source
-- is not loaded keeps what he was told.
function H.Tell(held, known, told)
	local now = Now()
	local standing = H.Standing()
	local moves = ns.Honors.Moves(standing, held, known, { now = now })
	told = type(told) == "table" and told or {}
	local write, said, moved, due = {}, {}, {}, nil
	for _, m in ipairs(moves) do
		local family, h = m.family, m.honour
		local was = type(standing[family]) == "table" and standing[family] or nil
		moved[family] = true
		local reached = m.kind == "seed" or m.kind == "cycle" or m.kind == "up" or m.kind == "back"
		-- (t: when its last notice was said; a letter is no notice, so it keeps the one before.)
		local saidAt = was and tonumber(was.t) or nil
		if reached and h and (h.frame or h.title) and not h.noLetter and not told[H.LetterMark(h.key, h.period)] then
			H.QueueLetter(h.key, h.period)
			write[family], pendingMoves[family] = { p = m.to, c = m.cycle, t = saidAt }, nil
		elseif m.kind == "seed" or m.kind == "cycle" or m.kind == "end" or not Ranking(family) then
			write[family], pendingMoves[family] = { p = m.to, c = m.cycle, t = saidAt }, nil
		else
			local q = pendingMoves[family]
			if not q or q.p ~= m.to or q.c ~= m.cycle then
				q = { p = m.to, c = m.cycle, since = now, away = not looked[family] }
				pendingMoves[family] = q
			end
			local at = math.max(q.since + H.NOTICE_SETTLE, (saidAt or -H.NOTICE_GAP) + H.NOTICE_GAP)
			if now >= at then
				said[#said + 1] = { move = m, away = q.away }
				write[family], pendingMoves[family] = { p = m.to, c = m.cycle, t = now }, nil
			elseif not due or at < due then
				due = at
			end
		end
	end
	-- Back where he was told before it was said (or its source gone meanwhile): nothing to say.
	for family in pairs(pendingMoves) do if not moved[family] then pendingMoves[family] = nil end end
	local monthly = false
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and type(h.family) == "string" then
			looked[h.family] = true
			if ns.Honors.CYCLE[h.family] then monthly = true end
		end
	end
	for family in pairs(standing) do if Loaded(known, family) then looked[family] = true end end
	-- (And while this month's Bone Throw list names him: the charm he may hold when it closes, which
	-- no word announces.)
	if not monthly then
		local bones = BonesTop(ns.Honors.MonthOf(now))
		for _, r in ipairs(bones and bones.month or {}) do
			if Same(r.name, ns.me) then monthly = true break end
		end
	end
	if next(write) then
		local mine = ns.ArenaProfile.Mine(true)
		mine.standing = type(mine.standing) == "table" and mine.standing or {}
		for family, v in pairs(write) do mine.standing[family] = v end
	end
	if #said > 0 then Say(said) end
	-- Looked at again when a notice is due, and at the month's turn while he holds a month's honour
	-- (its new month's letter; a closed list's end): no ticker.
	if due then LookAt(due) end
	if monthly then LookAt(NextMonth(now) + 60) end
	return moves
end

---------------------------------------------------------------------------
-- The role clients' timers (the Treasurer's donors, a bank's Oracle), our own refresh
---------------------------------------------------------------------------

local donorTicker, oracleTicker
function H.WatchRoles()
	local treasurer = ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(ns.me)
	if treasurer and not donorTicker then
		donorTicker = ns.Every(H.DONOR_EVERY, "arena donors", function() H.SendDonors(true) end)
		ns.After(60, "arena donors login", function() H.SendDonors(true) end)
	end
	-- (1.3.4) The King's and the High Council's: the Treasurer's word said again, once one is held.
	local s = H.Store()
	if s and type(s.donors) == "table" then H.WatchDonorRelay() end
	local bank = ns.ArenaRoles.IsBank(ns.me, "L")
	if bank and not oracleTicker then
		oracleTicker = ns.Every(H.ORACLE_EVERY, "arena oracle", function() H.OracleTick() end)
	elseif not bank and oracleTicker then
		if oracleTicker.Cancel then oracleTicker:Cancel() end
		oracleTicker = nil
	end
end

ns.On("LOGIN", function()
	-- (First: the account's profiles as 1.2.0 left them, before anything of this session writes one.)
	H.ReadOldLetters()
	H.WatchLevels()
	H.WatchRoles()
	-- Our own honours whenever the realm's words change (HONORS_CHANGED, below); at login only where
	-- saved data already holds some (an idle client starts no timer: the weight rule).
	local LG = ns.ArenaLedger
	local titles = LG and LG.CoreT and LG.CoreT("L", "titles")
	-- (1.5.5: also the Olympus Speedrunner's, his gold comet held by the signed list alone, and a
	-- character the level race's apology is due to, with no arena data saved.)
	H.speedrunner = type(ns.IsSpeedrunnerName) == "function" and ns.IsSpeedrunnerName(ns.me) == true
	H.sorryDue = H.ApologyDue()
	if H.Store() or (titles and next(titles)) or H.speedrunner or H.sorryDue then
		ns.After(H.REFRESH_DELAY, "arena honours refresh", function() H.Refresh() end)
	end
end)
-- (1.5.5) A signed list that names us the Olympus Speedrunner, or no longer does (DATA_CHANGED: a newer
-- titles list taken): our honours looked at again. (The independent check: so too once the apology falls
-- due, a list naming the Speedrunner taken after our login: H.ApologyDue waits for one.)
ns.On("DATA_CHANGED", function()
	if not ns.db or type(ns.IsSpeedrunnerName) ~= "function" then return end
	local now, sorry = ns.IsSpeedrunnerName(ns.me) == true, H.ApologyDue()
	local look = now ~= (H.speedrunner == true) or (sorry and not H.sorryDue)
	H.speedrunner, H.sorryDue = now, sorry
	if look then H.RefreshSoon() end
end)
-- Our honours looked at again a moment after a change that may be ours (the realm's words, the
-- belts, our own), once for a burst.
local refreshDue = false
function H.RefreshSoon()
	if refreshDue or refreshing then return end
	refreshDue = true
	ns.After(2, "arena honours refresh", function() refreshDue = false H.Refresh() end)
end
ns.On("HONORS_CHANGED", function(name)
	if name == nil or Same(name, ns.me) then H.RefreshSoon() end
end)
ns.On("ARENA_CHANGED", function() H.WatchRoles() end)

Arena.Action("honors.letter", nil, function(key) return H.ShowLetter(key) end)
Arena.Action("honors.refresh", nil, function() return H.Refresh() end)
