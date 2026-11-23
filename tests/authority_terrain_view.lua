local mod="mods/luanttd_core"
local Sim=dofile(mod.."/sim.lua")
local Terrain=dofile(mod.."/openttd/terrain.lua")
local V=dofile(mod.."/terrain_view.lua")
local P=dofile(mod.."/campaign_authority_projection.lua")()
local grid=Terrain.new(Sim.W,Sim.H,function(_,z) return z end,{max_height=255})
local near=P.subscribe("initial")
local receipt={ok=true,seq=1,tick=74,value={x=4,z=4,width=1,height=1,tiles={}}}
local mask,base,top=Terrain.tile(grid,4,4)
receipt.value.tiles[1]={slope=mask,level=base,top=top}
assert(P.accept("initial",near,receipt))
local ordinary=V(Sim,Terrain,grid)
local projected=V(Sim,Terrain,nil,P)
local id=Sim.id(4,4)
for x=7.5,9.5,.25 do
  for z=7.5,9.5,.25 do
    assert(projected.sample(id,x,z)==ordinary.sample(id,x,z))
  end
end
local origin={x=8,y=20,z=8}
local d={x=0,y=-1,z=0}
assert(projected.pick(origin,d)==id and ordinary.pick(origin,d)==id)
P.unsubscribe("initial")
assert(not projected.pick(origin,d))
assert(not projected.tile(id))
print("PASS native terrain ray geometry matches the exact projected slope; unhydrated sectors have no target")
