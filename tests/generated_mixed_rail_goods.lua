-- SPDX-License-Identifier: GPL-2.0-only
-- Actual generated 64² mixed industry seed1751. This host test uses the same
-- priced company build commands, owned rail dispatch and 74-tick ledger as
-- the game. Good batches are sourced only by actual Wood truck deliveries.
local root="mods/luanttd_core/"
local function m(path) return dofile(root..path..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local TG=m("openttd/terragenesis")(m("openttd/slope"))
local Clear=m("openttd/terragenesis_clear")
local Gen={generate=function(o) return Clear.generate(TG.generate(o),TG.next_random) end,
  describe=Clear.describe,next_random=TG.next_random}
local Cam,G=m("generated_campaign"),m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
dofile("tests/fixed_parcel_footprint.lua")(Build)
local Calendar=m("openttd/stock_engine_calendar")
local at=Sim.id
local s=Cam.landscape(Sim,Terrain,Gen,{width=64,depth=64,seed=1751,terrain_type=1,quantity_sea_lakes=0,
  tgen_smoothness=1,freeform_edges=true,water_borders=15,variety=0,rng_state=TG.startup_rng(1751)})
local named=m("openttd/stock_town_name")
assert(Cam.towns(Sim,Terrain,s,Gen,m("openttd/town_worldgen")(G,Build),named,G,Build,
  {difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}).success)
local P,Rating=m("openttd/passengers"),m("openttd/station_rating")
local Cat=m("openttd/station_catchment")(P,Rating,function()return 0 end,function()return 0 end)
local Coal=m("openttd/coal_industry")(P,Rating,Cat,m("openttd/income"))
local Timber=Sim.timber_rules()
local CoalWorld=m("coal_industry_world")(Sim,Terrain,Coal)
local TimberWorld=m("timber_world")(Sim,Terrain,Timber)
local picked=Cam.industries(Sim,Terrain,s,Gen,m("openttd/industry_worldgen")(Coal,Timber),CoalWorld,4,nil,TimberWorld)
assert(picked.target==4 and picked.shortfall==0)
Cam.landmarks(Sim,Terrain,s,Gen,m("openttd/scenery_object_worldgen"),Calendar.date(Sim.date(s)))
Cam.forests(Sim,Terrain,s,Gen,m("openttd/tree_worldgen"),2)
local by_tile={}
for _,r in ipairs(s.stock_generated_profile.industries) do by_tile[r.tile]=r end
local mine,power,mill,forest=by_tile[at(47,41)],by_tile[at(30,28)],by_tile[at(23,42)],by_tile[at(48,44)]
assert(mine.kind=="coal_mine" and power.kind=="power_station")
assert(mill.kind=="sawmill" and forest.kind=="forest")
local growth=m("town_growth_runtime")(Sim,Terrain,G,Build,m("openttd/town_passengers"))
local function attach()
  Sim.mount_stock_town_growth(s,growth,true)
  Sim.mount_road_bus_market(s,Calendar,1950,true)
  Sim.mount_coastal_flood(s)
end
s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_coal,s.road_timber,s.road_junction_clearance=true,true,true
attach()
local owner="Mixed Freight"
local function road(x,z,u,v)
  local ok,why=Sim.build(s,owner,"road",Sim.line(at(x,z),at(u,v)))
  assert(ok,("Road %d,%d to %d,%d: %s"):format(x,z,u,v,tostring(why)))
end
-- One spine, one honest through stop for each endpoint, and room to
-- turn in the actual direction of travel. No terrain modifications.
road(25,44,47,44)
for _,r in ipairs{
  {25,44,25,45},{25,45,30,45},{30,45,30,44}, -- Wood: turn beyond sawmill
  {47,44,47,46},{47,46,46,46},{46,46,46,44}, -- Wood: turn beyond Forest
  {46,44,46,40},{46,40,45,40},{45,40,45,43},{45,43,46,43}, -- Coal: mine approach and loop
  {29,44,29,26},{29,26,28,26},{28,26,28,30},{28,30,29,30}, -- Coal: plant approach and loop
} do road(unpack(r)) end
local wood_pick,wood_drop=at(45,44),at(26,44)
local coal_pick,coal_drop=at(46,41),at(29,28)
local depot=at(32,43)
local function stop(id)
  local ok,why=Sim.build_truck_stop(s,owner,id);assert(ok,why)
  return s.stations[s.tiles[id].station]
end
local wood_a,wood_b,coal_a,coal_b=stop(wood_pick),stop(wood_drop),stop(coal_pick),stop(coal_drop)
assert(Sim.build(s,owner,"road_depot",{depot}))
local _,forest_accept=Sim.timber_stop_status(s,wood_a,"wood")
local _,mill_accept=Sim.timber_stop_status(s,wood_b,"wood")
assert(not forest_accept.accepts and mill_accept.eighths==8 and mill_accept.near[1].id==mill.industry)
local _,source_accept,_,ca=Sim.coal_stop_status(s,coal_a)
local _,destination_accept,_,cb=Sim.coal_stop_status(s,coal_b)
assert(not source_accept and #ca.sources==1 and ca.sources[1]==mine.industry)
assert(destination_accept and cb.eighths==16 and cb.near[1].ind.id==power.industry)
local function truck(engine,cargo,from,to)
  local id=assert(Sim.purchase(s,owner,engine,cargo,nil,depot))
  local v=s.fleet[id]
  for _,leg in ipairs{{from,to},{to,from}} do
    local r,td,cost,frames=Sim.path(s,leg[1],leg[2],"road",owner,nil,v)
    assert(r and td and cost>0 and #frames>260)
    assert(r[1]==leg[1].tile and r[#r]==leg[2].tile)
    assert(frames[1][4]==leg[1].tile and frames[#frames][4]==leg[2].tile)
  end
  assert(Sim.add_order(s,owner,id,from.id,"normal"))
  assert(Sim.add_order(s,owner,id,to.id,"normal"))
  assert(Sim.toggle(s,owner,id))
  return id
end
local function p(f,...) return m("openttd/"..f)(...) end
local Track,Slope=m("openttd/rail_track"),m("openttd/slope")
local F=p("rail_follow",Track)
local C=p("rail_yapf_cost",Track,F)
local Search=p("rail_yapf_search",Track,F,C)
local Motion=p("rail_motion",Track)
local PBS=p("rail_reservation",Track,F,C)
local Life=p("rail_consist_reservation",Track,F,PBS)
local Signal=p("rail_signals",Track)
local Consist=p("rail_consist_motion",Track,Motion,F,Life)
local Dispatch=m("rail_consist_dispatch")(Consist,Life)
local Speed=p("rail_station_speed",Track,F)
local Reverse=p("rail_reverse",Track,Motion,Consist,Life,Signal,F,PBS)
local Roster=m("openttd/rail_roster")
local Height=p("rail_height",Track,Slope)
local Q=p("rail_construction",Track,Signal,Height)
local function shape(id) return Terrain.tile(s.corner_grid,Sim.xy(id)) end
local Run,Owned,Tools,profile
local function asset(path,header)
  local f=io.open(root..path,"rb")
  if not f then return false end
  local actual=f:read(#header);f:close()
  return actual==header
end
local function goods_assets()
  return asset("models/bl_rail_goods_van.obj","# Original covered Goods Van #32") and
    asset("textures/bl_rail_goods_van.png",string.char(137).."PNG")
end
local function attach_rail()
 local Lab=m("trackworks")(Sim,Track,F,Slope,C,Search,shape)
 local height,pr=Height.bind(Lab.board(s),shape)
 profile=pr
 Run=m("rail_dispatch_run")(Track,F,C,Search,PBS,Life,Signal,Consist,Dispatch,Speed,Lab,height,Reverse,nil,nil,Roster)
 Owned=m("rail_owned_service")(m("rail_depot_fleet")(Sim,Lab,Roster),Roster,Run,
   Sim.rail_coal_validate,Sim.rail_oil_validate,nil,Sim.rail_goods_validate,Sim.rail_goods_active)
 Lab.owned_depot_occupied=Owned.occupies_depot
 local function price(o,why) return o and o.cost,why end
 local prices={
   track=function(t,plan,o) return price(Q.piece(t,plan.track,o)) end,
   platform=function(tiles,axis,o) return price(Q.station(tiles,axis,1,#tiles,o)) end,
   depot=function(t,d,o) return price(Q.depot(t,d,o)) end,
   signal=function(t,d,one_way,o) return price(Q.signal(t,d%2,{kind=one_way and Signal.PBS_ONEWAY or Signal.PBS},o)) end,
 }
 Tools=m("rail_construction_tools")({Sim=Sim,s=s,terrain={tile=shape},render={update=function()end},save=function()end},
   Lab,Track,Run,prices)
 Sim.mount_paid_rail(s,Run)
 Sim.mount_rail_goods(s,goods_assets)
end
s.rail_owned_service,s.rail_paid_service,s.rail_grade_enabled,s.rail_goods_service=true,true,true,true
attach_rail()
assert(Owned.initialize(s,{starting_year=1950,climate="temperate",generation_seed=1751,
  startup_random=(1751*1664525+1013904223)%4294967296}))
assert(Sim.rail_goods_active(s))
local function checked(ticket,why)
 assert(ticket,why)
 local ok,note=Tools.build(owner,ticket)
 assert(ok,note)
end
local function lay(x,z,u,v,k)
 local a,b=at(x,z),at(u,v)
 for _,id in ipairs(Sim.line(a,b)) do
  if s.tiles[id].wood then assert(Sim.build(s,owner,"clear",{id})) end
 end
 local plan,why=Tools.quote_track(owner,a,b,k,false)
 assert(plan,("Track (%d,%d)–(%d,%d): %s"):format(x,z,u,v,tostring(why)))
 checked(plan)
end
-- West-to-north flank: grade-aware joins, no chopped houses, road/rail
-- crossings, land flattening, artificial shortcuts, or industry edits.
local rail_depot=at(15,42)
lay(16,42,21,42,Track.X)
lay(22,42,22,42,Track.UPPER)
lay(22,41,22,12,Track.Y)
lay(22,11,22,11,Track.RIGHT)
lay(21,11,16,11,Track.X)
if s.tiles[rail_depot].wood then assert(Sim.build(s,owner,"clear",{rail_depot})) end
checked(Tools.quote_depot(owner,rail_depot,Track.SW))
checked(Tools.quote_platform(owner,at(17,42),at(19,42),Track.SW))
checked(Tools.quote_platform(owner,at(16,11),at(18,11),Track.NE))
checked(Tools.quote_signal(owner,at(16,42),Track.NE,false))
checked(Tools.quote_signal(owner,at(20,42),Track.SW,false))
checked(Tools.quote_signal(owner,at(19,11),Track.SW,false))
local source=s.tiles[at(17,42)].rail_station_id
local dest=s.tiles[at(16,11)].rail_station_id
local a,b=Sim.rail_goods_stop_status(s,source),Sim.rail_goods_stop_status(s,dest)
assert(#a.sources==1 and a.sources[1]==mill.industry and not a.accepts)
assert(#b.sources==0 and b.eighths==12 and b.accepts)
assert(Sim.rail_goods_designate(s,owner,source,"load"))
assert(Sim.rail_goods_designate(s,owner,dest,"unload"))
local quote=assert(Owned.quote(s,owner,rail_depot,{0,32}))
local unit=assert(Owned.commit(s,owner,quote))
assert(unit.price==12421 and unit.stock_ids[1]==0 and unit.stock_ids[2]==32)
assert(Owned.start_goods(s,owner,unit.id,source,dest))
local wood=truck("wood_truck","wood",wood_a,wood_b)
local coal=truck("coal_tipper","coal",coal_a,coal_b)
local function copy(t,seen)
 if type(t)~="table" then return t end
 seen=seen or {}
 if seen[t] then return seen[t] end
 local out={};seen[t]=out
 for k,v in pairs(t) do out[k]=copy(v,seen) end
 return out
end
local reloaded,paid_rail,unloaded,receipt=false,0,0,0
local prior_pulse,prior_visit,peak,climbed=0,nil,0,false
for day=1,193 do
  Sim.daily(s)
  local run=assert(Run.current_paid(s,unit.id))
  assert(not run.failure,run.failure)
  assert(run.stock_wagon==32 and run.freight.cargo=="goods")
  local g=assert(Sim.rail_goods_status(s))
  assert(g.tick==s.passenger_house_clock.counter and g.tick==s.stock_load_tick)
  peak=math.max(peak,run.consist_mass)
  local head_id,head_td=Sim.rail_paid_pose(s,1,1,unit.id)
  local wagon_id,wagon_td=Sim.rail_paid_pose(s,2,1,unit.id)
  if head_id and wagon_id then
    assert(head_td and wagon_td and profile(wagon_id))
    local _,pitch=Height.render(assert(profile(head_id)),head_td,.5)
    assert(pitch)
    climbed=climbed or pitch>0
  else
    assert(run.consist.parts[1].hidden or run.consist.parts[2].hidden)
  end
  for _,e in ipairs(Sim.rail_goods_loading_events(s)) do
    if e.kind=="deliver" then
      assert(e.owner==owner and e.source_industry==mill.industry and e.units==5)
      assert(e.station_local==dest and e.tile==at(16,11))
      assert(e.age>0 and (e.distance==34 or e.distance==32))
      if prior_visit==e.visit then assert(e.tick-prior_pulse==40) end
      prior_visit,prior_pulse=e.visit,e.tick
      unloaded=unloaded+e.units
    elseif e.kind=="fare" then
      receipt=receipt+1
      assert(e.owner==owner and e.station_local==dest and e.tile==at(16,11) and e.units==25)
      assert(receipt==1 and day==124 and e.amount==605 or receipt==2 and day==193 and e.amount==571)
      paid_rail=paid_rail+e.amount
    end
  end
  if day==59 then
    assert(g.onboard==5 and g.loading and g.last_platform==source and g.delivered==0)
    local company=s.companies[owner]
    local old_cash,old_revenue,old_expense=company.cash,company.revenue,company.expense
    s=copy(s);attach();attach_rail();reloaded=true
    local after=assert(Sim.rail_goods_status(s))
    assert(after.onboard==g.onboard and after.tick==g.tick and after.cargo_tile==g.cargo_tile)
    assert(Owned.get(s,owner,unit.id).status=="dispatched")
    local recovered=s.companies[owner]
    assert(recovered.cash==old_cash and recovered.revenue==old_revenue and recovered.expense==old_expense)
  end
end
local w,c,g=s.fleet[wood],s.fleet[coal],assert(Sim.rail_goods_status(s))
assert(reloaded and climbed and peak==80 and g.delivered==50 and paid_rail==1176 and g.fare==paid_rail)
assert(unloaded==g.delivered and receipt==2 and g.running_expense==575 and g.repeating)
assert(w.delivered==80 and c.delivered==60 and w.revenue>0 and c.revenue>0)
assert(s.stock_timber_industries[mill.industry].wood_received==w.delivered)
assert(s.sites[power.site].received.coal==c.delivered)
assert(s.sites[1].name=="Great Chinfingley Market" and s.sites[1].received.goods==unloaded)
local town_total=0
for _,site in ipairs(s.sites) do town_total=town_total+(site.received and site.received.goods or 0) end
assert(town_total==unloaded and not s.timber_transactions.open_station)
local company=s.companies[owner]
assert(company.paid_units==unloaded+w.delivered+c.delivered and company.paid_units==190)
assert(company.revenue==g.fare+w.revenue+c.revenue and company.revenue==3360)
assert(company.cash==100000+company.revenue-company.expense)
print("PASS generated mixed seed1751: 80t actual road Wood and 60t Coal, 50 Goods crates/$1176 in 2 physical rail trips after reload")
