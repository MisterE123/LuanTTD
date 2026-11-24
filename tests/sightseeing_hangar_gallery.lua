-- Real Luanti render of the shipped open-door mesh and parked taildragger.
local mod=core.get_modpath("goodsart")
local H=dofile(mod.."/sightseeing_hangar.lua")({hangar={x=3,z=0}},{hangar={x=5,z=0}})
core.set_mapgen_setting("mg_name","singlenode",true)
core.register_node("goodsart:grass",{tiles={"bl_grass0.png"}})
core.register_node("goodsart:ga",{drawtype="mesh",mesh="bl_hangar_ga.obj",paramtype="light",
  tiles={{name="bl_hangar_ga_atlas.png",backface_culling=false}},sunlight_propagates=true,walkable=true,pointable=false,
  collision_box={type="fixed",fixed=H.collision}})
for n,solid in pairs(H.walls) do
  local atlas=n:gsub("_%d_%d$","_atlas")
  core.register_node("goodsart:"..n,{drawtype="mesh",mesh="bl_"..n..".obj",
    tiles={"bl_"..atlas..".png"},paramtype="light",sunlight_propagates=true,walkable=true,pointable=false,
    collision_box={type="fixed",fixed=solid}})
end
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="goodsart:"..n}) end
local profiles={
  country={"small_airport",2,0},city={"city_airport",4,8},
}
local function view(p,n)
  local f=profiles[n]
  p:set_pos({x=2.405,y=.505,z=f[3]+1.8})
  p:set_look_horizontal(math.pi+.40);p:set_look_vertical(.062)
end
core.register_chatcommand("fieldview",{func=function(n,param)
  local p=assert(core.get_player_by_name(n))
  if not profiles[param] then return false end
  view(p,param)
  return true
end})
core.register_on_joinplayer(function(p)
  core.emerge_area({x=-8,y=-1,z=-6},{x=12,y=5,z=25},function(_,_,left)
    if left~=0 then return end
    for x=-6,9 do for z=-5,20 do node(x,0,z,"grass") end end
    for k,f in pairs(profiles) do
      node(0,1,f[3],f[1].."_"..f[2].."_0")
      node(2,1,f[3],f[1].."_"..(f[2]+1).."_0")
      node(3,1,f[3],"ga")
    end
    p:set_properties({eye_height=.263})
    p:set_physics_override({gravity=0})
    p:override_day_night_ratio(.96)
    p:set_sky({type="plain",base_color="#bcd5df",clouds=false})
    for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
      p:hud_set_flags({[flag]=false})
    end
    view(p,"country")
    core.log("action","FIELD_MESH_FIXTURE_READY")
  end)
end)
