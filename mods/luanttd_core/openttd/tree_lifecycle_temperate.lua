-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 src/tree_cmd.cpp, Temperate TileLoop_Trees.
-- Shore water, ambient effects and the shared RNG are owned by the host.
return function(Worldgen)
  local T={NO_SPREAD=0,RAINFOREST_ONLY=1,SPREAD_ALL=2,NO_GROWTH=3}
  local GRASS,ROUGH,SHORE=Worldgen.ground.grass,Worldgen.ground.rough,Worldgen.ground.shore
  local function clone(old)
    local copy={}
    for k,v in pairs(old) do copy[k]=v end
    return copy
  end
  function T.visit(tree,x,z,tick,setting,random,neighbor,context)
    setting=setting or T.SPREAD_ALL
    local cycle=11*x+9*z+math.floor(tick/256)
    local new=tree
    if cycle%8==7 and tree.ground==GRASS and tree.density<3 then
      new=clone(tree);new.density=tree.density+1
    end
    if setting==T.NO_GROWTH or cycle%16~=15 then return new end
    local spread=setting==T.SPREAD_ALL
    if tree.growth==3 then
      local choice=random()%8
      if choice==0 then
        if new==tree then new=clone(tree) end
        new.growth=4
      elseif choice==1 and tree.count<4 and spread then
        if new==tree then new=clone(tree) end
        new.count,new.growth=tree.count+1,0
      elseif (choice==1 or choice==2) and spread then
        local d=math.floor(random()/536870912)
        local target=neighbor(d,context,x,z)
        if Worldgen.can_plant(target,false) and not (target.class==0 and
           (target.ground or 0)==0 and target.density~=3) then
          local g=target.class==6 and SHORE or target.ground==1 and ROUGH or GRASS
          return new,{kind="plant",direction=d,tree={class=4,type=tree.type,count=1,growth=0,
            ground=g,density=g==GRASS and target.density or 3,water_class=g==SHORE and "sea" or nil}}
        end
      end
      return new
    end
    if tree.growth==6 then
      if not spread then
        if new==tree then new=clone(tree) end
        new.growth=0
      elseif tree.count>1 then
        if new==tree then new=clone(tree) end
        new.count,new.growth=tree.count-1,3
      else
        return nil,{kind="clear",ground=new.ground,density=new.density}
      end
    else
      if new==tree then new=clone(tree) end
      new.growth=tree.growth+1
    end
    return new
  end
  -- OnTick_Trees / DecrementTreeCounter / PlantRandomTree. Map area is the
  -- stock power-of-two product (axes 64–4096); ScaleBySize uses ceil.
  -- A rejected destination still consumes the single draw that chose it.
  function T.global_tick(counter,area,tick,setting,random,tile)
    setting=setting or T.SPREAD_ALL
    if setting==T.NO_SPREAD or setting==T.NO_GROWTH then return counter end
    local skip=math.ceil(area/4096)
    if skip<16 and tick%(16/skip)~=0 then return counter end
    local next_counter=(counter-math.ceil(area/65536))%256
    if counter>next_counter or setting==T.RAINFOREST_ONLY then return next_counter end
    local r=random()
    local i=r%area
    local t=tile(i)
    if not Worldgen.can_plant(t,false) then return next_counter end
    local g=t.class==6 and SHORE or t.ground==1 and ROUGH or GRASS
    return next_counter,i,{class=4,type=math.floor(math.floor(r/16777216)*12/256),
      count=1,growth=0,ground=g,density=g==GRASS and t.density or 3,
      water_class=g==SHORE and "sea" or nil}
  end
  return T
end
