-- The real audience queue and local Chronicle, including a reload between call and replay.
local ns, test, eq, H = ...
local KING = "Asmongold Asmongler-Realm"
local function Bench(fn)
	local saved = { acts = ns.rdb.acts, states = ns.rdb.actsState }
	local ok, err = pcall(function()
		ns.Chronicle.Clear()
		H.WithThrone(function(w, K)
			C_Map.GetBestMapForUnit = function() return 1453 end
			C_Map.GetMapInfo = function() return { mapType = 3 } end
			GetRealZoneText = function() return "Stormwind City" end
			fn(w, K, ns.Court, ns.Chronicle)
		end)
	end)
	ns.rdb.acts, ns.rdb.actsState = saved.acts, saved.states
	if not ok then error(err, 0) end
end
local function Open(K, id)
	H.AsSoldier("Visitor")
	K.HandleCommand("CHANNEL", KING, "T1~C~" .. id .. "~Olympus~1453~Stormwind City")
end

test("Court call message: optional text stays with its recipient and authenticated King in the Chronicle after reload", function()
	Bench(function(w, K, C, Ch)
		H.AsKing(); C.Toggle()
		local id = C.Holding().id
		C.Request("Visitor-Realm", id, "Olympus II")
		C.Call("Visitor-Realm", "  Meet\nby~the |gate.  ")
		eq(#w.whispered, 2, "the legacy call plus its optional note")
		eq(w.whispered[1].msg, "T5~" .. id, "older clients still receive their unchanged call")
		local note = w.whispered[2].msg
		assert(#note <= 255)
		eq(#Ch.Entries(), 0, "the whispered note is not a public act on the sender's screen")
		C.Reset(); Open(K, id)
		C.HandleCall("WHISPER", KING, w.whispered[1].msg)
		local popups = #w.popups
		C.HandleCall("WHISPER", KING, note)
		eq(#w.popups, popups, "the note does not open a second called popup")
		eq(#Ch.Entries(), 1)
		local e = Ch.Entries()[1]
		eq(e.kind, "court"); eq(e.by, KING); eq(e.to, "Visitor-Realm")
		eq(e.words, "Meet by the gate.")
		assert(Ch.Text():find(e.words, 1, true), "can be reopened and copied after dismissing the popup")
		-- Court.Reset discards the same session-only state as a reload; Chronicle's saved rows
		-- and state remain, as when the realm's SavedVariables are read back in.
		C.Reset(); Open(K, id)
		C.HandleCall("WHISPER", KING, note)
		eq(#Ch.Entries(), 1, "reload and replay do not duplicate the recorded message")
		eq(C.Messages()[1], e, "the recipient can still read its retained message")
		H.AsSoldier("Other Alt"); eq(#C.Messages(), 0, "recipient lookup does not mix another character's messages")
	end)
end)

test("Court call message: untrusted, malformed, expired and duplicate note packets cannot write royal words", function()
	Bench(function(w, K, C, Ch)
		Open(K, 81001)
		local function Note(id, at, words) return "T5~" .. id .. "~" .. at .. "~" .. words end
		local note = Note(81001, w.clock, "Please bring your question.")
		C.HandleCall("CHANNEL", KING, note)
		C.HandleCall("WHISPER", "Pretender-Realm", note)
		C.HandleCall("WHISPER", KING, Note(81002, w.clock, "Wrong audience"))
		C.HandleCall("WHISPER", KING, Note(81001, w.clock - C.CALL_OPEN - 1, "Too late"))
		C.HandleCall("WHISPER", KING, Note(81001, w.clock + 1, "From the future"))
		C.HandleCall("WHISPER", KING, Note(81001, w.clock, string.rep("x", 161)))
		eq(#Ch.Entries(), 0); eq(C.Current().calledAt, nil)
		C.HandleCall("WHISPER", KING, note)
		eq(#Ch.Entries(), 1)
		C.HandleCall("WHISPER", KING, note)
		C.HandleCall("WHISPER", KING, Note(81001, w.clock, "Changed replay"))
		eq(#Ch.Entries(), 1); eq(Ch.Entries()[1].words, "Please bring your question.")
		K.HandleCommand("CHANNEL", KING, "T1~Z~81001~Olympus")
		C.HandleCall("WHISPER", KING, note)
		eq(#Ch.Entries(), 1, "closing a court revokes its live note window, not its history")
	end)
end)

test("Court call message: optional UI prompt rechecks its audience and authority; blank/direct calls and dismissal stay unchanged", function()
	Bench(function(w, K, C, Ch)
		H.AsKing(); C.Toggle()
		C.Request("Visitor-Realm", C.Holding().id, "Olympus II")
		local option
		for _, row in ipairs(C.HomeLines()) do if row.text == ns.L.COURT_NOTE_CALL then option = row end end
		assert(option and option.onClick, "a separate optional message action leaves the original call intact")
		option.onClick()
		local popup = w.popups[#w.popups]
		eq(popup.name, "OLYMPUS_COURT_NOTE")
		local data = popup.data
		H.AsSoldier("Visitor"); C.Confirm(data, "Not royal")
		eq(#w.whispered, 0, "authority is rechecked on accept")
		H.AsKing(); C.Prompt("Visitor-Realm")
		data = w.popups[#w.popups].data
		C.Toggle(); C.Toggle(); C.Request("Visitor-Realm", C.Holding().id, "Olympus II")
		C.Confirm(data, "An old prompt")
		eq(#w.whispered, 0, "an old prompt cannot call someone in a replacement court")
		C.Prompt("Visitor-Realm"); data = w.popups[#w.popups].data
		C.Confirm(data, ""); C.Confirm(data, "duplicate accept")
		eq(#w.whispered, 1); eq(w.whispered[1].msg, "T5~" .. C.Holding().id)
		C.Prompt("Visitor-Realm")
		eq(#w.popups, 3, "no modal after the player has already been called")
		w.clock = w.clock + C.CALL_GAP; C.Call("Visitor-Realm")
		eq(#C.Holding().queue, 0, "second direct click still dismisses the request")
		eq(#Ch.Entries(), 0)
	end)
end)

test("Court call message: retained history is bounded and royal words respect the existing text filter", function()
	Bench(function(w, K, C, Ch)
		local savedMax, savedFilter = Ch.MAX, ns.Filter
		local ok, err = pcall(function()
			Ch.MAX = 3
			for id = 81101, 81105 do
				Open(K, id)
				C.HandleCall("WHISPER", KING, "T5~" .. id .. "~" .. w.clock .. "~Private line " .. id)
			end
			eq(#Ch.Entries(), 3); eq(#C.Messages(), 3)
			eq(C.Messages()[1].words, "Private line 81103", "only the newest bounded history remains")
			ns.Filter = { Hides = function() return true end }
			assert(Ch.Line(Ch.Entries()[3]):find(ns.L.FILTER_WORDS_HIDDEN_SHORT, 1, true))
			assert(not Ch.Text():find("Private line", 1, true), "copy does not bypass the shared word filter")
		end)
		Ch.MAX, ns.Filter = savedMax, savedFilter
		if not ok then error(err, 0) end
	end)
end)

test("Court call message: gamepad uses Olympus's own optional text window and its actual accept callback", function()
	H.WithUI(function()
		H.WithGamepadUI(true, function(game)
			Bench(function(w, K, C)
				H.AsKing(); C.Toggle(); C.Request("Visitor-Realm", C.Holding().id, "Olympus II")
				C.Prompt("Visitor-Realm")
				local f = assert(ns.Dialog.Find("OLYMPUS_COURT_NOTE"))
				f.editBox:SetText("Come to the fountain.")
				f.buttons[1]:Click()
				eq(#w.whispered, 2)
				assert(w.whispered[2].msg:find("Come to the fountain.", 1, true))
				eq(#game.shown, 0, "no native game popup with the gamepad UI")
			end)
		end)
	end)
end)
