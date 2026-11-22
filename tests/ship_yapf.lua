local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local W=dofile(root.."ship_follow.lua")(T)
local S=dofile(root.."ship_yapf.lua")(T,W,dofile(root.."yapf_road_search.lua"))
local function id(x,z) if x>=0 and x<64 and z>=0 and z<64 then return z*64+x end end
local function xy(i) return i%64,math.floor(i/64) end
local records={}
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local B={xy=xy,tile=function(i) return records[i] end}
function B.adjacent(i,d)
  local x,z=xy(i)
  return id(x+dx[d],z+dz[d])
end
local function place(x,z,kind,attrs)
  attrs=attrs or {};attrs.kind=kind;records[id(x,z)]=attrs;return id(x,z)
end
local ship={ocean_speed_frac=0,canal_speed_frac=128}

-- Neither owns the underlying passage. Locks and ship-depot cells follow
-- their axis in both directions; they are not one-way *or* forced reversals.
local low=place(2,5,"sea")
local canal=place(3,5,"canal")
local lock=place(4,5,"lock",{dir=T.SW,water_class="river"})
local river=place(5,5,"river")
local jetty=place(6,5,"ship_depot",{axis=T.X,owner="someone else",water_class="canal"})
place(4,4,"river")
local sw,ne=T.diagonal_trackdir(T.SW),T.diagonal_trackdir(T.NE)
for _,step in ipairs({{low,canal},{canal,lock},{lock,river},{river,jetty}}) do
  local f=W.follow(B,ship,step[1],sw)
  assert(f.ok and f.tile==step[2] and T.has(f.trackdirs,sw) and not f.bridge)
  local other=W.follow(B,ship,step[2],ne)
  assert(other.ok and other.tile==step[1] and T.has(other.trackdirs,ne))
end
assert(not W.follow(B,ship,id(4,4),1).ok,"cannot enter a lock across the wrong axis")
assert(W.follow(B,ship,jetty,sw).tile==id(7,5) and not W.follow(B,ship,jetty,sw).ok)
assert(S.tile_cost(B,ship,low,sw,sw,0)==100)
assert(S.tile_cost(B,ship,canal,sw,sw,0)==200)
assert(S.tile_cost(B,ship,river,sw,sw,0)==200)
assert(S.tile_cost(B,ship,lock,sw,sw,0)==200)

local coast=place(8,8,"coast",{slope=8})
local sea=place(8,9,"sea")
assert(W.at(B,coast)==T.trackdirs(8) and W.water_class(records[coast])=="sea")
assert(W.follow(B,ship,sea,9).trackdirs==T.trackdirbit(11))
local ends=place(9,8,"sea")
assert(W.follow(B,ship,coast,11).tile==ends)
assert(W.at(B,place(0,0,"sea"))==T.trackdirs(8)) -- lower corner only survives both boundaries
assert(W.at(B,place(0,3,"buoy",{water_class="river"}))==T.trackdirs(2+8+16))
assert(W.at(B,place(0,4,"shore_rail",{rail_bits=8,slope=2}))==T.trackdirs(4))
assert(W.water_class(records[id(0,4)])=="sea")
assert(W.at(B,place(4,15,"river",{slope=3}))==0)

-- Actual aqueduct mouths take the straight paired transition, while open
-- river below keeps its own water class and route. Entering the local
-- mouth by going away from the paired end is forbidden even on its axis.
place(9,12,"canal")
local a=place(10,12,"aqueduct",{dir=T.SW,other=id(15,12),skip=4})
local z=place(15,12,"aqueduct",{dir=T.NE,other=a,skip=4})
place(16,12,"canal")
local ground=place(12,12,"river")
assert(W.follow(B,ship,id(9,12),sw).tile==a)
local jump=W.follow(B,ship,a,sw)
assert(jump.ok and jump.tile==z and jump.skip==4 and jump.bridge and jump.trackdirs==T.trackdirbit(sw))
assert(W.follow(B,ship,z,ne).tile==a)
assert(W.follow(B,ship,z,sw).tile==id(16,12))
place(11,12,"river")
assert(not W.follow(B,ship,id(11,12),ne).ok)
assert(W.follow(B,ship,ground,ne).tile==id(11,12) and not W.follow(B,ship,ground,ne).bridge)
assert(S.tile_cost(B,ship,z,sw,sw,4)==1000)
local d=S.destination(B,ship,{kind="tile",tile=id(16,12)})
local found,best=S.find(B,ship,id(9,12),T.trackdirbit(sw),d)
assert(found and best.cost==1400)
local route=S.trace(B,ship,d,best)
assert(#route==4 and route[2].tile==a and route[3].tile==z)

-- Stock line choice reacts to speed fractions and penalized turns, not
-- just shortest tiles. All water by the 'southern' curve is a canal.
records={}
local origin=place(4,20,"sea")
local target=place(13,20,"sea")
for q=5,12 do place(q,20,"sea") end
for x=4,13 do place(x,23,"canal") end
for j=21,22 do place(4,j,"canal");place(13,j,"canal") end
local fast_inland={ocean_speed_frac=244,canal_speed_frac=0}
local fast_ocean={ocean_speed_frac=0,canal_speed_frac=224}
d=S.destination(B,fast_inland,{kind="tile",tile=target})
local both=T.union(T.trackdirbit(sw),T.trackdirbit(1))
local won,canals=S.find(B,fast_inland,origin,both,d)
local won2,oceans=S.find(B,fast_ocean,origin,both,d)
assert(won and won2)
local inland_trace=S.trace(B,fast_inland,d,canals)
local ocean_trace=S.trace(B,fast_ocean,d,oceans)
assert(inland_trace[2].tile==id(4,21) and ocean_trace[2].tile==id(5,20))
assert(#inland_trace>#ocean_trace)
-- The higher-level route can externally supply an allowed-region set and
-- an intermediate patch destination; without it low-level search is free.
function B.region(i) local _,y=xy(i);return y==20 and "north" or "south" end
function B.region_patch(i) local x=xy(i);return x>=10 and "right" or "left" end
B.region_corridor={north=true}
local restricted,forced=S.find(B,fast_inland,origin,both,d)
assert(restricted and S.trace(B,fast_inland,d,forced)[2].tile==id(5,20))
B.region_corridor=nil
local rdest=S.destination(B,fast_ocean,{kind="region",tile=id(11,20),region="north",patch="right"})
local hit,latest=S.find(B,fast_ocean,origin,both,rdest)
assert(hit and latest.tile==id(10,20))

-- Physical commercial dock is not a vehicle path tile. The docking
-- region matches only marked *adjacent water*, can include multiple
-- alternatives, and occupied alternatives cost 300 per visible ship.
local harbor=place(13,19,"dock",{station=55,water_part=true,water_class="sea"})
records[target].docking=true
local right=place(14,19,"sea",{docking=true})
assert(W.at(B,harbor)==0)
assert(W.ship_destination(B,target,55) and W.ship_destination(B,right,55))
assert(not W.ship_destination(B,id(12,20),55))
assert(not W.ship_destination(B,target,56))
function B.docking_occupancy(i) return i==target and 2 or 0 end
assert(S.tile_cost(B,ship,target,sw,sw,0)==700)
assert(S.tile_cost(B,ship,right,sw,sw,0)==100)
function B.closest_station_tile(st,from) assert(st==55 and from==origin);return harbor end
fast_ocean.tile=origin
d=S.destination(B,fast_ocean,{kind="station",station=55})
local yes,arrival=S.find(B,fast_ocean,origin,both,d)
assert(yes and arrival.tile==target)
print("PASS: directional sea/coast/river/canal/locks, paired aqueducts, distinct docks, speed-weighted ship YAPF alternatives")
