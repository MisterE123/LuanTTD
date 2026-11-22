local d="mods/luanttd_core/openttd/"
local Motion=dofile(d.."road_motion.lua")(dofile(d.."road_motion_data.lua"))
local O=dofile(d.."road_stop_occupancy.lua")(Motion)
local tiles={}
local board={tile=function(id) return tiles[id] end,
  adjacent=function(id,direction) return id+({[0]=-1,16,1,-16})[direction] end}
local function record(kind,dir,station,stop_type)
  return {kind=kind,dir=dir,owner=2,station=station or 7,stop_type=stop_type or "bus"}
end
local function rv(id,tile,td,facing,n)
  return {id=id,first=id,type="road",tile=tile,state=td,frame=0,direction=facing,
    total_length=n or 8,speed=99,bus=true,owner=2}
end
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function e(s,id,dir,occupied,length)
  local a,b=O.entry(s,id,dir)
  eq(a,occupied);eq(b,length)
end
local s=O.new()
tiles[37]=record("bay_stop",0)
local rs=O.register(s,board,37)
local a,b,c=rv(1,37,8,5),rv(2,37,8,5),rv(3,37,8,5)
local order={kind="go_station",station=7,should_stop=true}
local function status(n) eq(rs.status,n) end
status(3)
a.frame=15
eq(O.station_callback(s,board,37,a),true);status(3) -- actual frame 0 claims
a.frame=0
assert(O.station_callback(s,board,37,a));eq(a.state,40);status(130)
eq(select(2,O.station_callback(s,board,37,b)),"entrance")
a.frame=Motion.bay_stop_frame(a.state,1)
eq(O.at_stop(s,board,a,1,order),"load");eq(a.state,44);status(2)
assert(O.station_callback(s,board,37,b));status(128);eq(b.state,42)
eq(O.at_stop(s,board,a,1,{kind="leave_station"}),"wait_entrance");eq(a.speed,0)
b.frame=Motion.bay_stop_frame(b.state,1)
eq(O.at_stop(s,board,b,1,order),"load");eq(b.state,46);status(0)
eq(select(2,O.station_callback(s,board,37,c)),"full")
local depart={kind="leave_station"}
eq(O.at_stop(s,board,a,1,depart),"depart");eq(depart.kind,nil);status(128)
eq(O.at_stop(s,board,b,1,{kind="leave_station"}),"wait_entrance")
local ok,td=O.transition(s,board,a,36,6)
eq(ok,false);eq(td,"bay_reverse");status(128)
ok,td=O.transition(s,board,a,36,0)
eq(ok,true);eq(td,0);status(1)
c.articulated=true
eq(select(2,O.station_callback(s,board,37,c)),"articulated");status(1)
c.articulated=false
assert(O.station_callback(s,board,37,c));status(128);eq(c.state,40)
c.frame=Motion.bay_stop_frame(c.state,1)
eq(O.at_stop(s,board,c,1,{kind="go_station",station=8}),"depart");status(128)
O.delete_tail(s,board,c);status(1)

-- Existing source table has independent stationary points for both bays
-- in both traffic sides; physics/rendering must preserve this offset.
local parking={[0]={5,6,9,6},[1]={6,10,6,6},[8]={10,9,6,9},[9]={9,5,9,9}}
for d0,p in pairs(parking) do
  for side=0,1 do for slot=0,1 do
    local state=32+d0+slot*2
    local f=Motion.bay_stop_frame(state,side)
    local k,x,y=Motion.sample(state,side,f)
    eq(k,"position");eq(x,p[slot*2+1]);eq(y,p[slot*2+2])
  end end
end

-- Caches join by station + facility + canonical road-stop orientation.
-- Populate separated lines, join across a gap while they have traffic,
-- then split again with a primary front in each half.
s=O.new()
for _,id in ipairs{70,71,72,73,74} do tiles[id]=record("drive_stop",0) end
tiles[75]=record("drive_stop",0,7,"truck")
tiles[76]=record("drive_stop",0,8)
for _,id in ipairs{71,70,74,73,75,76} do O.register(s,board,id) end
eq(s.stops[70].base,70);eq(s.stops[71].base,70)
eq(s.stops[73].base,73);eq(s.stops[74].base,73)
eq(s.stops[75].base,75);eq(s.stops[76].base,76)
a,b,c=rv(1,70,0,1,22),rv(2,74,8,5,36),rv(3,74,0,1,8)
assert(O.enter(s,board,70,a));assert(O.enter(s,board,74,b));assert(O.enter(s,board,74,c))
e(s,71,0,22,32);e(s,73,2,36,32);e(s,73,0,8,32)
O.register(s,board,72)
e(s,74,2,36,80);e(s,72,0,30,80);eq(s.stops[73].base,70)
local function copy(x)
  if type(x)~="table" then return x end
  local y={}
  for k,v in pairs(x) do y[k]=copy(v) end
  return y
end
local restored=copy(s)
eq(O.get_entry(restored,70,0),O.get_entry(restored,74,0))
eq(O.get_entry(restored,71,2),O.get_entry(restored,73,2))
assert(O.get_entry(restored,72,0)~=O.get_entry(s,72,0))
local view=O.routing(s,board);eq(view.stop_continues(74,75),false)
local occupied,length=view.stop_entry(73,0);eq(occupied,30);eq(length,80)
local trailer=rv(9,73,8,5,10);trailer.first=2;trailer.state=72
local wreck=rv(10,74,0,1,8);wreck.crashed=true;wreck.state=64
local parked=rv(11,74,0,1,8) -- front in ordinary ROAD state, must not count
local aircraft={type="air",direction=1,state=64,total_length=8}
local actors={[70]={a,a},[73]={trailer},[74]={b,c,wreck,parked,aircraft,c}}
O.clear(s,board,72,function(id) return actors[id] or {} end)
tiles[72]=nil
eq(s.stops[73].base,73)
e(s,71,0,22,32);e(s,74,0,8,32);e(s,74,2,36,32)
eq(O.rebuild(s,board,73,function(id) return actors[id] or {} end).west.occupied,36)
assert(s.stops[72]==nil and s.lines[72]==nil)
O.clear(s,board,73)
tiles[73]=nil
e(s,74,2,36,16);eq(s.stops[74].base,74)

-- A platform can be overfull by full chain length and remains passable:
-- no arbitrary hard capacity, queue spacing comes from the vehicle probe.
b.frame=11
b.state=72
eq(O.at_stop(s,board,b,1,order,function() return true end),"load")
eq(b.state,76)
eq(O.transition(s,board,b,75,8),true) -- different type => leave this entry at front exit
e(s,74,2,0,16)
O.crash(s,board,c);e(s,74,0,0,16)
tiles[90]=record("drive_stop",1);tiles[106]=record("drive_stop",1)
O.register(s,board,90);O.register(s,board,106)
local van=rv(20,90,1,3,16)
assert(O.station_callback(s,board,90,van))
van.frame=11
eq(O.at_stop(s,board,van,1,order,function() return true end),"move_inline")
eq(van.state,65);eq(van.last_station_visited,nil)
ok,td=O.transition(s,board,van,106,1)
eq(ok,true);eq(td,65)
e(s,106,1,16,32)
van.tile=106;van.speed=0
assert(O.blocked_load(board,van,order));eq(van.state,65);eq(van.last_station_visited,7)
assert(not O.blocked_load(board,van,{kind="leave_station",should_stop=true}))
print("PASS stock bay/door lifecycles, directional drive-through cache, and exact controller stop gates")
