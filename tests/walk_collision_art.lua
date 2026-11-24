local C=dofile("mods/luanttd_core/walk_collision_art.lua")
for i,v in ipairs(C.farm) do assert(v>.19 and v<.35,i) end
for _,asset in ipairs({"scenery_house_0","town_stock_18","town_stock_19","town_stock_07_0","town_stock_28_3"}) do
  local b=assert(C.box(asset),asset)
  assert(#b>=2 and #b<=6,asset)
  for _,a in ipairs(b) do for i=1,3 do
    assert(a[i]<a[i+3] and math.abs(a[i]*128)%1==0 and math.abs(a[i+3]*128)%1==0)
  end end
end
for _,asset in ipairs({"town_stock_0a","town_stock_0b","town_stock_0c"}) do
  assert(not C.box(asset),"pure scenery stays traversable")
end
local rail=assert(C.box("rail_ground_fence_8_0"))
assert(#rail==8 and rail==C.box("rail_ground_fence_9_0"))
for _,a in ipairs(rail) do
  assert(a[4]-a[1]<.31 and a[6]-a[3]<.31,"do not fill the whole diagonal with collision")
end
print("PASS: quantized mesh hulls, shared templates, ≤6 house and ≤8 rail boxes, parks excluded")
