-- Two conventional shuttles depart the very same owned depot and choose
-- opposite turnout branches. Their ordinary passenger routes are disjoint.
return function(Sim,s,Lab,Owned,Run,T,Sig)
  local owner,id="Shared Depot Railways",Sim.id
  Sim.company(s,owner)
  local function rail(x,z,bits)
    local t=s.tiles[id(x,z)]
    t.owner,t.rail_tracks,t.build=owner,bits,"stock_rail"
  end
  for x=4,29 do rail(x,15,1) end
  rail(16,15,21)
  local depot=id(16,14)
  rail(16,14,2)
  assert(Lab.depot(s,owner,depot,T.SE))
  local orders={}
  for _,p in ipairs({{4,6},{9,11},{20,21},{27,29}}) do
    assert(Lab.station(s,owner,id(p[1],15),id(p[2],15)))
    orders[#orders+1]=s.tiles[id(p[1],15)].rail_station_id
    for dx=-1,3 do
      for _,dz in ipairs({-2,-1,1,2}) do
        local t=s.tiles[id(p[1]+dx,15+dz)]
        if not t.owner then t.house,t.parcel,t.variant=true,"shop",2 end
      end
    end
  end
  assert(Run.place_signal(s,owner,id(12,15),0,Sig.BLOCK,true))
  assert(Run.place_signal(s,owner,id(19,15),8,Sig.BLOCK,true))
  local a=assert(Owned.commit(s,owner,assert(Owned.quote(s,owner,depot,{0,27}))))
  local b=assert(Owned.commit(s,owner,assert(Owned.quote(s,owner,depot,{0,27}))))
  assert(Owned.start(s,owner,a.id,orders[1],orders[2]))
  assert(Owned.start(s,owner,b.id,orders[4],orders[3]))
  local d=assert(Run.current(s))
  assert(#d.runs==2 and not d.life.bits[depot])
  for _,r in ipairs(d.runs) do
    assert(r.local_signals and r.consist.parts[1].hidden and d.life.trains[r.id].parts[1].in_depot)
  end
  return {owner=owner,depot=depot,a=a.id,b=b.id,turnout=id(16,15)}
end
