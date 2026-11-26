-- Native map adapter: station identity is not the particular pier used to
-- build, load, or delete it. Geometry remains on each individual tile.
local M={}
function M.pairs(st)
  return st and (st.docks or st.land and st.water and {st}) or {}
end
function M.each_tile(st,emit)
  for _,p in ipairs(M.pairs(st)) do emit(p.land);emit(p.water) end
end
function M.footprint(st,xy)
  local tiles,rev={},{}
  M.each_tile(st,function(id)
    local x,z=xy(id)
    tiles[#tiles+1]={x=x-1,y=z-1,kind="dock"}
    rev[#rev+1]=id
  end)
  return tiles,table.concat(rev,":")
end
return M
