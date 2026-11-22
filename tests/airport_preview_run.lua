local root="mods/luanttd_core/"
local src=root.."openttd/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(src.."terrain.lua")
local Slope=dofile(src.."slope.lua")
local Small=dofile(src.."airport_small.lua")
local Motion=dofile(src.."airport_motion.lua")(Small)
local N=dofile(root.."airport_network.lua")(Sim,Terrain,Small)
local R=dofile(root.."airport_preview_run.lua")(Sim,N,Small,Motion,Terrain,Slope)
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z)return x>21 and 1 or 0 end)
for _,t in ipairs(s.tiles) do
  t.terrain="grass";t.wood=nil;t.house=nil;t.site=nil;t.build=nil;t.owner=nil
end
local function at(x,z) return Sim.id(x,z) end
local quote=assert(N.quote(s,"A",at(6,6)))
assert(quote.price==7200 and #quote.tiles==12 and not s.tiles[at(6,6)].airfield and not s.companies.A)
assert(not N.quote(s,"A",at(20,6)))
assert(not N.quote(s,"A",at(47,6)))
local a=assert(N.build(s,"A",at(6,6)))
local b=assert(N.build(s,"A",at(31,20)))
assert(a.ground==0 and b.ground==8 and #a.tiles==12 and #b.tiles==12)
assert(N.airport_for(s,at(9,8))==a and not N.quote(s,"A",at(8,6)))
assert(Sim.company(s,"A").expense==14400)
local p=assert(R.start(s,"A",a.id,b.id))
assert(p.phase=="hangar" and not R.pose(p))
local function save(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local copy={}
  for k,v in pairs(t) do copy[k]=save(v) end
  return copy
end
local high,events=0,{}
local function wait(n)
  for _=1,12000 do
    R.tick(s,1,function(ev)
      events[ev]=(events[ev] or 0)+1
    end)
    assert(p.phase~="blocked",p.failure)
    local pos=R.pose(p)
    if pos then high=math.max(high,pos.y) end
    if p.arrivals==n then return end
  end
  error("Pilot did not reach target")
end
wait(1)
assert(p.last_airfield==b.id and b.flags==Small.block.TERM1 and R.pose(p).y==1.5 and high>5)
s=save(s);p=R.current(s)
wait(2)
assert(p.last_airfield==a.id and R.pose(p).y==.5 and p.departures==2)
wait(3)
assert(p.last_airfield==b.id and R.pose(p).y==1.5 and events.takeoff==3 and events.touchdown==3)
assert(not N.remove(s,"A",at(31,20)))
assert(R.clear(s,"A"))
local dirty,cost=N.remove(s,"A",at(32,20))
assert(#dirty==12 and cost==360 and not N.airport_for(s,at(31,20)))
print("PASS: paid 4x3 airfield construction, stock aircraft from hangar, climb, runway claims, three real terminals across reload")
