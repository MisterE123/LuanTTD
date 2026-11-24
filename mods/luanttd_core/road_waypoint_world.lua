-- A waypoint owns a facility, not the street under it or a cargo queue.
return function(Sim,Terrain,Stock,Underlay,rules)
  local W={}
  local function span(ids,other)
    local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
    local function add(id)
      local x,z=Sim.xy(id)
      x0,z0,x1,z1=math.min(x0,x),math.min(z0,z),math.max(x1,x),math.max(z1,z)
    end
    for _,id in ipairs(ids) do add(id) end
    for id in pairs(other or {}) do add(id) end
    return {tile=Sim.id(x0,z0),w=x1-x0+1,h=z1-z0+1}
  end
  local function road_axis(s,id)
    local bits=Sim.road_bits(s,id)
    return (bits==10 and 0) or (bits==5 and 1) or nil
  end
  function W.quote(s,owner,req)
    local company=s.companies[owner]
    if not company or not s.corner_grid then return nil,"PARAMETERS" end
    local groups=s.stock_road_waypoints or {}
    local ground=rules.ground(s)
    if not ground then return nil,"OCCUPANCY_UNKNOWN" end
    local policy=s.stock_road_town_policy or {}
    local limit=12
    local board={xy=Sim.xy,id=Sim.id}
    function board.tile(id)
      local t=s.tiles[id]
      if not t or t.stock_void or t.build~="road" or t.level_crossing or t.road_bridge_id or t.road_tunnel_id or
          t.tram or t.station or t.roadworks then return nil end
      local x,z=Sim.xy(id)
      local slope,base,top=Terrain.tile(s.corner_grid,x,z)
      local mark=t.road_waypoint_id and groups[t.road_waypoint_id]
      local above,deck=rules.bridge(s,id)
      local bridge_forbidden=above and not deck
      if deck then
        local axis=mark and road_axis(s,id) or Stock.axis({kind="road",road={bits=Sim.road_bits(s,id)}}) or req.axis
        bridge_forbidden=not Underlay.quote({kind="station",station_type="road_waypoint",layout=4+(axis or 0),max_z=top},0,deck)
      end
      return {kind=mark and "station" or "road",station=mark and mark.id,axis=mark and road_axis(s,id),
        stop_type=mark and "road_waypoint",through=mark~=nil,slope=slope,base=base,
        occupied=ground[id]==true,bridge_forbidden=bridge_forbidden,
        road={bits=Sim.road_bits(s,id),roadtype=t.roadtype or 0,owner=t.road_town and "town" or t.owner,
          disallowed=t.road_disallowed or t.disallowed}}
    end
    if req.remove then
      local x,z=Sim.xy(req.first)
      local u,v=Sim.xy(req.last)
      if math.abs(x-u)+math.abs(z-v)>=128 then return nil,"PARAMETERS" end
      local changes,priced,affected={},0,{}
      for zz=math.min(z,v),math.max(z,v) do for xx=math.min(x,u),math.max(x,u) do
        local id=Sim.id(xx,zz)
        local t=s.tiles[id]
        local mark=t and groups[t.road_waypoint_id]
        if mark and mark.owner==owner and not ground[id] then
          local bits=Sim.road_bits(s,id)
          changes[#changes+1]={id=id,waypoint=mark.id,road_bits=bits,build="road",tool="road_waypoint_remove"}
          affected[mark.id]=(affected[mark.id] or 0)+1
          priced=priced+50
        end
      end end
      if #changes==0 then return nil,"NO_CLEAR_WAYPOINT" end
      for id,chosen in pairs(affected) do
        for _,v in pairs(s.fleet) do
          for _,pending in ipairs(v.road_via_pending or {}) do
            if pending==id then return nil,"WAYPOINT_IN_USE" end
          end
        end
        local count=0
        for _ in pairs(groups[id].tiles) do count=count+1 end
        if count==chosen then
          for _,v in pairs(s.fleet) do
            for _,order in ipairs(v.orders or {}) do
              if order.station=="waypoint:"..id then return nil,"WAYPOINT_IN_ORDERS" end
            end
          end
        end
      end
      if priced>company.cash then return nil,"NOT_ENOUGH_CASH" end
      return {cost=priced,changes=changes,road_waypoint=true}
    end
    local direction=Stock.axis(board.tile(req.first))
    if direction==nil then return nil,"NO_VALID_ROAD_WAYPOINT_AXIS" end
    if req.axis~=nil and req.axis~=direction then return nil,"PARAMETERS" end
    local x,z=Sim.xy(req.first)
    local u,v=Sim.xy(req.last)
    local last=direction==0 and Sim.id(x,v) or Sim.id(u,z)
    local q,why=Stock.quote(board,req.first,last,direction,{company=owner,limit=limit,
      on_town_road=policy.stop_on_town_road,build_on_slopes=policy.build_on_slopes,
      piece_price=function()return 95 end})
    if not q then return nil,why end
    local picked=q.existing
    if picked and req.separate and picked~=req.join then return nil,"MUST_REMOVE_ROAD_STOP_FIRST" end
    if req.join and picked and req.join~=picked then return nil,"ADJOINS_MULTIPLE_WAYPOINTS" end
    if req.join then
      if not groups[req.join] and not Sim.road_station_retirement().get(s,"waypoint",req.join) then return nil,"NO_CLEAR_WAYPOINT" end
      picked=req.join
    elseif not picked and not req.separate then
      local seen={}
      for _,id in ipairs(q.ids) do
        local x,z=Sim.xy(id)
        for dz=-1,1 do for dx=-1,1 do
          local n=Sim.id(x+dx,z+dz)
          local t=n and s.tiles[n]
          local adjacent=t and groups[t.road_waypoint_id]
          if adjacent and adjacent.owner==owner then seen[t.road_waypoint_id]=true end
        end end
      end
      for id in pairs(seen) do
        if picked then return nil,"ADJOINS_MULTIPLE_WAYPOINTS" end
        picked=id
      end
    end
    if not picked and not req.separate and not req.join then
      local x,z=Sim.xy(q.ids[1])
      local shift=math.floor(#q.ids/2)
      local middle=direction==0 and Sim.id(x,z+shift) or Sim.id(x+shift,z)
      local retired=Sim.road_station_retirement().closest(s,"waypoint",owner,middle)
      if retired then picked=retired.id end
    end
    local existing=picked and (groups[picked] or Sim.road_station_retirement().get(s,"waypoint",picked))
    if existing and existing.owner~=owner then return nil,"OWNED_BY" end
    local extent=span(q.ids,existing and existing.tiles)
    if math.max(extent.w,extent.h)>limit then return nil,"STATION_SPREAD" end
    if q.cost>company.cash then return nil,"NOT_ENOUGH_CASH" end
    local id=picked or s.next_stock_road_waypoint or 1
    local edits={}
    for _,row in ipairs(q.changes) do
      if row.station~=id then
        edits[#edits+1]={id=row.id,waypoint=id,road_bits=direction==0 and 10 or 5,road_terminal_level=row.z,
          build="road",tool="road_waypoint",foundation=direction}
      end
    end
    if #edits==0 then return nil,"ALREADY_BUILT" end
    return {cost=q.cost,changes=edits,road_waypoint=true,id=id,axis=direction,area=extent,picker_area=span(q.ids)}
  end
  function W.apply(s,owner,q)
    s.stock_road_waypoints=s.stock_road_waypoints or {}
    local all=s.stock_road_waypoints
    local edited={}
    if q.id then
      local mark=all[q.id]
      if not mark then
        mark=Sim.road_station_retirement().take(s,"waypoint",q.id)
        if mark then mark.tile=q.picker_area.tile
        else
          s.next_stock_road_waypoint=q.id+1
          mark={id=q.id,owner=owner,tile=q.changes[1].id,tiles={},name="Road waypoint #"..q.id}
        end
        all[q.id]=mark
      end
      mark.area=q.area
      for _,row in ipairs(q.changes) do
        local t=s.tiles[row.id]
        t.road_waypoint_id,t.road_bits,t.road_terminal_level=row.waypoint,row.road_bits,row.road_terminal_level
        t.road_disallowed,t.disallowed=nil,nil
        mark.tiles[row.id]=true
        edited[#edited+1]=row.id
      end
    else
      local groups={}
      for _,row in ipairs(q.changes) do
        local t=s.tiles[row.id]
        local mark=assert(all[row.waypoint])
        t.road_waypoint_id,t.road_terminal_level=nil,nil
        mark.tiles[row.id]=nil
        groups[mark.id]=true
        edited[#edited+1]=row.id
      end
      for id in pairs(groups) do
        local mark=all[id]
        if not next(mark.tiles) then
          mark.area=nil
          Sim.road_station_retirement().retire(s,"waypoint",mark)
          all[id]=nil
        else
          mark.area=span({},mark.tiles)
          if not mark.tiles[mark.tile] then
            local chosen
            for tile in pairs(mark.tiles) do if not chosen or tile<chosen then chosen=tile end end
            mark.tile=chosen
          end
        end
      end
    end
    return edited
  end
  return W
end
