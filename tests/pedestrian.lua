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
assert(physics.gravity==1 and physics.speed_walk==P.walk_speed and P.walk_nodes_per_second>.22 and P.walk_nodes_per_second<.25 and properties.eye_height==P.eye_height and P.eye_height>.23 and P.eye_height<.28
  and P.visual_height>.28 and P.visual_height<.31 and properties.visual_size.y==P.visual_scale
  and properties.visual=="mesh" and properties.collisionbox[4]==.064)
assert(vel.x==0 and vel.y==0 and vel.z==0)
walk.step(p,avatar,{aux1=true})
assert(avatar.running and physics.speed_walk==P.run_speed and P.run_nodes_per_second>.53)
assert(math.abs(physics.speed_fast*20-P.run_nodes_per_second)<1e-9)
walk.step(p,avatar,{aux1=false})
assert(not avatar.running and physics.speed_walk==P.walk_speed)
pos={x=8.5,y=.12,z=2.5};vel.y=-2
walk.step(p,avatar)
assert(avatar.swimming and physics.gravity==0 and vel.y> -2,"falling into water changes to a controlled float")
pos={x=8.5,y=1.32,z=2.5};vel.y=0
walk.step(p,avatar,{jump=true,aux1=true})
assert(not avatar.running,"Holding E must not change swim speed")
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

-- Check a simulated native velocity response at different step cadences
-- and validate no single packet can add a large impulse.
for _,dt in ipairs({.03,.07,.09,.1}) do
  local y,speed,high=-.31,-.64,-.31
  for i=1,math.ceil(4/dt) do
    local dy=P.swim_impulse(.14-y,speed,dt)
    assert(dy<=4.8*dt+1e-9 and dy>=-3.8*dt-1e-9)
    speed=speed+dy
    y=y+speed*dt
    high=math.max(high,y)
  end
  assert(math.abs(y-.14)<.04 and high<.24,"unstable water rise")
end
print("PASS waterline trim settles at different step rates without a hard vertical impulse")

local Rail=dofile("mods/luanttd_core/rail_platform_walk.lua")
local function on_deck(p,boxes)
  for _,b in ipairs(boxes) do
    if p.x>b[1] and p.x<b[4] and p.z>b[3] and p.z<b[6] and math.abs(p.y-b[5])<.001 then
      return true
    end
  end
end
local function deck(q)
  for _,p in ipairs(q.landing) do assert(on_deck(p,q.boxes),"landing floats or is outside deck") end
end
for fx=0,7 do deck(Rail.stock(fx)) end
for axis=0,1 do
  for gauge=0,3 do deck(Rail.ordinary(axis,gauge)) end
  deck(Rail.coal(axis,"load"));deck(Rail.coal(axis,"unload"))
  assert(#Rail.crossing(axis)==9 and on_deck({x=.5,y=-.392,z=.5},Rail.crossing(axis)))
end
assert(#Rail.ballast(3)==2 and Rail.ballast(4)==nil)
rows[3].h=1
rows[5].rail_station_id=8
local platform={x=10.30,y=1.825,z=3.13}
local pedestrian_rail=P.new({s={tiles=rows},Sim=sim,render={uses_slope=function()return false end,
  walk_platform_landings=function(id)if id==5 then return {platform} end end}})
local rail_stop=assert(pedestrian_rail.ride_landing("rail",{x=8.2,y=1.66,z=2.5}))
assert(rail_stop==platform,"a train dismount prefers a nearby platform")
local bus_stop=assert(pedestrian_rail.ride_landing("road",{x=9.0,y=1.65,z=2.5}))
assert(bus_stop.x==6.5 and not pedestrian_rail.ride_landing("air",{x=9.0,y=42,z=2.5}))
print("PASS platform boxes cover landing points in both axes; local ride exits favor platform or road and reject an aerial drop")
