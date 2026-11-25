-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors, road_cmd.cpp DrawTile_Road:
-- Temperate Crossings, both overlay and standard rail sprite branches.
-- Barren and Grass have dedicated grounds; every other Roadside uses
-- paved ground. This is separate from the road bit/vehicle logic.
local M={}
function M.temperate(roadside)
  if roadside==nil or roadside=="barren" then return "barren" end
  if roadside=="grass" then return "grass" end
  return "paved"
end
-- Same source file, GetRoadGroundSprite with no road type (tram only).
function M.pure_tram(roadside,works)
  if works=="grass" or works=="paved" then return works end
  if roadside=="grass_works" then return "grass" end
  return M.temperate(roadside)
end
return M
