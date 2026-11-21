-- Real RSA/Ed25519 verification with public-only RSA artifacts from a disposable
-- key. Repeated-byte Ed25519 seeds below are fictitious test identities only.
local base, test, eq, H = ...
local fixture = assert(loadfile(H.ROOT .. "tests/fixtures/federation-authority.lua"))()
local T, DAY = 1795000000, 86400
local REALM, GROUP, SCOPE = "CAMWOWUS1Realm2PvE", "ForeverPvE", "US:ForeverPvE:Alliance"
local GUILD, OTHER = "Olympus Azure", "Olympus Amber"
local HC, OP, COIN, ROGUE = "Silver Rock-" .. REALM, "Amber Vale-" .. REALM, "Gold Ledger-" .. REALM, "Dark Bird-" .. REALM

local function World(run)
	local oldGuild, oldPopup = GetGuildInfo, StaticPopupDialogs.OLYMPUS_FEDERATION_CERTIFICATE
	local w = { now = T, guild = GUILD, sent = {}, jobs = {}, applied = {}, handlers = {}, enrolled = true,
		fresh = true, operatorRank = 1, council = true, revision = 1 }
	local n = setmetatable({ db = {}, rdb = {}, realm = REALM, group = GROUP, faction = "Alliance", me = HC,
		On = function() end, After = function() end, Every = function() end, Fire = function() end,
		Now = function() return w.now end, QuietPresence = function() return w.quiet == true end,
		ChatLocked = function() return w.locked == true end, IsMember = function() return w.member ~= false end,
		IsHighCouncillor = function(name) return w.council and name == HC end, IsAuthorName = function() return false end,
		TreasurerPins = function() return { COIN }, true end,
		Data = { ServerTime = function() return w.now end },
		CaptureError = function(_, err) error(err) end,
	}, { __index = base })
	w.ns = n
	n.Roster = { generation = 1, snapshotAt = T, members = {},
		Fresh = function() return w.fresh and { guild = w.guild, members = {} } or nil end,
		RankOf = function(name) return name == HC and 0 or name == OP and w.operatorRank or nil end }
	n.FederationProgram = {
		BaseEnrolled = function(guild) return w.enrolled and (guild == GUILD or guild == OTHER) end,
		IsEnrolled = function(guild) return w.enrolled and not w.suspended and (guild == GUILD or guild == OTHER) end,
		EnrollmentRevision = function() return w.revision end,
		Role = function(name, guild)
			if guild ~= GUILD then return nil end
			if name == HC and w.council then return "caretaker" end
			if name == OP and w.operatorRank == 1 then return "official" end
		end,
		Caretakers = function() return { [GUILD] = HC } end,
	}
	local function Save(dist, text, key, to, options)
		w.sent[#w.sent + 1] = { dist = dist, text = text, key = key, to = to, options = options }
		return true
	end
	n.Comm = { Handle = function(kind, fn) w.handlers[kind] = fn end, RelayPieces = function() end,
		Peers = function() return { OP, HC } end,
		SendBatch = function(dist, chunks, key, to, _, _, options) return Save(dist, table.concat(chunks, "\n"), key, to, options) end,
		Whisper = function(to, text, key, _, _, _, options) return Save("WHISPER", text, key, to, options) end }
	assert(loadfile(H.ADDON_DIR .. "Sign.lua"))("Olympus", n)
	assert(loadfile(H.ADDON_DIR .. "Ed25519.lua"))("Olympus", n)
	n.Ed25519.after = function(fn) w.jobs[#w.jobs + 1] = fn end
	local seeds = { [HC] = string.rep("A", 32), [OP] = string.rep("B", 32), [COIN] = string.rep("C", 32), [ROGUE] = string.rep("D", 32) }
	w.keys = {}
	for name, seed in pairs(seeds) do w.keys[name] = n.Ed25519.PublicKey(seed) end
	n.Debts = { Hex = n.Ed25519.ToHex,
		MyKey = function() return "test-account", w.keys[n.me] end,
		Sign = function(body) return n.Ed25519.Sign(assert(seeds[n.me]), body, w.keys[n.me]) end }
	GetGuildInfo = function() return w.guild end
	assert(loadfile(H.ADDON_DIR .. "FederationAuthority.lua"))("Olympus", n)
	w.a = n.FederationAuthority
	for _, kind in ipairs({ "fugitive", "appeal", "suspension", "milestones" }) do
		w.a.Register(kind, function(content)
			local key, value = content:match("^([^~]+)~([^~]+)$")
			if not key then return nil end
			return { value = value }, key
		end, function(record) w.applied[#w.applied + 1] = record end)
	end
	function w:Drain()
		local steps = 0
		while #self.jobs > 0 do
			steps = steps + 1; assert(steps < 20000, "bounded crypto job completion")
			table.remove(self.jobs, 1)()
		end
	end
	function w:Decision(kind, key, value, opts)
		opts = opts or {}
		local issuer = opts.issuer or n.me
		local body = table.concat({ "FA1", opts.scope or SCOPE, kind, issuer, opts.guild or GUILD,
			opts.issued or self.now, opts.expires or (self.now + DAY), opts.id or string.rep("a", 32),
			n.Ed25519.ToB64(opts.certificate or fixture.council), n.Ed25519.ToB64(key .. "~" .. value) }, "~")
		return body .. "~" .. n.Ed25519.ToB64(n.Ed25519.Sign(seeds[issuer], body, self.keys[issuer]))
	end
	local ok, err = pcall(function() n.Sign.WithKey(fixture.n, fixture.mu, fixture.k, function() run(w, n, w.a) end) end)
	GetGuildInfo, StaticPopupDialogs.OLYMPUS_FEDERATION_CERTIFICATE = oldGuild, oldPopup
	if not ok then error(err, 0) end
end

test("federation authority: real root grant and Ed decision round trip, forged content and replay rejected", function()
	World(function(w, _, a)
		assert(a.ImportCertificate(fixture.council))
		eq(a.Ready("fugitive", GUILD), true)
		local wire = assert(a.Make("fugitive", "target~active", GUILD))
		local originalContent, forgedContent = base.Ed25519.ToB64("target~active"), base.Ed25519.ToB64("target~forged")
		eq(a.Accept("fugitive", wire:gsub(originalContent, forgedContent, 1)), nil, "changed content is rejected before a replay floor exists")
		local r = assert(a.Accept("fugitive", wire))
		eq(r.issuer, HC); eq(a.Current("fugitive", "target").parsed.value, "active")
		eq(#w.applied, 1)
		eq(a.Accept("fugitive", wire), nil, "duplicate signature cannot replay its effect")
		local changed = wire:gsub("FA1~", "FA1~EU:", 1)
		eq(a.Accept("fugitive", changed), nil)
		local bad = wire:sub(1, -2) .. (wire:sub(-1) == "A" and "B" or "A")
		eq(a.Accept("fugitive", bad), nil)
		eq(#w.applied, 1)
	end)
end)

test("federation authority: real private chunk receiver coexists with the loaded Dues FA receiver", function()
	World(function(w, n, a)
		local savedInfo = C_ChatInfo
		local ok, err = pcall(function()
			local client, deliver = H.FreshComm()
			client.IsMember = function() return true end
			client.realm, client.group, client.faction = REALM, GROUP, "Alliance"
			client.me = HC
			n.Comm = client.Comm
			n.Comm.RelayPieces({ F8 = true })
			n.Comm.Handle("F8", assert(w.handlers.F8, "authority registered its own transport kind"))
			assert(loadfile(H.ADDON_DIR .. "Dues.lua"))("Olympus", n)
			local dues, old = 0, n.Dues.HandleGuild
			n.Dues.HandleGuild = function(...) dues = dues + 1; return old(...) end
			deliver("WHISPER", OP, "FA~not-a-summary")
			eq(dues, 1, "the existing dues receiver remains registered")
			local wire = w:Decision("fugitive", "transport", "active")
			for _, chunk in ipairs(n.Codec.Chunk("F8~1~S~" .. wire, "f8test")) do deliver("WHISPER", OP, chunk) end
			w:Drain()
			eq(assert(a.Current("fugitive", "transport")).parsed.value, "active")
			eq(dues, 1, "authority fragments never enter the dues parser")
		end)
		C_ChatInfo = savedInfo
		if not ok then error(err, 0) end
	end)
end)

test("federation authority: grant bursts cannot bypass the global pending crypto bound", function()
	World(function(w, n)
		local accepted = 0
		local word = "F8~1~C~" .. n.Ed25519.ToB64(fixture.council)
		for i = 1, 20 do
			local sender = "Test " .. string.char(64 + i) .. "-" .. REALM
			if w.handlers.F8("WHISPER", sender, word) then accepted = accepted + 1 end
		end
		assert(accepted <= 8, "distinct native senders share the same bounded crypto work queue")
		assert(n.Ed25519.Busy() <= 8)
		w:Drain()
	end)
end)

test("federation authority: keyed roster lookups stay bounded and still observe role withdrawal", function()
	World(function(w, n, a)
		assert(a.ImportCertificate(fixture.council))
		for i = 1, 6 do
			assert(a.Accept("fugitive", w:Decision("fugitive", "target" .. i, "active", { id = string.rep(string.char(96 + i), 32) })))
		end
		local calls, original = 0, n.FederationProgram.BaseEnrolled
		n.FederationProgram.BaseEnrolled = function(...) calls = calls + 1; return original(...) end
		for _ = 1, 100 do assert(a.Current("fugitive", "target1")) end
		assert(calls <= 120, "one roster lookup must not scan and validate all decision records")
		w.council, w.revision = false, w.revision + 1
		eq(a.Current("fugitive", "target1"), nil, "fast lookup still checks current signed role")
	end)
end)

test("federation authority: root role, region, ruleset, faction and guild boundaries stay independent", function()
	World(function(w, n, a)
		eq(a.ImportCertificate(fixture.rogue), false, "a signed root grant still requires its current signed role")
		local wire = w:Decision("fugitive", "target", "active")
		n.faction = "Horde"; eq(a.Accept("fugitive", wire), nil)
		n.faction = "Alliance"; n.realm, n.group = "CAMWOWUS1Realm2PvP", "ForeverPvP"
		eq(a.Accept("fugitive", wire), nil)
		n.realm, n.group = REALM, GROUP
		w.enrolled = false; eq(a.Accept("fugitive", wire), nil)
		w.enrolled = true; assert(a.Accept("fugitive", wire))
	end)
end)

test("federation authority: delegated operator gets a native rank-1 scoped grant and cannot pardon or suspend", function()
	World(function(w, n, a)
		assert(a.ImportCertificate(fixture.council))
		w.operatorRank = 3; eq(a.Delegate(OP, w.keys[OP], GUILD), nil)
		w.operatorRank = 1; eq(a.Delegate(OP, w.keys[OP], OTHER), nil)
		local grant = assert(a.Delegate(OP, w.keys[OP], GUILD))
		local cert = assert(a.Certificate(grant, w.now))
		eq(cert.role, "operator"); eq(cert.guild, GUILD)
		assert(cert.expires - cert.issued <= 1800)
		n.me = OP; assert(a.ImportCertificate(grant))
		eq(a.Ready("fugitive", GUILD), true)
		eq(a.Ready("appeal", GUILD), false); eq(a.Ready("suspension", GUILD), false)
		eq(a.Ready("milestones", GUILD), false)
		local wire = assert(a.Make("fugitive", "target~active", GUILD))
		local r = assert(a.Accept("fugitive", wire))
		assert(r.expires <= cert.expires, "decision cannot extend the short delegation")
		eq(a.Make("fugitive", "target~active", OTHER), nil)
		w.operatorRank = 3
		eq(a.Ready("fugitive", GUILD), false, "native demotion withdraws a still-unexpired delegation")
		local demoted = w:Decision("fugitive", "demoted", "active", { issuer = OP, certificate = grant,
			issued = T, expires = T + 1000, id = string.rep("c", 32) })
		eq(a.Accept("fugitive", demoted), nil, "raw signatures cannot bypass the local Make role check")
		w.operatorRank = 1
		local backdated = w:Decision("fugitive", "later", "active", { issuer = OP, certificate = grant,
			issued = T, expires = T + DAY, id = string.rep("b", 32) })
		w.now = T + 1801
		eq(a.Accept("fugitive", backdated), nil, "an expired operator cannot backdate a fresh long-lived decision")
		eq(a.Current("fugitive", "target"), nil)
	end)
end)

test("federation authority: pardon tombstone outlives the short record but yields to author key revocation", function()
	World(function(w, _, a)
		assert(a.Accept("appeal", w:Decision("appeal", "target", "clear", { expires = T + 7 * DAY })))
		w.now = T + 7 * DAY + 1
		eq(a.Current("appeal", "target"), nil)
		eq(a.SuppressesOlder("appeal", "target", T - 1), true, "older legacy lists cannot silently re-ban an appealed player")
		eq(a.SuppressesOlder("appeal", "target", T + 1), false, "a genuinely newer decision is not hidden")
		assert(a.ImportRevocation(fixture.revoke_council))
		eq(a.SuppressesOlder("appeal", "target", T - 1), false, "a revoked signing key cannot leave a live suppression grant")
	end)
end)

test("federation authority: treasurer can publish milestones but cannot issue a sanction", function()
	World(function(_, n, a)
		n.me = COIN; assert(a.ImportCertificate(fixture.treasurer))
		eq(a.Ready("milestones", GUILD), true)
		eq(a.Ready("fugitive", GUILD), false)
		eq(a.Ready("appeal", GUILD), false)
		eq(a.Ready("suspension", GUILD), false)
		assert(a.Accept("milestones", assert(a.Make("milestones", "year~counts", GUILD))))
	end)
end)

test("federation authority: remote guild accepts a scoped caretaker attestation without inventing a native officer row", function()
	World(function(w, n, a)
		assert(a.ImportCertificate(fixture.council))
		local grant = assert(a.Delegate(OP, w.keys[OP], GUILD))
		local wire = w:Decision("fugitive", "target", "active", { issuer = OP, certificate = grant, expires = T + 1000 })
		w.guild = OTHER
		local original = n.FederationProgram.Role
		n.FederationProgram.Role = function(name, guild)
			if name == OP then return nil end -- this receiver has no census/native officer proof for the other guild
			return original(name, guild)
		end
		local r = assert(a.Accept("fugitive", wire), "signed caretaker grant supplies the bounded remote rank-1 attestation")
		eq(r.guild, GUILD); eq(r.issuer, OP)
		local foreign = w:Decision("fugitive", "other", "active", { issuer = OP, certificate = grant, guild = OTHER,
			expires = T + 1000, id = string.rep("d", 32) })
		eq(a.Accept("fugitive", foreign), nil, "remote trust does not widen the grant's guild")
	end)
end)

test("federation authority: short root grant clamps decisions and author revocation invalidates parent and child", function()
	World(function(w, _, a)
		assert(a.ImportCertificate(fixture.short))
		local grant = assert(a.Delegate(OP, w.keys[OP], GUILD))
		local wire = assert(a.Make("fugitive", "target~active", GUILD))
		local r = assert(a.Accept("fugitive", wire))
		assert(r.expires <= T + 300)
		assert(a.ImportRevocation(fixture.revoke_short))
		eq(a.Certificate(grant, T), nil, "revoking a parent revokes delegated keys too")
		eq(a.Current("fugitive", "target"), nil)
		eq(a.Accept("fugitive", wire), nil)
	end)
end)

test("federation authority: certificate receive is rate bounded and deferred into real crypto jobs", function()
	World(function(w, n, a)
		local checks, original = 0, n.Sign.Verify
		n.Sign.Verify = function(...) checks = checks + 1; return original(...) end
		local word = "F8~1~C~" .. n.Ed25519.ToB64(fixture.council)
		eq(w.handlers.F8("WHISPER", OP, word), true)
		eq(w.handlers.F8("WHISPER", OP, word), true)
		eq(w.handlers.F8("WHISPER", OP, word), false, "one sender cannot enqueue unlimited grants")
		eq(checks, 0, "the network event itself does no synchronous crypto")
		assert(n.Ed25519.Busy() > 0)
		w:Drain()
		assert(checks > 0); eq(a.Ready("fugitive", GUILD), true)
	end)
end)

test("federation authority: private revocation sync uses the signed word and suspended guild retains control plane", function()
	World(function(w, n, a)
		assert(a.ImportCertificate(fixture.council))
		assert(a.ImportRevocation(fixture.revoke_council))
		w.suspended = true
		eq(w.handlers.F8("WHISPER", OP, "F8~1~Q~" .. SCOPE), true)
		assert(#w.sent > 0, "revocations are recovered even while shared tools are suspended")
		local saw = false
		for _, packet in ipairs(w.sent) do if packet.text:find("FKR1", 1, true) then saw = true end end
		assert(saw, "anti-entropy must contain the author-signed revocation")
		-- A second isolated state accepts the network revocation before accepting
		-- any later presentation of the previously valid root grant.
		n.db = {}
		assert(w.handlers.F8("WHISPER", OP, "F8~1~R~" .. fixture.revoke_council))
		w:Drain()
		eq(a.ImportCertificate(fixture.council), false)
	end)
end)

test("federation authority: newer clear stays final across replay and equal-time deterministic order", function()
	World(function(w, _, a)
		local old = w:Decision("suspension", "guild", "on", { id = string.rep("a", 32) })
		local clear = w:Decision("suspension", "guild", "off", { id = string.rep("b", 32) })
		assert(a.Accept("suspension", clear)); eq(a.Accept("suspension", old), nil)
		eq(a.Current("suspension", "guild").parsed.value, "off")
	end)
end)
