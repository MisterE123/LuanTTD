-- SPDX-License-Identifier: GPL-2.0-only
-- Default-cargo Yate: actual oil from a well is delivered to a refinery
-- by a tanker; the Yate buys its stock hold and carries the refinery's
-- resulting Goods across real water to town. No Goods packets are seeded.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,T,P,R,I=m("sim"),m("openttd/terrain"),m("openttd/passengers"),
  m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,R)
local St=m("station_rating_runtime")(Sim,R,P)
local Coal=m("openttd/coal_industry")(P,R,C,I)
local Timber=m("openttd/timber_industry")(P,C,R,I,Coal,m("openttd/town_goods"))
local Rules=m("openttd/oil_industry")(m("openttd/farm_factory_industry"),P,C,R,I,Coal,Timber)
local Road=m("road_farm_service")(Sim,Rules,m("oil_industry_runtime")(Rules,m("timber_industry_runtime"),C),
  P,I,R,St,{tag="oil",label="Refinery chain",storage="stock_oil_industries",
    vehicles={oil="oil_tanker",goods="goods_truck"},cargo={"oil","goods"}})
local track=m("openttd/rail_track")
local flow=m("openttd/ship_follow")(track)
local network=m("ship_network")(Sim,T,flow,m("openttd/ship_facilities")(track,flow))
local function route(key,roster,engine)
  return m("ship_preview_run")(network,track,flow,m("openttd/ship_yapf")(track,flow,m("openttd/yapf_road_search")),
    m("openttd/ship_motion")(track,flow),m("openttd/ship_regions"),{width=64,height=64,x0=1,z0=1},
    {engine=roster.model(engine),engine_for=roster.model,validate_both=true,key=key,paid=function()return true end})
end
local oil_roster,goods_roster=m("openttd/oil_ship_roster"),m("openttd/ship_roster")
local oil,goods=route("qa_oil",oil_roster,204),route("qa_goods",goods_roster,211)
local Load,Timing=m("road_loading_runtime"),m("openttd/loading_timing")
local Tanker=m("ship_oil_service")(Sim,oil_roster,P,R,Load,Timing)
local Dry=m("ship_goods_service")(Sim,goods_roster,P,R,Load,Timing)
local H=m("openttd/town_passengers")
local s=Sim.new(1751)
s.road_stock_house_supply=true
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=T.new(64,64,function(_,z) return z<33 and 1 or 0 end)
for z=1,64 do for x=1,64 do
  s.tiles[Sim.id(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
    water_class=z>=33 and "sea" or nil}
end end
local tanker_owner,goods_owner="Oil Carrier","Yate Shipping"
local W=m("oil_industry_world")(Sim,T,Rules)
assert(W.place(s,assert(W.plan(s,12,28,31,28))))
local citytile=Sim.id(51,28)
s.sites[1]={id=1,kind="town",name="Port Town",population=400,tile=citytile}
s.tiles[citytile].house=true
s.tiles[citytile].source_house={id=18,town=1}
local function build(owner,k,x,z)
  return assert(network.build(s,owner,k,Sim.id(x,z),k=="depot" and 0 or nil)).id
end
local oa,ob,od=build(tanker_owner,"dock",12,32),build(tanker_owner,"dock",31,32),build(tanker_owner,"depot",17,35)
local ga,gb,gd=build(goods_owner,"dock",34,32),build(goods_owner,"dock",51,32),build(goods_owner,"depot",43,35)
assert(oil.start(s,tanker_owner,od,oa,ob,nil,204))
assert(goods.start(s,goods_owner,gd,ga,gb,nil,211))
local oil_price=assert(oil_roster.quote(204)).price
local buy=assert(goods_roster.quote(goods_roster.default_cargo))
local tc,gc=Sim.company(s,tanker_owner),Sim.company(s,goods_owner)
tc.cash,gc.cash=tc.cash-oil_price,gc.cash-buy.purchase
assert(buy.capacity==160 and buy.refit==0)
s.qa_tanker=Tanker.new({id="oil",engine=204,built=1950,owner=tanker_owner})
s.qa_yate=Dry.new({id="dry",engine=211,built=1950,owner=goods_owner})
s.qa_clock=H.new_clock(6,6)
local function copy(t,seen)
  if type(t)~="table" then return t end
  seen=seen or {};if seen[t] then return seen[t] end
  local result={};seen[t]=result
  for k,v in pairs(t) do result[k]=copy(v,seen) end
  return result
end
local A,B,pipe
local function remount()
  local map=network.board(s)
  local list,ports=Tanker.bind_stations(s,s.qa_tanker,map,function(k)return k==oa or k==ob end)
  local docks,dry=Dry.bind_stations(s,s.qa_yate,map,function(k)return k==ga or k==gb end)
  assert(#list==2 and #docks==2 and docks[1].id~=list[1].id)
  for _,p in ipairs(docks) do list[#list+1]=p end
  pipe=Road.bind(s,{ship_stations=list})
  local function debit(who,fixed)
    local c=Sim.company(s,who)
    local old=c.stock_money_fraction or 0
    local rem=(old-fixed%256)%256
    c.stock_money_fraction=rem
    local n=math.floor(fixed/256)+(rem>old and 1 or 0)
    c.cash,c.expense=c.cash-n,c.expense+n
  end
  A=Tanker.bind(s.qa_tanker,pipe,s.qa_tanker.stations,ports,map,{charge_fixed=debit})
  B=Dry.bind(s.qa_yate,pipe,s.qa_yate.stations,dry,map,{charge_fixed=debit})
  assert(#A.report(oa).sources==1 and A.report(ob).accepts)
  assert(#B.report(ga).sources==1 and not B.report(ga).accepts)
  assert(#B.report(gb).sources==0 and B.report(gb).accepts)
  assert(not B.report(oa) and not A.report(ga))
end
remount()
local function step(service,run,tick,source)
  assert(service.loading(tick))
  run.advance_paid(s,{
    arrive=function(p)
      assert(p.last_berth~=s.stock_ship_stations[p.last_dock].water)
      return service.arrive(p.last_dock,p.arrivals,tick,p.last_berth,p.last_dock==source and "full" or "no_load")
    end,
    leave=function(p,force) return service.leave(p.arrivals,tick,force) end,
  })
  assert(not run.current(s).failure,run.current(s).failure)
  assert(service.after(tick));service.rating(tick)
end
local restored=false
for _=1,1200 do
  s.day=s.day+1
  A.settle(s.day);B.settle(s.day)
  local visits=0
  H.advance(s.qa_clock,74,function(tile,tick)
    pipe.tile_visit(tile%64,math.floor(tile/64),tick)
    visits=(visits+1)%16
    if visits==0 then
      step(A,oil,tick,oa);step(B,goods,tick,ga)
      pipe.after_vehicle_tick(tick)
    end
  end)
  local v=s.qa_yate.vehicle
  if not restored and v.load_state and v.units>0 and v.units<buy.capacity then
    local before=v.units
    s=copy(s);remount();restored=true
    assert(s.qa_yate.vehicle.units==before and s.qa_yate.vehicle.load_state.slice==10)
  end
  if v.delivered>=buy.capacity then
    local c=Sim.company(s,goods_owner)
    local refinery=s.stock_oil_industries[W.BASE+1]
    assert(restored and refinery.received.oil>0 and s.qa_tanker.vehicle.delivered>0)
    assert(v.delivered==buy.capacity and v.revenue>0 and v.running_fixed>0)
    assert(c.cash==100000-buy.purchase+c.revenue-c.expense and c.paid_units==v.delivered and c.revenue==v.revenue)
    print(("PASS stock Yate default Goods: real refinery output, exact berth, partial restart, %d crates / $%d"):format(v.delivered,v.revenue))
    return
  end
end
error("Yate didn't complete the Goods voyage")
