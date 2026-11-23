-- Use the real stock-authority paths through the direction picker.
local root="mods/luanttd_core/"
local function load(f) return dofile(root..f..".lua") end
local Sim,Track,Slope,Terrain=load("sim"),load("openttd/rail_track"),load("openttd/slope"),load("openttd/terrain")
local F=load("openttd/rail_follow")(Track)
local C=load("openttd/rail_yapf_cost")(Track,F)
local Search=load("openttd/rail_yapf_search")(Track,F,C)
local Signal=load("openttd/rail_signals")(Track)
local Q=load("openttd/rail_construction")(Track,Signal,load("openttd/rail_height")(Track,Slope))
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
for i=1,#s.tiles do s.tiles[i]={terrain="grass",h=0} end
local owner,id="SignalQA",Sim.id(3,3)
local cash=Sim.company(s,owner)
local function shape(t) return Terrain.tile(s.corner_grid,Sim.xy(t)) end
local Lab=load("trackworks")(Sim,Track,F,Slope,C,Search,shape)
assert(Lab.change(s,owner,id,Track.X,false,0))
local Run=load("rail_dispatch_run")(Track,F,C,Search,nil,{new=function()return {} end},Signal,nil,nil,nil,Lab)
local markup,form,closed
core={get_modpath=function()return "mods/luanttd_core" end,formspec_escape=function(x)return x end,
 show_formspec=function(_,name,body)form,markup=name,body end,
 close_formspec=function(_,name)assert(name==form);closed=true end}
local api={Sim=Sim,s=s,terrain={tile=shape},road_first=true,render={update=function()end},save=function()end}
api.rail_build=load("rail_construction_tools")(api,Lab,Track,Run,{
  signal=function(t,dir,oneway,o)local q,e=Q.signal(t,dir%2,{kind=oneway and Signal.PBS_ONEWAY or Signal.PBS},o);return q and q.cost,e end,
  clear_signal=function()return Q.base_prices().clear_signal end})
local U=load("ui")(api)
local p={get_player_name=function()return owner end,get_pos=function()return {x=4,z=7} end}
U.select_tool(p,"rail_signal_pbs")
assert(U.signal_arrow(p,id)==2)
U.build_world(p,id)
assert(form=="luanttd_core:rail_signal" and markup:find("West  →  East",1,true)
  and markup:find("East  →  West",1,true) and not s.stock_rail_dispatch)
local buy=assert(markup:match("(signal_%d+_dir0);East"))
assert(U.fields(p,form,{[buy]=true}))
assert(closed and cash.cash==99935 and api.rail_build.signal_details(id).dirs[1]==0)
assert(U.fields(p,form,{[buy]=true}) and cash.cash==99935)
U.context(p,id)
assert(form=="luanttd_core:rail_signal" and markup:find("travelling West",1,true))
local flip=assert(markup:match("(signal_%d+_flip);Flip"))
assert(U.fields(p,form,{[flip]=true}))
assert(cash.cash==99935 and api.rail_build.signal_details(id).dirs[1]==2 and markup:find("travelling East",1,true))
assert(U.fields(p,form,{[flip]=true}) and api.rail_build.signal_details(id).dirs[1]==2)
local remove=assert(markup:match("(signal_%d+_remove);Review"))
assert(U.fields(p,form,{[remove]=true}) and form=="luanttd_core:demolish_layers")
assert(api.rail_build.signal_details(id) and s.tiles[id].rail_tracks==1)
local confirmed=assert(markup:match("(bulldoze_%d+_%d+);Remove signal"))
assert(U.fields(p,form,{[confirmed]=true}) and not api.rail_build.signal_details(id) and s.tiles[id].rail_tracks==1)
assert(cash.cash==99925)
print("PASS choose either valid direction, flip free, remove through confirmation, stale replay cannot spend")
