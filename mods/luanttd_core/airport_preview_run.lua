-- One fixed-wing trimotor alternating two true 4x3 airfields.
-- Taxi, runway block, holding and flight math remain source-port code.
return function(Sim,Network,Small,Motion,Terrain,Slope,Roster)
  local source=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/openttd/"
  local O=dofile(source.."rail_order_list.lua")
  local R={VERSION=1,DWELL_TICKS=74,engine={id=215,visual="bayshore_trimotor",
    passengers=25,mail=4,acceleration=18,max_speed=473}} -- (37 * 128) / 10
  function R.all(s)
    local runs={}
    local p=s.airport_pilot
    if p and p.version==R.VERSION then runs[1]=p end
    for _,f in pairs(s.airport_owned_runs or {}) do
      if f.version==R.VERSION then runs[#runs+1]=f end
    end
    table.sort(runs,function(a,b) return (a.paid_clock or 0)<(b.paid_clock or 0) end)
    return runs
  end
  function R.gather(s)
    local runs=R.all(s)
    if runs[1] and not runs[1].paid_clock then table.remove(runs,1) end
    return runs
  end
  function R.current(s,paid_clock)
    local p=s.airport_pilot
    if p and p.version==R.VERSION and (not paid_clock or p.paid_clock==paid_clock) then return p end
    if paid_clock then
      local f=(s.airport_owned_runs or {})[paid_clock]
      if f and f.version==R.VERSION then return f end
      return nil
    end
    return R.all(s)[1]
  end
  function R.engine_for(p)
    if p.engine_id then
      return assert(Roster and Roster.entry(p.engine_id),"Unknown saved aircraft")
    end
    return R.engine
  end
  function R.fits(field,engine)
    if not field or not (Network.layout and Network.layout(field.layout) or not field.layout) then
      return false
    end
    local design=engine and Roster and Roster.entry(engine)
    return not (design and design.small==false) or field.layout=="city"
  end
  local function layout(field)
    return Network.layout and assert(Network.layout(field.layout),"Unrecognized saved airport") or Small
  end
  function R.route_stop(s,field,engine,except)
    if not R.fits(field,engine) then return false,"LARGER_AIRFIELD_REQUIRED" end
    if field.layout=="city" then
      -- 3D limitation, not stock FTA: two Darwin bodies can physically
      -- overlap between stands 2 and 3. Leave both source paths intact.
      for _,other in ipairs(R.all(s)) do
        if other~=except and R.uses_airfield(other,field.id) then
          return false,"CITY_AIRFIELD_SERVICE_ALREADY_ASSIGNED"
        end
      end
    end
    return true
  end
  function R.start(s,owner,first,second,owned)
    if s.air_owned_preview and not owned then return nil,"PURCHASED_AIRCRAFT_REQUIRED" end
    local in_fleet=owned and owned.serial~=nil
    if (in_fleet and (s.airport_pilot or R.current(s,owned.serial))) or
       (not in_fleet and R.current(s)) then return nil,"AIRCRAFT_PILOT_ALREADY_EXISTS" end
    if s.air_paid_service and not (s.road_stock_house_supply and s.corner_grid) then
      return nil,"STOCK_HOUSE_CLOCK_REQUIRED"
    end
    local a,b=s.stock_small_airports and s.stock_small_airports[first],s.stock_small_airports and s.stock_small_airports[second]
    if not a or not b or a==b or a.owner~=owner or b.owner~=owner then return nil,"TWO_OWN_AIRFIELDS_REQUIRED" end
    for _,field in ipairs({a,b}) do
      local ok,why=R.route_stop(s,field,owned and owned.stock_id)
      if not ok then return nil,why end
    end
    -- Fleet aircraft contend for the actual FTA flags. A second filing
    -- from another hangar need not wait for its destination to be idle.
    if not in_fleet and (a.flags~=0 or b.flags~=0) then return nil,"AIRFIELD_BUSY" end
    local p={version=R.VERSION,owner=owner,first=first,second=second,arrivals=0,departures=0,
      target=first,phase="hangar",dwell=0}
    if owned then
      local own=in_fleet and s.stock_owned_air_fleet and s.stock_owned_air_fleet[owned.serial] or s.stock_owned_aircraft
      assert(own==owned and s.air_paid_service)
      p.engine_id=owned.stock_id
      p.finance={annual_fp=owned.annual_fp,ticks=0,charged_ticks=0,expense=0}
    end
    local engine=R.engine_for(p)
    p.vehicle=layout(a).new(a,{owner=owner,order={kind="station",id=second},
      max_speed=engine.max_speed,acceleration=engine.acceleration})
    if s.air_paid_service then
      p.paid_clock=in_fleet and owned.serial or s.next_paid_air_run or 1
      p.paid_built_day=owned and owned.day or s.day
      if not in_fleet then s.next_paid_air_run=p.paid_clock+1 end
    end
    if in_fleet then
      s.airport_owned_runs=s.airport_owned_runs or {}
      s.airport_owned_runs[p.paid_clock]=p
    else s.airport_pilot=p end
    return p
  end
  function R.uses_airfield(p,id)
    if p.target==id then return true end
    if not p.transport_orders then return p.first==id or p.second==id end
    for _,o in ipairs(p.transport_orders) do if o.id==id then return true end end
    return false
  end
  function R.clear(s,owner)
    local p=R.current(s)
    if not p or p.owner~=owner then return nil,"NO_OWN_AIRCRAFT_PILOT" end
    if p.engine_id then return nil,"OWNED_AIRCRAFT_CANNOT_BE_CLEARED" end
    for id,a in pairs(s.stock_small_airports or {}) do
      if R.uses_airfield(p,id) then a.flags=0 end
    end
    s.airport_pilot=nil
    return true
  end
  -- Aircraft may fly outside the signed map. Stock GetTileHeightBelowAircraft
  -- clamps only its terrain query and reads the north-corner tile height.
  function R.terrain_under(s,x,z)
    local tx=math.max(1,math.min(Sim.W,math.floor(x/16)))
    local tz=math.max(1,math.min(Sim.H,math.floor(z/16)))
    return Terrain.corner(s.corner_grid,tx,tz)*8
  end
  local function tick(s,ticks,observe,paid,actor)
    local p=actor or R.current(s)
    if not p or p.phase=="blocked" or (p.paid_clock~=nil)~=(paid~=nil) then return end
    local airports=s.stock_small_airports
    local v=p.vehicle
    local a=airports[p.target]
    if not a then p.phase,p.failure="blocked","AIRFIELD_CHANGED";return p end
    local hooks={airports=airports,layout=layout,plane_speed=Motion.PLANE_SPEED,terrain_height=function(x,z)
      return R.terrain_under(s,x,z)
    end}
    local function find_order(advance)
      local list,c=p.transport_orders,p.transport_order_cursor
      if advance and list[c.implicit+1].id==v.last_station then
        -- Vehicle::HandleLoading advances only when this was the ordered terminal.
        O.increment_implicit(list,c)
      end
      O.update_real(list,c)
      return list[c.real+1]
    end
    for _=1,ticks or 1 do
      local ready,skipped
      if paid then
        skipped=v.loading and p.transport_skip_loading
        ready=v.loading and paid.leave(p,skipped)
      elseif v.loading and p.transport_skip_loading then
        skipped,ready,p.dwell=true,true,0
      elseif p.dwell>0 then
        p.dwell=p.dwell-1
        ready=p.dwell==0
      end
      if ready then
        v.loading=nil
        if p.transport_orders then v.order=find_order(not skipped)
        else v.order={kind="station",id=v.last_station==p.first and p.second or p.first} end
        p.transport_skip_loading,p.transport_cancel_full=nil,nil
        p.phase="taxi"
      end
      if p.transport_orders and not v.loading and not v.stopped then
        local order=find_order(false)
        if not v.order or v.order.id~=order.id then
          v.order=order
          -- Aircraft::GetOrderStationLocation retargets immediately only
          -- in FLYING. Keep the previous airport and FTA flags through
          -- committed approach/rollout and ground handling.
          if v.state==Small.state.FLYING and a.id~=order.id then
            local dest=airports[order.id]
            if not dest then p.phase,p.failure="blocked","AIRFIELD_CHANGED";return p end
            if not R.fits(dest,p.engine_id) then p.phase,p.failure="blocked","LARGER_AIRFIELD_REQUIRED";return p end
            layout(dest).inbound(dest,v)
            a=dest
            p.target,p.phase=a.id,"flying"
          end
        end
      end
      if p.finance and not v.stopped then p.finance.ticks=p.finance.ticks+1 end
      local next,events,why=Motion.tick(a,v,hooks)
      if why then p.phase,p.failure="blocked",why;return p end
      a=next
      p.target=a.id
      if p.phase=="hangar" and not v.hidden then p.phase="taxi" end
      for _,ev in ipairs(events) do
        if ev=="departed" then p.departures=p.departures+1;p.phase="flying"
        elseif ev=="hold" then p.phase="holding";p.hold_ticks=(p.hold_ticks or 0)+1
        elseif ev=="approach" then p.phase="approach"
        elseif ev=="touchdown" then p.phase="rollout"
        elseif ev=="terminal" then
          p.arrivals=p.arrivals+1;p.phase="terminal";p.dwell=paid and 0 or R.DWELL_TICKS
          p.last_airfield=a.id
          if paid then
            local tile=Sim.id(math.floor(v.x/16),math.floor(v.z/16))
            local field=tile and s.tiles[tile].airfield
            if not field or field.airport~=a.id then
              p.phase,p.failure="blocked","INVALID_PAID_TERMINAL_TILE";return p
            end
            p.last_terminal_tile=tile
            local ok,reason=paid.arrive(p,tile)
            if not ok then p.phase,p.failure="blocked",reason or "MISSING_PAID_AIRFIELD";return p end
          end
        end
        if observe then observe(ev,p,a) end
      end
    end
    return p
  end
  -- Prevent the presentation clock from also flying a commercial plane.
  function R.tick(s,ticks,observe) return tick(s,ticks,observe,nil) end
  function R.advance_paid(s,callbacks,observe,actor) return tick(s,1,observe,callbacks,actor) end
  function R.settle_owned_day(s,p)
    local f=p and p.finance
    if not f or f.ticks<=f.charged_ticks then return end
    local fixed=Roster.day_charge(f.annual_fp,f.ticks-f.charged_ticks)
    local c=Sim.company(s,p.owner)
    local whole,remainder=Roster.debit_fraction(c.stock_money_fraction or 0,fixed)
    c.cash,c.expense,c.month_exp=c.cash-whole,c.expense+whole,c.month_exp+whole
    c.stock_money_fraction=remainder
    f.charged_ticks,f.expense=f.ticks,f.expense+whole
  end
  function R.pose(p)
    if not p or p.vehicle.hidden then return end
    local v=p.vehicle
    return {x=v.x/8-.5,y=(v.y-1)/8+.5,z=v.z/8-.5},(v.direction-3)*math.pi/4
  end
  return R
end
