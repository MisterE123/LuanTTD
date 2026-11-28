-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. OpenTTD 16.0-RC1: ClearTile_Town,
-- HouseSpec::GetRemovalCost and ChangeTownRating (town_cmd.cpp).
return function(specs)
  local H={MINIMUM=-1000,MAXIMUM=1000,BASE_PRICE=1600}
  function H.quote(id,current,tolerance,policy,price)
    policy=policy or {}
    local spec=specs[id]
    if not spec then return nil,"UNKNOWN_HOUSE_SPEC" end
    if policy.automatic then return nil,"BUILDING_MUST_BE_DEMOLISHED" end
    if policy.protected then return nil,"BUILDING_IS_PROTECTED" end
    local change=spec[2]
    if not (policy.magic_bulldozer or policy.no_test_rating) then
      if change>H.MAXIMUM then return nil,"BUILDING_IS_PROTECTED" end
      if tolerance~=3 and change>current then return nil,"HOUSE_AUTHORITY_RATING" end
    end
    local new=current
    local change_rating=not (policy.no_modify_rating or policy.magic_bulldozer and change>0)
    if change_rating then
      if change>0 and new>H.MINIMUM then new=math.max(H.MINIMUM,new-change) end
    end
    return {cost=math.floor((price or H.BASE_PRICE)*spec[1]/256),
      before=current,after=new,penalty=change,change_rating=change_rating}
  end
  return H
end
