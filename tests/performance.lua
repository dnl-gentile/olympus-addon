-- Case-boundary diagnostics: never select, skip, or alter a test body.
local Performance = {}

function Performance.New(options)
	options = options or {}
	local self = {
		profile = options.profile, gcMB = options.gcMB or 0,
		output = options.output or io.stdout, clock = options.clock or os.clock,
		wall = options.wall or os.time, memory = options.memory or collectgarbage,
	}
	function self:Write(message)
		self.output:write(message .. "\n")
		self.output:flush()
	end
	function self:Start(name)
		if not self.profile then return end
		local state = { name = name, cpu = self.clock(), wall = self.wall(), kb = self.memory("count") }
		self:Write(("  BEGIN %.1f MiB %s"):format(state.kb / 1024, name))
		return state
	end
	function self:Finish(state)
		if not state and self.gcMB <= 0 then return end
		local kb = self.memory("count")
		if state then
			self:Write(("  END cpu=%.3fs wall=%ds heap=%.1f MiB delta=%+.1f MiB %s")
				:format(self.clock() - state.cpu, self.wall() - state.wall, kb / 1024, (kb - state.kb) / 1024, state.name))
		end
		if self.gcMB > 0 and kb > self.gcMB * 1024 then
			local started = self.clock()
			self.memory("collect")
			if self.profile then
				self:Write(("  GC cpu=%.3fs heap=%.1f -> %.1f MiB"):format(self.clock() - started, kb / 1024, self.memory("count") / 1024))
			end
		end
	end
	return self
end

return Performance
