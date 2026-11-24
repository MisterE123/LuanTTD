-- Isolated in-world test for extreme distance and elevation, using the
-- normal HUD renderer and a real native client's HUD calls.
local labels_once
core.register_on_joinplayer(function(p)
  if labels_once then return end
  labels_once=true
  local name=p:get_player_name()
  local T=dofile(mod.."/openttd/terrain.lua")
  local Sim=api.Sim
  local close,far=Sim.id(15,18),Sim.id(43,18)
  for z=1,Sim.H+1 do for x=1,Sim.W+1 do
    S.corner_grid.levels[(z-1)*(Sim.W+1)+x]=math.max(0,math.min(12,x-13))
  end end
  for z=1,Sim.H do for x=1,Sim.W do
    local id=Sim.id(x,z)
    local _,base=T.tile(S.corner_grid,x,z)
    S.tiles[id]={h=base,terrain="grass",variant=(x+z)%4}
  end end
  S.sites[505]={id=505,tile=far,kind="town",name="Far Ridge",population=440,stock={},produced={},received={},service=0}
  S.tiles[far].site=505
  S.sites[506]={id=506,tile=close,kind="factory",name="Lower Works",population=0,stock={},produced={},received={},service=0}
  S.tiles[close].site=506
  local camera={x=17,y=19,z=35.5}
  core.emerge_area({x=12,y=0,z=23},{x=93,y=19,z=47},function(_,action,left)
    assert(action~=core.EMERGE_CANCELLED and action~=core.EMERGE_ERRORED)
    if left~=0 then return end
    core.after(0,function()
      local real=assert(core.get_player_by_name(name))
      real:set_pos(camera)
      real:set_look_horizontal(-math.pi/2)
      real:set_look_vertical(.12)
      core.set_timeofday(.27)
      render.raise_bound(12)
      render.update{close,far}
      core.after(2,function()
        local shown={}
        for id,row in pairs(real:hud_get_all()) do
          if row.name and row.world_pos then shown[row.name]={id=id,at=row.world_pos} end
        end
        local first=assert(shown["Far Ridge  (440)"])
        assert(first.at.y==17 and first.at.x==86.5)
        assert((first.at.x-camera.x)>42,"Fixture must be outside the old visibility radius")
        local ground=assert(shown["Lower Works"])
        assert(ground.at.y>6 and ground.at.x==30.5)
        -- A raised new surface must move the same existing nametag, not
        -- allocate another or leave it at its first observed height.
        S.tiles[far].h=14
        core.after(1.5,function()
          local moved=assert(real:hud_get(first.id))
          assert(moved.name=="Far Ridge  (440)" and moved.world_pos.y==19)
          core.log("action","PLACE_LABELS_NATIVE_SCENE_READY far=69.5 raised=19 same_hud=true")
        end)
      end)
    end)
  end)
end)
