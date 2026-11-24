-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. OpenTTD 16.0-RC1 station_cmd.cpp
-- GetAirportNoiseLevelForDistance / AirportGetNearestTown and
-- town.h Town::MaxTownNoise. Pure airport/town calculations.
local A={}
function A.for_distance(level,distance,tolerance)
  if level<2 then return level end
  local reduction=math.floor(distance/(8+tolerance*4))
  return reduction>=level and 1 or level-reduction
end
function A.town_capacity(population,divisor)
  if population==0 then return 0 end
  return math.min(65535,math.floor(population/divisor)+3)
end
-- Examine only occupied airport perimeter cells, not the rectangular
-- envelope if a layout has holes. Town coordinates are integer tiles.
function A.closest(tiles,width,height,towns)
  local nearest,dist
  for _,cell in ipairs(tiles) do
    local px,pz=cell.local_x,cell.local_z
    if px==0 or pz==0 or px==width-1 or pz==height-1 then
      for _,town in pairs(towns) do
        local d=math.abs(cell.x-town.x)+math.abs(cell.z-town.z)
        if not dist or d<dist or d==dist and town.id<nearest.id then
          nearest,dist=town,d
        end
      end
    end
  end
  return nearest,dist
end
return A
