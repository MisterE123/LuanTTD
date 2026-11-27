-- Replay numeric snapshots from the official RC1 engine through the
-- live simulation. These controlled maps have no industry or operators
-- running vehicles and deliberately keep stock subsidies disabled.
local m="mods/luanttd_core/"
local function load_module(name) return dofile(m..name..".lua") end
local Sim,T,G,H=load_module("sim"),load_module("openttd/terrain"),load_module("openttd/town_growth"),load_module("openttd/town_passengers")
local Art=load_module("stock_town_art")
local calendar=load_module("openttd/stock_engine_calendar")
local bind=load_module("campaign_simulation_bindings")(Sim,m:sub(1,-2))
local Codec=load_module("packed_campaign")
local first_tick=1354

-- GetHouseNorthPart, town_cmd.cpp. Offsets follow the stock 1x2 and
-- four-tile record order, not the Luanti artwork's part indices.
local function root_of(id)
  local function is_layout(candidate,w,d)
    local spec=H.specs[candidate]
    return spec and spec[7]==w and spec[8]==d
  end
  if id>=3 then
    if is_layout(id-1,2,1) then return id-1,-1,0 end
    if is_layout(id-1,1,2) or is_layout(id-1,2,2) then return id-1,0,-1 end
    if is_layout(id-2,2,2) then return id-2,-1,0 end
    if is_layout(id-3,2,2) then return id-3,-1,-1 end
  end
  return id,0,0
end

local function initialize(ref)
  local a,opening=ref.initial,assert(ref.stock[first_tick])
  local height,kind,m1,m5,m3,m2={},{},{},{},{},{}
  for _,run in ipairs(a.runs) do
    for _=1,run[1] do
      local i=#height+1
      height[i],kind[i],m1[i],m5[i],m3[i],m2[i]=unpack(run,2)
    end
  end
  assert(#height==64^2)
  local s={version=1,seed=1751,day=0,tiles={},sites={},companies={},stations={},fleet={},next_station=1,next_vehicle=1,
    topology=0,subsidies={},news={},speed=1,stock_coastal_profile=true,
    stock_generated_profile={version=1,width=64,depth=64,map_height_limit=30,town_settings={growth_setting=a.settings[1]}}}
  Sim.W,Sim.H=64,64
  s.corner_grid=T.new(64,64,function(x,z)return height[(math.min(z,64)-1)*64+math.min(x,64)] end)
  local towns,order={},{}
  for id,c in ipairs(a.towns) do
    local x,z=c.xy%64+1,math.floor(c.xy/64)+1
    local town=G.new(id,x,z,{growing=c.flags%2==1,custom_growth=math.floor(c.flags/8)%2==1,
      grow_counter=c.grow_counter,growth_rate=c.growth_rate,time_until_rebuild=c.time_until_rebuild,
      fund_buildings_months=c.fund_buildings_months,road_build_months=c.road_build_months,
      layout=({[0]="original","better","grid2","grid3"})[c.layout]})
    town.house_counts={}
    for cargo,name in pairs({[0]="passenger",[2]="mail"}) do
      local raw=opening.supply[id][cargo]
      if raw then
        town.supplied[name]={new_max=raw[1],new_act=raw[2],old_max=raw[3],old_act=raw[4]}
      end
    end
    town.unique={church=math.floor(c.flags/2)%2==1,stadium=math.floor(c.flags/4)%2==1}
    towns[id],order[id]=town,id
    s.sites[id]={id=id,kind="town",name="RC1 comparison "..id,tile=c.xy+1,population=0,
      stock={},produced={},received={},service=0}
  end
  for id,typ in ipairs(kind) do
    local i,x,z=id-1,Sim.xy(id)
    local _,base=T.tile(s.corner_grid,x,z)
    local t={h=base,variant=(x+z)%4,terrain=base>0 and "hill" or "grass"}
    s.tiles[id]=t
    if typ==0 then
      t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=math.floor(m5[id]/4)%8,m5[id]%4,math.floor(m5[id]/32)%8
    elseif typ==2 then
      local road=opening.roads[i]
      t.build,t.road_bits,t.road_town="road",road[1],road[2]+1
    elseif typ==3 then
      local h=opening.houses[i]
      local root,dx,dz=root_of(h[1])
      local r={id=h[1],x=x,z=z,town=h[6]+1,root=h[1]==root,root_x=x+dx,root_z=z+dz,completed=h[2]==1,
        stage=h[3],counter=h[4],age=h[5],age_epoch=1950}
      if not r.root then
        local primary=assert(opening.houses[Sim.id(r.root_x,r.root_z)-1])
        assert(primary[1]==root and primary[6]==h[6])
      end
      Art.stamp(r,{id=root,random_bits=m1[id]},assert(Art[root]),-2*dx-dz)
      t.house,t.source_house=true,r
      local town=assert(towns[r.town])
      if r.root then town.num_houses=town.num_houses+1 end
      town.house_counts[r.id]=(town.house_counts[r.id] or 0)+1
      if r.completed then town.population=town.population+H.specs[r.id][1] end
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
  for id,town in ipairs(towns) do
    town.radii=G.radii(town.num_houses)
    s.sites[id].population=town.population
  end
  s.stock_town_growth={version=1,towns=towns,order=order}
  s.passenger_rating_rng={opening.clock[4],opening.clock[5]}
  s.stock_tree_tick_counter,s.stock_extra_tree_placement=a.settings[3],a.settings[2]
  s.passenger_house_clock=H.new_clock(6,6,opening.clock[3],first_tick)
  Sim.mount_road_bus_market(s,calendar,1950)
  s.day=opening.clock[1]
  bind.towns(s)
  bind.flood(s)
  return s,towns
end

local function replay(file,expected,expected_days,reopen_day)
  local ref=dofile("tests/fixtures/"..file..".lua")
  local s,towns=initialize(ref)
  local count=0
  local function compare(sample,tick,fraction)
    local function eq(got,want,key)
      assert(got==want,("%s at tick %d: %s: LuanTTD %s, stock %s")
        :format(file,tick,key,tostring(got),tostring(want)))
    end
    local c=sample.clock
    eq(fraction,c[2],"economy day fraction")
    eq(s.passenger_house_clock.counter,tick,"landscape tick")
    eq(s.passenger_house_clock.head,c[3],"landscape cursor")
    eq(s.passenger_rating_rng[1],c[4],"RNG word 1");eq(s.passenger_rating_rng[2],c[5],"RNG word 2")
    for id,town in ipairs(towns) do
      local e=sample.towns[id]
      local flags=(town.growing and 1 or 0)+(town.unique.church and 2 or 0)+
        (town.unique.stadium and 4 or 0)+(town.custom_growth and 8 or 0)
      eq(flags,e[1],"town flags: "..id)
      eq(town.grow_counter,e[2],"growth countdown: "..id)
      eq(town.growth_rate,e[3],"growth rate: "..id)
      eq(town.time_until_rebuild,e[4],"rebuild countdown: "..id)
      if sample.funding then
        eq(town.fund_buildings_months or 0,sample.funding[id],"paid funding countdown: "..id)
      end
      for cargo,name in pairs({[0]="passenger",[2]="mail"}) do
        local got=town.supplied[name] or {}
        local want=sample.supply[id][cargo] or {0,0,0,0}
        eq(got.new_max or 0,want[1],"current town production: "..id.."/"..name)
        eq(got.new_act or 0,want[2],"current moved town cargo: "..id.."/"..name)
        eq(got.old_max or 0,want[3],"last month town production: "..id.."/"..name)
        eq(got.old_act or 0,want[4],"last month moved town cargo: "..id.."/"..name)
      end
    end
    for id,t in ipairs(s.tiles) do
      local i=id-1
      local r=sample.roads[i]
      eq(t.road_bits,r and r[1],"road bits at "..i)
      eq(t.road_town,r and (r[2]+1),"road TownID at "..i)
      local h,want=t.source_house,sample.houses[i]
      eq(h~=nil,want~=nil,"house present at "..i)
      if want then
        eq(h.id,want[1],"HouseID at "..i)
        eq(h.completed and 1 or 0,want[2],"house completion at "..i)
        eq(h.stage,want[3],"house stage at "..i)
        eq(h.counter,want[4],"house construction counter at "..i)
        eq(h.age or 0,want[5],"house age at "..i)
        eq(h.town,want[6]+1,"house TownID at "..i)
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

  compare(ref.stock[first_tick],first_tick,0)
  local function within_day(tick)
    local sample=ref.stock[tick]
    if sample and sample.clock[2]~=0 then compare(sample,tick,(tick-first_tick)%74) end
  end
  for day=s.day+1,expected_days do
    Sim.daily(s,nil,within_day)
    assert(s.day==day)
    local tick=s.passenger_house_clock.counter
    local sample=ref.stock[tick]
    if sample then assert(sample.clock[1]==day);compare(sample,tick,0) end
    if day==reopen_day then
      assert(sample,"Reopen only after a verified stock checkpoint")
      s=Codec.decode(Codec.encode(s))
      towns=s.stock_town_growth.towns
      bind.towns(s)
      bind.flood(s)
    end
  end
  local samples=0
  for _ in pairs(ref.stock) do samples=samples+1 end
  assert(count==samples and count==expected)
  print(("PASS %d real RC1 snapshots (%s): exact RNG, owners, construction clocks and town cargo totals"):format(count,file))
  return s,towns
end

replay("town-growth-rc1-pair-natural",5,59)
replay("town-growth-rc1-pair-active",3,59)
local funded,ft=replay("town-growth-rc1-one-funded",4,90,31)
assert(ft[1].fund_buildings_months==0 and funded.sites[1].population==168)
local s,towns=replay("town-growth-rc1-1950",37,151)
-- Stock month rollover uses the last tick in the batch, not its
-- first. Create a funding expiry at the next boundary and observe the
-- real tick callbacks before and after that saved town action expires.
local town=towns[1]
assert(town.population==238)
for _=152,180 do Sim.daily(s) end
s.stock_generated_profile.town_settings.growth_setting=0
town.fund_buildings_months,town.custom_growth,town.growing,town.grow_counter=1,false,true,1000
town.time_until_rebuild=65535
local previous_rate=town.growth_rate
local before=s.passenger_house_clock.counter
local old_month=s.stock_town_growth.last_month
local seen=0
local goods_entry=load_module("openttd/station_rating").new()
goods_entry.ever_accepted,goods_entry.current_month=true,true
-- A road/combined facade may refer to the same shared GoodsEntry in two
-- views. The Station timer rotates that actual entry once. The fixture
-- adds no service or transport course to the stock route replay above.
local station={id=999,tile=1,mode="road",stock={},last_service={},goods={passenger=goods_entry},
  passenger_rating_state=goods_entry}
s.stations[station.id]=station
Sim.daily(s,nil,function(tick)
  seen=seen+1
  if tick<before+74 then
    assert(s.stock_town_growth.last_month==old_month and town.fund_buildings_months==1 and town.growing,
      "Funding expired before the economy date changed")
    assert(town.grow_counter==1000-(tick-before),"Pre-rollover growth countdown did not run")
    assert(goods_entry.current_month and not goods_entry.last_month)
  else
    assert(tick==before+74 and s.stock_town_growth.last_month==old_month+1)
    assert(town.fund_buildings_months==0 and not town.growing,"Month failed to expire funding on its boundary tick")
    assert(not goods_entry.current_month and goods_entry.last_month and goods_entry.ever_accepted)
  end
end)
assert(seen==74 and town.grow_counter==G.adjust_counter(1000-73,town.growth_rate,previous_rate))
for _=1,31 do
  if s.stock_town_growth.last_month~=old_month+1 then break end
  Sim.daily(s)
end
assert(s.stock_town_growth.last_month==old_month+2 and not goods_entry.last_month and goods_entry.ever_accepted,
  "After a month with no new deliveries the previous acceptance must expire")
print("PASS ordinary expiry preserves the first 73 growth ticks, then runs before the stock month-boundary tick")
