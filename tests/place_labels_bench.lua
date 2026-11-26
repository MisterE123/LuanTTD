-- Reproducible CPU benchmark for the observation part of the authority worker.
-- lua tests/place_labels_bench.lua [number of camera queries] [unmodified label module]
local L=dofile("mods/luanttd_core/world_place_labels.lua")
local prior=arg[2] and dofile(arg[2]) or L
local terrain=dofile("mods/luanttd_core/openttd/terrain.lua")
local Sim={W=4096,H=4096}
function Sim.id(x,z)return (z-1)*Sim.W+x end
function Sim.xy(id)return (id-1)%Sim.W+1,math.floor((id-1)/Sim.W)+1 end
-- A flat lazy terrain object, as used for wide campaign worlds. Only
-- station-site records are allocated; the benchmark measures labels alone.
local board={sites={},tiles={}}
local corners={width=Sim.W,depth=Sim.H,levels=setmetatable({}, {__index=function()return 0 end})}
for z=1,64 do
  for x=1,64 do
    local i=#board.sites+1
    local tile=Sim.id(x*63+(z*19+x*11)%39,z*63+(z*17+x*23)%41)
    board.sites[i]={id=i,kind=i%3==0 and "town" or "factory",name="Site "..i,tile=tile,population=i%1200}
    board.tiles[tile]={h=0}
  end
end
local function top(_,x,z)local _,_,y=terrain.tile(corners,x,z);return y end
local samples=tonumber(arg[1]) or 2000
local function run(labels,index)
  local hash,rows=0,0
  collectgarbage("collect")
  local time=os.clock()
  for i=1,samples do
    local results=labels.describe(Sim,board,(353*i)%8192,(437*i)%8192,top,280,index)
    rows=rows+#results
    for _,r in ipairs(results) do hash=(hash*127+r.id+r.y)%2147483647 end
  end
  return (os.clock()-time)*1000,hash,rows
end
local index=L.site_index(Sim,board)
local a,ha,ra=run(prior)
local b,hb,rb=run(L,index)
assert(ha==hb and ra==rb and ra>0)
print(("4096² / %d sites / %d queries / %d labels: %.3f → %.3f ms/query (%.2fx, includes cold indexing); checksum %d"):format(
  #board.sites,samples,ra,a/samples,b/samples,a/b,ha))
