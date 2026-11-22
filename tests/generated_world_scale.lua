-- Detached 64/128 audit. No engine callbacks, shared runtime edits, or app copy.
-- Optional argv[1] is the installed Luanti builtin/common/serialize.lua.
local p="mods/bayline/"
local function m(n) return dofile(p..n..".lua") end
local Sim,Terrain,Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local Cam,TGP,Clear=m("generated_campaign"),m("openttd/terragenesis")(Slope),m("openttd/terragenesis_clear")
local Rivers=m("openttd/river_worldgen")(Slope)
local G=m("openttd/town_growth")
local B=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
local TownNames=m("openttd/stock_town_name")
local TownGen=m("openttd/town_worldgen")(G,B)
local H=m("openttd/town_passengers")
local Growth=m("town_growth_runtime")(Sim,Terrain,G,B,H)
local Packets,Rating=m("openttd/passengers"),m("openttd/station_rating")
local Cat=m("openttd/station_catchment")(Packets,Rating,function() return 0 end,function() return 0 end)
local Coal=m("openttd/coal_industry")(Packets,Rating,Cat,m("openttd/income"))
local Timber=Sim.timber_rules()
local Industry=m("openttd/industry_worldgen")(Coal,Timber)
local CoalWorld=m("coal_industry_world")(Sim,Terrain,Coal)
local TimberWorld=m("timber_world")(Sim,Terrain,Timber)
local Objects,Trees=m("openttd/scenery_object_worldgen"),m("openttd/tree_worldgen")
local Calendar=m("openttd/stock_engine_calendar")
local Storage,Stream=m("world_storage"),m("terrain_stream")(Slope)
local Owner=m("world_async_protocol")
local Pass=m("town_passenger_runtime")(Sim,H,Packets,Rating)
local serializer
if arg and arg[1] then core={};dofile(arg[1]);serializer=core; core=nil end
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function retained() collectgarbage("collect");return collectgarbage("count") end
local function rng(t)
  return t and ("%.0f/%.0f"):format(t[1],t[2]) or "-"
end

local function generate(size,river_amount)
  local t0=os.clock()
  local baseline=retained()
  local base,river,stats
  local Gen={next_random=TGP.next_random,describe=Clear.describe}
  function Gen.generate(o)
    base=TGP.generate(o)
    river,stats=Rivers.generate(base,TGP.next_random,{original=false,terrain=Terrain,
      amount_of_rivers=river_amount,min_river_length=16})
    return Clear.generate(river,TGP.next_random),stats
  end
  local s=Cam.landscape(Sim,Terrain,Gen,{
    width=size,depth=size,seed=1751,terrain_type=3,quantity_sea_lakes=0,
    tgen_smoothness=1,freeform_edges=true,water_borders=15,variety=0,rng_state=TGP.startup_rng(1751),
  })
  local towns=assert(Cam.towns(Sim,Terrain,s,Gen,TownGen,TownNames,G,B,{
    difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}))
  assert(towns.success)
  local industries=Cam.industries(Sim,Terrain,s,Gen,Industry,CoalWorld,4,nil,TimberWorld)
  local landmarks=Cam.landmarks(Sim,Terrain,s,Gen,Objects,Calendar.date(1950))
  local forest=Cam.forests(Sim,Terrain,s,Gen,Trees,2)
  local init=os.clock()-t0
  local mem=retained()-baseline
  eq(#s.tiles,size*size);eq(#s.corner_grid.levels,(size+1)^2)
  local p=s.stock_generated_profile
  eq(p.width,size);eq(p.depth,size);eq(p.timber_generation,true)
  local ss={size=size,mem=mem,init=init,towns=p.towns,industries=#industries.placed,landmarks=0,
    forest=forest.stats.tiles,head=p.river_rng_cursor or 1,river=stats.rivers}
  landmarks.each(function() ss.landmarks=ss.landmarks+1 end)
  assert(p.towns>0 and ss.industries>0 and ss.landmarks>0 and ss.forest>0 and p.forest[1]~=p.object_rng[1])
  print(("%dx%d seed1751 rivers=%d: existing host stages %.3fs CPU; %.1f KiB retained vs baseline; %d towns, %d industries, %d landmarks, %d forest tiles; river count %d; terrain/town/industry/object/trees RNG %s %s %s %s %s")
     :format(size,size,river_amount,ss.init,ss.mem,ss.towns,ss.industries,ss.landmarks,ss.forest,ss.river,
      rng(p.terrain_rng),rng(p.town_rng),rng(p.industry_rng),rng(p.object_rng),rng(p.forest)))

  if serializer then
    t0=os.clock()
    local save=serializer.serialize(s)
    local ser=os.clock()-t0
    t0=os.clock()
    local result=assert(serializer.deserialize(save,true))
    ss.saved=#save
    eq(result.tiles[size*size].stock_void,true);eq(result.stock_generated_profile.object_rng[2],p.object_rng[2])
    print(("%dx%d serialized campaign %d bytes, encode %.3fs/decode %.3fs CPU"):format(size,size,#save,ser,os.clock()-t0))
  end
  return s,ss,base,river
end

local function day(s,n)
  s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
  s.road_junction_clearance=true
  local present={}
  for _,p in ipairs(s.stock_generated_profile.industries) do present[p.kind]=true end
  s.road_coal,s.road_timber=present.coal_mine and present.power_station,present.sawmill and present.forest
  Sim.mount_stock_town_growth(s,Growth,true)
  Sim.mount_road_bus_market(s,Calendar,1950,true)
  Sim.mount_coastal_flood(s)
  local t=os.clock()
  for _=1,n do Sim.daily(s) end
  print(("%dx%d stock %d simulation days %.3fs CPU, clock offset %d, head %d"):format(Sim.W,Sim.H,n,os.clock()-t,
    s.passenger_house_clock.counter,s.passenger_house_clock.head))
end

local function arrival(s)
  local function clean(x,z)
    local id=Sim.id(x,z)
    local t=s.tiles[id]
    if t.terrain=="water" or t.house or t.site or t.build or t.stock_landmark or t.stock_industry then return end
    local mask,base=Terrain.tile(s.corner_grid,x,z)
    if mask==0 then return base end
  end
  for z=67,Sim.H-14 do for x=5,Sim.W-14 do
    local v=clean(x,z)
    if v then
      for _,d in ipairs{{1,0},{0,1}} do
        local dx,dz=d[1],d[2]
        local a=Sim.id(x+dx,z+dz)
        if Sim.site_radius(s,a) then
          for span=9,11 do
            local bx,bz=x+(span-1)*dx,z+(span-1)*dz
            local b=Sim.id(bx,bz)
            if Sim.site_radius(s,b) then
              local lane=true
              for i=1,span do if clean(x+i*dx,z+i*dz)~=v then lane=false;break end end
              if lane then
                local owner="ScaleAudit"
                local ids=Sim.line(Sim.id(x,z),Sim.id(x+span*dx,z+span*dz))
                assert(Sim.build(s,owner,"road",ids))
                assert(Sim.build(s,owner,"road_station",{a,b}))
                local sa,sb=s.stations[s.tiles[a].station],s.stations[s.tiles[b].station]
                local path,td,cost,frames=Sim.path(s,sa,sb,"road",owner)
                assert(path and cost>0 and frames and #frames>100 and td~=nil)
                eq(path[1],a);eq(path[#path],b)
                assert(a>8192 and frames[1][4]==a and frames[#frames][4]==b)
                print(("far clipped 128² directed stock road trace: tile %d → %d, station %d → %d, %d frames"):format(a,b,sa.id,sb.id,#frames))
                return a,sa.id
              end
            end
          end
        end
      end
    end
  end end
  error("No legal far-world road survey corridor")
end

do
  local s=generate(64,0)
  day(s,24)
end

local s,ss,base,river=generate(128,1)
Pass.start(s)
eq(s.passenger_house_clock.log_x,7);eq(s.passenger_house_clock.log_y,7)
eq(s.passenger_house_clock.head,ss.head)
local coverage={}
local temporary=H.new_clock(7,7,ss.head)
H.advance_houses(temporary,256,function(x,z)
  local i=z*128+x
  assert(not coverage[i]);coverage[i]=true
end,{},function() return 0 end,function() error("No houses injected") end)
eq(temporary.head,ss.head);eq(temporary.counter,256)
assert(coverage[0] and coverage[16383] and coverage[8128])
s.road_economy=true -- route's source authority should be enabled before building
local a,st=arrival(s)
day(s,24)
if serializer then
  local blob=serializer.serialize(s)
  local copy=assert(serializer.deserialize(blob,true))
  eq(copy.passenger_house_clock.log_x,7);eq(copy.passenger_house_clock.log_y,7)
  eq(copy.passenger_house_clock.head,s.passenger_house_clock.head)
  eq(copy.stations[st].tile,a)
  eq(s.passenger_house_clock.counter,24*74)
  Sim.daily(s)
  day(copy,1)
  eq(copy.passenger_house_clock.head,s.passenger_house_clock.head)
  eq(copy.passenger_house_clock.counter,25*74)
  eq(copy.passenger_rating_rng[1],s.passenger_rating_rng[1])
  eq(copy.passenger_rating_rng[2],s.passenger_rating_rng[2])
else
  eq(s.passenger_house_clock.counter,24*74)
end

-- Exercise the actual sparse foundation at the 128² scale too; this is
-- a detached base+overlay, not a replacement for the above dense sim.
local grid=Storage.new(128,128,river.storage_options())
local view=Stream.new(Stream.for_storage(Storage,grid,TGP.describe),{size=16,capacity=4})
local region=assert(view.update(64,64,16,4))
local left,right
for _,part in ipairs(region.chunks) do
  if part.x==49 and part.z==49 then left=part
  elseif part.x==65 and part.z==49 then right=part end
end
assert(left and right)
for z=49,64 do eq(Stream.corner(left,65,z),Stream.corner(right,65,z)) end
eq(Storage.stats(grid).chunks,0)
local a,b=Storage.snapshot(grid,65,65,96,96)
assert(Owner.snapshot(a) and b)
eq(#a.corners+#a.tiles,5185)
assert(not Owner.region(1,1,33,32))
print(("detached 128² sparse base save %d bytes, %d-byte maximum async input; no overlay chunks"):format(#Storage.encode(grid),#a.corners+#a.tiles))
print("PASS 128² production landscape clock, far route and bounded detached sparse input")
