local ADDON, ns = ...
local L = ns.L

-- The King's key rotation (1.1, Fern's request #8, its second part): a leaked realm key (/oly key)
-- shut without teaching everyone /oly key by hand. The King alone (his pinned character: no
-- Steward, Hand or officer) presses Rotate on the Throne; his addon makes a new key (never typed,
-- never shown: not on his stream either) and hands it out where only its receivers read it,
-- never on the Olympus channel (public, or sealed with the key that leaked):
--   K3~<epoch>~<key>   by whisper from the King to every Lord and Captain the census confirms
--                      online (Data.KnownRank), and over GUILD from each of them (their officers)
--                      to their own guild; K1~<key> with it there, for guildmates before 1.1.
--   K4~<epoch>~<guild> a Lord's or Captain's addon tells the King it has it (a whisper).
--   K5~<epoch held>    over GUILD, after login: a guildmate asks whether a newer key exists;
--                      an officer holding one answers with K3.
-- The epoch is the server's second the key was made (or an officer typed one, 1.1): every 1.1
-- client keeps the newest, and a key without one (K1 alone, from an officer before 1.1) no
-- longer replaces it. A K3 takes a whisper from the King's pinned name alone, or GUILD from our
-- own officers (the server's roster), and never the channel.
-- The King's client keeps handing the key to Lords and Captains who come online for GRACE, on
-- the old channel, then moves (with his guild); "Move now" sooner. Guilds with no officer online
-- in that time stay on the old channel until one of theirs types the key by hand; the Throne says
-- how many acknowledged. Older clients ignore K3, K4 and K5.

local Keys = {}
ns.Keys = Keys

Keys.GRACE = 600          -- the King's client hands the new key out this long before it moves
Keys.RESEND = 600         -- the same Lord or Captain is whispered again after this long without an answer
Keys.MAX_WHISPERS = 60    -- whispers a round at most (the queue sends one each 1.2 s)
Keys.DATE_AHEAD = 60      -- an epoch further ahead of the server's clock is not taken
Keys.ANSWER_GAP = 60      -- an officer answers a guildmate's ask (K5) once a minute at most
Keys.ASK_AFTER = 25       -- the ask goes this long after login
Keys.ONLINE_FRESH = 240   -- a Lord or Captain counts as online from a report this recent (a whisper to
                          -- someone who logged off since shows the King the game's "no player named" line)

local stats = { rotated = 0, taken = 0, refused = 0, whispered = 0, acks = 0, relayed = 0, answered = 0, legacy = 0 }
local lastAnswer = -math.huge

local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end
local function Hash(key) return ns.Comm.Hash36(tostring(key)) end
local function ValidKey(key)
	return type(key) == "string" and #key >= 6 and #key <= 64 and not key:find("[~|%c]")
end

-- The epoch of the key we hold, or nil (none, or one taken without an epoch).
local function Epoch()
	local r = ns.rdb
	local e = r and r.keyEpoch
	if type(e) ~= "table" or type(r.realmKey) ~= "string" or r.realmKey == "" or e.key ~= Hash(r.realmKey) then return nil end
	return tonumber(e.at)
end
Keys.Epoch = Epoch
function Keys.HoldsEpoch() return Epoch() ~= nil end

-- The King's rotation (ns.rdb.keyRotation): { at, key, till, acked = { [Name-Realm] = guild }, sent = { [Name-Realm] = t }, moved, movedAt }.
local function Rotation()
	local r = ns.rdb and ns.rdb.keyRotation
	return type(r) == "table" and r or nil
end
Keys.Rotation = Rotation

-- The key this client hands its guild (K0, K5): the one it holds. (The King's new key goes to his
-- guild when he moves to it.)
function Keys.HandOut()
	local key = ns.rdb and ns.rdb.realmKey
	if not ValidKey(key) then return nil end
	return key, Epoch()
end

-- A key with its epoch, taken when newer than ours: the channel follows.
local function Take(key, at, quiet)
	local rdb = ns.rdb
	if not rdb or not ValidKey(key) then return false end
	local was = Epoch()
	if was and at <= was then return false end
	local changed = rdb.realmKey ~= key
	rdb.realmKey = key
	rdb.keyEpoch = { key = Hash(key), at = at }
	stats.taken = stats.taken + 1
	ns.Log("realm key: a key of epoch %d taken%s", at, changed and " (a new channel)" or "") -- (never the key)
	if changed then
		if not quiet then ns.Print(L.KEY_ROTATED_TAKEN) end
		ns.Comm.JoinChannel()
	end
	return true
end
Keys.Take = Take

-- To our guild (an officer): the key with its epoch, and alone for guildmates before 1.1.
local function ToGuild(key, at)
	ns.Comm.Send("GUILD", ("K3~%d~%s"):format(at, key), "key3")
	ns.Comm.Send("GUILD", "K1~" .. key, "key")
	stats.relayed = stats.relayed + 1
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

function Keys.HandleKey(dist, sender, text)
	local at, key = tostring(text):match("^K3~(%d+)~(.+)$")
	at = tonumber(at)
	if not at or not ValidKey(key) then return end
	sender = ns.FullName(sender)
	local fromKing
	if dist == "WHISPER" then
		-- The King by his pinned name: the server stamps the sender, nobody else carries it.
		if not ns.IsKingCharacter(sender) then
			stats.refused = stats.refused + 1
			return ns.Log("realm key by whisper from %s ignored: not the King", sender)
		end
		fromKing = true
	elseif dist == "GUILD" then
		-- Our own officers, by our roster (the server's word): as K1 always was.
		local rank = ns.Roster.RankOf(sender)
		if not rank or rank > ns.CAPTAIN_RANK then
			stats.refused = stats.refused + 1
			return
		end
	else
		return -- never the channel: nothing of a key is read there
	end
	if at > Clock() + Keys.DATE_AHEAD then
		stats.refused = stats.refused + 1
		return ns.Log("realm key from %s ignored: dated ahead", sender)
	end
	local took = Take(key, at)
	if fromKing then
		-- The King's client counts who has it; an officer hands it to his guild.
		ns.Comm.Whisper(sender, ("K4~%d~%s"):format(at, GetGuildInfo("player") or ""), "key4")
		if took and ns.Roster.IsOfficer() then ToGuild(key, at) end
	end
end

function Keys.HandleAck(dist, sender, text)
	if dist ~= "WHISPER" then return end
	local rot = Rotation()
	if not rot or not (ns.King and ns.King.IsKing and ns.King.IsKing()) then return end
	local at, guild = tostring(text):match("^K4~(%d+)~(.*)$")
	if tonumber(at) ~= rot.at then return end
	sender = ns.FullName(sender)
	rot.acked = type(rot.acked) == "table" and rot.acked or {}
	if rot.acked[sender] then return end
	rot.acked[sender] = ns.King.CleanGuild(guild) or "?"
	stats.acks = stats.acks + 1
	ns.King.Changed()
end

function Keys.HandleAsk(dist, sender, text)
	if dist ~= "GUILD" then return end
	local asked = tonumber(tostring(text):match("^K5~(%d+)$"))
	if not asked or not ns.Roster.IsOfficer() then return end
	local key, at = Keys.HandOut()
	if not key or not at or at <= asked then return end
	local now = ns.Now()
	if now - lastAnswer < Keys.ANSWER_GAP then return end
	lastAnswer = now
	stats.answered = stats.answered + 1
	ns.After(math.random(1, 5), "key answer", function() ns.Comm.Send("GUILD", ("K3~%d~%s"):format(at, key), "key3") end)
end

ns.Comm.Handle("K3", function(...) Keys.HandleKey(...) end)
ns.Comm.Handle("K4", function(...) Keys.HandleAck(...) end)
ns.Comm.Handle("K5", function(...) Keys.HandleAsk(...) end)

-- After login: is there a newer key than ours in the guild?
function Keys.Ask()
	if not ns.IsMember() then return end
	ns.Comm.Send("GUILD", ("K5~%d"):format(Epoch() or 0), "key5")
end

-- An officer typed /oly key (Comm.SetRealmKey): his key, dated now, for his guild's 1.1 clients too.
function Keys.Typed(key)
	if not ValidKey(key) or not ns.rdb then return end
	local at = Clock()
	local was = tonumber(ns.rdb.keyEpoch and ns.rdb.keyEpoch.at)
	if was and at <= was then at = was + 1 end
	ns.rdb.keyEpoch = { key = Hash(key), at = at }
	ns.Comm.Send("GUILD", ("K3~%d~%s"):format(at, key), "key3")
end

-- A K1 (a key without an epoch, from an officer before 1.1 or from before this version): taken
-- only while we hold no key with an epoch (Comm.lua).
function Keys.TakesLegacy(key)
	if not Keys.HoldsEpoch() or key == (ns.rdb and ns.rdb.realmKey) then return true end
	stats.legacy = stats.legacy + 1
	return false
end

---------------------------------------------------------------------------
-- The King: rotate, hand out, move
---------------------------------------------------------------------------

-- A new key from this computer (the Link's entropy sample, the clocks, the game's generator),
-- SHA-256, 20 hex digits. Nothing in the game is a cryptographic source: for a channel's
-- password it is plenty, and nobody sees it.
function Keys.NewKey()
	local parts = { tostring(ns.me), tostring(time and time()), tostring(GetTime and GetTime()), tostring(math.random()),
		tostring(math.random()), tostring({}), tostring(debugprofilestop and debugprofilestop() or 0) }
	if ns.Link and not ns.Link.missing and ns.Link.EntropySample then parts[#parts + 1] = ns.Link.EntropySample() end
	local raw = ns.Sign.SHA256(table.concat(parts, "|"))
	local hex = {}
	for i = 1, #raw do hex[i] = ("%02x"):format(raw:byte(i)) end
	return table.concat(hex):sub(1, 20)
end

-- Only the King, by his pinned character: never a Steward, a Hand or an officer.
function Keys.CanRotate()
	return ns.King ~= nil and ns.King.IsKing() and ns.KingCharacter() ~= nil and ns.IsKingCharacter(ns.me)
end

-- The Lords and Captains the census confirms online (two senders: Data.KnownRank), of every
-- guild but ours (ours gets it over GUILD when the King moves): { name, guild }.
function Keys.Targets()
	local out, mine, now = {}, GetGuildInfo("player"), ns.Now()
	for _, e in ipairs(ns.Data.Summary().guilds) do
		local g = e.g
		if e.fresh and e.name ~= mine and now - (tonumber(g.t) or 0) <= Keys.ONLINE_FRESH then
			local home = g.realm or ns.realm
			local function Add(name, online)
				if type(name) ~= "string" or not online then return end
				local full = ns.FullName(name, home)
				local rank = ns.Data.KnownRank(full, e.name)
				if rank and rank <= ns.CAPTAIN_RANK then out[#out + 1] = { name = full, guild = e.name } end
			end
			Add(g.leader, g.leaderOnline)
			for _, o in ipairs(g.officers or {}) do Add(o.name, o.online) end
		end
	end
	return out
end

-- Whispers the new key to the Lords and Captains online who have not answered (again after RESEND).
function Keys.Hand()
	local rot = Rotation()
	if not rot or rot.moved or not Keys.CanRotate() then return 0 end
	rot.acked, rot.sent = type(rot.acked) == "table" and rot.acked or {}, type(rot.sent) == "table" and rot.sent or {}
	local now, n = ns.Now(), 0
	for _, t in ipairs(Keys.Targets()) do
		if n >= Keys.MAX_WHISPERS then break end
		if not rot.acked[t.name] and now - (tonumber(rot.sent[t.name]) or -math.huge) >= Keys.RESEND then
			rot.sent[t.name] = now
			ns.Comm.Whisper(t.name, ("K3~%d~%s"):format(rot.at, rot.key), "key3:" .. t.name)
			n = n + 1
		end
	end
	stats.whispered = stats.whispered + n
	return n
end

function Keys.Rotate()
	if ns.King and ns.King.Preview and ns.King.Preview() then return ns.Print(L.THRONE_PREVIEW_NOTE) end
	if not Keys.CanRotate() then return ns.Print(L.KEY_ROTATE_ONLY_KING) end
	local rot = Rotation()
	if rot and not rot.moved then return ns.Print(L.KEY_ROTATE_BUSY) end
	local at = Clock()
	local was = Epoch()
	if was and at <= was then at = was + 1 end
	rot = { at = at, key = Keys.NewKey(), till = ns.Now() + Keys.GRACE, acked = {}, sent = {} }
	ns.rdb.keyRotation = rot
	stats.rotated = stats.rotated + 1
	ns.Log("realm key: the King rotates it (epoch %d)", at)
	Keys.Hand()
	ns.Print(L.KEY_ROTATED:format(math.ceil(Keys.GRACE / 60)))
	ns.King.Changed()
	return true
end

-- The King moves to his new key, and his guild with him (over GUILD).
function Keys.Move()
	local rot = Rotation()
	if not rot or rot.moved or not Keys.CanRotate() then return false end
	rot.moved, rot.movedAt = true, ns.Now()
	Take(rot.key, rot.at, true)
	ToGuild(rot.key, rot.at)
	ns.Print(L.KEY_ROTATION_MOVED)
	ns.King.Changed()
	return true
end

function Keys.Tick()
	local rot = Rotation()
	if not rot or rot.moved or not Keys.CanRotate() then return end
	if ns.Now() >= (tonumber(rot.till) or 0) then return Keys.Move() end
	Keys.Hand()
end

local function Counts(rot)
	local acked, guilds, sent = 0, {}, 0
	for _, g in pairs(type(rot.acked) == "table" and rot.acked or {}) do
		acked = acked + 1
		guilds[g] = true
	end
	for _ in pairs(type(rot.sent) == "table" and rot.sent or {}) do sent = sent + 1 end
	local n = 0
	for _ in pairs(guilds) do n = n + 1 end
	return sent, acked, n
end

-- On the Throne (the King's alone): rotate, and while it is handed out, how far it got.
function Keys.ThroneLines()
	local K = ns.King
	if not (K and (K.IsKing() or (K.Preview and K.Preview()))) then return {} end
	local Line, INK, TITLE = K.Line, K.INK, K.TITLE
	local lines = { Line(L.KEY_ROTATE_TITLE, TITLE) }
	local rot = Rotation()
	if rot and not rot.moved then
		local sent, acked, guilds = Counts(rot)
		lines[#lines + 1] = Line(L.KEY_ROTATING:format(sent, acked, guilds), INK, { indent = 1 })
		local left = math.max(0, math.ceil(((tonumber(rot.till) or 0) - ns.Now()) / 60))
		lines[#lines + 1] = Line("> " .. L.KEY_MOVE_NOW:format(left), INK, { indent = 1, onClick = function() ns.ShowDialog("OLYMPUS_KEY_MOVE") end })
	else
		if rot and rot.moved then
			local _, acked, guilds = Counts(rot)
			lines[#lines + 1] = Line(L.KEY_ROTATED_AGO:format(ns.Ago(rot.movedAt), acked, guilds), INK, { indent = 1 })
		end
		lines[#lines + 1] = Line("> " .. L.KEY_ROTATE, INK, { indent = 1,
			onClick = function() Keys.RotatePrompt() end,
			tooltip = function(tt)
				tt:AddLine(L.KEY_ROTATE, 1, 0.82, 0)
				tt:AddLine(L.KEY_ROTATE_TIP, 1, 1, 1, true)
			end })
	end
	lines[#lines].gapAfter = true
	return lines
end

function Keys.RotatePrompt()
	if ns.King and ns.King.Preview and ns.King.Preview() then return ns.Print(L.THRONE_PREVIEW_NOTE) end
	if not Keys.CanRotate() then return ns.Print(L.KEY_ROTATE_ONLY_KING) end
	ns.ShowDialog("OLYMPUS_KEY_ROTATE", tostring(math.ceil(Keys.GRACE / 60)))
end

StaticPopupDialogs["OLYMPUS_KEY_ROTATE"] = {
	text = L.KEY_ROTATE_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() ns.SafeCall("key rotate", Keys.Rotate) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
StaticPopupDialogs["OLYMPUS_KEY_MOVE"] = {
	text = L.KEY_MOVE_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() ns.SafeCall("key move", Keys.Move) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- /oly status: the key's state, never the key.
function Keys.StatusLine()
	local at = Epoch()
	local rot = Rotation()
	local state = rot and (rot.moved and ("rotated by the King " .. ns.Ago(rot.movedAt)) or "the King's new key being handed out") or "no rotation here"
	return ("%s  |  epoch %s  |  %s  |  taken %d, refused %d, legacy K1 ignored %d, whispered %d, acks %d, relayed %d"):format(
		ns.rdb and ns.rdb.realmKey and "sealed" or "public", at and (date and date("%Y-%m-%d %H:%M", at) or tostring(at)) or "none",
		state, stats.taken, stats.refused, stats.legacy, stats.whispered, stats.acks, stats.relayed)
end
function Keys.Stats() return stats end

ns.On("LOGIN", function()
	ns.After(Keys.ASK_AFTER, "key epoch ask", Keys.Ask)
	ns.Every(60, "key rotation", Keys.Tick)
end)

-- Tests start from a clean state.
function Keys.Reset()
	lastAnswer = -math.huge
	for k in pairs(stats) do stats[k] = 0 end
end
