-- SPDX-License-Identifier: GPL-2.0-only
-- Presentation only: couple the two actual rolling-stock pins along their
-- chord. Only cars next to each other in the rendered train can share it.
local atan2,cos,sin,sqrt=math.atan2,math.cos,math.sin,math.sqrt
local function pin(body,toward)
  local p,r=body.pos,body.rotation
  local x,z=sin(r.y),-cos(r.y)
  local n=(toward.x-p.x)*x+(toward.z-p.z)*z>=0 and .454 or -.454
  return {x=p.x+x*n*cos(r.x),y=p.y+.095-n*sin(r.x),z=p.z+z*n*cos(r.x)}
end
return function(a,b)
  if a.index+1~=b.index then return end
  local pa,pb=pin(a,b.pos),pin(b,a.pos)
  local dx,dy,dz=pb.x-pa.x,pb.y-pa.y,pb.z-pa.z
  local length=sqrt(dx*dx+dy*dy+dz*dz)
  if length<.012 or length>.58 then return end
  return {pos={x=(pa.x+pb.x)/2,y=(pa.y+pb.y)/2,z=(pa.z+pb.z)/2},
    rotation={x=-atan2(dy,sqrt(dx*dx+dz*dz)),y=math.pi-atan2(dx,dz),z=0},length=length/.12}
end
