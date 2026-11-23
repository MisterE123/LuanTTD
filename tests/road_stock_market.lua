local mod="mods/luanttd_core/"
local S=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local E=dofile(mod.."openttd/stock_engine_calendar.lua")
local super=arg and arg[1]=="superbus"
local function world(year,art)
  local s=S.new(1751)
  s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
  S.mount_road_bus_market(s,E,year,art,nil,{foster_mk2_bus=art and true or nil})
  dofile(mod.."town_layout.lua")(S,s)
  s.corner_grid=dofile(mod.."terrain_preview.lua")(S,T,s)
  return s
end
local cohort=world(1950,true)
local y,m,d=S.date(cohort)
assert(y==1950 and m==1 and d==1)
assert(S.vehicle_available(cohort,"bus") and not S.vehicle_available(cohort,"leopard_bus") and not S.vehicle_available(cohort,"foster_bus"))
assert(not S.vehicle_available(cohort,"coach"))
local hereford=S.stock_road_offer(cohort,"leopard_bus")
assert(hereford.public_date and hereford.intro_date and hereford.public_date>hereford.intro_date)
local launch=hereford.public_date-cohort.stock_bus_market.epoch
cohort.day=launch-1
assert(not S.vehicle_available(cohort,"leopard_bus"))
S.daily(cohort)
assert(S.vehicle_available(cohort,"leopard_bus") and S.date(cohort)==select(1,E.ymd(hereford.public_date)))
local announced=false
for _,n in ipairs(cohort.news) do announced=announced or n=="New model now available: Hereford Leopard Bus." end
assert(announced)
local s=world(1995,true)
assert(S.stock_road_offer(s,"bus").status=="retired")
assert(S.vehicle_available(s,"foster_bus") and S.vehicle_available(s,"leopard_bus"))
local no_art=world(1995,false)
assert(not S.vehicle_available(no_art,"foster_bus") and S.vehicle_available(s,"foster_bus"),
  "Native assets are mounted per world and a missing model cannot be purchased")
if super then
  assert(not S.vehicle_available(s,"foster_mk2_bus"))
  s=world(2025,true)
  assert(not S.vehicle_available(world(2025,false),"foster_mk2_bus"))
end
local function at(x,y) return assert(S.id(x,y)) end
local a,b,depot=at(9,12),at(18,12),at(10,13)
assert(S.build(s,"A","road",S.line(a,b)))
assert(S.build(s,"A","road_station",{a,b}))
assert(S.build(s,"A","road_depot",{depot}))
local cash=S.company(s,"A").cash
assert(not S.purchase(s,"A","bus","passenger",nil,depot))
assert(not S.purchase(s,"A","foster_bus","passenger",s.tiles[a].station))
assert(S.company(s,"A").cash==cash)
local engine=super and "foster_mk2_bus" or "foster_bus"
local seats=super and 40 or 37
local v=assert(S.purchase(s,"A",engine,"passenger",nil,depot))
assert(S.company(s,"A").cash==cash-(super and 8750 or 8203))
assert(S.vehicle_capacity(s.fleet[v])==seats and s.fleet[v].stock_bus.stock_id==(super and 119 or 118))
assert(S.add_order(s,"A",v,s.tiles[a].station))
assert(S.add_order(s,"A",v,s.tiles[b].station))
assert(S.toggle(s,"A",v))
local function advance(w,more)
  local before=w.fleet[v].delivered
  for _=1,260 do
    S.daily(w)
    local bus=w.fleet[v]
    if bus.delivered>before and bus.stock_bus.charged_ticks>more then
      assert(bus.expense==math.ceil(bus.stock_bus.running_fp/256) and bus.revenue>0)
      return bus.stock_bus.charged_ticks
    end
  end
  error("Permanently unprofitable/blocked stock bus was never paid")
end
local prev=advance(s,0)
local function copy(t)
  if type(t)~="table" then return t end
  local r={};for k,v in pairs(t) do r[k]=copy(v) end
  return r
end
local clone=copy(s)
S.mount_road_bus_market(clone,E,1950,true,nil,{foster_mk2_bus=true})
assert(S.date(clone)==(super and 2025 or 1995) and S.vehicle_capacity(clone.fleet[v])==seats)
assert(advance(clone,prev)>prev)
print("PASS: stock real calendar public offer and retirement, actual Foster bus seats/price/payout, independent art gate and saved epoch")
