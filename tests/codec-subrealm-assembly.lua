-- One Forever character's pieces, stamped with two sub-realms of his family, are one message (#79):
-- his own sub-realm on the channel, ours when a relay hands his bare name on. Other realms, and
-- another family, stay apart.
local ns, test, eq = ...
local Codec = ns.Codec

test("Forever: one sender's pieces under two sub-realms of a family complete one message (#79)", function()
	local asm = Codec.NewAssembler()
	local payload = string.rep("r", Codec.CHUNK * 2 + 5)
	local parts = Codec.Chunk(payload, "137")
	eq(#parts, 3)
	eq(Codec.Feed(asm, "Not Dakooria-CAMWOWUS1Realm7PvE", parts[1], 0), nil)
	eq(Codec.Feed(asm, "Not Dakooria-CAMWOWUS1Realm1PvE", parts[2], 1), nil)
	eq(Codec.Feed(asm, "Not Dakooria-CAMWOWUS2Realm5PvE", parts[3], 2), payload)
	eq(asm.open, 0)
	eq(next(asm.bySender), nil)
end)

test("Forever: another family, or realms outside Forever, are never filed together", function()
	local asm = Codec.NewAssembler()
	local parts = Codec.Chunk(string.rep("s", Codec.CHUNK + 1), "9")
	eq(Codec.Feed(asm, "Same Name-CAMWOWUS1Realm1PvE", parts[1], 0), nil)
	eq(Codec.Feed(asm, "Same Name-CAMWOWUS1Realm1PvP", parts[2], 0), nil)
	eq(asm.open, 2)
	local other = Codec.NewAssembler()
	eq(Codec.Feed(other, "Tester-Realm", parts[1], 0), nil)
	eq(Codec.Feed(other, "Tester-OtherRealm", parts[2], 0), nil)
	eq(other.open, 2)
	eq(Codec.AssemblyName("Tester-Realm"), "Tester-Realm")
	eq(Codec.AssemblyName("Bare"), "Bare")
end)
