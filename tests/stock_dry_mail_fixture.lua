-- SPDX-License-Identifier: GPL-2.0-only
-- Real completed Vanilla house types and separated dock catchments.
return function(Sim,s)
  s.road_mail=true
  s.sites={
    {id=1,kind="town",name="North Quay",tile=Sim.id(10,14),population=950,stock={},produced={},received={},service=0},
    {id=2,kind="town",name="South Quay",tile=Sim.id(42,14),population=950,stock={},produced={},received={},service=0},
  }
  for i,anchor in ipairs({10,42}) do
    for z=14,17 do for x=anchor-2,anchor+3 do
      local t=s.tiles[Sim.id(x,z)]
      t.house=true
      t.source_house={id=4,town=i,completed=true}
    end end
  end
end
