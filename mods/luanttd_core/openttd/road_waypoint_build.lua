-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. RC1 waypoint_cmd.cpp GetAxisForNewRoadWaypoint
-- and CmdBuildRoadWaypoint stock path (no NewGRF callbacks).
return function(Stop)
  local W={}
  local function has(mask,piece) return math.floor(mask/piece)%2==1 end
  function W.axis(t)
    if not t then return end
    if t.kind=="station" and t.stop_type=="road_waypoint" then return t.axis end
    if t.kind~="road" then return end
    local r=t.road and t.road.bits or 0
    local a=t.tram and t.tram.bits or 0
    local y=has(r,1) or has(r,4) or has(a,1) or has(a,4)
    local x=has(r,2) or has(r,8) or has(a,2) or has(a,8)
    if not y then return 0 elseif not x then return 1 end
  end
  function W.footprint(board,first,last,axis,limit)
    local x,z=board.xy(first)
    local u,v=board.xy(last)
    if not (x and u and (axis==0 and x==u or axis==1 and z==v)) then return nil,"PARAMETERS" end
    local count=axis==0 and math.abs(v-z)+1 or math.abs(u-x)+1
    if count>(limit or 12) then return nil,"STATION_SPREAD" end
    local ids={}
    for zz=math.min(z,v),math.max(z,v) do
      for xx=math.min(x,u),math.max(x,u) do ids[#ids+1]=assert(board.id(xx,zz)) end
    end
    return ids
  end
  -- Stock CalculateRoadStopCost uses INVALID_ROADTYPE for an
  -- existing-road-only waypoint. Keep the pavement and owner metadata
  -- for the receiving station adapter; don't replace it with a route.
  function W.quote(board,first,last,axis,opts)
    local ids,why=W.footprint(board,first,last,axis,opts.limit)
    if not ids then return nil,why end
    local options={}
    for k,v in pairs(opts) do options[k]=v end
    options.requested_type=nil
    local q={cost=0,changes={},ids=ids}
    local request={dir=axis,through=true,stop_type="road_waypoint"}
    local existing,z=nil,nil
    for _,id in ipairs(ids) do
      local t=board.tile(id)
      local result,reason=Stop.tile(t,request,options,z)
      if not result then return nil,reason end
      if existing and result.station and existing~=result.station then return nil,"ADJOINS_MULTIPLE_WAYPOINTS" end
      existing=existing or result.station
      z=result.z
      q.cost=q.cost+result.cost
      q.changes[#q.changes+1]={id=id,axis=axis,z=z,road=t.road,tram=t.tram,station=result.station}
    end
    q.existing,q.z=existing,z
    return q
  end
  return W
end
