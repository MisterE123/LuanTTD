-- SPDX-License-Identifier: GPL-2.0-only
local dir="mods/luanttd_core/openttd/"
local O=dofile(dir.."road_overtake.lua")
local F=dofile(dir.."yapf_road_follow.lua")
local Speed=dofile(dir.."road_speed.lua")
local Motion=dofile(dir.."road_motion.lua")(dofile(dir.."road_motion_data.lua"))
local Proximity=dofile(dir.."road_proximity.lua")
local tiles={}
for t=0,7 do tiles[t]={kind="road",roadtype=0,road_bits=10} end -- ROAD_X
local function adjacent(t,d) assert(d==2);return t+1 end
local v={id=1,first=1,type="road",direction=5,state=8,tile=1,
  x=18,y=5,z=0,frame=2,speed=68,heading=5,subspeed=0,progress=0,max_speed=144,compatible={[0]=true}}
local u={id=2,first=2,type="road",direction=5,state=8,tile=1,
  x=23,y=5,z=0,frame=7,speed=0,stopped=true,max_speed=144,acceleration=0}
local oncoming={id=3,first=3,type="road",direction=1,state=0,tile=2,x=45,y=9,z=0}
local other_part={id=4,first=3,type="road",direction=1,state=0,tile=2,x=45,y=9,z=0}
local rail={id=5,first=5,type="rail",tile=2}
local include_oncoming=true
local function occupants(tile)
  local list={}
  for _,r in ipairs{v,u,other_part,rail} do if r.tile==tile then list[#list+1]=r end end
  if include_oncoming and oncoming.tile==tile then list[#list+1]=oncoming end
  return list
end
local base={tile=function(t) return tiles[t] end,adjacent=adjacent}
local board=O.plain_board(F,base,occupants)
local function refuse(why)
  local started,reason=O.try(board,v,u,true)
  assert(not started and reason==why and not O.active(v),tostring(reason).." / "..why)
end
refuse("other-vehicle") -- opposing lane vehicle not found by the same-direction probe still vetoes
oncoming.tile=1
refuse("other-vehicle") -- both physical look-ahead tiles must be checked
include_oncoming=false
tiles[2].roadworks=true;refuse("no-continuation");tiles[2].roadworks=nil
tiles[2].road_bits=11;refuse("junction");tiles[2].road_bits=10
tiles[2].kind="crossing";refuse("incompatible");tiles[2].kind="road"
tiles[2].kind="tunnel";refuse("incompatible");tiles[2].kind="road"
tiles[2].kind="bridge";refuse("incompatible");tiles[2].kind="road"
tiles[1].kind="drive_stop";refuse("station");tiles[1].kind="road"
tiles[2].disallowed=2;refuse("no-continuation")
tiles[2].disallowed=1
local allowed,ctr=O.check(board,v,u,true)
assert(allowed and ctr==17) -- no invented two-way requirement on a plain stock road.
tiles[2].disallowed=nil

local lead=Proximity.find(v,v,19,5,5,{v,u},true)
assert(lead==u)
local moved,began=O.within_blocked(board,v,u,true)
assert(not moved and began and v.speed==68 and v.overtaking_ctr==17 and v.x==18 and v.y==5)
-- Advance via the same RoadSpeed and RoadMotion entry points the runtime
-- uses. No visual interpolation or made-up passing lane is applied here.
local passed_at,returned_at,moves,ticks=0,nil,0,0
local function step(c)
  O.before_step(c,board.is_station(c.tile))
  local kind,x,y,d,f=O.next_pose(Motion,c,1)
  local new_tile
  if kind=="next_tile" then
    new_tile=adjacent(c.tile,x)
    kind,x,y,d,f=O.enter_pose(Motion,c,new_tile,0,8,1,Motion.DEFAULT_START)
  end
  assert(kind=="enter" or kind=="move" or kind=="rotate")
  local close=Proximity.find(c,c,x,y,d,{u},true)
  if close then
    if new_tile then return O.entry_blocked(c,close) end
    return O.within_blocked(board,c,close,true)
  end
  c.x,c.y,c.direction,c.frame,c.tile=x,y,d,f,new_tile or c.tile
  c.heading=d
  moves=moves+1
  if c.x>=u.x and passed_at==0 then passed_at=moves end
  if c.y==u.y then
    assert(math.abs(c.x-u.x)>=8,"Bodies overlap in the normal lane")
    returned_at=returned_at or moves
  else
    assert(c.y==9 and O.active(c),"passing must use the actual opposite lane row")
  end
  return true
end
while not returned_at and ticks<120 do
  Speed.tick(v,v.max_speed,O.active(v),step)
  ticks=ticks+1
end
assert(passed_at==5 and returned_at==18 and v.x==36 and v.y==5 and ticks>18)
assert(not O.active(v) and v.overtaking_ctr==35 and v.tile==2)

-- A moving lead vehicle can be passed too, based on the two stock
-- current maximum speeds. A 35-attempt pass is longer than the stopped
-- fixture and advances both actors with the real stock distance budget.
local through=function(c,kind,x,y,d,f)
  local target
  if kind=="next_tile" then
    target=adjacent(c.tile,x)
    kind,x,y,d,f=O.enter_pose(Motion,c,target,0,8,1,Motion.DEFAULT_START)
  end
  return kind,x,y,d,f,target
end
local function apply(c,kind,x,y,d,f,target)
  assert(kind=="enter" or kind=="move" or kind=="rotate")
  c.x,c.y,c.direction,c.frame,c.tile=x,y,d,f,target or c.tile
  c.heading=d
  return true
end
v.x,v.y,v.tile,v.frame,v.speed,v.heading,v.subspeed,v.progress=18,5,1,2,68,5,0,0
u.x,u.y,u.tile,u.frame,u.speed,u.heading,u.subspeed,u.progress=23,5,1,7,48,5,0,0
u.max_speed,u.stopped=48,false
assert(not O.within_blocked(board,v,u,true) and v.overtaking_ctr==0 and O.active(v))
local started_active,safe_return=0,false
for tick=1,180 do
  Speed.tick(u,u.max_speed,false,function(c) return apply(c,through(c,Motion.step(c,1))) end)
  Speed.tick(v,v.max_speed,O.active(v),function(c)
    local was_active=O.active(c)
    O.before_step(c,board.is_station(c.tile))
    if was_active then started_active=started_active+1 end
    local kind,x,y,d,f,target=through(c,O.next_pose(Motion,c,1))
    local close=Proximity.find(c,c,x,y,d,{u},true)
    if close then
      if target then return O.entry_blocked(c,close) end
      return O.within_blocked(board,c,close,true)
    end
    apply(c,kind,x,y,d,f,target)
    if not O.active(c) and c.y==u.y then
      assert(c.x-u.x>=8,"moving pass returned too close to leader")
      safe_return=true
    end
    return true
  end)
  if safe_return then break end
end
assert(safe_return and started_active==35 and v.overtaking_ctr==35)

-- Moving/accelerating compares target caps only under the stated stock model.
v.tile,u.tile=1,1
v.speed,v.max_speed,u.speed,u.max_speed,u.stopped=68,100,60,140,false
assert(not O.check(board,v,u,true))
assert(O.check(board,v,u,false))
u.acceleration=1
assert(not O.check(board,v,u,false))
u.stopped=true
assert(select(2,O.check(board,v,u,false))==17)
u.stopped=false;u.max_speed=90
assert(select(2,O.check(board,v,u,true))==0)
assert(not O.entry_blocked(v,u) and not O.active(v) and v.speed==u.speed)
u.max_speed=nil
assert(select(2,O.check(board,v,u,true))=="unknown-speed")
u.max_speed=90
-- A pass survives an elapsed counter on curves and flips only on a
-- later straight. A station force-aborts without advancing the byte.
v.overtaking,v.overtaking_ctr,v.state=16,34,2
assert(O.before_step(v,false)==nil and v.overtaking_ctr==35)
local curve_kind,cx,cy=O.next_pose(Motion,{x=9,y=0,state=2,frame=0,direction=3,overtaking=16},1)
assert(curve_kind=="move" and cx==5 and cy==1)
v.state=32
assert(O.before_step(v,true)=="station" and v.overtaking_ctr==35 and v.overtaking==0)
v.state,v.overtaking,v.overtaking_ctr=8,16,19
assert(O.reversing(v,14) and v.overtaking==0 and v.overtaking_ctr==19)
print("PASS road vehicles use stock conditional pass start, actual lane change, timeout return and vetoes")
