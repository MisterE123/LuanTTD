local P=dofile("mods/luanttd_core/pedestrian.lua")
local T=dofile("mods/luanttd_core/openttd/slope.lua")

for _,shape in ipairs({1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}) do
  local box=P.slope_box(T.surface,shape)
  assert(box.type=="fixed" and #box.fixed>0)
  for _,b in ipairs(box.fixed) do
    assert(b[1]>=-.5 and b[4]<=1.5 and b[3]>=-.5 and b[6]<=1.5 and b[2]<b[5])
    for _,x in ipairs({b[1],b[4]}) do for _,z in ipairs({b[3],b[6]}) do
      local y=T.surface((x+.5)/2,(z+.5)/2,shape)-.5
      assert(y+.0001>=b[5] and y-b[5]<=.25)
    end end
  end
end

local rows={
  {h=0,terrain="water",stock_void=true},
  {h=1,terrain="grass",house=true},
  {h=2,terrain="grass",build="road"},
  {h=1,terrain="grass",stock_canal=true},
  {h=1,terrain="grass"},
}
local sim={
  xy=function(id)return id,1 end,
  id=function(x,z) return z==1 and rows[x] and x or nil end,
}
local walk=P.new({s={tiles=rows},Sim=sim,
  render={uses_slope=function(id) return id==3 end,surface=function(id,x,z) return 2+(x-6)*.5 end}})
local pos,vel={x=3,y=15,z=2.5},{x=1,y=2,z=3}
local yaw,pitch=1.2,.62
local properties={eye_height=1.63,collisionbox={-.3,0,-.3,.3,1.7,.3},stepheight=.6,
  visual="upright_sprite",mesh="",textures={"builder.png"},visual_size={x=1,y=2,z=1},is_visible=true}
local physics={gravity=0,speed_walk=2,sneak=false}
local flags={hotbar=true,crosshair=true}
local eye={x=.1,y=.2,z=.3}
local p={
  get_pos=function()return pos end,
  set_pos=function(_,a)pos=a end,
  get_velocity=function()return vel end,
  add_velocity=function(_,v)vel={x=vel.x+v.x,y=vel.y+v.y,z=vel.z+v.z}end,
  get_look_horizontal=function()return yaw end,
  get_look_vertical=function()return pitch end,
  set_look_horizontal=function(_,v)yaw=v end,
  set_look_vertical=function(_,v)pitch=v end,
  get_properties=function()return properties end,
  set_properties=function(_,v)
    for k,value in pairs(v) do properties[k]=value end
  end,
  get_physics_override=function()return physics end,
  set_physics_override=function(_,v)physics=v end,
  hud_get_flags=function()return flags end,
  get_eye_offset=function() return eye end,
  set_eye_offset=function(_,v) eye=v end,
  hud_set_flags=function(_,v)flags=v end,
}
local target=assert(walk.find(p,2,{x=4.5,z=2.5}))
assert(target.x==6.5 and target.y>2.29 and target.y<2.30,"choose a road instead of burrowing into a house")
local edge=assert(walk.find(p,3,{x=5.51,z=3.49}))
assert(edge.x==5.75 and edge.z==3.25,"keep spawn footprint clear of neighbor tiles")
P.hide_builder(p)
assert(properties.eye_height==1.63 and properties.visual=="sprite" and properties.mesh==""
  and properties.textures[1]=="bl_sightseeing_hidden_player.png" and properties.visual_size.y==.001
  and properties.nametag_color.a==0)
local avatar={saved=P.capture(p)}
walk.enter(p,avatar,target)
assert(pos==target and pos.y<3 and yaw==1.2 and pitch==0)
assert(physics.gravity==1 and physics.speed_walk==.38 and properties.eye_height==P.eye_height and P.eye_height>.23 and P.eye_height<.28
  and P.visual_height>.28 and P.visual_height<.31 and properties.visual_size.y==P.visual_scale
  and properties.visual=="mesh" and properties.collisionbox[4]==.064)
assert(vel.x==0 and vel.y==0 and vel.z==0)
pos={x=8.5,y=.12,z=2.5};vel.y=-2
walk.step(p,avatar)
assert(pos==target,"falling off the road into water safely returns to dry ground")
P.restore_controls(p,avatar.saved)
P.restore_pose(p,avatar.saved)
assert(pos.x==3 and pos.y==15 and yaw==1.2 and pitch==.62)
assert(properties.eye_height==1.63 and physics.gravity==0 and flags.crosshair and flags.hotbar and eye.z==.3)
assert(properties.visual=="sprite" and properties.textures[1]=="bl_sightseeing_hidden_player.png"
  and properties.visual_size.y==.001 and properties.nametag_color.a==0)
print("Pedestrian: safe landing, slope support, client walking parameters, shoreline recovery and builder state restore")
