local base="mods/bayline/"
local function load(n)return dofile(base..n..".lua")end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local s=Sim.new(1751)
load("town_layout")(Sim,s)
local stats
s.corner_grid,stats=load("harbor_valley_seed")(Sim,Terrain,s,load("terrain_preview")(Sim,Terrain,s))
local c=Sim.company(s,"Bridge Builder")
local id=Sim.id
local wet=stats.bridge
local a,b=id(wet.x1,wet.z),id(wet.x2,wet.z)
local funds=c.cash
local applied,saves,form=0,0,nil
core={formspec_escape=function(s)return s end,show_formspec=function(n,f,s) form={n=n,f=f,s=s} end}
local p={get_player_name=function()return "Bridge Builder"end,get_player_control=function()return{}end}
local picker=load("bridge_picker")({s=s,Sim=Sim,structure_tools=true,
  render={raise_bound=function(h)assert(h>=1)end,update=function(ids)assert(#ids>=3);applied=applied+1 end},
  save=function()saves=saves+1 end})
local seen=nil
local function capture(yes,msg) seen={yes,msg} end
local q=assert(picker.quote("road","Bridge Builder",a,b))
assert(q.minimum==2447 and #q.ids==7 and #q.offers==2) -- Concrete is too short.
assert(q.offers[2].name=="Steel girder" and q.offers[2].speed==64)
assert(picker.open(p,"road",a,b,capture) and form.s:find("Timber",1,true) and form.s:find("$2,447",1,true))
assert(c.cash==funds and not s.stock_road_bridges and applied==0 and saves==0)
local stale=form.s:match("(bridge_%d+_2)")
picker.fields(p,form.f,{[stale]=true})
assert(seen[1] and c.cash==funds-q.offers[2].price and applied==1 and saves==1)
picker.fields(p,form.f,{[stale]=true})
assert(applied==1 and saves==1)
assert(s.tiles[a].road_bridge_id==s.tiles[b].road_bridge_id)
assert(s.stock_road_bridges[s.tiles[a].road_bridge_id].bridge_type==2)
local other_a,other_b=id(21,15),id(27,15)
assert(picker.open(p,"road",other_a,other_b,capture))
local olds=s.topology
s.topology=s.topology+1
local choose=form.s:match("(bridge_%d+_0)")
picker.fields(p,form.f,{[choose]=true})
assert(not seen[1] and applied==1 and saves==1 and s.topology==olds+1)
assert(picker.open(p,"road",other_a,other_b,capture))
picker.fields(p,form.f,{quit=true})
picker.fields(p,form.f,{[form.s:match("(bridge_%d+_0)")]=true})
assert(applied==1 and saves==1)
print("PASS real bridgehead quotes, responsive style list, no draw-time payment, one actual native construction, and stale/cancel refusal")
