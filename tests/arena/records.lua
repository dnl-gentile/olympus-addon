-- Original signed KN halves exercise Records and its actual Bones adapter. No private source key.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES
local function Do(w, c, f, ...) return w:As(c, c.ns.Records[f], ...) end
local function Setup(clock)
	local w = FW.New({ compliance = "shipped", clock = clock })
	return w, w:Player(N.fighterA), w:Player(N.fighterB), w:Player(N.bettor3)
end
local function Pair(w, a, b, id, winner, t)
	local out = {}
	for seat, c in ipairs({ a, b }) do
		out[seat] = w:As(c, function()
			local B = c.ns.Arena.B36
			local time = t or w.clock
			local core = ("%s~%s~%s~-~2~-~e~%s~%s~%s~t~%s~0a1b2c3d~%s~%s~%d"):format(id, a.name, b.name, winner or "1", B(2000), B(300), B(40), B(time), B(time - 300), seat)
			local D = c.ns.Debts local _, pk = D.MyKey()
			return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYB1|" .. core))
		end)
	end
	return out[1] .. "^" .. out[2]
end
-- A crafting delivery's two signed halves (the requester's, the crafter's), of today's server day,
-- as a Records body.
local function CraftPair(w, requester, crafter, id, itemID, quantity, tier)
	local out, day = {}, math.floor(w.clock / 86400)
	for i, client in ipairs({ requester, crafter }) do
		out[i] = w:As(client, function()
			local role = i == 1 and "r" or "c"
			local core = table.concat({ id, requester.name, crafter.name, itemID or 123, quantity or 5, tier or 2, day, role }, "~")
			local D = client.ns.Debts
			local _, pk = D.MyKey()
			return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYC1|" .. core))
		end)
	end
	return out[1] .. "^" .. out[2]
end
-- The game names every client of the world by its GUID (GetPlayerInfoByGUID), from now on.
local function EnableGuidLookup(w)
	for _, client in ipairs(w.clients) do
		client.globals.GetPlayerInfoByGUID = function(guid)
			for _, named in ipairs(w.clients) do
				if named.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, named.short, named.realm end
			end
		end
	end
end
-- A direct duel's two signed halves (A won 1:0 by knockout, 20 s), dated now, as a Records body.
local function DuelPair(w, a, b, id)
	local halves = {}
	for side, client in ipairs({ a, b }) do
		halves[side] = w:As(client, function()
			local A, D = client.ns.Arena, client.ns.Debts
			local core = table.concat({ id, side == 1 and "A" or "B", A.GK(a.guid), a.name, A.GK(b.guid), b.name, "1", "A", "A", "K", "AK" .. A.B36(20), A.B36(w.clock), "-", "60", "60" }, "~")
			local _, pk = D.MyKey()
			return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYH1|" .. core))
		end)
	end
	return halves[1] .. "^" .. halves[2]
end
local function Keys(w, a, b)
	for _, c in ipairs({ a, b }) do assert(Do(w, c, "SendKey")) end
	w:Run(3)
end
local function Take(w, c, body) Do(w, c, "Take", "b", body, N.bettor1, "relay") w:Run(3) end
local function Errors(w)
	for _, c in ipairs(w.clients) do for _, err in ipairs(c.errors) do error(c.name .. ": " .. err) end end
end
-- The world runs in steps (5 s) until fn() holds or `seconds` passed: when it first held, or nil.
local function RunUntil(w, seconds, fn, step)
	local stop = w.clock + seconds
	while w.clock < stop do
		w:Run(math.min(step or 5, stop - w.clock))
		if fn() then return w.clock end
	end
	return nil
end

test("shared records diagnostics include every registered ranking type", function()
	local w, _, _, c = Setup()
	local text = Do(w, c, "StatusText")
	assert(text:find("Bones games", 1, true), "Bones is visible")
	assert(text:find("Craft deliveries", 1, true), "crafting is not hidden from the records diagnostic")
	assert(text:find("Duels", 1, true), "duels are visible")
	Errors(w)
end)

-- The weight rule (the design): 1.2.6's first build loaded the records on every login and sent an
-- empty digest of each type (RD letter~~) from clients that hold nothing, so a practice game, a
-- client that only heard the King's word, or any idle member sent RD and ran a records timer.
test("records: the weight rule: a client that holds nothing loads nothing at login, runs no records timer and sends no records message", function()
	local w, _, _, c = Setup()
	w:Run(3600)
	for _, t in ipairs(w:Timers(c, true)) do
		assert(not tostring(t.where):find("^records") and not tostring(t.where):find("^craft ranking"), "an idle client's timer: " .. tostring(t.where))
	end
	-- (1.4.0: and no discovery ask, RH: a ranking view asks, never a login.)
	for _, kind in ipairs({ "RK", "RD", "RA", "RR", "RV", "RS", "RT", "RH" }) do eq(#w:Sent({ from = c, type = kind }), 0, kind .. " from an idle client") end
	Errors(w)
end)

test("1.2.4 records: both original signatures and firsthand keys admit one Bones result; repeated bodies never count twice", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr1") Keys(w, a, b)
	Take(w, c, body) eq(Do(w, c, "Count", "b"), 1)
	local rows = w:As(c, c.ns.FarkleTable.Best, "L") eq(#rows, 2) eq(rows[1].won, 1)
	Take(w, c, body) eq(Do(w, c, "Count", "b"), 1) eq(#Do(w, c, "Clashes", "b"), 0)
	Errors(w)
end)

test("1.2.4 records history: bounded digests rotate every old unsealed day without dropping the newest days or advancing on a refused send", function()
	local w, a, b, c = Setup()
	local R = c.ns.Records
	local total, days = R.DIGEST_DAYS + 10, {}
	local store = Do(w, c, "Store", "b", true)
	for i = 0, total - 1 do
		local at = w.clock - i * 86400
		local body = Pair(w, a, b, "Krpage" .. i, "1", at)
		local rec = w:As(c, R.TYPES.b.Read, body)
		assert(rec, "valid original result fixture")
		local day = math.floor(at / 86400)
		store.days[day] = { [rec.id] = body }
		days[#days + 1] = day
	end
	local seen = {}
	local send = c.ns.Arena.Send
	c.ns.Arena.Send = function() return false end
	local first = Do(w, c, "DigestBody", "b")
	eq(Do(w, c, "SendDigest", "b"), false)
	eq(Do(w, c, "DigestBody", "b"), first, "full queue keeps the same historical page")
	c.ns.Arena.Send = function(kind, mode, body)
		eq(kind, "RD"); eq(mode, "L")
		local list = body:match("^b~([^~]*)~")
		local page, count = {}, 0
		for day in list:gmatch("([0-9a-z]+)%.[0-9a-z]+%.[0-9a-z]+") do
			day = c.ns.Arena.N(day, 0, 400000)
			page[day], seen[day] = true, true
			count = count + 1
		end
		assert(count <= R.DIGEST_DAYS, "wire stays bounded")
		for i = 1, 3 do assert(page[days[i]], "newest day remains visible") end
		return true
	end
	for _ = 1, 3 do assert(Do(w, c, "SendDigest", "b")) end
	c.ns.Arena.Send = send
	for _, day in ipairs(days) do assert(seen[day], "old unsealed day reachable by a later login: " .. day) end
	Errors(w)
end)

test("1.2.4 records rotation review: equal inventories on different full pages never schedule false pushes", function()
	for _, kind in ipairs({ "days", "months" }) do
		local w, a, b, c = Setup()
		local mine, peer = Do(w, c, "Store", "b", true), Do(w, b, "Store", "b", true)
		local R = c.ns.Records
		if kind == "days" then
			for i = 0, R.DIGEST_DAYS + 9 do
				local at = w.clock - i * 86400
				local body = Pair(w, a, b, "Kreview" .. i, "1", at)
				local rec = w:As(c, R.TYPES.b.Read, body)
				local day = math.floor(at / 86400)
				mine.days[day], peer.days[day] = { [rec.id] = body }, { [rec.id] = body }
			end
		else
			local latest = Do(w, c, "MonthOf", w.clock) - 1
			for i = 0, R.DIGEST_MONTHS + 4 do
				-- Already-adopted fixtures: real RSA adoption has a separate round trip.
				mine.seals[latest - i], peer.seals[latest - i] = { r = "", h = string.rep("a", 64) }, { r = "", h = string.rep("a", 64) }
			end
		end
		b.ns.Arena.Send = function() return true end
		assert(Do(w, b, "SendDigest", "b")) -- advance to a noncontiguous historical page
		local page = Do(w, b, "DigestBody", "b")
		local pushes = 0
		c.ns.Arena.Send = function(tag) if tag == "RD" then pushes = pushes + 1 end; return true end
		w:As(c, c.comm.handlers.RD, "CHANNEL", b.name, "RD~L1~" .. page)
		-- (Changed on purpose, 1.4.0: a push is no longer drawn (the random stub that forced the
		-- draw is gone) and waits for its slot, PUSH_MIN + score * PUSH_WINDOW, not 2 to 10 s: the
		-- run covers the whole window, so a false push would be seen.)
		w:Run(R.PUSH_MIN + R.PUSH_WINDOW + 1)
		eq(pushes, 0, kind .. " omitted by rotation do not prove a missing record")
		Errors(w)
	end
end)

test("1.2.4 records rotation review: genuinely newer days and sealed months still schedule recovery pushes", function()
	for _, kind in ipairs({ "days", "months" }) do
		local w, a, b, c = Setup()
		local mine, peer = Do(w, c, "Store", "b", true), Do(w, b, "Store", "b", true)
		local R = c.ns.Records
		if kind == "days" then
			for i = 0, R.DIGEST_DAYS do
				local at = w.clock - i * 86400
				local body = Pair(w, a, b, "Knewer" .. i, "1", at)
				local rec = w:As(c, R.TYPES.b.Read, body)
				local day = math.floor(at / 86400)
				mine.days[day] = { [rec.id] = body }
				if i > 0 then peer.days[day] = { [rec.id] = body } end
			end
		else
			local latest = Do(w, c, "MonthOf", w.clock) - 1
			for i = 0, R.DIGEST_MONTHS do
				mine.seals[latest - i] = { r = "", h = string.rep("a", 64) }
				if i > 0 then peer.seals[latest - i] = { r = "", h = string.rep("a", 64) } end
			end
		end
		local pushes = 0
		c.ns.Arena.Send = function(tag) if tag == "RD" then pushes = pushes + 1 end; return true end
		local page = Do(w, b, "DigestBody", "b")
		w:As(c, c.comm.handlers.RD, "CHANNEL", b.name, "RD~L1~" .. page)
		-- (Changed on purpose, 1.4.0: the push is no longer drawn and waits for its slot, PUSH_MIN +
		-- score * PUSH_WINDOW: the run covers that window instead of the draw's 2 to 10 s.)
		w:Run(R.PUSH_MIN + R.PUSH_WINDOW + 1)
		eq(pushes, 1, "newest " .. kind .. " is not a rotated omission")
		Errors(w)
	end
end)

test("1.2.4 records regression: an unsigned conflicting body cannot invalidate a legitimate record or its ranking", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr2") Keys(w, a, b) Take(w, c, body)
	local fake = Pair(w, a, b, "Kr2", "2"):gsub("~[%w%-_]+$", "~" .. string.rep("A", 86))
	Take(w, c, fake)
	eq(#Do(w, c, "Clashes", "b"), 0, "no conflict before signature verification")
	eq(Do(w, c, "Count", "b"), 1) eq(#w:As(c, c.ns.FarkleTable.Best, "L"), 2)
	Errors(w)
end)

test("1.2.4 records history: sealed monthly summaries beyond the newest twenty-four remain discoverable", function()
	local w, _, _, c = Setup()
	local R, store = c.ns.Records, Do(w, c, "Store", "b", true)
	local latest = Do(w, c, "MonthOf", w.clock) - 1
	local total = R.DIGEST_MONTHS + 5
	-- Already-adopted summary fixtures: signature/hash adoption is exercised by the separate
	-- RSA round trip. This test exercises the real bounded relay's discovery inventory.
	for i = 0, total - 1 do store.seals[latest - i] = { r = "", h = string.rep("a", 64) } end
	local original, seen = c.ns.Arena.Send, {}
	c.ns.Arena.Send = function() return false end
	local first = Do(w, c, "DigestBody", "b")
	eq(Do(w, c, "SendDigest", "b"), false)
	eq(Do(w, c, "DigestBody", "b"), first)
	c.ns.Arena.Send = function(_, _, body)
		local list = body:match("^b~[^~]*~([^~]*)$")
		local page, count = {}, 0
		for month in list:gmatch("([0-9a-z]+)%.%x+") do
			month = c.ns.Arena.N(month, 0, 100000)
			page[month], seen[month], count = true, true, count + 1
		end
		assert(count <= R.DIGEST_MONTHS)
		assert(page[latest], "newest completed month is on every page")
		return true
	end
	for _ = 1, 3 do assert(Do(w, c, "SendDigest", "b")) end
	c.ns.Arena.Send = original
	for i = 0, total - 1 do assert(seen[latest - i], "older sealed month remains reachable") end
	Errors(w)
end)

test("1.2.4 records: a signed conflicting result is excluded and retained, and changes the holder digest for relay", function()
	local w, a, b, c = Setup() Keys(w, a, b) Take(w, c, Pair(w, a, b, "Kr3"))
	local before = Do(w, c, "DigestBody", "b")
	Take(w, c, Pair(w, a, b, "Kr3", "2"))
	eq(#Do(w, c, "Clashes", "b"), 1) eq(#w:As(c, c.ns.FarkleTable.Best, "L"), 0)
	assert(Do(w, c, "DigestBody", "b") ~= before, "verified conflict is visible to anti-entropy")
	Errors(w)
end)

test("1.2.4 records: a relay cannot bootstrap identity; pending records survive reload and wait for original players' keys", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr4")
	Take(w, c, body) eq(Do(w, c, "Count", "b"), 0) eq(Do(w, c, "Pending", "b"), 1)
	w:Logout(c) w:Login(c) w:Run(15)
	eq(Do(w, c, "Pending", "b"), 1)
	Keys(w, a, b) eq(Do(w, c, "Count", "b"), 1) eq(Do(w, c, "Pending", "b"), 0)
	Errors(w)
end)

test("1.2.4 records review: one relayer cannot evict every other player's pending records", function()
	local w, a, b, c = Setup()
	local R = c.ns.Records
	for i = 1, R.PENDING_EACH do
		local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krpend" .. i), N.bettor1, "relay")
		eq(why, "pending")
	end
	local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krpendover"), N.bettor1, "relay")
	eq(why, "pending-sender", "the sender is capped before it can consume the global store")
	_, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krpendpeer"), N.bettor2, "relay")
	eq(why, "pending", "another relayer still has room")
	eq(Do(w, c, "Pending", "b"), R.PENDING_EACH + 1)
	Errors(w)
end)

test("1.2.4 records review: one relayer cannot monopolize the signature wait queue", function()
	local w, a, b, c = Setup() Keys(w, a, b)
	local R, original = c.ns.Records, c.ns.Arena.Check
	R.TYPES.b.DAY_MAX = 1000
	c.ns.Arena.Check = function() end -- keep the real Records inflight slots occupied
	for i = 1, R.CHECKS_EACH do
		local ok, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krcheck" .. i), N.bettor1, "relay")
		eq(ok, true); eq(why, "checking")
	end
	for i = 1, R.WAIT_EACH do
		local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krwait" .. i), N.bettor1, "relay")
		eq(why, "waiting")
	end
	local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krwaitover"), N.bettor1, "relay")
	eq(why, "busy-sender")
	local ok
	ok, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krwaitpeer"), N.bettor2, "relay")
	eq(ok, true); eq(why, "checking", "another relayer retains an active verifier slot")
	c.ns.Arena.Check = original
	Errors(w)
end)

test("1.2.4 records: asynchronous callbacks recheck per-player capacity before storing results", function()
	local w, a, b, c = Setup() Keys(w, a, b)
	c.ns.Records.TYPES.b.DAY_MAX = 1
	local checks, original = {}, c.ns.Arena.Check
	c.ns.Arena.Check = function(key, claim, cb) checks[#checks + 1] = { key, claim, cb } end
	Do(w, c, "Take", "b", Pair(w, a, b, "Kr5"), N.bettor1, "relay")
	Do(w, c, "Take", "b", Pair(w, a, b, "Kr6"), N.bettor1, "relay")
	c.ns.Arena.Check = original
	for _, check in ipairs(checks) do w:As(c, original, unpack(check)) end
	w:Run(3) eq(Do(w, c, "Count", "b"), 1, "two inflight records cannot consume the same final slot")
	Errors(w)
end)

test("1.2.4 records: an unsealed month is never silently erased, even after the legacy Bones store prunes it", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr7") Keys(w, a, b) Take(w, c, body)
	local month = Do(w, c, "MonthOf", w.clock)
	w:Logout(a) w:Logout(b) w:Run(80 * 86400)
	w:As(c, c.ns.FarkleTable.Prune)
	eq(Do(w, c, "Count", "b"), 1)
	eq(#w:As(c, c.ns.FarkleTable.Best, "L", { month = month }), 2, "ranking reconstructs its signed records")
	w:Logout(c) w:Login(c) w:Run(15) eq(Do(w, c, "Count", "b"), 1)
	Errors(w)
end)

test("1.2.4 records: bounded verifier retries do not spin when the shared verification queue is full", function()
	local w, a, b, c = Setup() Keys(w, a, b)
	local original, calls = c.ns.Arena.Check, 0
	c.ns.Arena.Check = function(key, claim, cb) calls = calls + 1 cb(nil) end
	Do(w, c, "Take", "b", Pair(w, a, b, "Kr8"), N.bettor1, "relay")
	eq(calls, 2) w:Run(5) eq(calls, 2)
	c.ns.Arena.Check = original w:Run(35) eq(Do(w, c, "Count", "b"), 1)
	Errors(w)
end)

test("1.2.4 records: Alliance and Horde stores are separate in the same realm saved data; malformed totals are refused", function()
	local w, a, b, c = Setup() Keys(w, a, b) Take(w, c, Pair(w, a, b, "Kr9"))
	local faction = c.ns.faction c.ns.faction = "Horde"
	eq(Do(w, c, "Count", "b"), 0) c.ns.faction = faction eq(Do(w, c, "Count", "b"), 1)
	local sent = w:As(a, a.ns.Arena.Send, "RT", "L", "b~1~12345678~1~1", {})
	assert(sent) w:Run(1) Errors(w)
end)

test("1.2.4 records: any ordinary holder relays a Bones result to a late member; identity still comes from its players", function()
	local w, a, b, c = Setup() Keys(w, a, b) Take(w, c, Pair(w, a, b, "Kr10"))
	local late = w:Player(N.bettor1)
	Keys(w, a, b)
	w:Run(c.ns.Records.ANSWER_GAP + 1) -- an original result just heard suppresses redundant immediate answers
	-- (Changed on purpose, 1.4.0: no draw stubs, as no answer is drawn any more: the holder whose
	-- digest made the late client ask answers it first, Records.Slot.)
	assert(Do(w, c, "SendDigest", "b")) w:Run(20)
	eq(Do(w, late, "Count", "b"), 1, "neither original player sent the result to this late client")
	eq(#w:As(late, late.ns.FarkleTable.Best, "L"), 2)
	Errors(w)
end)

test("global records: two validating holders recover Bones ranking for a late client while both original players are offline", function()
	local w, a, b, c = Setup()
	local second = w:Player(N.bettor2)
	local body = Pair(w, a, b, "Kr11")
	Keys(w, a, b)
	Take(w, c, body)
	Take(w, second, body)
	eq(Do(w, c, "Count", "b"), 1)
	eq(Do(w, second, "Count", "b"), 1)

	-- The original players and their firsthand RK declarations are gone before this client exists.
	w:Logout(a)
	w:Logout(b)
	local late = w:Player(N.bettor1)
	-- (Changed on purpose, the weight rule: a client that holds nothing sends nothing at its login,
	-- so the late client makes no discovery call of its own. A holder's periodic digest (Tick,
	-- DIGEST_EVERY) is the path, as the author asked: "a rede precisa armazenar aquele estado e
	-- republicar para as pessoas quando a fonte original não tiver online". The holders' digest,
	-- the late client's ask, the body and two independently signed validations, within one round.)
	-- (Changed on purpose, 1.4.0: no draw stubs any more, as no digest is drawn: each holder has
	-- its slot in every round, R.Slot. The bound is a round and its window, plus the answers.)
	local R = c.ns.Records
	local heldAt = RunUntil(w, R.DIGEST_EVERY + w:As(c, R.DigestWindow) + 120, function() return Do(w, late, "Count", "b") == 1 end)
	-- (Changed on purpose, 1.4.0: once it holds the record the late client is a holder like any
	-- other and takes its turn in the next round. What the weight rule forbids is a digest from the
	-- empty client, before it held anything.)
	local digests = w:Sent({ from = late, type = "RD" })
	assert(not digests[1] or (heldAt and digests[1].t >= heldAt - 5), "the late, empty client asked nobody at its login")

	local count = Do(w, late, "Count", "b")
	local refused = {}
	for why, n in pairs(c.ns.Arena.Stats().refused or {}) do refused[#refused + 1] = tostring(why) .. "=" .. tostring(n) end
	table.sort(refused)
	assert(count == 1, ("validated network survives originals offline: count=%d pending=%d RD=%d RA=%d RR=%d RK=%d RV=%d witnessed=%d"):format(
		count, Do(w, late, "Pending", "b"), #w:Sent({ type = "RD" }), #w:Sent({ type = "RA" }), #w:Sent({ type = "RR" }),
		#w:Sent({ type = "RK" }), #w:Sent({ type = "RV" }), late.ns.Records.Stats().witnessed or 0)
		.. (" out=%d/%d producers=%d/%d arenaoff=%s/%s"):format(Do(w, c, "OutSize"), Do(w, second, "OutSize"),
			c.ns.Arena.ProducerCount(), second.ns.Arena.ProducerCount(), tostring(c.ns.Arena.Off()), tostring(second.ns.Arena.Off()))
		.. " refused=" .. table.concat(refused, ","))
	eq(Do(w, late, "Pending", "b"), 0)
	eq(#w:As(late, late.ns.FarkleTable.Best, "L"), 2)
	assert((late.ns.Records.Stats().witnessed or 0) >= 1, "identity was admitted by holder quorum")
	Errors(w)
end)

-- The author: "ela passa a fazer o relay daquele negócio validado, que vai ser validado junto com
-- outras pessoas que têm o negócio que receberam validade". The test above drew every holder
-- (random 0); in the game a holder answered an ask only when drawn (about RELAYS of the army). The
-- first build's late client then kept the body, waiting, after ONE holder's validation: its next
-- asks listed that body as held, so no holder answered it again, no second validation ever came,
-- and the result never counted (7 asks over an hour, 1 RV, count 0). It now asks for the
-- validations alone (RA letter~w~day) with each ask of that day, and never gets the body again.
local function ShortOfOne(w, id)
	local a, b, c = w.clients[1], w.clients[2], w.clients[3]
	local second = w:Player(N.bettor2)
	local day = math.floor(w.clock / 86400) -- (the record's: Pair stamps it now)
	local body = Pair(w, a, b, id)
	Keys(w, a, b)
	Take(w, c, body)
	Take(w, second, body)
	w:Logout(a)
	w:Logout(b)
	-- (Changed on purpose, 1.4.0: no holder is drawn any more, so the second holder is offline for
	-- this round instead of not drawn for its answer. The caller logs it in for the next round.)
	w:Logout(second)
	local late = w:Player(N.bettor1)
	w:Run(c.ns.Records.DIGEST_EVERY + 120)
	eq(Do(w, late, "Count", "b"), 0, "one holder's validation admits nothing")
	eq(Do(w, late, "Pending", "b"), 1, "the body is here, waiting")
	return c, second, late, day
end
local function WitnessAsks(w, from)
	local n = 0
	for _, s in ipairs(w:Sent({ from = from, type = "RA" })) do if s.msg:find("~b~w~", 1, true) then n = n + 1 end end
	return n
end

test("global records review: a late client one validation short asks for the validations alone and counts the result in the next round, without the body again", function()
	local w = Setup()
	local c, second, late = ShortOfOne(w, "Kr12")
	local bodies = #w:Sent({ type = "EP" }) -- (the body went in parts, EP; nothing else here does)
	w:Login(second) -- (1.4.0: back for the next round)
	w:Run(c.ns.Records.DIGEST_EVERY + 120)
	eq(Do(w, late, "Count", "b"), 1, "the second holder's validation came: the result counts")
	eq(Do(w, late, "Pending", "b"), 0)
	assert(WitnessAsks(w, late) >= 1, "the late client asked for the validations of what it holds")
	eq(#w:As(late, late.ns.FarkleTable.Best, "L"), 2)
	eq(#w:Sent({ type = "EP" }), bodies, "the body was not sent again")
	assert(#w:Sent({ from = second, type = "RV" }) >= 1, "the second holder validated it")
	Errors(w)
end)

test("global records review: validations are heard in one session only; after a reload the waiting body is validated in the next session", function()
	local w = Setup()
	local c, second, late = ShortOfOne(w, "Kr13")
	w:Logout(late) w:Login(late)
	w:Run(15)
	eq(Do(w, late, "Pending", "b"), 1, "the body survived the reload, waiting")
	w:Login(second) -- (1.4.0: back for the next round, ShortOfOne)
	w:Run(c.ns.Records.DIGEST_EVERY + 120)
	eq(Do(w, late, "Count", "b"), 1, "both holders' validations heard in this session")
	eq(Do(w, late, "Pending", "b"), 0)
	Errors(w)
end)

test("global records review: an ask for validations alone draws none for a record no holder has, and a malformed one is refused", function()
	local w = Setup()
	local c, _, late, d = ShortOfOne(w, "Kr14")
	local before = #w:Sent({ type = "RV" })
	local refused = (c.ns.Records.Stats().refused.shape or 0)
	eq(#Do(w, c, "Bodies", "b", d, d), 1, "the holder holds a record of that day")
	local day = c.ns.Arena.B36(d)
	assert(w:As(late, late.ns.Arena.Send, "RA", "L", "b~w~" .. day .. "~" .. ("0"):rep(16), { dist = "CHANNEL" }))
	assert(w:As(late, late.ns.Arena.Send, "RA", "L", "b~w~" .. day .. "~xyz", { dist = "CHANNEL" }))
	w:Run(30)
	eq(#w:Sent({ type = "RV" }), before, "nobody holds that record: no validation")
	eq(c.ns.Records.Stats().refused.shape, refused + 1, "the malformed ask is refused")
	Errors(w)
end)

-- The first build signed, in one timer callback, each validation of an answer and the holder's key
-- again with each: a day of N missing records was 2N Ed25519 signatures on one frame of a drawn
-- holder (a hitch, the 1.2.1 lesson). The key is now declared once an answer, and each validation
-- is signed when its turn on the low lane comes (a message a second).
test("global records review: an answer declares the holder's key once and signs each validation as it leaves, never a day's at once", function()
	local w, a, b, c = Setup()
	local late = w:Player(N.bettor1)
	Keys(w, a, b)
	local d = math.floor(w.clock / 86400)
	for i = 1, 4 do Take(w, c, Pair(w, a, b, "Krs" .. i)) end
	eq(Do(w, c, "Count", "b"), 4)
	w:Run(c.ns.Records.ANSWER_GAP + 1)
	local D, signs = c.ns.Debts, 0
	local Sign = D.Sign
	D.Sign = function(...) signs = signs + 1 return Sign(...) end
	-- (Changed on purpose, 1.4.0: no draw stub. The holder whose digest made the late client ask
	-- answers it first, so c's digest goes first; and its answer comes at its slot, ANSWER_MIN +
	-- score * ANSWER_SPREAD, so the world runs until it is on its way, a second at a time.)
	assert(Do(w, c, "SendDigest", "b"))
	-- The late client holds none of that day's records: an ask with no prefixes.
	assert(w:As(late, late.ns.Arena.Send, "RA", "L", "b~d~" .. late.ns.Arena.B36(d) .. "~", { dist = "CHANNEL" }))
	local R = c.ns.Records
	assert(RunUntil(w, R.ANSWER_MIN + R.ANSWER_SPREAD + 1, function() return Do(w, c, "OutSize") > 0 end, 1), "the answer is on its way, a message at a time")
	assert(signs <= 2, "the key once and at most the first validation so far, not 8 signatures: " .. signs)
	w:Run(120)
	eq(Do(w, c, "OutSize"), 0)
	eq(signs, 1 + 4, "one key declaration and one signature a validation")
	eq(#w:Sent({ from = c, type = "RV" }), 4)
	D.Sign = Sign
	Errors(w)
end)

-- 1.4.0, the relay bars (Records.Bar): the author's character never relays a record and a client
-- whose quiet presence is on sends nothing that says it is online; the King's client relays last.
-- This world's borders are told who the author is, on each client after each login (the core's
-- Borders.IsDevName, which Records asks: no arena file names him).
local function TellBorders(w, c)
	for _, client in ipairs(c and { c } or w.clients) do
		rawset(client.ns, "Borders", { IsDevName = function(name) return client.ns.Workshop.IsAuthorName(name) == true end })
	end
end
-- (A record's body goes in parts, EP: the pieces of an arena message over 255 bytes. Nothing but
-- records goes in parts in these scenes.)
local function SentKinds(w, c)
	local out = {}
	for _, kind in ipairs({ "RK", "RD", "RA", "RR", "RV", "RS", "RT", "RH", "EP" }) do out[kind] = #w:Sent({ from = c, type = kind }) end
	return out
end
local function Draws(w)
	for _, client in ipairs(w.clients) do client.ns.Records.random = function() return 0 end end
end

test("records: the author's character holds records but never relays one (no digest, record or validation); his own key still goes", function()
	local w, _, b, c = Setup()
	local author = w:Player(N.author)
	TellBorders(w)
	local body = Pair(w, author, b, "Kau1")
	Keys(w, author, b)
	Take(w, c, body)
	Take(w, author, body)
	eq(Do(w, author, "Count", "b"), 1, "he holds it")
	-- A new session of his: his record names him, so his key goes after the login (KeyLater).
	w:Logout(author) w:Login(author) TellBorders(w, author)
	local before = SentKinds(w, author)
	w:Logout(b)
	local late = w:Player(N.bettor1)
	Draws(w) -- every holder drawn, where a draw is still made
	w:Run(c.ns.Records.DIGEST_EVERY + 300)
	local after = SentKinds(w, author)
	for _, kind in ipairs({ "RD", "RR", "EP", "RV", "RS", "RT" }) do eq(after[kind] - before[kind], 0, kind .. " from the author's client") end
	assert(after.RK - before.RK >= 1, "his own key, declared after his login")
	assert(#w:Sent({ from = c, type = "RD" }) >= 1, "another holder's digest went")
	assert(#w:Sent({ from = late, type = "RA" }) >= 1, "the late client asked")
	assert(#w:Sent({ from = c, type = "EP" }) >= 1 and #w:Sent({ from = c, type = "RV" }) >= 1, "another holder answered it")
	Errors(w)
end)

test("records: a King holder whose quiet presence is on sends no records word: no key, digest, record or validation", function()
	local w, _, b, c = Setup()
	local king = w:Player(N.king, { guild = H.World.KING_GUILD, rank = 0 })
	local body = Pair(w, king, b, "Kking1")
	Keys(w, king, b)
	Take(w, c, body)
	Take(w, king, body)
	eq(Do(w, king, "Count", "b"), 1, "he holds it")
	-- A new session; his quiet presence turned on before his key would go (KeyLater).
	w:Logout(king) w:Login(king)
	eq(w:As(king, king.ns.SetQuietPresence, true, "records-test"), true, "the King may turn it on")
	local before = SentKinds(w, king)
	w:Logout(b)
	local late = w:Player(N.bettor1)
	Draws(w)
	w:Run(c.ns.Records.DIGEST_EVERY + 300)
	local after = SentKinds(w, king)
	-- (1.4.0: RH too.)
	for _, kind in ipairs({ "RK", "RD", "RR", "EP", "RV", "RS", "RT", "RH" }) do eq(after[kind] - before[kind], 0, kind .. " from the quiet King's client") end
	assert(#w:Sent({ from = late, type = "RA" }) >= 1, "the late client asked")
	assert(#w:Sent({ from = c, type = "EP" }) >= 1 and #w:Sent({ from = c, type = "RV" }) >= 1, "another holder answered it")
	-- Turned off: his key goes at the next tick.
	eq(w:As(king, king.ns.SetQuietPresence, false, "records-test"), true)
	w:Run(c.ns.Records.DIGEST_EVERY + 1)
	assert(SentKinds(w, king).RK - before.RK >= 1, "his key, once it is off")
	Errors(w)
end)

-- The author's paste is where a seal starts: his own signed word, not a relay. It still leaves his
-- client (RS and its totals, RT), while a seal ask (a relay) is answered by the other holders.
test("records: the author's pasted seal still leaves his client, though he answers no seal ask", function()
	local w, _, _, c = Setup()
	local author = w:Player(N.author)
	TellBorders(w)
	local month = Do(w, author, "MonthOf", w.clock) - 1
	-- (This world has no signer of the author's RSA key; the seal's own check is the real round trip,
	-- tests/records-seal-roundtrip.lua. Here his client takes the pasted text as signed.)
	rawset(author.ns, "Sign", setmetatable({ Plausible = function() return true end, Verify = function() return true end }, { __index = author.ns.Sign }))
	local hash = w:As(author, author.ns.Records.HashOf, "")
	local seal = ("RS1~%d~%s~Alliance~b~%d~0~%s~%s"):format(w.clock, H.World.GROUP, month, hash, ("ab"):rep(64))
	eq(Do(w, author, "Paste", seal), true)
	w:Run(30)
	eq(#w:Sent({ from = author, type = "RS" }), 1, "his seal went")
	assert(#w:Sent({ from = author, type = "RT" }) >= 1, "its totals went")
	-- An ask for that month's seal, once his own word is ANSWER_GAP old: no answer from him.
	w:Run(c.ns.Records.ANSWER_GAP + 1)
	assert(w:As(c, c.ns.Arena.Send, "RA", "L", "b~s~" .. c.ns.Arena.B36(month) .. "~-", { dist = "CHANNEL" }))
	w:Run(30)
	eq(#w:Sent({ from = author, type = "RS" }), 1, "no seal relayed by his client")
	Errors(w)
end)

-- 1.4.0, the rounds (Records.Slot, no draw). The digests went by a draw: each holder sent its own
-- with a chance of RELAYS / the army's addons (King.AddonsOnline). In an army of 300 with two
-- holders online that was 3 in 300 each, a round with no digest was the rule, and a late client
-- whose players were offline waited hours for the rankings. Each holder now has a slot every round.
local function Army(client, size)
	client.ns.King.AddonsOnline = function() return size end
	client.ns.Records.random = function() return 0.5 end -- (a draw, where one is still made: lost at 3 in 300)
end
local function Small(client) client.ns.King.AddonsOnline = function() return 1 end end
local function AskedDay(w, from, day)
	local tag = "~b~d~" .. day .. "~"
	for _, s in ipairs(w:Sent({ from = from, type = "RA" })) do if s.msg:find(tag, 1, true) then return true end end
	return false
end
test("records: in an army of 300, two holders tell a late client what they hold within one round, with no draw", function()
	local w, a, b, c = Setup()
	local second = w:Player(N.bettor2)
	Army(c, 300) Army(second, 300)
	local body = Pair(w, a, b, "Kround1")
	local day = c.ns.Arena.B36(math.floor(w.clock / 86400))
	Keys(w, a, b)
	Take(w, c, body)
	Take(w, second, body)
	w:Logout(a) w:Logout(b)
	local late = w:Player(N.bettor1)
	Army(late, 300)
	local R = c.ns.Records
	local window = w:As(c, R.DigestWindow)
	eq(window, 300, "the round's window follows the army's size")
	local start = w.clock
	local askedAt = RunUntil(w, R.DIGEST_EVERY + window + 10, function() return AskedDay(w, late, day) end)
	assert(#w:Sent({ from = c, type = "RD" }) + #w:Sent({ from = second, type = "RD" }) >= 1, "a holder's digest went this round")
	assert(w:As(c, R.Lag).n + w:As(second, R.Lag).n >= 1, "its time from slot to wire is kept (the stats)")
	assert(askedAt, "the late client asked for the record's day within one round")
	-- ...and both holders answered it (no draw for the answers either): the body and two validations.
	assert(RunUntil(w, start + R.DIGEST_EVERY + window + 120 - w.clock, function() return Do(w, late, "Count", "b") == 1 end), "the late client holds it within one round")
	eq(Do(w, late, "Pending", "b"), 0)
	Errors(w)
end)

-- (A review of the rounds: a digest heard silences ours only when it told the same of every day
-- and month ours would. Holders whose digests lack a record never silence the one holder of it,
-- even when their slots come first, round after round.)
local STALE = { "Aldo", "Brin", "Cass", "Dara", "Edda", "Fenn", "Gale", "Hask", "Ivo", "Jory", "Kell" }
test("records: the one holder of a record nobody else told always tells it, though stale holders' slots come first", function()
	local w, a, b, empty = Setup()
	w:Logout(empty) -- (no client here asks for what it lacks: the digests alone are watched)
	local holders = {}
	for i, first in ipairs(STALE) do holders[i] = w:Player(first .. " Tarrow") end
	local common, extra = Pair(w, a, b, "Kstale1"), Pair(w, a, b, "Kstale2")
	Keys(w, a, b)
	local R = holders[1].ns.Records
	-- The next round, and the holder whose slot in it comes last: the one that holds both records.
	local round = math.floor(w.clock / R.DIGEST_EVERY) + 1
	local function Score(c) return w:As(c, R.Score, "RD|b|" .. round, c.name) end
	table.sort(holders, function(x, y) return Score(x) < Score(y) end)
	local unique = holders[#holders]
	for _, h in ipairs(holders) do Take(w, h, common) end
	Take(w, unique, extra)
	eq(Do(w, unique, "Count", "b"), 2)
	-- (Its push is shut here, so that only its round's slot can tell it: a digest of its own a
	-- moment ago that nobody heard, and a push gap longer than the test. The push has its own test.)
	local send = unique.ns.Arena.Send
	unique.ns.Arena.Send = function() return true end
	assert(Do(w, unique, "SendDigest", "b"))
	unique.ns.Arena.Send = send
	unique.ns.Records.PUSH_GAP = 1e9
	w:Logout(a) w:Logout(b)
	local from, to = round * R.DIGEST_EVERY, (round + 1) * R.DIGEST_EVERY
	w:Run(to - w.clock)
	local function InRound(c, before)
		local n = 0
		for _, s in ipairs(w:Sent({ from = c, type = "RD" })) do if s.t >= from and s.t < (before or to) then n = n + 1 end end
		return n
	end
	eq(InRound(unique), 1, "the holder of the only copy told it, once")
	-- (Until it told it, the stale holders' round digests alone: about ELECT, the rest silenced. What
	-- its digest then sets off, asks and pushes, is the catch-up's.)
	local told = w:Sent({ from = unique, type = "RD" })
	local stale = 0
	for i = 1, #holders - 1 do stale = stale + InRound(holders[i], told[#told].t) end
	assert(stale >= R.ELECT and stale <= R.ELECT + 1, "the stale holders' digests, about ELECT a round: " .. stale)
	Errors(w)
end)

test("records: digests heard after a push was due that lack the same record never cancel it; two that tell it all do", function()
	for _, case in ipairs({ { stale = true, pushes = 1 }, { stale = false, pushes = 0 } }) do
		local w, a, b, c = Setup()
		local others = {}
		for i = 1, 3 do others[i] = w:Player(STALE[i] .. " Tarrow") end
		local common, extra = Pair(w, a, b, "Kpush1"), Pair(w, a, b, "Kpush2")
		Keys(w, a, b)
		Take(w, c, common) Take(w, c, extra)
		for i, o in ipairs(others) do
			Take(w, o, common)
			if not case.stale and i > 1 then Take(w, o, extra) end
		end
		local R = c.ns.Records
		local pushes = 0
		c.ns.Arena.Send = function(tag) if tag == "RD" then pushes = pushes + 1 end; return true end
		-- The first digest lacks a record c holds: c's push is due. Two more digests come after it.
		w:As(c, c.comm.handlers.RD, "CHANNEL", others[1].name, "RD~L1~" .. Do(w, others[1], "DigestBody", "b"))
		w:Run(1)
		for i = 2, 3 do w:As(c, c.comm.handlers.RD, "CHANNEL", others[i].name, "RD~L1~" .. Do(w, others[i], "DigestBody", "b")) end
		w:Run(R.PUSH_MIN + R.PUSH_WINDOW + 1)
		eq(pushes, case.pushes, case.stale and "stale digests silence nothing" or "two digests that told it all")
		Errors(w)
	end
end)

-- 1.4.0, who answers an ask (no draw). With a draw of 0 every holder answered every ask: nine
-- holders, nine validations of one record and as many copies of its body. Now the holders whose
-- digest made the late client ask answer it (and one whose digest goes while it waits); any other
-- holder only as a fallback, when nothing came.
test("records: an ask is answered by the holders whose digests made it, not by every holder", function()
	local w, a, b, empty = Setup()
	w:Logout(empty)
	local holders = {}
	for i = 1, 9 do holders[i] = w:Player(STALE[i] .. " Tarrow") end
	local body = Pair(w, a, b, "Kelect1")
	Keys(w, a, b)
	for _, h in ipairs(holders) do Take(w, h, body) end
	w:Logout(a) w:Logout(b)
	local late = w:Player(N.bettor1)
	Draws(w) -- (a draw of 0, where one is still made: every holder drawn)
	local R = late.ns.Records
	assert(RunUntil(w, R.DIGEST_EVERY + R.DIGEST_WINDOW_MAX + 120, function() return Do(w, late, "Count", "b") == 1 end), "the late client holds it")
	eq(Do(w, late, "Pending", "b"), 0)
	w:Run(R.FALLBACK_MIN + R.FALLBACK_SPREAD_MAX + R.KING_AFTER + 1) -- (any later answer would show)
	-- Every holder that answered (the body, EP, or a validation, RV) had told its digest first.
	local answered = 0
	for _, h in ipairs(holders) do
		local digests, first = w:Sent({ from = h, type = "RD" }), nil
		for _, kind in ipairs({ "EP", "RV" }) do
			for _, s in ipairs(w:Sent({ from = h, type = kind })) do if not first or s.t < first then first = s.t end end
		end
		if first then
			answered = answered + 1
			assert(digests[1] and digests[1].t <= first, h.name .. " answered without having told its digest")
		end
	end
	assert(answered >= R.WITNESSES and answered <= R.ELECT + 1, "the holders that answered: " .. answered)
	Errors(w)
end)

-- (A review of the election: the asker needs two validations from distinct holders. Holders whose
-- digests made it ask and then left before answering leave it to the others, turn by turn, until
-- the body and two validations came: not one fallback, which would leave it waiting for good.)
test("records: when the holders whose digests made a late client ask leave before answering, the others answer it", function()
	local w, a, b, empty = Setup()
	w:Logout(empty)
	local holders = {}
	for i = 1, 5 do holders[i] = w:Player(STALE[i] .. " Tarrow") Army(holders[i], 300) end
	local body = Pair(w, a, b, "Kfall1")
	local day = holders[1].ns.Arena.B36(math.floor(w.clock / 86400))
	Keys(w, a, b)
	for _, h in ipairs(holders) do Take(w, h, body) end
	w:Logout(a) w:Logout(b)
	local late = w:Player(N.bettor1)
	Army(late, 300)
	local R = late.ns.Records
	assert(RunUntil(w, R.DIGEST_EVERY + w:As(late, R.DigestWindow) + 10, function() return AskedDay(w, late, day) end, 1), "the late client asked")
	local gone = {}
	for _, h in ipairs(holders) do
		if w:Sent({ from = h, type = "RD" })[1] then gone[h] = true w:Logout(h) end
	end
	assert(next(gone), "a holder whose digest made it ask left")
	local spread = math.max(R.FALLBACK_SPREAD_MIN, math.min(R.FALLBACK_SPREAD_MAX, 300 / 2))
	assert(RunUntil(w, R.FALLBACK_MIN + spread + 30, function() return Do(w, late, "Count", "b") == 1 end), "the others answered within a fallback's turn")
	eq(Do(w, late, "Pending", "b"), 0)
	local validators = 0
	for _, h in ipairs(holders) do
		if not gone[h] and w:Sent({ from = h, type = "RV" })[1] then validators = validators + 1 end
	end
	assert(validators >= R.WITNESSES, "two holders that stayed validated it: " .. validators)
	Errors(w)
end)

-- (A review of the election: each client works its round's window out from what it sees of the
-- army. The King's turn is fixed after the widest window any client may use, so a King whose own
-- view is the narrowest still comes after every other holder: his digest, and his answer.)
test("records: the King's client relays last, after the widest round and every other holder's turn, though his own window is the narrowest", function()
	local w, a, b, empty = Setup()
	w:Logout(empty)
	local king = w:Player(N.king, { guild = H.World.KING_GUILD, rank = 0 })
	local holder = w:Player(STALE[1] .. " Tarrow")
	Small(king) Army(holder, 480)
	local body = Pair(w, a, b, "Kking2")
	local day = king.ns.Arena.B36(math.floor(w.clock / 86400))
	Keys(w, a, b)
	Take(w, king, body) Take(w, holder, body)
	w:Logout(a) w:Logout(b)
	local R = king.ns.Records
	local round = math.floor(w.clock / R.DIGEST_EVERY) + 1
	local base = round * R.DIGEST_EVERY
	eq(w:As(king, R.DigestWindow), R.DIGEST_WINDOW_MIN, "his own window: the narrowest")
	eq(w:As(king, R.Slot, "RD|b|" .. round, king.name, base, R.DIGEST_WINDOW_MIN, R.DIGEST_WINDOW_MAX), base + R.DIGEST_WINDOW_MAX + R.KING_AFTER)
	local late = w:Player(N.bettor1)
	Army(late, 480)
	assert(RunUntil(w, R.DIGEST_EVERY + R.DIGEST_WINDOW_MAX + 2 * R.KING_AFTER + 600, function() return Do(w, late, "Count", "b") == 1 end), "the late client holds it")
	local asked
	for _, s in ipairs(w:Sent({ from = late, type = "RA" })) do if s.msg:find("~b~d~" .. day .. "~", 1, true) then asked = asked or s.t end end
	local kingDigests, kingWitness = w:Sent({ from = king, type = "RD" }), w:Sent({ from = king, type = "RV" })
	local holderDigests, holderWitness = w:Sent({ from = holder, type = "RD" }), w:Sent({ from = holder, type = "RV" })
	assert(holderDigests[1] and holderWitness[1] and asked, "the other holder told it and answered first")
	assert(kingDigests[1], "his digest went (one other holder alone told it)")
	for _, s in ipairs(kingDigests) do
		assert(s.t - math.floor(s.t / R.DIGEST_EVERY) * R.DIGEST_EVERY >= R.DIGEST_WINDOW_MAX + R.KING_AFTER, "his digest after the widest round")
	end
	assert(kingWitness[1] and kingWitness[1].t >= asked + R.DIGEST_WINDOW_MAX + R.KING_AFTER - 1, "his validation after every other holder's turn")
	Errors(w)
end)

-- (A review of the election: one answer budget a holder, and one asker cannot spend it all.)
local function Quiet()
	-- Past this round's slots (an army of one: the narrowest window, DIGEST_WINDOW_MIN): no digest
	-- here until the next round, so the asks below are the only jobs.
	local w, a, b, c = Setup(math.floor(H.World.CLOCK / 600) * 600 + 130)
	for _, client in ipairs(w.clients) do Small(client) end
	return w, a, b, c
end

test("records: signed cross-relay recovery needs two independent holders on each of two receivers", function()
	local w = FW.New({ compliance = "shipped", clock = math.floor(H.World.CLOCK / 600) * 600 + 130 })
	local home = "CAMWOWUS1Realm1PvE"
	local a, b = w:Player(N.fighterA, { realm = home }), w:Player(N.fighterB, { realm = home })
	local first = w:Player(N.bettor3, { realm = home })
	local second = w:Player(N.bettor2, { realm = home })
	local old = w:Player(N.steward, { realm = home })
	local pvp = w:Player(N.arbiter, { realm = "CAMWOWUS1Realm1PvP" })
	local body = Pair(w, a, b, "Krmesh")
	local day = math.floor(w.clock / 86400)
	Keys(w, a, b)
	Take(w, first, body)
	Take(w, second, body)
	eq(Do(w, first, "Count", "b"), 1)
	eq(Do(w, second, "Count", "b"), 1)
	w:Logout(a)
	w:Logout(b)
	local left = w:Player(N.bettor1, { realm = "CAMWOWUS1Realm2PvE" })
	local right = w:Player(N.bank, { realm = "CAMWOWUS2Realm5PvE" })
	-- (Changed on purpose for 1.5.9, the release that ships the direct ask, RA x: the relay that is
	-- asked runs it, and "old" is a signed relay still on the published 1.5.8, whose Records.lua drops
	-- a whispered RA as a wrong lane and never answers. The comparison is Relay.AtLeast's, a version at
	-- or past the floor (here by the addon's own Workshop.Newer, Relay.lua being no part of this world):
	-- this test compared versions for equality, so a peer newer than the floor was never asked.)
	local versions = { [first.name] = "1.5.9", [second.name] = "1.5.9", [old.name] = "1.5.8",
		[left.name] = "1.5.9", [right.name] = "1.5.9", [pvp.name] = "1.5.9" }
	local secondFresh = false
	for _, c in ipairs({ first, second, old, pvp, left, right }) do
		Small(c)
		c.onChannel = false -- native whispers cross these pockets, channel traffic does not
		c.ns.splitNames, c.ns.group = true, c.ns.ForeverFamily(c.realm)
		c.ns.Relay = {
			On = function() return true end,
			IsSignedRelay = function(name) return versions[name] ~= nil end,
			Names = function() return { old.name, pvp.name, first.name, second.name } end,
			RelayVersion = function(name) return versions[name] end,
			AtLeast = function(v, floor) return type(v) == "string" and (v == floor or H.ns.Workshop.Newer(v, floor)) end,
			MeshPeer = function(name) return versions[name] ~= nil and (name ~= second.name or secondFresh) end,
		}
	end
	for _, c in ipairs({ left, right }) do
		Take(w, c, body)
		eq(Do(w, c, "Count", "b"), 0, "unverified original identities are not counted")
		eq(Do(w, c, "Pending", "b"), 1, "the exact result is already held")
		local check = c.ns.Arena.Check
		c.ns.Arena.Check = function(key, claim, done)
			if not key:match("^rk ") then return check(key, claim, done) end
			c.ns.After(5, "delay rank holder key", function() check(key, claim, done) end)
		end
	end

	assert(Do(w, left, "AskWitness", "b", day))
	w:Run(12)
	eq(#w:Sent({ from = left, type = "RA", dist = "WHISPER" }), 1, "only the current same-ruleset holder is asked")
	eq(#w:Sent({ from = first, type = "RV", dist = "WHISPER", to = left.name }), 1)
	eq(Do(w, left, "Count", "b"), 0, "one independently checked holder is insufficient")
	eq(Do(w, right, "Count", "b"), 0, "another pocket did not receive the targeted reply")
	Do(w, left, "AskWitness", "b", day)
	w:Run(3)
	eq(#w:Sent({ from = left, type = "RA", dist = "WHISPER" }), 1, "a repeated local request cannot spend a second mesh round")

	secondFresh = true
	w:Run(600)
	assert(Do(w, left, "AskWitness", "b", day))
	w:Run(31)
	eq(Do(w, left, "Count", "b"), 1, "two eligible independent proofs unlock the unchanged signed result")
	eq(Do(w, right, "Count", "b"), 0)
	assert(Do(w, right, "Discover"))
	w:Run(12)
	eq(Do(w, right, "Count", "b"), 1, "second receiver recovers while original players are still offline")
	eq(#w:As(left, left.ns.FarkleTable.Best, "L"), 2, "the ranking contains the two original players")
	eq(#w:As(right, right.ns.FarkleTable.Best, "L"), 2, "both receivers calculate the same ranking")
	eq(#w:Sent({ type = "RA", dist = "WHISPER", to = old.name }), 0, "mixed-version peer is untouched")
	eq(#w:Sent({ type = "RA", dist = "WHISPER", to = pvp.name }), 0, "different ruleset is untouched")
	eq(#w:Sent({ type = "RR", dist = "WHISPER" }), 0, "the existing record body is never resent")
	eq(#w:Sent({ type = "RA", dist = "WHISPER" }), 5, "three paced rounds reach at most two peers each")
	for _, packet in ipairs(w:Sent({ type = "RV", dist = "WHISPER" })) do
		assert(packet.target == left.name or packet.target == right.name, "private reply has exactly the requester as target")
	end
	Errors(w)
end)

test("records: a cached witness signature remains bound to its signed sender", function()
	local w, a, b, holder = Quiet()
	local body = Pair(w, a, b, "Krcache")
	Keys(w, a, b)
	Take(w, holder, body)
	w:Logout(a)
	w:Logout(b)
	local late = w:Player(N.bettor1)
	local other = w:Player(N.bettor2)
	Take(w, late, body)
	eq(Do(w, late, "Pending", "b"), 1)
	assert(Do(w, holder, "SendKey"))
	w:Run(5)
	assert(Do(w, holder, "SendWitness", "b", body, nil, true))
	w:Run(5)
	local packet = assert(w:Sent({ from = holder, type = "RV" })[1])
	local R, A = late.ns.Records, late.ns.Arena
	local _, hash, _, pk = A.Fields(packet.msg:sub(7), 5)
	eq(Do(w, late, "WitnessesSince", "b", hash, 0), 1)
	-- An account key may be held for two characters. It only verifies the name in the signature.
	assert(Do(w, late, "Pin", other.name, pk))
	w:As(late, A.Inject, "WHISPER", other.name, packet.msg)
	w:Run(5)
	eq(Do(w, late, "WitnessesSince", "b", hash, 0), 1, "cache cannot turn a different sender into another witness")
	eq(Do(w, late, "Count", "b"), 0)
	Errors(w)
end)

test("records: an unsent ranking day request retries its bucket and a sent one advances", function()
	local w, _, _, asker = Quiet()
	local R = asker.ns.Records
	local day = math.floor(w.clock / 86400)
	local bodies, finish = {}, nil
	local send = asker.ns.Arena.Send
	asker.ns.Arena.Send = function(kind, mode, body, opts)
		if kind ~= "RA" then return send(kind, mode, body, opts) end
		bodies[#bodies + 1], finish = body, opts.done
		return #bodies ~= 1
	end
	local function Ask() return Do(w, asker, "Ask", "b", day, R.ASK_PREFIX_MAX + 1) end
	eq(Ask(), false, "the first send is refused before queueing")
	eq(Ask(), true)
	eq(Ask(), false, "only one request for this day is in transport")
	w:As(asker, finish, false, "dropped")
	eq(Ask(), true)
	eq(bodies[1], bodies[2]); eq(bodies[2], bodies[3])
	assert(bodies[3]:match("~0:$"), "the first bucket stays pending until sent")
	w:As(asker, finish, true)
	eq(Ask(), true)
	assert(bodies[4]:match("~1:$"), "a successful send moves to the next bucket")
	eq(Do(w, asker, "Stats").asked, 1)
	asker.ns.Arena.Send = send
	Errors(w)
end)

test("records: a refused or dropped digest-triggered ask does not consume the ranking day cooldown", function()
	local w, holder, _, asker = Quiet()
	local R = asker.ns.Records
	local day = asker.ns.Arena.B36(math.floor(w.clock / 86400))
	local digest = "RD~L1~b~" .. day .. ".1.1~"
	local send = asker.ns.Arena.Send
	local attempts = 0
	asker.ns.Arena.Send = function(kind, mode, body, opts)
		if kind == "RA" then
			attempts = attempts + 1
			if attempts == 1 then return false, "off" end
			if attempts == 2 then opts.done(false, "dropped"); return true end
		end
		return send(kind, mode, body, opts)
	end
	local function Digest()
		w:As(asker, asker.comm.handlers.RD, "CHANNEL", holder.name, digest)
		w:Run(R.ASK_SPREAD + 4)
	end
	Digest(); eq(attempts, 1); eq(R.Stats().asked, 0)
	Digest(); eq(attempts, 2); eq(R.Stats().asked, 0)
	Digest(); eq(attempts, 3); eq(R.Stats().asked, 1)
	eq(#w:Sent({ from = asker, type = "RA" }), 1)
	Digest(); eq(attempts, 3, "success enables the ordinary cooldown")
	asker.ns.Arena.Send = send
	Errors(w)
end)

local function RawAsk(w, from, day)
	assert(w:As(from, from.ns.Arena.Send, "RA", "L", "b~d~" .. from.ns.Arena.B36(day) .. "~", { dist = "CHANNEL" }))
end
test("records: a holder past its answer budget answers no ask, and one asker's asks cannot spend all of it", function()
	for _, case in ipairs({ "budget", "asker" }) do
		local w, a, b, c = Quiet()
		Keys(w, a, b)
		local today = math.floor(w.clock / 86400)
		Take(w, c, Pair(w, a, b, "Kbud1"))
		Take(w, c, Pair(w, a, b, "Kbud2", "1", w.clock - 86400))
		eq(Do(w, c, "Count", "b"), 2)
		w:Logout(a) w:Logout(b) -- (they would hold what c answers, and tell it)
		local one, two = w:Player(N.bettor1), w:Player(N.bettor2)
		Small(one) Small(two)
		local R = c.ns.Records
		if case == "budget" then R.BUDGET = 1 else R.ASKER_JOBS = 1 end
		local turn = R.FALLBACK_MIN + R.FALLBACK_SPREAD_MIN + 1 -- (an army of one: the narrowest fallback spread)
		local function Answers() return #w:Sent({ from = c, type = "RV" }) end
		RawAsk(w, one, today) w:Run(turn)
		eq(Answers(), 1, case .. ": the first job")
		RawAsk(w, one, today - 1) w:Run(turn)
		eq(Answers(), 1, case .. ": no answer past it")
		assert((R.Stats()[case] or 0) >= 1, case .. " counted")
		RawAsk(w, two, today - 1) w:Run(turn)
		eq(Answers(), case == "budget" and 1 or 2, case == "budget" and "the whole budget spent" or "another asker is answered")
		Errors(w)
	end
end)

-- 1.4.0, the validations of one ask. A holder's validation waits on the records' low lane behind
-- its answer's bodies (a message a second, while Comm's queue has room); meanwhile the other
-- holders' validations of that record arrive. It went anyway: every holder that had queued one
-- sent it. Now it is looked at again when its turn comes, and stays home once WITNESSES other
-- holders' validations of that record were heard since the ask; validations heard before the ask
-- silence nothing (the asker may not have taken them).
local function Witnessing(w)
	local a, b, c = w.clients[1], w.clients[2], w.clients[3]
	local h1, h2 = w:Player(STALE[1] .. " Tarrow"), w:Player(STALE[2] .. " Tarrow")
	local body = Pair(w, a, b, "Kwit" .. #w.clients)
	local day = math.floor(w.clock / 86400)
	Keys(w, a, b)
	for _, h in ipairs({ c, h1, h2 }) do Take(w, h, body) end
	-- (Each holder's key, heard by the others: a validation counts only from a sender whose key
	-- this client holds, OnWitness.)
	for _, h in ipairs({ c, h1, h2 }) do assert(Do(w, h, "SendKey")) end
	w:Run(3)
	w:Logout(a) w:Logout(b)
	return c, h1, h2, body, day, w:As(c, c.ns.Records.RecordHash, "b", body)
end
-- c's low lane held (Comm's queue full, as Arena.ROOM reads it) while fn runs.
local function Held(c, fn)
	local size = c.ns.Comm.QueueSize
	c.ns.Comm.QueueSize = function() return 99 end
	local ok, err = pcall(fn)
	c.ns.Comm.QueueSize = size
	if not ok then error(err, 0) end
end
test("records: two validated witnesses can arrive before the record body", function()
	local w = Quiet()
	local _, h1, h2, body, day, hash = Witnessing(w)
	local late = w:Player(N.bettor1)
	local stale = w:Player(STALE[3] .. " Tarrow")
	stale.ns.Records.WITNESS_FRESH = 8
	for _, holder in ipairs({ h1, h2 }) do assert(Do(w, holder, "SendKey")) end
	w:Run(3)
	for _, holder in ipairs({ h1, h2 }) do assert(Do(w, holder, "SendWitness", "b", body, day, true)) end
	w:Run(5)
	eq(Do(w, late, "WitnessesSince", "b", hash, 0), 2, "both witnesses were verified before the body arrived")
	eq(Do(w, late, "Pending", "b"), 0)
	eq(Do(w, late, "Count", "b"), 0, "a witness alone cannot count a record")
	Take(w, late, body)
	eq(Do(w, late, "Count", "b"), 1, "the body is admitted after verifying the players' signatures")
	eq(Do(w, late, "Pending", "b"), 0)
	eq(#w:As(late, late.ns.FarkleTable.Best, "L"), 2)
	eq(Do(w, stale, "WitnessesSince", "b", hash, 0), 2, "the other client also received both validations")
	w:Run(stale.ns.Records.WITNESS_FRESH)
	Take(w, stale, body)
	eq(Do(w, stale, "Count", "b"), 0, "expired validations cannot establish the players' keys")
	eq(Do(w, stale, "Pending", "b"), 1)
	Errors(w)
end)

test("records: a holder whose validation waits on its low lane stays home once two others' validations of that record were heard since the ask", function()
	local w = Quiet()
	local c, h1, h2, body, day, hash = Witnessing(w)
	local late = w:Player(N.bettor1)
	Small(late)
	local R = c.ns.Records
	-- c's digest named that day: c answers the ask first (ANSWER_MIN + score * ANSWER_SPREAD).
	assert(Do(w, c, "SendDigest", "b"))
	w:Run(1)
	local before = #w:Sent({ from = c, type = "RV" })
	local asked
	Held(c, function()
		asked = w.clock
		RawAsk(w, late, day)
		w:Run(R.ANSWER_MIN + R.ANSWER_SPREAD + 1)
		eq(#w:Sent({ from = c, type = "RV" }), before, "c's answer is waiting on its low lane")
		assert(Do(w, c, "OutSize") >= 1, "c's validation is queued")
		-- Meanwhile two other holders' validations of that record arrive.
		for _, h in ipairs({ h1, h2 }) do assert(Do(w, h, "SendWitness", "b", body, day, true)) end
		w:Run(5)
		eq(Do(w, c, "WitnessesSince", "b", hash, asked), 2, "c heard two validations since the ask")
	end)
	w:Run(30)
	eq(Do(w, c, "OutSize"), 0, "c's low lane went")
	eq(#w:Sent({ from = c, type = "RV" }), before, "c's own validation stayed home")
	assert(#w:Sent({ from = c, type = "EP" }) >= 1, "its body went (no copy of it was heard)")
	Errors(w)
end)

-- (A validation still waiting when a newer ask of that record comes answers the newer one: the
-- validations heard since the first ask silence nothing the newer ask needs.)
test("records: a validation still waiting on the low lane when a newer ask comes answers the newer ask", function()
	local w = Quiet()
	local c, h1, h2, body, day = Witnessing(w)
	local late = w:Player(N.bettor1)
	Small(late)
	local R = c.ns.Records
	assert(Do(w, c, "SendDigest", "b"))
	w:Run(1)
	local before = #w:Sent({ from = c, type = "RV" })
	Held(c, function()
		RawAsk(w, late, day)
		w:Run(R.ANSWER_MIN + R.ANSWER_SPREAD + 1)
		for _, h in ipairs({ h1, h2 }) do assert(Do(w, h, "SendWitness", "b", body, day, true)) end
		-- A newer ask once c's answer gap is over, its validation still waiting: c answers it too.
		w:Run(R.ANSWER_GAP + 1)
		RawAsk(w, late, day)
		w:Run(R.ANSWER_MIN + R.ANSWER_SPREAD + 1)
		eq(#w:Sent({ from = c, type = "RV" }), before, "still waiting")
	end)
	w:Run(30)
	eq(#w:Sent({ from = c, type = "RV" }), before + 1, "it went, for the newer ask")
	Errors(w)
end)

test("records: validations heard before an ask never silence a holder's answer to it", function()
	local w = Quiet()
	local c, h1, h2, body, day, hash = Witnessing(w)
	local late = w:Player(N.bettor1)
	Small(late)
	local R = c.ns.Records
	for _, h in ipairs({ h1, h2 }) do assert(Do(w, h, "SendWitness", "b", body, day, true)) end
	w:Run(5)
	eq(Do(w, c, "WitnessesSince", "b", hash, 0), 2, "c heard two validations, before the ask")
	assert(Do(w, c, "SendDigest", "b"))
	w:Run(1)
	local before = #w:Sent({ from = c, type = "RV" })
	Held(c, function()
		RawAsk(w, late, day)
		w:Run(R.ANSWER_MIN + R.ANSWER_SPREAD + 1)
	end)
	w:Run(30)
	eq(#w:Sent({ from = c, type = "RV" }), before + 1, "c validated it for this ask")
	Errors(w)
end)

-- (A review: the validations a holder heard are not the ones the asker took. The asker refuses one
-- whose sender's key it does not hold yet, "witness-key": that sender's key declaration may come
-- after it. The holders that heard two stay silent for that ask; the asker's next ask, later, is
-- answered with fresh validations, and the record counts.)
test("records: validations the asker refused (their senders' keys came after them) leave its next ask answered with fresh ones", function()
	local w = Quiet()
	local c, h1, h2, body, day = Witnessing(w)
	local late = w:Player(N.bettor1)
	Small(late)
	local R = late.ns.Records
	-- The late client holds the body, waiting for its players' keys (they are offline).
	Do(w, late, "Take", "b", body, c.name, "relay") w:Run(3)
	eq(Do(w, late, "Pending", "b"), 1)
	-- Its first ask: every holder's key declaration is lost on its way to it.
	local rk = late.comm.handlers.RK
	late.comm.handlers.RK = function() end
	local first = #w:Sent({ type = "RV" })
	assert(Do(w, late, "AskWitness", "b", day))
	w:Run(R.FALLBACK_MIN + R.FALLBACK_SPREAD_MIN + 5)
	late.comm.handlers.RK = rk
	eq(#w:Sent({ type = "RV" }) - first, R.WITNESSES, "two holders validated it; the third heard them and stayed home")
	eq(Do(w, late, "Pending", "b"), 1, "the asker took neither: their senders' keys were not with it")
	eq((Do(w, late, "Stats").refused["witness-key"] or 0), R.WITNESSES)
	-- Its next ask, once the holders' answer gap is over: fresh validations, and the record counts.
	w:Run(R.ANSWER_GAP)
	local second = #w:Sent({ type = "RV" })
	assert(Do(w, late, "AskWitness", "b", day))
	w:Run(R.FALLBACK_MIN + R.FALLBACK_SPREAD_MIN + 5)
	assert(#w:Sent({ type = "RV" }) - second >= R.WITNESSES, "fresh validations for the new ask")
	eq(Do(w, late, "Count", "b"), 1, "taken")
	eq(Do(w, late, "Pending", "b"), 0)
	Errors(w)
end)

-- (A review's guard, on the late clients' side: with three, five or nine holders and four late
-- clients logging in fifteen minutes apart (each a holder too once it took the records), every
-- late client takes every record, none left waiting, and no ask draws more than three validations
-- of one record, though the bodies queued before them make each holder's validations wait.)
test("records: three, five or nine holders and four late clients fifteen minutes apart: every late client takes all, with three validations of a record an ask at most", function()
	for _, holders in ipairs({ 3, 5, 9 }) do
		local w, a, b, empty = Setup()
		w:Logout(empty)
		local list = {}
		for i = 1, holders do list[i] = w:Player(STALE[i] .. " Tarrow") end
		Keys(w, a, b)
		local bodies = {}
		for i = 1, 4 do bodies[i] = Pair(w, a, b, "Kguard" .. holders .. "x" .. i) end
		for _, h in ipairs(list) do for _, body in ipairs(bodies) do Take(w, h, body) end end
		w:Logout(a) w:Logout(b)
		local R = list[1].ns.Records
		local lates = {}
		for i, name in ipairs({ N.bettor1, N.bettor2, STALE[10] .. " Tarrow", STALE[11] .. " Tarrow" }) do
			lates[i] = w:Player(name)
			w:Run(900)
		end
		for i, late in ipairs(lates) do
			eq(Do(w, late, "Count", "b"), #bodies, holders .. " holders: late client " .. i .. " took every record")
			eq(Do(w, late, "Pending", "b"), 0, holders .. " holders: late client " .. i .. " has none waiting")
		end
		-- Each validation answers the newest ask of its record's day before it.
		local asks = {}
		for _, s in ipairs(w:Sent({ type = "RA" })) do asks[#asks + 1] = s end
		local per = {}
		for _, s in ipairs(w:Sent({ type = "RV" })) do
			local hash = s.msg:match("^RV~L1~b~(%x+)~")
			local ask
			for i, q in ipairs(asks) do if q.t <= s.t then ask = i end end
			assert(ask, "a validation answers an ask")
			local k = ask .. ":" .. hash
			per[k] = (per[k] or 0) + 1
			assert(per[k] <= 3, ("%d holders: %d validations of one record for one ask"):format(holders, per[k]))
		end
		Errors(w)
	end
end)

-- 1.4.0, the asks a digest sets off. Every client that heard a digest lacking what it told asked at
-- once: a hundred late clients, a hundred asks of one day, and as many answers waiting on each
-- holder. Each ask now waits its turn (score × ASK_SPREAD) and stays home when an ask heard
-- meanwhile asked for all it would: the answers go on the channel, to everyone. The bound: one
-- ask, and those whose turns came within the delay from a turn to the wire (L: here the arena
-- ticker's period, Arena.TICK) of it.
local function Asks(w, day)
	local n, tag = 0, "~b~d~" .. day .. "~"
	for _, s in ipairs(w:Sent({ type = "RA" })) do if s.msg:find(tag, 1, true) then n = n + 1 end end
	return n
end
-- (Forty clients here, a full client each: the scale runs are tests/arena/records-load.lua's.)
test("records: forty empty clients that hear one digest ask for its day once, within the transport's delay, and every one of them takes the answer", function()
	local w, a, b, c = Quiet()
	local body = Pair(w, a, b, "Kmany1")
	local day = c.ns.Arena.B36(math.floor(w.clock / 86400))
	Take(w, c, body)
	local lates = {}
	for i = 1, 40 do lates[i] = w:Player(("Late%03d Tarrow"):format(i)) Small(lates[i]) end
	-- (The players' keys, heard first-hand by every client: the answer's body alone admits it.)
	Keys(w, a, b)
	local R = c.ns.Records
	assert(Do(w, c, "SendDigest", "b"))
	w:Run(R.ASK_SPREAD + 2)
	local bound = 1 + math.ceil(#lates * c.ns.Arena.TICK / R.ASK_SPREAD)
	local asks = Asks(w, day)
	assert(asks >= 1 and asks <= bound, ("asks of that day: %d, bound %d"):format(asks, bound))
	for i, late in ipairs(lates) do
		local merged = Do(w, late, "Stats").askMerged or 0
		eq(merged + #w:Sent({ from = late, type = "RA" }), 1, "late client " .. i .. ": its ask went, or merged with one heard")
	end
	w:Run(R.ANSWER_MIN + R.ANSWER_SPREAD + 60)
	for i, late in ipairs(lates) do eq(Do(w, late, "Count", "b"), 1, "late client " .. i .. " took the answer to the one ask") end
	eq(Asks(w, day), asks, "nobody asked again")
	Errors(w)
end)

-- (Merged only when the heard ask asked for all ours would: one that named a record this client
-- lacks (its asker holds it) brings no copy of it, and ours goes.)
test("records: an ask heard that named a record this client lacks never merges its own", function()
	local w, a, b, c = Quiet()
	local r1, r2 = Pair(w, a, b, "Kmerge1"), Pair(w, a, b, "Kmerge2")
	local day = c.ns.Arena.B36(math.floor(w.clock / 86400))
	local d = math.floor(w.clock / 86400)
	local one, two = w:Player(N.bettor1), w:Player(N.bettor2)
	Small(one) Small(two)
	Keys(w, a, b)
	Take(w, c, r1) Take(w, c, r2)
	local R = c.ns.Records
	-- The client whose turn comes first holds r1; the other holds nothing.
	local round = math.floor(w.clock / R.DIGEST_EVERY)
	local function Turn(x) return w:As(x, R.Score, "RA|b|" .. d .. "|" .. round, x.name) end
	local first, second = one, two
	if Turn(two) < Turn(one) then first, second = two, one end
	Take(w, first, r1)
	eq(Do(w, first, "Count", "b"), 1) eq(Do(w, second, "Count", "b"), 0)
	w:Logout(a) w:Logout(b) -- (they hold nothing: their asks, naming nothing, would merge both)
	assert(Do(w, c, "SendDigest", "b"))
	w:Run(R.ASK_SPREAD + 2)
	eq(#w:Sent({ from = first, type = "RA" }), 1, "the first asked, naming r1")
	eq(#w:Sent({ from = second, type = "RA" }), 1, "the second asked too: the first's ask named r1, which it lacks")
	w:Run(R.ANSWER_MIN + R.ANSWER_SPREAD + R.ANSWER_GAP + 60)
	eq(Do(w, second, "Count", "b"), 2, "the second holds both")
	eq(Do(w, first, "Count", "b"), 2, "the first holds both")
	Errors(w)
end)

-- (The pushes: a digest that lacks what many holders hold made every holder that heard it push its
-- own, when drawn (a draw of 0: all of them). Each now has a slot, PUSH_MIN + score × PUSH_WINDOW,
-- and stays home once ELECT digests heard since told all its own would.)
-- (A guard of the bound, not of a fault seen here: the harness delivers at once, and the first push
-- heard silenced the old draw's other pushes too. In the game the delay from a turn to the wire let
-- every drawn holder's push go.)
test("records: twelve holders that hold what a digest lacks push at most a few digests back in a push gap", function()
	local w, a, b, empty = Setup()
	w:Logout(empty)
	local holders = {}
	for i = 1, 12 do holders[i] = w:Player(("Hold%02d Tarrow"):format(i)) Small(holders[i]) end
	local lacking = w:Player(N.bettor1)
	Small(lacking)
	local common, extra = Pair(w, a, b, "Kpushes1"), Pair(w, a, b, "Kpushes2")
	Keys(w, a, b)
	for _, h in ipairs(holders) do Take(w, h, common) Take(w, h, extra) end
	Take(w, lacking, common)
	w:Logout(a) w:Logout(b)
	Draws(w) -- (a draw of 0, where one is still made: every holder drawn)
	local R = lacking.ns.Records
	-- Past the holders' own push gap (their digests of a moment ago, none: they took the records
	-- without telling), the lacking client's digest.
	local start = w.clock
	assert(Do(w, lacking, "SendDigest", "b"))
	w:Run(R.PUSH_GAP - 1)
	local pushes = 0
	for _, h in ipairs(holders) do
		for _, s in ipairs(w:Sent({ from = h, type = "RD" })) do if s.t >= start then pushes = pushes + 1 end end
	end
	local bound = R.ELECT + math.ceil(#holders * lacking.ns.Arena.TICK / R.PUSH_WINDOW) + 1
	assert(pushes >= 1 and pushes <= bound, ("pushes in a push gap: %d, bound %d"):format(pushes, bound))
	Errors(w)
end)

-- 1.4.0, discovery (RH). A client that holds nothing sends nothing at its login (the weight rule,
-- above): it waited for the holders' next round, up to a round and its window. The first time the
-- player opens a ranking view in a session it asks for the holders' digests of the types it heard
-- none of (Records.Discover), once, and once more DISCOVERY_RETRY later if still none came; each
-- holder answers with a reply round of its own, as a round's digest. The bound: the reply round's
-- window, the ask's turn, the answer's turn and its pieces on Comm's pace (critique: the bodies go in
-- parts, a message a PACE).
local function DiscoveryBound(R, window) return R.DISCOVERY_MIN + window + R.ASK_SPREAD + R.ANSWER_MIN + R.ANSWER_SPREAD + 30 * H.World.PACE end
local function RHs(w, from)
	local out = {}
	for _, s in ipairs(w:Sent({ from = from, type = "RH" })) do out[#out + 1] = s end
	return out
end
local function Timers(w, c, where)
	local n = 0
	for _, t in ipairs(w:Timers(c, true)) do if t.where == where then n = n + 1 end end
	return n
end
test("records: a late client that opens a ranking view asks once for the holders' digests, arms one retry, and holds the records within the reply round's bound", function()
	local w, a, b, c = Quiet()
	local second = w:Player(STALE[1] .. " Tarrow")
	Small(second)
	local body = Pair(w, a, b, "Kfind1")
	Keys(w, a, b)
	Take(w, c, body) Take(w, second, body)
	w:Logout(a) w:Logout(b)
	local late = w:Player(N.bettor1)
	Small(late)
	local R = late.ns.Records
	w:Run(30)
	eq(#RHs(w, late), 0, "nothing at its login (the weight rule)")
	eq(Do(w, late, "Count", "b"), 0)
	local opened = w.clock
	eq(Do(w, late, "Discover"), true, "the first view of the session asks")
	w:Run(2)
	eq(#RHs(w, late), 1, "one ask")
	eq(Timers(w, late, "records discovery"), 1, "one retry armed after the ask leaves")
	assert(RHs(w, late)[1].msg:match("^RH~L1~1~bcd~[0-9a-z]+%.1$"), "every unheard type and the first bounded attempt")
	eq(Do(w, late, "Discover"), false, "a second view asks nothing")
	local bound = DiscoveryBound(R, w:As(c, c.ns.Records.DigestWindow))
	local heldAt = RunUntil(w, bound, function() return Do(w, late, "Count", "b") == 1 end, 1)
	assert(heldAt, ("the late client holds it within %d s of opening the view"):format(bound))
	assert(heldAt - opened <= bound)
	eq(Do(w, late, "Pending", "b"), 0)
	assert(#w:Sent({ from = c, type = "RD" }) + #w:Sent({ from = second, type = "RD" }) >= 1, "a holder's reply round went")
	w:Run(R.DISCOVERY_RETRY + 30)
	assert(#RHs(w, late) <= R.DISCOVERY_MAX, "at most DISCOVERY_MAX asks a session")
	assert(Do(w, late, "StatusText"):find("discovery asks sent " .. #RHs(w, late), 1, true), "the records pop-up counts the asks sent")
	Errors(w)
end)

test("records: a ranking view asks only for the types this session heard no digest of, and never while quiet presence is on", function()
	local w, a, b, c = Quiet()
	local body = Pair(w, a, b, "Kfind2")
	Keys(w, a, b)
	Take(w, c, body)
	local king = w:Player(N.king, { guild = H.World.KING_GUILD, rank = 0 })
	local late = w:Player(N.bettor1)
	Small(late) Small(king)
	-- The late client heard a Bones digest this session: it asks for the other types alone.
	assert(Do(w, c, "SendDigest", "b"))
	w:Run(2)
	eq(Do(w, late, "Discover"), true)
	w:Run(2)
	assert(RHs(w, late)[1].msg:match("^RH~L1~1~cd~[0-9a-z]+%.1$"), "Bones heard: not asked")
	-- A King whose quiet presence is on asks nothing (an ask says he is online); once it is off, he does.
	eq(w:As(king, king.ns.SetQuietPresence, true, "records-test"), true)
	eq(Do(w, king, "Discover"), false)
	w:Run(king.ns.Records.DISCOVERY_RETRY + 30)
	eq(#RHs(w, king), 0, "no ask while his quiet presence is on")
	eq(w:As(king, king.ns.SetQuietPresence, false, "records-test"), true)
	eq(Do(w, king, "Discover"), true)
	w:Run(2)
	eq(#RHs(w, king), 1, "his ask, once it is off")
	Errors(w)
end)

-- (One reply round of a type a DISCOVERY_GAP on each holder, whoever asked: fifty asks in a minute
-- are one round. The author's character answers none; the King's slot comes after the widest round,
-- and two other holders' digests leave his at home.)
test("records: fifty discovery asks within a minute start one reply round of a type on each holder; the author never replies, the King not first", function()
	local w, a, b, empty = Quiet()
	local author = w:Player(N.author)
	local king = w:Player(N.king, { guild = H.World.KING_GUILD, rank = 0 })
	TellBorders(w)
	local holders = { w:Player(STALE[1] .. " Tarrow"), w:Player(STALE[2] .. " Tarrow"), author, king }
	for _, h in ipairs(holders) do Small(h) end
	local body = Pair(w, a, b, "Kfind3")
	Keys(w, a, b)
	for _, h in ipairs(holders) do Take(w, h, body) end
	w:Logout(a) w:Logout(b)
	Small(empty)
	local R = empty.ns.Records
	local start = w.clock
	for i = 1, 50 do
		assert(w:As(empty, empty.ns.Arena.Send, "RH", "L", "1~b", { dist = "CHANNEL" }))
		w:Run(59 / 50)
	end
	w:Run(R.DISCOVERY_MIN + R.DIGEST_WINDOW_MAX + R.KING_AFTER + 2 - (w.clock - start))
	for _, h in ipairs(holders) do
		eq(w:As(h, h.ns.Records.Stats).replyRounds or 0, (h == author) and 0 or 1, h.name .. ": reply rounds of Bones")
	end
	local first = w:Sent({ type = "RD" })
	assert(first[1] and first[1].client ~= king and first[1].client ~= author, "an ordinary holder replied first")
	eq(#w:Sent({ from = author, type = "RD" }), 0, "the author's client never replies")
	eq(#w:Sent({ from = king, type = "RD" }), 0, "two other holders' digests told all his would: his stayed home")
	assert(#w:Sent({ type = "RD" }) <= R.ELECT + 1, "about ELECT digests for the round")
	Errors(w)
end)

-- (Where the views ask: the Games tab, only where the member sees the rankings (the staff always,
-- everyone once the King shows them); the crafting ranking's board.)
test("records: the Games tab asks for digests only where the member sees the rankings", function()
	local w = H.World.New({ compliance = "shipped" })
	local member = w:Client(N.bettor1)
	local king = w:Role("king")
	Small(member) Small(king)
	w:Run(5)
	eq(w:As(member, member.ns.ArenaHome.RankingsPublic), false, "the rankings are not shown to members yet")
	w:As(member, member.ns.ArenaHome.TabLines)
	w:Run(2)
	eq(#RHs(w, member), 0, "a member who sees no ranking asks nothing")
	w:As(king, king.ns.ArenaHome.TabLines)
	w:Run(2)
	eq(#RHs(w, king), 1, "the staff see them: the King's view asks")
	w:As(king, king.ns.ArenaHome.TabLines)
	w:Run(2)
	eq(#RHs(w, king), 1, "a refresh asks nothing more")
	Errors(w)
end)

test("1.2.4 records: the duel adapter preserves GUID identity checks and adds a verified relayed result to ordinary rankings", function()
	local w, a, b, c = Setup()
	for _, client in ipairs(w.clients) do
		client.globals.GetPlayerInfoByGUID = function(guid)
			for _, named in ipairs(w.clients) do if named.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, named.short, named.realm end end
		end
	end
	local halves = {}
	for side, client in ipairs({ a, b }) do
		halves[side] = w:As(client, function()
			local A, D = client.ns.Arena, client.ns.Debts
			local core = table.concat({ "Fr11", side == 1 and "A" or "B", A.GK(a.guid), a.name, A.GK(b.guid), b.name, "1", "A", "A", "K", "AK" .. A.B36(20), A.B36(w.clock), "-", "60", "60" }, "~")
			local _, pk = D.MyKey() return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYH1|" .. core))
		end)
	end
	Keys(w, a, b)
	Do(w, c, "Take", "d", halves[1] .. "^" .. halves[2], N.bettor1, "relay") w:Run(3)
	eq(Do(w, c, "Count", "d"), 1)
	local entries = w:As(c, c.ns.ArenaLedger.Entries) eq(#entries, 1) eq(entries[1].fl, "dr")
	eq(#w:As(c, c.ns.ArenaLedger.RecordMonth, Do(w, c, "MonthOf", w.clock)), 2)
	w:Logout(c) w:Login(c) w:Run(15) eq(Do(w, c, "Count", "d"), 1)
	Errors(w)
end)

-- 1.4.0: a duel taken through Records is kept at its own time (keptAt = its time: the 1.2.3 rule,
-- LG.Counted), and its wait for the game's word on its fighters' GUIDs (GK_WAIT) was counted from
-- keptAt too. A duel relayed to a client more than GK_WAIT after it was fought was never looked at
-- again: it stayed history alone ("d"), out of every ranking, though the game knew both fighters a
-- moment later. The wait now counts from when this client took it (waitAt); keptAt is unchanged.
local function DuelEntry(w, c)
	local entries = w:As(c, c.ns.ArenaLedger.Entries)
	eq(#entries, 1)
	return entries[1]
end
local function DuelRows(w, c)
	return #w:As(c, c.ns.ArenaLedger.RankingView, "all", "A").rows
end
test("records: a duel relayed 20 minutes after it was fought is rated once the game knows its fighters, its place in the limits unchanged", function()
	local w, a, b, c = Setup()
	local body = DuelPair(w, a, b, "Frwait1")
	local fought = w.clock
	Keys(w, a, b)
	w:Run(1200 - 3)
	Do(w, c, "Take", "d", body, N.bettor1, "relay") w:Run(3)
	eq(Do(w, c, "Count", "d"), 1)
	local e = DuelEntry(w, c)
	eq(e.fl, "d", "the game does not know its fighters yet: history alone")
	eq(e.wait, "r")
	eq(e.keptAt, fought, "the 1.2.3 rule: a relayed duel is kept at its own time")
	eq(DuelRows(w, c), 0)
	w:Run(300)
	EnableGuidLookup(w)
	w:Run(c.ns.ArenaLedger.GK_RECHECK + 5)
	e = DuelEntry(w, c)
	eq(e.fl, "dr", "rated once the game names both fighters")
	eq(e.wait, nil)
	eq(e.keptAt, fought, "its place in the day's and the pair's limits is still its own time")
	eq(DuelRows(w, c), 2, "both fighters in the ranking view")
	Errors(w)
end)

test("records: a duel relayed within GK_WAIT of its fight is still rated once the game knows its fighters", function()
	local w, a, b, c = Setup()
	local body = DuelPair(w, a, b, "Frwait2")
	Keys(w, a, b)
	w:Run(300)
	Do(w, c, "Take", "d", body, N.bettor1, "relay") w:Run(3)
	eq(DuelEntry(w, c).fl, "d")
	w:Run(300)
	EnableGuidLookup(w)
	w:Run(c.ns.ArenaLedger.GK_RECHECK + 5)
	eq(DuelEntry(w, c).fl, "dr")
	eq(DuelRows(w, c), 2)
	Errors(w)
end)

-- (1.4.0) A duel still waiting when its window ends gets a new one in each later session, once a
-- session, GK_SESSIONS windows at most: the game may know its fighters then.
test("records: a duel still waiting for its fighters' GUIDs is looked at again in a later session, in GK_SESSIONS windows at most", function()
	local w, a, b, c = Setup()
	local LG = c.ns.ArenaLedger
	Keys(w, a, b)
	Do(w, c, "Take", "d", DuelPair(w, a, b, "Frwait3"), N.bettor1, "relay") w:Run(3)
	eq(DuelEntry(w, c).waits, 1, "its first window")
	w:Run(LG.GK_WAIT + 60)
	w:Logout(c) w:Login(c) w:Run(3)
	eq(DuelEntry(w, c).waits, 2, "a new window in the next session")
	-- (Once a session: the companion loading later in that session renews nothing more.)
	w:Run(LG.GK_WAIT + 60)
	w:As(c, c.ns.Fire, "ARENA_UI_LOADED") w:Run(3)
	eq(DuelEntry(w, c).waits, 2, "one window a session")
	w:Logout(c) w:Login(c) w:Run(3)
	EnableGuidLookup(w)
	w:Run(LG.GK_RECHECK + 5)
	local e = DuelEntry(w, c)
	eq(e.fl, "dr", "rated in a later session once the game knows its fighters")
	eq(e.waits, 3)
	Errors(w)

	-- Past GK_SESSIONS windows it waits no more: history alone, until its halves are heard again.
	w, a, b, c = Setup()
	LG = c.ns.ArenaLedger
	Keys(w, a, b)
	Do(w, c, "Take", "d", DuelPair(w, a, b, "Frwait4"), N.bettor1, "relay") w:Run(3)
	for i = 2, LG.GK_SESSIONS do
		w:Run(LG.GK_WAIT + 60)
		w:Logout(c) w:Login(c) w:Run(3)
		eq(DuelEntry(w, c).waits, i)
	end
	w:Run(LG.GK_WAIT + 60)
	w:Logout(c) w:Login(c) w:Run(3)
	EnableGuidLookup(w)
	w:Run(LG.GK_RECHECK + 5)
	e = DuelEntry(w, c)
	eq(e.waits, LG.GK_SESSIONS, "no window past the last")
	eq(e.fl, "d"); eq(e.wait, "r")
	Errors(w)
end)

-- 1.4.0: a crafting delivery's record was dated at noon UTC of its day (day * 86400 + 43200), and
-- Records refuses a record dated more than AHEAD (two minutes) past the clock ("time"). Every
-- delivery made before 11:58 UTC (before 08:58 in Brasilia) was refused by every client, its own
-- signers' too, and never reached the crafting ranking. It is dated at the start of its day now:
-- its day, id, content and month are the same, so clients of either version agree on it.
test("records: a crafting delivery made before noon UTC is taken and counts in the crafting ranking", function()
	local early = math.floor(H.World.CLOCK / 86400) * 86400 + 3 * 3600 -- 03:00 UTC
	local w, requester, crafter, holder = Setup(early)
	local body = CraftPair(w, requester, crafter, "craftearly1", 123, 5, 2)
	Keys(w, requester, crafter)
	local ok, why = Do(w, holder, "Take", "c", body, N.bettor1, "relay")
	w:Run(3)
	eq(Do(w, holder, "Count", "c"), 1, "taken: " .. tostring(ok) .. " " .. tostring(why))
	eq((Do(w, holder, "Stats").refused.time or 0), 0, "never refused as dated ahead of the clock")
	local rec = w:As(holder, holder.ns.CraftRanking.ReadRecord, body)
	eq(rec.t, math.floor(early / 86400) * 86400, "dated at the start of its day")
	eq(math.floor(rec.t / 86400), math.floor(early / 86400), "its day unchanged")
	local rows = w:As(holder, holder.ns.CraftRanking.Current)
	eq(#rows, 1); eq(rows[1].name, crafter.name); eq(rows[1].deliveries, 1)
	Errors(w)
end)


test("1.5.2 records: a temporarily refused discovery send does not consume the first view", function()
	local w, a, b, c = Quiet()
	local send = c.ns.Arena.Send
	c.ns.Arena.Send = function(kind, ...) if kind == "RH" then return false end return send(kind, ...) end
	eq(Do(w, c, "Discover"), false)
	eq(Timers(w, c, "records discovery"), 0)
	c.ns.Arena.Send = send
	eq(Do(w, c, "Discover"), true, "reopening can try once transport recovers")
	w:Run(2)
	eq(#RHs(w, c), 1)
	Errors(w)
end)

test("records: a discovery accepted by the queue but dropped can be retried on reopening", function()
	local w, _, _, asker = Quiet()
	local send = asker.ns.Arena.Send
	local finish
	asker.ns.Arena.Send = function(kind, mode, body, opts)
		if kind ~= "RH" then return send(kind, mode, body, opts) end
		finish = opts.done
		return true
	end
	eq(Do(w, asker, "Discover"), true)
	eq(Do(w, asker, "Discover"), false, "one in flight")
	eq(Timers(w, asker, "records discovery"), 0, "admission does not arm a retry")
	assert(type(finish) == "function", "transport reports completion")
	w:As(asker, finish, false, "dropped")
	asker.ns.Arena.Send = send
	eq(Do(w, asker, "Discover"), true, "reopening retries a dropped ask")
	w:Run(2)
	eq(#RHs(w, asker), 1)
	assert(RHs(w, asker)[1].msg:match("%.1$"), "only the completed send consumes the first attempt")
	Errors(w)
end)

test("1.5.2 records: the bounded retry reaches a holder through the real relay while duplicate copies count once", function()
	local w, _, _, asker = Quiet()
	eq(Do(w, asker, "Discover"), true)
	w:Run(asker.ns.Records.DISCOVERY_RETRY + 2)
	local asks = RHs(w, asker)
	eq(#asks, 2, "only the initial request and one retry")
	local holder = w:Player(N.bettor1)
	local C = holder.ns.Comm
	-- The world normally models Comm directly. Use the production Relay's receiver and
	-- dedupe here; only Comm's delivery boundary/fragment registration are stand-ins.
	C.RelayPieces = function() end
	C.Inject = function(dist, sender, text)
		local handler = holder.comm.handlers[text:sub(1, 2)]
		if handler then handler(dist, sender, text) end
	end
	w:As(holder, function()
		holder.ns.splitNames = true
		holder.ns.rdb.council = { names = { relay = N.king } }
		assert(loadfile(H.ADDON_DIR .. "Relay.lua"))("Olympus", holder.ns)
		holder.ns.Relay.HandleRelayed("WHISPER", N.king, "RM~P~" .. asker.name .. "~" .. asks[1].msg)
	end)
	eq(Do(w, holder, "Stats").discoveryHeard, 1)
	w:Run(asker.ns.Records.DISCOVERY_RETRY)
	w:As(holder, holder.ns.Relay.HandleRelayed, "WHISPER", N.king, "RM~P~" .. asker.name .. "~" .. asks[2].msg)
	eq(Do(w, holder, "Stats").discoveryHeard, 2, "the retry is not swallowed by Relay.SEEN_FOR")
	w:As(holder, holder.ns.Relay.HandleGuild, "GUILD", N.fighterA, "RG~P~" .. asker.name .. "~" .. asks[2].msg)
	eq(Do(w, holder, "Stats").discoveryHeard, 2, "another hop's copy stays deduplicated")
	Errors(w)
end)

test("1.5.2 records: discovery accepts legacy asks and bounded attempt tags, rejecting malformed tags", function()
	local w, asker, _, holder = Quiet()
	local receive = holder.comm.handlers.RH
	for _, tag in ipairs({ "", "1.0", "1.3", "1.1~extra", string.rep("a", 13) .. ".1" }) do
		w:As(holder, receive, "CHANNEL", asker.name, "RH~L1~1~b~" .. tag)
	end
	eq(Do(w, holder, "Stats").discoveryHeard or 0, 0)
	w:As(holder, receive, "CHANNEL", asker.name, "RH~L1~1~b")
	w:As(holder, receive, "CHANNEL", asker.name, "RH~L1~1~b~t123.2")
	eq(Do(w, holder, "Stats").discoveryHeard, 2, "old and tagged requests use the same reply budgets")
	Errors(w)
end)
