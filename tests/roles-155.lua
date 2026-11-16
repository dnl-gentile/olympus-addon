-- 1.5.5, the roles on WoW: Forever (the dev, 11-10: "fern's char is the treasurer, pyralis is something else ...
-- give him his old frame"; "asmon isnt the gm of any guild, fern is the gm of the main guild"; "Postpone the hold
-- on PvP"). The Quaestor, the Treasurer's executor: a signed ^quaestor^ entry, the Treasurer's blue dragon, his
-- title and a trusted relay of his side. On Forever's live realms the Treasurer is the signed list's alone, in the
-- King's main guild <OLYMPUS PRIME>, whose guild master is no King. No verification hold where nobody can verify.
-- A throwaway key made with scripts/council-sign.py for these tests (its private half was not kept) signed:
--   PVE_NAMES, PVE       "ForeverPvE": Test Councillor (Council Speaker); Crown Owl-CAMWOWUS2Realm1PvE the
--                        Alliance King; Ledger Wren-CAMWOWUS2Realm1PvE its Treasurer; Quill Maker-CAMWOWUS2Realm1PvE
--                        the author's character; the Alliance Quaestors Tally Reeve-CAMWOWUS2Realm3PvE and Coin
--                        Bearer-CAMWOWUS2Realm1PvE and the Horde's Tusk Reeve-CAMWOWUS2Realm1PvE (signed with the
--                        new "quaestor" command, three times); CAMWOWUS2Realm1PvE a PvE realm of NA
--   PVP_A_NAMES, PVP_A   "ForeverPvP": no councillor, no King; Quill Maker-CAMWOWUS1Realm8PvP the author's
--                        character, CAMWOWUS1Realm8PvP a PvP realm of NA: nobody who can verify
--   PVP_B_NAMES, PVP_B   newer: the same, with Watch Captain (Verifier) on the council
-- Invented names only. Every test name starts with "1.5.5 roles:", so
--   OLYMPUS_TEST_FILTER='1.5.5 roles' luajit tests/run.lua
-- runs them alone.
local ns, test, eq, x = ...
local L = ns.L
local ADDON_DIR = x.ADDON_DIR
local WithBorders, BorderUnit, BORDER_KING, Vouched = x.WithBorders, x.BorderUnit, x.BORDER_KING, x.Vouched

local KEY_N = "9650796067b3d18f17afa69881849cd530db6132696c6e1f3fe1963cd07320fb31efac898f51d53becaa09156d9fe99c27430afdbab59107f66f9cea66d20dea3c82aae2996fc5214656801f9e471ff02d7f86ce24573f106cf61135dce1f4b785e67894654add52a1b91327288a69632ef2e84725d4d55554757ab829d09f9c40ceea806dfd5af84547d7097304e42037b4e6680f124164244f3fcceef44b84f642bf72b6447c97894bbebfdcb2613132861ec36b952235587f82897e07ecf9e78618586e9dd6d7fb52603a019c237f563f4f130cd5e460696b2a36684ddf9f617da49a27a45b869443acfda9b87f1e32de80b5189319939a2d3859bd5893b3"
local KEY_MU = "1b3fe32f034c4dcb7cd52d7a3dde8c250c99f671227908548a6fed46eca27fd9a5888b1844fee15c4964d0f61aa3c231cbe48de50d37ab0a59630ba44568d7de48a192c1b1e5065fe12ef39d94dbc79ec7604b754a625d5bfca7ef85565b22bf412244e379ed26a8f8e789ef40d4cc57019d272c0cda4e75630efa695bf6c1a00da160fca9baa1d49611bcef88b58dbc9a58a3e6b8c98350a3bb9ff47d7431460c2810d28093926e9c2307c0ee4e2be38ffdd2dc9e1f7e59b20833cabcbcdaf3765208def21aac0b2418a5357d14465c87f2ebfbc933647b4a8b9602f16290299cebae5276aa3a5fed76fc93247d700d4ebe63be24bccf780974c2544fd304314b4add8ba"
local PVE_NAMES = "HS1~1794339326~ForeverPvE~Test Councillor~5d874993168286f19247d2e38d1f8dd8b62f902757f3071b22d8d9b0f506929d2fd2e5a9b15b3a91442fca6bd5ed765b20b4760782f61130d7215d321ea71ef64a38df4a4cd5f99342934e8089e9d1549006e7ceeb590d4ce190af763bf7c57df31b53c57902f07f27d3b702525cce6a0ba3ab3c984712f40eaf4c1845465196ed329e50c6e6f61ed735d518591d46957440cd7e898176395933ea7fdcebf29eaa1debba4244e9fbda1988458f8e11d97b3c80c11222f5bd9f85497c6d4d5b261477670253580d917b0818f2edaf9a4924a7f37b7788c055bbc5837bbeef99084d8442ecf92c7f1f6ade9c7502c41cf3fb9c97368b581b0c24986069258e0103"
local PVE = "HT1~1794339327~ForeverPvE~0~^^Test Councillor=Council Speaker;^king^Alliance^Crown Owl-CAMWOWUS2Realm1PvE;^treasurer^Alliance^Ledger Wren-CAMWOWUS2Realm1PvE;^author^Alliance^Quill Maker-CAMWOWUS2Realm1PvE;^quaestor^Alliance^Tally Reeve-CAMWOWUS2Realm3PvE,Coin Bearer-CAMWOWUS2Realm1PvE;^quaestor^Horde^Tusk Reeve-CAMWOWUS2Realm1PvE;^realms^NA^CAMWOWUS2Realm1PvE=pve~1cbb4ce5d6ce82569cb272673a3c6fdb2807e82b9cac44c824fabf7247c670b5acd4e3bfcdc927369abfcf27a4cbbf9a25398b4faf6259d73172b7f62d7d2af0f1ab6aa18356bb1febe7ab8a83f5233c44011633120b55873ec5c00c8d0fd8b0b9e8c409fc531b0398634a60833e0a4ea7bf463ce84947b266db8704f6dc78e0d64f46cf534229134c1d4c7131b7fd70832ee298e8d0b1c7cc1ee2ca7f8b90fb61add9c6f41c4fe84447022bce9e8cc29c6be7881a01ad51e5137ad32bfd1fc77d462b1f5777fb700c841cfcb54a7c4ca106ad254dfa51def8a13cfcb2abf1acc232073b9ccc78c786d08a700b8a983554eb89396537cff316ac159cf1bae645"
local PVP_A_NAMES = "HS1~1794339328~ForeverPvP~~6c3cfbc02405cd1d0ae6d06298a6d92d374b47026e91701221ecaa547fbbb31157eeda8054fe149b56554a612093095c8fe2f8c208a45a9da9a612440e57fcbb03b877e73e5bf363c21b7f2bbefd6cef774e0caa57db5f2d1ad3db8459d714a8423bcdea03f8e5c64233d78ea4e21f787e559b2294684dc25767b4896577b155edc5b100ec9aa13735c0ac675b729d06f45c7b1b2f4c520f037f097660fc5f3229ae8e2418bc1a6df68078295d626d755c5aa272f27989d394b56b66f599f9214e072adcb8969e3a9e00a16983876b2f5c52d316dbfe9eb76677a1eadb376fbf819c10d4b18fe90b566dc0e9e9a8c974ae0789f791042ab2b00e855d5a8a4ff8"
local PVP_A = "HT1~1794339329~ForeverPvP~0~^author^Alliance^Quill Maker-CAMWOWUS1Realm8PvP;^realms^NA^CAMWOWUS1Realm8PvP=pvp~172c57564f778002434069ffd733ba07bc248e5046b3da2cad6398c500b5b54f73877c0ff4ff4a20c0a8eb8b548cfca522b34cb6c35f05d57c313a7029ceeeb2f02ad90cdcc893d49044701a170fefcf34f2a4c0e957aee34297be674aa39a49aeff317896d9866bb64eae74eb9f0dcda596df289af647f0fc27a4e5c60c421922cb5e73025bfddaf1de6312d5f78410bfba85cd5b2c4fd630d0eaf88bbb3effe9c85b193e01dd6cebe6bc7969a6d2d6578e3328247270fa5c26fffbabda4f53f875f78d1a121722c56df7caf1693c15e6ace7d8c0efb95baa19aea291944611b7719d21b7d4386f9fd668f1265c10b0aee791da2e647ea08cbc1d32824c06b2"
local PVP_B_NAMES = "HS1~1794339330~ForeverPvP~Watch Captain~6eeb8ae1b1a6970388680b64b1f4230258cd678bce87801fa8f74cbf1b686936ddc2876c7ac46b6538fae4d907d6a66d43788aeaba744b9dc78a9c3bd0e99d43ad42f957997cfbbe15ada4d35feb797bd8926ef51bb059f71ab58733a82aaf0ba0747f530391e46b7f676bc5d5929cf17b88b1c5cb758a9c32a5ab5597f2f627d09f348ee05b17626cb9fb77c88d85bf8a477b1278a27053c15752edaef72eaa7903962a7980ce31af8b3d0a1987af05114b9c7739b027a6a09ff95fbba17d3b042e917b42d65bbb0260dcd220d00a06ea9db8b9664ace5a7392e6d42abfd9d35e5600d6b01394c109071108f01aa3e3cf985dd3fa7bbbc14b9439da46fcf779"
local PVP_B = "HT1~1794339331~ForeverPvP~0~^^Watch Captain=Verifier;^author^Alliance^Quill Maker-CAMWOWUS1Realm8PvP;^realms^NA^CAMWOWUS1Realm8PvP=pvp~019d809d62597dd7d504d637a9405fb1c8b6f741ce0c30a510fd02d73c90ff824c46fb82a8469224ed6633fdfaf31656e479a778c53aa8978e19f8e7f81a03181822f47def70ecb0e71c5d524e06751d099d4fcec7f5bb24d016dbf712042b45d77c8f193c9a4c365a5a2af05451f6f5c61bc0504bc64bd8ab1486f6590835480ea0751a2226ee5c7f5b31e70d3b52dbd5f40e308a0ceedc3d042bb40d56c1e150fb53429ddda38e16736a62ff84ede398f3d6bdfe641050dfa512f45e40f303e8fb22fe006616e26fa31a4cf7e4d24771c5a78d23b145d7282cecffdae82525e2cef4c4d54362a2a0d74427818af5851010d5523aa5b6ea43120d48c20e5e89"

local PVE_REALM, PVP_REALM = "CAMWOWUS2Realm1PvE", "CAMWOWUS1Realm8PvP"
local KING, TREASURER = "Crown Owl-" .. PVE_REALM, "Ledger Wren-" .. PVE_REALM
local QUAESTOR, QUAESTOR2, HORDE_QUAESTOR = "Tally Reeve-CAMWOWUS2Realm3PvE", "Coin Bearer-" .. PVE_REALM, "Tusk Reeve-" .. PVE_REALM
local MASTER, MAIN, OTHER = "Fief Holder-" .. PVE_REALM, "OLYMPUS PRIME", "Olympus Hearth"

-- This client on a Forever sub-realm (its family its group), of `faction`, in no guild, holding no signed list;
-- what it touches put back after. fn(printed): the lines it printed.
local function WithForever(realm, faction, fn)
	local saved = { realm = ns.realm, group = ns.group, me = ns.me, faction = ns.faction, split = ns.splitNames,
		titles = ns.rdb.councilTitles, council = ns.rdb.council, verify = ns.rdb.verify, guilds = ns.rdb.guilds,
		seen = ns.rdb.seen, global = ns.rdb.censusGlobal, gi = GetGuildInfo, ig = IsInGuild, print = ns.Print,
		online = ns.Roster.online, sweep = ns.Who.sweep }
	local printed = {}
	local ok, err = pcall(function()
		ns.realm, ns.faction, ns.splitNames = realm, faction or "Alliance", true
		ns.group = ns.GroupOf(realm)
		ns.me = "Some Body-" .. realm
		ns.rdb.councilTitles, ns.rdb.council, ns.rdb.verify = nil, nil, nil
		ns.rdb.guilds, ns.rdb.seen, ns.rdb.censusGlobal = {}, {}, {}
		ns.Roster.online, ns.Who.sweep = {}, nil
		GetGuildInfo = function() return nil end
		IsInGuild = function() return false end
		ns.Print = function(m) printed[#printed + 1] = tostring(m) end
		ns.Workshop.ResetVerify(); ns.Hop.Reset(); ns.King.Reset()
		fn(printed)
	end)
	ns.realm, ns.group, ns.me, ns.faction, ns.splitNames = saved.realm, saved.group, saved.me, saved.faction, saved.split
	ns.rdb.councilTitles, ns.rdb.council, ns.rdb.verify, ns.rdb.guilds = saved.titles, saved.council, saved.verify, saved.guilds
	ns.rdb.seen, ns.rdb.censusGlobal = saved.seen, saved.global
	GetGuildInfo, IsInGuild, ns.Print = saved.gi, saved.ig, saved.print
	ns.Roster.online, ns.Who.sweep = saved.online, saved.sweep
	ns.Workshop.ResetVerify(); ns.Hop.Reset(); ns.King.Reset()
	if not ok then error(err, 0) end
end

-- This client's character `me`, in `guild` at rank `rank` (guild nil: in none), as the server gives it.
local function As(me, guild, rank)
	ns.me = me
	GetGuildInfo = function(unit)
		if (unit == nil or unit == "player") and guild then return guild, rank == 0 and "Guild Master" or "Officer", rank end
	end
	IsInGuild = function() return guild ~= nil end
end

-- The signed lists taken as the author's own file is (the test key in the author's place meanwhile).
local function Take(...)
	local lists = { ... }
	ns.Sign.WithKey(KEY_N, KEY_MU, 86, function()
		for _, blob in ipairs(lists) do
			local took
			if blob:sub(1, 4) == "HS1~" then took = ns.Workshop.TakeCouncil(blob) else took = ns.Workshop.TakeTitles(blob) end
			assert(took, "the test key's list: " .. blob:sub(1, 40))
		end
	end)
end

-- Relay.lua into a namespace of its own, its handlers going nowhere; its names come from the harness's Core.
local function WithRelay(fn)
	local cns = setmetatable({ On = function() end, RegisterEvent = function() end, After = function() end, Every = function() end,
		Comm = setmetatable({ Handle = function() end, RelayPieces = function() end }, { __index = ns.Comm }) }, { __index = ns })
	assert(loadfile(ADDON_DIR .. "Relay.lua"))("Olympus", cns)
	cns.splitNames = true
	fn(cns.Relay, cns)
end

-- Relay.Names as one string, ",A,B,", to look a name up in.
local function Relays(R) return "," .. table.concat(R.Names(true), ",") .. "," end

test("1.5.5 roles: the saved signed author sees a private council without the author's sidecar, with no council membership; other viewers stay private and the King's screen stays masked", function()
	local saved = { signed = ns.COUNCIL_SIGNED, titles = ns.COUNCIL_TITLES, dev = ns.devThrone,
		view = ns.db.devKingView, shown = ns.CouncilNamesShown() }
	local ok, err = pcall(WithForever, PVE_REALM, "Alliance", function()
		ns.COUNCIL_SIGNED, ns.COUNCIL_TITLES, ns.devThrone, ns.db.devKingView = nil, nil, nil, nil
		ns.SetCouncilNamesShown(false)
		Take(PVE_NAMES, PVE)
		eq(ns.CouncilTitles().public, false, "the saved signed list remains private")
		local author = "Quill Maker-" .. PVE_REALM
		As(author, OTHER, 3)
		eq(ns.IsAuthorName(ns.me), true, "the author comes from the saved signed titles")
		eq(ns.IsHighCouncillor(ns.me), false, "author visibility grants no council membership")
		eq(ns.CouncilVisible(), true, "the author sees the council without CouncilList.lua")
		eq(ns.KingsScreen(), false); eq(ns.CouncilMasked(), false)
		-- His preview still follows the King's mask, even though the author may see the council.
		ns.devThrone = true
		eq(ns.King.Preview(), true); eq(ns.CouncilMasked(), true)
		ns.devThrone = nil
		As("Some Body-" .. PVE_REALM, OTHER, 3)
		eq(ns.IsAuthorName(ns.me), false); eq(ns.CouncilVisible(), false, "holding the list alone does not reveal it")
		As("Quill Maker-" .. PVP_REALM, OTHER, 3)
		eq(ns.IsAuthorName(ns.me), false); eq(ns.CouncilVisible(), false, "a namesake of another realm group is no author")
		As("Test Councillor-" .. PVE_REALM, OTHER, 3)
		eq(ns.IsHighCouncillor(ns.me), true); eq(ns.CouncilVisible(), true, "a genuine councillor still sees it")
		As(KING, OTHER, 3)
		eq(ns.King.IsKing(), true); eq(ns.CouncilVisible(), true); eq(ns.CouncilMasked(), true, "the King keeps his mask")
		As(author, OTHER, 3)
		ns.rdb.councilTitles = nil
		ns.Workshop.ResetVerify()
		eq(ns.IsAuthorName(ns.me), false); eq(ns.CouncilVisible(), false, "no signed author identity: no extra visibility")
	end)
	ns.COUNCIL_SIGNED, ns.COUNCIL_TITLES, ns.devThrone, ns.db.devKingView = saved.signed, saved.titles, saved.dev, saved.view
	ns.SetCouncilNamesShown(saved.shown)
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- The Quaestor
---------------------------------------------------------------------------

test("1.5.5 roles: the Quaestor is whom the signed list's ^quaestor^ entry names, two a side, by name on his realm group, either side's; no Treasurer, King or councillor for it; nobody without the list", function()
	WithForever(PVE_REALM, "Alliance", function()
		eq(ns.IsQuaestorName(QUAESTOR), false, "no list held: nobody")
		eq(#ns.QuaestorPins(), 0)
		assert(ns.PinsStatus():find("Quaestor none", 1, true), ns.PinsStatus())
		Take(PVE_NAMES, PVE)
		eq(ns.IsQuaestorName(QUAESTOR), true)
		eq(ns.IsQuaestorName("tally reeve-" .. PVE_REALM), true, "on another sub-realm of the PvE family, whatever the case")
		eq(ns.IsQuaestorName("Tally Reeve"), true, "a name without a realm is ours")
		eq(ns.IsQuaestorName(QUAESTOR2), true, "the Alliance's second")
		eq(ns.IsQuaestorName(HORDE_QUAESTOR), true, "the Horde's: a name is one per realm group whatever its side")
		eq(ns.IsQuaestorName("Tally Reeve-" .. PVP_REALM), false, "a namesake of the PvP group")
		eq(ns.IsQuaestorName(TREASURER), false, "the Treasurer is no Quaestor")
		eq(table.concat(ns.QuaestorPins(), ","), QUAESTOR .. "," .. QUAESTOR2, "our side's, as signed")
		eq(table.concat(ns.QuaestorPins("Horde"), ","), HORDE_QUAESTOR)
		-- None of the Treasurer's powers, nor anyone else's.
		eq(ns.IsTreasurer(QUAESTOR, MAIN), false); eq(ns.IsTreasurerCharacter(QUAESTOR), false)
		eq(ns.Treasury.TreasurerPin(QUAESTOR), nil); eq(ns.Treasury.IsKeeperName(QUAESTOR, MAIN), false)
		eq(ns.IsKingCharacter(QUAESTOR), false); eq(ns.IsHighCouncillor(QUAESTOR), false); eq(ns.IsSteward(QUAESTOR), false)
		eq(ns.IsSpeedrunnerName(QUAESTOR), false, "the other signed names read as before")
		-- /oly status: how many, never a name.
		local status = ns.PinsStatus()
		assert(status:find("Quaestor signed (2)", 1, true) and status:find("Treasurer signed (1)", 1, true), status)
		assert(not status:find("Tally", 1, true) and not status:find("Coin", 1, true) and not status:find("Ledger", 1, true), status)
		ns.faction = "Horde"
		assert(ns.PinsStatus():find("Quaestor signed (1)", 1, true), ns.PinsStatus())
	end)
	-- The grammar: a third of one side is left out (ns.PINS_MAX.quaestor), the kind in lower case alone, a realm required.
	local p = ns.ReadPins("^quaestor^Alliance^Aa Bb-R,Cc Dd-R,Ee Ff-R;^Quaestor^Horde^Gg Hh-R;^quaestor^Horde^Ii Jj")
	eq(table.concat(p.quaestor.Alliance, ","), "Aa Bb-R,Cc Dd-R"); eq(p.quaestor.Horde, nil)
	eq(ns.PINS_MAX.quaestor, 2)
end)

test("1.5.5 roles: a signed Quaestor wears the Treasurer's blue dragon round the target, the focus, a party portrait and his own, in any guild or none, never over the King's crown; his title on the profile card and the tooltip", function()
	local saved = { pins = ns.SignedPins, me = ns.me }
	local pins = { quaestor = { Alliance = { "Tally Reeve-Realm" } } }
	ns.SignedPins = function() return pins end
	local ok, err = pcall(function()
		-- His own portrait, on his own screen (a member's: the addon works for members alone).
		WithBorders(function(w)
			w.units.player = BorderUnit("Tally Reeve", "Olympus II", "Member", 3)
			ns.me = "Tally Reeve-Realm"
			w.internal("LOGIN")
			eq(w.shown("player"), "treasurer-dragon", "round his own")
		end)
		WithBorders(function(w)
			local q = BorderUnit("Tally Reeve", "Olympus II", "Member", 3)
			w.party(); w.units.party1 = q
			w.internal("LOGIN")
			eq(w.shown("party1"), "treasurer-dragon", "round his party portrait")
			w.target(q)
			eq(w.B.TierOf("target"), "treasurer-dragon"); eq(w.shown("target"), "treasurer-dragon")
			eq(w.B.TierOfName("Tally Reeve-Realm", nil), "treasurer-dragon", "by his name alone")
			w.units.focus = q; w.fire("PLAYER_FOCUS_CHANGED")
			eq(w.shown("focus"), "treasurer-dragon")
			w.target(BorderUnit("Tally Reeve", nil, nil, nil))
			eq(w.shown("target"), "treasurer-dragon", "in no guild")
			w.target(BorderUnit("Tally Reeve", "Olympus II", "Member", 3, { realm = "Elsewhere" }))
			eq(w.shown("target"), nil, "a namesake of another realm group")
			-- The King's crown first: a King the list also names a Quaestor wears the crown.
			pins.quaestor.Alliance = { BORDER_KING.name .. "-Realm" }
			w.target(BORDER_KING)
			eq(w.B.TierOf("target"), "gold-elite", "never above the King's crown")
			-- A newer list without him: the dragon goes from the frame that showed it.
			pins.quaestor.Alliance = { "Tally Reeve-Realm" }
			w.target(q)
			eq(w.shown("target"), "treasurer-dragon")
			local computed = w.computed()
			w.B.CensusChanged()
			eq(w.computed(), computed, "an unchanged Quaestor keeps his cached border")
			pins.quaestor = nil
			w.B.CensusChanged()
			eq(w.shown("target"), nil, "no Quaestor named: no dragon")
		end)
		-- His title on his profile card (UI.lua in a namespace of its own) and in the game's tooltip.
		pins.quaestor = { Alliance = { "Tally Reeve-Realm" } }
		local uns = setmetatable({ On = function() end }, { __index = ns })
		assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
		local function HasTitle(rows)
			for _, r in ipairs(rows or {}) do if r:find(L.QUAESTOR_TITLE, 1, true) then return true end end
			return false
		end
		eq(HasTitle(uns.UI.BasePersonDetails({ name = "Tally Reeve", realm = "Realm", guild = "Olympus II" }).rows), true, "on his card")
		eq(HasTitle(uns.UI.BasePersonDetails({ name = "Pip Fennel", realm = "Realm", guild = "Olympus II" }).rows), false, "on nobody else's")
		local tip = { tip = GameTooltip, uip = UnitIsPlayer, ufn = UnitFullName, ggi = GetGuildInfo, pt = ns.PlayerTooltip }
		local lines = {}
		local okTip, errTip = pcall(function()
			GameTooltip = { GetName = function() return "GameTooltip" end, GetUnit = function() return "Tally Reeve", "mouseover" end,
				AddLine = function(_, t) lines[#lines + 1] = tostring(t) end }
			UnitIsPlayer = function() return true end
			UnitFullName = function() return "Tally Reeve", "Realm" end
			GetGuildInfo = function() return "Olympus II", "Member", 3 end
			ns.PlayerTooltip = nil
			ns.Inspect.TooltipUnit(GameTooltip)
		end)
		GameTooltip, UnitIsPlayer, UnitFullName, GetGuildInfo, ns.PlayerTooltip = tip.tip, tip.uip, tip.ufn, tip.ggi, tip.pt
		if not okTip then error(errTip, 0) end
		local found = false
		for _, line in ipairs(lines) do if line:find(L.QUAESTOR_TITLE, 1, true) then found = true end end
		assert(found, "his title in the tooltip: " .. table.concat(lines, " | "))
	end)
	ns.SignedPins, ns.me = saved.pins, saved.me
	if not ok then error(err, 0) end
end)

test("1.5.5 roles: the Quaestor's title and the waiting verification line in each of the 7 languages", function()
	local WANT = { enUS = "Quaestor", ptBR = "Questor", esES = "Cuestor", deDE = "Quästor", frFR = "Questeur", itIT = "Questore",
		ruRU = "Квестор" }
	local english
	for _, code in ipairs({ "enUS", "ptBR", "esES", "deDE", "frFR", "itIT", "ruRU" }) do
		local lns, savedLocale = {}, GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			for line in io.lines(ADDON_DIR .. "Olympus.toc") do
				local f = line:match("^%s*(Locales%.lua)%s*$") or line:match("^%s*(Locales[\\/].-%.lua)%s*$")
				if f then assert(loadfile(ADDON_DIR .. f:gsub("\\", "/")))("Olympus", lns) end
			end
		end)
		GetLocale = savedLocale
		if not ok then error(err, 0) end
		eq(lns.L.QUAESTOR_TITLE, WANT[code], code)
		local waiting = lns.L.VERIFY_STATUS_WAITING
		assert(type(waiting) == "string" and select(2, waiting:gsub("%%s", "")) == 1, code .. ": " .. tostring(waiting))
		if code == "enUS" then english = waiting else assert(waiting ~= english, code .. " translates the waiting line") end
	end
end)

---------------------------------------------------------------------------
-- The Treasurer on Forever, the relays
---------------------------------------------------------------------------

test("1.5.5 roles: on Forever's live realms the beta's code Treasurer is nobody and no relay; the signed Treasurer is the Treasurer in the King's main guild alone; the signed Quaestors are relays of their own side", function()
	WithForever(PVE_REALM, "Alliance", function()
		local pins, signed = ns.TreasurerPins()
		eq(#pins, 0, "no Treasurer signed: none, never the beta's pins"); eq(signed, false)
		eq(ns.TreasurerFull(), nil); eq(ns.TreasurerName(), nil)
		local beta = ns.TREASURER .. "-" .. PVE_REALM
		eq(ns.IsTreasurer(beta, MAIN), false); eq(ns.IsTreasurerCharacter(beta), false); eq(ns.Treasury.TreasurerPin(beta), nil)
		assert(ns.PinsStatus():find("Treasurer none (0)", 1, true), ns.PinsStatus())
		WithRelay(function(R)
			for _, c in ipairs(ns.TREASURER_CHARACTERS) do eq(R.IsRelay(c), false, "the beta's Treasurer's characters are no relays here") end
		end)
		Take(PVE_NAMES, PVE)
		pins, signed = ns.TreasurerPins()
		eq(table.concat(pins, ","), TREASURER); eq(signed, true)
		eq(ns.IsTreasurer(TREASURER, MAIN), true, "the signed Treasurer in the King's main guild")
		eq(ns.IsTreasurer(TREASURER, "Olympus Prime"), true, "whatever its case")
		eq(ns.IsTreasurer(TREASURER, "Olympus"), false, "a guild named Olympus is another guild here")
		eq(ns.IsTreasurer(TREASURER, OTHER), false)
		eq(ns.IsTreasurer("Ledger Wren-" .. PVP_REALM, MAIN), false, "a namesake of the PvP group")
		eq(ns.Treasury.TreasurerPin(TREASURER), 1); eq(ns.Treasury.IsKeeperName(TREASURER, MAIN), true, "a keeper of the treasury")
		-- His own client: the guild master of the main guild, its Treasurer, no King.
		As(TREASURER, MAIN, 0)
		eq(ns.Treasury.IsTreasurer(), true, "the Treasury's own question, on his client")
		eq(ns.King.IsKing(), false, "the main guild's master is no King")
		WithRelay(function(R, cns)
			cns.me = "Some Body-" .. PVE_REALM
			local names = Relays(R)
			for _, n in ipairs({ "Ledger Wren", "Tally Reeve", "Coin Bearer", "Crown Owl" }) do
				assert(names:find("," .. n .. ",", 1, true), n .. " is a relay: " .. names)
			end
			assert(not names:find(",Tusk Reeve,", 1, true), "the Horde's Quaestor is no Alliance relay: " .. names)
			eq(R.IsRelay("tally reeve"), true)
			ns.faction = "Horde"
			names = Relays(R)
			assert(names:find(",Tusk Reeve,", 1, true), "the Horde's own Quaestor: " .. names)
			assert(not names:find(",Tally Reeve,", 1, true) and not names:find(",Ledger Wren,", 1, true), "no Alliance name on the Horde: " .. names)
			ns.faction = "Alliance"
		end)
	end)
	-- The beta's group (the harness's "Realm", where the code pins the King and the Treasurer): as before.
	eq(ns.OnForever(), false)
	eq(ns.IsTreasurer(ns.TREASURER .. "-Realm", "Olympus"), true, "the code's Treasurer in <Olympus>, as before")
	eq(ns.IsTreasurer(ns.TREASURER .. "-Realm", MAIN), false)
	eq(select(2, ns.TreasurerPins()), false); eq(ns.TreasurerFull(), ns.TREASURER .. "-Realm")
end)

---------------------------------------------------------------------------
-- The main guild
---------------------------------------------------------------------------

-- The Realm's King line, if any.
local function KingLine()
	for _, l in ipairs(ns.Views.RealmLines()) do
		if (l.text or ""):find(L.KING .. ": ", 1, true) then return l end
	end
end

test("1.5.5 roles: on Forever's live realms OLYMPUS PRIME is the King's main guild; its guild master is no King, list or none (not the Throne's, not the King's presence or line, his reports taken); the signed King is the King in any guild; its master and officers are of the Crown", function()
	WithForever(PVE_REALM, "Alliance", function()
		eq(ns.OnForever(), true); eq(ns.KingIsMaster(), false)
		eq(ns.IsKingGuild(MAIN), true); eq(ns.IsKingGuild("Olympus Prime"), true)
		eq(ns.IsKingGuild("Olympus"), false, "a guild named Olympus is another Olympus guild here")
		eq(ns.IsFederation(MAIN), true); eq(ns.KingGuildName(), "Olympus Prime", "named so where we are not in it")
		-- Its fresh report, two others vouching: its guild master online.
		local now = ns.Now()
		ns.rdb.guilds[MAIN] = Vouched({ total = 900, online = 300, t = now, st = now, leader = "Fief Holder", leaderOnline = true,
			leaderDays = 0, realm = PVE_REALM, from = PVE_REALM, zones = {}, officers = { { name = "Shield Bearer", online = true } } },
			"Witness One-" .. PVE_REALM, "Witness Two-" .. PVE_REALM)
		-- No list held: a member of another guild sees no King in its master.
		As("Some Body-" .. PVE_REALM, OTHER, 3)
		eq(ns.KingUnpinned(), false)
		eq(ns.Hop.King(), nil, "its master online is not the King online")
		eq(KingLine(), nil, "no King line: no King named, and its master is not him")
		-- Its master's own client: no King, of the Crown.
		As(MASTER, MAIN, 0)
		eq(ns.King.IsKing(), false, "its master, no list held")
		eq(ns.IsCrown(), true, "of the Crown"); eq(ns.IsLord(), true)
		eq(ns.KingGuildName(), MAIN, "ours when we are in it")
		-- The signed list: the King it names.
		Take(PVE_NAMES, PVE)
		eq(ns.King.IsKing(), false, "its master, the list naming another King")
		eq(ns.Data.OtherKing(MAIN, "Fief Holder"), false, "its reports are taken while a King is named")
		As("Some Body-" .. PVE_REALM, OTHER, 3)
		eq(ns.Hop.King(), nil, "nor the King's presence with the list")
		local line = KingLine()
		assert(line and line.text:find("Crown Owl", 1, true) and not line.text:find("Fief", 1, true), "the signed King's line: " .. tostring(line and line.text))
		-- An officer of the main guild, on his own client: of the Crown too.
		As("Shield Bearer-" .. PVE_REALM, MAIN, 1)
		eq(ns.IsCrown(), true, "the main guild's officer, of the Crown"); eq(ns.King.IsKing(), false)
		-- The signed King: a Captain of the main guild, a member of another Olympus guild, in none.
		As(KING, MAIN, 1)
		eq(ns.King.IsKing(), true, "a Captain of the main guild")
		As(KING, OTHER, 3)
		eq(ns.King.IsKing(), true, "a member of another Olympus guild")
		As(KING, nil, nil)
		eq(ns.IsKingCharacter(KING), true, "his name in no guild (no member's client of his own: no Throne there)")
		eq(ns.Data.OtherKing(MAIN, "Crown Owl"), false)
	end)
	-- The Horde's King's guild on Forever is its own, as before; the beta's group as before.
	WithForever(PVE_REALM, "Horde", function() eq(ns.IsKingGuild("Mudhutters"), true); eq(ns.IsKingGuild(MAIN), false) end)
	eq(ns.OnForever(), false); eq(ns.KingIsMaster(), true)
	eq(ns.IsKingGuild("Olympus"), true); eq(ns.IsKingGuild(MAIN), false)
	eq(ns.Data.OtherKing("Olympus", "Anyone"), true, "the beta's: a report naming another than the King is refused, as before")
end)

---------------------------------------------------------------------------
-- The verification hold
---------------------------------------------------------------------------

-- Verify.lua and its words in a namespace of their own over the harness's (which holds none), its clock
-- `clock.now`; the Workshop's list hooks reach it (ns.Verify) while fn runs.
local function WithVerify(clock, fn)
	local dialogs = {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local vns = setmetatable({ On = function() end, RegisterEvent = function() end, After = function() end,
		Every = function() return { Cancel = function() end } end, Comm = { Handle = function() end },
		L = setmetatable({}, { __index = ns.L }) }, { __index = ns })
	assert(loadfile(ADDON_DIR .. "Locales/VerifyText.lua"))("Olympus", vns)
	assert(loadfile(ADDON_DIR .. "Verify.lua"))("Olympus", vns)
	vns.Verify.Clock = function() return clock.now end
	local saved = ns.Verify
	ns.Verify = vns.Verify
	local ok, err = pcall(fn, vns.Verify, vns)
	ns.Verify = saved
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(err, 0) end
end

test("1.5.5 roles: no verification hold where nobody can verify: on ForeverPvP no deadline, notice or hold; the list that names its first verifier starts it with 7 fresh days from its arrival; ForeverPvE as before", function()
	local GUILD, DAY = "Olympus Vanguard", 86400
	local clock = { now = 0 }
	WithForever(PVP_REALM, "Alliance", function(printed)
		WithVerify(clock, function(V, vns)
			Take(PVP_A_NAMES, PVP_A)
			As("Bram Hollow-" .. PVP_REALM, GUILD, 0)
			ns.rdb.guilds[GUILD] = { leader = "Bram Hollow", realm = PVP_REALM, total = 120, online = 10, t = 0 }
			-- (1.6.0.1: on Forever's groups but PvE every guild waits until OTHER_GROUPS_WAIT_UNTIL, whoever can
			-- verify there, tests/verify.lua; this 1.5.5 rule is seen after that wait, past every deadline it set.)
			clock.now = V.OTHER_GROUPS_WAIT_UNTIL + 3600
			V.Observe(clock.now)
			clock.now = V.OTHER_GROUPS_WAIT_UNTIL + V.GRACE + 2 * DAY -- (past every deadline the 1.5.4 reset and the wait set)
			eq(V.VerifierHere(), false, "no King, no councillor")
			local status, info = V.Status(GUILD)
			eq(status, "pending"); eq(info.waiting, true)
			eq(vns.MasterHeld(GUILD), false, "no hold")
			eq(V.Mine(), nil, "its guild master is told nothing")
			V.PrintStatus()
			eq(printed[#printed], vns.L.VERIFY_STATUS_WAITING:format(GUILD))
			-- The author's own character on the council's list: he verifies, but starts no hold.
			ns.rdb.council = { at = 1, names = { ["quill maker"] = "Quill Maker" }, realm = "ForeverPvP" }
			eq(V.Trusted("Quill Maker-" .. PVP_REALM), true)
			eq(V.VerifierHere(clock.now + 1), false, "the author's characters never count here")
			eq(V.HoldFrom(), nil)
			-- A newer signed list names a councillor: every guild has GRACE from its arrival.
			local arrived = clock.now + 10
			clock.now = arrived
			Take(PVP_B_NAMES)
			eq(V.HoldFrom(), arrived, "the hold starts when the list arrives")
			eq(V.VerifierHere(), true)
			status, info = V.Status(GUILD)
			eq(status, "pending"); eq(info.waiting, nil); eq(info.left, V.GRACE, "7 days from the list's arrival")
			eq(vns.MasterHeld(GUILD), false)
			assert(V.Mine(), "now its guild master is told")
			Take(PVP_B)
			eq(V.HoldFrom(), arrived, "the titles list after it starts nothing again")
			clock.now = arrived + V.GRACE + 1
			eq((V.Status(GUILD)), "overdue"); eq(vns.MasterHeld(GUILD), true, "held once the fresh grace is over")
		end)
	end)
	-- ForeverPvE: its signed King (and councillor) verify from the start; the 1.5.4 reset's deadlines stand.
	WithForever(PVE_REALM, "Alliance", function()
		WithVerify(clock, function(V, vns)
			Take(PVE_NAMES, PVE)
			eq(V.Trusted(KING), true, "the signed King verifies, in no guild of ours")
			As("Bram Hollow-" .. PVE_REALM, GUILD, 0)
			ns.rdb.guilds[GUILD] = { leader = "Bram Hollow", realm = PVE_REALM, total = 120, online = 10, t = 0 }
			clock.now = V.RESET_AT + 3600
			V.Observe(clock.now)
			eq(V.VerifierHere(), true); eq(V.HoldFrom(), nil, "no list held before it: no fresh grace")
			clock.now = V.RESET_AT + 3600 + V.GRACE + 1
			eq((V.Status(GUILD)), "overdue"); eq(vns.MasterHeld(GUILD), true, "held, as before")
			eq(V.ListTaken(true), false, "a newer list keeping its verifiers starts nothing"); eq(V.HoldFrom(), nil)
		end)
	end)
end)
