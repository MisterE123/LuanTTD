-- SPDX-License-Identifier: GPL-2.0-only
-- Map adapter for the RC1 airport attachment command. Placement changes
-- only the airport facility; it never allocates a replacement road row.
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local Command=dofile(path.."openttd/station_join_command.lua")
local Picker=dofile(path.."openttd/station_join_picker.lua")
return function(Sim)
  local M={}
  local Joined=Sim.stock_joined_station
  local Catalog=dofile(path.."stock_station_catalog.lua")(Sim)
  local function area(airport) return {tile=airport.origin,w=airport.width,h=airport.height} end
  function M.choices(s,airport)
    local board=Catalog.board(s)
    board.matches=function(st) return st.bus_only and not st.airport and not st.rail and not st.dock end
    if s.stock_distant_join_stations==false then return {{name="Build a separate airport"}} end
    local choices=Picker.find(board,area(airport),airport.owner,s.stock_station_spread or 12,true)
    local rows={}
    for i,row in ipairs(choices) do
      rows[i]={id=row.id,name=row.new and "Build a separate airport" or (row.name or ("Bus station "..row.id))}
    end
    return rows
  end
  function M.quote(s,airport,req)
    local target,why=Command.airport_target(Catalog.board(s),area(airport),airport.owner,{
      allow_adjacent=req.adjacent,join_id=req.station_id,new_station=req.new_station,spread=s.stock_station_spread or 12,
      distant=s.stock_distant_join_stations~=false,
    })
    if why then return nil,why end
    if not target then return false end
    if not target.bus_only or target.rail or target.dock then return nil,"AIRPORT_JOIN_UNPORTED_FACILITY" end
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
    return Joined.detach_commercial(s,Sim,airport,"air",Command.AIRPORT)
  end
  return M
end
