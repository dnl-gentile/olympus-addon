local ADDON, ns = ...
local L = ns.L

-- Alt links (1.1, Fern's request #21): a player links the characters of this account as one
-- player, so the census and the treasury count them once.
-- - For this account only: the main names the alt (/oly alt add), then the player logs the alt
--   and confirms there. The offer waits in this account's saved variables (every character of the
--   account shares them, nobody else's can read them): no officer, and no other player, can attach
--   anyone's alt. An alt never starts a link on its own, and a character added later is not linked
--   until it confirms on itself too.
-- - Each linked character's own client says so on the Olympus channel (its own name, which the
--   server stamps), at login, when a link changes and every EVERY:
--     AL~<time of the account's last change>~<M|A|->~<its guild>~<its alts (M) | its main (A)>
--   A link counts on a client only when both characters said it: the main naming the alt, and the
--   alt naming the main. A name another player claims alone links nothing. (1.6.0) On a Forever
--   ruleset an Apostle's or Missionary's group says it over GUILD and to the keepers online too
--   (over GUILD the stamp carries the reader's own sub-realm: the sender's is his hello's).
-- - The census counts people: the army's total leaves out every linked character past the first
--   of its player's in a guild the total counts (Data.Summary). The treasury's ranking and its
--   week's donors put a player's characters on one line, under the main's name (Treasury.Report).
--   Vox Populi takes one vote per player. The alt gains nothing of its main's (a Hand's alt is no
--   Hand: every power goes by the character's own name).
-- - While any linked name is off (net-off, Moderation.lua) the links freeze: the player's own
--   client adds and removes none, and every client keeps the links it knew (a claim may add a
--   name then, never drop one, nor lapse), so nobody drops the punished character to walk back
--   in on the alt. Net-off hides the names linked to a name that is off (Moderation.Hidden).
-- Names travel short when on the sender's realm. Clients before 1.1 drop AL unread.

local Alts = {}
ns.Alts = Alts

Alts.MAX_ALTS = 8            -- alts one main links (the claim must fit one message)
Alts.EVERY = 1800            -- a linked character's client repeats its claim this often
Alts.LOGIN_AFTER = 60        -- ...the first time this long after login (the channel is joined)
-- A claim not heard this long is forgotten (never while frozen). (1.2.4, the author's ask: lists of
-- people are not erased early: it was 30 days, so a player away a month split in two again in the
-- census, the dues and the rankings.)
Alts.KEEP = 180 * 86400
Alts.MAX_CLAIMS = 5000       -- claims kept (the oldest unfrozen goes first)
Alts.DATE_AHEAD = 60         -- a claim dated further ahead of the server's clock is not taken
Alts.ASK_AFTER = 15          -- the alt's confirmation is asked this long after login (not in combat)

local stats = { taken = 0, same = 0, older = 0, frozen = 0, refused = 0, sent = 0, guild = 0, keepers = 0, unplaced = 0 }
local version = 0            -- bumped on every change of a claim or of this account's links
local cache                  -- { version, groups = { { main, members = { { name, guild } } } }, of = { [key] = group } }
local lastSent = -math.huge
local asked = false          -- the confirmation was shown this session

local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end
local function Key(name) return tostring(ns.FullName(ns.Normal(name)) or name):lower() end
Alts.Key = Key
local function Bump() version = version + 1 end
-- (1.2.3) What the links rest on changed since a reader last looked when this number did (the
-- Bones ranking keeps its list until then).
function Alts.Version() return version end

-- A character's name as the server writes it ("First Surname-Realm"), a short one on `realm`;
-- nil if it can't be one.
local function CharName(input, realm)
	local name = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil end
	name = ns.Normal(name)
	local short = ns.King and ns.King.CleanName and ns.King.CleanName(name)
	if not short then return nil end
	local r = ns.RealmOf(name)
	if r then r = r:gsub("[%s%-]", "") end
	return ns.FullName(short, (r and r ~= "") and r or realm)
end

---------------------------------------------------------------------------
-- This account's links (ns.db.alts: every character of the account shares it)
--   links[alt key]  = { name = alt, main = main, at }   confirmed on the alt
--   offers[alt key] = { name = alt, main = main, t, faction, group }   named on the main, waiting
--   guilds[key]     = the last guild observed for that character
--   told[key]       = the account's change that character's client last announced
---------------------------------------------------------------------------

local function Account()
	local db = ns.db
	if type(db) ~= "table" then return { links = {}, offers = {}, guilds = {}, told = {} } end
	local a = db.alts
	if type(a) ~= "table" then
		a = {}
		db.alts = a
	end
	for _, k in ipairs({ "links", "offers", "guilds", "told" }) do
		if type(a[k]) ~= "table" then a[k] = {} end
	end
	return a
end

local function Changed()
	local a = Account()
	local at = Clock()
	a.at = (tonumber(a.at) or 0) >= at and a.at + 1 or at
	Bump()
	ns.Fire("DATA_CHANGED")
end

-- This account's main of a character, its alts, and its whole group (names), from the saved links.
local function AccountMain(name)
	local link = Account().links[Key(name)]
	if type(link) == "table" then return link.main end
	for _, e in pairs(Account().links) do
		if type(e) == "table" and Key(e.main) == Key(name) then return e.main end
	end
	return nil
end
local function AccountAlts(main)
	local out, key = {}, Key(main)
	for _, e in pairs(Account().links) do
		if type(e) == "table" and Key(e.main) == key then out[#out + 1] = e.name end
	end
	table.sort(out)
	return out
end
function Alts.MyGroup()
	local main = ns.me and AccountMain(ns.me)
	if not main then return nil end
	local out = { main }
	for _, a in ipairs(AccountAlts(main)) do out[#out + 1] = a end
	return out
end

---------------------------------------------------------------------------
-- The claims heard on the channel (ns.rdb.altClaims, per realm group like the census), and the
-- groups they confirm
---------------------------------------------------------------------------

local function Claims()
	local rdb = ns.rdb
	local c = rdb and rdb.altClaims
	if type(c) ~= "table" then
		c = {}
		if rdb then rdb.altClaims = c end
	end
	return c
end

-- A character's claim: this account's own from its saved links (the confirmations themselves),
-- anyone else's as last heard. { name, role = "M"|"A"|"-", links = { names }, guild }.
local function ClaimOf(name)
	local key = Key(name)
	local a = Account()
	local link = a.links[key]
	if type(link) == "table" then return { name = link.name, role = "A", links = { link.main }, guild = a.guilds[key], own = true } end
	for _, e in pairs(a.links) do
		if type(e) == "table" and Key(e.main) == key then
			return { name = e.main, role = "M", links = AccountAlts(e.main), guild = a.guilds[key], own = true }
		end
	end
	local c = Claims()[key]
	return type(c) == "table" and c or nil
end

local function Has(list, name)
	local key = Key(name)
	for _, n in ipairs(list or {}) do if Key(n) == key then return true end end
	return false
end

-- 1.4.0 (the author, 11-03: "os números do beta não devem ser utilizados... reseta tudo"): a
-- character counts here only while it is of our realm group. This account's links are account-wide
-- (ns.db.alts), so the beta's links came to the launch realms with it; matched by guild name alone
-- (Duplicates), a beta pair in "Olympus" took people off a launch "Olympus". A character of another
-- group is in another census anyway. A name without a realm is ours; no group known yet: every one.
-- A character of our own realm is ours whatever the group's name: never one taken off for a group
-- name GroupOf spells otherwise.
local function OfOurGroup(name)
	local group = ns.group
	if type(group) ~= "string" or group == "" or type(name) ~= "string" then return true end
	local realm = ns.RealmOf and ns.RealmOf(ns.FullName(name))
	if not realm or realm == "" or realm == ns.realm then return true end
	return ns.GroupOf(realm) == group
end

-- (1.6.0) WoW: Forever's rulesets are families of sub-realms ("CAMWOW...Realm<n>PvE", ns.ForeverFamily),
-- and a name is one across its family (ns.TellName, Church.Key): a name given plain is the character of
-- that name on any sub-realm of ours. "/oly alt add First Surname" on the main gave the main's own
-- sub-realm to an alt that plays on another one: that alt was never asked, and its yes found nothing.
local function Family()
	local group = ns.group
	return type(group) == "string" and group:match("^Forever%a+$") and group or nil
end
local function Plain(name) return ns.Fold(ns.ShortName(ns.Normal(tostring(name or "")))) end
-- A name of our Forever family: its realm one of the family's, or none given.
local function InFamily(name)
	local family = Family()
	if not family or type(name) ~= "string" then return false end
	local realm = ns.RealmOf(name)
	return not realm or realm == "" or ns.GroupOf(realm) == family
end
-- The key of the one entry of `list` (this account's offers or links) whose character has the plain
-- name of `name` within our Forever family; nil for none, or two.
local function ByPlain(list, name)
	if not InFamily(name) then return nil end
	local plain, found = Plain(name), nil
	for k, e in pairs(list) do
		if type(e) == "table" and type(e.name) == "string" and Plain(e.name) == plain and InFamily(e.name) then
			if found and found ~= k then return nil end
			found = k
		end
	end
	return found
end
-- This account's offer for a character: under its own name, or one its main made with the plain name.
-- Its key and the offer.
local function OfferFor(name)
	local offers = Account().offers
	local key = Key(name)
	if type(offers[key]) == "table" then return key, offers[key] end
	local k = ByPlain(offers, name)
	if k then return k, offers[k] end
	return nil
end
-- The key of this account's link of a character: as named, or the linked character of that plain name.
local function LinkKey(name)
	local links = Account().links
	local key = Key(name)
	if type(links[key]) == "table" then return key end
	return ByPlain(links, name)
end

-- The group a main's claim confirms: the main and each alt that names it back. (1.6.0) An alt the
-- claim names plain (Wire, past one message's room with its sub-realm) is the one claim of our Forever
-- family with that plain name (byPlain), never one of two.
local function GroupOfMain(main, byPlain)
	if not main or main.role ~= "M" or not OfOurGroup(main.name) then return nil end
	local members = { { name = main.name, guild = main.guild } }
	local seen = { [Key(main.name)] = true }
	for _, alt in ipairs(main.links) do
		local c = ClaimOf(alt)
		if not c and byPlain and InFamily(alt) then
			local k = byPlain[Plain(alt)]
			c = k and Claims()[k] or nil
		end
		if c and c.role == "A" and c.links[1] and Key(c.links[1]) == Key(main.name) and OfOurGroup(c.name) and not seen[Key(c.name)] then
			seen[Key(c.name)] = true
			members[#members + 1] = { name = c.name, guild = c.guild }
		end
	end
	if #members < 2 then return nil end
	return { main = main.name, members = members }
end

-- Every confirmed group, rebuilt after any change (the census asks often).
local function Groups()
	if cache and cache.version == version and cache.rdb == ns.rdb and cache.db == ns.db and cache.group == ns.group and cache.realm == ns.realm then return cache end
	local forever = Family()
	cache = { version = version, rdb = ns.rdb, db = ns.db, group = ns.group, realm = ns.realm, groups = {},
		of = {}, short = forever and {} or nil }
	local mains, byPlain = {}, forever and {} or nil
	for key, c in pairs(Claims()) do
		if type(c) == "table" and c.role == "M" then mains[key] = true end
		if byPlain and type(c) == "table" and c.role == "A" and type(c.name) == "string" and InFamily(c.name) then
			local p = Plain(c.name)
			if byPlain[p] == nil then byPlain[p] = key elseif byPlain[p] ~= key then byPlain[p] = false end
		end
	end
	cache.byPlain = byPlain
	for _, e in pairs(Account().links) do
		if type(e) == "table" then mains[Key(e.main)] = true end
	end
	for key in pairs(mains) do
		local main = ClaimOf(key)
		local g = main and GroupOfMain(main, byPlain)
		if g then
			cache.groups[#cache.groups + 1] = g
			for _, m in ipairs(g.members) do
				local full = Key(m.name)
				cache.of[full] = g
				if cache.short then
					local short = ns.Fold(ns.ShortName(m.name))
					local prior = cache.short[short]
					if prior == nil then cache.short[short] = { name = full, group = g }
					elseif prior and (prior.name ~= full or prior.group ~= g) then cache.short[short] = false end
				end
			end
		end
	end
	return cache
end

-- The confirmed group of a character: { main, members = { { name, guild } } }, or nil.
function Alts.Group(name)
	if type(name) ~= "string" or name == "" then return nil end
	return Groups().of[Key(name)]
end

-- The guild-event log and the Church ledger can expose only the short name. On Forever's live
-- rulesets that name is unique within this census. The caller still rejects an explicit other group.
function Alts.GroupByGuildName(name)
	if type(name) ~= "string" or name == "" or not OfOurGroup(name) then return nil end
	local short = Groups().short
	local record = short and short[ns.Fold(ns.ShortName(ns.Normal(name)))]
	if record then return record.group end
end

-- (1.6.0) The main a character's own claim names (role A), as last heard: its word alone, which links
-- nothing (Group needs its main's claim too). The Church's witness reports an alt's recruit on it, and
-- the keeper, who asks both claims, decides (ChurchCount.Pair). On Forever the guild log gives the name
-- plain: then the one claim of our family with that plain name, never one of two.
function Alts.ClaimedMain(name)
	if type(name) ~= "string" or name == "" then return nil end
	local c = ClaimOf(name)
	if not c and InFamily(name) then
		local byPlain = Groups().byPlain
		local k = byPlain and byPlain[Plain(name)]
		c = k and Claims()[k] or nil
	end
	if type(c) ~= "table" or c.role ~= "A" or type(c.links) ~= "table" or type(c.links[1]) ~= "string" or not OfOurGroup(c.name) then return nil end
	return c.links[1]
end

-- The other names of its player's confirmed group (a list, empty when none).
function Alts.Linked(name)
	local g = Alts.Group(name)
	local out = {}
	if not g then return out end
	local key = Key(name)
	for _, m in ipairs(g.members) do
		if Key(m.name) ~= key then out[#out + 1] = m.name end
	end
	return out
end

-- The name its player's characters go under together: its main's (short, as the treasury writes
-- donors), or its own.
function Alts.Person(name)
	local g = type(name) == "string" and Alts.Group(name)
	return ns.ShortName(g and g.main or name)
end

-- How many characters of the guilds `counted` ({ [guild lower case] = true }) are a player's
-- second, third... there: the army's total leaves them out.
function Alts.Duplicates(counted)
	local n = 0
	for _, g in ipairs(Groups().groups) do
		local here = 0
		for _, m in ipairs(g.members) do
			if type(m.guild) == "string" and counted[m.guild:lower()] then here = here + 1 end
		end
		if here > 1 then n = n + here - 1 end
	end
	return n
end

-- The players who linked alts, as a sample of the census (CensusStats.PeopleEstimate: a floor of a
-- team client's estimate, never a rate, the author's 2026-10-20 decision): how many confirmed groups
-- have a character in the guilds `counted` (as Duplicates), and how many of their characters are
-- there. Counts only.
function Alts.Sample(counted)
	local characters, people = 0, 0
	for _, g in ipairs(Groups().groups) do
		local here = 0
		for _, m in ipairs(g.members) do
			if type(m.guild) == "string" and counted[m.guild:lower()] then here = here + 1 end
		end
		if here > 0 then characters, people = characters + here, people + 1 end
	end
	return characters, people
end

-- 1.2: other reasons to freeze the links, as net-off does: each fn(names), given these names and
-- their groups', returns true to freeze (the Blood Arena's open debt marks, Debts.lua: a debtor
-- never sheds an alt while a linked name owes). One that fails freezes nothing.
Alts.freezers = {}

-- Is a name of these (and of their groups) off (net-off), or held by a freezer? Then the links freeze.
local function OffAmong(names)
	local M = ns.Moderation
	local seen, all = {}, {}
	local function Check(name)
		local key = Key(name)
		if seen[key] then return false end
		seen[key] = true
		all[#all + 1] = name
		return M ~= nil and M.Character ~= nil and M.Character(name) ~= nil
	end
	for _, name in ipairs(names) do
		if Check(name) then return true end
		for _, other in ipairs(Alts.Linked(name)) do
			if Check(other) then return true end
		end
	end
	for _, fn in ipairs(Alts.freezers) do
		local ok, freeze = pcall(fn, all)
		if ok and freeze == true then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- The wire
---------------------------------------------------------------------------

-- This character's claim now: its role and names, from the account's links.
function Alts.Claim()
	if not ns.me then return "-", {} end
	local key = Key(ns.me)
	local link = Account().links[key]
	if type(link) == "table" then return "A", { link.main } end
	local alts = AccountAlts(ns.me)
	if #alts > 0 then return "M", alts end
	return "-", {}
end

-- Names as they travel: short on our realm, Name-Realm otherwise; as many as fit. (1.6.0) On a Forever
-- ruleset, when they do not all fit with their sub-realms, the last ones travel plain so that all fit:
-- a 1.6.0 client finds each by that character's own claim (GroupOfMain); an older one links only the
-- names that kept their sub-realm. Eight alts on other sub-realms left two out of the claim, linked
-- nowhere but on the player's own account.
local function Wire(at, role, guild, names)
	local head = ("AL~%d~%s~%s~"):format(at, role, tostring(guild or ""):gsub("[~|%c]", ""))
	local shown, plain = {}, {}
	for i, n in ipairs(names) do
		shown[i] = ns.RealmOf(n) == ns.realm and ns.ShortName(n) or n
		plain[i] = InFamily(n) and ns.ShortName(n) or shown[i]
	end
	local parts, len = {}, #head
	for i = 1, #names do
		local rest = 0
		for j = i + 1, #names do rest = rest + #plain[j] + 1 end
		local s = shown[i]
		if len + #s + 1 + rest > 250 then s = plain[i] end
		if len + #s + 1 > 250 then break end
		parts[#parts + 1] = s
		len = len + #s + 1
	end
	return head .. table.concat(parts, ",")
end

-- Guild membership is part of a claim, so it changes the same revision as the links.
-- Observe it at login, on the guild event and just before sending; every receiver (including
-- older versions) can then reject an older claim without keeping a previous guild forever.
local function GuildChanged()
	if not ns.me then return false end
	local a, key = Account(), Key(ns.me)
	local guild = GetGuildInfo("player")
	if a.guilds[key] == guild then return false end
	a.guilds[key] = guild
	Changed()
	return true
end

-- (1.6.0) On a Forever ruleset the channel reaches another guild only through one relay, within each
-- guild's share of its trickle (Relay.lua: Afford), and never another relay's guilds: a keeper, or a
-- guildmate reading the guild log, who never heard both claims credited no linked alt's recruit to its
-- Apostle or Missionary main (ChurchCount), and the trickle passes few of a busy evening's words. So
-- there such a group's claims also go to the claimant's own guild over GUILD, with each channel claim,
-- and by whisper to every keeper this client hears online (Church.KeepersOnline): each new claim within
-- the minute's round, and each again every EVERY. Every route's sender is the server's stamp (over GUILD
-- with the reader's own sub-realm: the receiver takes his hello's, Alts.Handle).
local toldKeepers = {} -- keeper key -> { at = the claim's revision told, t = when }
local function ChurchGroup(role, names)
	local C = ns.Church
	if type(C) ~= "table" or type(C.Role) ~= "function" then return false end
	local r = C.Role(role == "A" and names[1] or ns.me)
	return r == "A" or r == "M"
end
local function TellKeepers(wire, at, now)
	local C = ns.Church
	if type(C) ~= "table" or type(C.KeepersOnline) ~= "function" then return 0 end
	local n, me = 0, Key(ns.me)
	for _, k in ipairs(C.KeepersOnline(false) or {}) do
		local name = type(k) == "table" and k.name
		local kk = type(name) == "string" and Key(name) or nil
		local told = kk and toldKeepers[kk]
		if kk and kk ~= me and (not told or told.at ~= at or now - told.t >= Alts.EVERY) then
			toldKeepers[kk] = { at = at, t = now }
			if ns.Comm.Whisper(name, wire, "alts " .. kk, false, false) ~= false then n = n + 1 end
		end
	end
	stats.keepers = stats.keepers + n
	return n
end

-- Sends this character's claim: at the login's first round, after a change, every EVERY. A
-- character never linked sends nothing; one whose links were all removed says so once.
function Alts.Send(force)
	local changed = GuildChanged()
	if not ns.me or not ns.IsMember() then return false end
	force = force or changed
	local a = Account()
	local key = Key(ns.me)
	local role, names = Alts.Claim()
	local at = tonumber(a.at) or 0
	if role == "-" and not (a.told[key] and a.told[key] < at) then return false end
	local wire = Wire(at, role, GetGuildInfo("player"), names)
	local church = Family() ~= nil and ChurchGroup(role, names)
	if church then TellKeepers(wire, at, ns.Now()) end
	if not force and ns.Now() - lastSent < Alts.EVERY then return false end
	lastSent = ns.Now()
	a.told[key] = at
	stats.sent = stats.sent + 1
	ns.Comm.Send("CHANNEL", wire, "alts")
	if church and IsInGuild() then
		stats.guild = stats.guild + 1
		ns.Comm.Send("GUILD", wire, "alts guild")
	end
	return true
end

-- A frozen claim takes names, never drops one: the old role, its links and the new ones.
local function Frozen(old, new)
	if type(old) ~= "table" or old.role == "-" then return new end
	local out = { name = new.name, role = old.role, links = {}, guild = new.guild, at = new.at, heard = new.heard }
	for _, n in ipairs(old.links) do out.links[#out.links + 1] = n end
	if new.role == old.role and old.role == "M" then
		for _, n in ipairs(new.links) do
			if not Has(out.links, n) and #out.links < Alts.MAX_ALTS then out.links[#out.links + 1] = n end
		end
	end
	return out
end

-- (1.6.0) On a Forever ruleset a claim also comes over GUILD and by whisper (Alts.Send): its sender
-- is the server's stamp there too, its own character's word. Elsewhere the channel's alone, as before.
-- Over GUILD the server stamps a guildmate with the READER's own sub-realm, never his (Comm.PeerRealm,
-- Layers.lua), so there his sub-realm is the one his hello named. Taken under the stamp, a guild copy was
-- a second claimant beside the claim's channel copy at every guildmate on another sub-realm: a phantom
-- group of the main and the alts on his sub-realm (Duplicates took one character too many from the
-- census's total for each of them), none found by a plain name (GroupByGuildName), and an overflowing
-- claim's plain names each matched two claims (GroupOfMain linked five alts of eight). A guild copy from a
-- guildmate whose hello is not heard yet (every client repeats it within ten minutes, Comm.Hello), or
-- whose hello names no sub-realm of ours, is left to the other routes and to his next copy (every EVERY).
function Alts.Handle(dist, sender, text)
	local family = Family()
	if dist ~= "CHANNEL" and not (family and (dist == "GUILD" or dist == "WHISPER")) then return end
	local at, role, guild, list = tostring(text):match("^AL~(%d+)~([MA%-])~([^~]*)~?(.*)$")
	at = tonumber(at)
	if not at then return end
	sender = ns.FullName(sender)
	if dist == "GUILD" then
		local C = ns.Comm
		local own = type(C) == "table" and type(C.PeerRealm) == "function" and C.PeerRealm(sender) or nil
		if type(own) ~= "string" or own == "" or ns.GroupOf(own) ~= family then stats.unplaced = stats.unplaced + 1 return end
		sender = ns.FullName(ns.ShortName(sender), own)
	end
	local key = Key(sender)
	-- This account's own characters: its saved links say it better.
	if AccountMain(sender) then return end
	if at > Clock() + Alts.DATE_AHEAD then stats.refused = stats.refused + 1 return end
	local realm = ns.RealmOf(sender)
	local names = {}
	for n in tostring(list or ""):gmatch("[^,]+") do
		local full = CharName(n, realm)
		if full and Key(full) ~= key and not Has(names, full) and #names < Alts.MAX_ALTS then names[#names + 1] = full end
	end
	if role == "A" and #names ~= 1 then stats.refused = stats.refused + 1 return end
	if role == "M" and #names == 0 then role = "-" end
	if role == "-" then names = {} end
	guild = ns.King and ns.King.CleanGuild and ns.King.CleanGuild(guild) or nil
	local claims = Claims()
	local old = claims[key]
	if type(old) == "table" then
		if at < old.at then stats.older = stats.older + 1 return end
		if at == old.at then
			old.heard = ns.Now()
			stats.same = stats.same + 1
			return
		end
	else
		-- Room: the oldest claim nobody's net-off holds goes.
		local n = 0
		for _ in pairs(claims) do n = n + 1 end
		if n >= Alts.MAX_CLAIMS then
			local oldest
			for k, c in pairs(claims) do
				if type(c) == "table" and (not oldest or (c.heard or 0) < (claims[oldest].heard or 0)) and not OffAmong({ c.name }) then oldest = k end
			end
			if not oldest then return end
			claims[oldest] = nil
		end
	end
	local claim = { name = sender, role = role, links = names, guild = guild, at = at, heard = ns.Now() }
	-- A name of its group, or of what it names now, is off: the links freeze (added to, never dropped).
	local all = { sender }
	for _, n in ipairs(names) do all[#all + 1] = n end
	if type(old) == "table" and OffAmong(all) then
		claim = Frozen(old, claim)
		stats.frozen = stats.frozen + 1
		ns.Log("alt links of %s frozen: a linked name is off (net-off)", sender)
	end
	claims[key] = claim
	stats.taken = stats.taken + 1
	Bump()
	ns.Fire("DATA_CHANGED")
end
ns.Comm.Handle("AL", function(...) Alts.Handle(...) end)

---------------------------------------------------------------------------
-- The player's side: offer on the main, confirm on the alt, remove
---------------------------------------------------------------------------

-- Any name of this account's group (or of `extra`) is off: nothing is added or removed.
function Alts.Frozen(extra)
	local names = { ns.me }
	for _, n in ipairs(Alts.MyGroup() or {}) do names[#names + 1] = n end
	for _, n in ipairs(extra or {}) do names[#names + 1] = n end
	return OffAmong(names)
end

-- On the main: names an alt of this account; it is linked once the player logs it and confirms.
function Alts.Add(input)
	if not ns.me then return false end
	local name = CharName(input, ns.realm)
	if not name then ns.Print(L.ALT_WHO_BAD) return false end
	local a = Account()
	local me = ns.me
	-- (1.6.0) One this account linked already, named plain from another sub-realm of the ruleset: that one.
	local linked = LinkKey(name)
	if linked then name = a.links[linked].name end
	local key = Key(name)
	if key == Key(me) or (InFamily(name) and Plain(name) == Plain(me)) then ns.Print(L.ALT_NOT_SELF) return false end
	-- An alt never starts a link: its main does.
	if type(a.links[Key(me)]) == "table" then ns.Print(L.ALT_NOT_FROM_ALT:format(ns.DisplayName(a.links[Key(me)].main))) return false end
	if type(a.links[key]) == "table" or #AccountAlts(name) > 0 then ns.Print(L.ALT_ALREADY:format(ns.DisplayName(name))) return false end
	if #AccountAlts(me) >= Alts.MAX_ALTS then ns.Print(L.ALT_FULL:format(Alts.MAX_ALTS)) return false end
	if Alts.Frozen({ name }) then ns.Print(L.ALT_FROZEN) return false end
	-- One offer a character: one made before under its plain name on another sub-realm goes.
	local old = OfferFor(name)
	if old and old ~= key then a.offers[old] = nil end
	a.offers[key] = { name = name, main = me, t = Clock(), faction = ns.faction, group = ns.GroupOf(ns.realm) }
	ns.Print(L.ALT_OFFERED:format(ns.DisplayName(name)))
	return true
end

-- On the alt: the offer its main made, answered (yes: linked; no: the offer is dropped).
function Alts.Confirm(yes)
	if not ns.me then return false end
	local a = Account()
	local key = Key(ns.me)
	local okey, offer = OfferFor(ns.me)
	if type(offer) ~= "table" then return false end
	a.offers[okey] = nil
	if not yes then
		ns.Print(L.ALT_DECLINED:format(ns.DisplayName(offer.main)))
		return false
	end
	-- One census and one treasury: the same faction, the same realm group.
	if (offer.faction or "Alliance") ~= (ns.faction or "Alliance") or (offer.group and offer.group ~= ns.GroupOf(ns.realm)) then
		ns.Print(L.ALT_OTHER_CENSUS)
		return false
	end
	if type(a.links[Key(offer.main)] ) == "table" or #AccountAlts(ns.me) > 0 then ns.Print(L.ALT_ALREADY:format(ns.DisplayName(ns.me))) return false end
	-- (1.6.0) At most MAX_ALTS: offers count no link, so a ninth one made before the eighth yes was linked
	-- here, and every other client (which takes MAX_ALTS names of a claim) left one of them out.
	local others = 0
	for _, n in ipairs(AccountAlts(offer.main)) do if Key(n) ~= key then others = others + 1 end end
	if others >= Alts.MAX_ALTS then ns.Print(L.ALT_FULL:format(Alts.MAX_ALTS)) return false end
	if Alts.Frozen({ offer.main }) then ns.Print(L.ALT_FROZEN) return false end
	a.links[key] = { name = ns.me, main = offer.main, at = Clock() }
	-- Any other offer of this character (made under its plain name on another sub-realm) goes with it.
	local plain = Plain(ns.me)
	for k, o in pairs(a.offers) do
		if type(o) == "table" and type(o.name) == "string" and Plain(o.name) == plain and InFamily(o.name) and InFamily(ns.me) then a.offers[k] = nil end
	end
	Changed()
	ns.Print(L.ALT_LINKED:format(ns.DisplayName(ns.me), ns.DisplayName(offer.main)))
	Alts.Send(true)
	return true
end

-- From any character of the account: a link taken apart (an alt from its main, or this alt from
-- its main), or an offer withdrawn.
function Alts.Remove(input)
	if not ns.me then return false end
	local name = CharName(input, ns.realm)
	if not name then ns.Print(L.ALT_WHO_BAD) return false end
	local a = Account()
	local key = Key(name)
	if type(a.offers[key]) == "table" then
		a.offers[key] = nil
		ns.Print(L.ALT_OFFER_DROPPED:format(ns.DisplayName(name)))
		return true
	end
	-- (1.6.0) On a Forever ruleset the plain name finds its character on any sub-realm of it.
	local linked = LinkKey(name)
	if linked then key = linked end
	local link = a.links[key]
	local mine = type(a.links[Key(ns.me)]) == "table" and a.links[Key(ns.me)] or nil
	-- The alt named, or the main of this alt named (this alt leaves it).
	if type(link) ~= "table" and mine and (Key(mine.main) == key
		or (InFamily(name) and InFamily(mine.main) and Plain(mine.main) == Plain(name))) then link, key = mine, Key(ns.me) end
	if type(link) ~= "table" then
		local okey, offer = OfferFor(name)
		if okey then
			a.offers[okey] = nil
			ns.Print(L.ALT_OFFER_DROPPED:format(ns.DisplayName(offer.name)))
			return true
		end
		ns.Print(L.ALT_NOT_LINKED:format(ns.DisplayName(name)))
		return false
	end
	if Alts.Frozen({ link.name, link.main }) then ns.Print(L.ALT_FROZEN) return false end
	a.links[key] = nil
	Changed()
	ns.Print(L.ALT_REMOVED:format(ns.DisplayName(link.name), ns.DisplayName(link.main)))
	Alts.Send(true)
	return true
end

-- /oly alt: this account's links and offers; add <name>, remove <name>.
function Alts.Slash(rest)
	local verb, arg = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
	verb = (verb or ""):lower()
	if verb == "add" then return Alts.Add(arg) end
	if verb == "remove" or verb == "del" or verb == "tirar" then return Alts.Remove(arg) end
	if verb == "yes" or verb == "confirm" then return Alts.Confirm(true) end
	Alts.PrintStatus()
end

function Alts.PrintStatus()
	local a = Account()
	local group = Alts.MyGroup()
	if group then
		local shown = {}
		for i = 2, #group do shown[#shown + 1] = ns.DisplayName(group[i]) end
		ns.Print(L.ALT_STATUS:format(ns.DisplayName(group[1]), table.concat(shown, ", ")))
	else
		ns.Print(L.ALT_NONE)
	end
	local waiting = {}
	for _, o in pairs(a.offers) do if type(o) == "table" then waiting[#waiting + 1] = ns.DisplayName(o.name) end end
	table.sort(waiting)
	if #waiting > 0 then ns.Print(L.ALT_WAITING:format(table.concat(waiting, ", "))) end
	if Alts.Frozen() then ns.Print(L.ALT_FROZEN) end
	print(L.HELP_ALT)
end

StaticPopupDialogs["OLYMPUS_ALT_CONFIRM"] = {
	text = L.ALT_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() ns.SafeCall("alt confirm", Alts.Confirm, true) end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then ns.SafeCall("alt confirm", Alts.Confirm, false) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- The alt's question, once a session, never in combat: its main's offer, waiting in the account.
function Alts.AskConfirm()
	if asked or not ns.me then return false end
	local _, offer = OfferFor(ns.me)
	if type(offer) ~= "table" then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	asked = true
	ns.ShowDialog("OLYMPUS_ALT_CONFIRM", ns.DisplayName(ns.me), ns.DisplayName(offer.main))
	return true
end

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------

-- Claims nobody repeated for KEEP go, never one of a group holding a name that is off.
function Alts.Prune()
	local now, changed = ns.Now(), false
	local claims = Claims()
	for key, c in pairs(claims) do
		if type(c) ~= "table" or type(c.name) ~= "string" then
			claims[key] = nil
			changed = true
		elseif now - (tonumber(c.heard) or 0) > Alts.KEEP then
			local names = { c.name }
			for _, n in ipairs(c.links or {}) do names[#names + 1] = n end
			if not OffAmong(names) then
				claims[key] = nil
				changed = true
			end
		end
	end
	if changed then Bump() end
end

function Alts.StatusLine()
	local g = Groups()
	local mine = Alts.MyGroup()
	return ("%d players linked here  |  yours: %s  |  claims taken %d, repeats %d, frozen %d, refused %d, sent %d"):format(
		#g.groups, mine and table.concat(mine, ", ") or "none", stats.taken, stats.same, stats.frozen, stats.refused, stats.sent)
end
function Alts.Stats() return stats end

ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit)
	if unit and unit ~= "player" then return end
	ns.After(2, "alt guild", function() Alts.Send(false) end)
end)

ns.On("LOGIN", function()
	-- Record the guild with a fresh revision before the login's first claim.
	ns.After(10, "alt guild", GuildChanged)
	ns.After(Alts.ASK_AFTER, "alt confirm", Alts.AskConfirm)
	ns.After(Alts.LOGIN_AFTER, "alt claim", function() Alts.Send(true) end)
	ns.Every(60, "alt links", function()
		Alts.Prune()
		Alts.AskConfirm()
		Alts.Send(false)
	end)
end)

-- Tests start from a clean state.
function Alts.Reset()
	cache, lastSent, asked = nil, -math.huge, false
	toldKeepers = {}
	for k in pairs(stats) do stats[k] = 0 end
	Bump()
end
