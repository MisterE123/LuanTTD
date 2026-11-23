local root="mods/luanttd_core/openttd/"
local function m(s) return dofile(root..s..".lua") end
local Packets,Rating,Income=m("passengers"),m("station_rating"),m("income")
local Catchment=m("station_catchment")(Packets,Rating)
local Coal=m("coal_industry")(Packets,Rating,Catchment,Income)
local Timber=m("timber_industry")(Packets,Catchment,Rating,Income,Coal,m("town_goods"))
local F=m("farm_factory_industry")(Packets,Catchment,Rating,Income,Coal,Timber)
local Data=m("temperate_bank_data")
local Rules=m("temperate_bank_rules")(F,Data)
assert(Data.spec.generation[1]==0 and Data.spec.appearance[1]==7)
assert(F.cost("temperate_bank",1)==996093)
local one={house=true,clearable=true,slope=0}
assert(not Rules.site({population=1199},one,one))
assert(not Rules.site({population=1200},one,{clearable=true,slope=0}))
assert(not Rules.site({population=1200},one,{house=true,clearable=false,slope=0}))
assert(Rules.site({population=1200},one,one))
for slope=0,31 do
  local east=slope>=16 or not (slope==0 or slope==3 or slope==7 or slope==11 or slope==15)
  local south=slope>=16 or not (slope==0 or slope==12 or slope==13 or slope==14 or slope==15)
  assert(Rules.refuses(slope,4)==east and Rules.refuses(slope,2)==south)
end
assert(F.tile_acceptance(58,"valuables")==8 and F.tile_acceptance(59,"passenger")==1)
assert(F.tile_acceptance(89,"valuables")==0)
local src=F.new("temperate_bank",100,4,4,{counter=1,completed=true,economy_year=1950})
local dst=F.new("temperate_bank",101,20,4,{counter=200,completed=true,economy_year=1950})
local unload={id=2,owner="Bank QA",tile=6*32+20,x=20,z=6,tiles={{x=20,y=6,kind="truck"}}}
local pickup={id=1,owner="Bank QA",tile=6*32+4,x=4,z=6,tiles={{x=4,y=6,kind="truck"}}}
local covers={[1]=Catchment.build(pickup,32,32),[2]=Catchment.build(unload,32,32)}
local function report(st)
  return F.acceptance(st,covers[st.id],"valuables",{src,dst})
end
assert(report(pickup).eighths==16 and report(unload).eighths==16)
Rating.observe_loading(F.goods(pickup,"valuables"),48,1,12)
src.produced[1].waiting=5
assert(F.tile_loop(src,src.tiles[1],{})==0)
src.produced[1].waiting=0
assert(F.production_tick(src,{})==6)
local n,moved=F.tile_loop(src,src.tiles[1],{},function(i,cargo,n)
  return F.distribute(i,cargo,n,{pickup,unload},covers,{select_goods=true})
end)
assert(n==6 and moved>0)
local p=assert(table.remove(F.queue(pickup,"valuables"),1))
local function xy(id) return id%32,math.floor(id/32) end
local function industry(id) return id==100 and src or id==101 and dst end
Packets.pickup(p,pickup,xy)
assert(F.deliver(pickup,report(pickup),p,industry,{cargo_tile=pickup.tile,xy=xy}).units==0)
local value=F.deliver(unload,report(unload),p,industry,{cargo_tile=unload.tile,xy=xy})
assert(value.units==moved and value.payment>0 and dst.accepted[1].waiting==moved)
local produced,accepted=F.trigger(dst)
assert(produced==0 and accepted==moved and dst.produced[1].waiting==0 and dst.accepted[1].waiting==0 and dst.was_cargo_delivered)
for y=1950,2040 do
  assert(not F.month(dst,y,{original=false,random_u32=function() error("A stock Bank must not run random production decay") end}))
  assert(dst.produced[1].rate==6 and not dst.removed)
end
print("PASS pinned stock Bank siting and complementary slopes; real paid Valuables, no same-bank delivery or recycled production")
