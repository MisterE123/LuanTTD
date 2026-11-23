return function(Sim,s,Lab,Owned,Run,T,Signals)
  local owner,id="Collision QA",Sim.id
  Sim.company(s,owner)
  for x=4,29 do
    local t=s.tiles[id(x,15)]
    t.owner,t.rail_tracks,t.build=owner,1,"stock_rail"
  end
  assert(Lab.depot(s,owner,id(4,15),T.SW))
  assert(Lab.depot(s,owner,id(29,15),T.NE))
  assert(Lab.station(s,owner,id(7,15),id(8,15)))
  assert(Lab.station(s,owner,id(25,15),id(26,15)))
  for _,x in ipairs({7,8,9,10,24,25,26,27}) do
    for _,z in ipairs({12,13,14,16,17,18}) do
      local t=s.tiles[id(x,z)];t.house,t.parcel,t.variant=true,"shop",2
    end
  end
  local A=s.tiles[id(7,15)].rail_station_id
  local B=s.tiles[id(25,15)].rail_station_id
  local L,R=id(6,15),id(27,15)
  assert(Run.place_signal(s,owner,L,8,Signals.BLOCK,true))
  assert(Run.place_signal(s,owner,R,0,Signals.BLOCK,true))
  local a=assert(Owned.commit(s,owner,assert(Owned.quote(s,owner,id(4,15),{0,27}))))
  local b=assert(Owned.commit(s,owner,assert(Owned.quote(s,owner,id(29,15),{0,27}))))
  assert(Owned.start(s,owner,a.id,B,A))
  assert(Owned.start(s,owner,b.id,A,B))
  Sim.daily(s)
  local d=assert(Run.current(s))
  assert(not d.failure,d.failure)
  assert(not d.runs[1].consist.parts[1].hidden and not d.runs[2].consist.parts[1].hidden)
  -- Recreate the supported OpenTTD safety failure: remove both boundary
  -- signals after the players' trains have left their respective depots.
  d.signals.records[L],d.signals.records[R]=nil,nil
  s.topology=s.topology+1
  return {owner=owner,a=a.id,b=b.id}
end
