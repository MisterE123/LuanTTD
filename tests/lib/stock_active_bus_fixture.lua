-- Reconstruct the controlled numeric fixture, never a general save import.
local m="mods/luanttd_core/"
local function load_module(name) return dofile(m..name..".lua") end
local Sim,T,G,H=load_module("sim"),load_module("openttd/terrain"),load_module("openttd/town_growth"),load_module("openttd/town_passengers")
local Art=load_module("stock_town_art")
local calendar=load_module("openttd/stock_engine_calendar")
local bind=load_module("campaign_simulation_bindings")(Sim,m:sub(1,-2))
local first_tick=1354
local function road_opts(stock)
  return {start_year=1950,breakdowns=1,service_interval=stock and stock.interval or 0,
          service_percent=stock ~= nil and stock.percent==1}
end

-- GetHouseNorthPart, town_cmd.cpp. Offsets follow the stock 1x2 and
-- four-tile record order, not the Luanti artwork's part indices.
local function root_of(id)
  local function is_layout(candidate,w,d)
    local spec=H.specs[candidate]
    return spec and spec[7]==w and spec[8]==d
  end
  if id>=3 then
    if is_layout(id-1,2,1) then return id-1,-1,0 end
    if is_layout(id-1,1,2) or is_layout(id-1,2,2) then return id-1,0,-1 end
    if is_layout(id-2,2,2) then return id-2,-1,0 end
    if is_layout(id-3,2,2) then return id-3,-1,-1 end
  end
  return id,0,0
end

local function initialize(ref,with_faults)
  local a,opening=ref,ref
  local height,kind,m1,m5,m3,m2={},{},{},{},{},{}
  for _,run in ipairs(a.runs) do
    for _=1,run[1] do
      local i=#height+1
      height[i],kind[i],m1[i],m5[i],m3[i],m2[i]=unpack(run,2)
    end
  end
  assert(#height==64^2)
  local s={version=1,seed=1751,day=0,tiles={},sites={},companies={},stations={},fleet={},next_station=1,next_vehicle=1,
    topology=0,subsidies={},news={},speed=1,stock_coastal_profile=true,
    stock_generated_profile={version=1,width=64,depth=64,map_height_limit=30,town_settings={growth_setting=a.settings[1]}}}
  Sim.W,Sim.H=64,64
  s.corner_grid=T.new(64,64,function(x,z)return height[(math.min(z,64)-1)*64+math.min(x,64)] end)
  local towns,order,pending_stops={},{},{}
  for id,c in ipairs({a.town}) do
    local x,z=c.xy%64+1,math.floor(c.xy/64)+1
    local town=G.new(id,x,z,{growing=c.flags%2==1,custom_growth=math.floor(c.flags/8)%2==1,
      grow_counter=c.grow_counter,growth_rate=c.growth_rate,time_until_rebuild=c.time_until_rebuild,
      fund_buildings_months=c.fund_buildings_months,road_build_months=c.road_build_months,
      layout=({[0]="original","better","grid2","grid3"})[c.layout]})
    town.house_counts={}
    for cargo,name in pairs({[0]="passenger",[2]="mail"}) do
      local raw=opening.supply[cargo]
      if raw then
        town.supplied[name]={new_max=raw[1],new_act=raw[2],old_max=raw[3],old_act=raw[4]}
      end
    end
    town.unique={church=math.floor(c.flags/2)%2==1,stadium=math.floor(c.flags/4)%2==1}
    towns[id],order[id]=town,id
    s.sites[id]={id=id,kind="town",name="RC1 comparison "..id,tile=c.xy+1,population=0,
      stock={},produced={},received={},service=0}
  end
  for id,typ in ipairs(kind) do
    local i,x,z=id-1,Sim.xy(id)
    local _,base=T.tile(s.corner_grid,x,z)
    local t={h=base,variant=(x+z)%4,terrain=base>0 and "hill" or "grass"}
    s.tiles[id]=t
    if typ==0 then
      t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=math.floor(m5[id]/4)%8,m5[id]%4,math.floor(m5[id]/32)%8
    elseif typ==2 then
      local road=opening.roads[i]
      if road then
        t.build,t.road_bits,t.road_town="road",road[1],road[2]+1
        if road[3]==0 then t.owner="RC1 comparison company" end
      else
        local d=assert(opening.stops[i]);assert(d[1]==2)
        t.build,t.road_bits,t.depot_dir,t.owner="road_depot",d[2],1,"RC1 comparison company"
      end
    elseif typ==5 then
      local d=assert(opening.stops[i]);assert(d[1]==1)
      t.build,t.road_bits="road",d[2]
      pending_stops[d[3]+1]=id
    elseif typ==3 then
      local h=opening.houses[i]
      local root,dx,dz=root_of(h[1])
      local r={id=h[1],x=x,z=z,town=h[6]+1,root=h[1]==root,root_x=x+dx,root_z=z+dz,completed=h[2]==1,
        stage=h[3],counter=h[4],age=h[5],age_epoch=1950}
      if not r.root then
        local primary=assert(opening.houses[Sim.id(r.root_x,r.root_z)-1])
        assert(primary[1]==root and primary[6]==h[6])
      end
      Art.stamp(r,{id=root,random_bits=m1[id]},assert(Art[root]),-2*dx-dz)
      t.house,t.source_house=true,r
      local town=assert(towns[r.town])
      if r.root then town.num_houses=town.num_houses+1 end
      town.house_counts[r.id]=(town.house_counts[r.id] or 0)+1
      if r.completed then town.population=town.population+H.specs[r.id][1] end
    elseif typ==4 then
      local ground=math.floor(m2[id]/64)%8
      t.wood={class=4,type=m3[id],ground=ground,density=math.floor(m2[id]/16)%4,
        count=math.floor(m5[id]/64)+1,growth=m5[id]%8,water_class=ground==3 and "sea" or nil}
      if math.floor(m1[id]/32)%4~=3 then t.terrain,t.coastal_water,t.water_class="water",true,"sea" end
    elseif typ==6 then
      t.terrain="water"
      local w=math.floor(m5[id]/16)
      t.coastal_water=w==1 or w==5 or nil
      t.stock_water_rocks=w>=4 or nil
      t.water_class=({[0]="sea","canal","river","sea"})[math.floor(m1[id]/32)%4]
    elseif typ==7 then t.terrain,t.stock_void="water",true
    elseif typ==10 then t.stock_object={kind="reference-landmark"}
    else error("Unexpected tile class in the controlled reference: "..typ) end
  end
  for id,town in ipairs(towns) do
    town.radii=G.radii(town.num_houses)
    s.sites[id].population=town.population
  end
  s.stock_town_growth={version=1,towns=towns,order=order}
  s.passenger_rating_rng={opening.clock[4],opening.clock[5]}
  s.stock_tree_tick_counter,s.stock_extra_tree_placement=a.clock[6],a.settings[2]
  s.passenger_house_clock=H.new_clock(6,6,opening.clock[3],opening.clock[1])
  if with_faults then bind.road(s,road_opts(ref.service_options))
  else Sim.mount_road_bus_market(s,calendar,1950) end
  if a.engine then
    -- Engine reliability phases depend on startup randomisation, a
    -- separate input from the saved vehicle's actual reliability.
    local model=s.stock_bus_market.models[116]
    for key,value in pairs(a.engine) do model[key]=value end
    model.expiry_age=model.phase1+model.phase2+model.phase3
  end
  s.day=opening.clock[2]-712223
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  for k,id in ipairs(pending_stops) do
    local ok,err=Sim.build(s,"RC1 comparison company","road_station",{id});assert(ok,err)
    assert(s.tiles[id].station==k)
  end
  bind.towns(s)
  bind.flood(s)
  return s,towns
end


local F={Sim=Sim,first_tick=first_tick}
function F.open(initial,with_faults)
  local s,towns=initialize(initial,with_faults)
  assert(s.day==(initial.clock[1]-first_tick)/74+1 and s.next_station==3 and towns[1].population>0)
  local owner="RC1 comparison company"
  local c=Sim.company(s,owner)
  c.cash=initial.cash+100000
  local depot=2383
  for index,actor in ipairs(initial.actors or {initial}) do
    local id,err=Sim.purchase(s,owner,"bus","passenger",nil,depot)
    assert(id and id==index,err)
    local v=s.fleet[id]
    v.stock_vehicle_random_bits=actor.day_state[12]
    v.stock_waiting_random_triggers=actor.day_state[13]
    assert(Sim.add_order(s,owner,id,1,"normal"))
    assert(Sim.add_order(s,owner,id,2,"normal"))
    assert(Sim.toggle(s,owner,id))
    local route,td,cost,frames,bays=Sim.path(s,{tile=depot,mode="road",owner=owner},s.stations[1],"road",owner,nil,v)
    assert(route and frames,"Stock initial depot route unavailable")
    local raw=actor.bus
    local hit
    for i,f in ipairs(frames) do
      if f[1]==raw[2]+16 and f[2]==raw[3]+16 and f[3]==raw[4] and f[4]==raw[1]+1 and f[6]==actor.motion[1] and f[15]==actor.motion[2] then
        hit=i;break
      end
    end
    assert(hit,"The current port does not contain the recorded stock frame on the computed route")
    v.route,v.dest,v.dest_index,v.depot,v.station,v.progress=route,1,1,nil,nil,1
    v.road_leg_td,v.road_route_cost,v.road_motion_frames,v.road_bay_branch=td,cost,frames,bays
    v.road_speed_state={index=hit,heading=raw[4],progress=raw[5],speed=raw[6],subspeed=raw[7],ticks=actor.bus_tick}
    if with_faults then
      local a=assert(actor.day_state)
      v.stock_bus.ticks,v.stock_bus.day=a[2],a[3]
      v.cargo_age_counter=a[4]
      local f=assert(v.road_fault)
      f.reliability,f.reliability_spd_dec,f.age,f.max_age=a[5],a[6],a[7],a[8]
      f.date_of_last_service,f.date_of_last_service_newgrf=a[9],a[10]
      f.tick_counter,f.breakdown_chance=actor.bus_tick,a[11]
    end
  end
  -- Restore both words after the already-recorded build commands, not
  -- between replaying two actor purchases on the controlled board.
  s.passenger_rating_rng={initial.clock[4],initial.clock[5]}
  for i,g in pairs(initial.goods) do
    local st=s.stations[i+1]
    st.time_since_load,st.time_since_unload,st.passenger_rating_phase=g[1],g[2],g[9]
    st.passenger_fraction=g[7]
    st.passenger_rating_state={rating=g[3],last_age=g[4],last_speed=g[5],time_since_pickup=g[6],
      amount_fract=g[7],has_rating=math.floor(g[8]/2)%2==1,max_waiting_cargo=0}
  end
  c.cash,c.loan=initial.cash,initial.loan
  local q=initial.quarter
  if q then c.stock_quarter={income=q[1],expenses=q[2],delivered={passenger=q[3]}} end
  if with_faults then c.stock_money_fraction=initial.day_state[1] end
  return s,towns,s.fleet[1],owner
end
function F.reopen(s,with_faults,service_options)
  local Codec=load_module("packed_campaign")
  local next=Codec.decode(Codec.encode(s))
  if with_faults then bind.road(next,road_opts(service_options))
  else Sim.mount_road_bus_market(next,calendar,1950) end
  bind.towns(next)
  bind.flood(next)
  return next
end
return F
