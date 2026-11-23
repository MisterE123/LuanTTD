local root="mods/luanttd_core/"
local function m(s)return dofile(root..s..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local G=m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
local growth=m("town_growth_runtime")(Sim,Terrain,G,Build,m("openttd/town_passengers"))
local s=Sim.new(1)
Sim.W,Sim.H=64,64
s.tiles={};for id=1,64^2 do s.tiles[id]={h=1,terrain="grass"} end
s.corner_grid=Terrain.new(64,64,function()return 1 end)
s.sites={{id=1,kind="town",name="Stationfield",tile=Sim.id(7,8),population=1400},
 {id=2,kind="town",name="Banktown",tile=Sim.id(32,8),population=1500}}
s.stock_town_growth={towns={
  [1]={population=1400,num_houses=2,house_counts={[0x06]=2}},
  [2]={population=1500,num_houses=2,house_counts={[0x06]=2}}}}
local function house(x,z,town)
  local t=s.tiles[Sim.id(x,z)]
  t.house=true;t.source_house={id=0x06,town=town,town_growth=true,root=true,completed=true}
end
house(8,8,1);house(9,8,1);house(33,8,2);house(34,8,2)
local farm,_,F=Sim.mount_farm_world(s,Terrain,true)
assert(farm)
local R=m("openttd/temperate_bank_rules")(F,m("openttd/temperate_bank_data"))
local W=m("temperate_bank_world")(Sim,Terrain,F,R,growth,function(c,cost)
  c.cash=c.cash-cost;c.expense=c.expense+cost
end,function()return 16 end)
local c=Sim.company(s,"Company")
c.rating[1]=20
local p=Sim.id(8,8)
local q=assert(W.plan(s,p))
assert(q.price==996093 and #q.clears==2 and #q.pair==2)
local n,e=W.execute(s,"Company",p,q);assert(not n and e=="BANK_NOT_ENOUGH_CASH")
assert(not s.stock_bank_industries and s.tiles[p].house)
c.cash=2000000
s.topology=s.topology+1
n,e=W.execute(s,"Company",p,q);assert(not n and e=="BANK_STALE_QUOTE")
local quoted=assert(W.plan(s,p))
local bank,dirty=W.execute(s,"Company",p,quoted)
assert(bank and #dirty==2 and bank.town==1 and bank.id==W.BASE and bank.produced[1].rate==6)
assert(c.rating[1]==20 and c.expense==quoted.price and c.cash==2000000-quoted.price)
assert(s.sites[1].population<1400 and not s.tiles[p].house and not s.tiles[Sim.id(9,8)].house)
assert(s.tiles[p].stock_industry.gfx==58 and s.tiles[Sim.id(9,8)].stock_industry.gfx==59)
assert(s.road_bank and s.stock_bank_industries[bank.id]==bank)
local p2=Sim.id(33,8)
local second=assert(W.execute(s,"Company",p2,assert(W.plan(s,p2))))
assert(second.id==W.BASE+1 and second.town==2 and second.founder=="Company")
print("PASS exact two-city Temperate Bank construction, stale and unaffordable quotes, one debit and town-owned clearance")
