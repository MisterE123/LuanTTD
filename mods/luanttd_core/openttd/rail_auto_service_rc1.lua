-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 Vehicle::NeedsAutomaticServicing,
-- Vehicle::NeedsServicing, CheckIfTrainNeedsService, and
-- YapfTrainFindNearestDepot. These decisions don't move or service a body;
-- callers must apply the correct existing order, path and depot lifecycle.
local S={default_max_penalty=2000,infinite_reverse_penalty=100000}
local floor=math.floor

function S.due(vehicle,settings,engine_reliability,date)
  if settings.interval==0 or vehicle.stopped or vehicle.crashed or vehicle.has_depot_order or
     vehicle.loading or vehicle.depot_target and not vehicle.depot_service then return false end
  if settings.percent then
    if vehicle.reliability>=floor(engine_reliability*(100-settings.interval)/100) then return false end
  elseif vehicle.date_of_last_service+settings.interval*(settings.wallclock and 30 or 1)>=date then
    return false
  end
  return not settings.no_servicing_if_no_breakdowns or settings.breakdowns~=0 or
    settings.can_autoreplace and settings.can_autoreplace() or false
end

function S.decision(vehicle,settings,search,random)
  if vehicle.all_in_depot then return {kind="service_here"} end
  local max_penalty=settings.max_penalty or S.default_max_penalty
  local found=search(max_penalty,S.infinite_reverse_penalty)
  if not found or found.cost>max_penalty then
    if vehicle.depot_target then return {kind="cancel_depot"} end
    return
  end
  -- RC1 Chance16(3,16) consumes a draw only when rerouting an
  -- existing service order to a different depot.
  if vehicle.depot_target and vehicle.depot_target~=found.tile and
     floor(((random()%65536)*16+8)/65536)>=3 then return end
  return {kind="go_to_depot",route=found.route,tile=found.tile,
    service=true,nearest=true,nonstop=true,suppress_implicit=true}
end

return S
