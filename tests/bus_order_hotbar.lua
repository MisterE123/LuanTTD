-- Modal inventory entries and its world dispatch remain independent of
-- the normal hotbar state, even if the old slot was a section or back.
local H=dofile("mods/luanttd_core/hotbar.lua")
for slot=1,H.size do
  local menu,done,map=H.order_overlay(slot)
  local clamped=math.min(slot,2)
  assert(menu[clamped]==H.order_pick and map[clamped]==1)
  assert(menu[done]==H.order_done and done~=clamped and map[done]==8)
  assert(#menu==2 and menu[3]==nil)
  assert(not H.path("vehicle_orders"))
end
for _,item in ipairs({H.order_pick,H.order_done}) do
  local f=assert(io.open("mods/luanttd_core/textures/"..item[3],"rb"))
  assert(f:read(8)=="\137PNG\r\n\026\n");f:close()
end
assert(H.order_done[3]~=H.order_pick[3])
for slot=1,H.size do
  local menu,done,map=H.order_overlay(slot,"vehicle","Pick destinations")
  assert(menu.title=="Pick destinations" and menu[math.min(slot,2)]==H.order_pick and menu[done]==H.order_done)
  assert(map[done]==8)
end
print("PASS: modal picks are safe from all ten old slots; distinct Pick and Done icons")

-- All fixed-length mode adapters use the same slots/legend contract.
for _,mode in ipairs({"fixed","rail"}) do
  for slot=1,H.size do
    local menu,done,map,cancel=H.order_overlay(slot,mode,"Test route orders")
    local clamped=math.min(slot,3)
    assert(#menu==3 and menu.title=="Test route orders")
    assert(menu[clamped]==H.order_pick and menu[done]==H.order_dispatch and menu[cancel]==H.order_cancel)
    assert(map[clamped]==1 and map[done]==8 and map[cancel]==9)
  end
end
