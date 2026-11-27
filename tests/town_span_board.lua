local mod="mods/luanttd_core/"
local G=dofile(mod.."openttd/town_growth.lua")
local Worldgen=dofile(mod.."openttd/town_worldgen.lua")(G)
local project=dofile(mod.."town_generation_board.lua")
local S=dofile(mod.."openttd/town_spans.lua")(G)
local size=64
local Sim={W=size,H=size,bridge_deck_at=function()end}
function Sim.id(x,z) return x+(z-1)*size end
function Sim.xy(id) return (id-1)%size+1,math.floor((id-1)/size)+1 end
local state={tiles={},stock_road_bridges={}}
local desc={}
for i=1,size*size do state.tiles[i]={} end
local function read(x,z)
  if x<1 or z<1 or x>size or z>size then return end
  local d=desc[Sim.id(x,z)] or {}
  local t={kind="clear",slope=0,base=2}
  for k,v in pairs(d) do t[k]=v end
  return t
end
local board=project(Sim,{},state,G,Worldgen,read)
assert(board.town_level_crossings)
local a,b=Sim.id(35,35),Sim.id(41,35)
state.tiles[a].road_bridge_id=1;state.tiles[b].road_bridge_id=1
state.stock_road_bridges[1]={start=a,["end"]=b,head={inside_direction=2},tail={inside_direction=0}}
desc[a]={slope=8}
assert(board.parallel_bridge(32,32,5,12))
assert(not board.parallel_bridge(32,32,2,12))
assert(not board.parallel_bridge(32,32,5,3))
desc[a]={slope=0}
assert(not board.parallel_bridge(32,32,5,12))
desc[a]={slope=8}
state.tiles[a].road_bridge_id=nil
desc[a].kind="rail_bridge"
assert(not board.parallel_bridge(32,32,5,12))
desc[Sim.id(41,40)]={kind="rail",plain_track=2,plain_rail=true}
local quotes=0
Sim.town_road_piece=function(_,who,id,bits)
  assert(who==1 and id==Sim.id(41,40) and bits==8)
  quotes=quotes+1;return true
end
assert(S.continues({id=1},board,40,40,2) and quotes==1)
state.stock_road_town_policy={allow_town_level_crossings=false}
local disabled=project(Sim,{},state,G,Worldgen,read)
assert(not S.continues({id=1},disabled,40,40,2) and quotes==1)
print("PASS native town span board: radius-based parallel road bridge veto, rail bridge exclusion and stock crossing setting")
