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
  local function winding(key,pos,players,dt,index,speed,mesh,atlas)
    if not present(pos,players) then return end
    local r=reels[key]
    if not r or not r.ref or not r.ref:get_pos() then
      local ref=core.add_entity(pos,"luanttd_core:coal_winding_sheaves")
      if ref and mesh then ref:set_properties({mesh=mesh,textures={atlas}}) end
      r={ref=ref,angle=0}
      reels[key]=r
    end
    if r.ref and (index.hoist_active or index.produced and index.produced.rate>0) then
      r.angle=(r.angle+dt*speed*2.8)%(math.pi*2)
      r.ref:set_rotation({x=r.angle,y=0,z=0})
    end
    return true
  end
  local chimneys={{2.48,3.38,2.1},{4.34,3.52,2.1}}
  function V.step(dt,online,speed)
    speed=speed or S.speed or 0
    if not online then for id in pairs(reels) do remove(id) end;return end
    local smoke=false
    if not api.generated_world and speed>0 then smoke_elapsed=smoke_elapsed+dt end
    if smoke_elapsed>.62 then smoke=true;smoke_elapsed=0 end
    local active={}
    local players=core.get_connected_players()
    for id,ind in pairs(S.stock_coal_industries or {}) do
      if not ind.removed then
        if ind.kind=="coal_mine" then
          if (ind.layout or 0)==0 then
            local x,z=ind.x+2,ind.z+2
            local _,base=api.terrain.tile(Sim.id(x,z))
            local pos={x=2*x+.5,y=base+.5+2.395,z=2*z+.42}
            local paint=core.get_node_or_nil({x=2*x,y=base+1,z=2*z})
            if paint and paint.name=="luanttd_core:coal_mine_0_1_1" then
              active[id]=winding(id,pos,players,dt,ind,speed)
            end
          else
            for n,t in ipairs(ind.tiles) do
              if t.gfx==0 then
                local x,z=t.x+1,t.z+1
                local _,base=api.terrain.tile(Sim.id(x,z))
                local paint=core.get_node_or_nil({x=2*x,y=base+1,z=2*z})
                if paint and paint.name=="luanttd_core:industry_layout_gfx_0" then
                  local key=id..":"..n
                  local pos={x=2*x+.50,y=base+2.27,z=2*z+.25}
                  active[key]=winding(key,pos,players,dt,ind,speed,"bl_industry_layout_hoist_wheels.obj","bl_stock_industry_layout_parts_atlas.png")
                end
              end
            end
          end
        elseif (ind.layout or 0)==0 and smoke and ind.accepted and ind.accepted.last_accepted and
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
