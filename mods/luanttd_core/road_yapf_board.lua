-- Bridge LuanTTD's saved tiles to the stock OpenTTD 14.1 road APIs.
-- The adapter owns units and save records, never search rules.
return function(Sim,s,F,occupancy)
  local B={}
  local records={}
  local function dir_for_single(bits)
    for i=1,4 do if bits==2^(i-1) then return 4-i end end
  end
  local function load(id)
    local t=id and s.tiles[id]
    if not t then return nil end
    local out={owner=t.owner,roadtype=0}
    if t.build=="stock_road_tunnel" then
      local key=t.road_tunnel_id
      local span=key and s.stock_road_tunnels and s.stock_road_tunnels[key]
      if not span then return nil end
      local head=span.start==id and span.head or span.tail
      out.kind,out.dir,out.id,out.tunnel,out.plan="tunnel",head.inside_direction,id,key,span
      out.other=span.start==id and span["end"] or span.start
      out.skip,out.roadtype=span.middle_length,span.roadtype
    elseif t.build=="stock_road_bridge" then
      -- Bridge metadata belongs to the paired head, never to a ground
      -- tile under the elevated middle (which can itself have a road).
      local key=t.road_bridge_id
      local span=key and s.stock_road_bridges and s.stock_road_bridges[key]
      local head=span and (span.start==id and span.head or span["end"]==id and span.tail)
      if not head then return nil end
      out.kind,out.dir="bridge",head.inside_direction
      out.id,out.head,out.plan,out.span=id,head,span,key
      out.other=span.start==id and span["end"] or span.start
      out.skip,out.bridge_speed=span.middle_length,span.spec.speed
      out.roadtype,out.tramtype=span.roadtype,span.tramtype
    elseif t.build=="road_depot" and t.depot_dir then
      out.kind,out.dir="depot",4-t.depot_dir
    elseif t.build=="road_station" and s.stations[t.station] then
      local st=s.stations[t.station]
      local dir
      local axis=t.stop_axis or Sim.road_bits(s,id)
      if axis==5 or axis==10 then
        -- One unambiguous direction per through axis, as the tile stores it.
        out.kind,out.dir="drive_stop",axis==5 and F.SE or F.NE
      else
        dir=dir_for_single(Sim.road_bits(s,id))
        if dir==nil then return nil end
        out.kind,out.dir="bay_stop",dir
      end
      out.station=t.station
      out.stop_type=Sim.road_stop_tile_kind(st,id,t)
      out.pair=t.road_stop_pair==true and out.kind=="bay_stop" and out.stop_type=="bus"
    elseif t.build=="road" and t.road_waypoint_id then
      local wp=s.stock_road_waypoints and s.stock_road_waypoints[t.road_waypoint_id]
      if not wp or not wp.tiles[id] then return nil end
      local bits=Sim.road_bits(s,id)
      if bits~=10 and bits~=5 then return nil end
      out.kind,out.dir,out.station,out.stop_type="drive_stop",bits==10 and 0 or 1,wp.id,"road_waypoint"
      out.waypoint=true
    elseif t.build=="road" then
      out.kind="road"
      out.road_bits=Sim.road_bits(s,id)
      out.roadworks=t.roadworks
      out.disallowed=t.road_disallowed or t.disallowed or 0
    else
      -- Legacy prototype bridges and tunnels lack paired stock records.
      return nil
    end
    return out
  end
  function B.tile(id)
    if id==nil then return nil end
    if records[id]==nil then records[id]=load(id) or false end
    return records[id] or nil
  end
  B.xy=Sim.xy
  B.tile_at=Sim.id
  function B.adjacent(id,dir)
    return Sim.adjacent(id,4-dir)
  end
  function B.edge_available(from,to,d)
    return Sim.road_geometry_connected(s,from,4-d,to)
  end
  function B.center_z(id)
    return Sim.road_center_z(s,id)
  end

  -- RoadStop::IsDriveThroughRoadStopContinuation: same station index,
  -- facility type and platform direction, not just adjacent pavement.
  function B.stop_continues(id,other)
    local a,b=B.tile(id),B.tile(other)
    return a and b and b.kind=="drive_stop" and a.station==b.station and
      a.stop_type==b.stop_type and a.dir==b.dir or false
  end
  function B.stop_entry(id,d)
    local length,used=16,0
    local function occupied(i)
      return occupancy and occupancy.drive_length and occupancy.drive_length(i,d) or 0
    end
    used=occupied(id)
    for _,direction in ipairs({d,F.reverse_direction(d)}) do
      local other=B.adjacent(id,direction)
      while B.stop_continues(id,other) do
        used=used+occupied(other)
        length=length+16
        other=B.adjacent(other,direction)
      end
    end
    return used,length
  end
  function B.bay_free(id,index)
    return not (occupancy and occupancy.bay_taken and occupancy.bay_taken(id,index))
  end

  -- Current save format uses one tile per station. Don't extrapolate a
  -- multi-tile station from rendered shelters or their catchment area.
  function B.station_area(id,facility)
    if facility=="road_waypoint" then
      local wp=s.stock_road_waypoints and s.stock_road_waypoints[id]
      return wp and wp.area,wp and wp.tile
    end
    local st=s.stations[id]
    if not st then return nil,nil end
    local area=st.road_stop_areas and st.road_stop_areas[facility]
    if area then return area,st.tile end
    local t=B.tile(st.tile)
    if t and t.station==id and t.stop_type==facility then
      return {tile=st.tile,w=1,h=1},st.tile
    end
    return nil,st.tile
  end
  function B.cache_trimmed_station_area(id,facility)
    local st=s.stations[id]
    local t=st and B.tile(st.tile)
    if t and t.kind=="drive_stop" then
      return B.station_area(id,facility)
    end
  end
  return B
end
