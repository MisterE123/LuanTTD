local m=core.get_modpath("luanttd_core")
local function mod(p) return dofile(m.."/"..p..".lua") end
local Sim=mod("sim")
Sim.W,Sim.H=256,256
local codec=mod("packed_campaign")
local H=mod("openttd/town_passengers")
local P=mod("openttd/passengers")
local R=mod("openttd/station_rating")
local Rating=mod("station_rating_runtime")(Sim,R,P)
local old=mod("baseline_town")(Sim,H,P,Rating)
local new=mod("town_passenger_runtime")(Sim,H,P,Rating)
for _,g in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..g,"air") end
core.after(0,function()
  local s={tiles={},stations={},sites={},passenger_house_clock=H.new_clock(8,8),seed=1751,day=1,topology=1}
  for i=0,511 do
    local x,z=(i%32)*8,math.floor(i/32)*16
    local st={id=i+1,owner="Townbus "..i%4,site=i%11+1,tile=Sim.id(x+1,z+1),mode="road",stock={},last_service={}}
    s.stations[st.id]=st
    Rating.status(s,st)
    R.observe_loading(st.passenger_rating_state,60,0,32)
    st.passenger_rating_state.rating=125+i%130
    for dz=-2,2 do for dx=-2,2 do
      if dx~=0 or dz~=0 then
        local id=Sim.id(x+1+dx,z+1+dz)
        if id then s.tiles[id]={house=true,source_house={id=0x19,town=st.site,completed=true}} end
      end
    end end
  end
  local fixture=codec.encode(s)
  local function run(Town)
    local world=codec.decode(fixture)
    collectgarbage("collect")
    local t,c=core.get_us_time(),os.clock()
    for day=1,12 do world.day=day;Town.day(world) end
    local wall,cpu=(core.get_us_time()-t)/1000,(os.clock()-c)*1000
    local n=0
    for _,st in pairs(world.stations) do n=n+P.waiting(st) end
    return wall,cpu,world,n
  end
  local function same(a,b)
    if type(a)~="table" then return a==b end
    if type(b)~="table" then return false end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  for i=1,10 do
    local a,ac,av,ap,b,bc,bv,bp
    if i%2==1 then a,ac,av,ap=run(old);b,bc,bv,bp=run(new)
    else b,bc,bv,bp=run(new);a,ac,av,ap=run(old) end
    assert(ap>0 and ap==bp and same(av,bv),"changed road-only allocation")
    core.log("action",("ROAD_HOUSE_BENCH batch=%d before=%.3f after=%.3f cpu_a=%.3f cpu_b=%.3f units=%d"):format(i,a,b,ac,bc,ap))
  end
  core.request_shutdown("Road-only station coverage benchmark",false,0)
end)
