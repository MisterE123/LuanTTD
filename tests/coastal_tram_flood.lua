local mod="mods/luanttd_core"
local S=dofile(mod.."/sim.lua")
local Packed=dofile(mod.."/packed_campaign.lua")
local s=S.new(1751)
dofile(mod.."/town_layout.lua")(S,s)
local F=dofile("tests/coastal_tram_fixture.lua")(S,mod,os.getenv("LUANTTD_TEST_MIXED_FLOOD")=="1")
local proof=F.start(s)
assert(F.finish(assert(Packed.decode(Packed.encode(s))),proof))
print("PASS: paid coastal tram wreck persists, retires by stock tick, and leaves another paying tram intact")
