-- A command is synchronous in the campaign owner. Capture every road
-- position and protected tram tile once, not once per selected tile.
return function(Sim,Run,s)
  local blocked={}
  local runs=Run.all and Run.all(s) or {Run.current(s)}
  for _,p in ipairs(runs) do
    for _,leg in ipairs(p.legs or {}) do
      for _,tile in ipairs(leg.path or {}) do blocked[tile]=true end
    end
  end
  for _,v in pairs(s.fleet) do
    local id=Sim.position(s,v)
    if id then blocked[id]=true end
  end
  return function(id) return blocked[id]==true end
end
