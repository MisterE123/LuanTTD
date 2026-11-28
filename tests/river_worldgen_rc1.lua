-- SPDX-License-Identifier: GPL-2.0-only
local root="mods/luanttd_core/openttd/"
local function m(n)return dofile(root..n..".lua")end
local S=m("slope")
local G=m("terragenesis")(S)
local R=m("river_worldgen")(S,m("river_landscape_rc1"),m("river_yapf_rc1"),m("tree_lifecycle_temperate")(m("tree_worldgen")))
-- These digests come from the unmodified RC1 CreateRivers algorithm,
-- observed after its conversion of remaining water and 256 tile-loop
-- passes. The cases cover linked sea, small inland sea drainage, several
-- path lengths, river widening, lakes and a large tree-planted wetland.
local cases={
  {1751,128,128,1,0,1,16,0,1,1041299,1655128369,2448967438,1114008311},
  {49832,64,128,3,0,0,5,0,1,1347135023,951164981,701620539,686548475},
  {92714,256,128,2,2,2,10,0,1,1549243431,1555525384,2914004549,835943682},
  {5001,64,64,4,1,3,0,0,1,222643321,1184046099,3117213283,2786570841},
  {9152,128,64,3,3,1,0,0,0,1800457918,1427932911,2547896570,810400603},
  {1735,256,256,1,1,1,15,2,1,922317548,1335474452,1705647759,568998997},
}
for _,a in ipairs(cases) do
  local seed,w,h,relief,sea,smooth,coast,variety,freeform,expectedH,expectedT,rng0,rng1=unpack(a)
  local v=G.generate({seed=seed,width=w,depth=h,terrain_type=relief,quantity_sea_lakes=sea,
    tgen_smoothness=smooth,water_borders=coast,variety=variety,freeform_edges=freeform==1,
    rng_state=G.startup_rng(seed)})
  local map,stats=R.generate(v,G.next_random,{rc1=true,original=false,terrain=m("terrain"),min_river_length=16,
    amount_of_rivers=2,terrain_type=relief,tree_placer=2})
  local hh,tt,trees=1,1,0
  for z=1,h do for x=1,w do
    hh=(hh*65599+map.corner(x,z))%2147483647
    local k=map.tile(x,z)%16
    tt=(tt*65599+k)%2147483647
    if k==4 then trees=trees+1;assert(map.river_tree(x,z)) end
  end end
  assert(hh==expectedH and tt==expectedT and map.rng_after[1]==rng0 and map.rng_after[2]==rng1,
    ("seed %d: terrain %.0f, class %.0f, RNG %.0f/%.0f"):format(seed,hh,tt,unpack(map.rng_after)))
  if seed==1735 then assert(stats.rivers==16 and trees==485,"Wetland was not painted and settled") end
end
print("PASS six native 16.0-RC1 river stages including a 485-tile wooded wetland and overlapping sea drainage")
