-- Pure gameplay bindings. These must work in an async VM; neither assets
-- nor engine objects are discovered here. The host passes only the verified
-- roster capabilities and the OpenTTD settings that affect simulation.
return function(Sim,mod)
  local B={}
  local source=mod.."/openttd/"
  function B.road(s,opts)
    Sim.mount_road_bus_market(s,dofile(source.."stock_engine_calendar.lua"),
      opts.start_year,opts.foster,opts.craighead)
    Sim.mount_road_faults(s,dofile(source.."road_breakdowns.lua"),
      dofile(mod.."/road_faults_runtime.lua"),opts.breakdowns,
      {kernel=dofile(source.."road_depot_service.lua"),interval=opts.service_interval,
        percent=opts.service_percent})
  end
  function B.flood(s)
    if not s.stock_coastal_profile then return false end
    s.road_stock_house_supply=true
    Sim.mount_coastal_flood(s)
    return true
  end
  function B.towns(s)
    s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
    local G=dofile(source.."town_growth.lua")
    local Build=dofile(source.."town_growth_build.lua")(G,dofile(source.."town_growth_houses.lua"))
    local runtime=dofile(mod.."/town_growth_runtime.lua")(Sim,dofile(source.."terrain.lua"),G,Build,
      dofile(source.."town_passengers.lua"))
    Sim.mount_stock_town_growth(s,runtime,true)
    return runtime
  end
  return B
end
