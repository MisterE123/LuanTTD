-- The stone lighthouse is painted from stock scenery. Only its rotating
-- optics are transient; nothing here changes town, map or worker state.
return function(core,Sim)
  local V={}
  local entity="luanttd_core:lighthouse_beam"
  local enter,leave=48,56
  local tau=2*math.pi
  local rate=tau/32
  local refs,elapsed={},.45
  core.register_entity(entity,{
    initial_properties={
      visual="mesh",mesh="bl_lighthouse_beam.obj",textures={"bl_lighthouse_beam.png"},
      static_save=false,physical=false,collide_with_objects=false,pointable=false,
      visual_size={x=10,y=10,z=10}, -- OBJ numbers are authored in node units
      use_texture_alpha=true,backface_culling=false,shaded=false,glow=-1,
      automatic_rotate=rate,
    },
  })
  local function clear()
    for id,v in pairs(refs) do
      if v.ref:get_pos() then v.ref:remove() end
      refs[id]=nil
    end
  end
  function V.step(dt,s,viewers)
    local day=core.get_timeofday()
    if not viewers[1] or (day>=.235 and day<=.765) then
      clear()
      elapsed=.45 -- first look after sunset checks the coast immediately
      return
    end
    elapsed=elapsed+dt
    if elapsed<.45 then return end
    elapsed=0
    local keep,checked={},{}

    for _,p in ipairs(viewers) do
      for z=math.max(1,math.ceil((p.z-.525-leave)/2)),math.min(Sim.H,math.floor((p.z-.525+leave)/2)) do
        for x=math.max(1,math.ceil((p.x-.755-leave)/2)),math.min(Sim.W,math.floor((p.x-.755+leave)/2)) do
          local id=Sim.id(x,z)
          if not keep[id] then
            local t=s.tiles[id]
            if t and t.stock_landmark and t.stock_landmark.kind=="lighthouse" then
              -- Existing mesh optic sits off-center from the viewer tile
              -- (.255 east, .025 south) and 1.349 above the floor.
              local a={x=2*x+.755,y=t.h+1.849,z=2*z+.525}
              local old=refs[id]
              local r=old and old.y==a.y and leave or enter
              if (p.x-a.x)^2+(p.y-a.y)^2+(p.z-a.z)^2<=r*r then
                if checked[id]==nil then
                  local n=core.get_node_or_nil({x=2*x,y=t.h+1,z=2*z})
                  checked[id]=n~=nil and n.name=="luanttd_core:stock_lighthouse"
                end
                if checked[id] then keep[id]=a end
              end
            end
          end
        end
      end
    end
    for id,v in pairs(refs) do
      local a=keep[id]
      local live=v.ref:get_pos()
      if not a or v.y~=a.y or not live then
        if live then v.ref:remove() end
        refs[id]=nil
      end
    end
    local phase=(core.get_us_time()/1e6*rate)%tau
    for id,a in pairs(keep) do
      if not refs[id] then
        local ref=core.add_entity(a,entity)
        if ref then
          local seed=((id*37)%127)/127*tau
          ref:set_yaw((phase+seed)%tau)
          refs[id]={ref=ref,y=a.y}
        end
      end
    end
  end
  return V
end
