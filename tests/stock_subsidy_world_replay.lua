local mod="mods/luanttd_core/"
local function l(m)return dofile(mod..m..".lua") end
local Sim,T,G,H=l("sim"),l("openttd/terrain"),l("openttd/town_growth"),l("openttd/town_passengers")
local art=l("stock_town_art")
local function replay(seed,expected)
local ref=dofile(("tests/fixtures/rc1-subsidies-%d.lua"):format(seed))
local a=ref.initial
local d=a.clock
Sim.W,Sim.H=a.width,a.depth
local width,depth=Sim.W,Sim.H
local s={version=1,seed=1751,day=0,tiles={},sites={},companies={},stations={},fleet={},next_station=1,next_vehicle=1,
 topology=0,subsidies={},news={},speed=1,stock_coastal_profile=true,
 stock_generated_profile={version=1,width=width,depth=depth,map_height_limit=30,town_settings={growth_setting=a.settings[1]}}}
local m={height={},kind={},m1={},m5={},m3={},m2={}}
for _,run in ipairs(ref.runs) do
 for _=1,run[1] do
  local i=#m.height+1
  m.height[i],m.kind[i],m.m1[i],m.m5[i],m.m3[i],m.m2[i]=run[2],run[3]*16,run[4],run[5],run[6],run[7]
 end
end
assert(#m.height==width*depth)
s.corner_grid=T.new(width,depth,function(x,z)return m.height[(math.min(z,depth)-1)*width+math.min(x,width)] end)
local function root(id)
 local function dim(k,dx,dz)
  local row=H.specs[k];return row and row[7]==dx and row[8]==dz
 end
 if id>=3 then
  if dim(id-1,2,1) then return id-1,-1,0 end
  if dim(id-1,1,2) or dim(id-1,2,2) then return id-1,0,-1 end
  if dim(id-2,2,2) then return id-2,-1,0 end
  if dim(id-3,2,2) then return id-3,-1,-1 end
 end
 return id,0,0
end
local towns,order={},{}
for id,c in ipairs(a.towns) do
 local x,z=c.xy%width+1,math.floor(c.xy/width)+1
 local t=G.new(id,x,z,{growing=c.flags%2==1,custom_growth=math.floor(c.flags/8)%2==1,grow_counter=c.grow_counter,
  growth_rate=c.growth_rate,time_until_rebuild=c.time_until_rebuild,fund_buildings_months=c.fund_buildings_months,
  road_build_months=c.road_build_months,layout=({[0]="original","better","grid2","grid3"})[c.layout]})
 t.house_counts,t.unique={},{church=math.floor(c.flags/2)%2==1,stadium=math.floor(c.flags/4)%2==1}
 towns[id]=t;order[id]=id
 s.sites[id]={id=id,kind="town",name="RC1 comparison "..id,tile=c.xy+1,population=0,stock={},produced={},received={},service=0}
end
for id,v in ipairs(m.kind) do
 local i,x,z=id-1,Sim.xy(id)
 local typ=math.floor(v/16)
 local _,height=T.tile(s.corner_grid,x,z)
 local t={h=height,variant=(x+z)%4,terrain=height>0 and "hill" or "grass"}
 s.tiles[id]=t
 if typ==0 then
  t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=math.floor(m.m5[id]/4)%8,m.m5[id]%4,math.floor(m.m5[id]/32)%8
 elseif typ==2 then
  local r=a.roads[i];t.build,t.road_bits,t.road_town="road",r[1],r[2]
 elseif typ==3 then
  local h=a.houses[i]
  local hroot,dx,dz=root(h[1])
  local r={id=h[1],x=x,z=z,town=h[6],root=h[1]==hroot,root_x=x+dx,root_z=z+dz,completed=h[2]==1,
    stage=h[3],counter=h[4],age=h[5],age_epoch=1950}
  if not r.root then
   local q=assert(a.houses[Sim.id(r.root_x,r.root_z)-1])
   assert(q[1]==hroot and q[6]==h[6])
  end
  art.stamp(r,{id=hroot,random_bits=m.m1[id]},assert(art[hroot]),-2*dx-dz)
  t.house,t.source_house=true,r
  local town=assert(towns[r.town])
  if r.root then town.num_houses=town.num_houses+1 end
  town.house_counts[r.id]=(town.house_counts[r.id] or 0)+1
  if r.completed then town.population=town.population+H.specs[r.id][1] end
 elseif typ==4 then
  local ground=math.floor(m.m2[id]/64)%8
  t.wood={class=4,type=m.m3[id],ground=ground,density=math.floor(m.m2[id]/16)%4,
   count=math.floor(m.m5[id]/64)+1,growth=m.m5[id]%8,water_class=ground==3 and "sea" or nil}
  if math.floor(m.m1[id]/32)%4~=3 then t.terrain,t.coastal_water,t.water_class="water",true,"sea" end
 elseif typ==6 then
  t.terrain="water"
  local w=math.floor(m.m5[id]/16)
  t.coastal_water=w==1 or w==5 or nil
  t.stock_water_rocks=w>=4 or nil
  t.water_class=({[0]="sea","canal","river","sea"})[math.floor(m.m1[id]/32)%4]
 elseif typ==7 then t.terrain,t.stock_void="water",true
 elseif typ==10 then t.stock_object={kind="reference-landmark"}
 else error("Unexpected map class "..typ) end
end
for id,t in ipairs(towns) do t.radii=G.radii(t.num_houses);s.sites[id].population=t.population end
s.stock_town_growth={version=1,towns=towns,order=order}
s.passenger_rating_rng={d[5],d[6]}
s.stock_tree_tick_counter=d[7]
s.stock_extra_tree_placement=a.settings[2]
s.passenger_house_clock=H.new_clock(width==128 and 7 or 6,depth==128 and 7 or 6,d[4],d[3])
Sim.mount_road_bus_market(s,l("openttd/stock_engine_calendar"),1950)
s.day=d[1]
local bind=l("campaign_simulation_bindings")(Sim,mod:sub(1,-2))
local growth=bind.towns(s)
bind.flood(s)
local offered=assert(Sim.mount_stock_subsidies(s)).subsidies
assert(next(a.subsidies)==nil and s.stock_economy_subsidies.duration==a.duration)
local function compare(day,b)
 local actual=s.passenger_rating_rng
 assert(actual[1]==b.clock[5] and actual[2]==b.clock[6],"Stock RNG differed on day "..day)
 local expected=0
 for id,want in pairs(b.subsidies) do
  expected=expected+1
  local e=assert(offered.rows[id],"Missing stock subsidy "..id)
  assert(e.cargo==want.cargo_type and e.src.id==want.src and e.dst.id==want.dst and e.remaining==want.remaining)
 end
 assert(offered.count==expected)
 for id,t in ipairs(towns) do
  local want=b.towns[id]
  assert(t.grow_counter==want.grow_counter and t.growth_rate==want.growth_rate and t.time_until_rebuild==want.time_until_rebuild)
 end
 for id,t in ipairs(s.tiles) do
  local r,h=b.roads[id-1],b.houses[id-1]
  local w=t.source_house
  assert(t.road_bits==(r and r[1]) and t.road_town==(r and r[2]),"Road difference at "..id)
  assert((w~=nil)==(h~=nil) and (not w or (w.id==h[1] and w.town==h[6] and
      (w.completed and 1 or 0)==h[2] and w.stage==h[3] and w.counter==h[4] and (w.age or 0)==h[5])),
      "House difference at "..id)
 end
 print("PASS mounted stock subsidy and active town state",day,expected)

end
compare(1,a)
for day=2,90 do Sim.daily(s);if ref.checks[day] then compare(day,ref.checks[day]) end end
assert(offered.count==expected)
end
replay(11,2)
replay(57,2)
