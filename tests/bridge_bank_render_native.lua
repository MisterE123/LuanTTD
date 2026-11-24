-- Road bridge across real, opposed coastal slopes in the production renderer.
local terrain=dofile(mod.."/openttd/terrain.lua")
local lo,hi,z=11,17,14
local function id(x,a) return assert(Sim.id(x,a)) end
local new=terrain.new(Sim.W,Sim.H,function(x) return (x<=lo or x>=hi+1) and 1 or 0 end)
S.corner_grid.levels=new.levels
local dirty={}
for a=1,Sim.H do for x=1,Sim.W do
  local k=id(x,a)
  local _,h=terrain.tile(S.corner_grid,x,a)
  local sea=x>=lo and x<=hi
  S.tiles[k]={terrain=sea and "water" or "grass",variant=(x+a)%4,h=h,
    water_class=sea and "sea" or nil,coastal_water=(x==lo or x==hi) or nil}
  if x>=lo-5 and x<=hi+5 and a>=z-7 and a<=z+7 then dirty[#dirty+1]=k end
end end
S.speed=0
local owner="PierQA"
Sim.company(S,owner).cash=200000
local yes,note,_,deck=Sim.road_bridge(S,owner,id(lo,z),id(hi,z),0)
assert(yes,note);assert(deck==1)
assert(not S.tiles[id(lo,z)].coastal_water and not S.tiles[id(hi,z)].coastal_water)
api.render.raise_bound(deck)
local ready=false
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  local first,last={x=2*(lo-5),y=-1,z=2*(z-7)},{x=2*(hi+5),y=6,z=2*(z+7)}
  core.emerge_area(first,last,function(_,_,left)
    if left~=0 then return end
    api.render.update(dirty)
    local function node(x,y,a,dx,dz)
      return core.get_node({x=x*2+dx,y=y,z=a*2+dz}).name
    end
    for _,x in ipairs({lo,hi}) do
      assert(node(x,1,z,0,0):find("stock_road_bridge_wood_head_flat",1,true),node(x,1,z,0,0))
      assert(node(x,1,z,1,0):find("bridge_bank_",1,true),node(x,1,z,1,0))
      for dx=0,1 do for dz=0,1 do
        assert(node(x,0,z,dx,dz)=="luanttd_core:slope_fill_open",node(x,0,z,dx,dz))
      end end
    end
    assert(node((lo+hi)/2,0,z,0,0):find("ocean_top",1,true),"true water under the span must remain")
    assert(node(lo,0,z+1,0,0):find("ocean_top",1,true),"unbuilt adjacent coast must keep genuine sea")
    p:override_day_night_ratio(.92)
    ready=true
    core.log("action","BRIDGE_BANK_NATIVE_READY two stock coast ramps retain shaped dry banks, original deck and surrounding sea")
  end)
end)
local old
core.register_globalstep(function()
  if not ready then return end
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f then return end
  local mode=f:read("*l");f:close()
  local p=core.get_player_by_name(owner)
  if not p or old==mode or (mode~="left_bank" and mode~="right_bank") then return end
  old=mode
  local x=mode=="left_bank" and lo or hi
  local d=x==lo and 1 or -1
  local from={x=x*2+d*4.1,y=.54,z=z*2-4.7}
  local to={x=x*2+.5,y=1.17,z=z*2+.5}
  local dx,dy,dz=to.x-from.x,to.y-from.y-1.625,to.z-from.z
  p:set_pos(from)
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  p:hud_set_flags({hotbar=false,crosshair=false})
  core.log("action","BRIDGE_BANK_NATIVE_VIEW "..mode)
end)
