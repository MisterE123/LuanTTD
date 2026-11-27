local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
Sim.W,Sim.H=64,64
local s=Sim.new(1751)
s.sites={}
local T=dofile(root.."openttd/terrain.lua")
s.corner_grid=T.new(64,64,function() return 2 end)
local id=Sim.id(7,7)
s.tiles[id].site=1
s.sites[1]={id=1,kind="town",name="First",tile=id,population=10}
local A=dofile(root.."campaign_authority_endpoint.lua")(Sim,{world=s,terrain=T,
 terrain_projection=dofile(root.."campaign_terrain_projection.lua")})
local P=dofile(root.."campaign_authority_projection.lua")()
local sub={{key="first",token=P.subscribe("first")}}
local window={x=1,z=1,w=32,h=32,delta_tiles=true}
local seq=0
local function send(ack)
 window.scene=ack
 local r=A.snapshots({window},.5)
 assert(r.ok)
 seq=seq+1;r.seq=seq
 return r,r.value[1]
end
local r,w=send()
assert(w.tiles and #w.tiles==1024 and not w.tile_patch)
assert(P.accept_batch(sub,r))
local key=P.scene("first")
local oldrow=P.terrain(7,7)
s.tiles[id].variant=(s.tiles[id].variant or 0)+1
r,w=send(key)
assert(w.scene_base==key and w.scene~=key and #w.tile_patch==1 and not w.tiles and not w.corners)
assert(P.accept_batch(sub,r))
assert(P.terrain(7,7).surface.variant==s.tiles[id].variant and oldrow.surface.variant~=s.tiles[id].variant)
assert(P.windows()[1].value.registries.sites[1].name=="First")
assert(not P.accept_batch(sub,r))
key=P.scene("first")
s.sites[1].name="Second"
r,w=send(key)
assert(w.scene_base==key and #w.tile_patch==0 and w.registries.sites[1].name=="Second")
assert(P.accept_batch(sub,r))
assert(P.windows()[1].value.registries.sites[1].name=="Second")
key=P.scene("first")
s.sites[1]=nil
r,w=send(key)
assert(w.scene_base==key and #w.tile_patch==0 and next(w.registries)==nil)
assert(P.accept_batch(sub,r))
assert(next(P.windows()[1].value.registries)==nil)
key=P.scene("first")
s.tiles[id].variant=s.tiles[id].variant+1
r,w=send(key)
w.tile_patch[1][2]={id=0}
assert(not P.accept_batch(sub,r) and P.scene("first")==key)
r,w=send(key)
assert(w.tiles and not w.tile_patch)
assert(P.accept_batch(sub,r))
key=P.scene("first")
for z=2,12 do for x=2,12 do
 local t=s.tiles[Sim.id(x,z)]
 t.variant=(t.variant or 0)+1
end end
r,w=send(key)
assert(w.tiles and not w.tile_patch,"dense edits should prefer the full scene")
assert(P.accept_batch(sub,r))
key=P.scene("first")
s.corner_grid.levels[1]=3
r,w=send(key)
assert(w.corners and w.tiles and not w.tile_patch,"corner changes should retain a full immutable terrain packet")
assert(P.accept_batch(sub,r))
print("Exact sparse tile and registry replacement; malformed, stale, dense, corner-edited and initial fallback")

-- A malformed replacement in one sector cannot partially update another.
local second={x=33,z=1,w=32,h=32,delta_tiles=true}
local pair={sub[1],{key="second",token=P.subscribe("second")}}
local function send_pair()
  local result=A.snapshots({window,second},.5)
  assert(result.ok)
  seq=seq+1;result.seq=seq
  return result
end
window.scene=P.scene("first")
local pair_receipt=send_pair()
assert(P.accept_batch(pair,pair_receipt))
window.scene,second.scene=P.scene("first"),P.scene("second")
local t=Sim.id(40,7)
s.tiles[id].variant=(s.tiles[id].variant or 0)+1
s.tiles[t].variant=(s.tiles[t].variant or 0)+1
pair_receipt=send_pair()
local changes=pair_receipt.value[2].tile_patch
changes[2]=changes[1]
assert(not P.accept_batch(pair,pair_receipt))
assert(P.scene("first")==window.scene and P.scene("second")==second.scene)
pair_receipt=send_pair()
assert(pair_receipt.value[1].tiles and pair_receipt.value[2].tiles)
assert(P.accept_batch(pair,pair_receipt))
assert(P.terrain(7,7).surface.variant==s.tiles[id].variant)
assert(P.terrain(40,7).surface.variant==s.tiles[t].variant)
print("Sparse updates validate as one batch and recover with complete snapshots")
