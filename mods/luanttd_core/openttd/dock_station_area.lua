-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, station_cmd.cpp: CmdBuildDock / GetStationAround /
-- FindJoiningBaseStation; pathfinder_func.h: CalcClosestStationTile.
-- Mode-specific board: the caller supplies station identity at a tile.
local D={}
local min,max=math.min,math.max
local offsets={{-1,0,2,1},{0,0,1,2},{0,0,2,1},{0,-1,1,2}}
function D.search_area(board,land,dir)
  local x,z=board.xy(land)
  local d=offsets[dir+1]
  return {tile=board.id(x+d[1],z+d[2]),w=d[3],h=d[4]}
end
function D.union(board,a,b)
  if not a or not b then return a or b end
  local x,z=board.xy(a.tile)
  local u,v=board.xy(b.tile)
  local l,t=min(x,u),min(z,v)
  return {tile=board.id(l,t),w=max(x+a.w,u+b.w)-l,h=max(z+a.h,v+b.h)-t}
end
function D.join(board,area,owner,req,spread,distant)
  local st
  if req.join~=nil and (not distant or not board.station(req.join)) then
    return nil,"INVALID_STATION_TO_JOIN"
  end
  if not req.adjacent then
    local x,z=board.xy(area.tile)
    for v=z-1,z+area.h do
      for u=x-1,x+area.w do
        local tile=board.id(u,v)
        local near=tile and board.station_at(tile)
        if near and near.owner==owner then
          if st and near.id~=st.id then return nil,"ADJOINS_MULTIPLE_STATIONS" end
          st=near
        end
      end
    end
  end
  st=st or req.join~=nil and board.station(req.join) or nil
  if st and st.owner~=owner then return nil,"OWNED_BY" end
  local extent=D.union(board,st and st.spread,area)
  if max(extent.w,extent.h)>spread then return nil,"STATION_SPREAD" end
  return {id=st and st.id,spread=extent}
end
function D.closest_tile(board,area,origin)
  local x,z=board.xy(area.tile)
  local u,v=board.xy(origin)
  return board.id(min(x+area.w-1,max(u,x)),min(z+area.h-1,max(v,z)))
end
return D
