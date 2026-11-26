-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 src/town_cmd.cpp:
-- CanRoadContinueIntoNextTile, GrowTownWithBridge and GrowTownWithTunnel.
return function(G)
local S={}
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local slope={[0]=12,6,3,9}
local bits={[0]=8,4,2,1}
local function rev(d) return (d+2)%4 end
local function has(value,bit) return math.floor(value/bit)%2==1 end
local function overlaps(a,b)
  for _,bit in pairs(bits) do if has(a,bit) and has(b,bit) then return true end end
  return false
end
local function valid(t) return t and t.kind~="void" end
function S.continues(town,board,x,z,d)
  local u,v=x+dx[d],z+dz[d]
  local t=board.tile(u,v)
  if not valid(t) then return false end
  if t.kind=="bridge" or t.kind=="tunnel" then return t.inside==d end
  if t.kind=="drive_stop" then return t.axis==d%2 end
  if t.kind=="bay_stop" then return t.entrance==rev(d) end
  if t.kind=="station" or t.kind=="rail_bridge" or t.kind=="rail_tunnel" then return false end
  if t.kind=="depot" then return t.entrance==rev(d) end
  if t.kind=="road" then return false end -- Cmd looks only for a depot on MP_ROAD.
  if t.kind=="rail" and not board.town_level_crossings then return false end
  return not not board.road_quote(town,u,v,bits[rev(d)])
end
local function approach(board,x,z,d)
  local t=board.tile(x-dx[d],z-dz[d])
  return valid(t) and has(t.road_bits or 0,bits[d])
end
function S.bridge(town,board,x,z,d,random)
  local t=board.tile(x,z)
  if not valid(t) or overlaps(t.slope,slope[d]) or not approach(board,x,z,d) then return end
  local u,v,landing=x,z
  local max=t.slope==0 and 5 or math.min(11,math.floor(town.population/1000)+5)
  for n=1,max do
    u,v=u+dx[d],v+dz[d]
    local q=board.tile(u,v)
    if not valid(q) then return end
    local crosses=q.kind=="water" and not q.coast and not q.water_rocks and (t.slope~=0 or not q.sea)
      or q.kind=="rail" or (q.kind=="road" and (q.road_disallowed or 0)~=0)
    if not crosses then landing=n;break end
  end
  if not landing or landing==1 or not S.continues(town,board,u,v,d) then return end
  if t.slope~=0 and board.parallel_bridge(x,z,landing,slope[rev(d)]) then return end
  for _=0,22 do
    local style=G.range(12,random()) -- RandomRange(MAX_BRIDGES - 1), not 13.
    local quote=board.bridge_quote(town,x,z,u,v,style)
    if quote then return {kind="bridge",town=town.id,x=x,z=z,u=u,v=v,style=style,quote=quote} end
  end
end
function S.tunnel(town,board,x,z,d)
  local t=board.tile(x,z)
  if not valid(t) or t.slope~=slope[d] or not approach(board,x,z,d) then return end
  local max=5
  if S.continues(town,board,x,z,d) then
    for i=0,3 do
      local q=board.tile(x+dx[d]*i,z+dz[d]*i)
      if not valid(q) then return end
      local m=q.slope
      if m~=slope[d] and m<16 and m~=1 and m~=2 and m~=4 and m~=8 then return end
    end
    max=math.floor(town.population/1000)+7
  end
  for n=1,max do
    local u,v=x+dx[d]*n,z+dz[d]*n
    local q=board.tile(u,v)
    if not valid(q) then return end
    if q.base==t.base then
      if n==1 or not S.continues(town,board,u,v,d) then return end
      local quote=board.tunnel_quote(town,x,z,u,v)
      if quote then return {kind="tunnel",town=town.id,x=x,z=z,u=u,v=v,quote=quote} end
      return
    end
  end
end
return S
end
