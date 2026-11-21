local _, ns = ...
local D, T, P, L = ns.Dues, ns.Treasury, ns.FederationProgram, ns.L
local C = {}
ns.Contributions = C

local TOP, PATRONS, CHOICE_FOR, BOARD_FOR = 10, 1000, 3600, 300
local held, askedAt, sentChoiceAt, replies, requests = nil, -math.huge, -math.huge, {}, {}
local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Whole(n, max) return type(n) == "number" and n == n and n % 1 == 0 and n >= 1 and n <= max end
local function Region(realm) return type(realm) == "string" and realm:match("^CAMWOW(%u%u)%d+Realm%d+%a+$") end
local function PlayerName(short)
	return type(short) == "string" and #short <= 48 and short:match("^[%a\128-\255 ]+$") and short:match("^[^ ]+ ?[^ ]*$")
end
local function Name(full)
	if type(full) ~= "string" or ns.Secret(nil, full) or #full > 90 then return nil end
	local short, realm = full:match("^([%a\128-\255 ]+)%-([%w\128-\255]+)$")
	if PlayerName(short) and ns.ForeverFamily(realm) == ns.group and Region(realm) == Region(ns.realm) then
		return ns.Fold(full)
	end
end
local function Scope()
	local region = Region(ns.realm)
	if region and ns.group and ns.faction then return table.concat({ ns.group, ns.faction, region }, ":") end
end
local function Treasurer()
	local _, enabled = P.ContributionsPolicy()
	if not enabled then return nil end
	local names, signed = ns.TreasurerPins()
	local first = signed and names[1]
	if Name(first) then return first end
end
local function IsTreasurer(name)
	local exact, pin = Name(name), Treasurer()
	return exact ~= nil and pin ~= nil and exact == Name(pin)
end
local function Staff()
	return IsTreasurer(ns.me) and ns.IsMember() and D.MandatoryGuild(GetGuildInfo("player"))
		and ns.IsTreasurer(ns.me, GetGuildInfo("player")) == true
		and not T.DevView() and not ns.King.Preview() and not (ns.ViewAs and ns.ViewAs.Previewing and ns.ViewAs.Previewing())
end
local function Visible() return D.ContributionGuild() ~= nil and Treasurer() ~= nil end

-- Receipt provenance stays in the Treasurer's private book, never in a public snapshot or
-- clipboard backup. A subject's guild is a claim, not native membership evidence.
local SOURCES = 5000
local function Eligible(book, e, full)
	return type(book) == "table" and type(e) == "table" and not e.kind and not e.out and not e.item and not e.excluded and not e.returned and not e.contributionIdentityInvalid
		and (e.how == "trade" or e.how == "mail") and Name(full) ~= nil and Whole(e.money, T.MAX_COPPER)
		and Staff() and IsTreasurer(book.name) and book == T.BookOf(ns.me)
end
function C.StampIdentity(book, e, full)
	-- Legacy book display names can omit a realm. Preserve a negative scope result before
	-- that formatting so a later manual review cannot relabel a known foreign donor.
	if type(book) == "table" and type(e) == "table" and Staff() and book == T.BookOf(ns.me) then
		if ns.Secret(nil, full) or not Name(ns.FullName(ns.Normal(full))) then e.contributionIdentityInvalid = true end
	end
end
local function EligibleGuild(guild)
	return type(guild) == "string" and not D.MandatoryGuild(guild) and P.IsEnrolled(guild)
end
local function Sources(book, create)
	if type(book.contributionSources) ~= "table" and create then book.contributionSources = {} end
	return type(book.contributionSources) == "table" and book.contributionSources or nil
end
local function Receipt(book, e)
	local sources = Sources(book)
	local r = sources and sources[e.contributionReceipt]
	return type(r) == "table" and r.at == e.t and r.money == e.money and r.how == e.how and r or nil
end
local function KeepReceipt(book, e, full, guild, source, reference)
	local r = Receipt(book, e)
	if r then return Name(r.name) == Name(full) and r or nil end
	local sources = Sources(book, true)
	local n = 0; for _ in pairs(sources) do n = n + 1 end
	if n >= SOURCES then
		local retained = {}; for _, line in ipairs(book.lines or {}) do if line.contributionReceipt then retained[line.contributionReceipt] = true end end
		for id in pairs(sources) do if not retained[id] then sources[id], n = nil, n - 1 end end
		if n >= SOURCES then return nil end
	end
	local id = (tonumber(book.contributionNext) or 0) + 1
	if not Whole(id, T.MAX_COPPER) then return nil end
	book.contributionNext, e.contributionReceipt = id, id
	r = { at = e.t, money = e.money, how = e.how, name = full, guild = guild, source = source, reference = reference }
	sources[id] = r
	return r
end
local function Protect(book, e, full, guild, source, reference, nativeKey)
	if not Eligible(book, e, full) or not EligibleGuild(guild) then return false end
	local claims = type(book.contributionNativeClaims) == "table" and book.contributionNativeClaims or {}
	if nativeKey and claims[nativeKey] and claims[nativeKey] ~= e.contributionReceipt then return false end
	local r = KeepReceipt(book, e, full, guild, source, reference)
	if not r or r.counted then return false end
	r.guild, r.source, r.reference, r.nativeKey = guild, source, reference, nativeKey
	if nativeKey then
		book.contributionNativeClaims = claims
		claims[nativeKey] = e.contributionReceipt
	end
	e.kind, e.patron, e.contributionScope, e.name, e.guild, e.gv = "charity", full, Scope(), "Anonymous Patron", guild, source ~= "treasurer-attested" or nil
	return true
end
function C.ProtectTrade(book, e, full, observedGuild)
	if e.how ~= "trade" or observedGuild ~= e.guild then return false end
	return Protect(book, e, full, observedGuild, "native-trade")
end
function C.NativeReceipt(book, e, full, observedGuild)
	if ns.Secret(nil, full) then return false end
	full = ns.FullName(ns.Normal(full))
	if not Eligible(book, e, full) then return false end
	local guild, source = observedGuild, "native-trade"
	if e.how == "mail" then
		guild, source = nil, "native-mail"
		local seen, age
		if ns.Who and ns.Who.SeenGuild then seen, age = ns.Who.SeenGuild(full) end
		if type(age) == "number" and age >= 0 and age <= 120 then guild = seen end
	end
	-- Preserve the native receipt even when its donor's guild remains unknown. It can be
	-- explicitly reviewed later; no guild is taken from the mail subject or a census guess.
	if not KeepReceipt(book, e, full, guild, source) then return false end
	return Protect(book, e, full, guild, source)
end
local function InBook(book, e)
	for _, row in ipairs(type(book) == "table" and book.lines or {}) do if row == e then return true end end
	return false
end
function C.Classification(book, e, guild, reference)
	if not InBook(book, e) then return nil end
	local full = e.patron or ns.FullName(ns.Normal(e.name))
	if not Eligible(book, e, full) then return nil end
	local r = Receipt(book, e)
	if not r and ns.GuildFinance and ns.GuildFinance.ContributionSource then
		r = ns.GuildFinance.ContributionSource(book, e)
	end
	local claims = type(book.contributionNativeClaims) == "table" and book.contributionNativeClaims or {}
	if r and r.nativeKey and claims[r.nativeKey] and claims[r.nativeKey] ~= e.contributionReceipt then return nil end
	if reference == nil then
		if not r or not EligibleGuild(r.guild) then return nil end
		return { full = full, guild = r.guild, source = r.source or ("native-" .. e.how), nativeKey = r.nativeKey }
	end
	-- An attestation is an explicit Treasurer action, separately labelled. Membership is
	-- still limited to an existing enrolled guild: arbitrary free-text guilds cannot enter.
	if type(reference) ~= "string" or #reference < 3 or #reference > 80 or reference:find("[|~^;%c]")
		or not reference:find("%S") or not EligibleGuild(guild) then return nil end
	if r and type(r.guild) == "string" and r.guild ~= "" and ns.Fold(r.guild) ~= ns.Fold(guild) then return nil end
	return { full = full, guild = guild, source = "treasurer-attested", reference = reference, nativeKey = r and r.nativeKey }
end
function C.ProtectRecorded(book, e, proof)
	if type(proof) ~= "table" then return false end
	return Protect(book, e, proof.full, proof.guild, proof.source, proof.reference, proof.nativeKey)
end
function C.SourceLabel(book, e)
	local r = Receipt(book, e)
	return r and r.source, r and r.reference
end
function C.Count(book, e, sign)
	local key = Name(e.patron)
	local receipt = Receipt(book, e)
	if receipt and ((sign > 0 and receipt.counted) or (sign < 0 and not receipt.counted)) then return end
	if e.kind ~= "charity" or not key or not e.contributionScope or not Whole(e.money, T.MAX_COPPER) then return end
	book.contributionPatrons = type(book.contributionPatrons) == "table" and book.contributionPatrons or {}
	local bookScope = book.contributionPatrons[e.contributionScope]
	if type(bookScope) ~= "table" then bookScope = {}; book.contributionPatrons[e.contributionScope] = bookScope end
	local row = bookScope[key]
	if not row then
		if sign < 0 then return end
		local n = 0
		for _ in pairs(bookScope) do n = n + 1 end
		if n >= PATRONS then return end
		row = { name = e.patron, total = 0, weeks = {} }
		bookScope[key] = row
	end
	if receipt then receipt.counted = sign > 0 end
	row.total = math.max(0, math.min(T.MAX_COPPER, row.total + sign * e.money))
	if sign > 0 and e.t >= (row.guildAt or 0) then row.guild, row.guildAt = e.guild, e.t
	elseif sign < 0 and row.guildAt == e.t then row.guild, row.guildAt = nil, nil end
	local week = D.WeekOf(e.t)
	row.weeks[week] = math.max(0, math.min(T.MAX_COPPER, (row.weeks[week] or 0) + sign * e.money))
	for wk in pairs(row.weeks) do if wk < D.Week() - 1 then row.weeks[wk] = nil end end
	if row.total <= 0 then bookScope[key] = nil end
end
local function Rows()
	local book = Staff() and T.BookOf(ns.me)
	local root, scope = book and book.contributionPatrons, Scope()
	return type(root) == "table" and root[scope] or nil
end
local function Preferences(field, create)
	local scope = Scope()
	if not scope or not ns.rdb then return nil end
	local root = ns.rdb[field]
	if not root and create then root = {}; ns.rdb[field] = root end
	if type(root) ~= "table" then return nil end
	if not root[scope] and create then root[scope] = {} end
	return root[scope]
end
local function Choices(now)
	local prefs = Preferences("contributionNameChoices")
	for key, v in pairs(prefs or {}) do
		if type(v) ~= "table" or not Whole(v.at, 9999999999) or now - v.at > CHOICE_FOR then prefs[key] = nil end
	end
	return prefs or {}
end

local function BoardRows(weekly, asOf, now)
	local rows, prefs = {}, Choices(now)
	for key, row in pairs(Rows() or {}) do
		local copper = weekly and row.weeks[D.WeekOf(asOf)] or not weekly and row.total
		local choice = prefs[key]
		if Whole(copper, T.MAX_COPPER) and Name(row.name) == key then
			rows[#rows + 1] = { rank = copper, display = choice and choice.on == true and row.name or nil, order = key }
		end
	end
	table.sort(rows, function(a, b)
		if a.rank ~= b.rank then return a.rank > b.rank end
		return a.order < b.order
	end)
	local out = {}
	for i = 1, math.min(#rows, TOP) do
		local row = rows[i]
		-- Never transmit an anonymous donor's amount, stable pseudonym, guild or identity.
		out[i] = row.display and (ns.ShortName(row.display) .. "=" .. row.rank) or "?"
	end
	return table.concat(out, ";")
end
function C.Project(asOf)
	local now, scope = Clock(), Scope()
	if not Staff() or not scope or not Whole(asOf, 9999999999) or now - asOf < 0 or now - asOf > BOARD_FOR then return nil end
	return ("CP~1~B~%s~%d~%s~%s"):format(scope, asOf, BoardRows(true, asOf, now), BoardRows(false, asOf, now))
end
local function ParseBoard(text)
	local scope, at, week, total = text:match("^CP~1~B~([^~]+)~(%d+)~([^~]*)~([^~]*)$")
	at = tonumber(at)
	if not scope or scope ~= Scope() or not Whole(at, 9999999999) or Clock() - at > BOARD_FOR or at - Clock() > 30 then return nil end
	local rows = { at = at, scope = scope, week = {}, total = {} }
	for _, part in ipairs({ { week, rows.week }, { total, rows.total } }) do
		if part[1] ~= "" then
			for _, word in ipairs(ns.Codec.Split(part[1], ";")) do
				if #part[2] >= TOP then return nil end
				if word == "?" then part[2][#part[2] + 1] = {}
				else
					local name, copper = word:match("^([^=]+)=(%d+)$")
					copper = tonumber(copper)
					if not PlayerName(name) or not Whole(copper, T.MAX_COPPER) then return nil end
					part[2][#part[2] + 1] = { name = name, copper = copper }
				end
			end
		end
	end
	return rows
end
function C.Handle(dist, sender, text)
	local key, now = Name(sender), Clock()
	if dist ~= "WHISPER" or not key or type(text) ~= "string" or #text > 2400 then return false end
	local scope, at, on = text:match("^CP~1~P~([^~]+)~(%d+)~([01])$")
	at = tonumber(at)
	if scope and scope == Scope() and Whole(at, 9999999999) and math.abs(now - at) <= 120 and Staff() then
		local rows = Rows()
		if not rows or not rows[key] then return false end
		local prefs = Preferences("contributionNameChoices", true)
		local previous = prefs and prefs[key]
		if previous and (at < previous.at or (at == previous.at and (previous.on == false or on == "1"))) then return false end
		if not prefs then return false end
		prefs[key] = { on = on == "1", at = at }
		-- The guard also rebuilds at dispatch, covering pending reads after donor withdrawal.
		if on == "0" then T.CancelPrivate(function(job) return job.kind == "CP" end) end
		return true
	end
	if text == "CP~1~Q~" .. (Scope() or "") and Staff() then
		if not ns.SharedPeerAllowed(sender) then return false end
		for k, expires in pairs(requests) do if expires <= now then requests[k], replies[k] = nil, nil end end
		local n = 0; for _ in pairs(requests) do n = n + 1 end
		if requests[key] or n >= 64 then return false end
		local body = C.Project(now)
		requests[key], replies[key] = now + BOARD_FOR, body
		return body and T.Private(sender, "CP", body, "charitable contribution board") or false
	end
	if not Visible() or not IsTreasurer(sender) or now - askedAt > BOARD_FOR then return false end
	local data = ParseBoard(text)
	if not data or (held and held.by == key and data.at < held.at) then return false end
	data.by = key
	held = data
	ns.After(math.max(1, data.at + BOARD_FOR - now), "contribution board expiry", function()
		if held == data then held = nil; ns.Fire("DATA_CHANGED") end
	end)
	ns.Fire("DATA_CHANGED")
	return true
end
ns.Comm.Handle("CP", C.Handle)
T.OnPrivate("CP", {
	from = IsTreasurer, to = Visible, ranking = true,
	send = function(to, text)
		local key = Name(to)
		if not key or replies[key] ~= text or not ns.SharedPeerAllowed(to) then return false end
		local data = ParseBoard(text)
		return data ~= nil and C.Project(data.at) == text
	end,
	handle = C.Handle,
})

function C.Request()
	local to, now, scope = Treasurer(), Clock(), Scope()
	if not Visible() or not to or not scope or now - askedAt < 60 then return false end
	askedAt = now
	return ns.Comm.Whisper(to, "CP~1~Q~" .. scope, "charitable contribution ask", nil, nil, nil,
		{ guard = function() return Visible() and scope == Scope() and IsTreasurer(to) end })
end
local function OwnChoice(create)
	local me, scope = Name(ns.me), Scope()
	if not ns.db or not me or not scope then return nil end
	local root = ns.db.contributionNamePreference
	if not root and create then root = {}; ns.db.contributionNamePreference = root end
	if type(root) ~= "table" then return nil end
	local key = scope .. "|" .. me
	if not root[key] and create then root[key] = {} end
	return root[key]
end
function C.ShareChoice(force)
	local to, own, now, scope = Treasurer(), OwnChoice(), Clock(), Scope()
	if not to or not own or not Visible() or (own.on ~= true and now - (own.at or 0) >= CHOICE_FOR)
		or (not force and now - sentChoiceAt < 20 * 60) then return false end
	local on, me = own.on, Name(ns.me)
	sentChoiceAt = now
	return ns.Comm.Whisper(to, ("CP~1~P~%s~%d~%d"):format(scope, now, on and 1 or 0), "charitable name choice", nil, nil, nil,
		{ guard = function()
			return Name(ns.me) == me and scope == Scope() and Visible() and IsTreasurer(to) and OwnChoice() == own and own.on == on
		end })
end
function C.SetNameVisible(on)
	if not Visible() then return false end
	local own = OwnChoice(true)
	if not own then return false end
	own.on, own.at = on == true, Clock()
	C.ShareChoice(true)
	ns.Fire("DATA_CHANGED")
	return true
end
function C.RankLines(lines)
	if not Visible() then return end
	local own = OwnChoice()
	local show = own and own.on == true
	lines[#lines + 1] = { text = show and L.CONTRIBUTIONS_ANON_ACTION or L.CONTRIBUTIONS_NAME_ACTION,
		tooltip = function(tt) tt:AddLine(L.CONTRIBUTIONS_NAME_TIP, 1, 1, 1, true) end,
		onClick = function() C.SetNameVisible(not show) end, gapAfter = true }
	if C.InterestChoiceLine then lines[#lines + 1] = C.InterestChoiceLine() end
	lines[#lines + 1] = { text = L.CONTRIBUTIONS_REFRESH, onClick = C.Request, gapAfter = true }
	local data = held
	if not data or data.scope ~= Scope() or data.by ~= Name(Treasurer()) or Clock() - data.at > BOARD_FOR then
		lines[#lines + 1] = { text = L.CONTRIBUTIONS_WAITING }
		return
	end
	for _, window in ipairs({ { L.CONTRIBUTIONS_WEEKLY, data.week }, { L.CONTRIBUTIONS_ALL, data.total } }) do
		lines[#lines + 1] = { header = true, text = window[1] }
		if #window[2] == 0 then lines[#lines + 1] = { text = L.CONTRIBUTIONS_EMPTY } end
		for i, row in ipairs(window[2]) do
			lines[#lines + 1] = { indent = 1, text = i .. ". " .. (row.name and ns.DisplayName(row.name) or L.CONTRIBUTIONS_ANONYMOUS),
				right = row.copper and T.Coins(row.copper) or nil }
		end
	end
end

-- Prime interest has a separate consent and data path. A willing donor's private roster row
-- exposes one exact game character, a rank band and the verification of the last verified
-- contribution's guild. It carries no amount, guild name, BattleTag, Discord ID or invite.
local INTEREST_FOR, INTEREST_LIMIT = 7 * 86400, 20
local interestHeld, interestAsked, interestSent = nil, -math.huge, -math.huge
local interestReplies, interestRequests = {}, {}
local function PrimeOfficer(name)
	if IsTreasurer(name) then return true end
	if not Treasurer() or not Name(name) then return false end
	local prime = ns.KingGuildName()
	if not prime or not D.MandatoryGuild(prime) then return false end
	local rank
	if ns.IsMember() and D.MandatoryGuild(GetGuildInfo("player")) and ns.Roster.Fresh() then
		rank = ns.Roster.RankOf(name)
	else
		local evidence
		rank, evidence = ns.Data.AuthorizedRank(name, prime)
		if evidence ~= "signed" then return false end
	end
	return type(rank) == "number" and rank >= 0 and rank <= ns.CAPTAIN_RANK
end
local function InterestStaff()
	return ns.IsMember() and D.MandatoryGuild(GetGuildInfo("player")) and PrimeOfficer(ns.me)
		and not T.DevView() and not ns.King.Preview() and not (ns.ViewAs and ns.ViewAs.Previewing and ns.ViewAs.Previewing())
end
local function InterestRows(at)
	local scope, now = Scope(), Clock()
	if not Staff() or not scope or not Whole(at, 9999999999) or now - at < 0 or now - at > BOARD_FOR then return nil end
	local prefs, rows, donors = Preferences("contributionInterest"), {}, Rows() or {}
	local bands, active = {}, {}
	for _, mode in ipairs({ "A", "W" }) do
		local ordered = {}
		for key, row in pairs(donors) do
			local n = mode == "W" and row.weeks[D.WeekOf(at)] or mode == "A" and row.total
			if Whole(n, T.MAX_COPPER) then ordered[#ordered + 1] = { key = key, n = n } end
		end
		table.sort(ordered, function(a, b) return a.n > b.n or a.n == b.n and a.key < b.key end)
		for i = 1, math.min(#ordered, TOP) do bands[ordered[i].key] = mode end
	end
	for key, choice in pairs(prefs or {}) do
		local row = donors[key]
		if type(choice) ~= "table" or not Whole(choice.at, 9999999999) or now - choice.at > INTEREST_FOR then prefs[key] = nil
		elseif choice.on == true and row and Name(row.name) == key then
			active[#active + 1] = key
		end
	end
	table.sort(active)
	for i = 1, math.min(#active, INTEREST_LIMIT) do
		local key = active[i]
		local row = donors[key]
		local verified = row.guild and Whole(row.guildAt, 9999999999) and now - row.guildAt <= INTEREST_FOR
			and P.IsEnrolled(row.guild) and ns.Verify and ns.Verify.Status(row.guild) == "verified"
		rows[i] = ("%s=%s:%s"):format(row.name, bands[key] or "C", verified and "V" or "U")
	end
	return ("CI~1~B~%s~%d~%s"):format(scope, at, table.concat(rows, ";"))
end
local function InterestParse(text)
	local scope, at, body = text:match("^CI~1~B~([^~]+)~(%d+)~([^~]*)$")
	at = tonumber(at)
	if not scope or scope ~= Scope() or not Whole(at, 9999999999) or Clock() - at > BOARD_FOR or at - Clock() > 30 then return nil end
	local data = { scope = scope, at = at, rows = {} }
	for _, item in ipairs(body ~= "" and ns.Codec.Split(body, ";") or {}) do
		local name, rank, guild = item:match("^([^=]+)=([AWC]):([VU])$")
		if not Name(name) or #data.rows >= INTEREST_LIMIT then return nil end
		data.rows[#data.rows + 1] = { name = name, band = rank, verified = guild == "V" }
	end
	return data
end
function C.HandleInterest(dist, sender, text)
	local senderKey, now = Name(sender), Clock()
	if dist ~= "WHISPER" or not senderKey or type(text) ~= "string" or #text > 2400 then return false end
	local scope, at, on = text:match("^CI~1~P~([^~]+)~(%d+)~([01])$")
	at = tonumber(at)
	if scope and scope == Scope() and Whole(at, 9999999999) and math.abs(now - at) <= 120 and Staff() then
		local donors, prefs = Rows(), Preferences("contributionInterest", true)
		if not donors or not donors[senderKey] or not prefs then return false end
		local previous = prefs[senderKey]
		if previous and (at < previous.at or (at == previous.at and (previous.on == false or on == "1"))) then return false end
		prefs[senderKey] = { on = on == "1", at = at }
		if on == "0" then T.CancelPrivate(function(job) return job.kind == "CI" end) end
		ns.Fire("DATA_CHANGED")
		return true
	end
	if text == "CI~1~Q~" .. (Scope() or "") and Staff() and PrimeOfficer(sender) then
		for key, expires in pairs(interestRequests) do if expires <= now then interestRequests[key], interestReplies[key] = nil, nil end end
		local n = 0; for _ in pairs(interestRequests) do n = n + 1 end
		if n >= 20 or interestRequests[senderKey] then return false end
		local body = InterestRows(now)
		interestRequests[senderKey], interestReplies[senderKey] = now + 60, body
		return body and T.Private(sender, "CI", body, "prime recruitment interest") or false
	end
	if not InterestStaff() or not IsTreasurer(sender) or now - interestAsked > BOARD_FOR then return false end
	local data = InterestParse(text)
	if not data or (interestHeld and interestHeld.by == senderKey and data.at < interestHeld.at) then return false end
	data.by, interestHeld = senderKey, data
	ns.After(math.max(1, data.at + BOARD_FOR - now), "prime interest expiry", function()
		if interestHeld == data then interestHeld = nil; ns.Fire("DATA_CHANGED") end
	end)
	ns.Fire("DATA_CHANGED")
	return true
end
ns.Comm.Handle("CI", C.HandleInterest)
T.OnPrivate("CI", {
	from = IsTreasurer, to = InterestStaff,
	send = function(to, text)
		if not PrimeOfficer(to) or interestReplies[Name(to)] ~= text then return false end
		local data = InterestParse(text)
		return data ~= nil and InterestRows(data.at) == text
	end,
	handle = C.HandleInterest,
})
local function SendInterest(force)
	local own, now = OwnChoice(), Clock()
	local to, scope = Treasurer(), Scope()
	if not Visible() or not to or not scope or not own or type(own.interest) ~= "boolean"
		or now - (own.interestAt or 0) > INTEREST_FOR or (not force and now - interestSent < 20 * 60) then return false end
	local on, stamp, me = own.interest, own.interestAt, Name(ns.me)
	interestSent = now
	return ns.Comm.Whisper(to, ("CI~1~P~%s~%d~%d"):format(scope, now, on and 1 or 0), "prime interest consent", nil, nil, nil,
		{ guard = function()
			return Visible() and Name(ns.me) == me and Scope() == scope and IsTreasurer(to)
				and OwnChoice() == own and own.interest == on and own.interestAt == stamp
		end })
end
function C.SetInterest(on)
	if not Visible() then return false end
	local own = OwnChoice(true)
	if not own then return false end
	own.interest, own.interestAt = on == true, Clock()
	SendInterest(true)
	ns.Fire("DATA_CHANGED")
	return true
end
function C.InterestChoiceLine()
	local own = OwnChoice()
	local on = own and own.interest == true and Clock() - (own.interestAt or 0) <= INTEREST_FOR
	return { text = on and L.CONTRIBUTIONS_INTEREST_OFF or L.CONTRIBUTIONS_INTEREST_ON,
		tooltip = function(tt) tt:AddLine(L.CONTRIBUTIONS_INTEREST_TIP, 1, 1, 1, true) end,
		onClick = function() C.SetInterest(not on) end, gapAfter = true }
end
local function AskInterest()
	local to, now, scope = Treasurer(), Clock(), Scope()
	if not InterestStaff() or not to or now - interestAsked < 60 then return false end
	interestAsked = now
	return ns.Comm.Whisper(to, "CI~1~Q~" .. scope, "prime recruitment interest ask", nil, nil, nil,
		{ guard = function() return InterestStaff() and scope == Scope() and IsTreasurer(to) end })
end
local function InterestLines()
	local lines = { { text = "< " .. L.TAB_REALM, onClick = function() ns.Views.ShowPage(nil) end, gapAfter = true } }
	if not InterestStaff() then return lines end
	lines[#lines + 1] = { header = true, text = L.CONTRIBUTIONS_INTEREST_TITLE }
	if Staff() then
		lines[#lines + 1] = { text = L.CONTRIBUTIONS_RECEIPT_REVIEW, onClick = function() ns.Views.ShowPage("contribution-receipts") end }
		lines[#lines + 1] = { text = L.CONTRIBUTIONS_MILESTONE_DRAFT, onClick = C.PromptMilestone }
		lines[#lines + 1] = { text = L.CONTRIBUTIONS_MILESTONE_PUBLISH, onClick = function()
			local ok = C.PublishMilestones()
			ns.Print(ok and L.CONTRIBUTIONS_MILESTONE_PUBLISHED or L.CONTRIBUTIONS_MILESTONE_UNAVAILABLE)
		end }
		lines[#lines + 1] = { text = L.CONTRIBUTIONS_MILESTONE_CLEAR, onClick = function()
			local ok = C.ClearMilestones()
			ns.Print(ok and L.CONTRIBUTIONS_MILESTONE_PUBLISHED or L.CONTRIBUTIONS_MILESTONE_UNAVAILABLE)
		end, gapAfter = true }
	end
	local data = Staff() and InterestParse(InterestRows(Clock())) or interestHeld
	if not Staff() then lines[#lines + 1] = { text = L.CONTRIBUTIONS_INTEREST_REFRESH, onClick = AskInterest } end
	if not data or data.scope ~= Scope() or (not Staff() and data.by ~= Name(Treasurer())) or Clock() - data.at > BOARD_FOR then
		lines[#lines + 1] = { text = L.CONTRIBUTIONS_WAITING }
		return lines
	end
	local bands = { A = L.CONTRIBUTIONS_ALL, W = L.CONTRIBUTIONS_WEEKLY, C = L.CONTRIBUTIONS_PATRON }
	for _, row in ipairs(data.rows) do
		lines[#lines + 1] = { text = ns.DisplayName(row.name), right = bands[row.band],
			tooltip = function(tt) tt:AddLine(row.verified and L.CONTRIBUTIONS_GUILD_VERIFIED or L.CONTRIBUTIONS_GUILD_UNKNOWN, 1, 1, 1, true) end }
	end
	return lines
end
table.insert(ns.RealmPages, { key = "prime-interest", Lines = InterestLines, Link = function()
	if not InterestStaff() then return nil end
	return { text = "> " .. L.CONTRIBUTIONS_INTEREST_TITLE, onClick = function()
		if InterestStaff() then
			ns.Views.ShowPage("prime-interest")
			if not Staff() then AskInterest() end
		end
	end }
end })
local function RecheckReaders()
	local cleared = false
	if held and not Visible() then held, cleared = nil, true end
	if interestHeld and not InterestStaff() then interestHeld, cleared = nil, true end
	if cleared then ns.Fire("DATA_CHANGED") end
end
ns.On("LOGIN", function()
	ns.Every(60, "charitable consent", function() C.ShareChoice(); SendInterest() end)
end)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit) if unit == "player" then RecheckReaders() end end)
ns.RegisterEvent("GUILD_ROSTER_UPDATE", RecheckReaders)

-- Private receipt review: a native proof may be recognized from retained history; otherwise
-- the Treasurer explicitly attests one existing line and a reference. No second money entry.
local RECEIPT_DIALOG = "OLYMPUS_CONTRIBUTION_RECEIPT"
function C.PromptReceipt(book, e)
	if not InBook(book, e) or not Eligible(book, e, ns.FullName(ns.Normal(e.name))) then return false end
	return ns.ShowDialog(RECEIPT_DIALOG, nil, nil, { book = book, line = e }) ~= nil
end
StaticPopupDialogs[RECEIPT_DIALOG] = {
	text = L.CONTRIBUTIONS_RECEIPT_HELP,
	button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 280, maxLetters = 155,
	OnShow = function(self)
		local field = self.editBox or self.EditBox
		if field then field:SetText("") end
	end,
	OnAccept = function(self, data)
		local field = self.editBox or self.EditBox
		local guild, reference = tostring(field and field:GetText() or ""):match("^%s*(.-)%s*|%s*(.-)%s*$")
		if not data or not T.ClassifyContribution(data.line, data.book, guild, reference) then ns.Print(L.CONTRIBUTIONS_RECEIPT_INVALID) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function C.ReceiptLines()
	local lines = { { text = "< " .. L.CONTRIBUTIONS_INTEREST_TITLE, onClick = function() ns.Views.ShowPage("prime-interest") end } }
	if not Staff() then return lines end
	lines[#lines + 1] = { header = true, text = L.CONTRIBUTIONS_RECEIPT_REVIEW }
	lines[#lines + 1] = { text = L.CONTRIBUTIONS_RECEIPT_NOTE, gapAfter = true }
	local book, count = T.BookOf(ns.me), 0
	for i = #(book and book.lines or {}), 1, -1 do
		local e = book.lines[i]
		local source, reference = C.SourceLabel(book, e)
		if source and e.kind == "charity" then
			count = count + 1
			lines[#lines + 1] = { text = ns.DisplayName(e.patron), right = T.Coins(e.money), indent = 1 }
			lines[#lines + 1] = { text = (source == "treasurer-attested" and L.CONTRIBUTIONS_RECEIPT_ATTESTED or L.CONTRIBUTIONS_RECEIPT_NATIVE)
				.. (reference and (": " .. reference) or ""), indent = 2 }
		elseif Eligible(book, e, ns.FullName(ns.Normal(e.name))) then
			count = count + 1
			local proof = C.Classification(book, e)
			lines[#lines + 1] = { text = ns.DisplayName(e.name), right = T.Coins(e.money), indent = 1 }
			lines[#lines + 1] = { text = proof and L.CONTRIBUTIONS_RECEIPT_INCLUDE or L.CONTRIBUTIONS_RECEIPT_ATTEST,
				indent = 2, onClick = function()
					if proof then T.ClassifyContribution(e, book) else C.PromptReceipt(book, e) end
				end }
		end
		if count >= 40 then break end
	end
	if count == 0 then lines[#lines + 1] = { text = L.CONTRIBUTIONS_EMPTY } end
	return lines
end
table.insert(ns.RealmPages, { key = "contribution-receipts", Lines = C.ReceiptLines, Link = function()
	if Staff() then return { text = "> " .. L.CONTRIBUTIONS_RECEIPT_REVIEW, onClick = function() ns.Views.ShowPage("contribution-receipts") end } end
end })

-- The current Treasurer edits informational copy and signs each publication with a delegated
-- key. Author-signed legacy milestones remain readable. Neither route moves money or grants
-- rewards, ranks, access or native game actions.
local milestones = {}
local MILESTONE_DIALOG = "OLYMPUS_CONTRIBUTION_MILESTONE"
local function MilestoneField(text, max)
	return type(text) == "string" and #text > 0 and #text <= max and text:find("%S")
		and not text:find("[~^!;=|%c]")
end
local function ParseMilestones(blob)
	local region = Region(ns.realm)
	if type(blob) ~= "string" or #blob > 3000 or not region then return {} end
	local text, group, body, sig = blob:match("^(HT1~%d+~([^~]+)~[01]~([^~]*))~(%x+)$")
	if not text or group ~= ns.group then return {} end
	local rows, found = {}, false
	for field in body:gmatch("[^;]+") do
		local faction, where, issuer, items = field:match("^%^contributionmilestones%^([^%^]+)%^([^%^]+)%^([^%^]+)%^([^%^]+)$")
		if faction == ns.faction and where == region then
			if found or not IsTreasurer(issuer) then return {} end
			found = true
			for _, item in ipairs(ns.Codec.Split(items, "!")) do
				local title, description = item:match("^([^=]+)=([^=]+)$")
				if #rows >= 4 or not MilestoneField(title, 40) or not MilestoneField(description, 120) then return {} end
				rows[#rows + 1] = { title = title, description = description }
			end
		end
	end
	return found and ns.Sign.Verify(text, sig) and rows or {}
end
local function MilestoneContent(text)
	if text == "CM~1~-" then return {} end
	local items = type(text) == "string" and text:match("^CM~1~(.+)$")
	if not items or #text > 655 or items:find("^!") or items:find("!$") or items:find("!!", 1, true) then return nil end
	local rows = {}
	for _, item in ipairs(ns.Codec.Split(items, "!")) do
		local title, description = item:match("^([^=]+)=([^=]+)$")
		if #rows >= 4 or not MilestoneField(title, 40) or not MilestoneField(description, 120) then return nil end
		rows[#rows + 1] = { title = title, description = description }
	end
	return #rows > 0 and rows or nil
end
local registeredAuthority
function C.RegisterMilestoneAuthority()
	local A = ns.FederationAuthority
	if not A or not A.Register then return false end
	if registeredAuthority == A then return true end
	A.Register("milestones", function(content, record)
		if type(record) ~= "table" or not Scope() or not IsTreasurer(record.issuer) or not D.MandatoryGuild(record.guild) then return nil end
		local rows = MilestoneContent(content)
		if rows then return rows, Scope() end
	end, function()
		if ns.rdb and Scope() then
			ns.rdb.contributionMilestoneDelegated = type(ns.rdb.contributionMilestoneDelegated) == "table" and ns.rdb.contributionMilestoneDelegated or {}
			ns.rdb.contributionMilestoneDelegated[Scope()] = true
		end
		ns.Fire("DATA_CHANGED")
	end)
	registeredAuthority = A
	return true
end
C.RegisterMilestoneAuthority()
function C.MilestoneLines(lines)
	local pin, scope = Treasurer(), Scope()
	if not pin or not scope then return end
	local titles = ns.rdb and ns.rdb.councilTitles
	local blob = type(titles) == "table" and titles.blob or nil
	if blob ~= milestones.blob or scope ~= milestones.scope or pin ~= milestones.pin then
		milestones = { blob = blob, scope = scope, pin = pin, rows = ParseMilestones(blob) }
	end
	local delegated = ns.rdb and ns.rdb.contributionMilestoneDelegated
	local rows = type(delegated) == "table" and delegated[scope] and {} or milestones.rows
	if C.RegisterMilestoneAuthority() then
		local record = ns.FederationAuthority.Current("milestones", scope)
		if record and IsTreasurer(record.issuer) and D.MandatoryGuild(record.guild) then rows = MilestoneContent(record.content) or {} end
	end
	if not rows or #rows == 0 then return end
	lines[#lines + 1] = { header = true, text = L.CONTRIBUTIONS_MILESTONES }
	for _, row in ipairs(rows) do
		lines[#lines + 1] = { text = row.title, tooltip = function(tt) tt:AddLine(row.description, 1, 1, 1, true) end }
	end
end
local function Drafts(create)
	if not ns.db then return nil end
	if not ns.db.contributionMilestoneDraft and create then ns.db.contributionMilestoneDraft = {} end
	return ns.db.contributionMilestoneDraft
end
function C.SaveMilestoneDraft(text)
	if not Staff() or type(text) ~= "string" or #text > 658 or text == "" or text:find(";%s*$") or text:find("^%s*;") or text:find(";%s*;") then return false end
	local items = {}
	for _, item in ipairs(ns.Codec.Split(text, ";")) do
		local title, description = item:match("^%s*(.-)%s*|%s*(.-)%s*$")
		if #items >= 4 or not MilestoneField(title, 40) or not MilestoneField(description, 120) then return false end
		items[#items + 1] = title .. "=" .. description
	end
	if #items == 0 then return false end
	Drafts(true)[Scope()] = text
	return true
end
function C.PublishMilestones()
	if not Staff() or not C.RegisterMilestoneAuthority() then return false end
	local text = (Drafts() or {})[Scope()]
	if not C.SaveMilestoneDraft(text) then return false end
	local items = {}
	for _, item in ipairs(ns.Codec.Split(text, ";")) do
		local title, description = item:match("^%s*(.-)%s*|%s*(.-)%s*$")
		items[#items + 1] = title .. "=" .. description
	end
	local A = ns.FederationAuthority
	local ready, why = A.Ready("milestones")
	if not ready then return false, why end
	return A.Publish("milestones", "CM~1~" .. table.concat(items, "!"))
end
function C.ClearMilestones()
	if not Staff() or not C.RegisterMilestoneAuthority() then return false end
	local ready, why = ns.FederationAuthority.Ready("milestones")
	if not ready then return false, why end
	return ns.FederationAuthority.Publish("milestones", "CM~1~-")
end
function C.PromptMilestone()
	if Staff() then ns.ShowDialog(MILESTONE_DIALOG) end
end
StaticPopupDialogs[MILESTONE_DIALOG] = {
	text = L.CONTRIBUTIONS_MILESTONE_HELP,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 320, maxLetters = 658,
	OnShow = function(self)
		local field = self.editBox or self.EditBox
		if field and Staff() then field:SetText((Drafts() or {})[Scope()] or "") end
	end,
	OnAccept = function(self)
		local field = self.editBox or self.EditBox
		if field and not C.SaveMilestoneDraft(field:GetText()) then ns.Print(L.CONTRIBUTIONS_MILESTONE_INVALID) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
