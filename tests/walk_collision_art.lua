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

local function hit(boxes,x,y,z)
  for _,b in ipairs(boxes or {}) do
    if x>=b[1] and x<=b[4] and y>=b[2] and y<=b[5] and z>=b[3] and z<=b[6] then return true end
  end
end
local function boxes(asset,max)
  local b=assert(C.box(asset),asset)
  assert(#b>0 and #b<=max,asset)
  for _,q in ipairs(b) do for i=1,3 do
    assert(q[i]<q[i+3] and q[i]*128%1==0 and q[i+3]*128%1==0,asset)
  end end
  return b
end
local witnesses={
  {"power_station_0_0",-.34,-.24,.47}, -- near side solid wall
  {"power_station_2_1",.35,-.09,.10}, -- chimney shaft
  {"industry_factory_0_0",.54,-.24,-.26},
  {"industry_oil_refinery_0_1",1.04,-.24,-.02}, -- exchanger column
  {"industry_oil_well_0_0",.24,-.25,-.13},
  {"industry_steel_mill_1_0",.31,-.20,.39},
  {"industry_temperate_bank_1_0",-.36,-.03,.12},
  {"stock_lighthouse",.68,-.26,.60},
}
for _,r in ipairs(witnesses) do
  local b=boxes(r[1],10)
  assert(hit(b,r[2],r[3],r[4]),r[1])
end
-- Later campaign batches split the pump into static and animated meshes.
-- Check the static base whenever that separate art pack is mounted.
local function asset_exists(name)
  local file=io.open("mods/luanttd_core/models/bl_"..name..".obj","rb")
  if file then file:close();return true end
end
for _,name in ipairs({"industry_oil_well_base_0_0","industry_factory_work_40_1"}) do
  if asset_exists(name) then boxes(name,10) end
end
for _,name in ipairs({"coal_mine_0_0_0","sawmill_0_1_1","industry_iron_mine_1_1",
    "industry_layout_gfx_13","industry_oil_rig_0_1","stock_company_hq_4_1",
    "small_airport_0_0","rail_depot_0","tram_depot_0","ship_depot_0_0","road_depot_0"}) do
  boxes(name,10)
end
assert(hit(C.box("industry_oil_rig_0_1"),.50,3.59,.64),"continuous working deck is walkable")
for k=0,15 do
  assert(not hit(C.box("industry_oil_refinery_0_1"),.49,-.31,k*.11-.39),"open exchanger route")
  assert(not hit(C.box("road_depot_0"),.49,-.31,k*.10-.39),"road shed portal and front apron stay open")
  assert(not hit(C.box("rail_depot_0"),k*.10-.40,-.31,.50),"rail shed entry remains open")
end
assert(not C.box("small_airport_2_2") and not C.box("industry_oil_refinery_work_ground"))
for _,name in ipairs({"small_airport_2_0","small_airport_3_0","city_airport_4_0","city_airport_5_0"}) do
  assert(not C.box(name),"do not mask the dedicated sightseeing portal collision")
end

local tree_display=dofile("mods/luanttd_core/openttd/tree_display.lua")
local tree_count=0
if asset_exists("stock_tree_628_0_0") then
  for _,form in ipairs(tree_display.shapes) do
    for phase=0,6 do
      local prefix=("stock_tree_%03x_"):format(form)
      local flat=boxes(prefix.."0_"..phase,3)
      assert(flat[1][2]<-1.48 and flat[1][2]>-1.58,"root matches the registered overlay height")
      for lift=0,4 do
        local raised=boxes(prefix..lift.."_"..phase,3)
        assert(#raised==#flat)
        for i,b in ipairs(raised) do
          local a=flat[i]
          assert(b[1]==a[1] and b[3]==a[3] and b[4]==a[4] and b[6]==a[6])
          assert(b[2]-a[2]==lift*.5 and b[5]-a[5]==lift*.5)
          assert(b[4]-b[1]<.24 and b[6]-b[3]<.24,"no low canopy or imaginary foliage wall")
        end
        assert(hit(raised,0,flat[1][2]+.085+lift*.5,0),"walk must hit the actual stem at all ages")
        assert(not hit(raised,.27,flat[1][2]+.15+lift*.5,0))
        tree_count=tree_count+1
      end
    end
  end
  assert(tree_count==665)
end
for v=0,3 do
  boxes("scenery_tree_"..v,3)
  for e=0,4 do
    boxes("stock_forest_"..v.."_"..e,3)
    for _,g in ipairs({0,1,2,4,5,6}) do boxes("stock_forest_"..v.."_"..e.."_g"..g,3) end
  end
end
print(("PASS industry structures, raised decks, open working yards and depots; 144 forest/scenery profiles, %d exact stock tree profiles present"):format(tree_count))
