local A=dofile("mods/luanttd_core/atmosphere.lua")
local function eq(a,b) return math.abs(a-b)<.00001 end
local midday=A.sample(.5,.53)
local moon=A.sample(0,.53)
local dusk=A.sample(.75,.53)
assert(eq(midday.ratio,.98) and eq(moon.ratio,.53))
assert(moon.ratio<dusk.ratio and dusk.ratio<midday.ratio)
assert(moon.sky~=midday.sky and dusk.horizon~=moon.horizon and dusk.horizon~=midday.horizon)
for i=0,9999 do
  local a=A.sample(i/10000,.53)
  local b=A.sample((i+1)/10000,.53)
  assert(math.abs(a.ratio-b.ratio)<.002,"sky ratio has a jump")
end
assert(eq(A.sample(.9999,.53).ratio,A.sample(.0001,.53).ratio))

local function lifecycle()
  local phase,step,leave=.5
  local player,lookup={},{}
  local p=player
  local methods={sky=0,sun=0,moon=0,stars=0,clouds=0,lighting=0}
  for key in pairs(methods) do
    p["set_"..key]=function(_,params)
      p[key]=params
      methods[key]=methods[key]+1
    end
  end
  p.num_ratios=0
  p.override_day_night_ratio=function(_,ratio) p.ratio=ratio;p.num_ratios=p.num_ratios+1 end
  p.get_player_name=function() return "Player" end
  lookup.Player=p
  local core={
    register_globalstep=function(fn) step=fn end,
    register_on_leaveplayer=function(fn) leave=fn end,
    get_timeofday=function() return phase end,
    get_player_by_name=function(name) return lookup[name] end,
    set_timeofday=function() error("atmosphere must not drive world time") end,
  }
  local open=A.start(core)
  step(2)
  assert(methods.sky==0,"placement players managed before opening")
  open(p)
  assert(p.sun.visible and p.moon.visible and p.stars.visible)
  assert(p.moon.texture=="bl_coastal_moon.png" and p.sky.type=="regular")
  assert(p.sky.clouds==true and p.sky.body_orbit_tilt==20)
  assert(methods.clouds==1)
  local nightFog=p.sky.fog.fog_color
  assert(eq(p.ratio,.98))
  step(10)
  assert(p.num_ratios==1 and methods.sky==1,"frozen clock rewrites unchanged sky or light")
  phase=.75
  step(.61)
  assert(p.num_ratios==2 and methods.sky==2)
  local sunset=p.ratio
  assert(sunset<.98 and sunset>.53)
  phase=0
  step(.61)
  local expected=.53
  assert(eq(p.ratio,expected) and p.ratio<sunset)
  assert(methods.sky==3 and methods.moon==1)
  assert(nightFog~=p.sky.fog.fog_color)
  leave(p)
  phase=.4
  step(4)
  assert(methods.sky==3)
  open(p)
  assert(eq(p.ratio,.98) and methods.moon==2)
  assert(methods.sky==4)
end
lifecycle()
print("Atmosphere: smooth day/night, visible moon, haze independent, frozen/advancing clocks, reconnect and no setting or clock writes")

local Solar=dofile("mods/luanttd_core/campaign_solar_clock.lua")
local Sim=dofile("mods/luanttd_core/sim.lua")
local Calendar=dofile("mods/luanttd_core/openttd/stock_engine_calendar.lua")
local Step=dofile("mods/luanttd_core/campaign_step.lua")
local Codec=dofile("mods/luanttd_core/packed_campaign.lua")
Sim.engine_calendar=Calendar
local function make_world(year)
  return {day=0,speed=1,stock_bus_market={epoch=Calendar.date(year,1,1)}}
end
local function test_year(year,days)
  local s=make_world(year)
  local sample=Solar.new(Sim,s,1.25)
  local function phase() return Solar.phase(sample(0),0) end
  assert(sample(0).year_days==days and eq(phase(),.5))
  s.day=math.floor(days/2);s.campaign_day_fraction=days/2-s.day
  assert(eq(phase(),0))
  s.day=days-1;s.campaign_day_fraction=.999
  assert(phase()<.5 and phase()>.49)
  s.day=days;s.campaign_day_fraction=0
  assert(sample(0).year==year+1 and eq(phase(),.5))
end
test_year(1950,365)
test_year(2000,366)
test_year(2100,365)
do
  local s=make_world(2000)
  local sample=Solar.new(Sim,s,1.25)
  local function step(state)
    return Step.new(state,1.25,{persist_fraction=true,advance=function(w) w.day=w.day+1 end,refresh=function() end})
  end
  local owner=step(s)
  owner.step(.5,true,true)
  assert(eq(s.campaign_day_fraction,.4))
  local running=sample(1000000)
  assert(Solar.phase(running,1100000)>Solar.phase(running,1000000))
  assert(eq(Solar.phase(running,1200000),Solar.phase(running,99999000)),"any extrapolation must be bounded")
  s.speed=0
  owner.step(60,false,true)
  local pause=sample(2000000)
  assert(eq(pause.fraction,.4) and eq(Solar.phase(pause,2000000),Solar.phase(pause,3000000)))
  s=assert(Codec.decode(Codec.encode(s)))
  owner=step(s)
  assert(eq(Solar.phase(Solar.new(Sim,s,1.25)(3000000),3000000),Solar.phase(pause,2000000)))
  s.speed=4
  owner.step(.1875,false,true)
  assert(s.day==1 and eq(s.campaign_day_fraction,0))
end

local function clock(initial)
  local step,shutdown,writes,sync=nil,nil,{},0
  local rate,phase,calendar=initial,.8,.5
  local core={settings={
    get=function(_,key)assert(key=="time_speed");return rate end,
    set=function(_,key,value)assert(key=="time_speed");writes[#writes+1]=value;rate=value end,
    remove=function(_,key)assert(key=="time_speed");rate=nil end,
  },register_globalstep=function(f)step=f end,register_on_leaveplayer=function()end,
  register_on_shutdown=function(f)shutdown=f end,
  get_timeofday=function() return phase end,
  set_timeofday=function(next_)phase=math.floor(next_*24000)/24000;sync=sync+1 end}
  A.start(core,function()return calendar end)
  assert(tonumber(rate)==0 and eq(phase,.5))
  step(.22);assert(sync==1)
  calendar=nil;step(.6);assert(eq(phase,.5) and sync==1)
  calendar=.75;step(.6);assert(eq(phase,.75) and sync==2)
  step(2);assert(sync==2)
  calendar=.99999;step(.6);assert(eq(phase,0) and sync==3)
  phase=.5;step(.6);assert(eq(phase,0) and sync==4,"native clock diverged from its calendar owner")
  shutdown()
  assert(rate==initial and writes[1]=="0","temporary simulation clock override not restored")
end
clock("72")
clock(nil)
clock("300")
clock("0")
print("Daylight clock: calendar year and leap days, pause/resume, bounded worker interpolation, saved phase, and exact native synchronization")

do
  local p1,p2={},{}
  local function setup(p,name)
    for _,key in ipairs({"sky","sun","moon","stars","clouds","lighting"}) do
      p["set_"..key]=function(_,value) p[key]=value end
    end
    p.get_player_name=function() return name end
    p.override_day_night_ratio=function(_,ratio) p.ratio=ratio end
  end
  setup(p1,"Host")
  setup(p2,"Guest")
  local by_name={Host=p1,Guest=p2}
  local world_phase,display=.82,.50
  local singleplayer,saved=false,0
  local step
  local core={
    is_singleplayer=function() return singleplayer end,
    check_player_privs=function(name,wanted) return name=="Host" and wanted.server end,
    get_player_by_name=function(name) return by_name[name] end,
    get_timeofday=function() return display end,
    set_timeofday=function(x) display=math.floor(x*24000)/24000 end,
    register_globalstep=function(fn) step=fn end,
    register_on_leaveplayer=function()end,
    register_on_shutdown=function()end,
    settings={get=function()end,set=function()end},
  }
  local storage={
    get_int=function(_,k) assert(k=="atmosphere_always_day_v1");return saved end,
    set_int=function(_,k,v) assert(k=="atmosphere_always_day_v1");saved=v end,
  }
  local function start() return A.start(core,function() return world_phase end,storage) end
  local open,lighting=start()
  open(p1);open(p2)
  assert(eq(display,.82) and p1.ratio<.60 and eq(p2.ratio,p1.ratio))
  assert(eq(p1.lighting.volumetric_light.strength,.2) and p1.lighting.bloom.intensity>0)
  assert(not lighting.is_always_day() and not lighting.allowed(p2) and not lighting.toggle(p2) and saved==0)
  assert(lighting.allowed(p1) and lighting.toggle(p1) and lighting.is_always_day())
  assert(eq(display,.4) and eq(p1.ratio,.98) and eq(p2.ratio,.98) and saved==1)
  world_phase=.10
  step(1)
  assert(eq(display,.4) and eq(world_phase,.10),"the real phase continues behind the held sun")
  local reopen,restart=start()
  reopen(p2)
  assert(restart.is_always_day() and eq(display,.4) and eq(p2.ratio,.98))
  assert(restart.toggle(p1) and not restart.is_always_day() and saved==0)
  assert(eq(display,.10) and p2.ratio<.60,"restoring cycle instantly resumes the current phase")
  singleplayer=true
  assert(restart.allowed(p2),"single-player need not have multiplayer operator privilege")
end
print("World daylight preference: original default, authorized multiplayer control, real phase independent, and saved/reloaded preference")
