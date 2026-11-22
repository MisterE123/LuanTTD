-- SPDX-License-Identifier: GPL-2.0-only
-- Isolated source landscape and station ledger, runnable in Lua and
-- in two native Luanti processes across a SQLite snapshot.
local prefix=(... and type(...)=="string") and ... or "mods/bayline/"
local function m(n) return dofile(prefix..n..".lua") end
local P,Rating,Income=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,Rating)
local Coal=m("openttd/coal_industry")(P,Rating,C,Income)
local Timber=m("openttd/timber_industry")(P,C,Rating,Income,Coal,m("openttd/town_goods"))
local Farm=m("openttd/farm_factory_industry")
local O=m("openttd/oil_industry")(Farm,P,C,Rating,Income,Coal,Timber)
local Runtime=m("oil_industry_runtime")(O,m("timber_industry_runtime"),C)
local T={}
local function id(x,z) return z*64+x end
local function xy(i) return i%64,math.floor(i/64) end
local function persist(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local t={};for k,v in pairs(x) do t[k]=persist(v) end;return t
end
local function st(i,x,z,role)
  return {id=i,owner="A",town=8,x=x,z=z,tile=id(x,z),tiles={{x=x,y=z,kind=role or "truck"}},stock={}}
end
local function bind(w)
  return Runtime.bind(w,w.ledger,{
    width=64,height=64,xy=xy,stations=w.stations,industries=w.industries,
    house_at=function(x,z)
      if z==9 and (x==38 or x==39) then return {id=0,town=8} end
    end,
    random_u32=function()
      w.rng=(1664525*w.rng+1013904223)%4294967296
      w.draws=w.draws+1
      return w.rng
    end,
    animated=function(_,tile,on) w.animations[id(tile.x,tile.z)]=on end,
  })
end
local function lifecycle()
  local function no_rng() error("Stock original temperate oil decline must not draw") end
  local a=O.new("oil_well",1,2,3,{economy_year=1950})
  assert(O.appearance("oil_well","mapgen",{year=1970})==4 and O.appearance("oil_well","random",{year=1950})==0)
  assert(O.appearance("oil_refinery","random",{year=1970})==2)
  assert(O.conflicts("oil_well","oil_refinery",14,4) and not O.conflicts("oil_refinery","oil_well",14,4))
  assert(O.cost("oil_well",1)==6875000 and O.cost("oil_refinery",1)==953125)
  assert(O.refinery_edge(30,60,256,256) and not O.refinery_edge(31,60,256,256))
  assert(O.refinery_edge(31,60,256,256,{freeform=true}) and O.refinery_edge(63,60,256,256,{editor=true}))
  assert(O.refinery_edge(62,120,512,256) and not O.refinery_edge(63,120,512,256))
  assert(O.slope_allowed(20,0) and not O.slope_allowed(20,1) and not O.slope_allowed(29,16))
  assert(O.change(a,1951,{original=true,random_u32=no_rng})=="rate" and a.produced[1].rate==6 and a.prod_level==8)
  assert(O.change(a,1952,{original=true,random_u32=no_rng})=="rate" and a.produced[1].rate==3 and a.prod_level==4)
  assert(not O.change(a,1953,{original=true,no_decrease=true,random_u32=no_rng}))
  assert(O.change(a,1953,{original=true,type_count=1,random_u32=no_rng})=="closure")
  assert(O.month(a,1953,{original=true,random_u32=no_rng})=="removed" and a.removed)
  local b=O.new("oil_refinery",2,5,7,{economy_year=1950})
  local function zero() return 0 end
  assert(not O.month(b,1954,{type_count=2,random_u32=no_rng}))
  assert(not O.month(b,1955,{type_count=1,random_u32=zero}))
  assert(O.month(b,1955,{type_count=2,random_u32=zero})=="closure")
end
local function begin(w,B)
  local a,b,c,d=w.stations[1],w.stations[2],w.stations[3],w.stations[4]
  assert(O.trucks.oil.id==132 and O.trucks.oil.capacity==21 and O.cargo.oil.id==3 and O.cargo.oil.payment==4437)
  assert(not B.report(a.id,"oil").accepts and B.report(b.id,"oil").accepts and not B.report(b.id,"goods").accepts)
  assert(B.report(c.id,"goods").accepts and B.report(c.id,"goods").always_accepted)
  assert(B.report(d.id,"oil").raw_eighths==0 and not B.report(d.id,"oil").accepts)
end
local function pickup(st,cargo,units,tile)
  local q=st.stock[cargo]
  assert(q and q[1] and q[1].units>=units and q[1].origin_tile==nil)
  local p=q[1]
  if p.units==units then table.remove(q,1) else p=P.split(p,units) end
  P.pickup(p,{id=st.id,tile=tile},xy)
  return p
end
function T.create()
  lifecycle()
  local w={rng=1751,draws=0,ledger=Runtime.new(),clock={cursor=1,tick=0},animations={},industries={
      [11]=O.new("oil_well",11,8,8,{original=true,completed=true,generating_world=true,counter=1,economy_year=1950}),
      [4]=O.new("oil_refinery",4,25,8,{original=true,completed=true,generating_world=true,counter=1,economy_year=1950})},
    stations={st(1,8,11),st(2,24,9),st(3,38,9),st(4,31,11)}}
  local B=bind(w)
  begin(w,B)
  O.goods(w.stations[1],"oil").rating=255;O.goods(w.stations[1],"oil").last_speed=48
  O.goods(w.stations[2],"goods").rating=255;O.goods(w.stations[2],"goods").last_speed=48
  local well,refinery=w.industries[11],w.industries[4]
  assert(well.produced[1].last.production==96 and refinery.produced[1].rate==0)
  local spot={}
  for _,ind in pairs(w.industries) do for _,p in ipairs(ind.tiles) do spot[id(p.x,p.z)]=true end end
  local visit
  for tick=1,1000 do
    w.clock.tick=tick
    Coal.landscape_tick(w.clock,6,6,function(i)
      if not spot[i] then return end
      local x,z=xy(i)
      local produced,moved=B.tile_visit(x,z,tick)
      if produced>0 then
        assert(moved==12 and produced==12)
        visit=tick
        local _,_,why=B.tile_visit(x,z,tick);assert(why=="DUPLICATE_TILE_VISIT")
      end
    end)
    B.produce(4,tick);B.produce(11,tick)
    if visit and w.stations[1].stock.oil and w.stations[1].stock.oil[1].units>=21 then break end
  end
  assert(visit and well.produced[1].current.production==24)
  local p=pickup(w.stations[1],"oil",21,id(9,11))
  p.age=26
  local cargo_first=P.split(p,5)
  local r=assert(B.stage(2,visit+1,"132:2:1",cargo_first,id(24,9)))
  assert(r.units==5 and r.distance==17 and r.age==26 and r.payment>0)
  assert(refinery.accepted[1].waiting==5 and refinery.produced[1].waiting==0)
  w.tick,w.pending,w.onboard,w.initial=visit+1,cargo_first,p,r.payment
  return w
end
function T.finish(w)
  local B=bind(w)
  begin(w,B)
  local refinery=w.industries[4]
  local _,reason,old=B.stage(2,w.tick,"132:2:1",w.pending,id(24,9))
  assert(reason=="REPLAYED_DELIVERY" and old.payment==w.initial)
  local oil_paid=w.initial
  local loaded=5
  local function deliver(p,i,tick)
    local r=assert(B.stage(2,tick,"132:2:"..i,p,id(24,9)))
    assert(r.units==p.units and p.units<=5 and r.age>=26 and r.payment>0)
    oil_paid,loaded=oil_paid+r.payment,loaded+r.units
  end
  -- This fixture saves within one station scan, then completes it.
  -- The rest of the actual tanker cargo releases one true 5-unit
  -- slice every ordinary 20 station ticks, capped by remaining stock.
  local first=B.finish(2,w.tick)
  assert(first.conversion[1].produced==5 and first.conversion[1].consumed==5)
  local t=w.tick+1
  assert(B.tile_visit(25,8,t)==0,"Five units must remain below the source threshold")
  local seq=1
  while w.onboard.units>0 do
    seq,t=seq+1,t+20
    local n=math.min(5,w.onboard.units)
    local p
    if w.onboard.units>n then p=P.split(w.onboard,n) else p=w.onboard;w.onboard={units=0} end
    deliver(p,seq,t)
    local receipt=assert(B.finish(2,t))
    assert(receipt.conversion[1].produced==n and receipt.conversion[1].consumed==n)
    assert(not B.finish(2,t))
  end
  assert(loaded==21 and refinery.produced[1].waiting==21 and refinery.accepted[1].waiting==0)
  local lot,moved=B.tile_visit(25,8,t+1);assert(lot==21 and moved==21 and refinery.produced[1].waiting==0)
  local goods=pickup(w.stations[2],"goods",14,id(24,9))
  goods.age=3
  local a=assert(B.stage(3,t+2,"138:3:1",goods,id(38,9)))
  assert(a.units==14 and a.distance==14 and a.town==8 and a.payment>0)
  local final=assert(B.finish(3,t+2))
  assert(#final.conversion==0 and #final.deliveries==1)
  assert(not B.finish(3,t+2) and w.stations[2].stock.goods[1].units==7)
  assert(refinery.was_cargo_delivered and refinery.produced[1].current.production==21)
  assert(oil_paid==189 and a.payment==146)
  return oil_paid,a.payment
end
function T.threshold()
  local w=T.create()
  local B=bind(w)
  assert(B.finish(2,w.tick))
  local t=w.tick+1
  assert(B.tile_visit(25,8,t)==0 and w.industries[4].produced[1].waiting==5)
  assert(not w.stations[2].stock.goods)
  w=persist(w);B=bind(w) -- Rebind the actual split-scan saved schema.
  local part=P.split(w.onboard,1)
  assert(B.stage(2,t+1,"sixth-unit",part,id(24,9)))
  assert(B.finish(2,t+1))
  local lot,moved=B.tile_visit(25,8,t+2)
  assert(lot==6 and moved==6 and w.stations[2].stock.goods[1].units==6)
  assert(w.industries[4].produced[1].waiting==0)
  local _,_,repeat_visit=B.tile_visit(25,8,t+2);assert(repeat_visit=="DUPLICATE_TILE_VISIT")
  -- The same station scan can unload a fleet without inventing a
  -- 315-unit road tanker. Fifteen original loads enter one batch.
  for i=1,15 do
    local cargo=persist(w.pending);cargo.units=21
    assert(B.stage(2,t+3,"test-vehicle-"..i,cargo,id(24,9)))
  end
  assert(B.finish(2,t+3))
  lot,moved=B.tile_visit(25,8,t+4)
  assert(lot==255 and moved==255 and w.industries[4].produced[1].waiting==60)
  print("PASS: refinery waits at 5, releases 6 after reload, and caps a real multi-tanker scan release at 255")
end
if not ... then
  T.threshold()
  local oil,goods=T.finish(persist(T.create()))
  print(("PASS: source wells/refinery, 21 Oil/$%d -> 21 crates; 14 Goods/$%d delivered, no replay duplication"):format(oil,goods))
end
return T
