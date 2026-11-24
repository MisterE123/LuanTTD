-- Shared direct-world and typed actions for the fixed-wing development pilot.
return function(api,Network,Run,Owned,Roster)
  local Sim,S=api.Sim,api.s
  local reasons={
    SELECT_AIRFIELD_ORIGIN="Choose the northwest corner of the four by three airfield.",
    AIRPORT_TYPE_NOT_AVAILABLE="This stock airport has no native footprint in this installation.",
    CITY_AIRPORT_NOT_INTRODUCED="The stock City Airport becomes available in 1955.",
    METROPOLITAN_AIRPORT_NOT_INTRODUCED="The Metropolitan Airport becomes available in 1980.",
    HELIPORT_NOT_INTRODUCED="The Heliport enters service in 1963.",
    HELIDEPOT_NOT_INTRODUCED="The Helidepot enters service in 1976.",
    HELISTATION_NOT_INTRODUCED="The Helistation enters service in 1980.",
    HELIPORT_HELICOPTERS_ONLY="Only helicopters can serve this landing facility.",
    AIRPORT_HAS_NO_HANGAR="This Heliport has a landing pad but no hangar. Buy and order the helicopter from an airport hangar.",
    CITY_AIRFIELD_SERVICE_ALREADY_ASSIGNED="That City Airport already has an assigned flight.",
    INTERNATIONAL_AIRPORT_NOT_INTRODUCED="The International Airport becomes available in 1990.",
    INTERCONTINENTAL_AIRPORT_NOT_INTRODUCED="The Intercontinental Airport becomes available in 2002.",
    SELECT_PHYSICAL_HANGAR="Aim at one of the airport’s hangar buildings.",
    COMMUTER_AIRPORT_NOT_INTRODUCED="The Commuter Airport becomes available in 1983.",
    LARGER_AIRFIELD_REQUIRED="This aircraft needs a full-length runway at every stop.",
    AIRCRAFT_NOT_INTRODUCED="That aircraft has not entered service in this world yet.",
    AIRPORT_OUTSIDE_REGION="The complete airfield must fit inside the region.",
    AIRPORT_NEEDS_LEVEL_FIELD="The full runway, taxiways and apron need level land at the same height.",
    AIRPORT_SITE_OCCUPIED="Clear trees and structures before building the airfield.",
    TOWN_REFUSES_THIRD_AIRPORT="The town will not permit a third airport.",
    NOT_ENOUGH_MONEY="Your company cannot afford the airfield.",
    SELECT_OWN_AIRFIELD="Choose a tile belonging to your airfield.",
    AIRCRAFT_OCCUPIES_AIRFIELD="Clear the flight pilot before removing its airfield.",
    SELECT_YOUR_HANGAR_AND_COMPATIBLE_AIRFIELD="Choose your purchase hangar and a compatible stop. Oil rigs accept helicopters only.",
    TWO_OWN_AIRFIELDS_REQUIRED="Choose two different airfields owned by your company.",
    AIRCRAFT_PILOT_ALREADY_EXISTS="Clear the active flight before ordering another.",
    NO_OWN_AIRCRAFT_PILOT="Your company has no active flight pilot.",
    STOCK_HOUSE_CLOCK_REQUIRED="Paid flights need stock house production enabled.",
    AIRFIELD_BUSY="The runway or stand is already in use.",
    PURCHASED_AIRCRAFT_DISABLED="Enable paid aircraft and stock town supply before buying.",
    FIRST_AIRFIELD_MUST_BE_YOUR_PURCHASE_HANGAR="Click your aircraft’s purchase hangar airfield first.",
    OWN_COUNTRY_HANGAR_REQUIRED="Choose your company's country airfield.",
    OWNED_AIRCRAFT_CANNOT_BE_CLEARED="An owned aircraft cannot be cleared by a pilot command.",
    ONE_OWNED_PLANE_ONLY="This preview already has one aircraft.",
    TWO_OWNED_PLANES_ONLY="This preview already has two aircraft.",
    HANGAR_ALREADY_HAS_AIRCRAFT="This hangar already owns an aircraft.",
    SAMPSON_ONLY_FOR_SHARED_AIRFIELDS="Only two Sampsons may share airfields. Other aircraft currently operate solo.",
    START_FRESH_AIR_FLEET_WORLD="Start a fresh world for the two-aircraft preview.",
    NATIVE_AIRCRAFT_MODEL_UNAVAILABLE="This aircraft’s native model is missing.",
  }
  local function why(msg) return reasons[msg] or ("Flight pilot: "..tostring(msg)) end
  local function at(x,z) return x and z and Sim.id(tonumber(x),tonumber(z)) end
  local function busy(id)
    if Owned.owns_hangar(S,id) then return true end
    for _,run in ipairs(Run.all(S)) do if Run.uses_airfield(run,id) then return true end end
    return false
  end
  local function start(name,first,second)
    local p,msg
    if S.air_owned_preview then p,msg=Owned.start(S,name,first,second)
    else p,msg=Run.start(S,name,first,second) end
    if not p then return nil,why(msg) end
    api.save()
    return p,p.paid_clock and "Passenger flight ordered. Inspect an airfield for queues and fares."
      or "Trimotor ordered to both country airfields."
  end
  local function clear(name)
    local ok,msg=Run.clear(S,name)
    if ok then api.save() end
    return ok,ok and "Flight pilot cleared." or why(msg)
  end
  api.airfield={network=Network,busy=busy,reason=why,
    current=function() return Run.current(S) end,start=start,clear=clear,
    all=function() return Run.all(S) end,
    at=function(field)
      local records={}
      for _,p in ipairs(Run.all(S)) do
        if Run.uses_airfield(p,field) then records[#records+1]=p end
      end
      return records
    end,
    catalog=Roster.catalog,
    engine_name=function(p) return Run.engine_for(p).name or "Trimotor" end,
    owned=function(field) return Owned.status(S,field) end,
    quote=function(name,id,engine) return Owned.quote(S,name,id,engine) end,
    buy=function(name,id,engine)
      local q,msg=Owned.quote(S,name,id,engine)
      if not q then return nil,why(msg) end
      local unit,reason=Owned.commit(S,name,q)
      if not unit then return nil,why(reason) end
      api.save()
      return unit,("Bought %s for $%d. Use Order aircraft from this airfield."):format(Roster.entry(engine).name,unit.price)
    end}
  core.register_chatcommand("airfield",{
    description="Build or dismantle the full stock footprint of a small airfield",
    params="X Z | remove X Z",
    func=function(name,args)
      local x,z=args:match("^(%d+)%s+(%d+)$")
      local corner=at(x,z)
      if corner then
        local field,dirty=Network.build(S,name,corner)
        if not field then return false,why(dirty) end
        api.render.raise_bound(field.ground/8);api.render.update(dirty);api.save()
        return true,("Country airfield #%d built for $%d."):format(field.id,field.price)
      end
      local a,b=args:match("^remove%s+(%d+)%s+(%d+)$")
      local tile=at(a,b)
      if not tile then return false,"Use /airfield X Z or /airfield remove X Z." end
      local dirty,price=Network.remove(S,name,tile,false,busy)
      if not dirty then return false,why(price) end
      api.render.update(dirty);api.save()
      return true,("Complete airfield removed for $%d."):format(price)
    end,
  })
  core.register_chatcommand("flightpilot",{
    description="Run one original fixed-wing aircraft between two real airfields",
    params="X Z DEST_X DEST_Z | status | clear",
    func=function(name,args)
      local p=Run.current(S)
      if args=="status" or args=="" then
        if not p or p.owner~=name then return false,"Your company has no active flight pilot." end
        return true,("%s %s: %d departures and %d terminal stops."):format(api.airfield.engine_name(p),p.phase,p.departures,p.arrivals)
      elseif args=="clear" then
        local ok,msg=clear(name)
        return ok or false,msg
      end
      local x,z,u,v=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local one,two=Network.airport_for(S,at(x,z)),Network.airport_for(S,at(u,v))
      if not one or not two then return false,why("TWO_OWN_AIRFIELDS_REQUIRED") end
      local flight,msg=start(name,one.id,two.id)
      return not not flight,msg
    end,
  })
end
