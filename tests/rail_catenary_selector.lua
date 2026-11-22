-- The returned file paths and offsets are the presentation contract.
local A=dofile("mods/luanttd_core/rail_catenary_art.lua")
assert(A.atlas=="bl_rail_catenary_atlas.png")
for _,t in ipairs({{1,0},{2,0},{4,0},{8,0},{16,0},{32,0},{1,1},{1,2},{2,3},{2,4}}) do
  local mask,grade=t[1],t[2]
  local a=assert(A.overlay(mask,grade,"plain",0,0))
  assert(a.pole and a.offset==(grade==0 and 2 or 3))
  assert(io.open("mods/luanttd_core/models/"..a.mesh,"rb")):close()
end
for x=0,9 do
  assert(A.overlay(1,0,"plain",x,0).pole==(x%2==0))
  assert(A.overlay(2,0,"plain",0,x).pole==(x%2==0))
end
for _,m in ipairs({1,2}) do
  assert(A.overlay(m,0,"plain",1,1,true).pole)
  for _,x in ipairs({0,1}) do
    local P=A.overlay(m,0,"platform",x,x,true)
    assert(P and not P.pole and P.mesh=="bl_rail_catenary_"..m.."_0.obj")
  end
end
for _,kind in ipairs({"depot","bridge","tunnel","crossing","half","water","junction"}) do
  assert(A.overlay(1,0,kind,0,0)==nil)
end
for _,m in ipairs({0,3,5,12,48,63}) do
  assert(A.overlay(m,0,"plain",0,0)==nil)
end
assert(not A.overlay(4,1,"plain",0,0))
assert(not A.overlay(1,1,"platform",0,0))
local eq=function(a,b)return math.abs(a-b)<1e-7 end
assert(eq(A.wire_edge(1,1,0,0),A.wire_edge(1,0,2,0)))
assert(eq(A.wire_edge(1,1,2,0),A.wire_edge(1,0,0,1)))
assert(eq(A.wire_edge(2,3,1,0),A.wire_edge(2,0,3,1)))
assert(A.wire_edge(32,0,2,7)==nil)
print("RAIL_CATENARY_SELECTOR_PASS exact names, anchor, supported pieces, platform wire-only, grade edge continuity")
