local ns, test, eq = ...
local C, D, P, T, F = ns.Contributions, ns.Dues, ns.FederationProgram, ns.Treasury, ns.GuildFinance
local AT, R, SCOPE = 1795000000, 'CAMWOWUS1Realm2PvE', 'ForeverPvE:Alliance:US'
local TREASURER, DONOR, PRIME, OTHER = 'Silver Rock-' .. R, 'Lime Field-' .. R, 'Olympus Prime', 'Olympus Azure'
local function World(run)
	local undo, guild, time, nativeGuild, nativeAge = {}, PRIME, AT, OTHER, 0
	local function Set(t, k, value)
		local old = t[k]; undo[#undo + 1] = function() t[k] = old end; t[k] = value
	end
	Set(ns, 'rdb', { treasuryBooks = {} }); Set(ns, 'db', {}); Set(ns, 'me', TREASURER)
	Set(ns, 'realm', R); Set(ns, 'group', 'ForeverPvE'); Set(ns, 'faction', 'Alliance'); Set(ns, 'splitNames', true)
	Set(ns, 'IsMember', function() return true end)
	Set(ns, 'IsTreasurer', function(who) return who == TREASURER and guild == PRIME end)
	Set(ns, 'TreasurerPins', function() return { TREASURER }, true end)
	Set(P, 'ContributionsPolicy', function() return true, true end)
	Set(P, 'IsEnrolled', function(g) return g == OTHER end)
	Set(T, 'DevView', function() return false end); Set(T, 'KeeperByName', function() return false end)
	Set(T, 'IsKeeper', function() return true end); Set(T, 'RealKeeper', function() return true end)
	Set(T, 'Share', function() return false end)
	Set(ns.Who, 'SeenGuild', function(who) if who == DONOR then return nativeGuild, nativeAge end end)
	Set(_G, 'GetGuildInfo', function() return guild end); Set(_G, 'GetServerTime', function() return time end)
	Set(_G, 'IsInInstance', function() return false end); Set(_G, 'InCombatLockdown', function() return false end)
	local ok, err = pcall(run, Set, function(g) guild = g end, function(g, age) nativeGuild, nativeAge = g, age end)
	for i = #undo, 1, -1 do undo[i]() end
	if not ok then error(err, 0) end
end
local function Record(how, observed, opts)
	opts = opts or {}; opts.observed, opts.quiet = observed, true
	return T.Record(DONOR, 34567, how, nil, opts)
end
local function GrantName()
	assert(C.Handle('WHISPER', DONOR, ('CP~1~P~%s~%d~1'):format(SCOPE, AT)))
end

test('federation contribution sources: native settled mail with a recent native guild is protected once and anonymous', function()
	World(function(Set)
		local gold = 100000
		Set(_G, 'GetMoney', function() return gold end)
		Set(_G, 'GetInboxHeaderInfo', function() return nil, nil, DONOR, 'a gift', 34567, 0, nil, nil, nil, false, nil, true, false end)
		Set(_G, 'GetInboxInvoiceInfo', function() return nil end)
		T.MailTaking(1); T.MailTaking(1)
		eq(#T.Book().lines, 0, 'requesting mail gold is not a receipt')
		gold = gold + 34567; T.MoneyChanged()
		local book, e = T.Book(), T.Book().lines[1]
		eq(#book.lines, 1); eq(e.kind, 'charity'); eq(C.SourceLabel(book, e), 'native-mail')
		eq(T.Totals().allIn, 34567); eq(#T.PublicRanking(book), 0)
		eq(C.Project(AT), ('CP~1~B~%s~%d~?~?'):format(SCOPE, AT))
		C.Count(book, e, 1); GrantName()
		assert(C.Project(AT):find('Lime Field=34567', 1, true), 'a repeated accounting callback must not duplicate receipt')
	end)
end)

test('federation contribution sources: stale native guild and free-text mail subject cannot manufacture attribution', function()
	World(function(_, _, Seen)
		Seen(OTHER, 121)
		local e = Record('mail', true, { note = 'Olympus Azure', guild = OTHER })
		eq(e.kind, nil); eq(C.Project(AT), ('CP~1~B~%s~%d~~'):format(SCOPE, AT))
		eq(T.ClassifyContribution(e), false, 'unproved guild in mail option/subject remains a claim')
		eq(T.ClassifyContribution(e, nil, 'Olympus Invented', 'receipt archive 12'), false)
		eq(T.ClassifyContribution(e, nil, OTHER, ''), false)
	end)
end)

test('federation contribution sources: Treasurer attests an existing manual line without adding gold or counting twice', function()
	World(function(_, Guild)
		local e = Record('mail', false)
		local before = T.Totals().allIn
		eq(T.ClassifyContribution(e), false, 'ordinary manual ledger is not native proof')
		eq(T.ClassifyContribution(e, nil, OTHER, 'reviewed bank archive 12'), true)
		eq(C.SourceLabel(T.Book(), e), 'treasurer-attested')
		eq(e.gv, nil, 'an attestation must not claim native membership proof')
		eq(T.Totals().allIn, before); eq(#T.PublicRanking(T.Book()), 0)
		eq(T.ClassifyContribution(e, nil, OTHER, 'reviewed bank archive 12'), false)
		GrantName(); assert(C.Project(AT):find('Lime Field=34567', 1, true))
		Guild(OTHER)
		local another = Record('mail', false)
		eq(T.ClassifyContribution(another, nil, OTHER, 'archive 13'), false, 'only the actual scoped Treasurer may attest')
	end)
end)

test('federation contribution sources: proved historical intake is admitted but a copied ledger flag is not', function()
	World(function(Set)
		if not ns.GuildFinance then
			-- Load the real receipt/cache functions without leaving event or transport handlers
			-- in the shared harness after this test. The fixture shares this exact private book.
			local finance = setmetatable({ On = function() end,
				Treasury = setmetatable({ OnPrivate = function() end }, { __index = T }) }, { __index = ns })
			for _, key in ipairs({ "OLYMPUS_GFIN_EVENT", "OLYMPUS_GFIN_ASSIGN" }) do Set(StaticPopupDialogs, key, StaticPopupDialogs[key]) end
			assert(loadfile("Olympus/GuildFinance.lua"))("Olympus", finance)
			Set(ns, "GuildFinance", finance.GuildFinance)
		end
		local F = ns.GuildFinance
		local e = Record('mail', false, { guild = OTHER })
		assert(F.Received(e, T.Book()), 'fixture records the actual native receipt callback')
		assert(F.ContributionSource(T.Book(), e))
		eq(T.ClassifyContribution(e), true)
		eq(C.SourceLabel(T.Book(), e), 'native-mail')
		F.Reconcile()
		eq(ns.rdb.guildFinance.actors[TREASURER].receipts[e.financeReceipt].valid, true, 'classification preserves native financial attribution')
		eq(T.Totals().allIn, 34567)
		local fake = Record('mail', false, { guild = OTHER })
		fake.financeActor, fake.financeReceipt = TREASURER, e.financeReceipt
		eq(T.ClassifyContribution(fake), false, 'the same native receipt cannot admit another copied ledger line')
		eq(T.ClassifyContribution(fake, nil, OTHER, 'same receipt again'), false, 'attestation cannot consume a native proof twice')
		fake.money = fake.money + 1
		eq(T.ClassifyContribution(fake), false, 'id without matching original amount/time/payee is not proof')
	end)
end)

test('federation contribution sources: exclusion removes the exact contribution and reenabling does not multiply it', function()
	World(function()
		local e = Record('trade', true, { guild = OTHER })
		GrantName(); T.Toggle(e)
		eq(C.Project(AT):find('Lime Field', 1, true), nil)
		T.Toggle(e); T.Toggle(e); T.Toggle(e)
		assert(C.Project(AT):find('Lime Field=34567', 1, true))
		eq(T.Totals().allIn, 34567)
	end)
end)


test('federation contribution sources: restoring an older ledger cannot duplicate or expose a reclassified receipt', function()
	World(function()
		T.Book(true).opening = 0
		local e = Record('mail', false)
		local before = ns.Backup.Data().books[1]
		assert(T.ClassifyContribution(e, nil, OTHER, 'archive reference 12'))
		assert(T.RestoreBook(before))
		eq(#T.Book().lines, 1)
		eq(T.Totals().allIn, 34567)
		eq(#T.PublicRanking(T.Book()), 0)
		eq(T.Book().lines[1].patron, DONOR)
		GrantName(); assert(C.Project(AT):find('Lime Field=34567', 1, true))
	end)
end)

test('federation contribution milestones: scoped Treasurer publishes canonical edits without another author signature', function()
	World(function(Set, Guild)
		local validator, applied, current, writes = nil, nil, nil, {}
		local A = {
			Register = function(kind, check, apply) eq(kind, 'milestones'); validator, applied = check, apply end,
			Ready = function(kind) return kind == 'milestones' end,
			Publish = function(kind, content)
				local record = { kind = kind, content = content, issuer = TREASURER, guild = PRIME, issued = AT, expires = AT + 300 }
				local parsed, key = validator(content, record)
				assert(parsed); eq(key, SCOPE)
				current = record; applied(record, parsed); writes[#writes + 1] = content
				return true
			end,
			Current = function(kind, key) eq(kind, 'milestones'); eq(key, SCOPE); return current end,
		}
		Set(ns, 'FederationAuthority', A)
		assert(C.RegisterMilestoneAuthority())
		assert(C.SaveMilestoneDraft('Workshop | Crafting completed; Expedition | Guild run completed'))
		local lines = {}; C.MilestoneLines(lines); eq(#lines, 0, 'saving a draft never publishes it')
		assert(C.PublishMilestones())
		eq(writes[1], 'CM~1~Workshop=Crafting completed!Expedition=Guild run completed')
		lines = {}; C.MilestoneLines(lines); eq(#lines, 3); eq(lines[2].text, 'Workshop')
		assert(C.SaveMilestoneDraft('Second event | New achievement'))
		assert(C.PublishMilestones()); lines = {}; C.MilestoneLines(lines)
		eq(#lines, 2); eq(lines[2].text, 'Second event', 'a newer publication replaces the old list')
		assert(C.ClearMilestones()); lines = {}; C.MilestoneLines(lines); eq(#lines, 0, 'an authenticated empty revision withdraws the list')
		Guild(OTHER); eq(C.PublishMilestones(), false, 'a guild or role change removes publication permission')
		eq(#writes, 3)
	end)
end)

test('federation contribution milestones: validation rejects altered fields, arbitrary issuer and game-action payloads', function()
	World(function(Set)
		local validator
		Set(ns, 'FederationAuthority', { Register = function(_, check) validator = check end })
		assert(C.RegisterMilestoneAuthority())
		local record = { issuer = TREASURER, guild = PRIME }
		local valid = 'CM~1~Workshop=Informational note'
		assert(validator(valid, record))
		for _, text in ipairs({ 'CM~2~Workshop=Note', 'CM~1~Title=One!', 'CM~1~Title=One!!Other=Two', 'CM~1~Title=|Hitem:123|hclick|h',
			'CM~1~' .. string.rep('x', 41) .. '=Note', 'CM~1~A=' .. string.rep('x', 121), 'CM~1~A=B!C=D!E=F!G=H!I=J' }) do
			eq(validator(text, record), nil, text)
		end
		eq(validator(valid, { issuer = DONOR, guild = PRIME }), nil)
		eq(validator(valid, { issuer = TREASURER, guild = OTHER }), nil)
		eq(C.SaveMilestoneDraft('A | B;'), false)
		eq(C.SaveMilestoneDraft('A | B;; C | D'), false)
		eq(C.SaveMilestoneDraft('A | B; C | D; E | F; G | H; I | J'), false)
	end)
end)

test('federation contribution milestones: unavailable or revoked signing capability leaves draft local', function()
	World(function(Set)
		local sent = 0
		Set(ns, 'FederationAuthority', {
			Register = function() end,
			Ready = function() return false, 'revoked certificate' end,
			Publish = function() sent = sent + 1; return true end,
		})
		assert(C.SaveMilestoneDraft('Event | Informational achievement'))
		local ok, why = C.PublishMilestones()
		eq(ok, false); eq(why, 'revoked certificate'); eq(sent, 0)
	end)
end)


test('federation contribution sources: sale, excluded, Prime, foreign scope and another book remain ineligible', function()
	World(function(Set)
		for _, opts in ipairs({ { kind = 'sale' }, { excluded = true }, { item = 1234, count = 1 } }) do
			local e = Record('mail', false, opts)
			eq(T.ClassifyContribution(e, nil, OTHER, 'archive 12'), false)
		end
		local e = Record('mail', false)
		eq(T.ClassifyContribution(e, nil, PRIME, 'archive 12'), false, 'Prime mandate must not enter charity')
		eq(T.ClassifyContribution(e, { name = DONOR, lines = { e } }, OTHER, 'archive 12'), false)
		eq(T.ClassifyContribution(e, { name = TREASURER, lines = { e } }, OTHER, 'archive 12'), false, 'a lookalike table is not the actual private book')
		local foreign = T.Record('Lime Field-CAMWOWEU1Realm2PvE', 30000, 'mail', nil, { quiet = true })
		eq(T.ClassifyContribution(foreign, nil, OTHER, 'archive 12'), false)
		Set(P, 'ContributionsPolicy', function() return true, false end)
		eq(T.ClassifyContribution(e, nil, OTHER, 'archive 12'), false, 'revoked publication eligibility is checked at acceptance')
	end)
end)


test('federation contribution sources: clipboard roundtrip preserves negative foreign identity eligibility without private provenance', function()
	World(function()
		local e = T.Record('Lime Field-CAMWOWEU1Realm2PvE', 34567, 'mail', nil, { quiet = true })
		T.Book().opening = 0
		eq(e.contributionIdentityInvalid, true)
		local checked = assert(ns.Backup.Read(ns.Backup.Export()))
		eq(checked.books[1].lines[1].contributionIdentityInvalid, true)
		eq(checked.books[1].contributionSources, nil)
		eq(checked.books[1].contributionNativeClaims, nil)
		ns.rdb.treasuryBooks = {}
		assert(T.RestoreBook(checked.books[1]))
		eq(T.ClassifyContribution(T.Book().lines[1], nil, OTHER, 'archive 12'), false,
			'a formatting/backup roundtrip cannot turn a known foreign donor into a local candidate')
	end)
end)

test('federation contribution sources: historical recognition uses original receipt week, not the review week', function()
	World(function(Set)
		Set(_G, 'GetServerTime', function() return AT - 8 * 86400 end)
		local e = Record('mail', false)
		e.t = AT - 8 * 86400 -- retained historical ledger timestamp, before this review
		Set(_G, 'GetServerTime', function() return AT end)
		assert(T.ClassifyContribution(e, nil, OTHER, 'historical receipt 12'))
		GrantName()
		eq(C.Project(AT), ('CP~1~B~%s~%d~~Lime Field=34567'):format(SCOPE, AT))
	end)
end)


test('federation contribution sources: identical original receipt tuples each retain their own private classification after backup restore', function()
	World(function()
		T.Book(true).opening = 0
		local first, second = Record('mail', false), Record('mail', false)
		eq(first.t, second.t, 'two real receipts may have the same second, sender and amount')
		local before = ns.Backup.Data().books[1]
		assert(T.ClassifyContribution(first, nil, OTHER, 'archive receipt one'))
		assert(T.ClassifyContribution(second, nil, OTHER, 'archive receipt two'))
		assert(T.RestoreBook(before))
		eq(#T.Book().lines, 2); eq(T.Totals().allIn, 69134)
		for _, e in ipairs(T.Book().lines) do eq(e.kind, 'charity'); eq(e.name, 'Anonymous Patron') end
		eq(#T.PublicRanking(T.Book()), 0)
		GrantName(); assert(C.Project(AT):find('Lime Field=69134', 1, true))
	end)
end)
