-- Appended only in isolated native QA. No LuanTTD settings, true generated
-- terrain, and normal placement/order callbacks (no development commands).
-- Advance this one test's real tram clock explicitly. A headless
-- server globalstep before the emergence callback is otherwise enough
-- to move it off the persisted stop on some runners.
local step_tram=assert(api.tram_clock)
api.tram_clock=function() end
local owner="Default Tram QA"
local player={get_player_name=function() return owner end}
local function id(x,z) return assert(Sim.id(x,z)) end
local function audit()
  assert(api.generated_world and settings:get("bayline_stock_workbenches")==nil and settings:get("bayline_tram_preview")==nil)
  assert(api.tram_tools and api.tram and api.tram_view and api.world.has_menu("tramway"))
  assert(api.road_bay_tools and api.world.has_menu("road_stops") and Sim.road_stock_service_active(S))
  for _,tool in ipairs({"tram_order","tram_clear","tram_track","tram_stop","tram_depot","tram_bit"}) do
    assert(core.registered_tools["luanttd_core:menu_"..tool],tool)
  end
  -- Report actual rows in the live formspec, not startup guesswork.
  local index=dofile(mod.."/workbench_index.lua")(api)
  local show,text=core.show_formspec
  core.show_formspec=function(_,form,body) assert(form==index.form);text=body end
  index.open(player)
  for _,tab in ipairs({"road","rail","airwater","scenarios","world"}) do
    index.fields(player,{["wb_tab_"..tab]=true})
    local rows=text:match("wb_rows;([^;]+);")
    if rows then core.log("action","DEFAULT_WORKBENCHES "..tab.." "..rows) end
  end
  core.show_formspec=show
end

local function clear_flat(x,z,level)
  local tile=id(x,z)
  local t=S.tiles[tile]
  local slope,base=api.terrain.tile(tile)
  return slope==0 and base==level and t.terrain~="water" and not
    (t.build or t.site or t.house or t.wood or t.ship or t.airfield or t.stock_industry or t.stock_landmark or t.stock_void)
end
local function fit(x,z)
  local _,base=api.terrain.tile(id(x,z))
  for dx=-3,-1 do if not clear_flat(x+dx,z,base) then return end end
  for dz=-3,4 do if not clear_flat(x,z+dz,base) then return end end
  return base
end
local function ground_fixture()
  for z=6,Sim.H-6 do
    for x=7,Sim.W-6 do
      local level=fit(x,z)
      if level and level>0 then return x,z,level end
    end
  end
  error("The stock default map had no legal dedicated tram layout")
end

local function native_mesh()
  local run=assert(S.tram_pilot)
  local frame=assert(run.legs[run.leg].frames[run.index])
  local x,z=Sim.xy(frame[4])
  local _,base=api.terrain.tile(frame[4])
  for _,obj in ipairs(core.get_objects_inside_radius({x=2*x+.5,y=base+.512,z=2*z+.5},2.4)) do
    local entity=obj:get_luaentity()
    if entity and entity.name=="luanttd_core:tram_preview_vehicle" then
      local props=obj:get_properties()
      assert(props.mesh=="bl_streetcar.obj" and props.textures[1]=="bl_tram_palette.png")
      return obj
    end
  end
  error("The mounted run did not render its actual tram")
end

local function main(x,z,level)
  local depot,a,b=id(x-3,z),id(x,z-2),id(x,z+3)
  local function select_(tool) ui.select_tool(player,tool) end
  local function click(tile)
    local _,ok,why=ui.preview(player,tile)
    assert(ok,why)
    ui.build_world(player,tile)
  end
  local function drag(first,last)
    local function hit(tile)
      local a,b=Sim.xy(tile)
      return {x=a*2+.5,z=b*2+.5}
    end
    assert(ui.begin_autoroad(player,first,hit(first)))
    ui.end_autoroad(player,last,hit(last))
  end
  local function advance(arrival)
    api.interest.refresh({{get_pos=function() return {x=2*x,z=2*z} end}})
    for _=1,400 do
      step_tram(.25)
      api.tram_view.step(.25,true)
      if S.tram_pilot.arrivals>=arrival then return end
    end
    error("The streetcar did not finish its next leg")
  end

  if S.default_tram_qa then
    local saved=S.default_tram_qa
    local run=assert(S.tram_pilot)
    assert(run.arrivals==1 and run.steps==saved.steps and run.phase=="stopped")
    assert(run.legs[run.leg].target==a and S.companies[owner].cash==saved.cash)
    advance(2)
    assert(run.legs[run.leg].target==b and run.steps>saved.steps)
    local ref=native_mesh()
    assert(ui.guide(player,"tramway"):find("2 stop visits",1,true))
    assert(not api.tram.clear("Other"))
    ui.clear_tram_run(player)
    api.tram_view.step(0,true)
    assert(S.tram_pilot==nil and not ref:get_pos())
    assert(S.tiles[depot].tram.kind=="depot" and S.tiles[a].tram.kind=="drive_stop" and S.tiles[b].tram.kind=="drive_stop")
    assert(S.companies[owner].paid_units==0 and S.companies[owner].revenue==0)
    core.log("action",("DEFAULT_TRAM_NATIVE_PASS (%d,%d) two actual 3D stop visits; resumed SQLite; Clear kept all facilities"):format(x,z))
    core.request_shutdown("Default tram order and save/reload passed",false,0)
    return
  end
  local c=Sim.company(S,owner)
  -- Establish whether the ordinary station tool, unlike the separate lab
  -- survey, needs pre-built rail. A single stand-alone flat tile does not.
  local rx,rz
  for i=6,Sim.W-6 do
    for j=6,Sim.H-6 do
      if (math.abs(i-x)>5 or math.abs(j-z)>6) and clear_flat(i,j,select(2,api.terrain.tile(id(i,j)))) then
        rx,rz=i,j;break
      end
    end
    if rx then break end
  end
  local plat=id(rx,rz)
  assert(not S.tiles[plat].rail_tracks)
  select_("rail_platform");click(plat);click(plat)
  assert(S.tiles[plat].rail_station_id and S.tiles[plat].rail_tracks==1,"No direct platform placement")
  core.log("action","DEFAULT_RAIL_STATION_DIRECT_PASS Rail Station placed from the actual workshop on clean terrain")

  select_("tram_depot");click(depot)
  assert(S.tiles[depot].tram and S.tiles[depot].tram.kind=="depot")
  select_("tram_track");drag(id(x-2,z),id(x,z))
  assert(S.tiles[id(x-2,z)].tram.tram_bits==10)
  select_("tram_track");drag(id(x,z-3),id(x,z+4))
  select_("tram_stop");ui.rotate_tram(player);click(a);click(b)
  for _,tile in ipairs({a,b}) do assert(S.tiles[tile].tram.kind=="drive_stop") end

  -- Test that a partial order can be canceled, a duplicate stop is refused,
  -- and a subsequent correct order uses normal world callbacks.
  select_("tram_order")
  assert(not select(2,ui.preview(player,a)))
  click(depot);click(a)
  assert(not select(2,ui.preview(player,a)) and not S.tram_pilot)
  assert(ui.cancel_build_selection(player) and not ui.anchor(player))
  click(depot);click(a);click(b)
  assert(S.tram_pilot and S.tram_pilot.owner==owner and not ui.anchor(player))
  assert(c.revenue==0 and c.paid_units==0)
  advance(1)
  assert(S.tram_pilot.legs[S.tram_pilot.leg].target==a)
  native_mesh()
  S.default_tram_qa={x=x,z=z,h=level,steps=S.tram_pilot.steps,cash=c.cash}
  api.save()
  core.log("action","DEFAULT_TRAM_NATIVE_SAVED first exact stop, owned depot and streetcar")
  core.request_shutdown("Saved the default streetcar on its first stop",false,0)
end

core.after(0,function()
  audit()
  local saved=S.default_tram_qa
  local x,z,level
  if saved then x,z,level=saved.x,saved.z,saved.h else x,z,level=ground_fixture() end
  core.emerge_area({x=2*x-9,y=level-1,z=2*z-8},{x=2*x+4,y=level+5,z=2*z+10},
    function(_,_,remaining)
      if remaining==0 then core.after(0,main,x,z,level) end
    end)
end)
-- This probe is appended to the only game mod, inside a clean native server.
assert(core.get_current_modname()=="luanttd_core")
for _,registry in ipairs({core.registered_items,core.registered_entities}) do
  for name in pairs(registry) do
    -- Engine entries include both bare names and __builtin:falling_node.
    assert(not name:find(":",1,true) or name:match("^__builtin:") or name:match("^luanttd_core:"),
      "unexpected game content namespace: "..name)
  end
end
assert(core.registered_nodes["luanttd_core:bedrock"])
