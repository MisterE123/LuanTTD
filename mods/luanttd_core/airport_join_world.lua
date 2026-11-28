-- SPDX-License-Identifier: GPL-2.0-only
-- Map adapter for the RC1 airport attachment command. Placement changes
-- only the airport facility; it never allocates a replacement road row.
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local Command=dofile(path.."openttd/station_join_command.lua")
local Picker=dofile(path.."openttd/station_join_picker.lua")
return function(Sim)
  local M={}
  local Joined=Sim.stock_joined_station
  local function enclosing(cells)
    local ax,az,bx,bz=math.huge,math.huge,-1,-1
    for _,c in ipairs(cells) do
      ax,az,bx,bz=math.min(ax,c.x),math.min(az,c.y),math.max(bx,c.x),math.max(bz,c.y)
    end
    if bx>=0 then return {tile=Sim.id(ax+1,az+1),w=bx-ax+1,h=bz-az+1} end
  end

  local function make_board(s)
    local catalog={}
    local function register(mode,host,row)
      local id=row and row.stock_station_id
      if id==nil or row.neutral then return end
      local group=Joined.resolve(s,id,mode,host,row)
      local target=catalog[id]
      if not target then target={id=id,owner=row.owner};catalog[id]=target
      elseif not group or group~=target.group then error("Conflicting airport join StationID") end
      target.group=group
      if mode=="road" then
        target.road,target.name=host,row.name
        target.spread=enclosing(Sim.road_stop_tiles(row))
        target.bus_only=Sim.road_stop_has(row,"bus") and not Sim.road_stop_has(row,"truck") and not row.tram_only
      elseif mode=="air" then target.airport=host
      else target.unsupported=true end
      return target
    end
    for host,row in pairs(s.stations or {}) do
      if row.mode=="road" then register("road",host,row) end
    end
    for host,row in pairs(s.stock_small_airports or {}) do register("air",host,row) end
    for host,row in pairs(s.stock_rail_stations or {}) do register("rail",host,row) end
    for host,row in pairs(s.stock_ship_stations or {}) do register("dock",host,row) end
    local function at(cell)
      local t=s.tiles[cell]
      if not t then return end
      local st
      local road=t.station or t.tram and t.tram.tram_station
      if road then st=(s.stations or {})[road]
      elseif t.airfield then st=(s.stock_small_airports or {})[t.airfield.airport]
      elseif t.rail_station_id and not t.rail_waypoint_id then st=(s.stock_rail_stations or {})[t.rail_station_id]
      elseif t.ship and t.ship.kind=="dock" then st=(s.stock_ship_stations or {})[t.ship.station] end
      return st and st.stock_station_id~=nil and catalog[st.stock_station_id] or nil
    end
    return {xy=Sim.xy,id=Sim.id,station_at=at,
      station=function(id) return catalog[id] end,matches=function() return true end}
  end
  local function area(airport) return {tile=airport.origin,w=airport.width,h=airport.height} end
  function M.choices(s,airport)
    local board=make_board(s)
    board.matches=function(st) return st.bus_only and not st.airport and not st.unsupported end
    if s.stock_distant_join_stations==false then return {{name="Build a separate airport"}} end
    local choices=Picker.find(board,area(airport),airport.owner,s.stock_station_spread or 12,true)
    local rows={}
    for i,row in ipairs(choices) do
      rows[i]={id=row.id,name=row.new and "Build a separate airport" or (row.name or ("Bus station "..row.id))}
    end
    return rows
  end
  function M.quote(s,airport,req)
    local target,why=Command.airport_target(make_board(s),area(airport),airport.owner,{
      allow_adjacent=req.adjacent,join_id=req.station_id,new_station=req.new_station,spread=s.stock_station_spread or 12,
      distant=s.stock_distant_join_stations~=false,
    })
    if why then return nil,why end
    if not target then return false end
    if not target.bus_only or target.unsupported then return nil,"AIRPORT_JOIN_UNPORTED_FACILITY" end
    return target.road
  end

  function M.attach(s,airport,road)
    local id,owner=road.stock_station_id,road.owner
    local group=Joined.attach(s,id,owner,"road",road.id)
    Joined.attach(s,id,owner,"air",airport.id)
    group.tile,group.town,group.random_bits=road.tile,road.town or road.site,road.stock_random_bits
    group.facilities=(Sim.road_stop_has(road,"bus") and Command.BUS or 0)+
      (Sim.road_stop_has(road,"truck") and 2 or 0)
    Command.add_facility(group,Command.AIRPORT,airport.origin,owner,
      s.day,function() return Sim.stock_random_u32(s) end)
    airport.sign_tile,airport.name,airport.town,airport.stock_random_bits=group.tile,road.name,group.town,group.random_bits
    return group
  end

  function M.detach(s,airport)
    local group=airport.stock_station_id~=nil and Joined.resolve(s,airport.stock_station_id,"air",airport.id,airport)
    if not group then return false end
    local road=Joined.member(s,group,"road")
    local commercial=s.stock_ship_commercial
    local service=group.service_station_id and commercial and commercial.service.stations[group.service_station_id]
    if road then
      local bounds=enclosing(Sim.road_stop_tiles(road))
      local x,z=Sim.xy(group.tile)
      local u,v=Sim.xy(bounds.tile)
      group.tile=Sim.id(math.max(u,math.min(u+bounds.w-1,x)),math.max(v,math.min(v+bounds.h-1,z)))
      road.tile=group.tile
    end
    if road and service then
      road.passenger_fraction=service.passenger_fraction
      road.passenger_rating_phase=service.rating_phase
      road.time_since_load,road.time_since_unload=service.time_since_load,service.time_since_unload
      road.last_vehicle_type=service.last_vehicle_type
    end
    Joined.detach(s,group.id,"air",airport.id,airport)
    group.service_station_id=nil
    group.facilities=group.facilities-Command.AIRPORT
    return next(group.members)~=nil
  end
  return M
end
