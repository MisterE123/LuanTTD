-- Follow one real cell of the production weather field through dry, storm
-- and clearing phases in a native client. Only the clock is accelerated.
local function check_weather()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,check_weather);return
  end
  local F=dofile(mod.."/ambient_weather_field.lua")
  local Wind=dofile(mod.."/ambient_wind.lua")
  local home=p:get_pos()
  local seed=weather_options.seed()
  local st=assert(OwnerCheckpoint.read())
  local function land(x,z)
    local id=Sim.id(math.floor(x/2),math.floor(z/2))
    local t=id and st.tiles[id]
    return t and t.terrain~="water" and not t.stock_void and
      (1+(t.h or 0)*.3+(t.wood and .5 or 0)) or 0
  end
  local target,t0,quality
  for t=70,1850,1 do
    local cells=F.cells(home.x,home.z,t,Wind.prevailing,seed)
    for i=1,math.min(#cells,3) do
      local c=cells[i]
      if c.kind=="storm" and c.time>=22 and c.time<24 and c.dist>=42 and c.dist<72 then
        local a,b=F.wind(t,Wind.prevailing)
        local u,v=F.wind(t+51,Wind.prevailing)
        local sx,sz=c.x+u-a,c.z+v-b
        local score=land(sx,sz)*2+land(sx-14,sz+4)+land(sx+14,sz-4)+
          land(sx-28,sz+18)+land(c.x,c.z)*.65
        if not quality or score>quality then target,t0,quality=c,t,score end
      end
    end
  end
  assert(target,"No authentic developing weather cell near generated world")
  local function center(t)
    local x,z=F.wind(t,Wind.prevailing)
    local a,b=F.wind(t0,Wind.prevailing)
    return {x=target.x+x-a,z=target.z+z-b}
  end
  local function nearest(kind,at,range)
    local best,d
    for _,o in ipairs(core.get_objects_inside_radius(p:get_pos(),140)) do
      local e=o:get_luaentity()
      if e and e.name=="luanttd_core:voxel_cloud" then
        local prop=o:get_properties()
        assert(prop.visual=="mesh" and prop.use_texture_alpha and not prop.pointable and not prop.physical)
        assert(o:get_observers().SteelReview)
        if prop.mesh=="bl_voxel_cloud_"..kind..".obj" then
          local q=o:get_pos()
          local dist=(q.x-at.x)^2+(q.z-at.z)^2
          if dist<(range or 24)^2 and (not d or dist<d) then best,d=o,dist end
        end
      end
    end
    return best
  end
  local function aim(at)
    local me=p:get_pos()
    local dx,dy,dz=at.x-me.x,at.y-me.y-1.47,at.z-me.z
    p:set_look_horizontal(math.atan2(-dx,dz))
    p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  end
  local function scenic(target,far)
    local d=far or 35
    p:set_pos({x=target.x-d,y=target.y-1,z=target.z+d*.56})
    aim({x=target.x,y=target.y+1,z=target.z})
  end
  local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end
  qa_weather_clock=t0
  core.register_globalstep(function(dt) if qa_weather_clock then qa_weather_clock=qa_weather_clock+dt end end)
  core.after(4,function()
    local focus=center(qa_weather_clock)
    local deck=assert(nearest("bank",focus,5),"No dry cloud")
    assert(not nearest("column",focus,21),"Dry cloud spawned with a storm column")
    local before=deck:get_pos()
    aim(before)
    core.log("action","NATIVE VOXEL STORM FRONT")
    core.after(1.7,function()
      qa_weather_clock=t0+49
      local here=center(qa_weather_clock)
      scenic({x=here.x,y=before.y+1,z=here.z},38)
      core.after(3.3,function()
        local at=center(qa_weather_clock)
        assert(nearest("bank",at,8)==deck and deck:get_pos().x-before.x>27)
        assert(nearest("column",at,17),"Cloud never became a native storm")
        aim(deck:get_pos())
        core.log("action","NATIVE VOXEL STORM SIDE")
        core.after(1.8,function()
          local w=center(qa_weather_clock)
          p:set_pos({x=w.x,y=deck:get_pos().y,z=w.z})
          core.after(2.8,function()
            assert(deck:get_pos() and distance(deck:get_pos(),center(qa_weather_clock))>7,"Building camera failed to push cloud")
            assert(api.cinematic.toggle(p))
            local k=center(qa_weather_clock)
            p:set_pos({x=k.x,y=deck:get_pos().y,z=k.z})
            core.after(4.2,function()
              assert(deck:get_pos() and distance(deck:get_pos(),center(qa_weather_clock))<5,"Spectator wrongly pushed or removed cloud")
              qa_weather_clock=t0+129
              local next_=center(qa_weather_clock)
              scenic({x=next_.x,y=before.y,z=next_.z},40)
              core.after(3.6,function()
                local tail=center(qa_weather_clock)
                assert(nearest("bank",tail,9)==deck,"Storm should return to its parent cloud")
                assert(not nearest("column",tail,15),"Dissipated storm still has a tower")
                aim(deck:get_pos())
                core.log("action","NATIVE VOXEL STORM AFTER")
                core.after(1.6,function()
                  api.wildlife.toggle(p)
                  core.after(.9,function()
                    assert(not deck:get_pos(),"Eye Candy opt-out should remove weather")
                    core.log("action","PASS NATIVE VOXEL STORM: dry cloud grows, drifts, clears builder, stays for spectator, dissipates and toggles off")
                  end)
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end
core.after(.2,check_weather)
