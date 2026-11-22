-- Isolated geometry fixture: both axes and the exact coastal test circuit bridge
-- heads/deck/river datums. No game rules or route are loaded here.
local sprung=fixture_sprung_collector==true
local mod=core.get_modpath("railpreview")
local Art=dofile(mod.."/rail_bridge_catenary_art.lua")
local Plain=dofile(mod.."/rail_catenary_art.lua")
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local function mesh(name,obj,tex)
  core.register_node("railpreview:"..name,{description=name,drawtype="mesh",mesh=obj..".obj",
    tiles={tex..".png"},paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
end
local function wire(o)
  local obj=o.mesh:gsub("%.obj$","")
  local tex=o.texture:gsub("%.png$","")
  if not core.registered_nodes["railpreview:"..o.name] then mesh(o.name,obj,tex) end
  return o.name
end
for i=0,3 do
  core.register_node("railpreview:grass"..i,{description="Shore grass",tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("railpreview:water"..i,{description="Harbor water",walkable=false,
    tiles={"bl_water"..i..".png","bl_water0.png","bl_water_side.png"}})
  mesh("slope_"..i,"bl_land_"..({12,6,3,9})[i+1],"bl_grass1")
  for _,part in ipairs({"head_flat","head_ramp"}) do
    mesh(part.."_"..i,"bl_rail_bridge_wood_"..part.."_"..i,"bl_rail_bridge_wood")
    wire(assert(Art.overlay(part,i)))
  end
end
for axis=0,1 do
  mesh("rail_"..axis,"bl_rail_track_"..2^axis,"bl_rail_atlas")
  for _,part in ipairs({"span","pier"}) do
    mesh(part.."_"..axis,"bl_rail_bridge_wood_"..part.."_"..axis,"bl_rail_bridge_wood")
  end
  wire(assert(Art.overlay("span",axis,1,3)))
  wire(assert(Art.overlay("span",axis,2,3)))
  wire(assert(Plain.overlay(2^axis,0,"plain",1,1)))
  wire(assert(Plain.overlay(2^axis,0,"plain",0,0)))
end
for _,id in ipairs({"rail_sh_30","rail_sh_40","rail_passenger_wagon"}) do
  core.register_entity("railpreview:"..id,{initial_properties={visual="mesh",mesh="bl_"..id..".obj",
    static_save=false,physical=false,pointable=false,visual_size={x=1,y=1,z=1},
    textures={id=="rail_passenger_wagon" and "bl_rail_wagon_atlas.png" or "bl_"..id..".png"}}})
end
if sprung then
  for _,sh in ipairs({30,40}) do
    local stem="bl_rail_sh_"..sh
    for role,obj in pairs({body=stem.."_body",collector="bl_rail_sh_collector"}) do
      core.register_entity("railpreview:sh_"..sh.."_"..role,{
        initial_properties={visual="mesh",mesh=obj..".obj",textures={stem..".png"},
          static_save=false,physical=false,pointable=false,visual_size={x=1,y=1,z=1}},
      })
    end
  end
end
local function assembled(sh,x,y,z,axial_pitch,yaw,scale)
  local prefix="railpreview:sh_"..sh
  local p={x=x,y=y,z=z}
  local b=assert(core.add_entity(p,prefix.."_body"))
  b:set_rotation({x=axial_pitch,y=yaw,z=0})
  local c=assert(core.add_entity(p,prefix.."_collector"))
  c:set_properties({visual_size={x=1,y=scale,z=1}})
  c:set_attach(b,"",{x=0,y=5.80,z=.53},{x=0,y=0,z=0})
  local owner,_,heel=c:get_attach()
  assert(owner==b and math.abs(heel.y-5.8)<1e-6)
end
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="railpreview:"..n}) end
local function vehicle(id,x,z,angle)
  local ob=assert(core.add_entity({x=x,y=2.614,z=z},"railpreview:"..id))
  ob:set_rotation({x=0,y=angle,z=0})
end
local function part(tx,tz,name,dir,index,length)
  local x,z=2*tx,2*tz
  local o=assert(Art.overlay(name,dir,index,length))
  node(x,2,z,name.."_"..dir)
  node(x,2+o.offset,z,o.name)
end
local function ordinary(x,z,base,axis)
  node(2*x,base+1,2*z,"rail_"..axis)
  local select=assert(Plain.overlay(2^axis,0,"plain",x,z))
  node(2*x,base+select.offset,2*z,select.name)
end
local function build()
  for x=24,66 do for z=-3,49 do
    local i=(math.floor(x/2)*7+math.floor(z/2)*17)%4
    node(x,-1,z,"grass"..i)
    if x>=46 and x<=51 and z>=22 then
      node(x,0,z,"water"..i) -- stock tiles 23/24/25, top datum .5
    else
      node(x,0,z,"grass"..i)
      if ((x<44 or x>53) and z>=22) or (x>=28 and x<=34 and z<12) then
        node(x,1,z,"grass"..i)
      end
    end
  end end
  -- coastal test circuit seed 1751; see exact source quote fixture.
  for _,x in ipairs({18,19,20,28,29,30}) do ordinary(x,15,1,0) end
  part(21,15,"head_ramp",2)
  part(27,15,"head_ramp",0)
  for i=1,5 do
    local x=21+i; part(x,15,"span",0,i,5)
    if x==22 or x==26 then node(x*2,1,30,"slope_"..(x==22 and 0 or 2))
    else node(x*2,1,30,"pier_0") end
  end
  if sprung then
    local tilt=math.atan(.5)
    local scale=(.784*math.cos(tilt)-.580)/.204
    assembled("40",48.45,2.614,30.5,0,-math.pi/2,1)
    assembled("30",42.5,2.114,30.5,-tilt,math.pi/2,scale)
    assembled("40",54.5,2.114,30.5,-tilt,-math.pi/2,scale)
  else vehicle("rail_sh_40",48.45,30.5,-math.pi/2) end
  vehicle("rail_passenger_wagon",47.45,30.5,-math.pi/2)
  -- Orthogonal mixed head check: north flat abutment, south full ramp.
  -- Extra ground under the high approach; ordinary feeder ends unchanged.
  for x=28,34 do for z=0,3 do node(x,2,z,"grass1") end end
  for z=0,1 do ordinary(15,z,2,1) end
  part(15,2,"head_flat",1)
  for i=1,4 do
    part(15,2+i,"span",1,i,4);node(30,1,(2+i)*2,"pier_1")
  end
  part(15,7,"head_ramp",3)
  for x=28,34 do for z=14,21 do node(x,1,z,"grass1") end end
  for z=8,10 do ordinary(15,z,1,1) end
  vehicle("rail_sh_30",30.5,10.1,math.pi)
end
local views={
  sprung_near={from={x=42.60,y=1.20,z=29.35},at={x=42.58,y=2.68,z=30.5}},
  sprung_far={from={x=54.52,y=1.20,z=31.62},at={x=54.44,y=2.68,z=30.5}},
  harbor={from={x=48,y=7,z=21},at={x=48,y=2.24,z=30.5}},
  stock_ramp={from={x=39.75,y=.95,z=27.7},at={x=43.1,y=2.26,z=30.5}},
  bearing={from={x=48.10,y=.84,z=28.87},at={x=48.88,y=2.54,z=29.89}},
  river={from={x=46,y=-.55,z=25.7},at={x=49.25,y=1.87,z=30.3}},
  contact={from={x=46.93,y=1.35,z=28.69},at={x=48.45,y=3.10,z=30.5}},
  cross_axis={from={x=36.7,y=4.2,z=9},at={x=30.5,y=2.27,z=9.3}},
  flat_head={from={x=28.4,y=1.45,z=1.6},at={x=30.5,y=2.77,z=5.11}},
}
local function position(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.96)
  p:set_sky({type="plain",base_color="#bccfd9",clouds=false})
  for _,f in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do p:hud_set_flags({[f]=false}) end
  position(p,views.harbor)
  if not pending then
    pending=true;local name=p:get_player_name()
    core.emerge_area({x=23,y=-2,z=-4},{x=67,y=6,z=50},function(_,_,left)
      if left==0 then
        build();ready=true
        local who=core.get_player_by_name(name)
        if who then position(who,views.harbor) end
        core.log("action","RAIL_BRIDGE_CATENARY_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showbridgewire",{params="harbor|stock_ramp|bearing|river|contact|cross_axis|flat_head|sprung_near|sprung_far",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    position(p,views[arg]);return true
  end})
