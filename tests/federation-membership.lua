local ns, test, eq = ...
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]federation%-membership%.lua$") or "./"
local load = assert(loadfile(root .. "Olympus/FederationMembership.lua"))
local ALPHA, BETA = "Olympus Alpha", "Olympus Beta"
local REALM = "CAMWOWUS1Realm1PvE"
local function Name(short) return short .. "-" .. REALM end
local VIEWER, SUBJECT, STRANGER = Name("Black Cypress"), Name("Blue Pine"), Name("Grey Oak")
local FIRST, OTHER = Name("Red Pearl"), Name("Green Moss")

local function World()
	local w = { now = 1800000000, rev = 70, queue = {}, people = {}, holds = {} }
	local members = { [ALPHA] = { [VIEWER] = 4, [FIRST] = 0 }, [BETA] = { [SUBJECT] = 5, [OTHER] = 0 } }
	local keepers = { [ALPHA] = FIRST, [BETA] = OTHER }
	w.members = members
	local function Client(name, guild)
		local c = { me = name, group = "ForeverPvE", faction = "Alliance", realm = REALM, events = {} }
		c.IsMember = function() return not c.consentWithdrawn end
		c.QuietPresence = function() return c.quiet end
		c.ChatLocked = function() return c.locked end
		c.Fold, c.IsSecret = ns.Fold, function() return false end
		c.InGroup = function(realm) return ns.ForeverFamily(realm) == c.group end
		c.Data = { ServerTime = function() return w.now end, NetOff = function(g) return w.holds[g] end }
		c.Roster = {
			Fresh = function()
				return not c.stale and { guild = guild, serverAt = c.rosterAt or w.now } or nil
			end,
			RankOf = function(who) return members[guild][who] end,
		}
		c.FederationProgram = {
			EnrollmentRevision = function() return w.rev end,
			Role = function(who, g) return keepers[g] == who and "caretaker" or nil end,
			LocalEnrollment = function() return members[guild][name] and guild or nil end,
			IsEnrolled = function(g) return keepers[g] ~= nil end,
			Roleholders = function(g) return keepers[g] end,
			Caretakers = function() return keepers end,
		}
		c.SafeCall = function(_, fn, ...) return fn(...) end
		c.After = function() end
		c.On = function(event, callback) c.events[event] = callback end
		c.RegisterEvent = c.On
		c.Comm = {
			Handle = function() end,
			Whisper = function(peer, word, _, _, logged, _, options)
				eq(logged, false, "witnesses are private addon whispers")
				w.queue[#w.queue + 1] = { sender = name, peer = peer, word = word, guard = options.guard }
				return true
			end,
		}
		load("Olympus", c)
		w.people[name] = c
		return c.FederationMembership, c
	end
	w.viewer, w.viewerClient = Client(VIEWER, ALPHA)
	w.first, w.firstClient = Client(FIRST, ALPHA)
	w.other, w.otherClient = Client(OTHER, BETA)
	function w.Deliver()
		local packet = table.remove(w.queue, 1)
		if not packet or not packet.guard() then return false end
		local recipient = w.people[packet.peer]
		return recipient and recipient.FederationMembership.Receive("WHISPER", packet.sender, packet.word) or false
	end
	return w
end

test("federation membership witness: regular member uses a bound direct query and only then replays the deferred action", function()
	local w, replayed = World(), 0
	eq(w.viewer.Allowed(SUBJECT, BETA), false)
	eq(w.viewer.Request(SUBJECT, BETA, function() replayed = replayed + 1 end), true)
	eq(w.queue[1].peer, FIRST)
	eq(w.Deliver(), true)
	eq(w.queue[1].peer, OTHER)
	eq(w.Deliver(), true)
	local reply = w.queue[1]
	eq(reply.peer, VIEWER)
	eq(w.viewer.Receive("CHANNEL", reply.sender, reply.word), false, "a channel replay cannot attest")
	eq(w.viewer.Receive("WHISPER", STRANGER, reply.word), false, "only the expected exact caretaker can attest")
	eq(w.viewer.Receive("WHISPER", OTHER, reply.word:gsub("Blue Pine", "Grey Oak")), false, "the other character is not the requested subject")
	eq(replayed, 0)
	eq(w.Deliver(), true)
	eq(w.viewer.Allowed(SUBJECT, BETA), true)
	eq(w.viewer.Allowed(SUBJECT), true, "a later private craft response may reuse the witnessed guild")
	eq(w.viewer.Allowed(SUBJECT, ALPHA), false)
	eq(replayed, 1)
	eq(w.viewer.Receive("WHISPER", OTHER, reply.word), false, "nonce is one use")
	w.now = w.now + 90
	eq(w.viewer.Allowed(SUBJECT, BETA), false, "proof expires on the roster's server clock")
end)

test("federation membership witness: roster, consent, quiet and policy changes block queued witnesses", function()
	local w = World()
	eq(w.viewer.Request(SUBJECT, BETA), true)
	w.members[ALPHA][VIEWER] = nil
	eq(w.Deliver(), false, "the viewing client lost native enrollment before send")
	w = World()
	eq(w.viewer.Request(SUBJECT, BETA), true)
	eq(w.Deliver(), true)
	w.otherClient.stale = true
	eq(w.Deliver(), false, "the answering caretaker has no fresh roster")
	w = World()
	eq(w.viewer.Request(SUBJECT, BETA), true)
	eq(w.Deliver(), true)
	eq(w.Deliver(), true)
	w.members[BETA][SUBJECT] = nil
	eq(w.Deliver(), false, "the subject left the roster while the reply was queued")
	eq(w.viewer.Allowed(SUBJECT, BETA), false)
	w = World()
	eq(w.viewer.Request(SUBJECT, BETA), true)
	eq(w.Deliver(), true)
	eq(w.Deliver(), true)
	w.rev = w.rev + 1
	eq(w.Deliver(), false, "any new signed program revision invalidates pending witnesses")
	eq(w.viewer.Allowed(SUBJECT, BETA), false)
	w = World()
	w.viewerClient.quiet = true
	eq(w.viewer.Request(SUBJECT, BETA), false)
	w.viewerClient.quiet, w.viewerClient.consentWithdrawn = false, true
	eq(w.viewer.Request(SUBJECT, BETA), false)
	eq(#w.queue, 0)
	w = World()
	eq(w.viewer.Request(SUBJECT, BETA), true)
	eq(w.Deliver(), true)
	eq(w.Deliver(), true)
	w.viewerClient.events.QUIET_PRESENCE_CHANGED(true)
	eq(w.Deliver(), false, "privacy mode cancels deferred traffic even if the player already resumed")
	eq(w.viewer.Allowed(SUBJECT, BETA), false)
end)

test("federation membership witness: a local stranger cannot use the caretaker as a proxy", function()
	local w = World()
	local query = ("FM~Q~%d~ab-01~%s~%s"):format(w.rev, BETA, SUBJECT)
	eq(w.first.Receive("WHISPER", STRANGER, query), false)
	local forged = ("FM~V~%d~ab-01~%s~%s"):format(w.rev, VIEWER, SUBJECT)
	eq(w.other.Receive("WHISPER", STRANGER, forged), false)
	eq(#w.queue, 0)
end)
