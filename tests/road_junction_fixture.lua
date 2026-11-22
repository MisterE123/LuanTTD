-- A deterministic T scenario used by the live stock clock and desktop QA.
-- Only this test board is flattened. No shipping game scenario is edited.
return function(Sim,s,owner)
  local id=Sim.id
  for i=1,#s.corner_grid.levels do s.corner_grid.levels[i]=0 end
  for _,t in ipairs(s.tiles) do
    t.terrain,t.h,t.build,t.site,t.owner,t.road_town,t.house,t.wood,t.source_house,t.road_bits=
      "grass",0,nil,nil,nil,nil,nil,nil,nil,nil
  end
  for i,xy in ipairs({{8,10},{23,10},{16,20}}) do s.sites[i].tile=id(xy[1],xy[2]) end
  local function build(k,ids)
    local ok,e=Sim.build(s,owner,k,ids);assert(ok,e)
  end
  local west,east,south,joint=id(8,12),id(23,12),id(15,20),id(15,12)
  build("road",Sim.line(west,east));build("road",Sim.line(joint,south))
  build("road_station",{west,east,south})
  local a,b=id(9,13),id(16,16)
  build("road_depot",{a,b})
  return {west=west,east=east,south=south,joint=joint,depot_a=a,depot_b=b}
end
