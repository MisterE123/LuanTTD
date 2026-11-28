-- Pinned 16.0-RC1 native country-airfield build, demolition and reopen
-- in the active 128x128 bus/wood/Goods world, observed at command
-- boundaries. Prices and intervening airport animation are not compared.
local mod="mods/luanttd_core/"
local function m(n) return dofile(mod..n..".lua") end
local S,T,G,Codec=m("sim"),m("openttd/terrain"),m("openttd/town_growth"),m("packed_campaign")
local Air=m("airport_network")(S,T,m("openttd/airport_small"))
local Views=m("town_station_services")(S)
S.W,S.H=128,128
local s=S.new(1751)
local a,b=S.id(61,37),S.id(62,37)
local owner="Source comparison"
s.stock_pool_authority,s.stock_engine_startup_seed=true,1751
s.passenger_house_clock={counter=12600}
s.corner_grid=T.new(128,128,function() return 1 end)
for i in ipairs(s.tiles) do s.tiles[i]={terrain="grass",h=1} end
for i=0,4 do s.stations[100+i]={id=100+i,stock_station_id=i,mode="road",owner=owner,tile=S.id(20+i,21)} end
S.company(s,owner)
local function golden(p,check)
  assert(p.stock_station_id==5 and p.origin-1==check[1] and p.stock_random_bits==check[2])
  for i,pos in ipairs(p.tiles) do assert(s.tiles[pos.id].airfield.stock_random_bits==check[3][i]) end
  assert(s.passenger_rating_rng[1]==check[4] and s.passenger_rating_rng[2]==check[5])
end
s.passenger_rating_rng={3411287708,1941530451}
local p=assert(Air.build(s,owner,a,"country"))
golden(p,{4668,33746,{14,4,0,11,9,7,15,0,0,4,5,2},4056914964,412686927})
p.name="Airport Way"
s.air_paid_service=true
s.stock_ship_commercial={service={stations={
  {host_mode="air",host_id=p.id,owner=owner,time_since_load=255,time_since_unload=20},
}}}
s.passenger_house_clock.counter=12604
assert(Air.remove(s,owner,a,false))
assert(s.retired_airports[1].row.time_since_unload==20 and not Air.airport_for(s,a))
s.stock_ship_commercial=nil
s=assert(Codec.decode(Codec.encode(s)))
s.passenger_house_clock.counter=13315
s.passenger_rating_rng={1997285353,1116536364}
assert(assert(Air.quote(s,owner,b,"country")).reopen==1)
assert(not assert(Air.quote(s,owner,b,"country",true)).reopen)
assert(s.passenger_rating_rng[1]==1997285353 and s.passenger_rating_rng[2]==1116536364)
p=assert(Air.build(s,owner,b,"country"))
golden(p,{4669,34044,{6,11,4,4,12,4,14,14,4,14,2,10},4218151646,1073496766})
assert(p.name=="Airport Way" and p.id==1 and s.next_small_airport==2)
local t=G.new(1,62,37)
for i,time in ipairs({13315,13316,13498,13505}) do
  local load,unload,phase=Views.reactivated_clocks(s,p,time)
  assert(load==255 and unload==(i<3 and 20 or 21) and phase==({3,4,1,8})[i])
  assert(G.active_stations(t,Views.view(s,false,time))==(i<3 and 1 or 0))
end
print("PASS live RC1 country airport renewal: original ID, 25 construction draws and 20/21 town service-age boundary")

-- Stock OnTick_Station invokes airport acceptance even if no plane
-- is running. Compare both RNG words from the actual idle airfield.
local Rating=m("station_rating_runtime")(S,m("openttd/station_rating"),m("openttd/passengers"))
local accept_cases={
  {13495,2490727304,2461403597,4185292872,311340912},
  {13745,3178788726,4154065508,4114863135,3618574061},
  {13995,3673326371,1490676301,1065901724,2069778531},
  {14245,3140427287,827514026,1702226733,4150649793},
  {14495,1510562330,2637552008,1227316538,1262562114},
  {14745,235321109,1320416111,784320096,2713769697},
}
s.stations={}
for _,x in ipairs(accept_cases) do
  local tick,a,b,c,d=unpack(x)
  s.passenger_rating_rng={a,b}
  Rating.advance(s,1,nil,tick-1)
  assert(s.passenger_rating_rng[1]==a and s.passenger_rating_rng[2]==b)
  Rating.advance(s,1,nil,tick)
  assert(s.passenger_rating_rng[1]==c and s.passenger_rating_rng[2]==d)
end
local x=accept_cases[1]
local run={passenger_rating_rng={x[2],x[3]}}
local road_low,spent,road_high=S.stock_random_u32(run),S.stock_random_u32(run),S.stock_random_u32(run)
local function add(id,pool)
  s.stations[id]={mode="road",id=id,stock_station_id=pool,tile=S.id(20+id,25),
    owner=owner,stock={},passenger_rating_phase=184}
end
add(8,3);add(3,7)
s.topology=s.topology+1
s.passenger_rating_rng={x[2],x[3]}
local seen={}
Rating.advance(s,1,function(state,st) seen[st.stock_station_id]=S.stock_random_u32(state) end,x[1])
assert(seen[3]==road_low and seen[7]==road_high)
assert(s.passenger_rating_rng[1]==run.passenger_rating_rng[1] and s.passenger_rating_rng[2]==run.passenger_rating_rng[2])
print("PASS six native RC1 idle-airfield acceptance RNG pulses and mixed physical road/airport order")
