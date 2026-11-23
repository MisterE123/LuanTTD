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

local function clock(initial,normal)
  local step,shutdown,writes,sync=nil,nil,{},0
  local rate,phase,sim=initial,.395375,1
  local core={settings={
    get=function(_,key)assert(key=="time_speed");return rate end,
    set=function(_,key,value)assert(key=="time_speed");writes[#writes+1]=value;rate=value end,
    remove=function(_,key)assert(key=="time_speed");rate=nil end,
  },register_globalstep=function(f)step=f end,register_on_leaveplayer=function()end,
  register_on_shutdown=function(f)shutdown=f end,
  get_timeofday=function()return phase end,
  set_timeofday=function(next)assert(eq(next,phase),"speed change jumped the solar phase");sync=sync+1 end}
  A.start(core,function()return sim end)
  if normal==0 then
    sim=4;step(.6)
    assert(tonumber(rate)==0 and sync==0 and #writes==0 and not shutdown)
    return
  end
  assert(tonumber(rate)==normal)
  local updated=sync
  step(.6);assert(sync==updated)
  sim=0;step(.1);step(2);assert(tonumber(rate)==0 and sync==updated+1)
  sim=2;step(.1);assert(tonumber(rate)==2*normal and sync==updated+2)
  phase=.783 -- test administrator /time is not overwritten by playback.
  sim=4;step(.1);assert(tonumber(rate)==4*normal and sync==updated+3)
  sim=1;step(.1);assert(tonumber(rate)==normal and sync==updated+4)
  shutdown()
  assert(rate==initial,"temporary speed settings were not restored")
end
clock("72",720)
clock(nil,720)
clock("300",300)
clock("0",0)
print("Daylight clock: 1×/2×/4×, pause and resume, no phase jump, configurable baseline and explicit freeze")
