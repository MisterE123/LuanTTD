-- SPDX-License-Identifier: GPL-2.0-only
-- Pure Lua and native SQLite share these exact production/delivery cases.
local module_root=(... and type(...)=="string") and ... or "mods/bayline/"
local function m(n) return dofile(module_root..n..".lua") end
local P,Rate,I=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local Catch=m("openttd/station_catchment")(P,Rate)
local Coal=m("openttd/coal_industry")(P,Rate,Catch,I)
local Timber=m("openttd/timber_industry")(P,Catch,Rate,I,Coal,m("openttd/town_goods"))
local F=m("openttd/farm_factory_industry")(P,Catch,Rate,I,Coal,Timber)
local Fields=m("openttd/farm_factory_fields")(Coal)
local Runtime=m("farm_factory_runtime")(F,Fields,m("timber_industry_runtime"),Catch)
local T={}
local function tile(x,z) return z*64+x end
local function xy(id) return id%64,math.floor(id/64) end
local function order(p)
  local cargo=p.cargo
  return ({grain=F.trucks.grain,livestock=F.trucks.livestock,goods=F.trucks.goods})[cargo]
end

local function field_board(world)
  world.fields=world.fields or {}
  local function at(x,z)
    if x<1 or x>62 or z<1 or z>62 then return {kind="void"} end
    if x>=8 and x<=10 and z>=8 and z<=10 or x>=22 and x<=25 and z>=8 and z<=11 then return {kind="industry"} end
    return world.fields[tile(x,z)] or {kind="clear",ground="grass"}
  end
  return {width=64,height=64,freeform=true,tile=at,make_field=function(x,z,variant,farm,counter)
    world.fields[tile(x,z)]={kind="clear",ground="field",variant=variant,farm=farm,counter=counter,fences={}}
  end,set_fence=function(x,z,side,style) at(x,z).fences[side]=style end}
end
local function bind(w)
  local B=Runtime.bind(w,w.ledger,{industries=w.industries,stations=w.stations,width=64,height=64,xy=xy,
    field_board=field_board(w),
    random_u32=function()
      w.random=(1664525*w.random+1013904223)%4294967296
      return w.random
    end,
    house_at=function(x,z)
      if x==35 and z==10 or x==36 and z==10 then return {id=0,town=7} end
    end,
  })
  return B
end
local function station(id,x,z,mode)
  return {owner="A",id=id,town=7,x=x,z=z,tile=tile(x,z),tiles={{x=x,y=z,kind=mode or "truck"}},stock={}}
end
local function check(w)
  local B=bind(w)
  local farm=w.industries[9]
  assert(farm.produced[1].cargo=="grain" and farm.produced[2].cargo=="livestock")
  assert(#farm.accepted==16 and #farm.produced==16)
  local factory=w.industries[6]
  assert(factory.accepted[1].cargo=="livestock" and factory.accepted[2].cargo=="grain" and factory.accepted[3].cargo=="steel")
  assert(B.report(2,"grain").accepts and B.report(2,"livestock").accepts and B.report(2,"steel").accepts)
  assert(not B.report(2,"goods").accepts and B.report(3,"goods").accepts)
  assert(not B.report(4,"grain").accepts and B.report(4,"grain").raw_eighths>0) -- bus-only
  assert(B.report(1,"passenger").raw_eighths==2) -- farmhouse alone cannot accept a passenger at threshold
  return B
end
local function consume_packet(st,cargo,n,physical)
  local q=st.stock[cargo]
  assert(q and q[1] and q[1].origin_tile==nil and q[1].units>=n)
  local a=q[1]
  if a.units==n then table.remove(q,1) else a=P.split(a,n) end
  P.pickup(a,{id=st.id,tile=physical},xy)
  return a
end
local function lifecycle()
  local draws=0
  local function zero() draws=draws+1;return 0 end
  local f=F.new("farm",10,8,8,{original=false,random_u32=zero,completed=true})
  assert(draws==16+1+9 and F.output(f,"grain").rate==5 and F.output(f,"livestock").rate==5)
  local a=F.new("factory",11,22,8,{economy_year=1950})
  local opt={type_count=1,random_u32=zero}
  assert(F.month(a,1954,opt)==nil)
  assert(F.month(a,1955,opt)==nil and a.prod_level==16) -- last factory protected
  opt.type_count=2
  a.produced[1].current.production=6
  assert(F.month(a,1956,opt)==nil and a.last_prod_year==1956)
  assert(a.produced[1].last.production==6 and a.produced[1].current.production==0)
  assert(F.month(a,1961,opt)=="closure" and a.prod_level==0 and not a.removed)
  assert(F.month(a,1961,opt)=="removed" and a.removed)
  local farm=F.new("farm",12,8,8,{original=true})
  farm.produced[1].current.production=25;farm.produced[1].current.transported=21
  farm.produced[2].current.production=19;farm.produced[2].current.transported=0
  local function no_reversal() return 65535 end
  assert(F.month(farm,1954,{original=true,random_u32=no_reversal})==nil and farm.last_prod_year==1954)
  local seen=0
  local mode=F.change(farm,1954,{original=true,random_u32=function()
    seen=seen+1;return seen==1 and 0 or 65535
  end})
  assert(mode=="rate" and seen==2 and farm.prod_level==32 and
    F.output(farm,"grain").rate==20 and F.output(farm,"livestock").rate==20)
end
function T.save_point()
  lifecycle()
  local w={ledger=Runtime.new(),random=1751,clock={cursor=1,tick=0},industries={
    [9]=F.new("farm",9,8,8,{original=true,generating_world=true,completed=true,counter=1,economy_year=1950}),
    [6]=F.new("factory",6,22,8,{original=true,generating_world=true,completed=true,counter=1,economy_year=1950})},
    stations={station(1,8,11),station(2,22,12),station(3,35,11),station(4,22,10,"bus")}}
  local B=check(w)
  local farm,factory=w.industries[9],w.industries[6]
  assert(B.plant_on_built(farm)>0 and next(w.fields))
  assert(farm.produced[1].last.production==80 and farm.produced[2].last.production==80)
  for _,c in ipairs({"grain","livestock"}) do
    local g=F.goods(w.stations[1],c)
    g.rating,g.last_speed=255,48
  end
  local goods=F.goods(w.stations[2],"goods");goods.rating,goods.last_speed=255,48
  local spots={}
  for _,ind in pairs(w.industries) do for _,t in ipairs(ind.tiles) do spots[tile(t.x,t.z)]=true end end
  -- No externally minted tonnage: only original source producer, two
  -- actual valid slots and the shared original landscape cursor.
  local released
  for tick=1,800 do
    w.clock.tick=tick
    Coal.landscape_tick(w.clock,6,6,function(spot)
      if not spots[spot] then return end
      local x,z=xy(spot)
      local a,_,lots=B.tile_visit(x,z,tick)
      if a>0 then
        assert(#lots==2 and lots[1].cargo=="grain" and lots[2].cargo=="livestock")
        local _,_,why=B.tile_visit(x,z,tick);assert(why=="DUPLICATE_TILE_VISIT")
        released=released or tick
      end
    end)
    local goods,field=B.produce(6,tick),B.produce(9,tick)
    assert(goods==0 and (field==0 or field==20))
    local _,why=B.produce(9,tick);assert(why=="DUPLICATE_OR_STALE_PRODUCTION")
    if released then break end
  end
  assert(released and farm.produced[1].current.production==10 and farm.produced[2].current.production==10)
  w.tick=released+1
  -- Stage two actual truck pulses as one native station pass: per-cargo
  -- slot identity, vehicle-specific five-piece unload and physical fare.
  local grain=consume_packet(w.stations[1],"grain",5,tile(9,11))
  local stock=consume_packet(w.stations[1],"livestock",5,tile(8,11))
  assert(order(grain).load_amount==5 and order(stock).load_amount==5)
  grain.age,stock.age=6,8
  local a=assert(B.stage(2,w.tick,"141:visit2:pulse1:packet1",grain,tile(23,12)))
  assert(a.units==5 and a.distance==15 and a.age==6 and a.payment>0)
  w.grain,w.stock,w.receipt=grain,stock,a
  assert(F.input(factory,"grain").waiting==5 and F.input(factory,"livestock").waiting==0)
  assert(F.output(factory,"goods").waiting==0)
  return w
end
function T.finish(w)
  local B=check(w)
  local factory=w.industries[6]
  local packet=w.grain
  local again,why,receipt=B.stage(2,w.tick,"141:visit2:pulse1:packet1",packet,tile(23,12))
  assert(not again and why=="REPLAYED_DELIVERY" and receipt.payment==w.receipt.payment)
  local wrong=not B.stage(2,w.tick,"141:visit2:pulse1:packet1",packet,tile(24,12))
  assert(wrong)
  assert(not B.finish(2,w.tick+1))
  assert(not B.stage(3,w.tick,"cannot-advance",packet,tile(35,11)))
  local b=assert(B.stage(2,w.tick,"135:visit2:pulse1:packet1",w.stock,tile(22,12)))
  assert(b.units==5 and b.distance==15 and b.age==8 and b.payment>0)
  assert(F.input(factory,"grain").waiting==5 and F.input(factory,"livestock").waiting==5)
  local s=assert(B.finish(2,w.tick))
  assert(#s.deliveries==2 and #s.conversion==1 and s.conversion[1].produced==10 and s.conversion[1].consumed==10)
  assert(F.input(factory,"grain").waiting==0 and F.input(factory,"livestock").waiting==0 and F.input(factory,"steel").waiting==0)
  assert(not B.finish(2,w.tick) and F.output(factory,"goods").waiting==10)
  -- Never release Goods in the same logic pass that consumed the cargo.
  local _,_,late=B.tile_visit(22,8,w.tick);assert(late=="LANDSCAPE_PHASE_CLOSED")
  local n,moved=B.tile_visit(22,8,w.tick+1)
  assert(n==10 and moved==10 and F.output(factory,"goods").waiting==0)
  local goods=consume_packet(w.stations[2],"goods",10,tile(22,12))
  assert(goods.source==6 and goods.source_type=="industry")
  goods.age=4
  local g=assert(B.stage(3,w.tick+1,"138:visit3:pulse2:packet1",goods,tile(35,11)))
  assert(g.units==10 and g.distance==14 and g.town==7 and g.payment>0)
  local done=assert(B.finish(3,w.tick+1))
  assert(#done.conversion==0 and #done.deliveries==1)
  assert(not B.finish(3,w.tick+1) and #w.stations[2].stock.goods==0)
  return s.deliveries[1].payment,s.deliveries[2].payment,g.payment
end

if not ... then
  local function clone(x)
    if type(x)~="table" then return x end
    assert(not getmetatable(x))
    local t={};for k,v in pairs(x) do t[k]=clone(v) end;return t
  end
  local grain,stock,goods=T.finish(clone(T.save_point()))
  print(("PASS: same unload scan 5t grain/$%d + 5 livestock/$%d => 10 stock crates/$%d, no duplication across reload"):
    format(grain,stock,goods))
end
return T
