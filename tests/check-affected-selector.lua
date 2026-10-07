-- Pure selector selftests: these validate dependency policy, not addon test coverage.
local M = assert(loadfile("scripts/check-affected.lua"))("library")
local function Has(plan, name)
	for _, module in ipairs(plan.modules) do if module == name then return true end end
	return false
end
for _, path in ipairs({ "Olympus/Core.lua", "Olympus/FarkleTable.lua", "Olympus/Olympus.toc",
	"tests/run.lua", "tests/gamepad.lua", "tests/arena/lib/world.lua", "tests/fixtures/forever-api.lua",
	"scripts/check.sh", "Olympus/GamepadRegistry.lua", "Olympus_Arena/LotteryBoard.lua",
	"Olympus_Arena/BonesChat.lua", "Olympus_Arena/Locales/BonesChatText.lua",
	"Olympus/ChatWindow.lua", "Olympus/ArenaChat.lua",
	"unknown.lua", "../Olympus/Watch.lua" }) do
	assert(M.Select({ path }).full, "unknown/core changes must never narrow coverage: " .. path)
end
assert(M.Select({}).full)
for _, path in ipairs({ "", "/Olympus/Watch.lua", "Olympus\\Watch.lua", "Olympus/Watch.lua\n",
	"Olympus/Watch.lua\r", "Olympus/../Olympus/Watch.lua", false }) do
	assert(M.Select({ path }).full, "malformed evidence must fall back FULL")
end
assert(M.Select(false).full, "non-list evidence must fall back FULL")
local bones = M.Select({ "Olympus/InnkeeperArrow.lua", "Olympus/ArenaPlaces.lua" })
assert(not bones.full and Has(bones, "farkle-table.lua") and Has(bones, "places.lua") and Has(bones, "match.lua"))
-- Inspect the actual top-level test inventory, not another copy of the selector's list.
-- New family regressions must be retained before any mapped UI/game change can narrow checks.
local inventory = assert(io.popen("ls -1 tests/arena")) -- same inventory mechanism as tests/run.lua
local family = {}
for entry in inventory:lines() do
	local name = entry:match("^([^/]+%.lua)$")
	if name and (name:match("^bones%-") or name:match("^farkle%-") or name == "ArenaFarkle.lua"
		or name == "house-move-regression.lua" or name == "rehearsal-consent.lua") then
		family[#family + 1] = name
	end
end
assert(inventory:close(), "cannot enumerate the real family inventory")
assert(#family > 0, "empty family inventory must not validate a selector")
for _, path in ipairs({ "Olympus/InnkeeperArrow.lua", "Olympus/ArenaPlaces.lua",
	"Olympus_Arena/FarkleBoard.lua", "Olympus_Arena/Games/Farkle.lua",
	"Olympus_Arena/Locales/FarkleText.lua", "tests/innkeeper-arrow.lua" }) do
	local plan = M.Select({ path })
	assert(not plan.full, "known Bones input retains its complete dependency group: " .. path)
	for _, name in ipairs(family) do
		assert(Has(plan, name), path .. " omits a real family regression: " .. name)
	end
end
for _, name in ipairs(family) do
	local plan = M.Select({ "tests/arena/" .. name })
	assert(not plan.full, "family test changes retain their whole dependency group: " .. name)
	for _, sibling in ipairs(family) do assert(Has(plan, sibling), name .. " omits sibling " .. sibling) end
	assert(Has(plan, "net.lua") and Has(plan, "compliance.lua"), "shared protocol coverage retained")
end
assert(not Has(bones, "lottery-controller.lua"), "unrelated day simulations are omitted")
local watch = M.Select({ "Olympus/Watch.lua", "Olympus/WatchChat.lua", "Olympus/ViewAs.lua" })
assert(not watch.full and Has(watch, "compliance.lua") and Has(watch, "craft-requests.lua") and Has(watch, "net.lua"))
assert(not M.Select({ "tests/innkeeper-arrow.lua", "tests/watch-council-view.lua" }).full)
local both = M.Select({ "Olympus/ArenaPlaces.lua", "Olympus/Watch.lua" })
for _, plan in ipairs({ bones, watch }) do for _, module in ipairs(plan.modules) do assert(Has(both, module)) end end
for i = 2, #both.modules do assert(both.modules[i - 1] < both.modules[i], "sorted, unique union") end
assert(M.Select({ "Olympus/Watch.lua", "Olympus/Core.lua" }).full, "one unknown overrides every narrow mapping")
assert(Has(M.Select({ "tests/arena/net.lua" }), "farkle-table.lua"), "shared mapped fixtures retain both groups")
assert(Has(M.Select({ "tests/arena/net.lua" }), "role-chat-audiences.lua"), "shared mapped fixtures also retain Watch integration")
print("Affected selector policy: passed (no addon test bodies executed)")
