local _, ns = ...
local R = { MEMBERS = 1000, BOUNDARY = 90, PART = 5600, PARTS = 48, TEXT = 200000,
	KEEP = 5, SNAPSHOTS = 256, ISSUERS = 128, JOBS = 4, TTL = 86400, OPT_FOR = 31 * 86400 }
ns.DuesRosterCheckpoints = R
local T, D, A, E = ns.Treasury, ns.Dues, ns.Authority, ns.Ed25519
local incoming, verified, keys, permits, asked, stream, lastSeen = {}, {}, {}, {}, {}, nil, nil
local jobs, nextPump = 0, 0
local boundaryTicker, pageTicker, waking
local signing = {} -- actual in-flight jobs only, never a persisted promise of a signature
local function Clock() return math.floor(GetServerTime and GetServerTime() or ns.Now()) end
local function Whole(n, max) return type(n) == "number" and n == n and n % 1 == 0 and n >= 0 and n <= (max or 4294967295) end
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Name(s)
	if type(s) ~= "string" or s == "" or #s > 96 or s:find("[~|^;%c]") then return nil end
	local n = ns.FullName(ns.Normal(s))
	return type(n) == "string" and #n <= 96 and ns.RealmOf(n) and n or nil
end
local function Same(a, b) return Name(a) and Name(b) and Name(a):lower() == Name(b):lower() end
local function Guild(s) return type(s) == "string" and #s <= 72 and s ~= "" and not s:find("[~|^;%c]") and ns.IsFederation(s) and D.MandatoryGuild(s) end
local function Digest(s) return E.ToHex(ns.Sign.SHA256(s)) end
local function Raw(s, n)
	local ok, v = pcall(E.FromB64, s or "")
	return ok and type(v) == "string" and #v == n and v or nil
end
local function Safe()
	local V, K, M, W = ns.ViewAs, ns.King, ns.Moderation, ns.WatchChat
	return ns.IsMember() == true and not (V and V.Previewing and V.Previewing())
		and not (K and K.Preview and K.Preview()) and not (M and M.SelfOff and M.SelfOff())
		and not (W and W.Barred and W.Barred("powers", ns.me))
end
local function Blocked(name, guild)
	local M, W = ns.Moderation, ns.WatchChat
	return M and M.Hides and M.Hides(name, guild) or W and W.Barred and W.Barred("powers", name)
end
local function NativeGM()
	local roster = Safe() and ns.Roster and ns.Roster.Fresh(R.BOUNDARY)
	local guild, _, rank = GetGuildInfo("player")
	return roster and roster.complete and rank == 0 and ns.Roster.RankOf(ns.me) == 0 and Guild(guild) and guild or nil
end
local function Master(name, guild)
	if not Name(name) or not Guild(guild) or Blocked(name, guild) then return false end
	local rank, source = A.Rank(Name(name), guild)
	return rank == 0 and source == "signed"
end
function R.CurrentGM(guild)
	local manifest = A.Manifest()
	for _, p in pairs(manifest and manifest.people or {}) do
		if p.guild == guild and p.rank == 0 and Master(p.name, guild) then return p.name end
	end
end
local function Keeper() return Safe() and ns.DuesGrace and type(ns.DuesGrace.Keeper) == "function" and ns.DuesGrace.Keeper() end
local function Primary()
	local name = ns.TreasurerFull and ns.TreasurerFull() -- (1.3.4: the signed list's Treasurer where it names one)
	return Name(name)
end
local function Identity() return table.concat({ ns.me, GetGuildInfo("player") or "", ns.group or "", ns.faction or "" }, "|") end
local function Store(make)
	if type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.duesRosterCheckpoints
	if s == nil and make ~= false then
		s = { version = 1, scope = ns.group .. "|" .. ns.faction, own = {}, received = {}, floors = {}, keys = {}, amounts = {} }
		ns.rdb.duesRosterCheckpoints = s
	end
	if type(s) ~= "table" or s.version ~= 1 or s.scope ~= ns.group .. "|" .. ns.faction then return nil end
	for _, field in ipairs({ "own", "received", "floors", "keys", "amounts" }) do if type(s[field]) ~= "table" then return nil end end
	return s
end
local function Run(fn, done)
	if jobs >= R.JOBS then return false end
	jobs = jobs + 1
	local finished = false
	local queued = E.Run(fn, function(ok, result) if finished then return end; finished = true; jobs = jobs - 1; done(ok and result or nil) end)
	if not queued and not finished then finished = true; jobs = jobs - 1 end
	return queued == true
end
local function Option(s, guild)
	local o = s and s.own[guild]
	return type(o) == "table" and Same(o.actor, ns.me) and type(o.on) == "boolean" and type(o.snapshots) == "table"
		and Whole(o.revision) and o.revision > 0 and Whole(o.expires) and o or nil
end
function R.Sharing()
	local guild = NativeGM(); local o = guild and Option(Store(false), guild)
	return o and o.on == true and Clock() <= o.expires or false
end
local function Source(c)
	if type(c) ~= "table" or not Name(c.issuer) or not Guild(c.guild) or not Whole(c.revision) or c.revision < 1
		or not Whole(c.expires) or not Whole(c.week, 1000000) or not Whole(c.at)
		or c.scope ~= ns.group or c.faction ~= ns.faction or not ({ B = true, E = true, X = true })[c.kind] then return false end
	local s = Store(); local o = s and Option(s, c.guild)
	return Safe() and c.identity == Identity() and NativeGM() == c.guild and Master(ns.me, c.guild)
		and Same(c.issuer, ns.me) and o and o.revision == c.revision and Clock() <= c.expires
		and (c.kind == "X" and o.on == false or c.kind ~= "X" and o.on == true) or false
end
local function WireSnapshot(c)
	return type(c) == "table" and type(c.text) == "string" and #c.text <= R.TEXT
		and type(c.wire) == "string" and #c.wire <= R.PART * R.PARTS and c.wire:match("^[%w_-]+$")
		and type(c.root) == "string" and #c.root == 64 and c.root:match("^[a-f0-9]+$")
		and Raw(c.pk, 32) and Raw(c.claim, 64) and Raw(c.sig, 64) and type(c.guid) == "string" and #c.guid <= 64
end
local function CheckKey(sender, guild, guid, pk64, sig64, done)
	local pk, sig = Raw(pk64, 32), Raw(sig64, 64)
	if not Keeper() or not Master(sender, guild) or not pk or not sig or not ns.Debts.Bind(sender, guid) or jobs >= R.JOBS then return false end
	local s, identity = Store(), Identity(); if not s then return false end
	local old = s.keys[Name(sender):lower()]
	if old and (type(old) ~= "table" or old.pk ~= pk64 or old.guid ~= guid) then return false end -- no unattended key replacement
	if not old and Count(s.keys) >= R.ISSUERS then return false end
	jobs = jobs + 1
	local finished = false
	local queued = ns.Arena.Check("dues-roster-key:" .. sender .. ":" .. Digest(pk64 .. sig64),
		{ pk = pk, sig = sig, msg = "OLYA1|" .. guid .. "|" .. sender }, function(good)
			if finished then return end; finished = true; jobs = jobs - 1
			if good and identity == Identity() and Keeper() and Master(sender, guild) and ns.Debts.Bind(sender, guid) then
				local k = { guid = guid, guild = guild, pk = pk64, sig = sig64, original = sender }
				s.keys[Name(sender):lower()], keys[Name(sender):lower()] = k, k
				for _, c in pairs(s.received) do if type(c) == "table" and c.issuer == sender and c.root then asked[c.root] = nil end end
				R.RecheckSaved()
				if done then done(k) end
			end
		end)
	if queued == false and not finished then finished = true; jobs = jobs - 1 end
	return queued ~= false
end
-- Minimal complete native observations. Alt groups store one main per name rather than
-- repeating an N-name group N times. No levels, zones, notes, or online list are shared.
function R.NativeRows()
	local roster = NativeGM() and ns.Roster.Fresh(R.BOUNDARY)
	local total = GetNumGuildMembers and tonumber((GetNumGuildMembers()))
	if not roster or not Whole(total, R.MEMBERS) or total < 1 or #roster.members ~= total then return nil end
	local members, rows = {}, {}
	for _, m in ipairs(roster.members) do
		local n = Name(m.raw or m.name); if not n or members[n:lower()] then return nil end
		members[n:lower()] = n
	end
	for _, n in pairs(members) do
		local main = ns.Alts and ns.Alts.Person and Name(ns.Alts.Person(n)) or n
		if not main or not members[main:lower()] then main = n end
		rows[#rows + 1] = n .. "^" .. main
	end
	table.sort(rows)
	return #rows == total and rows or nil
end
function R.Text(c)
	if type(c) ~= "table" or c.scope ~= ns.group or c.faction ~= ns.faction or Name(c.issuer) ~= c.issuer or not Guild(c.guild)
		or not Whole(c.week, 1000000) or not Whole(c.at) or not Whole(c.revision) or c.revision < 1 or not Whole(c.expires)
		or c.expires < c.at or c.expires - c.at > R.OPT_FOR or type(c.guid) ~= "string" or #c.guid < 1 or #c.guid > 64 or c.guid:find("[^%w%-]")
		or not ({ B = true, E = true, X = true })[c.kind] or type(c.proof) ~= "table" or c.proof.realm ~= c.scope
		or not ({ HA = true, HT = true })[c.proof.kind] or type(c.proof.blobs) ~= "table" or #c.proof.blobs < 1 or #c.proof.blobs > A.MAX_PARTS
		or type(c.rows) ~= "table" or #c.rows > R.MEMBERS or c.kind == "X" and #c.rows ~= 0 then return nil end
	local expected = D.WeekStart(c.week + (c.kind == "E" and 1 or 0))
	if c.kind ~= "X" and (#c.rows == 0 or c.at < expected or c.at > expected + R.BOUNDARY) then return nil end
	local lines = { table.concat({ "DR1", c.scope, c.faction, c.issuer, c.guild, c.week, c.kind, c.at, c.revision, c.expires,
		c.guid, c.proof.kind, #c.proof.blobs, #c.rows }, "~") }
	for _, blob in ipairs(c.proof.blobs) do if type(blob) ~= "string" or blob:find("[\r\n]") or #blob > A.MAX_PART_TEXT then return nil end; lines[#lines + 1] = blob end
	local names, mains, last = {}, {}, nil
	for _, row in ipairs(c.rows) do
		if type(row) ~= "string" or last and row <= last then return nil end
		local name, main = row:match("^([^%^]+)%^([^%^]+)$")
		if Name(name) ~= name or Name(main) ~= main or names[name:lower()] then return nil end
		names[name:lower()], mains[name:lower()], last = name, main:lower(), row
		lines[#lines + 1] = row
	end
	for key, main in pairs(mains) do if not names[main] or mains[main] ~= main then return nil end end
	local text = table.concat(lines, "\n"); return #text <= R.TEXT and text or nil
end
function R.Parse(text)
	if type(text) ~= "string" or #text > R.TEXT then return nil end
	local lines = {}; for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
	local scope, faction, issuer, guild, week, kind, at, revision, expires, guid, pkind, pn, rn = lines[1]:match(
		"^DR1~([^~]+)~([^~]+)~([^~]+)~([^~]+)~(%d+)~([BEX])~(%d+)~(%d+)~(%d+)~([^~]+)~([AHT]+)~(%d+)~(%d+)$")
	pn, rn = tonumber(pn), tonumber(rn)
	if not pn or not rn or pn > A.MAX_PARTS or rn > R.MEMBERS or #lines ~= 1 + pn + rn then return nil end
	local proof, rows = { kind = pkind, realm = scope, blobs = {} }, {}
	for i = 1, pn do proof.blobs[i] = lines[i + 1] end
	for i = 1, rn do rows[i] = lines[1 + pn + i] end
	local c = { scope = scope, faction = faction, issuer = issuer, guild = guild, week = tonumber(week), kind = kind,
		at = tonumber(at), revision = tonumber(revision), expires = tonumber(expires), guid = guid, proof = proof, rows = rows }
	return R.Text(c) == text and c or nil
end
local function Slot(c) return c.guild .. "|" .. c.week .. "|" .. c.kind end
local function Floor(s, c) return s.floors[c.guild] end
local function Allowed(s, c, root)
	local f = Floor(s, c)
	if not f then return true end
	if type(f) ~= "table" or not Whole(f.revision) or not Whole(f.generation) or not Whole(f.epoch) then return false end
	if type(f.conflicts) ~= "table" then return false end
	if c.issuer ~= f.issuer or c.guid ~= f.guid then
		return c.generation == nil or c.generation > f.generation and c.roleEpoch >= f.epoch
	end
	return c.revision >= f.revision and not (c.revision == f.revision and (f.off or f.conflict or f.conflicts[Slot(c)]))
end
local function Accept(c, root, text, sig)
	local s = Store(); if not s or not Allowed(s, c, root) then return false end
	local f = Floor(s, c)
	if not f and Count(s.floors) >= R.ISSUERS then return false end
	if not f or c.issuer ~= f.issuer or c.guid ~= f.guid or c.revision > f.revision then
		s.floors[c.guild] = { revision = c.revision, issuer = c.issuer, guid = c.guid,
			generation = c.generation, epoch = c.roleEpoch, off = c.kind == "X", conflicts = {} }
	elseif c.kind == "X" then f.off = true end
	if c.kind == "X" then
		for key, old in pairs(s.received) do if type(old) == "table" and old.guild == c.guild then s.received[key], verified[key] = nil, nil end end
		ns.Fire("TREASURY_CHANGED"); return true
	end
	local key, old = Slot(c), s.received[Slot(c)]
	if old ~= nil and type(old) ~= "table" then return false end -- corrupt retained slot is unknown, not an empty history
	if old and old.root ~= root then
		if old.issuer == c.issuer and old.guid == c.guid and old.revision == c.revision then
			s.floors[c.guild].conflicts[key] = true
			s.received[key] = { guild = c.guild, week = c.week, revision = c.revision, conflict = true }; verified[key] = nil; return false
		end
	elseif old and old.root == root and verified[key] then return true end
	if not old and Count(s.received) >= R.SNAPSHOTS then return false end
	c.root, c.text, c.sig, c.identity = root, text, sig, nil
	s.received[key], verified[key] = c, c
	ns.Fire("TREASURY_CHANGED")
	return true
end
local function Verify(sender, text, sig, root, done)
	local finished, active = false, false
	local function Finish(c) if finished then return end; finished = true; if active then active = false; jobs = jobs - 1 end; if done then done(c) end end
	local c, s = R.Parse(text), Store()
	local k = s and keys[Name(sender):lower()]
	if not c or c.issuer ~= Name(sender) or not k or k.guid ~= c.guid or k.guild ~= c.guild
		or not Keeper() or not Master(sender, c.guild) or not Allowed(s, c, root) or c.at > Clock() + R.BOUNDARY
		or c.week < D.Week() - R.KEEP + 1 or c.week > D.Week() or Clock() > c.expires
		or Digest(text) ~= root or not Raw(sig, 64) or jobs >= R.JOBS then return false end
	local identity = Identity(); jobs = jobs + 1; active = true
	ns.Arena.Check("dues-roster:" .. Digest(root .. k.pk .. sig), { pk = Raw(k.pk, 32), sig = Raw(sig, 64), msg = "OLYDR1|" .. root }, function(ok)
		if not ok or identity ~= Identity() or Store() ~= s or not Keeper() or not Master(sender, c.guild) or keys[Name(sender):lower()] ~= k then Finish(nil); return end
		A.VerifyHistoricalRoleProof(c.proof, c.issuer, c.guild, c.at, c.faction, function(role)
			if role and identity == Identity() and Store() == s and Keeper() and Master(sender, c.guild) and Clock() <= c.expires then
				c.generation, c.roleEpoch = role.published, role.epoch
				if Accept(c, root, text, sig) then Finish(c); return end
			end
			Finish(nil)
		end)
	end)
	return true
end
local function Send(to, text, key, permit)
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < math.ceil(#text / ns.Codec.CHUNK) + 1 then return false end
	local p = { identity = Identity(), to = to, text = text, at = Clock(), permit = permit }
	permits[key] = p
	local ok = T.Private(to, "DQ", text, key)
	if not ok then permits[key] = nil end
	return ok
end
local function Ack(sender, root, i, digest)
	return Send(sender, ("DQ~1~A~%s~%d~%s"):format(root, i, digest), "roster-ack:" .. root .. ":" .. i,
		function() return Keeper() end)
end
local function Make(c)
	local text = R.Text(c); if not text then return false end
	local s, root = Store(), Digest(text)
	local o = s and Option(s, c.guild); if not o then return false end
	local key = Slot(c); o.snapshots = type(o.snapshots) == "table" and o.snapshots or {}
	if o.snapshots[key] then return false end
	local pending = { pending = true, kind = c.kind, at = c.at, template = c.kind == "X" and c or nil }
	o.snapshots[key], signing[pending] = pending, true
	local queued = Run(function()
		local _, pk = ns.Debts.MyKey(); local _, pk64, claim = ns.Debts.ClaimParts()
		return { sig = E.ToB64(ns.Debts.Sign("OLYDR1|" .. root)), pk = pk64, claim = claim }
	end, function(result)
		signing[pending] = nil
		if o.snapshots[key] ~= pending then return end
		if result and Source(c) then
			c.root, c.text, c.wire, c.sig, c.pk, c.claim = root, text, E.ToB64(text), result.sig, result.pk, result.claim
			o.snapshots[key] = c
		elseif pending.template then
			-- A temporary lost roster/identity capability is not a new consent decision.
			-- Keep only this exact bounded X intent; a later fresh DATA event rechecks it.
			pending.pending, pending.resumeAt = false, Clock() + 30
		else o.snapshots[key] = nil end
		R.Wake()
	end)
	if not queued then
		signing[pending] = nil
		if pending.template then pending.pending, pending.resumeAt = false, Clock() + 30 else o.snapshots[key] = nil end
	end
	return queued
end
local function WithdrawalTemplate(p)
	local c = type(p) == "table" and p.template
	return type(c) == "table" and c.kind == "X" and R.Text(c) ~= nil and Source(c)
		and c.guid == UnitGUID("player") and Clock() - c.at >= 0 and Clock() - c.at <= R.TTL and c or nil
end
local function ResumeWithdrawal(o)
	for key, p in pairs(o.snapshots) do
		local c = WithdrawalTemplate(p)
		if c and not signing[p] and (not p.resumeAt or Whole(p.resumeAt) and Clock() >= p.resumeAt) and jobs < R.JOBS then
			local saved = Store(false)
			p.resumeAt, signing[p] = Clock() + 30, true
			A.VerifyHistoricalRoleProof(c.proof, c.issuer, c.guild, c.at, c.faction, function(role)
				signing[p] = nil
				if Store(false) ~= saved or o.snapshots[key] ~= p then return end
				if role and WithdrawalTemplate(p) then
					o.snapshots[key] = nil
					Make(c) -- same original template: never a new capture date or reconstructed office
				elseif not role then p.abandoned = true end
				R.Wake()
			end)
			return
		end
	end
end
function R.SetSharing(on)
	local guild = NativeGM()
	if not guild or not Master(ns.me, guild) then return false end
	local s = Store(); if not s then return false end
	local old = Option(s, guild); if old and old.on == (on == true) and old.expires >= Clock() then return false end
	local o = { actor = ns.me, on = on == true, revision = (old and old.revision or 0) + 1, expires = Clock() + R.OPT_FOR,
		snapshots = {}, withdrawalUntil = on ~= true and Clock() + R.TTL or nil }
	s.own[guild], stream = o, nil
	if not o.on then
		local proof = A.ExportOriginalRoleProof()
		if proof then Make({ scope = ns.group, faction = ns.faction, issuer = Name(ns.me), guild = guild, week = D.Week(),
			kind = "X", at = Clock(), revision = o.revision, expires = o.expires, guid = UnitGUID("player"),
			proof = proof, rows = {}, identity = Identity() }) end
	end
	R.Wake()
	ns.Fire("TREASURY_CHANGED"); return true
end
local function Capture(kind, week)
	local guild, s, rows = NativeGM(), Store(), R.NativeRows()
	local o = guild and Option(s, guild)
	local proof = o and o.on and rows and A.ExportOriginalRoleProof()
	if not proof or Clock() > o.expires or not Master(ns.me, guild) then return false end
	return Make({ scope = ns.group, faction = ns.faction, issuer = Name(ns.me), guild = guild, week = week, kind = kind,
		at = Clock(), revision = o.revision, expires = o.expires, guid = UnitGUID("player"), proof = proof, rows = rows, identity = Identity() })
end
function R.Observe()
	local s, now, week = Store(), Clock(), D.Week(); if not s then return false end
	-- A frozen global amount is independent of primary-guild roster completeness. Missing
	-- this real reset never permits reconstruction from a later King's word.
	if Keeper() and now >= D.WeekStart(week) and now <= D.WeekStart(week) + R.BOUNDARY and not s.amounts[week] then
		s.amounts[week] = { at = now, amount = D.Amount() }
	end
	for w in pairs(s.amounts) do if not Whole(w, 1000000) or w < week - R.KEEP + 1 or w > week then s.amounts[w] = nil end end
	for key, c in pairs(s.received) do if type(c) == "table" and Whole(c.week, 1000000) and c.week < week - R.KEEP + 1 then s.received[key], verified[key] = nil, nil end end
	if not R.Sharing() then lastSeen = nil; return false end
	if now >= D.WeekStart(week) and now <= D.WeekStart(week) + R.BOUNDARY then
		Capture("B", week)
		if lastSeen and lastSeen.identity == Identity() and lastSeen.week + 1 == week
			and now - lastSeen.at >= 0 and now - lastSeen.at <= R.BOUNDARY then Capture("E", week - 1) end
	end
	lastSeen = { identity = Identity(), week = week, at = now }
	return true
end
local function Window(c, s)
	return type(c) == "table" and type(c.text) == "string" and R.Text(c) == c.text and verified[Slot(c)] == c and Allowed(s, c, c.root) and Clock() <= c.expires and Master(c.issuer, c.guild)
end
function R.ValidatedWindow(guild, week)
	if not Keeper() or not Guild(guild) or not Whole(week, 1000000) then return nil end
	local s = Store(); if not s then return nil end
	local b, e, amount = s.received[guild .. "|" .. week .. "|B"], s.received[guild .. "|" .. week .. "|E"], s.amounts[week]
	if not Window(b, s) or not Window(e, s) or b.issuer ~= e.issuer or b.guid ~= e.guid or b.revision ~= e.revision
		or type(amount) ~= "table" or not Whole(amount.amount, D.MAX_AMOUNT) or amount.amount < 1 or not Whole(amount.at)
		or amount.at < D.WeekStart(week) or amount.at > D.WeekStart(week) + R.BOUNDARY then return nil end
	local function Expand(c)
		local members, mains, sets, groups = {}, {}, {}, {}
		for _, row in ipairs(c.rows) do local name, main = row:match("^([^%^]+)%^(.+)$"); local key = name:lower()
			members[key], mains[key] = name, main:lower(); sets[main:lower()] = sets[main:lower()] or {}; table.insert(sets[main:lower()], key) end
		for _, set in pairs(sets) do table.sort(set); local group = table.concat(set, ";"); for _, key in ipairs(set) do groups[key] = group end end
		return members, mains, groups
	end
	local members, mains, groups = Expand(b); local ends, endMains, endGroups = Expand(e)
	return { guild = guild, week = week, at = b.at, endAt = e.at, amount = amount.amount, members = members, ends = ends,
		groups = groups, endGroups = endGroups, mains = mains, endMains = endMains, closed = true, covered = true, issuer = b.issuer }
end
function R.Scopes()
	local s, out = Store(), {}; if not Keeper() or not s then return out end
	for guild in pairs(s.floors) do if Guild(guild) and guild ~= GetGuildInfo("player") then out[#out + 1] = guild end end
	table.sort(out); return out
end
function R.LatestMembers(guild)
	local row = R.ValidatedWindow(guild, D.Week() - 1)
	return row and row.ends or nil
end
function R.Pump()
	if Clock() < nextPump then return false end
	nextPump = Clock() + 2
	if Keeper() then R.RecheckSaved() end
	for key, p in pairs(permits) do if Clock() - p.at < 0 or Clock() - p.at > R.TTL then permits[key] = nil end end
	for key, q in pairs(incoming) do if Clock() - q.at < 0 or Clock() - q.at > R.TTL then incoming[key] = nil end end
	if stream and (not WireSnapshot(stream.c) or not Source(stream.c) or Clock() - stream.at < 0 or Clock() - stream.at > R.TTL) then stream = nil end
	if not stream then
		local guild, s = NativeGM(), Store(); local o = guild and Option(s, guild)
		for _, c in pairs(o and o.snapshots or {}) do
			if WireSnapshot(c) and not c.sent and not c.abandoned and c.identity == Identity() and Source(c) and c.week >= D.Week() - R.KEEP + 1 then
				stream = { c = c, i = 0, at = Clock(), retries = 0 }; break
			end
		end
	end
	local q = stream; if not q or q.wait and Clock() - q.wait < 30 then return false end
	q.retries = q.retries + 1; if q.retries > 30 then q.c.abandoned, stream = true, nil; R.Wake(); return false end
	local c, to, text = q.c, Primary()
	if q.i == 0 then text = table.concat({ "DQ", "1", "K", c.guild, c.guid, c.pk, c.claim, c.root }, "~")
	else
		local body = c.wire:sub((q.i - 1) * R.PART + 1, q.i * R.PART)
		text = table.concat({ "DQ", "1", "P", c.root, q.i, math.ceil(#c.wire / R.PART), c.sig, Digest(body), body }, "~")
	end
	q.wait = Clock()
	return Send(to, text, "roster:" .. c.root .. ":" .. q.i, function() return stream == q and Source(c) end)
end
function R.Handle(dist, sender, text)
	if dist ~= "WHISPER" or not Safe() or not Name(sender) or type(text) ~= "string" or #text > R.PART + 400 then return false end
	if text == "DQ~1~Q" then
		if not Same(sender, Primary()) then return false end
		local s, guild = Store(false), NativeGM(); local o = guild and Option(s, guild)
		for _, c in pairs(o and o.snapshots or {}) do if WireSnapshot(c) and Source(c) then
			local msg = table.concat({ "DQ", "1", "K", c.guild, c.guid, c.pk, c.claim, c.root }, "~")
			return Send(sender, msg, "roster-recovery-key", function() return Source(c) end)
		end end
		return false
	end
	local guild, guid, pk, claim, claimRoot = text:match("^DQ~1~K~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([a-f0-9]+)$")
	if guild then
		if #claimRoot ~= 64 then return false end
		local cached = keys[Name(sender):lower()]
		if cached and cached.guid == guid and cached.pk == pk and cached.guild == guild and Keeper() and Master(sender, guild) then return Ack(sender, claimRoot, 0, Digest(pk .. claim)) end
		return CheckKey(Name(sender), guild, guid, pk, claim, function() Ack(sender, claimRoot, 0, Digest(pk .. claim)) end)
	end
	local root, index, hash = text:match("^DQ~1~A~([a-f0-9]+)~(%d+)~([a-f0-9]+)$")
	if root then
		local q = stream; index = tonumber(index)
		if not q or not Same(sender, Primary()) or not Source(q.c) or index ~= q.i then return false end
		if index == 0 and (root ~= q.c.root or hash ~= Digest(q.c.pk .. q.c.claim)) then return false end
		if index > 0 and (root ~= q.c.root or hash ~= Digest(q.c.wire:sub((index - 1) * R.PART + 1, index * R.PART))) then return false end
		if index == math.ceil(#q.c.wire / R.PART) then q.c.sent, stream = true, nil; R.Wake()
		else q.i, q.wait, q.retries = q.i + 1, nil, 0 end
		return true
	end
	local total, sig, body
	root, index, total, sig, hash, body = text:match("^DQ~1~P~([a-f0-9]+)~(%d+)~(%d+)~([^~]+)~([a-f0-9]+)~(.*)$")
	index, total = tonumber(index), tonumber(total)
	local k = keys[Name(sender):lower()]
	if not root or #root ~= 64 or not Whole(index, R.PARTS) or index < 1 or not Whole(total, R.PARTS) or total < index
		or not Keeper() or not k or not Master(sender, k.guild) or not Raw(sig, 64) or #body > R.PART or Digest(body) ~= hash then return false end
	local id = Name(sender):lower() .. ":" .. root
	local q = incoming[id]
	if not q then
		if index ~= 1 or Count(incoming) >= 8 then return false end
		q = { at = Clock(), total = total, sig = sig, pages = {}, next = 1 }; incoming[id] = q
	end
	if q.total ~= total or q.sig ~= sig or index > q.next or q.pages[index] and q.pages[index] ~= body then incoming[id] = nil; return false end
	q.pages[index] = body; q.next = math.max(q.next, index + 1)
	if index < total then return Ack(sender, root, index, hash) end
	if q.checking then return false end
	local encoded = table.concat(q.pages)
	local ok, joined = pcall(E.FromB64, encoded)
	if not ok or type(joined) ~= "string" or #joined > R.TEXT or E.ToB64(joined) ~= encoded or Digest(joined) ~= root then incoming[id] = nil; return false end
	q.checking = true
	local queued = Verify(sender, joined, sig, root, function(c)
		incoming[id] = nil
		if c then
			Ack(sender, root, index, hash)
			if ns.DuesGrace then ns.DuesGrace.QueueNotices(D.Week() - 1) end
		end
	end)
	if not queued then incoming[id] = nil end
	return queued
end
T.OnPrivate("DQ", {
	from = function(sender)
		if not Safe() then return false end
		if Same(sender, Primary()) then return NativeGM() ~= nil end
		local guild, rank = A.Role(sender); return Keeper() and rank == 0 and Master(sender, guild) or false
	end,
	to = function() return Keeper() or NativeGM() ~= nil end,
	send = function(to, text)
		for _, p in pairs(permits) do if p.text == text and Same(p.to, to) and p.identity == Identity()
			and Clock() - p.at >= 0 and Clock() - p.at <= R.TTL and Safe() and p.permit() then return true end end
		return false
	end,
	piece = function(piece)
		local id, i, n, body = piece:match("^C(%w+):(%d+):(%d+):(.*)$")
		i, n = tonumber(i), tonumber(n)
		return id and #id <= 8 and Whole(i, ns.Codec.MAX_CHUNKS) and i >= 1 and Whole(n, ns.Codec.MAX_CHUNKS) and n >= i and #body <= ns.Codec.CHUNK or false
	end,
	handle = R.Handle,
	repeatAfter = 20,
})
function R.GuildLines(lines)
	if not NativeGM() then return end
	local enabled = Master(ns.me, GetGuildInfo("player"))
	lines[#lines + 1] = { text = enabled and ns.L.DUESROSTER_SHARE or ns.L.DUESROSTER_NO_PROOF,
		checked = R.Sharing(), onClick = enabled and function() R.SetSharing(not R.Sharing()) end or nil,
		tooltip = function(tt) tt:AddLine(ns.L.DUESROSTER_PRIVACY, 1, 1, 1, true) end }
end
-- Reload never trusts a serialized "verified" flag or self-signed forwarded key. The
-- original GM must again provide its native-bound claim before retained signatures can
-- be checked; none of this repopulates the active governance manifest.
function R.RecheckSaved()
	local s = Store(); if not Keeper() or not s then return false end
	for _, c in pairs(s.received) do
		if type(c) == "table" and Name(c.issuer) and type(c.text) == "string" and R.Text(c) == c.text and c.sig and c.root and not verified[Slot(c)] then
			local actor = Name(c.issuer):lower()
			if not asked[c.root] or Clock() - asked[c.root] >= 180 then
				asked[c.root] = Clock()
				if keys[actor] then Verify(c.issuer, c.text, c.sig, c.root)
				elseif not asked[actor] or Clock() - asked[actor] >= 180 then
					asked[actor] = Clock()
					local enrolled = s.keys[actor]
					if type(enrolled) == "table" and enrolled.original == c.issuer and ns.Debts.Bind(c.issuer, enrolled.guid) then
						CheckKey(c.issuer, enrolled.guild, enrolled.guid, enrolled.pk, enrolled.sig)
					else Send(c.issuer, "DQ~1~Q", "roster-recovery:" .. actor, function() return Keeper() and Master(c.issuer, c.guild) end) end
				end
			end
		end
	end
	return true
end
-- No periodic work (and no store creation) for default/off clients. A retained opt-in
-- can wait for DATA_CHANGED from the actual roster scan/author manifest at login.
-- Observation still requires the complete fresh native roster; stale membership never
-- becomes a checkpoint. An off transition keeps only bounded delivery of its signed X.
function R.Wake()
	if waking then return end
	waking = true
	local observe, deliver, began = Keeper(), false, false
	local s, guild = Store(false), GetGuildInfo("player")
	local o = s and Guild(guild) and Option(s, guild)
	if o and Clock() <= o.expires and NativeGM() == guild and Master(ns.me, guild) then
		if o.on then observe, deliver = true, true
		elseif Whole(o.withdrawalUntil) and Clock() <= o.withdrawalUntil then
			for _, c in pairs(o.snapshots) do
				if type(c) == "table" and c.kind == "X" and not c.sent and not c.abandoned
					and (WithdrawalTemplate(c) or WireSnapshot(c) and Source(c)) then deliver = true; break end
			end
			if deliver then ResumeWithdrawal(o) end
		end
	end
	deliver = observe or deliver
	if observe and not boundaryTicker then
		boundaryTicker = ns.Every(60, "native dues roster boundaries", function() R.Wake(); if boundaryTicker then R.Observe() end end)
		began = true
	elseif not observe and boundaryTicker then boundaryTicker:Cancel(); boundaryTicker = nil; lastSeen = nil end
	if deliver and not pageTicker then
		pageTicker = ns.Every(2, "private dues roster pages", function() R.Wake(); if pageTicker then R.Pump() end end)
	elseif not deliver and pageTicker then pageTicker:Cancel(); pageTicker = nil; stream = nil end
	waking = false
	if began then R.Observe() end -- randomized Every startup must not miss a real reset boundary
end
function R.Scheduled() return boundaryTicker ~= nil, pageTicker ~= nil end
for _, event in ipairs({ "DATA_CHANGED", "TREASURY_CHANGED", "WATCH_CHANGED", "VIEWAS_CHANGED" }) do ns.On(event, R.Wake) end
ns.On("LOGIN", function()
	if boundaryTicker then boundaryTicker:Cancel(); boundaryTicker = nil end
	if pageTicker then pageTicker:Cancel(); pageTicker = nil end
	incoming, verified, keys, permits, asked, stream, lastSeen, signing = {}, {}, {}, {}, {}, nil, nil, {}
	R.Wake()
end)
