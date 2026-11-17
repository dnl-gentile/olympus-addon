local _, ns = ...
local D, T, L = ns.Dues, ns.Treasury, ns.L

-- A private, bounded book history, not an obligation verdict. A missing receipt alone is
-- unknown. A covered closed week below its frozen amount is merely "not confirmed in the
-- books". It never gates a feature, grants rank, removes a player, or moves money.
local G = { WEEKS = 5, MEMBERS = 1000, BOUNDARY = 90, ROOM = 900, GAP = 2, RETRY = 180, NOTICE_FOR = 86400 }
ns.DuesGrace = G
G.captainPolicy = "gm" -- second covered, unconfirmed notice: payer first, current native GM next
local observed, queue, nextSend, shown = nil, {}, 0, 25
local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Whole(n, max) return type(n) == "number" and n == n and n % 1 == 0 and n >= 0 and n <= max end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(ns.Normal(a)):lower() == ns.FullName(ns.Normal(b)):lower() end
local function Preview()
	return ns.King.Preview() or T.DevView() or ns.ViewAs and ns.ViewAs.Previewing and ns.ViewAs.Previewing()
end
local function Hidden(name, guild)
	local M = ns.Moderation
	return M and M.Hides and M.Hides(name, guild or GetGuildInfo("player")) ~= nil
end
function G.Keeper()
	local W = ns.WatchChat
	return D.Available() and not Preview() and not Hidden(ns.me) and not (W and not W.missing and W.Barred and W.Barred("powers", ns.me)) and T.TreasurerPin(ns.me) == 1
		and ns.IsTreasurer(ns.me, GetGuildInfo("player")) == true
end
local function Identity()
	return { me = ns.me, guild = GetGuildInfo("player"), store = ns.rdb, faction = ns.faction, realm = ns.realm }
end
local function Current(i)
	return i and Same(i.me, ns.me) and i.guild == GetGuildInfo("player") and i.store == ns.rdb
		and i.faction == ns.faction and i.realm == ns.realm
end
local function Store()
	if not ns.rdb then return nil end
	local s = ns.rdb.duesGrace
	if s == nil then s = { version = 1, weeks = {}, sent = {} }; ns.rdb.duesGrace = s end
	if type(s) ~= "table" or s.version ~= 1 or type(s.weeks) ~= "table" or type(s.sent) ~= "table" then return nil end
	for week in pairs(s.weeks) do
		if not Whole(week, 1000000) or week < D.Week() - G.WEEKS + 1 or week > D.Week() then s.weeks[week] = nil end
	end
	for key, week in pairs(s.sent) do
		if type(key) ~= "string" or #key > 256 or not Whole(week, 1000000) or week < D.Week() - G.WEEKS + 1 or week > D.Week() then s.sent[key] = nil end
	end
	return s
end
local function Members()
	if not ns.Roster.Fresh(G.BOUNDARY) then return nil end
	local total = GetNumGuildMembers and tonumber((GetNumGuildMembers()))
	if not Whole(total, G.MEMBERS) or total < 1 or #ns.Roster.members ~= total then return nil end
	local out = {}
	for _, member in ipairs(D.Roster()) do
		local name = ns.FullName(ns.Normal(member.raw))
		if type(name) ~= "string" or name:find("[~|;%c]") then return nil end
		out[name:lower()] = name
	end
	local n = 0; for _ in pairs(out) do n = n + 1 end
	return n == total and out or nil
end
local function Links(name, members)
	local out = { name:lower() }
	local A = ns.Alts
	if A and A.Linked then
		for _, alias in ipairs(A.Linked(name)) do
			local key = ns.FullName(ns.Normal(alias)):lower()
			if members[key] then out[#out + 1] = key end
		end
	end
	table.sort(out)
	return table.concat(out, ";")
end
local function Groups(members)
	local out = {}
	for key, name in pairs(members or {}) do out[key] = Links(name, members) end
	return out
end
-- Positive native receipts can confirm their own lower bound. Negative coverage requires
-- every pinned book, opened before the week, with no native proof retention overflow.
local function Books(week)
	local books, pins, covered = {}, {}, true
	for _, b in pairs(ns.rdb.treasuryBooks or {}) do
		local pin = type(b) == "table" and T.TreasurerPin(b.name)
		if pin and b.epoch == T.EPOCH then
			if pins[pin] ~= nil then pins[pin], covered = false, false
			else pins[pin] = b end
			local opened = b.openedAt or b.opened
			if not Whole(opened, T.MAX_COPPER) or opened > D.WeekStart(week)
				or b.duesProofsCut ~= nil and (type(b.duesProofsCut) ~= "table" or b.duesProofsCut[week]) then covered = false end
			if not D.NativePayerCoverage or D.NativePayerCoverage(b, week) ~= true then covered = false end
			if b.duesPayerProofs ~= nil and (type(b.duesPayerProofs) ~= "table"
				or b.duesPayerProofs[week] ~= nil and type(b.duesPayerProofs[week]) ~= "table") then covered = false end
		end
	end
	for pin in ipairs((ns.TreasurerPins())) do if not pins[pin] then covered = false end end
	for _, book in pairs(pins) do if type(book) == "table" then books[#books + 1] = book end end
	return books, covered and #books > 0
end
local function Copper(books, week, name, guild)
	local total, reliable, key = 0, true, name:lower()
	for _, b in ipairs(books) do
		local rows = type(b.duesPayerProofs) == "table" and b.duesPayerProofs[week]
		local p; if type(rows) == "table" then p = rows[key] end
		if p ~= nil then
			if type(p) == "table" and p.guild == guild and Whole(p.copper, T.MAX_COPPER)
				and Whole(p.seq, T.MAX_COPPER) and p.seq > 0 and Whole(p.at, T.MAX_COPPER) and p.at <= Clock() + 60 then
				total = math.min(T.MAX_COPPER, total + p.copper)
			else reliable = false end -- a changed guild/corrupt proof is not evidence of absence
		end
	end
	return total, reliable
end
local batchTag = {}
local function Batch(liveMembers, guild)
	if type(liveMembers) == "table" and liveMembers.tag == batchTag then return liveMembers end
	guild = guild or GetGuildInfo("player")
	local foreign = guild ~= GetGuildInfo("player") and ns.DuesRosterCheckpoints
	return { tag = batchTag, guild = guild, foreign = foreign, rows = {},
		members = liveMembers or (foreign and foreign.LatestMembers(guild) or not foreign and Members()) or false,
		store = Store(), books = {}, links = {} }
end
local function Row(row, week, guild)
	return type(row) == "table" and row.closed == true and row.guild == guild
		and Whole(row.amount, D.MAX_AMOUNT) and row.amount > 0 and type(row.members) == "table"
		and Whole(row.at, T.MAX_COPPER) and row.at >= D.WeekStart(week) and row.at <= D.WeekStart(week) + G.BOUNDARY
end
function G.Rows(name, liveMembers, guild)
	if not G.Keeper() or type(name) ~= "string" or name == "" then return {} end
	local batch, out = Batch(liveMembers, guild), {}
	if not D.MandatoryGuild(batch.guild) then return out end
	local s, key = batch.store, ns.FullName(ns.Normal(name)):lower()
	for week = D.Week() - G.WEEKS + 1, D.Week() - 1 do
		local row = s and s.weeks[week]
		if batch.foreign then
			row = batch.rows[week]
			if row == nil then row = batch.foreign.ValidatedWindow(batch.guild, week) or false; batch.rows[week] = row end
		end
		if Row(row, week, batch.guild) then
			local member = row.members[key]
			if type(member) == "string" and #member <= 96 and not member:find("[~|;%c]") and Same(member, name) then
				local source = batch.books[week]
				if not source then local books, covered = Books(week); source = { books, covered }; batch.books[week] = source end
				local books, covered = source[1], source[2]
				local copper, reliable = Copper(books, week, member, row.guild)
				local nowLinks = batch.links[key]
				if nowLinks == nil then
					if batch.foreign then
						local latest = batch.rows[D.Week() - 1]
						if latest == nil then latest = batch.foreign.ValidatedWindow(batch.guild, D.Week() - 1) or false; batch.rows[D.Week() - 1] = latest end
						nowLinks = latest and latest.endGroups[key] or false
					else nowLinks = batch.members and Links(member, batch.members) or false end
					batch.links[key] = nowLinks
				end
				local stable = type(row.groups) == "table" and type(row.endGroups) == "table" and nowLinks
					and row.groups[key] == nowLinks and row.endGroups[key] == nowLinks
				local main = batch.foreign and row.mains[key] == key or not batch.foreign and (not ns.Alts or not ns.Alts.Person or D.Key(ns.Alts.Person(member)) == D.Key(member))
				if main and stable then
					for alias in nowLinks:gmatch("[^;]+") do if alias ~= key then
						local extra, intact = Copper(books, week, alias, row.guild)
						copper, reliable = math.min(T.MAX_COPPER, copper + extra), reliable and intact
					end end
				end
				local state = copper >= row.amount and "counted" or (row.covered == true and covered and reliable and type(row.ends) == "table"
					and row.ends[key] == member and batch.members and batch.members[key] == member
					and stable and main and "unconfirmed" or "unknown")
				out[#out + 1] = { week = week, name = member, guild = row.guild, amount = row.amount, copper = copper, state = state }
			end
		end
	end
	return out
end
function G.Progress(name, liveMembers, guild)
	local out = { kept = 0, misses = 0, unknown = 0, known = 0, latest = nil }
	local rows = G.Rows(name, liveMembers, guild)
	out.unknown = G.WEEKS - 1 - #rows -- a retained gap never joins two proved weeks silently
	for _, row in ipairs(rows) do
		out.latest = row
		if row.state == "counted" then out.kept, out.misses, out.known = out.kept + 1, 0, out.known + 1
		elseif row.state == "unconfirmed" then
			out.misses, out.known = out.misses + 1, out.known + 1
			if out.misses >= 2 then out.kept = 0 end
		else out.unknown = out.unknown + 1 end -- no point, no erased evidence, no invented miss
	end
	out.grace = out.misses == 1
	return out
end
function G.Observe()
	if not G.Keeper() then observed = nil; return false end
	if ns.DuesRosterCheckpoints then ns.DuesRosterCheckpoints.Observe() end
	local s, members, now, week = Store(), Members(), Clock(), D.Week()
	if not s then return false end
	local old = observed
	if old and Current(old.identity) and old.week + 1 == week and now - old.at >= 0 and now - old.at <= G.BOUNDARY
		and now - D.WeekStart(week) <= G.BOUNDARY then
		local row = s.weeks[old.week]
		if type(row) == "table" then
			local _, covered = Books(old.week)
			row.closed, row.covered, row.ends, row.endGroups = true, covered and members ~= nil, members, Groups(members)
			G.QueueNotices(old.week)
		end
	end
	-- Never backfill membership from a login late in the week. Beginning and ending roster
	-- observations are independent of the current roster used to re-check a notice recipient.
	if not s.weeks[week] and members and now - D.WeekStart(week) >= 0 and now - D.WeekStart(week) <= G.BOUNDARY then
		s.weeks[week] = { guild = GetGuildInfo("player"), at = now, amount = D.Amount(), members = members, groups = Groups(members) }
	end
	observed = { identity = Identity(), week = week, at = now }
	-- A reload can resume a retained, actually closed week's remaining private notice,
	-- but it never reconstructs a missing boundary or repeats a completed payer phase.
	G.QueueNotices(week - 1)
	return true
end
local function GM(guild)
	if guild and guild ~= GetGuildInfo("player") then return ns.DuesRosterCheckpoints and ns.DuesRosterCheckpoints.CurrentGM(guild) end
	if not ns.Roster.Fresh(G.BOUNDARY) then return nil end
	for _, m in ipairs(D.Roster()) do if m.rank == 0 and not Hidden(m.raw) then return ns.FullName(ns.Normal(m.raw)) end end
end
local function MayReceive()
	return D.Available() and not Preview() and not Hidden(ns.me) and (D.Pays() or Same(GM(), ns.me))
end
local function NoticeText(week, name, officer, amount, copper, known, guild)
	return ("DG~1~N~%d~%s~%s~%d~%d~%d~%d"):format(week, guild or GetGuildInfo("player"), name, officer and 1 or 0, amount, copper, known)
end
function G.QueueNotices(week)
	if not G.Keeper() then return false end
	local since = Clock() - D.WeekStart(D.Week())
	if week ~= D.Week() - 1 or since < 0 or since > G.NOTICE_FOR then return false end
	local nativeGuild = GetGuildInfo("player")
	local s, scopes = Store(), { nativeGuild }
	if not s then return false end
	local R = ns.DuesRosterCheckpoints
	for _, guild in ipairs(R and R.Scopes() or {}) do scopes[#scopes + 1] = guild end
	for _, guild in ipairs(scopes) do
	local batch = Batch(nil, guild)
	for _, name in pairs(batch.members or {}) do
		local p = G.Progress(name, batch)
		if p.latest and p.latest.week == week and p.latest.state == "unconfirmed" and p.misses >= 2
			and not Hidden(name, guild) and not T.IsKeeperName(name, guild) then
			local key = week .. ":" .. name:lower() .. (guild ~= GetGuildInfo("player") and ":" .. guild or "")
			if not s.sent[key] and not queue[key] then
				queue[key] = { identity = Identity(), payer = name, guild = guild, week = week, at = Clock(), phase = s.sent[key .. ":self"] and 1 or 0 }
			end
		end
	end
	end
	return true
end
function G.Pump()
	if Clock() < nextSend or not G.Keeper() or not T.CanSend() then return false end
	local batches = {}
	for key, q in pairs(queue) do
		local guild = q.guild or GetGuildInfo("player")
		local batch = batches[guild]; if not batch then batch = Batch(nil, guild); batches[guild] = batch end
		if not D.MandatoryGuild(guild) or not Current(q.identity) or q.week ~= D.Week() - 1 or Clock() - q.at < 0 or Clock() - q.at > G.NOTICE_FOR
			or not batch.members or not batch.members[q.payer:lower()] or Hidden(q.payer, guild) then queue[key] = nil
		elseif not q.retryAt or Clock() >= q.retryAt then
			local p = G.Progress(q.payer, batch)
			if not p.latest or p.latest.week ~= q.week or p.latest.state ~= "unconfirmed" or p.misses < 2 then queue[key] = nil
			else
				local to = q.phase == 0 and q.payer or G.captainPolicy == "gm" and GM(guild)
				if to then -- an unavailable current GM never guesses or stalls another payer
					local text = NoticeText(q.week, q.payer, q.phase == 1, p.latest.amount, p.latest.copper, p.known, guild)
					q.to, q.text = to, text
					local ok = T.Private(to, "DG", text, "grace:" .. key .. ":" .. q.phase)
					q.retryAt = Clock() + G.RETRY -- a blocked/recent target never starves another payer
					if ok then nextSend = Clock() + G.GAP; return true end
				end
			end
		end
	end
	return false
end
function G.Handle(dist, sender, text)
	if dist ~= "WHISPER" or T.TreasurerPin(sender) ~= 1 or not MayReceive() or type(text) ~= "string" or #text > G.ROOM then return false end
	local week, guild, name, officer, amount, copper, known = text:match("^DG~1~N~(%d+)~([^~]+)~([^~]+)~([01])~(%d+)~(%d+)~(%d+)$")
	week, amount, copper, known = tonumber(week), tonumber(amount), tonumber(copper), tonumber(known)
	if week ~= D.Week() - 1 or guild ~= GetGuildInfo("player") or not Whole(amount, D.MAX_AMOUNT) or amount < 1
		or not Whole(copper, T.MAX_COPPER) or copper >= amount or not Whole(known, G.WEEKS) or known < 2 then return false end
	if officer == "0" and not Same(name, ns.me) or officer == "1" and (not Same(GM(), ns.me) or ns.Roster.RankOf(name) == nil) then return false end
	local s = Store(); if not s then return false end
	local key = "heard:" .. week .. ":" .. ns.FullName(name):lower() .. ":" .. officer
	if s.sent[key] then return false end
	s.sent[key] = week
	local payer = ns.rdb.duesPayer and ns.rdb.duesPayer[ns.me]
	if officer == "0" and payer and payer.reminderOff then return true end
	ns.Print((officer == "1" and L.DUESGRACE_OFFICER or L.DUESGRACE_SELF):format(ns.DisplayName(name), D.DateLabel(week), T.Coins(copper), T.Coins(amount)))
	return true
end
T.OnPrivate("DG", {
	piece = function(piece)
		local id, i, n, body = piece:match("^C(%w+):(%d+):(%d+):(.*)$")
		i, n = tonumber(i), tonumber(n)
		return id ~= nil and #id <= 8 and Whole(i, ns.Codec.MAX_CHUNKS) and i >= 1 and Whole(n, math.ceil(G.ROOM / ns.Codec.CHUNK)) and n >= i and #body <= ns.Codec.CHUNK
	end,
	from = function(sender) return MayReceive() and T.TreasurerPin(sender) == 1 end,
	to = MayReceive,
	send = function(to, text)
		if not G.Keeper() or not T.CanSend() then return false end
		for _, q in pairs(queue) do
			if D.MandatoryGuild(q.guild) and Current(q.identity) and q.text == text and Same(q.to, to) and q.week == D.Week() - 1
				and Clock() - q.at >= 0 and Clock() - q.at <= G.NOTICE_FOR and not Hidden(q.payer, q.guild) then
				local guild = q.guild or GetGuildInfo("player")
				if guild == GetGuildInfo("player") and (not ns.Roster.Fresh(G.BOUNDARY) or ns.Roster.RankOf(q.payer) == nil) then return false end
				local p = G.Progress(q.payer, nil, guild)
				return p.latest and p.latest.week == q.week and p.latest.state == "unconfirmed" and p.misses >= 2
					and text == NoticeText(q.week, q.payer, q.phase == 1, p.latest.amount, p.latest.copper, p.known, guild)
					and (q.phase == 0 and Same(to, q.payer) or q.phase == 1 and G.captainPolicy == "gm" and Same(to, GM(guild))) or false
			end
		end
		return false
	end,
	handle = G.Handle,
	dispatched = function(to, text) G.Delivered(to, text) end,
})
-- Treasury calls this only after the guarded batch passed to the native transport. It is
-- NOT a recipient acknowledgement or payment proof. Merely enqueueing cannot advance order.
function G.Delivered(to, text)
	local s = Store(); if not s then return end
	for key, q in pairs(queue) do
		if q.text == text and Same(q.to, to) and Current(q.identity) then
			if q.phase == 0 then s.sent[key .. ":self"] = q.week; q.phase, q.text, q.to, q.retryAt = 1, nil, nil, nil
			else s.sent[key], queue[key] = q.week, nil end
			return
		end
	end
end
function G.SummaryLines(lines)
	if not G.Keeper() then return end
	lines[#lines + 1] = { text = L.DUESGRACE_HINT, wrap = true }
	local R = ns.DuesRosterCheckpoints
	for _, guild in ipairs(R and R.Scopes() or {}) do
		local batch = Batch(nil, guild)
		lines[#lines + 1] = { header = true, text = L.DUESROSTER_FOREIGN:format(guild) }
		local n = 0
		for _, name in pairs(batch.members or {}) do
			local p = G.Progress(name, batch); n = n + 1
			if n <= shown and p.latest then lines[#lines + 1] = { indent = 1, text = ns.DisplayName(name), right = L.DUESGRACE_ROW:format(p.kept, p.known, p.unknown) } end
		end
	end
	local members = Members()
	if not members then return end
	local batch = Batch(members)
	local names = {}; for _, name in pairs(members) do names[#names + 1] = name end
	table.sort(names)
	local visible = 0
	for _, name in ipairs(names) do
		local p = G.Progress(name, batch)
		if p.latest then
			visible = visible + 1
			if visible <= shown then lines[#lines + 1] = { indent = 1, text = ns.DisplayName(name),
				right = L.DUESGRACE_ROW:format(p.kept, p.known, p.unknown) .. (p.grace and " · " .. L.DUESGRACE_TOLERANCE or "") } end
		end
	end
	if visible > shown then lines[#lines + 1] = { text = L.DUESGRACE_MORE:format(visible - shown),
		onClick = function() shown = math.min(G.MEMBERS, shown + 25); ns.Fire("TREASURY_CHANGED") end } end
end
ns.On("LOGIN", function() observed, queue, nextSend, shown = nil, {}, 0, 25; ns.Every(60, "dues grace reset", G.Observe); ns.Every(G.GAP, "dues grace notices", G.Pump) end)
