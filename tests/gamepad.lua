-- The gamepad pass (1.1.5): whole sessions of the addon with Blizzard's gamepad UI simulated, from a
-- gamepad login and across switches both ways, failing when anything of Olympus's reaches the
-- game's UI there. No controller needed: run with the offline suite (tests/run.lua loads it), or
-- alone (luajit tests/gamepad.lua).
--
-- How. Every addon file loads, in its TOC's order, into a sandbox of its own (setfenv): the client
-- model below. Its globals are only what Forever's client has (tests/fixtures/forever-api.lua,
-- made by scripts/forever-api.lua from the client's own UI source): a global the client has that
-- the model doesn't fails as "unmodelled", one it lacks reads as nil, as in the game. The game's
-- frames are strict objects whose every method call from Olympus's code is recorded, as is every
-- call of a function the gamepad audit (scripts/gamepad-audit.lua) counts as a reach: that record
-- is the ledger. Each record carries the gp: tag of the line that made it, so it says which
-- registry entry (Olympus/GamepadRegistry.lua) it belongs to; with the gamepad UI on, only
-- entries allowed there ("own", "exempt", "click" inside a click) may appear in it.
--
-- Mock fidelity (the model may not offer what the client lacks; each part cites what it follows):
--   1. One switch: C_InputInterfaceStyle.GetCurrentStyle and Enum.InputDeviceInterfaceType from
--      the fixture's documentation values; a switch sets the style first, then sends
--      INPUT_DEVICE_INTERFACE_TRANSITION(newMode, oldMode) at once (InputDocumentation.lua, a
--      synchronous event). No test replaces ns.GamepadUI or ns.Gate (tests/run.lua checks it).
--   2. Registrations keep their callbacks (Menu.ModifyMenu, TooltipDataProcessor.AddTooltipPostCall,
--      hooksecurefunc, HookScript, ChatFrameUtil.AddSenderNameFilter), and the model calls them
--      the way the game does.
--   3. A slash command is called directly by the chat box, which then closes itself
--      (Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua:269-273): with the gamepad UI on, any
--      Olympus code run that way is a taint event, a failure.
--   4. A restricted function (the fixture's restricted list, from the documentation's
--      HasRestrictions and IsProtectedFunction) called outside a click on a button is refused, and
--      the model sends ADDON_ACTION_BLOCKED as the client does.
--   5. Strict: an unknown global or a method the client's widget type lacks is an error; a getter
--      the client has that the model doesn't return yet is "unmodelled".
--   6. Timers run: C_Timer.After and tickers queue, and the pass advances the clock.
--   7. Smart Navigation: visible Button/EditBox widgets, explicitly focusable frames and frames
--      with mouse handlers under a managed panel are candidates. Mouse-handler reads cross the
--      securecallfunction boundary; ignored containers exclude themselves, not their children
--      (Blizzard_GamepadSmartNavigation/Utility.lua:263-333, build 70790).
--   8. Popups and the chat box: StaticPopup_Show shows one of StaticPopup1..4 (Blizzard_StaticPopup),
--      the chat box's functions set the last active edit box.
--   9. The map library is the real one (Olympus/libs), on a model of the world map.
-- A mock that differs from Forever's code is a bug in the model, not a reason to change an
-- assertion.
--
-- Alone: luajit tests/gamepad.lua. For work on the model: "--names" lists what it offers (read by
-- scripts/forever-api.lua), "--discover [gamepad]" logs in and lists what it lacks instead of
-- failing, "--debug" returns its parts to a script.

local H = ...
local MODE = type(H) == "string" and H or nil
if type(H) ~= "table" then H = nil end
local ROOT = H and H.ROOT or ((arg and arg[0] or ""):match("^(.*)tests[/\\]gamepad%.lua$") or "./")
local ADDON_DIR = ROOT .. "Olympus/"

local passed, failed = 0, 0
local test = H and H.test or function(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; print("  ok   " .. name)
	else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
if MODE then test = function() end end -- (--names, --discover, --debug: the model alone)
local eq = H and H.eq or function(a, b, msg)
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local FIX = assert(loadfile(ROOT .. "tests/fixtures/forever-api.lua"))()
local AUDIT = assert(loadfile(ROOT .. "scripts/gamepad-audit.lua"))("--module")
local REGISTRY = {}
do
	local list = assert(AUDIT.LoadRegistry((ROOT:gsub("[/\\]$", "")) ~= "" and (ROOT:gsub("[/\\]$", "")) or "."))
	for _, e in ipairs(list) do REGISTRY[e.id] = e end
end

-- The pass's helpers: GP.Covers(id) names the registry entry a test exercises (the audit checks
-- every entry is named somewhere under tests/).
local GP = { covered = {} }
function GP.Covers(id)
	assert(REGISTRY[id], "GP.Covers: no registry entry " .. tostring(id))
	GP.covered[id] = true
end

local function Set(list) local s = {} for w in (list or ""):gmatch("%S+") do s[w] = true end return s end
-- (The model's own objects take their metatables as they are: tests/run.lua wraps setmetatable to
-- catch a coroutine yield across a metamethod in the addon's code, which no model object has.)
local setmetatable = function(t, mt) debug.setmetatable(t, mt) return t end
local WIDGET_METHODS = {}
for kind, list in pairs(FIX.widgets) do WIDGET_METHODS[kind] = Set(list) end
-- A key's fixture line: "type|the templates it inherits|its name" ($parent: its parent's name).
local function Key(spec)
	local kind, inherits, name = tostring(spec):match("^([^|]*)|([^|]*)|(.*)$")
	return kind or spec, inherits ~= "" and inherits or nil, name ~= "" and name or nil
end
local TEMPLATES = {}
for name, t in pairs(FIX.templates) do TEMPLATES[name] = { type = t.type, keys = t.keys, methods = Set(t.methods), chain = Set(t.chain) } end

---------------------------------------------------------------------------
-- Which registry entry a runtime reach belongs to: the gp: tags of the Olympus line that made it
-- (the audit's own reading of the source), else of its function's first line.
---------------------------------------------------------------------------

local TAGS = {} -- [file under Olympus/] = { [line] = { ids } }
do
	local root = (ROOT:gsub("[/\\]$", ""))
	if root == "" then root = "." end
	local vendor = {}
	for id, e in pairs(REGISTRY) do for _, f in ipairs(type(e.vendor) == "table" and e.vendor or {}) do vendor[f] = id end end
	local p = io.popen('cd "' .. root .. '" && find Olympus -name "*.lua"')
	for rel in p:lines() do
		local scan = AUDIT.ScanFile(root, rel)
		local short = rel:gsub("^Olympus/", "")
		local t = {}
		if scan then for line, tag in pairs(scan.tags) do t[line] = tag.ids end end
		if vendor[short] then setmetatable(t, { __index = function() return { vendor[short] } end }) end
		TAGS[short] = t
	end
	p:close()
end
local function OlympusFile(source)
	return type(source) == "string" and source:match("[@/\\]Olympus[/\\](.+%.lua)$")
end
-- The gate's own work at a switch (Gamepad.lua's Park, Leftovers and Switched, and the parks and
-- leftover checks they run): what can be undone undone, what stays read. Its records are the
-- switch's, allowed there; the sessions check what each park leaves.
local GATE_WORK = {}
do
	local n = 0
	for line in assert(io.open(ADDON_DIR .. "Gamepad.lua")):lines() do
		n = n + 1
		local fn = line:match("^function Gate%.(%a+)%(")
		if fn == "Park" or fn == "Leftovers" or fn == "Switched" then GATE_WORK[n] = fn end
	end
end
-- The Olympus line that made a reach: the first Olympus function on the stack above the model,
-- with its tags (its line's, else its function's first line's); when it has none (a helper handed
-- one of the game's frames, ns.MakeRoundButton), the first tagged Olympus caller above it.
local function Caller(level)
	level = (level or 2) + 1
	local found, gateWork
	while true do
		local info = debug.getinfo(level, "Sl")
		if not info then break end
		local file = OlympusFile(info.source)
		if file then
			file = file:gsub("\\", "/")
			if file == "Gamepad.lua" and GATE_WORK[info.linedefined] then gateWork = GATE_WORK[info.linedefined] end
			if not (found and found.ids) then
				local tags = TAGS[file] or {}
				local here = { file = file, line = info.currentline, ids = tags[info.currentline] or tags[info.linedefined] }
				if here.ids and found then here.via = found.file .. ":" .. tostring(found.line) end
				if here.ids or not found then found = here end
			end
		end
		level = level + 1
	end
	if found then found.gateWork = gateWork end
	return found
end
-- Called directly from Olympus's code (the model's own calls don't count): FromOlympus(1) in a
-- function of the model asks about that function's caller.
-- (Through pcall and the like: C functions, and tests/run.lua's stand-ins for them, are skipped.)
-- (1.5.4) The model's hooksecurefunc wrappers (below): the client's hook is C code between the
-- caller and the function hooked, so Olympus's call through one is still Olympus's. The wrappers
-- are skipped as a C frame is.
local HOOK_WRAPPERS = setmetatable({}, { __mode = "k" })
local function FromOlympus(level)
	level = (level or 1) + 2
	while true do
		local info = debug.getinfo(level, "Sf")
		if not info then return false end
		if info.what ~= "C" and not HOOK_WRAPPERS[info.func] and not (info.source or ""):find("tests[/\\]run%.lua$") then
			return OlympusFile(info.source) ~= nil
		end
		level = level + 1
	end
end

---------------------------------------------------------------------------
-- The client.
---------------------------------------------------------------------------

local LUA = {
	"assert", "error", "ipairs", "pairs", "next", "select", "type", "tostring", "tonumber", "unpack", "rawget", "rawset",
	"setmetatable", "getmetatable", "pcall", "xpcall", "string", "table", "math", "coroutine", "bit", "print",
	"loadstring", "collectgarbage",
}

local function NewClient(opts)
	opts = opts or {}
	local C = { ledger = {}, taint = {}, timers = {}, tickers = {}, loadErrors = {}, clock = 1000, now = 1760000000, style = opts.gamepad and 1 or 0,
		clicking = false, eventFrames = {}, updating = {}, menus = {}, postCalls = {}, nameFilters = {}, blocked = {},
		printed = {}, frames = {}, unmodelled = {}, created = {} }
	local E = {}
	C.env = E

	-- The ledger: a reach from Olympus's code, with the entry its line is tagged for.
	function C.Record(sym, kind, level)
		local who = Caller((level or 2) + 1)
		local r = { sym = sym, kind = kind, gamepad = C.style == 1, click = C.clicking, file = who and who.file, line = who and who.line,
			ids = who and who.ids, gateWork = who and who.gateWork, trace = debug.traceback("", 3) }
		C.ledger[#C.ledger + 1] = r
		return r
	end
	function C.Mark() return #C.ledger end
	function C.Since(mark)
		local out = {}
		for i = (mark or 0) + 1, #C.ledger do out[#out + 1] = C.ledger[i] end
		return out
	end

	------------------------------------------------------------------
	-- Widgets: every method a real one of that type has (the fixture's widgets and the template's
	-- mixin methods), no other. The ones modelled below behave; a setter the client has is kept as
	-- set; a getter the client has that isn't modelled fails when called (an "unmodelled" method).
	------------------------------------------------------------------
	local W = {}
	local SETTER = { "^Set", "^Enable", "^Disable", "^Register", "^Unregister", "^Clear", "^Lock", "^Unlock", "^Raise",
		"^Lower", "^Play", "^Stop", "^Start", "^Add", "^Remove", "^Reset", "^Apply", "^Desaturate", "^Highlight", "^Fit",
		"^Adjust", "^Flash", "^Update", "^Refresh", "^Mark", "^Insert", "^Scroll", "^Pause", "^Finish", "^Restart",
		"^Hook", "^Release", "^Acquire", "^Copy", "^Narration" }
	local function IsSetter(k) for _, p in ipairs(SETTER) do if k:find(p) then return true end end return false end
	-- What the audit counts per file instead of tagging (its ratchet): Olympus's own tooltips (the
	-- game's GameTooltip owned by one of Olympus's frames) and its lines in the chat windows
	-- ("chat-output"). Anything else on the tooltip (a player's, the game's) is a reach.
	local TOOLTIP_OWN = AUDIT.RATCHET.GameTooltip.methods
	local function Own(w, k, ...)
		if rawget(w, "kind") == "GameTooltip" and TOOLTIP_OWN[k] then
			local owner = (k == "SetOwner") and (...) or rawget(w, "owner")
			return type(owner) == "table" and rawget(owner, "olympus") == true
		end
		return false
	end
	local function RecordMethod(w, label, k)
		local r = C.Record(label .. ":" .. k, "method", 2)
		if not r.ids and rawget(w, "kind") == "ScrollingMessageFrame" and k == "AddMessage" then r.ids = { "chat-output" } end
		return r
	end
	local meta = {}
	meta.__index = function(w, k)
		local m = W[k]
		local methods, extra, blizzard = rawget(w, "methods"), rawget(w, "templateMethods"), rawget(w, "blizzard")
		local allowed = methods[k] or (extra and extra[k])
		local label = rawget(w, "name") or rawget(w, "path") or "?"
		if m and allowed then
			if blizzard and not AUDIT.READS[k] then
				return function(self, ...)
					if FromOlympus(1) and not Own(w, k, ...) then RecordMethod(w, label, k) end
					return m(self, ...)
				end
			end
			return m
		end
		if allowed and type(k) == "string" then
			return function(self, ...)
				if blizzard and not AUDIT.READS[k] and FromOlympus(1) and not Own(w, k, ...) then RecordMethod(w, label, k) end
				if IsSetter(k) then
					self.set[k] = { ... }
					return
				end
				C.unmodelled[rawget(w, "kind") .. ":" .. k] = true
				error(("unmodelled method %s:%s (the client has it: model it in tests/gamepad.lua)"):format(rawget(w, "kind"), k), 2)
			end
		end
		return nil
	end
	-- What a template's own scripts do, where Olympus relies on it (Blizzard_SharedXML).
	C.TEMPLATE_SCRIPTS = {
		-- UIPanelCloseButton_OnClick (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua:150-162): the
		-- parent's onCloseCallback first, then HideUIPanel unless it said no. HideUIPanel
		-- (UIParentPanelManager.lua) does nothing in combat for a call that is not secure; out of
		-- combat it hides a window that is no UI panel.
		UIPanelCloseButton = function(w)
			w.scripts.OnClick = function(self)
				local parent = self:GetParent()
				if not parent then return end
				local goOn = true
				if parent.onCloseCallback then goOn = parent.onCloseCallback(self) end
				if goOn and not C.combat then parent:Hide() end
			end
		end,
	}
	-- Forever 70790: SimpleFrameAPI.GetChildren (line 323) yields Frames;
	-- SimpleAnimatableObjectAPI.GetAnimationGroups (line 26) is a separate collection.
	local function ParentCollection(parent, kind)
		if kind == "AnimationGroup" then return parent.animationGroups end
		if kind == "Texture" or kind == "FontString" or kind == "MaskTexture" or kind == "Line" then return parent.regions end
		return parent.children
	end
	local function NewWidget(kind, name, parent, template, blizzard)
		local methods = WIDGET_METHODS[kind]
		assert(methods, "the client has no widget type " .. tostring(kind))
		local w = setmetatable({ kind = kind, name = name, parent = parent, children = {}, regions = {}, animationGroups = {}, points = {},
			shown = true, scripts = {}, hooks = {}, events = {}, set = {}, methods = methods, w = 0, h = 0, level = 1,
			alpha = 1, scale = 1, blizzard = blizzard or false, olympus = not blizzard, enabled = true, seq = #C.created + 1,
			templateMethods = false }, meta)
		if parent then
			local list = ParentCollection(parent, kind)
			list[#list + 1] = w
		end
		if name then
			-- "$parent" in a name is its parent's name (the client's rule for named children).
			if parent and name:find("%$parent") then name = name:gsub("%$parent", parent.name or "") ; w.name = name end
			rawset(E, name, w)
		end
		if template then
			local tm = {}
			for t in tostring(template):gmatch("[^,%s]+") do
				local def = TEMPLATES[t]
				if not def then error(("the client has no template %s (tests/fixtures/forever-api.lua)"):format(t), 3) end
				for m in pairs(def.methods) do tm[m] = true end
				for c in pairs(def.chain) do if C.TEMPLATE_SCRIPTS[c] then C.TEMPLATE_SCRIPTS[c](w) end end
				for key, spec in pairs(def.keys) do
					local ktype, inherits, kname = Key(spec)
					if rawget(w, key) == nil and WIDGET_METHODS[ktype] then
						local child = NewWidget(ktype, kname and name and kname or nil, w, inherits, blizzard)
						rawset(child, "path", (name or rawget(w, "path") or kind) .. "." .. key)
						rawset(child, "fromKey", true) -- (named "$parent..." by the client's own template)
						rawset(w, key, child)
					end
				end
			end
			w.templateMethods = tm
			w.template = template
		end
		C.created[#C.created + 1] = w
		return w
	end
	C.NewWidget = NewWidget

	function W:GetName() return self.name end
	function W:GetParent() return self.parent end
	function W:GetObjectType() return self.kind end
	function W:IsObjectType(t)
		if t == self.kind then return true end
		local family = { Button = { "Frame" }, CheckButton = { "Button", "Frame" }, EditBox = { "Frame" }, ScrollFrame = { "Frame" },
			Slider = { "Frame" }, StatusBar = { "Frame" }, GameTooltip = { "Frame" }, MessageFrame = { "Frame" },
			ScrollingMessageFrame = { "Frame" }, Minimap = { "Frame" } }
		for _, f in ipairs(family[self.kind] or {}) do if f == t then return true end end
		-- Region's documented visibility API is absent on AnimationGroup and Font.
		return (t == "Region" and self.methods.IsVisible ~= nil) or t == "Object" or (t == "ScriptObject" and self.methods.GetScript ~= nil)
	end
	function W:IsForbidden() return false end
	function W:IsProtected() return false, false end
	function W:GetDebugName() return self.name or "?" end
	function W:SetParent(p)
		if self.parent then
			for _, list in ipairs({ self.parent.children, self.parent.regions, self.parent.animationGroups }) do
				for i, c in ipairs(list) do if c == self then table.remove(list, i) break end end
			end
		end
		self.parent = p
		if p then table.insert(ParentCollection(p, self.kind), self) end
		if p and p.blizzard and p ~= E.UIParent and self.olympus and FromOlympus(1) then
			C.Record((rawget(p, "name") or rawget(p, "path") or "?") .. " <- " .. (self.name or self.kind), "parent", 1)
		end
	end
	function W:GetChildren() return unpack(self.children) end
	function W:GetNumChildren() return #self.children end
	function W:GetRegions() return unpack(self.regions) end
	function W:Show()
		if self.shown then return end
		self.shown = true
		if self:IsVisible() then C.Fire1(self, "OnShow") end
	end
	function W:Hide()
		if not self.shown then return end
		local was = self:IsVisible()
		self.shown = false
		if was then C.Fire1(self, "OnHide") end
	end
	function W:SetShown(on) if on then self:Show() else self:Hide() end end
	function W:IsShown() return self.shown end
	function W:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
	function W:SetScript(kind, fn)
		self.scripts[kind] = fn
		if kind == "OnUpdate" then C.updating[self] = fn and true or nil end
	end
	function W:GetScript(kind) return self.scripts[kind] end
	function W:HasScript(kind) return true end
	function W:HookScript(kind, fn)
		self.hooks[kind] = self.hooks[kind] or {}
		table.insert(self.hooks[kind], fn)
		if self.blizzard then C.callbacks[#C.callbacks + 1] = { kind = "HookScript", frame = self, script = kind, fn = fn } end
	end
	function W:RegisterEvent(e)
		local known = FIX.events[e]
		if known == nil then error(("event %s: not in tests/fixtures/forever-api.lua (run scripts/forever-api.lua)"):format(tostring(e)), 2) end
		if not known then error(("the client has no event %s"):format(tostring(e)), 2) end
		self.events[e] = true
		C.eventFrames[e] = C.eventFrames[e] or {}
		C.eventFrames[e][self] = true
	end
	function W:UnregisterEvent(e)
		self.events[e] = nil
		if C.eventFrames[e] then C.eventFrames[e][self] = nil end
	end
	function W:UnregisterAllEvents() for e in pairs(self.events) do self:UnregisterEvent(e) end end
	function W:IsEventRegistered(e) return self.events[e] == true end
	function W:SetSize(w, h) self.w, self.h = w or 0, h or 0 end
	function W:SetWidth(w) self.w = w or 0 end
	function W:SetHeight(h) self.h = h or 0 end
	function W:GetWidth() return self.w end
	function W:GetHeight() return self.h end
	function W:GetSize() return self.w, self.h end
	function W:SetPoint(point, rel, relPoint, x, y)
		if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
		if type(rel) == "string" then rel = rawget(E, rel) end
		self.points[#self.points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
	end
	function W:SetAllPoints(rel) self.points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } } end
	function W:ClearAllPoints() self.points = {} end
	function W:GetNumPoints() return #self.points end
	function W:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p) end end
	-- Where it is: a left, bottom, width and height as the screen would have them (a frame with no
	-- point sits at its parent's corner; UIParent fills a 1366 x 768 screen).
	function W:GetRect()
		if self.rect then return unpack(self.rect) end
		local p = self.parent
		local l, b = 0, 0
		if p then l, b = p:GetRect() end
		return l or 0, b or 0, self.w, self.h
	end
	function W:GetLeft() return (self:GetRect()) end
	function W:GetBottom() return select(2, self:GetRect()) end
	function W:GetTop() local _, b, _, h = self:GetRect(); return b + h end
	function W:GetRight() local l, _, w = self:GetRect(); return l + w end
	function W:GetCenter()
		-- HBD's actual pins use CENTER/CENTER relative to Minimap. Honour that screen offset;
		-- the former parent-corner approximation discarded SetPoint and could not test bearing.
		local p = self.points[1]
		if p and p[1] == "CENTER" and p[2] == E.Minimap and p[3] == "CENTER" then
			local x, y = p[2]:GetCenter(); return x + (p[4] or 0), y + (p[5] or 0)
		end
		local l, b, w, h = self:GetRect(); return l + w / 2, b + h / 2
	end
	function W:GetScale() return self.scale end
	function W:SetScale(s) self.scale = s end
	function W:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
	function W:SetAlpha(a) self.alpha = a end
	function W:GetAlpha() return self.alpha end
	function W:SetFrameLevel(l) self.level = l end
	function W:GetFrameLevel() return self.level end
	function W:SetFrameStrata(s) self.strata = s end
	function W:GetFrameStrata() return self.strata or "MEDIUM" end
	function W:SetID(id) self.id = id end
	function W:GetID() return self.id or 0 end
	function W:IsMouseOver() return false end
	function W:EnableMouse(on) self.mouse = on and true or false end
	function W:IsMouseEnabled() return self.mouse == true end
	function W:Enable() self.enabled = true end
	function W:Disable() self.enabled = false end
	function W:SetEnabled(on) self.enabled = on and true or false end
	function W:IsEnabled() return self.enabled end
	function W:CreateTexture(name, layer) local t = NewWidget("Texture", name, self, nil, self.blizzard and not FromOlympus(1)); t.layer = layer; return t end
	function W:CreateFontString(name, layer, font) local f = NewWidget("FontString", name, self, nil, self.blizzard and not FromOlympus(1)); f.layer, f.font = layer, font; return f end
	function W:CreateMaskTexture(name) return NewWidget("MaskTexture", name, self) end
	function W:CreateLine(name) return NewWidget("Line", name, self) end
	function W:CreateAnimationGroup(name)
		local g = NewWidget("AnimationGroup", name, self)
		g.target = self
		return g
	end
	function W:CreateAnimation(kind, name)
		local a = NewWidget(kind or "Animation", name, nil)
		a.group = self
		return a
	end
	function W:GetAnimationGroups() return unpack(self.animationGroups) end
	function W:IsPlaying() return false end
	-- Text: measured at 6 pixels a letter (codes and links left out).
	local function Shown(text) return (tostring(text or ""):gsub("|T.-|t", "WW"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end
	function W:SetText(text)
		self.text = text ~= nil and tostring(text) or nil
		if self.fontString then self.fontString.text = self.text end
	end
	function W:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
	function W:GetText() if self.fontString then return self.fontString.text end return self.text end
	function W:GetStringWidth() return #Shown(self.text) * 6 end
	function W:GetUnboundedStringWidth() return #Shown(self.text) * 6 end
	function W:GetStringHeight() return 12 end
	function W:GetNumLines() return 1 end
	function W:IsTruncated() return false end
	function W:SetFontObject(font) self.font = font end
	function W:GetFontObject() return self.font end
	function W:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
	function W:SetFont(path, size, flags) self.fontFile = { path, size, flags } return true end
	function W:SetTextColor(...) self.textColor = { ... } end
	function W:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
	function W:GetFontString()
		if not self.fontString then
			self.fontString = NewWidget("FontString", nil, self)
			self.fontString.text = self.text
		end
		return self.fontString
	end
	function W:SetFontString(fs) self.fontString = fs end
	function W:SetNormalFontObject(f) self.normalFont = f end
	function W:SetTexture(t) self.texture = t return true end
	function W:GetTexture() return self.texture end
	function W:SetAtlas(a) self.atlas = a return true end
	function W:GetAtlas() return self.atlas end
	function W:SetColorTexture(...) self.color = { ... } end
	function W:SetVertexColor(...) self.vertex = { ... } end
	function W:GetVertexColor() return unpack(self.vertex or { 1, 1, 1, 1 }) end
	function W:SetTexCoord(...) self.texCoord = { ... } end
	function W:GetTexCoord() return unpack(self.texCoord or { 0, 1, 0, 1 }) end
	function W:SetDrawLayer(layer, sub) self.layer, self.sublayer = layer, sub end
	function W:GetDrawLayer() return self.layer or "ARTWORK", self.sublayer or 0 end
	function W:SetChecked(on) self.checked = on and true or false end
	function W:GetChecked() return self.checked == true end
	function W:SetNormalTexture(t) self.normalTexture = t end
	function W:GetNormalTexture() if type(self.normalTexture) ~= "table" then self.normalTexture = NewWidget("Texture", nil, self) end return self.normalTexture end
	function W:SetHighlightTexture(t) self.highlightTexture = t end
	function W:GetHighlightTexture() if type(self.highlightTexture) ~= "table" then self.highlightTexture = NewWidget("Texture", nil, self) end return self.highlightTexture end
	function W:SetPushedTexture(t) self.pushedTexture = t end
	function W:GetPushedTexture() if type(self.pushedTexture) ~= "table" then self.pushedTexture = NewWidget("Texture", nil, self) end return self.pushedTexture end
	function W:GetDisabledTexture() if type(self.disabledTexture) ~= "table" then self.disabledTexture = NewWidget("Texture", nil, self) end return self.disabledTexture end
	function W:SetDisabledTexture(t) self.disabledTexture = t end
	function W:GetCheckedTexture() if type(self.checkedTexture) ~= "table" then self.checkedTexture = NewWidget("Texture", nil, self) end return self.checkedTexture end
	function W:LockHighlight() self.locked = true end
	function W:UnlockHighlight() self.locked = false end
	function W:GetButtonState() return "NORMAL" end
	-- A click from Olympus's own code (not the player's): its script, no hardware event.
	function W:Click(button) C.RunScript(self, "OnClick", button or "LeftButton", false) end
	-- Edit boxes.
	function W:SetFocus() C.focus = self end
	function W:ClearFocus() if C.focus == self then C.focus = nil end end
	function W:HasFocus() return C.focus == self end
	function W:SetMaxLetters(n) self.maxLetters = n end
	function W:GetMaxLetters() return self.maxLetters or 0 end
	function W:SetCursorPosition(p) self.cursor = p end
	function W:GetCursorPosition() return self.cursor or 0 end
	function W:HighlightText(first, last) self.selectionStart, self.selectionEnd = first or 0, last or #(self.text or "") end
	function W:SetAutoFocus(on) self.autoFocus = on end
	function W:SetMultiLine(on) self.multiLine = on end
	function W:IsMultiLine() return self.multiLine == true end
	function W:GetNumLetters() return #(self.text or "") end
	-- Scroll frames.
	function W:SetScrollChild(c) self.scrollChild = c end
	function W:GetScrollChild() return self.scrollChild end
	function W:GetVerticalScroll() return self.vscroll or 0 end
	function W:SetVerticalScroll(v) self.vscroll = v end
	function W:GetVerticalScrollRange() return 0 end
	function W:GetHorizontalScroll() return 0 end
	function W:UpdateScrollChildRect() end
	-- Sliders and status bars.
	function W:SetMinMaxValues(a, b) self.min, self.max = a, b end
	function W:GetMinMaxValues() return self.min or 0, self.max or 0 end
	function W:SetValue(v) self.value = v end
	function W:GetValue() return self.value or 0 end
	function W:GetThumbTexture() return NewWidget("Texture", nil, self) end
	-- Tooltips (GameTooltip): who owns it and its lines.
	function W:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {}; self.shown = true end
	function W:GetOwner() return self.owner end
	function W:IsOwned(owner) return self.owner == owner end
	function W:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = tostring(text) end
	function W:AddDoubleLine(a, b) self.lines = self.lines or {}; self.lines[#self.lines + 1] = tostring(a) .. " | " .. tostring(b) end
	function W:ClearLines() self.lines = {} end
	function W:NumLines() return #(self.lines or {}) end
	-- (1.5.4) GameTooltip:SetHyperlink(link): the tooltip filled with the link's item, spell or quest
	-- (the fixture's GameTooltip methods; Blizzard_SharedXML's TooltipDataHandler fills the lines).
	function W:SetHyperlink(link) self.lines = self.lines or {}; self.hyperlink = link; self.lines[#self.lines + 1] = tostring(link) end
	function W:SetMinimumWidth(w) self.minWidth = w end
	-- (The unit a tooltip shows: its name and unit token, as the game's GameTooltip:GetUnit.)
	function W:GetUnit() if self.unit then return E.UnitName(self.unit), self.unit end end
	function W:SetUnit(unit) self.unit = unit; self.lines = {} end
	function W:SetPadding() end
	-- Minimap.
	function W:GetZoom() return 0 end
	-- Message frames (the chat windows): what was printed.
	function W:AddMessage(text, ...)
		C.printed[#C.printed + 1] = tostring(text)
		self.messages = self.messages or {}
		self.messages[#self.messages + 1] = tostring(text)
	end
	-- The template's own (BackdropTemplateMixin): kept as set.
	function W:SetBackdrop(b) self.backdrop = b end
	function W:GetBackdrop() return self.backdrop end
	function W:SetBackdropColor(...) self.backdropColor = { ... } end
	function W:SetBackdropBorderColor(...) self.backdropBorder = { ... } end
	function W:SetFixedFrameStrata(on) self.fixedStrata = on end
	function W:SetFixedFrameLevel(on) self.fixedLevel = on end
	function W:SetToplevel(on) self.toplevel = on end
	function W:SetMovable(on) self.movable = on end
	function W:IsMovable() return self.movable == true end
	function W:SetResizable(on) self.resizable = on end
	function W:SetClampedToScreen(on) self.clamped = on end
	function W:StartMoving() end
	function W:StopMovingOrSizing() end
	function W:SetUserPlaced(on) self.userPlaced = on end
	function W:IsUserPlaced() return self.userPlaced == true end
	function W:SetHitRectInsets(...) self.hitRect = { ... } end
	function W:SetJustifyH(j) self.justifyH = j end
	function W:GetJustifyH() return self.justifyH or "CENTER" end
	function W:SetJustifyV(j) self.justifyV = j end
	function W:SetWordWrap(on) self.wrap = on end
	function W:SetNonSpaceWrap(on) self.nonSpaceWrap = on end
	function W:SetMaxLines(n) self.maxLines = n end
	function W:SetSpacing(n) self.spacing = n end
	function W:SetShadowOffset(...) self.shadow = { ... } end
	function W:SetShadowColor(...) self.shadowColor = { ... } end
	function W:SetIgnoreParentAlpha(on) self.ignoreAlpha = on end
	function W:SetIgnoreParentScale(on) self.ignoreScale = on end
	function W:SetBlendMode(m) self.blend = m end
	function W:SetDesaturated(on) self.desaturated = on end
	function W:SetRotation(r) self.rotation = r end
	function W:SetHorizTile(on) self.horizTile = on end
	function W:SetVertTile(on) self.vertTile = on end
	function W:SetClipsChildren(on) self.clips = on end
	function W:SetPropagateKeyboardInput(on) self.propagate = on end
	function W:EnableKeyboard(on) self.keyboard = on end
	function W:EnableMouseWheel(on) self.wheel = on end
	function W:RegisterForClicks(...) self.clicks = { ... } end
	function W:RegisterForDrag(...) self.drag = { ... } end
	function W:SetMotionScriptsWhileDisabled(on) self.motionDisabled = on end

	-- Scripts run: the frame's own, then its hooks (the client's order for HookScript).
	function C.RunScript(w, kind, ...)
		local fn = w.scripts[kind]
		if fn then fn(w, ...) end
		for _, h in ipairs(w.hooks[kind] or {}) do h(w, ...) end
	end
	function C.Fire1(w, kind) C.RunScript(w, kind) end

	-- A callback the game calls isolated (securecallfunction: a menu's, a tooltip post-call, a
	-- filter's): an error goes to the error handler, the game goes on.
	C.isolatedErrors = {}
	function C.Isolated(fn, ...)
		local ok, err = xpcall(fn, debug.traceback, ...)
		if not ok then C.isolatedErrors[#C.isolatedErrors + 1] = err; pcall(C.handler, err) end
		return ok
	end
	-- The player's click on a button: the hardware event restricted calls need.
	function C.Click(w, mouse)
		assert(w:IsVisible(), "clicked a button that doesn't show: " .. tostring(w.name or w.kind))
		C.clicking = true
		local ok, err = pcall(function()
			C.RunScript(w, "OnClick", mouse or "LeftButton", true)
			C.RunScript(w, "PostClick", mouse or "LeftButton", true)
		end)
		C.clicking = false
		if not ok then error(err, 0) end
	end

	------------------------------------------------------------------
	-- Events and time.
	------------------------------------------------------------------
	function C.Fire(event, ...)
		local list = {}
		for f in pairs(C.eventFrames[event] or {}) do list[#list + 1] = f end
		table.sort(list, function(a, b) return rawget(a, "seq") < rawget(b, "seq") end)
		for _, f in ipairs(list) do
			local fn = f.scripts.OnEvent
			if fn then fn(f, event, ...) end
		end
	end
	function C.After(seconds, fn)
		C.timers[#C.timers + 1] = { at = C.clock + math.max(0, tonumber(seconds) or 0), fn = fn, seq = #C.timers }
	end
	-- Time goes by: due timers and tickers run in order, OnUpdate scripts once a step.
	function C.Advance(seconds)
		local stop = C.clock + (seconds or 0)
		local guard = 0
		while true do
			guard = guard + 1
			assert(guard < 100000, "timers run away")
			table.sort(C.timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
			local t = C.timers[1]
			local nextTick
			for _, k in ipairs(C.tickers) do
				if not k.cancelled and (not nextTick or k.at < nextTick.at) then nextTick = k end
			end
			local due = t and t.at <= stop and t
			local tickDue = nextTick and nextTick.at <= stop and nextTick
			if due and (not tickDue or due.at <= tickDue.at) then
				table.remove(C.timers, 1)
				C.clock = math.max(C.clock, due.at)
				due.fn()
			elseif tickDue then
				C.clock = math.max(C.clock, tickDue.at)
				tickDue.at = tickDue.at + tickDue.every
				tickDue.n = tickDue.n + 1
				if tickDue.iterations and tickDue.n >= tickDue.iterations then tickDue.cancelled = true end
				tickDue.fn(tickDue)
			else
				break
			end
		end
		local elapsed = stop - C.clock
		C.clock = stop
		for w in pairs(C.updating) do
			if w.scripts.OnUpdate and w:IsVisible() then w.scripts.OnUpdate(w, math.max(elapsed, 0.016)) end
		end
	end

	------------------------------------------------------------------
	-- The globals: Lua's (the client's Lua 5.1 and its own additions), then the game's.
	------------------------------------------------------------------
	for _, k in ipairs(LUA) do E[k] = _G[k] end
	E._G = E
	-- print: a line in the main chat window (Blizzard_PrintHandler sends it to DEFAULT_CHAT_FRAME).
	E.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		C.printed[#C.printed + 1] = table.concat(parts, " ")
	end
	-- The client's Lua additions (Blizzard's code reads them as globals; the fixture says "used").
	E.strsplit = function(sep, s, limit)
		local out, start = {}, 1
		s = tostring(s)
		while true do
			if limit and #out == limit - 1 then out[#out + 1] = s:sub(start) break end
			local i, j = s:find(sep, start, true)
			if not i then out[#out + 1] = s:sub(start) break end
			out[#out + 1] = s:sub(start, i - 1)
			start = j + 1
		end
		return unpack(out)
	end
	E.strtrim = function(s, chars)
		chars = chars and ("[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]") or "%s"
		return (tostring(s):gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
	end
	E.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
	E.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	E.tinsert, E.tremove, E.format, E.strlen, E.strsub, E.strfind, E.strmatch, E.gsub = table.insert, table.remove,
		string.format, string.len, string.sub, string.find, string.match, string.gsub
	E.strlower, E.strupper, E.strrep, E.strbyte, E.strchar = string.lower, string.upper, string.rep, string.byte, string.char
	E.floor, E.ceil, E.abs, E.min, E.max, E.sqrt, E.random, E.sort = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.random, table.sort
	E.time = function(t) if t then return os.time(t) end return C.now end
	E.date = function(fmt, t) return os.date(fmt, t or C.now) end
	E.GetTime = function() return C.clock end
	E.GetServerTime = function() return C.now end
	E.debugprofilestop = function() return C.clock * 1000 end
	E.debugstack = function() return debug.traceback("", 2) end
	-- Secret values (the client's issecretvalue): none in the pass.
	E.issecretvalue = function() return false end
	-- issecurevariable (the taint model, as far as the pass needs it): the game's own tables and
	-- globals, as the model made them, are secure; a table Olympus's code made (its own, or the
	-- map library's in Olympus/libs), or a global it wrote, is Olympus's: false, "Olympus".
	C.gameTables = setmetatable({}, { __mode = "k" })
	C.gameValues = {}
	E.issecurevariable = function(t, key)
		if key == nil then
			if rawget(E, t) == C.gameValues[t] then return true, nil end
			return false, "Olympus"
		end
		if type(t) == "table" and C.gameTables[t] then return true, nil end
		return false, "Olympus"
	end
	-- (After the world is made: everything in it is the game's.)
	function C.SealGame()
		local function Mark(t, depth)
			if type(t) ~= "table" or C.gameTables[t] or depth > 4 then return end
			C.gameTables[t] = true
			for _, v in pairs(t) do Mark(v, depth + 1) end
		end
		for k, v in pairs(E) do
			C.gameValues[k] = v
			if k ~= "_G" then Mark(v, 1) end
		end
	end
	-- The error handler: the game's own, until an addon sets one.
	local gameHandler = function(err) C.gameErrors = (C.gameErrors or 0) + 1 end
	C.handler = gameHandler
	C.gameHandler = gameHandler
	E.geterrorhandler = function() return C.handler end
	E.seterrorhandler = function(fn)
		if FromOlympus(1) then C.Record("seterrorhandler", "call", 1) end
		C.handler = fn
	end
	E.securecallfunction = function(fn, ...) return fn(...) end
	E.securecall = function(fn, ...) if type(fn) == "string" then fn = E[fn] end return fn(...) end
	E.InCombatLockdown = function() return C.combat == true end
	E.IsLoggedIn = function() return C.loggedIn == true end
	E.IsShiftKeyDown = function() return C.shift == true end
	E.IsControlKeyDown = function() return false end
	E.IsAltKeyDown = function() return false end
	E.GetCursorPosition = function() return 0, 0 end
	E.GetLocale = function() return "enUS" end
	E.GetBuildInfo = function() return "1.60.1", tostring(FIX.build), "Oct 1 2026", 16001 end
	-- (The realm: "Realm", or one a session sets, C.realmName.)
	C.realmName = "Realm"
	E.GetRealmName = function() return C.realmName end
	E.GetNormalizedRealmName = function() return (C.realmName:gsub("[%s%-]", "")) end
	E.GetRealmID = function() return 1 end
	-- Units: the player, and whoever a flow puts under the cursor or targets (C.units).
	-- (opts.surname: a Forever player, whose name has a surname where a realm would be.)
	C.units = { player = { name = "Tester", realm = opts.surname or "Realm", guid = "Player-1-00000001", guild = "Olympus II", rank = "Hero", rankIndex = 2 } }
	local function U(unit) return C.units[unit] end
	E.UnitFullName = function(unit) local u = U(unit); if u then return u.name, u.realm end end
	E.UnitName = function(unit) local u = U(unit); if u then return u.name, u.realm ~= C.realmName and u.realm or nil end end
	E.UnitGUID = function(unit) local u = U(unit); return u and u.guid end
	E.UnitFactionGroup = function(unit) if U(unit) then return "Alliance", "Alliance" end end
	E.UnitExists = function(unit) return U(unit) ~= nil end
	-- Forever's generated UnitDocumentation exposes UnitIsVisible separately from UnitExists.
	assert(FIX.globals.UnitIsVisible == "api")
	E.UnitIsVisible = function(unit) local u = U(unit); return u ~= nil and u.visible ~= false end
	E.UnitIsPlayer = function(unit) local u = U(unit); return u ~= nil and tostring(u.guid):find("^Player%-") ~= nil end
	E.UnitLevel = function(unit) return U(unit) and 60 or 0 end
	E.UnitClass = function(unit) if U(unit) then return "Warrior", "WARRIOR", 1 end end
	E.IsInGuild = function() return true end
	E.GetGuildInfo = function(unit) local u = U(unit); if u and u.guild then return u.guild, u.rank, u.rankIndex end end
	E.IsInInstance = function() return false, "none" end
	E.IsInGroup = function() return false end
	E.IsInRaid = function() return false end
	E.GetNumGroupMembers = function() return 0 end
	E.PlaySound = function() end
	E.GetMaxPlayerLevel = function() return 60 end
	E.GetMoney = function() return C.money or 0 end
	-- 1.2.5.1, the Olympus Accord's BattleTag (Accord.ReadTag): Battle.net connected (BNConnected, as
	-- Blizzard_FriendsFrame's FriendsFrame_CheckBattlenetStatus asks it) and the player's own tag,
	-- BNGetInfo's second value (a test tag, nobody's). C.bnet = false: disconnected, no tag.
	-- Forever 70790 also calls BNFeaturesEnabledAndConnected before BNGetInfo in
	-- Blizzard_UnitPopupShared/UnitPopupSharedUtils.lua:81-87 (HasBattleTag).
	E.BNConnected = function() return C.bnet ~= false end
	E.BNFeaturesEnabledAndConnected = function() return C.bnet ~= false and C.bnetFeatures ~= false end
	E.BNGetInfo = function()
		if C.bnet == false then return nil end
		return 1, C.battleTag or "Tester#1234", nil, "", false, false, false
	end

	-- The input style (fidelity rule 1): values from the documentation.
	local ENUM = {}
	for name, values in pairs(FIX.enums) do if values then ENUM[name] = values end end
	E.Enum = setmetatable(ENUM, { __index = function(_, k)
		if FIX.enums[k] == false then return nil end -- (the documentation has no such Enum table)
		error(("Enum.%s: not in tests/fixtures/forever-api.lua (run scripts/forever-api.lua)"):format(tostring(k)), 2)
	end })
	E.Constants = FIX.constants
	E.C_InputInterfaceStyle = { GetCurrentStyle = function() return C.style end }
	function C.Switch(gamepad)
		local new = gamepad and E.Enum.InputDeviceInterfaceType.Gamepad or E.Enum.InputDeviceInterfaceType.Mkb
		local old = C.style
		if new == old then return end
		C.style = new
		local mark = C.Mark()
		C.Fire("INPUT_DEVICE_INTERFACE_TRANSITION", new, old)
		C.switchLedger = C.Since(mark)
	end

	-- Timers (rule 6).
	E.C_Timer = {
		After = function(seconds, fn) C.After(seconds, fn) end,
		NewTicker = function(every, fn, iterations)
			local k = { every = every, fn = fn, at = C.clock + every, n = 0, iterations = iterations }
			function k.Cancel() k.cancelled = true end
			function k.IsCancelled() return k.cancelled == true end
			C.tickers[#C.tickers + 1] = k
			return k
		end,
		NewTimer = function(seconds, fn)
			local k = { cancelled = false }
			function k.Cancel() k.cancelled = true end
			function k.IsCancelled() return k.cancelled end
			C.After(seconds, function() if not k.cancelled then fn(k) end end)
			return k
		end,
	}

	-- Frames.
	E.CreateFrame = function(kind, name, parent, template)
		local w = NewWidget(kind, name, parent, template, false)
		w.olympus = FromOlympus(1) -- (else the model's own, a pool of the game's)
		-- (Olympus's frames hang from UIParent, the screen's root: no reach. Inside another of the game's, one.)
		if parent and parent.blizzard and parent ~= E.UIParent and FromOlympus(1) then
			C.Record((rawget(parent, "name") or rawget(parent, "path") or "?") .. " <- " .. (name or kind), "parent", 1)
		end
		return w
	end
	C.callbacks = {}

	-- The strict environment (rule 5). (opts.discover, for working on the model: an unmodelled
	-- name is noted and answers a callable stand-in instead of failing.)
	local function Probe(name)
		return setmetatable({}, {
			__index = function(_, k) C.unmodelled[name .. "." .. tostring(k)] = true return Probe(name .. "." .. tostring(k)) end,
			__call = function() C.unmodelled[name .. "()"] = true return nil end,
		})
	end
	-- Names the client has but not now (an addon not loaded yet), each with why: nil.
	C.absent = {}
	function C.Absent(name, why) C.absent[name] = why end
	setmetatable(E, {
		__index = function(_, k)
			if C.absent[k] then return nil end
			local kind = FIX.globals[k]
			if kind == nil then
				if type(k) == "string" and AUDIT.Own(k) then return nil end
				C.unmodelled[tostring(k)] = true
				if opts.discover then return Probe(tostring(k)) end
				error(("the addon reads the global %s, which tests/fixtures/forever-api.lua doesn't know (run scripts/forever-api.lua)"):format(tostring(k)), 2)
			elseif kind then
				C.unmodelled[k] = true
				if opts.discover then return Probe(k) end
				error(("unmodelled API %s: the client has it (%s); model it in tests/gamepad.lua"):format(k, kind), 2)
			end
			return nil
		end,
	})
	C.Probe = Probe
	return C
end

---------------------------------------------------------------------------
-- The game's side: its frames, its functions, its tables. Each modelled from what Forever's UI
-- source shows (the fixture, the files cited), as far as Olympus uses it.
---------------------------------------------------------------------------

local function World(C, opts)
	local E = C.env
	opts = opts or {}
	local Namespace
	-- A namespace (C_FriendList...): the members modelled; one the client has that isn't
	-- modelled fails, one it lacks is nil.
	function Namespace(name, members)
		return setmetatable(members, { __index = function(_, k)
			local full = name .. "." .. tostring(k)
			local kind = FIX.members[full]
			if kind == nil then
				C.unmodelled[full] = true
				if opts.discover then return C.Probe(full) end
				error(("the addon reads %s, which tests/fixtures/forever-api.lua doesn't know (run scripts/forever-api.lua)"):format(full), 2)
			elseif kind then
				C.unmodelled[full] = true
				if opts.discover then return C.Probe(full) end
				error(("unmodelled API %s: the client has it (%s); model it in tests/gamepad.lua"):format(full, kind), 2)
			end
			return nil
		end })
	end
	C.Namespace = Namespace
	E.C_Timer = Namespace("C_Timer", E.C_Timer)
	E.C_InputInterfaceStyle = Namespace("C_InputInterfaceStyle", E.C_InputInterfaceStyle)
	-- A function the audit counts as a reach: each call from Olympus's code goes in the ledger.
	local function Reach(name, fn)
		return function(...)
			if FromOlympus(1) then C.Record(name, "call", 1) end
			return fn(...)
		end
	end
	-- A restricted function (fidelity rule 4): from Olympus's code outside the player's click, the
	-- game refuses it and sends ADDON_ACTION_BLOCKED; inside a click, it runs.
	local function Restricted(name, fn)
		return function(...)
			if FromOlympus(1) then
				local r = C.Record(name, "call", 1)
				if not C.clicking then
					r.kind = "blocked"
					C.blocked[#C.blocked + 1] = name
					C.After(0, function() C.Fire("ADDON_ACTION_BLOCKED", "Olympus", name .. "()") end)
					return nil
				end
			end
			return fn(...)
		end
	end
	local function Fn(name, fn)
		local full = name
		if FIX.restricted[full] then return Restricted(full, fn) end
		local base, member = name:match("^([^%.]+)%.(.+)$")
		local ns = base and AUDIT.NAMESPACES[base]
		if AUDIT.REACH[name] or (base and AUDIT.REACH[base]) or (ns and ns.reach[member]) then return Reach(name, fn) end
		return fn
	end
	C.Fn = Fn

	-- The game's frames: the type, keys and mixin methods its XML gives it (the fixture's frames),
	-- else the type given here.
	local function Blizz(name, kind, parent)
		local def = FIX.frames[name]
		local w = C.NewWidget(def and def.type or kind, name, parent or E.UIParent, nil, true)
		if def then
			w.templateMethods = Set(def.methods)
			for key, spec in pairs(def.keys) do
				local ktype, inherits, kname = Key(spec)
				if WIDGET_METHODS[ktype] and rawget(w, key) == nil then
					local ok, child = pcall(C.NewWidget, ktype, kname, w, inherits, true)
					if not ok then child = C.NewWidget(ktype, kname, w, nil, true) end
					rawset(child, "path", name .. "." .. key)
					rawset(child, "fromKey", true) -- (named "$parent..." by the client's own XML)
					rawset(w, key, child)
				end
			end
		end
		C.frames[name] = w
		return w
	end
	C.Blizz = Blizz
	-- A method of the game's own Lua (a mixin's) on one of its frames: what it does here, and the
	-- call from Olympus's code in the ledger.
	local function Method(w, key, fn)
		rawset(w, key, function(self, ...)
			if FromOlympus(1) and not AUDIT.READS[key] then C.Record((w.name or "?") .. ":" .. key, "method", 1) end
			return fn(self, ...)
		end)
	end
	C.Method = Method

	E.UIParent = C.NewWidget("Frame", "UIParent", nil, nil, true)
	E.UIParent.rect = { 0, 0, 1366, 768 }
	E.UIParent.w, E.UIParent.h = 1366, 768
	E.GetPhysicalScreenSize = function() return 1366, 768 end
	E.GameTooltip = Blizz("GameTooltip", "GameTooltip")
	E.GameTooltip.shown = false
	E.Minimap = Blizz("Minimap", "Minimap")
	E.Minimap.w, E.Minimap.h, E.Minimap.rect = 140, 140, { 1210, 610, 140, 140 }
	E.C_Minimap = Namespace("C_Minimap", { GetViewRadius = function() return 100 end })

	-- Fonts (the game's font objects, read by name).
	for name, kind in pairs(FIX.globals) do
		if kind == "font" then E[name] = C.NewWidget("Font", name, nil, nil, true) end
	end
	E.ChatFontNormal = E.ChatFontNormal or C.NewWidget("Font", "ChatFontNormal", nil, nil, true)
	E.QuestFont = E.QuestFont or C.NewWidget("Font", "QuestFont", nil, nil, true)

	-- The chat windows (Blizzard_ChatFrameBase: ChatFrame1..10, DEFAULT_CHAT_FRAME = ChatFrame1,
	-- ChatFrameUtil.lua:19), their tabs and edit box.
	E.NUM_CHAT_WINDOWS = 10
	for i = 1, 10 do
		local f = Blizz("ChatFrame" .. i, "ScrollingMessageFrame")
		f.shown = i <= 2
		f.chatIndex = i
		local tab = Blizz("ChatFrame" .. i .. "Tab", "Button")
		tab.shown = i <= 2
	end
	E.DEFAULT_CHAT_FRAME = E.ChatFrame1
	E.SELECTED_CHAT_FRAME = E.ChatFrame1
	-- (ChatFrame1's own edit box, its template's "$parentEditBox".)
	E.ChatFrame1EditBox = rawget(E, "ChatFrame1EditBox") or Blizz("ChatFrame1EditBox", "EditBox")
	E.ChatFrame1EditBox.shown = false
	local windows = { "General", "Combat Log" }
	E.GetChatWindowInfo = function(i)
		if i < 1 or i > 10 then return nil end
		return windows[i] or "", 14, 1, 1, 1, 1, i <= 2, false, i == 1 and 1 or 0, false
	end
	E.FCF_GetChatWindowInfo = E.GetChatWindowInfo
	E.GetChatWindowChannels = function() return end
	E.GetChatWindowMessages = function() return end
	E.IsCombatLog = function(f) return f == E.ChatFrame2 end
	E.ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, id = 1 } end })
	E.NEW_CHAT_WINDOW, E.CHAT_CONFIGURATION = "New Window", "Chat Configuration"
	E.YES, E.NO, E.OKAY, E.ACCEPT, E.CANCEL, E.SEND_LABEL, E.UNKNOWNOBJECT = "Yes", "No", "Okay", "Accept", "Cancel", "Send", "Unknown"
	E.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
	E.REMOVE = "Remove" -- (the engine's global string, read by Blizzard's own code: the fixture's "used")

	-- The game's chat box (fidelity rule 8): opened, it is the last active edit box, which the
	-- gamepad chat reads.
	local function ChatBox(text)
		C.chatBox = { text = text }
		E.ACTIVE_CHAT_EDIT_BOX = E.ChatFrame1EditBox
		E.LAST_ACTIVE_CHAT_EDIT_BOX = E.ChatFrame1EditBox
		E.ChatFrame1EditBox:Show()
		E.ChatFrame1EditBox.text = text
	end
	E.ChatFrame_OpenChat = Fn("ChatFrame_OpenChat", function(text) ChatBox(text) end)
	E.ChatFrame_SendTell = Fn("ChatFrame_SendTell", function(name) ChatBox("/w " .. tostring(name) .. " ") end)
	E.ChatEdit_InsertLink = Fn("ChatEdit_InsertLink", function(link) if C.chatBox then C.chatBox.text = (C.chatBox.text or "") .. link return true end return false end)
	E.ChatFrame_RemoveChannel = Fn("ChatFrame_RemoveChannel", function(frame, name) C.removedChannels = (C.removedChannels or 0) + 1 end)
	E.GetCurrentKeyBoardFocus = function() return C.focus end
	-- A link clicked in a chat window: its OnHyperlinkClick calls SetItemRef (Blizzard_ChatFrameBase/
	-- Shared/ChatFrame.lua:19; Blizzard_UIPanels_Game/Mainline/ItemRef.lua:6). Modelled for the link
	-- types the pass clicks: "addon" goes to the game's AddOn handler, which only fires EventRegistry's
	-- "SetItemRef" (ItemRefHandlersShared.lua:279); another type, the game's own work, kept in C.itemRefs.
	-- (1.5.4: a reach when Olympus calls it, the audit's "SetItemRef": the Chat tab's link click.)
	E.SetItemRef = Fn("SetItemRef", function(link, text, button, frame)
		C.itemRefs = C.itemRefs or {}
		C.itemRefs[#C.itemRefs + 1] = { link = link, button = button, handled = tostring(link):find("^addon:") and "AddOn" or "game" }
	end)

	-- Channels (the census channel): joined, numbered, listed.
	C.channels = {}
	E.JoinChannelByName = Fn("JoinChannelByName", function(name)
		if not C.channels[name] then C.channels[name] = #C.channels + 5 end
		C.After(0.5, function() C.Fire("CHANNEL_UI_UPDATE") end)
	end)
	E.LeaveChannelByName = Fn("LeaveChannelByName", function(name) C.channels[name] = nil end)
	E.GetChannelName = function(id)
		for name, n in pairs(C.channels) do
			if id == name or id == n then return n, name end
		end
		return 0, nil
	end
	E.GetChannelList = function()
		local out = {}
		for name, n in pairs(C.channels) do out[#out + 1] = n; out[#out + 1] = name; out[#out + 1] = false end
		return unpack(out)
	end
	E.GetNumDisplayChannels = function() return 0 end
	E.GetChannelDisplayInfo = function() return nil end
	E.SetChannelPassword = function() end
	E.ChannelUnban = function() end

	-- Addon messages (Olympus's comm): what it sends, kept.
	C.sent = {}
	local prefixes = {}
	E.C_ChatInfo = Namespace("C_ChatInfo", {
		RegisterAddonMessagePrefix = function(p) prefixes[p] = true return true end,
		IsAddonMessagePrefixRegistered = function(p) return prefixes[p] == true end,
		SendAddonMessage = function(prefix, msg, kind, target) C.sent[#C.sent + 1] = { prefix, msg, kind, target } return 0 end,
		SendAddonMessageLogged = function(prefix, msg, kind, target) C.sent[#C.sent + 1] = { prefix, msg, kind, target } return 0 end,
		InChatMessagingLockdown = function() return false end,
		GetChannelInfoFromIdentifier = function() return nil end,
		SwapChatChannelsByChannelIndex = Fn("C_ChatInfo.SwapChatChannelsByChannelIndex", function() end),
		-- (1.2: a whisper the player wrote, ns.SayTo; restricted to a hardware event, as the global.)
		SendChatMessage = Fn("C_ChatInfo.SendChatMessage", function(text, kind, lang, target) C.said = C.said or {}; C.said[#C.said + 1] = { text, kind, target } end),
	})
	-- (1.2: a Farkle table's /sit, the player's click; restricted, the fixture's DoEmote.)
	E.DoEmote = Fn("DoEmote", function(token) C.emotes = C.emotes or {}; C.emotes[#C.emotes + 1] = token end)
	E.SendChatMessage = Fn("SendChatMessage", function(text, kind, lang, target) C.said = C.said or {}; C.said[#C.said + 1] = { text, kind, target } end)

	-- The guild (Forever's roster: GetGuildRosterInfo, as Roster.lua reads it).
	C.roster = opts.roster or {
		{ "Tester-Realm", "Hero", 2, 60, "Warrior", "Elwynn Forest", "", "", true, 0, "WARRIOR" },
		{ "Zeusmaster-Realm", "Zeus", 0, 60, "Mage", "Stormwind City", "", "", true, 0, "MAGE" },
		{ "Titanbold-Realm", "Titan", 1, 58, "Priest", "Westfall", "", "", false, 0, "PRIEST" },
	}
	E.GetNumGuildMembers = function() local online = 0 for _, m in ipairs(C.roster) do if m[9] then online = online + 1 end end return #C.roster, online, online end
	E.GetGuildRosterInfo = function(i) local m = C.roster[i]; if m then return unpack(m, 1, 11) end end
	E.GuildControlGetNumRanks = function() return 4 end
	E.GuildControlGetRankName = function(i) return ({ "Zeus", "Titan", "Hero", "Recruit" })[i] end
	E.CanGuildInvite = function() return true end
	E.CanGuildRemove = function() return false end
	E.C_GuildInfo = Namespace("C_GuildInfo", {
		GuildRoster = function() C.After(0.2, function() C.Fire("GUILD_ROSTER_UPDATE", false) end) end,
		AreGuildEventsEnabled = function() return true end,
		Invite = Fn("C_GuildInfo.Invite", function() end),
		Uninvite = Fn("C_GuildInfo.Uninvite", function() end),
	})
	E.GuildInvite = Fn("GuildInvite", function() end)
	E.GuildUninvite = Fn("GuildUninvite", function() end)

	-- Units, the group, the map.
	E.UnitIsConnected = function() return true end
	E.UnitIsDND = function() return false end
	E.UnitIsFriend = function() return true end
	E.UnitCanAttack = function() return false end
	E.UnitIsUnit = function(a, b) return a == b end
	E.UnitIsGroupLeader = function() return false end
	E.UnitIsGroupAssistant = function() return false end
	E.UnitPosition = function(unit)
		local p = unit == "player" and C.position
		if p then return p.wx, p.wy, p.z or 0, p.cont end
		return nil
	end
	assert(FIX.globals.IsResting == "api", "IsResting must be verified in the client fixture")
	E.IsResting = function() return C.resting == true end
	-- Forever 70790, UnitAuraDocumentation.lua:395-409: own AuraData (or nil), read-only.
	assert(FIX.members["C_UnitAuras.GetPlayerAuraBySpellID"] == "api")
	assert(FIX.events.UNIT_AURA == true, "the fixture must include the companion's native aura event")
	E.C_UnitAuras = Namespace("C_UnitAuras", {
		GetPlayerAuraBySpellID = function(spellID)
			if C.campAura and C.campAura.spellId == spellID then return C.campAura end
		end,
	})
	E.GetPlayerFacing = function() return C.facing end
	E.GetUnitName = function(unit) return E.UnitName(unit) end
	E.RegionalUniqueNamesEnabled = function() return false end
	E.GetNativeRealmID = function() return 1 end
	E.CheckInteractDistance = function() return false end
	E.CanInspect = function() return false end
	E.NotifyInspect = Fn("NotifyInspect", function() end)
	E.ClearInspectPlayer = Fn("ClearInspectPlayer", function() end)
	E.GetInventoryItemID = function() return nil end
	E.GetInventoryItemLink = function() return nil end
	E.INVSLOT_TABARD = 19
	E.C_PartyInfo = Namespace("C_PartyInfo", {
		InviteUnit = Fn("C_PartyInfo.InviteUnit", function(name) C.invited = name end),
		LeaveParty = Fn("C_PartyInfo.LeaveParty", function() C.left = true end),
	})
	E.AcceptGroup = Fn("AcceptGroup", function() C.accepted = true end)
	E.GetZoneText = function() return "Elwynn Forest" end
	E.GetRealZoneText = function() return "Elwynn Forest" end
	E.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest", PALADIN = "Paladin" }
	E.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
	E.SOUNDKIT = setmetatable({}, { __index = function(_, k)
		if FIX.members["SOUNDKIT." .. tostring(k)] == false then return nil end
		return 1
	end })
	E.PlaySound = function() end
	E.GetCVar = function(name) if name == "rotateMinimap" then return "0" end if name == "minimapZoom" then return "0" end return nil end
	E.C_CVar = Namespace("C_CVar", { GetCVar = function(name) return E.GetCVar(name) end })
	E.WOW_PROJECT_CLASSIC, E.WOW_PROJECT_ID = 2, 18 -- (Blizzard_ProjectConstants/Camelot: WOW_PROJECT_CAMELOT = 18)
	E.GetFileIDFromPath = function() return nil end
	E.GetTimePreciseSec = function() return C.clock end
	E.C_DateAndTime = Namespace("C_DateAndTime", {
		GetCurrentCalendarTime = function() local t = os.date("*t", C.now) return { year = t.year, month = t.month, monthDay = t.day, weekday = t.wday, hour = t.hour, minute = t.min } end,
		GetSecondsUntilWeeklyReset = function() return 3 * 86400 end,
	})
	-- (1.2.3: Most Wanted reads the game's death recaps a moment after login, for the earlier deaths:
	-- the pass's session has none, as HasRecapEvents says then, with an ID or without:
	-- DeathRecapDocumentation.lua.)
	E.C_DeathRecap = Namespace("C_DeathRecap", { HasRecapEvents = function() return false end, GetRecapEvents = function() return {} end })
	-- (1.2.3 repair: and the damage meter's deaths, for the recap IDs of this player's own: none in
	-- the pass's session, DamageMeterDocumentation.lua's shapes.)
	E.C_DamageMeter = Namespace("C_DamageMeter", {
		GetCombatSessionFromType = function() return { combatSources = {}, maxAmount = 0, totalAmount = 0 } end,
		GetCombatSessionFromID = function() return { combatSources = {}, maxAmount = 0, totalAmount = 0 } end,
		GetAvailableCombatSessions = function() return {} end,
	})
	E.C_GameRules = Namespace("C_GameRules", { IsGameRuleActive = function() return false end })
	E.C_Texture = Namespace("C_Texture", { GetAtlasInfo = function(a) return { width = 64, height = 64, file = a } end })
	E.C_Item = Namespace("C_Item", {
		GetItemIconByID = function() return 134400 end,
		GetItemNameByID = function() return nil end,
		GetItemCount = function() return 0 end,
		-- (1.5.4, the Chat tab's item links: Blizzard_APIDocumentationGenerated/ItemDocumentation.lua.
		-- This client holds no item's data: GetItemInfo answers nothing, as for an item not cached,
		-- IsItemDataCachedByID false, and RequestLoadItemDataByID asks the server for it.)
		GetItemInfo = function() return nil end,
		IsItemDataCachedByID = function() return false end,
		RequestLoadItemDataByID = function(id) C.itemsRequested = C.itemsRequested or {}; C.itemsRequested[#C.itemsRequested + 1] = id end,
	})
	-- (1.4.0: LoadAddOn gives the game's two answers, loaded and a reason, as Blizzard's
	-- Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua has it and ArenaNet.lua already reads
	-- them. An addon a session's setup lists in C.missingAddOns is not installed: false, "MISSING". One
	-- it gives files for, C.addOnFiles[name](env), has them run there, as the client runs an addon's
	-- files when it loads it. Any other name loads, as before.)
	E.C_AddOns = Namespace("C_AddOns", {
		IsAddOnLoaded = function(name) return C.loadedAddOns[name] == true end,
		-- (1.4.0: another installed addon's TOC fields, as the API's Register reads its Title; the
		-- fixture's "api", AddOnsDocumentation.lua's GetAddOnMetadata(name, variable).)
		GetAddOnMetadata = function(name, field) local t = C.addOnTitles[name] return field == "Title" and t or nil end,
		LoadAddOn = Fn("C_AddOns.LoadAddOn", function(name)
			if C.missingAddOns and C.missingAddOns[name] then return false, "MISSING" end
			local first = not C.loadedAddOns[name]
			if name == "Blizzard_WorldMap" and not rawget(E, "WorldMapFrame") then
				C.absent.WorldMapFrame = nil
				C.MakeWorldMap()
				C.loadedWorldMap = true
			end
			C.loadedAddOns[name] = true
			local files = first and C.addOnFiles and C.addOnFiles[name]
			if files then files(E) end
			return true
		end),
	})
	C.loadedAddOns = { Blizzard_WorldMap = not opts.worldMapOnDemand }
	C.addOnTitles = {}
	-- (The game's default key for "Open chat", Enter: Bindings.xml's OPENCHAT.)
	-- (1.2.1: and for "Guild & Communities", J: Forever's TOGGLEGUILDTAB, MainKey.lua's Shift + it.)
	E.GetBindingKey = function(action)
		if action == "OPENCHAT" then return "ENTER" end
		if action == "TOGGLEGUILDTAB" then return "J" end
		return nil
	end
	E.GetBindingText = function(k) return k end
	-- Blizzard_Keybindings.lua reads base actions separately from overrides; each override
	-- belongs to its frame, so clearing the Chat owner must not clear the main window's shortcut.
	C.baseBindings, C.bindingOwners = opts.bindings or {}, {}
	E.GetBindingAction = function(key, overrides)
		return overrides and C.bindings and C.bindings[key] and ("CLICK " .. C.bindings[key] .. ":LeftButton") or C.baseBindings[key] or ""
	end
	E.SetOverrideBindingClick = Fn("SetOverrideBindingClick", function(owner, prio, key, button)
		C.bindings = C.bindings or {}; C.bindings[key], C.bindingOwners[key] = button, owner
	end)
	E.ClearOverrideBindings = Fn("ClearOverrideBindings", function(owner)
		C.bindings = C.bindings or {}
		for key, who in pairs(C.bindingOwners) do if who == owner then C.bindings[key], C.bindingOwners[key] = nil, nil end end
	end)
	E.ReloadUI = Fn("ReloadUI", function() C.reloaded = true end)

	-- The world map (Blizzard_MapCanvas, the gamepad map's own: a canvas in a scroll container,
	-- data providers and pin pools), on a world of five maps (the harness's, run.lua's MAPS).
	local MAPS = {
		[947] = { "Azeroth", 1, 946 }, [1415] = { "Eastern Kingdoms", 2, 947 }, [1429] = { "Elwynn Forest", 3, 1415 },
		[1453] = { "Stormwind City", 3, 1415 }, [1436] = { "Westfall", 3, 1415 },
	}
	local CHILDREN = { [947] = { 1415 }, [1415] = { 1429, 1453, 1436 } }
	local function Info(id) local m = MAPS[id]; return m and { mapID = id, name = m[1], mapType = m[2], parentMapID = m[3] } end
	local function Vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
	E.CreateVector2D = function(x, y) return Vec(x, y) end
	E.C_Map = Namespace("C_Map", {
		GetMapInfo = Info,
		GetMapChildrenInfo = function(id)
			local out = {}
			for _, c in ipairs(CHILDREN[id] or {}) do out[#out + 1] = Info(c) end
			return out
		end,
		GetBestMapForUnit = function() return 1429 end,
		GetPlayerMapPosition = function() return Vec(0.5, 0.5) end,
		GetWorldPosFromMapPos = function(id, pos) return 0, Vec(pos.x * 1000, pos.y * 1000) end,
		GetMapWorldSize = function() return 1000, 1000 end,
		GetMapRectOnMap = function() return 0, 1, 0, 1 end,
		GetMapGroupID = function() return nil end,
		GetMapGroupMembersInfo = function() return nil end,
	})
	E.Lerp = function(a, b, t) return a + (b - a) * t end
	E.Mixin = function(object, ...)
		for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do object[k] = v end end
		return object
	end
	E.CreateFromMixins = function(...) return E.Mixin({}, ...) end
	-- MapCanvas_DataProviderBase.lua: OnAdded, RemoveAllData, RefreshAllData, GetMap, OnMapChanged.
	E.MapCanvasDataProviderMixin = {
		OnAdded = function(self, map) self.owningMap = map end,
		OnRemoved = function(self) self.owningMap = nil end,
		RemoveAllData = function() end,
		RefreshAllData = function() end,
		GetMap = function(self) return self.owningMap end,
		OnMapChanged = function(self) self:RefreshAllData() end,
		OnShow = function() end, OnHide = function() end, OnEvent = function() end,
	}
	E.MapCanvasPinMixin = {
		OnLoad = function() end, SetPosition = function(self, x, y) self.x, self.y = x, y end,
		UseFrameLevelType = function() end, GetMap = function(self) return self.owningMap end,
		OnAcquired = function() end, OnReleased = function() end,
	}
	-- A pool (Blizzard_SharedXMLBase/Pools.lua, ObjectPoolMixin and CreateUnsecuredRegionPoolInstance:
	-- createFunc(pool) and resetFunc(pool, object) kept as fields, set later by its user if not given).
	local function Pool(template, createFunc, resetFunc)
		local p = { createFunc = createFunc, resetFunc = resetFunc or function(_, o) o:Hide(); o:ClearAllPoints() end,
			activeObjects = {}, inactiveObjects = {}, activeObjectCount = 0 }
		function p:GetTemplate() return template end
		function p:Acquire()
			local o = table.remove(self.inactiveObjects)
			local new = o == nil
			if new then o = self.createFunc(self) end
			self.activeObjects[o] = true
			self.activeObjectCount = self.activeObjectCount + 1
			return o, new
		end
		function p:Release(o)
			if not self.activeObjects[o] then return false end
			self.resetFunc(self, o)
			self.activeObjects[o] = nil
			self.activeObjectCount = self.activeObjectCount - 1
			table.insert(self.inactiveObjects, o)
			return true
		end
		function p:ReleaseAll() for o in pairs(self.activeObjects) do self:Release(o) end end
		function p:EnumerateActive() return pairs(self.activeObjects) end
		function p:GetNumActive() return self.activeObjectCount end
		return p
	end
	E.CreateUnsecuredRegionPoolInstance = function(template, createFunc, resetFunc) return Pool(template, createFunc, resetFunc) end
	E.CreateFramePool = function(kind, parent, template, resetFunc)
		return Pool(template, function() return E.CreateFrame(kind, nil, parent, template) end, resetFunc)
	end
	-- (opts.worldMapOnDemand: a client whose Blizzard_WorldMap loads on demand: no map until
	-- C_AddOns.LoadAddOn("Blizzard_WorldMap"). opts.brokenMapLibrary: a map with no pin pools, where
	-- the library's file stops part way as it loads.)
	local map
	function C.MakeWorldMap()
		map = Blizz("WorldMapFrame", "Frame")
		map.shown = false
		map.mapID = 1453
		map.pinPools, map.dataProviders = (not opts.brokenMapLibrary) and {} or nil, {}
		map.marks = 0
		local canvas = C.NewWidget("Frame", nil, rawget(map, "ScrollContainer") or map, nil, true)
		map.ScrollContainer = rawget(map, "ScrollContainer") or C.NewWidget("ScrollFrame", nil, map, nil, true)
		map.ScrollContainer.Child = canvas
		Method(map, "GetCanvas", function() return canvas end)
		Method(map, "GetMapID", function(self) return self.mapID end)
		-- (1.5.5, Map.lua's name labels read them.) The pins' frame levels: MapCanvasMixin:GetPinFrameLevelsManager
		-- (Blizzard_MapCanvas.lua:1029), whose table starts at 2000 (MapCanvas_PinFrameLevelsManager.lua:3) and
		-- puts each type over the last (AddFrameLevel, :62-71) in Blizzard_WorldMap.lua:259-270's order; a type
		-- it lacks reads as the default's (GetFrameLevelStart, GetFrameLevelRange, :130-144). The map's widest
		-- view: HasZoomLevels and GetScaleForMinZoom (Blizzard_MapCanvas.lua:834, 944; its scroll container's
		-- first zoom level, MapCanvas_ScrollContainerMixin.lua:742).
		local levels = { start = {}, range = {} }
		local top = 2000
		for _, kind in ipairs({ "PIN_FRAME_LEVEL_WOW_LABS_AREA", "PIN_FRAME_LEVEL_MAP_EXPLORATION", "PIN_FRAME_LEVEL_PLUNDERSTORM_CIRCLE",
			"PIN_FRAME_LEVEL_EVENT_OVERLAY", "PIN_FRAME_LEVEL_GARRISON_PLOT", "PIN_FRAME_LEVEL_FOG_OF_WAR", "PIN_FRAME_LEVEL_QUEST_BLOB",
			"PIN_FRAME_LEVEL_SCENARIO_BLOB", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", "PIN_FRAME_LEVEL_DEBUG", "PIN_FRAME_LEVEL_DIG_SITE" }) do
			local range = kind == "PIN_FRAME_LEVEL_DEBUG" and 4 or 1
			levels.start[kind], levels.range[kind], top = top + 1, range, top + range
		end
		function levels:GetFrameLevelStart(kind) return self.start[kind] or 2000 end
		function levels:GetFrameLevelRange(kind) return self.range[kind] or 1 end
		map.pinLevels = levels
		Method(map, "GetPinFrameLevelsManager", function() return levels end)
		Method(map, "HasZoomLevels", function() return true end)
		Method(map, "GetScaleForMinZoom", function() return 1 end)
		Method(map, "AddDataProvider", function(self, p) self.dataProviders[p] = true; p:OnAdded(self) end)
		Method(map, "RemoveDataProvider", function(self, p) self.dataProviders[p] = nil end)
		-- MapCanvasMixin:MarkCanvasDirty, from RemoveAllPinsByTemplate and AcquirePin: from Olympus's copy
		-- of the library, in the ledger (the gamepad map runs in its taint after it).
		local function Dirty() map.marks = map.marks + 1; if FromOlympus(2) then C.Record("WorldMapFrame:MarkCanvasDirty", "method", 2) end end
		Method(map, "RemoveAllPinsByTemplate", function(self, t) local p = self.pinPools[t]; if p then p:ReleaseAll() end Dirty() end)
		Method(map, "AcquirePin", function(self, t, ...) local p = self.pinPools[t]; local pin = p:Acquire(); pin.owningMap = self; if pin.OnAcquired then pin:OnAcquired(...) end Dirty() return pin end)
		Method(map, "RemovePin", function(self, pin) for _, p in pairs(self.pinPools) do p:Release(pin) end Dirty() end)
		Method(map, "EnumeratePinsByTemplate", function(self, t) local p = self.pinPools[t]; if p then return p:EnumerateActive() end return pairs({}) end)
		-- (A mixin method, so hooksecurefunc can follow it, as Map.lua's does.)
		rawset(map, "OnMapChanged", function(self) for p in pairs(self.dataProviders) do p:OnMapChanged() end end)
		E.WorldMapFrame = map
		if C.gameTables then
			local function Mark(t, depth) if type(t) == "table" and not C.gameTables[t] and depth < 4 then C.gameTables[t] = true for _, v in pairs(t) do Mark(v, depth + 1) end end end
			Mark(map, 1)
			C.gameValues.WorldMapFrame = map
		end
	end
	if opts.worldMapOnDemand then
		C.Absent("WorldMapFrame", "Blizzard_WorldMap loads on demand on this client")
	else
		C.MakeWorldMap()
	end
	function C.ShowMap() map:Show(); map:OnMapChanged() end
	function C.HideMap() map:Hide() end

	-- The game's popups (Blizzard_StaticPopup: four frames, the definitions in StaticPopupDialogs).
	E.StaticPopupDialogs = {}
	for i = 1, 4 do local p = Blizz("StaticPopup" .. i, "Frame"); p.shown = false end
	local function FindPopup(which, data)
		for i = 1, 4 do
			local p = E["StaticPopup" .. i]
			if p.shown and p.which == which and (data == nil or p.data == data) then return p end
		end
	end
	E.StaticPopup_Show = Fn("StaticPopup_Show", function(which, a, b, data)
		local def = E.StaticPopupDialogs[which]
		if not def then return nil end
		for i = 1, 4 do
			local p = E["StaticPopup" .. i]
			if not p.shown then
				p.which, p.data, p.textArgs = which, data, { a, b }
				p:Show()
				C.gamePopups = (C.gamePopups or 0) + 1
				return p
			end
		end
	end)
	E.StaticPopup_Hide = Fn("StaticPopup_Hide", function(which, data) local p = FindPopup(which, data); if p then p:Hide() end end)
	E.StaticPopup_FindVisible = Fn("StaticPopup_FindVisible", function(which, data) return FindPopup(which, data) end)
	E.StaticPopup_Visible = Fn("StaticPopup_Visible", function(which) local p = FindPopup(which); return p and p:GetName() or nil end)
	-- Forever 70790, UIParentPanelManager/Shared/UIParentPanelManager.lua:871-898:
	-- ShowUIPanel leaves an already shown panel alone and refuses an insecure combat
	-- call before showing it. The map shortcut must pass its own gate before this call.
	E.ShowUIPanel = Fn("ShowUIPanel", function(frame)
		if frame and not frame:IsShown() and not C.combat then frame:Show() end
	end)

	-- The game's tables Olympus may read or write: the escape list, the slash commands.
	E.UISpecialFrames = { "GameMenuFrame", "SettingsPanel", "CharacterFrame" }
	E.SlashCmdList = {}

	-- Registrations that keep their callbacks (fidelity rule 2).
	local hooks = {}
	C.secureHooks = hooks
	E.hooksecurefunc = Fn("hooksecurefunc", function(t, key, post)
		if type(t) == "string" then t, key, post = E, t, key end
		local original = rawget(t, key) or t[key]
		assert(type(original) == "function", "hooksecurefunc on something that is no function: " .. tostring(key))
		hooks[#hooks + 1] = { t = t, key = key, post = post }
		C.callbacks[#C.callbacks + 1] = { kind = "hooksecurefunc", key = key, fn = post, frame = t ~= E and t or nil }
		local wrapper = function(...)
			local r = { original(...) }
			post(...)
			return unpack(r)
		end
		HOOK_WRAPPERS[wrapper] = true -- (the client's hook is no caller: FromOlympus)
		rawset(t, key, wrapper)
	end)
	E.Menu = Namespace("Menu", {
		ModifyMenu = Fn("Menu.ModifyMenu", function(tag, fn)
			C.menus[tag] = C.menus[tag] or {}
			table.insert(C.menus[tag], fn)
			C.callbacks[#C.callbacks + 1] = { kind = "Menu.ModifyMenu", tag = tag, fn = fn }
		end),
	})
	E.TooltipDataProcessor = Namespace("TooltipDataProcessor", {
		AddTooltipPostCall = Fn("TooltipDataProcessor.AddTooltipPostCall", function(kind, fn)
			C.postCalls[kind] = C.postCalls[kind] or {}
			table.insert(C.postCalls[kind], fn)
			C.callbacks[#C.callbacks + 1] = { kind = "AddTooltipPostCall", type = kind, fn = fn }
		end),
	})
	-- (1.2: a filter on the game's system lines, kept as the game keeps it, never removed.)
	E.ChatFrame_AddMessageEventFilter = Fn("ChatFrame_AddMessageEventFilter", function(event, fn)
		C.callbacks[#C.callbacks + 1] = { kind = "AddMessageEventFilter", key = event, fn = fn }
	end)
	E.ChatFrameUtil = Namespace("ChatFrameUtil", {
		AddSenderNameFilter = Fn("ChatFrameUtil.AddSenderNameFilter", function(fn)
			table.insert(C.nameFilters, fn)
			C.callbacks[#C.callbacks + 1] = { kind = "AddSenderNameFilter", fn = fn }
		end),
		-- The game's chat box opener (ChatFrameUtil.lua:433; ChatFrame_OpenChat above is its alias,
		-- Deprecated_ChatFrame.lua:74).
		OpenChat = Fn("ChatFrameUtil.OpenChat", function(text) ChatBox(text) end),
	})

	-- Restricted and roster calls.
	E.C_FriendList = Namespace("C_FriendList", {
		SendWho = Fn("C_FriendList.SendWho", function(q) C.whos = C.whos or {}; C.whos[#C.whos + 1] = q end),
		SetWhoToUi = Fn("C_FriendList.SetWhoToUi", function(on) C.whoToUi = on end),
		GetNumWhoResults = function() return 0, 0 end,
		GetWhoInfo = function() return nil end,
		IsIgnored = function() return false end,
	})
	E.C_TradeInfo = Namespace("C_TradeInfo", { SetTradeMoney = Fn("C_TradeInfo.SetTradeMoney", function(m) C.tradeMoney = m end) })
	E.RaidWarningFrame = Blizz("RaidWarningFrame", "Frame")
	E.RaidNotice_AddMessage = Fn("RaidNotice_AddMessage", function(frame, text) C.raidNotices = (C.raidNotices or 0) + 1 end)

	-- The game's gamepad UI state, as the taint probe reads it (Diagnostics.lua).
	E.GamepadMode = { FrameControlsManager = { shownFrames = {} }, PopupHandler = { visiblePopups = {} } }
	E.GamepadSharedUtility = { InputBindingManager = { bindingSetStack = {} } }
	E.GamepadMainActionBarFrame = Blizz("GamepadMainActionBarFrame", "Frame")
	E.SmartNavigation = Blizz("SmartNavigation", "Frame")

	-- The guild windows (Blizzard_Communities and the Social window, FriendsFrame): Forever's
	-- guild window is Communities; there is no old GuildFrame (no Blizzard_GuildUI in the client's
	-- source).
	E.FriendsFrame = Blizz("FriendsFrame", "Frame")
	E.FriendsFrame.shown, E.FriendsFrame.w, E.FriendsFrame.h = false, 338, 424
	E.FriendsFrameTab1 = Blizz("FriendsFrameTab1", "Button", E.FriendsFrame)
	E.CommunitiesFrame = Blizz("CommunitiesFrame", "Frame")
	E.CommunitiesFrame.shown, E.CommunitiesFrame.w, E.CommunitiesFrame.h = false, 814, 576
	E.LFGWhoListFrame = Blizz("LFGWhoListFrame", "Frame")
	E.LFGWhoListFrame.shown = false
	-- (Forever's who list listens for the answers: Blizzard_GroupFinder_VanillaStyle/Mainline/WhoList.lua:197.)
	E.LFGWhoListFrame:RegisterEvent("WHO_LIST_UPDATE")
	E.GameMenuFrame = Blizz("GameMenuFrame", "Frame")
	E.GameMenuFrame.shown = false

	-- Unit frames (Borders.lua's rigs).
	E.PlayerFrame = Blizz("PlayerFrame", "Button")
	E.TargetFrame = Blizz("TargetFrame", "Button")
	E.FocusFrame = Blizz("FocusFrame", "Button")
	rawset(E.TargetFrame, "TargetFrameContainer", rawget(E.TargetFrame, "TargetFrameContainer") or C.NewWidget("Frame", nil, E.TargetFrame, nil, true))
	rawset(E.FocusFrame, "TargetFrameContainer", rawget(E.FocusFrame, "TargetFrameContainer") or C.NewWidget("Frame", nil, E.FocusFrame, nil, true))
	rawset(E.TargetFrame, "CheckClassification", function() end)
	rawset(E.FocusFrame, "CheckClassification", function() end)
	rawset(E.PlayerFrame, "name", rawget(E.PlayerFrame, "name") or C.NewWidget("FontString", nil, E.PlayerFrame, nil, true))
	-- Forever's PartyFrame (Blizzard_UnitFrame/Shared/PartyFrame.lua): its four member frames from a
	-- pool, MemberFrame<i> of layoutIndex i, put out again in InitializePartyMemberFrames (Borders.lua's
	-- party rigs read these fields and post-hook that method).
	E.PartyFrame = Blizz("PartyFrame", "Frame")
	rawset(E.PartyFrame, "PartyMemberFramePool", rawget(E.PartyFrame, "PartyMemberFramePool") or {})
	for i = 1, 4 do
		local m = rawget(E.PartyFrame, "MemberFrame" .. i) or C.NewWidget("Button", nil, E.PartyFrame, nil, true)
		rawset(m, "layoutIndex", i)
		rawset(E.PartyFrame, "MemberFrame" .. i, m)
	end
	rawset(E.PartyFrame, "InitializePartyMemberFrames", function() end)

	-- Nameplates (Blizzard_NamePlates): none in sight.
	E.C_NamePlate = Namespace("C_NamePlate", { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() return nil end })
	E.CompactUnitFrame_UpdateName = function() end
	E.NamePlateSetupOptions = {}

	-- Templates' helpers (Blizzard_SharedXML: PanelTemplates_*), on Olympus's own tabs.
	E.PanelTemplates_TabResize = function(tab, padding) tab:SetWidth((tab:GetFontString():GetStringWidth() or 0) + (padding or 20)) end
	E.PanelTemplates_SelectTab = function(tab) tab.selectedTab = true end
	E.PanelTemplates_DeselectTab = function(tab) tab.selectedTab = false end
	E.PanelTemplates_AnchorTabs = function() end
	E.SetItemButtonTexture = function(b, t) b.icon = t end
	E.SetItemButtonCount = function(b, n) b.count = n end
	E.SetItemButtonQuality = function(b, q) b.quality = q end

	-- The calendar, mail and trade (load on demand; shown only when a flow opens them).
	E.ToggleCalendar = Fn("ToggleCalendar", function() C.calendarToggled = (C.calendarToggled or 0) + 1 end)
	E.C_Calendar = Namespace("C_Calendar", { OpenCalendar = function() end, GetNumGuildEvents = function() return 0 end, GetGuildEventInfo = function() return nil end })
	E.SendMail = Fn("SendMail", function() end)
	E.TakeInboxMoney = Fn("TakeInboxMoney", function() end)
	E.TakeInboxItem = Fn("TakeInboxItem", function() end)
	E.AutoLootMailItem = Fn("AutoLootMailItem", function() end)
	E.MoneyInputFrame_SetCopper = Fn("MoneyInputFrame_SetCopper", function(f, c) f.copper = c end)
	E.SendMailRadioButton_OnClick = Fn("SendMailRadioButton_OnClick", function() end)
	E.ATTACHMENTS_MAX_SEND, E.ATTACHMENTS_MAX_RECEIVE = 12, 16
	E.GetInboxHeaderInfo = function() return nil end
	E.GetInboxInvoiceInfo = function() return nil end
	E.GetInboxItem = function() return nil end
	E.GetSendMailMoney = function() return 0 end
	E.GetSendMailCOD = function() return 0 end
	E.GetSendMailItem = function() return nil end
	E.GetTargetTradeMoney = function() return 0 end
	E.GetPlayerTradeMoney = function() return 0 end
	E.GetTradePlayerItemInfo = function() return nil end
	E.GetTradeTargetItemInfo = function() return nil end
	E.GetTradePlayerItemLink = function() return nil end
	E.GetTradeTargetItemLink = function() return nil end
	E.TradeFrame = Blizz("TradeFrame", "Frame"); E.TradeFrame.shown = false
	E.MailFrame = Blizz("MailFrame", "Frame"); E.MailFrame.shown = false
	E.SendMailFrame = Blizz("SendMailFrame", "Frame"); E.SendMailFrame.shown = false
	for _, n in ipairs({ "SendMailNameEditBox", "SendMailSubjectEditBox" }) do E[n] = Blizz(n, "EditBox") end
	for _, n in ipairs({ "SendMailSendMoneyButton", "SendMailCODButton" }) do E[n] = Blizz(n, "CheckButton") end
	E.SendMailMoney = Blizz("SendMailMoney", "Frame")
	C.Absent("InspectFrame", "Blizzard_InspectUI loads on demand: not loaded in the pass")
	C.Absent("PlayerSpellsFrame", "Blizzard_PlayerSpells loads on demand: not loaded in the pass")
	C.Absent("CalendarFrame", "Blizzard_Calendar loads on demand: not loaded in the pass")
	C.Absent("GuildFrame", "Forever has no old guild window: no Blizzard_GuildUI in the client's source (its guild window is Communities)")
	C.Absent("PTR_IssueReporter", "Blizzard_PTRFeedback's frame shows on test clients only (a flow of its own adds it)")
	-- The guild bank (a bank character's, Bank.lua): closed.
	E.GetNumGuildBankTabs = function() return 0 end
	E.GetCurrentGuildBankTab = function() return 1 end
	E.GetGuildBankTabInfo = function() return nil end
	E.GetGuildBankItemInfo = function() return nil end
	E.GetGuildBankItemLink = function() return nil end
	E.GetGuildBankMoney = function() return 0 end
	E.QueryGuildBankTab = function() end
	E.C_AutoComplete = Namespace("C_AutoComplete", { GetAutoCompleteRealms = function() return {} end })
	E.C_TradeSkillUI = Namespace("C_TradeSkillUI", {})
	-- (1.2: a race's name, the chat rooms' and the profile's; the addon memory the diagnostics read.)
	E.C_CreatureInfo = Namespace("C_CreatureInfo", { GetRaceInfo = function(id)
		if type(id) ~= "number" then return nil end
		return { raceName = "Race " .. id, clientFileString = "Race" .. id, raceID = id }
	end })
	E.UpdateAddOnMemoryUsage = function() end
	E.GetAddOnMemoryUsage = function() return 0 end
end

---------------------------------------------------------------------------
-- Tail calls. A function that ends in "return f(...)" leaves the stack when it calls f (LuaJIT,
-- like the client, reuses its frame), so a reach of the game's made that way would show no Olympus
-- line on the stack. The pass loads the addon's files with each such return made an ordinary call,
-- on the same lines: "return OlympusTailCall__(f(...))" returns the same values, nothing else changes
-- but the depth of the stack.
---------------------------------------------------------------------------

local KEYWORDS = Set("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")
local function Tokens(src)
	local out, i, n = {}, 1, #src
	while i <= n do
		local c = src:sub(i, i)
		if c:find("%s") then
			i = i + 1
		elseif src:sub(i, i + 1) == "--" then
			local eq = src:match("^%[(=*)%[", i + 2)
			if eq then
				local close = src:find("]" .. eq .. "]", i, true)
				i = (close or n) + #eq + 2
			else
				local nl = src:find("\n", i, true)
				i = (nl or n) + 1
			end
		elseif c == "[" and src:match("^%[=*%[", i) then
			local eq = src:match("^%[(=*)%[", i)
			local close = src:find("]" .. eq .. "]", i, true)
			local e = (close or n) + #eq + 1
			out[#out + 1] = { kind = "string", s = i, e = e }
			i = e + 1
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then j = j + 2 elseif d == c then break else j = j + 1 end
			end
			out[#out + 1] = { kind = "string", s = i, e = j }
			i = j + 1
		elseif c:find("[%a_]") then
			local j = src:find("[^%w_]", i) or (n + 1)
			local word = src:sub(i, j - 1)
			out[#out + 1] = { kind = KEYWORDS[word] and "keyword" or "name", text = word, s = i, e = j - 1 }
			i = j
		elseif c:find("%d") or (c == "." and src:sub(i + 1, i + 1):find("%d")) then
			local j = i
			if src:sub(i, i + 1):lower() == "0x" then j = i + 2; while src:sub(j, j):find("[%x]") do j = j + 1 end
			else
				while src:sub(j, j):find("[%d%.]") do j = j + 1 end
				if src:sub(j, j):find("[eE]") then j = j + 1; if src:sub(j, j):find("[%+%-]") then j = j + 1 end; while src:sub(j, j):find("%d") do j = j + 1 end end
			end
			out[#out + 1] = { kind = "number", s = i, e = j - 1 }
			i = j
		else
			local three, two = src:sub(i, i + 2), src:sub(i, i + 1)
			local op = (three == "..." and three) or ((two == ".." or two == "==" or two == "~=" or two == "<=" or two == ">=" or two == "::") and two) or c
			out[#out + 1] = { kind = "op", text = op, s = i, e = i + #op - 1 }
			i = i + #op
		end
	end
	return out
end
local BINARY = Set("and or not + - * / % ^ .. == ~= < > <= >= #")
local ENDS = Set("end else elseif until")
local function NoTailCalls(src)
	local tokens = Tokens(src)
	local inserts = {} -- { position, text }
	for k, t in ipairs(tokens) do
		if t.kind == "keyword" and t.text == "return" then
			local depth, last, ok = 0, nil, true
			local j = k + 1
			local first = tokens[j]
			while tokens[j] do
				local u = tokens[j]
				if u.kind == "op" and (u.text == "(" or u.text == "{" or u.text == "[") then depth = depth + 1
				elseif u.kind == "op" and (u.text == ")" or u.text == "}" or u.text == "]") then depth = depth - 1
				elseif depth == 0 and ((u.kind == "keyword" and (ENDS[u.text] or u.text == "return")) or (u.kind == "op" and u.text == ";")) then break
				elseif depth == 0 and ((u.kind == "op" and (u.text == "," or BINARY[u.text])) or (u.kind == "keyword" and (BINARY[u.text] or u.text == "function"))) then ok = false end
				last = j
				j = j + 1
			end
			-- A call: starts with a name or "(", ends with its arguments ("(...)", a string, a table),
			-- and its last group is not the whole expression in parentheses.
			if ok and first and last and last >= k + 2 and (first.kind == "name" or (first.kind == "op" and first.text == "(")) then
				local tail = tokens[last]
				local isCall = tail.kind == "string" or (tail.kind == "op" and (tail.text == ")" or tail.text == "}"))
				if isCall and tail.kind == "op" then
					-- The group the last token closes: where it opens.
					local d, m = 0, last
					while m > k do
						local u = tokens[m]
						if u.kind == "op" and (u.text == ")" or u.text == "}" or u.text == "]") then d = d + 1
						elseif u.kind == "op" and (u.text == "(" or u.text == "{" or u.text == "[") then d = d - 1; if d == 0 then break end end
						m = m - 1
					end
					if m == k + 1 then isCall = false end -- "(expression)": not a call
				end
				if isCall then
					inserts[#inserts + 1] = { first.s, "OlympusTailCall__(" }
					inserts[#inserts + 1] = { tail.e + 1, ")" }
				end
			end
		end
	end
	table.sort(inserts, function(a, b) return a[1] > b[1] end)
	for _, ins in ipairs(inserts) do src = src:sub(1, ins[1] - 1) .. ins[2] .. src:sub(ins[1]) end
	return src
end

---------------------------------------------------------------------------
-- The addon in the client: its files in the TOC's order, the saved variables, the login.
---------------------------------------------------------------------------

local TOC = {}
for line in assert(io.open(ADDON_DIR .. "Olympus.toc")):lines() do
	local f = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
	if f then TOC[#TOC + 1] = (f:gsub("\\", "/")) end
end

-- A client with the addon loaded (opts.gamepad: the gamepad UI on from the start; opts.saved: the
-- saved variables, OlympusDB). Returns the client and the addon's namespace.
local function Boot(opts)
	opts = opts or {}
	local C = NewClient(opts)
	World(C, opts)
	if opts.setup then opts.setup(C) end
	C.SealGame()
	local ns = {}
	C.ns = ns
	if opts.saved then rawset(C.env, "OlympusDB", opts.saved) end
	rawset(C.env, "OlympusTailCall__", function(...) return ... end)
	for _, file in ipairs(TOC) do
		local f = assert(io.open(ADDON_DIR .. file, "rb"))
		local src = f:read("*a")
		f:close()
		local chunk = assert(loadstring(NoTailCalls(src), "@" .. ADDON_DIR .. file))
		setfenv(chunk, C.env)
		-- (A file that fails as it loads: the client reports it and loads the next one.)
		local ok, err = pcall(chunk, "Olympus", ns)
		if not ok then C.loadErrors[#C.loadErrors + 1] = file .. ": " .. tostring(err); pcall(C.handler, err) end
	end
	-- (opts.realmFrom(ns): a realm named by the addon itself, the Treasurer's group's for the dues.)
	if opts.realmFrom then C.realmName = opts.realmFrom(ns) end
	C.Fire("ADDON_LOADED", "Olympus")
	return C, ns
end

-- The login: PLAYER_LOGIN, the loading screen, then the timers for a while.
local function Login(C, seconds)
	C.loggedIn = true
	C.Fire("PLAYER_LOGIN")
	C.Fire("PLAYER_ENTERING_WORLD", true, false)
	C.Advance(seconds or 30)
end

---------------------------------------------------------------------------
-- What a session checks.
---------------------------------------------------------------------------

-- A record the gamepad UI allows: an entry of the registry whose guard lets it through there.
local function AllowedUnderPad(r)
	if not r.ids or r.kind == "blocked" then return false end
	if r.gateWork then return true end -- (the gate's own work at a switch: see GATE_WORK)
	for _, id in ipairs(r.ids) do
		local e = REGISTRY[id]
		if e and (e.guard == "own" or e.guard == "exempt" or e.guard == "isolated" or (e.guard == "click" and r.click)) then return true end
	end
	return false
end
local function Describe(r)
	return ("%s (%s) from Olympus/%s:%s, tagged %s%s%s"):format(r.sym, r.kind, tostring(r.file), tostring(r.line),
		r.ids and table.concat(r.ids, ",") or "nothing", r.click and ", in a click" or "", r.gateWork and (", the gate's " .. r.gateWork) or "")
end
-- Every record must name its entry (the audit's tags at runtime); with the gamepad UI on, only an
-- allowed one; never a restricted call refused.
local function Check(list, what)
	local bad = {}
	for _, r in ipairs(list) do
		if not r.ids then bad[#bad + 1] = "no registry entry: " .. Describe(r)
		elseif r.kind == "blocked" then bad[#bad + 1] = "refused outside a click: " .. Describe(r)
		elseif r.gamepad and not AllowedUnderPad(r) then bad[#bad + 1] = "with the gamepad UI: " .. Describe(r) end
	end
	if #bad > 0 then error(("%s: %d reach%s of the game's UI\n         %s\n%s"):format(what, #bad, #bad == 1 and "" or "es",
		table.concat(bad, "\n         "), list[1] and list[1].trace or ""), 2) end
end
-- With the gamepad UI on: no record at all but the allowed (own, exempt, a click's).
local function OnlyAllowed(list, what) Check(list, what) end
local function Ids(list)
	local out = {}
	for _, r in ipairs(list) do for _, id in ipairs(r.ids or {}) do out[id] = (out[id] or 0) + 1 end end
	return out
end

local function Errors(C)
	local out = {}
	for _, e in ipairs(C.ns.db and C.ns.db.errors or {}) do out[#out + 1] = tostring(e.where) .. ": " .. tostring(e.msg) .. "\n" .. tostring(e.stack) end
	return out
end
local function NoErrors(C, what)
	local errs = Errors(C)
	if #errs > 0 then error((what or "") .. ": " .. #errs .. " error(s) caught by the addon: " .. errs[1], 2) end
	if #C.isolatedErrors > 0 then error((what or "") .. ": an error in a callback the game called: " .. C.isolatedErrors[1], 2) end
	assert(next(C.unmodelled) == nil, "unmodelled: " .. (next(C.unmodelled) or ""))
end

-- Forever 70790, Blizzard_GamepadSmartNavigation/Utility.lua:263-276. This is candidate
-- discovery, not execution of a handler: the native taint boundary only returns a boolean.
local function SmartNavigationCanFocus(C, frame)
	local isButton = frame:IsObjectType("Button") or frame:IsObjectType("EditBox")
	local canFocus = rawget(frame, "smartNavigationCanFocus") == true
	if not isButton then
		isButton = C.env.securecallfunction(function()
			return frame:GetScript("OnMouseUp") ~= nil or frame:GetScript("OnMouseDown") ~= nil
		end)
	end
	return (isButton or canFocus) and frame:GetSize() and not rawget(frame, "smartNavigationIgnoredContainerFrame")
end

-- The frames the gamepad UI navigates with Smart Navigation. Flattening groups is sufficient
-- for this no-addon-candidate check: subsections and scroll groups are all traversed by the game.
local MANAGED = { "CommunitiesFrame", "GuildFrame", "FriendsFrame", "WorldMapFrame", "PTR_IssueReporter", "GameMenuFrame" }
-- (With every one of those frames shown, as the game would show them, then put back.)
local function NavigableOlympus(C, show)
	local out = {}
	local shown = {}
	if show then
		for _, n in ipairs(MANAGED) do
			local f = rawget(C.env, n)
			if f and not f:IsShown() then f:Show(); shown[#shown + 1] = f end
		end
	end
	local function Walk(f)
		for _, c in ipairs(f.children) do
			if c.olympus and c:IsVisible() and SmartNavigationCanFocus(C, c) then
				out[#out + 1] = c.name or c.kind
			end
			Walk(c)
		end
	end
	for _, n in ipairs(MANAGED) do
		local f = rawget(C.env, n)
		if f and f:IsVisible() then Walk(f) end
	end
	for _, f in ipairs(shown) do f:Hide() end
	return out
end

-- The game's own state an addon could leave written: the escape list, the slash commands, the
-- popups and their definitions, the chat box, the error handler, and every global of the game's.
local function Snapshot(C)
	local E = C.env
	local s = { globals = {}, special = {}, slash = {}, dialogs = {}, popups = {} }
	for k, v in pairs(E) do if type(k) == "string" and not AUDIT.Own(k) then s.globals[k] = v end end
	for i, n in ipairs(rawget(E, "UISpecialFrames") or {}) do s.special[i] = n end
	for k in pairs(rawget(E, "SlashCmdList") or {}) do s.slash[k] = true end
	for k in pairs(rawget(E, "StaticPopupDialogs") or {}) do if not tostring(k):find("^OLYMPUS_") then s.dialogs[k] = true end end
	for i = 1, 4 do local p = rawget(E, "StaticPopup" .. i); s.popups[i] = p and p.shown end
	s.chat = rawget(E, "LAST_ACTIVE_CHAT_EDIT_BOX")
	s.handler = C.handler
	return s
end
local function Diff(a, b)
	local out = {}
	for k, v in pairs(b.globals) do if a.globals[k] ~= v then out[#out + 1] = "global " .. k end end
	for k in pairs(a.globals) do if b.globals[k] == nil then out[#out + 1] = "global " .. k .. " gone" end end
	if table.concat(a.special, ",") ~= table.concat(b.special, ",") then out[#out + 1] = "UISpecialFrames: " .. table.concat(b.special, ",") end
	for k in pairs(b.slash) do if not a.slash[k] then out[#out + 1] = "SlashCmdList." .. k end end
	for k in pairs(b.dialogs) do if not a.dialogs[k] then out[#out + 1] = "StaticPopupDialogs." .. k end end
	for i = 1, 4 do if a.popups[i] ~= b.popups[i] then out[#out + 1] = "StaticPopup" .. i end end
	if a.chat ~= b.chat then out[#out + 1] = "LAST_ACTIVE_CHAT_EDIT_BOX" end
	if a.handler ~= b.handler then out[#out + 1] = "the error handler" end
	table.sort(out)
	return out
end

---------------------------------------------------------------------------
-- The flows: what a player does, the game's way (clicks are the player's).
---------------------------------------------------------------------------

local function Main(C)
	for _, n in ipairs({ "OlympusFrameHD", "OlympusFrame", "OlympusFrameHDBasic", "OlympusFrameBasic" }) do
		local f = rawget(C.env, n)
		if f and f:IsShown() then return f end
	end
end
-- The minimap button opens the window, every tab gets a click, its X closes it.
local function WindowFlow(C)
	-- (Open already, from another flow: its X first.)
	local open = Main(C)
	if open then C.Click(rawget(open, "CloseButton")); C.Advance(0.5) end
	local b = rawget(C.env, "OlympusMinimapButton")
	assert(b and b:IsVisible(), "the minimap button shows")
	C.Click(b)
	C.Advance(1)
	local f = assert(Main(C), "the minimap button opened the window")
	local tabs = {}
	for _, t in ipairs(rawget(f, "tabs") or {}) do tabs[#tabs + 1] = t end
	for _, t in ipairs(rawget(f, "sideTabs") or {}) do tabs[#tabs + 1] = t end
	for _, t in ipairs(tabs) do
		if t:IsVisible() then C.Click(t); C.Advance(1) end
	end
	C.Click(assert(rawget(f, "CloseButton"), "its X"))
	C.Advance(1)
	assert(not Main(C), "its X closed it")
	return #tabs
end

-- Every one of Olympus's dialogs, shown the addon's way (ns.ShowDialog). In Olympus's own window
-- (the gamepad UI's), each of its buttons clicked by the player, the dialog shown again for each;
-- the game's popup (mouse and keyboard) hidden again.
local function DialogsFlow(C)
	local ns, n, clicks = C.ns, 0, 0
	local keys = {}
	for k in pairs(C.env.StaticPopupDialogs) do if tostring(k):find("^OLYMPUS_") then keys[#keys + 1] = k end end
	table.sort(keys)
	for _, which in ipairs(keys) do
		for b = 1, 3 do
			local shown = ns.ShowDialog(which, "Someone", "Something", { name = "Someone-Realm" })
			if shown and b == 1 then n = n + 1 end
			local own = type(shown) == "table" and rawget(shown, "olympus") and rawget(shown, "buttons")
			local button = own and own[b]
			if button and button:IsVisible() then
				C.Click(button)
				clicks = clicks + 1
			end
			ns.HideDialog(which)
			C.Advance(0.1)
			if not own then break end
		end
	end
	return n, #keys, clicks
end

-- The author's King's view (King.SetDevView, a test character's: ns.devWorkshop): the window with
-- the King's tabs too (Throne, Vox) and the Workshop, each clicked.
local function KingViewFlow(C)
	local ns = C.ns
	ns.devWorkshop = true
	ns.King.SetDevView(true)
	assert(ns.King.Preview(), "the King's view")
	local tabs = WindowFlow(C)
	ns.King.SetDevView(false)
	ns.devWorkshop = nil
	return tabs
end

-- The game shows its guild windows, then hides them (their OnShow and OnHide, and Olympus's hooks).
local function GuildWindowsFlow(C)
	for _, name in ipairs({ "CommunitiesFrame", "FriendsFrame" }) do
		local f = rawget(C.env, name)
		if f then f:Show(); C.Advance(0.5); f:Hide(); C.Advance(0.5) end
	end
end

-- The world map: shown, its map changed, zoomed and sized, hidden.
local function MapFlow(C)
	local map = C.env.WorldMapFrame
	C.ShowMap()
	map.mapID = 1429
	map:OnMapChanged()
	local sc = map.ScrollContainer
	C.RunScript(sc, "OnMouseWheel", 1)
	C.RunScript(sc, "OnSizeChanged", 800, 600)
	C.Advance(1)
	C.HideMap()
	C.Advance(1)
end

-- A player's tooltip: the game's post-calls, isolated, with the tooltip and its data.
local function TooltipFlow(C)
	local tip = C.env.GameTooltip
	-- (Inspected before: the tabard line Olympus adds to his tooltip, with mouse and keyboard.)
	C.ns.Inspect.Record("Someone-Realm", "Olympus II", "WARRIOR", 60, nil, true)
	C.units.mouseover = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	tip:SetOwner(C.env.UIParent, "ANCHOR_CURSOR")
	tip:SetUnit("mouseover")
	local unit = C.env.Enum.TooltipDataType.Unit
	for _, fn in ipairs(C.postCalls[unit] or {}) do C.Isolated(fn, tip, { type = unit, guid = "Player-1-00000002" }) end
	for _, h in ipairs(tip.hooks.OnTooltipSetUnit or {}) do C.Isolated(h, tip) end
	local lines = #(tip.lines or {})
	tip:Hide()
	C.units.mouseover = nil
	return lines, #(C.postCalls[unit] or {}) + #(tip.hooks.OnTooltipSetUnit or {})
end

-- The game's right-click player menus: each callback, with a model of the menu's root
-- (Blizzard_Menu's root description: CreateTitle, CreateButton, CreateDivider).
local function MenuFlow(C)
	local made = 0
	local function Element()
		local d = {}
		function d.SetTooltip() end
		function d.SetEnabled() end
		function d.AddInitializer() end
		return d
	end
	local root = {}
	function root.CreateTitle() made = made + 1 return Element() end
	function root.CreateButton() made = made + 1 return Element() end
	function root.CreateDivider() return Element() end
	C.units.target = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	local ran = 0
	for tag, list in pairs(C.menus) do
		for _, fn in ipairs(list) do
			ran = ran + 1
			C.Isolated(fn, {}, root, { unit = "target", name = "Someone", server = "Realm" })
		end
	end
	C.units.target = nil
	return made, ran
end

-- A line in the game's chat: each sender name filter, as ChatFrameUtil.ProcessSenderNameFilters calls it.
local function ChatLineFlow(C)
	local out, ran = nil, 0
	for _, fn in ipairs(C.nameFilters) do
		ran = ran + 1
		C.Isolated(function() out = fn("CHAT_MSG_CHANNEL", "Someone", "hello", "Someone-Realm") or out end)
	end
	return out, ran
end

-- A slash command typed in the game's chat box (fidelity rule 3: called directly, then the box
-- closes in the caller's taint): with the gamepad UI on, any Olympus code run that way is a taint event.
local function TypeSlash(C, line)
	local cmd, msg = line:match("^(/%S+)%s*(.-)$")
	local E = C.env
	-- ChatFrameUtil.ImportListToHash: every SlashCmdList key's SLASH_<KEY>n globals.
	for key, fn in pairs(E.SlashCmdList) do
		local i = 1
		while true do
			local s = rawget(E, "SLASH_" .. key .. i)
			if not s then break end
			if s:lower() == cmd:lower() then
				local mark = C.Mark()
				local ran = false
				local hook = debug.gethook()
				debug.sethook(function()
					local info = debug.getinfo(2, "S")
					if info and OlympusFile(info.source) then ran = true end
				end, "c")
				local ok, err = pcall(fn, msg, E.ChatFrame1EditBox)
				debug.sethook(hook)
				if ran and C.style == 1 then C.taint[#C.taint + 1] = { line = line, ledger = C.Since(mark) } end
				if not ok then error(err, 0) end
				return true
			end
			i = i + 1
		end
	end
	return false -- (the game's own: "Type /help for a list of commands.")
end

-- A player who answered the first-open page (Consent.lua) before: the window opens on its tabs.
-- (1.2.5.1: and the Olympus Accord accepted, as every account using Olympus has it; a fresh session,
-- opts.fresh, is asked it first.)
local function Answered()
	return { addonChat = true, royalInspection = true, rollCall = true, layerHelp = true, treasurerShares = true,
		chatWarned = { A = true, C = true, L = true }, shareLocation = true, accord = { v = 1, yes = true, at = 0 } }
end
local function Session(gamepad, opts)
	opts = opts or {}
	opts.gamepad = gamepad
	if opts.saved == nil and not opts.fresh then opts.saved = Answered() end
	local C, ns = Boot(opts)
	if opts.brokenMapLibrary then
		C.brokeMapLibrary = #C.loadErrors == 1 and C.loadErrors[1]:find("HereBeDragons%-Pins") ~= nil
		C.loadErrors = {}
	end
	Login(C)
	assert(#C.loadErrors == 0, "a file failed to load: " .. tostring(C.loadErrors[1]))
	return C, ns
end

-- The player's click on one of Olympus's buttons that runs fn (the hardware event).
local function InClick(C, fn)
	C.clicking = true
	local ok, err = pcall(fn)
	C.clicking = false
	if not ok then error(err, 0) end
end

test("gamepad decree map shortcut: editors alone, live permissions, combat and both input styles", function()
	for _, initialPad in ipairs({ false, true }) do
		local C, ns = Session(initialPad)
		local function Link()
			for _, line in ipairs(ns.Views.Build("decrees")) do
				if line.mapNamesShortcut then return line end
			end
		end
		eq(Link(), nil, "ordinary members get no editing shortcut")
		ns.AUTHOR, ns.AUTHOR_REALM = ns.ShortName(ns.me), ns.realm
		eq(ns.Workshop.IsAuthor(), true)
		eq(Link(), nil, "developer identity alone grants no map editing")
		ns.rdb.council = { names = { [ns.ShortName(ns.me):lower()] = ns.ShortName(ns.me) }, realm = ns.realm }
		local row = assert(Link(), "signed council gets the Decrees link")
		local help = false
		for _, line in ipairs(ns.Views.Build("decrees")) do
			if line.text and line.text:find(ns.L.MAPNAME_DECREE_HELP, 1, true) then help = true end
		end
		eq(help, true, "the instructions are visible in Decrees")
		C.env.WorldMapFrame:Hide()
		if initialPad then
			eq(row.onClick, nil, "gamepad mode does not offer a native map action")
			eq(ns.Map.OpenNamesMap(), false)
			eq(C.env.WorldMapFrame:IsShown(), false)
			C.Switch(false); C.Advance(1)
		end
		row = assert(Link()); assert(row.onClick)
		C.combat = true
		eq(Link().onClick, nil, "combat disables the link")
		local combatMark = C.Mark()
		InClick(C, row.onClick)
		for _, reach in ipairs(C.Since(combatMark)) do
			assert(reach.sym ~= "ShowUIPanel", "combat must not call the protected panel opener")
		end
		eq(C.env.WorldMapFrame:IsShown(), false, "an earlier click handler rechecks combat")
		C.combat = false
		ns.rdb.council = nil
		InClick(C, row.onClick)
		eq(C.env.WorldMapFrame:IsShown(), false, "revoked council cannot use a stale row")
		ns.rdb.council = { names = { [ns.ShortName(ns.me):lower()] = ns.ShortName(ns.me) }, realm = ns.realm }
		InClick(C, assert(Link()).onClick)
		eq(C.env.WorldMapFrame:IsShown(), true)
		eq(ns.Map.nameEditor, nil, "opening the map does not enter the name editor")
		assert(not ns.Map.nameHit or not ns.Map.nameHit:IsShown(), "no click-to-edit surface enabled")
		eq(next(ns.rdb.mapNames or {}), nil, "no name published")
		C.env.WorldMapFrame:Hide()
		C.Switch(true); C.Advance(1)
		eq(Link().onClick, nil)
		InClick(C, row.onClick)
		eq(C.env.WorldMapFrame:IsShown(), false, "a stale mouse handler is inert with gamepad")
		C.Switch(false); C.Advance(1)
		InClick(C, assert(Link()).onClick)
		eq(C.env.WorldMapFrame:IsShown(), true)
		Check(C.ledger, "Decrees map shortcut")
		NoErrors(C, "Decrees map shortcut")
	end
	GP.Covers("map-overlay")
end)

for _, initialPad in ipairs({ false, true }) do
	test("gamepad map names: " .. (initialPad and "gamepad" or "mouse") .. " login, geographic selection, preview, confirmation and both switches", function()
		local C, ns = Session(initialPad)
		local M, N, E = ns.Map, ns.MapNames, C.env
		ns.rdb.council = { names = { [ns.ShortName(ns.me):lower()] = ns.ShortName(ns.me) }, realm = ns.realm }
		E.WorldMapFrame.mapID = 1415 -- the model stores the map selection here (MapFlow uses the same field)
		E.WorldMapFrame:OnMapChanged()
		E.WorldMapFrame:Show()
		local canvas = E.WorldMapFrame:GetCanvas()
		canvas:SetSize(1000, 700) -- visible canvas geometry for the actual click-to-coordinate path
		E.GetCursorPosition = function()
			local scale = canvas:GetEffectiveScale()
			return (canvas:GetLeft() + 413) * scale, (canvas:GetTop() - 456) * scale
		end
		if initialPad then
			M.SetNameEditing(true); M.OpenNameEditor(1429)
			eq(M.nameEditor, nil, "gamepad login creates no map editor")
			eq(M.nameButton, nil, "gamepad login creates no edit button")
			C.Switch(false); C.Advance(1)
		end
		M.LayoutNames()
		assert(M.nameButton and M.nameButton:IsShown(), "small map editor button for current council")
		C.Click(M.nameButton)
		assert(M.nameHit and M.nameHit:IsShown(), "arbitrary artwork names can be selected")
		local place
		for _, label in ipairs(M.nameLabels) do if label.key == 1429 then place = label end end
		assert(place and place:IsShown(), "a geographic label can be clicked")
		-- (1.5.5) Over the map's explored art, the pin of PIN_FRAME_LEVEL_MAP_EXPLORATION (Map.ArtLevel).
		local art = rawget(E.WorldMapFrame, "pinLevels").start.PIN_FRAME_LEVEL_MAP_EXPLORATION
		assert(place:GetFrameLevel() > art, ("label level %d over the explored art's %d"):format(place:GetFrameLevel(), art))
		C.Click(place)
		local editor = assert(M.nameEditor)
		assert(editor:IsShown()); eq(editor.key, 1429)
		editor.input:SetText("Council's garden")
		eq(N.Name(1429), "Elwynn Forest", "typing publishes nothing")
		C.Click(editor.previewButton)
		assert(editor.preview); eq(N.Name(1429), "Elwynn Forest", "preview publishes nothing")
		assert(editor.result:GetText():find("all Olympus", 1, true), "explicit audience warning")
		C.Click(editor.publish)
		eq(N.Name(1429), "Council's garden")
		eq(ns.Zones.NameForKey("m1429"), "Council's garden", "pin/list display resolves the same shared name")
		editor:Hide()
		C.Click(M.nameHit)
		assert(type(editor.key) == "string" and editor.key:find("^p1415:"), "artwork click selects a stable map coordinate")
		editor.input:SetText("River crossing")
		C.Click(editor.previewButton); C.Click(editor.publish)
		eq(N.Name(editor.key), "River crossing")
		C.Switch(true); C.Advance(1)
		eq(M.nameButton:IsShown(), false); eq(M.nameHit:IsShown(), false); eq(editor:IsShown(), false)
		for _, label in ipairs(M.nameLabels) do eq(label:IsShown(), false, "all geographical labels parked") end
		M.SetNameEditing(true); M.OpenNameEditor(1429)
		eq(editor:IsShown(), false, "stale callbacks cannot reopen editor under gamepad")
		C.Switch(false); C.Advance(1)
		eq(M.nameButton:IsShown(), true); eq(M.nameHit:IsShown(), false, "switch back leaves edit mode off")
		local visible = 0
		for _, label in ipairs(M.nameLabels) do if label:IsShown() then visible = visible + 1 end end
		eq(visible, 2, "shared geographical and point names restored")
		ns.rdb.council.names = {}
		M.LayoutNames(); eq(M.nameButton:IsShown(), false, "permission loss hides editor")
		for _, label in ipairs(M.nameLabels) do eq(label:IsShown(), false, "revoked author's names no longer shown") end
		GP.Covers("map-overlay")
		Check(C.ledger, "map-name editor"); NoErrors(C, "map-name editor")
	end)
end

for _, initialPad in ipairs({ false, true }) do
	test("gamepad innkeeper gossip: " .. (initialPad and "gamepad" or "mouse") .. " login and mode switches without native capabilities", function()
		local C, ns = Session(initialPad)
		local gossip = assert(ns.InnkeeperGossip)
		GP.Covers("innkeeper-gossip")
		for _, mode in ipairs({ initialPad, not initialPad, initialPad }) do
			C.Switch(mode); C.Advance(1)
			eq(ns.Gate.Allowed("innkeeper-gossip"), not mode)
			gossip.OnShow(); C.Advance(1)
			eq(gossip.State().mode, "inactive")
			eq(gossip.State().saved, nil, "missing native API never leaves borrowed geometry")
			eq(gossip.Open(), false); eq(gossip.Confirm(), false)
			ns.Gate.Park("innkeeper-gossip")
			eq(gossip.State().row, nil, "no native frame created without source-backed capabilities")
		end
		Check(C.ledger, "innkeeper gossip optional capabilities"); NoErrors(C, "innkeeper gossip")
	end)
end

-- (1.2.1, a player's report: the addon-only window opened by itself at every conversation with an
-- innkeeper. It now opens for a player who asked for the innkeeper on the Bones page, once an ask.)
test("gamepad innkeeper offer: an actual NPC keeps the addon-only lesson offer across input switches, once the player asked for it", function()
	local C, ns = Session(true)
	local inn
	for _, place in ipairs(ns.Places.list) do if place.id == "inn_goldshire" then inn = place end end
	assert(inn)
	C.position = { cont = inn.cont, wx = inn.wx, wy = inn.wy }
	C.resting = true
	C.units.npc = { name = "Localized Innkeeper", realm = C.realmName, guid = "Creature-0-1-0-1-" .. inn.npc .. "-00001" }
	local shown = 0
	ns.FarkleTable.ShowUI = function(what, id, name)
		eq(what, "innkeeper"); eq(id, nil); eq(name, "Localized Innkeeper")
		shown = shown + 1; return true
	end
	for _, pad in ipairs({ true, false, true }) do
		C.Switch(pad); C.Advance(1)
		local before = shown
		ns.InnkeeperGossip.OnShow(); C.Advance(1)
		eq(shown, before, "a visit alone opens nothing")
		ns.FarkleTable.WantKeeper()
		ns.InnkeeperGossip.OnShow(); C.Advance(1)
		eq(shown, before + 1, "the existing addon dialogue remains available once asked for")
		eq(ns.InnkeeperGossip.State().row, nil, "no native gossip child is needed")
	end
	C.units.npc = nil
	ns.FarkleTable.WantKeeper()
	ns.InnkeeperGossip.OnShow(); C.Advance(1)
	eq(shown, 3, "an inn alone never impersonates the NPC")
	GP.Covers("innkeeper-gossip")
	Check(C.ledger, "addon-only innkeeper offer"); NoErrors(C, "innkeeper offer")
end)

for _, initialPad in ipairs({ false, true }) do
	test("gamepad native Guild chat: " .. (initialPad and "gamepad" or "mouse") .. " login, user send, server echo and input switches", function()
		local C, ns = Session(initialPad)
		GP.Covers("roster-actions")
		ns.db.chatRooms = true
		local R = ns.ChatRooms
		for _, mode in ipairs({ initialPad, not initialPad, initialPad }) do
			C.Switch(mode); C.Advance(10)
			local before = #R.History("guild")
			local sent = #(C.said or {})
			InClick(C, function() assert(R.Send("guild", "native guild line")) end)
			eq(#C.said, sent + 1); eq(C.said[#C.said][2], "GUILD")
			eq(#R.History("guild"), before, "no optimistic echo")
			C.Fire("CHAT_MSG_GUILD", "native guild line", ns.me)
			eq(#R.History("guild"), before + 1)
			C.Fire("CHAT_MSG_GUILD", "native guild line", ns.me)
			eq(#R.History("guild"), before + 2, "two actual identical native events remain two messages")
			C.Advance(2); eq(#C.said, sent + 1, "no timer sends native guild text")
		end
		local before = #R.History("guild")
		ns.db.chatRooms = false
		C.Fire("CHAT_MSG_GUILD", "not consented", "Someone-Realm")
		ns.db.chatRooms = true
		eq(#R.History("guild"), before, "consent-off event is not retained")
		Check(C.ledger, "native Guild chat"); NoErrors(C, "native Guild chat")
	end)
end

-- 1.4.0: a Legate's "Invite online member to raid" (WarSquads.lua -> PartyGuard.InviteGuildmate):
-- the game's party invite inside the player's click on Olympus's own row, in both modes and across
-- switches (the gate's "roster-actions", a "click" entry); never a /who, never outside a guildmate.
for _, initialPad in ipairs({ false, true }) do
	test("gamepad Legate raid invite: " .. (initialPad and "gamepad" or "mouse") .. " login, the click's invite in both modes, nothing else of the game's", function()
		local C, ns = Session(initialPad)
		GP.Covers("roster-actions")
		C.Advance(10)
		assert(ns.Roster.Fresh(), "the session's roster is in")
		for _, mode in ipairs({ initialPad, not initialPad, initialPad }) do
			C.Switch(mode); C.Advance(1)
			local mark, sent = C.Mark(), #C.sent
			C.invited = nil
			local done
			InClick(C, function() done = ns.PartyGuard.InviteGuildmate("Zeusmaster-Realm") end)
			eq(done, true, "a guildmate on the roster")
			eq(C.invited, "Zeusmaster", "the game's own invite, from the click")
			C.invited = nil
			InClick(C, function() done = ns.PartyGuard.InviteGuildmate("Stranger-Realm") end)
			eq(done, false); eq(C.invited, nil, "nobody off the roster")
			eq(#C.sent, sent, "no addon message"); eq(#C.blocked, 0)
			Check(C.Since(mark), "the Legate's invite")
		end
		NoErrors(C, "the Legate's invite")
	end)
end

for _, initialPad in ipairs({ false, true }) do
	test("gamepad innkeeper guidance: " .. (initialPad and "gamepad" or "mouse") .. " login, switches, native bearing and cleanup", function()
		-- Isolate this session's jitter from earlier tests without changing global math
		-- or disabling the real Authority/Workshop timers. Their midpoint deadlines fall
		-- after this30-33.5s measurement; every guidance action/timer still must send nothing.
		local C, ns = Session(initialPad, { setup = function(client)
			local sessionMath = {}
			for key, value in pairs(client.env.math) do sessionMath[key] = value end
			sessionMath.random = function(lo, hi)
				if hi then return math.floor((lo + hi) / 2) end
				if lo then return math.max(1, math.floor((1 + lo) / 2)) end
				return 0.5
			end
			client.env.math, client.env.random = sessionMath, sessionMath.random
		end })
		local E, arrow = C.env, assert(ns.InnkeeperArrow, "the TOC loads local guidance")
		GP.Covers("minimap")
		local inn
		for _, place in ipairs(ns.Places.list) do if place.id == "inn_goldshire" then inn = place end end
		assert(inn, "actual registered inn")
		eq(arrow.State().active, false); eq(arrow.State().ticker, nil, "no idle guidance ticker at login")
		C.position = { cont = inn.cont, wx = inn.wx + 65, wy = inn.wy }
		C.resting = false
		local sent, kingSent = #C.sent, ns.KingArrow.State().stats.sent
		local pins = ns.Pins()
		eq(arrow.Start(), true)
		eq(#C.sent, sent, "local guidance sends no private position or request")
		local state = arrow.State()
		local frame, ticker = state.frame, state.ticker
		eq(state.target.id, inn.id); eq(frame.parent, E.Minimap)
		assert(frame:GetScript("OnUpdate"), "active local direction update")
		assert(pins:GetVectorToIcon(frame), "actual HBD registered its world pin")
		C.Advance(0.1); C.Advance(0.1)
		local fx, fy = frame:GetCenter(); local mx, my = E.Minimap:GetCenter()
		assert(math.abs(fx - mx) < 0.000001 and fy < my, "actual HBD places the inn south")
		assert(math.abs(math.abs(frame.icon.rotation) - math.pi) < 0.000001, "actual HBD screen vector points south")
		eq(frame.icon.alpha, 1)
		-- Native rotating minimap: the real HBD callback owns rotation and screen placement.
		C.facing = math.pi / 2
		C.Fire("CVAR_UPDATE", "rotateMinimap", "1")
		C.Advance(0.1); C.Advance(0.1)
		fx, fy = frame:GetCenter()
		assert(fx < mx and math.abs(fy - my) < 0.000001, "actual rotated HBD pin is west")
		assert(math.abs(frame.icon.rotation - math.pi / 2) < 0.000001, "rotated screen vector points west")
		for _, pad in ipairs({ not initialPad, initialPad }) do
			C.Switch(pad); C.Advance(0.2)
			eq(arrow.State().active, true, "exempt local minimap guidance survives input switch")
			eq(arrow.State().ticker, ticker, "no duplicate timer across switches")
			assert(frame:IsVisible()); assert(pins:GetVectorToIcon(frame))
		end
		eq(ns.KingArrow.State().stats.sent, kingSent, "guidance makes no additional King request")
		arrow.Cancel("user")
		eq(ticker:IsCancelled(), true); eq(frame:GetScript("OnUpdate"), nil)
		eq(C.updating[frame], nil); eq(frame:IsShown(), false)
		eq(pins:GetVectorToIcon(frame), nil, "actual HBD pin removed")
		local timers = #C.tickers
		C.Advance(0.5)
		eq(#C.tickers, timers, "cancelled guidance starts no idle ticker")
		eq(arrow.State().ticker, nil); eq(frame:IsShown(), false)
		eq(arrow.Start(), true); local arrivalTimer = arrow.State().ticker
		C.position.wx, C.position.wy = inn.wx, inn.wy
		C.Advance(1.1)
		eq(arrow.State().active, true, "coordinates alone are not arrival")
		C.resting = true; C.Advance(1.1)
		eq(arrow.State().reason, "arrived"); eq(arrivalTimer:IsCancelled(), true)
		eq(frame:GetScript("OnUpdate"), nil); eq(pins:GetVectorToIcon(frame), nil)
		eq(#C.sent, sent, "local guidance lifecycle emits no addon messages")
		Check(C.ledger, "innkeeper guidance in both input modes")
		NoErrors(C, "innkeeper guidance")
	end)
end

-- A player's card (a row of the census), its Whisper, Invite and Who buttons clicked.
local function PersonFlow(C)
	local ns = C.ns
	-- (1.2: UI.ShowPerson opens the player's profile in the Olympus window; the side card, its
	-- Whisper, Invite and Who on the same functions, stays for a client without PlayerProfile.lua.)
	local Show = ns.UI.ShowPersonCard or ns.UI.ShowPerson
	Show({ name = "Someone", realm = "Realm", guild = "Olympus II", class = "WARRIOR", level = 60 })
	local card
	-- (1.1.5's windows: ns.Window gives the metal frame its own name, the plain fallback "<name>Basic".)
	for _, n in ipairs({ "OlympusPersonFrameHD", "OlympusPersonFrame", "OlympusPersonFrameHDBasic", "OlympusPersonFrameBasic" }) do
		local f = rawget(C.env, n)
		if f and f:IsShown() then card = f end
	end
	card = card or assert(ns.UI.PersonCard and ns.UI.PersonCard(), "the card shows")
	for _, key in ipairs({ "whisper", "invite", "who" }) do
		local b = assert(rawget(card, key), "its " .. key .. " button")
		C.Advance(10) -- (Who's cooldown)
		C.Click(b)
	end
	C.Advance(1)
	card:Hide()
end

-- The census's quiet /who (Who.Search, the player's click on Refresh): its answer still to come
-- (the game's who list doesn't hear it meanwhile).
local function QuietWhoFlow(C)
	C.Advance(30)
	InClick(C, function() C.ns.Who.Search() end)
	C.Advance(1)
	return C.ns.Who.IsPending()
end

-- The Olympus window on its Chat tab (ChatWindow.lua), which takes the Open chat key.
local function ChatTabFlow(C)
	C.ns.ChatWindow.Toggle("A")
	C.Advance(1)
end

-- The game's target: a player of an Olympus guild (the borders' and nameplates' events).
local function TargetFlow(C)
	C.units.target = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	C.Fire("PLAYER_TARGET_CHANGED")
	C.Advance(1)
	-- The game's own refresh of the target frame and of a name, which Olympus hooks.
	C.env.TargetFrame:CheckClassification()
	C.env.CompactUnitFrame_UpdateName({ unit = "target", name = C.NewWidget("FontString", nil, nil, nil, true) })
	C.units.target = nil
	C.Fire("PLAYER_TARGET_CHANGED")
	C.Advance(1)
end

-- An officer's click on a week's entry: the game's calendar (Week.OpenCalendar).
local function CalendarFlow(C)
	local opened
	InClick(C, function() opened = C.ns.Week.OpenCalendar({ at = C.now + 86400, title = "Raid" }) end)
	return opened
end

-- The game's own /who: Olympus's hook on C_FriendList.SendWho (Who.lua) runs after it.
local function GameWhoFlow(C) C.env.C_FriendList.SendWho("n-Someone") end

-- An alert (ns.Alert: the raid warning frame) and a line in the chat (ns.Print).
local function AlertFlow(C)
	C.ns.Alert("test", "soft", { text = "A test alert", own = true })
	C.ns.Print("A test line")
end

-- The world map's Olympus icons: what Olympus's copy of the library holds there.
local function WorldPins(C)
	local lib = C.env.LibStub("HereBeDragons-Pins-2.0", true)
	local n = 0
	for ref, list in pairs(lib and lib.worldmapPins or {}) do n = n + 1 end
	return n, lib and lib.worldmapPinsPool and lib.worldmapPinsPool:GetNumActive() or 0
end

local function OlympusEscapeNames(C)
	local out = {}
	for _, n in ipairs(C.env.UISpecialFrames) do if AUDIT.Own(n) then out[#out + 1] = n end end
	return out
end

-- Olympus's textures and frames on the game's own frames, shown.
local function ShownOnGameFrames(C)
	local out = {}
	for _, w in ipairs(C.created) do
		if w.olympus and w:IsObjectType("Region") and w:IsVisible() then
			local p = w.parent
			while p and p.olympus do p = p.parent end
			if p and p ~= C.env.UIParent and p.blizzard and p ~= C.env.Minimap then out[#out + 1] = (w.name or w.kind) .. " on " .. (rawget(p, "name") or rawget(p, "path") or "?") end
		end
	end
	return out
end


---------------------------------------------------------------------------
-- The sessions.
---------------------------------------------------------------------------

test("gamepad pass 0: the offline tests switch the gamepad UI the game's way (its input style), never by replacing ns.GamepadUI or ns.Gate", function()
	-- (Core.lua's stand-in, taken over by Gamepad.lua, is tested in a namespace of its own: gns.)
	local f = assert(io.open(ROOT .. "tests/run.lua", "rb"))
	local src = f:read("*a")
	f:close()
	local n = 0
	for line in src:gmatch("[^\n]+") do
		n = n + 1
		local code = line:gsub("%-%-.*$", "")
		local lhs = code:match("^%s*([^=~<>]-)%s*=[^=]") or ""
		local guard = line:find("(the guard's own restore)", 1, true)
		if not guard and not code:find("^%s*local ") then
			for target in (lhs .. ","):gmatch("%s*([^,]-)%s*,") do
				-- (the addon's ns, or a copy's as w.ns; not a namespace of a test's own, gns)
				if target:find("^ns%.GamepadUI$") or target:find("%.ns%.GamepadUI$") or target:find("^ns%.Gate$") or target:find("%.ns%.Gate$") then
					error(("tests/run.lua:%d replaces %s: switch the input style instead (GamepadStyle, WithGamepadUI)"):format(n, target), 0)
				end
			end
		end
	end
	-- And run.lua's own guard, at the end of each of its tests (where it runs): nothing replaced so far.
	if rawget(_G, "GamepadStyle") then eq(GamepadStyle(nil), nil, "nothing replaced") end
end)

test("gamepad pass 0: the model offers nothing Forever's client lacks (tests/fixtures/forever-api.lua): its globals, its namespaces' members, its frames' methods, its Enum values", function()
	local C = NewClient({})
	World(C, {})
	local bad = {}
	for k, v in pairs(C.env) do
		if type(k) == "string" and k ~= "_G" and not AUDIT.Own(k) then
			local named = type(v) == "table" and rawget(v, "fromKey")
			if not FIX.globals[k] and not named then bad[#bad + 1] = k end
			-- A namespace's members.
			if type(v) == "table" and FIX.globals[k] == "namespace" then
				for m in pairs(v) do
					if FIX.members[k .. "." .. m] == false then bad[#bad + 1] = k .. "." .. m end
				end
			end
		end
	end
	-- Every widget the model made: its own fields that are methods must be its type's (or its mixins').
	for _, w in ipairs(C.created) do
		for key, value in pairs(w) do
			if type(value) == "function" and not (rawget(w, "methods")[key] or (rawget(w, "templateMethods") or {})[key]) then
				bad[#bad + 1] = (rawget(w, "name") or rawget(w, "path") or w.kind) .. ":" .. key
			end
		end
	end
	table.sort(bad)
	eq(#bad, 0, "the model offers what the client lacks: " .. table.concat(bad, ", "))
	-- The input style's values are the documentation's.
	eq(C.env.Enum.InputDeviceInterfaceType.Gamepad, 1)
	eq(C.env.Enum.InputDeviceInterfaceType.Mkb, 0)
end)

test("gamepad model 70790: template animation groups are separate from frame children and visible regions", function()
	local C = NewClient({})
	World(C, {})
	local host = C.NewWidget("Frame", "OlympusAnimationHost", C.env.CommunitiesFrame)
	local child = C.NewWidget("Button", "OlympusAnimationChild", host)
	local texture = C.NewWidget("Texture", nil, host)
	local group = C.NewWidget("AnimationGroup", nil, host)
	eq(host:GetNumChildren(), 1, "GetChildren returns child frames, not an animation group")
	eq(host:GetChildren(), child); eq(host:GetRegions(), texture)
	eq(host:GetAnimationGroups(), group)
		local made = host:CreateAnimationGroup()
		eq(select(2, host:GetAnimationGroups()), made); eq(made:GetParent(), host)
		eq(host:GetNumChildren(), 1, "API-created animation groups also stay outside GetChildren")
	eq(group:IsObjectType("Region"), false); eq(group.IsVisible, nil, "an animation group has no visibility API")
	C.env.CommunitiesFrame:Show()
	local shown = ShownOnGameFrames(C)
	eq(#shown, 3, "visual audit still includes host, child and texture")
	host:Hide()
	eq(#ShownOnGameFrames(C), 0, "hidden visual ancestry removes all three without asking the group for visibility")
end)

test("gamepad navigation 70790: focus marks, mouse-handler frames and ignored containers follow the native candidate predicate", function()
	local C = NewClient({ gamepad = true })
	World(C, {})
	local parent, invoked, barriers = C.env.CommunitiesFrame, 0, 0
	parent:Show()
	local function Frame(kind, name, p)
		local f = C.NewWidget(kind, "OlympusNavigation" .. name, p or parent)
		f:SetSize(20, 20)
		return f
	end
	local up, down = Frame("Frame", "MouseUp"), Frame("Frame", "MouseDown")
	up:SetScript("OnMouseUp", function() invoked = invoked + 1 end)
	down:SetScript("OnMouseDown", function() invoked = invoked + 1 end)
	local marked = Frame("Frame", "Marked")
	marked.smartNavigationCanFocus = true
	Frame("Frame", "Plain")
	Frame("Button", "Button")
	Frame("EditBox", "EditBox")
	local ignored = Frame("Button", "Container")
	ignored.smartNavigationIgnoredContainerFrame = true
	Frame("Button", "Child", ignored)
	Frame("Button", "Hidden"):Hide()
	local empty = Frame("Frame", "ZeroSize")
	empty:SetSize(0, 0); empty.smartNavigationCanFocus = true
	local secure = C.env.securecallfunction
	C.env.securecallfunction = function(fn, ...) barriers = barriers + 1; return secure(fn, ...) end
	local found = {}
	for _, name in ipairs(NavigableOlympus(C)) do found[name] = true end
	for _, suffix in ipairs({ "MouseUp", "MouseDown", "Marked", "Button", "EditBox", "Child", "ZeroSize" }) do
		eq(found["OlympusNavigation" .. suffix], true, "native candidate " .. suffix)
	end
	for _, suffix in ipairs({ "Plain", "Container", "Hidden" }) do eq(found["OlympusNavigation" .. suffix], nil, "not a candidate " .. suffix) end
	assert(barriers > 0, "mouse-handler reads use the native securecallfunction boundary")
	eq(invoked, 0, "finding candidates never executes their mouse handlers")
end)

test("gamepad pass 1: a whole session with the gamepad UI on from the login reaches nothing of the game's UI but what its rule allows", function()
	local C, ns = Session(true)
	local before = Snapshot(C)
	OnlyAllowed(C.ledger, "the login")
	NoErrors(C, "the login")
	-- No slash command at a gamepad login (D1): typed, it is the game's unknown command.
	eq(rawget(C.env, "SLASH_OLYMPUS1"), nil, "no /oly")
	eq(TypeSlash(C, "/oly status"), false, "/oly typed: not Olympus's")
	eq(#C.taint, 0, "no Olympus code from the chat box")
	GP.Covers("slash")
	-- Its hidden channel joined all the same (the census), off the chat windows' lists.
	assert(next(C.channels), "the census channel joined")
	GP.Covers("chat-channels")
	local mark = C.Mark()
	WindowFlow(C)
	local dialogs, all, clicks = DialogsFlow(C)
	eq(dialogs, all, "every dialog shown, in Olympus's own window")
	assert(clicks >= all, "their buttons clicked: " .. clicks)
	KingViewFlow(C)
	GuildWindowsFlow(C)
	MapFlow(C)
	TooltipFlow(C)
	eq(MenuFlow(C), 0, "no menu callback registered")
	eq(ChatLineFlow(C), nil, "no chat name filter")
	C.Advance(30)
	OnlyAllowed(C.Since(mark), "the flows")
	NoErrors(C, "the flows")
	eq(#NavigableOlympus(C, true), 0, "no Olympus button where the gamepad cursor goes")
	local diff = Diff(before, Snapshot(C))
	eq(#diff, 0, "the game's state written: " .. table.concat(diff, ", "))
	eq(C.handler, C.gameHandler, "the game's own error handler")
	-- Registered with the game: only the exempt mail post-hooks (Treasury.lua, "mail-hooks").
	local kinds = {}
	for _, cb in ipairs(C.callbacks) do kinds[#kinds + 1] = cb.kind .. " " .. tostring(cb.key or cb.tag or cb.script or "") end
	table.sort(kinds)
	eq(table.concat(kinds, ", "), "hooksecurefunc AutoLootMailItem, hooksecurefunc SendMail, hooksecurefunc TakeInboxItem, hooksecurefunc TakeInboxMoney",
		"what is registered with the game")
	GP.Covers("mail-hooks")
end)

test("gamepad pass 2: mouse and keyboard, then a switch to the gamepad UI: the gate steps back on the next frame, every callback left with the game does nothing, the player is told once what a /reload clears", function()
	local C, ns = Session(false)
	local E = C.env
	-- Mouse and keyboard: everything installs, every flow works the game's way.
	local mark = C.Mark()
	WindowFlow(C)
	KingViewFlow(C)
	PersonFlow(C)
	QuietWhoFlow(C)
	ChatTabFlow(C)
	DialogsFlow(C)
	GuildWindowsFlow(C)
	MapFlow(C)
	local lines, postCalls = TooltipFlow(C)
	assert(postCalls > 0 and lines > 0, "the tooltip's post-call and its line: " .. lines)
	local made, ran = MenuFlow(C)
	-- (Changed on purpose, 1.2.1: the game's guild roster menus are never hooked, PlayerMenu.NEVER,
	-- so 8 player menus where there were 10.)
	assert(ran >= #ns.PlayerMenu.WHICH and ran >= 8, "the player menus' callbacks: " .. ran)
	eq(C.menus.MENU_UNIT_COMMUNITIES_GUILD_MEMBER, nil, "never the game's guild roster menu")
	eq(C.menus.MENU_UNIT_GUILD, nil)
	local _, filters = ChatLineFlow(C)
	eq(filters, 1, "the chat name filter")
	TargetFlow(C)
	eq(CalendarFlow(C), true, "the calendar opens")
	GameWhoFlow(C)
	AlertFlow(C)
	eq(TypeSlash(C, "/oly status"), true, "/oly typed with mouse and keyboard")
	C.Advance(10)
	Check(C.ledger, "with mouse and keyboard")
	NoErrors(C, "with mouse and keyboard")
	local used = Ids(C.ledger)
	used.slash = E.SlashCmdList.OLYMPUS and 1 -- (a table write, not a call: the commands registered)
	for _, id in ipairs({ "slash", "communities-button", "tooltip-unit", "error-handler", "map-overlay", "dialogs", "chat-box", "who",
		"who-quiet", "map-library", "chat-key", "player-menu", "borders", "chat-marks", "nameplates", "minimap", "roster-actions",
		"calendar", "raid-notice", "chat-channels", "mail-hooks" }) do
		assert(used[id], "with mouse and keyboard, used: " .. id)
	end
	-- A game popup of Olympus's still up, its window on the escape list, the Communities window
	-- open with Olympus's button in it, the map showing Olympus's icons: then the switch.
	ns.ShowDialog("OLYMPUS_CRAFT_ASK")
	ns.UI.Toggle()
	-- (1.2.1: a guild window the player sees moves a question of Olympus's off the game's popups,
	-- GuildFrame.lua, and none opens there while one is up: the Communities window here is open the
	-- way ClassicUI Forever keeps it, unseen at alpha 0, which leaves the game's popup where it is.)
	E.CommunitiesFrame:SetAlpha(0)
	E.CommunitiesFrame:Show()
	C.ShowMap()
	-- (The author's preview of a border, on his own portrait: a texture of Olympus's on the game's
	-- player frame, and his nameplate mark's.)
	ns.devWorkshop = true
	ns.Borders.SetPreview(ns.Borders.TIERS[1].name)
	ns.Borders.RefreshAll(true)
	eq(QuietWhoFlow(C), true, "a quiet /who waiting for its answer")
	eq(E.LFGWhoListFrame:IsEventRegistered("WHO_LIST_UPDATE"), false, "the game's who list silenced meanwhile")
	assert(#ShownOnGameFrames(C) > 0, "Olympus's border on the game's player frame, before the switch")
	assert(#NavigableOlympus(C) > 0, "Olympus's button where the gamepad cursor goes, before the switch")
	assert(#OlympusEscapeNames(C) > 0, "Olympus's windows on the escape list")
	assert((WorldPins(C)) > 0, "Olympus's icons on the world map")
	assert(E.ChatFrame1EditBox:IsShown(), "the game's chat box opened from Olympus (a whisper)")
	assert(C.bindings and next(C.bindings), "the Chat tab's key")
	assert(C.handler ~= C.gameHandler, "Olympus's error handler")
	local escapeBefore = table.concat(E.UISpecialFrames, ",")

	C.Switch(true)
	-- In the switch's own event: only Olympus's borrowed keys given back.
	for _, r in ipairs(C.switchLedger) do
		assert(r.ids and (r.ids[1] == "chat-key" or r.ids[1] == "main-key"), "in the switch's event: " .. Describe(r))
	end
	eq(next(C.bindings), nil, "the Chat tab's key back to the game at once")
	GP.Covers("chat-key")
	GP.Covers("main-key")
	C.Advance(1)
	-- The next frame: each park.
	eq(#NavigableOlympus(C, true), 0, "no Olympus button where the gamepad cursor goes")
	GP.Covers("communities-button")
	local shown = ShownOnGameFrames(C)
	eq(#shown, 0, "Olympus's objects on the game's frames hidden: " .. table.concat(shown, ", "))
	GP.Covers("map-overlay"); GP.Covers("borders"); GP.Covers("nameplates")
	eq(C.handler, C.gameHandler, "the game's error handler back")
	GP.Covers("error-handler")
	eq(#OlympusEscapeNames(C), 0, "Olympus's names off the end of the escape list (" .. escapeBefore .. ")")
	GP.Covers("escape-list")
	eq((WorldPins(C)), 0, "Olympus's icons off the world map")
	GP.Covers("worldmap-icons")
	eq(ns.Who.IsPending(), false, "the quiet /who given up at the switch")
	eq(E.LFGWhoListFrame:IsEventRegistered("WHO_LIST_UPDATE"), true, "the game's who list hears its answers again at once")
	GP.Covers("who-quiet")
	-- What stays until a /reload, told once in Olympus's own window, whose Reload is the player's click.
	local left = table.concat(ns.Gate.leftovers, ",")
	for _, id in ipairs({ "chat-box", "dialogs", "slash", "worldmap-icons" }) do
		assert(left:find(id, 1, true), "until a /reload: " .. id .. " (" .. left .. ")")
	end
	GP.Covers("slash"); GP.Covers("dialogs"); GP.Covers("chat-box")
	eq(ns.Gate.Noticed(), true, "told")
	local notice
	for _, w in ipairs(C.created) do if w.olympus and w.which == "OLYMPUS_GAMEPAD_RELOAD" and w:IsShown() then notice = w end end
	assert(notice, "the notice, in Olympus's own window (Dialog.lua)")
	eq(E.StaticPopup1.which == "OLYMPUS_GAMEPAD_RELOAD", false, "not the game's popup")
	Check(C.Since(mark), "the switch")
	-- The notice's Reload: the player's click.
	local reload
	for _, b in ipairs(notice.buttons or {}) do if b:IsVisible() and b:GetText() == ns.L.GATE_RELOAD then reload = b end end
	assert(reload, "the notice's Reload button")
	C.Click(reload)
	eq(C.reloaded, true, "ReloadUI from the player's click")
	GP.Covers("reload-button")
	-- Every callback left with the game, called the game's way: nothing.
	local after = C.Mark()
	eq(TooltipFlow(C), 0, "no line on the tooltip")
	GP.Covers("tooltip-unit")
	local made2 = MenuFlow(C)
	eq(made2, 0, "no line in the player menus")
	GP.Covers("player-menu")
	eq(ChatLineFlow(C), nil, "no mark in the chat")
	GP.Covers("chat-marks")
	GuildWindowsFlow(C)
	MapFlow(C)
	TargetFlow(C)
	GameWhoFlow(C)
	AlertFlow(C)
	GP.Covers("raid-notice"); GP.Covers("chat-output")
	eq(CalendarFlow(C), false, "the calendar: only how to open it")
	GP.Covers("calendar")
	WindowFlow(C)
	PersonFlow(C)
	GP.Covers("roster-actions"); GP.Covers("who")
	DialogsFlow(C)
	-- /oly typed now: registered before, the game's chat box still calls it (the leftover the
	-- notice names); its first line refuses, nothing of the game's is touched.
	eq(TypeSlash(C, "/oly status"), true, "the command the game keeps")
	eq(#C.taint, 1, "the chat box ran Olympus's function: the /reload the notice asks for")
	C.Advance(30)
	Check(C.Since(after), "the gamepad UI after the switch")
	NoErrors(C, "after the switch")
	eq(ns.Gate.Noticed(), true)
	Check(C.ledger, "the whole session")
end)

test("gamepad pass 3: the gamepad UI and mouse and keyboard, back and forth three times: each install once, what can't be undone registered once, every flow working in both", function()
	local C, ns = Session(true)
	local E = C.env
	for round = 1, 3 do
		C.Switch(false)
		C.Advance(1)
		WindowFlow(C)
		ChatTabFlow(C)
		E.CommunitiesFrame:Show(); C.Advance(0.5)
		assert(#NavigableOlympus(C) > 0, "round " .. round .. ": Olympus's button back in the guild window")
		E.CommunitiesFrame:Hide()
		MapFlow(C)
		eq(select(2, TooltipFlow(C)), 1, "round " .. round .. ": the tooltip's post-call, once")
		eq(TypeSlash(C, "/oly status"), true, "round " .. round .. ": /oly back")
		C.Switch(true)
		C.Advance(1)
		E.CommunitiesFrame:Show(); C.Advance(0.5)
		eq(#NavigableOlympus(C), 0, "round " .. round .. ": none with the gamepad UI")
		E.CommunitiesFrame:Hide()
		WindowFlow(C)
		eq(TooltipFlow(C), 0, "round " .. round .. ": no tooltip line")
		NoErrors(C, "round " .. round)
	end
	Check(C.ledger, "three rounds")
	-- What can't be undone, registered once a session however many switches.
	local count = {}
	for _, cb in ipairs(C.callbacks) do
		local key = cb.kind .. " " .. tostring(cb.key or cb.tag or cb.type or "") .. " " .. tostring(cb.script or "") .. " " .. tostring(cb.frame and (rawget(cb.frame, "name") or rawget(cb.frame, "path")) or "")
		count[key] = (count[key] or 0) + 1
	end
	for key, n in pairs(count) do eq(n, 1, "registered once: " .. key) end
	eq(#C.menus.MENU_UNIT_PLAYER, 1, "the player menu's callback, once")
	local slash = 0
	for k in pairs(E.SlashCmdList) do if k:find("^OLYMPUS") then slash = slash + 1 end end
	eq(slash, 7, "/oly and /ol, /olc, /oll, /ola (1.2: a line in the fight room), /ogarmy and /olysite (1.3.3), once")
	GP.Covers("player-menu"); GP.Covers("slash"); GP.Covers("minimap")
	assert(rawget(E, "OlympusMinimapButton"):IsVisible(), "the minimap button in both modes")
end)

test("gamepad pass 4: blocked calls with the gamepad UI: counted, told once in a chat line, nothing of the game's touched; another addon's only logged", function()
	local C, ns = Session(true)
	local mark = C.Mark()
	local printed = #C.printed
	for i = 1, 500 do C.Fire("ADDON_ACTION_FORBIDDEN", "Olympus", "SetPreferredGamepadInteractTarget()") end
	C.Fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "SetPreferredGamepadInteractTarget()")
	eq(#C.Since(mark), 0, "the handler reaches nothing of the game's")
	C.Advance(5)
	Check(C.Since(mark), "after the blocks")
	local told = 0
	for i = printed + 1, #C.printed do if C.printed[i]:find(ns.L.BLOCKED_GAMEPAD, 1, true) then told = told + 1 end end
	eq(told, 1, "told once")
	local kept = ns.db.actionsBlocked or {}
	eq(#kept, 1, "one record")
	eq(kept[1].count, 500)
	eq(kept[1].gamepad, true)
	-- The taint probe (its record's evidence) reads the gamepad UI's own state, writes nothing.
	assert(tostring(kept[1].taint):find("^taint: none of %d+ values"), tostring(kept[1].taint))
	GP.Covers("diagnostics")
	NoErrors(C, "blocked calls")
end)

test("gamepad personal verification opens in both window styles and submits only by choice", function()
	local linkCalls, linkReady = {}, false
	local C, ns = Session(true, { setup = function(c)
		c.addOnFiles = { Olympus_Link = function(env)
			local host = rawget(env, "OlympusLinkHandoff")
			rawset(env, "OlympusLinkHandoff", nil)
			host.Link = {
				Slash = function(rest) linkCalls[#linkCalls + 1] = rest end,
				BotReady = function() return linkReady end,
			}
		end }
	end })
	local function OpenFromRealm(which)
		for _, row in ipairs(Main(C).views.realm.rows) do
			if row:IsShown() and row.line and row.line.id == "verify-self" then
				eq(row.line.text, ns.L.VERIFY_SELF_TITLE)
				C.Click(row)
				return assert(ns.Dialog.Find(which))
			end
		end
		error("The Realm must offer My Discord Verification")
	end

	ns.UI.SelectTab("census")
	for _, row in ipairs(Main(C).views.census.rows) do
		assert(not (row:IsShown() and row.line and row.line.id == "verify-self"), "verification moved from Census")
	end
	ns.UI.SelectTab("realm")
	local list = ns.Views.Build("realm")
	eq(list[3].id, "verify-self", "verification is the first action below The Realm navigation and search")
	local missing = "OLYMPUS_VERIFY_SELF_UNAVAILABLE"
	local panel = OpenFromRealm(missing)
	eq(panel.editBox:IsShown(), false, "Verify is missing at login")
	eq(panel.extraButton:IsShown(), false, "the unconfigured module cannot invite a code")
	linkReady = true
	panel = OpenFromRealm(missing)
	assert(panel.extraButton:IsShown(), "ready Link works even without the ordinary Verify bridge")
	eq(#linkCalls, 0, "opening does not start Link")
	C.Click(panel.extraButton)
	eq(#linkCalls, 1); eq(linkCalls[1], "", "explicit click opens the existing Link prompt, with no pasted code")
	panel = OpenFromRealm(missing)
	linkReady = false
	C.Click(panel.extraButton)
	eq(#linkCalls, 1, "the click checks that Link is still ready")
	panel = OpenFromRealm(missing)
	eq(panel.extraButton:IsShown(), false, "the launcher is hidden when Link is unconfigured")
	local link = ns.Link
	ns.Link = nil
	panel = OpenFromRealm(missing)
	eq(panel.extraButton:IsShown(), false, "the launcher is hidden when Link is absent")
	ns.Link = link
	linkReady = true
	panel:Hide()

	local calls = 0
	C.env.OlympusVerifyBridge242 = {
		Status = function() return { version = 243, deliveryOnly = true, membershipProof = false, roleAuthority = false,
			total = 0, truncated = false, requests = {} } end,
		QueueSelf = function(code) eq(code, "test-personal-code"); calls = calls + 1; return true end,
	}
	local before = C.gamePopups or 0
	local prompt = OpenFromRealm("OLYMPUS_VERIFY_SELF")
	assert(prompt.editBox:IsShown(), "Verify is detected after login")
	assert(prompt.editBox:HasFocus(), "the code field is ready for a paste")
	local guide = prompt.text:GetText()
	assert(guide:find("/verify", 1, true), "instructions live with the code field")
	assert(guide:find("Asmongold", 1, true) and guide:find("#olympus-verify", 1, true), "the guide names the bot's server and channel")
	eq(calls, 0)
	prompt.editBox:SetText("test-personal-code")
	C.Fire1(prompt.editBox, "OnEnterPressed")
	eq(calls, 0, "Enter in the editor does not submit")
	C.Click(prompt.buttons[1])
	eq(calls, 1); eq(prompt.editBox:GetText(), "")
	local result = assert(ns.Dialog.Find("OLYMPUS_VERIFY_SELF_RESULT"))
	assert(result.text:GetText():find("/verify-status", 1, true), "the bot is authoritative for access and roles")
	result:Hide()

	C.Switch(false); C.Advance(1)
	local host = C.NewWidget("Frame", nil, C.env.UIParent)
	host:SetSize(384, 512)
	for _, style in ipairs({ "old", "hd" }) do
		ns.UI.OpenDocked(host, "realm", false, style)
		eq(ns.UI.WindowStyle(), style)
		local dialog = OpenFromRealm("OLYMPUS_VERIFY_SELF")
		assert(dialog.editBox:IsShown() and dialog.extraButton:IsShown())
		dialog:Hide()
	end
	C.env.SlashCmdList.OLYMPUS("discord status")
	eq(#linkCalls, 2); eq(linkCalls[2], "status", "the slash command still forwards its original argument")
	C.Switch(true); C.Advance(1)
	assert(OpenFromRealm("OLYMPUS_VERIFY_SELF").editBox:IsShown())
	eq(calls, 1, "neither transition nor reopening resubmits")
	eq(C.gamePopups or 0, before, "no Blizzard popup for the personal code")
	NoErrors(C, "personal verification")
end)

test("gamepad pass 5: the rest of the list with the gamepad UI on: the Issue Reporter, the map library half-loaded or loaded on demand, the layer hop's group, focus in Olympus's own boxes, the game's look-ups", function()
	-- A test client's Issue Reporter (Blizzard_PTRFeedback): Olympus's Hide button on it with
	-- mouse and keyboard, a gamepad target no more after the switch; none at a gamepad login.
	local function Reporter(C)
		local E = C.env
		C.absent.PTR_IssueReporter = nil
		local r = C.Blizz("PTR_IssueReporter", "Frame")
		for _, key in ipairs({ "Border", "Body", "ReportBug", "InfoButton" }) do rawset(r, key, C.NewWidget("Frame", nil, r, nil, true)) end
		C.gameTables[r] = true
		return r
	end
	local C, ns = Session(false, { setup = Reporter })
	ns.db.hideIssueReporter = false
	ns.UI.ApplyIssueReporter()
	C.env.PTR_IssueReporter:Show()
	assert(#NavigableOlympus(C) > 0, "Olympus's Hide button on the Issue Reporter")
	C.Switch(true); C.Advance(1)
	eq(#NavigableOlympus(C), 0, "hidden at the switch")
	GP.Covers("issue-reporter")
	Check(C.ledger, "the Issue Reporter")
	local P = Session(true, { setup = Reporter })
	P.env.PTR_IssueReporter:Show()
	P.ns.UI.ApplyIssueReporter()
	eq(#NavigableOlympus(P), 0, "none at a gamepad login")
	Check(P.ledger, "the Issue Reporter, gamepad login")

	-- The map library on a client that loads the world map on demand: Bootstrap.lua loads it first.
	local D = Session(true, { worldMapOnDemand = true })
	assert(D.loadedWorldMap, "Blizzard_WorldMap loaded before the library")
	Check(D.ledger, "the world map loaded on demand")
	NoErrors(D, "the world map loaded on demand")
	GP.Covers("load-worldmap"); GP.Covers("map-library"); GP.Covers("lib-stub")
	-- Half-loaded (its file stopped part way): its update loop stopped, no map features, no error each frame.
	local B = Session(true, { brokenMapLibrary = true })
	assert(B.brokeMapLibrary, "the library's file stopped as it loaded")
	Check(B.ledger, "a half-loaded map library")
	GP.Covers("lib-partial")

	-- The layer hop with the gamepad UI: the helper's addon invites the guest it offered to (its
	-- own message, no click: "hop-group"); the asker's, offered and invited, accepts nothing for
	-- the player: the game's invite window is the controller's ("party-invite").
	local Hh = Session(true)
	local hop = Hh.ns.Hop
	Hh.ns.db.layerHelp, Hh.ns.db.layerAutoInvite = true, true
	hop.random = function(a) return a or 0 end
	hop.after = function(_, _, f) f() end
	Hh.units.target = { name = "Mob", realm = "Realm", guid = "Creature-0-4619-0-7-68-0000AAA1" }
	Hh.ns.Layers.HOLD = 0
	for k = 1, 2 do Hh.units.target.guid = ("Creature-0-4619-0-7-68-0000AAA%d"):format(k); Hh.ns.Layers.Observe("target") end
	local rankOf = Hh.ns.Roster.RankOf -- (1.2.0: only a member is invited; the asker is a guildmate)
	Hh.ns.Roster.RankOf = function(n) if type(n) == "string" and n:find("^Asker") then return 3 end return rankOf(n) end
	hop.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1429~7")
	hop.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
	Hh.ns.Roster.RankOf = rankOf
	eq(Hh.invited, "Asker", "the helper's invite, on its own")
	GP.Covers("hop-group")
	hop.Reset()
	-- (1.5.4) The first ask of a session shows the experimental hop's window: Olympus's own under
	-- the gamepad UI, no game popup; its Ask button sends the ask.
	local popupsBefore = Hh.gamePopups or 0
	hop.Ask(1429, 8, "the King's layer")
	eq(hop.State(), nil, "nothing asked before the window is answered")
	local confirm = assert(Hh.ns.Dialog.Find("OLYMPUS_HOP_CONFIRM"), "the experimental hop's window, Olympus's own")
	eq(Hh.gamePopups or 0, popupsBefore, "no game popup for it")
	InClick(Hh, function() confirm.buttons[1]:Click() end)
	local id = hop.State() and hop.State().id
	assert(id, "asked")
	hop.HandleOffer("WHISPER", "Bbb-Realm", ("LO~%d~3~5"):format(id))
	Hh.Advance(hop.WINDOW + 1)
	hop.Tick()
	hop.OnInvite("Bbb")
	eq(Hh.accepted, nil, "nothing accepted for the player")
	GP.Covers("party-invite")
	-- (1.5.4) A hop to a layer on another Forever sub-realm: in the helper's group, the relog window
	-- (Olympus's own, no game popup), nothing accepted or left on its own; its Leave group button,
	-- the player's click, leaves ("hop-group").
	hop.Reset()
	hop.confirmed.other = true
	local realmOf = Hh.ns.Layers.RealmOf
	Hh.ns.Layers.RealmOf = function(n) if type(n) == "string" and n:find("^Bbb") then return "CAMWOWUS2Realm1PvE" end return realmOf(n) end
	Hh.ns.Roster.RankOf = function(n) if type(n) == "string" and n:find("^Bbb") then return 3 end return rankOf(n) end -- (the helper is a guildmate)
	local function WaitForHop(phase)
		-- Comm pumps every 1.2 seconds. Wait for the actual completion callback through
		-- the real queue, allowing for its tick phase and a few login jobs ahead of us.
		for _ = 1, 24 do
			if hop.State().phase == phase then break end
			Hh.Advance(0.25)
		end
	end
	hop.Ask(1429, 8, "a layer there", "CAMWOWUS2Realm1PvE")
	id = assert(hop.State() and hop.State().id, "asked for the layer there")
	WaitForHop("asking") -- the offers' window opens when the ask leaves
	eq(hop.State().phase, "asking", "the ask went out")
	hop.HandleOffer("WHISPER", "Bbb-Realm", ("LO~%d~0~0"):format(id))
	eq(hop.State().count, 1, "the guildmate's offer, his hello placing him on that sub-realm, is taken")
	Hh.now = Hh.now + hop.WINDOW + 1 -- (the offers' window, on the wall clock the hop reads: time())
	local beforeRequest = #Hh.sent
	hop.Tick()
	WaitForHop("requested")
	eq(hop.State().phase, "requested", "asked him for the invite"); eq(hop.State().helper, "Bbb-Realm")
	local sentRequest
	for i = beforeRequest + 1, #Hh.sent do
		local packet = Hh.sent[i]
		if packet[2] == "LR~" .. id and packet[3] == "WHISPER" and Hh.ns.ShortName(packet[4]) == "Bbb" then sentRequest = true end
	end
	assert(sentRequest, "the paced request was actually sent to the chosen helper")
	hop.OnInvite("Bbb")
	eq(Hh.accepted, nil, "nothing accepted for the player under the gamepad UI")
	eq(hop.State().invitedBy, "Bbb-Realm", "his invite is the player's to accept")
	Hh.env.IsInGroup, Hh.env.GetNumGroupMembers = function() return true end, function() return 2 end
	Hh.units.party1 = { name = "Bbb", realm = "Realm", guid = "Player-1-0000BBB1" }
	popupsBefore = Hh.gamePopups or 0
	hop.OnRoster()
	eq(hop.State().phase, "relog", "the relog step, the helper on another sub-realm")
	assert(type(Hh.ns.db.hopPending) == "table" and Hh.ns.db.hopPending.helper == "Bbb", "the hop kept for the relog")
	local relog = assert(Hh.ns.Dialog.Find("OLYMPUS_HOP_RELOG"), "the relog window, Olympus's own")
	eq(Hh.gamePopups or 0, popupsBefore, "no game popup for it")
	eq(Hh.left, nil, "the group is not left on its own")
	InClick(Hh, function() relog.buttons[2]:Click() end)
	eq(Hh.left, true, "Leave group: the player's click leaves")
	eq(Hh.ns.db.hopPending, nil, "and the kept hop is over")
	Hh.ns.Layers.RealmOf, Hh.ns.Roster.RankOf = realmOf, rankOf
	Hh.env.IsInGroup, Hh.env.GetNumGroupMembers = function() return false end, function() return 0 end
	Hh.units.party1 = nil
	Check(Hh.ledger, "the layer hop")
	NoErrors(Hh, "the layer hop")

	-- Focus: a dialog's box takes the keyboard only through ns.Focus, never from the game's chat box.
	local F = Session(true)
	F.env.ChatFrame1EditBox:Show(); F.focus = F.env.ChatFrame1EditBox
	F.ns.ShowDialog("OLYMPUS_CRAFT_ASK")
	eq(F.focus, F.env.ChatFrame1EditBox, "the chat's box keeps the keyboard; the player clicks into Olympus's")
	GP.Covers("popup-focus")
	-- The game's look-ups (fonts, strings, the popups' places, the who windows): reads only.
	assert(F.ns.Who.WindowOpen() == false)
	GP.Covers("lookups")
	-- Forever has no who-list column helper (the old guild window's): Olympus's HD headers size themselves.
	eq(F.env.WhoFrameColumn_SetWidth, nil, "the client has none")
	GP.Covers("own-templates")
	Check(F.ledger, "focus and look-ups")
	NoErrors(F, "focus and look-ups")

	-- Inspecting for the tabard patrol (NotifyInspect, not protected): with the gamepad UI too.
	F.units.target = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II" }
	F.env.CanInspect = function() return true end
	F.env.CheckInteractDistance = function() return true end
	local before = F.Mark()
	F.ns.Inspect.InspectTarget()
	F.Advance(5)
	local asked = false
	for _, r in ipairs(F.Since(before)) do if r.sym == "NotifyInspect" then asked = true end end
	assert(asked, "the inspect asked for, with the gamepad UI too (not protected)")
	GP.Covers("inspect-patrol")
	Check(F.ledger, "the inspect patrol")

	-- The author's photo mode: refused with the gamepad UI (no frame of the game's touched).
	F.ns.devWorkshop = true
	F.ns.UI.TogglePhoto()
	eq(F.ns.UI.PhotoMode(), false, "no photo mode with the gamepad UI")
	F.ns.devWorkshop = nil
	GP.Covers("photo")
	Check(F.ledger, "photo")
	-- The dues of a Forever player on the Treasurer's realm group: with mouse and keyboard his click
	-- fills the game's mail window (the name, the note, the gold: nothing sent); after a switch to
	-- the gamepad UI nothing of the game's windows is filled, a line says what to send instead.
	local M = Session(false, { surname = "Ironsurname", realmFrom = function(ns) return ns.TREASURER_REALM end })
	M.env.MailFrame:Show(); M.env.SendMailFrame:Show()
	M.money = 1000000 -- (100 gold)
	local filled
	InClick(M, function() filled = M.ns.Dues.SendDues() end)
	eq(filled, "mail", "the mail filled, with mouse and keyboard")
	assert(Ids(M.ledger)["mail-trade-fill"], "the fill, in the ledger")
	M.Switch(true); M.Advance(1)
	local after = M.Mark()
	InClick(M, function() filled = M.ns.Dues.SendDues() end)
	eq(filled, "gamepad", "with the gamepad UI: only what to send")
	eq(#M.Since(after), 0, "nothing of the game's mail or trade window")
	GP.Covers("mail-trade-fill")
	Check(M.ledger, "the dues")
	NoErrors(M, "the dues")
end)

---------------------------------------------------------------------------
-- Standalone.
---------------------------------------------------------------------------

if MODE == "--debug" then
	return { Boot = Boot, Login = Login, Session = Session, WindowFlow = WindowFlow, Main = Main, Errors = Errors, DialogsFlow = DialogsFlow,
		GuildWindowsFlow = GuildWindowsFlow, MapFlow = MapFlow, TooltipFlow = TooltipFlow, MenuFlow = MenuFlow, ChatLineFlow = ChatLineFlow,
		TypeSlash = TypeSlash, Snapshot = Snapshot, Diff = Diff, Check = Check, NavigableOlympus = NavigableOlympus, Describe = Describe,
		AllowedUnderPad = AllowedUnderPad }
end
-- 1.2.4: the honours' notices (HonorsNet.Notice: a place dropped, the list left, back on it, a place
-- won back) are strips of Olympus's own, never the game's popups nor its raid warning: with the gamepad
-- UI on from the login, a strip shows and reaches nothing of the game's, takes neither the mouse nor
-- the keyboard, has no button the gamepad's cursor could stop on, never goes on the escape list, and
-- goes by itself.
test("gamepad honour notices (1.2.4): with the gamepad UI on, a notice's strip is Olympus's own on UIParent, shown without the mouse or the keyboard, no button, off the escape list, reaching nothing of the game's; gone by itself", function()
	local C, ns = Session(true)
	local mark = C.Mark()
	local before = Snapshot(C)
	eq(ns.HonorsNet.Notice("Top donors: you dropped to 2nd place.", "donor-top-2"), true, "a strip with the gamepad UI on")
	local f = ns.HonorsNet.NoticeFrames()[1]
	assert(f and f:IsShown(), "shown")
	eq(f.olympus, true, "Olympus's own frame") eq(f.parent, C.env.UIParent, "on UIParent")
	eq(f:IsMouseEnabled(), false, "no mouse") eq(f.keyboard, false, "no keyboard")
	for _, ch in ipairs(f.children) do assert(not ch:IsObjectType("Button"), "no button on it") end
	eq(#NavigableOlympus(C, true), 0, "nothing for the gamepad's cursor")
	eq(#OlympusEscapeNames(C), 0, "never on the escape list")
	C.Advance(ns.HonorsNet.NOTICE_SHOW + 1)
	eq(f:IsShown(), false, "gone by itself")
	OnlyAllowed(C.Since(mark), "a notice")
	NoErrors(C, "a notice")
	local diff = Diff(before, Snapshot(C))
	eq(#diff, 0, "the game's state written: " .. table.concat(diff, ", "))
end)

-- 1.2 (the Blood Arena): its restricted calls only inside the player's click, the match's waypoint
-- and the chat filters on the game's system lines never with the gamepad UI (the filter left from
-- mouse and keyboard doing nothing), its companion loaded as Olympus's own addon.
test("gamepad pass 6: the Arena's integrations: restricted calls from a click alone, no waypoint and no chat filter with the gamepad UI, the companion loaded as Olympus's own", function()
	local A = Session(true)
	local ns = A.ns
	local before = A.Mark()
	InClick(A, function()
		eq(ns.SayTo("Bob-Realm", "On my way"), true, "a whisper he wrote, handed to the game")
		ns.FarkleTable.Sit()
	end)
	local ids = Ids(A.Since(before))
	eq(ids["arena-clicks"], 2, "the whisper and the sit, inside the click")
	eq(A.said and A.said[#A.said][3], "Bob-Realm"); eq(A.emotes and A.emotes[1], "SIT")
	GP.Covers("arena-clicks")
	-- The match's [Show on map]: refused with the gamepad UI, nothing of the game's map touched.
	before = A.Mark()
	eq(ns.ArenaMatch.ShowOnMap(), false, "no waypoint with the gamepad UI")
	eq(#A.Since(before), 0, "nothing of the game's map")
	GP.Covers("map-waypoint")
	-- A Wanted last-seen row follows the same boundary: its text remains available, but a gamepad
	-- session never opens or focuses the game's map from Olympus code.
	before = A.Mark()
	eq(ns.Wanted.OpenSightingMap({ mapID = 1429 }), false, "no Wanted map focus with the gamepad UI")
	eq(#A.Since(before), 0, "a Wanted row touches none of the game's map")
	GP.Covers("wanted-map")
	-- A Farkle table's rolls hidden from the chat: no filter with the gamepad UI; registered once
	-- back with mouse and keyboard; doing nothing from its first line after a switch back.
	local FT = ns.FarkleTable
	local auraMark = A.Mark()
	eq(FT.CanOpen(), false, "no inn or camp read on a fresh gamepad client")
	A.campAura = { spellId = 1283391 }
	eq(FT.CanOpen(), true, "own campfire aura is readable at a gamepad login")
	eq(#A.Since(auraMark), 0, "a venue check writes nothing to the game's UI")
	local was = FT.Opts().chatRolls
	FT.Opts().chatRolls = false
	before = A.Mark()
	FT.ChatFilter()
	eq(#A.Since(before), 0, "no chat filter with the gamepad UI")
	A.Switch(false); A.Advance(1)
	eq(FT.CanOpen(), true, "the same local camp is valid after switching to mouse")
	FT.ChatFilter(); FT.ChatFilter()
	local filters = {}
	for _, cb in ipairs(A.callbacks) do if cb.kind == "AddMessageEventFilter" then filters[#filters + 1] = cb end end
	eq(#filters, 1, "registered once, with mouse and keyboard"); eq(filters[1].key, "CHAT_MSG_SYSTEM")
	A.Switch(true); A.Advance(1)
	eq(FT.CanOpen(), true, "switching back keeps the read-only camp check")
	A.campAura = nil
	eq(FT.CanOpen(), false, "losing the local effect removes the camp venue")
	eq(filters[1].fn(nil, "CHAT_MSG_SYSTEM", "Someone rolls 3 (1-6)"), false, "inert with the gamepad UI")
	FT.Opts().chatRolls = was
	GP.Covers("system-filters")
	-- The companion, Olympus_Arena: Olympus's own addon, loaded on demand with the gamepad UI too.
	before = A.Mark()
	ns.Arena.LoadUI()
	local loaded = false
	for _, r in ipairs(A.Since(before)) do if r.sym == "C_AddOns.LoadAddOn" then loaded = true end end
	assert(loaded, "the companion asked for, with the gamepad UI on")
	eq(A.loadedAddOns.Olympus_Arena, true)
	GP.Covers("load-companion")
	Check(A.ledger, "the Arena")
end)

-- 1.4.0: Olympus Link is its own load-on-demand addon, Olympus_Link, not in this package. Olympus
-- asks for it once, when its saved variables are read (LinkLoader.lua, at INIT), handing its
-- namespace over for that one call; the model's LoadAddOn answers "MISSING" for a module not
-- installed and runs a stand-in module's first file for one that is (C.addOnFiles).
local function LinkLoads(C)
	local n = 0
	for _, r in ipairs(C.ledger) do if r.sym == "C_AddOns.LoadAddOn" and r.ids and r.ids[1] == "load-link" then n = n + 1 end end
	return n
end
test("gamepad pass: Olympus Link's own addon (1.4.0): asked for once at a gamepad login, the namespace handed over for that call alone; not installed, nothing of it runs; a switch each way asks nothing more", function()
	-- Not installed: one ask at the login, the game's "MISSING", no namespace left in a global.
	local C, ns = Session(true, { setup = function(c) c.missingAddOns = { Olympus_Link = true } end })
	eq(LinkLoads(C), 1, "asked once, at the gamepad login")
	eq(ns.LinkLoader.Loaded(), false); eq(ns.LinkLoader.Why(), "MISSING")
	eq(rawget(ns, "Link"), nil, "no Link without its addon")
	eq(rawget(C.env, "OlympusLinkHandoff"), nil, "the handoff cleared after the call")
	local printed = #C.printed
	ns.LinkLoader.Slash("OLC2.7K3M9QX2TB.someone.1799990000.a.ffffffff.sig")
	eq(#C.printed, printed + 1, "one line")
	assert(C.printed[#C.printed]:find(ns.L.DISCORD_NOT_INSTALLED, 1, true), "the module is not installed: " .. C.printed[#C.printed])
	assert(not C.printed[#C.printed]:find("OLC2", 1, true), "the code is never echoed")
	C.Switch(false); C.Advance(1)
	C.Switch(true); C.Advance(1)
	eq(LinkLoads(C), 1, "a switch either way asks nothing more")
	eq(ns.LinkLoader.Load(), false, "and nor does a later ask: once a session")
	eq(LinkLoads(C), 1)
	Check(C.ledger, "Olympus Link not installed")
	NoErrors(C, "Olympus Link not installed")
	-- Installed: its first file takes the namespace during the call (and only then), sets ns.Link.
	local during
	local M, mns = Session(true, { setup = function(c)
		c.addOnFiles = { Olympus_Link = function(env)
			local host = rawget(env, "OlympusLinkHandoff")
			rawset(env, "OlympusLinkHandoff", nil)
			during = host
			if type(host) == "table" and type(host.LinkLoader) == "table" and host.LinkLoader.HOST_API == 1 then
				host.Link = { Slash = function(rest) host.Print("module: " .. tostring(rest)) end, StatusLine = function() return "test module" end }
			end
		end }
	end })
	eq(LinkLoads(M), 1, "asked once, at the gamepad login")
	assert(during == mns, "the namespace handed over during the call")
	eq(rawget(M.env, "OlympusLinkHandoff"), nil, "and not after it")
	eq(mns.LinkLoader.Loaded(), true); eq(mns.LinkLoader.StatusLine(), "test module")
	mns.LinkLoader.Slash("status")
	assert(M.printed[#M.printed]:find("module: status", 1, true), "/oly discord goes to the module: " .. M.printed[#M.printed])
	M.Switch(false); M.Advance(1)
	M.Switch(true); M.Advance(1)
	eq(LinkLoads(M), 1, "loaded once: a switch changes nothing")
	Check(M.ledger, "Olympus Link installed")
	NoErrors(M, "Olympus Link installed")
	GP.Covers("load-link")
end)

-- 1.2.6, Watch duel (Daniel's duel-view request, 2026-10-19). Two players duelling in front of the
-- player: target and his target. The game's functions a watch reads that the pass doesn't model
-- (the fixture's build 70790 lists UnitHealthMax, UnitRace, UnitSex, UnitTokenFromGUID and
-- GetPlayerInfoByGUID; it predates the others) are stood in as Forever 1.60.1's own documentation
-- gives them (UnitDocumentation.lua: UnitCanAttack :763, UnitAffectingCombat :614, UnitCastingInfo
-- :828, UnitChannelInfo :870, UnitHealthMax :1472, UnitHealth :1526, UnitInParty :1637, UnitInRaid
-- :1683, UnitPower :2732, UnitPowerMax :2801, UnitPowerType :2859), with plain values (the pass has
-- no secret ones). UnitCanAttack is true between the two duellists only.
local function DuelScene(C)
	local E = C.env
	C.units.target = { name = "Duelist", realm = "Realm", guid = "Player-1-00000003" }
	C.units.targettarget = { name = "Rival", realm = "Realm", guid = "Player-1-00000004" }
	local function U(unit) return C.units[unit] end
	E.UnitCanAttack = function(a, b) return a == "target" and b == "targettarget" end
	E.UnitTokenFromGUID = function(guid)
		for _, t in ipairs({ "player", "target", "focus", "mouseover" }) do local u = U(t) if u and u.guid == guid then return t end end
		return nil
	end
	E.GetPlayerInfoByGUID = function(guid)
		for _, u in pairs(C.units) do if u.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, u.name, u.realm end end
		return nil
	end
	E.UnitRace = function(unit) if U(unit) then return "Human", "Human", 1 end end
	E.UnitSex = function(unit) if U(unit) then return 2 end end
	E.UnitPowerType = function(unit) if U(unit) then return 1, "RAGE" end end
	E.UnitHealth = function(unit) if U(unit) then return 800 end end
	E.UnitHealthMax = function(unit) if U(unit) then return 1000 end end
	E.UnitPower = function(unit) if U(unit) then return 30 end end
	E.UnitPowerMax = function(unit) if U(unit) then return 100 end end
	E.UnitAffectingCombat = function(unit) return U(unit) ~= nil and C.duelling == true end
	E.UnitCastingInfo = function() return nil end
	E.UnitChannelInfo = function() return nil end
	E.UnitInParty = function() return false end
	E.UnitInRaid = function() return nil end
	E.CanInspect = function() return true end
	E.CheckInteractDistance = function() return true end
end
-- The player menu's callbacks the game's way, on his target: the lines Olympus adds (text, click).
local function MenuLines(C)
	local lines = {}
	local function Element()
		local d = {}
		function d.SetTooltip() end
		function d.SetEnabled() end
		return d
	end
	local root = {}
	function root.CreateTitle() return Element() end
	function root.CreateButton(_, text, fn) lines[#lines + 1] = { text = text, fn = fn } return Element() end
	function root.CreateDivider() return Element() end
	for _, list in pairs(C.menus) do
		for _, fn in ipairs(list) do C.Isolated(fn, {}, root, { unit = "target", name = "Duelist", server = "Realm" }) end
	end
	return lines
end
test("gamepad duel view (1.2.6): Watch duel's line only through the player menu's hook with mouse and keyboard, its click asking for the companion alone; a watch with the gamepad UI on, and across switches both ways, reads the fighters and asks their inspection (inspect-patrol, not protected) and reaches nothing else of the game's", function()
	-- Mouse and keyboard: the line in the player menu (player-menu), the companion asked for on its click.
	local M = Session(false)
	DuelScene(M)
	local watch
	for _, l in ipairs(MenuLines(M)) do if l.text == M.ns.L.ARENA_MENU_WATCH_DUEL then watch = l end end
	assert(watch, "Watch duel in the player menu on a duellist")
	local mark = M.Mark()
	InClick(M, function() watch.fn() end)
	local loaded = false
	for _, r in ipairs(M.Since(mark)) do if r.sym == "C_AddOns.LoadAddOn" then loaded = true end end
	assert(loaded, "the click asks for the companion")
	Check(M.Since(mark), "the menu line")
	NoErrors(M, "the menu line")
	GP.Covers("player-menu"); GP.Covers("load-companion")
	-- The gamepad UI: no menu hook, so no line; a watch's own work allowed there.
	local C, ns = Session(true)
	DuelScene(C)
	eq(#MenuLines(C), 0, "no player menu line with the gamepad UI")
	local S = ns.ArenaSpectate
	local subject = assert(S.PairFromUnit("target"), "the pair: target and his target")
	eq(subject.A.name, "Duelist-Realm"); eq(subject.B.name, "Rival-Realm")
	local before = Snapshot(C)
	mark = C.Mark()
	assert(S.Start(subject))
	local bar = C.env.CreateFrame("StatusBar", nil, C.env.UIParent)
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	local w = { health = bar, healthText = text, power = bar, powerText = text }
	local function Ticks()
		S.Track(true)
		eq(S.Push("A", w), true); eq(S.Push("B", w), true)
		eq(S.Cast("A", { bar = bar }), nil)
		C.duelling = not C.duelling
		eq(S.Fighting(), C.duelling == true)
		assert(S.Text():find("Duelist", 1, true))
		C.Advance(5)
	end
	Ticks()
	local asked = 0
	for _, r in ipairs(C.Since(mark)) do if r.sym == "NotifyInspect" then asked = asked + 1 end end
	assert(asked >= 1, "his inspection asked for, with the gamepad UI too (not protected)")
	GP.Covers("inspect-patrol")
	OnlyAllowed(C.Since(mark), "a duel watch")
	local diff = Diff(before, Snapshot(C))
	eq(#diff, 0, "the game's state written: " .. table.concat(diff, ", "))
	-- Across switches both ways, the same watch goes on (the gate's own work at each switch aside).
	for _, gamepad in ipairs({ false, true }) do
		C.Switch(gamepad); C.Advance(1)
		mark = C.Mark()
		Ticks()
		Check(C.Since(mark), "a duel watch after a switch")
	end
	S.Stop()
	eq(S.Watching(), nil)
	NoErrors(C, "a duel watch")
end)

-- 1.2.1: [Olympus], [Captains] and [Lords] before a line in the game's chat, links where the player
-- may write there. A click on one the game's way: the chat window's OnHyperlinkClick calls SetItemRef
-- (the hooks on it after).
local function ClickTag(C, tier, button)
	local E = C.env
	C.chatBox = nil
	local mark = C.Mark()
	InClick(C, function() E.SetItemRef("addon:Olympus:chan:" .. tier, "[x]", button or "LeftButton", E.ChatFrame1) end)
	return C.chatBox and C.chatBox.text or nil, C.Since(mark)
end
local function TagHooks(C)
	local n = 0
	for _, cb in ipairs(C.callbacks) do if cb.kind == "hooksecurefunc" and cb.key == "SetItemRef" then n = n + 1 end end
	return n
end
test("gamepad pass 7: the chat's channel names as links: hooked once with mouse and keyboard, the chat box opened on a left click alone; with the gamepad UI no link, no hook at its login, and the hook left from before does nothing", function()
	local C, ns = Session(false)
	local Chan = ns.Channels
	eq(TagHooks(C), 1, "the post-hook on SetItemRef, with mouse and keyboard")
	eq(Chan.Tag("A"), "|Haddon:Olympus:chan:A|h[" .. ns.L.CHAN_ALL .. "]|h", "[Olympus] a link: the player writes there")
	local text, ledger = ClickTag(C, "A")
	eq(text, "/ol ", "a left click: the chat box, /ol in it")
	eq(Ids(ledger)["chat-box"], 1, "the chat box, the gate's chat-box")
	Check(ledger, "the click")
	eq(C.itemRefs[#C.itemRefs].handled, "AddOn", "the game's own handling first, as for any link")
	eq((ClickTag(C, "A", "RightButton")), nil, "a right-click: nothing, as on the plain name")
	C.chatBox = nil
	InClick(C, function() C.env.SetItemRef("item:19019", "[Thunderfury]", "LeftButton", C.env.ChatFrame1) end)
	eq(C.chatBox, nil, "another link: the game's alone")
	-- The gamepad UI: no link on a line printed now, and the hook (the game keeps it) does nothing.
	C.Switch(true); C.Advance(1)
	eq(Chan.Tag("A"), "[" .. ns.L.CHAN_ALL .. "]", "no link with the gamepad UI")
	local padText, padLedger = ClickTag(C, "A")
	eq(padText, nil, "a link printed before: no chat box with the gamepad UI")
	eq(#padLedger, 0, "nothing of the game's reached")
	-- Back to mouse and keyboard: the same hook, not a second one.
	C.Switch(false); C.Advance(1)
	eq(TagHooks(C), 1, "registered once a session")
	eq((ClickTag(C, "A")), "/ol ")
	Check(C.ledger, "the whole session")
	NoErrors(C, "the chat's channel links")
	-- A gamepad login: nothing hooked, no link; the first switch to mouse and keyboard hooks it, once.
	local P, pns = Session(true)
	eq(TagHooks(P), 0, "no hook at a gamepad login")
	eq(pns.Channels.Tag("A"), "[" .. pns.L.CHAN_ALL .. "]")
	eq((ClickTag(P, "A")), nil)
	P.Switch(false); P.Advance(1)
	eq(TagHooks(P), 1, "hooked at the switch to mouse and keyboard")
	eq((ClickTag(P, "A")), "/ol ")
	Check(P.ledger, "a gamepad login, then mouse and keyboard")
	NoErrors(P, "a gamepad login, then mouse and keyboard")
	GP.Covers("chat-links"); GP.Covers("chat-box")
end)

-- 1.5.4: a link in a line of the Chat tab (ChatWindow.lua). A left click opens the game's link
-- window as the game's chat does (SetItemRef, the gate's item-ref) with mouse and keyboard; with
-- the gamepad UI the click reaches nothing of the game's, and the hover tooltip (GameTooltip owned
-- by Olympus's own bubble) stays in both modes. An item this client holds no data of (the model's
-- client holds none) shows as sent and is asked for once.
local ITEM_LINK = "item:14342::::::::60:::::"
local ITEM_TEXT = "|cff1eff00|H" .. ITEM_LINK .. "|h[Mooncloth]|h|r"
local function LinkBubble(C, ns)
	ns.db.addonChat = true
	ns.rdb.chat = { A = { { t = C.now - 30, sender = "Aa Bb-Realm", guild = "Olympus II", text = "look " .. ITEM_TEXT .. " cheap" } } }
	local f = ns.ChatWindow.Open("A")
	assert(f, "the Chat tab")
	C.Advance(1)
	for _, b in ipairs(f.bubbles or {}) do
		if b:IsShown() and (b.body:GetText() or ""):find("Mooncloth", 1, true) then return b, f end
	end
	error("no bubble with the link")
end
local function ClickLink(C, b)
	local mark = C.Mark()
	local before = #(C.itemRefs or {})
	C.RunScript(b, "OnHyperlinkClick", ITEM_LINK, ITEM_TEXT, "LeftButton")
	return #(C.itemRefs or {}) - before, C.Since(mark)
end
test("gamepad pass: a link in the Chat tab: a left click opens the game's link window (SetItemRef) with mouse and keyboard; with the gamepad UI the click reaches nothing of the game's and the hover tooltip stays; nothing at a gamepad login until the switch", function()
	local C, ns = Session(false)
	local b = LinkBubble(C, ns)
	eq(b.body:GetText(), "look " .. ITEM_TEXT .. " cheap", "the link as sent: this client holds no data of the item")
	eq(#(C.itemsRequested or {}), 1, "asked the client for its data once"); eq(C.itemsRequested[1], 14342)
	local opened, ledger = ClickLink(C, b)
	eq(opened, 1, "the game's link window, with mouse and keyboard")
	eq(C.itemRefs[#C.itemRefs].link, ITEM_LINK); eq(C.itemRefs[#C.itemRefs].handled, "game")
	eq(Ids(ledger)["item-ref"], 1, "the gate's item-ref")
	Check(ledger, "the click")
	C.RunScript(b, "OnHyperlinkClick", "player:Someone", "[Someone]", "LeftButton")
	eq(#C.itemRefs, 1, "a player link opens nothing (the game's chat box)")
	-- The gamepad UI: the hover tooltip in Olympus's bubble; the click reaches nothing of the game's.
	C.Switch(true); C.Advance(1)
	local padOpened, padLedger = ClickLink(C, b)
	eq(padOpened, 0, "nothing with the gamepad UI")
	eq(#padLedger, 0, "nothing of the game's reached" .. (padLedger[1] and (": " .. Describe(padLedger[1])) or ""))
	local mark = C.Mark()
	C.RunScript(b, "OnHyperlinkEnter", ITEM_LINK, ITEM_TEXT)
	eq(C.env.GameTooltip:IsShown(), true, "the hover tooltip with the gamepad UI")
	eq(C.env.GameTooltip.hyperlink, ITEM_LINK)
	C.RunScript(b, "OnHyperlinkLeave")
	Check(C.Since(mark), "the hover with the gamepad UI")
	C.Switch(false); C.Advance(1)
	eq((ClickLink(C, b)), 1, "again with mouse and keyboard")
	Check(C.ledger, "the whole session")
	NoErrors(C, "the Chat tab's links")
	-- A gamepad login: the click opens nothing; after the switch to mouse and keyboard, it does.
	local P, pns = Session(true)
	local pb = LinkBubble(P, pns)
	eq((ClickLink(P, pb)), 0, "nothing at a gamepad login")
	P.Switch(false); P.Advance(1)
	eq((ClickLink(P, pb)), 1, "after the switch to mouse and keyboard")
	Check(P.ledger, "a gamepad login, then mouse and keyboard")
	NoErrors(P, "a gamepad login, then mouse and keyboard")
	GP.Covers("item-ref")
end)

test("gamepad pass: named item colours in the Chat tab use the client's RGB without changing its table, at either login and across both switches", function()
	for _, loginPad in ipairs({ false, true }) do
		local C, ns = Session(loginPad)
		-- Blizzard_Colors/Mainline/ColorManager.lua: UpdateColorsForItemQuality stores r, g, b
		-- in ITEM_QUALITY_COLORS[quality] (the table is present in the Forever API fixture).
		local colour = { r = 30 / 255, g = 1, b = 0, hex = "|cnIQ2:" }
		local colours = { [2] = colour }
		C.env.ITEM_QUALITY_COLORS = colours
		C.env.C_Item.GetItemInfo = function() return "Mooncloth", "|cnIQ2:|H" .. ITEM_LINK .. "|h[Mooncloth]|h|r", 2 end
		local b = LinkBubble(C, ns)
		for _, pad in ipairs({ loginPad, not loginPad, loginPad }) do
			C.Switch(pad); C.Advance(1)
			-- Re-read the client's colour table in each mode, rather than using the cached look.
			ns.ChatWindow.itemLooks = {}
			ns.ChatWindow.Changed(); ns.ChatWindow.Render()
			eq(b.body:GetText(), "look " .. ITEM_TEXT .. " cheap", "hex colour in either input mode")
			eq((ClickLink(C, b)), pad and 0 or 1, "the game's link window still follows the gate")
			C.RunScript(b, "OnHyperlinkEnter", ITEM_LINK, ITEM_TEXT)
			eq(C.env.GameTooltip:IsShown(), true); eq(C.env.GameTooltip.hyperlink, ITEM_LINK)
			C.RunScript(b, "OnHyperlinkLeave")
			eq(C.env.ITEM_QUALITY_COLORS, colours); eq(colours[2], colour)
			eq(colour.r, 30 / 255); eq(colour.g, 1); eq(colour.b, 0); eq(colour.hex, "|cnIQ2:")
		end
		eq(#(C.itemsRequested or {}), 0, "the item is cached")
		Check(C.ledger, "named item colours, both input modes")
		NoErrors(C, "named item colours, both input modes")
	end
	GP.Covers("lookups"); GP.Covers("item-ref")
end)

-- A moderator's cover name (Cover.lua) on a name the game updates (a nameplate's, a raid frame's):
-- the target "Someone" a councillor under a cover, this player's Yes to moderator protection.
local function CoverScene(ns)
	ns.rdb.council = { at = 1, names = { someone = "Someone" } }
	ns.rdb.covers = { ["Someone-Realm"] = { alias = "Aldric Stonebrook", t = ns.Now() } }
	ns.db.coverConsent = true
end
local function CoverFlow(C)
	C.units.target = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	local fs = C.NewWidget("FontString", nil, nil, nil, true)
	fs:SetText("Someone")
	local mark = C.Mark()
	C.env.CompactUnitFrame_UpdateName({ unit = "target", name = fs })
	C.units.target = nil
	return fs:GetText(), fs, C.Since(mark)
end
test("gamepad pass 8: cover names: written over the game's name text with mouse and keyboard, the game's own given back at a switch to the gamepad UI, nothing written there or at a gamepad login", function()
	local C, ns = Session(false)
	CoverScene(ns)
	local text, fs = CoverFlow(C)
	eq(text, "Aldric Stonebrook", "the cover name, with mouse and keyboard")
	C.Switch(true); C.Advance(1)
	eq(fs:GetText(), "Someone", "the game's name back at the switch")
	local padText, _, padLedger = CoverFlow(C)
	eq(padText, "Someone", "nothing written with the gamepad UI")
	for _, r in ipairs(padLedger) do assert(not (r.ids and r.ids[1] == "cover-names"), "nothing of cover-names: " .. Describe(r)) end
	C.Switch(false); C.Advance(1)
	eq((CoverFlow(C)), "Aldric Stonebrook", "again with mouse and keyboard")
	Check(C.ledger, "the whole session")
	NoErrors(C, "cover names")
	local P, pns = Session(true)
	CoverScene(pns)
	eq((CoverFlow(P)), "Someone", "a gamepad login: nothing written")
	P.Switch(false); P.Advance(1)
	eq((CoverFlow(P)), "Aldric Stonebrook", "hooked at the switch to mouse and keyboard")
	Check(P.ledger, "a gamepad login, then mouse and keyboard")
	NoErrors(P, "cover names, a gamepad login")
	GP.Covers("cover-names")
end)

test("gamepad main shortcut (Shift + the guild key): no binding at gamepad login, both input-style switches and saved binding changes preserve the native owner", function()
	local P, pad = Session(true)
	eq(pad.MainKey.Held(), false); eq(P.env.OlympusMainKey, nil, "no key button at a gamepad login")
	P.Switch(false); P.Advance(1); eq(pad.MainKey.Held(), true)
	P.Switch(true); eq(pad.MainKey.Held(), false, "release in the switch before native rebinding")
	P.Advance(1); Check(P.ledger, "main key switches")
	local C, ns = Session(false)
	eq(ns.MainKey.Held(), true); eq(C.bindings["SHIFT-J"], "OlympusMainKey")
	if ns.UI.IsShown() then ns.UI.Toggle() end
	eq(ns.UI.IsShown() == true, false, "start with the main window closed")
	C.Click(C.env.OlympusMainKey); eq(ns.UI.IsShown(), true)
	C.Click(C.env.OlympusMainKey); eq(ns.UI.IsShown(), false)
	C.baseBindings["SHIFT-J"] = "TOGGLEQUESTLOG"; C.Fire("UPDATE_BINDINGS")
	eq(ns.MainKey.Held(), false); eq(C.bindings["SHIFT-J"], nil); eq(C.baseBindings["SHIFT-J"], "TOGGLEQUESTLOG")
	C.Click(C.env.OlympusMainKey); eq(ns.UI.IsShown(), false, "a stale callback cannot steal the player's key")
	C.baseBindings["SHIFT-J"] = nil; C.Fire("UPDATE_BINDINGS"); eq(ns.MainKey.Held(), true)
	C.Switch(true); eq(ns.MainKey.Held(), false); C.Advance(1)
	C.Switch(false); C.Advance(1); eq(ns.MainKey.Held(), true)
	Check(C.ledger, "main key and native bindings")
	GP.Covers("main-key")
end)

test("gamepad recruit popup isolation: no native popup on either login or either input-style switch", function()
	for _, initialPad in ipairs({ false, true }) do
		local C, ns = Session(initialPad, { setup = function(c)
			c.units.player.guild = nil
			c.env.IsInGuild = function() return false end
		end })
		eq(ns.IsMember(), false, "a recruit outside any guild")
		local contact = { name = "Captain-Realm", guild = "Olympus II" }
		InClick(C, function() ns.Recruit.Prompt(contact) end)
		local f = assert(ns.Dialog.Find("OLYMPUS_RECRUIT"), "the recruit's own confirmation")
		assert(f:IsShown()); eq(f.data, contact)
		eq(C.gamePopups or 0, 0, "no shared native popup state before the guild-rank event")
		C.Switch(not initialPad); C.Advance(1)
		assert(f:IsShown(), "the editable request survives a style switch")
		C.Switch(initialPad); C.Advance(1)
		assert(f:IsShown()); eq(C.gamePopups or 0, 0)
		InClick(C, function() f.buttons[2]:Click() end)
		eq(f:IsShown(), false, "Cancel remains the player's choice")
		InClick(C, function() ns.Recruit.Prompt(contact) end)
		eq(ns.Recruit.OnRoute(contact.name, ns.Recruit.DNC_ANSWER), true)
		eq(ns.Dialog.Find("OLYMPUS_RECRUIT"), nil, "do-not-contact closes it")
		eq(C.gamePopups or 0, 0)
		Check(C.ledger, "recruit confirmation across both input styles")
		NoErrors(C, "recruit confirmation across both input styles")
	end
	GP.Covers("dialogs")
end)

test("gamepad first unguilded login opens Join once and sends nothing", function()
	local function Unguilded(C)
		C.units.player.guild = nil
		C.env.IsInGuild = function() return false end
	end
	for _, pad in ipairs({ false, true }) do
		local C, ns = Session(pad, { fresh = true, setup = Unguilded })
		local U = ns.UI
		eq(ns.db.sessions, 1)
		assert(U.IsShown(), "opens after the first login without a guild")
		eq(U.PageId(), "join")
		local view = U.SelfTestView()
		eq(view.frame.total:GetText(), "")
		eq(view.frame.sub:GetText(), "")
		eq(view.lines[2].text, ns.L.RECRUIT_JOIN_ABOUT)
		eq(view.rows[2].left.justifyH, "CENTER")
		eq(view.lines[3].text, ns.L.RECRUIT_JOIN_ACTIVITIES)
		eq(view.rows[3].left.justifyH, "CENTER")
		assert(view.lines[5].primary, "the only primary action asks to join")
		eq(#(C.whos or {}), 0, "opening the page runs no search")
		eq(#(C.said or {}), 0, "opening the page sends no whisper")
		eq(ns.Accord.Frame(), nil, "the Accord waits until the player is in Olympus")
		U.Toggle()
		C.Fire("PLAYER_ENTERING_WORLD", false, false)
		C.Advance(10)
		eq(U.IsShown(), false, "a zoning event cannot reopen a dismissed page")
		Check(C.ledger, "first Join window")
		NoErrors(C, "first Join window")

		local nextC, nextNs = Session(pad, { saved = { sessions = 1 }, setup = Unguilded })
		assert(not nextNs.UI.IsShown(), "later sessions do not auto-open Join")
		NoErrors(nextC, "later Join window")
	end
	local C, ns = Session(true, { fresh = true, setup = function(c)
		Unguilded(c)
		c.combat = true
	end })
	assert(not ns.UI.IsShown(), "waits out combat")
	C.combat = false
	C.Fire("PLAYER_REGEN_ENABLED")
	assert(ns.UI.IsShown(), "opens when combat ends")
	Check(C.ledger, "first Join window after combat")
	NoErrors(C, "first Join window after combat")
end)

test("gamepad Join Olympus onboarding searches, waits and retries through attended clicks", function()
	for _, initialPad in ipairs({ false, true }) do
		local C, ns = Session(initialPad, { setup = function(c)
			c.units.player.guild = nil
			c.env.IsInGuild = function() return c.units.player.guild ~= nil end
		end })
		local L = ns.L
		local function Row(label)
			for _, row in ipairs(ns.UI.SelfTestView().rows) do
				if row:IsShown() and row.line.text and row.line.text:find(label, 1, true) then return row end
			end
		end
		local function Draft() return ns.Dialog.Find("OLYMPUS_RECRUIT") end
		local function Retry() return ns.Dialog.Find("OLYMPUS_RECRUIT_RETRY") end
		assert(ns.UI.SelectTab("census"))
		eq(ns.UI.PageId(), "join")
		local title = assert(Row(L.RECRUIT_JOIN_TITLE))
		eq(title.left.justifyH, "CENTER")
		eq(Row(L.RECRUIT_TITLE), nil, "the guild list is collapsed")
		local sends = #(C.said or {})
		local searches = #(C.whos or {})
		local reminderOff, reminderOn = "[ ] " .. L.RECRUIT_JOIN_REMINDER, "[x] " .. L.RECRUIT_JOIN_REMINDER
		C.Click(assert(Row(reminderOff), "reminders start unchecked before the first request"))
		C.Advance(1)
		assert(Row(reminderOn), "the option shows that reminders are on")
		C.Advance(91)
		eq(Retry(), nil, "opting in alone cannot open a reminder")
		eq(#(C.said or {}), sends, "opting in alone sends no whisper")
		eq(#(C.whos or {}), searches, "opting in alone starts no native search")
		C.Click(assert(Row(L.RECRUIT_JOIN_REQUEST)).primary)
		eq(#C.whos, searches + 1, "one native search from the player's click")
		eq(Draft(), nil, "no draft without a discovered contact")
		eq(#(C.said or {}), sends, "the initial action sends no chat")
		local contacts = {
			{ fullName = "Alice-Realm", fullGuildName = "Olympus II", level = 12, filename = "MAGE" },
			{ fullName = "Zoe-Realm", fullGuildName = "Olympus II", level = 13, filename = "MAGE" },
		}
		C.env.C_FriendList.GetNumWhoResults = function() return #contacts, #contacts end
		C.env.C_FriendList.GetWhoInfo = function(i) return contacts[i] end
		C.Fire("WHO_LIST_UPDATE")
		local draft = assert(Draft(), "a completed search prepares one request")
		eq(draft.data.name, "Alice-Realm")
		eq(#(C.said or {}), sends, "the game results send no chat")
		C.Click(draft.buttons[1])
		C.Advance(1)
		eq(#C.said, sends + 1, "one whisper after Send")
		assert(Row(L.RECRUIT_JOIN_WAITING:format(44)), "countdown in the Join window")
		eq(Row(L.RECRUIT_JOIN_AGAIN).line.onClick, nil, "no retry while waiting")
		C.Fire("CHAT_MSG_WHISPER", "I'll ask an officer later.", "Alice-Realm")
		eq(ns.Recruit.replied["Alice-Realm"], "I'll ask an officer later.", "an ordinary reply was received")
		local mark = C.Mark()
		C.Advance(43)
		eq(Retry(), nil, "there is no reminder before the 45-second countdown expires")
		ns.UI.Toggle()
		eq(ns.UI.IsShown(), false)
		C.combat = initialPad
		C.Advance(1)
		if initialPad then
			eq(Retry(), nil, "the expired reminder defers in combat")
			C.combat = false
			C.Advance(3)
		end
		assert(Retry(), "an opt-in reminder appears after the deadline despite a reply or closed window")
		eq(#C.said, sends + 1, "a reminder sends no whisper")
		eq(#C.whos, searches + 1, "a reminder issues no native search")
		eq(ns.UI.IsShown(), false, "the reminder does not open the Join window by itself")
		Check(C.Since(mark), "automatic Join reminder")
		C.Click(Retry().buttons[1])
		eq(ns.UI.PageId(), "join", "retry reopens the Join page")
		assert(Row(L.RECRUIT_JOIN_TIMEOUT), "a reply does not make the invite appear to have arrived")
		eq(assert(Draft()).data.name, "Zoe-Realm", "the next contact has not already been asked")
		eq(#C.said, sends + 1)
		C.Click(Draft().buttons[1])
		eq(#C.said, sends + 2, "the new request needs its own Send click")
		C.Advance(45)
		assert(Retry(), "the second confirmed request gets its own reminder")
		if initialPad then
			C.units.player.guild = "Olympus II"
			C.Fire("PLAYER_GUILD_UPDATE", "player")
		else
			C.Click(assert(Row(reminderOn)))
			C.Advance(1)
			assert(Row(reminderOff), "the player can turn reminders off at any time")
		end
		eq(Retry(), nil, "joining or turning reminders off closes the current popup")
		C.Advance(100)
		eq(Retry(), nil, "joining or turning reminders off stops future popups")
		NoErrors(C, "Join Olympus")
	end
end)

test("gamepad centered Census recruitment offers the Church intake and both dismissal choices", function()
	for _, initialPad in ipairs({ false, true }) do
		local C, ns = Session(initialPad)
		local U, R, V, L = ns.UI, ns.Recruit, ns.Views, ns.L
		local function Row(id)
			for _, row in ipairs(U.SelfTestView().rows) do
				if row:IsShown() and row.line.id == "census-recruit-" .. id then return row end
			end
		end
		local function Reopen()
			U.Toggle(); U.Toggle()
		end
		U.Toggle()
		local view = U.SelfTestView()
		eq(U.PageId(), "census/recruitment")
		local title = false
		for _, line in ipairs(view.lines) do
			if line.text == L.RECRUIT_CENSUS_TITLE then title = line.center end
			assert(not line.input, "the search returns after leaving the centered offer")
		end
		eq(title, true, "the offer's heading is centered")
		eq(view.frame.colHeader:IsShown(), false, "guild columns are absent from the offer")
		eq(view.frame.detail:IsShown(), false, "the offer fills the Census body")
		for _, button in ipairs(view.buttons) do eq(button:IsShown(), false, "hide regular footer actions") end
		eq(assert(Row("enable")).primary:GetText(), L.RECRUIT_CENSUS_ENABLE)
		C.Click(assert(Row("later")))
		eq(U.PageId(), "census/")
		assert(U.SelfTestView().lines[1].input, "leaving it off immediately restores the Census")
		U.Refresh()
		eq(Row("enable"), nil, "background refresh does not reopen the offer")
		Reopen()
		assert(Row("enable"), "leaving it off defers the offer until the next window opening")
		V.SetFilter("census", "anything"); U.Refresh()
		eq(Row("enable"), nil, "search keeps its ordinary results")
		V.SetFilter("census", ""); U.Refresh()

		local mark = C.Mark()
		local sends = #(C.said or {})
		C.Click(assert(Row("enable")).primary)
		eq(Row("enable"), nil, "the offer disappears while active")
		assert(R.WhisperLines()[1].text:find(L.RECRUIT_WHISPER_ON, 1, true), "Church shows the active intake")
		local printed
		for _, line in ipairs(C.printed) do
			if line:find(L.RECRUIT_CENSUS_ENABLED, 1, true) then printed = true end
		end
		eq(printed, true, "the click confirms activation")
		eq(R.EnableWhisperRecruiting(), false, "a stale click cannot turn it off")
		C.Fire("CHAT_MSG_WHISPER", "JOIN", "Recruit-Realm")
		eq(#R.requests, 1, "the normal JOIN intake is active")
		eq(#(C.said or {}), sends, "activation sends no whispers")
		for _, reach in ipairs(C.Since(mark)) do
			assert(reach.sym ~= "C_GuildInfo.Invite", "activation grants no native invite")
		end

		R.WhisperLines()[1].onClick()
		Reopen()
		eq(Row("enable"), nil, "turning recruitment off in Church leaves it off without another offer")
		-- Exercise the separate Never choice on an account with no recruiting decision yet.
		ns.rdb.recruitmentPreference[ns.me] = nil
		local oldRecord, oldVerify = ns.Record.Line, ns.Verify.Lines
		ns.Record.Line = function() return { id = "test-record", text = "Record" } end
		ns.Verify.Lines = function() return { { id = "test-verify", text = "Verification" } } end
		Reopen()
		view = U.SelfTestView()
		eq(view.lines[1].id, "test-record", "Record remains above the prompt")
		eq(view.lines[2].id, "test-verify", "verification stays reachable above the prompt")
		ns.Record.Line, ns.Verify.Lines = oldRecord, oldVerify
		C.Click(assert(Row("never")))
		eq(ns.db.hideRecruitmentOffer, true, "the opt-out lives in the account database")
		Reopen()
		eq(Row("enable"), nil, "the opt-out survives window reopening")
		assert(R.WhisperLines()[1].text:find(L.RECRUIT_WHISPER_OFF, 1, true), "Church can still turn it on")

		ns.db.hideRecruitmentOffer = nil
		C.env.CanGuildInvite = function() return false end
		Reopen()
		eq(Row("enable"), nil, "players without native invite permission see the normal Census")
		eq(R.EnableWhisperRecruiting(), false)
		C.units.player.guild = nil
		C.env.IsInGuild = function() return false end
		C.Fire("PLAYER_GUILD_UPDATE", "player")
		U.Refresh()
		eq(Row("enable"), nil, "outsiders cannot enable recruitment")
		NoErrors(C, "Census recruitment")
	end
end)

test("gamepad recruitment restores only this guild choice and keeps JOIN in the queue", function()
	for _, initialPad in ipairs({ false, true }) do
		local saved = Answered()
		local C, ns = Session(initialPad, { saved = saved })
		local R = ns.Recruit
		local function ArrivalLine(recruit)
			for _, line in ipairs(recruit.WhisperLines()) do
				if line.id == "recruit-whisper-arrival" then return line end
			end
		end
		eq(R.IsWhisperRecruiting(), false, "a new character starts opted out")
		InClick(C, function() eq(R.EnableWhisperRecruiting(), true) end)
		local choice = assert(ArrivalLine(R))
		assert(choice.text:find(ns.L.RECRUIT_WHISPER_POPUP_ON, 1, true), "pop-up is the default")
		C.Fire("CHAT_MSG_WHISPER", "JOIN", "FirstApplicant-Realm")
		eq(#R.requests, 1)
		assert(ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT") or ns.Dialog.Find("OLYMPUS_RECRUIT_REPLY"))
		InClick(C, choice.onClick)

		local reloaded, nextNS = Session(initialPad, { saved = saved })
		local nextR = nextNS.Recruit
		eq(nextR.IsWhisperRecruiting(), true, "restores the explicit opt-in for the current guild")
		eq(#nextR.requests, 0, "no previously received names are loaded")
		assert(ArrivalLine(nextR).text:find(nextNS.L.RECRUIT_WHISPER_QUEUE_ONLY, 1, true))
		local sends = #(reloaded.said or {})
		reloaded.Fire("CHAT_MSG_WHISPER", "JOIN", "NewApplicant-Realm")
		eq(#nextR.requests, 1, "the new request reaches the Church queue")
		assert(nextR.requests[1].name:find("NewApplicant", 1, true))
		eq(nextNS.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT"), nil)
		eq(nextNS.Dialog.Find("OLYMPUS_RECRUIT_REPLY"), nil)
		local announced = false
		for _, line in ipairs(reloaded.printed) do
			if line:find("NewApplicant", 1, true) then announced = true end
		end
		eq(announced, true, "queue-only still prints the normal chat notice")
		eq(#(reloaded.said or {}), sends, "restored intake does not send anything")

		local permission = true
		reloaded.env.CanGuildInvite = function() return permission end
		permission = false
		reloaded.Fire("GUILD_ROSTER_UPDATE")
		eq(nextR.IsWhisperRecruiting(), false, "lost native invite permission suspends recruiting")
		eq(#nextR.requests, 0, "loss of eligibility clears pending requests")
		permission = true
		reloaded.Fire("GUILD_ROSTER_UPDATE")
		eq(nextR.IsWhisperRecruiting(), true, "the opt-in returns when the same guild restores permission")
		reloaded.units.player.guild = "Olympus III"
		reloaded.Fire("PLAYER_GUILD_UPDATE", "player")
		eq(nextR.IsWhisperRecruiting(), false, "the saved choice cannot activate a different guild")
		reloaded.units.player.guild = "Olympus II"
		reloaded.Fire("PLAYER_GUILD_UPDATE", "player")
		eq(nextR.IsWhisperRecruiting(), true)
		local other, otherNS = Session(initialPad, { saved = saved, setup = function(client)
			client.units.player.name = "OtherCharacter"
		end })
		eq(otherNS.Recruit.IsWhisperRecruiting(), false, "another character on the same account starts off")
		InClick(reloaded, function() eq(nextR.ToggleWhisperRecruiting(), false) end)
		local afterOff, offNS = Session(initialPad, { saved = saved })
		eq(offNS.Recruit.IsWhisperRecruiting(), false, "explicitly turning it off survives login")
		NoErrors(C, "original recruitment session")
		NoErrors(reloaded, "reloaded recruitment session")
		NoErrors(other, "different recruiting character")
		NoErrors(afterOff, "recruitment disabled session")
	end
end)

test("gamepad attended recruit candidate queue uses scoped sightings and explicit WHO records", function()
	for _, initialPad in ipairs({ false, true }) do
		local C, ns = Session(initialPad)
		local R = ns.Recruit
		assert(ns.UI.SelectTab("church"))
		local frame = assert(Main(C))
		local function ClickLine(predicate)
			for _, row in ipairs(ns.UI.SelfTestView().rows) do
				if row:IsShown() and row.line and predicate(row.line) then C.Click(row); return end
			end
			error("missing recruitment line")
		end
		local function QueueLine(fragment)
			for _, line in ipairs(ns.UI.SelfTestView().lines) do
				if line.text and line.text:find(fragment, 1, true) then return line end
			end
		end
		local function Refresh() ns.UI.Refresh() end
		local invite
		for _, strip in ipairs(rawget(frame, "pageNavRows") or {}) do
			for _, tab in ipairs(rawget(strip, "nav") or {}) do
				if tab.item and tab.item.text == ns.L.CHURCH_NAV_INVITES then invite = tab end
			end
		end
		C.Click(assert(invite)); Refresh()
		ClickLine(function(line) return line.onClick == R.ToggleWhisperRecruiting end)
		Refresh()
		-- Keep the real ticker, with no random start spread in this scenario.
		ns.EVERY_SPREAD = 0
		C.units.nameplate2 = { name = "NearTest", realm = "Realm", guid = "Player-1-2" }
		ClickLine(function(line) return line.id == "recruit-candidate-toggle" end)
		Refresh()
		assert(QueueLine("NearTest"), "opting in captures already visible nameplates")
		local function Plate(index, name, guild, faction)
			local unit = "nameplate" .. index
			C.units[unit] = { name = name, realm = "Realm", guild = guild, faction = faction, guid = "Player-1-" .. index }
			C.Fire("NAME_PLATE_UNIT_ADDED", unit)
		end
		local sends, searches = #(C.said or {}), #(C.whos or {})
		local start = C.Mark()
		-- This scenario has both factions on screen, unlike the default all-Alliance model.
		C.env.UnitFactionGroup = function(unit)
			local player = C.units[unit]
			if player then return player.faction or "Alliance" end
		end
		Plate(2, "NearTest", nil, "Alliance")
		C.units.target = C.units.nameplate2
		C.Fire("PLAYER_TARGET_CHANGED")
		Plate(3, "WrongSide", nil, "Horde")
		Plate(4, "AlreadyGuilded", "Sister Guild", "Alliance")
		local who = {
			{ fullName = "WhoTest-Realm", fullGuildName = "", raceStr = "Human" },
			{ fullName = "UnknownWho-Realm", raceStr = "Human" },
			{ fullName = "HordeWho-Realm", fullGuildName = "", raceStr = "Orc" },
			{ fullName = "OtherRealm-Elsewhere", fullGuildName = "", raceStr = "Human" },
		}
		C.env.C_FriendList.GetNumWhoResults = function() return #who, #who end
		C.env.C_FriendList.GetWhoInfo = function(i) return who[i] end
		C.Fire("WHO_LIST_UPDATE")
		Refresh()
		assert(QueueLine("NearTest"), "a live unguilded friendly player is in the queue")
		assert(QueueLine("WhoTest"), "an explicitly empty, scoped WHO result is in the same queue")
		for _, name in ipairs({ "WrongSide", "AlreadyGuilded", "UnknownWho", "HordeWho", "OtherRealm" }) do
			eq(QueueLine(name), nil, "unsupported candidate " .. name)
		end
		local copies = 0
		for _, line in ipairs(ns.UI.SelfTestView().lines) do
			if line.text and line.text:find("NearTest", 1, true) then copies = copies + 1 end
		end
		eq(copies, 1, "target and plate observations are deduplicated")
		eq(ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT"), nil, "collection defaults to list only")
		local function Draft() return ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT") end
		ClickLine(function(line) return line.text and line.text:find("WhoTest", 1, true) end)
		eq(assert(Draft()).editBox:GetText(), "/ginvite WhoTest")
		Draft():Hide()
		ClickLine(function(line) return line.id == "recruit-candidate-prompts" end)
		C.Advance(15.1)
		local copy = assert(Draft())
		eq(copy.editBox:GetText(), "/ginvite NearTest", "only a live observation opens an automatic draft")
		Plate(5, "NextTest", nil, "Alliance")
		C.Advance(15.1)
		eq(Draft(), copy, "an open draft is never replaced by the timer")
		copy:Hide()
		C.units.nameplate5.guild = "New Guild"
		C.Advance(15.1)
		eq(Draft(), nil, "fresh native recheck refuses a player who joined a guild")
		Refresh()
		eq(QueueLine("WhoTest"), nil, "WHO results expire quickly")
		eq(#(C.said or {}), sends, "observation and copy drafts send no chat")
		eq(#(C.whos or {}), searches, "the queue issues no WHO queries")
		ClickLine(function(line) return line.text and line.text:find(ns.L.RECRUIT_CANDIDATE_WHISPER, 1, true) end)
		local whisper = assert(ns.Dialog.Find("OLYMPUS_RECRUIT_OUTREACH"))
		eq(#(C.said or {}), sends, "opening the private draft does not whisper")
		C.Click(whisper.buttons[1])
		eq(#(C.said or {}), sends + 1, "one explicit Send whispers the live player")
		ClickLine(function(line) return line.id == "recruit-candidate-prompts" end)
		assert(QueueLine(ns.L.RECRUIT_CANDIDATE_WHISPER_OFF), "whisper reminders start disabled")
		ClickLine(function(line) return line.id == "recruit-candidate-whisper-reminder" end)
		Refresh()
		assert(QueueLine(ns.L.RECRUIT_CANDIDATE_WHISPER_EVERY:format(2)))
		Plate(6, "TimedWhisper", nil, "Alliance")
		C.Advance(105)
		who[1].fullName = "WhoOnlyAgain-Realm"
		C.Fire("WHO_LIST_UPDATE")
		eq(ns.Dialog.Find("OLYMPUS_RECRUIT_OUTREACH"), nil, "the reminder waits for its interval")
		C.Advance(35)
		local timed = assert(ns.Dialog.Find("OLYMPUS_RECRUIT_OUTREACH"))
		eq(timed.data.queue[1].name, "TimedWhisper", "skip recently contacted and WHO-only candidates")
		eq(#(C.said or {}), sends + 1, "the scheduled draft sends nothing on its own")
		C.Advance(105)
		Plate(7, "AnotherWhisper", nil, "Alliance")
		C.Advance(35)
		eq(ns.Dialog.Find("OLYMPUS_RECRUIT_OUTREACH"), timed, "a later interval leaves the pending draft alone")
		eq(#(C.said or {}), sends + 1)
		timed:Hide()
		for _, call in ipairs(C.Since(start)) do
			assert(call.sym ~= "C_GuildInfo.Invite" and call.sym ~= "GuildInvite", "no native guild invitation")
		end
		for i = 10, 41 do Plate(i, "Candidate" .. i, nil, "Alliance") end
		Refresh()
		local bounded = 0
		for _, line in ipairs(ns.UI.SelfTestView().lines) do
			if line.text and line.text:find("Copy invite (nearby)", 1, true) then bounded = bounded + 1 end
		end
		eq(bounded, 24, "the session queue is bounded")
		ClickLine(function(line) return line.id == "recruit-candidate-toggle" end)
		Refresh()
		eq(QueueLine("Candidate41"), nil, "turning collection off discards observations")
		NoErrors(C, "recruit candidate queue")
	end
end)

test("gamepad whisper recruiting: deliberate outreach and native invite copy in both input modes", function()
	for _, initialPad in ipairs({ false, true }) do
		local C, ns = Session(initialPad)
		local R = ns.Recruit
		assert(ns.UI.SelectTab("church"))
		ns.ChurchView.Show("people"); ns.UI.Refresh()
		local frame = assert(Main(C))
		local function FindLine(predicate)
			for _, line in ipairs(ns.UI.SelfTestView().lines) do if predicate(line) then return line end end
		end
		local function ToggleLine()
			return FindLine(function(line) return line.onClick == R.ToggleWhisperRecruiting end)
		end
		eq(ToggleLine(), nil, "the Church's ordinary pages do not show the experiment")
		local invite
		for _, strip in ipairs(rawget(frame, "pageNavRows") or {}) do
			for _, tab in ipairs(rawget(strip, "nav") or {}) do
				if tab.item and tab.item.text == ns.L.CHURCH_NAV_INVITES then invite = tab end
			end
		end
		assert(invite and invite:IsVisible(), "Invites is in the Church tab strip")
		C.Click(invite); C.Advance(1)
		eq(ns.UI.PageId(), "church/invites")
		assert(ToggleLine().text:find(ns.L.RECRUIT_WHISPER_OFF, 1, true))
		C.Fire("CHAT_MSG_WHISPER", "JOIN OLYMPUS", "Stranger-Realm")
		eq(#R.requests, 0, "off by default")
		InClick(C, function() ToggleLine().onClick() end); ns.UI.Refresh()
		assert(ToggleLine().text:find(ns.L.RECRUIT_WHISPER_ON, 1, true))
		eq(FindLine(function(line) return line.text and line.text:find("Your mouse does not", 1, true) end), nil,
			"the recruiting panel omits the autoclicker joke")
		C.Fire("CHAT_MSG_WHISPER", "join me later", "Stranger-Realm")
		eq(#R.requests, 0, "ordinary unsolicited whispers do not queue anyone")

		local target = { name = "Newbie", realm = "Realm", guid = "Player-1-00000002", guild = "Another Guild" }
		C.units.target = target
		InClick(C, function() eq(R.PromptOutreach(), false, "do not prompt for a player with a guild") end)
		local function Printed(text)
			for _, line in ipairs(C.printed) do if line:find(text, 1, true) then return true end end
			return false
		end
		assert(Printed(ns.L.RECRUIT_WHISPER_SCAN:format(1, 0, 0, 0)), "the target was seen without a nameplate")
		assert(Printed(ns.L.RECRUIT_WHISPER_FILTERS:format(1, 0, 0, 0, 0, 0)), "the target's guild explains the exclusion")
		assert(Printed(ns.L.RECRUIT_WHISPER_EMPTY), "the empty scan explains the nameplate and target options")
		target.guild = nil
		C.units.nameplate1 = target -- duplicate unit token for the selected player
		C.units.nameplate2 = { name = "Nearby", realm = "Realm", guid = "Player-1-00000004" }
		C.units.nameplate97 = { name = "Last", realm = "Realm", guid = "Player-1-00000005" }
		C.units.nameplate4 = { name = "Invisible", realm = "Realm", guid = "Player-1-00000006", visible = false }
		local sends = #(C.said or {})
		InClick(C, function() eq(R.PromptOutreach(), true) end)
		local draft = assert(ns.Dialog.Find("OLYMPUS_RECRUIT_OUTREACH"))
		assert(Printed(ns.L.RECRUIT_WHISPER_SCAN:format(1, 0, 4, 3)), "nameplate indices above 40 are scanned")
		assert(Printed(ns.L.RECRUIT_WHISPER_FILTERS:format(0, 1, 0, 0, 0, 1)), "hidden and duplicate units are counted")
		eq(draft.editBox:GetText(), "Hey! Want to join Olympus? Over 45,000 strong across all servers and counting. Whisper JOIN if you're interested.")
		eq(#(C.said or {}), sends, "only a draft was opened")
		C.Switch(not initialPad); C.Advance(1)
		C.units.target = { name = "Other", realm = "Realm", guid = "Player-1-00000003" }
		C.Click(draft.buttons[1])
		eq(#(C.said or {}), sends, "the selected target changed before Send")
		C.units.target = target
		C.Click(draft.buttons[1])
		eq(#C.said, sends + 1); eq(C.said[#C.said][2], "WHISPER"); eq(C.said[#C.said][3], "Newbie")
		assert(draft.text:GetText():find("Nearby", 1, true), "the next visible name is ready for review")
		C.Click(draft.buttons[1])
		eq(#C.said, sends + 1, "each Send stays paced")
		C.Switch(initialPad); C.Advance(21)
		C.now = C.now + 21
		C.units.nameplate2.guild = "Another Guild"
		C.Click(draft.buttons[1])
		eq(#C.said, sends + 1, "a newly guilded unit is refused")
		C.Click(draft.buttons[2])
		assert(draft.text:GetText():find("Last", 1, true))
		eq(#C.said, sends + 1, "Skip prepares another draft and sends nothing")
		InClick(C, function() draft.editBox:GetScript("OnEnterPressed")(draft.editBox) end)
		eq(#C.said, sends + 2); eq(C.said[#C.said][3], "Last")
		eq(draft:IsShown(), false, "the queue ignores invisible and already contacted units")
		InClick(C, function() eq(R.PromptOutreach(), false, "recent contacts are not offered again") end)
		C.Fire("CHAT_MSG_WHISPER", " Interested if you raid Tuesdays |cffaabbcc ", "Newbie-Realm")
		C.Fire("CHAT_MSG_WHISPER", "JOIN OLYMPUS", "Newbie-Realm")
		eq(#R.requests, 1, "the contacted player's ordinary reply queues one request")
		local reply = assert(ns.Dialog.Find("OLYMPUS_RECRUIT_REPLY"), "a direct reply shows the invite action")
		assert(reply.text:GetText():find("Interested if you raid Tuesdays ||cffaabbcc", 1, true), "reply content is shown safely")
		eq(C.chatBox, nil, "the prompt has not touched Blizzard chat")
		local req = R.requests[1]
		eq(req.name, "Newbie-Realm")
		C.env.CanGuildInvite = function() return false end
		InClick(C, function() eq(R.Accept(req), false, "rank changed before the click") end)
		C.env.CanGuildInvite = function() return true end
		local mark = C.Mark()
		C.Click(reply.buttons[1])
		local copy = assert(ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT"))
		eq(copy.editBox:GetText(), "/ginvite Newbie")
		eq(#R.requests, 1, "preparing a command does not count it as sent")
		for _, call in ipairs(C.Since(mark)) do
			assert(call.sym ~= "C_GuildInfo.Invite" and call.sym ~= "GuildInvite", "no native guild call")
		end
		eq(C.chatBox, nil, "nothing was entered in Blizzard chat")
		eq(#C.said, sends + 2, "intake and invite preparation sent nothing")
		C.now = C.now + 21
		C.Fire("CHAT_MSG_WHISPER", "  jOiN  ", "Stranger-Realm")
		eq(#R.requests, 2, "an open invite draft queues the request")
		eq(copy.editBox:GetText(), "/ginvite Newbie", "keep the current invite draft")
		C.Click(copy.buttons[1])
		C.combat = true
		C.Fire("CHAT_MSG_WHISPER", "JOIN OLYMPUS", "Another-Realm")
		eq(#R.requests, 3, "the former keyword also queues while in combat")
		eq(ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT"), nil, "no invite draft in combat")
		C.combat = false
		C.Fire("CHAT_MSG_WHISPER", "  jOiN  ", "Interested-Realm")
		eq(#R.requests, 4)
		local independent = assert(ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT"), "the earliest waiting JOIN opens without prior outreach")
		local incoming = R.requests[2]
		eq(independent.editBox:GetText(), "/ginvite Stranger")
		assert(independent.editBox:HasFocus(), "the command can be copied immediately")
		eq(independent.editBox.selectionStart, 0)
		eq(independent.editBox.selectionEnd, #independent.editBox:GetText())
		eq(incoming.invitePrepared, nil, "an automatic display does not take the request out of handoff")
		eq(#C.said, sends + 2, "a new request never sends anything by itself")
		local function HasQueue(line) return line.text == ns.L.JOIN_REQUESTS:format(4) end
		ns.UI.Refresh()
		assert(FindLine(HasQueue), "Church Invites shows the incoming JOIN queue")
		local fresh, rankOf = ns.Roster.Fresh, ns.Roster.RankOf
		local joined = function(line) return line.text and line.text:find(ns.L.RECRUIT_WHISPER_JOINED, 1, true) end
		eq(FindLine(joined), nil, "an invite draft alone does not show anyone as joined")
		ns.Roster.RankOf = function(name) if name == req.name then return 3 end return rankOf(name) end
		ns.Roster.Fresh = function() return false end
		ns.UI.Refresh()
		eq(FindLine(joined), nil, "a stale roster cannot confirm joining")
		ns.Roster.Fresh = function() return true end
		ns.UI.Refresh()
		assert(FindLine(joined), "a fresh roster confirms the applicant is in this guild")
		ns.Roster.Fresh, ns.Roster.RankOf = fresh, rankOf
		assert(ns.UI.SelectTab("census"))
		eq(FindLine(HasQueue), nil, "the experiment's queue stays out of Census")
		eq(ToggleLine(), nil)
		eq(assert(Main(C)).buttons[2]:GetText(), ns.L.REFRESH, "manual Census Refresh remains")
		assert(ns.UI.SelectTab("church"))
		InClick(C, function() ToggleLine().onClick() end)
		eq(#R.requests, 0); eq(independent:IsShown(), false)
		Check(C.ledger, "recruiting through both input styles")
		NoErrors(C, "recruiting")
	end
	GP.Covers("dialogs")
	GP.Covers("roster-actions")
	GP.Covers("arena-clicks")
end)

test("gamepad incoming JOIN advances the pending replies in order without interrupting game chat", function()
	for _, pad in ipairs({ false, true }) do
		local C, ns = Session(pad)
		local R = ns.Recruit
		R.ToggleWhisperRecruiting()
		local chat = C.env.ChatFrame1EditBox
		local function Draft() return ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT") end
		local function Advance(seconds) C.now = C.now + seconds; C.Advance(seconds) end
		chat:Show(); chat:SetText("a message in progress"); C.focus = chat
		C.Fire("CHAT_MSG_WHISPER", "JOIN OLYMPUS", "First-Realm")
		Advance(4)
		eq(Draft(), nil, "while game chat has focus, the request stays queued")
		eq(C.focus, chat)
		eq(chat:GetText(), "a message in progress")
		chat:ClearFocus(); chat:Hide(); Advance(2)
		local draft = assert(Draft()); eq(draft.editBox:GetText(), "/ginvite First")
		C.Fire("CHAT_MSG_WHISPER", "JOIN", "Second-Realm")
		C.Fire("CHAT_MSG_WHISPER", "JOIN", "Third-Realm")
		Advance(20)
		eq(Draft(), draft, "later JOINs never replace the open draft")
		eq(draft.editBox:GetText(), "/ginvite First")
		if pad then C.Click(draft.buttons[1]) else C.Click(draft.extraButton) end
		eq(Draft(), nil)
		chat:Show(); C.focus = chat
		Advance(20)
		eq(Draft(), nil, "closing the Olympus window waits for the native chat editor")
		chat:ClearFocus(); chat:Hide()
		C.combat = true; Advance(4)
		eq(Draft(), nil, "combat also defers a queued popup")
		C.combat = false; Advance(2)
		draft = assert(Draft()); eq(draft.editBox:GetText(), "/ginvite Second")
		C.Click(draft.buttons[1])
		assert(R.HandoffSource(R.requests[2]), "closing still leaves a transferable request")
		local arrival
		for _, line in ipairs(R.WhisperLines()) do if line.id == "recruit-whisper-arrival" then arrival = line end end
		InClick(C, assert(arrival).onClick)
		Advance(21)
		eq(Draft(), nil, "queue-only prevents the next automatic popup")
		InClick(C, arrival.onClick)
		draft = assert(Draft()); eq(draft.editBox:GetText(), "/ginvite Third")
		C.Click(draft.buttons[1])
		Advance(21)
		eq(Draft(), nil, "shown requests do not reappear")
		C.env.CanGuildInvite = function() return false end
		C.Fire("CHAT_MSG_WHISPER", "JOIN", "Fourth-Realm")
		eq(Draft(), nil, "only a player with invite authority sees the command")
		eq(#R.requests, 3, "the shown requests remain available to review")
		eq(#(C.said or {}), 0, "advancing never sends chat or an invitation")
		Check(C.ledger, "incoming JOIN focus and permissions")
		NoErrors(C, "incoming JOIN focus and permissions")
	end
	GP.Covers("popup-focus")
end)

test("gamepad Forever Join requests can copy a command and open empty game chat only in mouse mode", function()
	for _, pad in ipairs({ false, true }) do
		local C, ns = Session(pad, { realmFrom = function() return "CAMWOWUS2Realm1PvE" end, surname = "Recruiter" })
		assert(ns.OnForever(), "the live Forever rules")
		local R, guild = ns.Recruit, C.units.player.guild
		local sender = "New Recruit-CAMWOWUS2Realm1PvE"
		eq(R.OnJoinRequest("WHISPER", sender, ("J3~%s~12~MAGE"):format(guild)), true)
		local req = assert(R.requests[1])
		local action
		for _, row in ipairs(R.RequestLines(false)) do
			if row.text:find(ns.L.RECRUIT_WHISPER_PREPARE_BUTTON, 1, true) then action = row.onClick end
		end
		assert(action, "the guild officer can prepare the native command")
		local mark = C.Mark()
		InClick(C, action)
		local draft = assert(ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT"))
		eq(draft.editBox:GetText(), "/ginvite New Recruit")
		eq(R.requests[1], req, "preparing the command does not send the invitation")
		eq(C.chatBox, nil, "the command is not injected into Blizzard's chat")
		for _, call in ipairs(C.Since(mark)) do
			assert(call.sym ~= "C_GuildInfo.Invite" and call.sym ~= "GuildInvite", "no native guild call")
		end
		local function Key(script, key)
			local action = assert(draft.editBox:GetScript(script), "the copy box handles the keyboard shortcut")
			InClick(C, function() action(draft.editBox, key) end)
		end
		local open, target = C.env.ChatFrameUtil.OpenChat
		C.env.ChatFrameUtil.OpenChat = function(text, frame)
			target = frame
			return open(text, frame)
		end
		local ctrl = false
		C.env.IsControlKeyDown = function() return ctrl end
		Key("OnKeyDown", "C"); Key("OnKeyUp", "C")
		eq(C.chatBox, nil, "typing C is not a copy")
		ctrl = true
		Key("OnKeyDown", "C")
		eq(C.chatBox, nil, "the copy box still has focus during the native copy")
		ctrl = false
		Key("OnKeyUp", "C")
		if pad then
			eq(C.chatBox, nil, "gamepad leaves the copy box open")
			eq(draft:IsShown(), true)
			C.Switch(false)
			C.Click(draft.extraButton)
		end
		eq(assert(C.chatBox).text, "", "the player pastes into empty game chat")
		eq(target, C.env.DEFAULT_CHAT_FRAME, "an unrelated focus override cannot receive the paste")
		eq(draft:IsShown(), false)
		eq(R.requests[1], req)
		for _, call in ipairs(C.Since(mark)) do
			assert(call.sym ~= "C_GuildInfo.Invite" and call.sym ~= "GuildInvite", "no protected guild call")
		end
		C.Switch(true)
		Check(C.ledger, "copy and hand off to game chat")
		NoErrors(C, "Forever Join requests")
	end
	GP.Covers("chat-box")
end)

test("gamepad public recruiting announcement: reminder dropdown, independent channels and explicit Post or Enter", function()
	for _, initialPad in ipairs({ false, true }) do
		local C, ns = Session(initialPad)
		local L, R = ns.L, ns.Recruit
		C.channels.General, C.channels.Trade, C.channels.Private, C.channels.OlympusNet = 1, 2, 3, 5
		C.env.C_ChatInfo.GetChannelInfoFromIdentifier = function(name)
			local ids = { General = 11, Trade = 22, Private = 0, OlympusNet = 55 }
			return ids[name] and { zoneChannelID = ids[name] } or nil
		end
		local census = {
			{ counted = true, fresh = true, validation = "accepted", src = "own", characters = 35001 },
			{ counted = true, fresh = true, validation = "accepted", src = "witnessed", characters = 9999 },
			{ counted = true, fresh = false, validation = "accepted", src = "author", characters = 50000 },
			{ counted = false, fresh = true, validation = "reported", src = "heard", characters = 60000 },
			{ counted = true, fresh = true, validation = "accepted", src = "own", era = "beta", characters = 80000 },
		}
		ns.Data.Groups = function() return { rows = census } end
		local function Find(text)
			for _, line in ipairs(R.WhisperLines()) do if line.text and line.text:find(text, 1, true) then return line end end
		end
		local function ClickLine(text)
			InClick(C, function() assert(Find(text), text).onClick() end)
		end
		local function ReminderChoices()
			for _, line in ipairs(R.WhisperLines()) do
				if line.id == "recruit-announcement-reminder" then return line.filters[1].options end
			end
		end
		local function Printed(text, start)
			for i = (start or 0) + 1, #C.printed do if C.printed[i]:find(text, 1, true) then return true end end
			return false
		end
		local function Draft() return ns.Dialog.Find("OLYMPUS_RECRUIT_ANNOUNCEMENT") end
		local function Post(text, sender, index, zoneID, channel)
			C.Fire("CHAT_MSG_CHANNEL", text, sender, "", channel, "", "", zoneID, index, channel)
		end

		local header = assert(Find(L.RECRUIT_ANNOUNCE_OPEN))
		assert(header.header and not header.onClick, "the announcement heading needs no click")
		local general, trade = L.RECRUIT_ANNOUNCE_CHANNEL:format(1, "General"), L.RECRUIT_ANNOUNCE_CHANNEL:format(2, "Trade")
		assert(Find(general) and Find(trade), "joined public channels are immediately visible")
		eq(Find(L.RECRUIT_ANNOUNCE_CHANNEL:format(3, "Private")), nil, "private channels are omitted")
		eq(Find(L.RECRUIT_ANNOUNCE_CHANNEL:format(5, "OlympusNet")), nil, "Olympus is omitted even if reported with a zone ID")
		local intervals = assert(ReminderChoices())
		eq(#intervals, 6)
		eq(intervals[1].text, L.RECRUIT_ANNOUNCE_REMINDER_OFF)
		eq(intervals[1].selected, true, "off by default")
		for i, minutes in ipairs({ 2, 5, 10, 15, 30 }) do
			eq(intervals[i + 1].text, L.RECRUIT_ANNOUNCE_REMINDER_ON:format(minutes))
			eq(intervals[i + 1].selected, false)
		end
		local tip
		assert(Find(L.RECRUIT_ANNOUNCE_REMINDER_ROTATE)).tooltip({ AddLine = function(_, message) tip = message end })
		eq(tip, L.RECRUIT_ANNOUNCE_REMINDER_TIP, "the control explains the draft and the explicit Post action")
		local sends = #(C.said or {})
		ClickLine(general)
		local draft = assert(Draft())
		eq(draft.editBox:GetText(), ("/1 %s is recruiting! Over 44,000 characters across servers and counting. Whisper JOIN if you're interested."):format(C.units.player.guild))
		C.Click(draft.buttons[1])
		eq(C.chatBox, nil, "no game chat box was opened")

		Post("I plan to join Olympus tomorrow", "Other-Realm", 1, 11, "General")
		ClickLine(general); assert(Draft(), "a casual line does not trigger the recruiting cooldown")
		Post("Olympus is recruiting, PST for an invite!", "Other-Realm", 2, 22, "Trade")
		assert(Draft(), "an ad in another channel leaves the current draft alone")
		Post("Olympus is recruiting, PST for an invite!", "Other-Realm", 1, 11, "General")
		eq(Draft(), nil, "another recruiter's ad closes an open draft for the same channel")
		ClickLine(general); eq(Draft(), nil, "a recent recruitment post blocks preparing the same channel")
		assert(Printed(L.RECRUIT_ANNOUNCE_WAIT:format(120)))
		C.Switch(not initialPad); C.Advance(1)
		ClickLine(trade); eq(Draft(), nil, "the other channel has its own cooldown")
		C.now = C.now + 120
		ClickLine(trade)
		local named = Draft().editBox:GetText()
		assert(named:find("Tester", 1, true) and named:find(C.units.player.guild, 1, true),
			"the named variant identifies the recruiter and the destination guild")
		local tradeText = Draft().editBox:GetText():gsub("^/2 ", "")
		C.Click(Draft().buttons[1])
		Post(tradeText, ns.me, 2, 22, "Trade")
		ClickLine(trade); eq(Draft(), nil, "own native echo starts the local cooldown as well")
		Post("Olympus is recruiting. Whisper JOIN!", "Other-Realm", 1, 11, "General")
		C.now = C.now + 119
		ClickLine(general); eq(Draft(), nil, "holds for two full minutes")
		C.now = C.now + 1
		census[1].fresh, census[2].fresh = false, false
		ClickLine(general)
		local fallback = assert(Draft()).editBox:GetText()
		assert(fallback:find("Whisper JOIN", 1, true) and not fallback:find("Over", 1, true), "no unsupported number")
		C.Click(Draft().buttons[1])

		local oldRow = assert(Find(general))
		C.channels.General, C.channels.Other = nil, 1
		InClick(C, oldRow.onClick)
		eq(Draft(), nil, "a stale row does not prepare for a reassigned channel index")
		local every, reminderTick = ns.Every
		ns.Every = function(seconds, where, callback)
			eq(seconds, 2 * 60); eq(where, "recruiting reminder")
			reminderTick = callback
			return every(seconds, where, callback)
		end
		assert(ns.UI.SelectTab("church"))
		local invite
		for _, strip in ipairs(rawget(assert(Main(C)), "pageNavRows") or {}) do
			for _, tab in ipairs(rawget(strip, "nav") or {}) do
				if tab.item and tab.item.text == L.CHURCH_NAV_INVITES then invite = tab end
			end
		end
		C.Click(assert(invite)); ns.UI.Refresh()
		local picker
		for _, row in ipairs(ns.UI.SelfTestView().rows) do
			if row:IsShown() and row.line and row.line.id == "recruit-announcement-reminder" then picker = row.filters[1] end
		end
		C.Click(assert(picker, "the interval renders as a dropdown"))
		assert(picker.choices:IsShown())
		C.Click(picker.choices.buttons[2])
		ns.Every = every
		eq(ReminderChoices()[2].selected, true)
		local before = #C.printed
		C.Advance(2 * 60 - 1)
		eq(Printed(L.RECRUIT_ANNOUNCE_REMIND, before), false, "no reminder before two minutes")
		C.Advance(62)
		eq(Printed(L.RECRUIT_ANNOUNCE_REMIND, before), false, "recruiting is off")
		eq(Draft(), nil)
		eq(#(C.said or {}), sends, "neither drafts nor reminders sent a public message")

		C.now = C.now + 121
		ClickLine(trade)
		draft = assert(Draft())
		eq(draft.buttons[2]:GetText(), L.RECRUIT_ANNOUNCE_POST)
		C.Fire1(draft.editBox, "OnEscapePressed")
		InClick(C, function() C.Fire1(draft.editBox, "OnEnterPressed") end)
		eq(#(C.said or {}), sends, "Escape and unfocused Enter do not post")
		if initialPad then
			-- The earlier input switch puts this session in mouse/keyboard mode.
			ns.Dialog.CloseOnEscape(draft)
			local escape = assert(C.env.OlympusQuestionEscape)
			escape:Hide()
			C.Advance(1)
			eq(Draft(), nil, "Escape dismisses the dialog")
			eq(#(C.said or {}), sends, "the Escape dismissal does not post")
			ClickLine(trade)
			draft = assert(Draft())
		end
		local original = draft.editBox:GetText()
		draft.editBox:SetText(original .. " edited")
		InClick(C, function() draft.editBox:SetFocus(); C.Fire1(draft.editBox, "OnEnterPressed") end)
		eq(#(C.said or {}), sends, "an edited draft remains copy-only")
		assert(Printed(L.RECRUIT_ANNOUNCE_POST_EDITED))
		draft.editBox:SetText(original)
		C.env.C_ChatInfo.InChatMessagingLockdown = function() return true end
		C.Click(draft.buttons[2])
		eq(#(C.said or {}), sends, "the native lockdown leaves the preview as a copy fallback")
		assert(Printed(L.RECRUIT_ANNOUNCE_POST_FALLBACK))
		C.env.C_ChatInfo.InChatMessagingLockdown = function() return false end
		C.channels.Trade = 4
		C.Click(draft.buttons[2])
		eq(#(C.said or {}), sends, "the live channel must still match the preview")
		C.channels.Trade = 2

		local native = C.env.C_ChatInfo.SendChatMessage
		C.env.C_ChatInfo.SendChatMessage = function() error("blocked by the game") end
		C.Click(draft.buttons[2])
		eq(Draft(), draft, "a native failure keeps the copy fallback")
		eq(draft.editBox:GetText(), original)
		C.env.C_ChatInfo.SendChatMessage = native
		C.Click(draft.buttons[2])
		eq(#C.said, sends + 1, "one explicit Post")
		eq(C.said[#C.said][1], original:gsub("^/2 ", ""), "the preview is posted as plain chat text")
		eq(C.said[#C.said][2], "CHANNEL")
		eq(C.said[#C.said][3], "2")
		assert(Printed(L.RECRUIT_ANNOUNCE_POST_CHECK), "a nil API return does not confirm delivery")
		C.Click(draft.buttons[2])
		eq(#C.said, sends + 1, "a repeated click waits even without a channel echo")
		assert(Printed(L.RECRUIT_ANNOUNCE_POST_WAIT:format(120)))
		Post(C.said[#C.said][1], ns.me, 2, 22, "Trade")
		eq(Draft(), nil, "the observed echo closes the draft")
		eq(C.chatBox, nil, "Post does not touch the game's chat editor")
		assert(R.ToggleWhisperRecruiting())
		assert(Find(L.RECRUIT_ANNOUNCE_REMINDER_ROTATE), "new reminders rotate public channels by default")
		ClickLine(L.RECRUIT_ANNOUNCE_REMINDER_ROTATE)
		assert(Find(L.RECRUIT_ANNOUNCE_REMINDER_SELECTED), "the recruiter can opt into one channel")
		reminderTick()
		eq(Draft(), nil, "a recent post suppresses the popup")
		C.now = C.now + 120
		C.combat = true
		reminderTick()
		eq(Draft(), nil, "combat suppresses the popup")
		C.combat = false
		C.channels.Trade = 4
		reminderTick()
		eq(Draft(), nil, "a changed channel index does not redirect the announcement")
		C.channels.Trade = 2
		reminderTick()
		draft = assert(Draft(), "a reminder opens the last selected channel")
		assert(draft.editBox:GetText():find("^/2 "))
		local reminderData = draft.data
		reminderTick()
		eq(draft.data, reminderData, "an existing draft is left alone")
		eq(#C.said, sends + 1, "the timer never posts")
		eq(draft.editBox:HasFocus(), false, "the timed popup never takes the keyboard")
		InClick(C, function() C.Fire1(draft.editBox, "OnEnterPressed") end)
		eq(#C.said, sends + 1, "unfocused Enter cannot submit a timed draft")
		InClick(C, function() draft.editBox:SetFocus(); C.Fire1(draft.editBox, "OnEnterPressed") end)
		eq(#C.said, sends + 2, "one focused Enter sends the reminder's draft")
		eq(C.said[#C.said][3], "2")
		eq(Draft(), nil, "one reminder can't post twice even without a channel echo")
		ClickLine(L.RECRUIT_ANNOUNCE_REMINDER_SELECTED)
		assert(Find(L.RECRUIT_ANNOUNCE_REMINDER_ROTATE))
		C.channels.General, C.channels.Other = 1, nil
		C.now = C.now + 120
		Post("Olympus is recruiting. Whisper JOIN!", "Other-Realm", 1, 11, "General")
		reminderTick()
		draft = assert(Draft(), "rotation skips the recently advertised General channel")
		assert(draft.editBox:GetText():find("^/2 "))
		C.Click(draft.buttons[1])
		ClickLine(trade)
		eq(assert(Draft()).data.public.name, "Trade", "an observed General ad does not block a manual Trade draft")
		C.Click(Draft().buttons[1])
		C.now = C.now + 120
		reminderTick()
		draft = assert(Draft(), "rotation comes back around to General")
		assert(draft.editBox:GetText():find("^/1 "))
		C.Click(draft.buttons[1])
		reminderTick()
		draft = assert(Draft(), "the next eligible channel is Trade")
		assert(draft.editBox:GetText():find("^/2 "))
		eq(#C.said, sends + 2, "rotation never posts when opening or dismissing a draft")
		eq(R.ToggleWhisperRecruiting(), false)
		eq(Draft(), nil, "stopping recruitment closes its reminder")
		ClickLine(general)
		C.Click(assert(Draft()).buttons[2])
		eq(#C.said, sends + 3)
		ClickLine(trade)
		eq(assert(Draft()).data.public.name, "Trade", "a successful General Post also leaves Trade ready")
		C.Click(Draft().buttons[1])
		C.Switch(initialPad); C.Advance(1)
		Check(C.ledger, "recruiting announcement")
		NoErrors(C, "recruiting announcement")
	end
	GP.Covers("dialogs")
	GP.Covers("recruit-public-post")
end)

-- 1.2.5.1: the Olympus Accord (Accord.lua) on a fresh account's first session, gamepad UI on from the
-- login: the Accord asks first, in Olympus's own window (no game popup, nothing of the game's UI
-- reached); the controller's click on I accept starts Olympus; the privacy page comes after it.
test("gamepad: a fresh account's first session: the Olympus Accord first, in Olympus's own window; I accept by the controller's click, then the privacy page", function()
	local C, ns = Session(true, { fresh = true })
	eq(ns.IsMember(), false, "nothing of Olympus before it is accepted")
	local f = ns.Accord.Frame()
	assert(f and f:IsShown(), "the letter, LOGIN_WAIT after login")
	eq(f.acceptEnabled, true, "the test tag is read")
	assert(f.tag:GetText():find("#****", 1, true), "its digits masked")
	local page = ns.Consent.Frame()
	eq(page ~= nil and page:IsShown(), false, "the privacy page waits for it")
	InClick(C, function() f.accept:Click() end)
	eq(ns.IsMember(), true); eq(f:IsShown(), false)
	eq(ns.db.accord.v, ns.ACCORD_VERSION)
	C.Advance(5)
	page = ns.Consent.Frame()
	assert(page and page:IsShown(), "then the privacy page")
	Check(C.ledger, "the Olympus Accord with the gamepad UI")
	NoErrors(C, "the Olympus Accord with the gamepad UI")
	-- Not now, on another fresh session: Olympus stays off, nothing of the game's reached either.
	local C2, ns2 = Session(true, { fresh = true })
	InClick(C2, function() ns2.Accord.Frame().notNow:Click() end)
	eq(ns2.IsMember(), false); eq(ns2.Accord.Frame():IsShown(), false)
	C2.Advance(120)
	eq(ns2.Accord.Frame():IsShown(), false, "not again by itself this session")
	Check(C2.ledger, "Not now with the gamepad UI")
	NoErrors(C2, "Not now with the gamepad UI")
end)

-- 1.2.5.1's review: the server's no-such-player line for the BattleTag's whisper to a team member
-- who just left (Accord.Quiet): no chat filter with the gamepad UI; registered once with mouse and
-- keyboard; doing nothing from its first line after a switch back to the gamepad UI.
test("gamepad: the Olympus Accord's quiet not-found line: no chat filter with the gamepad UI, one with mouse and keyboard, inert after the switch back", function()
	local A = Session(true)
	local ns = A.ns
	local before = A.Mark()
	ns.Accord.Quiet("Iron Warden-Realm")
	eq(#A.Since(before), 0, "no chat filter with the gamepad UI")
	A.Switch(false); A.Advance(1)
	ns.Accord.Quiet("Iron Warden-Realm"); ns.Accord.Quiet("Iron Warden-Realm")
	local filters = {}
	for _, cb in ipairs(A.callbacks) do
		if cb.kind == "AddMessageEventFilter" and cb.fn == ns.Accord.QuietLine then filters[#filters + 1] = cb end
	end
	eq(#filters, 1, "registered once, with mouse and keyboard"); eq(filters[1].key, "CHAT_MSG_SYSTEM")
	A.Switch(true); A.Advance(1)
	eq(filters[1].fn(nil, "CHAT_MSG_SYSTEM", "No player named 'Iron Warden' is currently playing."), false, "inert with the gamepad UI")
	GP.Covers("system-filters")
	Check(A.ledger, "the Olympus Accord's quiet line")
	NoErrors(A, "the Olympus Accord's quiet line")
end)

-- 1.4.0, the Board's group listings (Groups.lua, the review of PR #62): its sections in Olympus's
-- own window, drawn and clicked by the player, with the gamepad UI on from the login and across a
-- switch each way. The quest log's functions (GetNumQuestLogEntries, GetQuestLogTitle, C_QuestLog)
-- are not in tests/fixtures/forever-api.lua yet: Groups.lua is the first to read them, and the
-- fixture is made from the client's own UI source, which only the author has. Until he regenerates
-- it (scripts/forever-api.lua) they read as missing here, so the Quests section shows an empty log
-- (its typed name, its other members' listings) and never a stand-in the client may lack.
local QUEST_LOG = { "GetNumQuestLogEntries", "GetQuestLogTitle", "C_QuestLog" }
local function BoardRow(C, text)
	for _, w in ipairs(C.created) do
		local l = rawget(w, "line")
		if type(l) == "table" and l.onClick and type(l.text) == "string" and l.text:find(text, 1, true) and w:IsVisible() then return w end
	end
end
local function BoardStrip(C)
	for _, w in ipairs(C.created) do
		local l = rawget(w, "line")
		if type(l) == "table" and l.id == "board-sections" and w:IsVisible() then return w end
	end
end
local function BoardGroupsFlow(C, mode)
	local ns = C.ns
	local G, B, L = ns.Groups, ns.Board, ns.L
	local function Click(text)
		local row = assert(BoardRow(C, text), "the Board shows a row: " .. text)
		C.Click(row); C.Advance(0.2)
	end
	G.Reset()
	-- Another Olympus guild's listings of each kind, how many are in one, a flag for several places.
	local function Listing(sender, id, kind, target, title, zone)
		G.HandlePost("CHANNEL", sender, G.Encode({ id = id, guild = "Olympus Zeus", kind = kind, target = target, level = 40, class = "WA",
			need = "113", size = 2, every = 5, age = 0, title = title, zone = zone }))
	end
	Listing("Leader-Realm", "a1", "D", "DM")
	Listing("Raider-Realm", "b1", "R", "MC")
	Listing("Fighter-Realm", "c1", "P", "WSG")
	Listing("Quester-Realm", "d1", "Q", "176", "Kill Hogger", "Elwynn Forest")
	G.HandleMembers("CHANNEL", "Leader-Realm", "GM~a1~MA-1")
	B.HandlePost("CHANNEL", "Looker-Realm", B.Encode({ id = "f1", guild = "Olympus Zeus", flag = "D", level = 40, class = "PR", every = 10, age = 0,
		roles = "T", picks = "D:DM;P:*" }))
	B.Open()
	C.Advance(1)
	-- Each section from the strip, the player's click; each listing's card opened.
	for i, who in ipairs({ "Leader", "Raider", "Fighter", "Quester" }) do
		local strip = assert(BoardStrip(C), "the Board's sections")
		C.Click(assert(rawget(strip, "nav")[i + 1], "section " .. i)); C.Advance(0.2)
		eq(G.View(), G.KINDS[i])
		Click(who)
		assert(BoardRow(C, "> " .. L.GROUPS_WHISPER:format(who)), "its card under it")
	end
	-- Quests: a name typed (its dialog, Olympus's own with the gamepad UI).
	Click(L.GROUPS_LIST:format(L.GROUPS_KIND_Q))
	Click(L.GROUPS_TYPE_NAME)
	ns.HideDialog("OLYMPUS_GROUPS_NAME")
	Click("> " .. L.GROUPS_CANCEL)
	-- Our own listing: a dungeon group, an applicant invited by the leader's click (the game's
	-- invite, roster-actions), a flag's player invited the same way.
	C.Click(rawget(assert(BoardStrip(C)), "nav")[2]); C.Advance(0.2)
	assert(G.Post("D", "DM", nil, "113", ""))
	G.HandleApply("WHISPER", "Applicant-Realm", G.EncodeApply(G.Mine().id, "Olympus Zeus", "T", 40, "WA", ""))
	ns.UI.Refresh(); C.Advance(0.2)
	Click("Applicant")
	C.invited = nil
	Click("> " .. L.GROUPS_INVITE_AS:format(L.GROUPS_ROLE_T))
	eq(C.invited, "Applicant", "the game's invite, from the click")
	Click("Looker")
	Click("> " .. L.GROUPS_INVITE_AS:format(L.GROUPS_ROLE_T))
	eq(C.invited, "Looker")
	-- Our group's need edited, the listing lowered; the flags again.
	Click(L.GROUPS_WANTED:format(L.GROUPS_ROLE_H, ""))
	Click("> " .. L.GROUPS_LOWER)
	eq(G.Mine(), nil)
	C.Click(rawget(assert(BoardStrip(C)), "nav")[1]); C.Advance(0.2)
	eq(G.View(), "flags")
end

for _, initialPad in ipairs({ false, true }) do
	test("gamepad Board groups (1.4.0): " .. (initialPad and "gamepad" or "mouse") .. " login, every section drawn and clicked (Quests too), the game's invite from a click alone, a switch each way", function()
		local C, ns = Session(initialPad)
		for _, name in ipairs(QUEST_LOG) do C.Absent(name, "Groups.lua's quest log: not in the client fixture until it is regenerated (scripts/forever-api.lua)") end
		GP.Covers("roster-actions")
		for _, mode in ipairs({ initialPad, not initialPad, initialPad }) do
			C.Switch(mode); C.Advance(1)
			local mark = C.Mark()
			BoardGroupsFlow(C, mode)
			Check(C.Since(mark), "the Board's groups, " .. (mode and "gamepad" or "mouse and keyboard"))
			local ids = Ids(C.Since(mark))
			assert((ids["roster-actions"] or 0) >= 2, "the two invites, from the clicks")
		end
		Check(C.ledger, "the Board's groups"); NoErrors(C, "the Board's groups")
	end)
end

-- 1.4.0, a companion addon's group panel on the Board (API.lua's RegisterGroupPanel, the registry's
-- board-panel): an Olympus-owned frame in Olympus's own window, in place of Your group while the
-- addon has the player's Yes; the player's switch on the Board brings Olympus's own back. With the
-- gamepad UI on from the login and across a switch each way it stays Olympus's own window's.
for _, initialPad in ipairs({ false, true }) do
	test("gamepad Board group panel (1.4.0): " .. (initialPad and "gamepad" or "mouse") .. " login, a companion's panel in place of Your group, the switch back and forth, a switch of input each way", function()
		local C, ns = Session(initialPad)
		for _, name in ipairs(QUEST_LOG) do C.Absent(name, "Groups.lua's quest log: not in the client fixture until it is regenerated (scripts/forever-api.lua)") end
		GP.Covers("board-panel")
		ns.Groups.Reset()
		C.loadedAddOns.GroupFinder, C.addOnTitles.GroupFinder = true, "Group Finder"
		local api = assert(C.env.OlympusAPI.Register("GroupFinder"), "the companion's handle")
		ns.Consent.Choose("api:groupfinder", true)
		local builds, refreshes, button = 0, 0, nil
		eq(api:RegisterGroupPanel({ label = "Group Finder",
			build = function(frame)
				builds = builds + 1
				button = C.env.CreateFrame("Button", nil, frame)
				button:SetSize(120, 20)
				button:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
				frame:SetHeight(120)
			end,
			refresh = function() refreshes = refreshes + 1 end }), true)
		ns.Groups.Show("D", true)
		ns.Board.Open()
		C.Advance(1)
		for _, mode in ipairs({ initialPad, not initialPad, initialPad }) do
			C.Switch(mode); C.Advance(1)
			local mark = C.Mark()
			ns.UI.Refresh(); C.Advance(0.2)
			eq(builds, 1, "built once")
			assert(refreshes >= 1, "refreshed as the Board redraws")
			eq(api:IsGroupPanelShown(), true, "in place of Your group")
			assert(button:IsVisible(), "the companion's own button, in Olympus's window")
			eq(BoardRow(C, ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_D)), nil, "Olympus's own lines give it their place")
			-- The player's switch: Olympus's own, then the companion's again.
			local switch
			for _, w in ipairs(C.created) do
				local l = rawget(w, "line")
				if type(l) == "table" and l.id == "board-panel-switch" and w:IsVisible() then switch = w end
			end
			assert(switch, "the switch on the Board")
			C.Click(rawget(switch, "nav")[2]); C.Advance(0.2)
			eq(api:IsGroupPanelShown(), false); assert(not button:IsVisible())
			assert(BoardRow(C, ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_D)), "Olympus's own Your group")
			eq(ns.db.groupsPanel, "olympus", "kept for the account")
			C.Click(rawget(switch, "nav")[1]); C.Advance(0.2)
			eq(api:IsGroupPanelShown(), true)
			Check(C.Since(mark), "the group panel, " .. (mode and "gamepad" or "mouse and keyboard"))
		end
		-- The companion takes it off: the Board's own back.
		eq(api:UnregisterGroupPanel(), true)
		ns.UI.Refresh(); C.Advance(0.2)
		assert(not button:IsVisible())
		assert(BoardRow(C, ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_D)))
		Check(C.ledger, "the group panel"); NoErrors(C, "the group panel")
	end)
end

for _, initialPad in ipairs({ false, true }) do
	test("gamepad verification resend: " .. (initialPad and "gamepad" or "mouse") .. " login, actual window and unchanged deadline across both switches", function()
		local C, ns = Session(initialPad)
		GP.Covers("escape-list")
		C.now = ns.Verify.EPOCH + 3600 -- verification timestamps start in 2026, after the fixture's default clock
		C.units.player.rank, C.units.player.rankIndex = "Guild Master", 0
		local guild = C.units.player.guild
		ns.Verify.Observe()
		local started = ns.Verify.Start(guild)
		ns.rdb.council = { at = 1, realm = "Realm", names = { reviewer = "Reviewer" } }
		ns.Workshop.HandleAvailable("CHANNEL", "Reviewer-Realm", "HA~1")
		eq(#ns.Workshop.Available(), 1)
		local queued, whisper = 0, ns.Comm.Whisper
		ns.Comm.Whisper = function(to, word, ...)
			local ok = whisper(to, word, ...)
			if ok and word:match("^HR~") then queued = queued + 1 end
			return ok
		end
		for _, mode in ipairs({ initialPad, not initialPad, initialPad }) do
			C.Switch(mode); C.Advance(0.1)
			eq(ns.Verify.ShowNotice(), true)
			local panel = assert(ns.UI.CopyFrame("verify"))
			local button = assert(rawget(panel, "second"))
			eq(button:GetText(), ns.L.VERIFY_ASK_BTN)
			assert(panel:IsShown() and button:IsShown())
			C.Click(button); C.Click(button)
			eq(queued, 1, "repeated clicks and mode changes do not repeat the request during cooldown")
			eq(ns.Verify.Start(guild), started, "resending keeps the earliest guild clock")
			assert(ns.Verify.RequestWait(guild) > 0, "cooldown is visible to the next request")
			local listed = false
			for _, name in ipairs(OlympusEscapeNames(C)) do if name == panel:GetName() then listed = true end end
			eq(listed, not mode, "the verification window obeys the existing escape-list gate")
			assert(not C.env.ChatFrame1EditBox:IsShown(), "resending never opens the native chat box")
			panel:Hide() -- reopen after each switch, exercising the window's real OnShow registration
		end
		Check(C.ledger, "verification resend"); NoErrors(C, "verification resend")
	end)
end

for _, initialPad in ipairs({ false, true }) do
	test("gamepad self portrait settings: " .. (initialPad and "gamepad" or "mouse") .. " login, collapsed menu and retained callbacks across both switches", function()
		local C, ns = Session(initialPad)
		GP.Covers("player-menu")
		local function Root()
			local root = { items = {} }
			local function Add(text, click)
				local item = Root()
				item.text, item.click = text, click
				root.items[#root.items + 1] = item
				return item
			end
			function root:CreateButton(text, click) return Add(text, click) end
			function root:CreateTitle(text) return Add(text) end
			function root:CreateDivider() return Add() end
			function root:SetTooltip() end
			function root.Find(text)
				for _, item in ipairs(root.items) do if item.text == text then return item end end
			end
			return root
		end
		if initialPad then eq(C.menus.MENU_UNIT_SELF, nil, "no native own-portrait callback at gamepad login") end
		C.Switch(false); C.Advance(0.1)
		local callbacks = assert(C.menus.MENU_UNIT_SELF, "own portrait uses SELF")
		eq(#callbacks, 1)
		local panel, opened = nil, 0
		local open = ns.PlayerTooltip.OpenSettings
		ns.PlayerTooltip.OpenSettings = function() opened = opened + 1; panel = open(); return panel end
		ns.db.playerMenuCollapsed = true
		local root = Root()
		C.Isolated(callbacks[1], {}, root, { unit = "player", fromPlayerFrame = true })
		local sub = assert(root.Find(ns.L.PLAYERMENU_TITLE))
		assert(sub.Find(ns.L.ARENA_MENU_PROFILE), "own profile in the real portrait menu")
		local settings = assert(sub.Find(ns.L.PLAYER_TOOLTIP_SETTINGS))
		InClick(C, settings.click)
		eq(opened, 1); eq(panel:IsShown(), true, "actual settings window opens")
		panel:Hide()
		C.Switch(true); C.Advance(0.1)
		local empty = Root()
		C.Isolated(callbacks[1], {}, empty, { unit = "player", fromPlayerFrame = true })
		eq(#empty.items, 0, "retained native callback adds nothing after gamepad switch")
		InClick(C, settings.click)
		eq(opened, 1); eq(panel:IsShown(), false, "retained native menu click is inert")
		C.Switch(false); C.Advance(0.1)
		eq(#C.menus.MENU_UNIT_SELF, 1, "switch back does not duplicate registration")
		InClick(C, settings.click); eq(opened, 2); eq(panel:IsShown(), true)
		panel:Hide()
		Check(C.ledger, "own portrait settings"); NoErrors(C, "own portrait settings")
	end)
end

-- 1.5.5 (a contributor's ask): the switch for Olympus's lines in the game's menus (PlayerMenu.Enabled).
-- Off at a login, Olympus gives the game's menus no callback; turned on in Olympus's own panel it joins
-- them then (with mouse and keyboard; a gamepad login, at its switch back); turned off again, the
-- callback the game keeps adds nothing from the next menu on, in both modes.
for _, initialPad in ipairs({ false, true }) do
	test("gamepad player menus switch: " .. (initialPad and "gamepad" or "mouse") .. " login with it off, on and off again in Olympus's panel, both switches", function()
		local saved = Answered()
		saved.playerMenus = false
		local C, ns = Session(initialPad, { saved = saved })
		GP.Covers("player-menu")
		local function Root()
			local root = { items = {} }
			local function Add(text, click)
				local item = Root()
				item.text, item.click = text, click
				root.items[#root.items + 1] = item
				return item
			end
			function root:CreateButton(text, click) return Add(text, click) end
			function root:CreateTitle(text) return Add(text) end
			function root:CreateDivider() return Add() end
			function root:SetTooltip() end
			return root
		end
		eq(C.menus.MENU_UNIT_SELF, nil, "off at login: no callback given to the game's menus")
		if initialPad then C.Switch(false); C.Advance(0.1) end
		eq(C.menus.MENU_UNIT_SELF, nil, "nor with mouse and keyboard")
		local panel = assert(ns.PlayerTooltip.OpenSettings())
		eq(panel.menus:GetChecked(), false, "the panel says off")
		panel.menus:SetChecked(true); C.Click(panel.menus)
		eq(ns.db.playerMenus, true)
		local callbacks = assert(C.menus.MENU_UNIT_SELF, "turned on: joined at once")
		eq(#callbacks, 1)
		local root = Root()
		C.Isolated(callbacks[1], {}, root, { unit = "player", fromPlayerFrame = true })
		assert(#root.items > 0, "Olympus's lines at once")
		panel.menus:SetChecked(false); C.Click(panel.menus)
		eq(ns.db.playerMenus, false)
		local empty = Root()
		C.Isolated(callbacks[1], {}, empty, { unit = "player", fromPlayerFrame = true })
		eq(#empty.items, 0, "off: nothing from the next menu on")
		C.Switch(true); C.Advance(0.1)
		C.Switch(false); C.Advance(0.1)
		eq(#C.menus.MENU_UNIT_SELF, 1, "no second callback at the switches")
		empty = Root()
		C.Isolated(callbacks[1], {}, empty, { unit = "player", fromPlayerFrame = true })
		eq(#empty.items, 0, "still off after both switches")
		panel:Hide()
		Check(C.ledger, "player menus switch"); NoErrors(C, "player menus switch")
	end)
end

-- Native player details use the real Inspect callback, with the client's own
-- tooltip lifecycle. They never replace the native owner, anchor or text.
for _, initialPad in ipairs({ false, true }) do
	test("gamepad player tooltip: " .. (initialPad and "gamepad" or "mouse") .. " login, native details and both mode switches", function()
		local C, ns = Session(initialPad)
		GP.Covers("player-tooltip")
		local P, tip = assert(ns.PlayerTooltip), C.env.GameTooltip
		C.units.mouseover = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
		assert(P.Set("scale", 120))
		tip:SetScale(0.9)
		local function RankLines()
			local n = 0
			for _, line in ipairs(tip.lines or {}) do if line == "Olympus II · Titan" then n = n + 1 end end
			return n
		end
		for _, mode in ipairs({ initialPad, not initialPad, initialPad, false }) do
			C.Switch(mode); C.Advance(0.1)
			C.RunScript(tip, "OnTooltipCleared")
			tip:SetOwner(C.env.UIParent, "ANCHOR_CURSOR"); tip:SetUnit("mouseover")
			local owner, anchor = tip.owner, tip.anchor
			C.Isolated(ns.Inspect.TooltipUnit, tip)
			C.Isolated(ns.Inspect.TooltipUnit, tip)
			eq(RankLines(), mode and 0 or 1, "one observed guild rank, no duplicate on repeated post-calls")
			eq(tip:GetScale(), mode and 0.9 or 1.08, "optional scale follows native player's original size")
			eq(tip.owner, owner); eq(tip.anchor, anchor)
			if not mode then
				C.Switch(true); C.Advance(0.1) -- Gate parks native additions on the next frame.
				eq(tip:GetScale(), 0.9, "switch restores a visible tooltip before leaving mouse mode")
				C.Isolated(ns.Inspect.TooltipUnit, tip)
				eq(RankLines(), 1, "retained callback is inert under gamepad")
			end
			tip:Hide(); eq(tip:GetScale(), 0.9)
		end
		C.Switch(false); C.Advance(0.1)
		C.RunScript(tip, "OnTooltipCleared"); tip:SetUnit("mouseover")
		C.Isolated(ns.Inspect.TooltipUnit, tip); eq(tip:GetScale(), 1.08)
		tip:SetScale(1.3) -- A later addon owns this value; Olympus must leave it alone.
		tip:Hide(); eq(tip:GetScale(), 1.3, "never overwrite another tooltip addon's later change")
		Check(C.ledger, "native player tooltip"); NoErrors(C, "native player tooltip")
	end)
end

test("gamepad player tooltip: verified ranks, secret values, preferences and combat", function()
	local C, ns = Session(false)
	local P, tip = assert(ns.PlayerTooltip), C.env.GameTooltip
	local u = { name = "Someone", realm = "Realm", guid = "Player-1-00000002", guild = "Olympus II", rank = "Titan", rankIndex = 1 }
	C.units.mouseover = u
	local function Hover()
		C.RunScript(tip, "OnTooltipCleared")
		tip:SetOwner(C.env.UIParent, "ANCHOR_CURSOR"); tip:SetUnit("mouseover")
		C.Isolated(ns.Inspect.TooltipUnit, tip)
		for _, line in ipairs(tip.lines or {}) do if line:find("Olympus II ·", 1, true) then return line end end
	end
	eq(P.Options().scale, 100); eq(Hover(), "Olympus II · Titan"); eq(tip:GetScale(), 1)
	u.rank = nil; eq(Hover(), nil, "no inferred rank when the game has none")
	u.rank = "secret rank"
	C.env.issecretvalue = function(value) return value == "secret rank" end
	eq(Hover(), nil, "secret rank never reaches string processing")
	u.rank = "Titan"
	assert(P.Set("details", false)); eq(Hover(), nil)
	eq(P.Set("scale", 500), false); eq(P.Set("other", true), false); eq(P.Set("colors", "yes"), false)
	assert(P.Set("details", true)); assert(P.Set("scale", 120)); eq(Hover(), "Olympus II · Titan"); eq(tip:GetScale(), 1.2)
	C.combat = true; C.Fire("PLAYER_REGEN_DISABLED")
	eq(tip:GetScale(), 1, "combat restores the size already borrowed")
	eq(Hover(), nil, "new native additions pause during combat"); eq(tip:GetScale(), 1)
	C.combat = false; eq(Hover(), "Olympus II · Titan"); eq(tip:GetScale(), 1.2)
	tip:Hide(); eq(tip:GetScale(), 1)
	C.Switch(true); C.Advance(0.1) -- Gate parks native additions on the next frame.
	local panel = assert(P.OpenSettings())
	eq(panel:IsShown(), true, "preferences use Olympus's own panel in either input mode")
	panel.checks.colors:SetChecked(false); C.Click(panel.checks.colors)
	eq(P.Options().colors, false, "native checkbutton choice persists")
	panel:Hide()
	Check(C.ledger, "player tooltip preferences"); NoErrors(C, "player tooltip preferences")
end)

if MODE == "--discover" then
	local C, ns = Boot({ discover = true, gamepad = arg and arg[2] == "gamepad" })
	Login(C)
	local list = {}
	for k in pairs(C.unmodelled) do list[#list + 1] = k end
	table.sort(list)
	print(table.concat(list, "\n"))
	for _, e in ipairs(ns.db and ns.db.errors or {}) do print("ERROR " .. e.where .. ": " .. e.msg .. "\n" .. e.stack) end
	return
end
if MODE == "--names" then
	local C = NewClient()
	World(C)
	local names = {}
	for k in pairs(C.env) do names[#names + 1] = k end
	table.sort(names)
	for _, k in ipairs(names) do if type(k) == "string" then print("global " .. k) end end
	return
end

if not H then
	print(("\n%d passed, %d failed"):format(passed, failed))
	os.exit(failed == 0 and 0 or 1)
end
