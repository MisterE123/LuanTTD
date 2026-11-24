local base="mods/luanttd_core/"
local L=dofile(base.."world_place_labels.lua")
local Sim={W=512,H=512}
function Sim.id(x,z) return (z-1)*Sim.W+x end
function Sim.xy(id)return (id-1)%Sim.W+1,math.floor((id-1)/Sim.W)+1 end
local high,id=Sim.id(13,9),Sim.id(100,9)
local board={sites={
    [1]={id=1,tile=high,kind="town",name="Upland",population=610},
    [2]={id=2,tile=id,kind="factory",name="Distant Mill"},
    [3]={id=3,tile=Sim.id(300,9),kind="town",name="Outside"},
    [4]={id=4,tile=Sim.id(42,9),kind="farm",name="Closed",closed=true},
  },tiles={},
}
for _,site in pairs(board.sites) do board.tiles[site.tile]={h=17} end
board.tiles[id].stock_industry={kind="oil_rig"}
local function peek(tile) return tile==high and 20 or 17 end
local rows=L.describe(Sim,board,20,18,peek)
assert(#rows==2 and rows[1].name=="Upland" and rows[1].y==25 and rows[1].population==610)
assert(rows[2].name=="Distant Mill" and rows[2].y==27.5)
assert(not rows[1].dist and L.stop_height(board.tiles[high],20)==22.25)
assert(L.place_radius>L.stop_radius and L.within(10,10,311,10,L.place_radius) and not L.within(10,10,311,10,L.stop_radius))
for n=5,280 do
  local tile=Sim.id(n,8)
  board.sites[n]={id=n,tile=tile,kind="town",name=tostring(n)}
  board.tiles[tile]={h=2}
end
rows=L.describe(Sim,board,20,18,peek)
assert(#rows==L.max_places and #rows==64 and rows[1].name=="10")
print("PASS labels follow terrain/roof height, far sites do not require visible terrain, stops stay local, payload capped")
