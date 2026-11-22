-- SPDX-License-Identifier: GPL-2.0-only
-- Two paid rail actors share actual directional PBS claims on one clock.
local root="mods/bayline/"
local src=root.."openttd/"
local function port(name,...) return dofile(src..name..".lua")(...) end
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(src.."terrain.lua")
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
local Dispatch=dofile(root.."rail_consist_dispatch.lua")(Consist,Life)
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,dofile(src.."slope.lua"),C,Search)
local Roster=dofile(src.."rail_roster.lua")
local Run=dofile(root.."rail_dispatch_run.lua")(T,F,C,Search,PBS,Life,Signal,Consist,Dispatch,Speed,Lab,nil,Reverse,nil,nil,Roster)
local Fleet=dofile(root.."rail_depot_fleet.lua")(Sim,Lab,Roster)
local Owned=dofile(root.."rail_owned_service.lua")(Fleet,Roster,Run)
local s=Sim.new(1751)
s.rail_owned_service,s.rail_paid_service=true,true
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.stock_select_goods=false
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
for _,t in ipairs(s.tiles) do
  t.terrain,t.build,t.owner,t.site,t.wood,t.house,t.h="grass",nil,nil,nil,nil,nil,0
end
local owner="Joint Stock"
local id=Sim.id
local first,lastA,lastB=dofile("tests/rail_owned_pair_fixture.lua")(s,Sim,T,Lab,Run,Signal,owner)
local company=Sim.company(s,owner)
assert(Owned.initialize(s,{starting_year=1950,generation_seed=s.seed,startup_random=19017}))
local mixed=arg and arg[1]=="mixed"
if mixed then assert(Run.mount_owned_model(9)) end
local function buy(depot,model)
  local quote=assert(Owned.quote(s,owner,depot,{model or 0,27}))
  local u=assert(Owned.commit(s,owner,quote))
  return u.id
end
local a,b=buy(id(2,14)),buy(id(8,9),mixed and 9 or 0)
local setup={{id=a,first=first,second=lastA},{id=b,first=first,second=lastB}}
local function mount() Sim.mount_paid_rail(s,Run) end
mount()
assert(not Owned.start_pair(s,owner,setup[1],setup[2]))
s.rail_owned_pair_enabled=true
local old=Run.current(s)
local bad={id=b,first=first,second=9000}
local ok,why=Owned.start_pair(s,owner,setup[1],bad)
assert(not ok and why and #Run.current(s).runs==0 and Run.current(s)==old and not s.next_paid_rail_run)
assert(Owned.get(s,owner,a).status=="depot" and Owned.get(s,owner,b).status=="depot")
assert(not Owned.start_pair(s,owner,setup[1],{id=b,first=first,second=lastA}))
assert(company.cash==100000-12866-(mixed and 31616 or 12866))
local ok,note,runs=Owned.start_pair(s,owner,setup[1],setup[2])
assert(ok,note)
assert(runs[1].paid_clock~=runs[2].paid_clock and runs[1].id~=runs[2].id)
assert(runs[1].stock_engine==0 and runs[1].max_track_speed==64)
assert(runs[2].stock_engine==(mixed and 9 or 0) and runs[2].max_track_speed==(mixed and 128 or 64))
if mixed then assert(runs[1].running_year_fp==280000 and runs[2].running_year_fp==784000) end
assert(Owned.toggle(s,owner,b))
local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local d={}
  for k,v in pairs(t) do d[k]=clone(v) end
  return d
end
local function reload()
  s=clone(s);mount()
  company=s.companies[owner]
  assert(Owned.get(s,owner,a).status=="dispatched" and Owned.get(s,owner,b).status=="dispatched")
end
local merge=id(8,14)
local entered,tail,held={},{},{}
local reload_loading,reload_tail=false,false
local fare,units={[a]=0,[b]=0},{[a]=0,[b]=0}
local function by_train(train) return Run.current(s).runs[train] end
for _=1,140 do
  Sim.daily(s)
  if s.day==1 then assert(Owned.toggle(s,owner,b)) end
  local d=Run.current(s)
  assert(not d.failure,d.failure)
  assert(Life.valid_state(Run.board(s),d.life))
  local must_reload=false
  for _,r in ipairs(d.runs) do
    assert(Consist.check_spacing(Run.board(s),r.consist))
  end
  local busy_actual={}
  for _,r in ipairs(d.runs) do
    for i=1,2 do
      local tile,td=Sim.rail_paid_pose(s,i,1,r.fleet_id)
      local actual=r.consist.parts[i]
      assert(actual.hidden and tile==nil or not actual.hidden and actual.tile==tile and actual.pose.td==td)
      if not actual.hidden then
        assert(not busy_actual[tile] or busy_actual[tile]==r.id,"Two trains physically overlap on a shared rail tile")
        busy_actual[tile]=r.id
        if tile==merge and i==2 and r.consist.parts[1].tile~=merge and not reload_tail then
          local loser=3-r.id
          assert(Life.claim_owner(d.life,merge,T.track(actual.pose.td))==r.id)
          assert(Run.signal(s,loser==1 and id(7,14) or id(8,13),loser==1 and 8 or 1)=="red")
          reload_tail=true;must_reload=true
        end
      end
    end
  end
  for _,e in ipairs(Sim.rail_paid_motion_events(s)) do
    if e.kind=="front_entered" and e.tile==merge then entered[e.train]=e.world_tick end
    if e.kind=="tail_left" and e.tile==merge then tail[e.train]=e.world_tick end
    if e.kind=="waiting" then held[e.train]=e.world_tick end
    if e.kind=="arrived" and e.station==first then
      local cargo=by_train(e.train)
      local peer=by_train(3-e.train)
      if not reload_loading and peer.paired.arrivals>0 and cargo.paired.arrivals>0 then reload_loading=true;must_reload=true end
    end
  end
  for _,e in ipairs(Sim.rail_loading_events(s)) do
    local run=e.vehicle==0x4000+1 and a or e.vehicle==0x4000+2 and b
    assert(run,"Lost independent actor identity")
    if e.kind=="fare" then fare[run]=fare[run]+e.amount;units[run]=units[run]+e.units end
  end
  for _,fid in ipairs({a,b}) do
    local st=assert(Sim.rail_paid_status(s,fid))
    assert(st.fare==fare[fid] and st.delivered==units[fid])
  end
  if must_reload then
    local commercial=s.stock_ship_commercial
    local oldA,oldB=commercial.service.vehicles[0x4001].visit,commercial.service.vehicles[0x4002].visit
    reload()
    assert(s.stock_ship_commercial.service.vehicles[0x4001].visit==oldA)
    assert(s.stock_ship_commercial.service.vehicles[0x4002].visit==oldB)
  end
  if Run.current_paid(s,a).paired.complete and Run.current_paid(s,b).paired.complete then break end
end
local d=Run.current(s)
local c0,c1=Run.current_paid(s,a),Run.current_paid(s,b)
assert(c0.paired.complete and c1.paired.complete)
assert(entered[1] and entered[2] and tail[1] and tail[2])
if entered[1]<entered[2] then assert(tail[1]<=entered[2])
else assert(tail[2]<=entered[1]) end
assert(next(held),"No PBS contention in the fixture")
assert(reload_loading,"No serialized independent loading moment")
assert(reload_tail,"No saved last-wagon-only occupation on the shared merge")
for _,fid in ipairs({a,b}) do
  local r=Run.current_paid(s,fid)
  local head=r.consist.parts[1]
  assert(r.stopped and r.paired.arrivals==2 and r.passengers_onboard==0)
  assert(Life.claim_owner(d.life,head.tile,T.track(head.pose.td))==r.id,"Parked train lost its physical claims")
  assert(units[fid]>0 and fare[fid]>0 and Owned.running(s,owner,fid).running_expense>0)
end
assert(company.revenue==fare[a]+fare[b])
assert(not Owned.toggle(s,owner,a) and not Owned.toggle(s,owner,b))
print(("PASS: paired same-direction paid %s trains (units %d/%d, fares $%d/$%d), PBS waits and occupied terminals"):
  format(mixed and "Kirby/Ginzu" or "Kirby/Kirby",units[a],units[b],fare[a],fare[b]))
