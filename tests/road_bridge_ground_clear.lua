-- OpenTTD 16.0-RC1: MP_CLEAR permits an overhead span for free. Trees do not.
-- Both normal price quote and native construction consume only the called
-- landscape-clear sites; an independent owner on a public surface is okay.
local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Codec=load("sim"),load("openttd/terrain"),load("packed_campaign")
Sim.W,Sim.H=64,64
local s=Sim.new(1950)
s.tiles,s.sites={},{}
s.stock_generated_profile={width=64,depth=64}
s.corner_grid=Terrain.new(64,64,function() return 2 end,{freeform_edges=true})
for id=1,64*64 do s.tiles[id]={terrain="grass",h=2,variant=0} end
local function id(x) return Sim.id(x,18) end
s.sites[1]={id=1,kind="town",tile=Sim.id(12,20),name="Newmere"}
local owner,rival="Bridge Works","North Rail"
local c=Sim.company(s,owner)
Sim.company(s,rival)
local head,tail=id(10),id(18)
local function forest(x,n)
  s.tiles[id(x)].wood={class=4,count=n,ground=0,density=3,type=0,growth=3}
end
forest(10,2);forest(11,3)
s.tiles[id(12)].stock_clear_ground=1
s.tiles[id(13)].stock_clear_ground=2
s.stock_farm_fields={[id(14)]={stage=4}}
s.tiles[id(15)].owner,s.tiles[id(15)].stock_object=owner,{kind="owned_land"}
s.tiles[id(16)].build,s.tiles[id(16)].owner,s.tiles[id(16)].rail_tracks="stock_rail",rival,2
s.tiles[id(17)].stock_clear_density=0
s.tiles[id(17)].stock_clear_visits=4
local function raw() return Sim.road_bridge(s,owner,head,tail,0,true) end
local ok,cost,plan=raw()
assert(ok and plan.site_cost==40+60-80+20,cost)
assert(#plan.clears==4 and c.cash==100000 and s.tiles[id(11)].wood.count==3)
-- Reject a rival's stake before touching any tree or charging a cent.
s.tiles[id(15)].owner=rival
local accepted,why=raw()
assert(not accepted and why:find("OWNED_BY_ANOTHER",1,true) and c.cash==100000)
s.tiles[id(15)].owner=owner
assert(Sim.road_bridge(s,owner,head,tail,0))
local index=s.bridge_above
for x=10,18 do
  local t=s.tiles[id(x)]
  assert(t.h==2 and t.terrain=="grass")
  if x==16 then assert(t.rail_tracks==2 and t.owner==rival)
  elseif x==12 or x==13 then
    assert(t.stock_clear_ground==x-11)
  elseif x==14 then
    assert(s.stock_farm_fields[id(x)].stage==4)
  elseif x==17 then
    assert(t.stock_clear_density==0 and t.stock_clear_visits==4)
  else
    assert(not t.wood and not t.stock_object and not t.stock_clear_ground and not t.stock_clear_visits)
    assert(t.stock_clear_density==0)
  end
  if x>10 and x<18 then assert(index[id(x)]==index[id(11)]) end
end
assert(c.cash==100000-cost and s.stock_farm_fields[id(14)])
local A=load("openttd/road_town_permission")
assert(c.stock_town_authority_ratings[1]==A.clear_trees(A.clear_trees(A.initial)))
local restored=assert(Codec.decode(Codec.encode(s)))
assert(restored.bridge_above[id(11)] and restored.tiles[id(11)].stock_clear_density==0)
assert(restored.tiles[id(16)].owner==rival and restored.companies[owner].cash==c.cash)
assert(restored.tiles[id(13)].stock_clear_ground==2 and restored.stock_farm_fields[id(14)].stage==4)
-- A named replacement visits ground again; existing bare earth has no cost.
-- If a new tree grew around the span, a replacement clears and charges it.
forest(11,4)
local ok,upgrade,p=Sim.road_bridge(s,owner,head,tail,3,true)
assert(ok and p.replacement and p.site_cost==80+9*(50+2*40))
local cash=c.cash
assert(Sim.road_bridge(s,owner,head,tail,3))
assert(c.cash==cash-upgrade and not s.tiles[id(11)].wood and s.bridge_above[id(11)]==index[id(11)])
assert(c.stock_town_authority_ratings[1]==A.clear_trees(A.clear_trees(A.clear_trees(A.initial))))
print("PASS RC1 road bridge: preserve clear ground variants below; clear ramps, woods and owned stakes")
