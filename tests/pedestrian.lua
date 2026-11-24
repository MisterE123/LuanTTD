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
assert(not walk.at(1,{x=2.5,z=2.5}) and not walk.at(2,{x=4.5,z=2.5}))
local afloat,water=walk.at(4,{x=8.5,z=2.5})
assert(afloat and water==1.5 and math.abs(afloat.y-1.32)<.0001)
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
assert(avatar.swimming and physics.gravity==0 and vel.y> -2,"falling into water changes to a controlled float")
pos={x=8.5,y=1.32,z=2.5};vel.y=0
walk.step(p,avatar,{jump=true})
assert(vel.y>0,"Space strokes toward shore level")
pos={x=10.5,y=1.50,z=2.5};vel.y=0
walk.step(p,avatar)
assert(not avatar.swimming and physics.gravity==1,"dry ground restores walking")
P.restore_controls(p,avatar.saved)
P.restore_pose(p,avatar.saved)
assert(pos.x==3 and pos.y==15 and yaw==1.2 and pitch==.62)
assert(properties.eye_height==1.63 and physics.gravity==0 and flags.crosshair and flags.hotbar and eye.z==.3)
assert(properties.visual=="sprite" and properties.textures[1]=="bl_sightseeing_hidden_player.png"
  and properties.visual_size.y==.001 and properties.nametag_color.a==0)
print("Pedestrian: safe landing, slope support, client walking parameters, shoreline recovery and builder state restore")

local B=dofile("mods/luanttd_core/pedestrian_bridge.lua")
for d=0,3 do
  local boxes=B.box("head_ramp",d)
  assert(#boxes==8 and #B.box("span",d%2)==1)
  local span={axis=d%2,deck=3,start=1,["end"]=3,head={inside_direction=d},tail={flat_ramp=true}}
  local last=-2
  for _,b in ipairs(boxes) do
    local a=B.floor(span,1,b[1],b[3])-3
    local q=B.floor(span,1,b[4],b[6])-3
    assert(math.abs(b[5]-math.min(a,q))<1e-8 and math.abs(a-q)<.28)
    if last~=-2 then assert(math.abs(last-b[5])<.28) end
    last=b[5]
  end
  assert(B.floor(span,2,.5,.5)==3.5 and B.floor(span,3,.5,.5)==3.5)
  assert(not B.on_deck(span.axis,-.4,-.4) and B.on_deck(span.axis,.5,.5))
end
local flat=P.slope_box(T.surface,0,true)
assert(#flat.fixed==1 and flat.fixed[1][5]==-.5)
print("PASS bounded plate collision and accurate ramp heights for all four deck orientations; flat crop support")
