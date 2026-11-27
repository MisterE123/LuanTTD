-- SPDX-License-Identifier: GPL-2.0-only
-- Opening stock Yate in the ordinary worker controls, not a pilot.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local Endpoint,compose=m("campaign_authority_endpoint"),m("campaign_authority_runtime")
local tanker,yate="Oil Carrier","Yate Shipping"
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=Terrain.new(64,64,function(_,z)return z<33 and 1 or 0 end)
for z=1,64 do for x=1,64 do
  s.tiles[Sim.id(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
    water_class=z>=33 and "sea" or nil}
end end
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
s.ship_paid_service,s.ship_coal_service,s.road_oil=true,true,true
local W=assert(Sim.mount_oil_world(s,Terrain,true))
assert(W.place(s,assert(W.plan(s,12,28,31,28))))
local city=Sim.id(51,28)
s.sites[1]={id=1,kind="town",name="Port Town",population=400,tile=city,stock={},produced={},received={},service=0}
s.tiles[city].house,s.tiles[city].source_house=true,{id=18,town=1}
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0},
  ferry={[204]=true,[211]=true,[212]=true},air={},oil_tanker=true}
local A,rt
local function mount()
  rt=compose(Sim,root:sub(1,-2),s,cap)
  A=Endpoint(Sim,rt)
end
mount()
Sim.company(s,tanker);Sim.company(s,yate)
local function commit(who,req)
  local q=A.transport_quote(who,req)
  assert(q.ok,q.why)
  local r=A.command(who,{kind="transport_commit",token=q.value.token,revision=q.revision})
  assert(r.ok,r.why)
  return r.value,q.value.price
end
local function build(who,k,x,z)
  local at=Sim.id(x,z)
  local p=commit(who,{mode="ship",operation="build",kind=k,tile=at,axis=k=="depot" and 0 or nil})
  return p.id,at
end
local oa,ot=build(tanker,"dock",12,32)
local ob,ou=build(tanker,"dock",31,32)
local od=build(tanker,"depot",17,35)
local ga,gt=build(yate,"dock",34,32)
local gb,gu=build(yate,"dock",51,32)
local gd=build(yate,"depot",43,35)
local expense=s.companies[yate].expense
local function buy(who,dep,engine,price)
  local offer
  for _,o in ipairs(assert(rt.transport.depot(who,"ship",dep)).offers) do if o.request.engine==engine then offer=o;break end end
  assert(offer and offer.price==price)
  local unit=commit(who,offer.request)
  return unit.id,offer
end
local oil_id=buy(tanker,od,204,40625)
local id,offer=buy(yate,gd,211,32500)
assert(id=="coal" and s.stock_coal_ship.cargo==5 and s.stock_coal_ship.refit==0)
assert(offer.help.service:find("Goods",1,true) and not offer.help.connections:find("refit",1,true))
assert(not A.transport_quote(yate,{mode="ship",operation="refit",depot=gd,cargo="oil"}).ok)
local q=assert(rt.transport.depot(yate,"ship",gd))
local unit=assert(q.vehicles[1])
assert(unit.cargo=="goods")
local route=m("initial_vehicle_route")
local from,to=route.targets("ship",q,unit)
assert(route.find(from,ga) and route.find(to,gb))
assert(not route.find(from,oa) and not route.find(to,ob))
assert(not route.find(from,gb) and not route.find(to,ga))
local function start(who,id_,cargo,dep,a,b,t,u)
  return A.command(who,{kind="transport_start",mode="ship",vehicle=id_,cargo=cargo,depot=dep,
    first=a,second=b,first_tile=t,second_tile=u,revision=s.authority_revision})
end
local bad=start(yate,id,"goods",gd,ga,gb,ot,gu);assert(not bad.ok)
local old=start(yate,id,"coal",gd,ga,gb,gt,gu);assert(not old.ok)
local main=start(yate,id,"goods",gd,ga,gb,gt,gu);assert(main.ok,main.why)
local oil=start(tanker,oil_id,"oil",od,oa,ob,ot,ou);assert(oil.ok,oil.why)
local ord=assert(rt.orders.ship.read(yate,id))
assert(#ord.items==2 and ord.items[1].label:find("Goods",1,true) and ord.items[2].label:find("town",1,true))
assert(rt.company_fleet.vehicle(yate,"ship",id).label=="Yate Cargo Ship")
assert(not rt.orders.ship.read(tanker,id))
local saved,located
local interest=0
for _=1,1200 do
  rt.day()
  if select(3,Sim.date(s))==1 then interest=interest+200 end
  local v=rt.water.coal.status(s)
  assert(not v.failure,v.failure)
  if not located and v.phase=="sailing" then
    assert(type(assert(rt.company_fleet.locate(yate,"ship",id)).x)=="number")
    located=true
  end
  if not saved and v.loading and v.onboard>0 and v.onboard<160 then
    local pack=m("packed_campaign")
    s=assert(pack.decode(assert(pack.encode(s))));mount()
    assert(rt.water.coal.status(s).onboard==v.onboard and s.stock_goods_ship_service.vehicle.load_state.slice==10)
    saved=true
  end
  if v.delivered==160 then
    local c=s.companies[yate]
    assert(saved and located and v.fare>0 and v.running_expense>0)
    assert(c.revenue==v.fare and c.paid_units==v.delivered and c.cash==100000+c.revenue-c.expense)
    assert(c.expense==expense+32500+v.running_expense+interest, ("expense=%s before=%s running=%s"):format(c.expense,expense,v.running_expense))
    assert(s.stock_oil_ship_service.vehicle.delivered>0 and s.sites[1].received.goods==160)
    print(("PASS ordinary Yate Goods: depot, in-world selection, 160 crates/$%d, packed partial load and authoritative debit"):format(v.fare))
    return
  end
end
error("Ordinary Goods Yate never delivered")
