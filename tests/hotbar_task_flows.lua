local factory="mods/luanttd_core/hotbar.lua"
local function mount(H,picker,features)
  H.enable_structures(picker)
  if not features then return end
  H.enable_trams(); H.enable_ships(); H.enable_airfields(true,true,true,{helidepot=true,helistation=true})
  H.enable_freight(); H.enable_railworks(true,true,picker); H.enable_electric_rail()
  H.enable_rail_pair(); H.enable_rail_block(); H.enable_ship_coal(); H.enable_bay_termini(); H.enable_oneway()
  H.enable_rail_waypoints(); H.mount_guideway_picker(true,true)
  H.enable_bank(); H.enable_rail_coal(); H.enable_rail_goods(); H.enable_rail_wood()
  H.enable_rail_farm(true,true); H.enable_rail_oil(); H.enable_rail_valuables(); H.enable_rail_metals(true,true)
end
local function find(menu,id)
  for i=1,10 do if menu[i] and menu[i][1]==id then return i end end
end
for _,picker in ipairs({false,true}) do for _,features in ipairs({false,true}) do
  local H=dofile(factory)
  mount(H,picker,features)
  local live=H.task_menus()
  local old,new,images,semantic={},{},{},{}
  for _,r in pairs(H.menus) do
    for i=1,H.size do
      local e=r[i]
      if e and not e[1]:match("^section_") then old[e[1]]=true end
    end
  end
  for name,row in pairs(live) do
    local path=assert(H.path(name,live),"orphan row: "..name)
    local visible,map=H.compact(row)
    assert(#visible==#map and #visible<=10)
    if name~="home" then
      assert(visible[1][1]=="back",name)
      local clone={unpack(path)}
      H.choose(clone,map[1],live)
      assert(#clone==#path-1 and clone[#clone]==path[#path-1],name)
    end
    local ids={}
    for i=1,10 do
      local e=row[i]
      if e then assert(not ids[e[1]],name.."/"..e[1]); ids[e[1]]=true end
    end
    for i=1,#visible do
      local id,icon=visible[i][1],visible[i][3]
      new[id]=true
      local f=assert(io.open("mods/luanttd_core/textures/"..icon,"rb"),id)
      local bytes=f:read("*a"); f:close()
      assert(not images[bytes] or images[bytes]==id,id.." aliases "..tostring(images[bytes]))
      assert(not semantic[id] or semantic[id]==icon,id)
      semantic[id],images[bytes]=icon,id
    end
  end
  for id in pairs(old) do
    assert(new[id] or id=="inspect","previously available action lost: "..id)
  end
  local r=live.roads
  assert(find(r,"road") and find(r,"road_station") and find(r,"road_depot") and find(r,"service_depot"))
  assert(table.concat(H.path("road_spans",live),"/")=="home/roads/road_spans")
  if features then
    for _,mode in ipairs({"roads","railworks","tramway","harbor","airfields"}) do
      assert(#H.path(mode,live)==2,mode.." is not a peer")
    end
    assert(find(live.railworks,"rail_autotrack") and find(live.railworks,"rail_platform"))
    assert(find(live.railworks,"service_depot") and find(live.harbor,"service_depot"))
    assert(find(live.airfields,"service_hangar") and find(live.road_stops,"road_stop_remove"))
    assert(find(live.harbor,"ship_dock") and find(live.harbor,"ship_depot"))
    assert(find(live.waterworks,"ship_remove"))
  end
end end
print("PASS task-oriented hotbar: all mounted tool IDs retained, direct modal launchers, distinct image bytes, exact row length and Back routes")
