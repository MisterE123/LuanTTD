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
local Bridge=dofile("mods/luanttd_core/pedestrian_bridge.lua")
for _,family in ipairs({"wood","concrete","girder","suspension_concrete","suspension_steel","cantilever","fast_girder"}) do
  for _,mode in ipairs({"road","rail"}) do
    for dir=0,3 do
      local asset=mode.."_bridge_"..family.."_head_ramp_"..dir
      local a=assert(C.bridge(asset),asset)
      assert(#a==2)
      local b=Bridge.add_rails(Bridge.box("head_ramp",dir),a,dir%2==0)
      assert(#b<=24 and #b>=12,asset)
      local cross=(dir%2==0) and 3 or 1
      for _,q in ipairs(b) do
        if q[5]-q[2]>.14 then
          assert(q[cross+3] < .28 or q[cross] > .72,"bridge rail must leave its approach open")
        end
      end
    end
  end
end
for x=0,2 do for z=0,2 do
  local boxes=assert(C.box("industry_farm_"..x.."_"..z))
  assert(#boxes<=12)
  for _,b in ipairs(boxes) do
    assert((b[4]-b[1])<1.95 or (b[6]-b[3])<.50,"do not block farm courtyards")
  end
end end
for _,id in ipairs({14,20}) do for p=0,3 do
  local boxes=assert(C.box("town_stock_"..id.."_"..p))
  assert(#boxes>=5 and #boxes<=14)
  for _,b in ipairs(boxes) do
    assert(b[5]<.10,"do not collide with stadium canopy")
    if b[4]-b[1]>1.7 and b[6]-b[3]>1.7 then assert(b[5]<-.40,"only the pitch support can span footprint") end
  end
end end
print("PASS bridge guard gaps, farm yard gaps and stadium pitch/tread collider bounds")
do
  local b=C.box("scenery_house_0")
  assert(b[1][1]<=-.059 and b[1][5]==.125,"pad main facade horizontally, not vertically")
  assert(b[#b][1]==101/128 and b[#b][3]==166/128 and b[#b][5]==-39/128,
    "do not pad detached house fence")
  local s=C.box("industry_farm_0_0")
  assert(s[1][1]<=-.059 and s[1][5]==123/128,"pad silo wall only")
end
