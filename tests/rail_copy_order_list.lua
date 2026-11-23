-- Pinned CmdCloneOrder / CO_COPY: independent clone; keep recipient
-- index only for equal counts; bail out on a failed facility predicate.
local O=dofile("mods/luanttd_core/openttd/rail_order_list.lua")
local src={{kind="station",station=1,load_type=3,extras={flags={1,2}}},
  {kind="station",station=2,unload_type=2}}
local dst={{kind="station",station=3},{kind="station",station=4}}
local cursor={real=1,implicit=1}
local function permitted(t) return t.kind=="station" and t.station~=3 end
local c,i=assert(O.copy(src,dst,cursor,permitted))
assert(i.real==1 and i.implicit==1 and c[2].unload_type==2 and c[1].load_type==3)
c[1].extras.flags[1]=5
assert(src[1].extras.flags[1]==1 and dst[1].station==3 and cursor.real==1)
local _,reset=assert(O.copy(src,{},cursor,permitted))
assert(reset.real==0 and reset.implicit==0)
local failed,why=O.copy({src[1],dst[1]},dst,cursor,permitted)
assert(not failed and why:find("Order 2:",1,true))
assert(dst[2].station==4 and cursor.implicit==1)
print("PASS 16.0-RC1 CO_COPY deep clone and destination cursor/facility rules")
