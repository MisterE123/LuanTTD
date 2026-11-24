-- Convert the pointer's real tile into the station ID expected by the
-- existing order adapters. The worker resolves against current tiles;
-- a projected tile is useful for a hint, never for the actual mutation.
local function owned(st,owner) return st and st.owner==owner end
return function(mode,vehicle,owner,id,t,record)
  if not t then return end
  if mode=="road" then
    local st=record("stations",t.station)
    if owned(st,owner) and st.mode=="road" and not st.tram_only then return t.station,st.name or "Road stop" end
    local wp=t.road_waypoint_id and record("stock_road_waypoints",t.road_waypoint_id)
    if owned(wp,owner) then return "waypoint:"..wp.id,wp.name end
  elseif mode=="rail" then
    local st=record("stock_rail_stations",t.rail_station_id)
    if owned(st,owner) then return t.rail_station_id,st.name or ("Rail station #"..t.rail_station_id) end
  elseif mode=="ship" then
    local f=t.ship
    if not f then return end
    if f.kind=="dock" and owned(record("stock_ship_stations",f.station),owner) then
      return f.station,"Dock #"..f.station
    elseif vehicle=="oil" and f.kind=="oilrig" then
      local st=record("stock_ship_stations",f.station)
      if st and st.neutral and st.oil_rig then return f.station,st.name or "Oil Rig" end
    elseif vehicle=="ferry" and f.kind=="buoy" and type(f.station)=="number" then
      -- Both local/published world tiles carry the buoy ID, but the
      -- adapter checks that it is still in the real buoy registry.
      return "buoy:"..f.station,"Buoy #"..f.station
    end
  elseif mode=="air" then
    local f=t.airfield
    local st=f and record("stock_small_airports",f.airport)
    if st and st.neutral and st.layout=="oilrig" then return f.airport,st.name or "Oil Rig (helicopters only)" end
    if owned(st,owner) then return f.airport,st.layout=="city" and "City Airport" or "Airfield" end
  elseif mode=="tram" then
    local f=t.tram
    if f and f.kind=="drive_stop" and f.owner==owner then
      local st=record("stations",f.shared_station or f.tram_station)
      return id,st and st.name or "Tram stop"
    end
  end
end
