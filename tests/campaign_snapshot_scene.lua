local mod="mods/luanttd_core"
local Sim=dofile(mod.."/sim.lua")
Sim.W,Sim.H=128,128
local T=dofile(mod.."/openttd/terrain.lua")
local P=dofile(mod.."/campaign_terrain_projection.lua")
local s=Sim.new(1751)
s.corner_grid=T.new(Sim.W,Sim.H,function() return 0 end)
local function at(x,z) return Sim.id(x,z) end
local visible=at(33,33)
s.tiles[visible]={
  terrain="grass",variant=1,h=0,house=true,water_class="river",site=1,
  source_house={id=12,completed=false,stage=1},wood={type=2,count=3,private_table={}},
}
s.sites[1]={id=1,kind="town",tile=visible,name="Herring Cove",population=100}
local out_before=P.tile(s.tiles[visible])
assert(P.matches_tile(s.tiles[visible],out_before))
s.tiles[visible].wood.count=4
assert(not P.matches_tile(s.tiles[visible],out_before))
s.tiles[visible].wood.count=3
s.tiles[visible].wood.private_function=function() end
s.tiles[visible].wood.private_table={not_exported={a=2}}
s.tiles[visible].warehouse="non-projected"
assert(P.matches_tile(s.tiles[visible],out_before),"projection must ignore omitted fields/depth")
s.tiles[visible].wood.type=nil
assert(not P.matches_tile(s.tiles[visible],out_before),"removing a projected subfield invalidates the exact view")
s.tiles[visible].wood.type=2
local projections=0
local Projection=setmetatable({tile=function(t) projections=projections+1;return P.tile(t) end},{__index=P})
local direction,aspect="east",false
local worker=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,{
  world=s,terrain=T,terrain_projection=Projection,
  river_direction=function() return direction end,
  rail={signals_at=function(id,signals) if id==visible then signals[id]=aspect end end},
  actors=function(_,_,_,_,f) return {{key="road:1",x=f}} end,
  passengers={counts=function() return {boarded=s.day} end,events=function(_,cursor) return {{from=cursor}},s.day end},
})
local window={x=33,z=33,w=32,h=32}
local function sample(changed)
  local old=window.scene
  local r=worker.snapshots({window},.75)
  assert(r.ok and #r.value==1)
  local p=r.value[1]
  assert(p.actors[1].x==.75 and p.signals[visible]==aspect)
  assert(p.passengers.boarded==s.day and p.boarding_cursor==s.day)
  if changed then assert(p.scene~=old and p.tiles and #p.tiles==1024)
  else assert(p.scene==old and not p.tiles and not p.registries and not p.corners) end
  window.scene=p.scene
  return p
end
local first=sample(true)
assert(first.tiles[1].surface.source_house.stage==1 and projections==1024)
s.day=1;aspect=true
sample(false)
assert(projections==1024,"fresh motion, aspects, and passengers cannot rebuild static tile payload")
s.tiles[at(100,100)].terrain="water"
s.topology=s.topology+1
sample(false)
assert(projections==1024,"remote construction cannot invalidate acknowledged tile data")
s.tiles[visible].source_house.stage=2
local edited=sample(true)
assert(edited.tiles[1].surface.source_house.stage==2 and first.tiles[1].surface.source_house.stage==1)
assert(projections==1025,"one nested house edit should detach only one tile")
assert(edited.tiles[2]==first.tiles[2],"neighboring row was rebuilt with no change")
local other=at(61,62)
local past=edited.tiles[(62-33)*32+(61-33)+1]
s.tiles[other].variant=(s.tiles[other].variant or 0)+1
s.tiles[visible].source_house.stage=3
local changed_two=sample(true)
assert(projections==1027,"two distant changes in one sector should detach exactly two tiles")
assert(changed_two.tiles[(62-33)*32+(61-33)+1]~=past and changed_two.tiles[2]==first.tiles[2])
assert(changed_two.tiles[1].surface.source_house.stage==3 and edited.tiles[1].surface.source_house.stage==2)
s.tiles[visible].source_house.stage=nil
edited=sample(true)
assert(edited.tiles[1].surface.source_house.stage==nil)
s.sites[1].population=104
local n=projections
edited=sample(true)
assert(edited.registries.sites[1].population==104 and projections==n,"registry change must send updated data without reallocating static tile rows")
s.corner_grid.levels[(33-1)*(Sim.W+1)+33]=1 -- direct corner change without topology/revision
edited=sample(true)
assert(edited.tiles[1].slope~=0 and edited.corners:byte(1)==1,"corner without revision must invalidate geometry")
direction="north" -- computed river direction can change outside local table writes
edited=sample(true)
assert(edited.tiles[1].river_direction=="north")
n=projections
sample(false)
assert(projections==n)
local current=window.scene
window.scene=first.scene
local retry=assert(worker.snapshots({window},.75).value)[1]
assert(retry.scene==current and retry.tiles and retry.corners and retry.registries,
  "a stale subscriber must receive full scene")
window.scene=current
for z=1,33 do assert(worker.snapshots({{x=1,z=z,w=1,h=1}},.75).ok) end
sample(true) -- LRU ejected the old sector; receipt is now stale
assert(not worker.snapshots({{x={},z=1,w=32,h=32}},.75).ok)
print("PASS worker scene cache: static rows reused; exact nested/corner/river/registry updates, actor/queue/aspect freshness, retry, LRU eviction")

do
  local source={terrain="grass",h=10,wood={count=2},simulation_only={scheduling=123}}
  local view=P.tile(source)
  assert(not view.simulation_only and P.matches_tile(source,view))
  source.simulation_only.scheduling=444
  view.canal_dikes=3
  assert(P.matches_tile(source,view),"Non-tile fields do not participate in the tile comparison")
  source.wood=nil
  assert(not P.matches_tile(source,view),"A deleted field must invalidate a warm view")
  local overlay=setmetatable({road_bits=3},{__index={terrain="grass",h=10}})
  local inherited=P.tile(overlay)
  assert(inherited.h==10 and inherited.road_bits==3 and P.matches_tile(overlay,inherited))
  print("PASS: sparse projection notices deletions, respects the whitelist, and preserves preview overlays")
end
