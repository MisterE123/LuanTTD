-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, source pin 14.1. Ordinary fresh docks and ship
-- depots from station_cmd.cpp CmdBuildDock and water_cmd.cpp
-- CmdBuildShipDepot / IsPossibleDockingTile / CheckForDockingTile.
-- Company/town authority, station joins/IDs and actual clearing are supplied
-- by the host. Queries never change tiles.
return function(Track,Water)
  local D={DOCK_BASE_COST=350,DEPOT_BASE_COST=700,BUOY_BASE_COST=350,BUOY_CLEAR_COST=50}
  local up={[12]=0,[6]=1,[3]=2,[9]=3}
  local function check(board,id)
    if id~=nil then return board.tile(id) end
  end
  local function waterclass(t)
    return t and (t.water_class or Water.water_class(t))
  end
  local function budget(plan,opts)
    if opts.budget and plan.cost>opts.budget then return nil,"NOT_ENOUGH_MONEY" end
    return plan
  end
  local function call(fn,...)
    if not fn then return true end
    return fn(...)
  end
  local function ground(t)
    if not t then return false end
    if t.water_ground~=nil then return t.water_ground end
    return t.kind=="sea" or t.kind=="canal" or t.kind=="river" or t.kind=="water" or
      t.kind=="coast" or t.kind=="lock" or t.kind=="ship_depot"
  end
  local function type_water(t)
    if not t then return false end
    if t.is_water_tile~=nil then return t.is_water_tile end
    return t.kind=="sea" or t.kind=="canal" or t.kind=="river" or t.kind=="water" or
      t.kind=="coast" or t.kind=="lock" or t.kind=="ship_depot"
  end
  local function flat(t) return t and (t.slope or 0)==0 end
  local function default_clear(_,t)
    if t.clear_cost~=nil then return t.clear_cost end
    if t.kind=="clear" or t.kind=="sea" or t.kind=="water" or t.kind=="river" or t.kind=="canal" then return 0 end
  end
  function D.direction(slope)
    local incl=up[slope]
    return incl and Track.reverse_side(incl)
  end
  -- The three successive tiles are physical inclined approach, flat
  -- physical dock, then navigable plain-water ground in front. That last
  -- tile is not part of the station rectangle or a required stop.
  function D.dock(board,id,opts)
    opts=opts or {}
    local shore=check(board,id)
    local dir=shore and D.direction(shore.slope)
    if dir==nil or ground(shore) then return nil,"SITE_UNSUITABLE",id end
    local okay,why=call(opts.authority,id)
    if not okay then return nil,why,id end
    if shore.overhead then return nil,"BRIDGE_ABOVE",id end
    local clear=opts.clear or default_clear
    local a,msg=clear(id,shore,false)
    if a==nil then return nil,msg or "CLEAR_LAND",id end
    local pier=board.adjacent(id,dir)
    local wet=check(board,pier)
    if not ground(wet) or not flat(wet) then return nil,"SITE_UNSUITABLE",pier end
    if wet.overhead then return nil,"BRIDGE_ABOVE",pier end
    local class=waterclass(wet)
    if class==nil then return nil,"SITE_UNSUITABLE",pier end
    local b,reason=clear(pier,wet,false)
    if b==nil then return nil,reason or "CLEAR_DOCK_WATER",pier end
    if type_water(wet) then b=0 end
    local head=board.adjacent(pier,dir)
    local open=check(board,head)
    -- CmdBuildDock checks TileType::Water, not IsWaterTile or ship
    -- track bits, for the third tile. A flat ClearRocks tile passes
    -- this construction check without becoming a navigable berth.
    if not flat(open) or not (type_water(open) or open.rocks and open.kind=="sea") then
      return nil,"SITE_UNSUITABLE",head
    end
    local x,z=board.xy(id)
    local u,v=board.xy(pier)
    local area={x=math.min(x,u),z=math.min(z,v),w=dir%2==0 and 2 or 1,h=dir%2==1 and 2 or 1}
    local join,denied=call(opts.station,area)
    if not join then return nil,denied or "STATION_LIMIT",id end
    return budget({kind="dock",land=id,water=pier,approach=head,dir=dir,water_class=class,
      station_area=area,tiles={id,pier},cost=(opts.price or D.DOCK_BASE_COST)+a+b},opts)
  end
  function D.depot(board,id,axis,opts)
    opts=opts or {}
    if axis~=0 and axis~=1 then return nil,"INVALID_AXIS",id end
    if not check(board,id) then return nil,"BUILT_ON_WATER",id end
    local far=board.adjacent(id,axis==0 and 2 or 1)
    local a,b=check(board,id),check(board,far)
    if not ground(a) or not ground(b) then return nil,"BUILT_ON_WATER",(not ground(a) and id or far) end
    if a.overhead or b.overhead then return nil,"BRIDGE_ABOVE",a.overhead and id or far end
    if not flat(a) or not flat(b) then return nil,"SITE_UNSUITABLE",not flat(a) and id or far end
    if not call(opts.depot_slot,id) then return nil,"DEPOT_LIMIT",id end
    local ca,cb=waterclass(a),waterclass(b)
    if not ca or not cb then return nil,"BUILT_ON_WATER",not ca and id or far end
    local clear=opts.clear or default_clear
    local cost=opts.price or D.DEPOT_BASE_COST
    local tiles={id,far}
    for i,t in ipairs({a,b}) do
      local price,why=clear(tiles[i],t,true)
      if price==nil then return nil,why or "CLEAR_DEPOT_WATER",tiles[i] end
      if not type_water(t) then cost=cost+price end
    end
    return budget({kind="ship_depot",axis=axis,tiles=tiles,water_classes={ca,cb},cost=cost},opts)
  end
  -- CmdBuildBuoy, waypoint_cmd.cpp. Ordinary flat water keeps its
  -- WaterClass and tile owner; a waypoint's own owner is OWNER_NONE.
  -- The host can quote DC_AUTO on non-water water-ground if supported.
  function D.buoy(board,id,opts)
    opts=opts or {}
    local t=check(board,id)
    if id==0 or not ground(t) or t.is_coast or t.kind=="coast" then return nil,"BUOY_NEEDS_OPEN_WATER",id end
    if t.overhead then return nil,"BRIDGE_ABOVE",id end
    if not flat(t) then return nil,"BUOY_NEEDS_OPEN_WATER",id end
    local available,why=call(opts.waypoint_slot,id)
    if not available then return nil,why or "STATION_LIMIT",id end
    local cls=waterclass(t)
    if not cls then return nil,"BUOY_NEEDS_OPEN_WATER",id end
    local base=opts.price or D.BUOY_BASE_COST
    if not type_water(t) then
      local price,reason=(opts.clear or default_clear)(id,t,true)
      if price==nil then return nil,reason or "PROTECTED_TILE",id end
      base=base+price
    end
    return budget({kind="buoy",tile=id,tiles={id},water_class=cls,water_owner=t.owner,cost=base},opts)
  end
  local function possibly_docking(board,id,t)
    if t.kind=="lock" and t.part=="middle" then return false end
    return Water.at(board,id)~=0
  end
  -- Ordinary allowed water, depot approaches, buoys, coast/half track,
  -- ends of locks and paired aqueduct heads can be docking springboards.
  -- A physical water-part station object is not itself navigable.
  function D.docking_neighbors(board,pier)
    local result={}
    for dir=0,3 do
      local id=board.adjacent(pier,dir)
      local t=check(board,id)
      if t and possibly_docking(board,id,t) then result[#result+1]=id end
    end
    return result
  end
  return D
end
