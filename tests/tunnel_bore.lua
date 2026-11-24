local base="mods/luanttd_core/"
local Bore=dofile(base.."tunnel_bore.lua")
local Terrain=dofile(base.."openttd/terrain.lua")
local Projection=dofile(base.."campaign_terrain_projection.lua")
local Sim={W=3,H=2}
local function id(x,z) return (z-1)*Sim.W+x end
local function xy(at) return (at-1)%Sim.W+1,math.floor((at-1)/Sim.W)+1 end
Sim.xy=xy
local grass="luanttd_core:grass1"
local pave="luanttd_core:road_10_plain_2"
local slope="luanttd_core:slope_fill_open"
local definitions={
  [grass]={tiles={"grass","bottom","outer"}},
  [pave]={tiles={"road_top","bottom","outer"}},
  [slope]={tiles={"slope_without_top"}},
}
local nodes={}
local function reg(name,tiles,def)
  local n="luanttd_core:"..name
  nodes[n]={tiles=tiles,def=def}
  return n
end
local cut=Bore.mount(reg,definitions)
for _,info in ipairs({{"road",0},{"road",1},{"rail",0},{"rail",1}}) do
  local mode,axis=unpack(info)
  for half=0,1 do
    local boxes=Bore.collision(mode,axis,half).fixed
    assert(#boxes==9)
    local lateral=axis==0 and 3 or 1
    local sign=half==0 and 1 or -1
    for _,box in ipairs(boxes) do
      assert(box[5]==.5,"lost the original walkable ground surface")
      assert(not (box[lateral]<sign*.347 and box[lateral+3]>sign*.347 and box[2]<-.13),
        "a normal road lane or railway path is not physically open")
    end
  end
end
local east,west,unloaded=id(3,1),id(1,1),id(1,2)
local middle=id(2,1) -- used by two separate receipts below
local s={corner_grid=Terrain.new(3,2,function()return 5 end),tiles={},
  tunnel_below={[middle]=8},stock_road_tunnels={[8]={start=west,["end"]=east,base=4,
    head={inside_direction=2},middle_by_tile={[middle]=true,[unloaded]=true}}},
}
for i=1,6 do s.tiles[i]={terrain="grass",h=5,variant=1} end
s.tiles[west].road_tunnel_id=8
s.tiles[east].road_tunnel_id=8
s.tiles[middle].build="road"
local shape=dofile(base.."campaign_visual_state.lua")(Sim,{})
local rows={{id=middle,surface=Projection.tile(s.tiles[middle])}}
local function accept()
  shape.accept({windows=function()return {{value={x=2,z=1,width=1,height=1,tiles=rows,
    corners=Projection.corners(Terrain,s.corner_grid,2,1,1,1),registries=Projection.registries(s,rows)}}} end})
end
accept()
local projected=shape.state
local outer=cut(projected,middle,4,5,2,pave)
local inner=cut(projected,middle,4,5,3,grass)
assert(nodes[outer].tiles[1]=="road_top" and nodes[inner].tiles[1]=="grass")
assert(outer:match("_lamp$") and nodes[outer].def.mesh:match("_lamp%.obj$"))
assert(nodes[outer].tiles[3]=="bl_tunnel_lining_brick_lit.png" and
  nodes[outer].tiles[5]=="bl_tunnel_lamp_lens.png" and not nodes[outer].def.light_source)
assert(not inner:match("_lamp$") and not cut(projected,middle,5,5,2,pave):match("_lamp$"))
local odd=assert(cut(projected,middle,4,5,3,slope))
assert(nodes[odd].def.mesh:match("_1_1%.obj$") and nodes[odd].tiles[1]=="slope_without_top")
local warm_floor=cut(projected,middle,4,4,2,pave)
local ambient_floor=cut(projected,middle,5,4,2,pave)
assert(warm_floor:match("tunnel_floor_road_0_0_lit$") and ambient_floor:match("tunnel_floor_road_0_0$"))
assert(nodes[warm_floor].def.light_source==nodes[ambient_floor].def.light_source)
for i,box in ipairs(nodes[outer].def.collision_box.fixed) do
  for axis,label in ipairs(box) do
    assert(nodes[cut(projected,middle,5,5,2,pave)].def.collision_box.fixed[i][axis]==label)
  end
end
assert(not cut(projected,middle,4,6,2,pave) and not cut(projected,middle,4,3,2,pave))
assert(not cut(projected,middle,4,5,2,"luanttd_core:ocean_top_0_0"),"bore cut a water node")
assert(not cut(projected,middle,4,5,2,"luanttd_core:stock_rail_1"),"bore cut a legitimate mesh overlay")
assert(not cut(projected,unloaded,2,5,4,grass) and not cut(s,west,2,5,2,grass))
-- Demolition clears only the underground projection; painting must
-- immediately go back to exactly the prior roof/solid/floor identities.
s.tunnel_below[middle]=nil
accept()
assert(not cut(projected,middle,4,5,2,pave) and not cut(projected,middle,4,4,2,grass))
assert(s.tiles[middle].h==5 and s.tiles[middle].build=="road" and Terrain.corner(s.corner_grid,2,1)==5)
s.rail_tunnel_below={[middle]=1};s.stock_rail_spans={[1]={kind="tunnel",axis=1,base=3,
  start=id(2,2),middle_by_tile={[middle]=true}}}
accept()
assert(cut(projected,middle,4,4,2,grass):match("_rail_1_0_0_lamp$"))
assert(cut(projected,middle,5,3,2,grass):match("tunnel_floor_rail_1_1_lit$"))
assert(cut(projected,middle,5,3,3,grass):match("tunnel_floor_rail_1_1$"))
assert(not cut(projected,middle,4,5,2,grass))
print("PASS real road/rail bore section, interior-only lamps with unchanged collision/roof, sparse projection and teardown")
