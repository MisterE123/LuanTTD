-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 tunnelbridge_cmd.cpp CmdBuildTunnel. Shares the existing
-- tunnel price recurrence and InclinedSlopeDirection kernel.
-- Underground ownership/clearance and authorized landscape quote are
-- passed in from the host; this module never mutates tiles or money.
return function(Tunnel,Quote,Site,Track)
  local T={default_max_length=64}
  local floor=math.floor
  local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  local water={water=true,coast=true,river=true,sea=true,canal=true}
  local function water_ground(board,id,record)
    if board.has_water_ground then return board.has_water_ground(id,record) end
    if record.water_ground~=nil then return record.water_ground end
    return record.water or water[record.kind]
  end

  -- The width is intentional in BOTH branches (Map::MaxX). Positions
  -- here are stock zero-origin tile x/y for the crossing-probe decision.
  function T.probe_direction(d,x,z,max_x)
    local half=floor(max_x/2)
    if d%2==1 then return x<half and 2 or 0 end
    return z<half and 1 or 3
  end

  -- Stock tests every interior before enforcing the max length, and
  -- stops scanning at the FIRST same-base tile, regardless of exit slope.
  -- board.tunnel_in_way(id,base,probe_direction) is required if there is
  -- underground infrastructure to inspect; omitted means an empty index.
  -- board.max_x = Map::MaxX(), or provide opts.max_map_x. A preindexed
  -- board can ignore the direction parameter when occupancy is exact.
  -- terraform_quote(id,mask,false,already_cleared) returns an object with
  -- cost and a persistable/applicable host terrain plan, optional slope.
  function T.plan(board,start,opts)
    opts=opts or {}
    local rt=Site.railtype(opts)
    if not rt then return nil,"INVALID_RAILTYPE" end
    local a=start~=nil and board.tile(start)
    local dir=a and Tunnel.direction(a.slope)
    if dir==nil then return nil,"UNSUITABLE_TUNNEL_ENTRANCE" end
    if water_ground(board,start,a) then return nil,"CANT_BUILD_ON_WATER" end
    local start_price,error_word=Site.clear(board,start,a,"entrance",opts)
    if start_price==nil then return nil,error_word end
    local x,z=board.xy(start)
    local mx=opts.max_map_x or board.max_x
    local probe=mx and T.probe_direction(dir,x,z,mx)
    local middle,set={},{}
    local finish,b
    while true do
      x,z=x+dx[dir],z+dz[dir]
      finish=Site.id(board,x,z)
      b=finish~=nil and board.tile(finish)
      if not b then return nil,"TUNNEL_THROUGH_MAP_BORDER" end
      if b.base==a.base then break end
      if not opts.crossing_tunnels and board.tunnel_in_way and board.tunnel_in_way(finish,a.base,probe) then
        return nil,"ANOTHER_TUNNEL_IN_THE_WAY"
      end
      middle[#middle+1]=finish;set[finish]=true
    end
    if #middle>(opts.max_length or T.default_max_length) then return nil,"TUNNEL_TOO_LONG",finish end
    if water_ground(board,finish,b) then return nil,"CANT_BUILD_ON_WATER",finish end
    local exit_price,underlying=Site.clear(board,finish,b,"exit",opts)
    if exit_price==nil then return nil,"UNABLE_TO_EXCAVATE_LAND",finish,underlying end
    local mask=0
    local excavation
    if b.slope~=15-a.slope then
      mask=Track.intersect(b.slope,a.slope)
      if mask==0 then
        -- CmdTerraformLand with no selected corners succeeds at cost 0
        -- and CmdBuildTunnel does not re-test complementary slopes.
        excavation={cost=0,noop=true,slope=b.slope}
      else
        local reason
        if board.terraform_quote then
          excavation,reason=board.terraform_quote(finish,mask,false,{[start]=true,[finish]=true})
        else reason="TERRAIN_PLAN_REQUIRED" end
        if not excavation then return nil,"UNABLE_TO_EXCAVATE_LAND",finish,reason end
      end
    end
    local unit=Site.price(opts,"tunnel",450)
    local length=#middle+2
    local plan={kind="tunnel",transport="rail",railtype=rt,start=start,["end"]=finish,base=a.base,
      owner=opts.owner,axis=dir%2,middle=middle,middle_by_tile=set,middle_length=#middle,total_length=length,
      excavation_mask=mask,excavation=excavation,
      head={id=start,inside_direction=dir,base=a.base,slope=a.slope},
      tail={id=finish,inside_direction=(dir+2)%4,base=a.base,slope=excavation and excavation.slope or b.slope},
      structure_cost=Tunnel.construction_cost(#middle,0,0,unit,0),rail_cost=Quote.rail_price(rt,opts)*length,
      clear_cost=start_price+exit_price,excavation_cost=excavation and excavation.cost or 0,
      clears={start,finish},infrastructure_delta=opts.company==false and 0 or length*Site.TRACKBIT_FACTOR}
    Site.portal(plan.head,plan,finish,"tunnel",plan.head.inside_direction)
    Site.portal(plan.tail,plan,start,"tunnel",plan.tail.inside_direction)
    plan.price=plan.structure_cost+plan.rail_cost+plan.clear_cost+plan.excavation_cost
    if not opts.query and opts.budget and plan.price>opts.budget then return nil,"NOT_ENOUGH_CASH",finish end
    return plan
  end
  function T.pixel(plan,id)
    if plan.start==id or plan["end"]==id or plan.middle_by_tile[id] then return plan.base*8 end
  end
  return T
end
