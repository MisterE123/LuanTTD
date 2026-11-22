-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 CmdBuildTunnel, tunnelbridge_cmd.cpp; slope_func.h
-- GetInclinedSlopeDirection; pricebase.h PR_BUILD_TUNNEL. This port handles
-- ordinary paired road portals with already complementary slopes. The
-- stock fallback can excavate the exit; the host currently refuses it.
local M={}
local direction={[12]=0,[6]=1,[3]=2,[9]=3}
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local floor=math.floor
function M.direction(slope) return direction[slope] end
function M.construction_cost(middle,entrance,exit,price,road_half)
  local cost,next_bump,coef=0,25,3
  for n=1,middle do
    if n==next_bump then coef,next_bump=coef+1,next_bump*2 end
    cost=cost+price
    cost=cost+floor(cost/2^coef)
  end
  return cost+2*price+entrance+exit+(middle+2)*road_half*2
end
function M.plan(board,start,opts)
  opts=opts or {}
  local a=board.tile(start)
  if not a or not direction[a.slope] or a.water then return nil,"UNSUITABLE_TUNNEL_ENTRANCE" end
  local entrance=board.clear(start)
  if not entrance then return nil,"TUNNEL_ENTRANCE_NOT_CLEAR" end
  local d=direction[a.slope]
  local x,z=board.xy(start)
  local inner,set={},{}
  local target,b
  while true do
    x,z=x+dx[d],z+dz[d]
    target=board.id(x,z)
    b=target and board.tile(target)
    if not b then return nil,"TUNNEL_THROUGH_MAP_BORDER" end
    if b.base==a.base then break end
    if board.blocked and board.blocked(target,a.base) then return nil,"ANOTHER_TUNNEL_IN_THE_WAY" end
    inner[#inner+1],set[target]=target,true
  end
  if #inner>(opts.max_length or 64) then return nil,"TUNNEL_TOO_LONG",target end
  if b.water then return nil,"TUNNEL_EXIT_ON_WATER",target end
  local exit=board.clear(target)
  if not exit then return nil,"TUNNEL_EXIT_NOT_CLEAR",target end
  if b.slope~=15-a.slope then return nil,"TUNNEL_EXIT_NEEDS_OPPOSITE_SLOPE",target end
  local cost=M.construction_cost(#inner,entrance,exit,opts.price or 450,opts.road_half or 95)
  if opts.budget and cost>opts.budget then return nil,"NOT_ENOUGH_CASH",target end
  return {start=start,["end"]=target,base=a.base,middle=inner,middle_by_tile=set,middle_length=#inner,
    head={id=start,inside_direction=d},tail={id=target,inside_direction=(d+2)%4},price=cost,owner=opts.owner,
    roadtype=0}
end
return M
