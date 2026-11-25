-- SPDX-License-Identifier: GPL-2.0-only
-- Plain rail portions of OpenTTD 16.0-RC1 rail_cmd.cpp:
-- TestAutoslopeOnRailTile and TerraformTile_Rail. The host supplies live
-- ship occupancy and applies the quoted ground change on execution only.
return function(Track,Slope)
  local R={}
  local steep_corner={[23]=1,[27]=0,[29]=3,[30]=2}
  local running_corner={[4]=3,[8]=1,[16]=0,[32]=2}
  local free_corner={[4]=1,[8]=3,[16]=2,[32]=0}
  local single={[1]=true,[2]=true,[4]=true,[8]=true}
  local function z_at(shape,corner)
    shape=shape%32 -- RemoveHalftileSlope before reading the stock corner
    if steep_corner[shape]==corner then return 2 end
    return math.floor(shape/2^corner)%2
  end
  function R.quote(bits,old_s,old_z,new_s,new_z,opts)
    opts=opts or {}
    if not bits or bits==0 then return nil,"INVALID_PREVIOUS_RAIL" end
    local was_water=opts.half_water and single[old_s]
    if was_water and opts.ship_in_way then return nil,"VEHICLE_IN_THE_WAY" end
    local old_foundation,old_corner=Track.foundation(old_s,bits)
    if old_foundation=="invalid" then return nil,"INVALID_PREVIOUS_RAIL" end
    local plan
    if opts.build_on_slopes~=false and opts.autoslope~=false then
      local ok,new_foundation,new_corner=Track.build_slope(new_s,bits,0,opts.half_water,true)
      if ok then
        local old_plane,dz=Slope.foundation(old_s,old_foundation,old_corner)
        local new_plane,dn=Slope.foundation(new_s,new_foundation,new_corner)
        local a,b=old_z+dz,new_z+dn
        local c=running_corner[bits]
        local keep
        if c==nil then keep=a==b and old_plane==new_plane
        else keep=a+z_at(old_plane,c)==b+z_at(new_plane,c) end
        if keep then
          local barren=c~=nil and old_plane~=new_plane
          local clear=barren and opts.half_water and single[old_plane]
          plan={price=(opts.foundation_price or 250)+(clear and (opts.clear_water or 10000) or 0),barren=barren}
        end
      end
    end
    local unused=free_corner[bits]
    if unused==nil or old_foundation=="rail" and old_s~=5 and old_s~=10 then
      return plan,not plan and "MUST_REMOVE_RAILROAD_TRACK" or nil
    end
    -- Same source corner exception wins over autoslope because it's
    -- cheaper; even if AutoslopeEnabled is false, this corner is free.
    for c=0,3 do
      if c~=unused and old_z+z_at(old_s,c)~=new_z+z_at(new_s,c) then
        return plan,not plan and "MUST_REMOVE_RAILROAD_TRACK" or nil
      end
    end
    return {price=was_water and (opts.clear_water or 10000) or 0,barren=true,free_corner=unused}
  end
  return R
end
