-- Live stock Temperate town growth, limited to original native assets.
local source=debug and debug.getinfo(1,"S").source
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") and core.get_modpath("luanttd_core").."/")
  or assert(source and source:sub(2):match("^(.+[\\/])"),"Cannot locate stock town assets")
return function(Sim,Terrain,G,B,H)
  local W={}
  W.reconstruction=dofile(path.."road_reconstruction_world.lua")(Sim,Terrain,G,
    dofile(path.."openttd/road_reconstruction.lua"),dofile(path.."openttd/road_slope.lua"),
    dofile(path.."openttd/rail_track.lua"),dofile(path.."openttd/slope.lua"))
  local names=dofile(path.."stock_town_art.lua")
  local authority=dofile(path.."town_road_authority.lua")(Sim,dofile(path.."openttd/road_town_permission.lua"))
  local function at(layer,id) return layer and layer[id] end
  local function record(t) return t and t.house and t.source_house or nil end
  local function protected(s,id,t)
    return t.stock_canal or t.rail_tracks or t.rail_station_id or t.rail_depot_dir or
      t.level_crossing or t.road_waypoint_id or t.rail_span_id or t.road_tunnel_id or t.road_bridge_id or
      t.stock_industry or t.stock_landmark or t.ship or t.airfield or t.tram or t.signal or
      at(s.level_crossing_tiles,id) or at(s.bridge_above,id) or at(s.tunnel_below,id) or
      at(s.rail_bridge_above,id) or at(s.rail_tunnel_below,id) or at(s.aqueduct_above,id)
  end
  local function base_if_clear(s,id)
    local tile=at(s.tiles,id)
    if not tile or tile.terrain~="grass" and tile.terrain~="hill" or tile.owner or tile.site or
      tile.wood or tile.house or tile.source_house or tile.build or tile.station or tile.parcel or
      tile.road_bits or tile.road_town or protected(s,id,tile) then return end
    local x,z=Sim.xy(id)
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    if slope==0 then return base end
  end
  local function board(s)
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
        local base=base_if_clear(s,id)
        if base then return {kind="clear",slope=0,max_z=base*8} end
        return {kind=t.terrain=="water" and "water" or t.house and "house" or "object",protected=true}
      end,
      house_supported=function(id) return names[id]~=nil end,
    }
  end
  function W.eligible_site(s,x,z) return base_if_clear(s,Sim.id(x,z)) end

  -- Only stock road station records have authoritative ages in all
  -- supported combinations of this preview. Do not infer other modes
  -- from UI visits or from s.site.service (a legacy delivered-unit sum).
  local function services(s)
    local out={}
    for _,st in pairs(s.stations) do
      if st.mode=="road" and at(s.tiles,st.tile) and st.town_growth_service_clock then
        out[#out+1]=st
      end
    end
    table.sort(out,function(a,b) return a.id<b.id end)
    local list={}
    for i,st in ipairs(out) do
      local x,z=Sim.xy(st.tile)
      list[i]={x=x,z=z,time_since_load=st.time_since_load,time_since_unload=st.time_since_unload}
    end
    return list
  end

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
        if h.root~=false then
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
  function W.prepare_day(s,random,want_new)
    local state=W.start(s)
    for _,st in pairs(s.stations) do
      if st.mode=="road" and not st.town_growth_service_clock then
        st.time_since_load,st.time_since_unload=255,255
        st.town_growth_service_clock=true
      end
    end
    local views
    local month,first=math.floor(s.day/30),s.day%30==0
    if s.stock_bus_market then
      local y,m,d=Sim.date(s)
      month,first=y*12+m,d==1
    end
    if want_new and first and state.last_month~=month then
      views=services(s)
      local ratings=authority.station_view(s)
      for _,id in ipairs(state.order) do
        local t=state.towns[id]
        local was_funded=t.road_build_months==1
        local _,reason=G.month(t,views,2,random)
        if was_funded then W.reconstruction.expired(s,t) end
        t.reason=reason
        t.last_active=G.active_stations(t,views)
        authority.month(s,t,ratings)
      end
      state.last_month=month
    end
  end

  function W.fund_buildings(s,id)
    local town=s.stock_town_growth and s.stock_town_growth.towns[id]
    if not town then return nil end
    local mounted=services(s)
    local _,reason=G.fund(town,mounted,2)
    town.reason,town.last_active=reason,G.active_stations(town,mounted)
    return town
  end

  local function visual_changed(s,id)
    s.changed=s.changed or {}
    s.changed[#s.changed+1]=id
  end
  function W.advance_house(s,id,h)
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
      p.completed_tick=s.passenger_house_clock.counter+1
    end)
    if stage~=h.stage then
      if members then for _,part in ipairs(members) do visual_changed(s,part.id) end
      else visual_changed(s,id) end
    end
    return suppress
  end
  function W.footprint(s,h) return names.footprint(Sim,s,h) end
  function W.remove(s,h)
    local state=s.stock_town_growth
    local t=state and h and state.towns[h.town]
    if not t then return end
    if h.completed then
      t.population=t.population-assert(H.specs[h.id])[1]
      s.sites[h.town].population=t.population
    end
    if h.root~=false then
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
    local get_level=function(id) return base_if_clear(s,id) end
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
        names.stamp(part.record,proposal,style,part.index,tick)
        tile.house,tile.source_house,tile.h=true,part.record,level
        visual_changed(s,part.id)
      end
      B.house_committed(t,proposal,views,2)
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
  function W.tick(s,tick,random,write_house)
    local state=s.stock_town_growth
    if not state then return end
    local view
    local brd
    for _,id in ipairs(state.order) do
      local t=state.towns[id]
      G.tick(t,function()
        view=view or services(s)
        brd=brd or board(s)
        local proposal=B.grow(t,brd,{year=Sim.date(s),allow_roads=false},random)
        return commit(s,t,proposal,view,tick,write_house)
      end)
    end
  end
  return W
end
