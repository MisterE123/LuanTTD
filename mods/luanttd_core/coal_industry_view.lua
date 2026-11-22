-- Machinery and exhaust follow real active industry, not player proximity
-- as a production trigger. All entities are non-persistent presentation.
return function(api)
  local V={}
  local S,Sim=api.s,api.Sim
  local reels,smoke_elapsed={},0
  core.register_entity("luanttd_core:coal_winding_sheaves",{
    initial_properties={physical=false,pointable=false,collide_with_objects=false,static_save=false,
      visual="mesh",mesh="bl_coal_mine_0_sheaves.obj",textures={"bl_coal_mine_atlas.png"},
      visual_size={x=1,y=1,z=1},backface_culling=true,shaded=true},
  })
  local function remove(id)
    local a=reels[id]
    if a and a.ref and a.ref:get_pos() then a.ref:remove() end
    reels[id]=nil
  end
  local function present(pos,players)
    for _,p in ipairs(players) do
      local a=p:get_pos()
      if a and (a.x-pos.x)^2+(a.z-pos.z)^2<72^2 then return true end
    end
    return false
  end
  local chimneys={{2.48,3.38,2.1},{4.34,3.52,2.1}}
  function V.step(dt,online)
    if not online then return end
    local smoke=false
    if S.speed>0 then smoke_elapsed=smoke_elapsed+dt end
    if smoke_elapsed>.62 then smoke=true;smoke_elapsed=0 end
    local active={}
    local players=core.get_connected_players()
    for id,ind in pairs(S.stock_coal_industries or {}) do
      if not ind.removed then
        if ind.kind=="coal_mine" then
          local x,z=ind.x+2,ind.z+2
          local _,base=api.terrain.tile(Sim.id(x,z))
          local pos={x=2*x+.5,y=base+.5+2.395,z=2*z+.42}
          if present(pos,players) then
            local a=reels[id]
            if not a or not a.ref or not a.ref:get_pos() then
              a={ref=core.add_entity(pos,"luanttd_core:coal_winding_sheaves"),angle=0}
              reels[id]=a
            end
            if a.ref and ind.produced and ind.produced.rate>0 then
              a.angle=(a.angle+dt*S.speed*2.8)%(math.pi*2)
              a.ref:set_rotation({x=a.angle,y=0,z=0})
            end
            active[id]=true
          end
        elseif smoke and ind.accepted and ind.accepted.last_accepted and
            S.day-ind.accepted.last_accepted<4 then
          local x,z=ind.x+1,ind.z+1
          local _,base=api.terrain.tile(Sim.id(x,z))
          for _,c in ipairs(chimneys) do
            local pos={x=2*x+c[1],y=base+.5+c[2],z=2*z+c[3]}
            if present(pos,players) then
              core.add_particle({pos=pos,velocity={x=.10,y=.50,z=.10},acceleration={x=.04,y=.16,z=.02},
                expirationtime=1.38,size=3.1,texture="bl_coal_haze.png",collisiondetection=false})
            end
          end
        end
      end
    end
    for id in pairs(reels) do if not active[id] then remove(id) end end
  end
  return V
end
