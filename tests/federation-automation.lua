local ns, test, eq = ...
local ROOT = debug.getinfo(1, 'S').source:sub(2):match('^(.*)tests[/\\]federation%-automation%.lua$') or './'
local DAY, NOW = 86400, 1800010000
local R, GUILD, PRIME = 'CAMWOWUS2Realm5PvE', 'Olympus Willow', 'Olympus Prime'
local CARE, OFF, SUBJECT, ALT, THIRD = 'Alder Fall-' .. R, 'Rook Ash-' .. R, 'Arden Frost-' .. R, 'Quill Dawn-' .. R, 'Grey Lake-' .. R
local proofs = assert(loadfile(ROOT .. 'tests/fixtures/federation-fugitives.lua'))()
local FUGITIVES = os.getenv('OLYMPUS_FUGITIVE_AUTOMATION_MODULE') or ROOT .. 'Olympus/FederationFugitives.lua'
-- Crypto/admission is covered by FederationAuthority's own real-key suite. This fixture runs
-- the actual Fugitives decision validators and consumers, with only successful publication
-- and a native complete/fresh roster supplied at its boundary. No guild removal is performed.
local function Client(role, guild, db)
	guild = guild or GUILD
	local w = { now = NOW, guild = guild, role = role or 'caretaker', records = {}, handlers = {}, attempts = {}, writes = {},
		events = {}, listeners = {}, timers = {}, alerts = {}, links = {}, fresh = true, enrolled = true, ready = true,
		roles = { [CARE] = 'caretaker', [OFF] = 'official' } }
	w.me = w.role == 'official' and OFF or CARE
	w.roster = { guild = guild, complete = true, generation = 1, byName = { [CARE] = 0, [OFF] = 1, [SUBJECT] = 3 },
		members = { { full = CARE, rankIndex = 0 }, { full = OFF, rankIndex = 1 }, { full = SUBJECT, rankIndex = 3 } } }
	local c
	local function Current(kind, key)
		local r = w.records[kind .. ':' .. tostring(key)]
		return r and r.issued <= w.now and r.expires > w.now and r or nil
	end
	local function Decision(kind, content, issuer, targetGuild, issued, expires)
		local h = w.handlers[kind]
		if not h then return false, 'handler' end
		local record = { kind = kind, content = content, issuer = issuer or c.me, guild = targetGuild or w.guild,
			issued = issued or w.now, expires = expires or w.now + 3 * DAY, scope = 'US:ForeverPvE:Alliance' }
		local parsed, key = h.validate(content, record)
		if not parsed then return false, 'content' end
		record.parsed, record.key = parsed, key
		w.records[kind .. ':' .. key] = record
		h.apply(record, parsed)
		return true, record
	end
	c = setmetatable({ realm = R, group = 'ForeverPvE', faction = 'Alliance', me = w.me, db = db or {}, rdb = {}, RealmPages = {},
		L = setmetatable({}, { __index = ns.L }),
		Data = { ServerTime = function() return w.now end },
		IsMember = function() return w.member ~= false end, QuietPresence = function() return w.quiet == true end,
		ChatLocked = function() return w.locked == true end, KingsScreen = function() return w.stream == true end,
		IsRemovedGuild = function() return false end, IsKingGuild = function(g) return g == PRIME end,
		InGroup = function(r) return ns.ForeverFamily(r) == 'ForeverPvE' end,
		Roster = { Fresh = function() return w.fresh and w.roster or nil end,
			RankOf = function(name) return w.roster.byName[name] end },
		FederationProgram = {
			BaseEnrolled = function(g) return w.enrolled and g == w.guild end,
			IsEnrolled = function(g) local r = Current('suspension', ns.Fold(g)); return w.enrolled and g == w.guild and not (r and r.parsed.on) end,
			LocalEnrollment = function() local r = Current('suspension', ns.Fold(w.guild)); return w.enrolled and not (r and r.parsed.on) and w.guild or nil end,
			Role = function(name, g) if g == w.guild then return name == c.me and w.role or w.roles[name] end end,
			Caretakers = function() return { [w.guild] = CARE } end,
		},
		FederationAuthority = {
			Register = function(kind, validate, apply) w.handlers[kind] = { validate = validate, apply = apply } end,
			Current = Current,
			-- A verified historical pardon is not a live grant, but suppresses older decisions.
			-- Authentication of retained expired records is tested in the real FA crypto suite.
			SuppressesOlder = function(kind, key, issued)
				local r = w.records[kind .. ':' .. tostring(key)]
				return kind == 'appeal' and r ~= nil and r.issued >= issued and r.issued + 31 * DAY > w.now
			end,
			Publish = function(kind, content, g)
				w.attempts[#w.attempts + 1] = { kind = kind, content = content, guild = g }
				if not w.ready then return false, 'certificate' end
				local ok, record = Decision(kind, content, nil, g)
				if ok then w.writes[#w.writes + 1] = record end
				return ok, record
			end,
			RequestDelegation = function() end,
		},
		Alts = { Linked = function(name) return w.links[name] or {} end }, Groups = { GroupMembers = function() return {} end },
		Dialog = { Show = function(id, text)
			if w.refuseDialog then return nil end
			w.alerts[#w.alerts + 1] = { id = id, text = text }; return true
		end },
		Comm = { Handle = function() end, Peers = function() return {} end },
		RegisterEvent = function(event, fn) w.events[event] = fn end,
		On = function(event, fn) w.listeners[event] = fn end,
		Fire = function(event, ...) local fn = w.listeners[event]; if fn then fn(...) end end,
		After = function(_, _, fn) w.timers[#w.timers + 1] = fn end,
		Every = function() end, Print = function() end,
		-- Hex is only a faithful byte-encoding dependency stub; SHA256 and the Fugu event-ID
		-- construction itself are the actual addon functions, and assertions concern effects.
		Debts = { Hex = ns.Debts and ns.Debts.Hex or function(bytes) return (bytes:gsub('.', function(b) return ('%02x'):format(b:byte()) end)) end },
	}, { __index = ns })
	assert(loadfile(ROOT .. 'Olympus/Locales/FugitivesText.lua'))('Olympus', c)
	local oldAudit, oldPaste = StaticPopupDialogs.OLYMPUS_FUGITIVES_AUDIT, StaticPopupDialogs.OLYMPUS_FUGITIVES_PASTE
	assert(loadfile(FUGITIVES))('Olympus', c)
	StaticPopupDialogs.OLYMPUS_FUGITIVES_AUDIT, StaticPopupDialogs.OLYMPUS_FUGITIVES_PASTE = oldAudit, oldPaste
	w.c, w.f, w.Decision, w.Current = c, c.FederationFugitives, Decision, Current
	w.jobs = {}
	function w.EnableAsync()
		c.FederationAuthority.PublishAsync = function(kind, content, g, done, guard)
			w.jobs[#w.jobs + 1] = { kind = kind, content = content, guild = g, done = done, guard = guard }
			return true, "queued"
		end
	end
	function w.Finish(accept)
		local job = table.remove(w.jobs, 1)
		if not job then return false end
		if job.guard and not job.guard() then job.done(false, "guard"); return false end
		if accept == false then job.done(false, "certificate"); return false end
		local ok, record = Decision(job.kind, job.content, nil, job.guild)
		if ok then w.writes[#w.writes + 1] = record end
		job.done(ok, ok and nil or record)
		return ok
	end
	function w.Event(name, by, hour)
		return { kind = 'remove', p1 = by or OFF, p2 = name or SUBJECT, hour = hour or math.floor(w.now / 3600), removerExact = true, removedExact = true }
	end
	function w.Ban(name)
		assert(w.f.ObserveRemovals({ w.Event(name) }))
	end
	function w.Count(kind)
		local n = 0; for _, r in ipairs(w.writes) do if r.kind == kind then n = n + 1 end end; return n
	end
	return w
end

local function BeginHarbor(w)
	w.Ban(SUBJECT)
	eq(w.f.CheckHarboring(), false, 'first fresh observation starts a grace, not suspension')
	eq(#w.alerts, 1, 'an actual daily notice was shown')
end

local function UseRealProgram(w)
	local c = w.c
	c.Verify = { Status = function(g) if g == w.guild then return 'verified', { entry = { at = NOW - 1, gm = CARE } } end end }
	assert(loadfile(ROOT .. 'Olympus/FederationProgram.lua'))('Olympus', c)
	return c.FederationProgram
end

test('federation automation: exact native removal by a current operator publishes once and retries failed certificate setup', function()
	for _, role in ipairs({ 'caretaker', 'official' }) do
		local w = Client(role)
		w.ready = false
		eq(w.f.ObserveRemovals({ w.Event() }), false)
		eq(w.Count('fugitive'), 0); eq(next(w.c.db.federationNativeRemovals), nil, 'a failed publication cannot consume its event')
		w.ready = true
		assert(w.f.ObserveRemovals({ w.Event() }))
		eq(w.Count('fugitive'), 1); eq(w.f.IsListed(SUBJECT, GUILD), true)
		eq(w.f.ObserveRemovals({ w.Event() }), false); eq(w.Count('fugitive'), 1, 're-reading the native log cannot duplicate the decision')
	end
end)

test('federation automation: quit, ambiguous identity, wrong region/family and stale/future hours never create a decision', function()
	local edits = {
		function(e) e.kind = 'quit' end, function(e) e.removedExact = false end, function(e) e.removerExact = false end,
		function(e) e.p2 = 'Arden Frost' end, function(e) e.p1 = 'Rook Ash' end,
		function(e) e.p2 = SUBJECT:gsub('US2', 'EU2') end, function(e) e.p1 = OFF:gsub('US2', 'EU2') end,
		function(e) e.p2 = SUBJECT:gsub('PvE', 'PvP') end, function(e) e.p1 = OFF:gsub('PvE', 'PvP') end,
		function(e) e.hour = e.hour - 49 end, function(e) e.hour = e.hour + 1 end,
	}
	for i, edit in ipairs(edits) do
		local w = Client(); local e = w.Event(); edit(e)
		eq(w.f.ObserveRemovals({ e }), false, 'case ' .. i); eq(w.Count('fugitive'), 0)
	end
	local edge = Client(); assert(edge.f.ObserveRemovals({ edge.Event(nil, nil, math.floor(edge.now / 3600) - 48) }))
end)

test('federation automation: only an eligible own fresh roster and current native rank 0 or 1 may author removals', function()
	for _, setting in ipairs({ 'fresh', 'enrolled', 'member', 'quiet', 'locked', 'role', 'rank0', 'rank1', 'guild' }) do
		local w = Client(setting == 'rank1' and 'official' or 'caretaker')
		if setting == 'fresh' then w.fresh = false
		elseif setting == 'enrolled' then w.enrolled = false
		elseif setting == 'member' then w.member = false
		elseif setting == 'quiet' then w.quiet = true
		elseif setting == 'locked' then w.locked = true
		elseif setting == 'role' then w.role = 'member'
		elseif setting == 'rank0' or setting == 'rank1' then w.roster.byName[w.c.me] = 2
		elseif setting == 'guild' then w.roster.guild = 'Olympus Other' end
		eq(w.f.ObserveRemovals({ w.Event() }), false, setting); eq(w.Count('fugitive'), 0, setting)
	end
end)

test('federation automation: non-Prime kicks need exact official or caretaker; Prime native kicks remain eligible', function()
	local w = Client()
	eq(w.f.ObserveRemovals({ w.Event(SUBJECT, THIRD) }), false)
	w.roster.byName[OFF] = 2
	eq(w.f.ObserveRemovals({ w.Event(SUBJECT, OFF) }), false, 'a stale official label cannot stand in for native rank 1')
	w.roster.byName[OFF] = 1
	assert(w.f.ObserveRemovals({ w.Event(SUBJECT, CARE) }))
	w = Client('caretaker', PRIME)
	assert(w.f.ObserveRemovals({ w.Event(SUBJECT, THIRD) }))
	eq(w.Count('fugitive'), 1)
end)

test('federation automation: a newer Council pardon bars re-read old kicks but permits a genuinely later native removal', function()
	local w = Client(); local e = w.Event(nil, nil, math.floor(w.now / 3600) - 1)
	assert(w.Decision('appeal', 'P~' .. SUBJECT, CARE))
	eq(w.f.ObserveRemovals({ e }), false); eq(w.Count('fugitive'), 0)
	w.now = w.now + 3600
	assert(w.f.ObserveRemovals({ w.Event() }))
	eq(w.f.IsListed(SUBJECT, GUILD), true)
end)

test('federation automation: delegated ban and later pardon cover exact identities and known links without reviving a legacy ban', function()
	local w = Client(); w.links[ALT] = { SUBJECT }
	w.Ban(SUBJECT); eq(w.f.IsListed(ALT, GUILD), true)
	w.now = w.now + 1; assert(w.Decision('appeal', 'P~' .. SUBJECT, CARE))
	eq(w.f.IsListed(SUBJECT, GUILD), false); eq(w.f.IsListed(ALT, GUILD), false)
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local legacy = Client(); legacy.links[ALT] = { SUBJECT }
		assert(legacy.f.Import(proofs.INITIAL)); eq(legacy.f.IsListed(ALT, GUILD), true)
		legacy.now = legacy.now + 1; assert(legacy.Decision('appeal', 'P~' .. SUBJECT, CARE))
		eq(legacy.f.IsListed(SUBJECT, GUILD), false)
		eq(legacy.f.IsListed(ALT, GUILD), false, 'the legacy list cannot restore an appealed main through an alt link')
	end)
end)

test('federation automation: harboring needs 24 hours, a second fresh observation and the demonstrated daily notice', function()
	local w = Client(); BeginHarbor(w)
	eq(w.f.CheckHarboring(), false, 'the same observation is not a second day')
	w.now = w.now + DAY - 1; eq(w.f.CheckHarboring(), false)
	w.now = w.now + 1; assert(w.f.CheckHarboring())
	eq(w.Count('suspension'), 1); eq(w.f.Suspended(GUILD), true)
	local record = w.Current('suspension', ns.Fold(GUILD))
	eq(record.parsed.first, NOW); eq(record.parsed.last, NOW + DAY); eq(record.parsed.count, 1)
	eq(#w.alerts, 2, 'the new-day notice was actually displayed, not just remembered under a different key')
end)

test('federation automation: missing popup, quiet, stream, stale roster and non-caretaker cannot trigger harboring suspension', function()
	for _, setting in ipairs({ 'notice', 'quiet', 'stream', 'fresh', 'locked', 'member', 'role', 'rank' }) do
		local w = Client(); BeginHarbor(w); w.now = w.now + DAY
		if setting == 'notice' then w.refuseDialog = true
		elseif setting == 'role' then w.role = 'official'; w.c.me = OFF
		elseif setting == 'rank' then w.roster.byName[CARE] = 2
		elseif setting == 'fresh' then w.fresh = false
		elseif setting == 'locked' then w.locked = true
		elseif setting == 'member' then w.member = false
		else w[setting] = true end
		eq(w.f.CheckHarboring(), false, setting); eq(w.Count('suspension'), 0, setting)
	end
end)

test('federation automation: a changed fugitive roster restarts grace and counts only its new stable matching set', function()
	local w = Client(); BeginHarbor(w); w.now = w.now + DAY - 1
	w.Ban(THIRD)
	w.roster.byName[THIRD], w.roster.members[4] = 3, { full = THIRD, rankIndex = 3 }
	eq(w.f.CheckHarboring(), false)
	w.now = w.now + 1; eq(w.f.CheckHarboring(), false, 'the previous set\'s grace cannot suspend the new set')
	w.now = w.now + DAY; assert(w.f.CheckHarboring())
	eq(w.Current('suspension', ns.Fold(GUILD)).parsed.count, 2)
end)

test('federation automation: suspended guild retains base approval so its caretaker can clear a clean roster', function()
	local w = Client(); local p = UseRealProgram(w)
	eq(p.BaseEnrolled(GUILD), true); eq(p.IsEnrolled(GUILD), true)
	BeginHarbor(w); w.now = w.now + DAY; assert(w.f.CheckHarboring())
	eq(p.BaseEnrolled(GUILD), true); eq(p.IsEnrolled(GUILD), false)
	w.roster.byName[SUBJECT] = nil; table.remove(w.roster.members, 3)
	assert(w.f.CheckHarboring())
	eq(w.f.Suspended(GUILD), false); eq(p.IsEnrolled(GUILD), true)
	eq(w.Count('suspension'), 2, 'the second authorized record is the explicit clearing revision')
end)

test('federation automation: an active suspension renews only when at most one day of validity remains', function()
	local w = Client(); BeginHarbor(w); w.now = w.now + DAY; assert(w.f.CheckHarboring())
	local current = w.Current('suspension', ns.Fold(GUILD))
	w.now = w.now + 1; eq(w.f.CheckHarboring(), false); eq(w.Count('suspension'), 1)
	current.expires = w.now + DAY
	w.now = w.now + 1; assert(w.f.CheckHarboring()); eq(w.Count('suspension'), 2)
end)

test('federation automation: failed suspension publication retries without losing its original grace observation', function()
	local w = Client(); BeginHarbor(w); w.now = w.now + DAY; w.ready = false
	eq(w.f.CheckHarboring(), false); eq(w.Count('suspension'), 0)
	w.now = w.now + 1; w.ready = true
	assert(w.f.CheckHarboring()); eq(w.Current('suspension', ns.Fold(GUILD)).parsed.first, NOW)
end)


test('federation automation: asynchronous removal queues once, commits its dedup only after success and retries a failed publication', function()
	local w = Client(); w.EnableAsync()
	assert(w.f.ObserveRemovals({ w.Event() })); eq(#w.jobs, 1); eq(w.Count('fugitive'), 0)
	eq(next(w.c.db.federationNativeRemovals), nil)
	eq(w.f.ObserveRemovals({ w.Event() }), false, 'pending crypto cannot queue the same native source twice')
	eq(w.Finish(false), false); eq(next(w.c.db.federationNativeRemovals), nil)
	assert(w.f.ObserveRemovals({ w.Event() })); assert(w.Finish())
	eq(w.Count('fugitive'), 1); assert(next(w.c.db.federationNativeRemovals))
	eq(w.f.ObserveRemovals({ w.Event() }), false)
end)

test('federation automation: queued old kick cannot reban a character pardoned while signing waited', function()
	local w = Client(); w.EnableAsync()
	assert(w.f.ObserveRemovals({ w.Event() }))
	w.now = w.now + 1; assert(w.Decision('appeal', 'P~' .. SUBJECT, CARE))
	eq(w.Finish(), false, 'the publication guard must re-read the newer Council pardon')
	eq(w.Count('fugitive'), 0); eq(w.f.IsListed(SUBJECT, GUILD), false)
end)

test('federation automation: role, roster and privacy changes cancel queued native decisions without consuming their source', function()
	for _, setting in ipairs({ 'rank', 'fresh', 'quiet', 'stream', 'locked', 'member' }) do
		local w = Client(); w.EnableAsync(); assert(w.f.ObserveRemovals({ w.Event() }))
		if setting == 'rank' then w.roster.byName[CARE] = 2
		elseif setting == 'fresh' then w.fresh = false
		elseif setting == 'member' then w.member = false
		else w[setting] = true end
		eq(w.Finish(), false, setting); eq(w.Count('fugitive'), 0); eq(next(w.c.db.federationNativeRemovals), nil)
	end
end)

test('federation automation: a clean roster before asynchronous suspension commits cancels the stale sanction', function()
	local w = Client(); BeginHarbor(w); w.now = w.now + DAY; w.EnableAsync()
	assert(w.f.CheckHarboring()); eq(#w.jobs, 1); eq(w.f.Suspended(GUILD), false)
	w.roster.byName[SUBJECT] = nil; table.remove(w.roster.members, 3)
	eq(w.Finish(), false, 'do not suspend from a source that no longer holds')
	eq(w.Count('suspension'), 0); eq(w.f.Suspended(GUILD), false)
end)

test('federation automation: an asynchronous clear cannot erase a new still-present fugitive', function()
	local w = Client(); BeginHarbor(w); w.now = w.now + DAY; assert(w.f.CheckHarboring())
	w.roster.byName[SUBJECT] = nil; table.remove(w.roster.members, 3)
	w.EnableAsync(); assert(w.f.CheckHarboring())
	-- The existing ban remains current; a native fresh scan finds the person back before commit.
	w.roster.byName[SUBJECT], w.roster.members[3] = 3, { full = SUBJECT, rankIndex = 3 }
	eq(w.Finish(), false); eq(w.f.Suspended(GUILD), true)
end)

test('federation automation: expired short-lived pardon cannot resurrect an older still-valid legacy author list', function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local w = Client(); w.links[ALT] = { SUBJECT }
		assert(w.f.Import(proofs.INITIAL))
		assert(w.Decision('appeal', 'P~' .. SUBJECT, CARE, nil, w.now, w.now + 7 * DAY))
		eq(w.f.IsListed(SUBJECT, GUILD), false)
		w.now = w.now + 8 * DAY
		eq(w.Current('appeal', ns.Fold(SUBJECT)), nil, 'the short-lived active record has expired')
		eq(w.f.IsListed(SUBJECT, GUILD), false)
		eq(w.f.IsListed(ALT, GUILD), false)
		w.Ban(SUBJECT)
		eq(w.f.IsListed(SUBJECT, GUILD), true, 'an old pardon is not immunity against a genuinely newer decision')
		eq(w.f.IsListed(ALT, GUILD), true)
	end)
end)

test('federation automation: native removal work stays bounded while later distinct entries can catch up', function()
	local w = Client(); local events = {}
	for _, name in ipairs({ 'Blue One', 'Blue Two', 'Blue Three', 'Blue Four', 'Blue Five', 'Blue Six' }) do events[#events + 1] = w.Event(name .. '-' .. R) end
	assert(w.f.ObserveRemovals(events)); eq(w.Count('fugitive'), 4)
	assert(w.f.ObserveRemovals(events)); eq(w.Count('fugitive'), 6)
	eq(w.f.ObserveRemovals(events), false)
end)


test('federation automation: rejected async admission releases its pending marker and permits a later native retry', function()
	local w = Client()
	w.c.FederationAuthority.PublishAsync = function() return false, 'queue full' end
	eq(w.f.ObserveRemovals({ w.Event() }), false); eq(next(w.c.db.federationNativeRemovals), nil)
	w.EnableAsync(); assert(w.f.ObserveRemovals({ w.Event() })); assert(w.Finish())
	eq(w.Count('fugitive'), 1)
end)

test('federation automation: a failed asynchronous harboring signature releases pending state for a later retry', function()
	local w = Client(); BeginHarbor(w); w.now = w.now + DAY; w.EnableAsync()
	assert(w.f.CheckHarboring()); eq(w.Finish(false), false); eq(w.f.Suspended(GUILD), false)
	w.now = w.now + 1
	assert(w.f.CheckHarboring()); assert(w.Finish()); eq(w.f.Suspended(GUILD), true)
end)
