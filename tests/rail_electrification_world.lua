-- SPDX-License-Identifier: GPL-2.0-only
-- Actual company Sim records, Trackworks construction, depot ownership and
-- reservation schema; no live tool or stock train consumes typed rail yet.
local base="mods/luanttd_core/"
local function m(f) return dofile(base..f..".lua") end
local function p(f,...) return m("openttd/"..f)(...) end
local Sim,Terrain,Track,Slope=m("sim"),m("openttd/terrain"),m("openttd/rail_track"),m("openttd/slope")
local Types=m("openttd/rail_types")
local W=m("rail_electrification_world")(Sim,Terrain,Track,Types)
local F=p("rail_follow",Track)
local Cost=p("rail_yapf_cost",Track,F)
local Search=p("rail_yapf_search",Track,F,Cost)
local Motion=p("rail_motion",Track)
local PBS=p("rail_reservation",Track,F,Cost)
local Life=p("rail_consist_reservation",Track,F,PBS)
local Signal=p("rail_signals",Track)
local Consist=p("rail_consist_motion",Track,Motion,F,Life)
local Roster=m("openttd/rail_roster")
local at=Sim.id
local s=Sim.new(1751)
local A,B="Kirby Rail","Rival Rail"
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z) return x==31 and z==7 and 1 or 0 end)
for id in pairs(s.tiles) do s.tiles[id]={h=0,terrain="grass"} end
s.sites,s.stations,s.fleet={},{},{}
local function shape(id) return Terrain.tile(s.corner_grid,Sim.xy(id)) end
local Lab=m("trackworks")(Sim,Track,F,Slope,Cost,Search,shape)
local Run=m("rail_dispatch_run")(Track,F,Cost,Search,PBS,Life,Signal,Consist,m("rail_consist_dispatch")(Consist,Life),
  p("rail_station_speed",Track,F),Lab,nil,p("rail_reverse",Track,Motion,Consist,Life,Signal,F,PBS),nil,nil,Roster)
local Depot=m("rail_depot_fleet")(Sim,Lab,Roster)
local c=Sim.company(s,A)
Sim.company(s,B)
local mask,hidden,disable,clear,price=3,0,false,true,{rail=100,clear_rail=-70}
local ctx={availability=function(w,o) assert(w.tiles and o==A);return mask,hidden,disable end,
  is_clear=function()return clear end,prices=function()return price end}
local depot,signal,station,other=at(2,6),at(4,6),at(6,6),at(14,6)
local function laid(x,z,k,owner)
  local id=at(x,z)
  assert(Lab.change(s,owner or A,id,k or Track.X,false,shape(id)))
  return id
end
for x=2,9 do laid(x,6) end
assert(Lab.depot(s,A,depot,Track.SW))
assert(Lab.station(s,A,station,at(8,6)))
assert(Run.place_signal(s,A,signal,Track.diagonal_trackdir(Track.SW),Signal.PBS))
laid(14,6,Track.X,B)
local loop=laid(17,6,Track.RIGHT)
local dir_before=s.tiles[depot].rail_depot_dir
local sign_before=s.stock_rail_dispatch.signals.records[signal]
local record=s.stock_rail_stations[s.tiles[station].rail_station_id]
local function issued(ids,target,state) return W.quote(state or s,A,ids,target==nil and 1 or target,ctx) end
local function denied(ids,why,state,target)
  local q,msg=W.quote(state or s,A,ids,target==nil and 1 or target,ctx)
  assert(not q and msg==why,why..": "..tostring(msg))
end
local function snapshot(t,seen)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  seen=seen or {};if seen[t] then return seen[t] end
  local out={};seen[t]=out
  for k,v in pairs(t) do out[k]=snapshot(v,seen) end
  return out
end
local ids={depot,at(3,6),signal,station,at(7,6),at(8,6),at(12,6),other,loop}
local old_cash,old_topo=c.cash,s.topology
assert(W.tile_type(s,depot)==0 and W.tile_type(s,at(12,6))==nil)
assert(not W.quote(s,A,ids,1,{}) and not W.quote(s,A,ids,3,ctx))
denied({station,at(7,6)},"COMPLETE_PLATFORM_REQUIRED")
denied({other,at(12,6)},"OWNED_BY_ANOTHER")
denied({at(12,6)},"NO_SUITABLE_RAILROAD_TRACK")
denied({at(3,6),at(3,6)},"INVALID_PARAMETER")
denied({[1]=at(3,6),[4]=at(4,6)},"INVALID_PARAMETER")
hidden=2;denied(ids,"RAILTYPE_NOT_AVAILABLE");hidden=0
mask=1;denied(ids,"RAILTYPE_NOT_AVAILABLE");mask=3
clear=false;denied(ids,"RAIL_SURVEY_ACTIVE");clear=true
assert(c.cash==old_cash and s.topology==old_topo and not s.tiles[depot].rail_type)
assert(issued(ids).price==7*68)
local ticket=assert(issued(ids))
-- The current Lua server callback must recheck cash/availability, not its
-- copied tooltip fields. No mutation when pending work turns unaffordable.
ticket.price,ticket.target,ticket.ids=1,0,{other}
c.cash=ticket.cost-1
local ok,why,asked=W.commit(s,A,ticket,ctx)
assert(not ok and why=="NOT_ENOUGH_MONEY" and asked==7*68)
assert(s.topology==old_topo and not s.tiles[signal].rail_type)
c.cash=old_cash
price.rail=150
ok,why=W.commit(s,A,ticket,ctx)
assert(not ok and why=="STALE_RAILTYPE_QUOTE")
price.rail=100

-- Reservation can change without a topology bump. Unmounting a reservation
-- is a separate action, never a side effect of the refusal.
local life=s.stock_rail_dispatch.life
life.bits[signal],life.claims[signal]=1,{[Track.X]=44}
ok,why=W.commit(s,A,ticket,ctx)
assert(not ok and why=="RAIL_RESERVED" and life.claims[signal][Track.X]==44)
life.bits[signal],life.claims[signal]=nil,nil
local old_revision=s.corner_grid.revision
s.corner_grid.revision=old_revision+1
local fresh,stale=W.commit(s,A,ticket,ctx)
assert(not fresh and stale=="STALE_RAILTYPE_QUOTE")
s.corner_grid.revision=old_revision
local d=s.stock_rail_dispatch
d.runs[1]={consist={parts={{tile=at(3,6)}}},route={{tile=signal}}}
denied(ids,"RAIL_OCCUPIED")
denied({signal},"RAIL_ROUTE_ACTIVE")
d.runs[1]=nil
clear=nil
denied(ids,"RAIL_OCCUPANCY_UNKNOWN")
clear=true

-- Actual empty/occupied owned depot is taken from the stock owned fleet,
-- not from graphic object presence. Buying in a copied save keeps funds
-- and counters independent of the production mutation under test.
local held=snapshot(s)
held.rail_owned_service=true
assert(Depot.initialize(held,{starting_year=1950,climate="temperate",generation_seed=1751,startup_random=1}))
assert(Depot.commit(held,A,assert(Depot.quote(held,A,depot,{0,27}))))
denied({depot},"RAIL_OCCUPIED",held)
local no,w=W.commit(held,A,ticket,ctx)
assert(not no and w=="STALE_RAILTYPE_QUOTE")

-- Unsupported placements anywhere in the selection are errors, not a
-- hidden partial debit. Exercise malformed type, span and legacy cases.
local geom=snapshot(s)
geom.tiles[at(12,6)].rail_span_id=81
denied(ids,"PROTECTED_RAIL_STRUCTURE",geom)
geom=snapshot(s);geom.tiles[signal].rail_tracks=3
denied(ids,"SINGLE_RAIL_PIECE_REQUIRED",geom)
geom=snapshot(s);geom.tiles[signal].rail_type=2
denied(ids,"UNSUPPORTED_RAILTYPE_CONVERSION",geom)
geom=snapshot(s);geom.tiles[at(12,6)].build="rail"
denied(ids,"UNKNOWN_RAIL_PLACEMENT",geom)
geom=snapshot(s);geom.tiles[at(3,6)].rail_tracks=2
denied({depot},"ENCLOSED_RAIL_DEPOT_REQUIRED",geom)
geom=snapshot(s);geom.tiles[at(1,6)]={build="stock_rail",terrain="grass",rail_tracks=1,owner=A}
denied({depot},"ENCLOSED_RAIL_DEPOT_REQUIRED",geom)
geom=snapshot(s);geom.tiles[at(7,6)].rail_type=1
denied(ids,"MIXED_PLATFORM_UNSUPPORTED",geom)
geom=snapshot(s)
geom.tiles[at(30,6)]={build="stock_rail",terrain="grass",rail_tracks=1,owner=A}
denied({at(30,6)},"FLAT_RAIL_REQUIRED",geom)
geom=snapshot(s);geom.stock_rail_dispatch.life=nil
denied(ids,"RAIL_OCCUPANCY_UNKNOWN",geom)
assert(c.cash==old_cash and c.expense==0 and s.topology==old_topo and not s.tiles[signal].rail_type)

-- Commit fresh authority once, retaining every unrelated field.
local success,cost,dirty,receipt=W.commit(s,A,ticket,ctx)
assert(success and cost==476 and #dirty==7 and receipt.infra[0]==-7 and receipt.infra[1]==7)
assert(s.topology==old_topo+1 and c.cash==old_cash-476 and c.expense==476 and c.month_exp==476)
for _,id in ipairs(dirty) do assert(W.tile_type(s,id)==1) end
assert(W.tile_type(s,other)==0 and W.tile_type(s,at(5,6))==0 and not s.tiles[at(12,6)].rail_type)
assert(s.stock_rail_dispatch.signals.records[signal]==sign_before and s.tiles[depot].rail_depot_dir==dir_before)
assert(s.stock_rail_stations[record.id]==record and #record.tiles==3)
assert(not W.commit(s,A,ticket,ctx))
denied(ids,"OWNED_BY_ANOTHER") -- own holdings already match, foreign doesn't
local reloaded=snapshot(s)
for _,id in ipairs(dirty) do assert(W.tile_type(reloaded,id)==1) end
disable=true
denied({signal},"NO_SUITABLE_RAILROAD_TRACK",reloaded,0)
disable=false
local downgrade=assert(issued(dirty,0,reloaded))
assert(downgrade.price==84)
assert(W.commit(reloaded,A,downgrade,ctx))
for _,id in ipairs(dirty) do assert(reloaded.tiles[id].rail_type==0 and W.tile_type(s,id)==1) end
assert(reloaded.companies[A].cash==old_cash-560 and reloaded.companies[A].expense==560)
print("PASS live Sim typed electrification adapter: ownership, stale and occupied refusals, full platform, exact cash, state reload")
