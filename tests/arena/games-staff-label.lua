local H = ...
local test, eq, World = H.test, H.eq, H.World

for _, choice in ipairs({ { "enUS", "Games (staff)" }, { "ptBR", "Jogos (equipe)" } }) do
	local locale, label = choice[1], choice[2]
	test("Games staff label: actual " .. locale .. " staff heading names games without advertising bets", function()
		local w = World.New({ compliance = "shipped" })
		local king = w:Role("king")
		local member = w:Client(World.NAMES.fighterA)
		for _, client in ipairs({ king, member }) do
			client.globals.GetLocale = function() return locale end
			w:As(client, function()
				-- Load the actual locale into this client's real namespace, then render the
				-- same staff heading that the Games tab consumes; no authorization stand-in.
				assert(loadfile(H.ADDON_DIR .. "Locales/ArenaHomeText.lua"))("Olympus", client.ns)
				local staff = client == king
				eq(client.ns.ArenaHome.GamesStaff(), staff)
				local found = 0
				for _, row in ipairs(client.ns.ArenaHome.TabLines()) do
					if row.header and row.text == client.ns.L.ARENA_GAMES_STAFF then
						found = found + 1
						eq(row.text, label, "the visible Games staff heading uses the requested label")
					end
				end
				eq(found, staff and 1 or 0, "renaming the heading does not widen staff visibility")
				for kind in pairs(client.ns.Compliance.KINDS) do
					for game in pairs(client.ns.Compliance.GAMES) do
						eq(client.ns.Compliance.Allows(kind, game), false, "the shipped wager gate remains closed")
					end
				end
			end)
			eq(#client.errors, 0, table.concat(client.errors, "; "))
		end
	end)
end
