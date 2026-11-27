local V=dofile("mods/luanttd_core/campaign_visual_state.lua")({W=32,H=32},{})
local W={value={x=1,z=1,width=4,height=2,tiles={},corners=string.rep("\1",15),
  registries={bridge_above={[2]=12},stock_road_bridges={[12]={deck=14}},
    rail_bridge_above={[3]=9},stock_rail_spans={[9]={deck=16}},
    aqueduct_above={[4]=7},stock_aqueducts={[7]={deck=8},[8]={deck=12}},
    stock_farm_fields={[33]={base=19}},
    stock_road_tunnels={[2]={base=5}}}}}
for i,id in ipairs{1,2,3,4,33,34,35,36} do
  W.value.tiles[i]={id=id,top=1,surface={h=1}}
end
local rows=W.value.tiles
rows[6].surface.level_crossing={top=20}
rows[7].surface.ship={kind="aqueduct",aqueduct=8}
rows[8].surface.road_tunnel_id=2
V.accept({windows=function() return {W} end})
local tops=V.state.paint_tops
for i,expected in ipairs{4,17,19,11,22,23,15,8} do assert(tops[rows[i].id]==expected,i) end
W.value.registries.bridge_above=nil
V.accept({windows=function() return {W} end})
assert(V.state.paint_tops[2]==4 and V.state.paint_tops[3]==19 and not V.state.paint_tops[5])
print("PASS visual column heights are local, include stock layer anchors, and drop after authoritative removal")

-- Simulate two ordered receipts over the same tile, then remove the
-- newer window and finally the older one. The painter and click ray must
-- use the same canonical slope as the readonly projection either way.
local P=dofile("mods/luanttd_core/campaign_authority_projection.lua")()
local terrain=dofile("mods/luanttd_core/openttd/terrain.lua")
local sim={W=32,H=32,xy=function(id) return (id-1)%32+1,math.floor((id-1)/32)+1 end}
local view=dofile("mods/luanttd_core/terrain_view.lua")(sim,terrain,nil,nil,V.terrain_row)
local function add(key,seq,row)
  assert(P.accept(key,P.subscribe(key),{ok=true,seq=seq,tick=2,revision=seq,
    value={x=1,z=1,width=1,height=1,tiles={row},corners=string.rep("\\1",4)}}))
end
add("newer",8,{id=1,top=5,level=4,slope=3,surface={h=4}})
add("older",7,{id=1,top=2,level=1,slope=6,surface={h=1}})
for _,remove in ipairs({"newer","older","other"}) do
  V.accept(P)
  local row=P.terrain(1,1)
  assert(V.terrain_row(1)==row and not V.terrain_row(2))
  if row then
    local slope,level,top=view.tile(1)
    assert(slope==row.slope and level==row.level and top==row.top and V.state.tiles[1]==row.surface)
    assert(view.sample(1,2,2)==.5+terrain.normalized_height(slope,level,.25,.25))
  else
    assert(not view.tile(1) and not view.sample(1,2,2) and not V.state.tiles[1])
  end
  P.unsubscribe(remove)
end
print("PASS installed terrain rows agree with the projection across overlap, replacement and eviction")
