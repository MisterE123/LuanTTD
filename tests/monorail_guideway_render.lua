-- Native client check of worker-derived consists and the current exact bogie
-- renderer. The world only provides repeatable camera positions and lighting.
local mod=core.get_modpath(core.get_current_modname())
local function m(name) return dofile(mod.."/"..name..".lua") end
local marker=assert(io.open(mod.."/qa-variant.txt"))
local family=marker:read("*l");marker:close()
local gauge=family=="maglev" and 3 or 2
local profile=assert(m("rail_guideway_profiles").by_gauge[gauge])
local stem="bl_guideway_"..family
local Sim={tiles={}}
function Sim.id(x,z) if x>=1 and z>=1 and x<=30 and z<=60 then return (z-1)*30+x end end
function Sim.xy(id) return (id-1)%30+1,math.floor((id-1)/30)+1 end
local sides={[0]={-1,0},{0,1},{1,0},{0,-1}}
function Sim.adjacent(id,d)
  local x,z=Sim.xy(id)
  local offset=sides[4-d]
  return Sim.id(x+offset[1],z+offset[2])
end
local T=m("rail_track")
local D=m("rail_diagonal")(Sim,T)
local Pose=m("rail_pose")
local function eased(id,td,f) return D.sample(td,f,D.mode(Sim,id)) end
local stock=Pose(T).sample
local bogies=m("rail_guideway_bogies")(Sim,T,eased,stock,function() return 1,0 end,function(id) return Sim.tiles[id] end)
local link=m("rail_guideway_drawbar")
local view=m("campaign_projected_actors")(core,{},m("road_motion"),{}, {})
local frames={}
for _,name in ipairs({"loading","reversed"}) do
  local f=assert(io.open(mod.."/mixed-pose-"..name..".json","rb"))
  frames[name]=assert(core.parse_json(f:read("*a")));f:close()
end
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
core.set_mapgen_setting("mg_name","singlenode",true)
local function node(name,mesh,tex)
  core.register_node(":monoqa:"..name,{description="Guideway",mesh=mesh,tiles={tex},
    drawtype=mesh and "mesh" or "normal",paramtype="light",sunlight_propagates=true,
    pointable=false,walkable=false})
end
node("grass",nil,"bl_grass1.png")
for mask=1,8 do
  if mask==1 or mask==4 or mask==8 then
    node("track_"..mask,stem.."_flat_"..mask..".obj",stem.."_atlas.png")
    if mask~=1 then
      for n=1,3 do node("eased_"..mask.."_"..n,stem.."_eased_"..mask.."_"..n..".obj",stem.."_atlas.png") end
    end
  end
end
node("platform",stem.."_platform_0.obj",stem.."_facility_atlas.png")
node("depot",stem.."_depot_2.obj",stem.."_facility_atlas.png")
local function entity(name,assets)
  core.register_entity(":luanttd_core:dispatch_"..name,{initial_properties={
    static_save=false,physical=false,pointable=false,visual="mesh",mesh=assets[1],
    textures={assets[2]},shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1},
  }})
end
local carriages={profile.engine_visual,profile.passenger_visual,profile.mail_visual}
for _,name in ipairs(carriages) do
  entity(name.."_body",{"bl_rail_"..name.."_body.obj","bl_rail_"..name..".png"})
end
for _,name in ipairs({profile.suspension,profile.coupler}) do
  entity(name,{"bl_rail_"..name..".obj","bl_rail_"..profile.engine_visual..".png"})
end
local function place(x,y,z,name)
  core.set_node({x=x,y=y,z=z},{name="monoqa:"..name})
end
local function translate(parts,dx,dy,dz)
  local function move(p) return {x=p.x+dx,y=p.y+dy,z=p.z+dz} end
  local sum={x=0,y=0,z=0}
  for _,part in ipairs(parts) do
    part.pos=move(part.pos)
    for _,g in ipairs(assert(part.bogies)) do g.pos=move(g.pos) end
    if part.drawbar then part.drawbar.pos=move(part.drawbar.pos) end
    for k in pairs(sum) do sum[k]=sum[k]+part.pos[k] end
  end
  for k in pairs(sum) do sum[k]=sum[k]/#parts end
  return sum
end
local function layout()
  for x=0,48 do for z=0,83 do place(x,1,z,"grass") end end
  for _,name in ipairs({"loading","reversed"}) do
    local r=frames[name]
    local p=r.parts[1].pos
    local dz=(name=="loading" and 14 or 36)-math.floor(p.z/2)*2
    local dx=18-math.floor(p.x/2)*2
    -- The captured service may have loaded at a different fixed height.
    -- Translate the entire rig, including its bogies and drawbars, together.
    r.camera=translate(r.parts,dx,1+profile.offset-p.y,dz)
    local z=math.floor(r.camera.z/2)*2
    place(8,2,z,"depot")
    for x=10,43,2 do place(x,2,z,(x>14 and x<24) and "platform" or "track_1") end
  end
  local function line(x,z,mask)
    Sim.tiles[Sim.id(x,z)]={rail_tracks=mask,rail_type=gauge,h=1,owner="QA"}
  end
  line(18,26,1);line(17,26,8)
  for i=0,10 do line(17-i,27+i,4);line(16-i,27+i,8) end
  line(6,38,4);line(5,38,1)
  for id,t in pairs(Sim.tiles) do
    local x,z=Sim.xy(id)
    local mode=D.mode(Sim,id)
    place(2*x,2,2*z,mode>0 and "eased_"..t.rail_tracks.."_"..mode or "track_"..t.rail_tracks)
  end
end
local function aim(p,target,style)
  local offset=style==1 and {x=2.6,y=.15,z=-3.3} or style==2 and {x=-3.5,y=4.6,z=-4.7}
    or {x=3.1,y=3.1,z=2.5}
  p:set_pos({x=target.x+offset.x,y=target.y+offset.y,z=target.z+offset.z})
  local eye=vector.add(p:get_pos(),{x=0,y=1.47,z=0})
  local v=vector.subtract(target,eye)
  p:set_look_horizontal(math.atan2(-v.x,v.z))
  p:set_look_vertical(math.atan2(-v.y,math.sqrt(v.x*v.x+v.z*v.z)))
end
local function diagonal_case()
  local route={}
  for i=0,9 do
    local one=Sim.id(17-i,27+i)
    local two=Sim.id(16-i,27+i)
    route[#route+1]={tile=one,td=2};route[#route+1]={tile=two,td=3}
  end
  local frame={parts={}}
  for i=1,3 do
    -- Straight 45-degree centerline: one stock model length per body.
    local f=.78-(i-1)/math.sqrt(2)
    local j=10
    while f<0 do j=j-1;f=f+1 end
    local step=route[j]
    local pos,rot,gears=bogies({route=route,index=j},{id=step.tile,td=step.td,progress=f})
    frame.parts[i]={index=i,body_index=i,kind=carriages[i],pos=pos,rotation=rot,bogies=gears}
  end
  for i=1,#frame.parts-1 do frame.parts[i].drawbar=link(frame.parts[i],frame.parts[i+1],gauge) end
  frame.camera=frame.parts[2].pos
  return frame
end
local function scene(name,shot,frame)
  local p=core.get_player_by_name(name);if not p then return end
  view.render({["rail:1"]={mode="rail",id=1,parts=frame.parts}},.05)
  aim(p,frame.camera,shot)
  core.log("action","MONORAIL_GRAPHICS_FRAME "..shot)
end
core.register_on_joinplayer(function(p)
  local who=p:get_player_name()
  p:set_physics_override({gravity=0,speed=0,jump=0})
  p:override_day_night_ratio(.97)
  p:set_sky({type="plain",base_color="#c0dce8",clouds=false})
  for _,f in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[f]=false})
  end
  core.emerge_area({x=0,y=-4,z=0},{x=48,y=9,z=85},function(_,_,left)
    if left==0 then
      layout()
      scene(who,1,frames.loading)
      core.after(7,scene,who,2,frames.reversed)
      core.after(14,scene,who,3,diagonal_case())
    end
  end)
end)
