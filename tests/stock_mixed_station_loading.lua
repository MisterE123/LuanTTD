-- Native RC1 joined country airfield + through bus station confirms
-- physical list [5 (air), 2 (road)] at tick 13553, despite its ID order.
-- Run the real two mode loaders on one queue, with distinct local IDs.
local mod="mods/luanttd_core/"
local function m(n) return dofile(mod..n..".lua") end
local P,Timing=m("openttd/passengers"),m("openttd/loading_timing")
local Loading=m("road_loading_runtime")(Timing,P)
local Compartments=m("openttd/rail_multihead_loading").create(Loading,Timing)
local function expect(air_first,air_due,passengers)
  local st={id=1,stock={passenger={{source=0,source_type="town",origin_station=1,units=passengers,age=0}},
    mail={{source=0,source_type="town",origin_station=1,units=4,age=0}}}}
  -- Mode-local front ids can collide; the station list uses physical IDs.
  local air,bus={id=1,mode="air",cargo="passenger",units=0,batches={}},
    {id=1,mode="road",cargo="passenger",units=0,batches={}}
  local chosen,attempts={},{}
  local function new_cargo(kind)
    return function(_,body)
      attempts[#attempts+1]=kind..":"..body.cargo
    end
  end
  local air_ops={consist=Compartments,new_cargo=new_cargo("air")}
  local bus_ops={slice=5,new_cargo=new_cargo("bus")}
  Compartments.aircraft(air,{cap=65,mail=8,slice=20,aging=185})
  Compartments.begin(st,air,{7100,7100},{full=true},air_ops,1)
  Loading.begin(st,bus,31,{full=true},bus_ops)
  st.loading_order=air_first and {5,2} or {2,5}
  air.load_state.ticks=air_due and 1 or 3
  bus.load_state.ticks=1
  local rows=Loading.tick(st,{[5]=air,[2]=bus},{for_vehicle=function(_,carrier,key)
    chosen[#chosen+1]=key
    return carrier==air and air_ops or bus_ops
  end})
  assert(chosen[1]==st.loading_order[1] and chosen[2]==st.loading_order[2])
  if air_due then assert(rows[1].station_vehicle==st.loading_order[1] and rows[2].station_vehicle==st.loading_order[2])
  else assert(#rows==1 and rows[1].station_vehicle==2) end
  return air,bus,attempts
end
local a,b,events=expect(true,true,12)
assert(a.carrying_parts[1].units==12 and a.carrying_parts[2].units==4 and b.units==0)
assert(events[1]=="air:passenger" and events[2]=="air:mail" and not events[3])
a,b,events=expect(true,false,12)
assert(a.carrying_parts[1].load_state.reserved_units==12 and a.carrying_parts[2].load_state.reserved_units==4)
assert(a.units==0 and b.units==0 and #events==0)
a,b,events=expect(false,true,36)
assert(b.units==5 and b.load_state.reserved_units==26 and a.carrying_parts[1].units==5 and a.carrying_parts[2].units==4)
assert(events[1]=="bus:passenger" and events[2]=="air:passenger" and events[3]=="air:mail")
-- Cargo from a road member remains at its physical origin when the
-- aircraft member tries to unload, even though the local handles differ.
local packet={origin_station=11,stock_origin_station=0}
assert(Loading.designation(packet,49153,true,{},0)==nil)
assert(Loading.designation(packet,11,true,{},5)=="deliver")
assert(Loading.designation(packet,49153,true,{force_unload=true},0)=="transfer")
print("PASS one physical road/air loading list: prior reservations, ready taps, colliding host IDs and per-mode hooks")
