-- Compare a second ordinary, independently generated RC1 world.
local profiles={
  wide={fixture="rc1-wide-varied-town-year",width=512,depth=256,year=1960,seed=10873,
    towns=4,custom_towns=42,layout="random",growth_rate=3,larger_towns=3,initial_city_size=4,coast=10,rivers=3,variety=2},
  crowded={fixture="rc1-crowded-grid2-years",width=256,depth=256,year=1993,seed=9354,
    towns=4,custom_towns=14,layout="grid2",growth_rate=4,larger_towns=1,initial_city_size=8,coast=0},
  grid={fixture="rc1-fast-grid-town-year",width=256,depth=128,year=1950,seed=98217,
    towns=4,custom_towns=6,layout="grid3",growth_rate=3},
  quadratic={fixture="rc1-quadratic-town-year",width=256,depth=128,year=1950,seed=98217,
    towns=4,custom_towns=6,layout="grid3",growth_rate=3,town_cargo=0},
  houses={fixture="rc1-houses-only-town-year",width=256,depth=128,year=1950,seed=98217,
    towns=4,custom_towns=6,layout="grid3",growth_rate=3,town_roads=0},
  better={fixture="rc1-better-slow-town-year",width=128,depth=256,year=1950,seed=11681,
    towns=2,layout="better",growth_rate=1},
  midyear={fixture="rc1-midyear-town-setting",width=128,depth=128,year=1950,seed=1751,
    towns=4,custom_towns=4,layout="original",growth_rate=2},
  hills={fixture="rc1-hills-town-year",width=256,depth=256,year=1950,seed=1,
    towns=3,layout="original",growth_rate=2,relief=3,coast=0,rivers=3,larger_towns=4},
  random={fixture="rc1-random-1975-town-year",width=256,depth=256,year=1975,seed=77294,
    towns=2,layout="random",growth_rate=4},
}
local profile_id=arg[1] or "grid"
local cfg=assert(profiles[profile_id=="hills-long" and "hills" or profile_id])
local ref=dofile("tests/fixtures/"..(profile_id=="hills-long" and "rc1-hills-town-three-years" or cfg.fixture)..".lua")
cfg.relief,cfg.sea,cfg.coast,cfg.rivers=cfg.relief or 1,0,cfg.coast or 16,cfg.rivers or 2
cfg.trees,cfg.larger_towns,cfg.industries,cfg.variety,cfg.smooth=2,cfg.larger_towns or 3,4,cfg.variety or 0,1
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim,Terrain,Rebuild=m("sim"),m("openttd/terrain"),m("openttd/town_rebuild")
local core={settings={get=function() return nil end},get_dir_list=function(path)
  local out={}
  local p=assert(io.popen("ls -1 "..path))
  for line in p:lines() do out[#out+1]=line end
  p:close()
  return out
end}
local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run(cfg)
local function equal(tick,label,found,expected)
  assert(#found==#expected)
  for i,need in ipairs(expected) do
    assert(found[i]==need,("fast grid tick %s %s field %d: got %s, expected %s"):format(tick,label,i,tostring(found[i]),need))
  end
end
local industry_keys={[0]="coal_mine","power_station","sawmill","forest","oil_refinery",
  [6]="factory",[8]="steel_mill",[9]="farm",[11]="oil_well",[18]="iron_mine"}
local profile=s.stock_generated_profile
if ref.houses_only then
  assert(profile.town_settings.municipal.allow_town_roads==false and s.stock_road_town_policy.allow_town_roads==false)
  assert(s.has_town_roads,"Disabling live road expansion must not block starting streets")
end
assert(profile.industry_stats.target>=#ref.industries and #profile.industries==#ref.industries)
for i,source in ipairs(ref.industries) do
  local placement=profile.industries[i]
  local record=s["stock_"..placement.chain.."_industries"][placement.industry]
  assert(placement.kind==industry_keys[source[1]] and placement.tile-1==source[2] and placement.near==source[3],
    "Industry placement mismatch at physical industry "..i)
  assert(record.selected_layout==source[4],"Stock industry layout drift at physical industry "..i)
end

s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
local mount,Codec,endpoint=m("campaign_authority_runtime"),m("packed_campaign"),m("campaign_authority_endpoint")
local cap={road={start_year=cfg.year,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
local runtime=mount(Sim,mod,s,cap)
local function fold(h,...)
  for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
  return h
end
local digest,ticks,maps=1,0,0
local function observe(tick)
  local rng=s.passenger_rating_rng
  digest=fold(digest,tick,rng[1],rng[2]);ticks=ticks+1
  if ref.midyear and (tick==4388 or tick==10974) then
    local before={}
    for i,t in ipairs(s.stock_town_growth.towns) do before[i]={t.grow_counter,t.growth_rate,t.growing} end
    local authority=endpoint(Sim,runtime)
    local rate=tick==4388 and 0 or 4
    local revision=s.authority_revision or 0
    local request={kind="town_growth_setting",rate=rate,revision=revision}
    local unauthorized=authority.command("Visitor",request)
    assert(not unauthorized.ok and unauthorized.revision==revision)
    request.admin=true
    local result=authority.command("Server Admin",request)
    assert(result.ok and result.revision==revision+1)
    assert(s.stock_generated_profile.town_settings.growth_setting==rate)
    assert(not authority.command("Server Admin",request).ok,"A stale settings submission must fail")
    for i,t in ipairs(s.stock_town_growth.towns) do
      local b=before[i]
      assert(b[1]==t.grow_counter and b[2]==t.growth_rate and b[3]==t.growing,
        "Stock settings changes must not force a premature growth update")
    end
  end
  if profile_id=="hills" and tick==1281 then
    local edge,rock=s.tiles[40226+1],s.tiles[40225+1]
    assert(edge.build=="road" and edge.road_bits==10 and rock.stock_water_rocks and not rock.coastal_water)
  elseif profile_id=="hills" and tick==10738 then
    -- The exact live LevelTownLand attempt at the end of a steep avenue.
    assert(rng[1]==2321292048 and rng[2]==3535918853)
    local x,z=Sim.xy(47086+1)
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    assert(slope==0 and base==7)
  end
  if ref.wide and tick==1281 then
    local replaced=s.tiles[95901+1].source_house
    assert(replaced and replaced.id==13 and replaced.town==6 and replaced.random_bits==70)
    local approach,other=s.tiles[84229+1],s.tiles[84228+1]
    assert(approach.road_town==36 and approach.road_bits==11 and other.road_town==27 and other.road_bits==10)
  end
  local expected=ref.snapshots[tick]
  if not expected then return end
  local heights,types,houses,roads,spans=1,1,1,1,1
  local last=ref.year_end_house
  local year=ref.snapshot_years and ref.snapshot_years[tick] or Sim.date(s)
  if last and tick==last.tick then
    local house=assert(s.tiles[last.tile+1].source_house)
    assert(house.id==last.id and house.random_bits==last.random_bits and house.built_tick==last.tick,
      "RC1 HouseID 25 must still be eligible on December 31, 1952")
  end
  for id,t in ipairs(s.tiles) do
    local x,z=Sim.xy(id)
    local bridge,tunnel=t.road_bridge_id,t.road_tunnel_id
    local class=t.stock_void and 7 or t.stock_industry and 8 or t.stock_landmark and 10 or t.wood and 4
      or (bridge or tunnel) and 9 or t.terrain=="water" and 6 or t.build=="road" and 2 or t.source_house and 3 or 0
    heights=fold(heights,Terrain.corner(s.corner_grid,x,z));types=fold(types,class)
    local h=t.source_house
    if h then
      houses=fold(houses,id-1,h.id,h.town-1,h.completed and 1 or 0,h.stage,h.counter,Rebuild.age(h,year),h.random_bits)
    end
    if class==2 then roads=fold(roads,id-1,t.road_bits,t.road_town and t.road_town-1 or -1) end
    if class==9 then
      local span=bridge and s.stock_road_bridges[bridge] or s.stock_road_tunnels[tunnel]
      local u,v=Sim.xy(id==span.start and span["end"] or span.start)
      local dir=u>x and 2 or u<x and 0 or v>z and 1 or 3
      spans=fold(spans,id-1,bridge and 1 or 0,dir)
    end
  end
  if ref.houses_only then
    local initial=ref.snapshots[1281][1]
    assert(roads==initial[7] and spans==initial[8],"Municipal roads or spans changed while expansion was disabled")
  end
  equal(tick,"map", {s.passenger_house_clock.head,rng[1],rng[2],heights,types,houses,roads,spans},expected[1])
  assert(#s.stock_town_growth.towns==#expected-1)
  for i,t in ipairs(s.stock_town_growth.towns) do
    local site=s.sites[i]
    local p,q=t.supplied.passenger,t.supplied.mail
    local layouts={original=0,better=1,grid2=2,grid3=3}
    local layout=type(t.layout)=="number" and t.layout or layouts[t.layout]
    equal(tick,"town "..i,{site.tile-1,site.nameparts,t.larger_town and 1 or 0,t.grow_counter,t.growth_rate,
      t.time_until_rebuild,layout,p.new_max or 0,p.old_max or 0,q.new_max or 0,q.old_max or 0},expected[i+1])
  end
  maps=maps+1
end
local reopens=0
for day=1,ref.days or 365 do
  if day==32 or day==138 or day==267 or ref.restart_day and day==ref.restart_day+1 then
    reopens=reopens+1
    s=assert(Codec.decode(Codec.encode(s)))
    runtime=mount(Sim,mod,s,cap)
  end
  runtime.day(observe)
end
assert(ticks==(ref.days or 365)*74 and maps==(ref.snapshot_count or ref.midyear and 20 or ref.days and 18 or 14) and digest==ref.rng)
print(("PASS RC1 %s region: %d industry placements, %d towns, original span portals, %d map snapshots, %d RNG ticks, %d packed reopens")
  :format(profile_id,#ref.industries,#s.stock_town_growth.towns,maps,ticks,reopens))


if ref.quadratic then
  local copy=assert(Codec.decode(Codec.encode(s)))
  local authority=endpoint(Sim,runtime)
  local revision=s.authority_revision or 0
  local before=s.passenger_rating_rng
  local state={before[1],before[2],s.day,s.passenger_house_clock.counter}
  local cargo={kind="town_cargo_setting",mode=1,revision=revision}
  assert(not authority.command("Visitor",cargo).ok)
  cargo.admin=true
  assert(authority.command("Server Admin",cargo).ok)
  assert(not authority.command("Server Admin",cargo).ok)
  equal(state[4],"setting without simulation",{before[1],before[2],s.day,s.passenger_house_clock.counter},state)
  s=assert(Codec.decode(Codec.encode(s)))
  assert(s.stock_generated_profile.town_settings.cargo_mode==1)
  mount(Sim,mod,s,cap).day()
  mount(Sim,mod,copy,cap).day()
  local a,b=s.passenger_rating_rng,copy.passenger_rating_rng
  assert(a[1]~=b[1] or a[2]~=b[2],"Production stayed on the old algorithm after reopening")
  print("PASS switching town cargo mode is authorized, persisted and applied only to future visits")
end
