-- Shared with the 128×256 layout in build_rail_split_atlas.py.
-- One 32px period per Luanti node (a logical tile is two nodes wide).
local M={}
function M.top(u,v)
  return .02+.96*u,.54+.42*(1-v)
end
function M.wall(a,b,point,height)
  -- Perimeter orientation follows Luanti's solid cube: +X on -Z,
  -- +Z on +X, -X on +Z and -Z on -X. The same projection also keeps
  -- the actual world-space scale on the inner diagonal risers.
  local du,dv=b[1]-a[1],b[2]-a[2]
  local length=math.sqrt(du*du+dv*dv)
  assert(length>0)
  local along=(du*(point[1]-a[1])+dv*(point[2]-a[2]))/length
  return .25+.5*along,.125+.125*height
end
return M
