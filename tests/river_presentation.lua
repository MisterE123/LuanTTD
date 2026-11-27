local Sim={W=9,H=7}
local function id(x,z)
  if x>=1 and x<=9 and z>=1 and z<=7 then return (z-1)*9+x end
end
local dirs={{0,-1},{1,0},{0,1},{-1,0}}
function Sim.adjacent(k,d)
  return id((k-1)%9+1+dirs[d][1],math.floor((k-1)/9)+1+dirs[d][2])
end
local S={tiles={}}
for i=1,63 do S.tiles[i]={terrain="grass",h=0} end
for _,r in ipairs({{5,2,2},{5,3,1},{5,4,1},{6,4,0},{7,4,0},{4,3,1},{3,3,0},
    {2,6,1},{3,6,1}}) do
  S.tiles[id(r[1],r[2])]={terrain="water",water_class="river",h=r[3]}
end
S.tiles[id(8,4)]={terrain="water",water_class="sea",h=0}
local M=dofile("mods/luanttd_core/river_presentation.lua")(Sim)
local m=M.routes(S)
assert(m[id(7,4)]=="east" and m[id(6,4)]=="east" and m[id(5,4)]=="east")
assert(m[id(5,3)]=="south" and m[id(5,2)]=="south" and m[id(4,3)]=="east")
assert(not m[id(3,3)] and not m[id(2,6)] and m[id(3,6)]=="west")
S.tiles[id(6,4)]={terrain="grass",h=0}
m=M.routes(S)
assert(m[id(7,4)]=="east" and not m[id(6,4)])
assert(m[id(4,3)]=="west") -- drain direction changes when river is cut
print("PASS: directional shore outlet, tributary, calm pools, uphill protection and terrain edit")

-- Refresh if an outlet changes, but do not rescan unchanged watersheds
-- when an unrelated coast floods. Unknown revisions and changed terrain
-- stay conservative so ordinary landscaping can remove a river.
S.corner_grid={revision=0}
S.topology=0
local scan=M.routes
local scans=0
M.routes=function(...) scans=scans+1;return scan(...) end
local C=M.cached()
local out=id(7,4)
local function check()
  local expected=scan(S)
  for tile in ipairs(S.tiles) do assert(C.at(S,tile)==expected[tile],tile) end
end
check()
assert(scans==1 and C.at(S,out)=="east")
local function tide(x,z,place)
  local old=S.topology
  local tile=id(x,z)
  S.tiles[tile]=place
  S.changed[#S.changed+1]=tile
  S.topology=old+1
  C.after_plain_flood(S,old,#S.changed)
  check()
end
S.changed={id(8,4)} -- older dirty parcels are not part of this tide
tide(8,7,{terrain="water",water_class="sea",h=0})
assert(scans==1 and C.at(S,out)=="east")
tide(7,3,{terrain="water",water_class="sea",h=0})
assert(scans==2 and C.at(S,out)=="north")
S.topology=S.topology+1 -- interleaved non-tide edit
S.tiles[id(7,3)]={terrain="grass",h=0}
tide(7,7,{terrain="water",water_class="sea",h=0})
assert(scans==3 and C.at(S,out)=="east")
S.corner_grid.revision=S.corner_grid.revision+1
check()
assert(scans==4)
print("PASS: distant tides reuse directions; outlet changes, skipped revisions, and shared corner edits rebuild")
