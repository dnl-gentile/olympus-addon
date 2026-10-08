-- Contextual warnings in Olympus's own recruit-invite flow. Native guild invitations remain
-- the officer's choice; these tests drive the real moderation records, request rows and dialog.
local ns, test, eq, H = ...
local R, M = ns.Recruit, ns.Moderation
local WHICH = "OLYMPUS_RECRUIT_NETOFF"
local WHO = "New Recruit-Realm"

local function Scene(fn)
	H.WithUI(function()
		H.WithNetoff(function(w)
			local saved = { can = CanGuildInvite, guild = GetGuildInfo, invite = C_GuildInfo, oldInvite = GuildInvite,
				decline = DeclineGuild, uninvite = GuildUninvite, ignore = C_FriendList, blocked = ns.db.blocked }
			local ok, err = pcall(function()
				H.AsSoldier("Officer")
				R.ResetForTests()
				ns.Dialog.Reset()
				w.invites, w.sideEffects = {}, 0
				w.canInvite, w.guild = true, "Olympus II"
				CanGuildInvite = function() return w.canInvite end
				GetGuildInfo = function() return w.guild end
				C_GuildInfo = { Invite = function(name) w.invites[#w.invites + 1] = name end }
				GuildInvite = nil
				local function Unexpected() w.sideEffects = w.sideEffects + 1 end
				DeclineGuild, GuildUninvite = Unexpected, Unexpected
				C_FriendList = { AddIgnore = Unexpected, DelIgnore = Unexpected }
				ns.db.blocked = { [WHO] = true }
				local blocked, king = ns.db.blocked, ns.KingCharacter()
				fn(w)
				eq(w.sideEffects, 0, "no guild refusal, removal or native ignore-list change")
				eq(ns.db.blocked, blocked, "the personal block list stays local and untouched")
				eq(ns.db.blocked[WHO], true)
				eq(ns.KingCharacter(), king, "the pinned King is unchanged")
			end)
			ns.Dialog.Reset()
			R.ResetForTests()
			CanGuildInvite, GetGuildInfo, C_GuildInfo, GuildInvite = saved.can, saved.guild, saved.invite, saved.oldInvite
			DeclineGuild, GuildUninvite, C_FriendList, ns.db.blocked = saved.decline, saved.uninvite, saved.ignore, saved.blocked
			if not ok then error(err, 0) end
		end)
	end)
end

local function Word(w, name, off, reason, kind)
	M.Handle("CHANNEL", H.HC, ("O1~%s~%d~%d~%s~%s~%s"):format(kind or "c", off and 1 or 0,
		w.clock, name, H.HC, reason or ""))
end
local function Request(name)
	eq(R.OnJoinRequest("WHISPER", name or WHO, "J3~Olympus II~12~MAGE"), true)
	return R.requests[#R.requests]
end
local function InviteRow()
	for _, line in ipairs(R.RequestLines()) do
		if line.text == ns.Views.Green(ns.L.JOIN_INVITE:format("Olympus II")) then return line end
	end
	error("the officer's invite row is missing")
end
local function Warning() return assert(ns.Dialog.Find(WHICH), "the contextual warning") end

test("Recruit net-off warning: reason and timestamp precede the invitation; keep or invite is a manual choice", function()
	for _, gamepad in ipairs({ false, true }) do
		Scene(function(w)
			H.WithGamepadUI(gamepad, function(game)
				Word(w, WHO, true, "Repeated recruitment spam")
				local mark = assert(M.Hidden(WHO))
				local req = Request()
				local sent, whispered = #w.sent, #w.whispered
				InviteRow().onClick()
				eq(#w.invites, 0, "no native invite before the officer answers")
				local f = Warning()
				assert(f.text:GetText():find("Repeated recruitment spam", 1, true), "the reason shown")
				assert(f.text:GetText():find(M.When(mark), 1, true), "the timestamp shown")
				eq(f.buttons[1]:GetText(), ns.L.JOIN_NETOFF_INVITE)
				eq(f.buttons[2]:GetText(), ns.L.JOIN_NETOFF_CANCEL)
				f.buttons[2]:Click()
				eq(#w.invites, 0); eq(R.requests[1], req, "keeping the request rejects nobody")
				InviteRow().onClick()
				Warning().buttons[1]:Click()
				eq(#w.invites, 1); eq(w.invites[1], "New Recruit")
				eq(#R.requests, 0, "only the explicit invite completes the request")
				eq(#w.sent, sent); eq(#w.whispered, whispered, "no moderation action or whisper")
				eq(#game.shown, 0, "the warning uses an Olympus window in both input modes")
				eq(#w.popups, 0, "no native popup")
			end)
		end)
	end
end)

test("Recruit net-off warning: a changed moderation record requires a new decision", function()
	Scene(function(w)
		Word(w, WHO, true, "First reason")
		Request()
		InviteRow().onClick()
		w.clock = w.clock + 1
		Word(w, WHO, true, "Updated reason")
		Warning().buttons[1]:Click()
		eq(#w.invites, 0, "an old confirmation cannot approve a newer word")
		local f = Warning()
		assert(f.text:GetText():find("Updated reason", 1, true), "the new context shown")
		f.buttons[1]:Click()
		eq(#w.invites, 1)
	end)
end)

test("Recruit net-off warning: permission, guild, request expiry, dismissal and missing API are rechecked", function()
	for _, change in ipairs({ "permission", "guild", "expiry", "dismiss", "api", "target" }) do
		Scene(function(w)
			Word(w, WHO, true, "Review before inviting")
			local req = Request()
			InviteRow().onClick()
			local f = Warning()
			if change == "permission" then w.canInvite = false
			elseif change == "guild" then w.guild = "Olympus Zeus"
			elseif change == "expiry" then w.clock = w.clock + R.REQUEST_TTL + 1
			elseif change == "dismiss" then R.Dismiss(req)
			elseif change == "api" then C_GuildInfo = nil
			elseif change == "target" then req.name = "Other Recruit-Realm" end
			f.buttons[1]:Click()
			eq(#w.invites, 0, change .. " prevents a stale invitation")
		end)
	end
end)

test("Recruit net-off warning: clear, guild-only, revoked and pinned-King records do not warn; personal blocks stay local", function()
	for _, context in ipairs({ "clear", "guild", "revoked", "king" }) do
		Scene(function(w)
			local who = context == "king" and H.KING or WHO
			if context == "guild" then Word(w, "Olympus Zeus", true, "Guild removed", "g")
			elseif context == "revoked" then
				Word(w, who, true, "Old reason")
				w.clock = w.clock + 1
				Word(w, who, false)
			elseif context == "king" then Word(w, who, true, "Invalid King word") end
			local req = Request(who)
			eq(R.Accept(req), true, context .. " uses the normal manual invite")
			eq(#w.invites, 1); eq(ns.Dialog.Find(WHICH), nil)
		end)
	end
end)

test("Recruit net-off warning: its text is localized with matching format arguments", function()
	local pt = H.PtBR()
	for _, key in ipairs({ "JOIN_NETOFF_PROMPT", "JOIN_NETOFF_INVITE", "JOIN_NETOFF_CANCEL" }) do
		local en, br = rawget(ns.L, key), rawget(pt, key)
		assert(type(en) == "string" and en ~= "", "English " .. key)
		assert(type(br) == "string" and br ~= "" and br ~= en, "pt-BR " .. key)
		local function Codes(s) local out = {} for c in s:gmatch("%%[sd]") do out[#out + 1] = c end return table.concat(out) end
		eq(Codes(br), Codes(en), key)
	end
end)
