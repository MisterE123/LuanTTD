local A=dofile("mods/luanttd_core/openttd/airport_noise.lua")
assert(A.for_distance(0,500,0)==0 and A.for_distance(1,40,3)==1)
for t=0,3 do
  local step=8+4*t
  assert(A.for_distance(8,step-1,t)==8 and A.for_distance(8,step,t)==7)
  assert(A.for_distance(8,7*step,t)==1 and A.for_distance(8,8*step,t)==1)
end
assert(A.town_capacity(0,100)==0 and A.town_capacity(999,100)==12 and A.town_capacity(5000000,1)==65535)
local tiles={{local_x=0,local_z=0,x=9,z=12},{local_x=5,local_z=5,x=14,z=17},
  {local_x=2,local_z=5,x=11,z=17},{local_x=2,local_z=2,x=11,z=14}}
local town,d=A.closest(tiles,6,6,{{x=8,z=12,id=8},{x=14,z=16,id=2},{x=11,z=14,id=1}})
assert(town.id==2 and d==1,"must ignore interior and prefer lower town ID on perimeter tie")
town,d=A.closest(tiles,6,6,{{x=17,z=17,id=4},{x=8,z=20,id=3}})
assert(town.id==4 and d==3,"must measure from runway edge rather than build anchor")
print("PASS stock airport noise thresholds, zero population limit and perimeter town choice")
