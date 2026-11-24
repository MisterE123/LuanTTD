-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD developers, 16.0-RC1 src/tree_cmd.cpp CmdPlantTree,
-- src/company_cmd.cpp UpdateLandscapingLimit, and src/town_cmd.cpp
-- ChangeTownRating (RATING_TREE_UP_STEP / RATING_TREE_MAXIMUM).
-- The caller's query mode supplies dry-run LandscapeClear and company prices.
return function(Worldgen,Area)
  local K={base_price=20,unit=65536,rate=64*65536,burst=4096,random_species=255}
  local floor,min=math.floor,math.min
  local G=Worldgen.ground
  function K.replenish(quota,ticks,rate,burst)
    local cap=(burst or K.burst)*K.unit
    return min((quota or cap)+(rate or K.rate)*ticks,cap)
  end
  function K.rating(before)
    return before<220 and min(before+7,220) or before
  end
  function K.species(random)
    return floor(floor(random()/16777216)*12/256)
  end
  function K.new_tree(plan,random)
    local g=plan.ground
    local species=plan.species==K.random_species and K.species(random) or plan.species
    return {class=4,type=species,count=1,growth=0,ground=g,density=plan.density,
      water_class=g==G.shore and "sea" or nil}
  end
  function K.quote(grid,sx,sz,ex,ez,diagonal,opts)
    local species=opts.species
    if type(species)~="number" or species~=floor(species) or species~=K.random_species
        and (species<0 or species>11) then return nil,"INVALID_TREE_TYPE" end
    if sx<1 or sz<1 or ex<1 or ez<1 or sx>grid.width or ex>grid.width
        or sz>grid.depth or ez>grid.depth then return nil,"INVALID_SELECTION" end
    -- CmdPlantTree passes the cursor/end corner first, including for a diagonal drag.
    local iter=assert(Area.points(grid,ex,ez,sx,sz,diagonal))
    local unit=opts.unit_cost or K.base_price
    local quota=K.replenish(opts.quota,0,opts.rate,opts.burst)
    local limit,items,price,message=floor(quota/K.unit),{},0,"SITE_UNSUITABLE"
    for x,z in iter do
      local t=opts.tile(x,z)
      local class=t and t.class
      if class==4 and t.count==4 then
        message="TREE_ALREADY_HERE"
      elseif class==6 and (not t.coast or t.slope==1 or t.slope==2 or t.slope==4 or t.slope==8) then
        message="CANT_BUILD_ON_WATER"
      elseif (class==6 or class==0) and t.bridge_above then
        message="SITE_UNSUITABLE"
      elseif class==4 or class==6 or class==0 then
        limit=limit-1
        if limit<1 then
          message="TREE_PLANT_LIMIT_REACHED"
        else
          local item={x=x,z=z,id=t.id,species=species}
          if class==4 then
            item.add=true
            item.price=2*unit
          else
            local ground=t.ground or 0
            local clear=class==6 and t.rocky or class==0 and (ground==2 or ground==3)
            if clear then
              local cost,replaced=opts.clear(t,x,z)
              if cost==nil then return nil,replaced end
              item.clear,item.price=true,unit+cost
              ground=replaced.ground or 0
              t=replaced
            else
              item.price=unit
            end
            item.ground=t.class==6 and G.shore or ground==1 and G.rough or G.grass
            if item.ground==G.grass then item.density=assert(t.density) else item.density=3 end
            item.rate_town=true
          end
          price=price+item.price
          items[#items+1]=item
        end
      else
        message="SITE_UNSUITABLE"
      end
      if limit<0 then break end
    end
    if price==0 then return nil,message end
    if opts.cash and opts.cash<price then return nil,"NOT_ENOUGH_MONEY",price end
    return {items=items,cost=price,quota_after=quota-#items*K.unit}
  end
  return K
end
