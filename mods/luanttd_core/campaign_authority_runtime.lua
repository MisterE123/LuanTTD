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
  local function tile(id)
    local x,z=Sim.xy(id)
    return Terrain.tile(grid,x,z)
  end
  Sim.restore_road_orders(s)
  B.road(s,cap.road)
  B.flood(s)
  B.towns(s)
  local farm,oil
  if s.stock_generated_profile or s.road_farm then
    farm=assert(Sim.mount_farm_world(s,Terrain,true))
  end
  if s.stock_generated_profile or s.road_oil then
    oil=assert(Sim.mount_oil_world(s,Terrain,cap.oil_tanker))
  end
  local network=B.networks(s,Slope,tile)
  local N={world=s,network=network,farm=farm,oil=oil,terrain=Terrain}
  N.road_construction=dofile(mod.."/campaign_road_construction.lua")(Sim,s)
  N.terrain_projection=dofile(mod.."/campaign_terrain_projection.lua")
  N.landscape=dofile(mod.."/campaign_landscape_commands.lua")(Sim,s)
  local source=mod.."/openttd/"
  if s.ship_paid_service then
    local _,_,net,roster,run,depot,freight,coal=B.water(s,network.track,function(id) return cap.ferry[id]==true end)
    N.water={network=net,roster=roster,run=run,depot=depot,freight=freight,coal=coal}
  end
  if s.air_paid_service then
    local net,run,owned,roster=B.air(s,Slope,function(id) return cap.air[id]==true end)
    N.air={network=net,run=run,owned=owned,roster=roster}
  end
  if s.rail_paid_service then
    network.owned=s.rail_owned_service
    network.motion=dofile(source.."rail_motion.lua")(network.track)
    network.speed=dofile(source.."rail_station_speed.lua")(network.track,network.follow)
    local rail,signals,roster,_,heights,profile=B.rail(s,network)
    network.dispatch=rail
    N.rail={run=rail,signals=signals,roster=roster}
    local art=dofile(mod.."/rail_dispatch_manifest.lua")
    local pose=dofile(mod.."/rail_pose.lua")(network.track)
    local diag=dofile(mod.."/rail_diagonal.lua")(Sim,network.track,{tile=tile},network.lab.surface)
    local function diagonal(id,td,f)
      local mode=diag.mode(s,id)
      if mode~=0 then return diag.sample(td,f,mode) end
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
      function(id) local _,level=tile(id);return level end)
    function N.rail.poses(train,fraction)
      local parts=train.consist.parts
      local samples={}
      local push_pull=train.stock_engine==11 and #parts>1
      for i=1,#parts do
        local id,td,f,reversed,wormhole
        if train.paid_clock then id,td,f,reversed,wormhole=Sim.rail_paid_pose(s,i,fraction,train.fleet_id)
        else id,td,f,wormhole=rail.sample(train,i);reversed=train.consist.reversed end
        if id then samples[i]={id=id,td=td,progress=f,reversed=reversed,wormhole=wormhole} end
      end
      samples=fit(samples,parts,push_pull) or samples
      local engine=art.stock_kind[train.stock_engine] or "locomotive"
      local wagon="wagon"
      if train.stock_engine==11 and not train.stock_wagon then wagon="manley"
      elseif train.stock_wagon==29 then
        local coal=Sim.rail_coal_status(s)
        wagon=coal and (coal.onboard or 0)>0 and "coal_loaded" or "coal_empty"
      elseif train.stock_wagon==30 then wagon="oil_tanker"
      elseif train.stock_wagon==32 then wagon="goods_van" end
      local out={}
      for i=1,#parts do
        local p=samples[i]
        if p then
          local pos,rotation,kind,body_index,flip=body(train,p,i,engine,wagon)
          out[#out+1]={tile=p.id,td=p.td,fraction=p.progress,index=i,body_index=body_index,kind=kind,
            pos=pos,rotation=rotation,reversed=not not p.reversed,flip=flip}
        end
      end
      return out
    end
    N.rail.build=B.rail_build({s=s,Sim=Sim,rail_block_tools=s.rail_block_preview,
      terrain={tile=tile},render={update=function(ids)
        local changed=s.changed or {}
        for _,id in ipairs(ids) do changed[#changed+1]=id end
        s.changed=changed
      end},save=function() end},network,rail,signals)
    if roster then
      local owned=B.owned_rail(s,network.lab,roster,rail,function() return Sim.rail_oil_active(s) end)
      if s.stock_electrification then owned.mount_electric(dofile(source.."rail_types.lua")) end
      N.rail.owned=owned
    end
    B.rail_media(rail,cap.rail)
    Sim.mount_paid_rail(s,rail)
    if s.rail_goods_service then
      Sim.mount_rail_goods(s,function() return cap.rail.ready.goods_van==true end)
    end
    if not cap.rail.ready.oil_tanker then s.rail_oil_service=false end
    network.crossings.refresh(s,network.lab.board(s))
  end
  local Clock
  if s.tram_enabled then
    local interval=cap.seconds_per_day or 1.25
    local net,run,clock=B.tram(s,Slope,interval)
    N.tram={run=run,net=net}
    local tram_motion=dofile(mod.."/road_motion_presentation.lua")(dofile(mod.."/road_lanes.lua"))
    function N.tram.pose(frame)
      local x,z=tram_motion.xy(frame[1],frame[2],frame[5])
      local _,level=tile(frame[4])
      return {x=x,y=level+.512,z=z},tram_motion.yaw(frame[3])
    end
    Clock=function() clock(interval) end
  end
  N.orders=dofile(mod.."/road_vehicle_orders.lua")({s=s,Sim=Sim})
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
    local computed,pos,yaw,pitch=positions.timeline(s,v,fraction,surface)
    if computed then return pos,yaw,pitch end
    local f=Sim.road_motion_frame(s,v)
    if f then return positions.sample(s,{f},1,1,surface) end
  end
  local project=dofile(mod.."/campaign_actor_projection.lua")
  function N.actors(x,z,w,h,fraction) return project(Sim,N,x,z,w,h,fraction) end
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
    N.water and N.water.run,N.water and N.water.freight,N.water and N.water.coal,N.air and N.air.run)
  N.orders.ship,N.orders.air=water_air.ship,water_air.air
  N.transport=dofile(mod.."/campaign_transport_commands.lua")(Sim,N)
  function N.day() Sim.daily(s);if Clock then Clock() end end
  return N
end
