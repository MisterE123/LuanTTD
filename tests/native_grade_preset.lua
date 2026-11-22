-- Test-only height preset; only the fresh world's terrain is seeded here.
-- Keep the ends/terminal foundations flat. No owned road, stops, vehicles,
-- orders, or company activity are created by this fixture.
return function(original)
  return function(Sim,Terrain,S)
    local grid=original(Sim,Terrain,S)
    local ridge=Terrain.new(Sim.W,Sim.H,function(x,z)
      if x>=14 and x<=17 and z>=12 and z<=13 then return 1 end
      return Terrain.corner(grid,x,z)
    end)
    for x=9,18 do
      local shape,base,top=Terrain.tile(ridge,x,12)
      local expected=x==13 and 3 or x==17 and 12 or 0
      assert(shape==expected,"QA road fixture: wrong starting shape at "..x)
      assert(base==((x>=14 and x<=16) and 1 or 0),"QA road fixture: wrong base at "..x)
      assert(top==((x>=13 and x<=17) and 1 or 0),"QA road fixture: wrong top at "..x)
    end
    return ridge
  end
end
