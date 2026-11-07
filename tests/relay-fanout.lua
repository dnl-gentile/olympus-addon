-- GitHub #76: a relay's snapshot in pieces must reach every registered reporter whole, without
-- pushing out the single words waiting beside it (a verifier's approval).
local ns, test, eq, extra = ...

test("relay fan-out (#76): with 46 guilds registered, the relay's own snapshot in pieces reaches every reporter whole, and a verifier's approval sent with it reaches every reporter too", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, fn) timers[#timers + 1] = fn end
		for i = 1, 46 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- An 8-piece global census snapshot, handed in as Relay.Out's own path does, then an approval.
		local snapshot = "CG~2~S~1~ForeverPvE~Alliance~" .. ("Olympus Dawn,640,40,300,1;"):rep(66)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "77")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		local approval = "GV~1~A~1794011276~Olympus Dawn~Some Master-CAMWOWUS2Realm7PvE"
		R.Relay.HandleIn("WHISPER", R.me, "RL~L~" .. approval)
		for _ = 1, 2000 do
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end

		-- Each reporter puts back together what it was sent: the RM envelopes, then the snapshot.
		local whole, approved, fewest = 0, 0, 0
		-- The snapshot wrapped once for a reporter, cut into full whispers: the fewest it can take.
		local least = math.ceil(#("RM~P~" .. R.me .. "~" .. snapshot) / R.Codec.CHUNK)
		for i = 1, 46 do
			local outer, inner, prefix = R.Codec.NewAssembler(), R.Codec.NewAssembler(), ("Rep Number%d-"):format(i)
			local got, ok, whispers = false, false, 0
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					if s.msg:sub(1, 3) ~= "RM~" then whispers = whispers + 1 end
					if body == approval then ok = true
					elseif body and (body == snapshot or R.Codec.Feed(inner, "origin", body, 0) == snapshot) then got = true end
				end
			end
			if got then whole = whole + 1 end
			if ok then approved = approved + 1 end
			if whispers == least then fewest = fewest + 1 end
		end
		eq(whole, 46, "every reporter can put the whole snapshot together")
		eq(approved, 46, "the snapshot's batches never push the approval out of the queue")
		eq(fewest, 46, ("each reporter gets the snapshot in %d full whispers, not a piece and its label apart"):format(least))
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)
