-- Current human policy: accepted appointments survive offline/reload; current roster/root proof
-- still controls duties. Legates are manual, including the King's guild, 25 plus six correspondents.
local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]nominees%-durable%.lua$") or "./"
local function World(fn)
	local savedGuild, dialogs = GetGuildInfo, {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local w = { now = 1800000000, guild = "Olympus II", rank = 3, prints = {}, packets = {}, quiet = false }
	local c = setmetatable({ me = "Adept-Realm", realm = "Realm", group = "RealmGroup", faction = "Alliance", db = {}, rdb = {} }, { __index = ns })
	local ok, err = pcall(function()
		GetGuildInfo = function() return w.guild, "Member", w.rank end
		c.Now = function() return w.now end
		c.FullName = function(name, realm) return name and (name:find("-", 1, true) and name or name .. "-" .. (realm or "Realm")) end
		c.ShortName = function(name) return name and name:match("^[^-]+") end
		c.RealmOf = function(name) return name and name:match("%-([^%-]+)$") end
		c.IsMember = function() return c.IsFederation(w.guild) end
		c.IsKingGuild, c.KingGuildName = function(g) return g == "Olympus" end, function() return "Olympus" end
		c.KingCharacter = function() return "Pinned King-Realm" end
		c.IsKingCharacter = function(name) return c.FullName(name) == c.KingCharacter() end
		c.IsHighCouncillor = function(name) return w.council and c.FullName(name) == "Councilor-Realm" or false end
		c.King = { IsKing = function() return c.IsKingCharacter(c.me) and w.guild == "Olympus" and w.rank == 0 end, Preview = function() return false end }
		c.Workshop, c.ViewAs = { Visible = function() return false end }, { Is = function() return false end, Previewing = function() return false end }
		c.Print = function(line) w.prints[#w.prints + 1] = line end
		c.Log, c.Fire, c.On, c.After = function() end, function() end, function() end, function() end
		c.ChatLocked, c.Quiet = function() return false end, function() return w.quiet end
		c.Data = { KnownRank = function() return nil end, Guild = function() return nil end }
		c.Comm = { Handle = function() end, Send = function(dist, msg) w.packets[#w.packets + 1] = { dist = dist, msg = msg } end }
		c.Roster = { guild = w.guild, group = c.group, faction = c.faction, complete = true, generation = 1, snapshotAt = w.now,
			byName = { [c.me] = 3, ["Guildmaster-Realm"] = 0, ["Peer-Realm"] = 3 }, lastStats = { leader = "Guildmaster" } }
		c.Roster.RankOf = function(name) return c.Roster.byName[c.FullName(name)] end
		c.Roster.Fresh = function()
			local R = c.Roster
			return R.complete and R.guild == w.guild and R.group == c.group and R.faction == c.faction
				and w.now >= R.snapshotAt and w.now - R.snapshotAt <= 600 and R or nil
		end
		function w.reload() assert(loadfile(ROOT .. "Olympus/Nominees.lua"))("Olympus", c) end
		function w.take(guild, sender, rev, body)
			c.Nominees.Handle("CHANNEL", sender, ("NM~1~%s~%d~1~1~%s"):format(guild, rev, body))
		end
		w.reload(); fn(w, c)
	end)
	GetGuildInfo = savedGuild
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = nil end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	if not ok then error(err, 0) end
end

test("nominees retention: accepted own appointments survive 366 offline days and reload, but current roster authority and explicit revocation remain mandatory", function()
	World(function(w, c)
		w.take(w.guild, "Guildmaster-Realm", w.now, "c=Peer;d=Department of War=Adept")
		local stamp = c.rdb.nomineesHeard["olympus ii"].at
		w.now = w.now + 366 * 86400; c.Roster.snapshotAt = w.now
		eq(c.Nominees.RoleOf("Peer", w.guild), "centurion", "offline age is not removal")
		eq(c.Nominees.Prune(), false); w.reload()
		eq(c.Nominees.RoleOf("Peer", w.guild), "centurion", "restored old accepted record")
		eq(c.rdb.nomineesHeard["olympus ii"].at, stamp, "no forged freshness timestamp")
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, "Department of War"), true)
		c.Roster.complete = false
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, "Department of War"), false)
		c.Roster.complete = true; c.Roster.snapshotAt = w.now - 601
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, "Department of War"), false)
		c.Roster.snapshotAt = w.now; c.Roster.byName["Guildmaster-Realm"] = 1
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, "Department of War"), false, "old accepted list never bypasses current GM proof")
		c.Roster.byName["Guildmaster-Realm"] = 0
		w.take(w.guild, "Guildmaster-Realm", w.now, "c=Peer;d=Department of War=Adept")
		w.take(w.guild, "Peer-Realm", w.now + 1, "")
		eq(c.Nominees.RoleOf("Peer", w.guild), "centurion", "unprivileged fake removal is refused")
		w.take(w.guild, "Guildmaster-Realm", w.now + 2, "")
		eq(c.Nominees.RoleOf("Peer", w.guild), nil); w.reload()
		eq(c.Nominees.RoleOf("Peer", w.guild), nil, "valid removal remains removed after reload")
	end)
end)

test("nominees retention: duty notice is local and once for an actual continuous Legate appointment, not heartbeats, unrelated edits or reload; removal re-arms it", function()
	World(function(w, c)
		local function Count(needle)
			local n = 0; for _, line in ipairs(w.prints) do if line:find(needle or c.L.NOMINEES_LEGATE_DUTY, 1, true) then n = n + 1 end end
			return n
		end
		w.take(w.guild, "Peer-Realm", w.now, "c=Adept")
		eq(c.db.legateNotices, nil, "spoofed appointment has no notice or saved stamp")
		w.quiet = true
		w.take(w.guild, "Guildmaster-Realm", w.now, "c=Adept")
		eq(c.db.legateNotices, nil, "quiet context does not spend the notice")
		w.quiet = false
		-- An appointment already acknowledged by the old policy is told exactly once about the High
		-- Council's new badge/frame rule; it is not treated as a new appointment.
		c.db.legateNotices = { [c.me:lower()] = { guild = w.guild, role = "centurion", active = true, rev = w.now } }
		eq(c.Nominees.AppointmentNotice(c.Nominees.ListOf(w.guild)), true)
		local first = c.db.legateNotices[c.me:lower()].rev
		eq(Count(), 1); eq(Count(c.L.NOMINEES_BADGE_DECISION), 1, "the decision and replacement are explained")
		eq(c.db.legateNotices[c.me:lower()].rule, c.Nominees.NOTICE_RULE)
		eq(#w.packets, 0, "no peer message or native invitation")
		w.take(w.guild, "Guildmaster-Realm", w.now, "c=Adept")
		w.take(w.guild, "Guildmaster-Realm", w.now + 1, "c=Adept;c=Peer")
		eq(Count(), 1, "another nominee's revision is not our new appointment")
		eq(c.db.legateNotices[c.me:lower()].rev, first)
		w.reload(); c.Nominees.Minute(); eq(Count(), 1, "reload does not retell the duty")
		w.take(w.guild, "Guildmaster-Realm", w.now + 2, "c=Peer")
		eq(c.db.legateNotices[c.me:lower()].active, false)
		w.take(w.guild, "Guildmaster-Realm", w.now + 3, "c=Adept;c=Peer")
		eq(Count(), 2, "an actual reappointment explains the duty again")
		eq(c.db.legateNotices[c.me:lower()].rev, w.now + 3)
	end)
end)

test("nominees retention: a correspondent receives the one-time department badge notice, including an office change", function()
	World(function(w, c)
		local function Count()
			local n = 0; for _, line in ipairs(w.prints) do if line:find(c.L.NOMINEES_CORRESPONDENT_DUTY, 1, true) then n = n + 1 end end
			return n
		end
		w.take(w.guild, "Guildmaster-Realm", w.now, "d=Department of War=Adept")
		eq(Count(), 1)
		local badge = false; for _, line in ipairs(w.prints) do if line:find(c.L.NOMINEES_BADGE_DECISION, 1, true) then badge = true end end
		assert(badge, "the correspondent's notice includes the badge decision")
		w.take(w.guild, "Guildmaster-Realm", w.now + 1, "d=Department of War=Adept;c=Peer")
		eq(Count(), 1, "an unrelated appointment does not repeat it")
		w.take(w.guild, "Guildmaster-Realm", w.now + 2, "d=Federal Treasury=Adept;c=Peer")
		eq(Count(), 2, "a real department change explains the new badge")
	end)
end)

test("nominees retention: main c wire is explicit manual data, never an automatic council seat; empty revocation cannot be resurrected by an older peer", function()
	World(function(w, c)
		w.guild, c.Roster.guild = "Olympus", "Olympus"
		w.council = true; c.rdb.council = { names = { ["councilor"] = true } }
		eq(c.Nominees.RoleOf("Councilor", w.guild), nil, "a council seat is not an appointment")
		w.take(w.guild, "Peer-Realm", w.now, "c=Peer")
		eq(c.Nominees.RoleOf("Peer", w.guild), nil, "no ordinary-guild authority over main appointments")
		w.take(w.guild, "Pinned King-Realm", w.now, "c=Peer")
		eq(c.Nominees.RoleOf("Peer", w.guild), "centurion", "authenticated manual compatibility wire")
		w.take(w.guild, "Pinned King-Realm", w.now + 1, "")
		w.now = w.now + 366 * 86400; c.Roster.snapshotAt = w.now; w.reload()
		w.take(w.guild, "Pinned King-Realm", w.now - 366 * 86400, "c=Peer")
		eq(c.Nominees.RoleOf("Peer", w.guild), nil, "retained empty tombstone rejects the old main revision")
		w.take(w.guild, "Councilor-Realm", w.now, "c=Peer")
		eq(c.Nominees.RoleOf("Peer", w.guild), "centurion", "a real council root may appoint manually")
		w.council = false
		eq(c.Nominees.RoleOf("Peer", w.guild), nil, "current root revocation stops derived authority immediately")
	end)
end)

test("nominees retention: actual presentation preview predicates cannot print, spend or persist a Legate appointment notice", function()
	World(function(w, c)
		w.quiet = true; w.take(w.guild, "Guildmaster-Realm", w.now, "c=Adept"); w.quiet = false
		local l = c.Nominees.ListOf(w.guild)
		local printed = #w.prints
		c.ViewAs.Previewing = function() return true end
		eq(c.Nominees.AppointmentNotice(l), false); eq(c.db.legateNotices, nil)
		c.ViewAs.Previewing = function() return false end
		c.ViewAs.Available, c.ViewAs.Role = function() return true end, function() return "gm" end
		eq(c.Nominees.AppointmentNotice(l), false); eq(c.db.legateNotices, nil)
		c.ViewAs.Available = function() return false end
		c.King.Preview = function() return true end
		eq(c.Nominees.AppointmentNotice(l), false); eq(c.db.legateNotices, nil)
		eq(#w.prints, printed, "a preview cannot falsely tell the player he was appointed")
	end)
end)

test("nominees retention: 25 long-name Legates plus six correspondents fit bounded native parts and reload; overflow and malformed timestamps are refused", function()
	World(function(w, c)
		local N, entries = c.Nominees, {}
		for i = 1, 25 do entries[#entries + 1] = { role = "centurion", name = "Legate" .. string.char(64 + i) .. " Longsurname-Farawayrealm" } end
		for i, dept in ipairs(N.Departments()) do entries[#entries + 1] = { role = "correspondent", dept = dept, name = "Envoy" .. string.char(64 + i) .. " Longsurname-Farawayrealm" } end
		local parts = N.Parts(w.guild, w.now, entries)
		assert(#parts > 1 and #parts <= N.MAX_PARTS)
		for i = #parts, 1, -1 do
			assert(#parts[i] <= N.PART)
			N.Handle("CHANNEL", "Guildmaster-Realm", parts[i])
		end
		eq(#N.ListOf(w.guild).entries, 31); w.reload(); N = c.Nominees
		eq(#N.ListOf(w.guild).entries, 31); eq(N.MAX_LEGATES, 25)
		c.rdb.nomineesHeard["olympus forged"] = { g = "Olympus Forged", by = "Fake-Realm", rev = math.huge, at = w.now, body = "c=Peer" }
		w.reload(); eq(c.Nominees.ListOf("Olympus Forged"), nil, "non-finite saved revision cannot monopolize retention")
		eq(#c.Nominees.Parts(w.guild, math.huge, entries), 0)
		-- Even an oversized legacy save cannot turn indefinite age retention into unbounded cache.
		for i = 1, c.Nominees.SAVED_MAX + 5 do
			local guild = "Olympus G" .. i
			c.rdb.nomineesHeard[guild:lower()] = { g = guild, by = "Guildmaster-Realm", rev = 1, at = w.now - i, body = "c=Peer" }
		end
		w.reload(); assert(c.Nominees.ListOf(w.guild), "our own guild survives the cap")
		local count = 0; for _ in pairs(c.rdb.nomineesHeard) do count = count + 1 end
		eq(count, c.Nominees.SAVED_MAX)
		eq(c.Nominees.ListOf("Olympus G305"), nil, "eviction bounds memory as well as saved snapshots")
	end)
end)
