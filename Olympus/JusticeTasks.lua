local _, ns = ...
local J = {}; ns.JusticeTasks = J
-- Deliberate expulsion requests, not new kick powers. Original actors sign their facts;
-- actual Crown staff can recover those proofs by logged private whisper, never a public feed.
-- An API attempt or subsequent absence is never completion.
J.MAX, J.KEEP, J.MAX_ISSUERS, J.EVERY = 60, 30 * 86400, 128, 60
J.RETRY_MAX = 20
local pending, observations = {}, {}
local SignedFacts, TakeShared, ShareTick
local function Now() return math.floor(GetServerTime and GetServerTime() or ns.Now()) end
local function Word(key, fallback) return ns.L and rawget(ns.L, key) or fallback end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.Fold(a) == ns.Fold(b) end
local function Name(s)
	if type(s) ~= "string" or s == "" or #s > 72 or s:find("[~|%^%c]") then return nil end
	local full = ns.FullName(s)
	return type(full) == "string" and #full <= 72 and full or nil
end
local function Number(x)
	x = tonumber(x); return x and x == math.floor(x) and x >= 0 and x <= 2147483647 and x or nil
end
local function Preview()
	local V = ns.ViewAs; local K = ns.King
	return (V and V.Previewing and V.Previewing()) or (K and K.Preview and K.Preview()) or false
end
local function Roster()
	local R = ns.IsMember() == true and ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh() or nil
	return R and R.complete == true and R or nil
end
local function Guild() local R = Roster(); return R and R.guild end
local function Member(name, guild)
	local who, R = Name(name), Roster()
	return who and R and Same(R.guild, guild) and R.byName[who] ~= nil and who or nil
end
local function InGroup(name)
	local realm = ns.RealmOf and ns.RealmOf(name)
	return realm and ns.GroupOf(realm) == ns.group
end
local function Issuer(name)
	name = Name(name)
	if not name or not InGroup(name) then return false end
	local M, W = ns.Moderation, ns.WatchChat
	if M and M.Hides and M.Hides(name, nil, true) then return false end
	if W and W.PowersBarred and W.PowersBarred(name) then return false end
	return (ns.IsKingCharacter(name) == true and ns.KingRealm and ns.KingRealm() ~= nil) or ns.IsHighCouncillor(name) == true
end
local function ReadPeer(name)
	name = Name(name)
	if not name or not InGroup(name) then return false end
	if Issuer(name) then return true end
	local W, M, C = ns.Workshop, ns.Moderation, ns.WatchChat
	if M and M.Hides and M.Hides(name, nil, true) then return false end
	if C and C.PowersBarred and C.PowersBarred(name) then return false end
	-- The existing canonical author identity is read-only here. Neither this guard nor an
	-- original-key claim makes the author a council issuer or a native guild officer.
	return W and W.IsAuthorName and W.IsAuthorName(name) == true or false
end
function J.CanIssue() return not Preview() and Roster() ~= nil and Issuer(ns.me) end
function J.CanReadShared() return not Preview() and Roster() ~= nil and ReadPeer(ns.me) end
function J.Staff()
	return not Preview() and Roster() ~= nil and (Issuer(ns.me) or (ns.Workshop and ns.Workshop.IsAuthor and ns.Workshop.IsAuthor() == true)) or false
end
local function Correspondent(name, guild)
	name = Name(name)
	if not name or type(guild) ~= "string" or #guild > 72 or not ns.IsFederation(guild) then return false end
	local N, W = ns.Nominees, ns.WatchChat
	if Same(guild, Guild()) then
		if not Member(name, guild) then return false end
		return N and N.IsCorrespondent and N.IsCorrespondent(name, guild, "Council of Justice") == true and W and W.Justice and Same(W.Justice(), name) or false
	end
	-- A census-claimed title or guild is never enough to address another guild's correspondent.
	local list = N and N.ListOf and N.ListOf(guild)
	local master, origin
	if list then master, origin = ns.Data.AuthorizedRank(list.by, guild) end
	local role, department
	if N and N.RoleOf then role, department = N.RoleOf(name, guild) end
	-- IsCorrespondent deliberately only grants native duties in this client's own guild.
	-- Addressing another guild requires its independently signed/pinned master and accepted
	-- nomination. Ordinary correspondents are not signed officers; the recipient independently
	-- rechecks their membership and duty against their own current native roster.
	return master == 0 and (origin == "signed" or origin == "pinned") and role == "correspondent" and department == "Council of Justice" or false
end
function J.Own() return not Preview() and Correspondent(ns.me, Guild()) end
function J.Visible() return J.Staff() or J.Own() end
local function Bucket(make)
	if type(ns.rdb) ~= "table" or type(ns.group) ~= "string" or type(ns.faction) ~= "string" then return nil end
	local all = ns.rdb.justiceTasks
	if all == nil and make then all = {}; ns.rdb.justiceTasks = all end
	if type(all) ~= "table" then return nil end
	local key = ns.group .. "|" .. ns.faction
	local s = all[key]
	if s == nil and make then
		local count = 0; for _ in pairs(all) do count = count + 1 end
		if count >= 8 then return nil end
		s = { tasks = {}, floors = {}, seq = 0 }; all[key] = s
	end
	return type(s) == "table" and type(s.tasks) == "table" and type(s.floors) == "table" and Number(s.seq) and s or nil
end
local function Key(issuer, seq) return ns.Fold(issuer) .. "#" .. seq end
local function Valid(t)
	return type(t) == "table" and Name(t.issuer) == t.issuer and Name(t.assignee) == t.assignee and Name(t.subject) == t.subject
		and type(t.guild) == "string" and t.guild ~= "" and #t.guild <= 72 and not t.guild:find("[~|%^%c]")
		and Number(t.seq) and t.seq > 0 and Number(t.createdAt) and t.createdAt > 0
		and Number(t.receivedAt or 0) and Number(t.attemptedAt or 0) and Number(t.absentAt or 0)
		and (t.cancelledAt == nil or Number(t.cancelledAt)) and (t.confirmedAt == nil or (Number(t.confirmedAt) and Same(t.confirmedBy, t.issuer)))
end
local function Retire(s, key, t)
	local actor = ns.Fold(t.issuer)
	s.floors[actor] = math.max(s.floors[actor] or 0, t.seq); s.tasks[key] = nil
end
function J.Prune()
	local s = Bucket(false); if not s then return end
	for key, t in pairs(s.tasks) do
		if Valid(t) and Now() - t.createdAt > J.KEEP then Retire(s, key, t) end
	end
end
local function Room(s, issuer)
	if s.floors[ns.Fold(issuer)] == nil then
		local count = 0; for _ in pairs(s.floors) do count = count + 1 end
		if count >= J.MAX_ISSUERS then return false end
	end
	local count = 0; for _ in pairs(s.tasks) do count = count + 1 end
	return count < J.MAX
end
local function Live(t)
	return Valid(t) and not t.cancelledAt and not t.confirmedAt and Now() - t.createdAt <= J.KEEP and Issuer(t.issuer)
end
local function OwnTask(t)
	return Live(t) and J.Own() and Same(t.assignee, ns.me) and Same(t.guild, Guild()) and not Same(t.subject, ns.me)
end
local function Changed() ns.Fire("WATCH_CHANGED") end
local function Code() return ns.faction == "Horde" and "H" or "A" end
local function Wire(op, ...) return "JT~1~" .. op .. "~" .. Code() .. "~" .. table.concat({ ... }, "~") end
local function Send(to, text, t, role)
	if #text > 255 then return false end
	local identity, group, faction = Key(t.issuer, t.seq), ns.group, ns.faction
	return ns.Comm.Whisper(to, text, "justice:" .. identity .. ":" .. role, false, true, nil,
		{ owner = J, key = identity .. ":" .. role, permit = function(owner, key, dist, target, payload)
			if owner ~= J or key ~= identity .. ":" .. role or dist ~= "WHISPER" or not Same(to, target) or payload ~= text
				or Preview() or ns.group ~= group or ns.faction ~= faction then return false end
			local s = Bucket(false); if not s or s.tasks[identity] ~= t or not Issuer(t.issuer) then return false end
			if role == "receipt" then return OwnTask(t) and Same(to, t.issuer) end
			if role == "terminal-ack" then return Valid(t) and J.Own() and Same(t.assignee, ns.me) and Same(t.guild, Guild())
				and Same(to, t.issuer) and (t.cancelledAt ~= nil or t.confirmedAt ~= nil) end
			return J.CanIssue() and Same(ns.me, t.issuer) and Correspondent(t.assignee, t.guild)
				and ((role == "issue" and Live(t)) or (role == "cancel" and t.cancelledAt ~= nil) or (role == "confirm" and t.confirmedAt ~= nil))
		end })
end
local function IssueWire(t) return Wire("I", t.seq, t.createdAt, t.guild, t.assignee, t.subject) end
local function Receipt(t)
	if SignedFacts then SignedFacts(t, "R", t.issuer) end
	return Send(t.issuer, Wire("R", t.issuer, t.seq, t.receivedAt or 0, t.attemptedAt or 0, t.absentAt or 0), t, "receipt")
end
local function Terminal(t)
	if t.terminalAck or (t.terminalTries or 0) >= J.RETRY_MAX then return false end
	t.terminalTries = (t.terminalTries or 0) + 1
	if SignedFacts then SignedFacts(t, "T", t.assignee) end
	return Send(t.assignee, t.cancelledAt and Wire("X", t.seq, t.cancelledAt) or Wire("F", t.seq, t.confirmedAt), t, t.cancelledAt and "cancel" or "confirm")
end
local function TerminalAck(t)
	return Send(t.issuer, Wire("A", t.issuer, t.seq, t.cancelledAt and "X" or "F", t.cancelledAt or t.confirmedAt), t, "terminal-ack")
end
function J.Retry(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not J.CanIssue() or not Valid(t) or not Same(t.issuer, ns.me) or not Issuer(t.issuer) or not (t.cancelledAt or t.confirmedAt) then return false end
	t.terminalTries = 0; return Terminal(t)
end
function J.Issue(guild, assignee, subject)
	if not J.CanIssue() or type(guild) ~= "string" or guild == "" or #guild > 72 or guild:find("[~|%^%c]") then return false, "authority" end
	assignee, subject = Name(assignee), Name(subject)
	if not assignee or not subject or not Correspondent(assignee, guild) or Same(subject, assignee) or ns.IsKingCharacter(subject) then return false, "identity" end
	if Same(guild, Guild()) and not Member(subject, guild) then return false, "member" end
	J.Prune(); local s = Bucket(true)
	if not s or not Room(s, ns.me) then return false, "full" end
	for _, old in pairs(s.tasks) do if Live(old) and Same(old.guild, guild) and Same(old.subject, subject) then return false, "already" end end
	s.seq = math.max(Now(), s.seq + 1)
	local t = { issuer = ns.FullName(ns.me), seq = s.seq, createdAt = Now(), guild = guild, assignee = assignee, subject = subject }
	local key = Key(t.issuer, t.seq); s.tasks[key] = t; s.floors[ns.Fold(t.issuer)] = s.floors[ns.Fold(t.issuer)] or 0
	if SignedFacts then SignedFacts(t, "I", assignee, true) end
	Send(assignee, IssueWire(t), t, "issue"); Changed(); return true, key
end
function J.Tasks()
	if not J.Visible() then return {} end
	J.Prune(); local out, s = {}, Bucket(false)
	for key, t in pairs(s and s.tasks or {}) do
		if Valid(t) and (J.Staff() or (Same(t.assignee, ns.me) and Same(t.guild, Guild()))) then out[#out + 1] = { key = key, task = t } end
	end
	table.sort(out, function(a, b) return a.task.createdAt > b.task.createdAt end); return out
end
function J.Cancel(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not J.CanIssue() or not Live(t) or not Same(t.issuer, ns.me) then return false end
	t.cancelledAt = Now(); pending[key] = nil
	Terminal(t); Changed(); return true
end
function J.Confirm(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not J.CanIssue() or not Live(t) or not Same(t.issuer, ns.me) or not t.receivedAt or t.receivedAt == 0 or not t.attemptedAt or t.attemptedAt == 0 or not t.absentAt or t.absentAt == 0
		or t.attemptedAt < t.receivedAt or t.absentAt < t.attemptedAt then return false end
	t.confirmedAt, t.confirmedBy = Now(), ns.me
	Terminal(t); Changed(); return true
end
function J.AskRemoval(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not OwnTask(t) or not t.receivedAt or t.attemptedAt then return false end
	local R, M = Roster(), ns.Members
	if not R or not M or not M.CanRemove() then return false end
	local target
	for _, row in ipairs(R.members or {}) do if Same(ns.FullName(row.raw or row.name or ""), t.subject) then target = row; break end end
	if not target or not M.Removable(target) then return false end
	local copy = {}; for k, v in pairs(target) do copy[k] = v end
	local reference = {}; copy.justiceTask = reference
	pending[key] = { reference = reference, subject = t.subject, guild = t.guild, generation = R.generation, capturedAt = R.snapshotAt }
	return M.AskRemove(copy)
end
function J.MayRemove(row)
	local s, R = Bucket(false), Roster(); if not s or not R then return false end
	for key, p in pairs(pending) do
		local t = s.tasks[key]
		if p.reference == row.justiceTask and OwnTask(t) and not t.attemptedAt and Same(ns.FullName(row.raw), t.subject) then
			local rank = R.byName[t.subject]
			if type(rank) ~= "number" or rank < 1 or rank <= ns.Roster.MyRank() then return false end
			p.generation, p.capturedAt = R.generation, R.snapshotAt
			return true
		end
	end
	return false
end
local function Attempt(row, guild)
	if type(row) ~= "table" or not row.justiceTask then return end
	local s, R = Bucket(false), Roster(); if not s or not R then return end
	for key, p in pairs(pending) do
		local t = s.tasks[key]
		if p.reference == row.justiceTask and OwnTask(t) and Same(guild, t.guild) and Same(ns.FullName(row.raw), t.subject)
			and Member(t.subject, guild) and R.generation == p.generation then
			t.attemptedAt = Now()
			observations[key] = { generation = R.generation, snapshotAt = R.snapshotAt }
			pending[key] = nil; Receipt(t); Changed(); return
		end
	end
end
function J.Observe()
	local s, R = Bucket(false), Roster(); if not s or not R or not J.Own() then return end
	for key, t in pairs(s.tasks) do
		local capture = observations[key]
		-- Generations are process-local: never compare a saved generation to a later login.
		-- Across reload, only a native server-dated complete scan strictly after the attempt
		-- can supply an observation; an unavailable clock leaves it pending.
		local after = capture and R.generation > capture.generation and R.snapshotAt >= capture.snapshotAt
			or (not capture and Number(R.serverAt) and t.attemptedAt and R.serverAt > t.attemptedAt)
		if OwnTask(t) and t.attemptedAt and not t.absentAt and after and not Member(t.subject, t.guild) then
			t.absentAt = Now(); Receipt(t); Changed()
		end
	end
end
function J.Handle(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 255 or Preview() or not Roster() then return false end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return false end
	sender = Name(sender); if not sender or not InGroup(sender) then return false end
	if text:sub(1, 5) == "JT~2~" then return TakeShared and TakeShared(sender, text) or false end
	local op, code, rest = text:match("^JT~1~([IRXFA])~([AH])~(.*)$")
	if not op or code ~= Code() then return false end
	local f = {}; for part in (rest .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	J.Prune()
	if op == "I" then
		local seq, at, guild, assignee, subject = Number(f[1]), Number(f[2]), f[3], Name(f[4]), Name(f[5])
		if #f ~= 5 or not Issuer(sender) or not J.Own() or not seq or seq == 0 or not at or at > Now() + 60 or Now() - at > J.KEEP
			or not Same(guild, Guild()) or not Same(assignee, ns.me) or not Member(subject, guild) or Same(subject, ns.me) or ns.IsKingCharacter(subject) then return false end
		local s = Bucket(true); if not s then return false end
		local key = Key(sender, seq); local old = s.tasks[key]
		if old then
			if not Valid(old) or old.createdAt ~= at or not Same(old.guild, guild) or not Same(old.assignee, assignee) or not Same(old.subject, subject) then return false end
			if not OwnTask(old) then return false end
			Receipt(old); return true
		end
		if seq <= (s.floors[ns.Fold(sender)] or 0) or not Room(s, sender) then return false end
		local t = { issuer = sender, seq = seq, createdAt = at, guild = guild, assignee = assignee, subject = subject, receivedAt = Now() }
		s.tasks[key] = t; s.floors[ns.Fold(sender)] = s.floors[ns.Fold(sender)] or 0
		Receipt(t); Changed(); return true
	elseif op == "R" then
		local issuer, seq, received, attempted, absent = Name(f[1]), Number(f[2]), Number(f[3]), Number(f[4]), Number(f[5])
		local s = Bucket(false); local t = issuer and seq and s and s.tasks[Key(issuer, seq)]
		if #f ~= 5 or not J.CanIssue() or not Valid(t) or not Same(t.issuer, ns.me) or not Same(sender, t.assignee) or not Correspondent(sender, t.guild)
			or not received or received < t.createdAt or received > Now() + 60 or not attempted or not absent
			or (attempted > 0 and (attempted < received or attempted > Now() + 60)) or (absent > 0 and (attempted == 0 or absent < attempted or absent > Now() + 60)) then return false end
		if t.cancelledAt or t.confirmedAt then
			if Now() - (t.recoveryAt or 0) >= J.EVERY then t.recoveryAt = Now(); t.terminalTries = 0; Terminal(t) end
			return false
		end
		if t.receivedAt and t.receivedAt ~= received then return false end
		if (t.attemptedAt and t.attemptedAt ~= attempted) or (t.absentAt and t.absentAt ~= absent) then return false end
		t.receivedAt = received
		if attempted > 0 then t.attemptedAt = attempted end
		if absent > 0 then t.absentAt = absent end
		Changed(); return true
	elseif op == "X" or op == "F" then
		local seq = Number(f[1]); local s = Bucket(false); local t = seq and s and s.tasks[Key(sender, seq)]
		if op == "X" and #f == 2 and Number(f[2]) and tonumber(f[2]) <= Now() + 60 and seq and seq > 0 and Issuer(sender) and J.Own() and not t then
			s = Bucket(true); if not s or not Room(s, sender) then return false end
			s.floors[ns.Fold(sender)] = math.max(s.floors[ns.Fold(sender)] or 0, seq); return true
		end
		if not Valid(t) or not J.Own() or not Same(t.assignee, ns.me) or not Same(t.guild, Guild()) or not Same(sender, t.issuer) or not Issuer(sender) then return false end
		if op == "X" and #f == 2 and Number(f[2]) and tonumber(f[2]) >= t.createdAt and tonumber(f[2]) <= Now() + 60 and not t.confirmedAt then
			if t.cancelledAt and t.cancelledAt ~= tonumber(f[2]) then return false end
			t.cancelledAt = tonumber(f[2]); pending[Key(sender, seq)] = nil
		elseif op == "F" and #f == 2 and Number(f[2]) and tonumber(f[2]) <= Now() + 60 and t.attemptedAt and t.absentAt and tonumber(f[2]) >= t.absentAt then
			if t.cancelledAt or (t.confirmedAt and t.confirmedAt ~= tonumber(f[2])) then return false end
			t.confirmedAt, t.confirmedBy = tonumber(f[2]), sender
		else return false end
		TerminalAck(t); Changed(); return true
	elseif op == "A" then
		local issuer, seq, at = Name(f[1]), Number(f[2]), Number(f[4]); local s = Bucket(false)
		local t = issuer and seq and s and s.tasks[Key(issuer, seq)]
		if #f ~= 4 or not J.CanIssue() or not Valid(t) or not Same(t.issuer, ns.me) or not Same(sender, t.assignee) or not Correspondent(sender, t.guild)
			or not at or ((f[3] == "X" and t.cancelledAt ~= at) or (f[3] == "F" and t.confirmedAt ~= at)) or (f[3] ~= "X" and f[3] ~= "F") then return false end
		t.terminalAck = f[3]; Changed(); return true
	end
	return false
end
local cursor = 0
function J.Tick()
	if Preview() then return end
	J.Observe(); J.Prune()
	if ShareTick then ShareTick() end
	local tasks = J.Tasks(); if #tasks == 0 then return end
	for _ = 1, math.min(3, #tasks) do
		cursor = cursor % #tasks + 1
		local t = tasks[cursor].task
		if SignedFacts and J.CanIssue() and Same(t.issuer, ns.me) and Live(t) and t.signedVersion == 2
			and (not t.proofs or not t.proofs.R) and Now() - (t.lastSignedI or 0) >= J.SHARE_EVERY then SignedFacts(t, "I", t.assignee) end
		if J.CanIssue() and Same(t.issuer, ns.me) and Live(t) and not t.receivedAt then Send(t.assignee, IssueWire(t), t, "issue")
		elseif J.CanIssue() and Same(t.issuer, ns.me) and (t.cancelledAt or t.confirmedAt) then Terminal(t)
		elseif OwnTask(t) then Receipt(t) end
	end
end
-- JT2 is a private evidence extension, not another removal authority. I is the original
-- issuer's immutable request, R the original assignee's receipt/observations, T the issuer's
-- human terminal decision. Every signature binds the complete I hash, realm group and faction.
-- A relay's identity never replaces either original actor. JT1 remains direct/local evidence.
J.SHARE_PAGE, J.SHARE_OPEN, J.SHARE_KEEP, J.SHARE_EVERY = 2, 24, 300, 900
local pieces, deferred, checking, checked, asks, keyAsked, answered = {}, {}, {}, {}, {}, {}, {}
local askSeq, peerCursor, lastShare = 0, 0, 0
local quota = { at = 0, n = 0 }
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Checked(id)
	if not checked[id] and Count(checked) >= 512 then checked[next(checked)] = nil end
	checked[id] = true
end
local function Hash(text)
	if type(text) ~= "string" then return nil end
	local S = ns.Sign
	if not S or not S.SHA256 then return nil end
	return (S.SHA256(text):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end
local function Raw(text, len)
	local E = ns.Ed25519
	local ok, raw = pcall(function() return E and E.FromB64 and E.FromB64(text) end)
	return ok and type(raw) == "string" and #raw == len and raw or nil
end
local function KeyStore(make)
	local s = Bucket(make); if not s then return nil end
	if s.identityKeys == nil and make then s.identityKeys = {} end
	return type(s.identityKeys) == "table" and s.identityKeys or nil
end
local function KeepKey(name, pk)
	local store = KeyStore(true); if not store then return false end
	local key = ns.Fold(name); local list = store[key]
	if type(list) ~= "table" then
		if Count(store) >= J.MAX_ISSUERS then return false end
		list = {}; store[key] = list
	end
	for _, old in ipairs(list) do if old == pk then return true end end
	if #list >= 3 then table.remove(list, 1) end
	list[#list + 1] = pk; return true
end
function J.HasKey(name, pk)
	if type(name) ~= "string" or type(pk) ~= "string" then return false end
	local store = KeyStore(false); local list = store and store[ns.Fold(name)]
	for _, old in ipairs(type(list) == "table" and list or {}) do if old == pk and Raw(pk, 32) then return true end end
	return false
end
local function ActorKnown(name)
	if ReadPeer(name) then return true end
	-- An independently native-confirmed correspondent may introduce their own key before
	-- this reader receives any task. That permits later offline recovery, not a new duty.
	if Correspondent(name, Guild()) then return true end
	local s = Bucket(false)
	for _, t in pairs(s and s.tasks or {}) do if Valid(t) and Same(t.assignee, name) and Issuer(t.issuer) then return true end end
	return false
end
local function Private(to, text, key, permit)
	if type(text) ~= "string" or #text > 255 or not Name(to) or not InGroup(to) or Preview() or not Roster() then return false end
	local group, faction, me = ns.group, ns.faction, ns.me
	return ns.Comm.Whisper(to, text, nil, false, true, nil, { owner = J, key = key,
		permit = function(owner, identity, dist, target, payload)
			return owner == J and identity == key and dist == "WHISPER" and Same(target, to) and payload == text
				and not Preview() and Roster() ~= nil and ns.group == group and ns.faction == faction and Same(ns.me, me) and permit()
		end }) ~= false
end
local function MayKey(to)
	return (J.CanReadShared() and ActorKnown(to)) or (J.Own() and ReadPeer(to))
end
function J.SendKey(to)
	if not MayKey(to) then return false end
	local D, A = ns.Debts, ns.Arena
	if not D or not D.ClaimParts or not A or not A.GuidOf then return false end
	local ok, gk, pk, sig = pcall(D.ClaimParts)
	if not ok or not A.GuidOf(gk) or not Raw(pk, 32) or not Raw(sig, 64) then return false end
	KeepKey(ns.FullName(ns.me), pk)
	return Private(to, "JT~2~K~" .. Code() .. "~" .. gk .. "~" .. pk .. "~" .. sig, "key:" .. ns.Fold(to), function() return MayKey(to) end)
end
local function AskKey(actor)
	if not J.CanReadShared() and not J.Own() then return false end
	local now, key = Now(), ns.Fold(actor)
	if now - (keyAsked[key] or 0) < J.EVERY or (not keyAsked[key] and Count(keyAsked) >= J.MAX_ISSUERS) then return false end
	keyAsked[key] = now
	return Private(actor, "JT~2~B~" .. Code(), "key-ask:" .. key, function() return J.CanReadShared() or (J.Own() and ReadPeer(actor)) end)
end
local function Core(t) return table.concat({ "I", ns.group, Code(), t.issuer, t.seq, t.createdAt, t.guild, t.assignee, t.subject }, "~") end
local function Parts(text) local f = {}; for part in (text .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end; return f end
local function Signed(core)
	local D, E = ns.Debts, ns.Ed25519
	if not D or not D.MyKey or not D.Sign or not E or not E.ToB64 then return nil end
	local ok, gk, pk = pcall(D.MyKey)
	if not ok or not gk or type(pk) ~= "string" or #pk ~= 32 then return nil end
	local good, sig = pcall(D.Sign, "OLYJUST2|" .. core)
	if not good or type(sig) ~= "string" or #sig ~= 64 then return nil end
	local pk64 = E.ToB64(pk); KeepKey(ns.FullName(ns.me), pk64)
	return core .. "^" .. pk64 .. "^" .. E.ToB64(sig)
end
local function SendProof(to, proof, permit)
	if type(proof) ~= "string" or #proof > 1024 then return false end
	local id, total, accepted = Hash(proof):sub(1, 16), math.ceil(#proof / 180), true
	for i = 1, total do
		local text = ("JT~2~P~%s~%s~%d~%d~%s"):format(Code(), id, i, total, proof:sub((i - 1) * 180 + 1, i * 180))
		if not Private(to, text, "proof:" .. id .. ":" .. i, permit) then accepted = false end
	end
	return accepted
end
local function Original(t, kind)
	if kind == "R" then return OwnTask(t) and Same(t.assignee, ns.me) end
	return J.CanIssue() and Same(t.issuer, ns.me) and Correspondent(t.assignee, t.guild)
end
SignedFacts = function(t, kind, to, new)
	if not Valid(t) or not Original(t, kind) or (not new and t.signedVersion ~= 2) then return false end
	local core = Core(t)
	if kind == "R" then
		if not t.receivedAt then return false end
		core = table.concat({ "R", Hash(core), t.issuer, t.seq, t.receivedAt, t.attemptedAt or 0, t.absentAt or 0 }, "~")
	elseif kind == "T" then
		if not t.cancelledAt and not t.confirmedAt then return false end
		core = table.concat({ "T", Hash(core), t.issuer, t.seq, t.cancelledAt and "X" or "F", t.cancelledAt or t.confirmedAt }, "~")
	end
	t.proofs = type(t.proofs) == "table" and t.proofs or {}
	local proof = t.proofs[kind]
	if type(proof) ~= "string" or proof:match("^(.-)%^") ~= core then proof = Signed(core); if not proof then return false end; t.proofs[kind] = proof end
	t.signedVersion = 2
	Checked(Hash(proof)) -- this client's own signature, never a persisted trust bit
	J.SendKey(to)
	local sent = SendProof(to, proof, function()
		local s = Bucket(false)
		return s and s.tasks[Key(t.issuer, t.seq)] == t and Original(t, kind)
	end)
	if sent and kind == "I" then t.lastSignedI = Now() end
	return sent
end
local AcceptProof
local function Defer(sender, proof)
	local id = Hash(proof)
	-- A periodic retry is not a new arrival. Preserve the first deadline so unavailable keys
	-- or signatures cannot keep these bounded slots occupied indefinitely.
	if not deferred[id] and Count(deferred) < J.SHARE_OPEN then deferred[id] = { sender = sender, proof = proof, at = Now() } end
	return false
end
local function Budget()
	local now = Now()
	if now - quota.at >= J.EVERY then quota.at, quota.n = now, 0 end
	if quota.n >= 16 then return false end
	quota.n = quota.n + 1; return true
end
local function SameTask(a, b)
	return Valid(a) and Valid(b) and Core(a) == Core(b)
end
local function Asked(sender)
	local ask = asks[ns.Fold(sender)]
	return ask and Now() >= ask.at and Now() - ask.at <= J.SHARE_KEEP or false
end
local function Admissible(t, sender)
	if not Issuer(t.issuer) or not ns.IsFederation(t.guild) then return false end
	if J.CanReadShared() then
		return (ReadPeer(sender) and (Same(sender, t.issuer) or Asked(sender))) or (Same(t.issuer, ns.me) and Same(sender, t.assignee) and Correspondent(sender, t.guild))
	end
	return J.Own() and Same(sender, t.issuer) and Same(t.assignee, ns.me) and Same(t.guild, Guild())
end
local function MergeProof(sender, proof, core, kind, f, candidate)
	if not Admissible(candidate, sender) then return false end
	local s = Bucket(true); if not s then return false end
	local key = Key(candidate.issuer, candidate.seq); local t = s.tasks[key]
	if t and not SameTask(t, candidate) then return false end
	if kind == "I" then
		if not t then
			if candidate.seq <= (s.floors[ns.Fold(candidate.issuer)] or 0) or not Room(s, candidate.issuer) then return false end
			if J.Own() and Same(candidate.assignee, ns.me) and (not Member(candidate.subject, candidate.guild) or Same(candidate.subject, ns.me) or ns.IsKingCharacter(candidate.subject)) then return false end
			t = candidate; s.tasks[key] = t; s.floors[ns.Fold(t.issuer)] = s.floors[ns.Fold(t.issuer)] or 0
		end
		t.signedVersion = 2; t.proofs = type(t.proofs) == "table" and t.proofs or {}; t.proofs.I = proof
		if OwnTask(t) then
			if not t.receivedAt then t.receivedAt = Now() end
			Receipt(t)
		end
	elseif kind == "R" then
		if not t or not t.proofs or not t.proofs.I or not checked[Hash(t.proofs.I)] then return Defer(sender, proof) end
		local received, attempted, absent = Number(f[5]), Number(f[6]), Number(f[7])
		if not received or received < t.createdAt or received > Now() + 60 or not attempted or not absent
			or (attempted > 0 and (attempted < received or attempted > Now() + 60))
			or (absent > 0 and (attempted == 0 or absent < attempted or absent > Now() + 60))
			or (t.receivedAt and t.receivedAt ~= received) or (t.attemptedAt and t.attemptedAt ~= attempted) or (t.absentAt and t.absentAt ~= absent) then return false end
		t.receivedAt = received
		if attempted > 0 then t.attemptedAt = attempted end
		if absent > 0 then t.absentAt = absent end
		t.proofs.R = proof
	elseif kind == "T" then
		if not t or not t.proofs or not t.proofs.I or not checked[Hash(t.proofs.I)] then return Defer(sender, proof) end
		local at = Number(f[6])
		if not at or at < t.createdAt or at > Now() + 60 then return false end
		if f[5] == "X" then
			if t.confirmedAt or (t.cancelledAt and t.cancelledAt ~= at) then return false end
			t.cancelledAt = at; pending[key] = nil
		elseif f[5] == "F" then
			if not t.proofs.R or not checked[Hash(t.proofs.R)] or not t.absentAt then return Defer(sender, proof) end
			if at < t.absentAt or t.cancelledAt or (t.confirmedAt and t.confirmedAt ~= at) then return false end
			t.confirmedAt, t.confirmedBy = at, t.issuer
		else return false end
		t.proofs.T = proof
	end
	deferred[Hash(proof)] = nil; Changed(); return true
end
AcceptProof = function(sender, proof, stored)
	if type(proof) ~= "string" or #proof > 1024 then return false end
	local core, pk, sig = proof:match("^(.-)%^([%w_-]+)%^([%w_-]+)$")
	if not core or #proof > 1024 or not Raw(pk, 32) or not Raw(sig, 64) then return false end
	local f, candidate, actor = Parts(core)
	local kind = f[1]
	if kind == "I" and #f == 9 then
		if f[2] ~= ns.group or f[3] ~= Code() then return false end
		candidate = { issuer = Name(f[4]), seq = Number(f[5]), createdAt = Number(f[6]), guild = f[7], assignee = Name(f[8]), subject = Name(f[9]) }
		if not Valid(candidate) or candidate.createdAt > Now() + 60 or Now() - candidate.createdAt > J.KEEP then return false end
		actor = candidate.issuer
	elseif (kind == "R" and #f == 7) or (kind == "T" and #f == 6) then
		local issuer, seq = Name(f[3]), Number(f[4]); local s = Bucket(false)
		candidate = issuer and seq and s and s.tasks[Key(issuer, seq)]
		if not Valid(candidate) then return Defer(sender, proof) end
		if f[2] ~= Hash(Core(candidate)) then return false end
		actor = kind == "R" and candidate.assignee or candidate.issuer
	else return false end
	if stored then
		if kind == "I" then
			local s = Bucket(false); local held = s and s.tasks[Key(candidate.issuer, candidate.seq)]
			if not SameTask(held, candidate) then return false end
			candidate = held
		end
		if not J.Visible() or not Issuer(candidate.issuer) or not candidate.proofs then return false end
		local held = candidate.proofs[kind]
		if held ~= proof then return false end
	elseif not Admissible(candidate, sender) then return false end
	if not J.HasKey(actor, pk) then AskKey(actor); return Defer(sender, proof) end
	local id = Hash(proof)
	if checked[id] then return stored or MergeProof(sender, proof, core, kind, f, candidate) end
	if checking[id] or not Budget() or not ns.Arena or not ns.Arena.Check then return Defer(sender, proof) end
	checking[id] = true
	local group, faction = ns.group, ns.faction
	ns.Arena.Check("justice2:" .. id, { pk = Raw(pk, 32), sig = Raw(sig, 64), msg = "OLYJUST2|" .. core }, function(good)
		checking[id] = nil
		if group ~= ns.group or faction ~= ns.faction or not J.HasKey(actor, pk) or Preview() or not Roster() then return end
		-- Verification is deferred. Neither a saved proof nor a requested relay may outlive
		-- the reader/issuer authority or change task identity while that work is queued.
		if not Valid(candidate) or not Issuer(candidate.issuer) then return end
		if stored then
			local s = Bucket(false)
			if not J.Visible() or not s or s.tasks[Key(candidate.issuer, candidate.seq)] ~= candidate
				or not candidate.proofs or candidate.proofs[kind] ~= proof then return end
		elseif not Admissible(candidate, sender) then return end
		if (kind == "I" and Core(candidate) ~= core) or (kind ~= "I" and Hash(Core(candidate)) ~= f[2]) then return end
		if good == true then Checked(id); if not stored then MergeProof(sender, proof, core, kind, f, candidate) end
		elseif good == nil then Defer(sender, proof) else deferred[id] = nil end
	end)
	return true
end
local function AllowedSender(sender)
	if J.CanReadShared() and ReadPeer(sender) then return Asked(sender) end
	if J.Own() and Issuer(sender) then return true end
	local s = Bucket(false)
	for _, t in pairs(s and s.tasks or {}) do
		if J.CanReadShared() and Valid(t) and Same(t.issuer, ns.me) and Same(t.assignee, sender) and Correspondent(sender, t.guild) then return true end
	end
	return false
end
function J.Sync(peer)
	peer = Name(peer)
	if not J.CanReadShared() or not peer or Same(peer, ns.me) or not ReadPeer(peer) then return false end
	local key, prior = ns.Fold(peer), asks[ns.Fold(peer)]
	if prior and Now() - prior.at < J.EVERY then return false end
	if not prior and Count(asks) >= J.MAX_ISSUERS then return false end
	askSeq = math.max(Now(), askSeq + 1)
	local cursor = prior and prior.cursor or 0
	asks[key] = { nonce = askSeq, cursor = cursor, at = Now() }
	J.SendKey(peer)
	return Private(peer, ("JT~2~Q~%s~%d~%d"):format(Code(), askSeq, cursor), "sync:" .. key, function() return J.CanReadShared() and ReadPeer(peer) end)
end
TakeShared = function(sender, text)
	local op, code, rest = text:match("^JT~2~([BKPQZ])~([AH])~?(.*)$")
	if not op or code ~= Code() then return false end
	if op == "B" then
		if rest ~= "" or not MayKey(sender) then return false end
		if Now() - (answered["key:" .. ns.Fold(sender)] or 0) < J.EVERY then return false end
		answered["key:" .. ns.Fold(sender)] = Now(); return J.SendKey(sender)
	elseif op == "K" then
		local f = Parts(rest); local gk, pk, sig = f[1], f[2], f[3]
		local A, D = ns.Arena, ns.Debts; local guid = A and A.GuidOf and A.GuidOf(gk)
		if #f ~= 3 or not guid or not Raw(pk, 32) or not Raw(sig, 64) or not ActorKnown(sender) or not (J.CanReadShared() or J.Own()) then return false end
		if J.HasKey(sender, pk) then return true end
		-- No key embedded in a relay proof enters this cache. The original actor must whisper
		-- its OLYA1 claim itself, and the native GUID/name lookup must bind it independently.
		if not D or not D.Bind or not D.Bind(sender, guid) or not A.Check or not Budget() then return false end
		local group, faction = ns.group, ns.faction
		A.Check("justice-key:" .. ns.Fold(sender) .. ":" .. Hash(pk .. sig), { pk = Raw(pk, 32), sig = Raw(sig, 64), msg = "OLYA1|" .. guid .. "|" .. sender }, function(good)
			if good == true and not Preview() and Roster() and (J.CanReadShared() or J.Own()) and ns.group == group and ns.faction == faction and ActorKnown(sender) and D.Bind(sender, guid) then KeepKey(sender, pk); Changed() end
		end)
		return true
	elseif op == "Q" then
		local f = Parts(rest); local nonce, cursor = Number(f[1]), Number(f[2])
		if #f ~= 2 or not nonce or not cursor or cursor > J.MAX or not J.CanReadShared() or not ReadPeer(sender) then return false end
		local who = ns.Fold(sender)
		if Now() - (answered[who] or 0) < J.EVERY or (not answered[who] and Count(answered) >= J.MAX_ISSUERS * 2) then return false end
		answered[who] = Now(); J.SendKey(sender)
		local list = {}
		for _, e in ipairs(J.Tasks()) do if e.task.signedVersion == 2 and type(e.task.proofs) == "table" and type(e.task.proofs.I) == "string" and Issuer(e.task.issuer) then list[#list + 1] = e end end
		table.sort(list, function(a, b) return a.key < b.key end)
		if cursor >= #list then cursor = 0 end
		local last = math.min(cursor + J.SHARE_PAGE, #list)
		for i = cursor + 1, last do
			local t = list[i].task
			for _, kind in ipairs({ "I", "R", "T" }) do if t.proofs[kind] then
				SendProof(sender, t.proofs[kind], function() return J.CanReadShared() and ReadPeer(sender) and Issuer(t.issuer) end)
			end end
		end
		return Private(sender, ("JT~2~Z~%s~%d~%d"):format(Code(), nonce, last >= #list and 0 or last), "sync-end:" .. who, function() return J.CanReadShared() and ReadPeer(sender) end)
	elseif op == "Z" then
		local f = Parts(rest); local ask = asks[ns.Fold(sender)]
		local cursor = Number(f[2])
		if #f ~= 2 or not J.CanReadShared() or not ReadPeer(sender) or not ask or Now() - ask.at > J.SHARE_KEEP or Number(f[1]) ~= ask.nonce or not cursor or cursor > J.MAX then return false end
		ask.cursor = cursor; return true
	elseif op == "P" then
		if not AllowedSender(sender) then return false end
		local id, i, n, chunk = rest:match("^([a-f0-9]+)~(%d+)~(%d+)~(.+)$")
		i, n = Number(i), Number(n)
		if not id or #id ~= 16 or not i or not n or i < 1 or i > n or n > 6 or #chunk > 180 then return false end
		local key = ns.Fold(sender) .. ":" .. id; local p = pieces[key]
		if not p then
			local count = 0; for _, v in pairs(pieces) do if Same(v.sender, sender) then count = count + 1 end end
			if count >= 2 or Count(pieces) >= J.SHARE_OPEN then return false end
			p = { sender = sender, n = n, parts = {}, at = Now(), got = 0 }; pieces[key] = p
		end
		if p.n ~= n or (p.parts[i] and p.parts[i] ~= chunk) then return false end
		if not p.parts[i] then p.parts[i] = chunk; p.got = p.got + 1 end
		if p.got < n then return true end
		pieces[key] = nil
		local proof = table.concat(p.parts)
		if #proof > 1024 or Hash(proof):sub(1, 16) ~= id then return false end
		return AcceptProof(sender, proof)
	end
	return false
end
ShareTick = function()
	local now = Now()
	for key, p in pairs(pieces) do if now - p.at > J.SHARE_KEEP then pieces[key] = nil end end
	local retry = {}; for id, p in pairs(deferred) do
		if now - p.at > J.SHARE_KEEP then deferred[id] = nil else retry[#retry + 1] = p end
	end
	for i = 1, math.min(3, #retry) do AcceptProof(retry[i].sender, retry[i].proof) end
	if not J.CanReadShared() or now - lastShare < J.EVERY then return end
	lastShare = now
	local names, seen = {}, {}
	local function Add(name)
		name = Name(name)
		if name and not Same(name, ns.me) and ReadPeer(name) and not seen[ns.Fold(name)] then seen[ns.Fold(name)] = true; names[#names + 1] = name end
	end
	local K = ns.KingCharacter and ns.KingCharacter(); if K then Add(ns.FullName(K, ns.KingRealm())) end
	local W = ns.Workshop
	if W and W.AuthorName then Add(W.AuthorName()) end
	for _, author in ipairs(ns.AuthorCharacters and (ns.AuthorCharacters()) or {}) do Add(author) end
	for short in pairs(ns.rdb and ns.rdb.council and ns.rdb.council.names or {}) do Add(short) end
	for full in pairs(KeyStore(false) or {}) do Add(full) end
	table.sort(names)
	if #names == 0 then return end
	peerCursor = peerCursor % #names + 1
	local peer = names[peerCursor]; local prior = asks[ns.Fold(peer)]
	if not prior or now - prior.at >= J.SHARE_EVERY then J.Sync(peer) end
end
local function ProvenCore(proof, actor)
	if type(proof) ~= "string" then return nil end
	local core, pk = proof:match("^(.-)%^([%w_-]+)%^[%w_-]+$")
	return core and J.HasKey(actor, pk) and checked[Hash(proof)] and core or nil
end
local function TimedFacts(t)
	local p = t.proofs
	if type(p) ~= "table" or ProvenCore(p.I, t.issuer) ~= Core(t) then return nil end
	local out = { issuer = t.issuer, assignee = t.assignee, createdAt = t.createdAt }
	local receipt = ProvenCore(p.R, t.assignee)
	if receipt then
		local f = Parts(receipt)
		local received, attempted, absent = Number(f[5]), Number(f[6]), Number(f[7])
		if #f ~= 7 or f[1] ~= "R" or f[2] ~= Hash(Core(t)) or f[3] ~= t.issuer or Number(f[4]) ~= t.seq
			or not received or received < t.createdAt or received > Now() + 60 or not attempted or not absent
			or (attempted > 0 and (attempted < received or attempted > Now() + 60))
			or (absent > 0 and (attempted == 0 or absent < attempted or absent > Now() + 60)) then return nil end
		out.receivedAt, out.attemptedAt, out.absentAt = received, attempted > 0 and attempted or nil, absent > 0 and absent or nil
	end
	local terminal = ProvenCore(p.T, t.issuer)
	if terminal then
		local f = Parts(terminal); local at = Number(f[6])
		if #f == 6 and f[1] == "T" and f[2] == Hash(Core(t)) and f[3] == t.issuer and Number(f[4]) == t.seq and at and at >= t.createdAt and at <= Now() + 60 then
			if f[5] == "X" then out.cancelledAt = at
			elseif f[5] == "F" and out.absentAt and at >= out.absentAt then out.confirmedAt = at end
		end
	end
	return out
end
function J.ResponseMetric()
	if not J.Visible() then return nil end
	local out = { by = {}, rows = {}, days = 30, maximum = J.MAX, partial = true, legacy = 0, unknown = 0 }
	for _, e in ipairs(J.Tasks()) do
		local t, p = e.task, e.task.proofs
		if type(p) ~= "table" or type(p.I) ~= "string" then out.legacy = out.legacy + 1
		else
			-- Persisted signatures are rechecked after reload; never trust a saved verified flag.
			for _, kind in ipairs({ "I", "R", "T" }) do if p[kind] and not checked[Hash(p[kind])] then
				local actor = kind == "R" and t.assignee or t.issuer
				AcceptProof(actor, p[kind], true)
			end end
			local facts = TimedFacts(t)
			if not facts or not Issuer(t.issuer) or not Correspondent(t.assignee, t.guild) then out.unknown = out.unknown + 1
			else
				local row = out.by[t.assignee]
				if not row then row = { assignee = t.assignee, received = 0, deliveryUnknown = 0, pending = 0, attempted = 0, completed = 0, cancelled = 0, times = {} }; out.by[t.assignee] = row end
				if facts.receivedAt then
					row.received = row.received + 1
					if facts.cancelledAt then row.cancelled = row.cancelled + 1
					elseif facts.confirmedAt then row.completed = row.completed + 1
					else row.pending = row.pending + 1 end
				else row.deliveryUnknown = row.deliveryUnknown + 1 end
				if facts.attemptedAt then row.attempted = row.attempted + 1; row.times[#row.times + 1] = facts.attemptedAt - facts.receivedAt end
			end
		end
	end
	for _, row in pairs(out.by) do
		table.sort(row.times); local n = #row.times
		if n > 0 then row.medianSeconds = n % 2 == 1 and row.times[(n + 1) / 2] or (row.times[n / 2] + row.times[n / 2 + 1]) / 2 end
		out.rows[#out.rows + 1] = row
	end
	table.sort(out.rows, function(a, b)
		if a.medianSeconds ~= b.medianSeconds then return (a.medianSeconds or math.huge) < (b.medianSeconds or math.huge) end
		return ns.Fold(a.assignee) < ns.Fold(b.assignee)
	end)
	return out
end
function J.SharedStatus()
	if not J.Visible() then return nil end
	return { partial = true, originalKeys = Count(KeyStore(false) or {}), pendingProofs = Count(deferred), openPieces = Count(pieces), verifying = Count(checking) }
end
function J.ReportMetric()
	if not J.Visible() then return nil end
	local W = ns.Watch; if not W or not W.CouncilStore then return nil end
	if W.PruneCouncil then W.PruneCouncil() end
	local s = W.CouncilStore(false); if not s then return nil end
	local by, n = {}, 0
	for _, r in pairs(s.reports) do if type(r) == "table" and r.council == true and Name(r.reporter) and Number(r.at) and Now() - r.at <= W.REPORT_KEEP then
		if J.Staff() or Same(r.reporter, ns.me) then by[r.reporter] = (by[r.reporter] or 0) + 1; n = n + 1 end
	end end
	return { by = by, retained = n, days = 30, maximum = 200, partial = true }
end
local function Shown(name)
	local text = ns.DisplayName(name) or name
	return ns.CouncilMasked and ns.CouncilMasked() and ns.MaskName and ns.MaskName(text) or ns.Codec.Plain(text)
end
function J.Lines()
	if not J.Visible() then return {} end
	local lines = { { header = true, text = Word("JUSTICE_TASKS_TITLE", "Justice requests - private activity") },
		{ text = Word("JUSTICE_TASKS_EVIDENCE", "Native action attempted and later roster absence are separate observations, not proof of who caused the removal. Completion needs the issuer's explicit human review."), wrap = true },
		{ text = Word("JUSTICE_TASKS_COVERAGE", "Only tasks retained here: at most 60, for 30 days. Unknown or offline delivery is not time spent by the correspondent."), wrap = true } }
	if not J.Staff() then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_OWN", "Only your assigned requests and own activity are shown."), wrap = true } end
	if J.CanIssue() then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_NEW", "Request a deliberate guild removal"), onClick = function()
		if J.CanIssue() then ns.ShowDialog("OLYMPUS_JUSTICE_NEW", nil, nil) end
	end } end
	local tasks = J.Tasks()
	for _, e in ipairs(tasks) do
		local t, key = e.task, e.key
		local state = t.cancelledAt and Word("JUSTICE_TASKS_CANCELLED", "Cancelled") or t.confirmedAt and Word("JUSTICE_TASKS_CONFIRMED", "Human-confirmed completion")
			or t.absentAt and Word("JUSTICE_TASKS_ABSENT", "Observed absent; completion pending") or t.attemptedAt and Word("JUSTICE_TASKS_ATTEMPTED", "Native removal attempted; completion pending")
			or t.receivedAt and Word("JUSTICE_TASKS_RECEIVED", "Received; action pending") or Word("JUSTICE_TASKS_WAITING", "Delivery not acknowledged")
		lines[#lines + 1] = { header = true, text = Shown(t.subject) .. " - " .. state }
		lines[#lines + 1] = { text = ("%s · %s -> %s"):format(ns.Codec.Plain(t.guild), Shown(t.issuer), Shown(t.assignee)), indent = 1 }
		if t.receivedAt then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_ELAPSED", "Receipt -> manual attempt: %s"):format(t.attemptedAt and ((t.attemptedAt - t.receivedAt) .. "s") or Word("JUSTICE_TASKS_PENDING", "pending")), indent = 1 } end
		if J.CanIssue() and Same(t.issuer, ns.me) and (t.cancelledAt or t.confirmedAt) and not t.terminalAck then
			lines[#lines + 1] = { text = Word("JUSTICE_TASKS_RETRY", "Terminal decision delivery unacknowledged - retry privately"), indent = 1, onClick = function() J.Retry(key) end }
		end
		if OwnTask(t) and not t.attemptedAt then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_REMOVE", "Review this member in the existing removal dialog"), indent = 1, onClick = function() return J.AskRemoval(key) end } end
		if J.CanIssue() and Live(t) and Same(t.issuer, ns.me) then
			lines[#lines + 1] = { text = Word("JUSTICE_TASKS_CANCEL", "Cancel request"), indent = 1, onClick = function() J.Cancel(key) end }
			if t.attemptedAt and t.absentAt then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_CONFIRM", "Review and confirm completion (human judgement)"), indent = 1,
				onClick = function() ns.ShowDialog("OLYMPUS_JUSTICE_CONFIRM", Shown(t.subject), nil, key) end } end
		end
	end
	if #tasks == 0 then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_EMPTY", "No retained requests visible to you.") } end
	local response = J.ResponseMetric()
	lines[#lines + 1] = { header = true, text = Word("JUSTICE_RESPONSE_TITLE", "Response time - private retained evidence") }
	lines[#lines + 1] = { text = Word("JUSTICE_RESPONSE_COVERAGE", "Original issuer and assignee signatures only; at most 60 requests for 30 days. Lower median receipt-to-manual-attempt time sorts first. Sample size, unknown delivery, pending and human-confirmed completion are separate; this is not quality or proof of who caused removal."), wrap = true }
	if response then
		for _, row in ipairs(response.rows) do
			lines[#lines + 1] = { text = Shown(row.assignee), right = row.medianSeconds and (row.medianSeconds .. "s") or Word("JUSTICE_TASKS_UNKNOWN_TIME", "unknown") }
			lines[#lines + 1] = { text = Word("JUSTICE_RESPONSE_COUNTS", "Received: %d · timed attempts: %d · pending: %d · human-confirmed: %d · cancelled: %d · delivery unknown: %d"):format(row.received, row.attempted, row.pending, row.completed, row.cancelled, row.deliveryUnknown), indent = 1, wrap = true }
		end
		lines[#lines + 1] = { text = Word("JUSTICE_RESPONSE_UNVERIFIED", "Legacy/local-only: %d · original evidence or current authority unknown: %d. Neither is ranked."):format(response.legacy, response.unknown), wrap = true }
	end
	local share = J.SharedStatus()
	if share then lines[#lines + 1] = { text = Word("JUSTICE_RESPONSE_SYNC", "Original proofs awaiting keys or verification: %d. Partial private coverage; an offline or older client is not inactivity."):format(share.pendingProofs + share.openPieces + share.verifying), wrap = true } end
	local metric = J.ReportMetric()
	lines[#lines + 1] = { header = true, text = Word("JUSTICE_TASKS_REPORTS", "Reports - separate retained activity") }
	lines[#lines + 1] = { text = Word("JUSTICE_TASKS_REPORT_COVERAGE", "Only latest accepted reporter/subject pairs held here, at most 200 for 30 days. Partial coverage, not total sent, quality, or lifetime work."), wrap = true }
	if metric then
		lines[#lines + 1] = { text = Word("JUSTICE_TASKS_REPORT_COUNT", "Locally retained accepted report pairs: %d (partial coverage)."):format(metric.retained), wrap = true }
		local names = {}; for name in pairs(metric.by) do names[#names + 1] = name end; table.sort(names)
		for _, name in ipairs(names) do lines[#lines + 1] = { text = Shown(name), right = tostring(metric.by[name]) } end
	else lines[#lines + 1] = { text = Word("JUSTICE_TASKS_UNKNOWN", "No retained council report evidence here; count unknown.") } end
	return lines
end
StaticPopupDialogs["OLYMPUS_JUSTICE_NEW"] = { text = Word("JUSTICE_TASKS_NEW_HINT", "Guild | exact Justice correspondent | member to remove. This is an explicit private request, not an automatic removal."),
	button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 360, maxLetters = 220,
	OnShow = function(self) local e = self.editBox or self.EditBox; if e then e:SetText(""); e:SetFocus() end end,
	OnAccept = function(self) local edit = self.editBox or self.EditBox; local text = edit and edit:GetText() or ""
		local guild, assignee, subject = text:match("^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
		return J.Issue(guild, assignee, subject)
	end, timeout = 0, whileDead = true, hideOnEscape = true }
StaticPopupDialogs["OLYMPUS_JUSTICE_CONFIRM"] = { text = Word("JUSTICE_TASKS_CONFIRM_HINT", "Confirm completion for %s after your own review? The attempt and observed absence do not certify the actor or cause. This record will be labelled human-confirmed."),
	button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel", OnAccept = function(self, key) return J.Confirm(key or (self and self.data)) end,
	timeout = 0, whileDead = true, hideOnEscape = true }
ns.Comm.Handle("JT", J.Handle)
ns.On("MEMBER_REMOVAL_ATTEMPT", Attempt)
ns.On("DATA_CHANGED", J.Observe)
ns.On("LOGIN", function() ns.Every(J.EVERY, "justice private tasks", J.Tick) end)
