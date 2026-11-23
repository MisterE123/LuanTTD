-- Isolated actual Luanti sky, time, lighting and original terrain textures.
local world=core.get_modpath("atmosphere")
local open=dofile(world.."/atmosphere.lua").start(core)
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
local phases={noon=.5,dusk=.749,moonrise=.825,midnight=0,shadow=.40}

local function pose(p,name)
  local x,pitch=-19,-.15
  local yaw=-math.pi/2 -- scenery and the rising moon are to the east
  if name=="midnight" then pitch=-1.05 end
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
        for y=-1,height do core.set_node(vector.new(x,y,z),{name=y==height and "atmosphere:meadow" or "atmosphere:rock"}) end
      end
    end end
    for x=4,23 do for z=-22,-3 do
      core.set_node(vector.new(x,2,z),{name="atmosphere:shadow_pad"})
    end end
    for y=3,6 do core.set_node(vector.new(13,y,-13),{name="atmosphere:rock"}) end
    core.set_node(vector.new(0,3,0),{name="atmosphere:slope_axes"})
    p:set_physics_override({gravity=0})
    pose(p,"noon")
    core.set_timeofday(.5)
    open(p)
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
