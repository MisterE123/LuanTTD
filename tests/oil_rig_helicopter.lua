-- SPDX-License-Identifier: GPL-2.0-only
local function load(name)
  return dofile("mods/luanttd_core/openttd/"..name..".lua")
end
local heliport=arg and arg[1]=="heliport"
local A=load(heliport and "airport_heliport" or "airport_oil_rig")
local M=load("airport_motion")(A)
local Rotor=load("airport_rotary_motion")(M)
local S,B=A.state,A.block
local layout,dz=A.airport_type,A.delta_z
local static={origin=31,flags=0,x=500,z=800,width=1,height=1,layout=layout,ground=0,rotation=0,delta_z=dz,id=17}
local next_target={origin=32,flags=0,x=70,z=160,width=1,height=1,layout=layout,ground=0,rotation=0,delta_z=dz,id=18}
local xy,rotor_sounds,visits=0,0,0
local ctx={rotary=Rotor,layout=function() return A end,airports={[17]=static,[18]=next_target},
  ground_height=function() return 0 end,terrain_height=function() return 0 end,
  flight_terrain_height=function() return 0 end,
  slope_pixel_z=function(x,z)
    xy=xy+1
    if heliport then
      assert(x==505 and z==809,"Heliport needs ground height at the actual aircraft position")
    else
      assert(x==500 and z==800 or x==70 and z==160,"oil rig uses ground height at the station origin")
    end
    return 0
  end,
  tile_at=function(x,z)
    assert(heliport,"rotary descent should preserve the rig's station tile")
    assert(z==809,"Heliport grounds the aircraft on the approach lane")
    return x<500 and 30 or 31
  end,
  takeoff_sound=function() rotor_sounds=rotor_sounds+1 end,
  service_at_helipad=function(v,a) visits=visits+1 end}
local function helicopter(a,id)
  local v={id=id,owner="A",direction=0,x=a.x-250,z=a.z-250,y=129,helicopter=true,rotor_speed=32,
    speed=0,progress=0,subspeed=0,acceleration=30,max_speed=322,order={kind="station",id=a.id}}
  A.inbound(a,v)
  return v
end
local first,second=helicopter(static,"first"),helicopter(static,"second")
-- Exact point and both resulting changes are checked after actual motion,
-- not by repeatedly teleporting the aircraft through the FTA.
local terminal,hold,blocked,departure,target,rotor_readings=nil,0,0,nil,static,{}
for _=1,6000 do
  local here,events,why=M.tick(target,first,ctx)
  assert(not why,why)
  target=here
  for _,e in ipairs(events) do
    if e=="approach" then
      assert(first.direct_descent and A.has(static.flags,B.BUSY))
    elseif e=="touchdown" then
      assert(first.rotor_speed>=80 and first.rotor_speed<=83 and first.y==dz+1 and not first.direct_descent
        and first.tile==31)
    elseif e=="terminal" then
      assert(first.y==dz+1 and first.x==(heliport and 505 or 531) and first.z==809 and first.tile==31)
      assert(A.has(static.flags,B.PAD) and not A.has(static.flags,B.BUSY))
      terminal=true
    elseif e=="departed" then
      assert(terminal and first.rotor_speed==32 and not first.tile and first.target==18 and target==next_target)
      departure=true
    end
  end
  if not departure then
    local _,circle,why=M.tick(static,second,ctx)
    assert(not why,why)
    for _,e in ipairs(circle) do
      if e=="hold" then
        hold=hold+1
        if terminal and A.has(static.flags,B.PAD) then blocked=blocked+1 end
      end
    end
    if terminal and blocked>=3 then
      first.loading=nil
      first.order={kind="station",id=18}
    end
  else break end
  if first.direct_descent then rotor_readings[first.rotor_speed]=true end
end
assert(terminal and departure and hold>0 and blocked>=3 and rotor_sounds==1 and visits==1 and xy>100)
assert(rotor_readings[32] and (rotor_readings[36] or rotor_readings[40]) and (rotor_readings[72] or rotor_readings[76]))
assert(not A.has(static.flags,B.PAD) and not A.has(static.flags,B.BUSY))
local newcomer=helicopter(static,"closed")
newcomer.pos,newcomer.previous_pos=8,7
static.closed=true
assert(A.arrive(static,newcomer,ctx)=="hold")
newcomer.pos,newcomer.previous_pos=8,7
static.closed=nil;static.owner="someone-else"
assert(A.arrive(static,newcomer,ctx)=="hold")
newcomer.helicopter=false
assert(not A.arrive(static,newcomer,ctx))
print(("PASS %s aircraft FTA: two real moving helicopters, one pad, blocked hold, %d px descent, exact dispatch and rotor spin"):format(layout,dz))
