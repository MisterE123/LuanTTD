-- SPDX-License-Identifier: GPL-2.0-only
-- Real stock rolling positions, two flying Sampsons, one shared FTA word.
local root="mods/bayline/"
local src=root.."openttd/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(src.."terrain.lua")
local A=dofile(src.."airport_small.lua")
local Motion=dofile(src.."airport_motion.lua")(A)
local Network=dofile(root.."airport_network.lua")(Sim,Terrain,A)
local Pair=dofile(root.."airport_ground_pair.lua")(Sim,A,Motion,Terrain)
local s=Sim.new(965)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
for _,t in ipairs(s.tiles) do t.terrain,t.build,t.owner,t.wood,t.house,t.site="grass",nil,nil,nil,nil,nil end
local left=assert(Network.build(s,"A",Sim.id(7,13)))
local right=assert(Network.build(s,"A",Sim.id(32,13)))
local hub=assert(Network.build(s,"A",Sim.id(22,13)))
local blocked,reason=Pair.start(s,"B",left.id,right.id,hub.id)
assert(not blocked and reason=="OWNED_AIRFIELD_AND_TERRAIN_REQUIRED")
assert(not Pair.start(s,"A",left.id,left.id,hub.id))
hub.flags=A.block.BUSY
assert(not Pair.start(s,"A",left.id,right.id,hub.id))
assert(not s.airport_ground_pair and hub.flags==A.block.BUSY)
hub.flags=0
local pair=assert(Pair.start(s,"A",left.id,right.id,hub.id))
assert(not Pair.start(s,"A",left.id,right.id,hub.id))
assert(Pair.protects_airfield(s,left.id) and Pair.protects_airfield(s,hub.id))
assert(not Network.remove(s,"A",left.origin,true,function(id)return Pair.protects_airfield(s,id) end))
assert(not Pair.request_return(s,"A",1) and not Pair.request_return(s,"B",2))
assert(pair.actors[1].stock_engine==215 and pair.actors[2].stock_engine==215)
assert(not Pair.pose(pair.actors[1]) and not Pair.pose(pair.actors[2]))

local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local b={}
  for k,v in pairs(t) do b[k]=clone(v) end
  return b
end
local function reload()
  s=clone(s);pair=assert(Pair.current(s))
  left,right,hub=s.stock_small_airports[left.id],s.stock_small_airports[right.id],s.stock_small_airports[hub.id]
end

-- Observe, don't confer, block ownership. It must remain the same
-- until the actual source release transition, including across reload.
local owner={}
local arrivals={}
local tick=0
local trace=arg and arg[1]=="--trace"
local poses=arg and arg[1]=="--poses"
local scale=arg and arg[1]=="--scale"
if scale then print(dofile(root.."airport_airframe_art.lua").sampson.scale);return end
local number={next=1,blocked=2,wait_hangar=3,wait_terminal=4,hangar=5,terminal=6,hold=7,approach=8,
  assigned_terminal=9,to_hangar=10,takeoff=11,liftoff=12,departed=13,touchdown=14}
local found={reserved=0,released=0,holds=0,departure_holds=0}
local first_approach,second_approach,first_release,heard_hold
local ground_min=math.huge
local function inspect(e)
  if trace then
    print(table.concat({e.tick,e.vehicle,e.loop,e.airport,number[e.kind],e.pos,e.previous,e.state,e.flags,
      e.x,e.z,e.y,e.speed,e.subspeed,e.after_flags,e.after_pos,e.after_state,e.after_speed,e.after_subspeed}," "))
  end
  local busy,after=A.has(e.flags,A.block.BUSY),A.has(e.after_flags,A.block.BUSY)
  assert(busy==(owner[e.airport]~=nil))
  if not busy and after then
    owner[e.airport]=e.vehicle;found.reserved=found.reserved+1
  elseif busy and not after then
    assert(owner[e.airport]==e.vehicle,"Aircraft cleared another aircraft's runway")
    local from,to=A.layout[e.previous][1][2],A.layout[e.pos][1][2]
    assert(from==A.block.BUSY and to~=from,"Runway freed before its stock new point")
    local field=s.stock_small_airports[e.airport]
    local x,z,flags=A.point(e.pos,field.rotation,field.width,field.height)
    local reach=A.has(flags,A.flag.EXACTPOS) and 0 or A.has(flags,A.flag.SLOWTURN) and 8 or 4
    -- A point's controller has already reached its original tolerance.
    assert(math.abs(e.x-x-field.x)+math.abs(e.z-z-field.z)<=reach)
    owner[e.airport]=nil;found.released=found.released+1
  end
  if e.airport==hub.id then
    if e.kind=="approach" then
      assert(e.pos==10 and e.after_pos==11 and not busy and after)
      if not first_approach then first_approach=e else second_approach=e end
    elseif e.kind=="hold" and busy then
      assert(owner[hub.id]~=e.vehicle and e.after_state==A.state.FLYING and e.after_pos==15)
      assert(e.speed==e.after_speed and e.subspeed==e.after_subspeed and e.y>hub.ground+1)
      found.holds=found.holds+1;heard_hold=e
    elseif busy and not after and not first_release then
      first_release=e
    elseif e.kind=="blocked" and busy and owner[hub.id]~=e.vehicle then
      assert(e.after_speed==0 and e.after_subspeed==0)
      found.departure_holds=found.departure_holds+1
    end
  end
end
local function near_ground()
  local a,b=pair.actors[1].vehicle,pair.actors[2].vehicle
  if a.target==hub.id and b.target==hub.id and not a.hidden and not b.hidden and
      a.y<=hub.ground+9 and b.y<=hub.ground+9 then return a,b end
end
local function print_pose(marker,i,a,b)
  print(table.concat({marker,i,a.x,a.z,a.direction,b.x,b.z,b.direction,
    a.y-hub.ground-1,b.y-hub.ground-1,a.airborne and 1 or 0,b.airborne and 1 or 0}," "))
end
local persisted={}
local exact_index=0
local callbacks={
  position=poses and function()
    exact_index=exact_index+1
    local a,b=near_ground()
    if a then print_pose("exact",exact_index,a,b) end
  end or nil,
  arrive=function(p,tile,a)
    assert(s.tiles[tile].airfield.airport==a.id)
    local key=p.id..":"..p.arrivals
    assert(not persisted[key],"Arrival visit replayed")
    persisted[key]=true
    arrivals[#arrivals+1]={id=p.id,field=a.id,tile=tile}
    return true
  end,
}
local function step()
  tick=tick+1
  local events,why=Pair.advance(s,callbacks,tick)
  assert(events and not why,why)
  local last,last_loop=0,0
  for _,e in ipairs(events) do
    assert(e.vehicle>=last and (e.vehicle~=last or e.loop>last_loop))
    last,last_loop=e.vehicle,e.loop
    inspect(e)
  end
  local a,b=pair.actors[1],pair.actors[2]
  assert(a.vehicle.tick==b.vehicle.tick and a.vehicle.tick==pair.ticks)
  local v,w=near_ground()
  if v then
    local x,y=v.x-w.x,v.z-w.z
    if poses then print_pose("frame",tick,v,w) end
    ground_min=math.min(ground_min,x*x+y*y)
    assert(x*x+y*y>0,"Aircraft occupied the same on-ground physical point")
  end
end

while not heard_hold do step();assert(tick<4000) end
assert(tick==1109 and first_approach.vehicle==2 and first_approach.tick==665)
assert(hub.flags==A.block.BUSY+A.block.TERM1)
assert(pair.actors[1].phase=="holding" and pair.actors[2].phase=="rollout")
reload()
assert(hub.flags==A.block.BUSY+A.block.TERM1 and owner[hub.id]==2)
local dup,problem=Pair.advance(s,callbacks,tick)
assert(not dup and problem=="AIRCRAFT_TICK_ALREADY_PROCESSED" and pair.ticks==tick)
while #arrivals<2 do step();assert(tick<5000) end
assert(first_release.vehicle==2 and first_release.tick==1133 and heard_hold.tick<first_release.tick)
assert(second_approach.vehicle==1 and second_approach.tick==1984 and first_release.tick<second_approach.tick)
assert(pair.actors[2].vehicle.state==A.state.TERM1 and pair.actors[1].vehicle.state==A.state.TERM2)
assert(hub.flags==A.block.TERM1+A.block.TERM2 and not owner[hub.id])
assert(arrivals[1].tile~=arrivals[2].tile)
assert(Pair.pose(pair.actors[1]) and Pair.pose(pair.actors[2]))
assert(Pair.request_return(s,"A",1))
assert(Pair.request_return(s,"A",2))
reload()
assert(pair.actors[1].return_requested and pair.actors[2].return_requested)

while #arrivals<4 do step();assert(tick<10000) end
assert(hub.flags==0 and left.flags==A.block.TERM1 and right.flags==A.block.TERM1)
assert(pair.actors[1].phase=="returned" and pair.actors[1].last_airfield==left.id)
assert(pair.actors[2].phase=="returned" and pair.actors[2].last_airfield==right.id)
assert(found.departure_holds>0 and found.reserved==found.released and next(owner)==nil)
assert(not Pair.request_return(s,"A",1))
-- Occasional FTA point overlap in the airborne holding pattern has
-- never been represented as a new air-traffic separation system.
assert(ground_min==14^2,ground_min)
reload()
local before=hub.flags
hub.x=hub.x+16
local invalid,why=Pair.advance(s,callbacks,tick+1)
assert(not invalid and why=="AIRFIELD_CHANGED" and hub.flags==before and left.flags==A.block.TERM1)
if not trace and not poses then
  print(("PASS: two Sampson U52s, stock blocked approach at %d, first runway release %d, second approach %d, %d outbound taxi waits and 4 visits"):
    format(heard_hold.tick,first_release.tick,second_approach.tick,found.departure_holds))
end
