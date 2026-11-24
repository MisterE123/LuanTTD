-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Host adapter for 16.0-RC1 road_cmd.cpp:
-- CmdBuildRoad and RemoveRoad, TileType::TunnelBridge branches. Both
-- portals share one authoritative span in this host. The elevated
-- layer never takes over the ground tiles below it.
return function(Sim, Terrain, Construction, Bridge)
  local M={}
  local ELRL=1
  local outward={[0]=2,1,8,4}
  local axis={[0]=10,5}

  -- Cross-check both ends before quoting or changing the shared record.
  function M.get(s,id)
    local tile=id and s.tiles[id]
    if not tile then return end
    local kind,key,pool,field
    if tile.road_bridge_id then
      kind,key,pool,field="bridge",tile.road_bridge_id,s.stock_road_bridges,"road_bridge_id"
    elseif tile.road_tunnel_id then
      kind,key,pool,field="tunnel",tile.road_tunnel_id,s.stock_road_tunnels,"road_tunnel_id"
    end
    local plan=pool and pool[key]
    if not plan or type(plan.middle)~="table" or not s.corner_grid then return end
    local a,b=plan.start,plan["end"]
    local head,tail=plan.head,plan.tail
    local h=id==a and head or id==b and tail
    local dir=h and h.inside_direction
    if not outward[dir] or not s.tiles[a] or not s.tiles[b] or
        s.tiles[a][field]~=key or s.tiles[b][field]~=key or a==b or
        not head or not tail or not outward[head.inside_direction] or
        head.id~=a or tail.id~=b or (head.inside_direction+2)%4~=tail.inside_direction then return end
    local x,z=Sim.xy(id)
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    if slope==nil then return end
    return {id=id,slope=slope,base=base,kind=kind,key=key,transport="road",plan=plan,other=id==a and b or a,
      dir=dir,outer=outward[dir],axis=axis[dir%2],skip=#plan.middle,
      span=kind=="bridge" and key or nil,tunnel=kind=="tunnel" and key or nil,
      owner=plan.owner,roadtype=plan.roadtype,road_owner=plan.road_owner or plan.owner,
      tramtype=plan.tramtype,tram_owner=plan.tram_owner,bridge_speed=plan.spec and plan.spec.speed}
  end

  local function dirty(t)
    local out={t.id,t.other}
    if t.kind=="bridge" then
      for _,id in ipairs(t.plan.middle) do out[#out+1]=id end
    end
    return out
  end

  -- busy(a,b,plan) represents TunnelBridgeIsFree: a stock vehicle inside
  -- the wormhole remains in an endpoint's vehicle bucket. Native positions
  -- on the map below an overpass must not block works on its deck.
  function M.quote(s,owner,id,requested,action,busy)
    local t=M.get(s,id)
    if not t or type(busy)~="function" or type(owner)~="string" or
        type(requested)~="number" or requested%1~=0 or requested<1 or requested>15 then
      return nil,"INVALID_PARAMETER"
    end
    local cost
    if action=="lay" then
      if requested~=t.outer then return nil,"OUTSIDE_PORTAL_BIT_REQUIRED" end
      if t.tramtype~=nil then return nil,"ALREADY_BUILT" end
      t.span_occupied=busy(t.id,t.other,t.plan)
      local policy=s.stock_road_town_policy or {}
      local p,why=Construction.lay(t,requested,ELRL,{owner=owner,
        build_on_slopes=policy.build_on_slopes~=false})
      if not p then return nil,why end
      cost=p.cost
    elseif action=="remove" then
      if t.tramtype==nil then return nil,"NO_TRAMWAY" end
      if busy(t.id,t.other,t.plan,true) then return nil,"VEHICLE_IN_THE_WAY" end
      if t.tram_owner~=owner and t.tram_owner~="none" then return nil,"OWNED_BY_ANOTHER" end
      if t.roadtype==nil then return nil,"LAST_LAYER_REQUIRES_DEMOLITION" end
      local low=t.axis/5
      if math.floor(requested/low)%2==0 and math.floor(requested/(4*low))%2==0 then
        return nil,"NO_TRAMWAY"
      end
      cost=2*(t.skip+2)*Bridge.road_clear_cost(t.tramtype)
    else return nil,"INVALID_PARAMETER" end
    local c=s.companies[owner]
    if not c or c.cash<cost then return nil,"NOT_ENOUGH_MONEY" end
    return {id=id,other=t.other,key=t.key,kind=t.kind,owner=owner,cost=cost,action=action,
      requested=requested,geometry=s.topology,dirty=dirty(t)}
  end

  function M.apply(s,owner,q,busy)
    if not q or q.owner~=owner or q.geometry~=s.topology then return nil,"STALE_SPAN_QUOTE" end
    local fresh,why=M.quote(s,owner,q.id,q.requested,q.action,busy)
    if not fresh then return nil,why end
    if fresh.other~=q.other or fresh.kind~=q.kind or fresh.key~=q.key or fresh.cost~=q.cost then
      return nil,"STALE_SPAN_QUOTE"
    end
    local t=M.get(s,q.id)
    if q.action=="lay" then
      t.plan.tramtype,t.plan.tram_owner=ELRL,owner
      -- Tunnels built with only one way historically leave road_owner
      -- implicit; make it explicit before any change of structure owner.
      t.plan.road_owner=t.road_owner
    else
      t.plan.tramtype,t.plan.tram_owner=nil,nil
      if t.owner~="town" and t.owner~=t.road_owner then
        t.plan.owner=t.road_owner
        s.tiles[t.id].owner,s.tiles[t.other].owner=t.road_owner,t.road_owner
      end
    end
    local c=s.companies[owner]
    c.cash,c.expense,c.month_exp=c.cash-fresh.cost,c.expense+fresh.cost,c.month_exp+fresh.cost
    s.topology=s.topology+1
    return fresh.dirty,fresh.cost
  end
  return M
end
