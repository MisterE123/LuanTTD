-- SPDX-License-Identifier: GPL-2.0-only
-- Stock physical and company semantics, separate from asset readiness.
local mod="mods/luanttd_core/"
local src=mod.."openttd/"
local sim=dofile(mod.."sim.lua")
local R=dofile(src.."rail_roster.lua")
local Type=dofile(src.."rail_types.lua")
local F=dofile(mod.."rail_depot_fleet.lua")(sim,{},R)
local label="operator"
local selected={[54]=true,[57]=true,[58]=true}
local function world(year)
  local s=sim.new(1751)
  sim.company(s,label)
  assert(F.initialize(s,{starting_year=year,generation_seed=1751,startup_random=9001}))
  return s
end
local old=world(1980)
local recent=world(2010)
local late=world(2035)
local function has(mask,t) return Type.available(t,mask) end
assert(not has(F.railtype_mask(old,label,Type,true),2))
assert(has(F.railtype_mask(recent,label,Type,selected),2))
assert(not has(F.railtype_mask(recent,label,Type,true),3))
assert(has(F.railtype_mask(late,label,Type,true),3))
assert(not has(F.railtype_mask(late,label,Type,selected),3))
assert(not has(F.railtype_mask(late,label,Type),2))
assert(F.railtype_mask(late,"stranger",Type,true)==0)
assert(F.availability(old,54).status=="not_introduced" and F.availability(recent,54).public)
assert(R.entry(54).engine_class=="monorail" and R.entry(84).engine_class=="maglev")
assert(#R.catalog(true,true)==#R.catalog(true)+28)

local depot={id=1,kind="depot",owner=label,railtype=2}
local function will_buy(id) return F.availability(recent,id).public end
local opts={available=will_buy,company_railtypes={[2]=true}}
local consist={54,57,58}
local q,why=R.quote(depot,label,consist,opts)
assert(not q and why=="RAIL_VEHICLE_NOT_MOUNTED")
opts.mounted_advanced=selected
q=assert(R.quote(depot,label,consist,opts))
assert(q.price==84960, q.price)
assert(q.stats.length==24 and q.stats.power==9000 and q.stats.tare==141)
assert(q.stats.display_max_speed==304 and q.stats.cargo_capacity.mail==35 and q.stats.cargo_capacity.passenger==45)
assert(q.stats.compatible[2] and not (q.stats.compatible[0] or q.stats.compatible[1] or q.stats.compatible[3]))
for _,railtype in ipairs({0,1,3}) do
  depot.railtype=railtype
  local denied,reason=R.quote(depot,label,consist,opts)
  assert(not denied and reason=="INCOMPATIBLE_DEPOT_RAIL")
end
depot.railtype=2
opts.company_railtypes={}
local denied,reason=R.quote(depot,label,consist,opts)
assert(not denied and reason=="RAIL_VEHICLE_NOT_AVAILABLE")
print("PASS stock company gauge dates and purchase quote for X2001, 45-seat coach and 35-bag Mail Van; no mixed-gauge depot admission")

local magnetic={[84]=true,[89]=true,[90]=true}
assert(has(F.railtype_mask(late,label,Type,magnetic),3))
assert(not has(F.railtype_mask(late,label,Type,magnetic),2))
assert(not has(F.railtype_mask(recent,label,Type,magnetic),3))
depot.railtype=3
opts={available=function(id) return F.availability(late,id).public end,
      company_railtypes={[3]=true},mounted_advanced=magnetic}
q=assert(R.quote(depot,label,{84,89,90},opts))
assert(q.price==113085,q.price)
assert(q.stats.length==24 and q.stats.power==10000 and q.stats.tare==151)
assert(q.stats.display_max_speed==400 and q.stats.cargo_capacity.passenger==47 and q.stats.cargo_capacity.mail==37)
assert(q.stats.compatible[3] and not (q.stats.compatible[0] or q.stats.compatible[1] or q.stats.compatible[2]))
for _,railtype in ipairs({0,1,2}) do
  depot.railtype=railtype
  local absent,reason=R.quote(depot,label,{84,89,90},opts)
  assert(not absent and reason=="INCOMPATIBLE_DEPOT_RAIL")
end
depot.railtype=3
opts.mounted_advanced[57]=true
opts.company_railtypes[2]=true
local interop,reason=R.quote(depot,label,{84,57},opts)
assert(not interop and reason=="INCOMPATIBLE_DEPOT_RAIL",reason)
print("PASS Lev1 exact RC1 purchase, 47/37 separate compartments, and rejection of mixed-gauge depots and wagons")
