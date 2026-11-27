local root="mods/luanttd_core/"
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
local binds,last_region=0
local function watched_regions(...)
  local r=Regions(...)
  last_region=r
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
local rocks=arg[1]=="rocks"
if rocks then
  for x=9,17 do s.tiles[id(x,12)].stock_water_rocks=true end
end

-- The fast case has no cached per-cell labels. The live board must
-- reject even one missing water track or non-flat corner in the square.
local plain=N.board(s)
local sea=id(31,28)
assert(not plain.is_docking(sea))
local native=plain.tile
plain.tile=function(at)
  if at==id(32,28) then return {kind="dock",water_part=true,station=99} end
  return native(at)
end
assert(plain.is_docking(sea),"A decorated board must still use the full live berth test")
plain.tile=native
assert(plain:solid_plain_sea(17,17,16) and not plain:solid_plain_sea(1,1,16))
local overlay=setmetatable({tile=function() return nil end},{__index=plain})
assert(not overlay:solid_plain_sea(17,17,16))
s.tiles[sea].stock_water_rocks=true
assert(not plain:solid_plain_sea(17,17,16))
s.tiles[sea].stock_water_rocks=nil
local corner=(28-1)*(S.W+1)+31
s.corner_grid.levels[corner]=1
assert(not plain:solid_plain_sea(17,17,16))
s.corner_grid.levels[corner]=0

-- A genuine shore edit on the first column of one 16×16 region
-- changes the edge read by the region on its other side as well.
local Flood=dofile(root.."water_flood_world.lua")(S,Terrain,dofile(src.."water_flood.lua"))
local function flood(z)
  local prev=s.topology
  local n,plain,first=Flood.visit(s,16,z)
  assert(n>0 and plain and s.tiles[id(17,z)].terrain=="water")
  R.after_plain_flood(s,prev,first)
end
s.tiles[id(17,22)].terrain="grass";s.topology=s.topology+1
assert(R.quote(s,"Alice",d.id,a.id,b.id,buoy and buoy.tile))
local historic=last_region
assert(not T.has(historic.info(0,1).edge[2],5))
flood(22)
assert(R.quote(s,"Alice",d.id,a.id,b.id,buoy and buoy.tile))
assert(last_region==historic and T.has(historic.info(0,1).edge[2],5),
  "Local tide must invalidate the reciprocal water edge")
-- A separate transaction went by without a plain tide notification.
-- The following known plain event must not conceal that earlier edit.
s.tiles[id(17,24)].terrain="grass";s.topology=s.topology+1
flood(24)
assert(R.quote(s,"Alice",d.id,a.id,b.id,buoy and buoy.tile))
assert(last_region~=historic,"An unknown revision requires the full rebuild")

local p,why=R.start(s,"Alice",d.id,a.id,b.id,buoy and buoy.tile)
assert(p,why)
assert(not R.pose(p))
local crossed,pending_hook=0
local unique_detour=0
local function wait(n)
  for _=1,2200 do
    R.tick(s,1)
    assert(p.phase~="blocked",p.failure)
    if rocks and p.vehicle and p.vehicle.tile then
      local x,z=S.xy(p.vehicle.tile)
      assert(not s.tiles[p.vehicle.tile].stock_water_rocks)
      if z==12 then
        assert(x>=18,"Ferry entered the rocky band")
        unique_detour=unique_detour+1
      end
    end
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
if rocks then assert(unique_detour>0,"Ferry never passed the outside edge of the rocky band") end
assert(not R.clear(s,"Foreign") and R.clear(s,"Alice"))
print("PASS: stock ferry depot departure, source ship navigation, adjacent berth stops and repeated service across reload")
