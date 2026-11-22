local Sim={W=64,H=64,tools={road={mode="road"}}}
function Sim.id(x,z)
  if x>=1 and z>=1 and x<=Sim.W and z<=Sim.H then return (z-1)*Sim.W+x end
end
function Sim.xy(id) return (id-1)%Sim.W+1,math.floor((id-1)/Sim.W)+1 end
local S={tiles={},sites={}}
local function reset(n)
  Sim.W,Sim.H=n,n
  S.tiles={}
  for i=1,n*n do S.tiles[i]={terrain="grass",h=1} end
end
local M=dofile("mods/luanttd_core/jump_map.lua")({Sim=Sim,s=S})
reset(64)
S.tiles[1].stock_void=true
S.tiles[Sim.id(42,49)].station=1
local _,targets,cols,rows,stride,wide,marker=M.cells({},Sim.id(58,61))
assert(cols==64 and rows==64 and stride==1 and not wide)
assert(targets[1]==nil and targets[Sim.id(42,49)]==Sim.id(42,49) and targets[4096]==4096)
assert(marker[1]==57 and marker[2]==60)
local form={map_targets=targets,map_sites={[2]=42}}
assert(M.pick(form,{jump_4096=true})==4096 and M.pick(form,{jump_1=true})==nil)
assert(M.pick(form,{jump_site_2=true})==42 and M.pick(form,{jump_4097=true})==nil)
reset(128)
local right_corner=Sim.id(128,128)
S.tiles[right_corner].build="road"
_,targets,cols,rows,stride,wide=M.cells({},right_corner)
assert(cols==64 and rows==64 and stride==2 and wide and targets[4096]==right_corner)
local x,z=M.layout({map_zoom=true},right_corner)
assert(x==65 and z==65)
_,targets,cols,rows,stride,wide=M.cells({map_zoom=true},right_corner)
assert(cols==64 and rows==64 and stride==1 and wide and targets[1]==Sim.id(65,65) and targets[4096]==right_corner)
print("PASS full-region density, exact tile clicks, void protection, bounded wide overview and local detail")
assert(M.pick_coordinates("128","128")==right_corner)
assert(M.pick_coordinates(" 42 ","49")==Sim.id(42,49))
S.tiles[1].stock_void=true
for _,pair in ipairs({{"1","1"},{"129","5"},{"22","0"},{"1.5","2"},{"1e2","2"},{"1",false},{"-1","2"}}) do
  assert(not M.pick_coordinates(pair[1],pair[2]))
end
print("PASS exact coordinate jumps accept playable integers only")
