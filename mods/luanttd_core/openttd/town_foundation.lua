-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 town_cmd.cpp: TerraformTile_Town, GetFoundation_Town,
-- and DrawTile_Town. Original HouseSpecs have no NotSloped flag and no
-- NewGRF autoslope callbacks; keep these decisions explicit for callers.
local T={}
function T.level(shape,base)
  return base+(shape>=16 and 2 or shape~=0 and 1 or 0)
end
function T.autoslope(old_shape,old_base,new_shape,new_base,policy,not_sloped)
  if (policy and policy.autoslope==false) or not_sloped or new_shape>=16 then return end
  if T.level(old_shape,old_base)~=T.level(new_shape,new_base) then return end
  return policy and policy.foundation_price or 250
end
return T
