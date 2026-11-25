-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, v16.0-RC1 tree_cmd.cpp: CreateStarShapedPolygon,
-- CreateRandomStarShapedPolygon and IsPointInStarShapedPolygon.
local G={}
local floor,frexp,ldexp=math.floor,math.frexp,math.ldexp
local function f32(v)
  if v==0 then return v end
  local sig,exp=frexp(math.abs(v))
  local scaled=sig*16777216
  local n=floor(scaled)
  local fraction=scaled-n
  if fraction>.5 or fraction==.5 and n%2==1 then n=n+1 end
  return (v<0 and -1 or 1)*ldexp(n,exp-24)
end
local function trunc(v) return v<0 and math.ceil(v) or floor(v) end
local divisor=f32(2147483647/math.pi*2)
local step=f32(math.pi*2/16)
function G.make(random)
  local phases={}
  for i=1,4 do phases[i]=f32(f32(random())/divisor) end
  local out,theta={},0
  for i=1,16 do
    local deviation=0
    for j=1,4 do
      local angle=f32(f32(theta+phases[j])*j)
      local wave=f32(f32(math.sin(angle))*2^(4-j))
      deviation=f32(deviation+wave)
    end
    local radius=f32(8+deviation*.5)
    out[i]={x=trunc(f32(f32(math.cos(theta))*radius)),
            z=trunc(f32(f32(math.sin(theta))*radius))}
    theta=f32(theta+step)
  end
  return out
end
function G.contains(grove,x,z)
  for i=1,#grove do
    local a,b=grove[i],grove[i%#grove+1]
    local s=a.x*z-a.z*x
    local t=(b.x-a.x)*(z-a.z)-(b.z-a.z)*(x-a.x)
    if not ((s<0)~=(t<0) and s~=0 and t~=0) then
      local d=-b.x*(z-b.z)+b.z*(x-b.x)
      if (d<0)==(s+t<=0) then return true end
    end
  end
  return false
end
return G
