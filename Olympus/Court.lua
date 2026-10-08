local ADDON, ns = ...
local L = ns.L

-- Hold Court: the King opens his court where he stands. Every Olympus member with the addon
-- in that zone gets a line on top of the Census and the Realm: one click asks him for an
-- audience. The requests line up in The Watch's Judgment section; a click on one calls that
-- player, who gets a popup and a raid warning. His alone (not a Hand's), off until he opens it.
--   T1~C~<id>~<guild>~<zone mapID>~<zone name>   court open here (resent every 2 minutes)
--   T1~Z~<id>~<guild>                            court closed
--   T4~<id>~<guild>                              an audience asked (whisper to the King)
--   T5~<id>                                      called (whisper from the King)
--   T5~<id>~<server time>~<one line>               optional message, alongside the legacy call

local Court = {}
ns.Court = Court

Court.RESEND = 120      -- the King's client repeats it for late logins and zone changes
Court.EXPIRE = 330      -- a court not repeated this long is over (he logged off)
Court.MAX = 50          -- requests kept per court
Court.CALL_GAP = 10     -- one call every 10 seconds per subject at most
Court.ASK_AGAIN = 180   -- not called this long (the court was full, the King busy): ask again
Court.DISMISSED = 300   -- sent off: no new request from them this long
Court.CALL_OPEN = 120   -- a call's popup stays this long (and waits no longer in an instance, 1.1)
Court.NOTE_MAX = 160    -- bytes; the optional line is a private whisper, never a channel post

local holding           -- the King's court: { id, mapID, zone, sentAt, queue = { { name, guild, t, calledAt } }, by = { [name] = entry }, dismissed = { [name] = t } }
local court             -- the court seen: { id, king, mapID, zone, t, askedAt, calledAt }

-- The zone the player is in, as a zone map (a city or a zone, not a building or a floor),
-- with its name: the same for every client, whatever its language.
function Court.Here()
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local guard = 0
	while mapID and C_Map.GetMapInfo and guard < 5 do
		local info = C_Map.GetMapInfo(mapID)
		if not info or not info.mapType or info.mapType <= 3 or not info.parentMapID or info.parentMapID == 0 then break end
		mapID, guard = info.parentMapID, guard + 1
	end
	local name = (GetRealZoneText and GetRealZoneText()) or ""
	return mapID, name
end

local function Clean(s, n) return ns.Cut((tostring(s or ""):gsub("[~|%c]", " ")), n) end
local function CleanNote(s)
	return Clean(s, Court.NOTE_MAX):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end
local function ServerNow() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end

---------------------------------------------------------------------------
-- The King
---------------------------------------------------------------------------

function Court.Holding() return holding end

local function Send()
	if not holding or holding.preview then return end
	holding.sentAt = ns.Now()
	ns.Comm.Send("CHANNEL", ("T1~C~%d~%s~%d~%s"):format(holding.id, GetGuildInfo("player") or "", holding.mapID or 0,
		Clean(holding.zone, 40)), "court")
end

function Court.Toggle()
	local preview = ns.King.Preview()
	if not ns.King.IsKing() and not preview then return ns.Print(L.THRONE_ONLY_KING) end
	if holding then
		if not holding.preview then ns.Comm.Send("CHANNEL", ("T1~Z~%d~%s"):format(holding.id, GetGuildInfo("player") or ""), "court") end
		holding = nil
		ns.Print(L.COURT_CLOSED)
	else
		local mapID, zone = Court.Here()
		holding = { id = ns.King.NewId(), mapID = mapID, zone = zone, queue = {}, by = {}, dismissed = {}, preview = preview or nil }
		if preview then ns.Print(L.THRONE_PREVIEW_NOTE) end
		Send()
		ns.Print(L.COURT_OPENED:format(zone ~= "" and zone or "?"))
	end
	ns.Fire("COURT_CHANGED")
end

-- Where he stands now: the court moves with him (a new zone, a new line for its players).
local function Moved()
	if not holding then return end
	local mapID, zone = Court.Here()
	if mapID == holding.mapID and zone == holding.zone then return end
	holding.mapID, holding.zone = mapID, zone
	Send()
	ns.King.Changed()
	ns.Fire("COURT_CHANGED")
end

-- A request (T4), or one made on the King's own client (the preview, tests). What the
-- requester says of their guild shows only when we can place them (our roster, a Lord or
-- Captain the census confirms): anyone else is a name alone on the King's screen.
function Court.Request(sender, id, guild)
	if not holding or holding.id ~= id then return end
	sender = ns.FullName(sender)
	-- 1.1: a name the moderators took off (net-off, Moderation.lua) is not queued.
	if ns.Moderation.Hides and ns.Moderation.Hides(sender, guild) then return end
	local name, clean = ns.King.CleanName(sender), ns.King.CleanGuild(guild)
	if not name or not clean or holding.by[sender] or #holding.queue >= Court.MAX then return end
	local now = ns.Now()
	if now - (holding.dismissed[sender] or -math.huge) < Court.DISMISSED then return end
	local shown
	if ns.Roster.RankOf(sender) then shown = GetGuildInfo("player")
	elseif ns.King.Verified(sender, clean) then shown = clean end
	local entry = { name = sender, guild = shown, t = now }
	holding.queue[#holding.queue + 1] = entry
	holding.by[sender] = entry
	-- In chat: the first few, then every tenth (a crowded city asks all at once).
	local n = #holding.queue
	if n <= 5 or n % 10 == 0 then
		local who = shown and ("%s <%s>"):format(ns.DisplayName(sender), shown) or ns.DisplayName(sender)
		ns.Print(L.COURT_REQUEST:format(who) .. (n > 5 and ("  (" .. n .. ")") or ""))
	end
	ns.PlayAlert("soft", "court")
	ns.King.Changed()
	ns.Fire("COURT_CHANGED")
end

function Court.HandleRequest(dist, sender, text)
	if dist ~= "WHISPER" or not ns.King.IsKing() then return end
	local id, guild = text:match("^T4~(%d+)~(.*)$")
	Court.Request(sender, tonumber(id), guild)
end
ns.Comm.Handle("T4", function(...) Court.HandleRequest(...) end)

-- A click on a request: that player is called; a second click, once called, sends them off.
function Court.Call(name, words)
	if not holding or (not holding.preview and not ns.King.IsKing()) then return end
	local entry = holding and holding.by[name]
	if not entry then return end
	local now = ns.Now()
	if entry.calledAt then
		if now - entry.calledAt < Court.CALL_GAP then return end
		for i, e in ipairs(holding.queue) do
			if e == entry then table.remove(holding.queue, i) break end
		end
		holding.by[name] = nil
		holding.dismissed[name] = now
		ns.King.Changed()
		ns.Fire("COURT_CHANGED")
		return
	end
	entry.calledAt = now
	if not holding.preview then
		-- Older clients still get their exact call; the optional note has its own queue key.
		ns.Comm.Whisper(name, ("T5~%d"):format(holding.id), "court call " .. name)
		words = CleanNote(words)
		if words ~= "" then
			ns.Comm.Whisper(name, ("T5~%d~%d~%s"):format(holding.id, ServerNow(), words), "court note " .. name)
		end
	end
	ns.Print(L.COURT_CALLING:format(ns.DisplayName(name)))
	ns.King.Changed()
	ns.Fire("COURT_CHANGED")
end

function Court.Prompt(name)
	local e = holding and holding.by[name]
	if not e or e.calledAt or (not holding.preview and not ns.King.IsKing()) then return end
	return ns.ShowDialog("OLYMPUS_COURT_NOTE", ns.DisplayName(name), nil, { name = name, court = holding })
end

function Court.Confirm(data, words)
	if type(data) ~= "table" or data.answered or data.court ~= holding then return end
	if not holding or (not holding.preview and not ns.King.IsKing()) then return end
	local e = holding.by[data.name]
	if not e or e.calledAt then return end
	data.answered = true
	return Court.Call(data.name, words)
end

StaticPopupDialogs["OLYMPUS_COURT_NOTE"] = {
	text = L.COURT_NOTE_PROMPT, button1 = L.COURT_NOTE_SEND, button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 260, maxLetters = Court.NOTE_MAX, maxBytes = Court.NOTE_MAX + 1,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("court note", Court.Confirm, data or self.data, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("court note", Court.Confirm, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Everyone else
---------------------------------------------------------------------------

local function OnCourt(sender, id, rest, guild)
	if ns.FullName(sender) == ns.me then return end
	local mapID, zone = rest:match("^(%d+)~(.*)$")
	mapID = tonumber(mapID)
	if not mapID then return end
	local fresh = not court or court.id ~= id
	court = fresh and { id = id } or court
	court.king, court.mapID, court.zone, court.t = ns.FullName(sender), mapID, Clean(zone, 40), ns.Now()
	court.guild = guild
	-- News to whoever is there, once per court (and again when he comes to our zone).
	if Court.InMyZone() and court.toldIn ~= mapID then
		court.toldIn = mapID
		ns.Print(L.COURT_HERE:format(ns.KingName(sender), court.zone))
		-- (Busy, 1.1: no chime; once back, the court is named in the line of what waited.)
		local seen = court
		ns.Alert("court", "soft", { what = L.HELD_COURT:format(court.zone), key = "court" .. tostring(id),
			open = function() return Court.Current() == seen end })
	end
	ns.Fire("COURT_CHANGED")
end

local function OnClosed(sender, id)
	if not court or court.king ~= ns.FullName(sender) then return end
	court = nil
	ns.Fire("COURT_CHANGED")
end

ns.King.Register("C", OnCourt)
ns.King.Register("Z", OnClosed)

-- The court seen, while it lasts.
function Court.Current()
	if court and ns.Now() - court.t > Court.EXPIRE then court = nil end
	return court
end

function Court.InMyZone()
	local c = Court.Current()
	if not c then return false end
	local mapID = Court.Here()
	return mapID ~= nil and mapID == c.mapID
end

-- Asked and not called for a while (a full court, a busy King): the line offers to ask again.
local function CanAsk(c) return not c.calledAt and (not c.askedAt or ns.Now() - c.askedAt >= Court.ASK_AGAIN) end

function Court.Seek()
	local c = Court.Current()
	if not c or not Court.InMyZone() then return end
	if not CanAsk(c) then return ns.Print(L.COURT_ASKED_ALREADY) end
	c.askedAt = ns.Now()
	ns.Comm.Whisper(c.king, ("T4~%d~%s"):format(c.id, GetGuildInfo("player") or ""), "court ask")
	ns.Print(L.COURT_ASKED:format(ns.KingName(c.king)))
	ns.Fire("COURT_CHANGED")
end

StaticPopupDialogs["OLYMPUS_COURT_CALLED"] = {
	text = L.COURT_CALLED_POPUP,
	button1 = OKAY or "OK",
	timeout = Court.CALL_OPEN,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Court.HandleCall(dist, sender, text)
	if dist ~= "WHISPER" then return end
	local c = Court.Current()
	local id, at, words = text:match("^T5~(%d+)~(%d+)~([^~]*)$")
	if id then
		at = tonumber(at)
		local now = ServerNow()
		if not at or at > now or now - at > Court.CALL_OPEN or #words > Court.NOTE_MAX then return end
		words = CleanNote(words)
		if words == "" then return end
	else id = text:match("^T5~(%d+)$") end
	id = tonumber(id)
	-- Only the court's King calls; asked in an earlier session (a /reload) counts too.
	if not c or c.id ~= id or c.king ~= ns.FullName(sender) or not ns.King.Authorized("C", sender, c.guild) then return end
	if words and not c.noteAt then
		c.noteAt = at
		if ns.Chronicle and ns.Chronicle.Add then
			local wrote = ns.Chronicle.Add("court", sender, L.COURT_NOTE_TO:format(ns.DisplayName(ns.me)), {
				words = words, to = ns.me, id = table.concat({ sender, tostring(id), tostring(at), ns.me }, ":"),
			})
			if wrote then
				local entries = ns.Chronicle.Entries()
				ns.Print(ns.Chronicle.Line(entries[#entries])) -- the same word filter as the retained record
			end
		end
		ns.Fire("COURT_CHANGED")
	end
	if c.calledAt then return end
	c.calledAt = ns.Now()
	c.askedAt = c.askedAt or c.calledAt
	-- In an instance or on Busy (1.1): the chat line now, the raid warning and the popup once the
	-- player is out, if the call is still open then (the popup's two minutes).
	local king, zone = ns.KingName(sender), c.zone
	ns.King.Warn(L.COURT_CALLED:format(king, zone), true, "court", {
		what = L.HELD_COURT_CALL:format(king), key = "courtcall" .. tostring(id),
		open = function() return ns.Now() - c.calledAt < Court.CALL_OPEN end,
		show = function() ns.ShowDialog("OLYMPUS_COURT_CALLED", king, zone) end,
	})
	ns.Fire("COURT_CHANGED")
end
ns.Comm.Handle("T5", function(...) Court.HandleCall(...) end)

-- The current character's retained royal messages; their authors are the server's senders.
-- These are ordinary local Chronicle records, never relayed, and cleared with /oly log clear.
function Court.Messages()
	local out = {}
	for _, e in ipairs(ns.Chronicle and ns.Chronicle.Entries() or {}) do
		if e.kind == "court" and e.to == ns.me then out[#out + 1] = e end
	end
	return out
end

-- The line on top of the Census and the Realm, for the players in the court's zone.
function Court.Line()
	local c = Court.Current()
	if not c or not Court.InMyZone() or ns.King.IsKing() then return nil end
	local state
	local ask = CanAsk(c)
	if c.calledAt then state = "|cff40ff40" .. L.COURT_STATE_CALLED .. "|r"
	elseif not ask then state = "|cff9d9d9d" .. L.COURT_STATE_ASKED .. "|r"
	else state = "|cffffd200" .. L.COURT_STATE_ASK .. "|r" end
	return {
		header = true,
		text = "|T" .. ns.CROWN_ICON .. ":0|t " .. L.COURT_LINE:format(ns.KingName(c.king), c.zone),
		right = state,
		onClick = ask and function() Court.Seek() end or nil,
		tooltip = function(tt)
			tt:AddLine(L.COURT_LINE:format(ns.KingName(c.king), c.zone), 1, 0.82, 0)
			tt:AddLine(L.COURT_TIP, 1, 1, 1, true)
		end,
		gapAfter = true,
	}
end

---------------------------------------------------------------------------
-- The court inside The Watch (the King's), while it is open: the queue, a click calls
---------------------------------------------------------------------------

function Court.HomeLines()
	if not holding then return {} end
	local Line, INK, TITLE = ns.King.Line, ns.King.INK, ns.King.TITLE
	local lines = { Line(L.COURT_TITLE, TITLE) }
	lines[#lines + 1] = Line(L.COURT_OPEN_IN:format(holding.zone ~= "" and holding.zone or "?"), INK)
	lines[#lines + 1] = Line(L.COURT_WAITING:format(#holding.queue), TITLE)
	if #holding.queue == 0 then lines[#lines + 1] = Line(L.COURT_NOBODY, INK, { indent = 1 }) end
	for _, e in ipairs(holding.queue) do
		lines[#lines + 1] = Line(e.guild and ("%s <%s>"):format(ns.DisplayName(e.name), e.guild) or ns.DisplayName(e.name), INK, {
			indent = 1, key = e.name,
			right = e.calledAt and L.COURT_STATE_CALLED or ns.Ago(e.t),
			onClick = function() Court.Call(e.name) end,
			tooltip = function(tt)
				tt:AddLine(ns.DisplayName(e.name), 1, 0.82, 0)
				tt:AddLine(e.calledAt and L.COURT_TIP_DONE or L.COURT_TIP_CALL, 1, 1, 1, true)
			end,
		})
		if not e.calledAt then
			lines[#lines + 1] = Line(L.COURT_NOTE_CALL, INK, { indent = 2, onClick = function() Court.Prompt(e.name) end })
		end
	end
	return lines
end

ns.On("LOGIN", function()
	ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() ns.SafeCall("court moved", Moved) end)
	ns.Every(30, "court", function()
		if holding and ns.Now() - (holding.sentAt or 0) >= Court.RESEND then Send() end
		-- The line comes and goes with the zone we are in, and the court with its King.
		local c = court
		if c and (ns.Now() - c.t > Court.EXPIRE) then
			court = nil
			ns.Fire("COURT_CHANGED")
		end
	end)
end)

-- Tests start from a clean state.
function Court.Reset() holding, court = nil, nil end
