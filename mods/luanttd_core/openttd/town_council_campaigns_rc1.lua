-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 GetTownActionCost, GetMaskOfTownActions,
-- TownActionBuyRights and TownActionBribe.
local A={}
local floor,min=math.floor,math.min
A.PRICE=1000000
A.actions={
  exclusive_rights={factor=117,bonus=130,radius=17},
  bribe={factor=175},
}
function A.quote(key,town,owner,rating,money,settings,price)
  local a=A.actions[key]
  if not a then return nil,"INVALID_TOWN_ACTION" end
  if settings.bribe~=false and town.unwanted and (town.unwanted[owner] or 0)>0 then
    return nil,"UNWANTED_COMPANY"
  end
  if key=="exclusive_rights" and (settings.exclusive_rights==false or town.exclusivity or (town.exclusive_counter or 0)>0) then
    return nil,"RIGHTS_UNAVAILABLE"
  end
  if key=="bribe" and (settings.bribe==false or rating>=800 and
    (town.exclusivity==owner or (town.exclusive_counter or 0)==0)) then
    return nil,"BRIBE_UNAVAILABLE"
  end
  local cost=floor((price or A.PRICE)*a.factor/256)
  if cost>money then return nil,"NOT_ENOUGH_CASH" end
  return {key=key,cost=cost,bonus=a.bonus,radius=a.radius}
end
function A.execute(quote,town,owner,rating,random,station_bonus,clear_ratings)
  if quote.key=="exclusive_rights" then
    town.exclusive_counter,town.exclusivity=12,owner
  elseif quote.key=="bribe" then
    local failed=floor(((random()%65536)*14+7)/65536)<1
    if failed then
      town.unwanted=town.unwanted or {}
      town.unwanted[owner]=6
      clear_ratings(owner,town.id)
      return min(rating,-50),false
    end
    if town.exclusivity and town.exclusivity~=owner then
      town.exclusive_counter,town.exclusivity=0,nil
    end
    return rating<800 and min(800,rating+200) or rating,true
  end
  station_bonus(owner,town.x,town.z,quote.bonus,quote.radius)
  return rating,true
end
return A
