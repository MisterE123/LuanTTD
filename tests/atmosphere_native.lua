-- Isolated actual Luanti sky, time, lighting and original terrain textures.
local world=core.get_modpath("atmosphere")
local feature=core.settings:get_bool("luanttd_daylight_feature_test",false)
local phase=.5
local phase_provider
if feature then phase_provider=function() return phase end end
local open,lighting=dofile(world.."/atmosphere.lua").start(core,phase_provider,core.get_mod_storage())
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
core.register_node("atmosphere:meadow",{tiles={"bl_grass2.png","bl_grass2.png","bl_grass_side.png"}})
core.register_node("atmosphere:rock",{tiles={"bl_hill_side.png"}})
core.register_node("atmosphere:sea",{tiles={{name="bl_water_sea_anim.png",align_style="world",scale=4,
  animation={type="vertical_frames",aspect_w=64,aspect_h=64,length=4}}},paramtype="light"})
core.register_node("atmosphere:slope_axes",{tiles={"calibration.png"}, drawtype="mesh",
  mesh="bl_land_3.obj",paramtype="light",sunlight_propagates=true})
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
core.register_alias("mapgen_river_water_source","air")
core.register_node("atmosphere:shadow_pad",{tiles={"pad.png"}})
if feature then
  for i=0,2 do
    core.register_node("atmosphere:forest"..i,{tiles={"bl_scenery_palette.png"},drawtype="mesh",
      mesh=("bl_stock_forest_%d_2.obj"):format(i),paramtype="light",sunlight_propagates=true})
  end
end
local phases={noon=.5,dusk=.749,moonrise=.825,midnight=0,shadow=.40}

local function pose(p,name)
  local x,pitch=-19,-.15
  local yaw=-math.pi/2 -- scenery and the rising moon are to the east
  if name=="midnight" then pitch=-1.05 end
  if name=="rays" then
    p:set_pos(vector.new(-20,1.4,0))
    p:set_look_horizontal(-1.25)
    p:set_look_vertical(-.44)
    return
  end
  if name=="slope" then x,pitch,yaw=0,math.pi/2,0 end
  if name=="shadow" then
    p:set_pos(vector.new(13,19,-13))
    p:set_look_horizontal(0)
    p:set_look_vertical(math.pi/2)
    return
  end
  p:set_pos(vector.new(x,name=="slope" and 10 or 5,0))
  p:set_look_horizontal(yaw)
  p:set_look_vertical(pitch)
end

local function record(p,name)
  assert(p:get_sky(true).body_orbit_tilt==20,"production orbit tilt is missing")
  core.log("action",("ATMOSPHERE_VIEW %s %.6f %.6f %s %s"):format(
    name,core.get_timeofday(),p:get_day_night_ratio() or -1,tostring(p:get_moon().visible),p:get_sky(true).type))
end

-- A QA-only driver for real PlayerAPI parameters and screenshots.
if feature then
  core.register_chatcommand("atmosfeature",{func=function(name,shot)
    local p=assert(core.get_player_by_name(name))
    if shot=="rays-off" or shot=="rays-on" then
      phase=.4
      pose(p,"rays")
      local options=p:get_lighting()
      options.volumetric_light.strength=shot=="rays-on" and .20 or 0
      p:set_lighting(options)
    elseif shot=="hold" then
      phase=.82
      -- The presentation refresh interval is .6s; leave time for both
      -- calendar synchronization and the new phase to reach this player.
      core.after(.90,function()
        assert(p:get_day_night_ratio()<.66 and math.abs(core.get_timeofday()-.82)<.0001)
        assert(not lighting.toggle(p),"guest unexpectedly toggled shared sky")
        core.set_player_privs(name,{server=true,shout=true})
        assert(lighting.toggle(p),"operator could not hold the sun")
        phase=.94
        core.after(.35,function()
          assert(math.abs(core.get_timeofday()-.4)<.0001 and p:get_day_night_ratio()>.97)
          core.log("action","ATMOSPHERE_FEATURE hold")
        end)
      end)
      return true
    elseif shot=="cycle" then
      assert(lighting.toggle(p) and not lighting.is_always_day())
      assert(math.abs(core.get_timeofday()-.94)<.0001 and p:get_day_night_ratio()<.57)
    else
      return false,"Unsupported QA stage"
    end
    core.log("action","ATMOSPHERE_FEATURE "..shot)
    return true
  end})
end
core.register_chatcommand("atmosqa",{func=function(name,shot)
  local p=assert(core.get_player_by_name(name))
  assert(phases[shot] or shot=="slope")
  core.set_timeofday(phases[shot] or .5)
  pose(p,shot)
  core.after(1.0,record,p,shot)
  core.after(2.0,function()
    if tonumber(core.settings:get("time_speed"))==0 then
      assert(math.abs(core.get_timeofday()-(phases[shot] or .5))<.0001,"clock advanced despite freeze")
    end
  end)
  return true
end})

core.register_on_joinplayer(function(p)
  core.emerge_area(vector.new(-24,-6,-22),vector.new(38,16,23),function(_,_,left)
    if left~=0 then return end
    for x=-24,35 do for z=-22,22 do
      local height=math.floor(1.1*math.sin(.19*x+.11*z)+.7*math.cos(.29*z+.08*x))
      local water=(math.abs(z-4-.15*x)<5 or x>23)
      if water then
        core.set_node(vector.new(x,-1,z),{name="atmosphere:sea"})
      else
        for y=feature and -4 or -1,height do core.set_node(vector.new(x,y,z),{name=y==height and "atmosphere:meadow" or "atmosphere:rock"}) end
        if feature and x>=-16 and x<24 and (x*23+z*37)%17<2 then
          core.set_node(vector.new(x,height+1,z),{name="atmosphere:forest"..((x+z)%3)})
        end
      end
    end end
    if not feature then
      for x=4,23 do for z=-22,-3 do
        core.set_node(vector.new(x,2,z),{name="atmosphere:shadow_pad"})
      end end
      for y=3,6 do core.set_node(vector.new(13,y,-13),{name="atmosphere:rock"}) end
      core.set_node(vector.new(0,3,0),{name="atmosphere:slope_axes"})
    end
    p:set_physics_override({gravity=0})
    pose(p,"noon")
    core.set_timeofday(.5)
    open(p)
    if feature then
      local v=p:get_lighting()
      assert(math.abs(v.volumetric_light.strength-.20)<.0001 and v.bloom.intensity>0,
        "Luanti did not accept the production light settings")
      assert(not lighting.is_always_day())
      p:set_clouds({speed={x=0,z=0}})
      p:hud_set_flags({chat=false})
    end
    if tonumber(core.settings:get("time_speed"))~=0 then
      core.after(4.2,function()
        assert(core.get_timeofday()>.79,"native clock did not advance into night")
        assert(p:get_day_night_ratio()<.65,"lighting did not follow the native clock")
        record(p,"advance")
      end)
    end
    core.log("action","ATMOSPHERE_READY")
  end)
end)
