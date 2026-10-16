-- 1.2.1: an Apostle's own look (Borders.OwnLook, the frame picker in ProfileEdit.lua): the red
-- cross on his own portrait, on his own screen alone, offered to anyone the signed Apostles list
-- names (Church.SignedApostles over the signed titles list we hold), never sent; everyone else sees
-- his normal frame. On the test world. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local MEDIA = "Interface\\AddOns\\Olympus\\media\\honors\\"
local PLAIN_SILVER = "ui-hud-unitframe-target-portraiton-boss-rare-silver"

local function PE(w, c) return W3.M(w, c, "ProfileEdit") end

-- The game's unit frames on client c (as tests/arena/honors-net.lua stands them in) and Borders.lua
-- loaded into it: what each container shows, its metal underlay (sublevel 2).
local function Frames(w, c)
	local rec = { textures = {} }
	local function Texture(owner, sublevel)
		local t = { owner = owner, sublevel = sublevel, shown = true }
		t.SetTexture = function(self, file) self.file, self.atlas = file, nil return true end
		t.SetAtlas = function(self, a) self.atlas, self.file = a, nil end
		t.SetSize = function(self, x, y) self.size, self.w, self.h = x .. "x" .. y, x, y end
		t.SetPoint = function(self, ...) self.point = { ... } end -- (point, relativeTo, relativePoint, x, y)
		t.ClearAllPoints = function(self) self.point = nil end
		t.SetTexCoord = function(self, ...) self.coord, self.coords = table.concat({ ... }, " "), { ... } end
		t.SetDesaturated = function(self, value) self.desaturated = value end
		t.SetVertexColor = function(self, ...) self.color = table.concat({ ... }, " ") end
		t.Show = function(self) self.shown = true end
		t.Hide = function(self) self.shown = false end
		t.IsShown = function(self) return self.shown end
		rec.textures[#rec.textures + 1] = t
		return t
	end
	local function Container(label)
		return { label = label, CreateTexture = function(_, _, _, _, sublevel) return Texture(label, sublevel) end }
	end
	rec.Container = Container
	local g = c.globals
	g.TargetFrame = { TargetFrameContainer = Container("target"), CheckClassification = function() end }
	g.FocusFrame = { TargetFrameContainer = Container("focus"), CheckClassification = function() end }
	g.PlayerFrame = { PlayerFrameContainer = Container("player") }
	g.hooksecurefunc = function(t, key, post)
		if type(t) ~= "table" then return end
		local original = t[key]
		t[key] = function(...) local r = { original(...) } post(...) return unpack(r) end
	end
	g.C_Texture = { GetAtlasInfo = function() return {} end }
	g.InCombatLockdown = function() return false end
	g.UnitIsUnit = function(a, b) return a == b end
	w:As(c, function()
		rawset(c.ns, "Borders", nil)
		assert(loadfile(H.ADDON_DIR .. "Borders.lua"))("Olympus", c.ns)
	end)
	rec.B = W3.M(w, c, "Borders")
	function rec.Shown(owner)
		local found
		for _, t in ipairs(rec.textures) do
			if t.owner == owner and t.sublevel ~= 2 and t.shown then
				assert(not found, "two at once on " .. owner)
				found = t
			end
		end
		return found and (found.file or found.atlas) or nil
	end
	function rec.Underlay(owner)
		for _, t in ipairs(rec.textures) do if t.owner == owner and t.sublevel == 2 then return t end end
	end
	-- The texture shown on a container (not its underlay), itself.
	function rec.ShownTexture(owner)
		for _, t in ipairs(rec.textures) do if t.owner == owner and t.sublevel ~= 2 and t.shown then return t end end
	end
	return rec
end

-- The real Church.lua (its signed Apostles: Church.SignedApostles over the titles list held, and its
-- key) in a namespace of its own, holding a signed titles list naming `apostles` (CouncilTitles'
-- shape, as Workshop.TakeTitles keeps it once its signature checked); given to each client.
local function SignedApostles(clients, apostles)
	local titles = {}
	local cns = setmetatable({ Comm = { Handle = function() end }, On = function() end, ChatRooms = false, faction = "Alliance",
		CouncilTitles = function() return titles end }, { __index = H.ns })
	assert(loadfile(H.ADDON_DIR .. "Church.lua"))("Olympus", cns)
	local function Sign(list)
		local at = 1800000000
		local field = "Department of War^^Brannoc Weald=Marshal" .. (#list > 0 and (";^apostles^Alliance^" .. table.concat(list, ",")) or "")
		titles.at, titles.depts = at, {}
		titles.blob = ("HT1~%d~Emberfall~1~%s~%s"):format(at, field, ("ab"):rep(256))
	end
	Sign(apostles)
	for _, c in ipairs(clients) do rawset(c.ns, "Church", cns.Church) end
	return Sign
end

test("1.2.1 an Apostle's own look: a signed Apostle picks the red cross in the frame picker, labelled that only he sees it; it shows round his own portrait on the black underlay, never sent: his pick stays, and every other client shows his normal frame", function()
	local w, cast = W3.New()
	local apostle, viewer = cast.A, cast.spectator
	apostle.rank, apostle.rankName = 0, "Guild Master" -- (his normal frame: a guild master's bronze wings)
	local Sign = SignedApostles({ apostle, viewer }, { "Brin Morrow", apostle.short })
	local mine = Frames(w, apostle)
	local theirs = Frames(w, viewer)
	-- Before: his rank's frame round his own portrait.
	mine.B.Refresh("player", true)
	eq(mine.Shown("player"), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged")
	-- The picker offers it to him, labelled.
	local vm = PE(w, apostle).ViewModel()
	local entry
	for _, x in ipairs(vm.frames) do if x.key == "apostle-red" then entry = x end end
	assert(entry, "the red cross in his frame picker")
	eq(entry.own, true); eq(entry.art, "cross-red"); eq(entry.shape, "plain"); eq(entry.selected, false)
	eq(entry.label, "Red cross (only you see it)")
	local sentBefore = #w:Sent{ from = apostle }
	local pickBefore = apostle.ns.ArenaProfile.Pick().frame
	eq(PE(w, apostle).PickFrame("apostle-red"), true)
	w:Run(0)
	-- Never sent: nothing went out, his pick is what it was, his profile's word carries none.
	eq(#w:Sent{ from = apostle }, sentBefore, "nothing sent")
	eq(apostle.ns.ArenaProfile.Pick().frame, pickBefore, "his pick unchanged")
	local body = w:As(apostle, apostle.ns.ArenaProfile.Body)
	eq(body:find("apostle-red", 1, true), nil, "not in his profile's word")
	eq(apostle.db.ownLooks[apostle.name], "apostle-red", "kept on this account alone")
	-- Round his own portrait: the red cross, turned round (1.2.4, the author's call: no plain
	-- dragon under any honour, the black one under the red cross included).
	eq(mine.Shown("player"), MEDIA .. "cross-red")
	local under = mine.Underlay("player")
	eq(under.shown, false, "no underlay under the red cross")
	-- His target while it is himself: his own portrait too.
	apostle.target = apostle.name
	mine.B.Refresh("target", true)
	eq(mine.Shown("target"), MEDIA .. "cross-red")
	-- His Olympus portraits (the Arena's, as round his own); never another's.
	local rig = mine.B.Rig(mine.Container("arena"), true, true)
	local shown, kind = mine.B.ShowPreviewOn(rig, apostle.name)
	eq(shown, true); eq(kind, "honour"); eq(mine.Shown("arena"), MEDIA .. "cross-red")
	eq(mine.B.ShowPreviewOn(mine.B.Rig(mine.Container("other"), true, true), viewer.name), false)
	-- The picker: the red cross selected; what others see is still his pick.
	vm = PE(w, apostle).ViewModel()
	for _, x in ipairs(vm.frames) do eq(x.selected, x.key == "apostle-red", x.key) end
	eq(vm.preview.frame, pickBefore, "as others see him: his pick")
	-- 1.2.4, My profile: the red cross's row labelled (only he sees it) and marked as worn; the page's
	-- portrait keeps the frame others see, and the detail box names the look on his screen alone.
	local lines, _, text, _, art = w:As(apostle, apostle.ns.ProfileEdit.Page, { full = apostle.name }, {})
	local crossRow
	for _, l in ipairs(lines) do if type(l.text) == "string" and l.text:find("Red cross (only you see it)", 1, true) then crossRow = l end end
	assert(crossRow and crossRow.onClick, "the red cross's row")
	assert(crossRow.text:find("> ", 1, true), "worn: marked")
	eq(art.frame, pickBefore, "the portrait: the frame others see, never the own look")
	assert(text:find(apostle.ns.L.MYPROFILE_OWN_LOOK:format(apostle.ns.L.MYPROFILE_RED_CROSS), 1, true), text)
	eq(apostle.ns.L.MYPROFILE_OWN_LOOK:format(apostle.ns.L.MYPROFILE_RED_CROSS), "On your screen only: Red cross")
	-- Every other client: his normal frame.
	viewer.target = apostle.name
	theirs.B.Refresh("target", true)
	eq(theirs.Shown("target"), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged", "his normal frame elsewhere")
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, apostle.name, apostle.guid).frame, "rank")
	-- A forged profile word naming it shows nothing of it either.
	w:As(viewer, function()
		viewer.ns.Arena.Inject("CHANNEL", apostle.name, "AP~L1~" .. table.concat({ "-", "WA", "1", "2", "60", "0.0", "-", "0", "apostle-red", "-",
			viewer.ns.Arena.B36(w.clock) }, "~"))
	end)
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, apostle.name, apostle.guid).frame, "rank")
	theirs.B.Refresh("target", true)
	eq(theirs.Shown("target"), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged")
	-- Another frame picked ends it.
	eq(PE(w, apostle).PickFrame("rank"), true)
	eq(apostle.db.ownLooks, nil)
	eq(mine.Shown("player"), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged")
	-- Taken again, then the signed list leaves him out: it shows no more, and the picker drops it.
	eq(PE(w, apostle).PickFrame("apostle-red"), true)
	eq(mine.Shown("player"), MEDIA .. "cross-red")
	Sign({ "Brin Morrow" })
	mine.B.Refresh("player", true)
	eq(mine.Shown("player"), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged", "off the list: his normal frame")
	for _, x in ipairs(PE(w, apostle).ViewModel().frames) do assert(x.key ~= "apostle-red", "offered no more") end
	w:Run(3600)
	for _, x in ipairs(w:Sent{}) do eq(x.msg:find("apostle-red", 1, true), nil, "no message ever names it: " .. x.msg:sub(1, 2)) end
	W3.NoErrors(w)
end)

test("1.2.1 an Apostle's own look: never offered to anyone the signed Apostles list leaves out, and refused to them (nothing saved)", function()
	local w, cast = W3.New()
	local other = cast.spectator
	SignedApostles({ other }, { "Brin Morrow" })
	local r = Frames(w, other)
	for _, x in ipairs(PE(w, other).ViewModel().frames) do assert(x.key ~= "apostle-red", "not offered") end
	local ok, why = r.B.SetOwnLook("apostle-red")
	eq(ok, false); eq(why, "apostle")
	eq(PE(w, other).PickFrame("apostle-red"), false)
	eq(other.db.ownLooks, nil, "nothing saved")
	eq(r.B.OwnLook(), nil)
	-- (No signed list held at all: none either.)
	SignedApostles({ other }, {})
	eq(r.B.SetOwnLook("apostle-red"), false)
	W3.NoErrors(w)
end)

-- 1.2.4 began by making the Apostle crosses larger. The complete honours normalization now gives
-- every plain family its own measured box: the cross is 110 and the crook is 108. Both remain
-- aligned about the portrait's centre on the player frame, the target while it is the player and
-- Olympus portraits; every visible cross pixel remains within the reach the screens keep clear
-- of text (Borders.PortraitReach).
-- A TGA's alpha (32-bit, uncompressed, as scripts/make-honors.py ships them): width, height and
-- alpha(x, y), from the canvas's top left.
local function Alpha(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	local w, h = s:byte(13) + 256 * s:byte(14), s:byte(15) + 256 * s:byte(16)
	assert(s:byte(3) == 2 and s:byte(17) == 32, path .. ": a 32-bit uncompressed TGA")
	local fromTop = s:byte(18) % 64 >= 32 -- (descriptor bit 5: the first row is the top one)
	local base = 18 + s:byte(1)
	return w, h, function(x, y)
		local row = fromTop and y or h - 1 - y
		return s:byte(base + (row * w + x) * 4 + 4)
	end
end
-- A texture's box in its container, y up: from the container's TOPLEFT for a TOPLEFT point, from
-- its TOPRIGHT for a TOPRIGHT one.
local function Box(t)
	local point, x, y = t.point[1], t.point[4], t.point[5]
	assert(t.point[3] == point, "anchored to the same point of its container")
	return point == "TOPLEFT" and x or x - t.w, y, t.w, t.h, t.coords
end
-- The canvas point (pixels of its 256, from its top left) at container point (px, py), and the
-- container point of canvas point (ax, ay).
local function ArtAt(t, px, py)
	local left, top, w, h, c = Box(t)
	local fx, fy = (px - left) / w, (top - py) / h
	return (c[1] + fx * (c[2] - c[1])) * 256, (c[3] + fy * (c[4] - c[3])) * 256
end
local function At(t, ax, ay)
	local left, top, w, h, c = Box(t)
	local fx, fy = (ax / 256 - c[1]) / (c[2] - c[1]), (ay / 256 - c[3]) / (c[4] - c[3])
	return left + fx * w, top - fy * h
end
local function Near(a, b, within, why) assert(math.abs(a - b) <= within, ("%s: %.3f, not %.3f"):format(why, a, b)) end

test("1.2.4 normalized cross: 110 across beside the crook's normalized 108, aligned about the portrait's centre on his unit frame, target and Olympus portraits; the Apostles' crosses too; its art within the portraits' reach", function()
	local w, cast = W3.New()
	local apostle = cast.A
	SignedApostles({ apostle }, { apostle.short })
	local mine = Frames(w, apostle)
	local B = mine.B
	eq(PE(w, apostle).PickFrame("apostle-red"), true)
	w:Run(0)
	-- The portraits' centres: your own (and an Olympus portrait, a copy of yours: Borders.PORTRAIT),
	-- 60 across at 24, -19 from its container's top left; the target's, 58 across, 26 from its
	-- container's right and 19 from its top (Forever's Mainline/TargetFrame.xml).
	local P = B.PORTRAIT
	local ownX, ownY = P.x + P.size / 2, P.y - P.size / 2
	local targetX, targetY = -26 - 29, -19 - 29
	-- Another normalized plain family on the same rigs: the missionaries' crook, 108 across.
	local plainOwn, plainTarget = B.Rig(mine.Container("plain-own"), true, true), B.Rig(mine.Container("plain-target"), false)
	eq(B.ShowHonour(plainOwn, "missionary-1"), true); eq(B.ShowHonour(plainTarget, "missionary-1"), true)
	local crookOwn, crookTarget = mine.ShownTexture("plain-own"), mine.ShownTexture("plain-target")
	eq(crookOwn.file, MEDIA .. "crook-gold"); eq(crookOwn.size, "108x108"); eq(crookTarget.size, "108x108")
	local function Centred(t, plain, px, py, why)
		local ax, ay = ArtAt(t, px, py)
		local bx, by = ArtAt(plain, px, py)
		-- (within 0.3 of the canvas's pixels: 0.15 of a unit, two of them a unit)
		Near(ax, bx, 0.3, why .. ": the art across at the portrait's centre")
		Near(ay, by, 0.3, why .. ": the art down at the portrait's centre")
	end
	-- His unit frame: the red cross, turned round and centred by the same family rule as the crook.
	B.Refresh("player", true)
	local own = mine.ShownTexture("player")
	eq(own.file, MEDIA .. "cross-red")
	eq(own.size, "110x110", "the red cross 110 across")
	Near(own.w / crookOwn.w, 110 / 108, 1e-9, "the two normalized family boxes")
	eq(own.coord, "0.78125 0 0 0.78125", "the plain box, turned round")
	eq(own.point[1], "TOPLEFT"); Near(own.point[4], -7, 1e-9, "across"); Near(own.point[5], 6, 1e-9, "up")
	Centred(own, crookOwn, ownX, ownY, "his own portrait")
	eq(mine.Underlay("player").shown, false, "no underlay under it")
	-- His target while it is himself: from the target's top right, not turned round.
	apostle.target = apostle.name
	B.Refresh("target", true)
	local target = mine.ShownTexture("target")
	eq(target.file, MEDIA .. "cross-red"); eq(target.size, "110x110")
	eq(target.coord, "0 0.78125 0 0.78125")
	eq(target.point[1], "TOPRIGHT"); Near(target.point[4], 5, 1e-9, "across"); Near(target.point[5], 6, 1e-9, "up")
	Centred(target, crookTarget, targetX, targetY, "his target")
	-- His Olympus portraits: as round his own.
	local arena = B.Rig(mine.Container("arena"), true, true)
	local shown, kind = B.ShowPreviewOn(arena, apostle.name)
	eq(shown, true); eq(kind, "honour")
	local onArena = mine.ShownTexture("arena")
	eq(onArena.file, MEDIA .. "cross-red"); eq(onArena.size, "110x110")
	Centred(onArena, crookOwn, ownX, ownY, "his Olympus portrait")
	-- The same rig shows the crook again at its own normalized size (one texture per family).
	eq(B.ShowHonour(arena, "missionary-1"), true)
	eq(mine.ShownTexture("arena").size, "108x108", "the normalized crook")
	-- Each cross, the red and the top 3 Apostles', on an Olympus portrait: 110 across, and every
	-- visible pixel of its art (over 8 of 255 opaque) within Borders.PortraitReach past the
	-- portrait's square.
	local reach = B.PortraitReach()
	for _, key in ipairs({ "apostle-red", "apostle-1", "apostle-2", "apostle-3" }) do
		local rig = B.Rig(mine.Container(key), true, true)
		eq(B.ShowHonour(rig, key), true, key)
		local t = mine.ShownTexture(key)
		local art = apostle.ns.Honors.ArtOf(key)
		eq(t.file, MEDIA .. art, key); eq(t.size, "110x110", key)
		local cw, ch, A = Alpha(H.ADDON_DIR .. "media/honors/" .. art .. ".tga")
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for y = 0, ch - 1 do
			for x = 0, cw - 1 do
				if A(x, y) > 8 then
					for _, corner in ipairs({ { x, y }, { x + 1, y + 1 } }) do
						local px, py = At(t, corner[1], corner[2])
						minX, maxX = math.min(minX, px), math.max(maxX, px)
						minY, maxY = math.min(minY, py), math.max(maxY, py)
					end
				end
			end
		end
		local past = { left = P.x - minX, right = maxX - (P.x + P.size), top = maxY - P.y, bottom = (P.y - P.size) - minY }
		for side, v in pairs(past) do
			assert(v <= reach[side], ("%s: its art %.1f past the portrait's %s, the reach %d"):format(key, v, side, reach[side]))
		end
		-- (and bigger than it was: its top more than 17 past the square, the plain box's 14.5 to 15)
		assert(past.top > 17, key .. ": its top " .. past.top)
	end
	W3.NoErrors(w)
end)
