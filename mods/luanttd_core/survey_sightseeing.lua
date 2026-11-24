-- Survey actions use the current aimed target. Unlike the optional chat
-- shortcuts, a click on empty space never boards a previously selected
-- vehicle, drops the player at another tile or starts from a nearby airport.
local S={}
function S.use(key,p,api,world)
  local tile,hit=world.target(p,key=="survey_walk")
  if key=="survey_walk" then
    if not tile then return false,"Aim at open ground, a bridge deck or water, then click." end
    return world.toggle_walk_at(p,tile,hit)
  elseif key=="survey_drive_car" then
    if not tile then return false,"Aim at a connected street, then click." end
    if not (api.car and api.car.toggle_at) then return false,"Driving is unavailable here." end
    return api.car.toggle_at(p,tile,hit)
  end
end
return S
