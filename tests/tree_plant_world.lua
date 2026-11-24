local m="mods/luanttd_core/"
local S=dofile(m.."sim.lua")
local T=dofile(m.."openttd/terrain.lua")
local P=dofile(m.."packed_campaign.lua")
S.W,S.H=64,64
local s=S.new(144)
s.tiles,s.sites={},{}
s.stock_generated_profile={width=64,depth=64}
s.corner_grid=T.new(64,64,function() return 1 end,{freeform_edges=true})
local town=S.id(7,8)
s.sites[1]={id=1,kind="town",tile=town,name="Woodwick"}
local function put(x,z,t)
  local id=S.id(x,z);s.tiles[id]=t;return id
end
local a=put(7,7,{terrain="grass",h=1,stock_clear_density=1})
local b=put(8,7,{terrain="grass",h=1,stock_clear_ground=2})
local c=put(9,7,{terrain="grass",h=1,station=12})
local d=put(10,7,{terrain="grass",h=1,wood={class=4,count=2,growth=2,type=9,ground=0,density=3}})
local e=put(11,7,{terrain="grass",h=1})
s.rail_bridge_above={[e]=5}
local company=S.company(s,"Builder")
company.stock_town_authority_ratings={[1]=209}
local start=company.cash
local topo=s.topology
local Cmd=dofile(m.."campaign_landscape_commands.lua")(S,s)
local req={first=a,last=e,operation="plant_tree",species=7}
local q=assert(Cmd.quote("Builder",req))
assert(q.cost==280 and #q.tiles==3 and q.tiles[1]==a and q.tiles[2]==b and q.tiles[3]==d)
assert(not company.stock_tree_plant_limit and company.cash==start and not s.tiles[a].wood
  and company.stock_town_authority_ratings[1]==209)
-- Daily movement or another owner may invalidate a quoted footprint.
s.tiles[a].house=1
local ok,why=Cmd.commit("Builder",q)
assert(not ok and why=="TERRAIN_QUOTE_CHANGED" and company.cash==start)
s.tiles[a].house=nil
ok,why=Cmd.commit("Builder",q);assert(ok,why)
assert(company.cash==start-280 and company.stock_town_authority_ratings[1]==220 and s.topology==topo+1)
assert(s.tiles[a].wood.type==7 and s.tiles[a].wood.density==1)
assert(s.tiles[b].wood.type==7 and s.tiles[b].wood.density==0 and not s.tiles[b].stock_clear_ground)
assert(s.tiles[d].wood.type==9 and s.tiles[d].wood.count==3 and s.tiles[d].wood.growth==2)
assert(not s.tiles[c].wood and not s.tiles[e].wood)
assert(company.stock_tree_plant_limit==(4096-3)*65536 and company.clear_limit==(4096-1)*65536,
  tostring(company.clear_limit))
-- Use a contiguous fixture for the packed world codec.
for id=1,S.W*S.H do s.tiles[id]=s.tiles[id] or {terrain="grass",h=1} end
local save=assert(P.decode(P.encode(s)))
assert(save.companies.Builder.stock_tree_plant_limit==company.stock_tree_plant_limit
  and save.tiles[b].wood.density==0 and save.tiles[d].wood.type==9)
print("PASS landscaping worker tree gesture: stock price and quotas, stale quote, town rating, preserved grove, packed checkpoint")
