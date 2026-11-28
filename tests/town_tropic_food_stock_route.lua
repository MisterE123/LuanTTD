-- An isolated stock Tropic economy corridor with actual road movement,
-- cargo pickup, processing and sale. Ground and initial firm locations
-- are a controlled stock-valid board, not a native map comparison.
local io_path,load_checkpoint,save_checkpoint=...
local p=io_path or "mods/luanttd_core/"
local function m(n)return dofile(p..n..".lua") end
local function o(n)return m("openttd/"..n) end
local S,T,G=m("sim"),o("terrain"),o("town_growth")
local catalog=o("town_growth_houses_all_rc1")
local B=o("town_growth_build")(G,o("town_growth_houses"),catalog)
local W=m("town_growth_runtime")(S,T,G,B,o("town_passengers"))
local Cal,Codec=o("stock_engine_calendar"),m("packed_campaign")
local Houses=o("town_house_acceptance_rc1")
local owner="Tropic service"
S.W,S.H=64,64
local function id(x,z)return S.id(x+1,z+1) end
local s
local function start()
  return {version=1,seed=16013,day=0,tiles={},sites={},companies={},stations={},fleet={},
    next_station=1,next_vehicle=1,topology=0,subsidies={},speed=1,news={},stock_climate={landscape="tropic"},
    road_economy=true,road_stock_loading=true,road_stock_clock=true,road_stock_house_supply=true,
    road_bay_build=true,road_junction_clearance=true,stock_coastal_profile=true}
end
s=start()
local function resume()
  S.mount_road_bus_market(s,Cal,1985,false,false)
  S.mount_coastal_flood(s)
  S.mount_stock_town_growth(s,W,true)
  return assert(S.mount_tropic_freight(s))
end
local function prepare()
  s.corner_grid=T.new(64,64,function()return 1 end)
  for z=0,63 do for x=0,63 do
    s.tiles[id(x,z)]={h=1,variant=0,terrain="hill",stock_tropic_zone=x<=22 and 1 or nil,stock_clear_ground=x<=22 and 5 or nil}
  end end
  s.sites[1]={id=1,name="Test town",kind="town",tile=id(20,49),stock={},produced={},received={},population=467,service=0}
  s.tiles[s.sites[1].tile].site=1
  local town=G.new(1,21,50,{population=467,num_houses=4,climate="tropic",has_effect=function(i)return i==4 or i==5 end})
  s.stock_town_growth={version=1,towns={[1]=town},order={1}}
  local function house(x,z,number)
    local a=s.tiles[id(x,z)]
    assert(not a.build and not a.site and not a.stock_industry)
    a.house,a.source_house=true,{id=number,town=1,root=true,stage=3,completed=true,age_epoch=1985,random_bits=0}
  end
  for z=46,49 do
    assert(Houses.eighths(44,"food","tropic")==2)
    house(23,z,44)
  end
  house(19,47,44) -- stock Water Tower goes on this footprint.
  local firm={}
  s.stock_climate_industries=firm
  local F=resume()
  local existing={}
  local board={}
  function board.town() return {id=1,x=20,z=49,population=467} end
  function board.tile(x,z)
    local i=id(x,z);local t=i and s.tiles[i]
    if not t then return end
    return {valid=not t.stock_void,slope=T.tile(s.corner_grid,x+1,z+1),zone=t.stock_tropic_zone,
      on_water=t.terrain=="water",house=t.house,cell=t}
  end
  function board.clear(_,_,t,who)
    if t.cell.build or t.cell.site or t.cell.stock_industry or t.house and who~="town" then
      return false,"OCCUPIED"
    end
    return true
  end
  local function plant(k,n,x,z,layout)
    local shape,grading=F.climate_footprint(k,layout or 0,x,z,board,existing)
    assert(shape,grading);assert(not grading)
    firm[n]=F.new(k,n,x,z,{original=true,completed=true,counter=1,layout=layout,economy_year=1985})
    assert(#shape==#firm[n].tiles)
    for i,q in ipairs(shape) do
      local physical=firm[n].tiles[i]
      assert(q.x==physical.x and q.z==physical.z and q.gfx==physical.gfx)
      local a=s.tiles[id(q.x,q.z)]
      a.house,a.source_house=nil,nil
      a.stock_industry={id=n,gfx=q.gfx,chain="climate"}
    end
    existing[#existing+1]={type=F.spec[k].id,x=x,z=z,town=1}
  end
  plant("water_supply",11,19,6)
  plant("water_tower",12,19,47)
  plant("fruit_plantation",13,24,12)
  plant("maize_farm",14,24,19)
  local near,reason=F.climate_footprint("food_process",0,24,25,board,existing)
  assert(not near and reason=="INDUSTRY_TOO_CLOSE")
  plant("food_process",15,24,37)
  assert(S.plant_tropic_fields(s,firm[14])>0)
  local field_count=0
  for i,r in pairs(s.stock_farm_fields) do
    assert(r.industry==14 and r.variant>=0 and r.variant<=8)
    for _,style in pairs(r.fences) do assert(style==3) end
    assert(not s.tiles[i].stock_industry and s.tiles[i].stock_tropic_zone~=1)
    field_count=field_count+1
  end
  assert(field_count>=50)
  s.qa_initial_fields=field_count
  local c=S.company(s,owner);c.cash=80000000
  local function apply(q,why)
    assert(q,why);assert(S.apply_road_construction(s,owner,q))
  end
  local depot=id(22,4)
  apply(S.autoroad_plan(s,owner,id(22,5),id(22,51),1,false,true))
  apply(S.stock_road_terminal_plan(s,owner,depot,{kind="depot",dir=1}))
  local function stop(z)
    local a=id(22,z)
    apply(S.stock_road_stop_area_plan(s,owner,a,a,{kind="truck",dir=1,through=true,adjacent=true}))
    return assert(s.stations[s.tiles[a].station])
  end
  local intake,orchard,farm,processor,tower=stop(7),stop(14),stop(20),stop(38),stop(48)
  local function assign(engine,cargo,from,to)
    local n=assert(S.purchase(s,owner,engine,cargo,nil,depot))
    assert(S.add_order(s,owner,n,from.id))
    assert(S.add_order(s,owner,n,to.id))
    assert(S.toggle(s,owner,n))
    return n
  end
  assert(not S.vehicle_available(s,"wheat_hereford") and not S.vehicle_available(s,"grain_truck"))
  local vehicles={water=assign("water_uhl","water",intake,tower),
    fruit=assign("fruit_balogh","fruit",orchard,processor),
    maize=assign("maize_hereford","maize",farm,processor),
    food=assign("food_foster","food",processor,tower)}
  assert(not town.growing)
  return vehicles
end
local saved=load_checkpoint and load_checkpoint()
local opened=not not saved
local vehicles
if opened then
  s=assert(Codec.decode(saved))
  vehicles=assert(s.qa_food_trip)
  assert(s.fleet[vehicles.maize].units>0 and s.fleet[vehicles.maize].route)
  resume()
else vehicles=prepare() end
local town
local function all_paid()
  for _,n in pairs(vehicles) do if s.fleet[n].delivered==0 then return false end end
  return true
end
for day=s.day+1,350 do
  S.daily(s)
  town=s.stock_town_growth.towns[1]
  if not opened and s.fleet[vehicles.maize].units>0 and s.fleet[vehicles.maize].route then
    s.qa_food_trip=vehicles
    local packed=Codec.encode(s)
    if save_checkpoint then
      save_checkpoint(packed,s.fleet[vehicles.maize].units)
      return
    end
    s=assert(Codec.decode(packed));resume();opened=true
  end
  if opened and all_paid() and town.growing then
    local total,received=0,{}
    for cargo,n in pairs(vehicles) do
      local v=s.fleet[n];assert(v.revenue>0 and v.expense>0)
      received[cargo]=v.delivered
      total=total+v.delivered
    end
    local processor,sink=s.stock_climate_industries[15],s.stock_climate_industries[12]
    assert(processor.received.fruit==received.fruit and processor.received.maize==received.maize)
    assert(sink.received.water==received.water and received.fruit+received.maize>=received.food)
    assert(town.accepted.food.old_act>0 and not town.accepted.water)
    assert(town.received[4].old_act>0 and town.received[5].old_act>0 and town.reason=="serviced")
    assert(s.companies[owner].paid_units==total)
    local visited=0
    for i,r in pairs(s.stock_farm_fields) do
      if r.last_tick then
        visited=visited+1
        assert(r.industry==14 and not s.tiles[i].stock_industry and s.tiles[i].stock_tropic_zone~=1)
      end
    end
    assert(visited>=s.qa_initial_fields/2)
    print(("PASS Tropic Maize Farm lifecycle: %d initial crop tiles, %d visited tiles survive packed reopen"):format(s.qa_initial_fields,visited))
    print(("PASS live Fruit %d, Maize %d, Food %d and Water %d; town unlocked on day %d after packed reopen"):
      format(received.fruit,received.maize,received.food,received.water,day))
    return
  end
end
for k,n in pairs(vehicles) do local v=s.fleet[n];print(k,v.status,v.units,v.delivered) end
error("No complete live Food and Water month")
