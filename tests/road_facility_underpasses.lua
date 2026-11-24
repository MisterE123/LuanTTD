local root="mods/luanttd_core/"
local src=root.."openttd/"
local function load(n)return dofile(src..n..".lua") end
local S=dofile(root.."sim.lua")
local Terrain,Track,Slope=load("terrain"),load("rail_track"),load("slope")
local RBridge=load("road_bridge")(Slope)
local Signal=load("rail_signals")(Track)
local H=load("rail_height")(Track,Slope)
local Q=load("rail_construction")(Track,Signal,H)
local Site=load("rail_span_site")
local Bridge=load("rail_bridge")(RBridge,Q,Site)
local Tunnel=load("rail_tunnel")(load("road_tunnel"),Q,Site,Track)
local Rail=dofile(root.."rail_span_world.lua")(S,Terrain,H,Bridge,Tunnel,Track)
local Aqua=dofile(root.."ship_aqueduct_world.lua")(S,Terrain,load("aqueduct")(RBridge))
local s=S.new(1751)
local function id(x,z)return assert(S.id(x,z))end
s.sites,s.tiles={},{}
s.corner_grid=Terrain.new(S.W,S.H,function(x,z)
  local tier=math.min(3,math.max(1,24-z))
  return math.min(tier,math.max(0,tier-math.min(x-5,14-x)))
end)
for i=1,S.W*S.H do
  local x,z=S.xy(i)
  local _,base=Terrain.tile(s.corner_grid,x,z)
  s.tiles[i]={h=base,terrain="grass",variant=1}
end
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
s.rail_span_enabled=true
local owner="Overpass operator"
S.company(s,owner).cash=2000000
local C=dofile(root.."campaign_road_construction.lua")(S,s)
assert(S.build(s,owner,"road",S.line(id(8,9),id(8,19))))
assert(S.build(s,owner,"road",S.line(id(10,9),id(10,19))))
assert(S.road_bridge(s,owner,id(4,12),id(14,12),0))
local rail=assert(Rail.quote_bridge(s,owner,id(4,16),id(14,16)))
assert(Rail.commit(s,owner,rail))
local a,b=id(8,16),id(10,16)
assert(S.road_overhead_deck(s,a)==4)
local stop={tool="stock_terminal_auto",first=a,kind="bus"}
local wp={tool="road_waypoint",first=b}
assert(C.commit(owner,stop,nil,true))
assert(C.commit(owner,wp,nil,true))
assert(s.tiles[a].stop_axis==5 and s.tiles[b].road_waypoint_id)
assert(Rail.by_bridge_middle(s,b).deck==4)
local original_span=Rail.by_bridge_middle(s,a)
assert(C.commit(owner,{tool="stock_stop_remove",first=a},nil,true))
assert(s.tiles[a].build=="road" and s.tiles[a].road_bits==5 and not s.tiles[a].station)
assert(Rail.by_bridge_middle(s,a)==original_span)

local depot={tool="stock_terminal",first=id(9,12),kind="depot",direction=2}
assert(C.commit(owner,depot,nil,true))
assert(S.road_overhead_deck(s,depot.first)==4 and s.tiles[depot.first].build=="road_depot")
assert(not C.quote(owner,{tool="stock_terminal_auto",first=rail.start,kind="truck"}))

-- Real aqueduct rises only one level above flat lower ground, too low
-- for either an ordinary shelter or a waypoint, despite valid pavement.
local w,e=id(5,24),id(13,24)
s.tiles[id(4,24)].build="canal";s.tiles[id(14,24)].build="canal"
assert(S.build(s,owner,"road",S.line(id(8,22),id(8,26))))
assert(Aqua.build(s,owner,w,e))
local under=id(8,24)
assert(S.road_overhead_deck(s,under)==1)
local _,why=C.quote(owner,{tool="stock_terminal_auto",first=under,kind="truck"})
assert(why=="The road stop needs two levels below the elevated deck.",why)
_,why=C.quote(owner,{tool="road_waypoint",first=under})
assert(why=="The waypoint needs two levels below the elevated deck.",why)
assert(not s.tiles[under].station and s.tiles[under].build=="road")
local upper=id(8,20)
s.tiles[id(4,20)].build="canal";s.tiles[id(14,20)].build="canal"
assert(S.build(s,owner,"road",S.line(id(8,19),id(8,21))))
assert(Aqua.build(s,owner,id(5,20),id(13,20)))
assert(S.road_overhead_deck(s,upper)==3)
assert(C.commit(owner,{tool="stock_terminal_auto",first=upper,kind="truck"},nil,true))
assert(s.tiles[upper].road_stop_type=="truck" and s.tiles[upper].stop_axis==5)
s.aqueduct_above[a]=s.aqueduct_above[under]
assert(S.road_overhead_deck(s,a)==1,"lowest overhead deck governs a shared ground tile")
s.aqueduct_above[a]=999
local missing,has_bridge=S.road_overhead_deck(s,a)
assert(missing==nil and has_bridge)
print("PASS railway and aqueduct clearances for ordinary road facilities, including preserved raised decks and pavement")
