-- Real terrain masks, file textures, and independently sloped farm fences.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local terrain=dofile(core.get_modpath("goodsart").."/slope.lua")
for stage=0,8 do
  for mask=0,30 do
    if mask<15 or mask==23 or mask==27 or mask==29 or mask==30 then
      core.register_node("goodsart:field_"..stage.."_"..mask,{
        description="Original farm ground crop stage "..stage,
        drawtype="mesh",mesh="bl_farm_land_"..mask..".obj",tiles={"bl_farm_field_"..stage..".png"},
        paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
    end
  end
end
for mask=0,30 do
  if mask<15 or mask==23 or mask==27 or mask==29 or mask==30 then
    core.register_node("goodsart:meadow_"..mask,{
      description="Meadow continues beyond the crop edge",
      drawtype="mesh",mesh="bl_farm_land_"..mask..".obj",tiles={"bl_grass0.png"},
      paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
  end
end
for q=0,3 do
  core.register_node("goodsart:g"..q,{description="Meadow",pointable=false,
    tiles={"bl_grass"..q..".png","bl_grass0.png","bl_grass_side.png"}})
end
local function entity(name,crop)
  core.register_entity("goodsart:"..name,{
    initial_properties={static_save=false,physical=false,pointable=false,visual="mesh",
      mesh="bl_"..name..".obj",textures={crop and "bl_crop_growth_atlas.png" or "bl_farm_fence_atlas.png"},
      shaded=not crop,backface_culling=not crop,visual_size={x=1,y=1,z=1}},
  })
end
for style=1,6 do for grade=0,1 do entity("farm_fence_"..style.."_"..grade) end end
for stage=2,8 do entity("crop_growth_"..stage,true); entity("crop_growth_"..stage.."_patch",true) end

local views={
  ["through-crops"]={from={x=6.5,y=.505,z=8.8},at={x=7.2,y=.76,z=10.8},walk=true},
  survey={from={x=15.72,y=8.10,z=14.56},at={x=10.0,y=1.16,z=7.95}},
  ["field-edge"]={from={x=7.82,y=1.56,z=12.70},at={x=7.96,y=.95,z=8.70}},
  steep={from={x=14.27,y=1.68,z=11.67},at={x=10.6,y=1.20,z=7.9}},
}
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="goodsart:"..n}) end
local function view(p,v)
  local eye=v.walk and .262 or 1.47
  p:set_properties({eye_height=eye})
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+eye,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function fence(style,x,z,u,v,h,k)
  assert(math.abs(h-k)<=1)
  local a,b=math.atan2(v-z,u-x),math.atan2(z-v,x-u)
  local e=assert(core.add_entity({x=(x+u)/2,y=.5+math.min(h,k),z=(z+v)/2},
    "goodsart:farm_fence_"..style.."_"..math.abs(h-k)))
  e:set_rotation({x=0,y=h<=k and a or b,z=0})
end
local function height(x,z)
  -- Rows of flat; crest; then a true stock steep slope where axes meet.
  local a=x>=4 and 1 or (x==3 and z>=2 and 1 or 0)
  local b=z>=4 and 1 or 0
  return a+b
end
local function build()
  for j=-5,13 do for i=-6,13 do
    local crop=i>=0 and i<=4 and j>=0 and j<=3
    local stage=(j==2 and i<=2) and 6 or (j==3 and i<=2) and 8 or (j*5+i)%9
    local n,w,e,s=height(i,j),height(i+1,j),height(i,j+1),height(i+1,j+1)
    assert(terrain.valid(n,w,e,s))
    local mask,base=terrain.classify(n,w,e,s)
    local x,z=4+2*i,4+2*j
    for a=0,1 do for b=0,1 do
      for yy=-1,base do node(x+a,yy,z+b,"g"..((i*7+j*17)%4)) end
    end end
    node(x,base+1,z,crop and "field_"..stage.."_"..mask or "meadow_"..mask)
    if crop then
    local x0,z0,x1,z1=x-.5,z-.5,x+1.5,z+1.5
    if i==0 then fence((j+2)%6+1,x0,z0,x0,z1,n,e) end
    if i==4 then fence((j+4)%6+1,x1,z0,x1,z1,w,s) end
    if j==0 then fence(i%6+1,x0,z0,x1,z0,n,w) end
    if j==3 then fence(i%6+2,x0,z1,x1,z1,e,s) end
    if j==1 and i>=2 then fence(i+1,x0,z1,x1,z1,e,s) end
    if stage>=2 then
      if mask==0 then
        assert(core.add_entity({x=x+.5,y=base+.504,z=z+.5},"goodsart:crop_growth_"..stage))
      elseif stage~=8 then
        for a=0,3 do
          local dx,dz=a%2-.5,math.floor(a/2)-.5
          local y=base+.504+terrain.surface(.5+dx/2,.5+dz/2,mask)
          assert(core.add_entity({x=x+.5+dx,y=y,z=z+.5+dz},"goodsart:crop_growth_"..stage.."_patch"))
        end
      end
    end
    end
  end end
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.96)
  p:set_sky({type="plain",base_color="#bcd5df",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.survey)
  if pending then return end
  pending=true
  core.emerge_area({x=-8,y=-1,z=-5},{x=31,y=6,z=29},function(_,_,n)
    if n==0 then
      build();ready=true
      local current=core.get_player_by_name(name)
      if current then view(current,views.survey) end
      core.log("action","FIELD_MESH_FIXTURE_READY")
    end
  end)
end)
core.register_chatcommand("fieldview",{params="survey|field-edge|steep",
  func=function(name,key)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[key] then return false end
    view(p,views[key]);return true
  end})
