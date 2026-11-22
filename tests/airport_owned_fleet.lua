local root="mods/luanttd_core/"
local src=root.."openttd/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(src.."terrain.lua")
local Slope=dofile(src.."slope.lua")
local Small=dofile(src.."airport_small.lua")
local Motion=dofile(src.."airport_motion.lua")(Small)
local Net=dofile(root.."airport_network.lua")(Sim,Terrain,Small)
local Roster=dofile(src.."airport_roster.lua")
local Run=dofile(root.."airport_preview_run.lua")(Sim,Net,Small,Motion,Terrain,Slope,Roster)
local Owned=dofile(root.."airport_owned.lua")(Sim,Run,Roster,function()return true end)
local s=Sim.new(1751)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply=true,true,true
s.air_fleet_preview,s.air_owned_preview,s.air_paid_service=true,true,true
dofile(root.."town_layout.lua")(Sim,s)
s.corner_grid=dofile(root.."terrain_preview.lua")(Sim,Terrain,s)
local function build(x,z) return assert(Net.build(s,"A",Sim.id(x,z))) end
local a,c,b=build(7,12),build(20,12),build(30,11)
local function buy(airport) return assert(Owned.commit(s,"A",assert(Owned.quote(s,"A",airport.id,215)))) end
local function copy(t)
  if type(t)~="table" then return t end
  local result={}
  for k,v in pairs(t) do result[k]=copy(v) end
  return result
end
assert(Owned.quote(s,"A",a.id,216)) -- a Coleman can fly alone in the default fleet
local pa=buy(a)
assert(not Owned.quote(s,"A",b.id,216))
local pb=buy(b)
assert(pa.id==1 and pb.id==2)
assert(not Owned.quote(s,"A",c.id,215))
assert(not Owned.quote(s,"A",a.id,215))
assert(not Owned.start(s,"B",a.id,c.id))
assert(Sim.company(s,"A").expense==2*38281+3*7200)
-- Reverse dispatch order deliberately: stock iterates vehicle creation IDs.
assert(Owned.start(s,"A",b.id,c.id))
assert(Owned.start(s,"A",a.id,c.id))
for i,air in ipairs(Run.gather(s)) do assert(air.paid_clock==i) end
assert(Run.current(s,2).first==b.id and Run.current(s).first==a.id)
Sim.mount_paid_air(s,Run)
local function targets()
  return Sim.air_paid_status(s,1),Sim.air_paid_status(s,2)
end
local function run_both()
  local first,second=targets()
  local x,y=first and first.fare or 0,second and second.fare or 0
  for i=1,480 do
    Sim.daily(s)
    first,second=targets()
    for _,a in ipairs(Run.gather(s)) do assert(a.phase~="blocked",a.failure) end
    if first and second and first.fare>x and second.fare>y then
      assert(first.tick==second.tick and first.tick==s.passenger_house_clock.counter)
      assert(first.capacity==25 and second.capacity==25 and first.fare+second.fare==Sim.company(s,"A").revenue)
      assert(first.running_expense>0 and second.running_expense>0)
      assert(first.delivered+second.delivered==Sim.company(s,"A").paid_units)
      return first,second
    end
  end
  error("The two source aircraft did not both pay")
end
local a0,b0=run_both()
s=copy(s)
Sim.mount_paid_air(s,Run)
assert(Sim.air_paid_status(s,1).fare==a0.fare and Sim.air_paid_status(s,2).fare==b0.fare)
local fa,fb=run_both()
assert(fa.delivered>a0.delivered and fb.delivered>b0.delivered)
assert(fa.charged_running_ticks>a0.charged_running_ticks and fb.charged_running_ticks>b0.charged_running_ticks)
print(("PASS: genuine purchased two-aircraft shared country hub caught $%d and $%d after reloading active stock routes"):format(fa.fare,fb.fare))
