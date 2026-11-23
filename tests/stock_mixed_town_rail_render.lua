-- Re-project the physical body poses exported by the actual authority
-- (not a fresh mock of how a model should be ordered on the track).
local mod=core.get_modpath(core.get_current_modname())
local frames={}
for i=1,4 do
  local f=assert(io.open(mod.."/frame"..i..".json","rb"))
  frames[i]=assert(core.parse_json(f:read("*a")));f:close()
end
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
core.register_node("railpreview:grass",{description="Meadow",pointable=false,
  tiles={"bl_grass0.png","bl_grass0.png","bl_grass_side.png"}})
core.register_node("railpreview:track",{description="Rail",drawtype="mesh",mesh="bl_rail_track_1.obj",
  tiles={"bl_rail_atlas.png"},paramtype="light",sunlight_propagates=true,pointable=false,walkable=false})
core.register_node("railpreview:platform",{description="Platform",drawtype="mesh",mesh="bl_rail_platform_1.obj",
  tiles={"bl_rail_architecture_atlas.png"},paramtype="light",sunlight_propagates=true,pointable=false,walkable=false})
for kind,files in pairs({
  steam={"bl_rail_kirby_paul_tank.obj","bl_rail_kirby_paul_tank.png"},
  wagon={"bl_rail_passenger_wagon.obj","bl_rail_wagon_atlas.png"},
  mail_van={"bl_rail_mail_van.obj","bl_rail_mail_van.png"},
}) do
  core.register_entity("railpreview:"..kind,{initial_properties={
    static_save=false,physical=false,pointable=false,visual="mesh",mesh=files[1],
    textures={files[2]},shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1},
  }})
end
local function place(x,y,z,name)
  core.set_node({x=x,y=y,z=z},{name="railpreview:"..name})
end
local function aim(p,i)
  local o=frames[i].camera
  p:set_pos({x=o.x-1.95,y=o.y-.16,z=o.z-4.54})
  local eye=p:get_pos()
  local d=vector.subtract(o,{x=eye.x,y=eye.y+1.47,z=eye.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function build()
  for x=-8,40 do for z=-10,60 do place(x,1,z,"grass") end end
  for i,frame in ipairs(frames) do
    local p=frame.parts[1].pos
    local dx=16-math.floor(p.x/2)*2
    local dz=(i-1)*14-math.floor(p.z/2)*2
    local z=math.floor((p.z+dz)/2)*2
    for x=-6,38,2 do place(x,2,z,"track") end
    local a,average=0,0
    for _,b in ipairs(frame.parts) do
      local pos={x=b.pos.x+dx,y=b.pos.y,z=b.pos.z+dz}
      local row=assert(core.add_entity(pos,"railpreview:"..b.kind))
      row:set_rotation(b.rotation)
      a=a+pos.x;average=average+pos.y
    end
    frame.camera={x=a/#frame.parts,y=average/#frame.parts+.24,z=z+.5}
  end
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0,speed=0,jump=0})
  p:override_day_night_ratio(.96)
  p:set_sky({type="plain",base_color="#bfd5df",clouds=false})
  for _,f in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[f]=false})
  end
  if ready then aim(p,1)
  elseif not pending then
    pending=true
    core.emerge_area({x=-8,y=0,z=-10},{x=40,y=5,z=60},function(_,_,left)
      if left==0 then
        build();ready=true;local viewer=core.get_player_by_name(name)
        if viewer then aim(viewer,1) end
        core.log("action","MIXED_TOWN_CLIENT_MESH_READY")
      end
    end)
  end
end)
core.register_chatcommand("showmixed",{
  params="1..4",description="Show a captured real worker formation",
  func=function(n,arg)
    local p=core.get_player_by_name(n)
    local i=tonumber(arg)
    if not p or not ready or not frames[i] then return false end
    aim(p,i)
    core.log("action","MIXED_TOWN_CLIENT_CAPTURE "..i.." "..frames[i].form.." reversals "..frames[i].reversals)
    return true
  end,
})
