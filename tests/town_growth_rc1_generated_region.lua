-- Native OpenTTD 16.0-RC1 (07b339c) ordinary new game, no imported board.
-- Seed 1751, four temperate towns, improved trees, no rivers, industry,
-- companies, disasters or subsidies. Captured after CallLandscapeTick.
local expected={
  {{1281,12628,2288753431,474250251,430721903,507747446,1276596126,1217972741},{9706,4029305082,0,0,11269,10,102,118,43,59},{3649,1081850249,1,0,5669,10,101,138,48,69},{2417,2868745040,0,2,11269,10,101,135,46,67},{14000,3108163635,0,2,11269,10,32,49,17,24}},
  {{1354,14908,3284436849,1961320314,430721903,483030399,1613741127,1217972741},{9706,4029305082,0,0,11269,10,108,118,47,59},{3649,1081850249,1,0,5669,10,106,138,55,69},{2417,2868745040,0,2,11269,10,104,135,47,67},{14000,3108163635,0,2,11269,10,38,49,18,24}},
  {{3574,5691,3750010881,1307619702,430721903,679161192,194086098,1217972741},{9706,4029305082,0,0,11269,10,0,249,0,103},{3649,1081850249,1,0,5669,10,0,265,0,157},{2417,2868745040,0,2,11269,10,0,266,0,113},{14000,3108163635,0,2,11269,10,0,98,0,51}},
  {{5646,3690,558668691,2182314123,430721903,1875005531,212696391,1217972741},{9706,4029305082,0,0,11269,10,0,118,0,57},{3649,1081850249,1,0,5669,10,0,152,0,81},{2417,2868745040,0,2,11269,10,0,165,0,83},{14000,3108163635,0,1,11269,10,0,58,0,27}},
  {{7940,15330,3095523800,2514808912,430721903,541988528,1153858458,1217972741},{9706,4029305082,0,0,11269,10,0,149,0,62},{3649,1081850249,1,0,5669,10,0,188,0,111},{2417,2868745040,0,2,11269,10,3,179,0,83},{14000,3108163635,0,8977,11269,117,0,54,0,26}},
  {{10160,11402,3358294840,3492516121,430721903,2119490730,790232031,1217972741},{9706,4029305082,0,0,11269,10,0,148,0,66},{3649,1081850249,1,0,5669,10,0,187,0,95},{2417,2868745040,0,2,11269,10,0,168,0,92},{14000,3108163635,0,6758,11269,385,0,56,0,35}},
}
local by_tick={}
for _,sample in ipairs(expected) do by_tick[sample[1][1]]=sample end
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,Terrain,Rebuild=m("sim"),m("openttd/terrain"),m("openttd/town_rebuild")
local core={
  settings={get=function() return nil end},
  get_dir_list=function(path)
    local files={}
    local p=assert(io.popen("ls -1 "..path))
    for n in p:lines() do files[#files+1]=n end
    p:close();return files
  end,
}
local s=m("campaign_generation")(core,root:sub(1,-2),Sim,m("world_setup")).run({
  width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=0,
  towns=4,custom_towns=4,larger_towns=3,industries=0,trees=2,variety=0,smooth=1,layout="original",growth_rate=2,
})
local function dig(h,...)
  for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
  return h
end
local checked=0
local function eq(tick,label,got,want)
  assert(got==want,("tick %d, %s: LuanTTD %s, RC1 %s"):format(tick,label,tostring(got),tostring(want)))
end
local function compare(tick,label,got,want)
  assert(#got==#want)
  for i,v in ipairs(want) do eq(tick,label.." "..i,got[i],v) end
end
local function snapshot(tick)
  local heights,types,houses,roads=1,1,1,1
  local year=Sim.date(s)
  for id,t in ipairs(s.tiles) do
    local x,z=Sim.xy(id)
    local class=t.stock_void and 7 or t.stock_landmark and 10 or t.wood and 4 or t.terrain=="water" and 6 or
      t.build=="road" and 2 or t.source_house and 3 or 0
    heights=dig(heights,Terrain.corner(s.corner_grid,x,z))
    types=dig(types,class)
    local h=t.source_house
    if h then
      houses=dig(houses,id-1,h.id,h.town-1,h.completed and 1 or 0,h.stage,h.counter,Rebuild.age(h,year),h.random_bits)
    end
    if class==2 then roads=dig(roads,id-1,t.road_bits,t.road_town-1) end
  end
  local want=assert(by_tick[tick])
  local clock=s.passenger_house_clock
  compare(tick,"clock or map digest",{tick,clock.head,s.passenger_rating_rng[1],s.passenger_rating_rng[2],
    heights,types,houses,roads},want[1])
  assert(#s.sites==#want-1)
  for i,t in ipairs(s.stock_town_growth.towns) do
    local site=s.sites[i]
    local p,q=t.supplied.passenger,t.supplied.mail
    compare(tick,"town "..i,{site.tile-1,site.nameparts,t.larger_town and 1 or 0,t.grow_counter,t.growth_rate,
      t.time_until_rebuild,p.new_max,p.old_max,q.new_max,q.old_max},want[i+1])
  end
  checked=checked+1
end
local function observe(tick) if by_tick[tick] then snapshot(tick) end end
assert(s.passenger_house_clock.counter==1280)
for _=1,120 do Sim.daily(s,nil,observe) end
assert(checked==#expected)
print("PASS seeded 128-square four-town launch to May 1: all heights, tile classes, house state, roads, town clocks, production and RNG")
