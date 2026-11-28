local p="mods/luanttd_core/"
local Sim=dofile(p.."sim.lua")
local Terrain=dofile(p.."openttd/terrain.lua")
local G=dofile(p.."openttd/town_growth.lua")
local B=dofile(p.."openttd/town_growth_build.lua")(G,dofile(p.."openttd/town_growth_houses.lua"))
local H=dofile(p.."openttd/town_passengers.lua")
local W=dofile(p.."town_growth_runtime.lua")(Sim,Terrain,G,B,H)
local F=dofile("tests/town_growth_live_fixture.lua")
local function world()
  local s=Sim.new(1751)
  dofile(p.."town_layout.lua")(Sim,s)
  s.corner_grid=dofile(p.."terrain_preview.lua")(Sim,Terrain,s)
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  Sim.mount_stock_town_growth(s,W)
  return s
end
local s=world()
for _,town_id in ipairs(s.stock_town_growth.order) do
  local town=s.stock_town_growth.towns[town_id]
  local roots,population=0,0
  for _,tile in ipairs(s.tiles) do
    local h=tile.house and tile.source_house
    if h and h.town==town_id and h.root~=false then roots=roots+1;population=population+H.specs[h.id][1] end
  end
  assert(town.num_houses==roots and town.population==population and s.sites[town_id].population==population)
end
local x,z=5,15
local tile=s.tiles[Sim.id(x,z)]
tile.wood=nil
assert(W.eligible_site(s,x,z)~=nil)
for _,k in ipairs{"owner","site","wood","source_house","build","station","parcel","rail_tracks","stock_industry","ship","airfield","tram","signal"} do
  tile[k]=true
  assert(W.eligible_site(s,x,z)==nil,k)
  tile[k]=nil
end
local id=Sim.id(x,z)
for _,k in ipairs{"level_crossing_tiles","bridge_above","tunnel_below","rail_bridge_above","rail_tunnel_below","aqueduct_above"} do
  local old=s[k]
  s[k]={[id]=1}
  assert(W.eligible_site(s,x,z)==nil,k)
  s[k]=old
end
local proposed=assert(Terrain.plan(s.corner_grid,x,z,1,true,{freeform_edges=false}))
assert(Terrain.apply(s.corner_grid,proposed))
local shape,base,top=Terrain.tile(s.corner_grid,x,z)
local deck,slope,raw=W.eligible_site(s,x,z)
assert(shape<16 and shape>0 and slope==shape and deck==top and raw==base and deck>raw)
local qa=F.first(Sim,s)
print("Growth tile ",qa.tile,"built at",qa.built_tick,"saved at",qa.tick)
local function copy(x)
  if type(x)~="table" then return x end
  local t={}
  for k,v in pairs(x) do t[k]=copy(v) end
  return t
end
s=copy(s)
-- Explicit disable stops new starts but lets the project in flight finish.
Sim.mount_stock_town_growth(s,W,false)
local last=s.stock_town_growth.towns[qa.town].last_build.tick
local h=F.second(Sim,s,qa,H.specs)
local age_model=dofile(p.."openttd/town_rebuild.lua")
local completed_year=Sim.date(s)
assert(h.age_epoch==completed_year and age_model.age(h,completed_year)==0)
local packed=dofile(p.."packed_campaign.lua")
local aged=packed.decode(packed.encode(s)).tiles[qa.tile].source_house
assert(age_model.age(aged,completed_year+1)==1)
assert(age_model.age(aged,completed_year+260)==255)
print("PASS completed campaign houses retain exact year ages through a packed reopen")
assert(s.stock_town_growth.towns[qa.town].last_build.tick==last)
local before=s.sites[qa.town].population
assert(Sim.build(s,"GrowthQA","clear",{qa.tile}))
assert(s.sites[qa.town].population==before-H.specs[h.id][1])
assert(not s.tiles[qa.tile].house)
print(("PASS house built %d, completed %d, first stock production %d after reload"):format(h.built_tick,h.completed_tick,h.first_cargo_tick))

do
  local target=world()
  local owner="Town funder"
  local company=Sim.company(target,owner)
  local id=target.stock_town_growth.order[1]
  local state=target.stock_town_growth.towns[id]
  local quote=assert(Sim.quote_town_buildings(target,owner,id))
  assert(quote.cost==207031 and not quote.affordable and quote.months==0)
  assert(not Sim.fund_town_buildings(target,owner,id,quote.cost) and company.cash==100000)
  company.cash=quote.cost+10
  assert(not Sim.fund_town_buildings(target,owner,id,quote.cost-1) and state.fund_buildings_months==0)
  local A=dofile(p.."campaign_authority_endpoint.lua")(Sim,{world=target})
  local live=assert(A.town_authority(owner,id))
  assert(live.ok and live.value.funding.affordable and live.value.funding.cost==207031)
  local cmd={kind="town_fund_buildings",town=id,cost=quote.cost,revision=live.revision}
  assert(A.command(owner,cmd).ok)
  assert(A.command(owner,cmd).why=="STALE_COMMAND")
  assert(company.cash==10 and company.expense==207031 and company.month_exp==207031)
  assert(state.fund_buildings_months==3 and state.growing and state.reason=="funded")
  local Packed=dofile(p.."packed_campaign.lua")
  local restored=assert(Packed.decode(Packed.encode(target)))
  assert(restored.stock_town_growth.towns[id].fund_buildings_months==3)
  assert(restored.companies[owner].cash==10)
  Sim.mount_stock_town_growth(restored,W)
  for month=1,3 do
    restored.day=month*30
    W.prepare_day(restored);W.month(restored,W.month_due(restored),function()return 65535 end)
    assert(restored.stock_town_growth.towns[id].fund_buildings_months==3-month)
  end
  print("PASS normal town funding uses exact stock base cost, three live growth months, saved payments and expiry")
end

-- The saved world option reaches the ordinary worker's month and funding
-- entry points, not only worldgen and the isolated RC1 rate calculation.
for setting=0,4 do
  local s=world()
  s.stock_generated_profile={town_settings={growth_setting=setting}}
  local id=s.stock_town_growth.order[1]
  local t=s.stock_town_growth.towns[id]
  local rolls=0
  W.prepare_day(s);W.month(s,W.month_due(s),function() rolls=rolls+1;return 0 end)
  assert(t.growing==(setting~=0),"monthly setting "..setting)
  assert(t.growth_rate==G.normal_rate(t,0,setting))
  if setting==0 then assert(rolls==0) end
  assert(W.fund_buildings(s,id)==t and t.growing and t.fund_buildings_months==3)
  assert(t.growth_rate==G.normal_rate(t,0,setting))
end
print("PASS five saved growth modes reach the worker; funding overrides None as in RC1")

-- The ordinary worker's board applies the RC1 rule before spending a
-- house-choice RNG draw; one eligible diagonal road allows the lot.
do
  local s=world()
  local x,z=5,15
  local town=s.stock_town_growth.towns[s.stock_town_growth.order[1]]
  for dx=-1,1 do for dz=-1,1 do s.tiles[Sim.id(x+dx,z+dz)]={terrain="grass"} end end
  local track=s.tiles[Sim.id(x+1,z)]
  track.tram={kind="road",tramtype=1,tram_bits=10}
  local board=W.road_board(s)
  assert(not board.house_roadtypes(x,z))
  local draws=0
  local function random() draws=draws+1;return 0 end
  local opts={year=1950,allow_roads=false}
  assert(not B.house(town,board,x,z,opts,random) and draws==0)
  local diag=s.tiles[Sim.id(x-1,z-1)]
  diag.build,diag.road_bits="road",10
  assert(board.house_roadtypes(x,z))
  B.house(town,board,x,z,opts,random)
  assert(draws>0,"Ordinary road should allow the stock lot selection")
  print("PASS ordinary live house growth: no lots beside only tram, allowed beside a diagonal road")
end

-- Use the real live board, house writer, coast clear command and native
-- tile records. Drive only the initiating search result deterministically.
do
  local s=world()
  s.stock_generated_profile={}
  Sim.mount_coastal_flood(s)
  local x,z=5,15
  local id,river=Sim.id(x,z),Sim.id(x+1,z)
  if Terrain.tile(s.corner_grid,x,z)==0 then
    assert(Terrain.apply(s.corner_grid,assert(Terrain.plan(s.corner_grid,x,z,1,true,{freeform_edges=false}))))
  end
  local slope=Terrain.tile(s.corner_grid,x,z)
  assert(slope==1 or slope==2 or slope==4 or slope==8)
  local tile={terrain="water",water_class="sea",coastal_water=true,stock_water_rocks=true}
  s.tiles[id]=tile
  s.tiles[river]={terrain="water",water_class="river"}
  local board=W.road_board(s)
  assert(board.clear_quote(x,z,"house"))
  assert(not board.clear_quote(x+1,z,"house"))
  tile.owner="Private"
  assert(not board.clear_quote(x,z,"house"))
  tile.owner=nil
  local tid=s.stock_town_growth.order[1]
  local town=s.stock_town_growth.towns[tid]
  local prior=B.grow
  s.stock_town_growth.order={tid}
  town.growing,town.grow_counter=true,0
  B.grow=function(t,b,options,random)
    assert(t==town and b.clear_quote(x,z,"house"))
    return {kind="house",town=tid,id=6,x=x,z=z,random_bits=22,
      parts={{town=tid,id=6,x=x,z=z,root=true,root_x=x,root_z=z,completed=false,stage=0,counter=0}}}
  end
  local previous=town.num_houses
  W.tick(s,3000,function()return 0 end)
  B.grow=prior
  assert(tile.house and tile.source_house.id==6 and not tile.coastal_water and not tile.water_class
    and tile.terrain~="water" and s.tiles[river].water_class=="river" and town.num_houses==previous+1)
  print("PASS ordinary live town house clears only the selected unowned shore tile, preserving adjacent river")
end


-- Farmland is an ordinary clear tile, including when the stock land
-- levelling probe changes a field before attempting a house. A wide
-- four-corner job costs more with crops; failed quotes mutate nothing.
do
  local s=world()
  local x,z=32,32
  local id,other=Sim.id(x,z),Sim.id(x+3,z)
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 1 end)
  s.stock_generated_profile={map_height_limit=30}
  for dx=-2,2 do for dz=-2,2 do s.tiles[Sim.id(x+dx,z+dz)]={h=1,terrain="grass"} end end
  local planted=function() return {kind="clear",ground="field",variant=4,counter=0,
    slope=0,base=1,fences={south=2},industry=12301} end
  s.stock_farm_fields={[other]=planted()}
  for dx=-1,1 do for dz=-1,1 do s.stock_farm_fields[Sim.id(x+dx,z+dz)]=planted() end end
  local b=W.road_board(s)
  assert(b.clear_quote(x,z,"house"))
  local rev=s.corner_grid.revision
  assert(not b.terraform_land(x,z,15,true,true) and s.corner_grid.revision==rev)
  assert(s.stock_farm_fields[id] and s.stock_farm_fields[other])
  assert(b.terraform_land(x,z,15,true,false,function() return 4294967295 end))
  assert(not s.stock_farm_fields[id] and s.stock_farm_fields[other].industry==12301
    and s.tiles[id].stock_clear_density==0 and s.corner_grid.revision==rev+1)
  print("PASS municipal crop-field grading charges stock clear prices against its cap and clears only modified fields")
end


-- Living above an underground span does not authorize grading through
-- its roof or building beneath a separate overpass.
do
  local s=world()
  local x,z=32,32
  local id=Sim.id(x,z)
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 2 end)
  s.stock_generated_profile={map_height_limit=30}
  for dx=-2,2 do for dz=-2,2 do s.tiles[Sim.id(x+dx,z+dz)]={h=2,terrain="hill"} end end
  s.tunnel_below={[id]=1}
  s.rail_tunnel_below={}
  local b=W.road_board(s)
  assert(b.clear_quote(x,z,"house"))
  assert(not b.terraform_land(x,z,15,false,false) and s.corner_grid.revision==0 and s.tunnel_below[id]==1)
  s.tunnel_below[id]=nil
  s.rail_tunnel_below[id]=2
  assert(b.clear_quote(x,z,"house"))
  assert(not b.terraform_land(x,z,15,false,false) and s.corner_grid.revision==0 and s.rail_tunnel_below[id]==2)
  s.bridge_above={[id]=3}
  assert(not b.clear_quote(x,z,"house"))
  print("PASS municipal houses can sit above road or rail bores; unknown span geometry stays protected")
end

-- Native RC1 LevelTownLand beneath an actual deck (deck=3, target
-- north corner 1, other corners 2): the 250 quote succeeds and the
-- eight Execute draws leave a flat surface without editing the bridge.
do
  local function setup(level)
    local s=world()
    local x,z=32,32
    local id=Sim.id(x,z)
    s.corner_grid=Terrain.new(Sim.W,Sim.H,function(u,v) return u==x and v==z and level or 2 end)
    s.stock_generated_profile={map_height_limit=30}
    for dx=-2,2 do for dz=-2,2 do s.tiles[Sim.id(x+dx,z+dz)]={h=2,terrain="hill"} end end
    return s,W.road_board(s),x,z,id
  end
  for _,layer in ipairs(Sim.bridge_layers) do
    local s,b,x,z,id=setup(1)
    local span={deck=3,owner="Rail or road owner"}
    s[layer[1]],s[layer[2]]={[id]=11},{[11]=span}
    assert(Terrain.tile(s.corner_grid,x,z)==7 and not b.clear_quote(x,z,"house"))
    s.passenger_rating_rng={760892031,1251784568}
    assert(b.level_land(x,z,function() return Sim.stock_random_u32(s) end))
    local a,h=Terrain.tile(s.corner_grid,x,z)
    assert(a==0 and h==2 and s[layer[1]][id]==11 and s[layer[2]][11]==span and span.deck==3)
    assert(s.passenger_rating_rng[1]==1077725541 and s.passenger_rating_rng[2]==3220888100)
  end
  local s,b,x,z,id=setup(3)
  s.bridge_above,s.stock_road_bridges={[id]=11},{[11]={deck=3}}
  assert(Terrain.tile(s.corner_grid,x,z)==8)
  assert(not b.terraform_land(x,z,7,true,true,function() error("A denied grade cannot draw RNG") end))
  assert(s.corner_grid.revision==0 and Terrain.corner(s.corner_grid,x,z)==3 and s.bridge_above[id]==11)

  -- RC1's default maximum separation is 12 heights after lowering.
  s,b,x,z,id=setup(2)
  s.bridge_above,s.stock_road_bridges={[id]=11},{[11]={deck=14}}
  assert(not b.terraform_land(x,z,8,false,true,function() error("Overheight bridge blocks!") end))
  s.stock_road_bridges[11].deck=13
  assert(b.terraform_land(x,z,8,false,true,function() return 0 end))
  assert(Terrain.corner(s.corner_grid,x,z)==1 and s.bridge_above[id]==11)

  -- RC1 AutoslopeEnabled expressly excludes the town company. A
  -- neighbouring house prevents both directions of LevelTownLand even
  -- though a human player's foundation callback could preserve its top.
  s,b,x,z,id=setup(1)
  local home=Sim.id(x-1,z)
  s.stock_road_town_policy={autoslope=true}
  s.tiles[home].house,s.tiles[home].source_house=true,{id=0}
  assert(not b.level_land(x,z,function() error("The house blocks both quotes") end))
  assert(s.corner_grid.revision==0 and s.tiles[home].source_house.id==0)
  print("PASS RC1 municipal grading under a verified bridge, deck interference, stock draws and no town autoslope on houses")
end

-- Native RC1 lowered a ridge corner 3 -> 2 over a real road tunnel at
-- height 1, but rejected lowering a flat 2 -> 1 at the tunnel floor.
do
  local function terrain(level)
    local s=world()
    local x,z=32,32
    s.corner_grid=Terrain.new(Sim.W,Sim.H,function(u,v) return u==x and v==z and level or 2 end)
    s.stock_generated_profile={map_height_limit=30}
    for dx=-2,2 do for dz=-2,2 do s.tiles[Sim.id(x+dx,z+dz)]={h=2,terrain="hill"} end end
    return s,W.road_board(s),x,z,Sim.id(x,z)
  end
  for _,layer in ipairs({{"tunnel_below","stock_road_tunnels"},{"rail_tunnel_below","stock_rail_spans"}}) do
    local s,b,x,z,id=terrain(3)
    local span={base=1,kind="tunnel",owner="Operator"}
    s[layer[1]],s[layer[2]]={[id]=11},{[11]=span}
    s.passenger_rating_rng={3956879858,589167907}
    assert(b.terraform_land(x,z,8,false,true,function() return Sim.stock_random_u32(s) end))
    local slope,level=Terrain.tile(s.corner_grid,x,z)
    assert(slope==0 and level==2 and s[layer[1]][id]==11 and s[layer[2]][11]==span and span.base==1)
    assert(s.passenger_rating_rng[1]==2752835609 and s.passenger_rating_rng[2]==1918748449)
    local revision=s.corner_grid.revision
    assert(not b.terraform_land(x,z,8,false,true,function() error("The bore blocks the quote") end))
    assert(s.corner_grid.revision==revision and Terrain.corner(s.corner_grid,x,z)==2)
  end
  print("PASS RC1 municipal roof cover, protected bore, exact execution draws and unchanged route")
end

-- Native RC1 IsRoadAllowedHere + GrowTownWithRoad beneath a bridge
-- built along X: the normal lookahead denies X and accepts Y, then the
-- town installs ROAD_Y=5 without changing RNG or the elevated route.
do
  local s=world()
  local x,z=32,32
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 2 end)
  s.stock_generated_profile={map_height_limit=30}
  for dx=-5,5 do for dz=-3,3 do s.tiles[Sim.id(x+dx,z+dz)]={h=2,terrain="hill"} end end
  local head,tail,lot=Sim.id(x-4,z),Sim.id(x+4,z),Sim.id(x,z)
  local okay,why=Sim.road_bridge(s,"Span Builder",head,tail,0)
  assert(okay,why)
  local key=assert(s.bridge_above[lot])
  local bridge=assert(s.stock_road_bridges[key])
  assert(bridge.deck==3 and bridge.axis==0)
  local b=W.road_board(s)
  local town=s.stock_town_growth.towns[s.stock_town_growth.order[1]]
  local function no_draw() error("Flat lookahead must not draw RNG") end
  assert(not b.road_allowed(town,x,z,0,no_draw) and not b.road_allowed(town,x,z,2,no_draw))
  assert(b.road_allowed(town,x,z,1,no_draw) and b.road_allowed(town,x,z,3,no_draw))
  assert(b.clear_quote(x,z,"road") and not b.clear_quote(x,z,"house"))
  assert(b.road_quote(town,x,z,5))
  local balance=Sim.company(s,"Span Builder").cash
  s.passenger_rating_rng={2886033970,1113251459}
  assert(Sim.town_road_piece(s,town.id,lot,5,true))
  assert(s.tiles[lot].road_bits==5 and s.tiles[lot].road_town==town.id and not s.tiles[lot].owner)
  assert(s.bridge_above[lot]==key and s.stock_road_bridges[key]==bridge and bridge.owner=="Span Builder")
  assert(Sim.company(s,"Span Builder").cash==balance and s.passenger_rating_rng[1]==2886033970
    and s.passenger_rating_rng[2]==1113251459)
  -- The actual stock GrowTownWithRoad command adds NE=8 to ROAD_Y=5
  -- on a surface street under the same deck, yielding junction mask 13.
  assert(b.road_quote(town,x,z,8))
  assert(Sim.town_road_piece(s,town.id,lot,8,true))
  assert(s.tiles[lot].road_bits==13 and s.bridge_above[lot]==key and s.stock_road_bridges[key]==bridge)
  print("PASS RC1 town street crosses below an existing bridge without replacing the deck or allowing parallel lookahead")
end

-- Native RC1 builds normal municipal road above a road tunnel in
-- both directions, without running the bridge-only parallel veto.
do
  local s=world()
  local x,z=33,32
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(u)
    return u>=x-3 and u<=x+3 and 2 or 1
  end)
  s.stock_generated_profile={map_height_limit=30}
  for u=x-5,x+5 do for v=z-3,z+3 do s.tiles[Sim.id(u,v)]={h=2,terrain="hill"} end end
  local start,west,east=Sim.id(x-4,z),Sim.id(x-1,z),Sim.id(x+1,z)
  local ok,why=Sim.road_tunnel(s,"Span Builder",start,false)
  assert(ok,why)
  local key=assert(s.tunnel_below[west])
  local bore=assert(s.stock_road_tunnels[key])
  assert(bore.base==1 and s.tunnel_below[east]==key)
  local b=W.road_board(s)
  local town=s.stock_town_growth.towns[s.stock_town_growth.order[1]]
  local function no_draw() error("Flat lookahead must not draw RNG") end
  assert(b.road_allowed(town,x-1,z,1,no_draw))
  assert(b.road_allowed(town,x+1,z,2,no_draw))
  assert(b.road_quote(town,x-1,z,5) and b.road_quote(town,x+1,z,10))
  s.passenger_rating_rng={2536072277,1090321433}
  assert(Sim.town_road_piece(s,town.id,west,5,true))
  assert(Sim.town_road_piece(s,town.id,east,10,true))
  assert(s.tiles[west].road_bits==5 and s.tiles[east].road_bits==10 and s.tunnel_below[west]==key
    and s.stock_road_tunnels[key]==bore and s.passenger_rating_rng[1]==2536072277
    and s.passenger_rating_rng[2]==1090321433)
  print("PASS RC1 town roads run alongside or across a covered tunnel without altering the bore")
end

-- Real 16.0-RC1 LevelTownLand calls the normal road Auto clear: the
-- adjoining owned-by-town or unowned road stub costs 40 to remove;
-- a full ordinary road prevents both grading attempts.
do
  for _,test in ipairs({
      {bits=8,town=1,first={308770875,2314172559},last={3309771557,3607261628}},
      {bits=10,town=1,first={3309771557,3607261628}},
      {bits=8,first={3309771557,3607261628},last={1325700299,2080519754}},
      {bits=8,owner="Private builder",first={3309771557,3607261628}},
      {bits=8,town=1,works=true,first={3309771557,3607261628}},
    }) do
    local s=world()
    local x,z=32,32
    s.corner_grid=Terrain.new(Sim.W,Sim.H,function(u,v) return u==x and v==z and 1 or 2 end)
    s.stock_generated_profile={map_height_limit=30}
    for dx=-2,2 do for dz=-2,2 do s.tiles[Sim.id(x+dx,z+dz)]={h=2,terrain="hill"} end end
    local tip=s.tiles[Sim.id(x-1,z)]
    tip.build,tip.road_town,tip.road_bits="road",test.town,test.bits
    tip.owner,tip.roadworks=test.owner,test.works
    assert(Terrain.tile(s.corner_grid,x,z)==7 and Terrain.tile(s.corner_grid,x-1,z)==14)
    s.passenger_rating_rng={unpack(test.first)}
    local b=W.road_board(s)
    local changed=b.level_land(x,z,function() return Sim.stock_random_u32(s) end)
    if test.last then
      assert(changed and not tip.road_bits and not tip.road_town and not tip.build)
      assert(Terrain.tile(s.corner_grid,x,z)==0 and Terrain.tile(s.corner_grid,x-1,z)==0)
    else
      assert(not changed and tip.road_bits==test.bits and tip.owner==test.owner and s.corner_grid.revision==0)
    end
    local expect=test.last or test.first
    assert(s.passenger_rating_rng[1]==expect[1] and s.passenger_rating_rng[2]==expect[2])
  end
  print("PASS RC1 municipal land grade removes one-bit road tips, not full roads, with stock draws")
end
