-- Standalone Linux client render of the actual shipped OBJ and atlas.
local mono=core.settings:get_bool("qa_monorail_spans",false)
local stem,atlas="bl_guideway_mono_span_","bl_guideway_mono_span"
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local function mesh(name,source,atlas)
  core.register_node("railpreview:"..name,{description=name,drawtype="mesh",
    mesh=source..".obj",tiles={atlas..".png"},paramtype="light",sunlight_propagates=true,
    walkable=false,pointable=false})
end
for i=0,3 do
  core.register_node("railpreview:meadow"..i,{description="Railway valley meadow",
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("railpreview:river"..i,{description="Railway valley river",walkable=false,
    tiles={"bl_water"..i..".png","bl_water0.png","bl_water_side.png"}})
end
core.register_node("railpreview:darkrock",{description="Hill interior, not part of the portal mesh",
  tiles={"bl_grass1.png","bl_grass0.png","bl_grass_side.png^[multiply:#251e1b"}})
for d=0,3 do
  local s=({12,6,3,9})[d+1]
  mesh("slope_"..d,"bl_land_"..s,"bl_grass1")
  mesh("bore_"..d,mono and stem.."tunnel_"..d or "bl_rail_tunnel_portal_"..d,mono and atlas or "bl_rail_tunnel_portal")
  for _,head in ipairs({"flat","ramp"}) do
    local name="head_"..head.."_"..d
    mesh(name,mono and stem..name or "bl_rail_bridge_wood_"..name,mono and atlas or "bl_rail_bridge_wood")
  end
end
for a=0,1 do
  local b=2^a
  mesh("rail_"..a,(mono and "bl_guideway_mono_flat_" or "bl_rail_track_")..b,
    mono and "bl_guideway_mono_atlas" or "bl_rail_atlas")
  for _,piece in ipairs({"span","pier"}) do
    local k=piece.."_"..a
    mesh(k,mono and piece=="span" and stem..k or "bl_rail_bridge_wood_"..k,
      mono and piece=="span" and atlas or "bl_rail_bridge_wood")
  end
end
for _,id in ipairs({"steam","electric","rail_passenger_wagon","rail_open_wagon"}) do
  local name=mono and ({steam="rail_x2001",electric="rail_x2001",rail_passenger_wagon="rail_mono_passenger",
    rail_open_wagon="rail_mono_mail"})[id]
  core.register_entity("railpreview:"..id,{
    initial_properties={visual="mesh",mesh="bl_"..(name or id)..".obj",static_save=false,
      physical=false,pointable=false,textures={name and "bl_"..name..".png" or
        id:find("^rail_") and "bl_rail_wagon_atlas.png" or "bl_vehicle_palette.png"}},
  })
end
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="railpreview:"..n}) end
local function roll(stock,x,y,z,angle)
  local obj=assert(core.add_entity({x=x,y=y,z=z},"railpreview:"..stock))
  obj:set_rotation({x=0,y=angle,z=0})
  if not mono and (stock=="steam" or stock=="electric") then
    obj:set_properties({visual_size={x=1,y=1,z=.55}})
  end
end
local views={
  bridge={from={x=7.0,y=3.3,z=4.6},at={x=15.2,y=.85,z=8.4}},
  crown={from={x=10.0,y=.35,z=7.86},at={x=14.0,y=1.35,z=8.55}},
  bore={from={x=11.6,y=-.17,z=17.2},at={x=12.50,y=1.19,z=21.70}},
}
local function position(p,v)
  p:set_pos(v.from)
  local vec=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-vec.x,vec.z))
  p:set_look_vertical(math.atan2(-vec.y,math.sqrt(vec.x*vec.x+vec.z*vec.z)))
end
local function build()
  for x=-15,38 do for z=-13,42 do
    local variant=(math.floor(x/2)*7+math.floor(z/2)*17)%4
    node(x,-1,z,"meadow"..variant)
    if x>=12 and x<20 and z<13 then
      node(x,-1,z,"river"..variant)
    else
      node(x,0,z,"meadow"..variant)
    end
    if z>=22 and z<30 then
      node(x,1,z,(x==12 or x==13) and "darkrock" or ("meadow"..variant))
    end
    if z%2==0 and x%2==0 and z==20 and x~=12 then node(x,1,z,"slope_1") end
    if z%2==0 and x%2==0 and z==30 and x~=12 then node(x,1,z,"slope_3") end
  end end
  -- Four two-node spans and mixed legal head styles. The opposite head
  -- sits on a slope whose high edge touches the connecting straight.
  for x=2,8,2 do node(x,1,8,"rail_0") end
  node(10,1,8,"head_ramp_2")
  for x=12,18,2 do
    node(x,1,8,"span_0")
    node(x,0,8,"pier_0")
  end
  for z=-8,16,2 do node(20,1,z,"slope_2") end
  -- The retained terrain slope sits inside this single overlay anchor.
  node(20,1,8,"head_flat_0")
  for x=22,30,2 do
    for dx=0,1 do for dz=-7,15 do node(x+dx,1,dz,"meadow1") end end
    node(x,2,8,"rail_0")
  end
  local deck=mono and 1.746 or 1.614
  roll("steam",15.0,deck,8.5,-math.pi/2)
  roll("rail_passenger_wagon",14.0,deck,8.5,-math.pi/2)
  roll("rail_open_wagon",13.0,deck,8.5,-math.pi/2)
  -- Preserve the grade and run the approach through the genuine art bore.
  for _,z in ipairs({14,16,18,32,34}) do node(12,1,z,"rail_1") end
  node(12,1,20,"bore_1");node(12,1,30,"bore_3")
  roll("electric",12.5,mono and .746 or .614,20.76,math.pi)
end
local pending,ready=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bed3db",clouds=false})
  for _,f in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do p:hud_set_flags({[f]=false}) end
  position(p,views.bridge)
  if not pending then
    pending=true
    core.emerge_area({x=-15,y=-2,z=-13},{x=39,y=5,z=43},function(_,_,left)
      if left==0 then
        build();ready=true
        local who=core.get_player_by_name(name)
        if who then position(who,views.bridge) end
        core.log("action","RAIL_SPAN_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showrailspan",{
  params="bridge|crown|bore",description="Inspect the actual rail span kits",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    position(p,views[arg]);return true
  end,
})
