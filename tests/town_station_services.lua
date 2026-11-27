local m="mods/luanttd_core/"
local G=dofile(m.."openttd/town_growth.lua")
local Sim={
  xy=function(id)return (id-1)%16+1,math.floor((id-1)/16)+1 end,
  id=function(x,z)if x>=1 and x<=16 and z>=1 and z<=16 then return (z-1)*16+x end end,
  rail_coal_active=function()return true end, rail_profile_active=function(_,cargo)return cargo=="wood" end,
  ship_coal_active=function()return true end, ship_oil_active=function(_,id)return not id or id==9 end,
}
local M=dofile(m.."town_station_services.lua")(Sim)
local S={
  stations={},tiles={},rail_paid_service=true,air_paid_service=true,
  stock_rail_stations={[1]={owner="A",tiles={34},coal_role="load"},[2]={owner="A",tiles={35},wood_role="unload"},
    [3]={owner="A",tiles={36},coal_role="load"},[4]={owner="B",tiles={37},coal_role="load"}},
  stock_ship_stations={[5]={owner="A",sign_tile=52,land=52,water=53},[8]={owner="A",land=55,water=56},
    [9]={neutral=true,id=9,oil_rig=2,land=54,water=54}},
  stock_small_airports={[9]={neutral=true,id=9,oil_rig=2,origin=54,tiles={{id=54}}}},
  stock_neutral_stations={[9]={id=9,type="oilrig",industry=2,tile=54}},
  stock_ship_commercial={service={stations={
    {host_mode="rail",host_id=1,owner="A",sign={x=2,y=3},time_since_load=255,time_since_unload=12},
    {host_mode="air",host_id=9,owner=false,sign={x=6,y=4},time_since_load=255,time_since_unload=7},
  }}},
  stock_rail_coal={stations={
    {host_id=1,owner="A",time_since_load=1,time_since_unload=255},
    {host_id=3,owner="A",time_since_load=0}, -- no physical railway
    {host_id=4,owner="A",time_since_load=0}, -- old company
  }},
  stock_rail_wood={stations={{host_id=2,owner="A",time_since_load=255,time_since_unload=20}}},
  stock_ship_coal={stations={{host_id=5,owner="A",time_since_unload=4}}},
  stock_oil_ship_service={stations={{host_id=9,time_since_load=8},{host_id=8,owner="A",time_since_load=1}}},
}
S.tiles[34]={owner="A",rail_station_id=1}
S.tiles[35]={owner="A",rail_station_id=2}
S.tiles[37]={owner="B",rail_station_id=4}
for id=52,53 do S.tiles[id]={ship={kind="dock",station=5}} end
for id=55,56 do S.tiles[id]={ship={kind="dock",station=8}} end
S.tiles[54]={ship={kind="oilrig",station=9},airfield={airport=9}}
local town=G.new(1,4,4,{num_houses=45})
local rows=M.view(S)
assert(#rows==4 and G.active_stations(town,rows)==4)
assert(rows[1].mode=="rail" and rows[1].id==1 and rows[1].time_since_load==1 and rows[1].time_since_unload==12)
assert(rows[2].id==2 and rows[2].time_since_unload==20)
assert(rows[3].id==5 and rows[3].x==4 and rows[3].z==4)
assert(rows[4].mode=="ship" and rows[4].id==9 and rows[4].time_since_load==8 and rows[4].time_since_unload==7)
assert(G.month(town,rows,2,function()error("Recent real freight service must avoid unserviced lottery")end))
local Stock=dofile(m.."openttd/road_town_permission.lua")
local Authority=dofile(m.."town_road_authority.lua")(Sim,Stock)
S.companies={A={stock_town_authority_ratings={[1]=100}},B={},C={}}
local month_rows=M.view(S,true)
assert(#month_rows==6 and G.active_stations(town,month_rows)==4,
  "Fresh stations should be visible to council rating, but not count as served")
Authority.month(S,town,Authority.station_view(S,month_rows))
assert(S.companies.A.stock_town_authority_ratings[1]==126, "100+5+3*12-15; idle dock, three actual facilities")
assert(S.companies.B.stock_town_authority_ratings[1]==485, "A foreign stale clock must not replace a real idle platform")
assert(not S.companies.C.stock_town_authority_ratings,"Unrelated company ledger should stay untouched")
S.stock_rail_wood.stations[1].time_since_unload=21
S.tiles[52].ship=nil
S.tiles[54].ship=nil
S.stock_ship_commercial.service.stations[2].time_since_unload=21
rows=M.view(S)
assert(#rows==3 and G.active_stations(town,rows)==1,"Stale dock/rig clocks or expired freight counted")
S.stock_rail_stations[1].coal_role=nil
S.stock_ship_commercial.service.stations[1].time_since_unload=21
assert(G.active_stations(town,M.view(S))==0)
print("PASS physical station clocks merge passenger and freight, neutral dock and airport, and reject stale roles")
