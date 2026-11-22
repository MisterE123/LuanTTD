-- Starter-map adapter, not a substitute for OpenTTD flooding. The
-- legacy small campaign is a flat level-zero plain touching its ocean;
-- leave that save alone and prepare an actual raised bank in fresh
-- coastal scenario worlds before creating any commercial infrastructure.
return function(Sim,Terrain,s,grid)
  assert(grid.width==Sim.W and grid.depth==Sim.H and grid.revision==0)
  local dry,wet={},{}
  for z=1,Sim.H do
    for x=1,Sim.W do
      local t=assert(s.tiles[Sim.id(x,z)])
      local out=t.terrain=="water" and wet or dry
      for a=x,x+1 do for b=z,z+1 do
        out[(b-1)*(Sim.W+1)+a]=true
      end end
    end
  end
  -- Keep all water-adjacent shared corners and all original high
  -- land. Raising only zero -> one cannot violate the +/-1 edge rule.
  local raised=0
  local new=Terrain.new(Sim.W,Sim.H,function(x,z)
    local h=Terrain.corner(grid,x,z)
    local i=(z-1)*(Sim.W+1)+x
    if h==0 and dry[i] and not wet[i] then
      raised=raised+1;return 1
    end
    return h
  end,{max_height=grid.max_height,freeform_edges=grid.freeform_edges,unit_cost=grid.unit_cost})
  local shores,inland=0,0
  for z=1,Sim.H do
    for x=1,Sim.W do
      local t=s.tiles[Sim.id(x,z)]
      local mask,h,top=Terrain.tile(new,x,z)
      t.h=h
      if t.terrain=="water" then assert(mask==0 and h==0,"Expected the original ocean to stay flat and at level zero")
      elseif h==0 and top>0 then shores=shores+1
      elseif h>0 then inland=inland+1 end
    end
  end
  return new,{raised=raised,shores=shores,inland=inland}
end
