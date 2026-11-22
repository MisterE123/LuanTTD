local p="mods/luanttd_core/"
local Sim=dofile(p.."sim.lua")
local T=dofile(p.."openttd/terrain.lua")
local C=dofile(p.."openttd/clear_area.lua")
local s=Sim.new(1751)
for i in ipairs(s.tiles) do s.tiles[i]={terrain="grass",h=0,variant=0} end
s.sites,s.fleet,s.stations={},{},{}
s.corner_grid=T.new(Sim.W,Sim.H,function()return 0 end,{freeform_edges=true})
local company=Sim.company(s,"A")
company.cash=10099
company.clear_limit=C.UNIT*10+432
local function tile(x,z,record)
  local id=Sim.id(x,z);s.tiles[id]=record;record.h=0
  return id,record
end
local a=tile(4,4,{terrain="water",water_class="sea"})
local blocked=tile(5,4,{terrain="grass",build="road",road_bits=10,owner="B"})
local b=tile(6,4,{terrain="grass",build="road",road_bits=10,owner="A"})
local c=tile(7,4,{terrain="water",water_class="river"})
local cash,topo=company.cash,s.topology
local test=assert(Sim.clear_area(s,"A",c,a,false))
assert(test.cost==10080 and test.extra==10000 and test.skipped==1 and test.next_tile==c)
assert(test.ids[1]==a and test.ids[2]==b and s.topology==topo and company.cash==cash)
assert(s.tiles[a].terrain=="water" and s.tiles[b].build=="road")
local built=assert(Sim.clear_area(s,"A",c,a,false,true))
assert(built.cost==10080 and company.cash==19 and built.passed==2 and #built.dirty==2)
assert(s.tiles[a].terrain=="grass" and not s.tiles[b].build)
assert(s.tiles[c].terrain=="water" and s.tiles[blocked].owner=="B")
assert(company.clear_limit==C.UNIT*8+432)

local low=tile(4,5,{terrain="grass",build="road",road_bits=10,owner="A"})
local high=tile(5,6,{terrain="grass",build="road",road_bits=10,owner="A"})
company.cash=10000
company.clear_limit=C.UNIT+1
local di=assert(Sim.clear_area(s,"A",low,high,true,true))
assert(di.passed==1 and di.ids[1]==high and di.limit_reached and company.clear_limit==1)
assert(s.tiles[low].build=="road" and not s.tiles[high].build)
local q,why=Sim.clear_area(s,"A",low,high,false)
assert(not q and why=="CLEARING_LIMIT_REACHED")
Sim.daily(s)
assert(company.clear_limit==C.BURST*C.UNIT)
local layered=tile(4,7,{terrain="grass",build="road",road_bits=10,owner="A"})
s.bridge_above={[layered]=1}
assert(not Sim.clear_area(s,"A",layered,layered,false,true) and s.tiles[layered].build=="road")
print("PASS live clear area: preview read only, skip ownership, preserve transport over layers, exact cost/partial/quota/diagonal order")
