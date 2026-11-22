-- End-to-end simulation fixture. The real daily path must drive demand,
-- boarding, stock rating updates, expiry and reactivation.
local M=dofile("mods/luanttd_core/sim.lua")
local T=dofile("mods/luanttd_core/openttd/terrain.lua")
local P=dofile("mods/luanttd_core/openttd/passengers.lua")
local s=M.new(1751)
s.corner_grid=T.new(M.W,M.H)
s.road_economy=true
for z=9,11 do for x=6,12 do
  local t=s.tiles[M.id(x,z)]
  t.terrain="grass";t.h=0;t.house=nil;t.site=nil;t.wood=nil
end end
local a,b,c=M.id(6,10),M.id(9,10),M.id(12,10)
assert(M.build(s,"A","road",M.line(a,c)))
assert(M.build(s,"A","road_station",{a,b,c}))
local first=s.stations[s.tiles[a].station]
local unserved=s.stations[s.tiles[b].station]
local second=s.stations[s.tiles[c].station]
local vid=assert(M.purchase(s,"A","bus","passenger",first.id))
assert(M.add_order(s,"A",vid,second.id))
assert(M.toggle(s,"A",vid))
local v=s.fleet[vid]
local function advance_until(f,limit)
  for _=1,limit do M.daily(s);if f() then return end end
  error("Timed out waiting for rating or service event")
end
advance_until(function() return v.last_fare~=nil end,30)
assert(first.passenger_rating_state.has_rating and first.passenger_rating_state.rating>175)
assert(second.passenger_rating_state.last_speed>0)
assert(P.waiting(unserved)==0 and unserved.passenger_rating_state.last_speed==0)

if v.running then assert(M.toggle(s,"A",vid)) end
advance_until(function() return not v.running end,20)
local st=s.stations[v.station]
local hist=st.passenger_service_day
assert(hist and st.passenger_rating_state.last_speed>0)
P.enqueue(st,{units=1300,origin_station=st.id,source=st.site,age=0})
local waiting=P.waiting(st)
M.daily(s)
assert(P.waiting(st)>waiting,"actual local allocation must not be capped at 1,200")
advance_until(function() return not st.passenger_rating_state.has_rating end,650)
assert(P.waiting(st)==0 and st.passenger_rating_state.last_speed==0 and st.passenger_service_day==hist)
for _=1,8 do M.daily(s) end
assert(P.waiting(st)==0,"expired historic marker must not generate queue")
assert(M.toggle(s,"A",vid))
advance_until(function() return st.passenger_rating_state.last_speed>0 end,50)
advance_until(function() return st.passenger_rating_state.has_rating end,30)
assert(st.passenger_service_day==hist,"reactivation is not a first-ever visit")
assert(P.waiting(st)>0 or (v.last_board and v.last_board.day==s.day))
print("PASS: real daily transport path applies stock station rating to passenger allocation, expiry and reactivation")
