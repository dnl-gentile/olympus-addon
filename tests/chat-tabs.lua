-- Standalone native chat-window integration tests: luajit tests/chat-tabs.lua
local root = (arg[0]:match("^(.*)tests/") or "./")
local ns = { db = {}, me = "Tester-Realm", L = { A = "Olympus", C = "Captains", L = "Lords" } }
local allowed = { A = true, C = true, L = true }
local messages, sent, native = {}, {}, {}
ns.Channels = {
 TIERS = { A = { slash = "/ol", label = "A" }, C = { slash = "/olc", label = "C" }, L = { slash = "/oll", label = "L" } },
 CanUse = function(tier) return allowed[tier] end,
 TierForWord = function(word) return ({ olympus = "A", captains = "C", lords = "L" })[word] end,
}
function ns.Print(text) messages[#messages + 1] = text end
function ns.On() end
function ns.SafeCall(_, fn, ...) return fn(...) end
SlashCmdList = {}
NUM_CHAT_WINDOWS = 5
function hooksecurefunc(target, key, callback)
 if type(target) == "string" then callback, key, target = key, target, _G end
 local old = target[key]
 target[key] = function(...) local result = old(...); callback(...); return result end
end
function ChatEdit_UpdateHeader(edit)
 edit.header:SetText(edit.kind == "WHISPER" and "To Friend: " or "Say: ")
 edit.header:SetWidth(edit.header:GetStringWidth())
 edit:SetTextInsets(15 + edit.header:GetWidth(), 13, 0, 0)
end
local windows = {}
for id = 1, NUM_CHAT_WINDOWS do
 local edit = { text = "", kind = "SAY", scripts = {} }
 function edit:GetName() return "ChatFrame" .. id .. "EditBox" end
 edit.header = { text = "Say: ", width = 30 }
 function edit.header:SetText(text) self.text = text end
 function edit.header:SetWidth(width) self.width = width end
 function edit.header:GetWidth() return self.width end
 function edit.header:GetStringWidth() return #self.text * 6 end
 function edit:GetWidth() return 400 end
 edit.insets = {45, 13, 0, 0}
 function edit:GetTextInsets() return unpack(self.insets) end
 function edit:SetTextInsets(...) self.insets = {...} end
 function edit:UpdateHeader() ChatEdit_UpdateHeader(self) end
 function edit:GetText() return self.text end
 function edit:SetText(text) self.text = text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end end
 function edit:GetScript(event) return self.scripts[event] end
 function edit:SetScript(event, fn) self.scripts[event] = fn end
 function edit:HookScript(event, fn)
  local old = self.scripts[event]
  self.scripts[event] = function(...) if old then old(...) end; fn(...) end
 end
 function edit:GetAttribute() return self.kind end
 function edit:SetAttribute(key, value) if key == "chatType" then self.kind = value end end
 edit.scripts.OnTextChanged = function(self)
  local command, rest = self.text:match("^(/%a+)%s+(.*)$")
  if command == "/say" or command == "/w" then
   self.kind = command == "/say" and "SAY" or "WHISPER"
   self.text = rest
  end
 end
 edit.scripts.OnEnterPressed = function(self)
  local command, text = self.text:match("^(/%a+)%s+(.*)$")
  local tier = ({ ["/ol"] = "A", ["/olc"] = "C", ["/oll"] = "L" })[command]
  if tier then
   if allowed[tier] then sent[#sent + 1] = { tier, text } end
  else native[#native + 1] = { self.kind, self.text } end
  self.text = ""
  if self.scripts.OnHide then self.scripts.OnHide(self) end
 end
 edit.originalScripts = { OnEnterPressed = edit.scripts.OnEnterPressed, OnTextChanged = edit.scripts.OnTextChanged }
 local frame = { id = id, name = "Window " .. id, shown = id <= 2, editBox = edit }
 function frame:GetID() return self.id end
 function frame:GetName() return "ChatFrame" .. self.id end
 function frame:AddMessage(text) self.lastMessage = text end
 windows[id], _G["ChatFrame" .. id] = frame, frame
end
function GetChatWindowInfo(id) local f = windows[id]; return f.name, nil, nil, nil, nil, nil, f.shown end
function FCF_OpenNewWindow(name, noDefaults)
 assert(noDefaults)
 for id = 3, NUM_CHAT_WINDOWS do
  local f = windows[id]
  if not f.shown then f.shown, f.name, f.isDocked = true, name, true; return f end
 end
 error("must not create a window when full")
end
local selected
function FCF_SelectDockFrame(frame) selected = frame end
function FCF_SetWindowName(frame, name) frame.name = name end
function ChatEdit_SetLastActiveWindow(edit) assert(edit) end
local function load() assert(loadfile(root .. "Olympus/ChatTabs.lua"))("Olympus", ns) end
load()
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("ok " .. name) end
local function enter(edit, text)
 edit:SetText(text)
 edit.scripts.OnEnterPressed(edit)
end
local tab, edit
test("opens a dedicated tab and reuses it", function()
 assert(ns.ChatTabs.Open("A")); tab = ns.ChatTabs.Frame("A"); edit = tab.editBox
 assert(tab == selected and tab.id == 3 and tab.name == "Olympus")
 assert(ns.ChatTabs.Open("A") and ns.ChatTabs.Frame("A") == tab)
end)
test("Olympus input label and spacing survive native header refreshes", function()
 assert(edit.header.text == "Olympus: ")
 local left = edit.insets[1]
 edit:UpdateHeader(); edit:UpdateHeader()
 assert(edit.header.text == "Olympus: " and edit.insets[1] == left)
 edit:SetText("/say local")
 assert(edit.header.text == "Say: ")
 edit.scripts.OnHide(edit); edit.text = ""; edit.scripts.OnShow(edit)
 assert(edit.header.text == "Olympus: ")
 edit:SetText("/w Friend hello")
 assert(edit.header.text == "To Friend: ")
 edit.scripts.OnHide(edit); edit.text = ""; ns.ChatTabs.Open("A")
end)
test("plain input follows Olympus transport", function()
 enter(edit, "hello |Hitem:1|h[item]|h")
 assert(#sent == 1 and sent[1][1] == "A" and sent[1][2] == "hello |Hitem:1|h[item]|h" and #native == 0)
end)
test("explicit say and whispers keep native routing", function()
 enter(edit, "/say hello world")
 enter(edit, "/w Friend hello")
 assert(#native == 2 and native[1][1] == "SAY" and native[2][1] == "WHISPER")
 assert(#sent == 1)
end)
test("sticky whisper stays a whisper, reopening resets Olympus input", function()
 enter(edit, "reply")
 assert(native[3][1] == "WHISPER")
 ns.ChatTabs.Open("A"); enter(edit, "back")
 assert(#sent == 2 and sent[2][2] == "back")
end)
test("clearing an explicit command restores default input", function()
 edit:SetText("/help"); edit.text = ""; edit.scripts.OnTextChanged(edit, true)
 enter(edit, "ordinary")
 assert(#sent == 3)
end)
test("rank loss never sends protected text via Say", function()
 ns.ChatTabs.Open("L")
 local lord = ns.ChatTabs.Frame("L")
 assert(lord.editBox.header.text == "Lords: ")
 allowed.L = false
 assert(ns.ChatTabs.Frame("L") == nil)
 enter(lord.editBox, "secret")
 assert(#native == 3 and #sent == 3)
 assert(ns.ChatTabs.Open("L") == false)
 allowed.L = true
end)
test("full windows are not overwritten", function()
 ns.ChatTabs.Open("C")
 assert(ns.ChatTabs.Frame("C").editBox.header.text == "Captains: ")
 -- Close the binding through a rename while leaving every window occupied.
 windows[5].name = "My own tab"
 assert(ns.ChatTabs.Frame("C") == nil)
 assert(ns.ChatTabs.Open("C") == false and windows[5].name == "My own tab")
end)
test("reload restores only matching active windows", function()
 -- Simulate UI reload: fresh script handlers, saved window data and SavedVariables.
 for _, f in ipairs(windows) do
  f.editBox.olympusHooked = nil
  f.editBox.scripts = { OnEnterPressed = f.editBox.originalScripts.OnEnterPressed, OnTextChanged = f.editBox.originalScripts.OnTextChanged }
 end
 load(); ns.ChatTabs.Restore()
 assert(ns.ChatTabs.Frame("A") == tab and ns.ChatTabs.Frame("C") == nil)
end)
test("closed or reused tabs stop receiving Olympus traffic", function()
 tab.shown, tab.isDocked = false, false
 assert(ns.ChatTabs.Frame("A") == nil)
 tab.shown, tab.name = true, "Reused"
 assert(ns.ChatTabs.Frame("A") == nil)
end)
test("modern edit-box methods and reloaded input", function()
 tab.name = ns.db.chatTabs[ns.me].A.name
 local function modern(self) return self.kind end
 edit.GetChatType = modern
 function edit:SetChatType(kind) self.kind = kind end
 function edit:SetStickyType(kind) self.sticky = kind end
 assert(ns.ChatTabs.Open("A"))
 enter(edit, "after reload")
 assert(sent[#sent][2] == "after reload")
end)
test("reload migrates the old tab name without creating a new tab", function()
 tab.name = "Olympus - Olympus"
 ns.db.chatTabs[ns.me].A.name = tab.name
 ns.ChatTabs.Restore()
 assert(tab.name == "Olympus" and ns.db.chatTabs[ns.me].A.name == "Olympus")
 assert(ns.ChatTabs.Frame("A") == tab)
end)
test("legacy global header hook restores Olympus and explicit Say labels", function()
 edit.UpdateHeader = nil
 edit.olympusHooked = nil
 edit.scripts = { OnEnterPressed = edit.originalScripts.OnEnterPressed, OnTextChanged = edit.originalScripts.OnTextChanged }
 load(); ns.ChatTabs.Restore(); ns.ChatTabs.Open("A")
 assert(edit.header.text == "Olympus: ")
 ChatEdit_UpdateHeader(edit)
 assert(edit.header.text == "Olympus: ")
 edit:SetText("/say local")
 assert(edit.header.text == "Say: ")
end)
test("combat refuses to modify windows", function()
 InCombatLockdown = function() return true end
 assert(ns.ChatTabs.Open("A") == false)
 InCombatLockdown = nil
end)
print(passed .. " passed, 0 failed")
