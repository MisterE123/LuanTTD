local path="mods/luanttd_core/"
local function m(n) return dofile(path..n..".lua") end
local Sim,T,Track=m("sim"),m("openttd/terrain"),m("openttd/rail_track")
local Wire=m("rail_turnout_wire")(Sim,Track,m("openttd/rail_wire_mask")(Track))
Sim.W,Sim.H=64,64
local s=Sim.new(55);s.corner_grid=T.new(64,64)
s.tiles,s.fleet={},{}
for i=1,4096 do s.tiles[i]={terrain="grass",h=0} end
local x,z=32,32
local id=Sim.id(x,z)
local function rail(u,v,bits,gauge)
  s.tiles[Sim.id(u,v)]={terrain="grass",h=0,build="stock_rail",rail_tracks=bits,rail_type=gauge}
end
assert(Wire.supported(3) and Wire.supported(63) and Wire.supported(25))
assert(Wire.supported(12) and Wire.supported(48) and not Wire.supported(64))
rail(x,z,63,1)
rail(x-1,z,1,1)
rail(x+1,z,1,0)
rail(x,z-1,2,1)
rail(x,z+1,2,0)
local A=m("campaign_authority_endpoint")(Sim,{world=s,terrain=T,terrain_projection=m("campaign_terrain_projection"),
  rail_wire_mask=Wire.at})
local function read(known)
  local r=A.snapshots({{x=x,z=z,w=1,h=1,scene=known}})
  assert(r.ok,r.why)
  return r.value[1]
end
local a=read()
assert(#a.tiles==1 and a.tiles[1].id==id and a.tiles[1].rail_wire==4)
assert(not read(a.scene).tiles)
rail(x+1,z,1,1)
local b=read(a.scene)
assert(#b.tiles==1 and b.tiles[1].rail_wire==21 and b.scene~=a.scene)
rail(x,z+1,2,1)
local c=read(b.scene)
assert(#c.tiles==1 and c.tiles[1].rail_wire==63 and c.scene~=b.scene)
assert(not read(c.scene).tiles)
print("PASS bounded worker rail junction receipt tracks three exact mask changes from neighbors outside its single subscribed tile")
-- An independent electric pair retains the authority's exact smooth
-- approach even if this view doesn't have the complementary tile.
local D=m("rail_diagonal")(Sim,Track,{tile=function(at)
  return T.tile(s.corner_grid,Sim.xy(at))
end})
local C=m("rail_scene_context")
A=m("campaign_authority_endpoint")(Sim,{world=s,terrain=T,terrain_projection=m("campaign_terrain_projection"),
  rail_wire_mask=Wire.at,rail_scene_context=C.make(Sim,D,{tile=function(at)return T.tile(s.corner_grid,Sim.xy(at))end})})
rail(x,z,12,1)
rail(x,z-1,8,1)
rail(x,z+1,2,0)
rail(x+1,z,1,0)
local paired=read()
assert(paired.tiles[1].rail_wire==4 and C.dual(paired.tiles[1].rail_diagonal,12)=="12_2_0")
rail(x+1,z,1,1);rail(x,z+1,2,1)
local both=read(paired.scene)
assert(both.tiles[1].rail_wire==12 and C.dual(both.tiles[1].rail_diagonal,12)=="12_2_0")
print("PASS an independent pair keeps the same exact eased railway when its other wire comes live outside the subscribed tile")
