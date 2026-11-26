local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
Sim.W,Sim.H=128,128
local Terrain=dofile(mod.."openttd/terrain.lua")
local Rules=dofile(mod.."openttd/canal_dikes.lua")
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
for id in ipairs(s.tiles) do s.tiles[id]={h=0,terrain="grass",variant=1} end
local function tile(id) return Terrain.tile(s.corner_grid,Sim.xy(id)) end
local View=dofile(mod.."canal_dike_surface.lua")(Sim,s,tile,Rules)
local center=Sim.id(16,16)
local pos={left=Sim.id(15,16),down=Sim.id(16,17),right=Sim.id(17,16),up=Sim.id(16,15),corner=Sim.id(17,17)}
local function water(id,class)
  s.tiles[id]={h=0,terrain="water",variant=1,water_class=class or "sea"}
end
local function dry(id)
  s.tiles[id]={h=0,terrain="grass",variant=1}
end
assert(View.mask(center)==nil)
water(center,"canal")
assert(View.mask(center)==255)
water(pos.down);water(pos.right)
assert(View.mask(center)==649)
water(pos.corner)
assert(View.mask(center)==137)
s.tiles[center].ship={kind="buoy",water_class="canal"}
assert(View.mask(center)==137)
s.tiles[center].ship={kind="ship_depot",water_class="canal"}
assert(View.mask(center)==137)
s.tiles[center].ship={kind="lock",part="lower",dir=1,water_class="canal"}
assert(View.mask(center)==nil,"The lock has its own bank/wall art")
s.tiles[center].ship=nil
water(pos.up,"river")
assert(View.describe(pos.up).kind=="clear_water")
s.tiles[pos.left].ship={kind="aqueduct",dir=0}
assert(View.describe(pos.left).kind=="aqueduct" and Rules.watered(View.describe(pos.left),5,View.describe(center)))
s.tiles[pos.left].ship={kind="aqueduct",dir=2}
assert(not Rules.watered(View.describe(pos.left),5,View.describe(center)))
dry(pos.up);dry(pos.left)
local P=dofile(mod.."campaign_terrain_projection.lua")
local endpoint=dofile(mod.."campaign_authority_endpoint.lua")(Sim,{
  world=s,terrain=Terrain,terrain_projection=P,canal_dikes=View,
})
local window={x=16,z=16,w=1,h=1}
local function scene(mask,changed)
  local packet=assert(endpoint.snapshots({window},0).value)[1]
  if changed then
    assert(packet.scene~=window.scene and packet.tiles[1].surface.canal_dikes==mask)
  else
    assert(packet.scene==window.scene and not packet.tiles,"A static mask must not resend terrain")
  end
  window.scene=packet.scene
end
scene(137,true)
scene(nil,false)
dry(pos.corner)
scene(649,true) -- changed tile is outside the single-tile snapshot
scene(nil,false)
water(pos.corner)
scene(137,true)
assert(s.tiles[center].canal_dikes==nil,"Derived geometry must never mutate the saved world")
s.tiles[center].stock_canal=nil
s.tiles[center].water_class="sea"
scene(nil,true)
print("PASS canal dikes: host classification, diagonal-only authoritative scene invalidation, and no save/topology mutation")
