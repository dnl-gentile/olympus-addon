-- Codec.Gc's window is meant to drop assemblies whose sender stopped, not ones still arriving.
-- A report paced behind a busy queue (Comm's SEND_INTERVAL, one message a tick) can take longer
-- than the window from its first piece to its last; before the sliding window below, every such
-- report was discarded and the census never heard that guild (issue #79).
local ns, test, eq = ...
local Codec = ns.Codec

test("a steadily arriving report is not dropped", function()
	local asm = Codec.NewAssembler()
	local payload = string.rep("x", Codec.CHUNK * 4 + 10)
	local parts = Codec.Chunk(payload, "1")
	eq(#parts, 5)
	local now, done = 0, nil
	for i = 1, #parts do
		done = Codec.Feed(asm, "Someone-OtherRealm", parts[i], now) or done
		now = now + 25
		eq(Codec.Gc(asm, now), 0)
	end
	eq(done, payload)
end)

test("a stalled report is still dropped", function()
	local asm = Codec.NewAssembler()
	local parts = Codec.Chunk(string.rep("y", Codec.CHUNK * 2), "2")
	Codec.Feed(asm, "Quiet-OtherRealm", parts[1], 0)
	eq(Codec.Gc(asm, 30), 0)
	local dropped, sample = Codec.Gc(asm, 61)
	eq(dropped, 1)
	eq(type(sample), "string")
end)

test("a drip-fed report expires at ASM_MAX_AGE", function()
	local asm = Codec.NewAssembler()
	local parts = Codec.Chunk(string.rep("z", Codec.CHUNK * 9 + 1), "3")
	eq(#parts, 10)
	local now = 0
	for i = 1, 4 do
		Codec.Feed(asm, "Slow-OtherRealm", parts[i], now)
		now = now + 50
		Codec.Gc(asm, now)
	end
	eq(Codec.Gc(asm, Codec.ASM_MAX_AGE + 1), 1)
end)
