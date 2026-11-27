-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 src/town_cmd.cpp RoadTypesAllowHouseHere.
local M={}

-- Read the eight surrounding tiles. A nil result means neither road nor
-- road stop; false means road infrastructure present without an eligible
-- road type. One eligible road is enough regardless of other neighbors.
function M.allows(read,x,z)
  local found=false
  for dx=-1,1 do
    for dz=-1,1 do
      if dx~=0 or dz~=0 then
        local allows=read(x+dx,z+dz)
        if allows then return true end
        if allows==false then found=true end
      end
    end
  end
  return not found
end

-- Adapt physical Luanti tiles to the stock query. Its road-type lookup
-- considers only the ordinary road layer, not the stock electric tram.
function M.on_board(Sim,s)
  local function read(x,z)
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not t or t.stock_void or t.road_bridge_id or t.road_tunnel_id or
        t.road_waypoint_id then return end
    local crossing=t.level_crossing
    if crossing then return not not (crossing.roadtype~=nil and (crossing.road_bits or 0)~=0) end
    if t.build=="road_depot" or t.build=="road_station" then return true end
    if t.build=="road" and (t.road_bits or 0)~=0 then return true end
    local tram=t.tram
    if tram and (tram.kind=="road" or tram.kind=="drive_stop" or tram.kind=="depot") then return false end
    if t.build=="road" then return false end
  end
  return function(x,z) return M.allows(read,x,z) end
end

return M
