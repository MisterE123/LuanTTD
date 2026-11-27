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
  return 0
end)==false)
assert(calls==3 and T.tile(world.corner_grid,x,z)==0 and world.corner_grid.revision==1)
local marked={}
for _,id in ipairs(world.changed) do marked[id]=true end
assert(marked[S.id(x,z)] and marked[S.id(x-1,z-1)])
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
