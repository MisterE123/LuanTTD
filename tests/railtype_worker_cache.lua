-- Availability must stay in stock calendar order; render requests from
-- multiple companies must not re-run the full engine calculation.
local m="mods/luanttd_core/"
local F=dofile(m.."rail_depot_fleet.lua")
local Owned=dofile(m.."rail_owned_service.lua")
local Roster=dofile(m.."openttd/rail_roster.lua")
local Types=dofile(m.."openttd/rail_types.lua")
local Fleet=F({}, {}, Roster)
local base=Fleet.railtype_mask
local polls=0
Fleet.railtype_mask=function(...)
  polls=polls+1
  return base(...)
end
local ok=function() return true end
local O=Owned(Fleet,Roster,{mount_advanced_wagon=ok,mount_owned_model=ok})
local s={companies={operator={},rival={}},day=1,stock_electrification=true}
local function setup()
  assert(Fleet.initialize(s,{starting_year=1980,climate="temperate",generation_seed=1751,startup_random=9001,calendar_origin_day=s.day}))
end
setup()
local mono={[54]=true,[57]=true,[58]=true}
assert(O.railtype_mask(s,"operator",Types)==base(s,"operator",Types) and polls==1)
assert(O.railtype_mask(s,"rival",Types)==base(s,"rival",Types) and polls==1)
assert(O.railtype_mask(s,"guest",Types)==0 and polls==1)
assert(O.mount_advanced(Types,mono))
assert(O.railtype_mask(s,"operator",Types)==base(s,"operator",Types,mono) and polls==2)
s.day=30*365
assert(Types.available(2,O.railtype_mask(s,"rival",Types)) and polls==3)
s.stock_electrification=false
assert(O.railtype_mask(s,"rival",Types)==base(s,"rival",Types,mono) and polls==4)
s.companies.rival=nil
assert(O.railtype_mask(s,"rival",Types)==0 and polls==4)
s.companies.rival={}
assert(O.railtype_mask(s,"rival",Types)==base(s,"rival",Types,mono) and polls==4)
s.stock_rail_fleet=nil
setup()
assert(not Types.available(2,O.railtype_mask(s,"operator",Types)) and polls==5)
local alternate={}
for k,v in pairs(Types) do alternate[k]=v end
assert(O.railtype_mask(s,"operator",alternate)==base(s,"operator",alternate,mono) and polls==6)
print("PASS railtype display reuses public stock mask without changing ownership, era, mounting, or fleet replacement")
