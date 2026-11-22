-- The production action moves just the player, over authoritative geometry.
local calls={}
core={formspec_escape=function(x)return x end}
local tiles={[1]={h=5},[2]={h=2},[3]={stock_void=true}}
local Sim={id=function()return 1 end,xy=function(id)return 2*id,3*id end}
local api={Sim=Sim,s={tiles=tiles,bridge_above={[2]=6},stock_road_bridges={[6]={deck=12}}},
  terrain={},render={uses_slope=function(id)return id==1 end,
  surface=function(id,x,z)assert(id==1 and x==4.5 and z==6.5);return 6.5 end},
  save=function()error("Teleporting must not edit the simulation")end}
local U=dofile("mods/bayline/ui.lua")(api)
local p={get_player_name=function()return "QA" end,
  set_pos=function(_,pos)calls[#calls+1]=pos end,
  set_look_vertical=function()error("must preserve pitch")end,
  set_look_horizontal=function()error("must preserve yaw")end}
assert(U.teleport_tile(p,1) and calls[1].x==4.5 and calls[1].z==6.5 and calls[1].y==14.5)
assert(U.teleport_tile(p,2) and calls[2].x==8.5 and calls[2].z==12.5 and calls[2].y==21)
assert(not U.teleport_tile(p,3) and not U.teleport_tile(p,nil) and #calls==2)
print("PASS: direct tile teleport, slope and bridge clearance, void rejected, angle unchanged, no save")
