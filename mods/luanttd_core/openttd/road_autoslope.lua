-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 road_cmd.cpp TerraformTile_Road and autoslope.h.
-- The native command supplies the confirmed current tile and company.
return function(Road,Slope,Stops)
  local R={}
  local function active(opts)
    return opts.build_on_slopes~=false and opts.autoslope~=false
  end
  local function max_z(base,mask)
    return base+(mask==0 and 0 or mask>=16 and 2 or 1)
  end
  function R.normal(bits,old_mask,old_base,new_mask,new_base,opts)
    opts=opts or {}
    if bits==0 or not active(opts) then return end
    -- CheckRoadSlope is called as if these combined road/tram bits were
    -- being laid in empty land. Autocompleting a missing piece is NOT an
    -- autoslope-eligible result.
    local pieces=Road.prepare(new_mask,bits,0,0,true)
    if pieces~=bits then return end
    local old,old_dz=Slope.foundation(old_mask,Road.foundation(old_mask,bits))
    local new,new_dz=Slope.foundation(new_mask,Road.foundation(new_mask,bits))
    if old==new and old_base+old_dz==new_base+new_dz then
      return opts.foundation_price or Stops.base_foundation
    end
  end
  function R.terminal(direction,through,old_mask,old_base,new_mask,new_base,opts)
    opts=opts or {}
    if not active(opts) or max_z(old_base,old_mask)~=max_z(new_base,new_mask) then return end
    if not Stops.depot_facing(direction,new_mask) or through and
      not Stops.depot_facing((direction+2)%4,new_mask) then return end
    return opts.foundation_price or Stops.base_foundation
  end
  return R
end
