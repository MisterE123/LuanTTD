local S=dofile("mods/bayline/sim.lua")
local M=dofile("mods/bayline/road_motion.lua")
local route={S.id(6,6),S.id(7,6),S.id(7,7)}
local function close(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..b) end
local x,z,dx,dz,id=M.corner(route,2,S.xy)
assert(id==route[2]);close(dx,.5);close(dz,.5)
close(x,14.41);close(z,12.59)
assert(not M.corner(route,1,S.xy) and not M.corner(route,3,S.xy))
assert(not M.corner(route,2,S.xy,function() return false end))
for i=1,9 do
  local t=1.823+(i-1)*.044
  local a,b,p,q=M.corner(route,t,S.xy)
  assert(a>=14.14 and a<=14.5 and b>=12.5 and b<=12.86 and p>0 and q>0)
end
local first,last=M.corner(route,1.8200001,S.xy),M.corner(route,2.1799999,S.xy)
close(first,14.1400002);close(last,14.5)
local straight={S.id(6,6),S.id(7,6),S.id(8,6)}
assert(not M.corner(straight,2,S.xy))
print("PASS: turn tangent, centerline continuity, tile footprint, endpoints and grade gating")

local pi=math.pi
close(M.turn(-pi/2,pi,pi),-pi)
close(M.turn(pi,-pi/2,pi),3*pi/2)
local angle=-pi/2
for _=1,4 do
  local next_angle=M.turn(angle,pi,.4)
  assert(next_angle<=angle and angle-next_angle<=.40000001)
  angle=next_angle
end
close(angle,-pi)
local returned=M.turn(angle,pi/2,.3)
close(returned,-pi-.3)
print("PASS: shortest signed right/left turn across the ±180° seam, with bounded updates")

for _,heading in ipairs({0,pi/2,pi,-pi/2,-pi/6,pi/3}) do
  local yaw=M.nose_yaw(heading)
  close(math.sin(yaw),math.sin(heading))
  close(-math.cos(yaw),math.cos(heading))
end
print("PASS: Blender model nose follows cardinal, diagonal and wrapped world tangents")
