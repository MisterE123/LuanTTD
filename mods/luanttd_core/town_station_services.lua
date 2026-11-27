-- Native sign/clock adapter for OpenTTD 16.0-RC1 town_cmd.cpp,
-- ForAllStationsNearTown / CountActiveStations. Read actual station
-- ages; an arrival or a planned route alone is not service.
return function(Sim)
  local M={}
  local modes={road=0,rail=1,ship=2,air=3}
  local function at(t,id) return id and t and t[id] end
  local function has_rail(s,record,id)
    for _,cell in ipairs(record.tiles or {}) do
      local t=s.tiles[cell]
      if t and t.rail_station_id==id and not t.rail_waypoint_id then return true end
    end
  end
  local function has_ship(s,record,id)
    local function dock(cell)
      local t=at(s.tiles,cell)
      return t and t.ship and t.ship.kind=="dock" and t.ship.station==id
    end
    for _,d in ipairs(record.docks or {}) do
      if dock(d.land) and dock(d.water) then return true end
    end
    return dock(record.land) and dock(record.water)
  end
  local function has_air(s,record,id)
    for _,part in ipairs(record.tiles or {}) do
      local t=at(s.tiles,part.id)
      if t and t.airfield and t.airfield.airport==id then return true end
    end
  end
  local books={rail="stock_rail_stations",ship="stock_ship_stations",air="stock_small_airports"}
  local physical={rail=has_rail,ship=has_ship,air=has_air}
  local function project(id,mode,x,z,row)
    if not x or not z or not Sim.id(x,z) then return end
    return {id=id,mode=mode,x=x,z=z,time_since_load=row.time_since_load,time_since_unload=row.time_since_unload}
  end
  function M.view(s)
    local views={}
    for _,st in pairs(s.stations) do
      if st.mode=="road" and at(s.tiles,st.tile) and st.town_growth_service_clock then
        local x,z=Sim.xy(st.tile)
        views[#views+1]=project(st.id,"road",x,z,st)
      end
    end
    local commercial=s.stock_ship_commercial and s.stock_ship_commercial.service
    for _,st in pairs(commercial and commercial.stations or {}) do
      local mode,id=st.host_mode,st.host_id
      local record=mode and books[mode] and at(s[books[mode]],id)
      -- A commercial ledger may remain until the next daily bind after a
      -- demolition. Never turn that stale record into a live town boost.
      if record and s[mode.."_paid_service"] and physical[mode](s,record,id) then
        local sign=st.sign
        if sign and sign.x and sign.y then views[#views+1]=project(id,mode,sign.x,sign.y,st) end
      end
    end
    table.sort(views,function(a,b)
      if a.mode~=b.mode then return modes[a.mode]<modes[b.mode] end
      return a.id<b.id
    end)
    return views
  end
  return M
end
