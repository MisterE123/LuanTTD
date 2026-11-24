-- Use ordinary source terrain and generated town edge radii, then check
-- the RC1 landmark pass writes rocks into the same tile state ships see.
local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local Sim,Terrain,Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local TG=m("openttd/terragenesis")(Slope)
local Clear=m("openttd/terragenesis_clear_rc1")
local Calendar=m("openttd/stock_engine_calendar")
local Scenery=m("openttd/scenery_object_rc1")(Clear,Calendar)
local Campaign=m("generated_campaign")
local Growth=m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(Growth,m("openttd/town_growth_houses"))
local Worldgen=m("openttd/town_worldgen")(Growth,Build)
local Gen={generate=function(o) return Clear.generate(TG.generate(o),TG.next_random) end,
  describe=Clear.describe,next_random=TG.next_random}
local opts={width=128,depth=128,seed=1751,terrain_type=1,quantity_sea_lakes=0,tgen_smoothness=1,
  freeform_edges=true,water_borders=15,variety=0,rng_state=TG.startup_rng(1751)}
local s=Campaign.landscape(Sim,Terrain,Gen,opts)
assert(Campaign.towns(Sim,Terrain,s,Gen,Worldgen,m("openttd/stock_town_name"),Growth,Build,
  {difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}))
-- Industry generation ordinarily provides this checkpoint. This focused map
-- installs one obstruction but does not exercise industry quota selection.
local profile=s.stock_generated_profile
profile.industry_rng=profile.town_rng
local wet_before={}
for id,t in ipairs(s.tiles) do if t.stock_water_rocks then wet_before[id]=true end end
local date=assert(Calendar.date(1950,1,1))
local result=Campaign.landmarks(Sim,Terrain,s,Gen,Scenery,date)
assert(profile.object_rng[1]==result.rng_after[1] and profile.object_rng[2]==result.rng_after[2])
local Packed=m("packed_campaign")
local saved=assert(Packed.decode(Packed.encode(s)))
local Track=m("openttd/rail_track")
local Water=m("openttd/ship_follow")(Track)
local Ships=m("ship_network")(Sim,Terrain,Water,{})
local board=Ships.board(s)
local towers,rock_land,rock_sea,rock_shore=0,0,0,0
result.each(function(x,z,o)
  local tile=s.tiles[Sim.id(x,z)]
  assert(tile.stock_landmark and tile.stock_landmark.type==o.type and not tile.stock_clear_ground)
  if o.kind=="lighthouse" then towers=towers+1 end
end)
result.each_rock(function(x,z,ground,wet)
  local id=Sim.id(x,z)
  local tile=s.tiles[id]
  assert(tile.stock_clear_ground==ground and tile.stock_water_rocks==wet)
  assert(saved.tiles[id].stock_clear_ground==ground and saved.tiles[id].stock_water_rocks==wet)
  if wet and not wet_before[id] then
    assert(tile.terrain=="water" and tile.water_class=="sea" and Water.at(board,id)==0)
    if tile.coastal_water then rock_shore=rock_shore+1 else rock_sea=rock_sea+1 end
  elseif ground then
    assert(ground==2)
    rock_land=rock_land+1
  end
end)
assert(towers>0 and rock_shore>0 and rock_sea>0 and rock_land>0,
  ("%d towers, %d shore, %d sea, %d land"):format(towers,rock_shore,rock_sea,rock_land))
print(("PASS RC1 native lighthouse halos: %d towers, %d added shore rocks, %d open-water rocks, %d land rocks"):format(
  towers,rock_shore,rock_sea,rock_land))
