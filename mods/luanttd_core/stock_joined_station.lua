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

M.mode_by_pool={}
for mode,pool in pairs(pools) do M.mode_by_pool[pool]=mode end
return M
