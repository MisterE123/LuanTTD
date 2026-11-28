-- Start exact generated towns without rendering unported house meshes.
local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local function o(n) return m("openttd/"..n) end
local S,T,Slope=m("sim"),o("terrain"),o("slope")
local TG=o("terragenesis")(Slope)
local Climate,Tree=o("town_climate_landscape_rc1"),o("tree_climate_rc1")
local River=o("river_worldgen")(Slope,o("river_landscape_rc1"),o("river_yapf_rc1"),
  o("tree_lifecycle_temperate")(o("tree_worldgen"),Tree))
local Raster=o("stock_climate_raster_rc1")(Climate,River,Slope)
local Clear=o("terragenesis_clear_rc1")
local G=o("town_growth")
local Catalog=o("town_growth_houses_all_rc1")
local B=o("town_growth_build")(G,o("town_growth_houses"),Catalog)
local World=o("town_worldgen")(G,B)
local Campaign=m("generated_campaign")
local Codec=m("packed_campaign")
local Names,Stats=o("stock_town_name"),o("town_cargo_stats")
local Live=m("town_growth_runtime")(S,T,G,B,o("town_passengers"))
local floor=math.floor
local roots={}
for _,r in ipairs(Catalog) do roots[r[1]]={width=r[6],depth=r[7]} end
local function eq(d,a,b)
  assert(#a==#b,d)
  for i=1,#a do assert(a[i]==b[i],("%s field %d: %.0f != %.0f"):format(d,i,a[i],b[i])) end
end
local town_count,cells,roads,houses,food_checks,water_checks,reopens=0,0,0,0,0,0,0
for _,r in ipairs(dofile("tests/fixtures/rc1-climate-town-start.lua")) do
  local climate,seed,coverage,w,relief,amount,pre,post,map,towns=unpack(r)
  local Generator={next_random=TG.next_random,describe=Clear.describe}
  function Generator.generate(opts)
    local raw=TG.generate(opts)
    local prepared=Raster.prepare(raw,{desert_coverage=coverage,snow_coverage=coverage})
    local river,stats=River.generate(prepared,TG.next_random,{rc1=true,original=false,terrain=T,
      terrain_type=relief,amount_of_rivers=amount,tree_placer=0,climate_rules=Climate})
    return Clear.generate(river,TG.next_random),stats
  end
  local s=Campaign.landscape(S,T,Generator,{width=w,depth=w,seed=seed,terrain_type=relief,
    quantity_sea_lakes=0,tgen_smoothness=1,water_borders=0,variety=0,freeform_edges=true,
    landscape=climate,rng_state=TG.startup_rng(seed)})
  local profile=s.stock_generated_profile
  eq(climate.." before towns",
    {s.stock_climate.snowline or 10,unpack(profile.terrain_rng)},{pre[4],pre[5],pre[6]})
  s.stock_world_animations=o("world_animation_rc1").new()
  s.stock_pool_authority=true
  local made,why=Campaign.towns(S,T,s,Generator,World,Names,G,B,{layout="original",
    growth_setting=2,difficulty=3,custom_count=1,larger_towns=4,separation=20,
    initial_city_size=2,year=1985},roots)
  assert(made,why)
  local pop=s.stock_town_growth
  eq(climate.." after towns",{profile.town_rng[1],profile.town_rng[2],#pop.order},post)
  for j,id in ipairs(pop.order) do
    local t,site=pop.towns[id],s.sites[id]
    eq(climate.." town "..id,{t.stock_id or id-1,(t.z-1)*w+t.x-1,site.nameparts,t.larger_town and 1 or 0,
      t.population,t.num_houses,t.growth_rate,t.grow_counter,0,t.goal[4] or 0,t.goal[5] or 0},towns[j])
  end
  local digest={0,0,1,1,1,1,1,1,1,1}
  for z=1,w do for x=1,w do
    local cell=s.tiles[S.id(x,z)]
    local h=cell.source_house
    local kind=cell.stock_void and 7 or h and 3 or cell.terrain=="water" and 6 or cell.wood and 4
      or cell.build=="road" and 2 or (cell.road_bridge_id or cell.road_tunnel_id) and 9 or 0
    local owner=h and h.town-1 or 0
    local a={T.corner(s.corner_grid,x,z),kind,h and h.id or 0,owner%256,floor(owner/256),
      h and h.random_bits or 0,h and h.stage or 0,kind==2 and cell.road_bits or 0}
    if kind==2 then digest[1]=digest[1]+1 elseif kind==3 then digest[2]=digest[2]+1 end
    for i,v in ipairs(a) do digest[i+2]=(65599*digest[i+2]+v)%2147483647 end
  end end
  eq(climate.." physical tiles",digest,map)
  town_count,cells,roads,houses=town_count+#pop.order,cells+w*w,roads+digest[1],houses+digest[2]

  -- Exercise the actual monthly runtime on these generated town centers.
  -- Zero is the winning no-service RNG sample; the terrain gate must
  -- still block before the lottery when actual receipts are absent.
  local applicable={}
  for _,id in ipairs(pop.order) do
    local t=pop.towns[id]
    local cell=s.tiles[S.id(t.x,t.z)]
    local h=T.corner(s.corner_grid,t.x,t.z)
    if climate=="arctic" and h>=s.stock_climate.snowline and t.population>90 then applicable[#applicable+1]=t end
    if climate=="tropic" and cell.stock_tropic_zone==1 and t.population>60 then applicable[#applicable+1]=t end
  end
  local function winning() return 0 end
  if #applicable>0 then
    if climate=="tropic" then
      local restored=assert(Codec.decode(Codec.encode(s)))
      for _,t in ipairs(applicable) do
        local id=S.id(t.x,t.z)
        assert(restored.tiles[id].stock_tropic_zone==s.tiles[id].stock_tropic_zone)
        assert(restored.tiles[id].stock_water_rocks==s.tiles[id].stock_water_rocks)
      end
      for j,t in ipairs(applicable) do applicable[j]=restored.stock_town_growth.towns[t.id] end
      s=restored
      reopens=reopens+1
    end
    Live.month(s,1,winning)
    for _,t in ipairs(applicable) do
      assert(not t.growing)
      Stats.accept(s,t.id,"food",1,1)
    end
    Live.month(s,2,winning)
    for _,t in ipairs(applicable) do
      if climate=="arctic" then assert(t.growing);food_checks=food_checks+1
      else assert(not t.growing);Stats.accept(s,t.id,"water",1,0);Stats.accept(s,t.id,"food",1,1) end
    end
    if climate=="tropic" then
      Live.month(s,3,winning)
      for _,t in ipairs(applicable) do assert(t.growing);water_checks=water_checks+1 end
    end
  end
end
assert(food_checks>0 and water_checks>0 and reopens==2)
print(("PASS %d native RC1 towns and %d map cells (%d road tiles and %d house tiles) at generation"):
  format(town_count,cells,roads,houses))
print(("PASS live receipt gate at %d snowy Arctic towns and %d Tropic desert towns"):
  format(food_checks,water_checks))
