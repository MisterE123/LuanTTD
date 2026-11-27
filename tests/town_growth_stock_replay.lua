local m="mods/luanttd_core/"
local function l(n)return dofile(m..n..".lua")end
local Sim,T,G,H=l("sim"),l("openttd/terrain"),l("openttd/town_growth"),l("openttd/town_passengers")
-- Compare live authority with the recorded vanilla experiment, not a
-- reimplementation of the algorithm or an input derived from LuanTTD.
local ref=dofile("tests/fixtures/town-growth-rc1-1950.lua")
local a=ref.initial
local c=a.town
local first_tick=1354
local opening=assert(ref.stock[first_tick])
local height,kind,m1,m5,m3,m2={},{},{},{},{},{}
for _,run in ipairs(a.runs) do
  for _=1,run[1] do
    local i=#height+1
    height[i],kind[i],m1[i],m5[i],m3[i],m2[i]=unpack(run,2)
  end
end
assert(#height==64^2)
Sim.W,Sim.H=64,64
local s={version=1,seed=1751,day=0,tiles={},sites={},companies={},stations={},fleet={},next_station=1,next_vehicle=1,
 topology=0,subsidies={},news={},speed=1,stock_coastal_profile=true,
 stock_generated_profile={version=1,width=64,depth=64,map_height_limit=30,town_settings={growth_setting=a.settings[1]}}}
s.corner_grid=T.new(64,64,function(x,z)return height[(math.min(z,64)-1)*64+math.min(x,64)] end)
local x,z=c.xy%64+1,math.floor(c.xy/64)+1
local house_catalog=l("openttd/town_growth_houses")
local art=l("stock_town_art")
local opts={growing=c.flags%2==1,custom_growth=math.floor(c.flags/8)%2==1,grow_counter=c.grow_counter,
 growth_rate=c.growth_rate,time_until_rebuild=c.time_until_rebuild,fund_buildings_months=c.fund_buildings_months,
 road_build_months=c.road_build_months,layout=({[0]="original","better","grid2","grid3"})[c.layout]}
local town=G.new(1,x,z,opts)
town.house_counts={}
town.unique={church=math.floor(c.flags/2)%2==1,stadium=math.floor(c.flags/4)%2==1}
for id,v in ipairs(kind) do
  local i,x,z=id-1,Sim.xy(id)
  local typ=v
  local _,height=T.tile(s.corner_grid,x,z)
  local t={h=height,variant=(x+z)%4,terrain=height>0 and "hill" or "grass"}
  s.tiles[id]=t
  if typ==0 then
    t.stock_clear_ground=math.floor(m5[id]/4)%8
    t.stock_clear_density=m5[id]%4
    t.stock_clear_visits=math.floor(m5[id]/32)%8
  elseif typ==2 then
    t.build,t.road_bits,t.road_town="road",assert(opening.roads[i]),1
  elseif typ==3 then
    local h=opening.houses[i]
    local rec={id=h[1],x=x,z=z,town=1,root=true,root_x=x,root_z=z,completed=h[2]==1,
      stage=h[3],counter=h[4],age=h[5],age_epoch=1950}
    assert(not art[h[1]].width,"lab loader expects a single-tile opening house")
    art.stamp(rec,{id=h[1],random_bits=m1[id]},art[h[1]],0)
    t.house,t.source_house=true,rec
    town.num_houses=town.num_houses+1
    town.house_counts[h[1]]=(town.house_counts[h[1]] or 0)+1
    if rec.completed then town.population=town.population+H.specs[h[1]][1] end
  elseif typ==4 then
    local ground=math.floor(m2[id]/64)%8
    t.wood={class=4,type=m3[id],ground=ground,density=math.floor(m2[id]/16)%4,
      count=math.floor(m5[id]/64)+1,growth=m5[id]%8,water_class=ground==3 and "sea" or nil}
    if math.floor(m1[id]/32)%4~=3 then t.terrain,t.coastal_water,t.water_class="water",true,"sea" end
  elseif typ==6 then
    t.terrain="water"
    local w=math.floor(m5[id]/16)
    t.coastal_water=w==1 or w==5 or nil
    t.stock_water_rocks=w>=4 or nil
    t.water_class=({[0]="sea","canal","river","sea"})[math.floor(m1[id]/32)%4]
  elseif typ==7 then t.terrain,t.stock_void="water",true
  elseif typ==10 then t.stock_object={kind="reference-landmark"}
  else error("Unexpected tile class in the controlled reference: "..typ) end
end
town.radii=G.radii(town.num_houses)
s.sites[1]={id=1,kind="town",name="RC1 comparison",tile=c.xy+1,population=town.population,stock={},produced={},received={},service=0}
s.stock_town_growth={version=1,towns={[1]=town},order={1}}
s.passenger_rating_rng={opening.clock[4],opening.clock[5]}
s.stock_tree_tick_counter=a.settings[3]
s.stock_extra_tree_placement=a.settings[2]
s.passenger_house_clock=H.new_clock(6,6,opening.clock[3],first_tick)
Sim.mount_road_bus_market(s,l("openttd/stock_engine_calendar"),1950)
s.day=opening.clock[1]
local bind=l("campaign_simulation_bindings")(Sim,m:sub(1,-2))
bind.towns(s)
bind.flood(s)

local count=0
local function compare(sample,tick,fraction)
  local function eq(got,want,key)
    assert(got==want,("Vanilla RC1 mismatch at tick %d: %s: LuanTTD %s, stock %s")
      :format(tick,key,tostring(got),tostring(want)))
  end
  local expect=sample.clock
  local flags=(town.growing and 1 or 0)+(town.unique.church and 2 or 0)+
    (town.unique.stadium and 4 or 0)+(town.custom_growth and 8 or 0)
  eq(fraction,expect[2],"economy day fraction")
  eq(s.passenger_house_clock.counter,tick,"landscape tick")
  eq(s.passenger_house_clock.head,expect[3],"landscape cursor")
  eq(s.passenger_rating_rng[1],expect[4],"RNG word 1")
  eq(s.passenger_rating_rng[2],expect[5],"RNG word 2")
  eq(flags,expect[6],"town flags")
  eq(town.grow_counter,expect[7],"town growth countdown")
  eq(town.growth_rate,expect[8],"town growth rate")
  eq(town.time_until_rebuild,expect[9],"town rebuild countdown")
  for id,t in ipairs(s.tiles) do
    local i=id-1
    eq(t.road_bits,sample.roads[i],"road bits at "..i)
    local h,want=t.source_house,sample.houses[i]
    eq(h~=nil,want~=nil,"house present at "..i)
    if want then
      eq(h.id,want[1],"HouseID at "..i)
      eq(h.completed and 1 or 0,want[2],"house completion at "..i)
      eq(h.stage,want[3],"house stage at "..i)
      eq(h.counter,want[4],"house construction counter at "..i)
      eq(h.age or 0,want[5],"house age at "..i)
    end
    local grade=sample.grade and sample.grade[i]
    if grade then
      local x,z=Sim.xy(id)
      eq(T.corner(s.corner_grid,x,z),grade[1],"earthwork corner at "..i)
      local typ=h and 3 or t.road_bits and 2 or 0
      eq(typ,grade[2],"earthwork tile type at "..i)
      if typ==0 then
        local gt=4*(t.stock_clear_ground or 0)+(t.stock_clear_density or 3)+32*(t.stock_clear_visits or 0)
        eq(gt,grade[3],"earthwork clear ground at "..i)
      end
    end
  end
  count=count+1
end

compare(opening,first_tick,0)
local function within_day(tick)
  local ref_tick=ref.stock[tick]
  if ref_tick and ref_tick.clock[2]~=0 then
    compare(ref_tick,tick,(tick-first_tick)%74)
  end
end
for day=opening.clock[1]+1,90 do
  Sim.daily(s,nil,within_day)
  assert(s.day==day)
  local tick=s.passenger_house_clock.counter
  local day_ref=ref.stock[tick]
  if day_ref then
    assert(day_ref.clock[1]==day)
    compare(day_ref,tick,0)
  end
end
local samples=0
for _ in pairs(ref.stock) do samples=samples+1 end
assert(samples>=30 and count==samples and town.population==195)
print(("PASS %d real RC1 snapshots through April 1: exact RNG, clocks, all roads and houses; "..
  "verified terrain and dirt immediately before/after tick 4411"):format(count))
