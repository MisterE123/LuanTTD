-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 14.1 town_cmd.cpp UpdateTownRadius,
-- ForAllStationsNearTown, CountActiveStations, UpdateTownGrowth*,
-- TownTickHandler and monthly economy timer; town.h and timer_game_tick.h.
-- Temperate, ordinary vanilla houses and stations, no stock calendar shim.
local G={TOWN_TICKS=70,STATION_TICKS=185,ACTIVE_AGE=20,NONE=65535,MAX_TOWN_TICKS=930,
  WINTER=4294967294,DESERT=4294967295}
local floor,min,abs=math.floor,math.min,math.abs
local zones={
  [0]={4,0,0,0,0},{16,0,0,0,0},{25,0,0,0,0},{36,0,0,0,0},
  {49,0,4,0,0},{64,0,4,0,0},{64,0,9,0,1},{64,0,9,0,4},{64,0,16,0,4},
  {81,0,16,0,4},{81,0,16,0,4},{81,0,25,0,9},{81,36,25,0,9},
  {81,36,25,16,9},{81,49,0,25,9},{81,64,0,25,9},{81,64,0,36,9},
  {81,64,0,36,16},{100,81,0,49,16},{100,81,0,49,25},{121,81,0,49,25},
  {121,81,0,49,25},{121,81,0,49,36},
}
local funded={[0]=120,120,120,100,80,60}
local normal={[0]=320,420,300,220,160,100}
local function square(x,z) return x*x+z*z end
function G.chance(a,b,r) return floor(((r%65536)*b+floor(b/2))/65536)<a end
-- RandomRange uses multiply-high. Stock house probability limits are
-- small; splitting the number also handles arbitrary u32 test bounds.
function G.range(n,r)
  local a,b=floor(r/65536),r%65536
  local c,d=floor(n/65536),n%65536
  return a*c+floor((a*d+b*c+floor(b*d/65536))/65536)
end
function G.to_ticks(n) return (min(n%65536,G.MAX_TOWN_TICKS)+1)*G.TOWN_TICKS-1 end
function G.radii(num_houses)
  if num_houses<92 then return {unpack(zones[floor(num_houses/4)])} end
  local mass=floor(num_houses/8)
  return {mass*15-40,mass*9-15,0,mass*5-5,mass*3+5}
end
function G.zone(t,x,z)
  local d=square(x-t.x,z-t.z)
  if t.fund_buildings_months>0 and d<=25 then return 4 end
  local smallest=0
  for i,r in ipairs(t.radii or G.radii(t.num_houses)) do if d<r then smallest=i-1 end end
  return smallest
end
function G.new(id,x,z,opts)
  opts=opts or {}
  local n=opts.num_houses or 0
  return {id=id,x=x,z=z,num_houses=n,radii=G.radii(n),population=opts.population or 0,
    grow_counter=opts.grow_counter or id%G.TOWN_TICKS,
    growth_rate=opts.growth_rate or G.to_ticks(250),growing=not not opts.growing,
    custom_growth=not not opts.custom_growth,larger_town=not not opts.larger_town,
    fund_buildings_months=opts.fund_buildings_months or 0,
    road_build_months=opts.road_build_months or 0,exclusive_counter=opts.exclusive_counter or 0,
    exclusivity=opts.exclusivity,layout=opts.layout or "original",goal=opts.goal or {},
    supplied=opts.supplied or {},received=opts.received or {}}
end

-- Station's sign coordinate, not catchment polygon or linked town ID.
-- Supply actual Station entries from the stock-like index (not
-- waypoints/depots). A disused-but-still-indexed station can count until
-- stock deletes it; missing timers mean no demonstrated service.
function G.active_stations(t,stations)
  local n=0
  local limit=(t.radii or G.radii(t.num_houses))[1]
  local search=floor(limit/2)
  for _,st in ipairs(stations) do
    if st.indexed~=false and not st.waypoint and st.x~=nil and st.z~=nil then
      local x,z=st.x-t.x,st.z-t.z
      if abs(x)<=search and abs(z)<=search and square(x,z)<=limit and
          ((st.time_since_load or 255)<=G.ACTIVE_AGE or (st.time_since_unload or 255)<=G.ACTIVE_AGE) then
        n=n+1
      end
    end
  end
  return n
end
-- For facility modes not yet maintaining their own source station clock.
-- Do not call on the existing road station timer a second time.
function G.station_tick(st,ticks)
  if st.in_use==false or st.waypoint then return end
  local phase=(st.service_phase or 0)+(ticks or 1)
  local elapsed=floor(phase/G.STATION_TICKS)
  st.service_phase=phase%G.STATION_TICKS
  st.time_since_load=min(255,(st.time_since_load or 255)+elapsed)
  st.time_since_unload=min(255,(st.time_since_unload or 255)+elapsed)
end
function G.station_move(st,loaded,unloaded)
  if (loaded or 0)>0 then st.time_since_load=0 end
  if (unloaded or 0)>0 then st.time_since_unload=0 end
end
function G.normal_rate(t,active,setting)
  setting=setting or 2
  assert(setting>=0 and setting<=4 and setting==floor(setting),"Invalid stock town growth setting")
  local m=(t.fund_buildings_months~=0 and funded or normal)[min(active,5)]
  m=floor(m/2^(setting~=0 and setting-1 or 1))
  if t.larger_town then m=floor(m/2) end
  return G.to_ticks(floor(m/(floor(t.num_houses/50)+1)))
end
function G.adjust_counter(counter,current,previous)
  if current==G.NONE then return counter end
  if previous==G.NONE then return min(current,counter) end
  local d=previous+1
  local a=(counter*(current+1))%4294967296
  if a>=2147483648 then a=a-4294967296 end
  local q=a>0 and floor((a+floor(d/2))/d) or math.ceil((a-floor((d-1)/2))/d)
  return q%65536
end
function G.update_rate(t,stations,setting,active)
  if t.custom_growth then return t.growth_rate end
  active=active or G.active_stations(t,stations)
  local last=t.growth_rate
  t.growth_rate=G.normal_rate(t,active,setting)
  t.grow_counter=G.adjust_counter(t.grow_counter,t.growth_rate,last)
  return t.growth_rate
end
function G.update(t,stations,setting,random)
  setting=setting or 2
  local active=G.active_stations(t,stations)
  G.update_rate(t,stations,setting,active)
  t.growing=false
  local fund=t.fund_buildings_months~=0
  if not fund then
    if setting==0 then return false,"disabled" end
    for effect,goal in pairs(t.goal) do
      -- Ordinary temperate worlds do not use special climate gates.
      -- Do not silently treat an imported climate sentinel as cargo tons.
      if goal==G.WINTER or goal==G.DESERT then return false,"unsupported-climate-goal" end
      local record=t.received[effect]
      if goal>(record and record.old_act or 0) then return false,"unmet-cargo-goal" end
    end
  end
  if t.custom_growth then t.growing=t.growth_rate~=G.NONE;return t.growing,"custom" end
  if not fund and active==0 and not G.chance(1,12,assert(random,"Growth lottery needs seed RNG")()) then
    return false,"no-service"
  end
  t.growing=true
  return true,fund and "funded" or active==0 and "unserviced-chance" or "serviced"
end
local function month_rotate(stats)
  for _,a in pairs(stats) do
    a.old_act,a.old_max=a.new_act or 0,a.new_max or 0
    a.new_act,a.new_max=0,0
  end
end
function G.month(t,stations,setting,random)
  if t.road_build_months>0 then t.road_build_months=t.road_build_months-1 end
  if t.fund_buildings_months>0 then t.fund_buildings_months=t.fund_buildings_months-1 end
  if t.exclusive_counter>0 then
    t.exclusive_counter=t.exclusive_counter-1
    if t.exclusive_counter==0 then t.exclusivity=nil end
  end
  -- Stock rotates actual/max before checking received-cargo goals.
  month_rotate(t.supplied)
  month_rotate(t.received)
  return G.update(t,stations,setting,random)
end
function G.fund(t,stations,setting,random)
  t.fund_buildings_months=3
  local grow,why=G.update(t,stations,setting,random)
  t.grow_counter=min(t.grow_counter,2*G.TOWN_TICKS-math.fmod(t.growth_rate-t.grow_counter,G.TOWN_TICKS))
  return grow,why
end
function G.house_added(t,stations,setting)
  t.num_houses=t.num_houses+1
  t.radii=G.radii(t.num_houses)
  -- BuildTownHouse changes the rate without drawing the monthly lottery.
  G.update_rate(t,stations,setting)
end
function G.tick(t,attempt,editor)
  if editor or not t.growing then return false end
  local next_counter=t.grow_counter-1
  if next_counter>=0 then t.grow_counter=next_counter;return false end
  local built=not not attempt(t)
  -- A successful build can recalculate growth_rate before this assignment.
  t.grow_counter=built and t.growth_rate or min(t.growth_rate,G.TOWN_TICKS-1)
  return true,built
end
return G
