local root="mods/bayline/"
local src=root.."openttd/"
local S=dofile(root.."sim.lua")
local T=dofile(src.."rail_track.lua")
local Terrain=dofile(src.."terrain.lua")
local W=dofile(src.."ship_follow.lua")(T)
local D=dofile(src.."ship_facilities.lua")(T,W)
local N=dofile(root.."ship_network.lua")(S,Terrain,W,D)
local Y=dofile(src.."ship_yapf.lua")(T,W,dofile(src.."yapf_road_search.lua"))
local Move=dofile(src.."ship_motion.lua")(T,W)
local Regions=dofile(src.."ship_regions.lua")
local binds=0
local function watched_regions(...)
  local r=Regions(...)
  local find=r.find_route
  function r.find_route(...)
    binds=binds+1
    return find(...)
  end
  return r
end
local R=dofile(root.."ship_preview_run.lua")(N,T,W,Y,Move,watched_regions,{width=S.W,height=S.H,x0=1,z0=1})
local s=S.new(1751)
s.corner_grid=Terrain.new(S.W,S.H,function(x) return x<9 and 1 or 0 end)
local function id(x,z) return S.id(x,z) end
for i,t in ipairs(s.tiles) do
  local x,z=S.xy(i)
  t.site=nil;t.owner=nil;t.wood=nil;t.house=nil;t.build=nil
  t.terrain=x>=9 and "water" or "grass"
end
local a=assert(N.build(s,"Alice","dock",id(8,9)))
local b=assert(N.build(s,"Alice","dock",id(8,16)))
local d=assert(N.build(s,"Alice","depot",id(12,10),0))
local buoy=arg[1]=="buoy" and assert(N.build(s,"Alice","buoy",id(19,12))) or nil
local p,why=R.start(s,"Alice",d.id,a.id,b.id,buoy and buoy.tile)
assert(p,why)
assert(not R.pose(p))
local crossed,pending_hook=0
local function wait(n)
  for _=1,2200 do
    R.tick(s,1)
    assert(p.phase~="blocked",p.failure)
    if pending_hook then pending_hook() end
    if p.arrivals==n then break end
  end
  assert(p.phase=="moored" and p.arrivals==n,("arrivals %d requested %d"):format(p.arrivals,n))
  assert(p.last_dock==(n%2==1 and a.id or b.id))
  local pos=R.pose(p)
  assert(pos and pos.y==.5 and p.last_berth~=a.water and p.last_berth~=b.water)
end
wait(1)
local function persist(t)
  if type(t)~="table" then assert(type(t)=="number" or type(t)=="string" or type(t)=="boolean");return t end
  assert(not getmetatable(t))
  local u={}
  for k,v in pairs(t) do u[k]=persist(v) end
  return u
end
s=persist(s);p=R.current(s)
if buoy then
  pending_hook=function()
    if not p.pending_buoy_dock then return end
    local destination=p.pending_buoy_dock
    assert(not p.vehicle.order and p.via.passes==crossed+1 and p.last_buoy_pass.distance==3
      and p.last_buoy_pass.speed==p.vehicle.speed and p.vehicle.speed>0)
    assert(p.last_dock~=destination and p.last_buoy_pass.next_dock==destination)
    crossed=crossed+1
    if crossed==1 then
      s=persist(s);p=R.current(s)
      assert(p.pending_buoy_dock==destination and p.via.passes==crossed)
      R.tick(s,1)
      assert(not p.pending_buoy_dock and p.vehicle.order.kind=="station" and p.vehicle.order.id==destination
        and p.via.passes==crossed and not p.vehicle.loading)
    end
  end
end
wait(2)
wait(3)
wait(4)
assert(p.steps>180 and binds>4)
if buoy then assert(crossed==3 and p.via.passes==3) end
assert(not R.clear(s,"Foreign") and R.clear(s,"Alice"))
print("PASS: stock ferry depot departure, source ship navigation, adjacent berth stops and repeated service across reload")
