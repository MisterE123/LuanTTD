-- SPDX-License-Identifier: GPL-2.0-only
-- Real depot road motion and a native-positioned Balogh coal route.
local root="mods/luanttd_core/"
local function mod(p) return dofile(root..p..".lua") end
local Sim=mod("sim")
local Terrain=mod("openttd/terrain")
local P=mod("openttd/passengers")
local Income=mod("openttd/income")
local Rating=mod("openttd/station_rating")
local Catchment=mod("openttd/station_catchment")(P,Rating)
local Coal=mod("openttd/coal_industry")(P,Rating,Catchment,Income)
local World=mod("coal_industry_world")(Sim,Terrain,Coal)
local function copy(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
local s=Sim.new(1751)
local model=arg and arg[1] or "coal_tipper"
local dates={coal_uhl={1985,124,25,176},coal_dw={2025,125,28,224}}
local spec=dates[model]
local function market(w)
  if spec then Sim.mount_road_bus_market(w,mod("openttd/stock_engine_calendar"),spec[1],true,true,{[model]=true}) end
end
market(s)
mod("town_layout")(Sim,s)
s.corner_grid=mod("terrain_preview")(Sim,Terrain,s)
s.road_economy=true;s.road_stock_clock=true;s.road_stock_house_supply=true
s.road_stock_loading=true
local cap=Sim.vehicles[model]
if spec then assert(cap.capacity==spec[3] and cap.speed==spec[4] and cap.stock_engine_id==spec[2])
else assert(cap.capacity==20 and cap.speed==96 and cap.stock_engine_id==123 and cap.cost==5906) end
assert(Sim.allowed("coal_tipper","coal") and not Sim.allowed("coal_tipper","mail"))
s.road_coal=true
assert(Sim.road_coal_active(s))
local function id(x,z) return Sim.id(x,z) end
local industrial,msg=World.seed(s,id(30,11),id(40,12));assert(industrial,msg)
local first,last,depot=id(31,14),id(41,14),id(32,15)
local footprint=id(31,11)
assert(s.tiles[footprint].stock_industry and not s.tiles[footprint].site)
assert(not Sim.build(s,"Miner","road",{footprint}))
assert(not Sim.build(s,"Miner","road_station",{footprint}))
assert(not Sim.build(s,"Miner","clear",{footprint}))
assert(not Sim.landscape(s,"Miner","raise",31,11))
assert(Sim.build(s,"Miner","road",Sim.line(first,last)))
assert(Sim.build_truck_stop(s,"Miner",first))
assert(Sim.build_truck_stop(s,"Miner",last))
assert(Sim.build(s,"Miner","road_depot",{depot}))
local first_stop,last_stop=s.tiles[first].station,s.tiles[last].station
assert(not Sim.purchase(s,"Miner",model,"coal",first_stop))
assert(not Sim.purchase(s,"Miner",model,"mail",nil,depot))
local c=Sim.company(s,"Miner")
local before=c.cash
s.road_coal=false
assert(not Sim.vehicle_available(s,model) and not Sim.purchase(s,"Miner",model,"coal",nil,depot))
assert(c.cash==before)
s.road_coal=true
local truck=assert(Sim.purchase(s,"Miner",model,"coal",nil,depot))
assert(c.cash==before-cap.cost)
assert(Sim.add_order(s,"Miner",truck,first_stop,"full"))
assert(Sim.add_order(s,"Miner",truck,last_stop))
assert(Sim.toggle(s,"Miner",truck))
local source,plant=industrial.mine,industrial.power
local fuel=s.stock_coal_industries[plant]
local source_site,sink_site=s.stock_coal_industries[source].site,fuel.site
assert(s.sites[source_site].kind=="stock_coal_mine" and s.sites[sink_site].kind=="stock_power_station")
local wait,accept,rating,report=Sim.coal_stop_status(s,s.stations[first_stop])
assert(wait==0 and not accept and rating==175 and report.sources[1]==source)
wait,accept=Sim.coal_stop_status(s,s.stations[last_stop]);assert(wait==0 and accept)
local fare,paid,boarded,events=0,0,0,0
local started,loaded_save,paid_save,first_board,first_delivery,bay_timing
local initial_cash=c.cash
local initial_expense=c.expense
local function monitor()
  local v=s.fleet[truck]
  local tick=s.stock_load_tick
  assert(tick==s.day*74 and tick==s.passenger_house_clock.counter)
  assert(Sim.has_stock_road_service(s,v) and v.stock_aged_tick==tick)
  assert(s.stations[first_stop].stock.coal==nil and s.stations[last_stop].stock.coal==nil,
    "Stock coal must not leak into old site/feeder queues")
  for _,rec in ipairs(Sim.road_loading_events(s)) do
    if rec.vehicle==truck then
      assert(rec.cargo=="coal" and rec.owner=="Miner")
      if rec.kind=="board" then
        assert(rec.data.tile==first and rec.data.units>0 and rec.data.tick<=tick)
        boarded=boarded+rec.data.units;first_board=first_board or rec.data.tick
      elseif rec.kind=="fare" then
        assert(rec.data.tile==last and rec.data.units>0 and rec.data.amount>0)
        fare,paid,events=fare+rec.data.amount,paid+rec.data.units,events+1
      end
    end
  end
  assert(#Sim.road_loading_events(s)==0)
  assert(v.delivered==paid and v.revenue==fare)
  assert(s.sites[source_site].stock.coal==nil and s.sites[sink_site].stock.coal==nil)
  local company=Sim.company(s,"Miner")
  assert(company.cash==initial_cash+fare-(company.expense-initial_expense))
  assert(company.paid_units==paid and company.revenue==fare)
  if v.load_state then
    assert(v.load_state.slice==5)
    local st=s.stations[v.load_state.station]
    assert(Sim.position(s,v)==st.tile)
    local w,accepted,_,report=Sim.coal_stop_status(s,st)
    assert(w and report and (st.id==last_stop)==accepted)
    if v.load_state.station==first_stop and v.units>0 then bay_timing=true end
  end
  return v
end
for _=1,240 do
  Sim.daily(s)
  local v=monitor()
  if v.last_road_arrival_tick then started=started or v.last_road_arrival_tick end
  if not loaded_save and v.route and v.units==cap.capacity then
    assert(v.dest==last_stop and v.road_speed_state and #v.road_motion_frames>0)
    loaded_save={units=v.units,tick=v.road_speed_state.ticks}
    for _,p in ipairs(v.batches) do assert(p.source==source and p.source_type=="industry" and p.origin_tile==first) end
    s=copy(s)
    market(s)
    assert(s.fleet[truck].road_speed_state.ticks==loaded_save.tick and #Sim.road_loading_events(s)==0)
  end
  if not first_delivery and s.sites[sink_site].received.coal then first_delivery=s.day end
  if not paid_save and fare>0 then
    paid_save={fare=fare,paid=paid}
    s=copy(s)
    market(s)
    assert(s.fleet[truck].revenue==paid_save.fare and #Sim.road_loading_events(s)==0)
  end
  if loaded_save and paid_save and events>=2 then break end
end
assert(started and first_board and first_board>started and first_delivery and bay_timing and loaded_save and paid_save)
assert(fare>paid_save.fare and paid>=2*cap.capacity and boarded>=paid and s.sites[sink_site].received.coal==paid)
assert(s.stock_coal_industries[plant].was_cargo_delivered)
local vt=s.fleet[truck]
local before_motion,before_fare=vt.progress,fare
s.road_coal=false
Sim.daily(s)
assert(not Sim.has_stock_road_service(s,vt) and vt.progress==before_motion and vt.revenue==before_fare)
assert(not Sim.coal_stop_status(s,s.stations[first_stop]))
s.road_coal=true
Sim.daily(s)
monitor()
assert(vt.running and not vt.stock_coal_resume and vt.stock_aged_tick==s.stock_load_tick)
print(("PASS: real coal tipper road route, %d paid tons / $%d, first board %d, actual power plant and two save/reloads")
  :format(paid,fare,first_board))
