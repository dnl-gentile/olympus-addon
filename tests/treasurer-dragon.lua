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
	return cx, cy
end
-- The same, from where it finds the centre again until it stops moving: a ray's edge depends on
-- where the rays start (8 file pixels left or right of the centre move one reading 4 px), so the
-- start is the portrait's centre only for the first reading.
local function SettledRingCentre(alpha, x0, y0)
	local cx, cy = RingCentre(alpha, x0, y0)
	for _ = 1, 20 do
		local nx, ny = RingCentre(alpha, cx, cy)
		local moved = math.abs(nx - cx) + math.abs(ny - cy)
		cx, cy = nx, ny
		if moved < 0.01 then return cx, cy end
	end
	return cx, cy
end

test("1.2.1 party borders: every border drawn from Olympus's own file (the Treasurer's dragon, the bronze wings, the plain bronze) has its ring round the party member's portrait, within a pixel of its centre", function()
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
			for _, name in ipairs({ "treasurer-dragon", "bronze-elite", "bronze" }) do assert(measured[name], name .. " measured") end
		end)
	end)
	ns.TREASURER, ns.TREASURER_CHARACTERS, ns.TREASURER_REALM = unpack(saved, 1, 3)
	if not ok then error(err, 0) end
end)
