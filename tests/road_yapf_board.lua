local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local F=dofile(root.."openttd/yapf_road_follow.lua")
local C=dofile(root.."openttd/yapf_road_cost.lua")(F)
local Search=dofile(root.."openttd/yapf_road_search.lua")(F,C)
local make_board=dofile(root.."road_yapf_board.lua")
local s=Sim.new(1751)
for _,tile in ipairs(s.tiles) do
  tile.wood=nil;tile.house=nil;tile.site=nil;tile.h=0;tile.terrain="grass"
end
local function at(x,z) return Sim.id(x+3,z+6) end
local function fill(x,z,bits,build,owner)
  local t=s.tiles[at(x,z)]
  t.build,t.road_bits,t.owner=build or "road",bits,owner or "A"
  return t
end
local depot=fill(0,0,2,"road_depot")
depot.depot_dir=2
fill(1,0,14)
fill(2,0,10)
local mid=fill(3,0,10,nil,"B")
fill(4,0,10)
fill(5,0,14)
fill(1,1,3)
for x=2,4 do fill(x,1,10) end
fill(5,1,9)
local target=fill(6,0,8,"road_station")
target.station=1
s.stations[1]={id=1,tile=at(6,0),mode="road"}
local bus={tile=at(0,0),display_max_speed=112,bus=true,owner="A"}
local sw=F.direction_trackdir(F.SW)
local function route()
  local B=make_board(Sim,s,F)
  local d=C.destination(B,bus,{kind="station",station=1})
  local ok,best=Search.find(B,bus,bus.tile,2^sw,d)
  assert(ok)
  local course=Search.trace(B,bus,d,best)
  return B,best.cost,course
end
local B,cost,course=route()
assert(cost==600 and #course==7 and course[4].tile==at(3,0))
assert(B.tile(at(6,0)).kind=="bay_stop" and B.tile(at(6,0)).dir==F.NE)
local reverse=F.follow(B,bus,at(6,0),sw)
assert(reverse.ok and reverse.reversed and reverse.tile==at(6,0) and reverse.trackdirs==1)
assert(B.adjacent(at(0,0),F.SW)==at(1,0))
assert(B.edge_available(at(2,0),at(3,0),F.SW))
assert(B.center_z(at(0,0))==0 and B.tile(nil)==nil)
mid.build,mid.station,mid.stop_axis="road_station",2,10
s.stations[2]={id=2,tile=at(3,0),mode="road"}
B,cost,course=route()
assert(cost==1084 and #course==9 and course[3].tile==at(1,1))
local queue=make_board(Sim,s,F,{drive_length=function(tile,dir)
  assert(tile==at(3,0) and dir==F.SW);return 7
end,bay_taken=function(tile,bay) return tile==at(6,0) and bay==1 end})
assert(C.one_tile(queue,at(3,0),sw)==1250)
assert(C.one_tile(queue,at(6,0),sw)==850)
print("PASS: source YAPF on LuanTTD tiles with depot, actual bay, through stop and foreign road")

local Motion=dofile(root.."openttd/road_motion.lua")(dofile(root.."openttd/road_motion_data.lua"))
local Leg=dofile(root.."road_motion_leg.lua")
local Presentation=dofile(root.."road_motion_presentation.lua")(dofile(root.."road_lanes.lua"))
local frames=assert(Leg(Motion,F,B).compile(course))
local target_tile=at(6,0)
assert(frames[1][4]==at(0,0) and frames[#frames][4]==target_tile)
local rotates=0
for i=2,#frames do
  local a,b=frames[i-1],frames[i]
  if a[1]==b[1] and a[2]==b[2] then
    assert((a[3]-b[3])%8==1 or (b[3]-a[3])%8==1)
    rotates=rotates+1
  end
  local dx,dz=math.abs(b[1]-a[1]),math.abs(b[2]-a[2])
  assert(dx<=1 and dz<=1,("position jump at frame %d: %s %s"):format(i,dx,dz))
end
assert(rotates>=8)
local t=course[#course].td
local bx,by=B.xy(target_tile)
local _,sx,sy=Motion.sample(32+t,1,Motion.bay_stop_frame(32+t,1))
assert(frames[#frames][1]==bx*16+sx and frames[#frames][2]==by*16+sy)
local leg=assert(Leg(Motion,F,B).compile({
  {tile=target_tile,td=F.direction_trackdir(F.NE)},
  {tile=at(5,0),td=F.direction_trackdir(F.NE)},
  {tile=at(4,0),td=F.direction_trackdir(F.NE)},
  {tile=at(3,0),td=F.direction_trackdir(F.NE)},
}))
assert(leg[1][1]==frames[#frames][1] and leg[1][2]==frames[#frames][2]
  and leg[1][3]==frames[#frames][3], "arrival/departure jump at bay")
target.road_stop_pair=true
local router=dofile(root.."road_yapf_route.lua")(Sim,F,C,Search,make_board,Motion,Leg)
local route,same_td,_,first,branch=router.route(s,{tile=at(0,0)},s.stations[1],"A",{cargo="passenger",engine="bus"})
assert(route and same_td==t and branch.tile==target_tile and first[branch.first][9])
local p,q=first[#first],branch.second[#branch.second]
assert(p[6]+2==q[6] and p[4]==q[4] and p[3]==q[3])
assert(math.abs(p[1]-q[1])+math.abs(p[2]-q[2])==4, "stock bays should be four source pixels apart")
local _,_,_,second_depart=router.route(s,s.stations[1],s.stations[2],"A",
  {cargo="passenger",engine="bus",road_stop_pose=q})
assert(second_depart and second_depart[1][1]==q[1] and second_depart[1][2]==q[2]
  and second_depart[1][3]==q[3] and second_depart[1][6]==q[6], "second bay departure must retain actual boarded pose")
local _,lx=Presentation.xy(48,5,1)
local _,rx=Presentation.xy(48,9,1)
assert(math.abs(rx-lx-.310)<1e-7)
assert(rx-lx>.26796 and .155+.26796*.5<.3125)
assert(math.abs(Presentation.yaw(3))<1e-9)
assert(math.abs(Presentation.yaw(5)-math.pi/2)<1e-9)
assert(math.abs(Presentation.yaw(1)+math.pi/2)<1e-9)
local x0,z0,ang=Presentation.pose({15,0,7},{15,0,0},.5)
assert(math.abs(ang-4.5*math.pi/4)<1e-9)
-- Inside corner, carried initial heading SE. Seven new positions, two
-- distinct stationary rotations, then the edge marker: ten steps.
local v={x=5,y=0,direction=3,state=2,frame=0}
local n=0
for i=1,10 do
  local k,x,y,d,f=Motion.step(v,0)
  if i==10 then
    assert(k=="next_tile" and x==F.NE and v.direction==1 and n==2)
  else
    if k=="rotate" then n=n+1;assert(x==v.x and y==v.y and f==v.frame) end
    v.x,v.y,v.direction,v.frame=x,y,d,f
  end
end
print("PASS: source poses for depot, detour, bay turnaround, opposing lanes and inner corner")
