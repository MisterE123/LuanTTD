local mod="mods/luanttd_core/"
local S=dofile(mod.."sim.lua")
local Members=dofile(mod.."road_stop_members.lua")(S)
local function id(x,z)return S.id(x,z) end
local sign=id(8,8)
local st={tile=sign,id=17,owner="Town Transit",stock={passenger=22}}
local p=Members.preview(st,{{id=id(8,9),kind="bus"},{id=id(9,8),kind="truck"}})
assert(p.spread.w==2 and p.spread.h==2 and p.sign==sign)
assert(p.road_stop_areas.bus.h==2 and p.road_stop_areas.truck.tile==id(9,8))
Members.structural_apply(st,p)
assert(st.stock.passenger==22 and st.tile==sign and st.id==17 and st.stop_type==nil)
local q=Members.preview(st,{{id=sign},{id=id(8,9)}})
assert(q.sign==id(9,8) and q.spread.w==1 and not q.road_stop_areas.bus)
Members.structural_apply(st,q)
assert(st.tile==id(9,8) and st.stop_type=="truck" and st.stock.passenger==22)
print("PASS station-specific physical and facility bounds retain a shared identity and cargo; removal clamps its sign")
