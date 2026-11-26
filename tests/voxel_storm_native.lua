-- The native QA harness leaves the ordinary weather clock dormant until
-- a real client has entered the map and can see the mesh.
local function check_weather()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,check_weather);return
  end
  local at=p:get_pos(); at.y=at.y+5
  p:set_pos(at)
  p:set_look_horizontal(0);p:set_look_vertical(-.15)
  qa_storm_start=255
  local function parts()
    local all={}
    for _,o in ipairs(core.get_objects_inside_radius(p:get_pos(),90)) do
      local e=o:get_luaentity()
      if e and e.name=="luanttd_core:voxel_cloud" then
        local prop=o:get_properties()
        assert(prop.visual=="mesh" and not prop.pointable and not prop.physical and not prop.collide_with_objects)
        assert(o:get_observers().SteelReview)
        all[prop.mesh]=o
      end
    end
    return all
  end
  local base="bl_voxel_cloud_storm.obj"
  local feeder="bl_voxel_cloud_storm_feeder.obj"
  local anvil="bl_voxel_cloud_storm_anvil.obj"
  core.after(5.2,function()
    local first=parts()
    local cloud=assert(first[base],"missing shelf")
    assert(first[feeder] and first[anvil],"missing feeder or anvil")
    local origin=cloud:get_pos()
    local size=first[anvil]:get_properties().visual_size.x
    core.log("action","NATIVE VOXEL STORM FRONT")
    core.after(3.2,function()
      local camera={x=at.x-25,y=at.y+4,z=at.z+14}
      local focus=cloud:get_pos()
      assert(focus.x>origin.x+1)
      local later=parts()
      assert(later[base]==cloud and later[anvil]==first[anvil],"cloud volumes respawned during growth")
      assert(later[anvil]:get_properties().visual_size.x>size)
      local dx,dy,dz=focus.x-camera.x,focus.y-camera.y-1.47,focus.z-camera.z
      p:set_pos(camera)
      p:set_look_horizontal(math.atan2(-dx,dz))
      p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
      core.log("action","NATIVE VOXEL STORM SIDE")
      core.after(2.5,function()
        assert(api.wildlife.enabled(p))
        api.wildlife.toggle(p)
        core.after(.75,function()
          assert(not next(parts()),"Eye Candy opt-out should remove all volumes")
          core.log("action","PASS NATIVE VOXEL STORM: rising feeders, spreading anvil, stable advection and private opt-out")
        end)
      end)
    end)
  end)
end
core.after(.2,check_weather)
