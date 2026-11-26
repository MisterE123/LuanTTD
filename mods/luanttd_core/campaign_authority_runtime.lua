-- Rebind an already initialized campaign after reading its durable checkpoint.
-- Runs in the worker VM before processing any commands. Availability comes
-- from a small immutable capability manifest, never an ObjectRef or renderer.
return function(Sim,mod,s,cap)
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local Slope=dofile(mod.."/openttd/slope.lua")
  local B=dofile(mod.."/campaign_simulation_bindings.lua")(Sim,mod)
  local grid=assert(s.corner_grid,"Cannot mount a campaign without a corner grid.")
  Sim.W,Sim.H=grid.width,grid.depth
  assert(#s.tiles==Sim.W*Sim.H,"The authority checkpoint has the wrong tile count.")
  if cap.rail_forbid_90~=nil then s.stock_rail_forbid_90=cap.rail_forbid_90 end
  local function tile(id)
    local x,z=Sim.xy(id)
    return Terrain.tile(grid,x,z)
  end
  Sim.restore_road_orders(s)
  B.road(s,cap.road)
  B.flood(s)
  local growth=B.towns(s)
  local farm,oil
  if s.stock_generated_profile or s.road_farm then
    farm=assert(Sim.mount_farm_world(s,Terrain,true))
    if s.stock_heavy_industries then Sim.mount_heavy_world(s,Terrain) end
  end
  if s.stock_generated_profile or s.road_oil then
    oil=assert(Sim.mount_oil_world(s,Terrain,cap.oil_tanker))
  end
  -- Asset readiness is rediscovered by the host on each open. It is
  -- not a stale promise carried in the saved simulation.
  s.stock_level_crossing_art=cap.level_crossing_art
  local network=B.networks(s,Slope,tile)
  local N={world=s,network=network,farm=farm,oil=oil,terrain=Terrain}
  local rail_view={Sim=Sim,s=s,trackworks=network.lab,terrain={tile=tile}}
  local scene_diagonal=dofile(mod.."/rail_diagonal.lua")(Sim,network.track,rail_view.terrain,
    network.lab.surface,network.lab.split_surface)
  N.rail_scene_context=dofile(mod.."/rail_scene_context.lua").make(Sim,scene_diagonal,rail_view.terrain)
  N.rail_preview=dofile(mod.."/rail_preview.lua")(rail_view,mod.."/")
  N.crossing_gesture=dofile(mod.."/crossing_gesture.lua")
  if cap.temperate_bank then N.bank=Sim.mount_temperate_bank(s,Terrain,growth) end
  N.road_construction=dofile(mod.."/campaign_road_construction.lua")(Sim,s,network.oneway,N.bank,N)
  N.terrain_projection=dofile(mod.."/campaign_terrain_projection.lua")
  N.canal_dikes=dofile(mod.."/canal_dike_surface.lua")(Sim,s,tile,dofile(mod.."/openttd/canal_dikes.lua"))
  N.landscape=dofile(mod.."/campaign_landscape_commands.lua")(Sim,s)
  local source=mod.."/openttd/"
  local auxiliary={}
  local interval=cap.seconds_per_day or 1.25
  local function pilot(active,tick)
    auxiliary[#auxiliary+1]=dofile(mod.."/aux_transport_clock.lua")(s,interval,active,tick)
  end
  function N.frame(dt)
    for _,tick in ipairs(auxiliary) do tick(dt) end
  end
  if s.ship_paid_service then
    local _,follow,net,roster,run,depot,freight,coal,tanker,tanker_run=B.water(s,network.track,function(id) return cap.ferry[id]==true end)
    N.water={network=net,follow=follow,roster=roster,run=run,depot=depot,freight=freight,coal=coal,tanker=tanker,tanker_run=tanker_run}
    local Bridge=dofile(source.."road_bridge.lua")(Slope)
    local Aqua=dofile(source.."aqueduct.lua")(Bridge)
    N.water.aqueduct=dofile(mod.."/ship_aqueduct_world.lua")(Sim,Terrain,Aqua)
    local Construction=dofile(source.."water_construction.lua")(network.track,follow)
    N.water.works=dofile(mod.."/ship_water_world.lua")(Sim,net,Construction)
    function N.water.busy() return run.uses_facilities(s) or coal and coal.busy(s) or tanker and tanker_run.uses_facilities(s) end
    pilot(function()
      local r=run.current(s)
      return r and not r.paid_clock and (r.engine_id==nil or cap.ferry[r.engine_id])
        and (not run.paid_art_ready or run.paid_art_ready(s,r))
    end,function(n) run.tick(s,n) end)
  end
  if s.air_paid_service then
    local net,run,owned,roster=B.air(s,Slope,function(id) return cap.air[id]==true end,cap.city_airport,cap.heliport,cap.ground_rotary,cap.expansion_airports)
    N.air={network=net,run=run,owned=owned,roster=roster}
    pilot(function()
      local r=run.current(s)
      return r and not r.paid_clock
    end,function(n) run.tick(s,n) end)
  end
  if s.rail_paid_service then
    network.owned=s.rail_owned_service
    network.motion=dofile(source.."rail_motion.lua")(network.track)
    network.speed=dofile(source.."rail_station_speed.lua")(network.track,network.follow)
    local rail,signals,roster,signal_pixel,heights,profile=B.rail(s,network)
    network.dispatch=rail
    N.rail={run=rail,signals=signals,roster=roster}
    pilot(function()
      local d=rail.current(s)
      return d and not (d.runs[1] and d.runs[1].paid_clock)
    end,function(n) rail.tick(s,n) end)
    local art=dofile(mod.."/rail_dispatch_manifest.lua")
    local pose=dofile(mod.."/rail_pose.lua")(network.track)
    local diag=dofile(mod.."/rail_diagonal.lua")(Sim,network.track,{tile=tile},
      network.lab.surface,network.lab.split_surface)
    local function diagonal(id,td,f)
      local mode=diag.mode(s,id,2^network.track.track(td))
      if mode~=0 then return diag.sample(td,f,mode) end
    end
    local platforms=dofile(mod.."/rail_platform_run.lua")(Sim,network.track,network.motion,network.speed,network.lab)
    N.rail.platforms=platforms
    pilot(function() return platforms.current(s) end,function(n) platforms.tick(s,n) end)
    function N.rail.platform_pose(r)
      local id,td,f=platforms.sample(r)
      if not id then return end
      local x,z,dx,dz=diagonal(id,td,f)
      if x==nil then x,z,dx,dz=pose.sample(td,f) end
      local u,v=Sim.xy(id)
      local _,height=tile(id)
      local railhead=profile(id)
      if railhead then height=heights.render(railhead,td,f) or height end
      return {x=2*u+.5+x,y=height+.612,z=2*v+.5+z},math.pi-math.atan2(dx,dz),id
    end
    local function surface(id,td,f,part)
      local crossing=network.crossings.world.record(s,id)
      if crossing then return crossing.top,0 end
      local level,tilt=network.spans.presentation(s,id,td,f,part)
      if level~=nil then return level,tilt end
      local p=profile(id)
      if p then return heights.render(p,td,f) end
    end
    local fit=dofile(mod.."/rail_body_spacing.lua")(Sim,network.track,diagonal,pose.sample)
    local body=dofile(mod.."/rail_visual_body.lua")(Sim,art.models,diagonal,pose.sample,surface,
      function(id) local _,level=tile(id);return level end,
      dofile(mod.."/rail_guideway_bogies.lua")(Sim,network.track,diagonal,pose.sample,surface,function(id) return s.tiles[id] end))
    local signal_rows=dofile(mod.."/rail_signal_poses.lua")(Sim,network.track,dofile(mod.."/rail_signal_art.lua"),
      signal_pixel,function(id) local _,level=tile(id);return level end)
    function N.rail.signals_at(id,out)
      local d=s.stock_rail_dispatch
      local r=d and d.signals and d.signals.records[id]
      if r then signal_rows(id,r,s.tiles[id].rail_tracks or 0,out) end
    end
    local span_wire
    if cap.rail.bridge_wire then
      span_wire=dofile(mod.."/rail_bridge_wire_profile.lua")(Sim,network.spans,
        dofile(mod.."/rail_bridge_catenary_art.lua"),network.track,function(id,mask)
          local slope,height=tile(id)
          local index,level=network.lab.surface(slope,height,mask)
          if index==0 then return level end
        end)
    end
    local exhaust=dofile(mod.."/rail_exhaust_model.lua")
    local function above(index,book,id,y)
      local span=index and book and book[index[id]]
      return span and span.deck and span.deck+.612>y+.02
    end
    local function covered(id,y)
      return above(s.rail_bridge_above,s.stock_rail_spans,id,y) or above(s.bridge_above,s.stock_road_bridges,id,y)
        or above(s.aqueduct_above,s.stock_aqueducts,id,y)
    end
    local link=dofile(mod.."/rail_guideway_drawbar.lua")
    function N.rail.poses(train,fraction)
      local parts=train.consist.parts
      local samples={}
      local push_pull=(train.dual_head or train.stock_engine==11) and #parts>1
      for i=1,#parts do
        local id,td,f,reversed,wormhole
        if train.paid_clock then id,td,f,reversed,wormhole=Sim.rail_paid_pose(s,i,fraction,train.fleet_id,true)
        else id,td,f,wormhole=rail.presentation_sample(s,train,i);reversed=train.consist.reversed end
        if id then samples[i]={id=id,td=td,progress=f,reversed=reversed,wormhole=wormhole} end
      end
      samples=fit(samples,parts,push_pull) or samples
      local engine=art.stock_kind[train.stock_engine] or "locomotive"
      local wagon=art.wagon(train,Sim,s)
      local out={}
      for i=1,#parts do
        local p=samples[i]
        if p then
          local pos,rotation,kind,body_index,flip,bogies=body(train,p,i,engine,wagon)
          local body={tile=p.id,td=p.td,fraction=p.progress,index=i,body_index=body_index,kind=kind,
            pos=pos,rotation=rotation,reversed=not not p.reversed,flip=flip,bogies=bogies}
          if train.town_parts or train.freight_parts then
            local bodies=train.town_parts or train.freight_parts
            local part=bodies[body_index-(train.express_mail and 0 or 1)]
            body.stock_id=part and part.stock or train.stock_engine
            body.body_id=part and part.body_id or train.town_engine_body_id or train.freight_engine_body_id
          elseif train.freight and train.freight_wagon_body_id then
            body.stock_id=body_index==1 and train.stock_engine or train.stock_wagon
            body.body_id=body_index==1 and train.freight_engine_body_id or train.freight_wagon_body_id
          elseif train.matched_cab_ids and (body_index==1 or body_index==#parts) then
            body.stock_id=train.stock_engine
            body.body_id=train.matched_cab_ids[body_index==1 and 1 or 2]
          end
          if exhaust.profiles[kind] then
            local index=p.wormhole and s.rail_tunnel_below and s.rail_tunnel_below[p.id]
            local bore=index and (s.stock_rail_spans or {})[index]
            local underground=bore and math.abs(pos.y-(bore.base+.612))<.12
            body.exhaust=exhaust.work(train,kind,body_index,s.tiles[p.id],
              network.spans.by_portal(s,p.id),underground or covered(p.id,pos.y))
          end
          if train.bridge_collectors and cap.rail.split[kind] then
            local rows,axis,side
            if span_wire then rows,axis,side=span_wire(s,p.id,p.td,p.wormhole) end
            body.collector={rows=rows,axis=axis,side=side}
          end
          out[#out+1]=body
        end
      end
      if train.advanced_gauge then
        for i=1,#out-1 do out[i].drawbar=link(out[i],out[i+1],train.advanced_gauge) end
      end
      return out
    end
    N.rail.types=dofile(source.."rail_types.lua")
    function N.rail.railtype_available(owner,gauge)
      local owned=N.rail.owned
      return owned and N.rail.types.available(gauge,owned.railtype_mask(s,owner,N.rail.types))
    end
    function N.rail.span_available(owner,gauge)
      local spans=cap.rail.guideway_spans
      local ready=spans and spans[gauge] or gauge==2 and cap.rail.advanced_span
      return ready and N.rail.railtype_available(owner,gauge)
    end
    N.rail.build=B.rail_build({s=s,Sim=Sim,rail_block_tools=s.rail_block_preview,
      company_can_build_stock_railtype=N.rail.railtype_available,
      terrain={tile=tile},render={update=function(ids)
        local changed=s.changed or {}
        for _,id in ipairs(ids) do changed[#changed+1]=id end
        s.changed=changed
      end},save=function() end},network,rail,signals)
    if roster then
      local owned=B.owned_rail(s,network.lab,roster,rail,function() return Sim.rail_oil_active(s) end)
      if s.stock_electrification then
        local Types=dofile(source.."rail_types.lua")
        owned.mount_electric(Types)
        local Wire=dofile(mod.."/rail_electrification_world.lua")(Sim,Terrain,network.track,Types,network.spans)
        local ctx={availability=function(_,owner) return owned.railtype_mask(s,owner,Types) end,
          span_art_ready=function(_,span)
            local art=cap.rail
            return span.kind=="bridge" and art.bridge_wire and art.split.sh_30 and art.split.sh_40 or false
          end}
        N.rail.wire={
          quote=function(owner,ids,target) return Wire.quote(s,owner,ids,target,ctx) end,
          commit=function(owner,ticket) return Wire.commit(s,owner,ticket,ctx) end,
        }
      end
      owned.mount_advanced(N.rail.types,cap.rail.advanced)
      N.rail.owned=owned
      N.rail.assembly=dofile(mod.."/rail_depot_assembly_state.lua")(s,owned)
    end
    B.rail_media(rail,cap.rail)
    Sim.mount_paid_rail(s,rail)
    Sim.mount_rail_mail(s,cap.rail.ready.mail_van,cap.rail.mixed_town_engines)
    if s.rail_goods_service then
      Sim.mount_rail_goods(s,function() return cap.rail.ready.goods_van==true end)
    end
    Sim.mount_rail_freight_profiles(s,cap.rail.ready)
    if not cap.rail.ready.oil_tanker then s.rail_oil_service=false end
    network.crossings.refresh(s,network.lab.board(s))
  end
  local Clock
  if s.tram_enabled then
    local interval=cap.seconds_per_day or 1.25
    local net,run,clock=B.tram(s,Slope,interval)
    N.tram={run=run,net=net}
    local tram_occupancy=dofile(mod.."/tram_occupancy.lua")
    function N.tram.busy_probe() return tram_occupancy(Sim,run,s) end
    local wormhole=dofile(mod.."/road_bridge_motion.lua")
    function N.tram.span_busy(lo,hi,plan,removing)
      -- The stock check uses committed logical endpoint occupancy, not
      -- the visual coordinate under the bridge. Keep the existing live
      -- tram's precompiled itinerary intact when removing a layer.
      if removing and (run.uses(s,lo) or run.uses(s,hi)) then return true end
      if Sim.each_tram(s,function(p)
        local at=wormhole.frame_bucket(s,run.frame(p))
        return at==lo or at==hi
      end) then return true end
      local frame,at
      for _,v in pairs(s.fleet) do
        local mode=Sim.vehicles[v.engine] and Sim.vehicles[v.engine].mode
        if mode=="road" or mode=="rail" or mode=="ship" then
          frame=mode=="road" and Sim.road_motion_frame(s,v)
          at=frame and wormhole.frame_bucket(s,frame) or Sim.position(s,v)
          if at==lo or at==hi then return true end
        end
      end
      return false
    end
    function N.tram.facility(owner,id,kind)
      local tile=s.tiles[id]
      return tile and tile.tram and tile.tram.owner==owner and tile.tram.kind==kind
    end
    function N.tram.reason(r) return r end
    function N.tram.busy(id)
      if run.uses(s,id) then return true end
      for _,v in pairs(s.fleet) do if Sim.position(s,v)==id then return true end end
      return false
    end
    local tram_motion=dofile(mod.."/road_motion_presentation.lua")(dofile(mod.."/road_lanes.lua"))
    local pose_source=dofile(mod.."/road_source_pose.lua")(Sim,tram_motion)
    local function tram_surface(id,x,z)
      local h=net.surface_at(s,id,x,z)
      local _,level=tile(id)
      return (h or level)+.512
    end
    function N.tram.pose(frame)
      return pose_source.sample(s,{frame},1,1,tram_surface)
    end
    function N.tram.pose_at(fraction,serial)
      local a,b,t=run.pose_frames(s,fraction,serial)
      if not a then return end
      local pos,yaw,pitch=pose_source.sample(s,{a,b},2,1+t,tram_surface)
      return (t<.5 and a or b),pos,yaw,pitch
    end
    Sim.mount_shared_road_tram(s,run.traffic(net.frame_z))
    Clock=function()
      if not Sim.shared_road_tram_active(s) then clock(interval) end
    end
  end
  N.orders=dofile(mod.."/road_vehicle_orders.lua")({s=s,Sim=Sim,tram=N.tram})
  local motions=dofile(mod.."/road_motion_presentation.lua")(dofile(mod.."/road_lanes.lua"))
  local positions=dofile(mod.."/road_source_pose.lua")(Sim,motions)
  function N.road_pose(v,fraction)
    local function surface(id,x,z)
      local slope,base=Sim.road_surface(s,id)
      if slope then
        local u,w=Sim.xy(id)
        return base+.52+Slope.surface((x-2*u+.5)/2,(z-2*w+.5)/2,slope)
      end
      return s.tiles[id].h+.52
    end
    local computed,pos,yaw,pitch,bore=positions.timeline(s,v,fraction,surface)
    if computed then return pos,yaw,pitch,bore end
    local f=Sim.road_motion_frame(s,v)
    if f then return positions.sample(s,{f},1,1,surface) end
  end
  local project=dofile(mod.."/campaign_actor_projection.lua")
  function N.actors(x,z,w,h,fraction,frame) return project(Sim,N,x,z,w,h,fraction,frame) end
  if s.stock_generated_profile and s.stock_generated_profile.river_stats then
    local rivers=dofile(mod.."/river_presentation.lua")(Sim)
    local cached,revision,topology
    function N.river_direction(id)
      if not cached or revision~=grid.revision or topology~=s.topology then
        cached,revision,topology=rivers.routes(s),grid.revision,s.topology
      end
      return cached[id]
    end
  end
  if N.rail and N.rail.owned then
    N.orders.rail=dofile(mod.."/rail_vehicle_orders.lua")(s,N.rail.owned,dofile(source.."rail_order_cargo.lua"))
  end
  local water_air=dofile(mod.."/water_air_orders.lua")(s,Sim,dofile(source.."rail_order_list.lua"),
    N.water and N.water.run,N.water and N.water.freight,N.water and N.water.coal,N.air and N.air.run,
    N.water and N.water.tanker_run,N.water and N.water.tanker)
  N.orders.ship,N.orders.air=water_air.ship,water_air.air
  N.jump=dofile(mod.."/jump_map.lua")({Sim=Sim,s=s})
  N.passengers=dofile(mod.."/campaign_passenger_projection.lua")(Sim,s)
  N.guide=dofile(mod.."/campaign_company_guide.lua")(Sim,s)
  N.lesson=dofile(mod.."/business_tutorial_progress.lua")({s=s,Sim=Sim,rail_owned=N.rail and N.rail.owned},
    network.track,N.guide.depots)
  N.company_fleet=dofile(mod.."/campaign_company_fleet.lua")(Sim,N)
  N.demolition=dofile(mod.."/campaign_demolition_runtime.lua")(Sim,mod,N,Slope)
  N.transport=dofile(mod.."/campaign_transport_commands.lua")(Sim,N)
  N.news=dofile(mod.."/campaign_news.lua")(Sim,mod,N,cap)
  Sim.mount_news(s,N.news.arrive,N.news.road_flood)
  if N.rail then
    N.rail.run.news_collision=N.news.rail_collision
    N.rail.run.news_flood=N.news.rail_flood
  end
  for _,run in ipairs({N.rail and N.rail.run or false,N.water and N.water.run or false,
    N.water and N.water.freight or false,N.water and N.water.tanker_run or false,N.air and N.air.run or false}) do
    if run then run.news_arrival=N.news.arrive end
  end
  local openings
  local generated=s.stock_generated_profile
  if generated and generated.industry_stats and oil and farm then
    local _,_,farm_rules=Sim.mount_farm_world(s,Terrain,true)
    local stand=dofile(source.."passengers.lua")
    local rate=dofile(source.."station_rating.lua")
    local catchment=dofile(source.."station_catchment.lua")(stand,rate)
    local coal=dofile(source.."coal_industry.lua")(stand,rate,catchment,dofile(source.."income.lua"))
    local timber=Sim.timber_rules()
    local heavy=cap.heavy_industry and Sim.mount_heavy_world(s,Terrain) or nil
    -- Readiness is measured on the presentation host and copied in the
    -- same snapshot as rail/airport assets. A detached Lua runtime has
    -- no engine filesystem API.
    local rules=dofile(source.."industry_worldgen.lua")(coal,timber,Sim.oil_rules(),farm_rules,heavy~=nil,cap.industry_layouts)
    local function vehicle_on_ground(tile)
      for _,r in ipairs({N.water and N.water.run or false,N.water and N.water.freight or false,
          N.water and N.water.tanker_run or false}) do
        local p=r and r.current(s)
        if p and p.vehicle.tile==tile then return true end
      end
      return false
    end
    openings=dofile(mod.."/industry_openings_runtime.lua")(Sim,mod,s,{
      coal=dofile(mod.."/coal_industry_world.lua")(Sim,Terrain,coal),oil=oil,farm=farm,heavy=heavy,
      bank=N.bank,timber=dofile(mod.."/timber_world.lua")(Sim,Terrain,timber)},rules,{
        terrain=Terrain,coal=coal,density=generated.industry_density or 4,vehicle_on_ground=vehicle_on_ground,
          advertise=N.news.industry_opened})
  end
  function N.day()
    Sim.daily(s)
    if Clock then Clock() end
    if openings then openings() end
    N.news.day()
  end
  return N
end
