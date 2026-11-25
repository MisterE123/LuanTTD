local R=dofile("mods/luanttd_core/openttd/town_rebuild.lua")
local shape={width=2,depth=2,minimum_life=3}
local t={x=6,z=7,growing=true}
local house={x=5,z=5,root=true,completed=true,age=2}
assert(not R.visit(t,house,shape,true,0) and not t.time_until_rebuild)
house.age=3
for i=1,9 do assert(not R.visit(t,house,shape,true,0) and t.time_until_rebuild==10-i) end
assert(not R.visit(t,house,shape,false,0) and t.time_until_rebuild==1)
house.root=false
assert(not R.visit(t,house,shape,true,0) and t.time_until_rebuild==1)
house.root=true
local q=assert(R.visit(t,house,shape,true,12*2^24+255*2^16))
assert(t.time_until_rebuild==447 and q.clear.x==5 and q.clear.z==5)
assert(q.replace.x==6 and q.replace.z==6)
for _,k in ipairs({{1,1,5,5},{1,2,5,6},{2,1,6,5}}) do
  t.time_until_rebuild=1
  q=assert(R.visit(t,house,{width=k[1],depth=k[2]},true,12*2^24))
  assert(q.replace.x==k[3] and q.replace.z==k[4] and t.time_until_rebuild==192)
end
t.time_until_rebuild=1;t.x,t.z=1,2
q=assert(R.visit(t,house,shape,true,11*2^24+19*2^16))
assert(q.replace==nil and t.time_until_rebuild==211)
t.time_until_rebuild=1
q=assert(R.visit(t,house,shape,true,12*2^24))
assert(q.replace.x==house.x and q.replace.z==house.z)
t.time_until_rebuild=0
assert(not R.visit(t,house,shape,true,0) and t.time_until_rebuild==65535)
print("PASS stock root/counter guards, reused word, clear-only chance and footprint replacement toward town centre")

local p="mods/luanttd_core/"
local function m(n)return dofile(p..n..".lua")end
local Sim=m("sim");Sim.W,Sim.H=64,64
local T,G,H=m("openttd/terrain"),m("openttd/town_growth"),m("openttd/town_passengers")
local W=m("town_growth_runtime")(Sim,T,G,m("openttd/town_growth_build")(G,m("openttd/town_growth_houses")),H)
local s=Sim.new(1751)
for id in pairs(s.tiles) do s.tiles[id]={h=1,terrain="grass",variant=0} end
s.corner_grid=T.new(64,64,function()return 1 end)
s.stock_generated_profile={}
s.sites={{id=1,kind="town",tile=Sim.id(12,12),name="Foundation",population=65}}
local t=G.new(1,12,12,{population=65,num_houses=1,growing=true})
t.time_until_rebuild=1
s.stock_town_growth={version=1,towns={[1]=t},order={1}}
t.unique={stadium=true}
t.house_counts={[20]=1,[21]=1,[22]=1,[23]=1}
for i=0,1 do for j=0,1 do
  local cell=s.tiles[Sim.id(8+i,8+j)]
  cell.house,cell.source_house=true,{id=0x14+i*2+j,x=8+i,z=8+j,town=1,asset_root=0x14,asset_part=i*2+j,
    root=i+j==0 or nil,root_x=8,root_z=8,completed=true}
end end
local id=Sim.id(8,8)
local h=s.tiles[id].source_house
local child=s.tiles[Sim.id(9,9)].source_house
local cash=Sim.company(s,"Other owner").cash
local function no_draw()error("Clear-only town rebuild must reuse the completed house's existing random word")end
child.player_protected=true
assert(not W.rebuild(s,h,id,0,18,no_draw) and t.time_until_rebuild==1)
child.player_protected=nil
assert(not W.rebuild(s,child,Sim.id(9,9),0,20,no_draw) and t.time_until_rebuild==1)
local demolished=assert(W.rebuild(s,h,id,11*2^24+7*2^16,30,no_draw))
assert(not demolished.replace and t.time_until_rebuild==199 and t.num_houses==0
  and t.population==0 and s.sites[1].population==0 and not t.unique.stadium)
for i=0,1 do for j=0,1 do
  local part=Sim.id(8+i,8+j)
  assert(not s.tiles[part].house and not s.tiles[part].source_house
    and s.tiles[part].stock_clear_density==0 and t.house_counts[0x14+i*2+j]==0)
end end
assert(#s.changed==4 and Sim.company(s,"Other owner").cash==cash)
print("PASS live town-owned clearance removes and dirties a complete compound parcel once with no company charge")
