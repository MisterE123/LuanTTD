local path="mods/luanttd_core/"
local function m(n)return dofile(path..n..".lua")end
local S,T=m("sim"),m("openttd/terrain")
local K=m("openttd/rail_track")
local W=m("openttd/ship_follow")(K)
local N=m("ship_network")(S,T,W,m("openttd/ship_facilities")(K,W))
local s=S.new(81)
s.corner_grid=T.new(S.W,S.H,function(x)return x<15 and 1 or 0 end)
s.stock_generated_profile={}
local at=S.id
for i in ipairs(s.tiles) do
  local x=S.xy(i)
  s.tiles[i]={terrain=x>=15 and "water" or "grass",h=x<15 and 1 or 0,
    coastal_water=x==14 or nil,water_class=x>=15 and "sea" or nil}
end
local land=at(14,20)
s.sites={{id=1,kind="town",tile=at(13,20),name="Cove"}}
local company=S.company(s,"Dock Company")
s.stock_road_town_policy={tolerance=0,dist_local_authority=3}
local ratings={[1]=-200}
company.stock_town_authority_ratings=ratings
s.tiles[land].wood={type=1,count=3}
assert(not s.tiles[land].ship)
local cash=company.cash
local none,why=N.quote(s,"Dock Company","dock",land)
assert(not none and why=="STATION_AUTHORITY_RATING")
assert(company.cash==cash and s.tiles[land].wood.count==3 and ratings[1]==-200)
s.stock_road_town_policy.dist_local_authority=1 -- Manhattan 1 is excluded at the threshold
assert(N.quote(s,"Dock Company","dock",land).cost==410)
s.stock_road_town_policy.dist_local_authority=3
s.stock_road_town_policy.tolerance=3
assert(N.quote(s,"Dock Company","dock",land).cost==410)
s.stock_road_town_policy.tolerance=0
ratings[1]=-199
local q=assert(N.quote(s,"Dock Company","dock",land))
assert(q.cost==410 and q.water==at(15,20))
assert(company.cash==cash and ratings[1]==-199 and s.tiles[land].wood.count==3)
local p=assert(N.build(s,"Dock Company","dock",land))
assert(p.id==1 and company.cash==cash-410 and ratings[1]==-234 and not s.tiles[land].wood)
assert(s.tiles[land].stock_clear_density==0 and s.tiles[p.water].ship.station==p.id)
assert(N.remove(s,"Dock Company",p.water) and not s.tiles[land].wood and not s.tiles[land].ship)
assert(ratings[1]==-234)
print("PASS stock dock council threshold, permissive bypass, one three-tree quote/debit and one exact -35 rating penalty")
