-- SPDX-License-Identifier: GPL-2.0-only
-- Save adapter for RC1's BaseStation identity. Lua mode records keep their
-- private presentation IDs; only a verified facility membership may reuse a
-- physical StationID. Do not serialize pointers to those records here.
local M={}
local pools={
  road="stations",air="stock_small_airports",rail="stock_rail_stations",dock="stock_ship_stations",
}
local function member(s,mode,host)
  local pool=s[assert(pools[mode],"Invalid station facility mode")]
  local row=pool and pool[host]
  if not row or row.neutral or (mode=="road" and row.mode~="road") then return nil end
  return row
end

local function verified(s,group,mode,host,record)
  return record~=nil and group.members[mode]==host and host~=nil and record==member(s,mode,host)
    and record.stock_station_id==group.id and record.owner==group.owner
end

function M.attach(s,physical,owner,mode,host)
  local record=member(s,mode,host)
  assert(record and record.stock_station_id==physical and record.owner==owner,
    "Facility must already belong to the same owner and physical StationID")
  local book=s.stock_joined_stations
  if not book then book={};s.stock_joined_stations=book end
  local group=book[physical]
  if not group then
    group={id=physical,owner=owner,members={}};book[physical]=group
  end
  local previous=group.members[mode]
  assert(group.owner==owner and (previous==nil or previous==host),"Conflicting station facility")
  group.members[mode]=host
  return group
end

function M.resolve(s,physical,mode,host,record)
  local group=s.stock_joined_stations and s.stock_joined_stations[physical]
  if not group then return end
  -- Deliberately require an exact registered mode/ID, not just the same
  -- StationID and owner. A stale retired host is not a physical member.
  if verified(s,group,mode,host,record) then return group end
end

function M.detach(s,physical,mode,host,record)
  local group=assert(M.resolve(s,physical,mode,host,record),"Unknown station facility")
  group.members[mode]=nil
  if not next(group.members) then s.stock_joined_stations[physical]=nil end
  return group
end

function M.member(s,group,mode)
  local host=group.members[mode]
  local record=host and member(s,mode,host)
  assert(not host or record and verified(s,group,mode,host,record),"Stale station facility membership")
  return record
end

-- Current shared station pairs use one road facade and one commercial
-- facade. Keep this distinction explicit until multi-facility groups with
-- more than two modes share the same backend.
function M.commercial_member(group)
  if group.members.air then return "air",group.members.air end
  if group.members.rail then return "rail",group.members.rail end
  if group.members.dock then return "dock",group.members.dock end
end

-- Geometry of the non-road half for spread and sign after road changes.
-- Return ordinary map bounds (not a catchment or a berth).
function M.commercial_bounds(s,group,xy)
  local mode=M.commercial_member(group)
  if not mode then return end
  local record=M.member(s,group,mode)
  if not record then return end
  local minx,minz,maxx,maxz=math.huge,math.huge,-1,-1
  local function add(cell)
    local x,z=xy(cell)
    minx,minz,maxx,maxz=math.min(minx,x),math.min(minz,z),math.max(maxx,x),math.max(maxz,z)
  end
  if mode=="dock" then
    for _,p in ipairs(record.docks or {record}) do add(p.land);add(p.water) end
  else
    for _,cell in ipairs(record.tiles) do add(type(cell)=="table" and cell.id or cell) end
  end
  if maxx>=0 then return record,minx,minz,maxx,maxz end
end

-- Remove only a commercial facility and hand the common clock back to the
-- road facade. The caller still owns removal of the physical facility tiles.
function M.detach_commercial(s,Sim,record,mode,flag)
  local group=record.stock_station_id~=nil and M.resolve(s,record.stock_station_id,mode,record.id,record)
  if not group then return false end
  local road=M.member(s,group,"road")
  local commercial=s.stock_ship_commercial
  local service=group.service_station_id and commercial and commercial.service.stations[group.service_station_id]
  if road then
    local ax,az,bx,bz=math.huge,math.huge,-1,-1
    for _,t in ipairs(Sim.road_stop_tiles(road)) do
      ax,az,bx,bz=math.min(ax,t.x+1),math.min(az,t.y+1),math.max(bx,t.x+1),math.max(bz,t.y+1)
    end
    local x,z=Sim.xy(group.tile)
    group.tile=Sim.id(math.max(ax,math.min(bx,x)),math.max(az,math.min(bz,z)))
    road.tile=group.tile
    if service then
      road.passenger_fraction=service.passenger_fraction
      road.passenger_rating_phase=service.rating_phase
      road.time_since_load,road.time_since_unload=service.time_since_load,service.time_since_unload
      road.last_vehicle_type=service.last_vehicle_type
    end
  end
  M.detach(s,group.id,mode,record.id,record)
  group.service_station_id=nil
  group.facilities=group.facilities-flag
  return next(group.members)~=nil
end

M.mode_by_pool={}
for mode,pool in pairs(pools) do M.mode_by_pool[pool]=mode end
return M
