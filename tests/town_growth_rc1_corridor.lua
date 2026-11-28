-- Normal generated RC1 town growth with a passenger bus and a wood truck
-- carrying cargo between the generated forest and sawmill. Uses the
-- actual worker entry points and committed construction, not save import.
local road_base=dofile("tests/fixtures/rc1-active-road-freight-town-year.lua")
local function run(ref,founding,air)
  local goods_circuit=ref.has_goods
  local f=dofile("tests/town_growth_rc1_industry_start.lua")
  local S,s,T=f.Sim,f.world,f.Terrain
  local mod=f.mod
  local forced_crash=air and arg[1]=="air-crash"
  local air_capture=air and (forced_crash and air.touchdown or air)
  local function m(n) return dofile(mod.."/"..n..".lua") end
  local owner="Stock comparison"
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  s.road_mail,s.road_junction_clearance=true,arg[1]~="stock-only" or not ref.shared
  local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},ferry={},air={},oil_tanker=true}
  if air then
    s.air_paid_service,s.air_owned_preview,s.air_fleet_preview,cap.air[216]=true,true,true,true
  end
  local Mount,Endpoint=m("campaign_authority_runtime"),m("campaign_authority_endpoint")
  local Codec,Rebuild=m("packed_campaign"),m("openttd/town_rebuild")
  local N=Mount(S,mod,s,cap)
  local A=Endpoint(S,N)
  local revision
  local function checked(r)
   assert(r.ok,r.why)
   revision=r.revision
   return r.value
  end
  local function action(kind,fields)
   fields=fields or {}
   fields.kind,fields.revision=kind,revision
   return checked(A.command(owner,fields))
  end
  local function terminal(kind,x,z,direction,through)
   local first=S.id(x+1,z+1)
   local request={tool="stock_terminal",first=first,kind=kind,direction=direction,through=through}
   local quote=checked(A.road_quote(owner,request))
   action("road_commit",{request=request,quote=quote})
   return first
  end
  local function service(name,cargo,home,src,dst)
   local p=assert(S.vehicle_offer(s,name))
   local id=action("road_buy",{engine=name,cargo=cargo,depot=home,cost=p.cost})
   for _,tile in ipairs({src,dst}) do action("road_order_add",{vehicle=id,station=assert(s.tiles[tile].station)}) end
   action("road_toggle",{vehicle=id})
   return id
  end
  action("company_open")
  assert(S.build(s,owner,"road",{S.id(46,45),S.id(47,45)}))
  local bd=terminal("depot",47,44,0)
  local bs=terminal("bus",41,44,0,true)
  local bt=terminal("bus",43,47,3,true)
  local bus=service("bus","passenger",bd,bs,bt)
  local road={}
  for i,id in ipairs(road_base.road) do road[i]=id+1 end
  assert(S.build(s,owner,"road",road))
  local wd=terminal("depot",47,57,1)
  local ws=terminal("truck",47,59,3,true)
  local wt=terminal("truck",23,87,0,true)
  local truck=service("wood_truck","wood",wd,ws,wt)
  local ids={bus,truck}
  local goods
  if goods_circuit then
    local gd=terminal("truck",49,89,0,true)
    local gg=ref.shared and wd or terminal("depot",21,87,2)
    goods=service("goods_truck","goods",gg,wt,gd)
    ids[#ids+1]=goods
    assert(s.fleet[goods].stock_pool_id==4)
    assert(s.passenger_rating_rng[1]==2870742148 and s.passenger_rating_rng[2]==505883883)
    assert(s.companies[owner].cash==(ref.shared and 66224 or 65609))
  else
    assert(s.passenger_rating_rng[1]==456539431 and s.passenger_rating_rng[2]==329337364)
    assert(s.companies[owner].cash==72275)
  end
  assert(s.fleet[bus].stock_pool_id==2 and s.fleet[truck].stock_pool_id==3)
  local digest,ticks,maps,poses=1,0,0,0
  local function fold(h,...)
    for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
    return h
  end
  local function same(tick,label,value,expected)
    assert(#value==#expected)
    for i,v in ipairs(expected) do
      assert(value[i]==v,("RC1 corridor tick %d %s field %d: got %s, expected %s"):format(tick,label,i,tostring(value[i]),v))
    end
  end
  local founded=false
  local function physical_town(id)
    local t=id and s.stock_town_growth.towns[id]
    return t and (t.stock_id or id-1) or -1
  end
  local function snapshot(tick)
    local expected=(founded and founding or ref).world[tick]
    if not expected then return end
    local hh,tt,house,road=1,1,1,1
    local year=S.date(s)
    for id,t in ipairs(s.tiles) do
      local x,z=S.xy(id)
      local typ=t.stock_void and 7 or t.stock_industry and 8 or t.stock_landmark and 10 or t.wood and 4
        or t.terrain=="water" and 6 or t.build=="road_station" and 5
        or (t.road_bridge_id or t.road_tunnel_id) and 9 or (t.build=="road" or t.build=="road_depot") and 2 or t.source_house and 3 or 0
      hh=fold(hh,T.corner(s.corner_grid,x,z));tt=fold(tt,typ)
      local r=t.source_house
      if r then house=fold(house,id-1,r.id,physical_town(r.town),r.completed and 1 or 0,r.stage,r.counter,Rebuild.age(r,year),r.random_bits) end
      if t.build=="road" then road=fold(road,id-1,t.road_bits,physical_town(t.road_town)) end
    end
    local summary={s.passenger_house_clock.head,hh,tt,house,road}
    for _,id in ipairs(ids) do summary[#summary+1]=s.fleet[id].delivered end
    same(tick,"map and delivered units",summary,expected[1])
    for i,id in ipairs(s.stock_town_growth.order) do
      local t,site=s.stock_town_growth.towns[id],s.sites[id]
      local p,q=t.supplied.passenger,t.supplied.mail
      local row={site.tile-1,site.nameparts,t.larger_town and 1 or 0,t.grow_counter,t.growth_rate,
        t.time_until_rebuild,p.new_max or 0,p.new_act or 0,p.old_max or 0,p.old_act or 0,q.new_max or 0,q.new_act or 0,q.old_max or 0,q.old_act or 0}
      if goods_circuit then
        local a=t.accepted and t.accepted.goods or {}
        row[#row+1],row[#row+2]=a.new_act or 0,a.old_act or 0
      end
      same(tick,"town "..i,row,expected[i+1])
    end
    maps=maps+1
  end
  local air_rng,air_ticks,air_poses,air_motion,air_snapshots=1,0,0,1,0
  local original_random=S.stock_random_u32
  local forced,crashed,retired
  if forced_crash then
    S.stock_random_u32=function(world)
      local random=original_random(world)
      local info=debug.getinfo(3,"S")
      if not forced and info and info.source:find("aircraft_landing_risk.lua",1,true) then
        forced=true
        return 0
      end
      return random
    end
  end
  local function buy_airport_leg()
    s.companies[owner].cash=80000000
    local function transport(req)
      local quote=checked(A.transport_quote(owner,req))
      return action("transport_commit",{token=quote.token})
    end
    local ids={}
    for i,pos in ipairs({{43,52},{47,93}}) do
      local tile=S.id(pos[1]+1,pos[2]+1)
      ids[i]=transport({mode="air",operation="build",tile=tile,layout="country",separate=true}).id
      assert(s.stock_small_airports[ids[i]].stock_station_id==i+4)
    end
    local unit=transport({mode="air",operation="buy",depot=ids[1],engine=216})
    local physical=assert(s.stock_owned_air_fleet[unit.id]).stock_pool_ids
    assert(physical[1]==5 and physical[2]==6 and #physical==2)
    action("transport_start",{mode="air",first=ids[1],second=ids[2],vehicle=unit.id})
  end
  local function snapshot_air(tick,expected)
    local houses=1
    local year=S.date(s)
    for id,t in ipairs(s.tiles) do
      local r=t.source_house
      if r then
        houses=fold(houses,id-1,r.id,physical_town(r.town),r.completed and 1 or 0,r.stage,r.counter,
          Rebuild.age(r,year),r.random_bits)
      end
    end
    same(tick,"air corridor housing tiles",{houses},expected[1])
    for i,id in ipairs(s.stock_town_growth.order) do
      local t,site=s.stock_town_growth.towns[id],s.sites[id]
      local p,m=t.supplied.passenger,t.supplied.mail
      local g=t.accepted and t.accepted.goods or {}
      same(tick,"air corridor town "..i,{physical_town(id),site.tile-1,t.population,t.num_houses,
        t.grow_counter,t.growth_rate,t.time_until_rebuild,p.new_max or 0,p.new_act or 0,p.old_max or 0,p.old_act or 0,
        m.new_max or 0,m.new_act or 0,m.old_max or 0,m.old_act or 0,g.new_act or 0,g.old_act or 0},expected[i+1])
    end
    air_snapshots=air_snapshots+1
  end
  local function observe_air(tick)
    if tick<air.first then return end
    if tick>air_capture.last then
      if forced_crash and forced then
        local p=N.air.run.current(s)
        if p and p.phase=="crashed" and not crashed then
          local e=assert(s.stock_air_accidents and s.stock_air_accidents[1])
          assert(e.tick==air_capture.last+1 and e.victims==2 and p.vehicle.stopped and p.vehicle.crashed)
          local found=false
          for _,effect in pairs(s.stock_effect_vehicles) do if effect.kind=="explosion_large" then found=true end end
          assert(found,"The runway crash never allocated the stock explosion effect")
          crashed=true
        elseif not p and crashed then
          assert(next(s.stock_owned_air_fleet)==nil and next(s.airport_owned_runs)==nil)
          assert(#s.stock_air_accidents==1)
          for _,field in pairs(s.stock_small_airports) do
            assert(math.floor(field.flags/2^8)%2==0 and math.floor(field.flags/2^29)%2==0)
          end
          for _,effect in pairs(s.stock_effect_vehicles) do assert(not effect.kind) end
          retired=true
        end
      end
      return
    end
    if tick==air.build then buy_airport_leg() end
    air_rng=fold(air_rng,tick,unpack(s.passenger_rating_rng))
    air_ticks=air_ticks+1
    if tick<=air.build then return end
    local p=assert(N.air.run.current(s))
    local v=p.vehicle
    local fields={v.x-16,v.z-16,v.y,v.speed,v.subspeed,v.progress,v.direction,v.state,v.pos,
      v.previous_pos,s.stock_small_airports[p.target].stock_station_id,v.loading and 1 or 0}
    air_motion=fold(air_motion,tick,unpack(fields))
    air_poses=air_poses+1
    if air.sample[tick] then same(tick,"aircraft pose",fields,air.sample[tick]) end
    if air.towns and air.towns[tick] then snapshot_air(tick,air.towns[tick]) end
    if air.payload[tick] then
      local aircraft
      for _,v in pairs(assert(s.stock_ship_commercial).service.vehicles) do
        if v.mode=="air" then aircraft=v;break end
      end
      local p,m=unpack(assert(aircraft).carrying_parts)
      same(tick,"cabin and mail hold",{p.units,m.units},air.payload[tick])
    end
    if tick==air.economy.tick then
      local unit=s.stock_owned_air_fleet[p.paid_clock]
      local h=unit.stock_fault
      same(tick,"aircraft economy day",{unit.stock_pool_ids[1],h.reliability,h.breakdown_chance,h.breakdown_ctr},
        {air.economy.id,air.economy.reliability,air.economy.chance,air.economy.counter})
    end
    if tick==air.new_mail.tick then same(tick,"new mail into airport",s.passenger_rating_rng,air.new_mail.rng) end
  end
  local function observe(tick)
    if air then observe_air(tick);return end
    digest=fold(digest,tick,unpack(s.passenger_rating_rng));ticks=ticks+1
    snapshot(tick)
    local expected=not founded and ref.poses[tick]
    if not expected then return end
    for n,id in ipairs(ids) do
      local v=s.fleet[id]
      local r=v.road_speed_state or v.road_stop_motion or {}
      local p=S.road_motion_frame(s,v) or v.road_stop_pose
      if p then
        same(tick,v.engine,{p[4]-1,p[1]-16,p[2]-16,p[3],r.speed or 0,r.subspeed or 0,r.progress or 0,v.units or 0},expected[n])
      else
        local concealed=S.road_hidden_depot(v) and v.road_motion_frames[r.index]
        local depot=v.depot or concealed and concealed[4]
        assert(depot and depot-1==expected[n][1] and expected[n][5]==0 and expected[n][8]==0,
          "Expected the stock road vehicle to be visible at "..tick)
      end
    end
    if ref.shared and tick==1455 then
      local v=s.fleet[goods]
      assert(v.load_state and v.road_implicit_leg and v.road_implicit_leg.index==1)
      assert(v.station~=v.road_implicit_leg.dest and v.orders[1].station==v.road_implicit_leg.dest)
    elseif ref.shared and tick==1456 then
      local v=s.fleet[goods]
      assert(not v.load_state and not v.road_implicit_leg and v.dest==v.orders[1].station)
    end
    poses=poses+1
  end
  for day=1,365 do
    if day==33 or day==102 or day==244 or air and day==163 then
      s=assert(Codec.decode(Codec.encode(s)))
      N=Mount(S,mod,s,cap)
      if air then A=Endpoint(S,N);revision=s.authority_revision or 0 end
    end
    N.day(observe)
    if air and (retired or not forced_crash and s.passenger_house_clock.counter>=air_capture.last) then break end
    if founding and day==181 then
      A=Endpoint(S,N)
      revision=s.authority_revision or 0
      s.companies[owner].cash=80000000
      action("town_founding_setting",{policy=2})
      local request={tile=S.id(69,64),size="medium",city=true,layout="random",name="Rivermark",nameparts=0xC0FFEE}
      local offer=checked(A.town_found_quote(owner,request))
      local city=action("town_found",{request=request,cost=offer.cost})
      assert(city.id==16 and city.population==714 and s.stock_town_growth.towns[city.id].stock_id==4)
      -- The three existing road services and the new company city
      -- continue in one shared stock tick stream.
      assert(s.passenger_house_clock.counter==14674)
      digest,ticks,maps,founded=1,0,0,true
      observe(14674)
    end
  end
  if air then
    same(air_capture.last,"air corridor",{air_ticks,air_rng,air_poses,air_motion},
      {air_capture.last-air.first+1,air_capture.rng,air_capture.last-air.build,air_capture.motion})
    if forced_crash then
      S.stock_random_u32=original_random
      assert(forced and crashed and retired)
      print("PASS paid-worker forced landing accident: one report, route stops, cargo cleared, runway and aircraft slots released")
    end
    if not forced_crash and air.towns then
      local n=0
      for _ in pairs(air.towns) do n=n+1 end
      assert(air_snapshots==n)
    end
    print(("PASS RC1 live aircraft corridor: %d world RNG ticks, %d plane poses and %d town snapshots %s"):format(
      air_ticks,air_poses,air_snapshots,forced_crash and "before forced accident" or "through the end of 1950"))
    return
  end
  if founding then
    assert(digest==founding.rng and ticks==13617 and maps==6)
    print("PASS RC1 founded city in an active bus, wood and Goods economy, 13,617 exact RNG ticks and six map/cargo snapshots")
    return
  end
  local passenger,wood,finished=unpack(ref.world[28290][1],6)
  local expected_poses=0
  for _ in pairs(ref.poses) do expected_poses=expected_poses+1 end
  same(28290,"year",{digest,ticks,maps,poses,s.fleet[bus].delivered,s.fleet[truck].delivered,goods and s.fleet[goods].delivered or 0},
    {ref.rng,27010,14,expected_poses,passenger,wood,finished or 0})
  if ref.shared then
    print(("PASS RC1 shared depot: 27,010 RNG ticks, 14 world snapshots, %d samples per vehicle, %d passengers, %d wood, %d Goods and three packed reopens"):format(expected_poses,passenger,wood,finished))
  elseif goods_circuit then
    print("PASS RC1 town goods circuit: 27,010 RNG ticks, 14 world snapshots, 23 samples per vehicle, 273 passengers, 80 wood, 35 Goods into town, three packed reopens")
  else
    print("PASS RC1 normal industry corridor: 27,010 RNG ticks, 14 map/town and 19 vehicle checkpoints, 283 passengers and 80 wood delivered, three packed reopens")
  end
end
if arg[1]=="air" or arg[1]=="air-crash" then
  run(dofile("tests/fixtures/rc1-active-town-goods-year.lua"),nil,dofile("tests/fixtures/rc1-active-airport-town-corridor.lua"))
  return
end
if arg[1]=="founded" then
  run(dofile("tests/fixtures/rc1-active-town-goods-year.lua"),dofile("tests/fixtures/rc1-active-manual-town.lua"))
  return
end
if arg[1]~="shared" and arg[1]~="stock-only" then
  run(road_base)
  run(dofile("tests/fixtures/rc1-active-town-goods-year.lua"))
end
run(dofile("tests/fixtures/rc1-active-shared-road-goods-year.lua"))
