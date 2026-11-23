-- Appended only to a disposable ordinary worker-backed world. The player is
-- aimed at a verified open tile; real hotbar input drives the entire test.
local function survey_probe()
  local p=core.get_player_by_name("SurveyReview")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,survey_probe);return
  end
  local tile,x,z,h
  for v=8,Sim.H-8 do
    for u=8,Sim.W-8 do
      local id=Sim.id(u,v)
      local t=S.tiles[id]
      local slope,level=api.terrain.tile(id)
      if slope==0 and t.terrain~="water" and not (t.site or t.house or t.wood or t.build or t.stock_industry or
          t.stock_landmark or t.stock_void or t.stock_canal or t.airfield or t.rail_tracks or t.ship) then
        tile,x,z,h=id,u*2+.50,v*2+.50,level;break
      end
    end
    if tile then break end
  end
  assert(tile,"The generated Survey fixture needs one dry open tile")
  p:set_look_horizontal(0)
  p:set_look_vertical(math.pi/2)
  p:set_pos({x=x,y=h+7,z=z})
  local pending,deadline,builder=0,core.get_us_time()+30000000,nil
  local expected={"back","teleport_tile","inspect","jump","workbench_index","survey_walk","survey_drive_car",
    "survey_fly_plane","survey_train_cab","survey_ride_vehicle"}
  local function step()
    assert(core.get_us_time()<deadline,"Native survey timed out at step "..pending)
    local mode=world.avatar_state(p)
    if pending==0 and world.target(p)==tile then
      assert(world.menu(p)=="home")
      core.log("action","SURVEY_NATIVE_READY")
      pending=1
    elseif pending==1 and world.menu(p)=="survey" then
      assert(#world.hotbar_layout(p)==#expected)
      for i,id in ipairs(expected) do
        assert(p:get_inventory():get_stack("main",i):get_name()=="luanttd_core:menu_"..id,id)
      end
      core.log("action","SURVEY_NATIVE_OPEN")
      pending=2
    elseif pending==2 and mode and mode.mode=="walk" then
      local at=p:get_pos()
      assert((at.x-x)^2+(at.z-z)^2<.015 and math.abs(at.y-h-.545)<.08)
      assert(not p:hud_get_flags().hotbar and p:get_properties().mesh=="bl_street_pedestrian.glb")
      builder=assert(mode.saved)
      core.log("action","SURVEY_NATIVE_WALKING")
      pending=3
    elseif pending==3 and not mode then
      local at=p:get_pos()
      assert(world.menu(p)=="survey" and p:hud_get_flags().hotbar)
      local old=builder.pos
      -- Wait for the client's first post-teleport position report; its
      -- last street position may still be queued in the outgoing stream.
      if (at.x-old.x)^2+(at.y-old.y)^2+(at.z-old.z)^2<.05^2 then
        assert(math.abs(p:get_look_vertical()-builder.pitch)<.025)
        assert(#world.hotbar_layout(p)==#expected)
        core.log("action","PASS NATIVE SURVEY: clicked Survey, selected Walk, landed on aimed terrain, right-click restored original view/menu")
        return
      end
    end
    core.after(.07,step)
  end
  core.after(.35,step)
end
core.after(.3,survey_probe)
