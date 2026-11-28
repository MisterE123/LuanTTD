local m="mods/luanttd_core/"
local function D(name) return dofile(m..name..".lua") end
local S,T,G=D("sim"),D("openttd/terrain"),D("openttd/town_growth")
local H=D("openttd/town_passengers")
local B=D("openttd/town_growth_build")(G,D("openttd/town_growth_houses"))
local W=D("town_growth_runtime")(S,T,G,B,H)
local function fixture()
  local s=S.new(1751)
  s.corner_grid=T.new(S.W,S.H,function() return 1 end)
  s.stock_generated_profile={width=S.W,depth=S.H,map_height_limit=32}
  s.stock_town_growth={version=1,order={1},towns={}}
  s.sites={{id=1,kind="town",name="Grid Town",tile=S.id(11,12),population=0}}
  local town=G.new(1,11,12,{layout="grid2",grow_counter=0})
  town.growing=true
  s.stock_town_growth.towns[1]=town
  for i in ipairs(s.tiles) do s.tiles[i]={h=1,terrain="grass",variant=1} end
  local id=S.id(11,12)
  assert(S.town_road_piece(s,1,id,10,true))
  return s,town,id
end
local s,town,center=fixture()
local function draw() return 1073741824 end
W.tick(s,1,draw)
assert(s.tiles[center].road_bits==15 and s.changed[1]==center,"town must add the perpendicular street");
town.grow_counter=0
W.tick(s,2,draw)
local extension=S.id(11,13)
assert(s.tiles[extension].build=="road" and s.tiles[extension].road_town==1 and s.tiles[extension].road_bits==5,
 "town must extend onto a fresh road tile")
assert(s.changed[2]==extension and not next(s.companies))
local saved=D("packed_campaign").decode(D("packed_campaign").encode(s))
local next_board=W.road_board(saved)
assert(next_board.tile(11,13).road_town==1 and next_board.tile(11,13).road_bits==5)
print("PASS source grid growth writes adjoining municipal streets, marks them dirty and persists both")
local guarded,gt,gcenter=fixture()
guarded.tiles[S.id(11,13)].stock_industry={id=77}
local old=guarded.tiles[S.id(11,13)]
W.tick(guarded,1,draw)
assert(old.stock_industry.id==77 and not old.build)
local opts=W.road_board(guarded)
assert(not opts.road_quote(gt,11,13,5))
print("PASS live roads cannot clear an active industry")

local dry,dt=fixture()
dry.stock_road_town_policy={allow_town_roads=false}
W.tick(dry,1,draw)
assert(dry.tiles[S.id(11,12)].road_bits==10 and not dry.tiles[S.id(11,13)].build)
print("PASS stock town road restriction still applies")

local function slope_fixture()
  local world,city=fixture()
  local x,z=15,12
  local stride=S.W+1
  world.corner_grid.levels[(z-1)*stride+x]=2 -- one raised N corner
  assert(T.tile(world.corner_grid,x,z)==8)
  return world,city,x,z
end
local world,city,x,z=slope_fixture()
local calls=0
assert(W.road_board(world).road_allowed(city,x,z,0,function()
  calls=calls+1
  -- Decisions at 1-3, four row-major validation draws at 4-7,
  -- four clear flags at 8-11. Only draws 8 and 11 leave rock.
  return (calls<=3 or calls==8 or calls==11) and 0 or 4294967295
end)==false)
assert(calls==11 and T.tile(world.corner_grid,x,z)==0 and world.corner_grid.revision==1)
local marked={}
for _,id in ipairs(world.changed) do marked[id]=true end
assert(marked[S.id(x,z)] and marked[S.id(x-1,z-1)])
for _,d in ipairs({{-1,-1,true},{0,-1,false},{-1,0,false},{0,0,true}}) do
  local t=world.tiles[S.id(x+d[1],z+d[2])]
  assert(t.stock_clear_ground==(d[3] and 2 or nil) and t.stock_clear_density==(not d[3] and 0 or nil))
end
world,city,x,z=slope_fixture()
local private=S.id(x-1,z-1)
world.tiles[private].owner="RoadCo"
world.tiles[private].stock_object={kind="owned_land"}
calls=0
W.road_board(world).road_allowed(city,x,z,0,function() calls=calls+1;return 0 end)
assert(calls==4 and T.tile(world.corner_grid,x,z)==8 and world.corner_grid.revision==0)
assert(world.tiles[private].owner=="RoadCo" and not world.changed)
print("PASS source downhill sample changes real shared corners and marks every tile, but not paid land")

local function stock_span(world,city,x,z)
  -- Pin the municipal approach and repeatable shared RNG, but run the
  -- entire source street walk to select and commit the obstacle span.
  city.x,city.z,city.growth_rate=x-1,z,0
  world.sites[city.id].tile=S.id(city.x,city.z)
  local state=2
  local function random()
    state=state*16807%2147483647
    return 3*state%4294967296
  end
  W.tick(world,1,random)
  W.tick(world,2,random)
end
local bridgeworld,bridgecity=fixture()
local bx,bz=14,17
assert(S.town_road_piece(bridgeworld,1,S.id(bx-1,bz),10,true))
for u=bx+1,bx+2 do
  local tile=bridgeworld.tiles[S.id(u,bz)]
  tile.terrain,tile.water_class="water","river"
end
stock_span(bridgeworld,bridgecity,bx,bz)
local _,bridge=next(bridgeworld.stock_road_bridges or {})
assert(bridge and bridge.town==1 and bridge.start==S.id(bx,bz) and bridge["end"]==S.id(bx+3,bz))
for _,id in ipairs(bridge.middle) do
  assert(bridgeworld.bridge_above[id] and bridgeworld.tiles[id].water_class=="river")
end

local tunnelworld,tunnelcity=fixture()
local tx,tz=14,17
local stride=S.W+1
for v=tz,tz+1 do for u=tx+1,tx+3 do tunnelworld.corner_grid.levels[(v-1)*stride+u]=2 end end
assert(T.tile(tunnelworld.corner_grid,tx,tz)==3 and T.tile(tunnelworld.corner_grid,tx+3,tz)==12)
assert(S.town_road_piece(tunnelworld,1,S.id(tx-1,tz),10,true))
local under=S.id(tx+1,tz)
assert(S.town_road_piece(tunnelworld,1,under,5,true))
stock_span(tunnelworld,tunnelcity,tx,tz)
local _,tunnel=next(tunnelworld.stock_road_tunnels or {})
assert(tunnel and tunnel.town==1 and tunnel.start==S.id(tx,tz) and tunnel["end"]==S.id(tx+3,tz))
assert(tunnelworld.tunnel_below[under] and tunnelworld.tiles[under].build=="road")
local Follow=D("openttd/yapf_road_follow")
local Read=D("road_yapf_board")
local SFile=D("packed_campaign")
for _,r in ipairs({{bridgeworld,bridge,"bridge"},{tunnelworld,tunnel,"tunnel"}}) do
  local restored=SFile.decode(SFile.encode(r[1]))
  local board=Read(S,restored,Follow)
  for _,id in ipairs({r[2].start,r[2]["end"]}) do
    local head=board.tile(id)
    local visit=Follow.follow(board,{owner="Carrier"},id,Follow.direction_trackdir(head.dir))
    assert(visit.ok and visit[r[3]] and visit.tile==head.other and visit.skip==#r[2].middle)
  end
  assert(not next(restored.companies))
end
print("PASS live stock scouts built a routed public river bridge and a tunnel below an intact street")

-- A local municipal write retests only nearby quiet-sea words.
local waterworld={tiles={}}
for id=1,S.W*S.H do waterworld.tiles[id]={terrain="water",water_class="sea"} end
local cache=D("stock_open_sea_cache")(S,waterworld)
local count=0
local function water() count=count+1;return 0 end
local close,far=S.id(6,6),S.id(S.W-5,S.H-5)
local function visit(id)
  local a,b=S.xy(id)
  return cache.visit(water,a-1,b-1,1,id,waterworld.tiles[id])
end
visit(close);visit(far);visit(close);visit(far)
assert(count==2)
cache.invalidate(S.id(7,7))
visit(close);visit(far)
assert(count==3,"A municipal build cannot erase the distant sea cache")
print("PASS municipal dirty markers only invalidate nearby quiet-sea words")

-- Real worker house writes can clear ordinary woods without enabling
-- new municipal roads or touching another company's property.
local function wooded_house(own)
  local s,t=fixture()
  s.stock_road_town_policy={allow_town_roads=false}
  local id=S.id(11,13)
  local cell=s.tiles[id]
  cell.wood,cell.stock_clear_ground,cell.stock_clear_density=1,"grass",3
  local company=S.company(s,"Neighbor")
  local money=company.cash
  if own then cell.owner="Neighbor" end
  local draw={1073741824,0,300000000,41}
  local i=0
  W.tick(s,1,function() i=i+1;return draw[i] or (i%4)*1073741824 end)
  assert(company.cash==money and cell.owner==(own and "Neighbor" or nil))
  if own then
    assert(cell.wood and not cell.house and t.num_houses==0)
  else
    assert(cell.house and not cell.wood and not cell.stock_clear_ground and t.num_houses==1 and s.changed[1]==id)
    local C=D("packed_campaign")
    local reopened=C.decode(C.encode(s))
    assert(reopened.tiles[id].source_house.id==cell.source_house.id and not reopened.tiles[id].wood)
  end
end
wooded_house(false)
wooded_house(true)
print("PASS RC1 town writes on ordinary woods; private wooded lots remain intact")

-- CmdBuildRoad accepts an addition to ordinary company pavement without
-- replacing its owner, and still forbids a junction on one-way pavement.
do
  local s,t,center=fixture()
  local cell=s.tiles[center]
  cell.owner,cell.road_town="Carriers",nil
  local company=S.company(s,cell.owner)
  local cash=company.cash
  s.fleet[7]={engine=1,depot=center}
  assert(not S.town_road_piece(s,1,center,5,true) and cell.road_bits==10)
  s.fleet[7]=nil
  cell.road_disallowed=1
  assert(not S.town_road_piece(s,1,center,5,true) and cell.road_bits==10 and cell.road_disallowed==1)
  cell.road_disallowed=nil
  cell.roadworks=true
  assert(not S.town_road_piece(s,1,center,5,true) and cell.road_bits==10)
  cell.roadworks=nil
  W.tick(s,1,draw)
  assert(cell.road_bits==15 and cell.owner=="Carriers" and cell.road_town==nil)
  assert(company.cash==cash and s.changed[1]==center)
end
print("PASS live growth extends eligible company road without taking ownership or billing, rejects active traffic and works")

-- Turning town road construction off does not remove the existing
-- bridge from the stock house search. The town can build on its far side.
do
  local s,t=bridgeworld,bridgecity
  local x,z=S.xy(bridge.start)
  local far,fz=S.xy(bridge["end"])
  assert(z==fz)
  local far_street=S.id(far+1,z)
  if S.road_bits(s,far_street)==0 then assert(S.town_road_piece(s,t.id,far_street,10,true)) end
  local old_road=S.road_bits(s,far_street)
  local destination=S.id(far+1,z+1)
  s.tiles[destination].wood=1
  local count=t.num_houses
  t.x,t.z,t.grow_counter,t.growing,t.layout=x,z,0,true,"original"
  s.stock_road_town_policy={allow_town_roads=false}
  local words={0,1073741824,0,300000000,41}
  local i=0
  W.tick(s,3,function()
    i=i+1
    assert(i<40,"excess road-walk randomness")
    return words[i] or (i%4)*1073741824
  end)
  assert(t.num_houses==count+1 and s.tiles[destination].house and not s.tiles[destination].wood)
  assert(S.road_bits(s,far_street)==old_road and s.stock_road_bridges[s.tiles[bridge.start].road_bridge_id]==bridge)
end
print("PASS houses-only stock policy follows an existing bridge and builds beyond it without changing roads")

-- LevelTownLand quotes LandscapeClear on each affected tree tile, then
-- clears the admitted footprint with the corner change. Paid land stays.
do
  local s,_,x,z=slope_fixture()
  local id=S.id(x,z)
  local board=W.road_board(s)
  local company=S.company(s,"Neighbor")
  local cash=company.cash
  local grove={count=3}
  s.tiles[id].wood=grove
  s.tiles[id].owner="Neighbor"
  local revision=s.corner_grid.revision
  assert(not board.level_land(x,z,draw))
  assert(s.tiles[id].wood==grove and s.corner_grid.revision==revision)
  s.tiles[id].owner=nil
  assert(board.level_land(x,z,draw))
  assert(T.tile(s.corner_grid,x,z)==0 and not s.tiles[id].wood)
  assert(s.corner_grid.revision==revision+1 and company.cash==cash)
end
print("PASS stock municipal grading levels an eligible wooded site without modifying protected land")


-- Municipal CmdBuildRoad modifies only the road layer of stock mixed
-- pavement. A planned future tram visit is not ground occupancy.
do
  local s,t,center=fixture()
  local cell=s.tiles[center]
  local road=S.company(s,"Road Carrier")
  local tram=S.company(s,"Tram Carrier")
  local a,b=road.cash,tram.cash
  cell.owner,cell.road_town="Road Carrier",nil
  local rail={kind="road",tramtype=1,tram_bits=10,tram_owner="Tram Carrier"}
  cell.tram=rail
  local x,z=S.xy(center)
  local other=S.id(x+1,z)
  s.tiles[other].tram=rail
  local board=W.road_board(s)
  assert(not B.can_follow(board,x,z,2,true),"Town walks must not use a tram-only tile")
  local frames={{[4]=center}}
  s.stock_tram_fleet={[3]={phase="run",leg=1,index=1,legs={{path={center,other},frames=frames}}}}
  assert(not S.town_road_piece(s,t.id,center,5,true) and cell.road_bits==10)
  frames[1][4]=other
  assert(S.town_road_piece(s,t.id,center,5,true))
  assert(cell.road_bits==15 and cell.owner=="Road Carrier" and cell.tram==rail and
    rail.tram_bits==10 and rail.tram_owner=="Tram Carrier" and road.cash==a and tram.cash==b)
  print("PASS stock mixed town road adds only road bits; tram occupation, but not a future route, blocks the edit")
end

-- RC1 road.cpp CleanUpRoadBits preserves only the actual connection on
-- an adjacent facility. Existing plain pavement and clear land differ.
do
  local s,t,center=fixture()
  local x,z=S.xy(center)
  local offsets={{-1,0},{0,1},{1,0},{0,-1}}
  for d,offset in ipairs(offsets) do
    local to=S.id(x+offset[1],z+offset[2])
    local face=2^(4-d)
    local outward=(d+1)%4+1
    local reverse=2^(4-outward)
    local axis=face+reverse
    local tile=s.tiles[to]
    local function clean()
      return W.road_board(s).clean_road_bits(t,x,z,face)
    end
    assert(clean()==face,"clear land retains a forward extension")
    tile.build,tile.road_bits,tile.owner="road_station",axis,"Road Carrier"
    tile.stop_axis=axis
    assert(clean()==face,"through terminal with the same axis retains the road")
    tile.road_bits,tile.stop_axis=15-axis,15-axis
    assert(clean()==0,"cannot connect to the side of a through terminal")
    tile.road_bits,tile.stop_axis=reverse,reverse
    assert(clean()==face,"bay entrance faces the growth")
    tile.road_bits,tile.stop_axis=face,face
    assert(clean()==0,"cannot connect to a bay back wall")
    tile.build,tile.stop_axis,tile.depot_dir="road_depot",nil,5-outward
    assert(clean()==face,"depot entrance faces the growth")
    tile.depot_dir=5-d
    assert(clean()==0,"cannot connect to a depot back wall")
    tile.build,tile.road_bits,tile.owner,tile.depot_dir=nil,nil,nil,nil
  end
  print("PASS municipal road cleanup preserves through lanes and facing bay/depot entrances in every orientation")
end

-- CanBuildHouseHere uses LandscapeClear(Auto, NoWater). One ordinary
-- road half is removable by OWNER_TOWN; a road layer that would carry
-- through traffic, an occupied tip, or a tram/facility is not.
do
  for _,guard in ipairs({"none","two","works","tram","vehicle","depot","crossing"}) do
    local s,t=fixture()
    s.stock_road_town_policy={allow_town_roads=false}
    local id=S.id(11,13)
    local cell=s.tiles[id]
    local company=S.company(s,"Neighbor")
    local cash=company.cash
    cell.build,cell.road_bits,cell.owner="road",4,"Neighbor"
    if guard=="two" then cell.road_bits=5 end
    if guard=="works" then cell.roadworks=true end
    if guard=="tram" then cell.tram={kind="road",tram_bits=4} end
    if guard=="vehicle" then s.fleet[1]={depot=id} end
    if guard=="depot" then cell.build="road_depot" end
    if guard=="crossing" then cell.level_crossing={} end
    assert(S.town_clear_road_tip(s,id,false)==(guard=="none"))
    assert(cell.build and not cell.house and cell.owner=="Neighbor","Quote changed the surface")
    local draw={1073741824,0,300000000,41}
    local n=0
    W.tick(s,1,function() n=n+1;return draw[n] or (n%4)*1073741824 end)
    if guard=="none" then
      assert(cell.source_house and t.num_houses==1 and not cell.build and not cell.owner and not cell.road_bits)
      assert(s.changed[1]==id)
    else
      assert(cell.build and not cell.house and cell.owner=="Neighbor")
    end
    assert(company.cash==cash,"Municipal housekeeping must not bill the company")
  end
  local s,t=fixture()
  local id=S.id(17,12)
  assert(S.town_road_piece(s,2,id,10,true))
  local board=W.road_board(s)
  assert(board.road_allowed(t,17,12,0,function() error("Flat road should not need an RNG draw") end))
  assert(s.tiles[id].road_town==2)
end
print("PASS stock town can replace one clear road tip with a house, protects occupied/compound facilities, and can approach a foreign town's road")
