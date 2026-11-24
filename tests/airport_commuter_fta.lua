local base="mods/luanttd_core/openttd/"
local commuter=dofile(base.."airport_commuter.lua")
local city=dofile(base.."airport_city.lua")
local motion=dofile(base.."airport_motion.lua")(commuter)
local S,B=commuter.state,commuter.block
local a={id=1,x=32,z=32,ground=8,owner="air",rotation=0,flags=0}
local b={id=2,x=560,z=320,ground=8,owner="air",rotation=0,flags=0}
local host={airports={[1]=a,[2]=b},layout=function(row)return row.id==1 and commuter or city end,
  allowed=function()return true end,terrain_height=function()return 8 end}
do
  -- With the one shared runway busy, an arriving fixed-wing aircraft
  -- keeps its speed and holds while the rotorcraft approach stays available.
  local plane={owner=a.owner,pos=16,previous_pos=16,state=S.FLYING,speed=135,subspeed=0}
  a.flags=B.RUNWAY_IN
  assert(commuter.arrive(a,plane,host)=="hold")
  assert(plane.pos==21 and plane.speed==135)
  local heli={owner=a.owner,pos=16,previous_pos=16,state=S.FLYING,helicopter=true,speed=90,subspeed=0}
  assert(commuter.arrive(a,heli,host)=="approach" and heli.pos==25)
  a.flags=64
  heli.pos=26
  assert(commuter.free_terminal(a,heli) and heli.state==S.HELIPAD2 and a.flags==192)
  a.flags=0
end
local v=assert(commuter.new(a,{owner="air",max_speed=500,order={kind="station",id=b.id}}))
local visits,departures,frames={},0,0
for i=1,120000 do
  local from=assert(host.airports[v.target])
  local rc,why=motion.move(from,v,host)
  assert(rc~=nil,why)
  if rc then
    local event,n=host.layout(from).arrive(from,v,host)
    assert(event, n)
    if event=="departed" then departures=departures+1 end
    if event=="terminal" then
      visits[from.id]=(visits[from.id] or 0)+1
      v.loading=nil
      v.order={kind="station",id=3-from.id}
      if (visits[1] or 0)>=2 and (visits[2] or 0)>=2 then frames=i;break end
    end
  end
end
assert(frames>0 and departures>=4,"commercial circuit did not complete")
print("PASS RC1 Commuter shared runway and mixed City circuit",frames,departures)
