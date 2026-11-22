local H=dofile("mods/luanttd_core/house_frontage.lua")
local Sim=dofile("mods/luanttd_core/sim.lua")
local id=Sim.id(10,10)
local house={house=true,h=1}
local expected={{1,1,2},{0,1,1},{0,0,0},{1,0,3}}
local function frontage(S,stage,parcel)
  return table.concat({H.placement(Sim,S,id,house,stage,parcel)},",")
end
for direction=1,4 do
  local near=Sim.adjacent(id,direction)
  local state={tiles={[id]=house,[near]={build="road",road_town=3,h=1}}}
  local e=expected[direction]
  local c=expected[(direction+1)%4+1]
  assert(H.road(Sim,state,id,house)==direction)
  assert(frontage(state)==table.concat(e,","))
  assert(frontage(state,1)==table.concat(c,","))
  assert(frontage(state,nil,"shop")==table.concat(e,","))
  assert(frontage(state,nil,"market")=="0,0,0" and frontage(state,1,"green")=="0,0,0")
  house.site=9;assert(frontage(state)=="0,0,0");house.site=nil
  state.tiles[near].build="road_depot";assert(frontage(state)=="0,0,0")
end
local north,east=Sim.adjacent(id,1),Sim.adjacent(id,2)
local S={tiles={[north]={build="road",road_town=1,h=2},[east]={build="road",h=1}}}
assert(H.road(Sim,S,id,house)==2,"closer curb preferred")
S.tiles[north].h=1
assert(H.road(Sim,S,id,house)==1,"town street wins at the same curb height")
S.tiles[east].road_town=2
local winner=H.road(Sim,S,id,house)
for i=1,5 do assert(H.road(Sim,S,id,house)==winner,"corner tie should not flicker") end
assert(not house.facedir and not S.tiles[east].facedir,"art must not mutate saved state")
print("PASS: four physical house fronts, stage correction, static civic lots, deterministic street choice")
