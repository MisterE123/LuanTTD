local base="mods/luanttd_core/openttd/"
local metropolitan=dofile(base.."airport_metropolitan.lua")
local city=dofile(base.."airport_city.lua")
local motion=dofile(base.."airport_motion.lua")(metropolitan)
local S,B=metropolitan.state,metropolitan.block
local a={id=1,x=32,z=32,ground=8,owner="air",rotation=0,flags=0}
local b={id=2,x=560,z=320,ground=8,owner="air",rotation=0,flags=0}
local host={airports={[1]=a,[2]=b},layout=function(row)return row.id==1 and metropolitan or city end,
  allowed=function()return true end,terrain_height=function()return 8 end}
do
  local landing={owner=a.owner,pos=13,previous_pos=13,state=S.FLYING,speed=100,subspeed=0}
  a.flags=B.RUNWAY_OUT
  assert(metropolitan.arrive(a,landing,host)=="approach")
  assert(landing.pos==14 and a.flags==B.RUNWAY_IN+B.RUNWAY_OUT)
  local wait={owner=a.owner,pos=13,previous_pos=13,state=S.FLYING,speed=150,subspeed=0}
  assert(metropolitan.arrive(a,wait,host)=="hold" and wait.speed==150 and wait.pos==19)
  a.flags=0
end
local v=assert(metropolitan.new(a,{owner="air",max_speed=500,order={kind="station",id=b.id}}))
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
print("PASS RC1 Metropolitan independent runways and mixed City circuit",frames,departures)
