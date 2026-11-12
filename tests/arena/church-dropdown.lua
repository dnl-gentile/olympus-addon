-- Church's actual filter specs and the shared renderer, with the existing client UI fixture.
local H = ...
local test, eq, ns = H.test, H.eq, H.ns
local World = assert(loadfile(H.ROOT .. "tests/church-world.lua"))(ns, H.ROOT)

local function Filters(w, c)
	-- 1.5.8: the Church opens on Invites (the author's order); its Who and When filters are Ranking's.
	if c.View.page ~= "ranking" then c.View.page = "ranking" end
	for _, line in ipairs(w:As(c, c.View.Build)) do if line.id == "church-filters" then return line.filters end end
	error("Church filter row missing")
end

test("Church dropdown: titleless menu clears the window border and selects the actual filter", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	H.WithUI(function()
		local host = CreateFrame("Frame", nil, UIParent, "DefaultPanelTemplate")
		host:SetSize(340, 420)
		local scroll = CreateFrame("ScrollFrame", nil, host)
		local row = CreateFrame("Frame", nil, scroll)
		row:SetFrameLevel(host.NineSlice:GetFrameLevel() + 1)
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		local who = row.filters[1]
		who:Click()
		local menu = who.choices
		eq(menu.TitleContainer, nil, "dropdown has no window titlebar")
		eq(menu.CloseButton, nil, "dropdown has no window close button")
		eq(menu:GetParent(), UIParent, "menu is outside ScrollFrame clipping")
		eq(menu:GetFrameStrata(), "DIALOG", "above the main window border")
		eq(menu.catcher:GetFrameStrata(), "DIALOG")
		eq(menu:GetFrameLevel() > menu.catcher:GetFrameLevel(), true)
		eq(menu:GetHeight(), 12 + #Filters(w, c)[1].options * 22, "no titlebar space")
		eq(menu.buttons[1].label:GetText(), c.c.L.CHURCH_LIST_APOSTLES)
		w:As(c, function() menu.buttons[2]:Click() end)
		eq(c.View.list, "m", "actual Church callback updates the selected list")
		eq(menu:IsShown(), false); eq(menu.catcher:IsShown(), false)
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		who:Click(); eq(who.choices, menu, "one reusable popup per filter")
		eq(menu.buttons[2].choice.selected, true)
		menu.catcher:Click(); eq(menu:IsShown(), false)
		who:Click(); row.filters[2]:Click()
		eq(menu:IsShown(), false, "opening When closes Who")
		local when = row.filters[2]
		w:As(c, function() when.choices.buttons[1]:Click() end)
		eq(c.View.window, "w", "actual Church time-window callback")
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		when:Click()
		-- (1.2.6) A redraw that changes none of its choices (a search typed elsewhere) keeps it open,
		-- its rows the redrawn page's: closing it was the dropdown vanishing under the mouse (the
		-- author's report of 10-06; tests/arena/church-dropdown.lua's next test).
		ns.Views.SetFilter("church", "apostle")
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		eq(when.choices:IsShown(), true, "a redraw keeps the open dropdown")
		eq(when.choices.catcher:IsShown(), true)
		eq(when.choices.buttons[1].choice.selected, true, "the redrawn page's choices")
		when.choices.catcher:Click()
		eq(when.choices:IsShown(), false); eq(when.choices.catcher:IsShown(), false)
		ns.Views.SetFilter("church", "")
		who:Click(); who:Hide()
		eq(menu:IsShown(), false, "hidden page/filter closes its detached menu")
	end)
end)

test("Church dropdown: understated triggers retain Who, When and their active values", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	H.WithUI(function()
		local row = CreateFrame("Frame", nil, UIParent)
		local filters = Filters(w, c)
		ns.Views.DrawFilters(row, filters, 300)
		for i, filter in ipairs(filters) do
			eq(filter.understated, true)
			local b = row.filters[i]
			eq(b.template, nil, "no raised panel-button chrome")
			assert(b.label:GetText():find(filter.label, 1, true), "caption remains visible")
			assert(b.label:GetText():find(filter.value, 1, true), "active value remains visible")
			eq(b.label.font, "GameFontNormalSmall")
			assert(b.label:GetText():find("|cff9d9d9d", 1, true), "caption is understated")
		end
	end)
end)

-- 1.2.6: the author's report of 10-06 ("ta dificil de navegar nos dropdowns eles ficam sumindo"): the
-- Church page redraws on its own (a census word, a ranking answer: UI.RefreshSoon), and every redraw
-- closed the Who or When dropdown open under the mouse. The page drawn as the window draws it
-- (ChurchView.Build, Views.SplitPageNav, Views.Render), then drawn again.
test("Church dropdown: a redraw that changes none of its choices keeps Who or When open; a page without that filter closes it", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	c.View.page = "ranking" -- (1.5.8: the Church opens on Invites; the filters are Ranking's)
	H.WithUI(function()
		local content = CreateFrame("Frame", nil, UIParent)
		content:SetWidth(300)
		local function Draw()
			local body = ns.Views.SplitPageNav((w:As(c, c.View.Build)))
			ns.Views.Render(content, body)
			for _, r in ipairs(content.rows) do
				if r:IsShown() and r.filters and r.filters[1] and r.filters[1]:IsShown() then return r end
			end
			error("Church filter row missing")
		end
		local row = Draw()
		local who = row.filters[1]
		who:Click()
		local menu = who.choices
		eq(menu:IsShown(), true)
		Draw(); Draw()
		eq(menu:IsShown(), true, "Who stays open through the page's redraws")
		eq(menu.catcher:IsShown(), true)
		eq(row.filters[1], who, "the same trigger")
		-- A choice still works, and is the page's now.
		w:As(c, function() menu.buttons[2]:Click() end)
		eq(c.View.list, "m"); eq(menu:IsShown(), false)
		-- When, open while the window changes elsewhere: its lit choice follows the redraw.
		row = Draw()
		local when = row.filters[2]
		when:Click()
		c.View.window = "a"
		Draw()
		eq(when.choices:IsShown(), true, "When stays open")
		eq(when.choices.buttons[3].choice.selected, true, "its lit choice redrawn")
		eq(when.choices.buttons[2].choice.selected, false)
		-- The correspondents' list has no When: that page closes the menu left open.
		c.View.list = "c"
		Draw()
		eq(when:IsShown(), false)
		eq(when.choices:IsShown(), false, "no stale menu on a page without its filter")
		eq(when.choices.catcher:IsShown(), false)
	end)
end)

-- 1.5.8 (the author's test, 11-12: the announcement reminder's menu opened far from its words, at the
-- row's right edge): a text-like picker's menu opens under its words, and goes when its picker does.
test("Church dropdown (1.5.8): a text-like picker's menu opens under its words and closes with it", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	H.WithUI(function()
		local host = CreateFrame("Frame", nil, UIParent, "DefaultPanelTemplate")
		host:SetSize(340, 420)
		local scroll = CreateFrame("ScrollFrame", nil, host)
		local row = CreateFrame("Frame", nil, scroll)
		ns.Views.DrawFilters(row, Filters(w, c), 300)
		local when = row.filters[2] -- (the rightmost picker, understated)
		when:Click()
		local menu = when.choices
		local point, relativeTo, relativePoint = menu:GetPoint(1)
		eq(point, "TOPLEFT", "under its words, not at the row's right edge")
		eq(relativeTo, when); eq(relativePoint, "BOTTOMLEFT")
		local update = assert(menu:GetScript("OnUpdate"), "it watches its picker")
		update(menu, 0.1)
		eq(menu:IsShown(), true, "still open while the picker stays")
		when:Hide()
		update(menu, 0.1)
		eq(menu:IsShown(), false, "gone once its picker is gone")
	end)
end)
