local base="mods/luanttd_core/openttd/"
local hub=dofile(base.."airport_intercontinental.lua")
local city=dofile(base.."airport_city.lua")
local motion=dofile(base.."airport_motion.lua")(hub)
local S=hub.state
local a={id=1,x=32,z=32,ground=8,owner="air",rotation=0,flags=0}
local b={id=2,x=560,z=320,ground=8,owner="air",rotation=0,flags=0}
local host={airports={[1]=a,[2]=b},layout=function(row)return row.id==1 and hub or city end,
  allowed=function()return true end,terrain_height=function()return 8 end}
local approach,landing,takeoff=44,69,59
local arrive_block,depart_block=hub.layout[landing][1][2],hub.layout[takeoff][1][2]
do
  local v={owner="air",pos=approach,previous_pos=approach,state=S.FLYING,speed=120,subspeed=0}
  a.flags=depart_block
  assert(hub.arrive(a,v,host)=="approach" and v.pos==landing)
  assert(a.flags==arrive_block+depart_block,"Arrival reserves its own runway without stealing takeoff")
  a.flags=0
end
local v=assert(hub.new(a,{owner="air",max_speed=500,hangar_index=1,order={kind="station",id=b.id}}))
assert(v.pos==1 and v.hidden)
local hx,hz=hub.hangar_geometry.spawn(1)
assert(v.x==a.x+hx and v.z==a.z+hz)
local visits,departures,frames={},0,0
for i=1,120000 do
  local from=assert(host.airports[v.target])
  local rc,why=motion.move(from,v,host)
  assert(rc~=nil,why)
  if rc then
    local event,n=host.layout(from).arrive(from,v,host)
    assert(event,n)
    if event=="departed" then departures=departures+1 end
    if event=="terminal" then
      visits[from.id]=(visits[from.id] or 0)+1
      v.loading=nil
      v.order={kind="station",id=3-from.id}
      if (visits[1] or 0)>=2 and (visits[2] or 0)>=2 then frames=i;break end
    end
  end
end
assert(frames>0 and departures>=4,"Commercial circuit did not complete")
print("PASS RC1 intercontinental: independent runways and four mixed-City legs from Hangar 2",frames,departures)
