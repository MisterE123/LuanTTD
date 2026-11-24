local R=dofile("mods/luanttd_core/openttd/road_town_permission.lua")
local cross={4,8,1,2}
for t,min in pairs({[0]=16,64,112,-1000}) do
  assert(select(2,R.check(min-1,t,true,15,10,cross))=="TOWN_REFUSES")
  assert(R.check(min,t,true,15,10,cross)==math.max(min-50,math.min(min,-100)))
  assert(select(2,R.check(min,t,false,15,10,cross))=="TOWN_REFUSES")
end
assert(R.check(500,0,false,15,8,{4,8,1,0})==482,"unconnected half is not an inner street")
assert(R.check(500,0,false,15,4,{0,0,1,0})==482,"only one connecting neighbor is an edge")
assert(R.check(500,0,false,15,1,{1,2,4,8})==482,"nonreciprocal pavement doesn't form a neighbor")
assert(R.check(-180,3,true,15,10,cross)==-180,"do not raise a rating already below the penalty floor")
assert(R.check(-72,3,true,15,10,cross)==-100)
local town={x=0,z=0}
assert(R.in_radius(town,{x=2,z=0},4) and not R.in_radius(town,{x=2,z=1},4))
assert(not R.in_radius(town,{x=1,z=0},1))
assert(R.month(197,{{time_since_load=20},{time_since_load=21,time_since_unload=21},{time_since_unload=0}})==209)
assert(R.month(1000,{{time_since_load=20},{time_since_load=21}})==997)
assert(R.month(-1000,{{time_since_load=21}})==-1000)
local Sim=dofile("mods/luanttd_core/sim.lua")
local A=dofile("mods/luanttd_core/town_road_authority.lua")(Sim,R)
local state=Sim.new(1751)
local c=Sim.company(state,"a");local d=Sim.company(state,"b")
c.stock_town_authority_ratings={[1]=100}
local rail,road=Sim.id(11,10),Sim.id(10,10)
state.stations[1]={id=1,tile=road,mode="road",owner="a",time_since_load=20,town_growth_service_clock=true}
state.stations[2]={id=2,tile=road,mode="road",owner="b",time_since_load=21,town_growth_service_clock=true}
state.stock_rail_stations={[7]={id=7,tile=rail,owner="a"}}
state.stock_ship_commercial={service={stations={[24]={sign={x=11,y=10},host_mode="rail",host_id=7,owner="a",time_since_unload=8},
  [25]={sign={x=11,y=10},host_mode="rail",host_id=8,owner="b",time_since_unload=8}}}}
A.month(state,{id=1,x=10,z=10,radii={4}},A.station_view(state))
assert(c.stock_town_authority_ratings[1]==129 and d.stock_town_authority_ratings[1]==485)
local copy=dofile("mods/luanttd_core/packed_campaign.lua")
local restored=assert(copy.decode(copy.encode(state)))
assert(restored.companies.a.stock_town_authority_ratings[1]==129)

print("PASS RC1 town road authority thresholds, reciprocity, outer and inner deductions, rating floor and monthly station age")

do
  -- Mixed roadpieces on a 96-tile municipal row with 4,000 unrelated
  -- vehicle positions. Count actual position callbacks rather than
  -- relying on variable timing in CI.
  local Sim=dofile("mods/luanttd_core/sim.lua")
  local Terrain=dofile("mods/luanttd_core/openttd/terrain.lua")
  local s=Sim.new(1751)
  Sim.W,Sim.H=128,64
  s.corner_grid=Terrain.new(Sim.W,Sim.H)
  s.tiles,s.fleet={},{}
  for i=1,Sim.W*Sim.H do s.tiles[i]={h=0,terrain="grass",variant=1} end
  local name="Road Gesture"
  local company=Sim.company(s,name)
  company.cash=100000
  local function at(x,z) return assert(Sim.id(x,z)) end
  for x=10,105 do
    local t=s.tiles[at(x,20)]
    t.build,t.road_town,t.road_bits="road",1,1
  end
  for i=1,4000 do s.fleet[i]={at=at(33,38)} end
  local count=0
  Sim.position=function(_,v) count=count+1;return v.at end
  local function quote(z)
    return assert(Sim.autoroad_plan(s,name,at(10,z),at(105,z),0,false,true))
  end
  assert(#quote(21).changes==96 and count==0,"no fleet inspection on a fresh, empty roadbed")
  local q=quote(20)
  assert(#q.changes==96 and q.cost==18050 and count==4000)
  count=0
  s.fleet[4000].at=at(83,20)
  local blocked=quote(20)
  assert(blocked.stopped_at==at(83,20) and #blocked.changes==73 and count==4000)
  assert(company.cash==100000 and s.tiles[at(83,20)].road_bits==1,"read-only quote")
  s.fleet[4000].at=at(36,38)
  count=0
  local again=quote(20)
  assert(count==4000 and again.cost==q.cost and #again.changes==96,"next gesture checks new positions")
  print("PASS 96-tile municipal AutoRoad does 4,000 fleet probes instead of 384,000; no probes on clear ground and moving obstruction still limits the drag")
end

do
  local Sim=dofile("mods/luanttd_core/sim.lua")
  local T=dofile("mods/luanttd_core/openttd/terrain.lua")
  local s=Sim.new(1751)
  local function at(x,z) return assert(Sim.id(x,z)) end
  s.sites={{id=1,kind="town",tile=at(3,12),name="Forest City"},
    {id=2,kind="town",tile=at(3,20),name="Farmland"}}
  s.corner_grid=T.new(Sim.W,Sim.H)
  s.tiles,s.fleet={},{}
  for i=1,Sim.W*Sim.H do s.tiles[i]={h=0,terrain="grass",variant=1} end
  local name="Named forester"
  local c=Sim.company(s,name)
  local ranger=Sim.company(s,"Other company")
  local authority=Sim.road_tree_authority()
  assert(R.clear_trees(500)==465 and R.clear_trees(-980)==-1000 and R.clear_trees(-1015)==-1015)
  assert(authority.tree_town(s,at(22,12))==1 and not authority.tree_town(s,at(23,12)))
  assert(authority.tree_town(s,at(9,16))==1, "nearest equal distance chooses lowest town ID")

  local trees=at(22,12)
  s.tiles[trees].wood={count=4}
  local q=assert(Sim.autoroad_plan(s,name,trees,trees,0,true,true))
  assert(q.cost==175 and q.changes[1].road_tree_town==1 and not c.stock_town_authority_ratings)
  local ok,note=Sim.apply_road_construction(s,name,q)
  assert(ok and note:find("local authority rating",1,true))
  assert(c.stock_town_authority_ratings[1]==465 and not ranger.stock_town_authority_ratings)
  assert(Sim.autoroad_build(s,name,trees,trees,0,false,true) and c.stock_town_authority_ratings[1]==465)
  local unaff=at(21,12)
  s.tiles[unaff].wood={count=3}
  c.cash=50
  assert(not Sim.autoroad_build(s,name,unaff,unaff,0,true,true))
  assert(c.stock_town_authority_ratings[1]==465 and s.tiles[unaff].wood.count==3)
  c.cash=100000
  local distant=at(23,12)
  s.tiles[distant].wood={count=3}
  assert(Sim.autoroad_build(s,name,distant,distant,0,true,true))
  assert(c.stock_town_authority_ratings[1]==465)
  local depot=at(10,12)
  s.tiles[depot].wood={count=2}
  local build=assert(Sim.stock_road_terminal_plan(s,name,depot,{kind="depot",dir=2}))
  assert(build.cost==540 and build.changes[1].road_tree_town==1)
  assert(Sim.apply_road_construction(s,name,build))
  assert(c.stock_town_authority_ratings[1]==430)
  print("PASS source road clearance applies one local authority penalty per wooded tile, only on paid commits, within the strict radius")
end
dofile("tests/road_reconstruction.lua")
