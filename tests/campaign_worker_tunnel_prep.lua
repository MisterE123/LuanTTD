-- Test-only deterministic terrain, seeded before the ordinary worker opens.
-- Features crossing over the two bores are part of the starting fixture.
do
  local grid=assert(S.corner_grid)
  for z=1,grid.depth+1 do for x=1,grid.width+1 do
    local ridge_a=x>=27 and x<=37 and z>=16 and z<=25
    local ridge_b=z>=27 and z<=38 and x>=60 and x<=70
    grid.levels[(z-1)*(grid.width+1)+x]=(ridge_a or ridge_b) and 4 or 3
  end end
  grid.revision=grid.revision+1
  for z=12,46 do for x=19,73 do
    local _,level=api.terrain.tile(Sim.id(x,z))
    S.tiles[Sim.id(x,z)]={h=level,terrain="grass",variant=2}
  end end
  for _,range in ipairs({{20,25},{38,45}}) do
    for x=range[1],range[2] do S.tiles[Sim.id(x,20)].build="road";S.tiles[Sim.id(x,20)].road_bits=10 end
  end
  for z=19,22 do
    local t=S.tiles[Sim.id(32,z)]
    t.build,t.road_bits="road",5
  end
  -- Separate roof tiles for the Bulldozer replay; preserve the existing
  -- road and railway examples used to test the inverse removal.
  local surface_road=S.tiles[Sim.id(31,20)]
  surface_road.build,surface_road.road_bits,surface_road.owner="road",15,"TunnelBoreQA"
  local surface_rail=S.tiles[Sim.id(65,31)]
  surface_rail.build,surface_rail.road_bits,surface_rail.owner="road",10,"TunnelBoreQA"
  for x=64,67 do
    local t=S.tiles[Sim.id(x,32)]
    t.build,t.rail_tracks,t.owner="stock_rail",1,"TunnelBoreQA"
  end
  S.tiles[Sim.id(34,20)].house=true
  S.tiles[Sim.id(34,20)].source_house={id=0x1A,completed=true,town=1}
end
