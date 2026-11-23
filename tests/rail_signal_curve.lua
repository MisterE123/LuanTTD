-- Compare every stock fractional tile position for independent half rail.
local root="mods/luanttd_core/"
local function load(f)return dofile(root..f..".lua")end
local T=load("openttd/rail_track")
local Pick=load("openttd/rail_signal_place")(T)
for u=0,15 do for v=0,15 do
  assert(Pick(48,u,v)==(u<=v and 5 or 4))
  assert(Pick(12,u,v)==(u+v<=15 and 2 or 3))
  assert(Pick(1,u,v)==0 and Pick(2,u,v)==1)
end end

local Sim,Slope,Terrain=load("sim"),load("openttd/slope"),load("openttd/terrain")
local Follow=load("openttd/rail_follow")(T)
local Cost=load("openttd/rail_yapf_cost")(T,Follow)
local Search=load("openttd/rail_yapf_search")(T,Follow,Cost)
local Sig=load("openttd/rail_signals")(T)
local Block=load("openttd/rail_block_signals")(T,Sig)
local PBS=load("openttd/rail_reservation")(T,Follow,Cost)
local Life=load("openttd/rail_consist_reservation")(T,Follow,PBS)
local Q=load("openttd/rail_construction")(T,Sig,load("openttd/rail_height")(T,Slope))
local s=Sim.new(983)
s.rail_owned_service,s.rail_block_preview=true,true
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
for i=1,#s.tiles do s.tiles[i]={terrain="grass",h=0} end
local owner,id="Half rail",Sim.id(9,8)
local function shape(at) return Terrain.tile(s.corner_grid,Sim.xy(at)) end
local Lab=load("trackworks")(Sim,T,Follow,Slope,Cost,Search,shape)
assert(Lab.change(s,owner,id,T.UPPER,false,0))

local Run=load("rail_dispatch_run")(T,Follow,Cost,Search,PBS,Life,Sig,nil,nil,nil,Lab,nil,nil,nil,nil,nil,Block)
local markup,form
core={
  get_modpath=function()return "mods/luanttd_core" end,formspec_escape=function(x)return x end,
  show_formspec=function(_,f,m)form,markup=f,m end,close_formspec=function()end,
}
local api={Sim=Sim,s=s,terrain={tile=shape},road_first=true,rail_block_tools=true,
  render={update=function()end},save=function()end}
local function price(q,why)return q and q.cost,why end
api.rail_build=load("rail_construction_tools")(api,Lab,T,Run,{
  signal_track=function(t,k,type_,o)return price(Q.signal(t,k,{kind=type_},o))end,
  track=function(t,p,o) return p.remove and Q.rail_clear_price(0,o) or price(Q.piece(t,p.track,o)) end,
  clear_signal=function()return Q.base_prices().clear_signal end})
local R=api.rail_build
local U=load("ui")(api)
local p={get_player_name=function()return owner end,get_pos=function()return {x=21,z=15} end}
local x,z=Sim.xy(id)
local upper,lower={x=2*x-.25,z=2*z-.25},{x=2*x+1.1,z=2*z+1.1}
assert(R.signal_track(id,upper)==T.UPPER and R.signal_track(id,lower)==nil)
local money=Sim.company(s,owner)
U.select_tool(p,"rail_signal_pbs");U.build_world(p,id,upper)
local pbs=assert(markup:match("(signal_%d+_td2);"))
assert(U.fields(p,form,{[pbs]=true}))
assert(R.signal_details(id,T.UPPER).tds[1]==2 and R.signal_details(id,T.LOWER)==nil)
assert(not R.quote_track(owner,id,id,T.X,false))
assert(R.build(owner,assert(R.quote_track(owner,id,id,T.LOWER,false))))
assert(R.signal_track(id,lower)==T.LOWER and R.signal_details(id,T.UPPER).tds[1]==2)
U.select_tool(p,"rail_signal_block");U.build_world(p,id,lower)
local both=assert(markup:match("(signal_%d+_both);"))
assert(U.fields(p,form,{[both]=true}))
assert(#R.signal_details(id,T.LOWER).tds==2 and R.signal_details(id,T.LOWER).kind==Sig.BLOCK)
assert(R.signal_details(id,T.UPPER).kind==Sig.PBS)
U.context(p,id,upper)
local flip=assert(markup:match("(signal_%d+_flip);"))
assert(U.fields(p,form,{[flip]=true}))
assert(R.signal_details(id,T.UPPER).tds[1]==10 and #R.signal_details(id,T.LOWER).tds==2)
local remove=assert(R.quote_track(owner,id,id,T.UPPER,true))
assert(remove.price==-60 and remove.pieces[1].remove_signal)
assert(R.build(owner,remove))
assert(R.signal_details(id,T.UPPER)==nil and #R.signal_details(id,T.LOWER).tds==2)
assert(money.cash==100000-65-100-65+60 and s.tiles[id].rail_tracks==8)
local art,Pose=load("rail_signal_art"),load("rail_pose")(T)
for _,mask in ipairs({12,48,4,8,16,32}) do
  for td=2,13 do
    if T.valid_trackdir(td) and T.track(td)>=2 and T.has(mask,T.track(td)) then
      for _,right in ipairs({false,true}) do
        local u,v=assert(art.world_anchor(td,right,mask))
        for actual=2,5 do if T.has(mask,actual) then
          for i=0,96 do
            local a,b=Pose.sample(actual,i/96)
            assert((u/8-1-a)^2+(v/8-1-b)^2>=.397^2)
          end
        end end
      end
    end
  end
end
print("PASS RC1 half-track click selection, paid stock path and both-direction block signals, independent flip/remove and mast clearance")
