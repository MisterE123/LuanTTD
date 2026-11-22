-- SPDX-License-Identifier: GPL-2.0-only
local base="mods/luanttd_core/"
local Sim=dofile(base.."sim.lua")
local T=dofile(base.."openttd/rail_track.lua")
local Follow=dofile(base.."openttd/rail_follow.lua")(T)
local Lab=dofile(base.."trackworks.lua")(Sim,T,Follow)
local Roster=dofile(base.."openttd/rail_roster.lua")
local Fleet=dofile(base.."rail_depot_fleet.lua")(Sim,Lab,Roster)
local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local r={}
  for k,v in pairs(t) do r[k]=clone(v) end
  return r
end
local function no(reason,obj,why) assert(not obj and reason==why,tostring(why).." ~= "..reason) end
local function make(climate,extra)
  local S=Sim.new(1751)
  local a,b=Sim.id(2,4),Sim.id(2,5)
  for z=4,5 do
    for x=2,5 do
      local tile=S.tiles[Sim.id(x,z)]
      tile.rail_tracks,tile.owner,tile.build=1,z==4 and "Alice" or "Bob","stock_rail"
    end
  end
  assert(Lab.depot(S,"Alice",a,T.SW))
  assert(Lab.depot(S,"Bob",b,T.SW))
  Sim.company(S,"Alice")
  Sim.company(S,"Bob")
  local options={starting_year=1950,generation_seed=S.seed,startup_random=1779097732,climate=climate}
  for k,v in pairs(extra or {}) do options[k]=v end
  assert(Fleet.initialize(S,options))
  return S,a,b
end
local s,a,b=make("temperate")
assert(Fleet.availability(s,0).status=="available")
assert(Fleet.availability(s,1).status=="wrong_climate")
local newer=assert(Fleet.availability(s,8))
assert(newer.public and newer.age_months==16*12)
s.stock_rail_fleet.models[8]=nil -- pre-roster-expansion save
local from_old=assert(Fleet.availability(s,8))
assert(from_old.reliability==newer.reliability and from_old.intro==newer.intro)
assert(not s.stock_rail_fleet.models[8],"An availability query must not rewrite the old save")
local jubilee_quote=assert(Fleet.quote(s,"Alice",a,{8,27}))
assert(jubilee_quote.price==22241 and jubilee_quote.stats.max_track_speed==112)
local a4=assert(Fleet.availability(s,9))
assert(a4.public and a4.age_months==15*12)
s.stock_rail_fleet.models[9]=nil -- save prior to adding the A4 row
local old=assert(Fleet.availability(s,9))
assert(old.public and old.reliability==a4.reliability and old.intro==a4.intro)
assert(not s.stock_rail_fleet.models[9],"An availability query must not rewrite the old save")
local a4_quote=assert(Fleet.quote(s,"Alice",a,{9,27}))
assert(a4_quote.price==31616 and a4_quote.stats.max_track_speed==128)
assert(Fleet.availability(s,27).public and Fleet.availability(s,29).public)
local before=s.companies.Alice.cash
local before_month=s.companies.Alice.month_exp
local q=assert(Fleet.quote(s,"Alice",a,{0,27,29}))
assert(q.price==14241 and q.unit_number==1 and q.depot_dir==T.SW)
assert(s.companies.Alice.cash==before and #Fleet.list(s,"Alice")==0 and not Fleet.occupies_depot(s,a))
no("INVALID_OWNED_DEPOT",Fleet.quote(s,"Bob",a,{0}))
no("RAIL_VEHICLE_NOT_AVAILABLE",Fleet.quote(s,"Alice",a,{1,27}))
no("ONE_LEAD_LOCOMOTIVE_REQUIRED",Fleet.quote(s,"Alice",a,{27,0}))
no("ONE_LEAD_LOCOMOTIVE_REQUIRED",Fleet.quote(s,"Alice",a,{0,0}))
no("INVALID_RAIL_FLEET_CONSIST",Fleet.quote(s,"Alice",a,{[1]=0,[3]=27}))
local wrong_quote=clone(q);wrong_quote.price=1
no("STALE_RAIL_FLEET_QUOTE",Fleet.commit(s,"Alice",wrong_quote))
assert(s.companies.Alice.cash==before)
local hooks={price_settings=function() return {inflation=2*65536} end}
no("STALE_RAIL_FLEET_QUOTE",Fleet.commit(s,"Alice",q,hooks))
s.companies.Alice.cash=100
no("NOT_ENOUGH_CASH",Fleet.commit(s,"Alice",q))
s.companies.Alice.cash=before
s.day=1 -- a legitimate delayed UI purchase revalidates today's rules
local bought=assert(Fleet.commit(s,"Alice",q))
assert(bought.id==1 and bought.parts[1].build_year==1950 and bought.parts[1].reliability_decay==80)
assert(bought.parts[1].reliability==Fleet.availability(s,0).reliability and bought.parts[1].max_age_days==5490)
assert(not bought.parts[2].reliability and not bought.parts[3].max_age_days)
assert(Fleet.occupies_depot(s,a))
assert(s.companies.Alice.cash==before-14241 and s.companies.Alice.expense==14241 and s.companies.Alice.month_exp==before_month+14241)
s=clone(s)
no("STALE_RAIL_FLEET_QUOTE",Fleet.commit(s,"Alice",q))
assert(bought.id==Fleet.get(s,"Alice",1).id and not Fleet.get(s,"Bob",1))
local p=assert(Fleet.prepare_dispatch(s,"Alice",bought.id))
assert(p.stats.total_length==24 and p.stats.max_track_speed==64 and p.stats.acceleration==12)
assert(p.stats.cargo_capacity.passenger==40 and p.stats.cargo_capacity.coal==30)
assert(table.concat(p.stock_ids,",")=="0,27,29")
p.parts[1].stock_id=1; bought.stock_ids[1]=1
assert(Fleet.prepare_dispatch(s,"Alice",1).parts[1].stock_id==0)
local qa=assert(Fleet.quote(s,"Alice",a,{0,27}))
local qb=assert(Fleet.quote(s,"Bob",b,{0}))
assert(qa.unit_number==2 and qb.unit_number==1)
assert(Fleet.commit(s,"Bob",qb).id==2)
no("STALE_RAIL_FLEET_QUOTE",Fleet.commit(s,"Alice",qa))
assert(Fleet.bind_dispatch(s,"Alice",1,91))
assert(not Fleet.occupies_depot(s,a))
s=clone(s)
assert(Fleet.get(s,"Alice",1).run_id==91)
no("RAIL_CONSIST_ALREADY_DISPATCHED",Fleet.prepare_dispatch(s,"Alice",1))
no("RAIL_CONSIST_ALREADY_DISPATCHED",Fleet.bind_dispatch(s,"Alice",1,92))
no("RAIL_DISPATCH_ID_IN_USE",Fleet.bind_dispatch(s,"Bob",2,91))
assert(s.companies.Alice.cash==before-14241)

local c,at=make("temperate",{max_trains=1,vehicle_pool=3,max_train_tiles=1})
no("TRAIN_TOO_LONG",Fleet.quote(c,"Alice",at,{0,27,29}))
assert(Fleet.commit(c,"Alice",assert(Fleet.quote(c,"Alice",at,{0,27}))))
no("TOO_MANY_VEHICLES_IN_GAME",Fleet.quote(c,"Alice",at,{0}))
c,at=make("temperate",{vehicle_pool=2})
no("TOO_MANY_VEHICLES_IN_GAME",Fleet.quote(c,"Alice",at,{0,27},
  {other_pool_count=function()return 1 end}))
local nextunit=assert(Fleet.quote(c,"Alice",at,{0},
  {other_company_units=function()return {[1]=true,[3]=true} end}))
assert(nextunit.unit_number==2)
local orient=assert(Fleet.quote(c,"Alice",at,{0}))
c.tiles[at].owner="Bob"
no("INVALID_OWNED_DEPOT",Fleet.commit(c,"Alice",orient))
assert(c.companies.Alice.cash==100000 and not Fleet.occupies_depot(c,at))
c.tiles[at].owner="Alice"
assert(Fleet.commit(c,"Alice",orient))
c.tiles[at].rail_depot_dir=T.NE
no("INVALID_OWNED_DEPOT",Fleet.prepare_dispatch(c,"Alice",1))

local preview,pd=make("temperate",{roster_preview=true})
assert(not Fleet.availability(preview,1).public)
assert(Fleet.commit(preview,"Alice",assert(Fleet.quote(preview,"Alice",pd,{1,27}))).roster_preview)
assert(Fleet.prepare_dispatch(preview,"Alice",1).stats.max_track_speed==80)
local arctic,ad=make("arctic")
no("RAIL_VEHICLE_NOT_AVAILABLE",Fleet.quote(arctic,"Alice",ad,{0,27}))
assert(Fleet.availability(arctic,1).status=="not_introduced")
local transitions,states={},{}
for day=0,36525,1 do
  arctic.day=day
  local st=Fleet.availability(arctic,1)
  if not states[st.status] then
    transitions[#transitions+1]=st.status
    states[st.status]=st
  end
end
assert(table.concat(transitions,",")=="not_introduced,preview_period,available,retired")
assert(states.preview_period.as_of==states.preview_period.intro)
assert(states.available.as_of>=states.preview_period.as_of+365 and states.available.as_of<=states.preview_period.as_of+396)
assert(states.available.age_months==0 and states.available.reliability==states.available.reliability_start)
local retired=assert(Fleet.availability(arctic,1))
assert(retired.reliability==retired.reliability_final and retired.age_months>=retired.phase1+retired.phase2+retired.phase3)
assert(Fleet.availability(arctic,27).public)
local always=make("arctic",{never_expire=true})
always.day=36525
assert(Fleet.availability(always,1).public and Fleet.availability(always,1).age_months>200)
local Calendar=dofile(base.."openttd/stock_engine_calendar.lua")
local early,ed=make("temperate",{starting_year=1930,generation_seed=1751,startup_random=9001})
local jan=Calendar.date(1930,1,1)
early.day=Calendar.date(1936,2,27)-jan
assert(Fleet.availability(early,9).status=="not_introduced")
early.day=early.day+1
assert(Fleet.availability(early,9).status=="preview_period")
no("RAIL_VEHICLE_NOT_AVAILABLE",Fleet.quote(early,"Alice",ed,{9,27}))
early.day=Calendar.date(1937,3,1)-jan-1
assert(Fleet.availability(early,9).status=="preview_period")
early.day=early.day+1
local newly_available=assert(Fleet.availability(early,9))
assert(newly_available.public and newly_available.age_months==0)
assert(newly_available.reliability==newly_available.reliability_start)
local purchase=assert(Fleet.commit(early,"Alice",assert(Fleet.quote(early,"Alice",ed,{9,27}))))
assert(purchase.parts[1].build_year==1937 and purchase.parts[1].max_age_days==20*366)
assert(early.companies.Alice.cash==100000-31616)
early.day=Calendar.date(1980,1,1)-jan
assert(Fleet.availability(early,9).status=="retired")
no("RAIL_VEHICLE_NOT_AVAILABLE",Fleet.quote(early,"Alice",ed,{9,27}))
assert(Fleet.prepare_dispatch(early,"Alice",purchase.id).stock_ids[1]==9,"retirement must not delete built vehicles")
local starter,sd=make("temperate",{starting_year=1950,generation_seed=1751,startup_random=9001})
local year1950=Calendar.date(1950,1,1)
assert(Fleet.availability(starter,15).status=="not_introduced")
no("RAIL_VEHICLE_NOT_AVAILABLE",Fleet.quote(starter,"Alice",sd,{15,27}))
starter.day=Calendar.date(1962,12,10)-year1950
assert(Fleet.availability(starter,15).status=="preview_period")
starter.day=Calendar.date(1964,1,1)-year1950-1
assert(Fleet.availability(starter,15).status=="preview_period")
starter.day=starter.day+1
assert(Fleet.availability(starter,15).public and Fleet.availability(starter,15).age_months==0)

local diesel,dd=make("temperate",{starting_year=1966,generation_seed=1751,startup_random=9001})
local year1966=Calendar.date(1966,1,1)
local available=assert(Fleet.availability(diesel,15))
assert(available.public and available.age_months==48 and available.intro==Calendar.date(1962,1,1))
diesel.stock_rail_fleet.models[15]=nil -- older save with the same world seed
assert(Fleet.availability(diesel,15).reliability==available.reliability)
assert(not diesel.stock_rail_fleet.models[15])
local diesel_quote=assert(Fleet.quote(diesel,"Alice",dd,{15,27}))
assert(diesel_quote.price==30054 and diesel_quote.stats.max_track_speed==160)
local paid=assert(Fleet.commit(diesel,"Alice",diesel_quote))
assert(paid.parts[1].build_year==1966 and paid.parts[1].max_age_days==22*366)
assert(diesel.companies.Alice.cash==100000-30054)
diesel=clone(diesel)
no("STALE_RAIL_FLEET_QUOTE",Fleet.commit(diesel,"Alice",diesel_quote))
diesel.day=Calendar.date(2007,11,1)-year1966-1
assert(Fleet.availability(diesel,15).public)
diesel.day=diesel.day+1
assert(Fleet.availability(diesel,15).status=="retired")
no("RAIL_VEHICLE_NOT_AVAILABLE",Fleet.quote(diesel,"Alice",dd,{15,27}))
assert(Fleet.prepare_dispatch(diesel,"Alice",paid.id).stock_ids[1]==15)
for _,climate in ipairs({"temperate","arctic","tropic","toyland"}) do
  local research,od=make(climate)
  local a=Fleet.availability(research,30)
  assert(a.public==(climate~="toyland") and a.intro==Calendar.date(1925,1,1))
  if climate=="temperate" then no("RAIL_VEHICLE_NOT_MOUNTED",Fleet.quote(research,"Alice",od,{0,30})) end
  research.day=Calendar.date(2100,1,1)-Calendar.date(1950,1,1)
  assert(Fleet.availability(research,30).public==(climate~="toyland"))
end
local gated,gd=make("temperate",{roster_preview=true})
local forged=assert(Fleet.quote(gated,"Alice",gd,{0,29}))
forged.stock_ids[2]=30
no("RAIL_VEHICLE_NOT_MOUNTED",Fleet.commit(gated,"Alice",forged))
assert(gated.companies.Alice.cash==100000 and #Fleet.list(gated,"Alice")==0)
local o,od=make("temperate")
local mounted={oil_wagon_ready=function(state) return state==o end}
no("RAIL_VEHICLE_NOT_MOUNTED",Fleet.quote(o,"Alice",od,{0,30},mounted))
o.rail_oil_service=true
no("RAIL_VEHICLE_NOT_MOUNTED",Fleet.quote(o,"Alice",od,{0,30}))
no("RAIL_VEHICLE_NOT_MOUNTED",Fleet.quote(o,"Alice",od,{0,30,30},mounted))
local a4_oil=assert(Fleet.quote(o,"Alice",od,{9,30},mounted))
assert(a4_oil.stats.weight==186 and a4_oil.stats.max_weight==216)
no("RAIL_VEHICLE_NOT_MOUNTED",Fleet.quote(o,"Alice",od,{9,30}))
local oq=assert(Fleet.quote(o,"Alice",od,{0,30},mounted))
no("RAIL_VEHICLE_NOT_MOUNTED",Fleet.commit(o,"Alice",oq))
assert(oq.price==12499 and oq.stats.weight==71)
local unit=assert(Fleet.commit(o,"Alice",oq,mounted))
assert(unit.stock_ids[2]==30 and o.companies.Alice.cash==100000-oq.price)

local late=make("temperate",{starting_year=2060})
local at_start=Fleet.availability(late,0)
late.day=3660
assert(Fleet.availability(late,0).age_months==at_start.age_months)
print("PASS: actual owned depot procurement, stock design introduction/retirement, one-shot debit, limits, saved ordering and dispatch preparation")
