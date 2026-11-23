-- This render fixture exercises both light states without simulating a
-- full year. The real worker-driven seasonal phase has its own native
-- daylight/reopen test; here only the engine's visual time is pinned.
local set_visual_time=core.set_timeofday
local visual_time
core.set_timeofday=function(t) return set_visual_time(visual_time or t) end
local function now(t)
  visual_time=t
  set_visual_time(t)
end
local function lighthouse_beam_native()
  local p=core.get_player_by_name("LighthouseBeamQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,lighthouse_beam_native);return
  end
  local disk=assert(OwnerCheckpoint.read())
  local x,z,h
  for id,t in ipairs(disk.tiles) do
    if t.stock_landmark and t.stock_landmark.kind=="lighthouse" then
      x,z=Sim.xy(id);h=t.h;break
    end
  end
  assert(x,"Test seed had no OpenTTD lighthouse")
  local base={x=2*x,y=h+1,z=2*z}
  local optic={x=base.x+.755,y=h+1.849,z=base.z+.525}
  local name="luanttd_core:lighthouse_beam"
  local function visible()
    local count,found=0,nil
    for _,ref in ipairs(core.get_objects_inside_radius(optic,.025)) do
      local e=ref:get_luaentity()
      if e and e.name==name then count=count+1;found=ref end
    end
    assert(count<=1,"Lighthouse has duplicate optics")
    return found
  end
  local function aim()
    p:set_pos({x=optic.x,y=optic.y+10.8,z=optic.z-6})
    p:set_look_horizontal(0);p:set_look_vertical(1.12)
  end
  local function poll(test,cb,fail,i)
    if test() then cb()
    elseif i<80 then core.after(.2,function()poll(test,cb,fail,i+1)end)
    else error(fail) end
  end
  now(.5)
  aim()
  poll(function() return core.get_node(base).name=="luanttd_core:stock_lighthouse" end,function()
    assert(not visible(),"Lighthouse beam ran under full sun")
    core.log("action","LIGHTHOUSE_BEAM_DAY native stock lighthouse is painted, optics are off")
    core.after(3,function()
      now(.96)
      poll(visible,function()
        local original=visible()
        local properties=original:get_properties()
        assert(properties.mesh=="bl_lighthouse_beam.obj" and properties.use_texture_alpha and
          properties.visual_size.x==10 and properties.automatic_rotate>.17 and properties.automatic_rotate<.22 and not properties.static_save)
        core.log("action","LIGHTHOUSE_BEAM_NIGHT lantern-mounted alpha optics rotating natively")
        core.after(4.4,function()
          assert(visible()==original,"Next close observation recreated the beam")
          p:set_pos({x=optic.x,y=optic.y+64,z=optic.z})
          poll(function()return not visible()end,function()
            aim()
            poll(visible,function()
              now(.5)
              poll(function()return not visible()end,function()
                core.log("action","PASS NATIVE LIGHTHOUSE BEAM: night rotation; flight-distance cutoff; return; daylight switch-off")
              end,"Beam survived sunrise",1)
            end,"Beam did not return to nighttime lantern",1)
          end,"Distant flight did not despawn the beam",1)
        end)
      end,"Stock lantern never received its nighttime optic",1)
    end)
  end,"Stock lighthouse terrain never materialized",1)
end
core.after(.2,lighthouse_beam_native)
