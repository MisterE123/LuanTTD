-- Exercise the actual /car entry, input loop, turn direction, gates and exit
-- on real simulation road connectivity, with just the Lua engine API mocked.
local mod="mods/luanttd_core"
local Sim=dofile(mod.."/sim.lua")
local S={tiles={},companies={},stock_road_bridges={},stock_road_tunnels={}}
local function id(x,z) return assert(Sim.id(x,z)) end
local function road(x,z,bits)
  S.tiles[id(x,z)]={build="road",road_bits=bits,h=0}
end
road(10,8,4);road(10,9,5);road(10,10,11);road(9,10,2);road(11,10,10);road(12,10,8)
local cmd,registered,p,model,attached,state,hint,warning
local removed=0
local player_yaw,lookx,lookz=0,0,1
p={
  get_player_name=function() return "driver" end,
  get_pos=function() return {x=20,y=12,z=17} end,
  get_look_dir=function() return {x=lookx,y=-.8,z=lookz} end,
  get_attach=function()return attached end,
  get_look_horizontal=function()return player_yaw end,
  set_look_horizontal=function(_,x)player_yaw=x end,
  set_look_vertical=function()end,set_properties=function()end,set_physics_override=function()end,
  set_attach=function(_,q)attached=q end,set_detach=function()attached=nil end,
  hud_add=function()return 1 end,hud_change=function(_,_,_,s)hint=s end,hud_remove=function()end,
}
core={
  get_modpath=function()return mod end,
  register_entity=function(n,q)assert(n=="luanttd_core:sightseeing_car");registered=q end,
  register_chatcommand=function(n,q)assert(n=="car");cmd=q.func end,
  get_player_by_name=function()return p end,
  chat_send_player=function(_,msg)warning=msg end,
  add_entity=function(pos)
    local ref={pos=pos,get_pos=function(self)return self.pos end,
      move_to=function(self,q)self.pos=q end,set_yaw=function()end,
      remove=function(self)removed=removed+1;self.pos=nil end}
    model=ref
    return ref
  end,
}
local target=id(10,8)
local W={
  target=function()return target end,
  begin_avatar=function(_,mode)assert(mode=="car");state={mode=mode};return state end,
  end_avatar=function(_,mode)assert(mode=="car" and not attached);state=nil;return true end,
}
local rendering={surface=function(_,x,z)return x<1 and z or .5 end}
local C=dofile(mod.."/avatar_car.lua")({s=S,Sim=Sim,render=rendering},W)
local function tick(keys,n)
  for _=1,n do C.step(p,state,keys,.05) end
end
assert(registered.initial_properties.mesh=="bl_sightseeing_car.obj" and registered.static_save==false)
assert(cmd("driver") and C.active(p) and attached==model)
local start=model.pos.z
tick({up=true},12)
assert(model.pos.z>start+1 and hint:find("W drive",1,true))
tick({up=true},45)
assert(math.abs(model.pos.z-20.5)<.001 and hint:find("No open road",1,true),"T junction arbitrarily picked an exit")
tick({up=true,right=true},45)
assert(math.abs(model.pos.x-24.5)<.001 and math.abs(model.pos.z-(20.5-.155))<.001,"D did not steer right facing +Z")
tick({down=true},55)
assert(model.pos.x<21.7,"reverse did not move backwards")
assert(cmd("driver") and not C.active(p) and not attached and not state and removed==1)
assert(next(S.companies)==nil,"sightseeing mutated the ledger")

-- Drive exactly up to but not through a closed crossing. When it opens the
-- same input progresses normally; disconnect/demolition is checked live.
target=id(10,8)
S.tiles[id(10,9)].level_crossing={barred=true}
assert(cmd("driver"))
tick({up=true},30)
assert(model.pos.z<18 and hint:find("No open road",1,true),"entered a barred crossing")
S.tiles[id(10,9)].level_crossing.barred=false
tick({up=true},15)
assert(model.pos.z>18)
S.tiles[id(10,9)].road_bits=0
-- Remove both halves to invalidate the current or next admitted segment.
S.tiles[id(10,8)].road_bits=0
tick({up=true},20)
assert(not C.active(p) and not attached and warning:find("Road changed",1,true))

-- Bridge deck above an unrelated surface tile, then exit back onto asphalt.
local a,b,m=id(15,8),id(15,10),id(15,9)
road(15,7,4);road(15,11,1)
S.tiles[a]={build="stock_road_bridge",h=0,road_bridge_id=1}
S.tiles[b]={build="stock_road_bridge",h=0,road_bridge_id=1}
S.tiles[m]={terrain="water",h=0}
S.stock_road_bridges[1]={start=a,["end"]=b,head={inside_direction=1,road_slope=0,road_base=0},
  tail={inside_direction=3,road_slope=0,road_base=0},deck=1,middle_by_tile={[m]=true}}
target=id(15,7)
assert(cmd("driver"))
local deck,land
for _=1,70 do tick({up=true},1)
  if model.pos.z>=17.6 and model.pos.z<=19.4 and math.abs(model.pos.y-1.52)<.0001 then deck=true end
  if model.pos.z>21.6 and math.abs(model.pos.y-.52)<.0001 then land=true end
end
assert(deck and land,"did not stay on bridge layer and reach linked land")
C.leave("driver")
assert(not model.pos and not C.active(p),"disconnect leaked a street vehicle")
print("avatar car: command, movement, explicit right turn, reverse, gate, live edit, bridge layer, persistence isolation and cleanup OK")
