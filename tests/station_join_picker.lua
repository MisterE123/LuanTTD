local F=dofile("mods/luanttd_core/openttd/station_join_picker.lua")
local W,H=22,17
local function id(x,z)
  return x>=1 and x<=W and z>=1 and z<=H and (z-1)*W+x or nil
end
local function xy(t) return (t-1)%W+1,math.floor((t-1)/W)+1 end
local by_tile={}
local b={id=id,xy=xy,station_at=function(t)return by_tile[t] end,
  matches=function(st)return st.kind=="stop" end}
local r={tile=id(7,6),w=3,h=2}
local actual={}
local function collect(t)
  local x,z=xy(t)
  actual[#actual+1]=(x..","..z)
end
F.spiral(b,r,1,collect)
assert(table.concat(actual," ")==
  "10,5 9,5 8,5 7,5 6,5 6,6 6,7 6,8 7,8 8,8 9,8 10,8 10,7 10,6")
local function put(x,z,n,owner,w,kind)
  local i=id(x,z)
  by_tile[i]={id=n,tile=i,owner=owner or "Player",kind=kind or "stop",
    spread={tile=i,w=w or 1,h=1}}
end
put(10,5,18);put(6,5,14);put(13,5,25);put(10,7,37,"Rival")
put(8,7,2);put(9,7,3,"Player",1,"waypoint")
put(11,9,23,"Player",5) -- union from X=7 through X=15 is too wide
by_tile[id(10,6)]=by_tile[id(10,5)] -- don't repeat a multi-part station
b.deleted={{id=30,tile=id(8,7),owner="Player",kind="stop"},
  {id=31,tile=id(13,6),owner="Player",kind="stop"},
  {id=32,tile=id(14,6),owner="Player",kind="stop"},
  {id=33,tile=id(6,6),owner="Rival",kind="stop"}}
local function selections(distant)
  local rows=F.find(b,r,"Player",7,distant)
  assert(rows[1].new)
  local ids={}
  for i=2,#rows do ids[#ids+1]=rows[i].id end
  return table.concat(ids," ")
end
assert(selections(false)=="30 2 18 14",selections(false))
assert(selections(true)=="30 2 18 14 31 25",selections(true))
local edge={tile=id(1,1),w=2,h=3}
local seen,n={},0
F.spiral(b,edge,2,function(i)
  assert(not seen[i]);seen[i]=true;n=n+1
end)
assert(n==4*5-2*3)
print("PASS RC1 station chooser order, clipped rings, station spread, ownership, deleted IDs and facility filter")
