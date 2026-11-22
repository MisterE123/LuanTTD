local T=dofile("mods/bayline/openttd/terrain.lua")
local Sim=dofile("mods/bayline/sim.lua")
local grid=T.new(Sim.W,Sim.H,function(x,z)
  if (x==3 and z==3) or (x==4 and z==3) or (x==6 and z==6) then return 1 end
  return 0
end)
local V=dofile("mods/bayline/terrain_view.lua")(Sim,T,grid)
local function close(got,want) assert(math.abs(got-want)<1e-8,got.." ~= "..want) end
assert(V.tile(Sim.id(3,3))==9)
assert(V.tile(Sim.id(6,6))==8)
-- At the middle of a one-corner slope the diagonal is at ground level.
local id,t,hit=V.pick({x=12.5,y=6,z=12.5},{x=0,y=-1,z=0})
assert(id==Sim.id(6,6));close(t,5.5);close(hit.y,.5)
id,t,hit=V.pick({x=11.75,y=6,z=11.75},{x=0,y=-1,z=0})
assert(id==Sim.id(6,6));close(hit.y,1.25)
-- Travel across a flat tile and then hit the descending triangle.
id,t,hit=V.pick({x=9.5,y=3.2,z=11.7},{x=.8,y=-.6,z=0})
assert(id==Sim.id(6,6));close(hit.y,V.sample(id,hit.x,hit.z))
id,t,hit=V.pick({x=9.5,y=3.2,z=11.7},{x=.8,y=-.6,z=0},function(tile) return tile~=Sim.id(6,6) end)
assert(id==nil)
print("PASS: exact ramp and diagonal picking, rejected unavailable tile")
