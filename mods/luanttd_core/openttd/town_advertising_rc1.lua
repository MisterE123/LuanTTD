-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 town_cmd.cpp GetTownActionCost, TownActionAdvertise*
-- and station_cmd.cpp ModifyStationRatingAround (via station_rating.lua).
local A={}
A.campaigns={
  {key="small",name="Small",factor=2,bonus=64,radius=10},
  {key="medium",name="Medium",factor=4,bonus=112,radius=15},
  {key="large",name="Large",factor=9,bonus=160,radius=20},
}
function A.quote(key,price)
  for _,campaign in ipairs(A.campaigns) do
    if key==campaign.key then
      return {key=key,name=campaign.name,cost=math.floor((price or 1000000)*campaign.factor/256),
        bonus=campaign.bonus,radius=campaign.radius}
    end
  end
end
return A
