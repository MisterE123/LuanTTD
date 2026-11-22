-- SPDX-License-Identifier: GPL-2.0-only
-- Exact untreated seed 1751, actual source route frames and stock loader.
local prefix="mods/bayline/"
local function m(p) return dofile(prefix..p..".lua") end
local Sim,Terrain,Packets,Income,K=m("sim"),m("openttd/terrain"),m("openttd/passengers"),m("openttd/income"),m("openttd/station_rating")
local C=m("openttd/station_catchment")(Packets,K)
local Station=m("station_rating_runtime")(Sim,K,Packets)
local Coal=m("openttd/coal_industry")(Packets,K,C,Income)
local Timber=m("openttd/timber_industry")(Packets,C,K,Income,Coal,m("openttd/town_goods"))
local Rules=m("openttd/farm_factory_industry")(Packets,C,K,Income,Coal,Timber)
local Fields=m("openttd/farm_factory_fields")(Coal)
local World=m("farm_factory_world")(Sim,Terrain,Rules,Fields,C)
local Loader=m("road_loading_runtime")(m("openttd/loading_timing"),Packets)
local R=m("road_farm_service")(Sim,Rules,m("farm_factory_runtime")(
  Rules,Fields,m("timber_industry_runtime"),C),Packets,Income,K,Station)
local function copy(x)
  if type(x)~="table" then return x end
  local t={};for k,v in pairs(x) do t[k]=copy(v) end;return t
end
local function equal(x,y)
  if type(x)~="table" or type(y)~="table" then return x==y end
  for k,v in pairs(x) do if not equal(v,y[k]) then return false end end
  for k,v in pairs(y) do if x[k]==nil and v~=nil then return false end end
  return true
end
local function reject(action,reason)
  local result,code,id=action()
  assert(not result and code==reason,tostring(code).." expected "..reason)
  return id
end
local id=Sim.id
local s=Sim.new(1751)
m("town_layout")(Sim,s)
s.corner_grid=m("terrain_preview")(Sim,Terrain,s)
m("town_passenger_runtime")(Sim,m("openttd/town_passengers")).start(s)
local coal=assert(m("coal_industry_world")(Sim,Terrain,Coal).seed(s,id(30,11),id(40,12)))
local scenario=assert(World.scenario_1751(s))
local p=assert(World.quote_pair(s,scenario.farm,scenario.factory))
local before=copy(s)
assert(#p.farm.cells==9 and #p.factory.cells==12 and p.farm.level==0 and p.factory.level==0)
assert(not World.default_1751(Sim.new(1750),Station.random_u32))
reject(function() return World.commit_pair(s,p) end,"SHARED_INDUSTRY_RNG_REQUIRED")
assert(equal(s,before))
s.rail_bridge_above={[scenario.factory_intake]=128}
assert(reject(function() return World.commit_pair(s,p,Station.random_u32) end,"INDUSTRY_SITE_OCCUPIED")==scenario.factory_intake)
s.rail_bridge_above=nil
local forged=copy(p);forged.factory.cells[1].gfx=77
reject(function() return World.commit_pair(s,forged,Station.random_u32) end,"STALE_INDUSTRY_QUOTE")
s.stock_timber_industries={[0x1000]={}}
reject(function() return World.default_1751(s,Station.random_u32) end,"TIMBER_GOODS_WORKBENCH_ACTIVE")
s.stock_timber_industries=nil
s.stock_coal_industries[World.INDUSTRY_ID_BASE+1]={}
reject(function() return World.commit_pair(s,p,Station.random_u32) end,"INDUSTRY_ID_COLLISION")
s.stock_coal_industries[World.INDUSTRY_ID_BASE+1]=nil
assert(equal(s,before),"Failed preflight advanced RNG or changed first site")
local receipt=assert(World.default_1751(s,Station.random_u32))
assert(receipt.farm==0x2000 and receipt.factory==0x2001 and #receipt.tiles==21)
assert(equal(s.corner_grid,before.corner_grid) and equal(s.stock_coal_industries,before.stock_coal_industries))
for i,site in ipairs(before.sites) do assert(equal(s.sites[i],site)) end
for i,t in ipairs(before.tiles) do
  if t.house or t.build or t.site or t.stock_industry then assert(equal(s.tiles[i],t),"Protected native tile changed") end
end
for _,i in ipairs(receipt.tiles) do
  local ref,ind=assert(World.record(s,i))
  assert(ref.id==ind.id and #ind.tiles==(ind.kind=="farm" and 9 or 12))
  assert(ref.chain=="farm" and ref.layout==0 and not World.field(s,i))
  assert(s.tiles[i].h==before.tiles[i].h and s.tiles[i].terrain==before.tiles[i].terrain)
end
assert(World.record(s,scenario.factory_intake).gfx==41)
assert(not World.protected(s,id(18,16)) and not World.protected(s,id(17,19))) -- factory holes
local crop_count=0
for i,v in pairs(s.stock_farm_fields) do
  assert(World.field(s,i)==v and v.industry==receipt.farm and v.variant>=0 and v.variant<=8)
  local old=before.tiles[i]
  assert(not old.build and not old.house and not old.site and not old.stock_industry and not s.tiles[i].wood)
  crop_count=crop_count+1
end
assert(crop_count>=80 and equal(s.stock_farm_fields,copy(s).stock_farm_fields))
local probe=copy(s)
do
  local i,crop=next(probe.stock_farm_fields)
  local x,z=Sim.xy(i)
  local b=World.field_board(probe)
  crop.counter,crop.variant=7,8
  b.visit(x-1,z-1,74,true)
  assert(crop.variant==8 and crop.counter==7)
  b.visit(x-1,z-1,75);b.visit(x-1,z-1,75)
  assert(crop.variant==0 and crop.counter==0)
  probe.stock_farm_industries[receipt.farm].removed=true
  crop.counter,crop.variant=7,7
  b.visit(x-1,z-1,76)
  assert(not World.field(probe,i))
end
assert(not Sim.build(s,"A","clear",{scenario.factory_intake}))
assert(not Sim.build(s,"A","road",{scenario.factory_intake}))
assert(not Sim.landscape(s,"A","raise",18,17))
-- Use the existing typed-stop builder and protected source road logic.
s.road_economy,s.road_coal,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true,true
for _,group in ipairs(scenario.road_waypoints) do
  for j=2,#group do
    local ok,note=Sim.build(s,"A","road",Sim.line(group[j-1],group[j]));assert(ok,note)
  end
end
for _,i in ipairs({scenario.farm_stop,scenario.factory_stop,scenario.goods_stop}) do
  assert(Sim.build_truck_stop(s,"A",i))
  assert(not World.field(s,i),"Road needs to mask the field immediately, before its next landscape pass")
end
assert(Sim.build(s,"A","road_depot",{scenario.depot}))
local function st(i) return assert(s.stations[s.tiles[i].station]) end
local farm,factory,town=st(scenario.farm_stop),st(scenario.factory_stop),st(scenario.goods_stop)
local function leg(a,b,prior,expected)
  local path,td,_,frames=Sim.path(s,a,b,"road","A",nil,{engine="coal_tipper",cargo="coal",road_arrival_td=prior})
  assert(path and frames and path[1]==a.tile and path[#path]==b.tile)
  assert(not expected or #frames==expected,("path %d to %d: %s expected %s"):format(a.id,b.id,#frames,tostring(expected)))
  return td,frames
end
local _,out=leg(farm,factory,0,469)
local rt=leg(factory,farm,1,530)
assert(rt==0)
local _,deliver=leg(factory,town,1,401)
local back=leg(town,factory,8,308)
assert(back==1)
local B=R.bind(s,{field_board=World.field_board(s)})
assert(B.report(farm,"grain").sources[1]==receipt.farm and B.report(farm,"livestock").sources[1]==receipt.farm)
assert(B.report(factory,"grain").accepts and B.report(factory,"livestock").accepts and
  not B.report(factory,"goods").accepts and B.report(factory,"goods").sources[1]==receipt.factory)
local demand=B.report(town,"goods")
assert(demand.eighths==9 and demand.always_accepted and demand.house_eighths_by_town[1]==3 and demand.house_eighths_by_town[2]==6)
local function actor(cargo,seq,where)
  local def=Rules.trucks[cargo]
  local v={id=100+seq,engine=({grain="grain_truck",livestock="livestock_van",goods="goods_truck"})[cargo],
    owner="A",cargo=cargo,bought=s.day,road_stop_pose=where,batches={},units=0,revenue=0,delivered=0}
  assert(R.supported_vehicle(v) and not R.supported_vehicle({cargo=cargo,engine="truck"}))
  s.fleet[v.id]=v
  return v,def.capacity
end
local vg,cg=actor("grain",1,out[1])
local vl,cl=actor("livestock",2,out[1])
local vd,cd=actor("goods",3,deliver[1])
local clock={cursor=(s.passenger_house_clock and s.passenger_house_clock.cursor) or 1,tick=0}
if not clock.cursor or clock.cursor<=0 then clock.cursor=1 end
local current=0
local ready={}
local function ops(v)
  local options=B.ops(current)
  options.gradual=true
  if v then options.slice=select(1,B.timing(v)) end
  return options
end
local function begin(st,v,cap,flags)
  local l=Loader.begin(st,v,cap,flags,ops(v))
  l.arrived_tick=current
end
local function tick(n)
  for _=1,n do
    current=current+1;clock.tick=current
    Coal.landscape_tick(clock,6,6,function(flat)
      B.tile_visit(flat%64,math.floor(flat/64),current)
    end)
    local o=ops()
    for _,st in ipairs({farm,factory,town}) do
      local _,done=Loader.tick(st,s.fleet,o)
      o.station_done(st)
      for _,vid in ipairs(done) do ready[vid]=st end
    end
    for _,v in pairs(s.fleet) do Loader.age_vehicle(v,1,select(2,B.timing(v))) end
    B.after_vehicle_tick(current)
  end
end
local function leave(v)
  local stop=assert(ready[v.id],"Source vehicle cannot depart at this phase")
  Loader.leave(stop,v,ops());ready[v.id]=nil
end
begin(farm,vg,cg,{full=true})
begin(farm,vl,cl,{full=true})
begin(factory,vd,cd,{full=true})
for _=1,9000 do
  tick(1)
  if ready[vg.id] and ready[vl.id] then break end
end
leave(vg);leave(vl)
assert(vg.units==cg and vl.units==cl and vg.batches[1].origin_tile==out[1][4] and vl.batches[1].origin_tile==out[1][4])
-- The real directed road frames select the position of every pickup and
-- delivery. This isolated service fixture advances with their duration;
-- production init connects the live controller to the same ops.
tick(#out)
vg.road_stop_pose,vl.road_stop_pose=out[#out],out[#out]
begin(factory,vg,cg,{no_load=true})
begin(factory,vl,cl,{no_load=true})
for _=1,9000 do
  tick(1)
  if ready[vg.id] and ready[vl.id] and ready[vd.id] then break end
end
leave(vg);leave(vl);leave(vd)
assert(vg.delivered==cg and vl.delivered==cl and vd.units==cd)
assert(s.sites[receipt.factory_site].received.grain==cg and s.sites[receipt.factory_site].received.livestock==cl)
assert(vd.batches[1].source==receipt.factory and vd.batches[1].origin_tile==deliver[1][4])
tick(#deliver)
vd.road_stop_pose=deliver[#deliver]
begin(town,vd,cd,{no_load=true})
for _=1,250 do
  tick(1)
  if ready[vd.id] then break end
end
leave(vd)
assert(vd.delivered==cd and s.sites[town.town or town.site].received.goods==cd)
assert(not farm.stock.grain and not factory.stock.goods and not s.sites[receipt.factory_site].stock.goods)
assert(Sim.company(s,"A").paid_units==cg+cl+cd and Sim.company(s,"A").revenue==vg.revenue+vl.revenue+vd.revenue)
print(("PASS: seed 1751 %d source fields, actual factory road loop and stock road loader: grain %d/$%d, livestock %d/$%d, Goods %d/$%d"):
  format(crop_count,vg.delivered,vg.revenue,vl.delivered,vl.revenue,vd.delivered,vd.revenue))
