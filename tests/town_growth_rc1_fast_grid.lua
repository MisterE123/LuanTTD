-- Compare a second ordinary, independently generated RC1 world.
local profiles={
  grid={fixture="rc1-fast-grid-town-year",width=256,depth=128,year=1950,seed=98217,
    towns=4,custom_towns=6,layout="grid3",growth_rate=3},
  better={fixture="rc1-better-slow-town-year",width=128,depth=256,year=1950,seed=11681,
    towns=2,layout="better",growth_rate=1},
  random={fixture="rc1-random-1975-town-year",width=256,depth=256,year=1975,seed=77294,
    towns=2,layout="random",growth_rate=4},
}
local profile_id=arg[1] or "grid"
local cfg=assert(profiles[profile_id])
local ref=dofile("tests/fixtures/"..cfg.fixture..".lua")
cfg.relief,cfg.sea,cfg.coast,cfg.rivers=1,0,16,2
cfg.trees,cfg.larger_towns,cfg.industries,cfg.variety,cfg.smooth=2,3,4,0,1
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
assert(profile.industry_stats.target>=#ref.industries and #profile.industries==#ref.industries)
for i,source in ipairs(ref.industries) do
  local placement=profile.industries[i]
  local record=s["stock_"..placement.chain.."_industries"][placement.industry]
  assert(placement.kind==industry_keys[source[1]] and placement.tile-1==source[2] and placement.near==source[3],
    "Industry placement mismatch at physical industry "..i)
  assert(record.selected_layout==source[4],"Stock industry layout drift at physical industry "..i)
end

s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
local mount,Codec=m("campaign_authority_runtime"),m("packed_campaign")
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
  local expected=ref.snapshots[tick]
  if not expected then return end
  local heights,types,houses,roads,spans=1,1,1,1,1
  local year=Sim.date(s)
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
  equal(tick,"map", {s.passenger_house_clock.head,rng[1],rng[2],heights,types,houses,roads,spans},expected[1])
  assert(#s.stock_town_growth.towns==#expected-1)
  for i,t in ipairs(s.stock_town_growth.towns) do
    local site=s.sites[i]
    local p,q=t.supplied.passenger,t.supplied.mail
    local layouts={original=0,better=1,grid2=2,grid3=3}
    local layout=type(t.layout)=="number" and t.layout or layouts[t.layout]
    equal(tick,"town "..i,{site.tile-1,site.nameparts,t.larger_town and 1 or 0,t.grow_counter,t.growth_rate,
      t.time_until_rebuild,layout,p.new_max,p.old_max,q.new_max,q.old_max},expected[i+1])
  end
  maps=maps+1
end
for day=1,365 do
  if day==32 or day==138 or day==267 then
    s=assert(Codec.decode(Codec.encode(s)))
    runtime=mount(Sim,mod,s,cap)
  end
  runtime.day(observe)
end
assert(ticks==27010 and maps==14 and digest==ref.rng)
print(("PASS RC1 %s region: %d industry placements, %d towns, original span portals, 14 map snapshots, 27,010 RNG ticks, three packed reopens")
  :format(profile_id,#ref.industries,#s.stock_town_growth.towns))
