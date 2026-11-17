-- 1.5.4 relay fixes. An integration's profile presentation (FX) names its guild and goes to that
-- guild's reporter alone (its 10-second heartbeat to every reporter was most of what a relay sent),
-- while the issuer's grant and close, which every guild needs, still reach every reporter (below);
-- and a reporter's registration (RR) is bounded (below).
local ns, test, eq, extra = ...

test("relay fan-out (1.5.4): the relay's own profile presentation goes to the reporter of the guild it names alone; any other word of its own still reaches every reporter", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, fn) timers[#timers + 1] = fn end
		for i = 1, 10 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		R.Relay.HandleIn("WHISPER", "Dawn Keeper-CAMWOWUS2Realm7PvE", "RL~P~RR~Olympus Dawn")
		-- A presenter's heartbeat (FX~2~S~style~session~sequence~time~guild~issuer~grant id~caption),
		-- then another word. (Until the review of the 1.5.4 candidate this case used a grant, G, which
		-- now goes to every reporter once a minute: a member of any guild presents only under a grant
		-- he holds. The presenter's own S is what stays with the guild it names; the grant's own test
		-- is below.)
		local presentation = "FX~2~S~s~123~1~1794011276~Olympus Dawn~Max Ran-CAMWOWUS2Realm1PvE~42~a caption"
		local other = "ZZ~1~a word of the relay's own"
		R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. presentation)
		R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. other)
		for _ = 1, 200 do
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end
		local function Reached(word)
			local who = {}
			for _, s in ipairs(sent) do
				local body = s.target and s.msg:match("^RM~[LP]~[^~]+~(.*)$")
				if body == word then who[ns.ShortName(s.target)] = true end
			end
			local names = {}
			for name in pairs(who) do names[#names + 1] = name end
			table.sort(names)
			return names
		end
		local got = Reached(presentation)
		eq(#got, 1, "one reporter receives the presentation")
		eq(got[1], "Dawn Keeper", "the reporter of the guild it names")
		eq(#Reached(other), 11, "any other word of the relay's own still reaches every reporter")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

-- A relay with eleven guilds' reporters registered (Olympus Dawn's is Dawn Keeper): Hand gives it a
-- word heard from `sender` and drains its queue; Reached names the reporters a word went to.
local function GrantWorld(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, f) timers[#timers + 1] = f end
		local function Register()
			for i = 1, 10 do
				R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
			end
			R.Relay.HandleIn("WHISPER", "Dawn Keeper-CAMWOWUS2Realm7PvE", "RL~P~RR~Olympus Dawn")
		end
		Register()
		local function Hand(sender, word)
			R.Relay.HandleIn("WHISPER", sender, "RL~P~" .. word)
			for _ = 1, 200 do
				R.Comm.Pump()
				local due = timers; timers = {}
				for _, f in ipairs(due) do f() end
			end
		end
		-- (And, third, the reporters' short names, sorted and joined by commas.)
		local function Reached(word)
			local n, dawn, names = 0, false, {}
			for _, s in ipairs(sent) do
				if s.target and s.msg:match("^RM~[LP]~[^~]+~(.*)$") == word then
					n = n + 1
					names[#names + 1] = ns.ShortName(s.target)
					if ns.ShortName(s.target) == "Dawn Keeper" then dawn = true end
				end
			end
			table.sort(names)
			return n, dawn, table.concat(names, ",")
		end
		fn(R, Hand, Reached, Register)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end

test("federation relay: shared payloads go to enrolled guild reporters while census traffic stays general", function()
	GrantWorld(function(R, Hand, Reached)
		local active = true
		R.SharedToolsActive = function() return active end
		R.SharedGuildAllowed = function(guild) return not active or guild == "Olympus Dawn" end
		local craft, other = "W1~Olympus Dawn~crafting profile", "ZZ~1~non-federation word"
		Hand(R.me, craft)
		local n, _, names = Reached(craft)
		eq(n, 1); eq(names, "Dawn Keeper")
		Hand(R.me, other)
		eq(Reached(other), 11)
		active = false
		local legacy = "W1~Olympus Dawn~legacy crafting profile"
		Hand(R.me, legacy)
		eq(Reached(legacy), 11, "legacy program state has the old fan-out")
	end)
end)

-- The review of the 1.5.4 candidate: a grant (G) and a close (C) name the issuer's own guild, so the
-- scoping above kept them from every other guild, whose members could then never present. Fails
-- before: every grant and the close reached Dawn Keeper alone.
test("relay fan-out (1.5.4): the issuer's grant reaches every reporter on its first beat, the guild it names alone on a beat within GRANT_EVERY, every reporter again after it; another origin's grant is its own; a close reaches every reporter at once", function()
	GrantWorld(function(R, Hand, Reached)
		local t0 = R.clock
		-- The relay's own client issues the grant (its issuer beats every 10 s).
		local function Grant(seq) return ("FX~2~G~s~123~%d~%d~Olympus Dawn~42"):format(seq, 1794011276 + seq) end
		Hand(R.me, Grant(1))
		local n, dawn = Reached(Grant(1))
		eq(n, 11, "the first beat reaches every reporter"); eq(dawn, true)
		R.clock = t0 + 10
		Hand(R.me, Grant(2))
		n, dawn = Reached(Grant(2))
		eq(n, 1, "a beat within GRANT_EVERY: the guild it names alone"); eq(dawn, true, "its reporter")
		R.clock = t0 + R.Relay.GRANT_EVERY - 1
		Hand(R.me, Grant(3))
		eq((Reached(Grant(3))), 1, "still within GRANT_EVERY")
		-- Another issuer's grant (one of the signed relays', heard by whisper) is counted apart.
		local other = "FX~2~G~s~555~1~1794011300~Olympus Dawn~7"
		Hand("Max Ran-CAMWOWUS2Realm7PvE", other)
		eq((Reached(other)), 11, "another origin's first beat reaches every reporter")
		R.clock = t0 + R.Relay.GRANT_EVERY
		Hand(R.me, Grant(4))
		eq((Reached(Grant(4))), 11, "GRANT_EVERY after the last: every reporter again")
		R.clock = t0 + R.Relay.GRANT_EVERY + 5
		local close = "FX~2~C~s~123~5~1794011341~Olympus Dawn~42"
		Hand(R.me, close)
		n, dawn = Reached(close)
		eq(n, 11, "a close reaches every reporter at once"); eq(dawn, true)
	end)
end)

-- The review of the 1.5.4 candidate, mixed versions: a 1.5.3 client keeps a heard grant 32 s
-- (ProfileEffects.SESSION_TTL), so with the grant once each GRANT_EVERY a 1.5.3 presenter outside the
-- issuer's guild lost his presentation at his next heartbeat, and the 1.5.3 viewers in his guild saw
-- the effect come and go every minute. A guild whose member presents hears the grant each beat while
-- he does. Fails before (the beat after his heartbeat reaches Dawn Keeper alone).
test("relay fan-out (1.5.4): a guild whose member presents under the grant hears it each beat, for PRESENTING_FOR after his last heartbeat; a guild where nobody presents once each GRANT_EVERY; a guild with no reporter is not noted; Relay.Reset forgets", function()
	GrantWorld(function(R, Hand, Reached, Register)
		local t0, every, held = R.clock, R.Relay.GRANT_EVERY, R.Relay.PRESENTING_FOR
		local function Grant(seq) return ("FX~2~G~s~123~%d~%d~Olympus Dawn~42"):format(seq, 1794011276 + seq) end
		local function Names(word) return (select(3, Reached(word))) end
		Hand(R.me, Grant(1))
		eq((Reached(Grant(1))), 11, "the first beat reaches every reporter")
		-- A member of Guild 3 presents under the grant, beating every 10 s (FX~ver~S~style~session~seq~
		-- at~guild~issuer~grant~caption); a member of a guild with no reporter here too.
		local function Beat(seq, guild) return ("FX~2~S~s~777~%d~%d~%s~%s~42~a caption"):format(seq, 1794011280 + seq, guild, R.me) end
		R.clock = t0 + 5
		Hand("Some Member-CAMWOWUS2Realm3PvE", Beat(1, "Guild 3"))
		eq(Names(Beat(1, "Guild 3")), "Rep Number3", "his presentation stays with his guild")
		Hand("Lone Member-CAMWOWUS2Realm3PvE", Beat(1, "Guild 99"))
		eq((Reached(Beat(1, "Guild 99"))), 0, "a guild with no reporter here: nobody")
		R.clock = t0 + 10
		Hand(R.me, Grant(2))
		eq(Names(Grant(2)), "Dawn Keeper,Rep Number3", "the beat after his heartbeat: the issuer's guild and the presenter's")
		R.clock = t0 + 15
		Hand("Some Member-CAMWOWUS2Realm3PvE", Beat(2, "Guild 3"))
		R.clock = t0 + 20
		Hand(R.me, Grant(3))
		eq(Names(Grant(3)), "Dawn Keeper,Rep Number3", "and the next")
		R.clock = t0 + every
		Hand(R.me, Grant(4))
		eq((Reached(Grant(4))), 11, "GRANT_EVERY after the first: every reporter again")
		-- His last heartbeat was at t0 + 15: his guild hears the grant for PRESENTING_FOR after it.
		R.clock = t0 + 15 + held - 1
		Hand(R.me, Grant(5))
		eq(Names(Grant(5)), "Dawn Keeper,Rep Number3", "within PRESENTING_FOR of his last heartbeat")
		R.clock = t0 + 15 + held
		Hand(R.me, Grant(6))
		eq(Names(Grant(6)), "Dawn Keeper", "past it: the issuer's guild alone again")
		-- Relay.Reset forgets who presents.
		R.clock = t0 + 100
		Hand("Some Member-CAMWOWUS2Realm3PvE", Beat(3, "Guild 3"))
		R.Relay.Reset()
		Register()
		Hand(R.me, Grant(7))
		eq((Reached(Grant(7))), 11, "after Relay.Reset: every reporter at once")
		R.clock = t0 + 105
		Hand(R.me, Grant(8))
		eq(Names(Grant(8)), "Dawn Keeper", "and the presenter's guild is forgotten")
	end)
end)

-- The origins a relay remembers a grant for are bounded (stale ones out, then the oldest: an origin
-- left out early only has its next grant reach everyone again) and Relay.Reset wipes them.
test("relay fan-out (1.5.4): the origins remembered for the grant's GRANT_EVERY are bounded, the oldest left out first, and Relay.Reset wipes them", function()
	GrantWorld(function(R, Hand, Reached, Register)
		local cap, t0 = R.Relay.GRANT_ORIGINS, R.clock
		local ok, err = pcall(function()
			R.Relay.GRANT_ORIGINS = 2
			local function Grant(id, seq) return ("FX~2~G~s~%d~%d~%d~Olympus Dawn~%d"):format(id, seq, 1794011276 + seq, id) end
			Hand(R.me, Grant(1, 1))
			eq((Reached(Grant(1, 1))), 11)
			R.clock = t0 + 5
			Hand("Max Ran-CAMWOWUS2Realm7PvE", Grant(2, 1))
			eq((Reached(Grant(2, 1))), 11)
			R.clock = t0 + 10
			Hand(R.me, Grant(1, 2))
			eq((Reached(Grant(1, 2))), 1, "two origins held: the relay's own next beat stays with its guild")
			R.clock = t0 + 15
			Hand("Third Issuer-CAMWOWUS2Realm7PvE", Grant(3, 1))
			eq((Reached(Grant(3, 1))), 11, "a third origin's first beat reaches every reporter")
			R.clock = t0 + 20
			Hand(R.me, Grant(1, 3))
			eq((Reached(Grant(1, 3))), 11, "the oldest origin was left out to keep two: its next beat reaches every reporter again")
			R.Relay.GRANT_ORIGINS = cap
			R.clock = t0 + 25
			Hand(R.me, Grant(1, 4))
			eq((Reached(Grant(1, 4))), 1, "kept again since: within GRANT_EVERY the guild alone")
			R.Relay.Reset()
			Register()
			R.clock = t0 + 30
			Hand(R.me, Grant(1, 5))
			eq((Reached(Grant(1, 5))), 11, "after Relay.Reset: every reporter at once")
		end)
		R.Relay.GRANT_ORIGINS = cap
		if not ok then error(err, 0) end
	end)
end)

-- 1.5.4 (a player's security report of 1.5.3): a relay took any whisperer as any number of guilds'
-- reporter, with names of any length; one character could take every guild's feed. Fails before.
test("relay registration (1.5.4): one guild per reporter, a guild name as the game allows it, and a bounded number of guilds", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local function Count() return R.Relay.Stats().reporters end
		R.Relay.HandleIn("WHISPER", "Grab Ber-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild One")
		eq(Count(), 1)
		R.Relay.HandleIn("WHISPER", "Grab Ber-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild Two")
		eq(Count(), 1, "a reporter's new guild leaves his old one")
		R.Relay.HandleIn("WHISPER", "Long Name-CAMWOWUS2Realm7PvE", "RL~P~RR~" .. ("x"):rep(R.Relay.MAX_GUILD_NAME + 1))
		eq(Count(), 1, "a guild name longer than the game allows is refused")
		R.Relay.HandleIn("WHISPER", "Long Name-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild Ünïcode Ésprit")
		eq(Count(), 2, "an accented name within the bytes is kept")
		local cap = R.Relay.MAX_REPORTERS
		R.Relay.MAX_REPORTERS = 3
		for i = 1, 4 do R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i)) end
		eq(Count(), 3, "no more guilds than the cap")
		R.Relay.HandleIn("WHISPER", "Rep Number1-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild 1")
		eq(Count(), 3, "a known guild's reporter still registers again at the cap")
		R.Relay.MAX_REPORTERS = cap
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)
