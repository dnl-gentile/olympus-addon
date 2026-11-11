-- The packed census snapshot (Codec.PackCensus, Codec.UnpackCensus): the snapshot the relay's tree
-- carries to the registrants that read it (RelayTree.lua's RZ), in about three fifths of the pieces.
-- What the tree does with it: tests/relay-tree.lua; what it buys: tests/relay-tree-load.lua.
local ns, test, eq = ...

local function Snapshot(guilds, made)
	local rows = {}
	for i = 1, guilds do
		rows[i] = ("OLYMPUS LEGION %d,%d,%d,%d,%d"):format(i, 100 + i, 10 + i % 40, 250 + i, made - i * 3)
	end
	return ("CG~2~S~%d~ForeverPvE~Alliance~"):format(made) .. table.concat(rows, ";")
end

-- Fails before: no such form.
test("packed census: a snapshot comes back byte for byte, in about half the bytes; what the form cannot carry exactly is not packed", function()
	local C = ns.Codec
	local made = 1794350000
	local rows = {
		"OLYMPUS LXX,43,26,412,1794349990", "Olympus Dawn,640,40,300,1794349100", "OLYMPIANS,1000,0,0,1794350000",
		-- a name that begins with a mark of the form, an observation a week old, one after the snapshot
		"*Odd,1,1,600,1793745200", "+Plus,7,3,12,1794350200", "!Bang,5,5,5,1794349999",
		-- the bare prefix is a name of its own, and the largest counts two digits hold
		"OLYMPUS ,9,1,100,1794349000", "OLYMPUS FORCES OF EVIL,1295,1295,1295,1794349839",
	}
	for _, head in ipairs({ ("CG~2~S~%d~ForeverPvE~Alliance~"):format(made), ("CG~1~S~%d~"):format(made) }) do
		local text = head .. table.concat(rows, ";")
		local packed = C.PackCensus(text)
		assert(packed, "packed: " .. head)
		eq(packed:sub(1, 5), "CP~1~")
		eq(C.UnpackCensus(packed), text, "byte for byte")
		assert(#packed < #text * 0.7, ("%d bytes packed of %d"):format(#packed, #text))
	end
	-- The census as it is today: 170 guilds, about 37 bytes a row.
	local big = Snapshot(170, made)
	local packed = C.PackCensus(big)
	eq(C.UnpackCensus(packed), big)
	assert(#packed <= #big * 0.6, ("170 guilds: %d bytes packed of %d"):format(#packed, #big))
	-- Not packed: another word, an ask, a count past two digits, a row it does not know, a row
	-- left empty (it would not come back), a snapshot past the transport's bound.
	local head = "CG~2~S~1794350000~ForeverPvE~Alliance~"
	eq(C.PackCensus(nil), nil)
	eq(C.PackCensus("R2~Olympus II~43"), nil)
	eq(C.PackCensus("CG~2~Q~1794350000~0~0"), nil)
	eq(C.PackCensus(head .. "A,1296,1,1,1794350000"), nil, "a count past two digits")
	eq(C.PackCensus(head .. "A,1,1,1"), nil, "a row short of a field")
	eq(C.PackCensus(head .. "A,1,1,1,1794350000;"), nil, "an empty row at the end")
	eq(C.PackCensus(head .. "A,01,1,1,1794350000"), nil, "a count with a zero before it")
	eq(C.PackCensus(head .. ("A,1,1,1,1794350000;"):rep(400) .. "A,1,1,1,1794350000"), nil, "past the bound")
	-- Not unpacked: another form's number, a row that is no row, digits of another case, garbage.
	eq(C.UnpackCensus(nil), nil)
	eq(C.UnpackCensus("garbage"), nil)
	eq(C.UnpackCensus("CP~2~2~1794350000~ForeverPvE~Alliance~A,0101010"), nil, "a later form")
	eq(C.UnpackCensus("CP~1~2~1794350000~ForeverPvE~Alliance~A,01"), nil)
	eq(C.UnpackCensus("CP~1~2~1794350000~ForeverPvE~Alliance~A,0A01010"), nil)
	eq(C.UnpackCensus("CP~1~2~1794350000~ForeverPvE~A,0101010"), nil, "no scope where the snapshot's version has one")
	eq(C.UnpackCensus("CP~1~1~1794350000~A,0101010"), "CG~1~S~1794350000~A,1,1,1,1794350000")
end)
