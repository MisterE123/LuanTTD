local depot,platform,mixed=88,97,107
local s={stations={[1]={mode="road"},[4]={mode="road",stop_type="truck"}},
  tiles={[depot]={station=1},[platform]={rail_station_id=15},[mixed]={station=4}}}
local road={{kind="board",cargo="passenger",data={tile=depot,units=6}},
  {kind="board",cargo="mail",data={tile=mixed,units=8}}}
local rail={{kind="board",tile=platform,station_local=15,units=3}}
local sim={
  xy=function(t) return t%10,math.floor(t/10) end,
  waiting_passengers=function(_,st) assert(st==s.stations[1]);return 9 end,
  commercial_passengers_waiting=function(_,mode,id) assert(mode=="rail" and id==15);return 2 end,
  road_loading_events=function() local old=road;road={};return old end,
  rail_loading_events=function() local old=rail;rail={};return old end,
}
local P=dofile("mods/luanttd_core/campaign_passenger_projection.lua")(sim,s)
local counts=P.counts({{id=depot},{id=platform},{id=mixed}})
assert(counts["road:1"]==9 and counts["rail:15"]==2 and counts["road:4"]==0)
P.collect()
local one,tick=P.events({{x=7,z=8,w=2,h=1}},0)
assert(#one==1 and one[1].mode=="road" and one[1].units==6 and tick==2)
local two,tick2=P.events({{x=7,z=9,w=1,h=1}},0)
assert(#two==1 and two[1].mode=="rail" and two[1].units==3 and tick2==2)
assert(#P.events({{x=7,z=8,w=2,h=3}},tick2)==0)
P.frame(2)
assert(#P.events({{x=7,z=8,w=2,h=3}},0)==0)
print("PASS bounded visible passenger counts and exact station-specific boarding events expire without replay")
