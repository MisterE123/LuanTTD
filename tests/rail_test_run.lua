local root="mods/bayline/"
local Sim=dofile(root.."sim.lua")
local T=dofile(root.."openttd/rail_track.lua")
local Motion=dofile(root.."openttd/rail_motion.lua")(T)
local Run=dofile(root.."rail_test_run.lua")(T,Motion,dofile(root.."openttd/road_speed.lua"),Sim)
local Pose=dofile(root.."rail_pose.lua")(T)
local function near(a,b) assert(math.abs(a-b)<1e-9,a.." ~= "..b) end
for td=0,13 do
  if T.valid_trackdir(td) then
    for i=0,40 do
      local x,z,dx,dz=Pose.sample(td,i/40)
      local a,b,da,db=Pose.sample(T.reverse_trackdir(td),1-i/40)
      near(x,a);near(z,b);near(dx,-da);near(dz,-db)
      near(dx*dx+dz*dz,1)
    end
  end
end
local s1,c,s2=Sim.id(14,16),Sim.id(15,16),Sim.id(15,17)
local route={{tile=s1,td=8},{tile=c,td=5},{tile=s2,td=1}}
local frames,len=Run.compile(route)
assert(frames and #frames==3 and len>0)
local d1,d2=frames[1].span,frames[2].span
local _,t,f=Run.at(frames,d1)
assert(t==8 and f==1)
local end_x,end_z,end_dx,end_dz=Pose.sample(t,f)
local start_x,start_z,start_dx,start_dz=Pose.sample(5,0)
near(end_x,start_x+2);near(end_z,start_z);near(end_dx,start_dx);near(end_dz,start_dz)
assert(d1==16*192 and d2<16*256)
assert(not Run.compile({{tile=s1,td=8},{tile=s2,td=1}}))
print("PASS: stock motion distance, all rail arcs, signed orientation and tangent seams")
