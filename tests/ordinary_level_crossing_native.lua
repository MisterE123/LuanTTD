-- Appended to the isolated real Luanti mod by the ordinary crossing fixture.
-- Invoke the normal registered Road tool's UI selection/preview/build callback,
-- not the dedicated Crossing tool, on the user's reported missing half.
local function test_ordinary_road()
  local owner="Normal Road QA"
  local player={get_player_name=function()return owner end}
  local from=Sim.id(11,12)
  local approach=Sim.id(13,12)
  local cross=Sim.id(14,12)
  local c=Sim.company(S,owner)
  assert(api.crossing_tools and core.registered_items["luanttd_core:menu_road"])
  local built,why=Sim.build(S,owner,"road",Sim.line(from,approach))
  assert(built,why)
  assert(Sim.road_bits(S,approach)==8 and not Sim.road_connected(S,approach,2))
  local track=assert(api.rail_build.quote_track(owner,cross,cross,Track.Y,false))
  assert(api.rail_build.build(owner,track))
  local planted=assert(api.crossing_quote(owner,cross,{kind="road",pieces=10}))
  assert(api.crossing_commit(owner,planted))
  local record=S.tiles[cross].level_crossing
  local orig=core.serialize(record)
  local money,expense=c.cash,c.expense
  ui.select_tool(player,"road")
  ui.build_world(player,approach) -- click a normal Road drag start
  local ids,okay,hint=ui.preview(player,cross)
  assert(okay and #ids==2 and hint:find("63",1,true),hint)
  ui.build_world(player,cross)
  assert(Sim.road_bits(S,approach)==10 and Sim.road_connected(S,approach,2))
  assert(S.tiles[cross].level_crossing==record and core.serialize(record)==orig)
  assert(money-c.cash==63 and c.expense-expense==63)
  local node=core.get_node({x=28,y=record.top+1,z=24}).name
  assert(node=="luanttd_core:level_crossing_1_open",node)
  core.log("action","ORDINARY_LEVEL_CROSSING_UI_PASS adjacent missing half $63; crossing unchanged")
  core.request_shutdown("Ordinary Road serves the existing crossing",false,0)
end
core.after(0,function()
  core.emerge_area({x=20,y=0,z=20},{x=32,y=3,z=26},function(_,_,left)
    if left==0 then core.after(0,test_ordinary_road) end
  end)
end)
