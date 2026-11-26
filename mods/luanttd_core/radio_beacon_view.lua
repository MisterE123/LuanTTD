-- Small, non-persistent red obstruction flash on the physical beacon housing.
-- This is scenery, not a simulated aircraft signal or a light-emitting map node.
return function(core,Sim,painted)
  local V,name={}, "luanttd_core:radio_beacon"
  local enter,leave=43,49
  local period,pulse=1.65,.32
  local refs,clock,poll={},0,.5
  core.register_entity(name,{
    initial_properties={
      visual="sprite",textures={"bl_radio_beacon.png"},visual_size={x=.205,y=.205},
      static_save=false,physical=false,collide_with_objects=false,pointable=false,
      use_texture_alpha=true,glow=14,is_visible=false,
    },
  })
  local function remove(id)
    local r=refs[id]
    if r.ref:get_pos() then r.ref:remove() end
    refs[id]=nil
  end
  function V.step(dt,s,viewers)
    clock,poll=clock+dt,poll+dt
    if not viewers[1] then
      for id in pairs(refs) do remove(id) end
      poll=.5
      return
    end
    if poll>=.5 then
      poll=poll%.5
      local seen,checked={},{}
      for _,p in ipairs(viewers) do
        local a,b=math.max(1,math.floor((p.x-leave)/2)),math.min(Sim.W,math.ceil((p.x+leave)/2))
        local c,d=math.max(1,math.floor((p.z-leave)/2)),math.min(Sim.H,math.ceil((p.z+leave)/2))
        for z=c,d do for x=a,b do
          local id=Sim.id(x,z)
          local t=s.tiles[id]
          if t and (t.airfield or t.stock_landmark) then
            if checked[id]==nil then checked[id]=painted(id,x,z,t) or false end
            local at=checked[id]
            if at and (p.x-at.x)^2+(p.y-at.y)^2+(p.z-at.z)^2<=(refs[id] and leave or enter)^2 then
              seen[id]=at
            end
          end
        end end
      end
      for id,r in pairs(refs) do
        local at=seen[id]
        if not at or at.x~=r.x or at.y~=r.y or at.z~=r.z or not r.ref:get_pos() then remove(id) end
      end
      for id,at in pairs(seen) do
        if not refs[id] then
          local ref=core.add_entity(at,name)
          if ref then
            refs[id]={ref=ref,x=at.x,y=at.y,z=at.z,phase=(id*37%127)/127*period,on=false}
          end
        end
      end
    end
    for _,r in pairs(refs) do
      local on=(clock+r.phase)%period<pulse
      if on~=r.on then
        r.ref:set_properties({is_visible=on})
        r.on=on
      end
    end
  end
  return V
end
