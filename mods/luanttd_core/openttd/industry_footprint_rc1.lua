-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 CheckIfIndustryTilesAreFree,
-- IsSlopeRefused and CheckIfIndustryTileSlopes in industry_cmd.cpp.
local M={}
M.WATER_CHECK=65535
local function bit(v,b) return math.floor(v/b)%2==1 end
function M.slope_refused(current,refused)
  if bit(current,16) then return true end
  if current==0 then return false end
  if bit(refused,16) then return true end
  local complement=15-current
  local w,s,e,n=bit(complement,1),bit(complement,2),bit(complement,4),bit(complement,8)
  return bit(refused,1) and (n or w) or bit(refused,2) and (n or e)
    or bit(refused,4) and (s or w) or bit(refused,8) and (s or e)
end
-- The port reads physical ground, not the 3D mesh. The host supplies
-- native skip/clear checks and a ground lookup bounded by TileAddWrap.
function M.tiles_free(layout,refused,x,z,spec,board)
  local physical={}
  for _,part in ipairs(layout) do
    local u,v,gfx=x+part[1],z+part[2],part[3]
    local t=board.tile(u,v)
    if not t or not t.valid then return nil,"SITE_UNSUITABLE" end
    if gfx==M.WATER_CHECK then
      if not t.water or t.slope~=0 then return nil,"SITE_UNSUITABLE" end
    else
      if t.vehicle then return nil,"VEHICLE_IN_THE_WAY" end
      if t.bridge_above then return nil,"SITE_UNSUITABLE" end
      local mask=assert(refused[gfx],"Missing stock industry tile spec")
      if not bit(mask,32) and (not not t.on_water)~=(not not spec.built_on_water) then
        return nil,"SITE_UNSUITABLE"
      end
      local town_clear=spec.only_in_town or spec.town_1200 or spec.only_near_town and t.house
      if town_clear and not t.house then return nil,"CAN_ONLY_BE_BUILT_IN_TOWNS" end
      local ok,reason=board.clear(u,v,t,town_clear and "town" or "company",
        not town_clear,not town_clear,not town_clear)
      if not ok then return nil,reason end
      physical[#physical+1]={x=u,z=v,gfx=gfx,slope=t.slope}
    end
  end
  return physical
end
function M.slopes(physical,refused,terragenesis,generating_world,ignore)
  for _,tile in ipairs(physical) do
    if M.slope_refused(tile.slope,refused[tile.gfx]) then
      if terragenesis and generating_world and not ignore then return true,true end
      return false,"SITE_UNSUITABLE"
    end
  end
  return true,false
end
return M
