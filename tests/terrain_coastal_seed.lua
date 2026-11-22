local root="mods/bayline/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local seed=dofile(root.."terrain_coastal_seed.lua")
local s=Sim.new(1751)
dofile(root.."town_layout.lua")(Sim,s)
local before=dofile(root.."terrain_preview.lua")(Sim,Terrain,s)
local g,r=seed(Sim,Terrain,s,before)
local flat,danger,wet=0,0,0
for z=1,Sim.H do for x=1,Sim.W do
  local t=s.tiles[Sim.id(x,z)]
  local old,base=Terrain.tile(before,x,z)
  local mask,h,high=Terrain.tile(g,x,z)
  assert(t.h==h and high>=h)
  if t.terrain=="water" then
    assert(old==0 and mask==0 and base==0 and h==0);wet=wet+1
  else
    if old==0 and base==0 then danger=danger+1 end
    if mask==0 and h==0 then flat=flat+1 end
    if t.house or t.site then assert(high>0,"Fresh starter needs a dry bank at existing buildings") end
  end
end end
assert(wet==399 and danger==1291 and flat<10 and r.raised>1200 and r.shores>0 and r.inland>1100)
assert(before~=g and before.revision==g.revision and g.revision==0)
print(("PASS: 399 sea tiles preserved, 1,291 original dry flats at level zero reduced to %d; %d shaped shore tiles and %d inland dry tiles."):format(flat,r.shores,r.inland))
