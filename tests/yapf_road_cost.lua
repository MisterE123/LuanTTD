local F=dofile("mods/bayline/openttd/yapf_road_follow.lua")
local C=dofile("mods/bayline/openttd/yapf_road_cost.lua")(F)
local tiles={}
local function id(x,y) return y*16+x end
local function xy(i) return i%16,math.floor(i/16) end
local by_dir={[0]=-1,16,1,-16}
local board={
  tile=function(i) return tiles[i] end, xy=xy, tile_at=id,
  adjacent=function(i,d) return i+by_dir[d] end,
  center_z=function(i) return (tiles[i] and tiles[i].z) or 0 end,
  stop_continues=function(a,b)
    local t,p=tiles[a],tiles[b]
    return p and p.kind=="drive_stop" and p.station==t.station and p.dir==t.dir
  end,
  stop_entry=function(i,d) return tiles[i].occupied[d] or 0,tiles[i].length end,
  bay_free=function(i,b) return not tiles[i].taken[b] end,
  station_area=function(st,facility)
    assert(st==42 and facility=="bus")
    return {tile=id(6,0),w=2,h=1},id(5,2)
  end
}
local function set(x,y,bits,kind)
  local t={kind=kind or "road",roadtype=0,road_bits=bits,owner="A"}
  tiles[id(x,y)]=t
  return t
end
local v={tile=id(0,0),owner="A",bus=true,display_max_speed=100}
local sw=F.direction_trackdir(F.SW)
set(0,0,8,"depot").dir=F.SW
set(1,0,14)
set(2,0,10)
local middle=set(3,0,10)
set(4,0,10)
set(5,0,14)
local dest=set(6,0,10,"drive_stop")
dest.dir,dest.stop_type,dest.station,dest.length,dest.occupied=F.NE,"bus",42,16,{}
set(7,0,10)
set(1,1,3)
set(5,1,9)
for x=2,4 do set(x,1,10) end
local d=C.destination(board,v,{kind="station",station=42})
assert(d.tile==id(6,0) and C.detect(board,d,id(6,0),sw))
v.tile=id(11,2)
assert(C.destination(board,v,{kind="station",station=42}).tile==id(7,0))
v.tile=id(0,0)
assert(C.estimate(board,d,{last_tile=id(0,0),last_td=sw,cost=0})==500)
assert(C.estimate(board,d,{last_tile=id(1,1),last_td=sw,cost=20})==462)

-- Cost along otherwise equivalent route branches, with and without an off-order stop.
-- Follow actual stock trackdirs at every joint, sum separate segments without writing a search.
local function branch(points,entry)
  local node
  for j=1,#points do
    local tile=points[j]
    local td=F.direction_trackdir(entry)
    if j<#points then
      local next_tile=points[j+1]
      local exit
      for k=0,3 do if tile+by_dir[k]==next_tile then exit=k end end
      for _,candidate in ipairs(F.trackdirs(F.origin_trackdirs(tiles[tile],false,entry))) do
        if F.exit_direction(candidate)==exit then td=candidate; break end
      end
      entry=exit
    end
    node={tile=tile,td=td,parent=node}
    node.cost=(node.parent and node.parent.cost or 0)+C.one_tile(board,tile,td)
  end
  return node.cost
end
local straight={id(1,0),id(2,0),id(3,0),id(4,0),id(5,0),id(6,0)}
local around={id(1,0),id(1,1),id(2,1),id(3,1),id(4,1),id(5,1),id(5,0),id(6,0)}
assert(branch(straight,F.SW)==500+900)
assert(branch(around,F.SW)==984+900)
middle.kind,middle.dir,middle.station,middle.occupied,middle.length="drive_stop",F.NE,43,{},16
assert(branch(straight,F.SW)==1300+900)
assert(not C.detect(board,d,id(3,0),sw))

-- The segment boundary is at the old tile, not the junction it approaches.
-- Raising the junction costs nothing on this segment, whereas raising the
-- interior tile does. Destination wins over maximum cost at that tile.
local start={tile=id(2,0),td=sw,parent={cost=15}}
tiles[id(5,0)].z=6
assert(C.calc(board,v,d,start) and start.last_tile==id(4,0) and start.cost==1115)
middle.z=2
assert(C.calc(board,v,d,start) and start.cost==1315)
middle.z=0
assert(not C.calc(board,v,d,start,nil,100))
start={tile=id(6,0),td=sw}
assert(C.calc(board,v,d,start,nil,1) and start.cost==900)
middle.occupied[F.SW]=5
assert(C.one_tile(board,id(3,0),sw)==1150)
local prev=tiles[id(2,0)]
prev.kind,prev.dir,prev.station="drive_stop",F.NE,43
assert(C.one_tile(board,id(3,0),sw)==900)
prev.kind="road"
middle.kind,middle.taken="bay_stop",{[0]=true}
assert(C.one_tile(board,id(3,0),sw,{road_stop_bay_occupied_penalty=1501})==850)
middle.kind="crossing"
assert(C.one_tile(board,id(3,0),sw)==400)
middle.kind="road"

-- Speeds use the old tile and stock integer division.
prev.road_speed=67
v.order_max_speed=41
start={tile=id(2,0),td=sw}
assert(C.calc(board,v,d,start) and start.cost==300+math.floor(100*15*4/82))
-- Dead end without choices returns to the same start state and is rejected.
tiles={}
set(8,5,10)
set(9,5,10)
assert(not C.calc(board,v,d,{tile=id(8,5),td=sw}))
-- A depot entrance ends a segment before reversing; a bay reverses within it.
tiles={}
local endpoint=set(9,5,8,"depot")
endpoint.dir=F.NE
local origin=set(8,5,10)
local early={tile=id(8,5),td=sw}
assert(C.calc(board,v,d,early) and early.last_tile==id(9,5) and early.cost==200)
endpoint.kind,endpoint.stop_type,endpoint.station,endpoint.taken="bay_stop","bus",42,{}
assert(C.detect(board,d,id(9,5),sw))
d.non_articulated=false
assert(not C.detect(board,d,id(9,5),sw))
-- Skipped tunnel/bridge tiles and bridge speed are charged together.
tiles={}
local a,b=set(8,5,0,"bridge"),set(12,5,0,"bridge")
a.dir,a.other,a.skip,a.bridge_speed=F.SW,id(12,5),3,30
b.dir,b.other,b.skip=F.NE,id(8,5),3
v.order_max_speed=nil
local exact=C.destination(board,v,{kind="tile",tile=id(12,5)})
local span={tile=id(8,5),td=sw}
assert(C.calc(board,v,exact,span) and span.last_tile==id(12,5) and span.cost==780)
local depot=C.destination(board,v,{kind="any_depot"})
assert(C.estimate(board,depot,span)==780)
print("PASS: 14.1 road costs, segment boundaries, destination and off-order stop tradeoff (Lua fixture)")

local S=dofile("mods/bayline/openttd/yapf_road_search.lua")(F,C)
tiles={}
set(0,0,2,"depot").dir=F.SW
set(1,0,14)
set(2,0,10)
local optional=set(3,0,10)
set(4,0,10)
set(5,0,14)
set(1,1,3)
for x=2,4 do set(x,1,10) end
set(5,1,9)
local ordered=set(6,0,10,"drive_stop")
ordered.dir,ordered.station,ordered.stop_type,ordered.occupied,ordered.length=F.NE,42,"bus",{},16
set(7,0,10)
v.tile=id(0,0)
d=C.destination(board,v,{kind="station",station=42})
local function route()
  local found,best=S.find(board,v,v.tile,2^sw,d)
  assert(found)
  local path=S.trace(board,v,d,best)
  local sequence={}
  for _,p in ipairs(path) do sequence[#sequence+1]=p.tile end
  return best.cost,table.concat(sequence,",")
end
local c,path=route()
assert(c==1400 and path=="0,1,2,3,4,5,6",c..":"..path)
optional.kind,optional.dir,optional.station,optional.stop_type="drive_stop",F.NE,43,"bus"
optional.occupied,optional.length={},16
c,path=route()
assert(c==1884 and path=="0,1,17,18,19,20,21,5,6",c..":"..path)
local found,best,stats=S.find(board,v,v.tile,2^sw,d,{max_search_nodes=1})
assert(not found and best and stats.capped and stats.closed_count==1)
assert(S.find(board,v,v.tile,2^sw,d,{disable_node_optimization=true}))
assert(S.find(board,v,v.tile,2^sw,d,{max_search_nodes=0}))
-- No destination can be reached beyond a severed complete row.
tiles[id(6,0)]=nil
found,best=S.find(board,v,v.tile,2^sw,d)
assert(not found and best~=nil and best.last_tile~=id(6,0))
found,best=S.find(board,v,v.tile,2^sw,d,{max_search_nodes=0})
assert(not found and best==nil)
print("PASS: source YAPF search prefers ordinary short route, avoids off-order stop, respects node limits")

local R=dofile("mods/bayline/openttd/road_track_choice.lua")(F,C,S)
tiles[id(6,0)]=ordered
local order,cache={kind="station",station=42},{}
local choice,path_found,why=R.choose(board,v,id(1,0),F.SW,order,cache)
assert(F.exit_direction(choice)==F.SE and path_found and why=="search")
local bent=choice
cache={{tile=id(1,0),td=bent}}
choice,path_found,why=R.choose(board,v,id(1,0),F.SW,order,cache)
assert(choice==bent and path_found==nil and why=="cached" and #cache==0)
-- Cache an exit that is deleted, but leave the fork as a junction.
-- The extra west/northward leg keeps a real alternative trackdir.
cache={{tile=id(1,0),td=bent}}
tiles[id(1,0)].road_bits=11
tiles[id(1,1)]=nil
choice,path_found,why=R.choose(board,v,id(1,0),F.SW,order,cache)
assert(choice==sw and why=="search" and path_found)
cache={{tile=id(1,0),td=bent}}
tiles[id(1,0)].road_bits=10
choice,path_found,why=R.choose(board,v,id(1,0),F.SW,order,cache)
assert(choice==sw and why=="unique" and path_found==nil and #cache==0)
cache={{tile=id(1,0),td=bent}}
tiles[id(1,0)].road_bits=8
choice,path_found,why=R.choose(board,v,id(1,0),F.SW,order,cache)
assert(choice==14 and why=="reverse" and #cache==0)
print("PASS: source bus junction decision and removed-exit cache invalidation")
