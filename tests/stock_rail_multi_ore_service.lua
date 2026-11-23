-- Exercise the actual ordered industry carrier with a deterministic
-- receipt/pipeline adapter, independently of physics tick discretization.
local root="mods/luanttd_core/"
local function m(s)return dofile(root..s..".lua") end
local Sim,P,I,Rate,Roster=m("sim"),m("openttd/passengers"),m("openttd/income"),m("openttd/station_rating"),m("openttd/rail_roster")
local Timing,Loader=m("openttd/loading_timing"),m("road_loading_runtime")
local Catch=m("openttd/station_catchment")(P,Rate)
local Station=m("station_rating_runtime")(Sim,Rate,P)
local Coal=m("openttd/coal_industry")(P,Rate,Catch,I)
local Rail=m("rail_coal_service")(Sim,Coal,Catch,Roster,P,Rate,Station,I,Loader,Timing)
local rules={cargo={iron_ore={weight_16=16}},goods=function(st,cargo)
  st.goods=st.goods or {}
  st.goods[cargo]=st.goods[cargo] or Rate.new()
  return st.goods[cargo]
end}
local S=m("rail_industry_service")({wagon=assert(Roster.entry(35)),max_wagons=2,tag="ORE",single_error="FORMATION"},
  Sim,rules,Catch,Roster,Rail,P,Rate,Station,Loader,Timing)
assert(S.loading_pulse({gradual=true,loaded=10,unloaded=0,full=true},24,2)==40)
assert(S.loading_pulse({gradual=true,loaded=10,unloaded=0,full=true},24,1)==160)
assert(S.loading_pulse({gradual=true,loaded=10,unloaded=0,full=true},24,1,false)==40)
assert(S.loading_pulse({gradual=false,loaded=10,unloaded=0,full=true},24,2)==10)
assert(Roster.profile_consist({0,35,35},35,2) and Roster.profile_consist({0,35},35,2))
assert(not Roster.profile_consist({0,35,36},35,2) and not Roster.profile_consist({0,0,35},35,2) and
  not Roster.profile_consist({22,35,35},35,2) and not Roster.profile_consist({0,35,35,35},35,2) and
  not Roster.profile_consist({0,36,36},36))
local state,s=S.new(),Sim.new(1234)
Sim.W,Sim.H=64,64
local function tile(x,y)return (y-1)*64+x end
local roles={[1]="load",[2]="unload"}
s.stock_rail_stations={}
for id,x in ipairs({8,20}) do
  local tiles={tile(x,8),tile(x+1,8)}
  s.stock_rail_stations[id]={owner="Cargo",id=id,axis=0,tiles=tiles}
  for _,t in ipairs(tiles) do
    s.tiles[t]={owner="Cargo",rail_tracks=1,rail_station_id=id,rail_station_axis=0}
  end
end
local events,staged,finished={},{},{}
local received=0
local b=S.bind(s,state,{roles=roles,emit=function(e) events[#events+1]=e end,
  pipeline=function(stations)
    assert(#stations==2)
    return {report=function(id)return {accepts=id==Rail.index(2),sources={5}} end,
      stage=function(id,tick,token,packet,at)
        assert(id==Rail.index(2) and not staged[token] and packet.source==5)
        assert(at==tile(20,8) or at==tile(21,8))
        staged[token]=true;received=received+packet.units
        return {units=packet.units,distance=12,age=packet.age,payment=packet.units*3}
      end,
      finish=function(id,tick)
        assert(id==Rail.index(2) and not finished[tick]);finished[tick]=true
        return {}
      end}
  end})
local v=assert(b.vehicle({id=8,wagon=35,owner="Cargo",built=1950,speed=64,length=24,
  parts={{stock=35,index=2,body_id=40},{stock=35,index=3,body_id=42}}}))
local q=b.views[1].stock.iron_ore
q[1]={origin_station=Rail.index(1),source_type="industry",source=5,units=60,age=0}
assert(b.loading_tick(1))
local l=assert(b.arrive(1,1,1,tile(9,8),tile(9,8),{tile(9,8),tile(8,8)}))
assert(b.arrive(1,1,1,tile(9,8),tile(9,8),{tile(9,8),tile(8,8)})==l)
assert(not b.arrive(1,1,1,tile(9,8),tile(9,8),{tile(9,8),tile(9,8)}))
assert(b.after_motion(1) and #b.views[1].loading_order==1)
local loaded,clock=false,1
for t=2,270 do
  local ok,ready=b.loading_tick(t)
  assert(ok);clock=t
  if not loaded and v.units>0 then
    loaded=true
    assert(v.carrying_parts[1].units==5 and v.carrying_parts[2].units==5 and l.ticks==40)
    assert(l.reserved_units==50 and not l.ready_tick)
  end
  if ready then assert(b.leave(1,t));b.after_motion(t);break end
  assert(b.after_motion(t))
end
assert(loaded and not v.load_state and v.units==60 and #b.views[1].loading_order==0)
assert(v.carrying_parts[1].units==30 and v.carrying_parts[2].units==30)
assert(v.carrying_parts[1].batches~=v.carrying_parts[2].batches)
clock=clock+1
assert(b.loading_tick(clock))
assert(b.arrive(2,2,clock,tile(21,8),tile(21,8),{tile(21,8),tile(20,8)}))
assert(b.after_motion(clock) and #b.views[2].loading_order==1)
for t=clock+1,clock+330 do
  local ok,ready=b.loading_tick(t)
  assert(ok)
  if ready then assert(b.leave(2,t));assert(b.after_motion(t));break end
  assert(b.after_motion(t))
end
local fares,seq=0,0
for _,e in ipairs(events) do
  if e.kind=="fare" then fares=fares+1;assert(e.amount==180 and e.units==60 and e.visit==2)
  elseif e.kind=="deliver" then assert(e.body_id==40 or e.body_id==42);seq=seq+1 end
end
assert(fares==1 and seq==12 and received==60 and v.revenue==180 and v.delivered==60)
assert(Sim.company(s,"Cargo").paid_units==60 and #b.views[2].loading_order==0 and v.units==0)
print("PASS physical #35 5/5 slices, one 40-tick visit, stock 160-tick short-platform helper, 12 unique drops/one payment")
