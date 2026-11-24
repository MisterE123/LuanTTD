-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 src/tilearea_spiral.cpp.
-- The caller uses the stock zero-origin row-major tile indices.
local M={}
local floor=math.floor
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
-- Translate the upstream iterator's initialized position and westward
-- ring jump. Off-map entries are skipped (not clamped/repeated).
local function spiral(w,h,x,z,radius,ew,eh,dir)
  local at=0
  local function start_side() return (dir%2==0 and ew or eh)+at*2+1 end
  local remaining=dir>=0 and start_side() or 0
  local function advance()
    if dir==-1 then
      x,z,dir=x+1,z-1,0
    else
      x,z=x+dx[dir],z+dz[dir]
      remaining=remaining-1
      if remaining>0 then return end
      dir=dir+1
      if dir==4 then x,z,at,dir=x+1,z-1,at+1,0 end
    end
    remaining=start_side()
  end
  return function()
    while at~=radius or dir==-1 do
      local x0,z0=x,z
      advance()
      if x0>=0 and x0<w and z0>=0 and z0<h then return x0+z0*w end
    end
  end
end
function M.centered(w,h,i,diameter)
  local half=diameter%2
  return spiral(w,h,i%w+(1-half),floor(i/w),floor(diameter/2),half,half,half==1 and -1 or 0)
end
function M.perimeter(w,h,i,radius,width,depth)
  return spiral(w,h,i%w+width+1,floor(i/w),radius,width,depth,0)
end

return M
