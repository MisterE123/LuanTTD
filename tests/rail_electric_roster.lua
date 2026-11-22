local root="mods/luanttd_core/openttd/"
local R=dofile(root.."rail_roster.lua")
local Calendar=dofile(root.."stock_engine_calendar.lua")
local Types=dofile(root.."rail_types.lua")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end

local e=assert(R.entry(23))
eq(e.visual,"sh_30");eq(e.railtype,1);eq(e.image_index,20);eq(e.length,8)
eq(e.power,3600);eq(e.speed,160);eq(e.tare,84);eq(e.running_factor,180)
eq(R.introduction(23,1966,1751,0),Calendar.date(1965,1,1))
eq(R.purchase_price(23),40625)
for _,v in ipairs(R.catalog()) do assert(not R.electric_engine(v.stock_id)) end
eq(R.catalog(true)[8].stock_id,23)
eq(R.catalog(true)[9].stock_id,24)
local later=assert(R.entry(24))
eq(later.visual,"sh_40");eq(later.railtype,1);eq(later.image_index,20);eq(later.length,8)
eq(later.power,5000);eq(later.speed,176);eq(later.tare,82);eq(later.running_factor,205)
eq(later.vehicle_life,23);eq(later.model_life,80)
eq(R.introduction(24,2000,1751,0),Calendar.date(1973,1,1))
eq(R.purchase_price(24),46875)

local stats=assert(R.stats({23,27}))
eq(stats.power,3600);eq(stats.weight,109);eq(stats.running_year_fp,864000)
eq(stats.cargo_capacity.passenger,40)
assert(not stats.compatible[0] and stats.compatible[1])
assert(Types.is_compatible(1,0) and not Types.has_power(1,0))
local mixed=assert(R.stats({0,23,27}))
assert(mixed.compatible[0] and mixed.compatible[1] and mixed.power==3900)

local d={id=5,kind="depot",owner="Ada",railtype=1}
local opts={company_railtypes={[0]=true,[1]=true},available=function() return true end}
local function reject(expected,id)
  local q,why=R.quote(d,"Ada",{id or 23,27},opts)
  assert(not q);eq(why,expected)
end
reject("RAIL_VEHICLE_NOT_MOUNTED")
reject("RAIL_VEHICLE_NOT_MOUNTED",24)
opts.mounted_electric={[23]=true}
reject("RAIL_VEHICLE_NOT_MOUNTED",24)
opts.mounted_electric[24]=true
d.railtype=0
reject("INCOMPATIBLE_DEPOT_RAIL")
reject("INCOMPATIBLE_DEPOT_RAIL",24)
d.railtype=1
opts.company_railtypes[1]=nil
reject("RAIL_VEHICLE_NOT_AVAILABLE")
opts.company_railtypes[1]=true
eq(assert(R.quote(d,"Ada",{23,27},opts)).price,42554)
eq(assert(R.quote(d,"Ada",{24,27},opts)).price,48804)
assert(R.quote(d,"Ada",{0,27},opts))
opts.available=function(id) return not R.electric_engine(id) end
reject("RAIL_VEHICLE_NOT_AVAILABLE")
reject("RAIL_VEHICLE_NOT_AVAILABLE",24)
print("PASS exact electric SH30 and SH40 rows, per-model mounting, powered depot purchase, and stock prices")
