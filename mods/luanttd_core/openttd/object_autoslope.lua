-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 object_cmd.cpp: TerraformTile_Object, restricted to
-- original stock specs (no callbacks) and ordinary company construction.
-- nil delegates to the LandscapeClear fallback (protected in normal play).
local M={}
function M.quote(kind,owns,old_shape,old_base,new_shape,new_base,policy)
  if kind=="owned_land" then return owns and 0 or nil end
  if kind~="statue" and kind~="headquarters" then return end
  if policy and policy.autoslope==false then return end
  if old_shape>=16 or new_shape>=16 then return end
  local old_top=old_base+(old_shape~=0 and 1 or 0)
  local new_top=new_base+(new_shape~=0 and 1 or 0)
  if old_top~=new_top then return end
  return policy and policy.foundation_price or 250
end
return M
