-- Two owned buses competing for both real drive-through stops in one town.
local F=dofile("tests/lib/stock_active_bus_fixture.lua")
local ref=dofile("tests/fixtures/rc1-shared-bus-stops-town.lua")
local Sim=F.Sim
local Terrain=dofile("mods/luanttd_core/openttd/terrain.lua")
local Rebuild=dofile("mods/luanttd_core/openttd/town_rebuild.lua")
local s,_,_,owner=F.open(ref.start,true)
local first=ref.start.clock[1]
local checked,traced=0,0
local hashes={1,1,1}
local heights={}
for _,run in ipairs(ref.start.runs) do
  for _=1,run[1] do heights[#heights+1]=run[2] end
end
local function eq(label,value,expected)
  assert(value==expected,("%s: LuanTTD %s, RC1 %s"):format(label,tostring(value),tostring(expected)))
end
local function hash(id,...)
  local h=hashes[id]
  for i=1,select("#",...) do h=(h*65599+(select(i,...)))%2147483647 end
  hashes[id]=h
end
local function observe(tick)
  traced=traced+1
  hash(1,tick,unpack(s.passenger_rating_rng))
  for id=1,2 do
    local v=s.fleet[id]
    local frame=assert(Sim.road_motion_frame(s,v),"source keeps both buses visible for this window")
    local moving=v.road_speed_state
    local c=moving or assert(v.road_stop_motion)
    local actual={frame[4]-1,frame[1]-16,frame[2]-16,Sim.stock_road_frame_z(s,frame),frame[3],
      c.progress,moving and c.speed or 0,c.subspeed}
    hash(2,tick,id-1,unpack(actual))
    if ref.motion[tick] and id==(tick==3968 and 1 or 2) then
      for i,n in ipairs(ref.motion[tick]) do eq("source queued bus/municipal road frame "..tick.."/"..i,actual[i],n) end
      if tick==3047 then
        eq("loading began at frame 3",frame[15],3)
        eq("at actual station",v.load_state.station,2)
      elseif tick==3048 then
        eq("depart without waiting an extra loading round",v.load_state,nil)
        eq("departure from the same lane pixel",frame[15],3)
      elseif tick==3968 then
        eq("municipal tile 2192 retained both road connections",s.tiles[2193].road_bits,9)
      end
    end
    local st=s.stations[id]
    local waiting=0
    for _,p in ipairs((st.stock or {}).passenger or {}) do waiting=waiting+p.units end
    hash(3,tick,id-1,waiting,st.passenger_fraction or 0)
  end
  local expected=ref.digest[tick]
  if expected then
    for i,n in ipairs(expected) do eq("branch digest "..i.." through "..tick,hashes[i],n) end
  end
end
local function compare(tick)
  local a=ref.checks[tick]
  if not a then return end
  local t=s.stock_town_growth.towns[1]
  local c=s.companies[owner]
  eq("actual date",s.day,a.day)
  eq("growth counter",t.grow_counter,a.town[1]);eq("growth rate",t.growth_rate,a.town[2])
  eq("rebuilding countdown",t.time_until_rebuild,a.town[3])
  eq("authority rating",c.stock_town_authority_ratings and c.stock_town_authority_ratings[1] or 500,a.rating)
  eq("first RNG",s.passenger_rating_rng[1],a.rng[1]);eq("second RNG",s.passenger_rating_rng[2],a.rng[2])
  eq("balance",c.cash,a.cash);eq("fraction",c.stock_money_fraction,a.loans[2]);eq("loan",c.loan,a.loans[1])
  local paid=c.paid_units
  for i=1,2 do
    local st,v=s.stations[i],s.fleet[i]
    local q=a.service[i]
    eq("station load age",st.time_since_load,q[1]);eq("station unload age",st.time_since_unload,q[2])
    eq("station rating",st.passenger_rating_state.rating,q[3])
    for j,key in ipairs({"reliability","breakdown_chance","breakdown_ctr","age","date_of_last_service","date_of_last_service_newgrf"}) do
      eq("bus "..i.." "..key,v.road_fault[key],ref.vehicle_health[tick][i][j])
    end
    paid=paid+(v.load_state and v.load_state.payment and v.load_state.payment.delivered or 0)
  end
  eq("passenger deliveries",paid,a.lifetime)
  for i,q in ipairs(a.quarters) do
    local hist=i==1 and c.stock_quarter or c.stock_quarters and c.stock_quarters[i-1]
    hist=hist or {income=0,expenses=0,delivered={}}
    eq("quarter income",hist.income,q[1]);eq("quarter expenses",hist.expenses,q[2])
    eq("quarter passengers",hist.delivered.passenger or 0,q[3])
  end
  for stock,name in pairs({[0]="passenger",[2]="mail"}) do
    for i,key in ipairs({"new_max","new_act","old_max","old_act"}) do
      eq(name.." "..key,t.supplied[name][key],a.supply[stock][i])
    end
  end
  local year=Sim.date(s)
  for id,tile in ipairs(s.tiles) do
    local x,z=Sim.xy(id)
    eq("height "..id,Terrain.corner(s.corner_grid,x,z),a.grade_changes[id-1] or heights[id])
    local h,w=tile.source_house,a.houses[id-1]
    eq("house present "..id,h~=nil,w~=nil)
    if w then
      eq("house spec",h.id,w[1]);eq("house town",h.town,w[2]+1)
      eq("house complete",h.completed,w[3]==1);eq("house stage",h.stage,w[4])
      eq("house counter",h.counter,w[5]);eq("house age",Rebuild.age(h,year),w[6])
      eq("house animation bits",h.random_bits,w[7])
    end
    local q=a.roads[id-1]
    if q or tile.build=="road" then
      eq("road bits "..id,tile.road_bits,q and q[1])
      eq("road town "..id,tile.road_town,q and q[2]+1)
      eq("road owner "..id,tile.owner,q and q[3]==0 and owner or nil)
    end
  end
  checked=checked+1
  print(("Matched two-bus RC1 day %d: %d passengers delivered"):format(a.day,paid))
end
compare(first)
for day=3,151 do
  if day==32 or day==91 then s=F.reopen(s,true,ref.start.service_options) end
  Sim.daily(s,nil,observe)
  compare(s.passenger_house_clock.counter)
end
assert(checked==6 and traced==11026 and s.tiles[2193].road_bits==9)
print("PASS two buses sharing stock drive-through stops: 11,026 ticks, six town/company snapshots, two packed reopens")
