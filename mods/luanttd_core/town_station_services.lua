-- Native sign/clock adapter for OpenTTD 16.0-RC1 town_cmd.cpp,
-- ForAllStationsNearTown / CountActiveStations. Read actual station
-- ages; an arrival or a planned route alone is not service.
return function(Sim)
  local M={}
  local path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
  local freight=dofile(path.."rail_freight_kinds.lua")
  local Rig=dofile(path.."openttd/oil_rig.lua")
  local rating_ticks=dofile(path.."openttd/station_rating.lua").rating_ticks
  local modes={road=0,rail=1,ship=2,air=3}
  local function at(t,id) return id and t and t[id] end
  local function has_rail(s,record,id)
    for _,cell in ipairs(record.tiles or {}) do
      local t=s.tiles[cell]
      if t and t.owner==record.owner and t.rail_station_id==id and not t.rail_waypoint_id then return cell end
    end
  end
  local function has_ship(s,record,id)
    local neutral=Rig.neutral_ref(s,record)
    if neutral then
      local t=at(s.tiles,neutral.tile)
      if t and t.ship and t.ship.kind=="oilrig" and t.ship.station==id then return neutral.tile end
      return
    end
    local function dock(cell)
      local t=at(s.tiles,cell)
      return t and t.ship and t.ship.kind=="dock" and t.ship.station==id
    end
    for _,d in ipairs(record.docks or {}) do
      if dock(d.land) and dock(d.water) then return record.sign_tile or d.land end
    end
    if dock(record.land) and dock(record.water) then return record.sign_tile or record.land end
  end
  local function has_air(s,record,id)
    for _,part in ipairs(record.tiles or {}) do
      local t=at(s.tiles,part.id)
      if t and t.airfield and t.airfield.airport==id then return record.origin or part.id end
    end
  end
  local books={rail="stock_rail_stations",ship="stock_ship_stations",air="stock_small_airports"}
  local physical={rail=has_rail,ship=has_ship,air=has_air}
  local function project(id,mode,x,z,row)
    if not x or not z or not Sim.id(x,z) then return end
    return {id=id,mode=mode,x=x,z=z,owner=row.owner,time_since_load=row.time_since_load,time_since_unload=row.time_since_unload}
  end
  local active={coal=Sim.rail_coal_active,goods=Sim.rail_goods_active,oil=Sim.rail_oil_active}
  local function is_road_part(s,id,station)
    local t=at(s.tiles,id)
    return t and (t.station==station or t.tram and t.tram.tram_station==station)
  end
  function M.reactivated_clocks(s,record,at_tick)
    local r=record.stock_reactivation
    if not r then return end
    at_tick=at_tick or Sim.road_station_retirement().clock(s,"rail")
    local ticks=math.max(0,at_tick-r.tick)+r.phase
    local age=math.floor(ticks/rating_ticks)
    return math.min(255,(r.load or 255)+age),math.min(255,(r.unload or 255)+age),ticks%rating_ticks,r.sequence
  end
  function M.resume_service(s,record,ledger)
    local load,unload,phase,sequence=M.reactivated_clocks(s,record)
    if sequence and ledger.stock_reopen_sequence~=sequence then
      ledger.time_since_load,ledger.time_since_unload,ledger.rating_phase=load,unload,phase
      ledger.stock_reopen_sequence=sequence
    end
  end
  function M.view(s,include_idle,at_tick)
    local views={}
    local admitted={rail={},ship={},air={},rig={}}
    local function merge(mode,st,role)
      local id=st.host_id
      local record=at(s[books[mode]],id)
      if not record then return end
      local neutral=Rig.neutral_ref(s,record)
      if st.owner~=record.owner and not (neutral and st.owner==false) then return end
      if role then
        local designation=record[role.."_role"]
        if designation~="load" and designation~="unload" then return end
      end
      local anchor=physical[mode](s,record,id)
      if not anchor then return end
      local slot=admitted[neutral and "rig" or mode]
      local row=slot[id]
      if row then
        -- The newest real load and unload may come from different
        -- controllers, but the source counts one physical StationID.
        row.time_since_load=math.min(row.time_since_load or 255,st.time_since_load or 255)
        row.time_since_unload=math.min(row.time_since_unload or 255,st.time_since_unload or 255)
        return
      end
      local x,z
      if mode=="rail" and record.sign_tile then x,z=Sim.xy(record.sign_tile)
      elseif neutral or mode=="ship" or not st.sign then x,z=Sim.xy(anchor)
      else x,z=st.sign.x,st.sign.y end
      row=project(id,neutral and "ship" or mode,x,z,st)
      slot[id]=row
      views[#views+1]=row
    end
    for _,st in pairs(s.stations or {}) do
      local physical=is_road_part(s,st.tile,st.id)
      if not physical and st.road_members then
        -- The sign can sit over a demolished tile inside the surviving
        -- station's spread. Index the sign, not an arbitrary platform.
        for id in pairs(st.road_members) do
          if is_road_part(s,id,st.id) then physical=true;break end
        end
      end
      if st.mode=="road" and physical and (include_idle or st.town_growth_service_clock) then
        local x,z=Sim.xy(st.tile)
        local clock=st.town_growth_service_clock and st or {owner=st.owner}
        views[#views+1]=project(st.id,"road",x,z,clock)
      end
    end
    local commercial=s.stock_ship_commercial and s.stock_ship_commercial.service
    for _,st in pairs(commercial and commercial.stations or {}) do
      local mode=st.host_mode
      if books[mode] and s[mode.."_paid_service"] then merge(mode,st) end
    end
    for _,cargo in ipairs(freight.all) do
      local state=s["stock_rail_"..cargo]
      if state and ((active[cargo] and active[cargo](s)) or (freight.profiles[cargo] and
          Sim.rail_profile_active and Sim.rail_profile_active(s,cargo))) then
        for _,st in pairs(state.stations or {}) do merge("rail",st,cargo) end
      end
    end
    local coal=s.stock_ship_coal
    if coal and Sim.ship_coal_active and Sim.ship_coal_active(s) then
      for _,st in pairs(coal.stations or {}) do merge("ship",st) end
    end
    local tank=s.stock_oil_ship_service
    if tank and Sim.ship_oil_active and Sim.ship_oil_active(s) then
      for _,st in pairs(tank.stations or {}) do
        if Sim.ship_oil_active(s,st.host_id) then merge("ship",st) end
      end
    end
    local dry=s.stock_goods_ship_service
    if dry and Sim.ship_goods_active and Sim.ship_goods_active(s) then
      for _,st in pairs(dry.stations or {}) do
        if Sim.ship_goods_active(s,st.host_id) then merge("ship",st) end
      end
    end
    local function resumed(mode)
      for id,record in pairs(s[books[mode]] or {}) do
        if record.stock_reactivation and not admitted[mode][id] then
          local load,unload=M.reactivated_clocks(s,record,at_tick)
          if math.min(load,unload)<=20 then
            merge(mode,{host_id=id,owner=record.owner,time_since_load=load,time_since_unload=unload})
          end
        end
      end
    end
    resumed("rail");resumed("air")
    if include_idle then
      -- A new or unserved physical station can already affect council
      -- rating before any carrier has created a service ledger.
      for _,mode in ipairs({"rail","ship","air"}) do
        for id,record in pairs(s[books[mode]] or {}) do
          local neutral=Rig.neutral_ref(s,record)
          if not admitted[neutral and "rig" or mode][id] then
            merge(mode,{host_id=id,owner=record.owner})
          end
        end
      end
    end
    -- RC1 keeps the sign in the station spatial index after the last
    -- facility is removed. The small tick no longer ages its service,
    -- but town growth/rating still count it until the eighth big tick.
    local function inactive(mode,bucket,kind)
      if not s[bucket] then return end
      Sim.road_station_retirement().visit(s,kind,function(st)
        if not include_idle and (st.time_since_load or 255)>20 and (st.time_since_unload or 255)>20 then return end
        local x,z=Sim.xy(st.tile)
        local row=project(st.id,mode,x,z,st)
        if row then views[#views+1]=row end
      end,at_tick)
    end
    inactive("road","retired_road_stations","station")
    inactive("ship","retired_ship_stations","dock")
    inactive("rail","retired_rail_stations","rail")
    inactive("air","retired_airports","airport")
    table.sort(views,function(a,b)
      if a.mode~=b.mode then return modes[a.mode]<modes[b.mode] end
      return a.id<b.id
    end)
    return views
  end
  -- Capture only the town-facing sign and service clocks. Once the last
  -- facility is removed this identity must not remain a route endpoint.
  function M.retire(s,mode,record)
    local kind=assert(({rail="rail",air="airport"})[mode])
    local sign=record.sign_tile or record.origin or record.tile or
      (mode=="rail" and record.tiles and record.tiles[1])
    if not sign then return end
    local dead={id=record.id,owner=record.owner,tile=sign,stock_station_id=record.stock_station_id,
      name=record.name,town=record.town,sequence=record.stock_reactivation and record.stock_reactivation.sequence}
    for _,active in ipairs(M.view(s,true)) do
      if active.mode==mode and active.id==record.id then
        dead.tile=Sim.id(active.x,active.z)
        dead.time_since_load,dead.time_since_unload=active.time_since_load,active.time_since_unload
        break
      end
    end
    Sim.road_station_retirement().retire(s,kind,dead)
  end
  return M
end
