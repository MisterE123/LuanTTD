-- Exact forest → wood packet → sawmill → goods packet → town lifecycle.
-- Uses the stock shared map cursor, no independent secondary clock.
local r="mods/bayline/"
local function m(n)return dofile(r..n..".lua")end
local P,I,K,H=m("openttd/passengers"),m("openttd/income"),m("openttd/station_rating"),m("openttd/town_passengers")
local A=m("openttd/station_catchment")(P,K)
local Coal=m("openttd/coal_industry")(P,K,A,I)
local Goods=m("openttd/town_goods")
local T=m("openttd/timber_industry")(P,A,K,I,Coal,Goods)
local R=m("timber_industry_runtime")(T,A)
local function copy(v)
  if type(v)~="table" then return v end
  local x={}
  for k,a in pairs(v) do x[k]=copy(a) end
  return x
end
local function id(x,z) return x+z*64 end
local function xy(i)return i%64,math.floor(i/64) end
local world={sites={
  T.new("forest",10,4,4,{completed=true,original=true,counter=1,economy_year=1950}),
  T.new("sawmill",13,16,9,{completed=true,original=true,counter=1,economy_year=1950}),
},stations={
  {id=1,x=7,z=8,tile=id(7,8),town=71,owner="R",tiles={{x=7,y=8,kind="truck"}}},
  {id=2,x=19,z=10,tile=id(19,10),town=72,owner="R",tiles={{x=19,y=10,kind="truck"}}},
  {id=3,x=29,z=10,tile=id(29,10),town=73,owner="R",tiles={{x=29,y=10,kind="truck"}}},
  {id=4,x=29,z=10,tile=id(29,10),town=73,owner="R",tiles={{x=29,y=10,kind="bus"}}},
}}
local ledger,clock=R.new(),H.new_clock(6,6)
local houses={[id(30,10)]={id=0,town=75},[id(31,10)]={id=1,town=75,completed=false}}
local a,b,source,sawmill,town
local function bind()
  a,b=world.sites[1],world.sites[2]
  source,sawmill,town=world.stations[1],world.stations[2],world.stations[3]
  return R.bind(world,ledger,{width=64,height=64,xy=xy,stations=world.stations,
    industries=world.sites,random_u32=function()return 4294967295 end,
    house_at=function(x,z)return houses[id(x,z)] end})
end
local B=bind()
for _,entry in ipairs({{source,"wood"},{sawmill,"goods"}}) do
  local g=T.goods(entry[1],entry[2]);K.observe_loading(g,48,0,20);g.rating=255
end
local function stock_tick()
  local tick=clock.counter+1
  H.advance(clock,1,function(key,t)
    local x,z=xy(key)
    B.tile_visit(x,z,t)
  end)
  for _,ind in ipairs(B.industries) do B.produce(ind.id,tick) end
end
assert(#a.tiles==18 and #b.tiles==8 and b.produced.rate==0)
assert(T.trucks.goods.id==138 and T.trucks.goods.capacity==14 and T.trucks.wood.id==144 and T.trucks.wood.capacity==20)
assert(B.report(2,"wood").accepts and B.report(2,"wood").eighths==8 and not B.report(1,"wood").accepts)
assert(B.report(3,"goods").accepts and B.report(3,"goods").always_accepted and B.report(3,"goods").house_eighths_by_town[75]==8)
assert(not B.report(4,"goods").accepts and B.report(4,"goods").always_accepted) -- raw town masks are independent
houses[id(31,10)]=nil
assert(B.report(3,"goods").eighths==4 and not B.report(3,"goods").accepts)
houses[id(31,10)]={id=1,town=75}
local hole={id=9,x=14,z=8,tiles={{x=14,y=8,kind="truck"}}}
local narrower=T.acceptance(hole,A.build(hole,64,64),"wood",world.sites)
assert(#narrower.near==1 and not narrower.accepts,"Covers only nonaccepting Sawmill geometry")

-- Stock owner-best aggregation and duplicate host station aliases:
-- A shares two eligible facilities; B has one, all equally rated.
local choices,coverage={},{}
for j,mode in ipairs({"truck","rail","truck"}) do
  local st={id=8+j,owner=j<3 and "A" or "B",x=7,z=8,tiles={{x=7,y=8,kind=mode}}}
  local g=T.goods(st,"wood");g.rating=127;K.observe_loading(g,48,0,20)
  choices[j]=st;coverage[st.id]=A.build(st,64,64)
end
choices[4]=choices[1]
assert(T.distribute(a,"wood",16,choices,coverage)==8)
assert(T.queue(choices[1],"wood")[1].units==2 and T.queue(choices[2],"wood")[1].units==2 and
  T.queue(choices[3],"wood")[1].units==4)

-- The natural forest accumulates 13, 26, 39, not station units per day.
for _=1,500 do stock_tick() end
assert(a.produced.waiting==26 and #(T.queue(source,"wood"))==0 and b.produced.waiting==0)
for _=1,250 do
  stock_tick()
  if #T.queue(source,"wood")>0 then break end
end
local wood=T.queue(source,"wood")
assert(#wood==1 and wood[1].units==39 and wood[1].origin_tile==nil)
assert(a.produced.current.production==39 and a.produced.current.transported==39 and b.produced.waiting==0)
local p=P.split(wood[1],20);P.pickup(p,source,xy)
local p2=P.split(p,6);p.age,p2.age=17,18
local tick=clock.counter+1
local f=assert(B.stage(2,tick,"train7/visit15/round1/packet1",p,sawmill.tile))
assert(f.units==14 and f.distance==14 and f.payment==I.regular(14,14,17,5005,15,255))
assert(b.accepted.waiting==14 and b.produced.waiting==0 and not b.was_cargo_delivered)
assert(not B.stage(3,tick,"invalid later station scan",p,town.tile))
assert(select(2,B.produce(13,tick))=="PREVIOUS_STATION_SCAN_PENDING")
local _,__,why=B.tile_visit(b.tiles[1].x,b.tiles[1].z,tick)
assert(why=="PREVIOUS_STATION_SCAN_PENDING")
world,ledger,clock=copy(world),copy(ledger),copy(clock)
B=bind()
assert(select(2,B.stage(2,tick,"train7/visit15/round1/packet1",p,sawmill.tile))=="REPLAYED_DELIVERY")
local altered=copy(p);altered.units=13
assert(select(2,B.stage(2,tick,"train7/visit15/round1/packet1",altered,sawmill.tile))=="DELIVERY_ID_COLLISION")
local g=assert(B.stage(2,tick,"truck11/visit2/round1/packet1",p2,sawmill.tile))
assert(g.units==6 and b.produced.waiting==0 and b.accepted.waiting==20)
local receipt=assert(B.finish(2,tick))
assert(#receipt.deliveries==2 and receipt.conversion[1].consumed==20 and receipt.conversion[1].produced==20)
assert(b.accepted.waiting==0 and b.produced.waiting==20 and b.was_cargo_delivered)
assert(not B.finish(2,tick) and select(2,B.stage(2,tick,"late duplicate",p,sawmill.tile))=="STALE_STATION_SCAN")
assert(select(3,B.tile_visit(b.tiles[1].x,b.tiles[1].z,tick))=="LANDSCAPE_PHASE_CLOSED")
assert(#T.queue(sawmill,"goods")==0,"Goods must not appear in the unload scan or same-tick terrain phase")
B.produce(10,tick);B.produce(13,tick)
assert(select(2,B.produce(13,tick))=="DUPLICATE_OR_STALE_PRODUCTION")
-- The test issued an explicit arrival at next tick (without terrain
-- visits); move the *same* terrain clock one tick, then continue.
H.advance(clock,1,function()end)
for _=1,260 do
  stock_tick()
  if #T.queue(sawmill,"goods")>0 then break end
end
local goods=T.queue(sawmill,"goods")
assert(#goods==1 and goods[1].units==20 and goods[1].source==b.id and goods[1].origin_tile==nil)
local load=P.split(goods[1],14);P.pickup(load,sawmill,xy);load.age=9
tick=clock.counter+1
local paid=assert(B.stage(3,tick,"bus-no/stockgoods138",load,town.tile))
assert(paid.units==14 and paid.remaining==0 and paid.town==73 and paid.distance==10 and paid.age==9)
assert(paid.payment==I.regular(14,10,9,6144,5,28) and #paid.industries==0)
assert(B.finish(3,tick).deliveries[1].payment==paid.payment)
assert(goods[1].units==6 and b.produced.current.transported==20 and b.produced.current.production==20)
world,ledger=copy(world),copy(ledger);B=bind()
assert(not B.finish(3,tick) and not B.stage(3,tick,"bus-no/stockgoods138",load,town.tile))

-- Saturation, ordered distinct real tile batches, editor/closure and
-- rainfall/economy changes are separate from a station's sale.
local sample=T.new("sawmill",50,0,0,{completed=true,original=true,economy_year=1950})
sample.accepted.waiting=7;sample.produced.waiting=65532
local produced,used=T.trigger(sample);assert(produced==3 and used==7 and sample.accepted.waiting==0)
assert(T.trigger(sample)==0)
sample.produced.waiting=5
assert(T.tile_loop(sample,sample.tiles[1],{},function()error("minimum is strict")end)==0)
sample.produced.waiting=6
assert(T.tile_loop(sample,sample.tiles[1],{recession=true},function(_,_,n)assert(n==3);return 0 end)==3)
assert(T.month(sample,1954,{random_u32=function()error("too soon")end})==nil)
sample.produced.current.production=0
assert(T.month(sample,1960,{random_u32=function()return 0 end})=="closure")
assert(T.month(sample,1961)=="removed")
local developmental=T.new("forest",40,1,1,{generating_world=true,original=true})
developmental.produced.waiting=50
assert(T.tile_loop(developmental,developmental.tiles[1],{},function()error("finishing this loop does not ship")end)==0)
assert(developmental.tiles[1].completed and T.tile_loop(developmental,developmental.tiles[1],{},function()return 12 end)==50)
assert(developmental.tiles[1].gfx==17)
T.tile_loop(developmental,developmental.tiles[1],{})
assert(developmental.tiles[1].gfx==16)
print(("forest 39t, sawmill consumes 20t once and offers 20 crates later, town 14 crates/$%d, exact packet save/reload"):format(paid.payment))
