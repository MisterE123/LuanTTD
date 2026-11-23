local hotbar="mods/luanttd_core/hotbar.lua"
local function check(H,menu,slot,expected)
  local path=assert(H.path(menu),menu)
  local k,got=H.choose(path,slot)
  assert(got==expected,("%s[%s]: got %s, expected %s"):format(menu,slot,tostring(got),tostring(expected)))
  return k,path
end
local function routes(H,target,...)
  local path={"home"}
  for _,slot in ipairs({...}) do
    assert(H.choose(path,slot)=="menu",target)
  end
  assert(H.active(path)==target,target)
  local canonical=assert(H.path(target),target)
  assert(table.concat(canonical,"/")==table.concat(path,"/"),target.." duplicate shortcut")
  for i=#canonical-1,1,-1 do
    local action,menu=H.choose(path,8)
    assert(action=="menu" and menu==canonical[i] and #path==i)
  end
end
local bare=dofile(hotbar)
for i=1,7 do
  local p={"home"}
  assert(bare.choose(p,i)=="menu")
  assert(select(2,bare.choose(p,8))=="home")
end
assert(not bare.choose({"home"},8))
check(bare,"roads",2,"road")
check(bare,"roads",9,"clear")
check(bare,"roads",5,nil)
check(bare,"roads",7,nil)
check(bare,"roads",3,"road_station")
routes(bare,"navigation",5)
check(bare,"navigation",5,"jump")
bare.enable_trams()
routes(bare,"tramway",2,7,4)
assert(not bare.menus.home[8] and not bare.menus.home[10])
check(bare,"tramway",5,"tram_bit")
check(bare,"tramway",7,"tram_clear")
check(bare,"tramway",10,"tram_order")
bare.enable_structures()
routes(bare,"structures",2,10)
check(bare,"structures",2,"structure_wood")
check(bare,"structures",3,"structure_steel")
check(bare,"structures",5,"structure_concrete")
check(bare,"roads",6,"structure_tunnel")
check(bare,"road_direction",3,nil)
bare.enable_railworks()
routes(bare,"railengineering",8,6)
check(bare,"railengineering",2,nil)
check(bare,"railengineering",4,nil)
check(bare,"railengineering",6,"rail_rotate")
routes(bare,"railpieces",8,6,7)
for i,tool in ipairs({"rail_track_x","rail_track_y","rail_track_upper","rail_track_lower",
    "rail_track_left","rail_track_right","rail_piece_remove"}) do
  check(bare,"railpieces",i,tool)
end

local builders={
  "enable_structures","enable_trams","enable_ships","enable_airfields","enable_railworks","enable_freight",
}
local function verify(order)
  local H=dofile(hotbar)
  for _,i in ipairs(order) do H[builders[i]](true,true,true) end
  H.enable_oneway();H.enable_bay_termini();H.enable_electric_rail();H.enable_rail_pair();H.enable_rail_block()
  H.enable_rail_oil();H.enable_rail_coal();H.enable_rail_goods();H.enable_ship_coal()
  routes(H,"structures",2,7,3)
  routes(H,"tramway",2,7,4)
  routes(H,"harbor",10,2)
  routes(H,"waterworks",10,2,4)
  routes(H,"harbor_ops",10,2,7)
  routes(H,"airfields",10,3)
  routes(H,"railworks",8)
  routes(H,"freight",2,5)
  routes(H,"railpieces",8,7,1,7)
  routes(H,"railsignals",8,5)
  routes(H,"railops",8,7)
  routes(H,"railfreight",8,7,5)
  routes(H,"railtypes",8,7,1,1)
  routes(H,"road_stops",2,3)
  for _,menu in ipairs({"road_direction","road_stops","roads","terrain","structures","tramway","harbor",
    "waterworks","airfields","freight","railworks","railengineering","railpieces","railsignals","railtypes"}) do
    check(H,menu,9,"clear")
  end
  for menu,slots in pairs(H.menus) do
    if menu~="home" then assert(slots[8][1]=="back",menu) end
    local d={}
    for k=1,10 do
      if slots[k] then
        assert(not d[slots[k][1]],menu..": duplicate "..slots[k][1])
        d[slots[k][1]]=true
        if slots[k][1]=="clear" then assert(k==9,menu) end
      end
    end
  end
  check(H,"navigation",2,nil)
  check(H,"navigation",3,nil)
  check(H,"navigation",4,nil)
  check(H,"navigation",5,"jump")
  check(H,"navigation",6,nil)
  check(H,"navigation",7,nil)
  check(H,"railworks",2,"rail_autotrack")
  check(H,"railworks",6,"rail_span_tunnel")
  check(H,"railworks",10,"rail_bridge_picker")
  check(H,"railengineering",4,"rail_crossing_tool")
  check(H,"railops",4,"rail_order_span")
  check(H,"railops",6,"rail_order_pair")
  check(H,"railsignals",4,"rail_signal_block")
  check(H,"roads",10,"road_bridge_picker")
  check(H,"waterworks",2,"ship_canal")
  check(H,"waterworks",3,"ship_lock")
  check(H,"waterworks",4,"ship_aqueduct")
  check(H,"harbor_ops",2,"ship_order")
  check(H,"harbor_ops",3,"ship_coal_order")
  check(H,"road_stops",2,"road_station")
  check(H,"road_stops",3,"road_bay_pair")
  check(H,"road_direction",2,"oneway_drag")
  check(H,"airfields",3,"airfield_order")
  check(H,"freight",3,"truck_stop_tool")
  check(H,"railfreight",2,"rail_coal_load")
  check(H,"railfreight",3,"rail_coal_unload")
  check(H,"railfreight",4,"rail_goods_load")
  check(H,"railfreight",5,"rail_goods_unload")
  check(H,"railfreight",6,"rail_coal_flip")
  check(H,"railfreight",7,"rail_oil_freight")
  check(H,"rail_oil_freight",2,"rail_oil_load")
  check(H,"rail_oil_freight",3,"rail_oil_unload")
  H.enable_rail_oil()
  check(H,"railfreight",4,"rail_goods_load")
  check(H,"railfreight",5,"rail_goods_unload")
  local title,focus,hint=H.legend({"home","roads","road_direction"},2,true)
  assert(title=="Road Construction  ›  Road Options" and focus:match("^2  Paint"))
  assert(hint:match("Click or drag") and hint:match("8 Back") and hint:match("9 Bulldoze"))
  title,focus,hint=H.legend({"home"},10,false)
  assert(title==H.menus.home.title and focus=="0  Sea & Air" and hint=="Left-click to open")
  _,focus,hint=H.legend({"home","navigation"},8,false)
  assert(focus=="8  Back" and hint:match("Left%-click to return") and not hint:match("9 Bulldoze"))
end
local permutations=0
local function generate(path,used)
  if #path==#builders then
    permutations=permutations+1;verify(path);return
  end
  for i=1,#builders do
    if not used[i] then
      used[i]=true;path[#path+1]=i
      generate(path,used)
      used[i]=nil;path[#path]=nil
    end
  end
end
generate({}, {})
local oil=dofile(hotbar)
oil.enable_rail_oil();assert(not oil.path("railfreight"))
oil.enable_railworks();oil.enable_rail_oil();oil.enable_rail_goods()
check(oil,"rail_oil_freight",2,"rail_oil_load")
check(oil,"rail_oil_freight",3,"rail_oil_unload")
print(("PASS: canonical construction routes, Back / Bulldoze, live legend, and mounted paid tools across all %d registration orders"):format(permutations))
