local ns, test, eq = ...
local C, D, P, T = ns.Contributions, ns.Dues, ns.FederationProgram, ns.Treasury
local AT, R, GROUP, SCOPE = 1795000000, "CAMWOWUS1Realm2PvE", "ForeverPvE", "ForeverPvE:Alliance:US"
local TREASURER, FIRST, SECOND, OFFICER = "Silver Rock-" .. R, "Lime Field-" .. R, "Blue Ocean-" .. R, "Amber Vale-" .. R
local PRIME, OTHER = "Olympus Prime", "Olympus Azure"

local function World(run)
	local undo, guild, time, rank, evidence = {}, PRIME, AT, 1, "signed"
	local function Set(t, k, v)
		local old = t[k]
		undo[#undo + 1] = function() t[k] = old end
		t[k] = v
	end
	Set(ns, "rdb", { treasuryBooks = {} })
	Set(ns, "db", {})
	Set(ns, "me", TREASURER)
	Set(ns, "realm", R)
	Set(ns, "group", GROUP)
	Set(ns, "faction", "Alliance")
	Set(ns, "splitNames", true)
	Set(ns, "IsMember", function() return true end)
	-- The board reader is an admitted participant in this isolated Treasury scene.
	-- The denial regression below explicitly withdraws that independent grant.
	Set(ns, "SharedPeerAllowed", function(name) return name == OFFICER end)
	Set(ns, "IsTreasurer", function(name) return name == TREASURER and guild == PRIME end)
	Set(ns, "TreasurerPins", function() return { TREASURER }, true end)
	Set(ns.Data, "AuthorizedRank", function(name, g) if name == OFFICER and g:lower() == PRIME:lower() then return rank, evidence end end)
	Set(P, "ContributionsPolicy", function() return true, true end)
	Set(P, "IsEnrolled", function(g) return g == OTHER end)
	Set(T, "DevView", function() return false end)
	Set(T, "KeeperByName", function() return false end)
	Set(T, "Share", function() return false end)
	Set(_G, "GetGuildInfo", function() return guild end)
	Set(_G, "GetServerTime", function() return time end)
	-- Treasury stamps receipts with ns.Now; consent and weekly projections use server time.
	-- Both must follow this scene's clock rather than the date the test happens to run.
	Set(ns, "Now", function() return time end)
	Set(_G, "IsInInstance", function() return false end)
	Set(_G, "InCombatLockdown", function() return false end)
	local ok, err = pcall(run, Set, function(g) guild = g end, function(now) time = now end,
		function(r, from) rank, evidence = r, from end)
	for i = #undo, 1, -1 do undo[i]() end
	if not ok then error(err, 0) end
end

local function Record(name, copper, guild)
	return T.Record(name, copper, "trade", nil, { observed = true, guild = guild, quiet = true })
end

test("federation donor privacy: observed gold counts in the balance but default ranking bytes omit any identity or amount", function()
	World(function()
		local e = Record(FIRST, 34567, OTHER)
		eq(e.t, AT, "the native receipt uses the same clock as the weekly projection")
		eq(e.kind, "charity")
		eq(T.Totals().allIn, 34567)
		eq(#T.PublicRanking(T.Book()), 0, "legacy public ranks omit protected receipt")
		eq(#T.DonationRecords(), 0, "legacy honors omit protected receipt")
		local legacy = T.Message()
		eq(legacy:find("Lime Field", 1, true), nil, "no protected donor name in legacy Treasury wire")
		eq(D.Ledger().players[D.Key(FIRST)], nil)
		eq(C.Project(AT), ("CP~1~B~%s~%d~?~?"):format(SCOPE, AT))
	end)
end)

test("federation donor privacy: explicit direct character choice grants a named row and expiry or withdrawal redacts it", function()
	World(function(_, _, Move)
		Record(FIRST, 34567, OTHER)
		Record(SECOND, 15000, OTHER)
		local offer = ("CP~1~P~%s~%d~1"):format(SCOPE, AT)
		eq(C.Handle("CHANNEL", FIRST, offer), false, "a relayed or channel claim is not consent")
		eq(C.Handle("WHISPER", OFFICER, offer), false, "only a recorded donor can grant consent")
		eq(C.Handle("WHISPER", FIRST, offer), true)
		local board = C.Project(AT)
		assert(board:find("Lime Field=34567", 1, true))
		eq(board:find("Blue Ocean", 1, true), nil)
		eq(board:find("15000", 1, true), nil)
		eq(C.Handle("WHISPER", FIRST, ("CP~1~P~%s~%d~0"):format(SCOPE, AT)), true)
		eq(C.Handle("WHISPER", FIRST, offer), false, "a stale replay cannot undo withdrawal")
		eq(C.Project(AT):find("Lime Field", 1, true), nil)
		eq(C.Handle("WHISPER", SECOND, offer), true)
		Move(AT + 3601)
		eq(C.Project(AT + 3601):find("Blue Ocean", 1, true), nil)
	end)
end)

test("federation donor privacy: contribution interest has its own consent and is sent only on exact scoped Prime authority", function()
	World(function(Set, _, _, Rank)
		local sent = {}
		Set(T, "Private", function(to, kind, body) sent[#sent + 1] = { to, kind, body }; return true end)
		Set(ns.Verify, "Status", function(guild) if guild == OTHER then return "verified" end end)
		Record(FIRST, 34567, OTHER)
		Record(SECOND, 15000, OTHER)
		eq(C.HandleInterest("WHISPER", FIRST, ("CI~1~P~%s~%d~1"):format(SCOPE, AT)), true)
		eq(C.Handle("WHISPER", SECOND, ("CP~1~P~%s~%d~1"):format(SCOPE, AT)), true)
		local request = "CI~1~Q~" .. SCOPE
		eq(C.HandleInterest("WHISPER", SECOND, request), false)
		eq(C.HandleInterest("WHISPER", OFFICER:gsub("US1", "EU1"), request), false)
		Rank(1, "census")
		eq(C.HandleInterest("WHISPER", OFFICER, request), false, "census claims cannot grant a private read")
		Rank(1, "signed")
		eq(C.HandleInterest("WHISPER", OFFICER, request), true)
		eq(#sent, 1)
		eq(sent[1][1], OFFICER)
		eq(sent[1][2], "CI")
		assert(sent[1][3]:find(FIRST .. "=W:V", 1, true))
		for _, text in ipairs({ SECOND, "34567", OTHER }) do eq(sent[1][3]:find(text, 1, true), nil) end
		eq(C.Project(AT):find("Lime Field", 1, true), nil, "Prime interest must never grant public name consent")
	end)
end)

test("federation contributions daily dues: only live Prime, once per day, without fabricating arrears", function()
	World(function(Set, Guild, Move)
		local modal = {}
		Set(ns, "me", FIRST)
		Set(T, "IsKeeper", function() return false end)
		Set(ns, "ShowDialog", function(id, description) modal[#modal + 1] = { id, description }; return {} end)
		Set(ns, "Print", function() end)
		Guild(OTHER)
		eq(D.DailyReminder(), false)
		Guild(PRIME)
		eq(D.DailyReminder(), true)
		eq(modal[1][1], "OLYMPUS_DUES_DAILY")
		assert(modal[1][2]:find(ns.L.DUES_DAILY_GRACE, 1, true))
		eq(D.DailyReminder(), false)
		Move(AT + 86400)
		eq(D.DailyReminder(), true)
	end)
end)

test("federation donor privacy: Treasury backup redacts donor identity while preserving the protected accounting line", function()
	World(function()
		T.Book().opening = 0
		local e = Record(FIRST, 34567, OTHER)
		assert(e and e.kind == "charity")
		local packed = ns.Backup.Export()
		local restored = assert(ns.Backup.Read(packed))
		eq(#restored.books[1].lines, 1)
		local line = restored.books[1].lines[1]
		eq(line.kind, "charity")
		eq(line.name, "Anonymous Patron")
		eq(line.patron, nil)
		eq(line.guild, nil)
		eq(restored.books[1].sums.allIn, 34567)
		assert(T.RestoreBook(restored.books[1]))
		eq(T.Book().lines[1].patron, FIRST, "existing private native source remains local")
		eq(T.Totals().allIn, 34567, "copy must not duplicate recorded gold")
	end)
end)

test("federation contributions milestones: legacy author-signed scoped notes still require the pinned Treasurer", function()
	World(function(Set)
		local okSig = string.rep("d", 512)
		Set(ns.Sign, "Verify", function(_, sig) return sig == okSig end)
		local function Blob(issuer, sig, region)
			local head = ("HT1~%d~%s~0~"):format(AT, GROUP)
			return head .. ("^contributionmilestones^Alliance^%s^%s^Workshop completed=Guild crafting event"):format(region or "US", issuer) .. "~" .. (sig or okSig)
		end
		assert(C.SaveMilestoneDraft("First event | Crafting workshop held"))
		local rows = {}
		C.MilestoneLines(rows)
		eq(#rows, 0, "local draft is not public")
		ns.rdb.councilTitles = { blob = Blob(TREASURER, string.rep("e", 512)) }
		C.MilestoneLines(rows); eq(#rows, 0)
		ns.rdb.councilTitles = { blob = Blob(OFFICER) }
		C.MilestoneLines(rows); eq(#rows, 0)
		ns.rdb.councilTitles = { blob = Blob(TREASURER, okSig, "EU") }
		C.MilestoneLines(rows); eq(#rows, 0)
		ns.rdb.councilTitles = { blob = Blob(TREASURER) }
		C.MilestoneLines(rows); eq(#rows, 2)
		eq(rows[2].text, "Workshop completed")
	end)
end)

test("federation donor privacy: revocation invalidates a previously queued named answer", function()
	World(function(Set)
		T.ResetPrivate()
		local ok, err = pcall(function()
			local guard
			Set(ns.Comm, "QueueSize", function() return 0 end)
			Set(ns.Comm, "SendBatch", function(_, _, _, _, _, _, opts) guard = opts.guard; return true end)
			Set(ns.Comm, "Cancel", function() end)
			Record(FIRST, 34567, OTHER)
			eq(C.Handle("WHISPER", FIRST, ("CP~1~P~%s~%d~1"):format(SCOPE, AT)), true)
			eq(C.Handle("WHISPER", OFFICER, "CP~1~Q~" .. SCOPE), true)
			assert(guard and guard())
			eq(C.Handle("WHISPER", FIRST, ("CP~1~P~%s~%d~0"):format(SCOPE, AT)), true)
			eq(guard(), false, "already paced messages must not disclose a withdrawn name")
		end)
		T.ResetPrivate()
		if not ok then error(err, 0) end
	end)
end)

test("federation donor privacy: board membership is checked at request and dispatch without blocking withdrawal", function()
	World(function(Set, _, SetTime)
		-- Contributions keeps its five-minute request window in memory across
		-- book resets. Advance beyond the earlier case instead of resetting it.
		local now = AT + 601
		SetTime(now)
		T.ResetPrivate()
		local ok, err = pcall(function()
			local guard, admitted = nil, false
			Set(ns, "SharedPeerAllowed", function(name) return name == OFFICER and admitted end)
			Set(ns.Comm, "QueueSize", function() return 0 end)
			Set(ns.Comm, "SendBatch", function(_, _, _, _, _, _, opts) guard = opts.guard; return true end)
			Set(ns.Comm, "Cancel", function() end)
			Record(FIRST, 34567, OTHER)
			assert(C.Handle("WHISPER", FIRST, ("CP~1~P~%s~%d~1"):format(SCOPE, now)))
			eq(C.Handle("WHISPER", OFFICER, "CP~1~Q~" .. SCOPE), false)
			eq(guard, nil, "no board enters the queue for an unadmitted reader")
			admitted = true
			assert(C.Handle("WHISPER", OFFICER, "CP~1~Q~" .. SCOPE))
			assert(guard and guard())
			admitted = false
			eq(guard(), false, "a queued board cannot outlive recipient participation")
			assert(C.Handle("WHISPER", FIRST, ("CP~1~P~%s~%d~0"):format(SCOPE, now)), "a donor can still withdraw consent")
		end)
		T.ResetPrivate()
		if not ok then error(err, 0) end
	end)
end)
