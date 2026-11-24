-- Project native map records into the RC1 Temperate rail ground tick.
-- The caller is the single world simulation owner, not the renderer.
return function(Sim,Rules)
  local W={}
  local step_x,step_z={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  local function identify(t)
    if t.house or t.source_house then return "house" end
    if t.stock_industry then return "industry" end
    if t.level_crossing or (t.road_bits or 0)~=0 or t.tram or t.build=="road" or t.build=="road_depot" then return "road" end
    if t.road_bridge_id or t.road_tunnel_id or t.rail_span_id or t.ship and t.ship.aqueduct then return "tunnelbridge" end
    if t.stock_landmark or t.stock_object then return "object" end
    if t.rail_tracks then return "rail" end
    if t.airfield or t.station or t.ship then return "station" end
    if t.wood then return "trees" end
    return t.terrain=="water" and "water" or "clear"
  end
  function W.visit(s,x,z)
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not t or not t.rail_tracks or t.level_crossing or t.rail_station_id or t.rail_waypoint_id then return false end
    local old=t.rail_ground or Rules.BARREN
    local new,water=Rules.visit({ground=old,tracks=t.rail_tracks,owner=t.owner,plain=t.rail_depot_dir==nil},function(d)
      local key=Sim.id(x+step_x[d],z+step_z[d])
      local adjacent=key and s.tiles[key]
      if not adjacent or adjacent.stock_void then return end
      return {kind=identify(adjacent),owner=adjacent.owner,
        owned_land=adjacent.stock_object and adjacent.stock_object.kind=="owned_land"}
    end)
    if water then return false,water end
    if new==old then return false end
    t.rail_ground=new
    return true
  end
  return W
end
