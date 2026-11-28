-- SPDX-License-Identifier: GPL-2.0-only
-- Attach a railway platform to the existing bus station using the stock
-- CmdBuildRailStation / FindJoiningStation command-side selection rules.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local Join=dofile(mod.."openttd/station_join_command.lua")
local Picker=dofile(mod.."openttd/station_join_picker.lua")
return function(Sim)
  local M={}
  local Catalog=dofile(mod.."stock_station_catalog.lua")(Sim)
  function M.quote(s,owner,area,physical)
    if not Sim.stock_joined_station then return nil,"INVALID_STATION" end
    local target,why=Join.target(Catalog.board(s),{tile=Sim.id(area.x,area.z),w=area.w,h=area.h},owner,{
      allow_adjacent=true,join_id=physical,distant=s.stock_distant_join_stations~=false,
      spread=s.stock_station_spread or 12,
    })
    if why then return nil,why end
    if not target or not target.bus_only or target.rail or target.airport or target.dock then
      return nil,"RAIL_JOIN_UNPORTED_FACILITY"
    end
    return target.road
  end
  function M.choices(s,owner,area)
    local choices={{name="Build a separate rail station"}}
    if s.stock_distant_join_stations==false or not Sim.stock_joined_station then return choices end
    local board=Catalog.board(s)
    board.matches=function(row) return row.bus_only and not row.rail and not row.airport and not row.dock end
    local source=Picker.find(board,{tile=Sim.id(area.x,area.z),w=area.w,h=area.h},owner,s.stock_station_spread or 12,true)
    for _,row in ipairs(source) do
      if not row.new then choices[#choices+1]={id=row.id,name=row.name or ("Bus station "..row.id)} end
    end
    return choices
  end
  function M.attach(s,rail,road)
    local Joined=Sim.stock_joined_station
    local group=Joined.attach(s,rail.stock_station_id,rail.owner,"road",road.id)
    Joined.attach(s,rail.stock_station_id,rail.owner,"rail",rail.id)
    group.tile,group.town,group.random_bits=road.tile,road.town or road.site,road.stock_random_bits
    group.facilities=Join.BUS
    Join.add_facility(group,Join.TRAIN,rail.tiles[1],rail.owner,s.day,function() return Sim.stock_random_u32(s) end)
    rail.sign_tile,rail.town,rail.name,rail.stock_random_bits=group.tile,group.town,road.name,group.random_bits
    return group
  end
  function M.group(s,rail)
    return Sim.stock_joined_station and rail.stock_station_id~=nil and
      Sim.stock_joined_station.resolve(s,rail.stock_station_id,"rail",rail.id,rail)
  end
  function M.road_extent(s,rail)
    local group=M.group(s,rail)
    local road=group and Sim.stock_joined_station.member(s,group,"road")
    if not road then return end
    local area=Catalog.enclosing(Sim.road_stop_tiles(road))
    local x,z=Sim.xy(area.tile)
    return {x=x,z=z,w=area.w,h=area.h}
  end
  function M.detach(s,rail)
    return Sim.stock_joined_station and Sim.stock_joined_station.detach_commercial(s,Sim,rail,"rail",Join.TRAIN)
  end
  return M
end
