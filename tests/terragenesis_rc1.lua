-- SPDX-License-Identifier: GPL-2.0-only
-- Reference: OpenTTD 16.0-RC1, 07b339c0aaeb0a87be9490b2f1c3f17c6b00b837.
-- A read-only observer in GenerateLandscape records tiles in Map::Size() order
-- immediately before CreateRivers(), after FixSlopes() and turning sea level
-- ground into water. Each digest starts at 1 and uses (v*65599+byte)%2147483647.
-- Normal new games using -G seed, temperate TerraGenesis, year 1950; only the
-- listed map controls vary. Neither rivers nor towns contribute to these values.
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."terragenesis.lua")(dofile(p.."slope.lua"))
local cases={
  -- seed, width, depth, relief, sea, smooth, borders, variety, freeform,
  -- height digest, tile-class digest, RNG words, clear ground (else 0) digest
  {1751,128,128,1,0,1,16,0,true,1041299,1479066007,965723248,4217575946,1872833868},
  {49832,64,128,3,0,0,5,0,true,1347135023,220291938,1004590592,2088352089,1502277269},
  {92714,256,128,2,2,2,10,0,true,567279525,1563035095,2306014960,1446523869,2054420284},
  {5001,64,64,4,1,3,0,0,true,936856755,37587746,1637086945,1838723087,1991332498},
  {9152,128,64,3,3,1,0,0,false,102692795,1859011483,455618788,566147275,1502277269},
  {1735,256,256,1,1,1,15,2,true,409706876,1180995030,4004424778,2290870707,1729200922},
}
local cells=0
for _,row in ipairs(cases) do
  local seed,w,h,relief,sea,smooth,coast,variety,freeform,expectedH,expectedT,rng0,rng1,expectedC=unpack(row)
  local v=G.generate({seed=seed,width=w,depth=h,terrain_type=relief,quantity_sea_lakes=sea,
    tgen_smoothness=smooth,water_borders=coast,variety=variety,freeform_edges=freeform,
    rng_state=G.startup_rng(seed)})
  local hh,tt,cc=1,1,1
  for z=1,h do for x=1,w do
    hh=(hh*65599+v.corner(x,z))%2147483647
    local word=v.tile(x,z)
    tt=(tt*65599+word%16)%2147483647
    cc=(cc*65599+math.floor(word/256)%16)%2147483647
  end end
  assert(hh==expectedH and tt==expectedT and cc==expectedC and v.rng_after[1]==rng0 and v.rng_after[2]==rng1,
    ("seed %u %dx%d: got heights %.0f, classes %.0f, cover %.0f, RNG %.0f/%.0f"):format(seed,w,h,hh,tt,cc,unpack(v.rng_after)))
  cells=cells+w*h
end
print(("PASS six normal RC1 worlds, %d complete pre-river corner/class/cover triples and RNG checkpoints"):format(cells))
