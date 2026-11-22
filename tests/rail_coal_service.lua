-- Real campaign footprint and one landscape loop; no rail runner is
-- mounted here. Clock/work order matches actual native callbacks.
local root="mods/bayline/"
local function mod(n) return dofile(root..n..".lua") end
local Sim,Terrain,Packets,Income=mod("sim"),mod("openttd/terrain"),mod("openttd/passengers"),mod("openttd/income")
local Rating=mod("openttd/station_rating")
local Catchment=mod("openttd/station_catchment")(Packets,Rating)
local Station=mod("station_rating_runtime")(Sim,Rating,Packets)
local Coal=mod("openttd/coal_industry")(Packets,Rating,Catchment,Income)
local Roster=mod("openttd/rail_roster")
local Timing,Loading=mod("openttd/loading_timing"),mod("road_loading_runtime")
local Rail=mod("rail_coal_service")(Sim,Coal,Catchment,Roster,Packets,Rating,Station,Income,Loading,Timing)
local Road=mod("road_coal_service")(Sim,Coal,Catchment,Packets,Income,Rating,Station)
local root_world=mod("coal_industry_world")(Sim,Terrain,Coal)
local function copy(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
local s,id=Sim.new(1751),Sim.id
mod("town_layout")(Sim,s)
s.corner_grid=mod("terrain_preview")(Sim,Terrain,s)
assert(root_world.seed(s,id(30,11),id(40,12)))
local company,road_company="Rail coal","Road coal"
Sim.company(s,company);Sim.company(s,road_company)
local station_tile=id(31,14)
s.stations[1]={id=1,tile=station_tile,owner=road_company,mode="road",stop_type="truck",stock={}}
local function platform(local_id,tiles)
  s.stock_rail_stations=s.stock_rail_stations or {}
  s.stock_rail_stations[local_id]={id=local_id,owner=company,axis=0,tiles=tiles}
  for _,i in ipairs(tiles) do
    s.tiles[i]={build="stock_rail",rail_tracks=1,rail_station_id=local_id,rail_station_axis=0,owner=company}
  end
end
local origin_tiles={id(30,15),id(31,15),id(32,15)}
local sink_tiles={id(39,16),id(40,16),id(41,16)}
platform(1,origin_tiles)
platform(2,sink_tiles)
local carrier_from,carrier_to=origin_tiles[3],sink_tiles[1]
local head_from,head_to=origin_tiles[2],sink_tiles[2]
local archive=Rail.new()
local events,received={},0
local rail,road,industries,mine,power,location
local function rebind()
  industries=s.stock_coal_industries
  mine,power=industries[1],industries[2]
  rail=Rail.bind(s,archive,{emit=function(e) events[#events+1]=e end,
    received=function(_,p,n) assert(p.id==power.id);received=received+n end})
  road=Road.bind(s,{separate_queue=true})
  assert(rail.extend(road.stations,road.coverage))
  assert(#road.stations==3 and road.stations[1].id==1 and road.stations[2].id==0x4001)
  location={}
  for _,i in ipairs(industries) do for _,tile in ipairs(i.tiles) do location[tile.z*64+tile.x]={i,tile} end end
end
rebind()
-- Matching stock owner-best allocation, one fresh 16t event each run.
-- The rail copy shares/doesn't share the eligible truck's company:
-- equal ratings are not equal allocation for three eligible stations.
local function fair(views,observe_all)
  local covers={}
  for _,st in ipairs(views) do
    st.stock={coal={}}
    local g=Coal.goods(st)
    g.rating=127
    if observe_all or st.mode=="road" then
      Coal.observe_loading(st,{mode=st.mode,build_year=Sim.date(s),max_speed=96},30,Sim.date(s))
    end
    covers[st.id]=Catchment.build(st,Sim.W,Sim.H)
  end
  local total=Rail.distribute(mine,16,views,covers,{})
  local served={}
  for i,st in ipairs(views) do served[i]=Coal.waiting(st) end
  assert(total==8 and (served[1] or 0)+(served[2] or 0)+(served[3] or 0)==8)
  return table.concat(served,",")
end
local function probe(id_,mode_,player)
  return {id=id_,mode=mode_,owner=player,tile=station_tile,
    tiles={{x=30,y=13,kind=mode_=="road" and "truck" or "rail"}}}
end
assert(fair({probe(1,"road","owner")},true)=="8")
assert(fair({probe(1,"road","owner"),probe(0x4001,"rail","owner")},false)=="8,0")
assert(fair({probe(1,"road","owner"),probe(0x4001,"rail","owner")},true)=="4,4")
assert(fair({probe(1,"road","owner"),probe(0x4001,"rail","owner"),probe(0x4002,"rail","other")},true)=="2,2,4")
assert(Rail.wagon.stock_id==29 and Rail.wagon.capacity==30 and Rail.wagon.length==8 and Rail.wagon.load_amount==5)
assert(not rail.report(1).accepts and rail.report(1).sources[1]==mine.id and not rail.report(2).sources[1])
assert(rail.report(2).accepts and rail.report(2).near[1].ind.id==power.id)
assert(Rail.platform(s,s.stock_rail_stations[1],head_from)==3)
assert(not Rail.platform(s,s.stock_rail_stations[1],station_tile))
assert(not rail.vehicle({id=9,owner=company,speed=64,built=Sim.date(s),length=16,stock_id=27}))
assert(rail.vehicle({id=9,owner=company,speed=64,built=Sim.date(s),length=16,stock_id=29}))
assert(not rail.vehicle({id=10,owner=company,speed=64,built=Sim.date(s),length=16,stock_id=29}))
assert(select(2,rail.arrive(9,1,1,0,station_tile,carrier_from,{full=true}))=="FRONT_NOT_ON_PLATFORM")
local l=assert(rail.arrive(9,1,1,0,head_from,carrier_from,{full=true}))
assert(l.capacity==30 and l.slice==5 and l.platform_tiles==3 and l.ticks==1)
assert(rail.arrive(9,1,1,0,head_from,carrier_from,{full=true})==l)
assert(not rail.leave(9,1,0))
-- A road truck can compete on the same exact stock producer. Its
-- rating/statistics and queue belong to the ordinary saved road stop.
local road_st=s.stations[1]
Coal.observe_loading(road_st,{mode="road",max_speed=96,build_year=Sim.date(s)},20,Sim.date(s))
assert(Coal.goods(road_st).last_speed==48)
local clock={cursor=1}
local shipped,first_depart=0,nil
local saved_loading,saved_unload=false,false
local last_board=0
local reloads=0
local function checkpoint()
  s=copy(s);archive=copy(archive);clock=copy(clock);reloads=reloads+1;rebind()
end
for tick=1,4800 do
  s.day=1+math.floor((tick-1)/74)
  clock.tick=tick
  -- The real source tile-loop consumes at most one lot; station
  -- competition is a single fixed-point allocation for both modes.
  Coal.landscape_tick(clock,6,6,function(key)
    local t=location[key]
    if t then
      local amount,moved=Coal.tile_loop(t[1],t[2],{},function(ind,n)
        return Rail.distribute(ind,n,road.stations,road.coverage,{day=s.day})
      end)
      assert(moved<=amount)
      shipped=shipped+moved
    end
  end)
  local v=archive.vehicles[9]
  if first_depart and tick==first_depart+185*9+17 then
    -- Plant nearly full: first 5t unloading round can accept only 2.
    power.accepted.waiting=65533
    assert(rail.arrive(9,2,2,tick-1,head_to,carrier_to,{no_load=true}))
  end
  local previous_events=#events
  local ready=assert(rail.loading_tick(tick))
  assert(#rail.loading_tick(tick)==0,"Duplicate station tick")
  if #ready>0 then
    if not first_depart then
      assert(v.units==30 and v.load_state.reserved_units==0)
      for _,p in ipairs(v.batches) do assert(p.origin_tile==carrier_from) end
      first_depart=tick
      assert(rail.leave(9,1,tick))
      assert(not rail.leave(9,1,tick))
    else
      assert(v.delivered==27 and received==27 and v.units==0 and v.revenue>0)
      assert(rail.leave(9,2,tick))
      assert(not rail.leave(9,2,tick))
      assert(rail.after_motion(tick))
      break
    end
  end
  assert(rail.after_motion(tick) and not rail.after_motion(tick))
  -- Road OnTick_Station shares the ordering, and industry output fills
  -- waiting after the same vehicle tick, not a second landscape pass.
  if tick%185==0 then road.step_rating(s.stations[1]) end
  road.after_vehicle_tick(tick)
  for i=previous_events+1,#events do
    local e=events[i]
    if e.kind=="board" then
      assert(e.units<=5 and (last_board==0 or e.tick-last_board>=40))
      last_board=e.tick
    end
  end
  if not saved_loading and not first_depart and v.units>0 and v.load_state then
    assert(v.load_state.station==0x4001)
    saved_loading=true;checkpoint()
  elseif not saved_unload and first_depart and received>0 and v.load_state then
    assert(power.accepted.waiting==0 and v.load_state.payment and v.delivered==0)
    saved_unload=true;checkpoint()
  end
end
local v=archive.vehicles[9]
assert(first_depart and saved_loading and saved_unload and reloads==2 and not v.load_state)
assert(v.delivered==27 and received==27 and power.was_cargo_delivered and power.accepted.waiting==0)
assert(Coal.goods(archive.stations[0x4001]).last_speed==64)
local road_units=0
for _,p in ipairs(s.stations[1].stock_coal_packets) do
  assert(p.origin_station==1 and p.origin_tile==nil)
  road_units=road_units+p.units
end
assert(road_units>0 and shipped>=road_units+30 and mine.produced.current.transported==shipped)
local fare,board,delivered,bill=0,0,0,0
for _,e in ipairs(events) do
  if e.kind=="board" then board=board+e.units
  elseif e.kind=="deliver" then
    assert(e.station_local==2 and e.tile==carrier_to and e.source_industry==mine.id and e.destination_industry==power.id)
    assert(e.distance==8 and e.age>Coal.cargo.days1)
    delivered=delivered+e.units
    fare=fare+Income.regular(e.units,e.distance,e.age,Coal.cargo.payment,Coal.cargo.days1,Coal.cargo.days2)
  elseif e.kind=="fare" then bill=bill+e.amount end
end
assert(board==30 and delivered==27 and fare==bill and fare==v.revenue)
assert(s.companies[company].paid_units==27 and s.companies[company].revenue==fare)
assert(s.companies[road_company].paid_units==0 and not Coal.goods(archive.stations[0x4001]).ever_accepted)
print(("stock rail #29 and truck share one mine: 30t boarded, 27t accepted/$%d, %dt in competing truck queue; two reloads"):format(fare,road_units))
