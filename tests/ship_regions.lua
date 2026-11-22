local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local W=dofile(root.."ship_follow.lua")(T)
local Y=dofile(root.."ship_yapf.lua")(T,W,dofile(root.."yapf_road_search.lua"))
local Regions=dofile(root.."ship_regions.lua")
local width,height=128,64
local function id(x,z)
  if x>=0 and z>=0 and x<width and z<height then return z*width+x end
end
local function xy(n) return n%width,math.floor(n/width) end
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local tiles={}
local B={tile_at=id,xy=xy,tile=function(t) return tiles[t] end}
function B.adjacent(n,d)
  local x,z=xy(n);return id(x+dx[d],z+dz[d])
end
local function put(x,z,kind,attributes)
  local t=attributes or {};t.kind=kind;tiles[id(x,z)]=t
  return id(x,z)
end
local function line(x,y,z,kind)
  for i=x,y do put(i,z,kind or "canal") end
end

-- Multi-region narrow canal, including an axis-constrained stock lock
-- attached to ordinary navigable water at the region boundary.
line(4,109,10)
local lock=put(31,10,"lock",{dir=T.SW,water_class="canal"})
for x=16,30 do put(x,14,"sea") end -- separated patch in region (1,0)
local R=Regions(T,W,B,{width=width,height=height})
assert(R.patch_info(id(16,10)).label==1 and R.patch_info(id(16,14)).label==2)
assert(R.patch_info(id(16,12)).label==0)
assert(R.region(id(16,14))==1 and R.region_patch(id(16,14))==2)
assert(R.patch_info(lock).key==257 and R.center(R.patch_info(lock))==id(24,8))
local adj=R.neighbors(R.patch_info(lock))
assert(#adj==2 and adj[1].x==0 and adj[2].x==2 and R.info(1,0).edge[2]==2^10)
assert(#R.neighbors(R.patch_info(id(16,14)))==0)
local path,stats=R.find(id(5,10),{id(109,10)},5)
assert(#path==5 and path[1].x==0 and path[5].x==4 and stats.cost==605)
assert(R.find(id(16,14),{id(109,10)})[1]==nil)
assert(#R.find(id(5,10),{id(14,10)})==1)
local multi=R.find(id(5,10),{id(109,10),id(16,14),id(35,10)})
assert(#multi==3 and multi[#multi].x==2) -- closer reachable target beats earlier/farther one
local back=R.find(id(109,10),{id(5,10)},5)
assert(#back==5 and back[1].x==6 and back[5].x==2)
local _,limit=R.find(id(109,10),{id(5,10)},5,{max_region_nodes=1})
assert(limit.capped and limit.closed==1)
local sw=T.diagonal_trackdir(T.SW)
local v={tile=id(5,10),ocean_speed_frac=0,canal_speed_frac=0}
local low,cost,high=R.find_route(Y,v,v.tile,T.trackdirbit(sw),id(6,10),{kind="tile",tile=id(109,10)})
assert(type(low)=="table" and #high==5 and low[#low].tile==id(64,10) and cost==(64-5)*100)
assert(R.cost({x=0,z=0},{x=1,z=0},{x=1,z=2})==200)
assert(R.cost({x=0,z=0},{x=1,z=0},{x=4,z=0})==301)
assert(R.cost(nil,{x=0,z=0},{x=3,z=0})==300)

-- Directional boundary: nonflat coast's only available corner opens to
-- -X/-Z, not +X. Adjacent water alone cannot join these two patches.
line(11,19,20,"sea")
local a,b=id(14,20),id(17,20)
R.invalidate(id(15,20))
assert(#R.find(a,{b})==2)
put(15,20,"coast",{slope=2})
R.invalidate(id(15,20))
assert(R.info(0,1).edge[2]==0 and R.info(1,1).edge[0]==0)
assert(#R.find(a,{b})==0)
assert(R.region_patch(id(15,20))~=0)
put(15,20,"sea")
R.invalidate(id(15,20))
assert(R.info(0,1).edge[2]==2^4 and R.info(1,1).edge[0]==2^4)
assert(#R.find(a,{b})==2)

-- Direct cross-region aqueduct qualifies even when no edge tiles line up,
-- with different underlying level-zero water not joining the elevated run.
local near=put(13,31,"aqueduct",{dir=T.SW,other=id(57,31),skip=43})
local far=put(57,31,"aqueduct",{dir=T.NE,other=near,skip=43})
line(10,12,31)
line(58,60,31)
for x=15,55 do put(x,30,"river") end
R.invalidate(near);R.invalidate(far)
local left,right=id(10,31),id(60,31)
local na=R.neighbors(R.patch_info(left))
assert(#na==1 and na[1].x==3 and na[1].z==1)
assert(R.info(0,1).cross_aqueduct and R.info(3,1).cross_aqueduct)
assert(R.info(0,1).edge[2]~=2^15 and R.info(3,1).edge[0]~=2^15)
assert(#R.find(id(31,30),{right})==0)
local shortcut,region_stat=R.find(left,{right})
assert(#shortcut==2 and shortcut[1].x==0 and shortcut[2].x==3 and region_stat.cost==300)
assert(#R.find(right,{left})==2)
v.tile=left
low,cost,high=R.find_route(Y,v,left,T.trackdirbit(sw),id(11,31),{kind="tile",tile=right})
assert(#high==2 and #low==8 and low[4].tile==near and low[5].tile==far)
assert(cost==(60-10)*100)
-- A high-level corridor restriction is passed only to the second low-level attempt.
local rounds=0
local proxy=setmetatable({find=function(board,...)
  rounds=rounds+1
  if rounds==1 then assert(not board.region_corridor);return false end
  assert(board.region_corridor[shortcut[1].region] and board.region_corridor[shortcut[2].region])
  assert(not board.region_corridor[shortcut[1].region+1])
  return Y.find(board,...)
end},{__index=Y})
assert(R.find_route(proxy,v,left,T.trackdirbit(sw),id(11,31),{kind="tile",tile=right}))
assert(rounds==2)

-- Adjacent within-region aqueduct's nonconsecutive pixel positions must
-- become one local patch rather than a boundary link. Remove both heads.
local local_near=put(70,39,"aqueduct",{dir=T.SW,other=id(75,39),skip=4})
local local_far=put(75,39,"aqueduct",{dir=T.NE,other=local_near,skip=4})
put(69,39,"canal");put(76,39,"canal")
R.invalidate(local_near);R.invalidate(local_far)
assert(R.region_patch(local_far)==R.region_patch(local_near) and not R.info(4,2).cross_aqueduct)
tiles[local_near]=nil;tiles[local_far]=nil;R.invalidate(local_near);R.invalidate(local_far)
assert(R.info(4,2).count==2)

-- Only physically adjacent docking water goes into the multi-origin set.
local marker=put(110,8,"dock",{station=91,water_part=true})
local berth2=put(110,9,"sea",{docking=true})
local berth1=put(109,8,"sea",{docking=true})
local inland=put(105,8,"sea",{docking=true})
R.invalidate(berth1)
function B.station_dock_tiles(s) assert(s==91);return {berth2,inland,marker,berth1,berth1} end
local slots=R.target_tiles({kind="station",station=91})
assert(#slots==3 and slots[1]==berth1 and slots[2]==berth1 and slots[3]==berth2)

-- LuanTTD can use partial edge regions on a 1-based map, without indexing
-- the unused rows or returning a heuristic center outside the map.
local P=Regions(T,W,B,{x0=1,z0=1,width=17,height=20})
local p=P.patch_info(id(17,20))
assert(p.region==3 and P.center(p)==id(17,20))
print("PASS: stock water regions/patches, reciprocal direction, lock, paired aqueducts, backward high-level route, lookahead/fallback and cache invalidation")
