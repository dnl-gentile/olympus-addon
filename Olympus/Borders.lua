local ADDON, ns = ...
local L = ns.L

-- The elite borders (1.0.1, asked for on the community Discord): the game's own elite and rare
-- art, and Max's bronze frames drawn over it, around the portrait of an Olympus player on your
-- target and focus frames, and around your own portrait for your own rank, like Elite Player
-- Frame (Enhanced) but for other players too. `/oly borders on|off`, on by default.
-- 1.1.5 (the author's call): three tiers, all winged: the King gold, the High Council silver and a
-- guild master of an Olympus guild Max's bronze. The rank tiers of 1.0.1 (Lords gold, Captains
-- silver, Raiders bronze wings, Veterans bronze) are gone: new borders are to come, and one that
-- nearly everybody has is worth nothing. Any other member: the nameplate star alone, no border.
--
-- How, on Forever's unit frames (Blizzard_UnitFrame, the "Camelot" family: TargetFrameTemplate
-- and PlayerFrame): the game draws an elite or rare creature's border with BossPortraitFrameTexture,
-- a texture of the frame's TargetFrameContainer, set in TargetFrameMixin:CheckClassification
-- (GetBossPortraitFrameData gives the atlas and where it goes). Olympus leaves that texture alone:
-- it puts its own hidden textures on the same container, one per border, just above the game's
-- (same layer, one sublevel up), with the game's atlases (or Max's files, at the size and offsets
-- of the game's frames they were drawn over), sized and anchored once, out of combat. From then on
-- it only shows and hides them: Show and Hide are not protected for a texture (the client's API
-- documentation marks them protected for a frame only), so a target change in combat is fine.
-- The game's frames get no call from Olympus but those CreateTexture, and nothing written in them
-- but hooksecurefunc's hook, which keeps their CheckClassification secure.
-- After the game's CheckClassification on the target and focus frames (hooksecurefunc on the frames
-- themselves: the mixin's functions were copied into them when they were made) Olympus shows the
-- border of the unit again, so it follows every update the game makes.
--
-- The party's frames (1.1.5, the author's ask: in a group the portraits under your own had none):
-- Forever's PartyFrame (Blizzard_UnitFrame's Shared/PartyFrame.lua and Mainline/
-- PartyFrameTemplates.xml; Camelot overrides neither) takes its four PartyMemberFrameTemplate
-- buttons from a frame pool. Each has a 37 x 37 portrait 7 px from its left and 6 px from its
-- top, under its own ring art (its Texture, ARTWORK) and no container: Olympus's textures go on
-- the member frame itself, as that ring does, at ARTWORK sublevel 3 as everywhere. A border is the
-- target's art and offsets scaled by 37/58 (the target's portrait is 58 x 58, 26 px from its
-- container's right and 19 px from its top, Mainline/TargetFrame.xml) about the portrait's top
-- corner, and turned round as on your own frame (the portrait on the left): an atlas at the
-- client's own size of it (C_Texture.GetAtlasInfo) times 37/58, Max's file at its tier's size
-- times 37/58. The unit of PartyFrame.MemberFrame<i> (the key Blizzard gives the frame of
-- layoutIndex i) is party<i>. A member's border is worked out on GROUP_ROSTER_UPDATE when he is
-- new to his place (joining, leaving, places swapped: by GUID, so one who stays is not worked out
-- again), on his name or guild reaching the client, and on the census changes below; an empty
-- place is not worked out. One hook, hooksecurefunc on PartyFrame's InitializePartyMemberFrames as
-- on the target frame's CheckClassification, because no event says it: each time PartyFrame is
-- shown (the interface hidden and shown again: Alt+Z, a cinematic) it releases its four frames to
-- the pool and takes them back in no fixed order (the pool's pairs()), so a frame may then show
-- another member; after it each border goes to the frame now showing its member. A frame's
-- textures are made once, out of combat (in combat: once it ends). The raid's frames have no
-- portrait: none there.
--
-- The gamepad UI (Forever's controller mode): off there. Olympus leaves the game's frames alone with
-- the gamepad UI (0.9.8), and nothing offline can show that a hook in the target frame's update is
-- harmless to it (0.9.9: the world map looked harmless too). Logged in with the gamepad UI, Olympus
-- neither hooks nor makes textures; switched to it later, its textures hide at once and the hooks
-- (the target's and focus's, the party's) return without a call; back to mouse and keyboard, the
-- borders come back.
--
-- Cheap: a unit's border is worked out only when the target or focus changes (or who is in a
-- party member's place, GROUP_ROSTER_UPDATE), when its name or guild reaches the client
-- (UNIT_NAME_UPDATE, PLAYER_GUILD_UPDATE), or when the census report of its guild (or the High
-- Council's list, or for a councillor the council's names shown or hidden on the King's screen, or
-- whether a net-off word hides him: 1.1) changes, and only from lookups: its guild's report by
-- name, never a walk over every guild.
-- A character or a guild the moderators took off (net-off, Moderation.lua; 1.1, Konig's review)
-- gets no border and no nameplate mark: an Olympus player to nobody's eye.
--
-- The author's preview (1.0.0): his character holds no Olympus rank, so his own portrait shows
-- none of the borders he ships. `/oly borders test <tier>` (a tier's name, as /oly status prints
-- it) shows that border round his own portrait, turned round as a holder sees his own, and on his
-- target or focus frame while that is himself (never on a party frame: those show the others, his
-- party members their own borders); `/oly borders test off` ends it. His alone
-- (Workshop.Visible: his character, or his test build, as Asmon's and the Treasurer's views):
-- anyone else's command gets what /oly borders prints, and changes nothing. His screen alone:
-- nothing is sent, nothing is saved (a /reload forgets it), nobody else's border changes. It goes
-- through the same Refresh as a real border, so the same rules hold: none while the borders are
-- off or with the gamepad UI, the textures made once out of combat.
--
-- The nameplate marks (1.0.0, Nameplates.lua) come from the same facts and tiers (Borders.MarkOf),
-- and `/oly borders off` hides them with the borders. The author's preview shows its tier's mark
-- too, and has one tier of the marks alone: "member", the star (no border has it). So do the marks
-- in the game's own chat (1.1.5, Borders.ChatName below), from a sender's name.

local Borders = {}
ns.Borders = Borders

-- Who gets which border, checked from the top: the first that holds is the border (highest
-- first). The game's art is as Blizzard_UnitFrame/Camelot/TargetFrameUtils.lua
-- (GetBossPortraitFrameData) gives it for a boss, a rare and an elite creature, at the offsets the
-- game anchors each at (x, y: from the top right of the target frame's container; mirrored on your
-- own frame). Each is drawn as the game draws it: no tint, no desaturation.
-- A tier may name a file instead of an atlas: file (the texture's path), coords (the art's area
-- on it: left, right, top, bottom), width and height (its size on screen, the game's 1x size of
-- the frame it was drawn over) and fallback (that frame's atlas, drawn without colour when the
-- client can't load the file).
-- Who:
--   king     the King of our faction: his character (ns.IsKingCharacter) in his guild
--            (ns.IsKingGuild); where no character is pinned, that guild's guild master
--   council  the High Council (the signed list, ns.IsHighCouncillor), except on the King's screen
--            while he streams
--   leader   the guild master of an Olympus guild, as its census names him (Data.KnownRank, as
--            the Crown asks it: two senders naming him, one of them someone else; our own
--            guild's: the rank the server gives, or our roster's)
-- (1.0.1's Max's second option, ns.BORDERS_COUNCIL_GOLD, the High Council in the King's gold
-- wings, is gone with 1.1.5: the gold is the King's alone, on the borders, the nameplates and in
-- the game's chat, and the council's tier is the silver.)
local WINGED = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged"
local PLAIN = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold"
-- Max's bronze frames, drawn over the winged and the plain gold at twice their size: 256 x 256
-- TGAs, the art at the top left (scripts/make-borders.py makes them from media/borders/src).
local MEDIA = "Interface\\AddOns\\Olympus\\media\\borders\\"
Borders.TIERS = {
	{ name = "gold-elite", atlas = WINGED, x = 11, y = -4, king = true },
	{ name = "silver-elite", atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", x = 8, y = -7,
		council = true },
	{ name = "bronze-elite", file = MEDIA .. "bronze-winged", coords = { 0, 220 / 256, 0, 180 / 256 }, width = 110, height = 90,
		x = 11, y = -4, fallback = WINGED, leader = true },
}
-- Kept for borders to come, given to nobody (1.1.5): no texture is made for them, no unit matches
-- them and the preview leaves them out. The plain gold, the plain silver (the game's, by the name
-- Forever's client knows it: its Mainline TargetFrameUtils.lua gives it to a rare elite; the plain
-- gold's size and shape, so at its offsets) and Max's plain bronze (media/borders/bronze-plain).
Borders.RESERVED = {
	{ name = "gold", atlas = PLAIN, x = 0, y = 1 },
	{ name = "silver", atlas = "ui-hud-unitframe-target-portraiton-boss-rare-silver", x = 0, y = 1 },
	{ name = "bronze", file = MEDIA .. "bronze-plain", coords = { 0, 200 / 256, 0, 200 / 256 }, width = 100, height = 100,
		x = 0, y = 1, fallback = PLAIN },
}

-- Where they go: the frame (a global of the game's), its container, and the hook that follows the
-- game's updates. Your own portrait sits on the left, so there the art is mirrored. (The party's
-- frames come from a pool, not globals: MapParty and PartyRig below.)
local RIGS = {
	{ unit = "target", frame = "TargetFrame", container = "TargetFrameContainer", hook = "CheckClassification" },
	{ unit = "focus", frame = "FocusFrame", container = "TargetFrameContainer", hook = "CheckClassification" },
	{ unit = "player", frame = "PlayerFrame", container = "PlayerFrameContainer", mirror = true },
}
-- The party's places (see the top of the file), and where its portraits sit against the target's.
local PARTY = { "party1", "party2", "party3", "party4" }
local TARGET_PORTRAIT, TARGET_RIGHT, TARGET_TOP = 58, 26, 19 -- (from its container's top right)
local PARTY_PORTRAIT, PARTY_LEFT, PARTY_TOP = 37, 7, 6       -- (from its frame's top left)
local PARTY_SCALE = PARTY_PORTRAIT / TARGET_PORTRAIT
local TRACKED = { target = true, focus = true, player = true, party1 = true, party2 = true, party3 = true, party4 = true }

local rigs = {}  -- [unit] = { tex = { [tier name] = texture }, shown = tier name or nil }
local partyRigs = {} -- [a party member frame of the game's] = its rig, made once (rigs[party<i>]: the one showing party<i>)
local known = {} -- [unit] = { guid, tier, guild, report, rt, council }: the last worked out
local installed, waiting = false, false
local preview    -- the author's preview: a tier's name while on (this session only, never saved)
Borders.stats = { computed = 0 } -- (tests, /oly status)

-- Values the client hides from addons (secret values) count as none.
local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

-- 1.1 (Konig's review): a character the moderators took off (net-off, Moderation.lua), or one of a
-- guild they took off the network, shows as no Olympus player on this client: no border, no
-- nameplate mark (never the King: nobody takes him off). Our own portrait keeps ours.
-- look (1.1.5): the guild is one we try for him, not one the server or his own message gave
-- (Borders.MarkOfName): Moderation notes nothing from it.
local function NetOff(who, guild, look)
	local M = ns.Moderation
	if type(M) ~= "table" or type(M.Hides) ~= "function" or who == ns.me then return false end
	return M.Hides(who, guild, look) ~= nil
end

-- What decides a unit's border, or nil for anyone no border is for: not a player, of the other
-- faction (the census is per faction, and so is the King), or a value the client hides.
local function Facts(unit)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
	local faction = UnitFactionGroup(unit)
	local name, realm = UnitFullName(unit)
	local guild, rankName, rankIndex = GetGuildInfo(unit)
	if Secret(faction, name, realm, guild, rankName, rankIndex) then return nil end
	if faction ~= (ns.faction or "Alliance") then return nil end
	local who = ns.UnitFullName(unit)
	if type(who) ~= "string" or who == "" then return nil end
	local f = { guild = type(guild) == "string" and guild or nil, who = who }
	f.off = NetOff(who, f.guild)
	f.councillor = ns.IsHighCouncillor(who) == true
	f.council = f.councillor and not ns.CouncilMasked()
	if not f.guild or not ns.IsFederation(f.guild) then return f end
	f.olympus = true
	f.king = ns.IsKingGuild(f.guild) and (ns.IsKingCharacter(who) or (ns.KingCharacter() == nil and rankIndex == 0))
	local guilds = ns.rdb and ns.rdb.guilds
	local report = type(guilds) == "table" and guilds[f.guild] or nil
	f.report = report
	local mine = GetGuildInfo("player")
	if mine and f.guild == mine then
		-- Our own guild: the rank the server gives (our roster's if it gives none).
		local rank = type(rankIndex) == "number" and rankIndex or (ns.Roster and ns.Roster.RankOf(who))
		f.fromRoster = type(rankIndex) ~= "number"
		f.leader = rank == 0
	elseif type(report) == "table" then
		-- Another guild: the rank its census gives him, as the Crown's checks trust it (Data.KnownRank,
		-- not soft): the picture most senders give, and two senders naming him in it, one of them
		-- someone else. One report never makes its own sender a guild master: alone, against the
		-- guild's other senders, or once their row is old. Nor does one report of anyone else's
		-- (1.0.0, Konig's review of 1.0.0: a single character's report naming him gave a border on
		-- every screen); the Crown asks two for a guild master.
		local rank, named = ns.Data.KnownRank(who, f.guild)
		if (named or 0) < 2 then rank = nil end
		f.leader = rank == 0
	end
	return f
end

local function Match(f)
	if not f or f.off then return nil end
	for _, t in ipairs(Borders.TIERS) do
		if (t.king and f.king) or (t.council and f.council) or (t.leader and f.leader) then return t end
	end
	return nil
end

-- The border a unit gets now (a tier's name: "gold-elite", "silver-elite", "bronze-elite"; nil
-- for none), worked out afresh.
function Borders.TierOf(unit)
	local t = Match(Facts(unit))
	return t and t.name or nil
end

-- What a unit's border (or nameplate mark) was worked out from, to know when it must be worked
-- out again (Borders.Changed): its guild, that guild's census report as it stood (its time, and
-- its votes: an outvoted report keeps the row and changes the votes, which Data.KnownRank reads),
-- the High Council's list, our roster when his rank came from it (our own guild's, the server
-- giving none; Roster.lua makes a new table at each scan), and for a High Councillor whether the
-- council's names were hidden (the King's screen while he streams, ns.CouncilMasked: the eye in
-- the Realm, Asmon's view, becoming the King); and (1.1) his name, and whether a net-off word hid him.
local function Inputs(f)
	local report = f and f.report
	local row = type(report) == "table"
	local masked
	if f and f.councillor then masked = ns.CouncilMasked() == true end
	return { guild = f and f.guild, report = report, rt = row and report.t or nil, vouch = row and report.vouch or nil,
		council = ns.rdb and ns.rdb.council, roster = f and f.fromRoster and (ns.Roster and ns.Roster.byName or false) or nil,
		masked = masked, who = f and f.who, off = f and f.off }
end

-- Has anything a unit's border or mark was worked out from (Inputs) changed since? Lookups only:
-- its guild's report by name, never a walk over every guild.
function Borders.Changed(k)
	local rdb = ns.rdb
	local report = k.guild and rdb and type(rdb.guilds) == "table" and rdb.guilds[k.guild] or nil
	local row = type(report) == "table"
	return report ~= k.report or (row and report.t or nil) ~= k.rt or (row and report.vouch or nil) ~= k.vouch
		or (rdb and rdb.council) ~= k.council or (k.roster ~= nil and k.roster ~= (ns.Roster and ns.Roster.byName or false))
		or (k.masked ~= nil and k.masked ~= (ns.CouncilMasked() == true))
		or (k.who ~= nil and NetOff(k.who, k.guild) ~= k.off)
end

local function Compute(unit, guid)
	Borders.stats.computed = Borders.stats.computed + 1
	local f = Facts(unit)
	local t = Match(f)
	local k = Inputs(f)
	k.guid, k.tier = guid, t and t.name or nil
	known[unit] = k
	return k
end

-- The nameplate mark (Nameplates.lua), and the mark in the game's chat, of each border: the
-- King's the game's gold elite mark (his alone), the High Council's its silver, a guild master's
-- the bronze.
Borders.MARK_OF = { ["gold-elite"] = "gold", ["silver-elite"] = "silver", ["bronze-elite"] = "bronze" }

-- The mark a unit gets next to its name on a nameplate, from the same facts and trust rules as
-- its border: "gold" (the King), "silver" (the High Council), "bronze" (a guild master), "member"
-- (any other member of an Olympus guild of our faction: the star), nil for anyone else; and what
-- it was worked out from (Inputs).
function Borders.MarkOf(unit)
	local f = Facts(unit)
	local mark
	if f and not f.off then -- (1.1: none for net-off)
		local t = Match(f)
		mark = t and Borders.MARK_OF[t.name] or (f.olympus and "member" or nil)
	end
	return mark, Inputs(f)
end

-- 1.1.1: the mark by a name in Olympus's chat window (ChatWindow.lua), where there is a line's
-- sender and guild but no unit: MarkOf's twin, lookups only. The guild is the one his line
-- names, and nothing the server stamps (a unit's GetGuildInfo, which MarkOf reads) backs it:
-- Channels keeps an [Olympus] line from a sender it could not verify (VerifiedLevel's 1, false),
-- so any name on the channel can claim a made-up "Olympus X" guild. A mark here needs the claim
-- proven. Our own guild: his rank from our roster; not in the roster, or our guild's name spelled
-- another way (names ignore case, as Channels reads it), no mark. Another guild: a rank its census
-- gives him (the star; the bronze for its guild master when two senders name him, as Facts asks),
-- or the King, his Stewards and Hands by the names Channels verifies them by; a guildmate of ours
-- speaking for another guild, no mark; anyone else, none (a plain member of another guild is in no
-- census). Not Channels.VerifiedLevel itself: its Data.ClaimGuild records the claim, and a redraw
-- must not. The King, a High Councillor and net-off as MarkOf. Not tied to /oly borders or /oly
-- nameplates: the chat's marks have their own switch (/oly chatmarks). Since 1.1.5 the marks of the
-- game's own chat (Borders.ChatName below) ask it, and Olympus's own lines carry none. A lookup: its
-- net-off check notes no guild for him (Moderation.Hides' look), since the guild it is asked with
-- may be one we only try for him (the King's for a Hand by his name). Returns the mark ("gold",
-- "silver", "bronze", "member" or nil) and the facts (f.proven: the claim backed).
function Borders.MarkOfName(who, guild)
	if type(who) ~= "string" or who == "" then return nil end
	who = ns.FullName(who)
	guild = type(guild) == "string" and guild ~= "" and guild or nil
	local f = { guild = guild, who = who }
	f.off = NetOff(who, guild, true)
	f.councillor = ns.IsHighCouncillor(who) == true
	f.council = f.councillor and not ns.CouncilMasked()
	if f.off then return nil, f end
	if guild and ns.IsFederation(guild) then
		f.olympus = true
		local rank
		local mine = GetGuildInfo("player")
		if mine and guild == mine then
			rank = ns.Roster and ns.Roster.RankOf(who)
			f.proven = type(rank) == "number"
		elseif not (mine and guild:lower() == mine:lower()) and not (ns.Roster and ns.Roster.RankOf(who)) then
			local known, named = ns.Data.KnownRank(who, guild)
			if (named or 0) >= 2 then rank = known end
			local K = ns.King
			f.proven = known ~= nil or (ns.IsKingGuild(guild) and (ns.IsKingCharacter(who) or (type(K) == "table"
				and ((type(K.IsStewardName) == "function" and K.IsStewardName(who)) or (type(K.IsHandName) == "function" and K.IsHandName(who))))))
				and true or false
		end
		f.king = ns.IsKingGuild(guild) and (ns.IsKingCharacter(who) or (ns.KingCharacter() == nil and rank == 0))
		f.leader = rank == 0
	end
	local t = Match(f)
	return t and Borders.MARK_OF[t.name] or (f.olympus and f.proven and "member" or nil), f
end

function Borders.Enabled() return not (ns.db and ns.db.borders == false) end

-- On, with mouse and keyboard, for a member of an Olympus guild (outside one the addon offers
-- nothing but the Join Olympus screen).
local function Active()
	return Borders.Enabled() and not ns.GamepadUI() and ns.IsMember() == true
end

local function AtlasExists(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo
	if type(info) ~= "function" then return true end
	local ok, v = pcall(info, atlas)
	return ok and v ~= nil
end

-- An atlas's size as the client gives it (its AtlasInfo's width and height), or nil.
local function AtlasSize(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo
	if type(info) ~= "function" then return nil end
	local ok, v = pcall(info, atlas)
	if ok and type(v) == "table" and type(v.width) == "number" and type(v.height) == "number" then return v.width, v.height end
	return nil
end

-- A tier's art on a new texture (mirror: turned round, for your own portrait), or false when the
-- client has none of it. An atlas at its own size; a file at the tier's size, its art's area only.
-- A file SetTexture fails or says false for: the game's frame it was drawn over, without colour.
-- The game's way to turn art round is its texture coordinates the other way, right before left
-- (Blizzard_OrderHallTalents.lua, for an atlas).
-- scale (a party member's frame, PARTY_SCALE: 37/58): each at that share of that size, an atlas's
-- from the client's own size of it (none known: false, rather than the target's size there).
local function Dress(tex, t, mirror, scale)
	local left, right, top, bottom = 0, 1, 0, 1
	local ok, loaded = false, false
	if t.file then ok, loaded = pcall(tex.SetTexture, tex, t.file) end
	if ok and loaded ~= false then
		tex:SetSize(t.width * (scale or 1), t.height * (scale or 1))
		left, right, top, bottom = unpack(t.coords)
		if not mirror then tex:SetTexCoord(left, right, top, bottom) end
	else
		local atlas = t.file and t.fallback or t.atlas
		if t.file and not (atlas and AtlasExists(atlas)) then return false end
		local width, height
		if scale then
			width, height = AtlasSize(atlas)
			if not width then return false end
		end
		if t.file then ns.Log("borders: %s not loaded, the game's %s without colour instead", t.file, t.fallback) end
		tex:SetAtlas(atlas, not scale, nil, true)
		if scale then tex:SetSize(width * scale, height * scale) end
		if t.file then tex:SetDesaturated(true) end
	end
	if mirror then tex:SetTexCoord(right, left, top, bottom) end
	return true
end

-- A rig shows one border (a tier's name) or none (nil): Show and Hide alone, fine in combat.
local function Show(rig, name)
	if rig.shown == name then return end
	if rig.shown and rig.tex[rig.shown] then rig.tex[rig.shown]:Hide() end
	rig.shown = nil
	if name and rig.tex[name] then
		rig.tex[name]:Show()
		rig.shown = name
	end
end

-- A frame's textures, one per tier the client has the art of, each hidden and placed by Place.
local function MakeRig(owner, mirror, scale, Place)
	local rig = { tex = {} }
	for _, t in ipairs(Borders.TIERS) do
		-- (A missing atlas: no texture. A file's is made to try it: one the client can't
		-- load, with no atlas to fall back to, stays hidden and unused.)
		if t.file or AtlasExists(t.atlas) then
			local tex = owner:CreateTexture(nil, "ARTWORK", nil, 3)
			tex:Hide()
			if Dress(tex, t, mirror, scale) then
				Place(tex, t)
				rig.tex[t.name] = tex
			end
		end
	end
	return rig
end

-- A party member frame's textures: the target's art and offsets scaled to its portrait about the
-- portrait's top corner, turned round (from the frame's top left).
local function PartyRig(frame)
	local s = PARTY_SCALE
	return MakeRig(frame, true, s, function(tex, t)
		tex:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY_LEFT - (t.x + TARGET_RIGHT) * s, (t.y + TARGET_TOP) * s - PARTY_TOP)
	end)
end

-- Forever's PartyFrame (its member frames from a pool), or nil.
local function PartyFrameOf()
	local party = _G.PartyFrame
	if type(party) == "table" and type(party.PartyMemberFramePool) == "table" then return party end
	return nil
end

-- Which frame shows which party member now (PartyFrame.MemberFrame<i>, of layoutIndex i: party<i>),
-- a frame's textures made the first time it is seen out of combat (in combat: once it ends); a
-- frame not showing a place now shows no border. Field reads alone on the game's frames.
local function MapParty()
	local party = PartyFrameOf()
	if not party then return end
	local combat = InCombatLockdown and InCombatLockdown()
	if not combat then waiting = false end
	local mapped = {}
	for i, unit in ipairs(PARTY) do
		local frame = party["MemberFrame" .. i]
		local rig
		if type(frame) == "table" and frame.layoutIndex == i and type(frame.CreateTexture) == "function" then
			rig = partyRigs[frame]
			if not rig and combat then
				waiting = true
			elseif not rig then
				rig = PartyRig(frame)
				partyRigs[frame] = rig
			end
		end
		rigs[unit] = rig
		if rig then mapped[rig] = true end
	end
	for _, rig in pairs(partyRigs) do
		if not mapped[rig] then Show(rig, nil) end
	end
end

-- Once, with mouse and keyboard and out of combat (a texture of the game's frames may count as
-- theirs, whose points and size are not ours to set in combat): the textures, then the hooks.
-- A client without Forever's unit frames (Classic Era, Anniversary) gets none.
function Borders.Install()
	if installed then return true end
	if ns.GamepadUI() then return false end
	if InCombatLockdown and InCombatLockdown() then
		waiting = true
		return false
	end
	waiting, installed = false, true
	for _, spec in ipairs(RIGS) do
		local frame = _G[spec.frame]
		local container = type(frame) == "table" and frame[spec.container] or nil
		if type(container) == "table" and type(container.CreateTexture) == "function" then
			rigs[spec.unit] = MakeRig(container, spec.mirror, nil, function(tex, t)
				if spec.mirror then
					-- The target's portrait sits 26 px from its frame's right edge, yours 24 px from its left.
					tex:SetPoint("TOPLEFT", container, "TOPLEFT", -(t.x + 2), t.y)
				else
					tex:SetPoint("TOPRIGHT", container, "TOPRIGHT", t.x, t.y)
				end
			end)
			if spec.hook and type(frame[spec.hook]) == "function" and type(hooksecurefunc) == "function" then
				local unit, where = spec.unit, "borders " .. spec.unit
				hooksecurefunc(frame, spec.hook, function() ns.SafeCall(where, Borders.Refresh, unit) end)
			end
		end
	end
	-- The party's frames there now, and the hook that follows PartyFrame handing them out anew.
	MapParty()
	local party = PartyFrameOf()
	if party and type(party.InitializePartyMemberFrames) == "function" and type(hooksecurefunc) == "function" then
		hooksecurefunc(party, "InitializePartyMemberFrames", function() ns.SafeCall("borders party", Borders.RefreshParty) end)
	end
	ns.Log("borders: set up on %s", Borders.Frames())
	return true
end

local function HideAll()
	for _, rig in pairs(rigs) do Show(rig, nil) end -- (a party frame showing nobody is hidden already: MapParty)
end

-- The unit is us: our own frame, or the target or focus while it is us (by GUID; by UnitIsUnit
-- where a GUID is hidden).
local function IsMe(unit, guid)
	if unit == "player" then return true end
	local mine = UnitGUID and UnitGUID("player")
	if guid ~= nil and mine ~= nil and not Secret(mine) then return guid == mine end
	if type(UnitIsUnit) ~= "function" then return false end
	local ok, same = pcall(UnitIsUnit, unit, "player")
	return ok and not Secret(same) and same == true
end

-- The unit's border again: the one worked out for it while it is the same unit (fresh: work it
-- out again), none while the borders are off. On our own portrait, and on the target or focus
-- while it is us, the author's preview instead while it is on.
function Borders.Refresh(unit, fresh)
	if not Active() then
		if rigs[unit] then Show(rigs[unit], nil) end
		return
	end
	if not installed and not Borders.Install() then return end
	local rig = rigs[unit]
	if not rig then return end
	local guid = UnitGUID and UnitGUID(unit)
	if Secret(guid) then guid = nil end
	local k = known[unit]
	if fresh or not k or guid == nil or k.guid ~= guid then k = Compute(unit, guid) end
	Show(rig, preview and UnitExists(unit) and IsMe(unit, guid) and preview or k.tier)
end

-- The party's frames again: which shows whom (MapParty), and each member's border, worked out
-- afresh (fresh) or when he is new to his place (by GUID). An empty place: nothing worked out.
function Borders.RefreshParty(fresh)
	if not Active() then
		for _, rig in pairs(partyRigs) do Show(rig, nil) end
		return
	end
	if not installed and not Borders.Install() then return end
	MapParty()
	for _, unit in ipairs(PARTY) do
		if UnitExists(unit) then
			Borders.Refresh(unit, fresh)
		else
			known[unit] = nil
			if rigs[unit] then Show(rigs[unit], nil) end
		end
	end
end

function Borders.RefreshAll(fresh)
	for _, spec in ipairs(RIGS) do Borders.Refresh(spec.unit, fresh) end
	Borders.RefreshParty(fresh)
end

-- The census, the High Council's list, our roster or the council's names hidden or shown on the
-- King's screen changed: only a unit whose border was worked out from something that changed
-- since (Borders.Changed) is worked out again.
function Borders.CensusChanged()
	if not installed then return end
	for unit, k in pairs(known) do
		if Borders.Changed(k) then Borders.Refresh(unit, true) end
	end
end

function Borders.Report()
	if not Borders.Enabled() then return ns.Print(L.BORDERS_OFF) end
	ns.Print(L.BORDERS_ON)
	if ns.GamepadUI() then ns.Print(L.BORDERS_GAMEPAD) end
end

-- On or off, and the nameplate marks with them (Nameplates.lua).
function Borders.SetEnabled(on)
	ns.db.borders = on and true or false
	Borders.RefreshAll(true)
	ns.Nameplates.RefreshAll(true)
	Borders.Report()
end

---------------------------------------------------------------------------
-- The author's preview (see the top of the file)
---------------------------------------------------------------------------

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end

local function TierNamed(name)
	for _, t in ipairs(Borders.TIERS) do
		if t.name == name then return t end
	end
	return nil
end

-- "gold-elite" -> L.BORDERS_WHO_GOLD_ELITE: who holds that border, for the Workshop's lines.
local function Who(name) return L["BORDERS_WHO_" .. name:upper():gsub("%-", "_")] end

-- The author, or his test build (Dev.lua, never published): whoever sees the Workshop.
function Borders.PreviewAllowed()
	local W = ns.Workshop
	return type(W) == "table" and type(W.Visible) == "function" and W.Visible() == true
end
function Borders.Preview() return preview end

-- The marks' own preview tier (Nameplates.lua): the star of any other member. No border has it,
-- so his portrait shows none while it is on.
Borders.MEMBER = "member"

-- `/oly borders test <tier>|off` (any case; nothing: which tiers there are). False for anyone
-- else, with nothing done: the command then answers as /oly borders does. A tier shows its border
-- and its nameplate mark (Nameplates.lua); "member" the star alone.
function Borders.SetPreview(word)
	if not Borders.PreviewAllowed() then return false end
	word = type(word) == "string" and word:lower() or ""
	if word == "off" then
		preview = nil
		ns.Print(L.BORDERS_PREVIEW_OFF)
	elseif TierNamed(word) then
		preview = word
		-- (1.1: with the marks off, it says no mark shows with the border.)
		ns.Print(ns.Nameplates.Enabled() == false and L.BORDERS_PREVIEW_ON_NO_MARK:format(word) or L.BORDERS_PREVIEW_ON:format(word))
	elseif word == Borders.MEMBER then
		preview = word
		-- (With the marks off it only waits: NAMEPLATES_PREVIEW_WHEN_OFF below says so.)
		if ns.Nameplates.Enabled() ~= false then ns.Print(L.BORDERS_PREVIEW_ON_MEMBER) end
	else
		local names = {}
		for _, t in ipairs(Borders.TIERS) do names[#names + 1] = t.name end
		ns.Print(L.BORDERS_PREVIEW_HELP:format(table.concat(names, ", ")))
		return true
	end
	Borders.RefreshAll()
	ns.Nameplates.RefreshAll()
	-- Why it doesn't show yet, if it doesn't: the same rules as a real border.
	if preview then
		if not Borders.Enabled() then ns.Print(L.BORDERS_PREVIEW_WHEN_OFF)
		elseif ns.GamepadUI() then ns.Print(L.BORDERS_GAMEPAD)
		elseif ns.IsMember() ~= true then ns.Print(L.BORDERS_PREVIEW_NOT_MEMBER)
		elseif preview == Borders.MEMBER then
			-- (no border: the marks alone, and only while they are on)
			if ns.Nameplates.Enabled() == false then ns.Print(L.NAMEPLATES_PREVIEW_WHEN_OFF) end
		elseif not installed then ns.Print(L.BORDERS_PREVIEW_COMBAT) -- (only combat keeps them from being made)
		elseif not (rigs.player and rigs.player.tex[preview]) then ns.Print(L.BORDERS_PREVIEW_MISSING) end
	end
	ns.Fire("WORKSHOP_CHANGED")
	return true
end

-- The Workshop's lines for it (not in its copy for Discord): one per tier, and last the marks'
-- member star; a click shows it, a click on the one shown ends it.
function Borders.PreviewLines(lines)
	if not Borders.PreviewAllowed() then return end
	lines[#lines + 1] = { header = true, text = L.BORDERS_PREVIEW_TITLE,
		right = Grey(preview and L.BORDERS_PREVIEW_NOW:format(preview) or L.BORDERS_PREVIEW_NONE) }
	local names = {}
	for _, t in ipairs(Borders.TIERS) do names[#names + 1] = t.name end
	names[#names + 1] = Borders.MEMBER
	for _, name in ipairs(names) do
		local on = preview == name
		lines[#lines + 1] = {
			indent = 1, text = (on and Gold(name) or name) .. "  " .. Grey(Who(name)),
			right = on and Green(L.BORDERS_PREVIEW_SHOWN) or nil,
			onClick = function() Borders.SetPreview(on and "off" or name) end,
			tooltip = function(tt)
				tt:AddLine(L.BORDERS_PREVIEW_TITLE, 1, 0.82, 0)
				tt:AddLine(name == Borders.MEMBER and L.BORDERS_PREVIEW_TIP_MEMBER or L.BORDERS_PREVIEW_TIP, 1, 1, 1, true)
				-- (1.1: with the marks off, no mark shows with it.)
				if ns.Nameplates.Enabled() == false then tt:AddLine(L.NAMEPLATES_PREVIEW_WHEN_OFF, 0.6, 0.6, 0.6, true) end
			end,
		}
	end
	lines[#lines].gapAfter = true
end

-- The frames that got their textures ("target, focus, player"), for the log and /oly status.
function Borders.Frames()
	local out = {}
	for _, spec in ipairs(RIGS) do
		if rigs[spec.unit] then out[#out + 1] = spec.unit end
	end
	for _, unit in ipairs(PARTY) do
		if rigs[unit] then out[#out + 1] = unit end
	end
	return #out > 0 and table.concat(out, ", ") or "none (not Forever's unit frames)"
end

function Borders.StatusLine()
	local state = Borders.Enabled() and "on" or "off (/oly borders on)"
	if Borders.Enabled() and ns.GamepadUI() then state = "on, hidden with the gamepad UI" end
	local where
	if installed then
		local shown = {}
		for _, spec in ipairs(RIGS) do
			local rig = rigs[spec.unit]
			if rig then shown[#shown + 1] = spec.unit .. " " .. (rig.shown or "-") end
		end
		for _, unit in ipairs(PARTY) do
			local rig = rigs[unit]
			if rig then shown[#shown + 1] = unit .. " " .. (rig.shown or "-") end
		end
		where = #shown > 0 and table.concat(shown, ", ") or Borders.Frames()
	else
		where = waiting and "set up after combat" or "not set up yet"
	end
	return ("%s  |  %s  |  worked out %d times%s"):format(state, where, Borders.stats.computed,
		preview and ("  |  preview " .. preview) or "")
end

---------------------------------------------------------------------------
-- The game's own chat (1.1.5: the High Council's ask, then the author's call)
---------------------------------------------------------------------------
-- A mark before a sender's name in the game's chat, where players outside Olympus can be: the
-- channels (General, Trade, LocalDefense, LookingForGroup and any other CHAT_MSG_CHANNEL), say,
-- yell, emote, party, raid, instance and whispers both ways. Never guild or officer chat: everyone
-- there is of our guild. The mark follows the sender's border tier (Borders.MARK_OF, by
-- Borders.MarkOfName's facts and trust rules): the King the game's gold elite dragon
-- (nameplates-icon-elite-gold), a High Councillor its silver one (nameplates-icon-elite-silver)
-- then the icon he picked (ns.CouncilIcon), a guild master of an Olympus guild the bronze (the gold
-- tinted as Nameplates.BRONZE), any other member of an Olympus guild we can prove the star; nothing
-- for anyone else. 14 px, as the Chat tab showed them; an atlas the client lacks: the star.
-- (It began with the councillors' marks alone, in guild chat too, while Olympus's own lines carried
-- every mark. Olympus's own lines, Channels.FormatLine and the Chat tab, carry none since: the
-- name in its colour.)
-- No line of the game names its sender's guild, so his is a guild MarkOfName's rules can prove
-- (ChatGuilds): ours when our roster has him; the King's for the King, his Stewards and Hands by
-- their names; the one his own Olympus messages speak for (Data.ClaimedGuild: his lines on the
-- Olympus channel, his census reports, his board posts...), as the 1.1.1 Chat tab took the guild
-- his line named, and only when that guild's census names him (its guild master or an officer: a
-- plain member of another guild is in no census, so he gets no star here). Never a guild only
-- someone else's report names him in: any character can send a census report for any guild
-- named Olympus, so two of them could otherwise put the bronze on anybody's name in Trade (a
-- border or a nameplate mark needs the guild the server gives the unit). A High Councillor's
-- silver needs no guild: the signed list.
-- The game's hook for it, ChatFrameUtil.AddSenderNameFilter (Forever 1.60.1,
-- Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua): Blizzard calls it through securecallfunction
-- with the line's event, the name it decorated (class colour and all) and the line's arguments, and
-- shows what it returns inside the player link only; the link's data, the click, the right-click
-- menu, /r and the whisper window keep the real name. Nothing of Blizzard's is replaced, and a
-- client without it has no marks.
-- Off with the gamepad UI, as the borders: logged in with it, nothing is registered until a switch
-- to mouse and keyboard; switched to it later, the callback returns at once. Also none: outside an
-- Olympus guild (ns.IsMember, as the borders: a list kept from before says nothing there; asked
-- again on every marked line), a High Councillor's on the King's screen while the council's names
-- are hidden (ns.CouncilMasked: asked again on every line with a council mark, so a first login
-- whose guild was not known yet, or any other flip, never leaves one on his stream; his guild
-- master's bronze or the star there instead, if any), a character or a guild the moderators took
-- off (net-off), a secret name or sender, and `/oly chatmarks off` (ns.db.chatMarks false).
-- Blizzard runs the callback for every line on every chat window: it reads a boolean, the event
-- list and one table entry; a sender not seen yet is worked out once (ChatName: lookups only, at
-- most two guilds' census rows, never a walk over every guild), and the table is emptied every
-- CHAT_FORGET seconds and whenever the census, the council's lists, our guild or the council's
-- names hidden or shown change, so a new list or icon shows within a minute.

Borders.CHAT_EVENTS = {
	CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true,
	CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
	CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_CHANNEL = true, -- (General, Trade, LocalDefense, LookingForGroup, any other channel)
	CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true, -- (INFORM's sender is whom we wrote to)
}
local CHAT_EVENTS = Borders.CHAT_EVENTS
Borders.CHAT_FORGET = 60
Borders.CHAT_MAX = 500 -- senders kept between two emptyings (then it starts again)
local chatMarks, chatKept = {}, 0 -- sender, as the line gives him -> { text, council } or false for none
local chatOn, chatHooked, chatPreview = false, false, false -- chatPreview: the author's mark ("gold"...) or false

Borders.CHAT_STAR = "|TInterface\\AddOns\\Olympus\\media\\borders\\star:14:14|t"
local CHAT_ATLAS = { gold = "nameplates-icon-elite-gold", silver = "nameplates-icon-elite-silver", bronze = "nameplates-icon-elite-gold" }
local CHAT_BRONZE_TINT = ":0:0:158:118:86" -- (Nameplates.BRONZE x 255)
local CHAT_RANK = { gold = 4, silver = 3, bronze = 2, member = 1 }
Borders.CHAT_PREVIEWS = { gold = true, silver = true, bronze = true, member = true }

-- A mark's text before a name: "gold", "silver" (then his own icon, when `who` is given), "bronze",
-- "member"; nil else. (Workshop.lua's council icon picker shows the silver with the icon it picks.)
local function ChatText(mark, who)
	if mark == "member" then return Borders.CHAT_STAR end
	local atlas = CHAT_ATLAS[mark]
	if not atlas then return nil end
	if not AtlasExists(atlas) then return Borders.CHAT_STAR end
	local text = "|A:" .. atlas .. ":14:14" .. (mark == "bronze" and CHAT_BRONZE_TINT or "") .. "|a"
	if mark == "silver" and who then text = text .. ns.CouncilIcon(who) end
	return text
end

-- A mark as it may go before a name: |T...|t textures and |A...|a atlases and nothing else (no
-- "%": two of Blizzard's lines use the name as a gsub replacement; no bracket or link), else nil.
function Borders.ChatMarkText(mark) return ChatText(mark, nil) end

local function ChatClean(s)
	if type(s) ~= "string" or s == "" or #s > 200 then return nil end
	for _, bad in ipairs({ "%", "[", "]", "|H", "|h" }) do
		if s:find(bad, 1, true) then return nil end
	end
	if s:gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", "") ~= "" then return nil end
	return s
end

-- The guilds a sender of the game's chat may be proven in (see above): ours alone for a guildmate;
-- the King's for his Crown by name; the one his own messages claim.
local function ChatGuilds(who)
	local mine = GetGuildInfo("player")
	if Secret(mine) then mine = nil end
	if mine and ns.Roster and ns.Roster.RankOf(who) then return { mine } end
	local out = {}
	local K = ns.King
	if ns.IsKingCharacter(who) or (type(K) == "table" and ((type(K.IsStewardName) == "function" and K.IsStewardName(who))
		or (type(K.IsHandName) == "function" and K.IsHandName(who)))) then
		local king = ns.KING_GUILD[ns.faction or "Alliance"]
		if king then out[#out + 1] = ns.Data.GuildKey(king) or king end
	end
	local claimed = type(ns.Data.ClaimedGuild) == "function" and ns.Data.ClaimedGuild(who) or nil
	if claimed and claimed ~= out[1] then out[#out + 1] = claimed end
	return out
end

-- The mark before a sender's name in the game's chat, or false for none; and whether it is a High
-- Councillor's (the King's stream hides those).
function Borders.ChatName(sender)
	local who = ns.FullName(ns.Normal(sender))
	if type(who) ~= "string" or who == "" then return false end
	if chatPreview and who == ns.me then return ChatClean(ChatText(chatPreview, who)) or false, false end
	if ns.IsMember() ~= true then return false end
	local best = Borders.MarkOfName(who, nil) -- (a High Councillor's: no guild needed)
	for _, guild in ipairs(ChatGuilds(who)) do
		local mark = Borders.MarkOfName(who, guild)
		if mark and (not best or CHAT_RANK[mark] > CHAT_RANK[best]) then best = mark end
	end
	if not best then return false end
	return ChatClean(ChatText(best, who)) or false, best == "silver"
end

local function IsMine(sender) return ns.FullName(ns.Normal(sender)) == ns.me end

local function ChatMarkOf(name, sender)
	if Secret(name, sender) or type(name) ~= "string" or type(sender) ~= "string" or sender == "" then return nil end
	local e = chatMarks[sender]
	if e == nil then
		if chatKept >= Borders.CHAT_MAX then chatMarks, chatKept = {}, 0 end
		local text, council = Borders.ChatName(sender)
		e = text and { text = text, council = council } or false
		chatMarks[sender], chatKept = e, chatKept + 1
	end
	if not e then return nil end
	local text = e.text
	-- A marked line asks again what may change between two emptyings (but the author's preview on
	-- his own lines): that we are in an Olympus guild, and for a council mark whether the King's
	-- screen hides the council now (worked out again as the mask says, never kept).
	if not (chatPreview and IsMine(sender)) then
		if ns.IsMember() ~= true then return nil end
		if e.council and ns.CouncilMasked() then
			text = Borders.ChatName(sender)
			if not text then return nil end
		end
	end
	return text .. name
end

-- Blizzard's callback: the name to show, or nil for the name as it was (an error is nil too).
function Borders.ChatFilter(event, name, text, sender)
	if not chatOn or not CHAT_EVENTS[event] then return nil end
	local ok, out = pcall(ChatMarkOf, name, sender)
	if ok then return out end
	return nil
end

function Borders.ChatForget() chatMarks, chatKept = {}, 0 end

function Borders.ChatEnabled() return not (ns.db and ns.db.chatMarks == false) end

-- Whether the game's chat shows them now, and registering the callback the first time it may
-- (once a session: it is never removed, turning them off clears chatOn).
function Borders.ChatRefresh()
	Borders.ChatForget()
	local CFU = rawget(_G, "ChatFrameUtil")
	local api = type(CFU) == "table" and type(CFU.AddSenderNameFilter) == "function"
	if not chatHooked and api and Borders.ChatEnabled() and not ns.GamepadUI() then
		chatHooked = pcall(CFU.AddSenderNameFilter, Borders.ChatFilter) == true
	end
	chatOn = chatHooked and Borders.ChatEnabled() and not ns.GamepadUI()
	return chatOn
end
function Borders.ChatShown() return chatOn end

function Borders.ChatReport()
	local CFU = rawget(_G, "ChatFrameUtil")
	if not (type(CFU) == "table" and type(CFU.AddSenderNameFilter) == "function") then return ns.Print(L.CHATMARKS_NO_API) end
	ns.Print(Borders.ChatEnabled() and L.CHATMARKS_ON or L.CHATMARKS_OFF)
	if Borders.ChatEnabled() and ns.GamepadUI() then ns.Print(L.CHATMARKS_GAMEPAD) end
end

-- `/oly chatmarks on|off|test [gold|silver|bronze|member|off]` (nothing: whether they show). test:
-- the author's own lines get that mark for this session (his character holds none of them; test
-- alone: the High Council's silver, or off again); anyone else gets the report.
function Borders.ChatSlash(rest)
	rest = type(rest) == "string" and rest:lower() or ""
	local word, arg = rest:match("^%s*(%S*)%s*(%S*)")
	if word == "on" or word == "off" then
		ns.db.chatMarks = word == "on"
		Borders.ChatRefresh()
	elseif word == "test" and Borders.PreviewAllowed() then
		if arg == "off" or (arg == "" and chatPreview) then
			chatPreview = false
		elseif Borders.CHAT_PREVIEWS[arg] then
			chatPreview = arg
		elseif arg == "" then
			chatPreview = "silver"
		else
			return ns.Print(L.CHATMARKS_TEST_HELP)
		end
		Borders.ChatRefresh()
		return ns.Print(chatPreview and L.CHATMARKS_TEST_ON:format(chatPreview) or L.CHATMARKS_TEST_OFF)
	end
	Borders.ChatReport()
end

function Borders.ChatStatusLine()
	local CFU = rawget(_G, "ChatFrameUtil")
	if not (type(CFU) == "table" and type(CFU.AddSenderNameFilter) == "function") then return "none (no ChatFrameUtil.AddSenderNameFilter)" end
	local state = chatOn and "on" or (not Borders.ChatEnabled() and "off (/oly chatmarks on)" or (ns.GamepadUI() and "hidden with the gamepad UI" or "not registered yet"))
	return ("%s  |  %d senders worked out%s"):format(state, chatKept, chatPreview and ("  |  preview " .. chatPreview) or "")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.On("LOGIN", function()
	Borders.ChatRefresh()
	ns.Every(Borders.CHAT_FORGET, "chat marks", Borders.ChatForget)
end)
ns.On("COUNCIL_MASK_CHANGED", function() Borders.ChatForget() end)
-- The census, the council's lists or our guild changing: worked out again.
ns.On("DATA_CHANGED", function() Borders.ChatForget() end)
ns.On("LOGIN", function() Borders.RefreshAll(true) end)
ns.On("DATA_CHANGED", function() Borders.CensusChanged() end)
-- The King shows or hides the council's names (the eye in the Realm, ns.SetCouncilNamesShown).
ns.On("COUNCIL_MASK_CHANGED", function() Borders.CensusChanged() end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Borders.Refresh("target") end)
-- Joining, leaving, places swapped: a member new to his place worked out (the frames are the game's to update).
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() Borders.RefreshParty() end)
ns.RegisterEvent("UNIT_NAME_UPDATE", function(unit) if TRACKED[unit] then Borders.Refresh(unit, true) end end)
-- A unit's guild reaching the client (or ours changing: every border again).
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit)
	if unit == nil or unit == "player" then Borders.ChatForget() end
	if unit == nil or unit == "player" then Borders.RefreshAll(true)
	elseif TRACKED[unit] then Borders.Refresh(unit, true) end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if waiting then Borders.RefreshAll(true) end end)
-- Not on every client: registered where the game has them.
pcall(ns.RegisterEvent, "PLAYER_FOCUS_CHANGED", function() Borders.Refresh("focus") end)
-- A switch between mouse and keyboard and the gamepad UI (Blizzard_SharedXML/InputUtil.lua's):
-- to the gamepad UI, every border hides at once; either way they are looked at again just after.
pcall(ns.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function(newMode)
	local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
	if gamepad ~= nil and newMode == gamepad then HideAll() end
	ns.After(0.2, "borders style", function() Borders.RefreshAll(true) end)
	-- The game's chat marks follow at once (and are registered on the first switch to mouse and keyboard).
	ns.After(0, "chat marks style", function() Borders.ChatRefresh() end)
end)
