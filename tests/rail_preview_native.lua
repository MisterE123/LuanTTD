-- Render the old and new placement ghosts side-by-side using the same
-- terrain, track bits, approach and observer. No world editor required.
local path=core.get_modpath("luanttd_core").."/"
local Track=dofile(path.."openttd/rail_track.lua")
local Autorail=dofile(path.."openttd/autorail.lua")(Track)
local S={tiles={}}
local Sim={}
function Sim.id(x,z) if x>=0 and x<25 and z>=0 and z<25 then return z*25+x+1 end end
function Sim.xy(id) return (id-1)%25,math.floor((id-1)/25) end
for i=1,625 do S.tiles[i]={h=0} end
local selector=dofile(path.."tile_selector.lua")({
  Sim=Sim,s=S,terrain={tile=function() return 0,0 end},
  trackworks={surface=function() return 0,0 end},
})
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for i=0,3 do
  core.register_node("luanttd_core:turf"..i,{description="Turf",pointable=false,
    tiles={"bl_grass"..i..".png","bl_grass"..i..".png","bl_grass_side.png"}})
end
for _,bits in ipairs({2,5}) do
  core.register_node("luanttd_core:built"..bits,{description="Built track",drawtype="mesh",
    mesh="bl_rail_track_"..bits..".obj",tiles={"bl_rail_atlas.png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
end
core.register_entity("luanttd_core:legacy_ghost",{
  initial_properties={visual="mesh",mesh="bl_rail_track_1.obj",
    textures={"bl_rail_atlas.png^[colorize:#78ffda:165^[opacity:180"},
    visual_size={x=10,y=10,z=10},use_texture_alpha=true,physical=false,
    pointable=false,collide_with_objects=false,static_save=false,glow=9,shaded=false},
  on_activate=function(self,name) self.object:set_observers({[name]=true}) end,
})
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="luanttd_core:"..n}) end
local function build_fixture(p)
  for x=0,34 do for z=0,34 do
    node(x,0,z,"turf"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for variant=0,1 do
    local k=5*variant
    local pieces,ids={},{}
    local b,u,v=Autorail.snap(16*(9+k)+8,16*4+8,16*(3+k)+8,16*10+8)
    for _,q in ipairs(assert(Autorail.trace(9+k,4,u,v,b))) do
      local id=Sim.id(q.x,q.z)
      ids[#ids+1]=id
      pieces[#pieces+1]={id=id,tracks=2^q.track}
    end
    local first,last=ids[1],ids[#ids]
    local candidates={{10+k,4},{3+k,11}}
    for i,c in ipairs(candidates) do
      local vertex=Sim.id(c[1],c[2])
      local bits=i==1 and 5 or 2
      S.tiles[vertex].rail_tracks,S.tiles[vertex].owner=bits,p:get_player_name()
      node(2*c[1],1,2*c[2],"built"..bits)
    end
    if variant==0 then
      selector.area(p,ids,last,first,"valid")
      for _,record in ipairs(pieces) do
        local x,z=Sim.xy(record.id)
        local e=core.add_entity({x=2*x,y=1.038,z=2*z},"luanttd_core:legacy_ghost",p:get_player_name())
        e:set_properties({mesh="bl_rail_track_"..record.tracks..".obj"})
      end
    else selector.rail(p,pieces) end
  end
  for i,label in ipairs({"Before: curved tiles + outlines","After: continuous placement ghost"}) do
    p:hud_add({type="text",position={x=(i==1 and .28 or .72),y=.17},alignment={x=0,y=0},text=label,number=0xf7edcc})
  end
end
core.register_on_joinplayer(function(p)
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd5dd",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  p:set_pos({x=17,y=17,z=14})
  p:set_look_horizontal(0)
  p:set_look_vertical(math.pi/2-.01)
  core.emerge_area({x=-1,y=-1,z=-1},{x=35,y=4,z=35},function(_,_,remaining)
    if remaining==0 then build_fixture(p);core.log("action","RAIL_DIAGONAL_FIXTURE_READY") end
  end)
end)
