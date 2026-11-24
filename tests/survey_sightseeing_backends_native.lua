-- Genuine Survey inventory and pointer gestures, on a real road and Country
-- Airport built by the ordinary worker. The fixture only aims the builder or a walker and
-- reads observations; it never substitutes a mode backend or triggers clicks.
local function start(p)
  local player=p:get_player_name()
  local function xy(x,z) return assert(Sim.id(x,z)) end
  local x,z,h
  for v=8,Sim.H-12 do
    for u=8,Sim.W-12 do
      local level,free=nil,true
      for dz=0,5 do for dx=-1,5 do
        local id=xy(u+dx,v+dz)
        local slope,datum=api.terrain.tile(id)
        local t=S.tiles[id]
        if slope~=0 or level and datum~=level or t.terrain=="water" or t.wood or t.house or t.site or
           t.owner or t.build or t.stock_industry or t.stock_landmark or t.stock_void then free=false end
        level=datum
      end end
      if free then x,z,h=u,v,level;break end
    end
    if x then break end
  end
  assert(x,"Survey fixture needs six flat empty rows around a Country Airport")
  local road,grass,airport=xy(x+2,z+4),xy(x+2,z+3),xy(x,z)
  local function ask(q,cb)
    q.player=player
    local ok,why=authority.query(q,function(r)
      assert(r.ok,q.kind..": "..tostring(r.why or r.value));cb(r)
    end)
    assert(ok,why)
  end
  local function stage(name) core.log("action","SURVEY_BACKENDS_"..name) end
  local initial,saved,walk_saved
  local phase="ready"
  local deadline=core.get_us_time()+105000000
  local function aim(tile,theta)
    local a,b=Sim.xy(tile)
    local pitch=1.16
    local eye=p:get_properties().eye_height
    local dist=(7+eye-.5)/math.tan(pitch)
    p:set_look_horizontal(theta);p:set_look_vertical(pitch)
    p:set_pos({x=a*2+.55+dist*math.sin(theta),y=h+7,z=b*2+.55-dist*math.cos(theta)})
  end
  local function snap_builder()
    assert(world.menu(p)=="survey" and p:hud_get_flags().hotbar)
    return {pos=p:get_pos(),yaw=p:get_look_horizontal(),pitch=p:get_look_vertical(),
      gravity=p:get_physics_override().gravity,height=p:get_properties().eye_height}
  end
  local function nearby(a,b,r)
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<r*r
  end
  local function yaw_dist(a,b) return math.abs((a-b+math.pi)%(2*math.pi)-math.pi) end
  local function restored()
    if world.avatar_state(p) or not nearby(p:get_pos(),saved.pos,.065) then return false end
    assert(not p:get_attach() and world.menu(p)=="survey" and p:hud_get_flags().hotbar and p:hud_get_flags().crosshair)
    assert(yaw_dist(p:get_look_horizontal(),saved.yaw)<.025 and math.abs(p:get_look_vertical()-saved.pitch)<.025,
      "Sighting restored position but not camera rotation")
    assert(math.abs(p:get_properties().eye_height-saved.height)<.001 and p:get_physics_override().gravity==saved.gravity,
      "Sighting failed to restore builder optics/physics")
    return true
  end
  local function phase_aim(tile,theta,next_phase)
    aim(tile,theta)
    -- Let the native player's outgoing state settle after a fixture
    -- teleport before arming the next test. This is not a game delay.
    core.after(.40,function() phase=next_phase end)
  end
  local function visible_help(title,instruction)
    local heading,help=false,false
    for _,line in pairs(p:hud_get_all()) do
      local text=line.text or ""
      heading=heading or text:find(title,1,true)
      help=help or text:find(instruction,1,true)
    end
    return heading and help
  end
  local function mounted(model)
    local ob=assert(p:get_attach())
    local props=ob:get_properties()
    assert(props.mesh==model and not p:hud_get_flags().hotbar and not p:hud_get_flags().crosshair)
    local viewers=ob:get_observers()
    assert(viewers and viewers[player],"Cockpit is not privately visible")
    return ob:get_pos()
  end
  local function step()
    assert(core.get_us_time()<deadline,"Timed out resolving Survey action: "..phase)
    local tile=world.target(p)
    local avatar=world.avatar_state(p)
    local _,status=ui.world_status(p,tile)
    if phase=="ready" and tile==grass then
      assert(world.menu(p)=="home")
      stage("READY")
      phase="opening"
    elseif phase=="opening" and world.menu(p)=="survey" then
      assert(p:get_inventory():get_stack("main",7):get_name()=="luanttd_core:menu_survey_drive_car")
      for i=1,#world.hotbar_layout(p) do
        local name=p:get_inventory():get_stack("main",i):get_name()
        assert(not name:find("survey_fly_plane",1,true) and not name:find("survey_ride_vehicle",1,true))
      end
      stage("OPEN")
      phase="car_selected"
    elseif phase=="car_selected" and p:get_wield_index()==7 and
        visible_help("Drive Car","Left-click a connected street to drive") then
      stage("CAR_SELECTED")
      phase="car_bad"
    elseif phase=="car_bad" and status and status:find("Aim at a connected road",1,true) then
      assert(tile==grass and not avatar and not p:get_attach())
      phase="aiming"
      phase_aim(road,-1.12,"car_good")
    elseif phase=="car_good" then
      if avatar and avatar.mode=="car" then
        assert(saved,"No prior pose near road")
        initial=mounted("bl_sightseeing_car_interior.obj")
        assert(nearby(initial,{x=(x+2)*2+.5,y=h+.60,z=(z+4)*2+.5},.68),
          "Car attached away from the selected segment")
        stage("CAR_ENTER")
        phase="car_drive"
      elseif tile==road and not saved then
        saved=snap_builder()
        stage("CAR_REJECT")
      end
    elseif phase=="car_drive" then
      if not nearby(mounted("bl_sightseeing_car_interior.obj"),initial,.75) then
        stage("CAR_MOVED")
        phase="car_leave"
      end
    elseif phase=="car_leave" and restored() then
      assert(p:get_wield_index()==7,"Drive Car slot lost after restore")
      phase="aiming"
      phase_aim(grass,-1.12,"walk_select")
    elseif phase=="walk_select" and tile==grass then
      saved=snap_builder()
      stage("CAR_RESTORE")
      phase="walk_to_hangar"
    elseif phase=="walk_to_hangar" and avatar and avatar.mode=="walk" then
      stage("WALK_ENTER")
      phase="settling_walk"
      local door={x=2*(x+3)+.945,y=h+.51,z=z*2+2.53}
      core.after(.46,function()
        assert(world.avatar_state(p)==avatar)
        p:set_look_horizontal(math.pi);p:set_look_vertical(.07);p:set_pos(door)
        phase="waiting_for_hangar"
      end)
    elseif phase=="waiting_for_hangar" and api.render.pick_sightseeing_hangar(p)==xy(x+3,z) then
      assert(avatar and avatar.mode=="walk" and p:get_properties().zoom_fov>0)
      walk_saved=p:get_pos()
      stage("HANGAR_AIMED")
      phase="plane_good"
    elseif phase=="plane_good" and avatar and avatar.mode=="plane" then
      assert(saved and avatar.previous and avatar.previous.mode=="walk")
      initial=mounted("bl_sightseeing_plane_cockpit.obj")
      assert(nearby(initial,{x=x*2+4,y=h+.95,z=z*2+4},4),
        "Plane attached away from the clicked Country Airport")
      stage("PLANE_ENTER")
      phase="plane_roll"
    elseif phase=="plane_roll" then
      local at=mounted("bl_sightseeing_plane_cockpit.obj")
      if at.y>initial.y+1.25 and not nearby(at,initial,2) then
        stage("PLANE_AIRBORNE")
        phase="plane_leave"
      end
    elseif phase=="plane_leave" and avatar and avatar.mode=="walk" and not p:get_attach() then
      if nearby(p:get_pos(),walk_saved,.16) then
        assert(not p:hud_get_flags().hotbar and p:get_properties().zoom_fov>0)
        stage("WALK_RESTORED")
        phase="walk_leave"
      end
    elseif phase=="walk_leave" and restored() then
      core.log("action","PASS NATIVE SURVEY BACKENDS: drove a real car, clicked a hangar aircraft from Walk, took off, and returned to Walk and Builder through Inventory")
      return
    end
    core.after(.074,step)
  end
  ask({kind="company"},function(company)
    ask({kind="command",command={kind="road_build",revision=company.revision,first=xy(x-1,z+4),last=xy(x+5,z+4)}},function()
      ask({kind="transport_quote",request={mode="air",operation="build",layout="country",tile=airport}},function(q)
        assert(#q.value.tiles==12,"Fixture didn't receive a stock Country Airport quote")
        ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},function(c)
          local disk=assert(OwnerCheckpoint.read())
          assert(disk.stock_small_airports[c.value.id] and disk.tiles[road].build=="road")
          aim(grass,-.4)
          local function ready()
            assert(core.get_us_time()<deadline,"No worker road or airport data in projection")
            local a,b=api.render.host_tile(road),api.render.host_tile(airport)
            if not (a and a.build=="road" and b and b.airfield) then core.after(.12,ready);return end
            step()
          end
          core.after(.45,ready)
        end)
      end)
    end)
  end)
end
local function begin()
  local p=core.get_player_by_name("SurveyReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then start(p)
  else core.after(.2,begin) end
end
core.after(.3,begin)
