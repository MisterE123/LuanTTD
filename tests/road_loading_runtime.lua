local base="mods/bayline/"
local P=dofile(base.."openttd/passengers.lua")
local Timing=dofile(base.."openttd/loading_timing.lua")
local L=dofile(base.."road_loading_runtime.lua")(Timing,P)
local function same(a,b)
  assert(a==b,("%s != %s"):format(tostring(a),tostring(b)))
end
local function packet(n,origin,source)
  return {units=n,origin_station=origin or 1,source=source or 11,age=0}
end
local function fixture(list,cargo)
  local st={id=2,tile=200,stock={}}
  local v={id=3,cargo=cargo or "passenger",batches={}}
  st.stock[v.cargo]=list or {}
  return st,v,{[v.id]=v}
end
local function run(st,fleet,ops,limit)
  local events,leave,tick={},nil,0
  for t=1,limit do
    local rounds,depart=L.tick(st,fleet,ops)
    for _,ev in ipairs(rounds) do
      ev.tick=t
      events[#events+1]=ev
    end
    if #depart>0 then leave=depart;tick=t;break end
  end
  return events,tick,leave
end

-- Stock gradually picks up eight per pulse; partial final unload pulse is
-- not allowed to board a new arrival until the next 20-tick pulse.
local st,v,fleet=fixture({packet(19)})
local loaded={}
local ops={accepts=function() return true end,
  xy=function(tile) return tile/10,7 end,
  loaded=function(_,_,n) loaded[#loaded+1]=n end}
L.begin(st,v,31,{},ops)
local events,time,depart=run(st,fleet,ops,120)
same(time,61);same(depart[1],v.id)
same(#events,4);same(events[1].tick,1);same(events[2].tick,21);same(events[3].tick,41)
same(loaded[1],8);same(loaded[2],8);same(loaded[3],3);same(#loaded,3)
same(v.units,19);same(#v.batches,1);same(v.batches[1].travel_x,20)
L.leave(st,v,ops)
same(v.load_state,nil);same(#st.loading_order,0)

-- Forced unload still delivers eligible other-origin riders for money.
-- Same-origin riders transfer first, in the exact reverse Stage order,
-- with the feeder share kept proportional if transfer spans two slices.
st,v,fleet=fixture({packet(8,4,47)})
v.batches={packet(5,2,10),packet(6,1,11),packet(4,2,12)}
local delivered,unloaded,paid,transfers={},0,nil,{}
ops={
  accepts=function() return true end,
  deliver=function(_,_,p) delivered[#delivered+1]=p.source;return 57 end,
  transferred=function(_,_,p) transfers[#transfers+1]={p.source,p.units,p.feeder_share} end,
  transfer_income=function(_,_,p) return p.units*2 end,
  payment=function(_,_,p) paid=p end,
  unloaded=function(_,_,n) unloaded=unloaded+n end,
}
L.begin(st,v,31,{force_unload=true},ops)
events,time,depart=run(st,fleet,ops,120)
same(events[1].unloaded,8);same(events[1].delivered,0)
same(events[2].unloaded,7);same(events[2].delivered,6)
same(events[3].loaded,8);same(events[3].tick,41)
same(#delivered,1);same(delivered[1],11)
same(transfers[1][1],12);same(transfers[1][2],4);same(transfers[1][3],6)
same(transfers[2][1],10);same(transfers[2][2],4);same(transfers[2][3],5)
same(transfers[3][1],10);same(transfers[3][2],1);same(transfers[3][3],2)
same(paid.route,57);same(paid.transfer,13);same(paid.visual,57)
same(unloaded,15);same(time,101) -- 1, 21, 41, 61, 81, 101: transfers can reload under stock flags
L.leave(st,v,ops)

-- Full-load is indefinite. The amount reserved belongs to that vehicle
-- and is excluded from the actual stop queue; empty pulses review every 20.
st,v,fleet=fixture({}, "mail")
local tries,refreshed=0,0
ops={attempt=function() tries=tries+1 end,refresh_link=function() refreshed=refreshed+1 end}
L.begin(st,v,22,{full=true},ops)
events,time=run(st,fleet,ops,1020)
same(time,0);same(tries,51);same(refreshed,51)
st.stock.mail[1]=packet(40)
local _,no_leave=L.tick(st,fleet,ops) -- due tick 1021
same(#no_leave,0);same(#st.stock.mail,1);same(st.stock.mail[1].units,18)
same(v.load_state.reserved_units,14);same(v.units,8)
L.age_vehicle(v,1)
same(v.batches[1].age,1);same(v.load_state.reserved[1].age,1)
events,time=run(st,fleet,ops,70)
same(time,60);same(v.units,22);same(v.load_state.reserved_units,0)
L.leave(st,v,ops)
same(st.stock.mail[1].units,18)

-- A no-load order never grants loading eligibility. Timetable departure
-- compares elapsed road-controller ticks to the threshold, not fare time.
st,v,fleet=fixture({packet(10)})
tries=0
ops={attempt=function() tries=tries+1 end}
L.begin(st,v,31,{no_load=true,wait=61,lateness=20},ops)
events,time=run(st,fleet,ops,100)
same(time,41);same(tries,0);same(#events,3);same(v.units,0)
L.leave(st,v,ops)

-- No reservations in idle ticks unless some vehicle actually has a round.
-- Earlier full-load vehicle reserves before later normal vehicle loads.
st,v,fleet=fixture({packet(12)})
local w={id=4,cargo="passenger",batches={}};fleet[w.id]=w
L.begin(st,v,22,{full=true},{})
L.begin(st,w,22,{}, {})
v.load_state.ticks=5
events,depart=L.tick(st,fleet,{})
same(v.load_state.reserved_units,12);same(w.units,0);same(#depart,1);same(depart[1],w.id)
L.leave(st,w,{})
st.stock.passenger[1]=packet(3)
L.tick(st,fleet,{})
same(st.stock.passenger[1].units,3)
L.leave(st,v,{})
same(st.stock.passenger[1].units,15)

-- A disappearing acceptance converts the staged deliveries back to KEEP
-- and returns the now excess reservation before retrying the stop.
st,v,fleet=fixture({packet(30)})
v.batches={packet(20,1),packet(2,2)}
local accept=true
ops={accepts=function() return accept end}
L.begin(st,v,22,{full=true},ops)
accept=false
events,time=run(st,fleet,ops,30)
same(events[1].unloaded,0);same(v.load_state.reserved_units,0)
same(st.stock.passenger[1].units,30)
same(time,21);same(v.units,22);same(v.batches[1].origin_station,1)

-- Non-gradual configuration waits the amount moved, at minimum one.
st,v,fleet=fixture({packet(13)})
ops={gradual=false}
L.begin(st,v,31,{},ops)
events,time=run(st,fleet,ops,40)
same(events[1].loaded,13)
same(time,14)
print("PASS: stock road loading clocks, unload-first order, reservations, full/no-load, feeder settlement, acceptance changes and late timetable waits")
