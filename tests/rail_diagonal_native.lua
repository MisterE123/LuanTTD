-- Isolated graphics fixture; compare the same track bits side by side.
local path=core.get_modpath(core.get_current_modname())
local Track=dofile(path.."/rail_track.lua")
local Sim={}
function Sim.id(x,z) if x>=1 and x<=25 and z>=1 and z<=25 then return (z-1)*25+x end end
function Sim.xy(id) return (id-1)%25+1,math.floor((id-1)/25)+1 end
local diagonal=dofile(path.."/rail_diagonal.lua")(Sim,Track)
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for i=0,3 do
  core.register_node("railpreview:ground"..i,{description="Turf",pointable=false,tiles={"bl_grass"..i..".png","bl_grass"..i..".png","bl_grass_side.png"}})
end
local function register(name,asset)
  core.register_node("railpreview:"..name,{description="Stock track preview",drawtype="mesh",
    mesh=asset..".obj",tiles={"bl_rail_atlas.png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
end
for _,bits in ipairs({1,4,8}) do
  register("t"..bits,"bl_rail_track_"..bits)
  if bits~=1 then
    for i=1,3 do register("e"..bits.."_"..i,"bl_rail_eased_"..bits.."_"..i) end
  end
end
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="railpreview:"..n}) end
local function layout()
  for x=0,34 do for z=0,34 do
    node(x,0,z,"ground"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for variant=0,1 do
    local s={tiles={}}
    local function rail(x,z,bits) s.tiles[Sim.id(x,z)]={h=0,owner="QA",rail_tracks=bits} end
    local k=3*variant
    rail(10+k,3,1);rail(9+k,3,8)
    for i=0,5 do
      rail(9+k-i,4+i,4);rail(8+k-i,4+i,8)
    end
    rail(3+k,10,4);rail(2+k,10,1)
    for id,tile in pairs(s.tiles) do
      local x,z=Sim.xy(id)
      local mode=variant==1 and diagonal.mode(s,id) or 0
      node(2*x,1,2*z,mode~=0 and "e"..tile.rail_tracks.."_"..mode or "t"..tile.rail_tracks)
    end
    assert(diagonal.mode(s,Sim.id(6+k,7))==3)
  end
end
core.register_on_joinplayer(function(p)
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd5dd",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  p:set_pos({x=17,y=17,z=16})
  p:set_look_horizontal(0)
  p:set_look_vertical(math.pi/2-.01)
  core.emerge_area({x=-1,y=-1,z=-1},{x=35,y=4,z=35},function(_,_,remaining)
    if remaining==0 then layout();core.log("action","RAIL_DIAGONAL_FIXTURE_READY") end
  end)
end)
