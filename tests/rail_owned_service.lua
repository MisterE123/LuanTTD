-- SPDX-License-Identifier: GPL-2.0-only
-- Purchased stock steam, a real coach, paid orders and shared clock.
local root="mods/luanttd_core/"
local src=root.."openttd/"
local function port(name,...) return dofile(src..name..".lua")(...) end
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(src.."terrain.lua")
local RoadSlope=dofile(src.."slope.lua")
local T=dofile(src.."rail_track.lua")
local F=port("rail_follow",T)
local C=port("rail_yapf_cost",T,F)
local Search=port("rail_yapf_search",T,F,C)
local Raw=port("rail_motion",T)
local PBS=port("rail_reservation",T,F,C)
local Life=port("rail_consist_reservation",T,F,PBS)
local Signal=port("rail_signals",T)
local Consist=port("rail_consist_motion",T,Raw,F,Life)
local Speed=port("rail_station_speed",T,F)
local Reverse=port("rail_reverse",T,Raw,Consist,Life,Signal,F,PBS)
local H=port("rail_height",T,RoadSlope)
local Q=port("rail_construction",T,Signal,H)
local Site=dofile(src.."rail_span_site.lua")
local B=port("rail_bridge",port("road_bridge",RoadSlope),Q,Site)
local U=port("rail_tunnel",dofile(src.."road_tunnel.lua"),Q,Site,T)
local L=dofile(root.."rail_span_life.lua")(T,PBS,Life)
local Motion=dofile(root.."rail_span_consist.lua")(T,Raw,F,Consist,Life)
local Dispatch=dofile(root.."rail_consist_dispatch.lua")(Motion,L)
local W=dofile(root.."rail_span_world.lua")(Sim,Terrain,H,B,U,T)
local CrossWorld=dofile(root.."level_crossing_world.lua")(Sim,Terrain,port("level_crossing",T),T)
local Cross=dofile(root.."level_crossing_runtime.lua")(Sim,CrossWorld)
local Roster=dofile(src.."rail_roster.lua")
local s=Sim.new(1751)
local mode=arg and arg[1]
local turnout=mode=="depot_turnout"
local mixed=mode=="mixed_signals"
local two_coaches=mode=="two_coaches"
local Block=mixed and port("rail_block_signals",T,Signal) or nil
local turnout_decisions={}
local turnout_id
local via_tile,via_id,via_passes,via_reloaded
local lookahead=mode=="platform_lookahead" or mode=="platform_fallback" or mode=="platform_claim_rollback"
local real_find,fallback_calls=Search.find,0
local jubilee=mode=="jubilee" or mode=="jubilee_spans"
local use_spans=mode=="spans" or mode=="jubilee_spans"
local engine=jubilee and 8 or 0
local power,mass,vmax,accel,annual=jubilee and 1000 or 300,jubilee and 156 or 72,
  jubilee and 112 or 64,jubilee and 24 or 16,jubilee and 672000 or 280000
s.rail_paid_service,s.rail_span_enabled,s.level_crossing_enabled=true,use_spans,use_spans
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z)
  if not use_spans then return 0 end
  if x>=14 and x<=18 then return 5 end
  if x==7 or x==8 then return 3 end
  return 4
end)
local function terrain(id)
  local x,z=Sim.xy(id)
  return Terrain.tile(s.corner_grid,x,z)
end
for id,t in ipairs(s.tiles) do
  local _,h=terrain(id)
  t.owner=nil;t.build=nil;t.site=nil;t.wood=nil;t.house=nil;t.h=h;t.terrain="grass"
end
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,RoadSlope,C,Search,terrain)
local Fleet=dofile(root.."rail_depot_fleet.lua")(Sim,Lab,Roster)
local Run,Owned
local function mount(new,art)
  if new then
    Run=dofile(root.."rail_dispatch_run.lua")(T,F,C,Search,PBS,L,Signal,Motion,Dispatch,Speed,Lab,nil,Reverse,W,Cross,Roster,Block)
    Owned=dofile(root.."rail_owned_service.lua")(Fleet,Roster,Run)
    if art then assert(Run.mount_owned_model(8)) end
  end
  Sim.mount_paid_rail(s,Run)
end
mount(true)
if turnout then
  local choose=Search.choose
  Search.choose=function(board,v,origin,dest,settings,o)
    local td,found,best,flags=choose(board,v,origin,dest,settings,o)
    local approached=board.adjacent(origin.tile,T.exit_side(origin.td))
    if approached==turnout_id and td then turnout_decisions[T.track(td)]=true end
    return td,found,best,flags
  end
end
local owner="Railworks"
local company=Sim.company(s,owner)
local function id(x,z) return Sim.id(x,z or 10) end
local function rail(x)
  local t=s.tiles[id(x)];t.owner=owner;t.rail_tracks=1;t.build="stock_rail"
end
if use_spans then
  for _,x in ipairs({2,3,4,10,11,12,19,20,21,22,23,24}) do rail(x) end
  local b=assert(W.quote_bridge(s,owner,id(5),id(9)));assert(W.commit(s,owner,b))
  local u=assert(W.quote_tunnel(s,owner,id(13)));assert(W.commit(s,owner,u))
  assert(Sim.build(s,owner,"road",{id(20,9)}));assert(Sim.build(s,owner,"road",{id(20,11)}))
  local quote=assert(Cross.quote(s,owner,id(20),{kind="road",pieces=5},Lab.board(s)))
  assert(Cross.commit(s,owner,quote,Lab.board(s)))
else for x=2,24 do rail(x) end end
local start_depot=id(2)
if turnout then
  -- Screenshot layout: a side depot above a main line with a station
  -- in both directions. Depot -> mouth offers either curve; the
  -- east/west main line remains a third, independent piece.
  local RailTools=dofile(root.."rail_construction_tools.lua")
  local construction=RailTools({Sim=Sim,s=s,terrain={tile=terrain},save=function()end,render={update=function()end}},Lab,T,nil,{
    track=function(t,st,o)local q,why=Q.piece(t,st.track,o);return q and q.cost,why end,
    depot=function(t,d,o)local q,why=Q.depot(t,d,o);return q and q.cost,why end})
  start_depot,turnout_id=id(16,9),id(16)
  local p=assert(construction.quote_depot(owner,start_depot,T.SE))
  assert(construction.build(owner,p))
  assert(s.tiles[turnout_id].rail_tracks==21)
else
  assert(Lab.depot(s,owner,start_depot,T.SW))
end
assert(Lab.station(s,owner,id(11),id(12)))
assert(Lab.station(s,owner,id(22),id(24)))
if mode~="signal_free" and not turnout and not mixed and not two_coaches then assert(Run.place_signal(s,owner,id(10),0,Signal.PBS)) end
local west,east=s.tiles[id(11)].rail_station_id,s.tiles[id(22)].rail_station_id
s.sites[1].tile=id(10,13);s.sites[2].tile=id(24,13)
for _,z in ipairs({7,8,12,13}) do
  for _,x in ipairs({8,9,10,11,12,21,22,23,24,25}) do
    local t=s.tiles[id(x,z)]
    t.house,t.parcel,t.variant=true,"shop",2
  end
end
assert(not Owned.initialize(s,{starting_year=1950,generation_seed=s.seed,startup_random=9001}))
s.rail_owned_service=true
if mixed then
  s.rail_block_preview=true
  assert(Run.place_signal(s,owner,id(14),8,Signal.BLOCK,true))
  assert(Run.place_signal(s,owner,id(18),8,Signal.PBS))
end
assert(Owned.initialize(s,{starting_year=1950,generation_seed=s.seed,startup_random=9001}))
if two_coaches then
  local before=company.cash
  local function buy(stock)
    local quote=assert(Owned.quote_part(s,owner,start_depot,stock))
    return assert(Owned.commit(s,owner,quote))
  end
  local u=buy(0)
  local a,b=buy(27),buy(27)
  u=assert(Owned.get(s,owner,u.id))
  assert(#u.parts==3 and u.parts[2].body_id==a.body_id and u.parts[3].body_id==b.body_id)
  assert(company.cash==before-u.price)
  local ok,reason,run=Owned.start(s,owner,u.id,east,west)
  assert(ok,reason)
  assert(run.passenger_coaches==2 and run.total_length==24 and #run.consist.parts==3)
  local proof={units=false,reversed=false,reloaded=false}
  local function copy(t)
    if type(t)~="table" then return t end
    local out={}
    for k,v in pairs(t) do out[k]=copy(v) end
    return out
  end
  for i=1,180 do
    Sim.daily(s)
    assert(not Run.current(s).failure,Run.current(s).failure)
    local st=assert(Sim.rail_paid_status(s,u.id))
    assert(st.capacity==80 and #st.carrying_parts==2)
    assert(Motion.check_spacing(Run.board(s),run.consist))
    local p,q=st.carrying_parts[1],st.carrying_parts[2]
    if st.loading then
      assert(p.tile==run.consist.parts[2].tile and q.tile==run.consist.parts[3].tile)
      if p.onboard>0 and q.onboard>0 then
        assert(run.consist_mass==97+math.floor(p.onboard/16)+math.floor(q.onboard/16))
        proof.units=true
        if not proof.reloaded then
          s=copy(s);mount()
          run=assert(Run.current_paid(s,u.id))
          proof.reloaded=true
        end
      end
    end
    if run.shuttle.reversals>=2 and st.fare>0 then
      assert(proof.units and proof.reloaded)
      print(("PASS purchased engine and two individual coaches use real 80-seat rolling stock, per-coach mass, paid return and save: $%d"):format(st.fare))
      return
    end
  end
  error("Two-coach stock service never paid and reversed")
end
local base=company.cash
local coal=assert(Owned.commit(s,owner,assert(Owned.quote(s,owner,start_depot,{0,29}))))
assert(not Owned.start(s,owner,coal.id,east,west))
if jubilee then
  local q,why=Owned.quote(s,owner,start_depot,{8,27})
  assert(not q and why=="JUBILEE_MODEL_NOT_AVAILABLE")
  assert(not Owned.commit(s,owner,assert(Fleet.quote(s,owner,id(2),{8,27}))))
  assert(Run.mount_owned_model(8))
end
local quote=assert(Owned.quote(s,owner,start_depot,{engine,27}))
local unit=assert(Owned.commit(s,owner,quote))
assert(unit.price==(jubilee and 22241 or 12866))
local cash=base-coal.price-unit.price
assert(company.cash==cash and company.revenue==0)
assert(not Owned.start(s,"Other",unit.id,east,west))
if lookahead or mode=="route_hints" then
  -- A platform built on continuing track needs a safe exit in the
  -- arrival direction. Diagnose the exact far tile, not "one-way".
  rail(25)
  local ok,why=Owned.start(s,owner,unit.id,east,west)
  assert(not ok and why:find("Platform (24,10) has no safe exit",1,true),why)
  assert(Owned.get(s,owner,unit.id).status=="depot" and company.cash==cash)
  if not lookahead then assert(Run.place_signal(s,owner,id(25),8,Signal.PBS)) end
  -- The depot feeds two routes around a complete loop. Both platforms
  -- are on through tracks rather than at buffered ends.
  local function loop_tile(x,z,mask)
    local t=s.tiles[id(x,z)]
    t.owner,t.rail_tracks,t.build=owner,mask,"stock_rail"
  end
  loop_tile(6,10,1+8+32)
  loop_tile(26,10,32)
  loop_tile(26,15,4)
  loop_tile(6,15,16)
  for z=11,14 do loop_tile(6,z,2);loop_tile(26,z,2) end
  for x=7,25 do loop_tile(x,15,1) end
  if lookahead then
    assert(Run.place_signal(s,owner,id(18),8,Signal.PBS_ONEWAY))
    assert(Run.place_signal(s,owner,id(22,15),0,Signal.PBS))
    assert(Run.place_signal(s,owner,id(13),8,Signal.PBS))
  end
  print("PASS exact unsafe-platform message, then validate the complete junction-fed loop")
end
if mode=="platform_fallback" then
  -- Simulate future-order YAPF returning no destination specifically on
  -- the staged occupied station board, never in the static preflight.
  Search.find=function(board,v,origin,dest,...)
    if origin.tile==id(24) and dest.kind=="station" and dest.station==west and
        board.tile(origin.tile).reserved then fallback_calls=fallback_calls+1;return false end
    return real_find(board,v,origin,dest,...)
  end
end
if mode=="waypoint" then
  local function set(x,z,bits)
    local t=s.tiles[id(x,z)]
    t.owner,t.build,t.rail_tracks=owner,"stock_rail",bits
  end
  -- The two-turn bypass is longer than the main line, which must still
  -- win the initial depot route. A real waypoint order must force YAPF
  -- and the PBS physical claims down the bypass on both paid legs.
  set(14,10,1+32);set(20,10,1+8)
  set(14,15,16);set(20,15,4)
  for z=11,14 do set(14,z,2);set(20,z,2) end
  for x=15,19 do set(x,15,1) end
  via_tile,via_passes=id(17,15),0
  local api={Sim=Sim,s=s,terrain={tile=terrain},render={update=function()end},save=function()end}
  local Build=dofile(root.."rail_construction_tools.lua")(api,Lab,T,Run,Q)
  local pre=company.cash
  assert(not Build.quote_waypoint(owner,id(10))) -- existing PBS signal
  assert(not Build.quote_waypoint(owner,id(11))) -- existing platform
  assert(not Build.quote_waypoint("Other",via_tile))
  local q=assert(Build.quote_waypoint(owner,via_tile));assert(q.price==600 and q.axis==0)
  s.tiles[via_tile].rail_type=1
  assert(Build.build(owner,q))
  assert(s.tiles[via_tile].rail_type==1)
  assert(not Build.build(owner,q)) -- same stale quote may not debit again
  via_id=assert(Lab.waypoint_at(s,via_tile)).id
  assert(via_id~=west and via_id~=east and company.cash==pre-600)
  local remove=assert(Build.quote_waypoint(owner,via_tile,true));assert(remove.price==150)
  assert(Build.build(owner,remove))
  assert(s.tiles[via_tile].rail_tracks==1 and s.tiles[via_tile].rail_type==1 and not Lab.waypoint_at(s,via_tile))
  assert(Build.build(owner,assert(Build.quote_waypoint(owner,via_tile))))
  assert(not Sim.plan(s,owner,"clear",{via_tile}))
  via_id=assert(Lab.waypoint_at(s,via_tile)).id
  cash=company.cash
  assert(not Owned.start(s,owner,unit.id,east,west,nil,id(16)))
  assert(Owned.get(s,owner,unit.id).status=="depot")
end
local ok,msg,run=Owned.start(s,owner,unit.id,east,west,nil,via_tile)
assert(ok,msg)
if mixed then assert(run.local_signals and not run.ordinary_unreserved) end
assert(run.fleet_id==unit.id and run.stock_engine==engine and run.stock_wagon==27 and run.visual==(jubilee and "jubilee" or "steam"))
if via_tile then
  assert(run.order.kind=="station") -- no waypoint on depot to first station
  for _,r in ipairs(run.route) do assert(r.tile~=via_tile) end
end
if lookahead or mode=="route_hints" then
  assert(run.branch_pbs)
  local through=false
  for _,r in ipairs(run.route) do
    if r.tile==id(6) then through=true;assert(T.track(r.td)==T.X) end
    assert(r.tile~=id(6,11))
  end
  assert(through)
end
assert(run.max_track_speed==vmax and run.power==power and run.consist_mass==mass and run.acceleration==accel)
assert(run.paid_clock and run.running_year_fp==annual)
assert(Owned.get(s,owner,coal.id).parts[1].stock_id==0)
assert(Owned.get(s,owner,unit.id).status=="dispatched" and Owned.occupies_depot(s,start_depot))
assert(not Owned.start(s,owner,unit.id,east,west))
assert(not Run.clear(s,owner) and #Run.tick(s,100)==0)
local mixed_path,mixed_closed,mixed_reopened
local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local b={}
  for k,v in pairs(t) do b[k]=clone(v) end
  return b
end
local function reload()
  s=clone(s);mount()
  run=assert(Run.current_paid(s));company=s.companies[owner]
  local r=assert(Owned.get(s,owner,unit.id))
  assert(r.status=="dispatched" and r.run_id==unit.id and r.parts[1].stock_id==engine and r.parts[2].stock_id==27)
  assert(not Owned.commit(s,owner,quote))
  if via_tile then
    assert(run.via.id==via_id and run.via.tile==via_tile and run.via.passes==via_passes)
    assert(Lab.board(s).tile(via_tile).kind=="waypoint")
  end
end
assert(Owned.toggle(s,owner,unit.id))
Sim.daily(s)
assert(run.running_ticks_total==0 and run.stock_steps==0 and run.stopped and run.phase=="depot")
reload()
assert(Owned.toggle(s,owner,unit.id))
if jubilee then
  -- On a broken/missing-art install the saved model is not substituted,
  -- boarded or moved. Restoring the qualified model retains the unit.
  s=clone(s);mount(true,false);run=Run.current_paid(s);company=s.companies[owner]
  assert(not Run.paid_art_ready(s) and Sim.rail_paid_status(s,unit.id).paused)
  local ledger=company.cash
  Sim.daily(s)
  assert(run.running_ticks_total==0 and run.stock_steps==0 and company.cash==ledger)
  assert(Run.mount_owned_model(8) and Run.paid_art_ready(s))
end
if mode=="platform_claim_rollback" then
  local d=Run.current(s)
  local intruder=555
  assert(L.register(Run.board(s),d.life,intruder,owner,{{tile=id(25),td=8}}))
  for _=1,60 do
    Sim.daily(s)
    assert(not d.failure,d.failure)
    if run.stuck then break end
  end
  assert(run.stuck and run.consist.parts[1].tile==id(17) and run.phase=="waiting")
  for x=18,24 do assert(not d.life.bits[id(x)],"Failed extension leaked a claim at "..x) end
  assert(L.claim_owner(d.life,id(25),T.X)==intruder and L.valid_state(Run.board(s),d.life))
  assert(Run.signal(s,id(18),8)=="red")
  d.life.bits[id(25)],d.life.claims[id(25)],d.life.trains[intruder]=nil,nil,nil
  local arrived
  for _=1,60 do
    Sim.daily(s)
    assert(not d.failure,d.failure)
    if run.phase=="dwell" then arrived=true;break end
  end
  assert(arrived and run.consist.parts[1].tile==id(24))
  assert(L.claim_owner(d.life,id(23,15),T.X)==run.id and L.valid_state(Run.board(s),d.life))
  print("PASS: occupied extension rolls back path, station, and PBS aspect; retry after clearing completes")
  return
end
-- Known carry from a different stock transport, not a new private
-- per-train fraction. Calculate the reference separately from Roster.
local fraction=37
company.stock_money_fraction=fraction
local settled_ticks,charged_cash,charged_fixed=0,0,0
local function settlement(active,missed)
  local previous=run.running_ticks_total
  local previous_cash,previous_expense=company.cash,company.expense
  local previous_revenue=company.revenue
  local fixed=active and math.floor(annual*(previous-settled_ticks-(missed or 0))/(365*74)) or 0
  local whole=math.floor((fixed+255-fraction)/256)
  fraction=(fraction-fixed)%256
  charged_fixed,charged_cash=charged_fixed+fixed,charged_cash+whole
  if active then settled_ticks=previous-(missed or 0) end
  Sim.daily(s)
  local live=assert(Owned.running(s,owner,unit.id))
  assert(company.stock_money_fraction==fraction and live.running_expense==charged_cash)
  assert(live.running_cost_fp==charged_fixed and live.charged_running_ticks==settled_ticks)
  assert(Sim.rail_paid_status(s).running_expense==charged_cash)
  if s.day%30~=0 then
    assert(company.expense-previous_expense==whole)
    assert(company.cash-previous_cash==company.revenue-previous_revenue-whole)
  end
  -- Repeated callback in one world day, including after reload, must
  -- not settle ticks already processed or settle today's unfinished day.
  assert(Run.settle_passenger_running_day(s)==nil)
  assert(run.running_ticks_total>=previous)
  return run.running_ticks_total-previous
end
if arg and arg[1]=="finance" then
  assert(settlement(true)==74 and charged_cash==0)
  s.rail_paid_service=false
  assert(settlement(false)==0 and charged_cash==0)
  reload()
  s.rail_paid_service=true
  assert(settlement(true)==74 and charged_cash==3)
  for _=1,8 do
    if run.speed>0 then break end
    settlement(true)
  end
  assert(run.speed>0)
  assert(Owned.toggle(s,owner,unit.id))
  local braking=settlement(true)
  assert(braking>0 and braking<74 and run.speed==0)
  reload()
  assert(settlement(true)==0)
  local parked=charged_cash
  s.day=364
  assert(settlement(true)==0 and s.day==365 and charged_cash==parked) -- Jan 1, 1951
  assert(settlement(true)==0 and charged_cash==parked)
  assert(Owned.toggle(s,owner,unit.id))
  assert(settlement(true)==74)
  -- Upgrade a save made before paid passenger operations had a daily
  -- expense journal. There is no retroactive rate batch in that old save.
  local legacy=run.running_ticks_total
  run.passenger_finance=nil
  reload()
  settled_ticks,charged_cash,charged_fixed=0,0,0
  assert(settlement(true,legacy)==74 and charged_cash==0)
  assert(Owned.running(s,owner,unit.id).legacy_unbilled_running_ticks==legacy)
  assert(settlement(true,legacy)==74 and charged_cash==3)
  print("PASS: exact shared fraction/debit, daily-once restart, disabled, braking, parked, calendar and uncharged-save upgrade")
  return
end
local fare,passengers=0,0
local had_mass,had_load_reload,had_paid_reload,at_bridge,at_tunnel,at_cross=false,false,false,false,false,false
local expense_after_purchase=company.expense
local peak=0
local saw_through_claim=false
for _=1,130 do
  local previous=run.running_ticks_total
  assert(settlement(true)==74)
  assert(run.running_ticks_total==previous+74)
  local d=Run.current(s)
  assert(not d.failure,d.failure)
  local st=Sim.rail_paid_status(s)
  if lookahead and run.station==east and run.phase=="dwell" then
    assert(run.order.station==east and run.arrival.tile==id(24))
    assert(L.claim_owner(d.life,id(25),T.X)==run.id)
    assert(L.claim_owner(d.life,id(26,10),T.RIGHT)==run.id)
    assert(L.claim_owner(d.life,id(23,15),T.X)==run.id)
    assert(not L.claim_owner(d.life,id(22,15),T.X))
    saw_through_claim=true
  end
  assert(st.capacity==40 and st.onboard==run.passengers_onboard)
  assert(run.speed<=vmax and run.consist_mass==mass+math.floor(st.onboard/16))
  peak=math.max(peak,run.speed)
  if run.consist_mass>mass then had_mass=true end
  assert(Motion.check_spacing(Run.board(s),run.consist) and L.valid_state(Run.board(s),d.life))
  for _,e in ipairs(Sim.rail_paid_motion_events(s)) do
    if mixed then
      if e.kind=="path_after_block" then
        assert(e.tile==id(14))
        mixed_path=true
      end
      if e.kind=="block_aspect" and e.tile==id(14) and e.td==8 then
        if e.green and mixed_closed then mixed_reopened=true
        elseif not e.green then mixed_closed=true end
      end
    end
    if e.kind=="span_released" and (e.tile==id(5) or e.tile==id(9)) then at_bridge=true end
    if e.kind=="tunnel_hidden" then at_tunnel=true end
    if e.kind=="front_entered" and e.tile==id(20) then
      at_cross=true
      if use_spans then assert(CrossWorld.record(s,id(20))) end
    end
    if e.kind=="arrived" and e.station==east then assert(e.cargo_tile==id(24)) end
    if e.kind=="waypoint_passed" then
      assert(via_tile and e.tile==via_tile and e.waypoint==via_id and e.speed>0)
      via_passes=via_passes+1
    end
    assert(not via_tile or e.kind~="arrived" or e.tile~=via_tile)
  end
  for _,e in ipairs(Sim.rail_loading_events(s)) do
    if e.kind=="board" then assert(e.units<=5) end
    if e.kind=="fare" then fare,passengers=fare+e.amount,passengers+e.units end
  end
  assert(st.fare==fare and st.delivered==passengers and company.revenue==fare and
    company.cash==cash+fare-(company.expense-expense_after_purchase))
  if st.loading and st.onboard>0 and not had_load_reload then
    had_load_reload=true;reload()
    if jubilee then
      mount(true,false);run=assert(Run.current_paid(s))
      local frozen=Sim.rail_paid_status(s)
      local ticks,steps,balance=run.running_ticks_total,run.stock_steps,company.cash
      assert(frozen.paused and frozen.loading and frozen.onboard==st.onboard)
      assert(settlement(false)==0)
      local again=Sim.rail_paid_status(s)
      assert(again.paused and again.loading and again.onboard==st.onboard)
      assert(company.cash==balance and run.running_ticks_total==ticks and run.stock_steps==steps)
      assert(Run.mount_owned_model(8))
    end
  end
  if via_tile and run.order.kind=="waypoint" and run.index>1 and not via_reloaded then
    via_reloaded=true
    reload()
    assert(run.order.kind=="waypoint" and run.order.station==via_id)
  end
  if fare>0 and not had_paid_reload then had_paid_reload=true;reload() end
  if run.shuttle.arrivals>=3 and passengers>0 and had_mass and had_load_reload and had_paid_reload then break end
end
assert(run.shuttle.arrivals>=3 and run.shuttle.reversals>=(lookahead and 0 or 2) and passengers>0)
if via_tile then
  assert(via_reloaded and via_passes>=2 and run.via.passes==via_passes)
  assert(not s.stock_rail_stations[via_id])
  print("PASS: paid owned shuttle passes both ordered waypoints moving; native quote/keep-rail/serialization")
end
if lookahead then
  assert(saw_through_claim and run.shuttle.reversals==0)
  if mode=="platform_fallback" then assert(fallback_calls>0) end
  print("PASS: reserve beyond an unsafe through platform without skipping the actual stop, take next order and repeat")
end
if mixed then
  assert(mixed_path and mixed_closed and mixed_reopened,"mixed entrance must reserve after entry, and occupancy must close and reopen it")
  print("PASS 16.0-RC1 live mixed entrance reserves after crossing its conventional signal, reopens behind its last wagon")
end
if mode=="signal_free" or turnout then
  assert(run.ordinary_unreserved and not run.platform_lookahead and run.shuttle.reversals>=2)
  assert(not next(s.stock_rail_dispatch.signals.records))
  if turnout then
    assert(turnout_decisions[T.LEFT] and turnout_decisions[T.X], "the actual consist must choose a turn at depot departure and the main line during service")
    print("PASS automatic depot attachment: live order routing selects the exit curve, then passes the turnout both ways with no signals")
  end
  print("PASS stock default signal-free passenger shuttle reverses automatically and earns fares")
end
assert(had_mass and had_load_reload and had_paid_reload and Owned.running(s,owner,unit.id).future_daily_rate_fp==(jubilee and 1841 or 767))
if jubilee and not use_spans then assert(peak>64,"Jubilee never reached original speed above the Kirby cap") end
if use_spans then assert(at_bridge and at_tunnel and at_cross,("%s %s %s"):format(tostring(at_bridge),tostring(at_tunnel),tostring(at_cross))) end
assert(charged_cash>0 and charged_fixed>0)
print(("PASS: bought %s + coach, stock acceleration/actual mass, load and fare reload, %d passengers/$%d, $%d running expense (%s)"):
 format(Roster.entry(engine).name,passengers,fare,charged_cash,use_spans and "stock bridge, tunnel and crossing" or "ordinary stock railway"))

if not mode then
  core={get_modpath=function() return "mods/luanttd_core" end}
  local tutorial=dofile(root.."business_tutorials.lua")({s=s,Sim=Sim,rail_owned=Owned})
  local goal,earned=tutorial.progress(owner,"rail")
  assert(goal==7 and earned==fare,"the real paid consist should complete the lesson")
  local dispatch=s.stock_rail_dispatch
  s.stock_rail_dispatch={owner=owner,signals=dispatch.signals,runs={}}
  local fleet=Owned.list
  Owned.list=function()return {} end
  assert(tutorial.progress(owner,"rail")==4,"the documented return-facing signal should pass")
  local signal=dispatch.signals.records[id(10)]
  local mask=signal.present_signals
  signal.present_signals=T.signal_along(8)
  assert(tutorial.progress(owner,"rail")==3,"flipping the documented signal should raise a lesson warning")
  signal.present_signals=mask
  Owned.list=fleet;s.stock_rail_dispatch=dispatch
end
