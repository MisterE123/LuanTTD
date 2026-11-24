-- Actual company hangar purchase, independent of presentation. These
-- pinned stock small planes are already available at the 1950 start.
-- Later model retirement/maintenance and non-default refits are not mounted.
return function(Sim,Run,Roster,model_ready)
  local O={}
  local function plane_count(s)
    local n=s.stock_owned_aircraft and 1 or 0
    for _ in pairs(s.stock_owned_air_fleet or {}) do n=n+1 end
    return n
  end
  function O.status(s,field)
    local p=s.stock_owned_aircraft
    if p and (not field or field==p.hangar) then return p end
    if not field then return end
    for _,unit in pairs(s.stock_owned_air_fleet or {}) do
      if unit.hangar==field then return unit end
    end
  end
  function O.quote(s,owner,field,engine)
    if not (s.air_owned_preview and s.air_paid_service and s.road_stock_house_supply) then
      return nil,"PURCHASED_AIRCRAFT_DISABLED"
    end
    if s.air_fleet_preview then
      if s.stock_owned_aircraft or s.airport_pilot then return nil,"START_FRESH_AIR_FLEET_WORLD" end
      if O.status(s,field) then return nil,"HANGAR_ALREADY_HAS_AIRCRAFT" end
      if plane_count(s)>=2 then return nil,"TWO_OWNED_PLANES_ONLY" end
      -- Every mounted airframe can operate solo. Only the modeled
      -- Sampson pair has cleared the shared runway/taxi envelope.
      for _,unit in pairs(s.stock_owned_air_fleet or {}) do
        if engine~=215 or unit.stock_id~=215 then return nil,"SAMPSON_ONLY_FOR_SHARED_AIRFIELDS" end
      end
    elseif plane_count(s)>0 or Run.current(s) then return nil,"ONE_OWNED_PLANE_ONLY" end
    local airport=s.stock_small_airports and s.stock_small_airports[field]
    if not airport or airport.owner~=owner then return nil,"OWN_COUNTRY_HANGAR_REQUIRED" end
    if airport.layout=="heliport" then return nil,"AIRPORT_HAS_NO_HANGAR" end
    if Run.fits and not Run.fits(airport,engine) then return nil,"LARGER_AIRFIELD_REQUIRED" end
    if Roster.available and not Roster.available(Sim,s,engine) then return nil,"AIRCRAFT_NOT_INTRODUCED" end
    local quote,why=Roster.quote(engine,s.stock_air_purchase_base,s.stock_air_running_base)
    if not quote then return nil,why end
    if not model_ready(engine) then return nil,"NATIVE_AIRCRAFT_MODEL_UNAVAILABLE" end
    quote.hangar,quote.owner=field,owner
    return quote
  end
  function O.commit(s,owner,quote)
    if not quote or quote.owner~=owner then return nil,"OWN_COUNTRY_HANGAR_REQUIRED" end
    local fresh,why=O.quote(s,owner,quote.hangar,quote.stock_id)
    if not fresh then return nil,why end
    if fresh.price~=quote.price or fresh.annual_fp~=quote.annual_fp then
      return nil,"AIRCRAFT_QUOTE_CHANGED"
    end
    local c=Sim.company(s,owner)
    if c.cash<fresh.price then return nil,"NOT_ENOUGH_MONEY" end
    c.cash,c.expense,c.month_exp=c.cash-fresh.price,c.expense+fresh.price,c.month_exp+fresh.price
    fresh.id,fresh.day,fresh.status=1,s.day,"hangar"
    if s.air_fleet_preview then
      local id=s.next_paid_air_run or 1
      s.next_paid_air_run=id+1
      s.stock_owned_air_fleet=s.stock_owned_air_fleet or {}
      fresh.id,fresh.serial=id,id
      s.stock_owned_air_fleet[id]=fresh
    else s.stock_owned_aircraft=fresh end
    return fresh
  end
  function O.owns_hangar(s,id)
    return O.status(s,id)~=nil
  end
  function O.start(s,owner,first,second)
    if not (s.air_owned_preview and s.air_paid_service and s.road_stock_house_supply) then
      return nil,"PURCHASED_AIRCRAFT_DISABLED"
    end
    local unit=O.status(s,first)
    if not unit or unit.owner~=owner or unit.status~="hangar" then
      return nil,"FIRST_AIRFIELD_MUST_BE_YOUR_PURCHASE_HANGAR"
    end
    if not model_ready(unit.stock_id) then return nil,"NATIVE_AIRCRAFT_MODEL_UNAVAILABLE" end
    local run,why=Run.start(s,owner,first,second,unit)
    if not run then return nil,why end
    unit.status="dispatched"
    return run
  end
  return O
end
