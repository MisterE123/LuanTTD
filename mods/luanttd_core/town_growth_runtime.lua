-- Live stock Temperate town growth, limited to original native assets.
local source=debug and debug.getinfo(1,"S").source
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") and core.get_modpath("luanttd_core").."/")
  or assert(source and source:sub(2):match("^(.+[\\/])"),"Cannot locate stock town assets")
return function(Sim,Terrain,G,B,H)
  local W={}
  W.reconstruction=dofile(path.."road_reconstruction_world.lua")(Sim,Terrain,G,
    dofile(path.."openttd/road_reconstruction.lua"),dofile(path.."openttd/road_slope.lua"),
    dofile(path.."openttd/rail_track.lua"),dofile(path.."openttd/slope.lua"),
    dofile(path.."openttd/roadside_temperate.lua"))
  local names=dofile(path.."stock_town_art.lua")
  local Lift=dofile(path.."openttd/town_lift.lua")
  local Rebuild=dofile(path.."openttd/town_rebuild.lua")
  local HouseRoadTypes=dofile(path.."openttd/town_house_roadtypes.lua")
  local authority=dofile(path.."town_road_authority.lua")(Sim,dofile(path.."openttd/road_town_permission.lua"))
  local roads=dofile(path.."town_generation_board.lua")
  local Worldgen=dofile(path.."openttd/town_worldgen.lua")(G,B)
  local function at(layer,id) return layer and layer[id] end
  local function record(t) return t and t.house and t.source_house or nil end
  local function underground(s,id)
    return at(s.tunnel_below,id) or at(s.rail_tunnel_below,id)
  end
  local function protected(s,id,t,above_tunnel,below_bridge)
    return t.stock_canal or t.rail_tracks or t.rail_station_id or t.rail_depot_dir or
      t.level_crossing or t.road_waypoint_id or t.rail_span_id or t.road_tunnel_id or t.road_bridge_id or
      t.stock_industry or t.stock_landmark or t.ship or t.airfield or t.tram or t.signal or
      at(s.level_crossing_tiles,id) or (not below_bridge and
        (at(s.bridge_above,id) or at(s.rail_bridge_above,id) or at(s.aqueduct_above,id))) or
      (not above_tunnel and underground(s,id))
  end
  local function clear_levels(s,id,allow_cover,allow_coast,allow_steep,below_bridge)
    local tile=at(s.tiles,id)
    if allow_cover and not allow_steep and tile and tile.build=="road" and Sim.town_clear_road_tip(s,id,false) then
      local x,z=Sim.xy(id)
      local slope,base,top=Terrain.tile(s.corner_grid,x,z)
      if slope and slope<16 then return top,slope,base end
      return
    end
    local coast=tile and allow_coast and tile.terrain=="water" and tile.coastal_water
    if not tile or tile.terrain~="grass" and tile.terrain~="hill" and not coast or tile.owner or tile.site or
      tile.stock_void or tile.stock_object or (not allow_cover and at(s.stock_farm_fields,id)) or
      tile.wood and not allow_cover or tile.house or tile.source_house or tile.build or tile.station or tile.parcel or
      tile.road_bits or tile.road_town or protected(s,id,tile,allow_cover,below_bridge) then return end
    local x,z=Sim.xy(id)
    local slope,base,top=Terrain.tile(s.corner_grid,x,z)
    if slope and (slope<16 or allow_steep) and (not coast or Sim.town_clear_coast(s,id,false)) then return top,slope,base end
  end
  local function board(s,allow_cover)
    return {
      tile=function(x,z)
        local id=Sim.id(x,z)
        local t=at(s.tiles,id)
        if not t then return end
        local p=protected(s,id,t)
        if not p and not t.site and not t.house and not t.wood then
          if t.build=="road" or t.build=="road_station" and not t.road_stop_pair then
            return {kind=t.build=="road" and "road" or "drive_stop",road_town=t.road_town,
              road_bits=t.road_bits or 0}
          end
        end
        local top,slope=clear_levels(s,id,allow_cover,allow_cover)
        if top then
          local coast=t.terrain=="water" and t.coastal_water
          return {kind=coast and "water" or t.wood and "trees" or "clear",coast=coast,
            slope=slope,max_z=top*8}
        end
        return {kind=t.terrain=="water" and "water" or t.house and "house" or "object",protected=true}
      end,
      clear_quote=function(x,z,kind) return kind=="house" and clear_levels(s,Sim.id(x,z),allow_cover,allow_cover)~=nil end,
      house_supported=function(id) return names[id]~=nil end,
      house_roadtypes=HouseRoadTypes.on_board(Sim,s),
    }
  end
  function W.eligible_site(s,x,z) return clear_levels(s,Sim.id(x,z)) end

  local services=dofile(path.."town_station_services.lua")(Sim).view
  function W.start(s)
    if s.stock_town_growth then
      assert(s.stock_town_growth.version==1,"Unsupported town growth save")
      return s.stock_town_growth
    end
    local save={version=1,order={},towns={}}
    for _,site in ipairs(s.sites) do
      if site.kind=="town" then
        local x,z=Sim.xy(site.tile)
        save.towns[site.id]=G.new(site.id,x,z,{larger_town=site.larger_town})
        save.order[#save.order+1]=site.id
      end
    end
    table.sort(save.order)
    for _,tile in ipairs(s.tiles) do
      local h=record(tile)
      local t=h and save.towns[h.town]
      if t then
        t.house_counts=t.house_counts or {}
        t.house_counts[h.id]=(t.house_counts[h.id] or 0)+1
        if h.root==true or not h.asset_root and h.root~=false then
          t.num_houses=t.num_houses+1
          if h.completed then t.population=t.population+assert(H.specs[h.id])[1] end
          if h.id==0x03 then t.unique={church=true,stadium=t.unique and t.unique.stadium} end
          if h.id==0x14 or h.id==0x20 then t.unique={stadium=true,church=t.unique and t.unique.church} end
        end
      end
    end
    for _,id in ipairs(save.order) do
      local t=save.towns[id]
      t.radii=G.radii(t.num_houses)
      s.sites[id].population=t.population
    end
    s.stock_town_growth=save
    return save
  end

  -- Existing saves may have a non-stock default age before migration.
  -- Age unproven road stations from 255; keep preview clocks on reload.
  local function growth_setting(s)
    local options=s.stock_generated_profile and s.stock_generated_profile.town_settings
    return options and options.growth_setting or 2
  end

  function W.prepare_day(s)
    W.start(s)
    for _,st in pairs(s.stations) do
      if st.mode=="road" and not st.town_growth_service_clock then
        st.time_since_load,st.time_since_unload=255,255
        st.town_growth_service_clock=true
      end
    end
  end

  function W.month_due(s)
    local month,first=math.floor(s.day/30),s.day%30==0
    if s.stock_bus_market then
      local y,m,d=Sim.date(s)
      month,first=y*12+m,d==1
    end
    local state=s.stock_town_growth
    return first and state and state.last_month~=month and month or nil
  end

  function W.month(s,month,random)
    local state=s.stock_town_growth
    if not state or not month or state.last_month==month then return end
    local views=services(s,true)
    if #state.order>=8 then views.count_near=G.index_active_stations(views) end
    local ratings=authority.station_view(s,views)
    for _,id in ipairs(state.order) do
      local t=state.towns[id]
      local was_funded=t.road_build_months==1
      local _,reason=G.month(t,views,growth_setting(s),random)
      if was_funded then W.reconstruction.expired(s,t) end
      t.reason=reason
      t.last_active=G.active_stations(t,views)
      authority.month(s,t,ratings)
    end
    state.last_month=month
  end

  function W.fund_buildings(s,id)
    local town=s.stock_town_growth and s.stock_town_growth.towns[id]
    if not town then return nil end
    local mounted=services(s)
    local _,reason=G.fund(town,mounted,growth_setting(s))
    town.reason,town.last_active=reason,G.active_stations(town,mounted)
    return town
  end

  local function visual_changed(s,id)
    s.changed=s.changed or {}
    s.changed[#s.changed+1]=id
  end

  local function available(s,id,t)
    -- The first live mount does not demolish or move developed parcels.
    -- The road and span command still enforces actual geometry/traffic.
    return t and not (t.stock_void or t.stock_object or t.owner or t.house or t.source_house or
      t.parcel or t.site or t.station or protected(s,id,t)) and (not t.build or t.build=="road")
  end
  function W.road_board(s,founding)
    local function read(x,z)
      local id=Sim.id(x,z)
      local t=at(s.tiles,id)
      if not t then return end
      if t.stock_void then return {kind="void"} end
      local slope,base,top=Terrain.tile(s.corner_grid,x,z)
      local kind,road_bits,axis,entrance
      if t.house then kind="house"
      elseif t.build=="road_depot" and type(t.depot_dir)=="number" then kind,entrance="depot",4-t.depot_dir
      elseif t.build=="road_station" then
        local b=t.stop_axis or Sim.road_bits(s,id)
        if b==5 or b==10 then kind,axis,road_bits="drive_stop",b==5 and 1 or 0,b
        else
          kind="bay_stop"
          for d=0,3 do if b==2^(3-d) then entrance=d;break end end
        end
      elseif t.stock_industry then kind="industry"
      elseif t.rail_tracks and not t.level_crossing then kind="rail"
      elseif t.build=="road" or t.level_crossing or t.tram and t.tram.kind=="road" then
        kind,road_bits="road",Sim.road_bits(s,id)
      elseif t.terrain=="water" then kind="water"
      elseif t.wood then kind="trees"
      elseif available(s,id,t) or underground(s,id) and clear_levels(s,id,true,true) then kind="clear"
      else kind="object" end
      local plain_rail=kind=="rail" and t.build=="stock_rail" and not t.rail_station_id and
        not t.rail_depot_dir and not t.rail_waypoint_id and not t.rail_span_id
      -- Bridge scouting counts ordinary railway even with signals. The
      -- geometric level-crossing path still excludes signalled track.
      local plain_track=plain_rail and not t.signal and t.rail_tracks or nil
      return {kind=kind,slope=slope,base=base,max_z=top*8,road_bits=road_bits,plain_track=plain_track,
        plain_rail=not not plain_rail,crossing=t.level_crossing~=nil,
        company_road=Sim.town_company_road(s,id) or nil,
        road_town=t.road_town,road_disallowed=t.road_disallowed or t.disallowed,
        owner=t.owner,axis=axis,entrance=entrance,coast=kind=="water" and t.coastal_water,
        sea=kind=="water" and t.water_class=="sea" and not t.coastal_water,
        water_rocks=t.stock_water_rocks}
    end
    local function roadable(x,z)
      local id=Sim.id(x,z)
      return available(s,id,at(s.tiles,id)) or Sim.town_mixed_road(s,id)
    end
    return roads(Sim,Terrain,s,G,Worldgen,read,{
      founding=founding,
      houseable=function(x,z) return clear_levels(s,Sim.id(x,z),true,true)~=nil end,
      terraformable=function(x,z)
        return clear_levels(s,Sim.id(x,z),true,false,true,true)~=nil
      end,
      roadable=roadable,
      span_ends=function(x,z,u,v)
        local a,b=Sim.id(x,z),Sim.id(u,v)
        return available(s,a,at(s.tiles,a)) and available(s,b,at(s.tiles,b))
      end,
      bridge_clears=function(ids)
        -- A municipality may cross a structure at the stock clearance
        -- but may never clear a private parcel on the way. "town" in
        -- the command is a sentinel, not a player's name comparison.
        for _,id in ipairs(ids or {}) do
          if not available(s,id,at(s.tiles,id)) then return false end
        end
        return true
      end,
      dirty=function(id)
        visual_changed(s,id)
        Sim.invalidate_live_sea_near(s,id)
      end,
      grade_changed=function() s.topology=(s.topology or 0)+1 end,
    })
  end
  function W.advance_house(s,id,h,tick,year)
    if not h or not h.town_growth or h.completed then return false end
    local t=s.stock_town_growth.towns[h.town]
    local stage=h.stage
    if h.asset_root and not h.root then return true end
    local members=names.footprint(Sim,s,h)
    if h.asset_root and not members then return true end
    local records={h}
    if members then
      for i,part in ipairs(members) do records[i]=part.record end
    end
    local suppress=B.advance_house(h,records,H.specs,function(p,population)
      t.population=t.population+population
      s.sites[h.town].population=t.population
      p.completed_tick=tick or s.passenger_house_clock.counter+1
      local age_epoch=year or Sim.date(s)
      for _,part in ipairs(records) do part.age_epoch=age_epoch end
    end)
    if stage~=h.stage then
      if members then for _,part in ipairs(members) do visual_changed(s,part.id) end
      else visual_changed(s,id) end
    end
    return suppress
  end
  function W.footprint(s,h) return names.footprint(Sim,s,h) end
  function W.remove(s,h)
    if s.stock_town_lifts and Lift.supports(h) and h.x and h.z then
      Lift.erase(s.stock_town_lifts,Sim.id(h.x,h.z))
    end
    local state=s.stock_town_growth
    local t=state and h and state.towns[h.town]
    if not t then return end
    if h.completed then
      t.population=t.population-assert(H.specs[h.id])[1]
      s.sites[h.town].population=t.population
    end
    if h.root==true or not h.asset_root and h.root~=false then
      t.num_houses=t.num_houses-1;t.radii=G.radii(t.num_houses)
      if t.unique then
        if h.id==0x03 then t.unique.church=nil end
        if h.id==0x14 or h.id==0x20 then t.unique.stadium=nil end
      end
    end
    if t.house_counts then t.house_counts[h.id]=t.house_counts[h.id]-1 end
  end

  local function commit(s,t,proposal,views,tick,write_house)
    -- Everything is read-only until the exact proposal and occupancy
    -- recheck succeed. Do not issue a generic clear or terraform command.
    if not proposal or proposal.kind~="house" or proposal.town~=t.id then return false end
    local style=names[proposal.id]
    local allow_cover=s.stock_generated_profile and not write_house
    local get_level=function(id) return clear_levels(s,id,allow_cover,allow_cover) end
    local parts,level=names.inspect(Sim,proposal,get_level)
    if not parts then return false end
    local root=parts[1]
    local h,id=root.record,root.id
    local wrote=false
    local function native_write()
      local recheck,current=names.inspect(Sim,proposal,get_level)
      if wrote or not recheck or current~=level then return false end
      wrote=true
      for _,part in ipairs(parts) do
        local tile=s.tiles[part.id]
        local _,_,base=clear_levels(s,part.id,allow_cover,allow_cover)
        local coast=tile.terrain=="water" and tile.coastal_water
        local road=tile.build=="road"
        if road then
          assert(Sim.town_clear_road_tip(s,part.id,true))
        elseif coast then
          -- RC1's NoWater flag prohibits clearing actual water, not a
          -- coast or rocky coast. Reuse the exact municipal clear quote.
          assert(Sim.town_clear_coast(s,part.id,true))
        elseif allow_cover then
          -- Stock ClearTile_Clear treats fields as clear landscape. Only
          -- clear this footprint; the field's source farm is unaffected.
          -- OWNER_TOWN has no company to debit or penalize for trees.
          Sim.mark_clear_land(s,part.id)
          tile.wood=nil
          if s.stock_farm_grass then s.stock_farm_grass[part.id]=nil end
        end
        names.stamp(part.record,proposal,style,part.index,tick)
        tile.house,tile.source_house,tile.h=true,part.record,base
        if s.stock_town_lifts and Lift.supports(part.record) then Lift.install(s.stock_town_lifts,part.id,Sim) end
        visual_changed(s,part.id)
        if coast or road then Sim.invalidate_live_sea_near(s,part.id) end
      end
      B.house_committed(t,proposal,views,growth_setting(s))
      t.last_build={tile=id,house=h.id,tick=tick,name=style.name}
      return true
    end
    if write_house then
      -- The stock search has already drawn RNG. The detached writer must
      -- either commit this exact house or stop the owner, never resample.
      local ok=write_house(s,{tile=id,x=h.x,z=h.z,house=h.id,town=t.id,tick=tick,level=level,
        random_bits=proposal.random_bits},native_write)
      assert(ok==true and wrote,"Town house writer failed after source planning")
      return true
    end
    return native_write()
  end
  function W.rebuild(s,h,id,word,tick,random,year)
    if not h.root or not h.completed then return end
    local t=s.stock_town_growth and s.stock_town_growth.towns[h.town]
    if not t or not t.growing then return end
    local style=names[h.id]
    if not style then return end
    local parts=h.asset_root and names.footprint(Sim,s,h) or not h.asset_root and {{id=id,record=h}}
    if not parts then return end
    for _,p in ipairs(parts) do
      local cell=s.tiles[p.id]
      if not cell or not cell.house or cell.source_house~=p.record
        or p.record.player_protected or cell.owner or protected(s,p.id,cell) then return end
    end
    year=year or Sim.date(s)
    local receipt=Rebuild.visit(t,h,style,true,word,year)
    if not receipt then return end
    -- OWNER_TOWN clears the complete building. No company can be
    -- billed or get a demolishing-company reputation adjustment.
    for _,p in ipairs(parts) do
      local cell=s.tiles[p.id]
      W.remove(s,p.record)
      cell.house,cell.source_house,cell.parcel=nil,nil,nil
      Sim.mark_clear_land(s,p.id)
      visual_changed(s,p.id)
    end
    s.topology=s.topology+1
    local target=receipt.replace
    if target then
      local policy=s.stock_road_town_policy
      local proposal=B.house(t,board(s,s.stock_generated_profile),target.x,target.z,
        {year=year,allow_roads=not policy or policy.allow_town_roads~=false},random)
      commit(s,t,proposal,services(s),tick,nil)
    end
    return receipt
  end
  function W.tick(s,tick,random,write_house,year)
    local state=s.stock_town_growth
    if not state then return end
    local view,brd
    local policy=s.stock_road_town_policy
    local ordinary=not write_house and s.stock_generated_profile
    local expand=ordinary and (not policy or policy.allow_town_roads~=false)
    -- OnTick_Town visits the same ordered towns even when no build is
    -- due. G.tick supplies the town when its countdown actually expires;
    -- share one callback and the lazy board for this source tick.
    local function attempt(t)
      -- OnTick_Town runs before OnTick_Station on this source tick;
      -- an unused stop due for destruction is still in the sign index.
      view=view or services(s,false,tick-1)
      -- Houses-only still follows existing crossings, drive-through
      -- stops and road portals; only construction of new roads stops.
      brd=brd or (ordinary and W.road_board(s) or board(s,false))
      local function write(proposal)
        return commit(s,t,proposal,view,tick,write_house)
      end
      local proposal,extra_built=B.grow(t,brd,{year=year or Sim.date(s),allow_roads=not not expand,
        build_on_slopes=not policy or policy.build_on_slopes~=false,
        allow_level_crossings=not policy or policy.allow_town_level_crossings~=false,
        extra_house=expand and write or nil},random)
      if not proposal then return not not extra_built end
      if proposal.kind=="house" then return write(proposal) or not not extra_built end
      local id=Sim.id(proposal.x,proposal.z)
      if proposal.kind=="road" then
        local tile=s.tiles[id]
        if not (tile and tile.build=="stock_rail" or available(s,id,tile) or
            Sim.town_mixed_road(s,id) or Sim.town_company_road(s,id)) or
            not Sim.town_road_piece(s,t.id,id,proposal.bits,true) then return false end
        visual_changed(s,id)
        Sim.invalidate_live_sea_near(s,id)
        return true
      end
      local finish=Sim.id(proposal.u,proposal.v)
      if not available(s,id,s.tiles[id]) or not available(s,finish,s.tiles[finish]) then return false end
      local ok,_,dirty
      if proposal.kind=="bridge" then
        if not brd.bridge_quote(t,proposal.x,proposal.z,proposal.u,proposal.v,proposal.style) then return false end
        ok,_,dirty=Sim.road_bridge(s,"town",id,finish,proposal.style,false,t.id)
      elseif proposal.kind=="tunnel" then
        ok,_,dirty=Sim.road_tunnel(s,"town",id,false,t.id,brd.excavation,random)
      end
      if not ok then return false end
      for _,cell in ipairs(dirty) do
        visual_changed(s,cell)
        Sim.invalidate_live_sea_near(s,cell)
      end
      return true
    end
    for _,id in ipairs(state.order) do G.tick(state.towns[id],attempt) end
  end
  return W
end
