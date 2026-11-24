-- Fixed-slot stock iron producer, standard 1:1 steel trigger and the
-- existing ordinary Factory Goods queue, with real catchments/payments.
local root="mods/luanttd_core/"
local function m(s) return dofile(root..s..".lua") end
local P,R,I=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,R)
local Coal=m("openttd/coal_industry")(P,R,C,I)
local Timber=m("openttd/timber_industry")(P,C,R,I,Coal,m("openttd/town_goods"))
local F=m("openttd/iron_steel_rules")(m("openttd/farm_factory_industry")(P,C,R,I,Coal,Timber),m("openttd/iron_steel_data"))
local mine=F.new("iron_mine",18,4,3,{completed=true,counter=1,economy_year=1950})
local mill=F.new("steel_mill",8,20,3,{completed=true,economy_year=1950})
local plant=F.new("factory",6,35,3,{completed=true,economy_year=1950})
assert(#mine.tiles==16 and #mill.tiles==12 and #F.layout.steel_mill[1]==14)
assert(F.cost("iron_mine",1)==6875000 and F.cost("steel_mill",0)==839843)
assert(F.tile_acceptance(52,"iron_ore")==8 and F.tile_acceptance(105,"iron_ore")==0)
local st1={id=1,owner="Industry",tile=5*64+7,x=7,z=5,tiles={{x=7,y=5,kind="truck"}}}
local st2={id=2,owner="Industry",tile=5*64+20,x=20,z=5,tiles={{x=20,y=5,kind="truck"}}}
local st3={id=3,owner="Industry",tile=5*64+35,x=35,z=5,tiles={{x=35,y=5,kind="truck"}}}
local st={st1,st2,st3}
local cover={}
for _,v in ipairs(st) do cover[v.id]=C.build(v,64,64) end
R.observe_loading(F.goods(st1,"iron_ore"),48,1,22)
R.observe_loading(F.goods(st2,"steel"),48,1,15)
local all={mine,mill,plant}
local report_mill=F.acceptance(st2,cover[2],"iron_ore",all)
local report_factory=F.acceptance(st3,cover[3],"steel",all)
assert(report_mill.accepts and report_factory.accepts and not F.acceptance(st1,cover[1],"iron_ore",all).accepts)
local function from(i,c,n) return F.distribute(i,c,n,st,cover,{select_goods=true}) end
local function xy(id)return id%64,math.floor(id/64) end
local function by_id(id) return id==mine.id and mine or id==mill.id and mill or id==plant.id and plant end
assert(F.production_tick(mine,{})==10 and mine.produced[1].waiting==10)
local original,moved=F.tile_loop(mine,mine.tiles[1],{},from)
assert(original==10 and moved>0 and mine.produced[1].waiting==0 and #F.queue(st1,"iron_ore")==1)
local p=assert(table.remove(F.queue(st1,"iron_ore"),1))
P.pickup(p,st1,xy)
local ore=F.deliver(st2,report_mill,p,by_id,{cargo_tile=st2.tile,xy=xy})
assert(ore.units==moved and ore.payment>0 and mill.accepted[1].waiting==moved and #ore.industries==1)
local yield,spent=F.trigger(mill)
assert(yield==moved and spent==moved and mill.produced[1].waiting==moved and mill.accepted[1].waiting==0)
-- The source tile loop only offers lots strictly greater than minimum 5.
-- A second independent ore visit grows the same steel stockpile.
if yield<=5 then
  assert(F.tile_loop(mill,mill.tiles[1],{},from)==0)
  for _=1,256 do F.production_tick(mine,{}) end
  F.tile_loop(mine,mine.tiles[2],{},from)
  local again=assert(table.remove(F.queue(st1,"iron_ore"),1))
  P.pickup(again,st1,xy)
  assert(F.deliver(st2,report_mill,again,by_id,{cargo_tile=st2.tile,xy=xy}).units>0)
  yield=yield+F.trigger(mill)
end
local written,forwarded=F.tile_loop(mill,mill.tiles[1],{},from)
assert(written==yield and forwarded>0 and mill.produced[1].waiting==0)
local sm=assert(table.remove(F.queue(st2,"steel"),1))
P.pickup(sm,st2,xy)
local sold=F.deliver(st3,report_factory,sm,by_id,{cargo_tile=st3.tile,xy=xy})
assert(sold.units==forwarded and sold.payment>0)
assert(plant.accepted[3].waiting==sold.units and F.trigger(plant)==sold.units and plant.produced[1].waiting==sold.units)
print("PASS RC1 stock Iron Ore -> Steel Mill -> existing Factory Goods receipt, no inserted cargo")

-- Reject partial or forged footprints before touching the map, and keep
-- the stock RNG/last-production fields on a successful native install.
local Sim,T=m("sim"),m("openttd/terrain")
local W=m("iron_steel_world")(Sim,T,F)
local world=Sim.new(1751)
world.corner_grid=T.new(Sim.W,Sim.H,function()return 1 end)
for id in ipairs(world.tiles) do world.tiles[id]={h=1,terrain="grass",variant=1} end
world.sites={}
local function at(x,z)return Sim.id(x,z) end
local pos=at(8,8)
local forge=F.new("iron_mine",0,7,7,{completed=true,counter=9})
forge.tiles[16].gfx=104
local bad,why=W.place_generated(world,"iron_mine",pos,{record=forge,name="Forge"})
assert(not bad and why=="HEAVY_INDUSTRY_FOOTPRINT_MISMATCH")
assert(not world.stock_heavy_industries and not world.tiles[pos].stock_industry and not world.tiles[at(11,11)].stock_industry)
local a=F.new("iron_mine",0,7,7,{completed=true,counter=9})
local original=a.produced[1].last.production
local i,cells,st=W.place_generated(world,"iron_mine",pos,{record=a,name="North Rail Iron Ore Mine"})
assert(i==a and i.id==W.BASE and i.counter==9 and i.produced[1].last.production==original)
assert(#cells==16 and st.stock_industry==i.id and world.tiles[at(11,11)].stock_industry.gfx==115)
local b=F.new("steel_mill",0,21,7,{completed=true,counter=16})
local j,tiles=W.place_generated(world,"steel_mill",at(22,8),{record=b,name="North Rail Steel Mill"})
assert(j==b and j.id==W.BASE+1 and #tiles==12 and world.tiles[at(24,9)].stock_industry.gfx==52)
assert(W.visual_sources().industry_iron_mine and #W.visual_sources().industry_steel_mill==12)
local alt=F.new("steel_mill",0,11,19,{completed=true,counter=17,layout=1})
local item,foot=W.place_generated(world,"steel_mill",at(12,20),{record=alt,name="North Rail alternate Mill"})
assert(item==alt and item.layout==1 and #foot==14 and #W.visual_sources().industry_steel_mill_l1==14)
assert(world.tiles[at(14,20)].stock_industry.gfx==52 and world.tiles[at(14,20)].stock_industry.style=="industry_steel_mill_l1")
assert(world.tiles[at(13,23)].stock_industry.gfx==56 and world.tiles[at(14,23)].stock_industry.gfx==57)
assert(not world.tiles[at(12,23)].stock_industry and not world.tiles[at(15,23)].stock_industry)
print("PASS exact native heavy-industry footprint placement with atomic failure and original source state")
