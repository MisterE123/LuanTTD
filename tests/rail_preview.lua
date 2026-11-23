-- Feed the placement renderer the real AutoRail quote, then compare
-- every ghost against the committed same-height diagonal presentation.
local root="mods/luanttd_core/"
local Track=dofile(root.."openttd/rail_track.lua")
local Slope=dofile(root.."openttd/slope.lua")
local Sim,S={}, {tiles={},companies={},topology=0}
function Sim.id(x,z) if x>=0 and x<100 and z>=0 and z<100 then return z*100+x+1 end end
function Sim.xy(id) return (id-1)%100,math.floor((id-1)/100) end
for i=1,10000 do S.tiles[i]={h=2,terrain="grass"} end
function Sim.company(s,n)
  s.companies[n]=s.companies[n] or {cash=100000,expense=0,month_exp=0}
  return s.companies[n]
end
local function terrain(id) local t=S.tiles[id];return t.slope or 0,t.h end
local Lab=dofile(root.."trackworks.lua")(Sim,Track,nil,Slope,nil,nil,terrain)
local api={Sim=Sim,s=S,terrain={tile=terrain},trackworks=Lab,render={update=function() end},save=function() end}
local Build=dofile(root.."rail_construction_tools.lua")(api,Lab,Track,nil,{track=function() return 2 end})
local Ghost=dofile(root.."rail_preview.lua")(api,root)
local Diagonal=dofile(root.."rail_diagonal.lua")(Sim,Track,api.terrain,Lab.surface)
local function aim(x,z) return {x=16*x+8,z=16*z+8} end
local p=assert(Build.quote_autotrack("QA",aim(5,5),aim(15,15)))
assert(#p.pieces>10)
local g=Ghost(p.pieces,"QA",{x=15,z=15})
assert(#g==#p.pieces and g[1].mesh:match("eased_.*_[12]%.obj$")
  and g[#g].mesh:match("eased_.*_[12]%.obj$"))
for i=2,#g-1 do assert(g[i].mesh:match("eased_.*_3%.obj$"),g[i].mesh) end
for _,q in ipairs(g) do assert(not S.tiles[q.id].rail_tracks and q.pos.y==3.038) end
assert(Build.build("QA",p))
for i,q in ipairs(g) do
  local mode=Diagonal.mode(S,q.id)
  assert(q.mesh==("bl_rail_eased_%d_%d.obj"):format(p.pieces[i].tracks,mode))
end
-- A neighboring piece that already exists participates in placement.
-- A connection to a turnout or another railhead elevation is not eased.
local a,b=Sim.id(50,50),Sim.id(50,51)
local r={id=a,tracks=8}
S.tiles[b].rail_tracks,S.tiles[b].owner=4,"QA"
assert(Ghost({r},"QA")[1].mesh=="bl_rail_eased_8_2.obj")
S.tiles[b].owner="Other"
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].owner,S.tiles[b].rail_tracks="QA",5
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].rail_tracks,S.tiles[b].h=4,3
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].h,S.tiles[b].rail_type=2,1
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].rail_type=nil
assert(Ghost({{id=a,tracks=9}},"QA")[1].mesh=="bl_rail_track_9.obj")
S.tiles[a].slope=3
local grade=Ghost({{id=a,tracks=1}},"QA")[1]
assert(grade.mesh=="bl_rail_grade_1.obj" and grade.pos.y==4.038)
-- A valid very long diagonal must never skip every other quoted tile.
local long=assert(Build.quote_autotrack("QA",aim(1,20),aim(73,92)))
assert(#long.pieces>96)
local window=Ghost(long.pieces,"QA",{x=100,z=130})
assert(#window==96 and window[1].mesh:match("_3%.obj$"))
local indices={}
for i,item in ipairs(long.pieces) do indices[item.id]=i end
for i=2,#window do assert(indices[window[i].id]==indices[window[i-1].id]+1) end
print("PASS: AutoRail placement ghosts exactly match built diagonals; preview is read-only, handles adjoining tracks, turnouts and grades; long ghosts stay connected")
