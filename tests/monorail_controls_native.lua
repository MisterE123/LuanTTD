-- Input-only graphical QA. Lua only aims the camera and observes the save;
-- every menu and construction event must be produced by a native pointer.
local function start(p)
  local function say(s) core.log("action","MONO_UI_"..s) end
  local function slot(key,stage)
    for i=1,12 do
      if p:get_inventory():get_stack("main",i):get_name()=="luanttd_core:menu_"..key then
        say(stage.." "..i);return
      end
    end
    error("No visible slot for "..key.." in "..tostring(world.menu(p)))
  end
  local bx,bz,base
  for z=5,Sim.H-4 do
    for x=4,Sim.W-13 do
      local yes,level=true,nil
      for u=x,x+11 do
        local id=Sim.id(u,z)
        local t=S.tiles[id]
        local slope,h=api.terrain.tile(id)
        if slope~=0 or level and h~=level or not t or t.terrain=="water" or t.stock_void or t.wood or
            t.owner or t.house or t.site or t.build or t.stock_industry or t.stock_landmark then yes=false;break end
        level=h
      end
      if yes then bx,bz,base=x,z,level;break end
    end
    if bx then break end
  end
  assert(bx,"Fresh generated terrain lacks a flat 12-tile strip")
  local function id(dx) return Sim.id(bx+dx,bz) end
  local function aim(tile)
    local x,z=Sim.xy(tile)
    local pitch=1.15
    local distance=(6+p:get_properties().eye_height-.5)/math.tan(pitch)
    p:set_pos({x=x*2+.5,y=base+6,z=z*2+.5-distance})
    p:set_look_horizontal(0);p:set_look_vertical(pitch)
  end
  local phases={
    {"home","section_railworks","HOME"},{"railworks","section_railops","RAILWORKS"},
    {"railops","section_railengineering","OPS"},{"railengineering","section_railtypes","ENG"},
    {"railtypes","rail_select_monorail","TYPE"},{"railtypes","back","TYPE_BACK"},
    {"railengineering","back","ENG_BACK"},{"railops","back","OPS_BACK"},
    {"railworks","rail_autotrack","TRACK"},
  }
  local phase=1
  local deadline=core.get_us_time()+120000000
  aim(id(1))
  local function target(tile,next_phase)
    phase="aiming"
    aim(tile)
    core.after(.45,function() phase=next_phase end)
  end
  local function placed(from,finish,station)
    local d=OwnerCheckpoint.read()
    if not d then return false end
    for x=from,finish do
      local t=d.tiles[id(x)]
      if t.rail_type~=2 or t.rail_tracks~=1 or station and not t.rail_station_id then return false end
    end
    return true
  end
  local show=core.show_formspec
  local form
  core.show_formspec=function(n,name,description)
    if n==p:get_player_name() then form=description end
    return show(n,name,description)
  end
  local function step()
    assert(core.get_us_time()<deadline,"input QA timed out: "..tostring(phase))
    local at=world.target(p)
    local menu=world.menu(p)
    local item=p:get_wielded_item():get_name()
    local ctrl=p:get_player_control()
    local _,status=ui.world_status(p,at)
    if type(phase)=="number" then
      local now=phases[phase]
      if menu==now[1] and (phase~=1 or at==id(1)) and
          (phase~=6 or status and status:find("Monorail selected",1,true)) then
        slot(now[2],now[3]);phase=phase==#phases and "track_press" or phase+1
      end
    elseif phase=="track_press" and item:find("rail_autotrack",1,true) and ctrl.dig and ui.anchor(p)==id(1) then
      aim(id(11));phase="track_ghost"
    elseif phase=="track_ghost" and at==id(11) and ctrl.dig then
      local ghost=ui.rail_overlay(p,at)
      if ghost and #ghost>=10 then
        for _,q in ipairs(ghost) do assert(q.result_railtype==2) end
        say("TRACK_GHOST");phase="track_done"
      end
    elseif phase=="track_done" and placed(1,11,false) then
      say("TRACK_BUILT");target(id(0),"depot")
    elseif phase=="depot" and at==id(0) then
      slot("rail_depot_tool","DEPOT");phase="depot_done"
    elseif phase=="depot_done" then
      local d=OwnerCheckpoint.read()
      if d and d.tiles[id(0)].rail_type==2 and d.tiles[id(0)].rail_depot_dir==2 then
        say("DEPOT_BUILT");target(id(2),"one")
      end
    elseif phase=="one" and at==id(2) then
      slot("rail_platform","STATION_ONE");phase="one_drag"
    elseif phase=="one_drag" and ctrl.dig and ui.anchor(p)==id(2) then
      aim(id(3));say("STATION_ONE_AIM");phase="one_done"
    elseif phase=="one_done" and placed(2,3,true) then
      say("STATION_ONE_BUILT");target(id(8),"two")
    elseif phase=="two" and at==id(8) then
      slot("rail_platform","STATION_TWO");phase="two_drag"
    elseif phase=="two_drag" and ctrl.dig and ui.anchor(p)==id(8) then
      aim(id(10));say("STATION_TWO_AIM");phase="two_done"
    elseif phase=="two_done" and placed(8,10,true) then
      say("STATION_TWO_BUILT");target(id(0),"inspect")
    elseif phase=="inspect" and at==id(0) and api.render.host_tile(id(0)) and
        api.render.host_tile(id(0)).rail_depot_dir==2 then
      slot("rail_autotrack","DEPOT_FOCUS");phase="open"
    elseif phase=="open" and form and (form:find("Assemble",1,true) or form:find("X2001",1,true)) then
      say("DEPOT_OPEN");phase="assembly"
    elseif phase=="assembly" and form and form:find("X2001",1,true)
        and form:find("Passenger Carriage",1,true) and form:find("Mail Van",1,true) then
      say("ASSEMBLY");phase="bought"
    elseif phase=="bought" then
      local d=OwnerCheckpoint.read()
      for _,u in pairs(d and d.stock_rail_fleet and d.stock_rail_fleet.units or {}) do
        if u.depot==id(0) and #u.stock_ids==3 and u.stock_ids[1]==54 and u.stock_ids[2]==57 and u.stock_ids[3]==58 then
          say("BOUGHT");phase="running";break
        end
      end
    elseif phase=="running" then
      local d=OwnerCheckpoint.read()
      for _,r in ipairs(d and d.stock_rail_dispatch and d.stock_rail_dispatch.runs or {}) do
        if r.stock_engine==54 and r.engine_railtype==2 and r.phase~="depot" then
          assert(r.shuttle.first~=r.shuttle.second)
          say("PASS: native hotbar and pointer built the guideway, depot and both platforms, bought the physical consist and dispatched it")
          return
        end
      end
    end
    core.after(.075,step)
  end
  core.after(.4,step)
end
local function ready()
  local p=core.get_player_by_name("MonoQA")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then start(p)
  else core.after(.2,ready) end
end
core.after(.3,ready)
