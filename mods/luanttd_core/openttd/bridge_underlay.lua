-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, CheckBuildAbove and CheckBuildAbove_* tile handlers.
-- Copyright OpenTTD contributors. Geometry and mutation are supplied by
-- the caller; Quote is pure. Height is expressed in shared-corner levels.
local U={}
local function station(h,blocked) return {height=h,blocked=blocked or 0} end
-- Pillar flags use BridgePillarFlag's order from bridge_type.h.
local edge_ne,edge_se,edge_sw,edge_nw=16,32,64,128
local west,south,east,north=1,2,4,8
local x_edges,y_edges=edge_ne+edge_sw,edge_se+edge_nw
local x_platform,y_platform=station(2,x_edges),station(2,y_edges)
local unbridgeable=station(0,255)
local unused=unbridgeable
local stop={[0]=station(2,edge_ne),station(2,edge_se),station(2,edge_sw),station(2,edge_nw),
  x_platform,y_platform}
-- _station_bridgeable_info in src/table/station_land.h.
local stations={
  rail={[0]=x_platform,y_platform,x_platform,y_platform,
    station(5,x_edges+edge_se+east+south),station(5,y_edges+edge_sw+south+west),
    station(5,x_edges+edge_nw+north+west),station(5,y_edges+edge_ne+north+east)},
  rail_waypoint={[0]=x_platform,y_platform},
  dock={[0]=station(2),station(2),station(2),station(2),station(3),station(3)},
  buoy={[0]=station(1)}, oilrig={}, airport={},
  bus=stop, truck=stop,
  road_waypoint={[0]=unused,unused,unused,unused,x_platform,y_platform},
}
local lock={middle=2,lower=3,upper=2}
local min_depot=3 -- MINIMAL_DEPOT_BRIDGE_HEIGHT from src/depot_type.h.
local station_error={rail="STATION",rail_waypoint="RAIL_WAYPOINT",dock="DOCK",
  buoy="BUOY",bus="ROADSTOP",truck="ROADSTOP",road_waypoint="ROAD_WAYPOINT"}
-- stock (no StationSpec) RailStationTileLayout<StationType::Rail>.
-- Position starts at zero and walks along each platform before the next.
function U.rail_gfx(tracks,length,track,along,axis)
  local graphic
  if length==1 then graphic=track==math.floor((tracks-1)/2) and 2 or 0
  elseif track==0 and tracks%2==1 then graphic=along==math.floor((length-1)/2) and 2 or 0
  elseif length>4 and (along==0 or along==length-1) then graphic=0
  else graphic=track%2==tracks%2 and 4 or 6 end
  return graphic+axis
end
function U.station_info(kind,layout)
  local t=stations[kind]
  local r=t and t[layout]
  if not r then return 0,255 end
  return r.height,r.blocked
end

local function clearance(t,height,above,tag)
  local diff=t.max_z+height-above
  if diff<=0 then return 0 end
  return nil,"BRIDGE_TOO_LOW_FOR_"..tag,diff*8
end

-- MP_CLEAR always allows an overhead bridge (ClearTileProcs in clear_cmd.cpp).
-- opts.clear(t, auto) optionally delegates normal landscape-clear
-- permission/cost and returns (price, error, clear_ground).
-- Returns (cost, error, extra) where extra is pixel height on denial
-- or the delegated clear_ground bit on approval.
function U.quote(t,axis,deck,opts)
  local clear=opts and opts.clear
  local k=t.kind
  if k=="clear" or k=="road" or k=="crossing" or k=="rail" or k=="plain_rail" or
      k=="signals" or k=="shore_rail" and t.plain~=false or k=="tunnel" or k=="water" or
      k=="sea" or k=="river" or k=="canal" or k=="coast" then return 0 end
  if k=="road_depot" then return clearance(t,min_depot,deck,"ROADVEH_DEPOT") end
  if k=="rail_depot" then return clearance(t,min_depot,deck,"TRAIN_DEPOT") end
  if k=="ship_depot" then return clearance(t,min_depot,deck,"SHIP_DEPOT") end
  if k=="lock" and lock[t.part] then return clearance(t,lock[t.part],deck,"LOCK") end
  if k=="station" then
    local height=U.station_info(t.station_type,t.layout)
    if height~=0 then return clearance(t,height,deck,station_error[t.station_type]) end
    if clear then return clear(t,true) end
    return nil,"BRIDGE_MIDDLE_OBSTRUCTED"
  end
  if k=="object" and t.allow_under_bridge then
    return clearance(t,t.object_height,deck,"OBJECT")
  end
  if k=="bridge" or k=="aqueduct" then
    if axis~=t.axis and deck>t.deck then return 0 end
  end
  if clear then return clear(t,false) end
  return nil,"BRIDGE_MIDDLE_OBSTRUCTED"
end
return U
