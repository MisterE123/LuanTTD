-- Opt-in native tools for two-part docks, a two-tile depot and one ferry.
return function(api,Network,Run)
  local Sim,S=api.Sim,api.s
  local messages={
    SITE_UNSUITABLE="Build on a straight sloping shore with two flat water tiles directly in front.",
    DOCK_CLEAR_TREES="Clear the trees before placing a dock here.",
    BUOY_NEEDS_OPEN_WATER="A buoy needs one flat, open water tile.",
    BUOY_IN_USE="A ferry has this buoy in its orders. Clear the ferry pilot before removing it.",
    SELECT_BUOY="Choose a built buoy on the water.",
    NO_CHANNEL_TO_BUOY="The ferry cannot navigate to that buoy on both dock legs.",
    NO_CHANNEL_FROM_BUOY="The ferry cannot reach the next dock after passing that buoy.",
    PROTECTED_TILE="The site is occupied by another structure.",
    BRIDGE_ABOVE="A bridge blocks the site.",
    AQUEDUCT_SITE_OCCUPIED="The aqueduct needs clear, opposed bank slopes and clearance below.",
    LAND_SLOPED_IN_WRONG_DIRECTION="The aqueduct heads need opposing natural slopes.",
    BRIDGEHEADS_NOT_SAME_HEIGHT="Both aqueduct slopes must end at the same height.",
    SELECT_OWN_AQUEDUCT="Choose an aqueduct head belonging to your company.",
    SELECT_OWN_CANAL="Choose your own uncovered canal.",
    SELECT_OWN_LOCK="Choose one of the three tiles of your lock.",
    VEHICLE_IN_THE_WAY="A ship or other facility is in the way.",
    FLAT_LAND_REQUIRED="Stock canals need level tiles.",
    LANDSCAPE_CLEAR_REQUIRED="Clear buildings and protected ground first.",
    OWNED_BY_ANOTHER="That canal is owned by another company.",
    ALREADY_BUILT="The selected canal is already built.",
    NOT_ENOUGH_MONEY="Your company cannot afford this construction.",
    BUILT_ON_WATER="Both depot halves must be on contiguous open water.",
    SUBSURFACE_RESERVED="The tile is reserved by a tunnel.",
    OWN_DEPOT_AND_TWO_DOCKS_REQUIRED="Choose your own depot and two different docks.",
    NO_CHANNEL_TO_FIRST_DOCK="No navigable route from the depot to the first dock.",
    PILOT_ALREADY_EXISTS="Clear the existing ferry pilot first.",
    NO_OWN_PILOT="You do not have a ferry pilot.",
    BUY_PASSENGER_FERRY_FIRST="Buy a passenger ferry at this depot first.",
    OWNED_FERRY_CANNOT_BE_CLEARED="Use the ship depot to stop or resume your purchased ferry.",
    DEPOT_HAS_PASSENGER_FERRY="This depot contains your purchased passenger ferry.",
    NO_RETURN_CHANNEL="The ferry needs a navigable route both ways between the docks.",
    STOCK_HOUSE_CLOCK_REQUIRED="Paid ferry service needs stock house production enabled.",
    SELECT_OWN_FACILITY="Choose either half of your own dock or depot.",
    FERRY_FREIGHT_SHARED_DEPOT="The coal ship and ferry cannot share a depot in this workbench.",
    DEPOT_HAS_OWNED_SHIP="This depot contains your purchased Yate.",
    FERRY_FREIGHT_SHARED_BERTH="These orders would share a coal-ship berth. Choose separate docks.",
  }
  local function text(reason) return messages[reason] or ("Ferry pilot: "..tostring(reason)) end
  local function at(x,z) return x and z and Sim.id(tonumber(x),tonumber(z)) end
  local function start(name,depot,first,second,via_tile)
    local run,why
    if api.passenger_ferry then run,why=api.passenger_ferry.start(name,depot,first,second,via_tile)
    else run,why=Run.start(S,name,depot,first,second,via_tile) end
    if not run then return nil,text(why) end
    api.save()
    if run.via then
      return run,run.paid_clock and "Passenger ferry dispatched via buoy. It passes the buoy without stopping; inspect either dock for fares."
        or "Ferry dispatched via buoy. It passes the buoy without stopping; this route pilot does not load passengers."
    end
    return run,run.paid_clock and "Passenger ferry dispatched. Inspect either dock for arrivals and fares."
      or "Ferry dispatched. This route pilot does not load passengers."
  end
  local function clear(name)
    local ok,why=Run.clear(S,name)
    if not ok then return nil,text(why) end
    api.save()
    return true,"Ferry pilot cleared."
  end
  local function busy()
    return Run.uses_facilities(S) or api.ship_coal and api.ship_coal.busy()
  end
  api.shipyard={network=Network,busy=busy,reason=text,
    current=function()return Run.current(S) end,start=start,clear=clear}
  core.register_chatcommand("shipyard",{
    params="dock X Z | depot X Z x|z | buoy X Z | lock X Z | remove X Z | aqueduct X Z END_X END_Z | canal X Z END_X END_Z [diagonal]",
    description="Build a harbor dock, depot, buoy, or waterway",
    func=function(name,args)
      local x0,z0,x1,z1,drag=args:match("^canal%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(%a*)$")
      if x0 then
        if drag~="" and drag~="diagonal" then return false,"The canal drag option is diagonal." end
        if busy() then return false,"The existing ferry or coal ship orders protect their waterways." end
        local first,last=at(x0,z0),at(x1,z1)
        if not first or not last then return false,"Select canal tiles inside the region." end
        local p,reason=api.waterworks.build(S,name,first,last,drag=="diagonal")
        if not p then return false,text(reason) end
        api.render.update(p.dirty);api.save()
        return true,("Canal built: %d tiles, $%d."):format(#p.tiles,p.cost)
      end
      local left,upper,right,lower=args:match("^aqueduct%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      if left then
        if busy() then return false,"The existing ferry or coal ship orders protect their waterways." end
        local first,last=at(left,upper),at(right,lower)
        local plan,changed=api.aqueduct.build(S,name,first,last)
        if not plan then return false,text(changed) end
        api.render.raise_bound(plan.deck);api.render.update(changed);api.save()
        return true,("Aqueduct complete: %d tiles, $%d."):format(plan.total_length,plan.price)
      end
      local kind,x,z,dir=args:match("^(%a+)%s+(%d+)%s+(%d+)%s*(%a*)$")
      local id=at(x,z)
      local axis=({x=0,z=1})[dir]
      if not id or (kind~="dock" and kind~="depot" and kind~="remove" and kind~="lock" and kind~="buoy") or
        (kind=="depot" and axis==nil) or (kind~="depot" and dir~="") then
        return false,"Use /help shipyard for construction and removal syntax."
      end
      local selected=S.tiles[id].ship
      if kind~="buoy" and not (kind=="remove" and selected and selected.kind=="buoy") and busy() then
        return false,"The existing ferry or coal ship orders protect their facilities."
      end
      if kind=="lock" then
        local plan,why=api.waterworks.build_lock(S,name,id)
        if not plan then return false,text(why) end
        api.render.update(plan.dirty);api.save()
        return true,("Three-part lock built for $%d."):format(plan.cost)
      end
      if kind=="remove" then
        local changed,cost
        local p=S.tiles[id].ship
        if p and p.aqueduct then changed,cost=api.aqueduct.remove(S,name,id)
        elseif p and p.kind=="lock" then changed,cost=api.waterworks.remove_lock(S,name,id)
        elseif not p and S.tiles[id].stock_canal then changed,cost=api.waterworks.remove(S,name,id)
        else changed,cost=Network.remove(S,name,id) end
        if not changed then return false,text(cost) end
        api.render.update(changed);api.save()
        return true,("Complete structure removed for $%d."):format(cost)
      end
      local p,why=Network.build(S,name,kind,id,axis)
      if not p then return false,text(why) end
      api.render.update(p.tiles);api.save()
      return true,("%s #%d built for $%d."):format(({dock="Dock",depot="Ship depot",buoy="Buoy"})[kind],p.id,p.cost)
    end,
  })
  core.register_chatcommand("ferrypilot",{
    params="DEPOT_X DEPOT_Z FIRST_X FIRST_Z SECOND_X SECOND_Z [VIA_X VIA_Z] | status | clear",
    description="Order the ferry between two docks, optionally via a buoy",
    func=function(name,args)
      local p=Run.current(S)
      if args=="status" or args=="" then
        if not p or p.owner~=name then return false,text("NO_OWN_PILOT") end
        local paid=Sim.ferry_paid_status(S)
        if paid then
          local rows={("Ferry %s%s · %d/%d aboard · %d delivered · $%d fares"):format(
            p.phase,paid.paused and " (paid preview paused)" or "",paid.onboard,paid.capacity,paid.delivered,paid.fare)}
          for _,id in ipairs({p.first,p.second}) do
            local stop=paid.waiting[id]
            rows[#rows+1]=("Dock %d: %d waiting · %s"):format(id,stop.waiting,stop.accepts and "accepts passengers" or "no acceptance")
          end
          if p.via then rows[#rows+1]=("Buoy #%d: %d passed without stopping"):format(p.via.id,p.via.passes) end
          return true,table.concat(rows,"\n")
        end
        return true,("Ferry %s; %d dock visits, %d stock steps%s%s."):format(p.phase,p.arrivals,p.steps,
          p.via and (" / %d buoy passes"):format(p.via.passes) or "",p.failure and (" / "..text(p.failure)) or "")
      elseif args=="clear" then
        local ok,msg=clear(name)
        return not not ok,msg
      end
      local a,b,c,d,e,f,g,h=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      if not a then a,b,c,d,e,f=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$") end
      local depot,first,second=at(a,b),at(c,d),at(e,f)
      if not depot or not first or not second then return false,"Use /help ferrypilot for command syntax." end
      local board=Network.board(S)
      local td,ta,tb=board.tile(depot),board.tile(first),board.tile(second)
      local via=at(g,h)
      if g and not via then return false,text("SELECT_BUOY") end
      local run,msg=start(name,td and td.depot,ta and ta.station,tb and tb.station,via)
      return not not run,msg
    end,
  })
end
