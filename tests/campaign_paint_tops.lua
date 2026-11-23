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
