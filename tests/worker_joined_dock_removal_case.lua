-- Demolish the physical pier against the real owner command interface,
-- not an injected cargo manifest or a stand-in loader.
return function(Sim,A,s,owner,run,station)
  assert(run.vehicle.loading and run.vehicle.last_station==station)
  local st=assert(s.stock_ship_stations[station])
  local land
  for _,part in ipairs(st.docks) do
    for d=1,4 do
      if Sim.adjacent(run.vehicle.tile,d)==part.water then
        assert(not land,"One mooring cannot belong to two piers in this fixture")
        land=part.land
      end
    end
  end
  assert(land)
  local q=A.demolition(owner,land)
  assert(q.ok)
  for _,o in ipairs(q.value.options) do
    if o.key=="harbor" then assert(o.ok,o.detail) end
  end
  local r=A.command(owner,{kind="demolition",token=q.value.token,layer="harbor",revision=q.revision})
  assert(r.ok,r.why)
  assert(run.dock_forced_leave and run.vehicle.loading)
  assert(#st.docks==1 and st.land~=land and not s.tiles[land].ship)
end
