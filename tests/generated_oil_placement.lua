-- SPDX-License-Identifier: GPL-2.0-only
-- RC1-proven placement catalog and ordinary native oil world mounts.
local root="mods/luanttd_core/"
local function m(name) return dofile(root..name..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local P,Rating,Income=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,Rating)
local Coal=m("openttd/coal_industry")(P,Rating,C,Income)
local Timber=Sim.timber_rules()
local Farm=m("openttd/farm_factory_industry")(P,C,Rating,Income,Coal,Timber)
local w=Sim.new(9183)
Sim.W,Sim.H=128,128
w.tiles,w.sites={},{[1]={id=1,kind="town",tile=Sim.id(56,56),name="Test Town"}}
w.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 2 end,{freeform_edges=true})
for i=1,Sim.W*Sim.H do w.tiles[i]={terrain="grass",h=2,variant=1} end
w.road_farm,w.road_timber=true,true -- not mutually exclusive in generated worlds.
local OilWorld=assert(Sim.mount_oil_world(w,Terrain,true))
local Oil=assert(Sim.oil_rules())
local W=m("openttd/industry_worldgen")(Coal,Timber,Oil,Farm)
local board={width=Sim.W,height=Sim.H,freeform=true,towns={{id=1,x=55,z=55}}}
function board.tile(x,z)
  local t=w.tiles[Sim.id(x+1,z+1)]
  return t and {kind=t.stock_industry and "industry" or "clear",slope=0,base=2}
end
assert(W.specs[4].kind=="oil_refinery" and W.specs[11].kind=="oil_well")
assert(W.specs[6].kind=="factory" and W.specs[9].kind=="farm")
assert(W.probability(board,4,{density=4})==32) -- 64 on 256; coast scales 1D
assert(W.probability(board,11,{density=4})==16) -- 64 on 256; land scales area
assert(W.probability(board,6,{density=4})==20 and W.probability(board,9,{density=4})==36)
assert(W.probability(board,4,{density=0})==0)
local rejected,why=W.quote(board,4,64,64,0)
assert(not rejected and why=="REFINERY_NOT_NEAR_EDGE")
assert(W.quote(board,4,64,64,0,{editor=true}))
local refinery=assert(W.quote(board,4,20,60,0))
assert(tonumber(refinery.type)==4 and #refinery.cells==15)
rejected,why=W.quote(board,11,34,61,0,nil,{refinery})
assert(not rejected and why=="INDUSTRY_TOO_CLOSE") -- directional source <=14
assert(W.quote(board,4,20,60,0,nil,{{type=11,x=34,z=61,town=1}}))
rejected,why=W.quote(board,9,61,60,0,nil,{{type=6,x=57,z=58,town=1}})
assert(not rejected and why=="INDUSTRY_TOO_CLOSE")
local function place(plan)
  local rng=0
  W.initialize(plan,0,44,function()rng=rng+1;return rng end)
  local record=W.record(plan,0,{year=1950})
  local ind,parts,site=OilWorld.place_generated(w,plan.kind,Sim.id(plan.x+1,plan.z+1),
    {record=record,name="Test Town "..plan.name})
  assert(ind,parts)
  assert(ind.town==1 and ind.site==site.id and site.industry_chain=="oil" and site.stock_industry==ind.id)
  assert(ind.random==44 and ind.random_colour==1 and ind.tiles[1].random_bits==2)
  assert(not ind.tiles[1].completed and ind.tiles[1].construction_counter==3)
  for i,part in ipairs(parts) do
    assert(part.id==part.tile and w.tiles[part.id].stock_industry.gfx==ind.tiles[i].gfx)
  end
  return ind
end
local r=place(refinery)
local a=place(assert(W.quote(board,11,44,61,0,nil,{refinery})))
assert(a.id==r.id+1 and a.produced[1].last.production==96)
assert(not w.tiles[Sim.id(24,61)].stock_industry,"Refinery's unoccupied stock hole was filled")
assert(w.stock_oil_placements[r.id].source_type==4 and w.stock_oil_placements[a.id].source_type==11)
a.removed=true
assert(#OilWorld.sweep_closed(w)==5 and not w.tiles[Sim.id(45,62)].stock_industry and
  w.sites[a.site].closed and not w.sites[r.site].closed)
print("PASS generated Oil and Farm RC1 catalog, edge/directional conflict/weights, exact footprints and oil lifecycle state")
