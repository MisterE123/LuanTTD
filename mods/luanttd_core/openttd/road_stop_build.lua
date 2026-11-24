-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. 16.0-RC1: src/station_cmd.cpp CheckBuildableTile,
-- CheckFlatLandRoadStop and CalculateRoadStopCost, src/depot_func.h
-- CanBuildDepotByTileh, and src/table/pricebase.h.
local R={base_stop=200,base_depot=500,base_foundation=250}
local entrances={[0]=12,6,3,9} -- stock NE, SE, SW, NW
local roadaxes={[0]=10,5}
local masks={1,2,4,8}
local function has(n,m) return math.floor(n/m)%2==1 end
local function combine(a,b,test)
  local out=0
  for _,m in ipairs(masks) do if test(has(a,m),has(b,m)) then out=out+m end end
  return out
end
local function band(a,b) return combine(a,b,function(x,y)return x and y end) end
local function both(a,b) return combine(a,b,function(x,y)return x or y end) end
local function count(n)
  local pieces=0
  for _,m in ipairs(masks) do if has(n,m) then pieces=pieces+1 end end
  return pieces
end
function R.depot_facing(dir,tileh)
  local edge=entrances[dir]
  if not edge then return false end
  if tileh==0 then return true end
  local raised=band(tileh,edge)
  if tileh>=16 then return raised==edge end
  return raised~=0
end
function R.foundation(tileh,z,dir,through,allowed,settings)
  if not entrances[dir] then return nil,"PARAMETERS" end
  local steep=tileh>=16
  if (through and steep) or (tileh~=0 and settings.build_on_slopes==false) then return nil,"FLAT_LAND_REQUIRED" end
  local flat_z=z
  local cost=0
  if tileh~=0 then
    if not R.depot_facing(dir,tileh) or through and not R.depot_facing((dir+2)%4,tileh) then return nil,"FLAT_LAND_REQUIRED" end
    flat_z=z+(steep and 2 or 1)
    cost=settings.foundation or R.base_foundation
  end
  if allowed~=nil and flat_z~=allowed then return nil,"FLAT_LAND_REQUIRED" end
  return cost,flat_z
end
local function axis_match(axis,bits)
  if band(bits,roadaxes[1-axis])==0 then return true end
  local n=count(bits)
  if n==1 or n==2 and (bits==10 or bits==5) then return nil,"DRIVE_THROUGH_DIRECTION" end
  if n==2 then return nil,"DRIVE_THROUGH_CORNER" end
  return nil,"DRIVE_THROUGH_JUNCTION"
end
local function check_type(tile,kind,opts)
  local way=tile[kind]
  local r=opts.requested_type
  local wanted=r and r.kind==kind
  local cost=0
  if way then
    local pieces=count(way.bits)
    if kind=="road" and way.owner=="town" then
      if opts.on_town_road==false then return nil,"DRIVE_THROUGH_ON_TOWN_ROAD" end
    elseif way.owner~=nil and way.owner~=opts.company and way.owner~="none" and
      (opts.on_competitor_road==false or kind=="tram" and pieces==1 or kind=="road" and (way.disallowed or 0)~=0) then
      return nil,"OWNED_BY"
    end
    if wanted and opts.power and not opts.power(r.roadtype,way.roadtype) then return nil,"NO_SUITABLE_ROAD" end
    cost=opts.piece_price(way.roadtype)*(2-pieces)
  elseif wanted then
    cost=opts.piece_price(r.roadtype)*2
  end
  return cost
end
-- One tile from CalculateRoadStopCost. Bridge-underlay allowance and
-- clear-land command come from the owner, never the UI. Ownership, axis,
-- price, and ground occupancy are revalidated on placement.
function R.tile(t,request,opts,allowed_z)
  if not t or type(t.slope)~="number" or type(t.base)~="number" or not entrances[request.dir] then return nil,"PARAMETERS" end
  if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
  local price,z=R.foundation(t.slope,t.base,request.dir,request.through,allowed_z,opts)
  if price==nil then return nil,z end
  if t.bridge_forbidden then return nil,t.bridge_reason or "MUST_DEMOLISH_BRIDGE_FIRST" end
  local axis=request.dir%2
  if t.kind=="station" then
    if t.stop_type~=request.stop_type or t.through~=request.through then return nil,"INCOMPATIBLE_STATION_TILE" end
    if request.through and t.axis~=axis then return nil,"DRIVE_THROUGH_DIRECTION" end
    return {station=t.station,z=z,cost=0}
  elseif request.through and t.kind=="road" then
    local bits=both(t.road and t.road.bits or 0,t.tram and t.tram.bits or 0)
    local ok,why=axis_match(axis,bits)
    if not ok then return nil,why end
    for _,kind in ipairs{"road","tram"} do
      local cost,why=check_type(t,kind,opts)
      if cost==nil then return nil,why end
      price=price+cost
    end
  elseif not opts.requested_type then
    return nil,"NO_ROAD"
  else
    local cost,why=opts.clear(t)
    if cost==nil then return nil,why end
    price=price+cost+opts.piece_price(opts.requested_type.roadtype)*2
  end
  return {z=z,cost=price+(opts.unit_price or R.base_stop),through=request.through,axis=axis}
end
-- CmdBuildRoadDepot. The GUI's ConnectRoadToStructure posts a separate
-- build after this succeeds; this command itself doesn't demand a road.
function R.depot(t,request,opts)
  if not t or not entrances[request.dir] or request.roadtype==nil then return nil,"PARAMETERS" end
  local price=0
  local elevation=t.base
  if t.slope~=0 then
    if opts.build_on_slopes==false then return nil,"FLAT_LAND_REQUIRED" end
    if not R.depot_facing(request.dir,t.slope) then return nil,"LAND_SLOPED_IN_WRONG_DIRECTION" end
    price=opts.foundation or R.base_foundation
    elevation=elevation+(t.slope>=16 and 2 or 1)
  end
  local rotate=t.kind=="depot" and t.roadtype==request.roadtype
  if rotate then
    if t.owner~=opts.company then return nil,"OWNED_BY" end
    if request.dir==t.dir then return {cost=0,dir=request.dir,unchanged=true,z=elevation} end
    if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
  else
    local clear,why=opts.clear(t)
    if clear==nil then return nil,why end
    price=price+clear
    if t.bridge_deck and t.bridge_deck<(t.top or elevation)+(opts.minimum_bridge_height or 3) then
      return nil,"BRIDGE_TOO_LOW_FOR_ROADVEH_DEPOT"
    end
    if opts.can_allocate==false then return nil,"NO_DEPOT_SLOTS" end
  end
  return {cost=price+(opts.depot_price or R.base_depot),dir=request.dir,rotate=rotate,z=elevation}
end
return R
