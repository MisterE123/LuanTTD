local path="mods/luanttd_core/"
local Sim=dofile(path.."sim.lua")
Sim.W,Sim.H=64,64
local source={stock_coal_industries={
  {id=1,kind="coal_mine",x=4,z=4,tiles={{x=5,z=5,gfx=0}}},
  {id=2,kind="power_station",x=6,z=8,tiles={{x=9,z=8,gfx=10}}},
}}
local camera={x=12,y=8,z=12}
local emitted={}
local rotation,removed
core={
  register_entity=function() end,
  get_connected_players=function() return {{get_pos=function()return camera end}} end,
  get_node_or_nil=function(p)
    return {name=p.x==12 and "luanttd_core:coal_mine_0_1_1" or "luanttd_core:power_station_3_0"}
  end,
  add_entity=function(p)
    removed=false
    return {get_pos=function()return not removed and p end,remove=function()removed=true end,
      set_rotation=function(_,r) rotation=r.x end}
  end,
  add_particle=function(p) emitted[#emitted+1]=p end,
}
local V=dofile(path.."coal_industry_view.lua")({s=source,Sim=Sim,generated_world=true,
  terrain={tile=function()return 0,2 end}})
local a,b=Sim.id(6,6),Sim.id(10,9)
V.observe({[a]={gfx=1,frame=193,dir=1,tick=1060},[b]={gfx=10,frame=2,dir=0,tick=1060,active=true}})
V.step(.2,true,1)
assert(rotation and rotation>0 and #emitted==3)
local prev=rotation
V.step(.2,true,0)
assert(rotation==prev and #emitted==3)
local flash=emitted[1]
assert(flash.pos.x>20 and flash.pos.y>3 and flash.pos.z>18 and flash.glow==12)
assert(flash.texture=="bl_transformer_arc.png")
V.observe({[a]={gfx=1,frame=128,dir=-1,tick=1570},[b]={gfx=10,frame=3,dir=0,tick=1570,active=true}})
V.step(.1,true,1)
assert(rotation<prev and #emitted==6)
camera={x=450,y=8,z=450}
V.step(.2,true,1)
assert(removed and #emitted==6 and not V.witness(a))
print("PASS real machinery presentation rules: active/reverse/pause, one flash per frame, source position, range culling")
