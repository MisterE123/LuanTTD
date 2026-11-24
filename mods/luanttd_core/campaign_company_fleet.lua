-- A company-scoped vehicle directory; records never include routes, other
-- companies, or renderer state. Depot purchases can be edited while parked.
return function(Sim,R)
  local S=R.world
  local C={}
  local function row(kind,id,v,owner,label,depot,depot_key)
    if not v or v.owner~=owner then return end
    return {mode=kind,id=id,owner=owner,label=label,depot=depot,depot_key=depot_key or depot}
  end
  function C.vehicle(n,mode,id)
    if mode=="road" then
      local v=S.fleet[id]
      if not v then return end
      return row(mode,id,v,n,v.name,v.home_depot or v.depot)
    elseif mode=="rail" and R.rail and R.rail.owned then
      local v=R.rail.owned.get(S,n,id)
      if not v then return end
      return row(mode,id,v,n,"Train "..v.unit_number,v.depot)
    elseif mode=="ship" and id=="oil" and R.water and R.water.tanker then
      local v=R.water.tanker.status(S)
      local depot=v and S.stock_ship_depots and S.stock_ship_depots[v.depot]
      if v then return row(mode,id,v,n,v.name,depot and depot.tiles[1],v.depot) end
    elseif mode=="ship" and (id=="ferry" or id=="coal") then
      local v=id=="ferry" and S.stock_owned_ferry or id=="coal" and S.stock_coal_ship
      if not v then return end
      local depot=S.stock_ship_depots and S.stock_ship_depots[v.depot]
      return row(mode,id,v,n,id=="coal" and (v.engine==212 and "Bakewell Cargo Ship" or "Yate Cargo Ship") or v.engine_id==208 and "Bakewell 300 Hovercraft" or v.engine_id==207 and
        "FFP Passenger Ferry" or "MPS Passenger Ferry",depot and depot.tiles[1],v.depot)
    elseif mode=="air" then
      local v=(S.stock_owned_air_fleet or {})[id] or id==1 and S.stock_owned_aircraft
      if not v then return end
      local field=S.stock_small_airports and S.stock_small_airports[v.hangar]
      return row(mode,id,v,n,(v.name or "Aircraft").." #"..id,field and field.origin,v.hangar)
    elseif mode=="tram" then
      local service=R.tram and R.tram.run
      local v=service and service.by_ui and service.by_ui(S,id) or id==1 and S.tram_pilot
      local label=v and v.carrier and "Streetcar #"..v.carrier.id or "Test streetcar"
      local out=row(mode,id,v,n,label,v and (v.depot or v.legs and v.legs[1] and v.legs[1].source))
      if out and service and service.retirement_key then out.retirement=service.retirement_key(v) end
      return out
    end
  end
  function C.locate(n,mode,id)
    local v=C.vehicle(n,mode,id)
    if not v then return end
    local p,away
    if mode=="road" then
      local unit=S.fleet[id]
      p=R.road_pose(unit,1)
      away=unit.running or unit.route
    elseif mode=="rail" then
      local state=R.rail.run.current(S)
      for _,run in ipairs(state and state.runs or {}) do
        if run.owner==n and run.fleet_id==id then
          away=true
          for _,body in ipairs(R.rail.poses(run,1)) do
            if body.index==1 then p=body.pos;break end
          end
          break
        end
      end
    elseif mode=="ship" and R.water then
      local w=R.water
      if id=="ferry" then
        local run=w.run.current(S)
        away=run and run.owner==n
        if away then
          if run.paid_clock then p=Sim.ferry_paid_pose(S,1) else p=w.run.pose(run) end
        end
      elseif id=="oil" and w.tanker then
        local q=w.tanker.status(S)
        away=q and q.first~=nil
        if away then p=w.tanker.pose(S,1) end
      elseif w.freight and w.coal then
        local run=w.freight.current(S)
        away=run and run.owner==n
        if away then p=w.coal.pose(S,1) end
      end
    elseif mode=="air" and R.air then
      for _,run in ipairs(R.air.run.all(S)) do
        if run.owner==n and (run.paid_clock or 1)==id then
          away=true
          if run.paid_clock then p=Sim.air_paid_pose(S,1,run.paid_clock) else p=R.air.run.pose(run) end
          break
        end
      end
    elseif mode=="tram" and R.tram then
      local service=R.tram.run
      local run=service.by_ui and service.by_ui(S,id) or id==1 and service.current(S)
      local frame=run and R.tram.run.frame(run)
      away=run and run.phase~="depot"
      if frame then p=R.tram.pose(frame) end
    end
    if not p and not away and v.depot then
      local x,z=Sim.xy(v.depot)
      local _,h=R.terrain.tile(S.corner_grid,x,z)
      if h then p={x=2*x+.5,y=h+.75,z=2*z+.5} end
    end
    if p then return {x=p.x,y=p.y,z=p.z} end
  end
  function C.page(n,page,filter)
    local rows={}
    local function add(mode,id)
      if filter and mode~=filter then return end
      local r=C.vehicle(n,mode,id)
      if r then rows[#rows+1]=r end
    end
    if not filter then
      for id in pairs(S.fleet) do add("road",id) end
      if R.rail and R.rail.owned then
        for _,v in ipairs(R.rail.owned.list(S,n)) do add("rail",v.id) end
      end
      for id in pairs(S.stock_owned_air_fleet or {}) do add("air",id) end
      if S.stock_owned_aircraft and not (S.stock_owned_air_fleet or {})[1] then add("air",1) end
      add("ship","ferry");add("ship","coal");add("ship","oil")
    end
    add("tram",1)
    for id in pairs(S.stock_tram_fleet or {}) do add("tram",id) end
    table.sort(rows,function(a,b) return a.mode==b.mode and a.id<b.id or a.mode<b.mode end)
    local count=math.max(1,math.ceil(#rows/20))
    page=math.min(page,count)
    local out={records={},page=page,pages=count,total=#rows}
    for i=1+(page-1)*20,math.min(#rows,page*20) do out.records[#out.records+1]=rows[i] end
    return out
  end
  return C
end
