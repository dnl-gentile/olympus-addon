local ADDON, ns = ...

-- Loaded first (before the libraries), so that:
-- 1. errors raised while the rest of the addon loads are still captured (Diagnostics
--    stores them once the SavedVariables are ready), and
-- 2. the world map exists before HereBeDragons-Pins hooks into it. On some clients
--    (Classic Era) Blizzard_WorldMap is load-on-demand and the library breaks without it.

ns.earlyErrors = {}

-- Every error seen this session (any addon or Blizzard file), deduplicated. Kept in the
-- SavedVariables so we can see errors our own frames cause inside Blizzard code.
ns.allErrors = {}
local index = {}

local previous = geterrorhandler()
seterrorhandler(function(err, ...)
	local ok = pcall(function()
		local msg = tostring(err)
		local key = msg:sub(1, 240)
		local e = index[key]
		if e then
			e.count = e.count + 1
		elseif #ns.allErrors < 40 then
			e = { msg = msg, count = 1, stack = debugstack and debugstack(3, 10, 0) or "", t = date and date("%H:%M:%S") }
			index[key] = e
			ns.allErrors[#ns.allErrors + 1] = e
		end
		if msg:find("AddOns[\\/]Olympus[\\/]") then
			if ns.CaptureError and ns.db then
				ns.CaptureError("global", msg)
			elseif #ns.earlyErrors < 20 then
				ns.earlyErrors[#ns.earlyErrors + 1] = { msg, debugstack and debugstack(3, 10, 0) or "" }
			end
		end
	end)
	return previous(err, ...)
end)

if not WorldMapFrame then
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if load then pcall(load, "Blizzard_WorldMap") end
end
