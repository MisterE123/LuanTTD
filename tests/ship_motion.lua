local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local Water=dofile(root.."ship_follow.lua")(T)
local Y=dofile(root.."ship_yapf.lua")(T,Water,dofile(root.."yapf_road_search.lua"))
local M=dofile(root.."ship_motion.lua")(T,Water)
local function id(x,z) if x>=0 and x<64 and z>=0 and z<64 then return z*64+x end end
local function xy(i) return i%64,math.floor(i/64) end
local units={[0]={-1,0},{0,1},{1,0},{0,-1}}
local records={}
local B={xy=xy,tile_at=id,tile=function(i) return records[i] end}
function B.adjacent(i,d)
  local x,z=xy(i);return id(x+units[d][1],z+units[d][2])
end
local function place(x,z,k,t)
  t=t or {};t.kind=k;records[id(x,z)]=t;return id(x,z)
end
local sw,ne=T.diagonal_trackdir(T.SW),T.diagonal_trackdir(T.NE)
local low=place(3,5,"sea",{docking=true})
place(3,4,"dock",{water_part=true,station=1})
place(4,5,"canal")
local lock=place(5,5,"lock",{dir=T.SW,part="middle",water_class="canal",slope=3,base=0,top=1})
place(6,5,"river",{base=1})
local high=place(7,5,"canal",{docking=true,base=1})
place(7,4,"dock",{water_part=true,station=2,base=1})
local sp=256 -- one axial pixel/tick at full speed
local v=assert(M.new(B,low,sw,{order={kind="station",id=2},acceleration=sp,max_speed=sp}))
local function assign(order_tile)
  local d=Y.destination(B,v,{kind="station",station=v.order.id,tile=order_tile})
  local ok,n=Y.find(B,v,v.tile,T.trackdirbit(M.trackdir(v)),d)
  assert(ok)
  assert(M.set_path(v,Y.trace(B,v,d,n)))
end
local changes={}
local hooks={water_changed=function(_,_,new,old) changes[#changes+1]=new.."/"..old end}
local function arrive(approaching_target,is_uphill)
  local levels,held,last={},0
  local events={}
  for _=1,500 do
    local oldz,oldx=v.z,v.x
    local event,n=M.tick(B,v,hooks)
    if v.z~=oldz then
      assert(v.z-oldz==(is_uphill and 1 or -1), "invalid lock increment")
      assert(v.tick%8==0 and v.tile==lock and v.x%16==8 and v.y%16==8)
      if last then assert(v.tick-last==8) end
      last=v.tick
      levels[#levels+1]=v.z
    end
    if event=="lock" then assert(oldx==v.x and n==0 and v.speed==0);held=held+1 end
    if event=="dock" then
      assert(v.loading and v.tile==approaching_target and #levels==8 and held>=57 and held<=64)
      assert(v.x%16==(is_uphill and 1 or 14), "dock must stop in first interior pixel, not tile center")
      return levels
    end
    events[#events+1]=event
  end
  error("no loading; final event "..tostring(events[#events]))
end
assign(id(7,4))
local levels=arrive(high,true)
assert(levels[1]==1 and levels[#levels]==8)
assert(v.last_station==2 and table.concat(changes,",")=="canal/sea,river/canal,canal/river")
local x=v.x
assert(M.tick(B,v)=="loading" and x==v.x)
-- The dock has no open water ahead, so leave first reverses at its current
-- position. Animation advances only 45 degrees per 8 ticks.
M.leave(v,{kind="station",id=1})
assert(M.tick(B,v)=="reverse" and v.direction==1 and v.rotation==5)
local nturn=0
while v.rotation~=v.direction do
  assert(M.tick(B,v)=="rotate" and v.x==x)
  nturn=nturn+1
end
assert(nturn>=25 and nturn<=32)
assign(id(3,4))
levels=arrive(low,false)
assert(levels[1]==7 and levels[#levels]==0 and v.last_station==1)

-- A true 90-degree track transition pauses presentation at the prior
-- pixel until visible heading finishes rotating. It is not a diagonal
-- shortcut through the opposite side of a two-corner water tile.
local corner=place(10,12,"coast",{slope=1})
local second=place(10,13,"coast",{slope=2})
v=assert(M.new(B,corner,5,{order={kind="tile",tile=second},acceleration=500,max_speed=500}))
assert(M.set_path(v,{{tile=corner,td=5},{tile=second,td=2}}))
for i=1,7 do assert(M.step(B,v)=="move") end
local ox,oy=v.x,v.y
assert(M.step(B,v)=="turn" and v.direction==2 and v.rotation==4 and v.speed==0)
local px,py,_,heading=M.visual(v)
assert(px==ox and py==oy and heading==4 and v.tile==second)
assert(v.x==ox and v.y==oy+1 and M.trackdir(v)==2)
for i=1,16 do assert(M.tick(B,v)=="rotate") end
assert(v.direction==v.rotation)
px,py=M.visual(v);assert(px==v.x and py==v.y)

-- Stock aqueduct state keeps the near logical tile but moves pixels across
-- an independent lower river. Far head is consumed from path at frame 0.
records={}
local west=place(16,9,"canal",{base=2})
local a=place(17,9,"aqueduct",{dir=T.SW,other=id(22,9),skip=4,deck=2})
local b=place(22,9,"aqueduct",{dir=T.NE,other=a,skip=4,deck=2})
local east=place(23,9,"canal",{base=2})
for j=18,21 do place(j,9,"river",{base=0}) end
local stop=place(24,9,"canal",{base=2,docking=true})
local dock=place(24,8,"dock",{station=3,water_part=true})
v=assert(M.new(B,west,sw,{order={kind="station",id=3},acceleration=1024,max_speed=1024}))
assign(dock)
local inside=0
local traversed={}
for _=1,160 do
  local old=v.x
  local event,n=M.tick(B,v)
  if event=="aqueduct" then
    assert(n>=1 and v.track==M.WORMHOLE and v.tile==a and v.z==16)
    local physical=xy(id(math.floor(v.x/16),math.floor(v.y/16)))
    if physical>=18 and physical<=21 then traversed[physical]=true end
    if old>=18*16 then assert(v.x==old+1, "wormhole tick must consume only its first movement") end
    inside=inside+1
  end
  if event=="dock" then break end
  assert(event~="reverse")
end
assert(inside>60 and traversed[18] and traversed[19] and traversed[20] and traversed[21])
assert(v.tile==stop and v.last_station==3 and v.loading and v.track==1 and v.z==16)
assert(v.path[v.path_index-1].tile==stop)

-- Depot trip requires center of correct saved north part and respects
-- busy exit; buoys are satisfied within three tiles, independent of dock.
records={}
local n=place(8,9,"ship_depot",{axis=0,depot=1,water_class="sea"})
place(9,9,"ship_depot",{axis=0,depot=1,water_class="sea"})
local apron=place(10,9,"sea")
local p=place(11,9,"buoy",{water_class="sea"})
v=assert(M.new(B,n,sw,{in_depot=true,order={kind="tile",tile=p},acceleration=256,max_speed=256}))
assert(M.tick(B,v,{depot_busy=function() return true end})=="depot_wait")
assert(v.hidden and v.track==M.DEPOT)
assert(M.depart_depot(B,v)=="depot_depart" and not v.hidden and v.track==1 and v.direction==5)
v=assert(M.new(B,apron,ne,{order={kind="depot",id=1,tile=n},acceleration=256,max_speed=256}))
assert(M.set_path(v,{{tile=apron,td=ne},{tile=id(9,9),td=ne},{tile=n,td=ne}}))
for _=1,50 do local e=M.tick(B,v);if e=="depot" then break end end
assert(v.tile==n and v.track==M.DEPOT and v.hidden and v.x%16==8 and v.y%16==8)
v=assert(M.new(B,apron,sw,{order={kind="waypoint",tile=p},acceleration=256,max_speed=256}))
assert(M.tick(B,v)=="waypoint" and v.order==nil)
-- Stock YAPF aims at the exact navigable buoy tile, but ShipController
-- advances OT_GOTO_WAYPOINT during ordinary movement within Manhattan 3.
-- Diagonal offsets distinguish that from Chebyshev and from tile arrival.
records={}
for xx=17,22 do for zz=17,22 do place(xx,zz,"canal") end end
local marker=place(18,18,"buoy",{water_class="canal"})
local four= id(20,20)
local three=id(20,19)
local order={kind="waypoint",tile=marker}
v=assert(M.new(B,four,sw,{order=order,acceleration=256,max_speed=256}))
local goal=assert(Y.destination(B,v,order))
assert(goal.tile==marker and Y.detect(B,goal,marker,sw))
assert(not Y.detect(B,goal,four,sw) and not Y.detect(B,goal,three,sw))
local passes=0
local next_order={kind="station",id=4}
local arrival_hooks={on_waypoint=function(_,ship,finished)
  assert(finished.tile==marker and not ship.loading and ship.last_station==nil)
  passes=passes+1
  ship.order=next_order
end}
assert(M.tick(B,v,arrival_hooks)=="move" and v.order==order and passes==0)
v=assert(M.new(B,three,sw,{order=order,acceleration=256,max_speed=256}))
assert(M.tick(B,v,arrival_hooks)=="waypoint" and v.tile==three and v.order==next_order and passes==1)
assert(not v.loading and v.last_station==nil and v.speed>0)
assert(M.tick(B,v,arrival_hooks)=="move" and v.order==next_order and passes==1)
print("PASS: stock ship motion, two-way lock and mooring; rotation seam, paired aqueduct, depot, buoy and waiting")
