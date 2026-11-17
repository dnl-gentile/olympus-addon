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

-- Only successful incoming trades with a game-observed guild on the signed beneficiary's own
-- book enter this ranking. An ordinary mail's free-text guild, manual edits and other book
-- keepers are not sufficient. The book still counts this gold in its actual balance.
function C.ProtectTrade(book, e, full, observedGuild)
	if e.kind or e.how ~= "trade" or e.out or e.item or e.excluded or not Name(full) or not Whole(e.money, T.MAX_COPPER)
		or not Staff() or not IsTreasurer(book.name) or type(observedGuild) ~= "string"
		or observedGuild ~= e.guild or D.MandatoryGuild(observedGuild) or not P.IsEnrolled(observedGuild) then return false end
	e.kind, e.patron, e.contributionScope, e.name = "charity", full, Scope(), "Anonymous Patron"
	return true
end
function C.Count(book, e, sign)
	local key = Name(e.patron)
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
		if not key or replies[key] ~= text then return false end
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
		lines[#lines + 1] = { text = L.CONTRIBUTIONS_MILESTONE_DRAFT, onClick = C.PromptMilestone, gapAfter = true }
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

-- The Treasurer prepares informational copy locally. Publication requires the existing author
-- signature on the current titles list and identifies the same exact signed Treasurer pin.
-- Milestones never change money, rewards, ranks, access or native game state.
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
function C.MilestoneLines(lines)
	local pin, scope = Treasurer(), Scope()
	if not pin or not scope then return end
	local titles = ns.rdb and ns.rdb.councilTitles
	local blob = type(titles) == "table" and titles.blob or nil
	if blob ~= milestones.blob or scope ~= milestones.scope or pin ~= milestones.pin then
		milestones = { blob = blob, scope = scope, pin = pin, rows = ParseMilestones(blob) }
	end
	if not milestones.rows or #milestones.rows == 0 then return end
	lines[#lines + 1] = { header = true, text = L.CONTRIBUTIONS_MILESTONES }
	for _, row in ipairs(milestones.rows) do
		lines[#lines + 1] = { text = row.title, tooltip = function(tt) tt:AddLine(row.description, 1, 1, 1, true) end }
	end
end
local function Drafts(create)
	if not ns.db then return nil end
	if not ns.db.contributionMilestoneDraft and create then ns.db.contributionMilestoneDraft = {} end
	return ns.db.contributionMilestoneDraft
end
function C.SaveMilestoneDraft(text)
	if not Staff() or type(text) ~= "string" then return false end
	local title, description = text:match("^%s*(.-)%s*|%s*(.-)%s*$")
	if not MilestoneField(title, 40) or not MilestoneField(description, 120) then return false end
	Drafts(true)[Scope()] = title .. " | " .. description
	return true
end
function C.PromptMilestone()
	if Staff() then ns.ShowDialog(MILESTONE_DIALOG) end
end
StaticPopupDialogs[MILESTONE_DIALOG] = {
	text = L.CONTRIBUTIONS_MILESTONE_HELP,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 260, maxLetters = 163,
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
