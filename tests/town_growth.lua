local p="mods/luanttd_core/openttd/"
local G=dofile(p.."town_growth.lua")
local Catalog=dofile(p.."town_growth_houses.lua")
local H=dofile(p.."town_passengers.lua")
local B=dofile(p.."town_growth_build.lua")(G,Catalog)
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function rng(seq)
  local i=0
  return function() i=i+1;return assert(seq[i],"Unexpected random draw #"..i) end
end
local t=G.new(7,12,12,{num_houses=49,population=312})
eq(t.grow_counter,7)
eq(t.radii[1],81)
eq(G.radii(91)[1],121);eq(G.radii(92)[1],125)
local a={x=21,z=12,time_since_load=20,time_since_unload=255}
local b={x=21,z=13,time_since_load=0,time_since_unload=0}
local c={x=12,z=12,time_since_load=255,time_since_unload=21}
local w={x=12,z=12,time_since_load=0,time_since_unload=0,waypoint=true}
eq(G.active_stations(t,{a,b,c,w}),1)
a.in_use=false
eq(G.active_stations(t,{a}),1) -- spatial index can retain an emptied station
a.in_use=true
G.station_tick(a,184);eq(a.time_since_load,20)
G.station_tick(a,1);eq(a.time_since_load,21)
G.station_move(c,0,0);eq(c.time_since_unload,21)
G.station_move(c,0,3);eq(c.time_since_unload,0)
eq(G.active_stations(t,{a,b,c,w}),1)
t.grow_counter=G.to_ticks(250)
local allowed,why=G.update(t,{a,b,c,w},2)
assert(allowed and why=="serviced" and t.growth_rate==14769)
eq(t.grow_counter,t.growth_rate)
c.time_since_unload=21
allowed,why=G.update(t,{a,b,c,w},2,rng({65535}))
assert(not allowed and why=="no-service" and t.growth_rate==11269)
allowed,why=G.update(t,{a,b,c,w},2,rng({0}))
assert(allowed and why=="unserviced-chance")
t.goal.goods=5
t.received.goods={old_act=99,new_act=4}
local call=0
allowed,why=G.month(t,{c},2,function() call=call+1;return 0 end)
assert(not allowed and why=="unmet-cargo-goal" and call==0)
t.received.goods.new_act=5;c.time_since_load=0
assert(G.month(t,{c},2) and t.received.goods.old_act==5)
assert(G.fund(t,{c},0) and t.fund_buildings_months==3 and t.grow_counter==141)
assert(G.month(t,{c},0) and t.fund_buildings_months==2)
assert(G.month(t,{c},0) and t.fund_buildings_months==1)
assert(not G.month(t,{c},0) and t.fund_buildings_months==0)

t.growing=true;t.grow_counter=1;t.growth_rate=100
assert(not G.tick(t,function() error("Build on wrong tick") end) and t.grow_counter==0)
local tried,built=G.tick(t,function() return false end)
assert(tried and not built and t.grow_counter==69)
local n=0
for i=1,70 do G.tick(t,function(s) n=n+1;s.growth_rate=88;return true end) end
assert(n==1 and t.grow_counter==88)

local ordinary={kind="clear",slope=0,max_z=0}
local coast={kind="water",slope=0,max_z=0}
local home={kind="house",slope=0,max_z=0}
local map={}
local function key(x,z) return x..":"..z end
local function put(x,z,q) map[key(x,z)]=q end
local function get(x,z)
  if x<0 or x>=64 or z<0 or z>=64 then return end
  return map[key(x,z)] or ordinary
end
local board={tile=get,road_quote=function(t,x,z,bits)
  assert(get(x,z).kind=="clear")
  return {unchanged=true,bits=bits}
end,clear_quote=function(x,z) return get(x,z)==ordinary end}
t=G.new(2,12,12,{num_houses=25})
local stub=B.grow(t,board,{year=1950,allow_roads=true},rng({0}))
assert(stub.kind=="road" and stub.x==12 and stub.z==12 and stub.bits==5 and get(12,12)==ordinary)
put(12,12,{kind="road",road_town=2,road_bits=10,slope=0,max_z=0})
put(13,12,{kind="road",road_town=2,road_bits=10,slope=0,max_z=0})
-- Direction 1 = SE (+Z) is a side parcel, and building never writes
-- the raw board. Selection comes from actual ordered HouseID/Zones data.
local hi=1073741824
local plan=B.grow(t,board,{year=1950},rng({hi,0,300000000,41}))
assert(plan.kind=="house" and plan.id==3 and plan.x==12 and plan.z==13 and not plan.parts[1].completed)
assert(get(12,13)==ordinary and plan.parts[1].counter==0 and plan.parts[1].stage==0)
B.house_committed(t,plan,{c},2)
assert(t.num_houses==26 and t.unique.church and t.house_counts[3]==1)
put(12,13,{kind="clear",owner="player",slope=0,max_z=0})
assert(not B.house(t,board,12,13,{year=1950},rng({})))
put(12,13,{kind="clear",bridge_above=true,slope=0,max_z=0})
assert(not B.house(t,board,12,13,{year=1950},rng({})))
put(12,13,coast)
assert(not B.house(t,board,12,13,{year=1950},rng({})))
put(12,13,home)
assert(not B.house(t,board,12,13,{year=1950},rng({})))

local stages={}
local h=plan.parts[1]
for i=1,23 do
  assert(B.advance_house(h,plan.parts,H.specs,function() error("Matured before 24 physical visits") end))
  assert(not h.completed)
end
assert(B.advance_house(h,plan.parts,H.specs,function(p,pop) stages[#stages+1]={p.id,pop} end))
assert(h.completed and h.age==0 and h.stage==3 and #stages==1 and stages[1][2]==5)
assert(not B.advance_house(h,plan.parts,H.specs))
local emissions=0
H.produce_tile(12+13*64,89,h,{},function() return 1 end,function(_,n) emissions=emissions+n end)
assert(emissions>0)

-- The four physical tiles of a stock stadium count as one house.
t.layout="original"
board.house_supported=function(id) return id==0x14 end
local stadium=assert(B.house(t,board,24,24,{year=1950},function() return 0 end))
assert(stadium.x==24 and stadium.z==24 and #stadium.parts==4)
for i,xy in ipairs{{24,24},{24,25},{25,24},{25,25}} do
  local part=stadium.parts[i]
  assert(part.id==0x13+i and part.x==xy[1] and part.z==xy[2] and part.root_x==24 and part.root_z==24)
end
B.house_committed(t,stadium,{c},2)
assert(t.num_houses==27 and t.unique.stadium and t.house_counts[0x17]==1)
local population=0
for i=1,24 do
  assert(B.advance_house(stadium.parts[2],stadium.parts,H.specs))
  assert(stadium.parts[2].counter==(i-1)%8)
  assert(B.advance_house(stadium.parts[1],stadium.parts,H.specs,function(_,n) population=population+n end))
end
assert(population==65)
for _,part in ipairs(stadium.parts) do assert(part.completed and part.age==0) end
assert(not B.house(t,board,30,30,{year=1950},function() return 0 end))
board.house_supported=nil

-- The ordinary 2x2 grid houses occupy the two blocks between streets.
t.layout="grid2"
assert(B.house_on_layout(t,13,13,true,true))
assert(not B.house_on_layout(t,14,14,true,true))
eq(B.grid_bits(t,12,12,2,0),15)
eq(B.grid_bits(t,12,13,1,0),5)
eq(B.grid_bits(t,13,12,2,0),10)
print("PASS exact town service gate, month/fund/tick, nondestructive house selection, and physical construction to cargo")

-- A town whose last street was demolished must ignore a slope that
-- normally supports a road foundation, and can seed on flat trees.
do
  local t=G.new(1,12,12)
  local tiles={}
  tiles["12:12"]={kind="clear",slope=3}
  tiles["11:12"]={kind="trees",slope=0}
  local cleared={}
  local board={tile=function(x,z) return tiles[x..":"..z] end,
    seed_road_clear_quote=function(x,z) cleared[#cleared+1]={x,z}; return true end,
    road_quote=function(_,x,z,bits)
      assert(x==11 and z==12 and bits==10)
      return {bits=bits}
    end}
  local road=assert(B.grow(t,board,{year=1950,allow_roads=true},rng({257})))
  assert(road.x==11 and road.z==12 and road.bits==10)
  assert(#cleared==1 and cleared[1][1]==11 and cleared[1][2]==12)
end
