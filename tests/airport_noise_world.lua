-- Real saved airport footprint accounting, source fallback and rating cutoff.
local root="mods/luanttd_core/"
local function load(n) return dofile(root..n..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Noise=load("openttd/airport_noise")
local A=load("airport_network")(Sim,Terrain,load("openttd/airport_small"),load("openttd/airport_city"),
  load("openttd/airport_oil_rig"),load("openttd/airport_heliport"),{},Noise)
local s=Sim.new(1751)
local tile=Sim.id
s.corner_grid=Terrain.new(Sim.W,Sim.H)
for i=1,Sim.W*Sim.H do s.tiles[i]={terrain="grass",h=0,variant=0} end
s.day=90000
s.sites={{id=1,kind="town",name="Left",tile=tile(8,8),population=800},
  {id=2,kind="town",name="Right",tile=tile(16,8),population=1600}}
s.stock_road_town_policy={station_noise_level=true,tolerance=0}
local owner="Council Test"
local c=Sim.company(s,owner)
c.cash=100000
c.stock_town_authority_ratings={[1]=-200}
local p,err=A.quote(s,owner,tile(11,8),"country")
assert(not p and err=="AIRPORT_AUTHORITY_RATING")
s.stock_road_town_policy.dist_local_authority=3
assert(A.quote(s,owner,tile(11,8),"country"),"Boundary must be excluded")
s.stock_road_town_policy.dist_local_authority=nil
s.stock_road_town_policy.station_noise_level=false
assert(select(2,A.quote(s,owner,tile(11,8),"country"))=="AIRPORT_AUTHORITY_RATING",
  "Town rating still applies with airport noise disabled")
s.stock_road_town_policy.station_noise_level=true
c.stock_town_authority_ratings[1]=-199
local q,e=A.quote(s,owner,tile(11,8),"country")
assert(q,e)
assert(q.town==1 and q.noise.town==2 and q.noise.add==3 and q.noise.distance==2 and q.noise.limit==5)
assert(A.town_noise(s,2).used==0)
local one=assert(A.build(s,owner,tile(11,8),"country"))
assert(one.town==1 and not one.noise and A.town_noise(s,2).used==3 and A.town_noise(s,1).used==0)
assert(A.build(s,owner,tile(15,8),"heliport"))
assert(A.build(s,owner,tile(16,8),"heliport"))
assert(A.town_noise(s,2).used==5)
local paid=c.cash
local nope,why,town=A.build(s,owner,tile(17,8),"heliport")
assert(not nope and why=="TOWN_REFUSES_AIRPORT_NOISE" and town==2 and c.cash==paid)
-- Third-airport fallback is per associated station town, independent of
-- perimeter noise. Permissive skips only the count/rating, not enabled noise.
s.stock_road_town_policy.station_noise_level=false
assert(not A.town_noise(s,2))
assert(select(2,A.quote(s,owner,tile(17,8),"heliport"))=="TOWN_REFUSES_THIRD_AIRPORT")
s.stock_road_town_policy.tolerance=3
assert(A.quote(s,owner,tile(17,8),"heliport"))
s.stock_road_town_policy.station_noise_level=true
s.stock_road_town_policy.tolerance=0
local P=load("packed_campaign")
s=assert(P.decode(P.encode(s)))
assert(A.town_noise(s,2).used==5)
assert(A.remove(s,owner,tile(15,8),true))
assert(A.town_noise(s,2).used==5,"Quote may not release allowance")
assert(A.remove(s,owner,tile(15,8),false))
assert(A.town_noise(s,2).used==4)
assert(A.build(s,owner,tile(17,8),"heliport"))
s.sites[2].population=0
assert(A.town_noise(s,2).limit==0 and A.town_noise(s,2).used==5)
print("PASS rated airport limits, perimeter versus anchor, no default third airport, budget clipping and removal/restart")
