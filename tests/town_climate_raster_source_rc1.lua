-- SPDX-License-Identifier: GPL-2.0-only
-- Six ordinary new worlds from the actual OpenTTD 16.0-RC1 executable
-- (07b339c), observed after sea conversion and again before CreateRivers.
-- Each row includes the climate, requested coverage, seed, map width
-- (square), and pre/post stock fields: snowline, LFSR cursor, RNG0, RNG1,
-- north corner, tile type, tropic zone, clear ground and clear density.
-- The last five values hash every byte in row-major source order.
local p="mods/luanttd_core/openttd/"
local Slope=dofile(p.."slope.lua")
local TGP=dofile(p.."terragenesis.lua")(Slope)
local Climate=dofile(p.."town_climate_landscape_rc1.lua")
local TreeClimate=dofile(p.."tree_climate_rc1.lua")
local River=dofile(p.."river_worldgen.lua")(Slope,
  dofile(p.."river_landscape_rc1.lua"),dofile(p.."river_yapf_rc1.lua"),
  dofile(p.."tree_lifecycle_temperate.lua")(dofile(p.."tree_worldgen.lua"),TreeClimate))
local Terrain=dofile(p.."terrain.lua")
local Raster=dofile(p.."stock_climate_raster_rc1.lua")(Climate,River,Slope)
local cases={
  { "arctic", 40, 1751, 128, {10,1,3675836511,693001808,1668593645,23957362,1872833868,439927600,747634718}, {7,1,3675836511,693001808,1668593645,23957362,1872833868,439927600,747634718} },
  { "arctic", 100, 49832, 64, {10,1,940541026,321843086,1043834943,1526291101,231806982,2115869472,859387501}, {2,1,940541026,321843086,1043834943,1526291101,231806982,2115869472,859387501} },
  { "tropic", 50, 1751, 128, {10,1,3675836511,693001808,58059820,23957362,1872833868,439927600,747634718}, {10,6090,3675836511,693001808,58059820,23957362,1033224911,1829914997,1410709165} },
  { "tropic", 0, 49832, 64, {10,1,1924817233,3664284445,363182570,1526291101,231806982,86137925,859387501}, {10,2899,1924817233,3664284445,363182570,1526291101,1455844581,86137925,993450461} },
  { "tropic", 100, 19281, 64, {10,1,3677949912,2554809715,530532440,301688963,231806982,1229272672,965705233}, {10,2899,3677949912,2554809715,530532440,301688963,258712474,743250523,1415090158} },
  { "toyland", 40, 1751, 128, {10,1,3675836511,693001808,928901197,23957362,1872833868,439927600,747634718}, {10,1,3675836511,693001808,928901197,23957362,1872833868,439927600,747634718} },
}

local floor=math.floor
local function compare(raster,v)
  local a={raster.snowline or 10,raster.climate_tileloop_cursor or 1,
    raster.rng_after[1],raster.rng_after[2],1,1,1,1,1}
  for z=1,raster.depth do for x=1,raster.width do
    local word=raster.tile(x,z)
    local typ=word%16
    local zone=raster.tropic_zone and raster.tropic_zone(x,z) or 0
    local ground=typ==0 and floor(word/256)%16 or 255
    local density=typ==0 and (raster.clear_density and raster.clear_density(x,z) or 3) or 255
    local row={raster.corner(x,z),typ,zone,ground,density}
    for i=1,5 do a[4+i]=(a[4+i]*65599+row[i])%2147483647 end
    if raster.town_climate then
      local town=raster.town_climate(x,z)
      assert(town.tile_height==row[1] and town.is_desert==(zone==1) and town.snowline==raster.snowline)
    end
  end end
  for i=1,#a do assert(a[i]==v[i],("%s field %d: got %.0f expected %.0f"):format(raster.base_id,i,a[i],v[i])) end
end
local cells=0
for _,r in ipairs(cases) do
  local climate,coverage,seed,w,pre,post=unpack(r)
  local src=TGP.generate({seed=seed,width=w,depth=w,terrain_type=3,water_borders=0,
    landscape=climate,rng_state=TGP.startup_rng(seed)})
  compare(src,pre)
  local mounted=Raster.prepare(src,{snow_coverage=coverage,desert_coverage=coverage})
  compare(mounted,post)
  cells=cells+w*w
end
print(("PASS six native RC1 pre-river climate rasters, %d complete two-stage tile comparisons"):format(2*cells))

-- The same source release, observed *after* CreateRivers on actual
-- generated Tropic games with the stock Tree Placer: None setting.
-- Extra fields are the river/sea/coast class and the per-river byte.
local river_cases={
  {50,1751,128,3,0,2,{7679,3936488172,3848737868,214,1130517285,875399956,984457462,743150958,1023517959,1682335,1996784304}},
  {50,1751,256,1,15,2,{51822,277821337,3072597859,1304,1731727065,1489568074,1738104775,1610769177,1024485159,770269100,1245874751}},
  {75,49832,128,3,5,3,{7679,2379605804,3698227604,209,508722553,907661280,799493301,592628164,1184674994,570630785,239808661}},
  {20,19281,128,1,15,2,{7679,2571095424,1517832688,250,102453527,937255442,1115757148,600390354,451448432,918629972,494609232}},
}
local squares,river_tiles,old_desert=0,0,0
for _,r in ipairs(river_cases) do
  local coverage,seed,w,relief,coasts,native_rivers,expected=unpack(r)
  local raster=TGP.generate({seed=seed,width=w,depth=w,terrain_type=relief,water_borders=coasts,
    landscape="tropic",rng_state=TGP.startup_rng(seed)})
  local prep=Raster.prepare(raster,{desert_coverage=coverage})
  local result=River.generate(prep,TGP.next_random,{terrain=Terrain,rc1=true,original=false,
    terrain_type=relief,tree_placer=0,climate_rules=Climate,amount_of_rivers=native_rivers})
  local a={result.river_tileloop_cursor,result.rng_after[1],result.rng_after[2],0,1,1,1,1,1,1,1}
  for z=1,w do for x=1,w do
    local word=result.tile(x,z)
    local typ=word%16
    local water=typ==6 and floor(word/16)%16 or 0
    local zone=result.tropic_zone(x,z)
    local row={result.corner(x,z),typ,zone,typ==0 and floor(word/256)%16 or 255,
      result.clear_density(x,z) or 255,water,water==3 and result.river_bits(x,z) or 255}
    if water==3 then a[4]=a[4]+1 end
    if prep.tropic_zone(x,z)==Climate.DESERT and zone==Climate.NORMAL then old_desert=old_desert+1 end
    local t=result.town_climate(x,z)
    assert(t.tile_height==row[1] and t.is_desert==(zone==Climate.DESERT))
    for i=1,7 do a[4+i]=(a[4+i]*65599+row[i])%2147483647 end
  end end
  for i=1,#a do assert(a[i]==expected[i],("Tropic seed %u field %d: got %.0f expected %.0f"):format(seed,i,a[i],expected[i])) end
  squares,river_tiles=squares+w*w,river_tiles+a[4]
end
assert(old_desert==2779 and river_tiles==1977)
print(("PASS four native RC1 Tropic river maps: %d complete tile comparisons, %d river tiles and %d removed desert zones"):
  format(squares,river_tiles,old_desert))

-- Real Tropic seeds with the stock Improved tree placer. These
-- deliberately contain wooded terminal wetlands, not zero-tree maps.
local wooded={
  {92714,{51822,1503952669,1178545279,2224,62,1130132792,353067503,1420509103,327503182,2096091960,1616726842,514408431,1803457060,723148231,637249236,1383020346,1374757934}},
  {49832,{51822,2937394600,1693022804,1718,51,980850018,111563986,1420509103,1350869292,1844192794,1301171585,1596626412,1874600199,757206843,1182334445,1129495338,1765783348}},
  {9152,{51822,1205151467,1282742301,1463,50,470363359,753800510,1420509103,941766583,2141828185,476755711,752508495,2040181177,1017504916,1001053822,341347638,1474211817}},
}
local total_trees=0
local keys={"type","count","growth","ground","density"}
for _,r in ipairs(wooded) do
  local seed,expected=unpack(r)
  local w=256
  local base=TGP.generate({seed=seed,width=w,depth=w,terrain_type=1,water_borders=0,variety=2,
    landscape="tropic",rng_state=TGP.startup_rng(seed)})
  local prep=Raster.prepare(base,{desert_coverage=10})
  local result=River.generate(prep,TGP.next_random,{terrain=Terrain,rc1=true,original=false,terrain_type=1,
    tree_placer=2,tree_climate=TreeClimate,climate_rules=Climate,amount_of_rivers=3,min_river_length=4})
  local a={result.river_tileloop_cursor,result.rng_after[1],result.rng_after[2],0,0}
  for i=1,12 do a[i+5]=1 end
  for z=1,w do for x=1,w do
    local word=result.tile(x,z)
    local typ=word%16
    local water=typ==6 and floor(word/16)%16 or 0
    local row={result.corner(x,z),typ,result.tropic_zone(x,z),typ==0 and floor(word/256)%16 or 255,
      result.clear_density(x,z) or 255,water,water==3 and result.river_bits(x,z) or 255}
    local tree=result.river_tree(x,z)
    assert((tree~=nil)==(typ==4))
    for k,name in ipairs(keys) do row[k+7]=tree and tree[name] or 255 end
    if water==3 then a[4]=a[4]+1 end
    if tree then a[5]=a[5]+1 end
    for i=1,12 do a[5+i]=(a[5+i]*65599+row[i])%2147483647 end
  end end
  for i=1,#a do assert(a[i]==expected[i],("Tropic wooded seed %u field %d: got %.0f expected %.0f"):format(seed,i,a[i],expected[i])) end
  total_trees=total_trees+a[5]
end
assert(total_trees==163)
print("PASS three native RC1 wooded Tropic river maps, 196,608 tiles and 163 exact trees")

-- Explicit edge cases from TreeType and the climate prefix of TileLoop_Trees.
assert(TreeClimate.kind("tropic",TreeClimate.DESERT,12)==27)
assert(not TreeClimate.kind("tropic",TreeClimate.DESERT,13))
assert(TreeClimate.kind("tropic",TreeClimate.NORMAL,0)==28 and TreeClimate.kind("tropic",TreeClimate.NORMAL,255)==31)
assert(TreeClimate.kind("tropic",TreeClimate.RAINFOREST,0)==20 and TreeClimate.kind("tropic",TreeClimate.RAINFOREST,255)==26)
local TL=dofile(p.."tree_lifecycle_temperate.lua")(dofile(p.."tree_worldgen.lua"),TreeClimate)
local tree={class=4,type=21,count=1,growth=3,ground=1,density=1}
local dry=TL.visit(tree,3,4,2560,2,function() error("noncactus in desert skips ordinary growth roll") end,
  nil,nil,TreeClimate.DESERT)
assert(dry.growth==4 and dry.ground==2 and dry.density==3)
assert(not TreeClimate.can_spread("tropic",TreeClimate.DESERT,2))
assert(TreeClimate.can_spread("tropic",TreeClimate.RAINFOREST,1))
assert(not TreeClimate.can_spread("tropic",TreeClimate.NORMAL,1))
local calls=0
local forest=TL.visit(tree,0,0,0,3,function() calls=calls+1;return 65535 end,nil,nil,TreeClimate.RAINFOREST)
assert(forest==tree and calls==1)
