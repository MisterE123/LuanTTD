-- Survey actions use the current aimed target. Unlike the optional chat
-- shortcuts, a click on empty space never boards a previously selected
-- vehicle, drops the player at another tile or starts from a nearby airport.
local S={}
function S.use(key,p,api,world)
  if key=="survey_train_cab" or key=="survey_ride_vehicle" then
    local v=api.vehicle_ui
    if not (v and v.ride_toggle) then return false,"Vehicle sightseeing is unavailable here." end
    local target=v.pick(p,42)
    if key=="survey_train_cab" then
      if not target or target.kind~="rail" then return false,"Aim at the train you want to ride, then click." end
      return v.ride_toggle(p,"cab",target)
    end
    if not target then return false,"Aim at a passenger train or bus, then click." end
    return v.ride_toggle(p,"ride",target)
  end

  local tile,hit=world.target(p)
  if key=="survey_walk" then
    if not tile then return false,"Aim at a dry patch of ground, then click." end
    return world.toggle_walk_at(p,tile,hit)
  elseif key=="survey_drive_car" then
    if not tile then return false,"Aim at a connected street, then click." end
    if not (api.car and api.car.toggle_at) then return false,"Driving is unavailable here." end
    return api.car.toggle_at(p,tile,hit)
  elseif key=="survey_fly_plane" then
    if not tile then return false,"Aim at an airport, then click." end
    local plane=api.sightseeing_plane
    if not (plane and plane.board) then return false,"Flying is unavailable here." end
    return plane.board(p,tile)
  end
end
return S
