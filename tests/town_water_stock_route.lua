-- Stock road worker service on a generated Tropic board. Only the two
-- native Water industry records are installed; this is not a full
-- climate campaign, availability UI or renderer test.
local io_path,load_checkpoint,save_checkpoint=...
local p=io_path or "mods/luanttd_core/"
local function m(n)return dofile(p..n..".lua") end
local function o(n)return m("openttd/"..n) end
local S,T,Sl=m("sim"),o("terrain"),o("slope")
local TG=o("terragenesis")(Sl)
local Climate,Tree=o("town_climate_landscape_rc1"),o("tree_climate_rc1")
local River=o("river_worldgen")(Sl,o("river_landscape_rc1"),o("river_yapf_rc1"),
  o("tree_lifecycle_temperate")(o("tree_worldgen"),Tree))
local Raster=o("stock_climate_raster_rc1")(Climate,River,Sl)
local Clear,Calendar=o("terragenesis_clear_rc1"),o("stock_engine_calendar")
local G,Roots=o("town_growth"),o("town_growth_houses_all_rc1")
local B=o("town_growth_build")(G,o("town_growth_houses"),Roots)
local World=o("town_worldgen")(G,B)
local Campaign=m("generated_campaign")
local Names=o("stock_town_name")
local shapes={}
for _,r in ipairs(Roots) do shapes[r[1]]={width=r[6]*r[7]>1 and r[6] or nil,depth=r[7],unique=r[8]} end
local growth=m("town_growth_runtime")(S,T,G,B,o("town_passengers"),shapes)
local Codec=m("packed_campaign")
local Map={next_random=TG.next_random,describe=Clear.describe}
function Map.generate(opts)
  local raw=TG.generate(opts)
  local raster=Raster.prepare(raw,{desert_coverage=75,snow_coverage=75})
  local river,stats=River.generate(raster,TG.next_random,{terrain=T,rc1=true,original=false,
    terrain_type=1,tree_placer=2,tree_climate=Tree,amount_of_rivers=2,climate_rules=Climate})
  return Clear.generate(river,TG.next_random),stats
end
local seed=49832
local company="Water service"
local town_id=34 -- Original TownID 33.
local function resume(s)
  S.W,S.H=256,256
  S.mount_road_bus_market(s,Calendar,1985,false,false)
  assert(S.mount_tropic_freight(s))
  S.mount_stock_town_growth(s,growth,true)
  S.mount_coastal_flood(s)
  return s
end
local function start()
  local s=Campaign.landscape(S,T,Map,{width=256,depth=256,seed=seed,terrain_type=1,
    quantity_sea_lakes=0,tgen_smoothness=1,water_borders=0,variety=0,freeform_edges=true,
    landscape="tropic",rng_state=TG.startup_rng(seed)})
  s.stock_world_animations=o("world_animation_rc1").new()
  s.stock_pool_authority=true
  s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
  s.road_junction_clearance,s.road_bay_build=true,true
  S.mount_road_bus_market(s,Calendar,1985,false,false)
  assert(not S.vehicle_available(s,"water_uhl"))
  S.mount_coastal_flood(s)
  assert(Campaign.towns(S,T,s,Map,World,Names,G,B,{layout="original",growth_setting=2,
    cargo_mode=1,difficulty=3,custom_count=1,larger_towns=4,separation=20,initial_city_size=2,year=1985},shapes))
  S.mount_stock_town_growth(s,growth,true)
  local firm={}
  s.stock_climate_industries=firm
  local F=assert(S.mount_tropic_freight(s))
  local supply=F.new("water_supply",15,25,91,{original=true,completed=true,counter=1})
  local tower=F.new("water_tower",49,26,106,{original=true,completed=true,counter=1})
  supply.produced[1].rate=17
  firm[15],firm[49]=supply,tower
  local function id(x,z)return S.id(x+1,z+1) end
  -- These records match the native footprint. Only the tower replaces
  -- its existing house; all local road terrain comes from TerraGenesis.
  for _,f in pairs(firm) do
    for _,q in ipairs(f.tiles) do
      local cell=s.tiles[id(q.x,q.z)]
      assert(cell.terrain~="water" and not cell.build)
      cell.house,cell.source_house=nil,nil
      cell.stock_industry={id=f.id,gfx=q.gfx,chain="climate"}
    end
  end
  local c=S.company(s,company);c.cash=80000000
  local before=s.stock_town_growth.towns[town_id]
  assert(before and before.goal[4]==G.DESERT and before.goal[5]==G.DESERT)
  local a,b,dep=id(27,92),id(27,105),id(27,90)
  local function apply(q,why)
    assert(q,why)
    assert(S.apply_road_construction(s,company,q))
    return q.cost
  end
  local road=apply(S.autoroad_plan(s,company,id(27,91),id(27,106),1,false,true))
  local depot=apply(S.stock_road_terminal_plan(s,company,dep,{kind="depot",dir=1}))
  local function stop(tile)
    local cost=apply(S.stock_road_stop_area_plan(s,company,tile,tile,{kind="truck",dir=1,through=true,adjacent=true}))
    local st=assert(s.stations[s.tiles[tile].station])
    assert(st.town==town_id or st.site==town_id,("Wrong town for stop %d: %s %s"):format(tile,tostring(st.town),tostring(st.site)))
    return st,cost
  end
  local pickup,pick_cost=stop(a)
  local destination,dest_cost=stop(b)
  assert(S.vehicle_available(s,"water_uhl"))
  local nr=assert(S.purchase(s,company,"water_uhl","water",nil,dep))
  assert(S.add_order(s,company,nr,pickup.id) and S.add_order(s,company,nr,destination.id))
  assert(S.toggle(s,company,nr))
  return s,{vehicle=nr,road=road,depot=depot,pickup=pick_cost,destination=dest_cost}
end
local saved=load_checkpoint and load_checkpoint()
local s,q
if saved then
  s=resume(assert(Codec.decode(saved)))
  q=assert(s.qa_water_trip)
  assert(q.day>0 and s.fleet[q.vehicle].units>0 and s.fleet[q.vehicle].route)
else s,q=start() end
local nr=q.vehicle
local seen,opened,dump=not not saved,not not saved,{}
for day=(q.day or 0)+1,95 do
  local v=s.fleet[nr]
  S.daily(s)
  if v.route and not v.depot then seen=true end
  local t=s.stock_town_growth.towns[town_id]
  local rec=t.received[4]
  if not opened and v.units>0 and v.route then
    local old=v.units
    q.day=day
    s.qa_water_trip=q
    local encoded=Codec.encode(s)
    if save_checkpoint then
      save_checkpoint(encoded,old)
      return
    end
    s=resume(assert(Codec.decode(encoded)))
    assert(s.fleet[nr].units==old)
    opened=true
  end
  if v.delivered>=21 then
    assert(seen and opened and v.delivered==21 and v.revenue>0 and v.expense>0 and s.companies[company].paid_units==v.delivered)
    assert((rec.new_act or 0)+(rec.old_act or 0)>0 and not t.growing and not t.accepted.water)
    assert(s.stock_climate_industries[49].received.water==v.delivered)
    print(("PASS Water truck workers and packed reopen: %d litres, $%d fares, day %d; road/depot/stops %d/%d/%d/%d"):format(
      v.delivered,v.revenue,day,q.road,q.depot,q.pickup,q.destination))
    return
  end
  if day<=4 or day%20==0 then dump[#dump+1]=table.concat({day,v.status,v.units,v.delivered,S.position(s,v) or 0}," ") end
end
error(table.concat(dump,"\n"))
