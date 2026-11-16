local _, ns = ...
local L, R = ns.L, ns.Recruit
local H = {}
R.Handoff = H

-- Compatibility facade for older call sites; no referral traffic or timers remain.
-- Player feedback: passing invites to other members caused unwanted messages and spam.
local function NameOf(item) return item.scanned and item.full or item.name end
local function NameKey(name)
	local who = ns.FullName(name)
	return ns.Fold(ns.splitNames and ns.ShortName(who) or who)
end
local function Off() return false end
local function Empty() end
H.State, H.Taken = Empty, Off
H.Toggle, H.ToggleAuto, H.AutoOn, H.Accepting = Off, Off, Off, Off
H.Offer, H.Claim, H.CanPass, H.Pass, H.Overflow, H.PassBlocked = Off, Off, Off, Off, Off, Off
H.SetAuto, H.SetAccepting, H.Receive = Off, Off, Off
H.Controls, H.RequestLines, H.Reset = Empty, Empty, Empty
function H.Restore(saved)
	if type(saved) == "table" then saved.acceptHandoffs, saved.offerOverflow = nil, nil end
end
ns.Comm.Handle("J4", Off) -- Ignore legacy clients silently, without replies or applicant logging.

H.LOG_MAX, H.SEEN_PER_MINUTE = 200, 6
local PACKET = { P = "probe", V = "available", D = "declined", O = "offer", C = "claim", N = "name", A = "ack" }
local seenTags, seenAt = {}, {}

function H.Tag(name)
	if type(name) ~= "string" or name == "" then return "?" end
	local key, h = NameKey(name), 5381
	for i = 1, #key do h = (h * 33 + key:byte(i)) % 65536 end
	local letters, n = {}, 0
	for ch in (ns.ShortName(name) or name):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		letters[n] = ch
		if n == 2 then break end
	end
	return ("%s%04x"):format(table.concat(letters), h)
end

local function MemberShort(name)
	return type(name) == "string" and (ns.ShortName(name) or name) or "?"
end

function H.Log(code, detail)
	local db = ns.db
	if type(db) ~= "table" or type(code) ~= "string" then return end
	local log = db.recruitLog
	if type(log) ~= "table" then
		log = {}
		db.recruitLog = log
	end
	local t = (GetServerTime and GetServerTime()) or (time and time()) or 0
	detail = ns.Cut(tostring(detail or ""):gsub("[%c|]", ""), 120)
	log[#log + 1] = ("%d %s %s"):format(t, code, detail)
	while #log > H.LOG_MAX do table.remove(log, 1) end
end

-- A handoff packet sent (`kind` "TX", or "GUARD" when its check refused it at the send) or heard
-- ("RX", or "REFUSED"), with the member and, for a name, the applicant's tag.
function H.LogPacket(kind, op, peer, applicant)
	local name = applicant and applicant ~= "" and (" " .. H.Tag(applicant)) or ""
	local arrow = (kind == "RX" or kind == "REFUSED") and "<" or ">"
	H.Log(kind, ("%s%s %s %s"):format(PACKET[op] or tostring(op), name, arrow, MemberShort(peer)))
end

-- A scanned player seen (`source`: target, nameplate, who, mouseover): once a session per player
-- and SEEN_PER_MINUTE a minute at most, so a crowded city does not push the handoffs out.
function H.LogSeen(source, name)
	local tag = H.Tag(name)
	if seenTags[tag] then return end
	local now = ns.Now()
	for i = #seenAt, 1, -1 do if now - seenAt[i] >= 60 then table.remove(seenAt, i) end end
	if #seenAt >= H.SEEN_PER_MINUTE then return end
	seenAt[#seenAt + 1] = now
	seenTags[tag] = true
	H.Log("SEEN", ("%s %s"):format(tostring(source), tag))
end

function H.LogItem(code, item, extra)
	if type(item) ~= "table" then return end
	H.Log(code, ("%s%s%s"):format(item.scanned and "scan " or "", H.Tag(NameOf(item)), extra and (" " .. extra) or ""))
end

local function Stamp(t)
	return date and date("%H:%M:%S", t) or tostring(t)
end

-- The newest `max` lines (all with none), newest last, each "hh:mm:ss CODE detail".
function H.LogLines(max)
	local log = type(ns.db) == "table" and type(ns.db.recruitLog) == "table" and ns.db.recruitLog or {}
	local out = {}
	for i = math.max(1, #log - (max or #log) + 1), #log do
		local t, rest = tostring(log[i]):match("^(%d+) (.*)$")
		if t then out[#out + 1] = Stamp(tonumber(t)) .. " " .. rest end
	end
	return out
end

-- One line of where this client stands: recruiting, accepting, offering, scanning, the invites
-- taken this minute, and the members online this client heard run Olympus.
function H.Summary()
	return "Recruiting invites stay with this recruiter. Invite handoffs removed following reports of spam."
end

-- /oly bug's section: the summary and the newest `max` lines.
function H.BugLines(max)
	local out = { "Recruiting: " .. H.Summary() }
	local lines = H.LogLines(max or 40)
	if #lines == 0 then out[#out + 1] = "  (no recruiting events yet)" end
	for _, line in ipairs(lines) do out[#out + 1] = "  " .. line end
	return out
end

-- Review of 1.5.8: a bug report sent in game stops at Workshop.BUG_MAX bytes, and its recruiting
-- section comes last, past the status, debug and log sections: what another member sent back lost
-- the lines that show he received a player. /oly recruit send sends the log alone instead: who sent
-- it, the summary and the newest lines that fit, newest last.
function H.SendText()
	local W = ns.Workshop
	local budget = (W and W.BUG_MAX or 4800) - 16
	local head = ("Recruiting log of %s (Olympus %s)\n%s"):format(MemberShort(ns.me), tostring(ns.VERSION), H.Summary())
	local lines, picked, size = H.LogLines(), {}, #head + 2
	for i = #lines, 1, -1 do
		size = size + #lines[i] + 2 -- (a line break travels as two bytes)
		if size > budget then break end
		table.insert(picked, 1, lines[i])
	end
	return head .. "\n" .. (#picked > 0 and table.concat(picked, "\n") or L.RECRUIT_LOG_EMPTY)
end

local testSerial = 0
-- /oly recruit: `log` opens the whole log in the copy window; `testjoin [Name]`, on a test build
-- only, feeds a JOIN whisper from that name (or a made-up one with digits, never a real character)
-- to the same handler the game's whisper reaches.
function H.Slash(rest)
	local word, arg = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
	word = (word or ""):lower()
	if word == "log" or word == "registro" then
		local lines = H.LogLines()
		local text = H.Summary() .. "\n\n" .. (#lines > 0 and table.concat(lines, "\n") or L.RECRUIT_LOG_EMPTY)
		if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy("/oly recruit log", text, nil, { key = "recruitlog", big = true }) end
		return true
	elseif word == "send" or word == "enviar" then
		local W = ns.Workshop
		if not (W and W.AuthorOnline and W.AuthorOnline()) then
			ns.Print(L.RECRUIT_SEND_OFFLINE)
			return false
		end
		return W.SendBug(H.SendText()) and true or false
	elseif word == "testjoin" then
		if not rawget(ns, "TEST_BUILD") then
			ns.Print(L.RECRUIT_TESTJOIN_OFF)
			return false
		end
		local name = arg
		if name == "" then
			testSerial = testSerial + 1
			local t = (time and time()) or 0
			name = ("Olytest%d%d"):format(t % 100000, testSerial)
		end
		H.Log("TESTJOIN", H.Tag(ns.FullName(name)))
		ns.Print(L.RECRUIT_TESTJOIN_SENT:format(name))
		R.OnWhisper("JOIN", name)
		return true
	end
	ns.Print(L.RECRUIT_LOG_USAGE)
	return false
end

function H.ResetLogForTests()
	wipe(seenTags)
	wipe(seenAt)
	testSerial = 0
end
