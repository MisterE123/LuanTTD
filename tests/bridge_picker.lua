local base="mods/luanttd_core/"
local function load(n)return dofile(base..n..".lua")end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local s=Sim.new(1751)
load("town_layout")(Sim,s)
local stats
s.corner_grid,stats=dofile("tests/coastal_corridor_fixture.lua")(Sim,Terrain,s,load("terrain_preview")(Sim,Terrain,s))
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
assert(q.minimum==2447 and #q.ids==7 and #q.offers==3) -- Ordinary concrete and the fast girder are too short.
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
local sent,observed
local remote=load("bridge_picker")({s=s,Sim=Sim,authority_handoff=true,worker_bridge_client={
  query=function(q,done) assert(not sent);sent={q,done};return true end,
}})
local prevcash=c.cash
assert(remote.open(p,"road",other_a,other_b,capture))
assert(sent[1].kind=="bridge_picker" and sent[1].first==other_a)
local answer=sent[2];sent=nil
answer({ok=true,revision=17,value={token=21,ids={other_a,other_b},minimum=2012,
  offers={{style=2,name="Steel girder",speed=64,price=2012}}}})
observed=form.s
assert(observed:find("Steel girder",1,true) and observed:find("$2,012",1,true) and c.cash==prevcash)
local button=observed:match("(bridge_%d+_2)")
remote.fields(p,form.f,{[button]=true})
local req=assert(sent)[1]
assert(req.kind=="command" and req.command.kind=="bridge_picker" and req.command.token==21
  and req.command.revision==17 and req.command.style==2)
sent[2]({ok=true,why="Bridge complete on the worker."})
assert(seen[1] and c.cash==prevcash and applied==1 and saves==1)
print("PASS the same native bridge list submits the owner's price and protected ticket without mutating the host")

sent=nil
assert(remote.open(p,"rail",other_a,other_b,capture))
answer=sent[2];sent=nil
local offers={}
for i=0,9 do offers[i+1]={style=i,name="RC1 style "..i,price=1200+i,speed=48+i} end
answer({ok=true,revision=34,value={token=98,ids={other_a,other_b},offers=offers}})
local large=form.s
assert(large:find("scroll_container[",1,true) and large:find("scroll_container_end[]",1,true))
assert(large:find("max=32",1,true) and not large:find("size[10,10.8]",1,true))
assert(large:find("RC1 style 9",1,true))
remote.fields(p,form.f,{bridge_scroll="CHG:30"})
assert(not sent,"Scrolling must not commit or consume a bridge ticket")
button=assert(large:match("(bridge_%d+_9)"))
remote.fields(p,form.f,{[button]=true})
assert(sent[1].command.token==98 and sent[1].command.style==9)
print("PASS ten stock bridge offers scroll inside a bounded popup and a lower choice preserves its exact ticket")
