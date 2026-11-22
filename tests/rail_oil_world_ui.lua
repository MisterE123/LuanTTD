local forms,save_count,updates,calls=nil,0,0,0
core={
  formspec_escape=function(s)return s end,
  show_formspec=function(name,key,markup)forms={name,key,markup} end,
}
local raw={
  [1]={id=1,owner="Alex",tiles={10}},
  [2]={id=2,owner="Alex",tiles={11}},
  [3]={id=3,owner="Alex",tiles={12},coal_role="load"},
  [4]={id=4,owner="Other",tiles={13}},
  [5]={id=5,owner="Alex",tiles={14}},
}
local tiles={[15]={owner="Alex"}}
for i,v in pairs(raw) do
  tiles[v.tiles[1]]={owner=v.owner,rail_station_id=i,rail_tracks=1}
end
local reports={[1]={sources={100},waiting=23},[2]={sources={},accepts=true,waiting=0},
  [3]={sources={102}},[4]={sources={100},accepts=true},[5]={sources={},accepts=false}}
local disabled,deny=false,false
local S={tiles=tiles,stock_rail_stations=raw}
local api={
  s=S,rail_oil_tools=true,rail_coal_tools=true,
  render={update=function(dirty) assert(#dirty==1);updates=updates+1 end},
  save=function() save_count=save_count+1 end,
  Sim={
    id=function(x,y) return x+y*32 end,
    tools={inspect={name="Inspect"}},
    rail_oil_stop_status=function(_,id) return not disabled and reports[id] or nil end,
    rail_coal_stop_status=function()error("coal preflight should reject oil stage before querying")end,
    rail_oil_designate=function(_,owner,id,role)
      calls=calls+1
      assert(owner=="Alex")
      assert(id==1 and role=="load" or id==2 and role=="unload")
      if deny then return false,"This platform is part of an active rail route." end
      raw[id].oil_role=role;reports[id].role=role
      return true,"Oil stage designated.",raw[id].tiles
    end,
  },
}
local U=dofile("mods/luanttd_core/ui.lua")(api)
local p={get_player_name=function()return "Alex" end}
local function can(id) return select(2,U.preview(p,id)) end
assert(U.is_world_tool("rail_oil_load") and U.is_world_tool("rail_oil_unload"))
U.select_tool(p,"rail_oil_load")
assert(can(10) and not can(11) and not can(12) and not can(13) and not can(15))
for _,id in ipairs({11,12,13,15}) do U.build_world(p,id) end
assert(calls==0 and updates==0 and save_count==0)
deny=true
U.build_world(p,10)
assert(calls==1 and updates==0 and save_count==0)
assert(select(2,U.world_status(p,nil,false)):find("active rail route",1,true))
deny=false
U.build_world(p,10)
assert(raw[1].oil_role=="load" and calls==2 and updates==1 and save_count==1)
assert(select(3,U.preview(p,10)):find("Already designated",1,true))
U.select_tool(p,"rail_oil_unload")
assert(not can(10) and not can(12) and not can(14) and can(11))
U.build_world(p,11)
assert(raw[2].oil_role=="unload" and calls==3 and updates==2 and save_count==2)
U.select_tool(p,"rail_coal_load")
assert(not can(10) and select(3,U.preview(p,10)):find("without an oil stage",1,true))
U.service(p,"rail_platform_state",1)
assert(forms[2]=="luanttd_core:service" and forms[3]:find("23,000 L waiting",1,true))
U.service(p,"rail_platform_state",2)
assert(forms[3]:find("Goods for road freight",1,true))
reports[2].accepts=false
U.service(p,"rail_platform_state",2)
assert(forms[3]:find("no longer accepts oil",1,true))
disabled=true;api.rail_oil_tools=false
assert(not U.is_world_tool("rail_oil_unload"))
U.service(p,"rail_platform_state",1)
assert(forms[3]:find("Rail Oil workbench paused",1,true) and raw[1].oil_role=="load")
print("PASS: Oil world tool validates catchments and ownership, redraws/saves accepted designation only, and inspects liters/Goods")
