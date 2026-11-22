local mod="mods/luanttd_core/"
local S=dofile(mod.."sim.lua")
local Terrain=dofile(mod.."openttd/terrain.lua")
local s=S.new(1751)
s.road_economy=true
s.road_stock_loading=true
s.road_stock_clock=true
s.road_stock_house_supply=true
dofile(mod.."town_layout.lua")(S,s)
s.corner_grid=dofile(mod.."terrain_preview.lua")(S,Terrain,s)
local function id(x,z) return assert(S.id(x,z)) end
local a,b,d=id(9,12),id(18,12),id(10,13)
assert(S.build(s,"A","road",S.line(a,b)))
assert(S.build(s,"A","road_station",{a,b}))
assert(S.build(s,"A","road_depot",{d}))
local c=S.company(s,"A")
local legacy=assert(S.purchase(s,"A","bus","passenger",nil,d))
assert(S.vehicle_capacity(s.fleet[legacy])==30 and not s.fleet[legacy].stock_regal)
s.road_regal_enabled=true
local oldcash=c.cash
assert(not S.purchase(s,"A","bus","passenger",s.tiles[a].station))
assert(not S.purchase(s,"A","bus","mail",nil,d))
assert(not S.purchase(s,"B","bus","passenger",nil,d))
assert(c.cash==oldcash)
local bus=assert(S.purchase(s,"A","bus","passenger",nil,d))
assert(c.cash==oldcash-6562)
local v=s.fleet[bus]
local f=v.stock_regal
assert(f and f.stock_id==116 and S.vehicle_capacity(v)==31 and f.value==6562)
assert(not S.refit(s,"A",bus,"mail") and not S.service(s,"A",bus))
for _=1,8 do S.daily(s) end
assert(f.ticks==0 and f.running_fp==0 and f.value==6537)
assert(S.sell(s,"A",bus) and c.cash==oldcash-25)
bus=assert(S.purchase(s,"A","bus","passenger",nil,d))
local function order(tile)
  assert(S.add_order(s,"A",bus,s.tiles[tile].station))
end
order(a);order(b)
assert(S.toggle(s,"A",bus))
local function copy(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
local function until_paid()
  local vehicle=s.fleet[bus]
  local original=vehicle.delivered
  local loaded=vehicle.units>0 and S.vehicle_capacity(vehicle)==31
  for _=1,220 do
    S.daily(s)
    loaded=loaded or (vehicle.units>0 and S.vehicle_capacity(vehicle)==31)
    if vehicle.delivered>original then
      local finance=vehicle.stock_regal
      local company=s.companies.A
      assert((loaded or original>0) and finance.charged_ticks>0 and finance.ticks>=finance.charged_ticks,
        ("loaded=%s original=%d ticks=%d billed=%d"):format(tostring(loaded),original,finance.ticks,finance.charged_ticks))
      assert(vehicle.expense==math.ceil(finance.running_fp/256))
      assert(company.stock_money_fraction==(-finance.running_fp)%256)
      assert(not S.sell(s,"A",bus) and S.vehicle_capacity(s.fleet[legacy])==30)
      return
    end
  end
  error("Original bus never delivered passengers")
end
until_paid()
s=copy(s);s.road_regal_enabled=false
until_paid()
print("PASS: source MPS Regal depots, 31-seat loading, resale value and once-only fixed costs for a saved paid route")
