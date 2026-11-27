-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: station_cmd.cpp GetClosestDeletedStation,
-- DeleteStationIfEmpty, StationHandleBigTick; waypoint_cmd.cpp
-- FindDeletedWaypointCloseTo and CmdBuildRoadWaypoint.
return function(Sim)
  local R={}
  local buckets={station="retired_road_stations",waypoint="retired_road_waypoints",
    dock="retired_ship_stations"}
  local function now(s,kind)
    if kind=="dock" and s.passenger_house_clock then return s.passenger_house_clock.counter end
    return s.stock_load_tick or s.day*74
  end
  function R.retire(s,kind,row)
    local key=assert(buckets[kind])
    s[key]=s[key] or {}
    local tick=now(s,kind)
    local first=250-(tick+row.id)%250
    s[key][row.id]={row=row,until_tick=tick+first+7*250}
  end
  function R.get(s,kind,id)
    local map=s[buckets[kind]]
    local entry=map and map[id]
    if entry and now(s,kind)<entry.until_tick then return entry.row end
  end
  function R.take(s,kind,id)
    local row=R.get(s,kind,id)
    if row then s[buckets[kind]][id]=nil end
    return row
  end
  function R.list(s,kind,owner)
    local out={}
    for id in pairs(s[buckets[kind]] or {}) do
      local row=R.get(s,kind,id)
      if row and row.owner==owner then out[#out+1]=row end
    end
    table.sort(out,function(a,b)return a.id<b.id end)
    return out
  end
  function R.closest(s,kind,owner,tile,eligible)
    local closest,threshold=nil,8
    for _,row in ipairs(R.list(s,kind,owner)) do
      local dist=Sim.distance(tile,row.tile)
      if dist<threshold and (not eligible or eligible(row)) then closest,threshold=row,dist end
    end
    return closest
  end
  function R.expire(s)
    for kind,key in pairs(buckets) do
      local tick=now(s,kind)
      for id,entry in pairs(s[key] or {}) do
        if tick>=entry.until_tick then s[key][id]=nil end
      end
    end
  end
  return R
end
