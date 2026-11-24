-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: station_gui.cpp FindStationsNearby,
-- AddNearbyStation; tilearea_spiral.cpp SpiralTileIterator.
local M={}
local dx,dz={-1,0,1,0},{0,1,0,-1}
local min,max=math.min,math.max

-- The supplied rectangle is in source map coordinates. Walking each
-- edge starting from its west corner reproduces the GUI's list order.
function M.spiral(board,area,radius,visit)
  local x,z=board.xy(area.tile)
  local u,v=x+area.w,z-1
  for r=0,radius-1 do
    for d=1,4 do
      local extent=d%2==1 and area.w or area.h
      for _=1,extent+2*r+1 do
        local tile=board.id(u,v)
        if tile then visit(tile) end
        u,v=u+dx[d],v+dz[d]
      end
    end
    u,v=u+1,v-1
  end
end
function M.within_spread(board,area,old,spread)
  if not old then return true end
  local x,z=board.xy(area.tile)
  local u,v=board.xy(old.tile)
  return max(x+area.w,u+old.w)-min(x,u)<=spread and
    max(z+area.h,v+old.h)-min(z,v)<=spread
end
function M.find(board,area,owner,spread,distant)
  local x,z=board.xy(area.tile)
  local last_x,last_z=x+area.w-1,z+area.h-1
  local rows,seen,deleted={{new=true}},{},{}
  local function include(st)
    rows[#rows+1]=st
    seen[st.id]=true
  end
  local function chebyshev(u,v,a,b) return max(math.abs(u-a),math.abs(v-b)) end
  for _,st in ipairs(board.deleted or {}) do
    if st.owner==owner and board.matches(st) then
      local u,v=board.xy(st.tile)
      if max(chebyshev(u,v,x,z),chebyshev(u,v,last_x,last_z))<spread then
        local list=deleted[st.tile] or {}
        list[#list+1]=st
        deleted[st.tile]=list
      end
    end
  end
  local function scan(tile)
    if deleted[tile] then
      for _,st in ipairs(deleted[tile]) do if not seen[st.id] then include(st) end end
      deleted[tile]=nil
    end
    local st=board.station_at(tile)
    if st and st.owner==owner and not seen[st.id] and board.matches(st) and
        M.within_spread(board,area,st.spread,spread) then include(st) end
  end
  for v=z,last_z do
    for u=x,last_x do scan(assert(board.id(u,v))) end
  end
  local radius=distant and (spread-min(area.w,area.h)) or 1
  if radius>0 then M.spiral(board,area,radius,scan) end
  return rows
end
return M
