local ns, test, eq, WithBorders, BorderUnit, king = ...
test("office badges: Legates and correspondents lose the bronze role frame, keep distinct signed badges, and never replace earned or guild-master frames", function()
	WithBorders(function(w)
		local roles = { ["Legate-Realm"] = { "centurion" }, ["Correspondent-Realm"] = { "correspondent", "Department of War" } }
		w.ns.Nominees = { RoleOf = function(name, guild) if guild == "Olympus II" and roles[name] then return unpack(roles[name]) end end }
		w.ns.Roster = { RankOf = function(name) if roles[name] then return 3 end end }
		w.internal("LOGIN")
		w.target(BorderUnit("Legate", "Olympus II", "Member", 3))
		eq(w.B.TierOf("target"), nil); eq(w.shown("target"), nil, "the old bronze role frame is gone")
		eq(w.B.TierOfName("Legate-Realm", "Olympus II"), nil, "Olympus portraits use the same frame rule")
		eq(w.B.MarkOf("target"), "role-legate"); eq(w.B.MarkOfName("Legate-Realm", "Olympus II"), "role-legate")
		eq(assert(w.roleBadge("target")).file, "Interface\\AddOns\\Olympus\\media\\pauldrons\\legate")
		eq(w.roleBadge("target").size, "36 36")
		w.target(BorderUnit("Correspondent", "Olympus II", "Member", 3))
		eq(w.B.TierOf("target"), nil); eq(w.shown("target"), nil, "a correspondent also has no bronze role frame")
		eq(w.B.MarkOf("target"), "role-department-of-war")
		eq(assert(w.roleBadge("target")).file, "Interface\\AddOns\\Olympus\\media\\pauldrons\\department-of-war")
		w.target(BorderUnit("Guildmaster", "Olympus II", "Master", 0))
		eq(w.B.TierOf("target"), "bronze-elite", "guild-master wings unchanged")
		eq(w.roleBadge("target"), nil)
		w.ns.HonorsNet = { Verified = function(name) if name == "Legate-Realm" then return { frame = "retained-honour", metal = "bronze" } end end,
			FrameTexture = function() return "Interface\\AddOns\\Olympus\\media\\borders\\bronze-plain", "plain" end }
		w.target(BorderUnit("Legate", "Olympus II", "Member", 3))
		eq(w.B.TierOf("target"), nil)
		eq(w.shownTexture("target").file, "Interface\\AddOns\\Olympus\\media\\borders\\bronze-plain", "a verified earned frame is not removed with the role frame")
		eq(assert(w.roleBadge("target")).file, "Interface\\AddOns\\Olympus\\media\\pauldrons\\legate", "the office badge remains separate from the honour")
	end)
end)

test("office badges: a missing badge invents no fallback frame, and signed High Council department badges do not replace silver", function()
	WithBorders(function(w)
		w.ns.Nominees = { RoleOf = function(name)
			if name == "Legate-Realm" then return "centurion" end
			if name == "Correspondent-Realm" then return "correspondent", "Federal Treasury" end
		end }
		w.ns.CouncilTitle = function(name)
			if name == "Sage Owl-Realm" then return { dept = "Council of Justice" } end
		end
		w.noFile["Interface\\AddOns\\Olympus\\media\\pauldrons\\legate"] = true
		w.internal("LOGIN")
		w.target(BorderUnit("Legate", "Olympus II", "Member", 3)); eq(w.shown("target"), nil); eq(w.roleBadge("target"), nil)
		w.target(BorderUnit("Correspondent", "Olympus II", "Member", 3)); eq(w.shown("target"), nil)
		eq(assert(w.roleBadge("target")).file, "Interface\\AddOns\\Olympus\\media\\pauldrons\\federal-treasury")
		w.target(BorderUnit("Sage Owl", "Olympus II", "Member", 3)); eq(w.shown("target"), "silver-elite")
		eq(assert(w.roleBadge("target")).file, "Interface\\AddOns\\Olympus\\media\\pauldrons\\council-of-justice")
		w.style = 1; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0); eq(w.shown("target"), nil)
		w.style = 0; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
		w.target(BorderUnit("Correspondent", "Olympus II", "Member", 3)); eq(w.shown("target"), nil); assert(w.roleBadge("target"))
	end)
end)

test("office badge assets: the complete approved yellow-on-black family is square, RGBA and consistently authored", function()
	local root = debug.getinfo(1, "S").source:match("^@(.*)tests[/\\]treasurer%-dragon%.lua$") or "./"
	for _, name in ipairs({ "olympus", "legate", "federal-treasury", "department-of-war", "council-of-justice",
		"association-of-artisanry", "department-of-heraldry", "missionary-church-of-olympus" }) do
		local f = assert(io.open(root .. "Olympus/media/pauldrons/" .. name .. ".tga", "rb"), name)
		local s = f:read("*a"); f:close()
		eq(s:byte(13) + 256 * s:byte(14), 256, name .. " width")
		eq(s:byte(15) + 256 * s:byte(16), 256, name .. " height")
		eq(s:byte(17), 32, name .. " RGBA")
		eq(#s, 18 + 256 * 256 * 4, name .. " uncompressed pixels")
		local red, blue = 0, 0
		for i = 19, #s, 4 do
			blue = blue + s:byte(i)
			red = red + s:byte(i + 2)
		end
		assert(red > blue * 2.5, name .. ": the approved warm yellow-on-black art, not the old blue-backed asset")
	end
end)

test("honour frames: every plain family uses its normalized visible size without moving the portrait centre", function()
	WithBorders(function(w)
		local current
		local sizes = {
			boar = 91, charm = 117, comet = 92, cornucopia = 96, crook = 108, cross = 110,
			druid = 102, hunter = 94, kodo = 92, koi = 94, lion = 103, mage = 95,
			mechanostrider = 93, nightsaber = 98, ["orc-wolf"] = 96, owlcat = 101,
			paladin = 96, priest = 96, ram = 95, raptor = 99, raven = 105, rogue = 97,
			shaman = 95, ["skeletal-horse"] = 92, warlock = 93,
		}
		w.ns.HonorsNet = {
			Verified = function() return { frame = current, metal = "bronze" } end,
			FrameTexture = function(key) return "Interface\\AddOns\\Olympus\\media\\honors\\" .. key .. "-bronze", "plain" end,
		}
		w.internal("LOGIN")
		for family, size in pairs(sizes) do
			current = family
			w.target(BorderUnit("Honor " .. family, "Olympus II", "Member", 3))
			local tex = assert(w.shownTexture("target"), family)
			eq(tex.size, size .. " " .. size, family .. " normalized box")
			eq(tex.at.x - size / 2, -50, family .. " horizontal centre")
			eq(tex.at.y - size / 2, -49, family .. " vertical centre")
		end
	end)
end)

test("Queen dragon: the exact signed Queen gets Kaise's supplied portrait overlay on unit, party and Olympus portraits; the King still takes precedence", function()
	WithBorders(function(w)
		local queen = BorderUnit("Kaise Kaise", "HOLYPMUS", "Queen", 0)
		w.ns.IsQueenCharacter = function(name) return name == "Kaise Kaise-Realm" end
		w.party()
		w.units.party1 = queen
		w.internal("LOGIN")
		w.target(queen)
		eq(w.B.TierOf("target"), "queen-dragon")
		eq(w.B.TierOfName("Kaise Kaise-Realm", nil), "queen-dragon", "the signed identity needs no caller-supplied guild")
		eq(w.B.TierOfName("Kaise Kaise-Elsewhere", "HOLYPMUS"), nil, "a namesake on another realm group")
		local texture = assert(w.shownTextureOn("TargetFrame.TargetFrameContainer"))
		eq(texture.file, "Interface\\AddOns\\Olympus\\media\\borders\\queen-dragon")
		eq(texture.size, "175 166.25")
		eq(w.shown("party1"), "queen-dragon", "the same authored dragon round her party portrait")
		w.ns.IsQueenCharacter = function() return true end
		w.target(king)
		eq(w.B.TierOf("target"), "gold-elite", "the King's gold remains the highest portrait tier")
	end)
end)

test("Queen dragon fallback: a missing file retains the native atlas placement rather than the enlarged artwork offsets", function()
	WithBorders(function(w)
		w.ns.IsQueenCharacter = function(name) return name == "Kaise Kaise-Realm" end
		w.noFile["Interface\\AddOns\\Olympus\\media\\borders\\queen-dragon"] = true
		w.party(); w.units.party1 = BorderUnit("Kaise Kaise", "HOLYPMUS", "Queen", 0)
		w.internal("LOGIN"); w.target(w.units.party1)
		local target = assert(w.shownTexture("target"))
		eq(target.atlas, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold")
		eq(target.at.x, 0); eq(target.at.y, 1)
		eq(target.coord, nil, "native atlas coordinates stay intact"); eq(target.useSize, true)
		local party = assert(w.shownTexture("party1"))
		local native
		for _, tex in ipairs(w.textures) do
			if tex.owner == party.owner and tex.atlas == "ui-hud-unitframe-target-portraiton-boss-rare-silver" then native = tex end
		end
		assert(native, "native plain frame on the same party portrait")
		eq(party.at.x, native.at.x); eq(party.at.y, native.at.y)
	end)
end)

test("Treasurer dragon: verified primary pin owns one supplied portrait overlay, never the mail alt or namesake", function()
	local saved = { ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM }
	local primary, mail = "Test Treasurer-Realm", "Test Mail-Realm"
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = "Test Treasurer", { "Test Treasurer", "Test Mail" }, "Realm"
	local ok, err = pcall(function()
		WithBorders(function(w)
			w.internal("LOGIN")
			w.target(BorderUnit("Test Treasurer", "Olympus II", "Member", 3))
			eq(w.B.TierOf("target"), "treasurer-dragon")
			eq(w.B.TierOfName(primary, nil), "treasurer-dragon", "no caller guild label needed")
			local texture = assert(w.shownTextureOn("TargetFrame.TargetFrameContainer"))
			eq(texture.file, "Interface\\AddOns\\Olympus\\media\\borders\\treasurer-dragon")
			eq(texture.size, "100 95")
			eq(w.B.TierOfName(mail, "Olympus II"), nil)
			eq(w.B.TierOfName("Test Treasurer-Elsewhere", "Olympus II"), nil)
			local computed = w.computed()
			w.B.CensusChanged()
			eq(w.computed(), computed, "unchanged primary pin keeps the cached border")
			ns.TREASURER, ns.TREASURER_CHARACTERS = "Replacement", { "Replacement", "Test Mail" }
			w.B.CensusChanged()
			eq(w.shown("target"), nil, "pin removal invalidates the existing target cache")
			ns.TREASURER, ns.TREASURER_CHARACTERS = "Test Treasurer", { "Test Treasurer", "Test Mail" }
			w.B.CensusChanged()
			eq(w.shown("target"), "treasurer-dragon", "pin restoration refreshes that same target")
			w.target(king)
			ns.TREASURER, ns.TREASURER_CHARACTERS = king.name, { king.name }
			eq(w.B.TierOf("target"), "gold-elite")
		end)
	end)
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = unpack(saved, 1, 3)
	if not ok then error(err, 0) end
end)

-- 1.2.1 (the owner's report: the Treasurer's dragon sat slightly off round a party member's
-- portrait). Each border Olympus draws from a file of its own (the dragon, Max's bronze wings and
-- plain bronze) is measured on the party member frame as placed: the inner edge of its ring is
-- read from the file's alpha (rays from the portrait's centre, a circle fitted to the edge, the
-- parts that are no circle, the dragon's claws and the plain frame's open side, left out), and its
-- centre must fall on the portrait's (the template's 37 x 37 at 7, -6) within a pixel. The game's
-- own atlases are drawn at the game's offsets, so they are right by construction and not read here.
local ROOT = debug.getinfo(1, "S").source:match("^@(.*)tests[/\\]treasurer%-dragon%.lua$") or "./"
local function Alpha(file)
	local f = assert(io.open(ROOT .. "Olympus/media/borders/" .. file:match("([^\\]+)$") .. ".tga", "rb"))
	local s = f:read("*a")
	f:close()
	local w, h = s:byte(13) + 256 * s:byte(14), s:byte(15) + 256 * s:byte(16)
	local top = math.floor(s:byte(18) / 32) % 2 == 1
	return function(x, y) -- (x, y from the art's top left; nil outside it)
		if x < 0 or y < 0 or x >= w or y >= h then return nil end
		local row = top and y or (h - 1 - y)
		return s:byte(18 + (row * w + x) * 4 + 4)
	end
end
-- The circle through points (least squares), as centre x, y and radius.
local function Circle(pts)
	local n, sx, sy, sxx, syy, sxy, b1, b2, b3 = #pts, 0, 0, 0, 0, 0, 0, 0, 0
	for _, p in ipairs(pts) do
		local x, y = p[1], p[2]
		local q = x * x + y * y
		sx, sy, sxx, syy, sxy = sx + x, sy + y, sxx + x * x, syy + y * y, sxy + x * y
		b1, b2, b3 = b1 - x * q, b2 - y * q, b3 - q
	end
	local m = { { sxx, sxy, sx, b1 }, { sxy, syy, sy, b2 }, { sx, sy, n, b3 } }
	for i = 1, 3 do
		local piv = i
		for r = i + 1, 3 do if math.abs(m[r][i]) > math.abs(m[piv][i]) then piv = r end end
		m[i], m[piv] = m[piv], m[i]
		for r = 1, 3 do
			if r ~= i then
				local f = m[r][i] / m[i][i]
				for c = 1, 4 do m[r][c] = m[r][c] - f * m[i][c] end
			end
		end
	end
	local d, e, f = m[1][4] / m[1][1], m[2][4] / m[2][2], m[3][4] / m[3][3]
	local cx, cy = -d / 2, -e / 2
	return cx, cy, math.sqrt(cx * cx + cy * cy - f)
end
-- The centre of the inner edge of the art's ring, in the art's pixels, from a point inside it.
local function RingCentre(alpha, x0, y0)
	local pts = {}
	for deg = 0, 358, 2 do
		local t, r = math.rad(deg), 5
		while r < 75 do
			local a = alpha(math.floor(x0 + r * math.cos(t) + 0.5), math.floor(y0 + r * math.sin(t) + 0.5))
			if a == nil or a >= 128 then break end
			r = r + 0.25
		end
		if r < 75 then pts[#pts + 1] = { x0 + r * math.cos(t), y0 + r * math.sin(t) } end
	end
	local cx, cy, cr
	for _ = 1, 8 do
		cx, cy, cr = Circle(pts)
		local keep = {}
		for _, p in ipairs(pts) do
			if math.abs(math.sqrt((p[1] - cx) ^ 2 + (p[2] - cy) ^ 2) - cr) < 2.5 then keep[#keep + 1] = p end
		end
		if #keep == #pts then break end
		pts = keep
	end
	assert(#pts >= 40, "enough of the ring's edge: " .. #pts)
	return cx, cy, cr
end
-- The same, from where it finds the centre again until it stops moving: a ray's edge depends on
-- where the rays start (8 file pixels left or right of the centre move one reading 4 px), so the
-- start is the portrait's centre only for the first reading.
local function SettledRingCentre(alpha, x0, y0)
	local cx, cy, cr = RingCentre(alpha, x0, y0)
	for _ = 1, 20 do
		local nx, ny, nr = RingCentre(alpha, cx, cy)
		local moved = math.abs(nx - cx) + math.abs(ny - cy)
		cx, cy, cr = nx, ny, nr
		if moved < 0.01 then return cx, cy, cr end
	end
	return cx, cy, cr
end

test("Queen dragon geometry: the actual alpha opening fits native and party portraits instead of shrinking inside them", function()
	WithBorders(function(w)
		w.party(); w.internal("LOGIN")
		local own = w.B.Rig(w.container("QueenOwn"), true, true)
		w.B.ShowTier(own, "queen-dragon")
		-- Forever 70790 Mainline TargetFrame.xml: 58 at -26,-19 from TOPRIGHT;
		-- PlayerFrame.xml:27-29: 60 at 24,-19; party: 37 at 7,-6.
		local centres = {
			["TargetFrame.TargetFrameContainer"] = { -55, 48, 58 },
			["FocusFrame.TargetFrameContainer"] = { -55, 48, 58 },
			["PlayerFrame.PlayerFrameContainer"] = { 54, 49, 60 },
			["QueenOwn"] = { 54, 49, 60 },
			["PartyMember#1"] = { 25.5, 24.5, 37 },
		}
		local measured = 0
		for _, tex in ipairs(w.textures) do
			local want = centres[tex.owner]
			if want and tex.file and tex.file:match("queen%-dragon$") then
				local l, r, t, b = tex.coord:match("^(%S+) (%S+) (%S+) (%S+)$")
				l, r, t, b = tonumber(l), tonumber(r), tonumber(t), tonumber(b)
				local sx, sy = tex.dims[1] / (math.abs(r - l) * 256), tex.dims[2] / ((b - t) * 256)
				local cx, cy, radius = SettledRingCentre(Alpha(tex.file), 90, 96)
				local x = tex.at.x + (tex.at.p == "TOPRIGHT" and -tex.dims[1] or 0)
				local gx = x + (l > r and l * 256 - cx or cx - l * 256) * sx
				local gy = -tex.at.y + (cy - t * 256) * sy
				assert(math.abs(radius * 2 * sx - want[3]) < 3,
					("%s: Queen opening %.2f px must fit its %d px portrait"):format(tex.owner, radius * 2 * sx, want[3]))
				assert(math.abs(sx - sy) < 0.000001, "the supplied art keeps its proportions")
				assert(math.abs(gx - want[1]) < 1 and math.abs(gy - want[2]) < 1,
					("%s: Queen centre is displaced %.2f, %.2f"):format(tex.owner, gx - want[1], gy - want[2]))
				measured = measured + 1
			end
		end
		eq(measured, 5, "target, focus, own native, own Olympus and party all measured")
	end)
end)

test("1.2.1 party borders: every border drawn from Olympus's own file (the Queen's and Treasurer's dragons, the bronze wings, the plain bronze) has its ring round the party member's portrait, within a pixel of its centre", function()
	local saved = { ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM }
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = "Test Treasurer", { "Test Treasurer", "Test Mail" }, "Realm"
	local ok, err = pcall(function()
		WithBorders(function(w)
			w.party()
			w.units.party1 = BorderUnit("Test Treasurer", "Olympus II", "Member", 3)
			w.internal("LOGIN")
			eq(w.shown("party1"), "treasurer-dragon", "the Treasurer's dragon round his party portrait")
			local portrait = w.partyRegions.Portrait
			local px, py = portrait.x + portrait.width / 2, -portrait.y + portrait.height / 2 -- (its centre, down from the frame's top)
			local measured = {}
			for _, tex in ipairs(w.textures) do
				if tex.owner == "PartyMember#1" and tex.file then
					local name = w.tierOf(tex)
					local l, r, t, b = tex.coord:match("^(%S+) (%S+) (%S+) (%S+)$")
					l, r, t, b = tonumber(l), tonumber(r), tonumber(t), tonumber(b)
					assert(l > r, name .. ": turned round (the portrait on the left)")
					-- The art's pixels across and down (its area on the 256 file), and the frame's pixels a file pixel.
					local cw, ch = l * 256, b * 256
					local sx, sy = tex.dims[1] / cw, tex.dims[2] / ch
					local x0, y0 = tex.at.x, -tex.at.y -- (its top left, down from the frame's top)
					-- The portrait's centre in the art's pixels (turned round), then the ring's.
					local fx, fy = cw - (px - x0) / sx, (py - y0) / sy
					local cx, cy = SettledRingCentre(Alpha(tex.file), fx, fy)
					local gx, gy = x0 + (cw - cx) * sx, y0 + cy * sy
					measured[name] = ("%.2f %.2f"):format(gx - px, gy - py)
					assert(math.abs(gx - px) < 1 and math.abs(gy - py) < 1,
						("%s: its ring's centre %.2f px across and %.2f px down from the portrait's"):format(name, gx - px, gy - py))
				end
			end
			for _, name in ipairs({ "queen-dragon", "treasurer-dragon", "bronze-elite", "bronze" }) do assert(measured[name], name .. " measured") end
		end)
	end)
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = unpack(saved, 1, 3)
	if not ok then error(err, 0) end
end)

test("party dragon recovery: PartyFrame created after login is hooked before its pooled member frames appear", function()
	WithBorders(function(w)
		w.internal("LOGIN") -- target/player art exists, but PartyFrame has not loaded yet
		w.party(false)
		w.units.party1 = king
		w.fire("GROUP_ROSTER_UPDATE") -- the game's pool exists, its members not assigned yet
		eq(w.shown("party1"), nil)
		PartyFrame:InitializePartyMemberFrames()
		eq(w.shown("party1"), "gold-elite", "the post-initialize hook must draw the new party immediately")
		local hooks = #w.hooks
		w.fire("GROUP_ROSTER_UPDATE"); PartyFrame:InitializePartyMemberFrames()
		eq(#w.hooks, hooks, "one party initialization hook, even after repeated roster updates")
		eq(w.shown("party1"), "gold-elite")
	end)
end)

test("Queen preview regression: slash preview reaches own and self-target portraits without replacing another party member's identity", function()
	local savedDev, savedEM = ns.devWorkshop, rawget(_G, "EditModeManagerFrame")
	local ok, err = pcall(WithBorders, function(w)
		ns.Borders = w.B
		w.ns.IsQueenCharacter = function(name) return name == "Kaise Kaise-Realm" end
		w.party()
		w.units.party1 = king
		w.units.party2 = BorderUnit("Kaise Kaise", "HOLYPMUS", "Queen", 0)
		w.internal("LOGIN")
		SlashCmdList.OLYMPUS("borders test queen-dragon")
		eq(w.B.Preview(), "queen-dragon"); eq(w.shown("player"), "queen-dragon")
		w.target(w.units.player); eq(w.shown("target"), "queen-dragon", "self-target follows local preview")
		eq(w.shown("party1"), "gold-elite", "another player's real King identity")
		eq(w.shown("party2"), "queen-dragon", "another player's real signed Queen identity")
		EditModeManagerFrame = { ArePartyFramesForcedShown = function() return true end }
		PartyFrame:InitializePartyMemberFrames()
		eq(w.shownOn(w.partyFrame("party4").label), "queen-dragon", "empty Edit Mode stand-in previews supplied art")
		SlashCmdList.OLYMPUS("borders test off")
		eq(w.B.Preview(), nil); eq(w.shown("player"), nil)
		eq(w.shown("party1"), "gold-elite"); eq(w.shown("party2"), "queen-dragon")
	end, function(w)
		w.units.player = BorderUnit("Quillpen", "Olympus II", "Member", 3)
		ns.me, ns.devWorkshop = "Quillpen-Realm", { Quillpen = true }
	end)
	ns.devWorkshop, EditModeManagerFrame = savedDev, savedEM
	if not ok then error(err, 0) end
end)

test("party dragon recovery: late pool initialization waits for combat and respects gamepad parking", function()
	WithBorders(function(w)
		w.internal("LOGIN")
		w.combat = true
		w.party(false)
		w.units.party1 = king
		w.fire("GROUP_ROSTER_UPDATE")
		PartyFrame:InitializePartyMemberFrames()
		eq(w.shown("party1"), nil, "no party texture allocated in combat")
		eq(#w.hooks, 2, "only the existing target/focus hooks while in combat")
		w.combat = false; w.fire("PLAYER_REGEN_ENABLED")
		eq(w.shown("party1"), "gold-elite"); eq(#w.hooks, 3)
		w.style = 1; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
		eq(w.shown("party1"), nil)
		PartyFrame:InitializePartyMemberFrames()
		eq(w.shown("party1"), nil, "the game's callback remains inert under gamepad")
		w.style = 0; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
		eq(w.shown("party1"), "gold-elite"); eq(#w.hooks, 3, "no repeated hook on return")
		-- The input event can be missed: the retained pool callback still removes our art,
		-- and the next name update must not reuse the frame's old party assignment.
		w.style = 1
		w.partyOrder = { 2, 1, 3, 4 }
		PartyFrame:InitializePartyMemberFrames()
		eq(w.shownOn("PartyMember#1"), nil, "missed input event still hides the old portrait")
		eq(w.shownOn("PartyMember#2"), nil, "no new portrait while the gate refuses it")
		w.style = 0; w.fire("UNIT_NAME_UPDATE", "party1")
		eq(w.shownOn("PartyMember#2"), "gold-elite", "a name update before the input event remaps the pool")
		eq(w.shownOn("PartyMember#1"), nil, "the previous pooled frame remains empty")
		eq(#w.hooks, 3)
	end)
end)
