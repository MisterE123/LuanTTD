-- Pure gameplay bindings. These must work in an async VM; neither assets
-- nor engine objects are discovered here. The host passes only the verified
-- roster capabilities and the OpenTTD settings that affect simulation.
return function(Sim,mod)
  local B={}
  local source=mod.."/openttd/"
  function B.road(s,opts)
    Sim.mount_road_bus_market(s,dofile(source.."stock_engine_calendar.lua"),
      opts.start_year,opts.foster,opts.craighead,opts.extra)
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
  function B.air(s,slope,ready,city_ready,heliport_ready,ground_ready,expansion_ready)
    local terrain=dofile(source.."terrain.lua")
    local small=dofile(source.."airport_small.lua")
    local motion=dofile(source.."airport_motion.lua")(small)
    local city=city_ready and dofile(source.."airport_city.lua")
    local rig=dofile(source.."airport_oil_rig.lua")
    local heliport=heliport_ready and dofile(source.."airport_heliport.lua")
    local ground={}
    if ground_ready and (ground_ready.helidepot or ground_ready.helistation) then
      local profiles=dofile(source.."airport_rotary_ground_profiles.lua")
      for name,r in pairs(profiles) do if ground_ready[name] then ground[name]=r end end
    end
    for _,name in ipairs({"metropolitan","commuter","international","intercontinental"}) do
      if expansion_ready and expansion_ready[name] then ground[name]=dofile(source.."airport_"..name..".lua") end
    end
    local net=dofile(mod.."/airport_network.lua")(Sim,terrain,small,city or nil,rig,heliport or nil,ground)
    local roster=dofile(source.."airport_roster.lua")
    local run=dofile(mod.."/airport_preview_run.lua")(Sim,net,small,motion,terrain,slope,roster)
    run.paid_art_ready=function(p) return not p or not p.engine_id or ready(p.engine_id) end
    s.air_paid_service=true
    Sim.mount_paid_air(s,run)
    local owned=dofile(mod.."/airport_owned.lua")(Sim,run,roster,ready)
    return net,run,owned,roster
  end
  function B.water(s,track,ready)
    local water=dofile(source.."ship_follow.lua")(track)
    local yapf=dofile(source.."ship_yapf.lua")(track,water,dofile(source.."yapf_road_search.lua"))
    local terrain=dofile(source.."terrain.lua")
    local facilities=dofile(source.."ship_facilities.lua")(track,water)
    local net=dofile(mod.."/ship_network.lua")(Sim,terrain,water,facilities)
    local motion=dofile(source.."ship_motion.lua")(track,water)
    local regions=dofile(source.."ship_regions.lua")
    local roster=dofile(source.."passenger_ship_roster.lua")
    local calendar=dofile(source.."stock_engine_calendar.lua")
    local function make(opts)
      return dofile(mod.."/ship_preview_run.lua")(net,track,water,yapf,motion,regions,
        {width=Sim.W,height=Sim.H,x0=1,z0=1},opts)
    end
    local run=make({engine=roster.model(206),engine_for=roster.model,validate_both=true})
    local depot=dofile(mod.."/passenger_ship_depot.lua")(Sim,roster,calendar,run,ready)
    run.settle_owned_day,run.count_owned_tick,run.paid_art_ready=depot.settle,depot.count_tick,depot.ready
    s.ship_paid_service=true
    Sim.mount_paid_ferry(s,run)
    local cargo_run,coal
    if s.ship_coal_service or s.stock_coal_ship then
      local freight=dofile(source.."ship_roster.lua")
      cargo_run=make({engine=freight.model(211),engine_for=freight.model,
        key="stock_coal_ship_run",serial="next_stock_coal_ship_run",paid=function() return true end,
        validate_both=true})
      coal=Sim.mount_coal_ship(s,cargo_run,run,net,ready)
    end
    local tankers=dofile(source.."oil_ship_roster.lua")
    local oil_run=make({engine=tankers.model(204),engine_for=tankers.model,key="stock_oil_ship_route",
      serial="next_stock_oil_ship_route",paid=function()return true end,validate_both=true,
      use_neutral=dofile(source.."oil_rig.lua").neutral_ref})
    local oil=Sim.mount_oil_ship(s,net,oil_run,ready,run,cargo_run)
    return terrain,water,net,roster,run,depot,cargo_run,coal,oil,oil_run
  end
  function B.networks(s,slope,terrain_tile,survey_clear)
    local track=dofile(source.."rail_track.lua")
    local follow=dofile(source.."rail_follow.lua")(track)
    local cost=dofile(source.."rail_yapf_cost.lua")(track,follow)
    local search=dofile(source.."rail_yapf_search.lua")(track,follow,cost)
    local lab=dofile(mod.."/trackworks.lua")(Sim,track,follow,slope,cost,search,terrain_tile)
    local terrain=dofile(source.."terrain.lua")
    local H=dofile(source.."rail_height.lua")(track,slope)
    local Q=dofile(source.."rail_construction.lua")(track,dofile(source.."rail_signals.lua")(track),H)
    local Site=dofile(source.."rail_span_site.lua")
    local Bridge=dofile(source.."rail_bridge.lua")(dofile(source.."road_bridge.lua")(slope),Q,Site)
    local Tunnel=dofile(source.."rail_tunnel.lua")(dofile(source.."road_tunnel.lua"),Q,Site,track)
    local assets=dofile(mod.."/bridge_style_assets.lua")
    local spans=dofile(mod.."/rail_span_world.lua")(Sim,terrain,H,Bridge,Tunnel,track,
      function(style,gauge) return assets.mounts("rail",style,gauge) end)
    local kernel=dofile(source.."level_crossing.lua")(track)
    local adapter=dofile(mod.."/level_crossing_world.lua")(Sim,terrain,kernel,track)
    local crossings=dofile(mod.."/level_crossing_runtime.lua")(Sim,adapter)
    s.rail_span_enabled,s.level_crossing_enabled=true,true
    adapter.reindex(s)
    local N={track=track,follow=follow,cost=cost,search=search,lab=lab,spans=spans,
      crossings=crossings,terrain_tile=terrain_tile,slope=slope}
    Sim.mount_crossings(s,crossings,function(w)
      return N.dispatch and N.dispatch.board(w) or lab.board(w)
    end,survey_clear)
    local road_follow=dofile(source.."yapf_road_follow.lua")
    local rules=dofile(source.."road_oneway.lua")(dofile(source.."road_slope.lua"),road_follow)
    N.oneway=dofile(mod.."/road_oneway_world.lua")(Sim,terrain,road_follow,rules)
    Sim.mount_road_oneway(s,N.oneway)
    return N
  end
  function B.rail(s,geo)
    local track,follow,cost,search,lab=geo.track,geo.follow,geo.cost,geo.search,geo.lab
    local motion,speed=geo.motion,geo.speed
    local pbs=dofile(source.."rail_reservation.lua")(track,follow,cost)
    local life=dofile(source.."rail_consist_reservation.lua")(track,follow,pbs)
    local signal=dofile(source.."rail_signals.lua")(track)
    local consist=dofile(source.."rail_consist_motion.lua")(track,motion,follow,life)
    local dispatch_motion,dispatch_life=consist,life
    if geo.spans then
      dispatch_motion=dofile(mod.."/rail_span_consist.lua")(track,motion,follow,consist,life)
      dispatch_life=dofile(mod.."/rail_span_life.lua")(track,pbs,life)
    end
    local dispatch=dofile(mod.."/rail_consist_dispatch.lua")(dispatch_motion,dispatch_life)
    local reverse=dofile(source.."rail_reverse.lua")(track,motion,consist,life,signal,follow,pbs)
    local heights=dofile(source.."rail_height.lua")(track,geo.slope)
    local pixel,profile=heights.bind(lab.board(s),geo.terrain_tile)
    s.rail_grade_enabled=true
    local function height(id,x,y)
      local crossing=geo.crossings and geo.crossings.world.record(s,id)
      return crossing and crossing.top*8 or pixel(id,x,y)
    end
    local roster=geo.owned and dofile(source.."rail_roster.lua") or nil
    local block=dofile(source.."rail_block_signals.lua")(track,signal)
    local pilot=dofile(mod.."/rail_dispatch_run.lua")(track,follow,cost,search,pbs,dispatch_life,signal,
      dispatch_motion,dispatch,speed,lab,height,reverse,geo.spans,geo.crossings,roster,block)
    return pilot,signal,roster,height,heights,profile
  end
  function B.owned_rail(s,lab,roster,pilot,oil_active)
    local depot=dofile(mod.."/rail_depot_fleet.lua")(Sim,lab,roster)
    local owned=dofile(mod.."/rail_owned_service.lua")(depot,roster,pilot,Sim.rail_coal_validate,Sim.rail_oil_validate,
      oil_active,Sim.rail_goods_validate,Sim.rail_goods_active,{active=Sim.rail_profile_active,validate=Sim.rail_profile_validate},
      Sim.rail_mail_active)
    lab.owned_depot_occupied=owned.occupies_depot
    s.rail_owned_service=true
    if not s.stock_rail_fleet then
      local seed=math.floor(math.abs(s.seed or 1751))%4294967296
      assert(owned.initialize(s,{starting_year=Sim.date(s,0),climate="temperate",
        generation_seed=seed,startup_random=(seed*1664525+1013904223)%4294967296}))
    end
    return owned
  end
  function B.rail_build(api,network,pilot,signal)
    local track=network.track
    local Height=dofile(source.."rail_height.lua")(track,network.slope)
    local Q=dofile(source.."rail_construction.lua")(track,signal,Height)
    local function value(plan,why)
      if plan then return plan.cost end
      return nil,why
    end
    local prices={
      track=function(tile,p,o)
        if p.remove then return Q.rail_clear_price(tile.railtype or 0,o) end
        local q,why=Q.piece(tile,p.track,o)
        return q and q.cost,why,q
      end,
      station_area=function(tiles,axis,tracks,length,o) return value(Q.station(tiles,axis,tracks,length,o)) end,
      depot=function(tile,d,o) return value(Q.depot(tile,d,o)) end,
      signal=function(tile,d,oneway,o)
        return value(Q.signal(tile,d%2,{kind=oneway and signal.PBS_ONEWAY or signal.PBS},o))
      end,
      signal_track=function(tile,t,kind,o) return value(Q.signal(tile,t,{kind=kind},o)) end,
      clear_signal=function() return Q.base_prices().clear_signal end,
    }
    return dofile(mod.."/rail_construction_tools.lua")(api,network.lab,track,pilot,prices)
  end
  function B.rail_media(pilot,art)
    for _,id in ipairs(art.engines) do assert(pilot.mount_owned_model(id)) end
    local Art=dofile(mod.."/rail_dispatch_manifest.lua")
    pilot.mount_bridge_collectors(function(id)
      if not id then return art.split.sh_30==true and art.split.sh_40==true end
      return art.split[Art.stock_kind[id]]==true
    end)
  end
  function B.tram(s,slope,interval)
    local terrain=dofile(source.."terrain.lua")
    local bridge=dofile(source.."road_bridge.lua")(slope)
    local construct=dofile(source.."tram_construction.lua")(dofile(source.."road_slope.lua"),bridge.roadtypes)
    local span=dofile(mod.."/tram_span_layers.lua")(Sim,terrain,construct,bridge)
    local net=dofile(mod.."/tram_network.lua")(Sim,construct,terrain,span)
    local road=dofile(source.."road_motion.lua")(dofile(source.."road_motion_data.lua"))
    local motion=dofile(source.."tram_motion.lua")(dofile(source.."tram_motion_data.lua"),road)
    local follow=dofile(source.."yapf_road_follow.lua")
    local cost=dofile(source.."yapf_road_cost.lua")(follow)
    local search=dofile(source.."yapf_road_search.lua")(follow,cost)
    local wormhole=dofile(mod.."/road_bridge_motion.lua")
    local trip=dofile(mod.."/tram_trip.lua")(follow,cost,search,motion,wormhole)
    local passenger={station=Sim.tram_stop_station,arrive=Sim.tram_passenger_arrive,depart=Sim.tram_passenger_depart,age=Sim.tram_passenger_age}
    local run=dofile(mod.."/tram_preview_run.lua")(net,trip,dofile(source.."road_speed.lua"),
      Sim.shared_road_tram_active,passenger)
    local clock=dofile(mod.."/aux_transport_clock.lua")(s,interval,function() return run.current(s) end,
      function(n) run.advance(s,n) end)
    return net,run,clock
  end
  return B
end
