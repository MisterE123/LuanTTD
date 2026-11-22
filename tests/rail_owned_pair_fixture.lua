-- SPDX-License-Identifier: GPL-2.0-only
-- Stock Y merge, real shared station and stock Y split into two terminals.
return function(s,Sim,T,Lab,Run,Signal,owner)
  local id=Sim.id
  local function rail(x,z,mask)
    local t=s.tiles[id(x,z)]
    t.owner,t.rail_tracks,t.build=owner,mask,"stock_rail"
  end
  local function curve(a,b)
    for td=0,13 do
      if T.valid_trackdir(td) and T.entry_side(td)==a and T.exit_side(td)==b then return 2^T.track(td) end
    end
    error("No stock track through requested corner")
  end
  for x=2,35 do rail(x,14,1) end
  for z=9,13 do rail(8,z,2) end
  for z=4,13 do rail(28,z,2) end
  rail(8,14,1+curve(T.NW,T.SW))
  rail(28,14,1+curve(T.NE,T.NW))
  assert(Lab.depot(s,owner,id(2,14),T.SW))
  assert(Lab.depot(s,owner,id(8,9),T.SE))
  assert(Lab.station(s,owner,id(17,14),id(19,14)))
  assert(Lab.station(s,owner,id(33,14),id(35,14)))
  assert(Lab.station(s,owner,id(28,4),id(28,6)))
  assert(Run.place_signal(s,owner,id(7,14),8,Signal.PBS_ONEWAY))
  assert(Run.place_signal(s,owner,id(8,13),1,Signal.PBS_ONEWAY))
  assert(Run.place_signal(s,owner,id(12,14),8,Signal.PBS_ONEWAY))
  assert(Run.place_signal(s,owner,id(20,14),8,Signal.PBS_ONEWAY))
  assert(Run.place_signal(s,owner,id(27,14),8,Signal.PBS_ONEWAY))
  assert(Run.place_signal(s,owner,id(29,14),8,Signal.PBS_ONEWAY))
  assert(Run.place_signal(s,owner,id(28,12),9,Signal.PBS_ONEWAY))
  local first,lastA,lastB=s.tiles[id(17,14)].rail_station_id,s.tiles[id(33,14)].rail_station_id,s.tiles[id(28,4)].rail_station_id
  for i,center in ipairs({{18,14},{34,14},{28,5}}) do
    s.sites[i].tile=id(center[1],center[2]+2)
    for dz=-3,3 do for dx=-3,3 do
      local t=s.tiles[id(center[1]+dx,center[2]+dz)]
      if not t.build then
        t.terrain,t.h,t.owner,t.site,t.wood,t.source_house="grass",0,nil,nil,nil,nil
        t.house,t.parcel,t.variant=true,"shop",2
      end
    end end
  end
  return first,lastA,lastB
end
