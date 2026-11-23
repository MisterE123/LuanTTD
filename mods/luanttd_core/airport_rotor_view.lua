-- Native rendering only: two physical rotor axes follow the stock rotor
-- period; no vehicle, clock or station authority lives in this layer.
return function(core)
  local V={}
  function V.register(art)
    if not art or not art.rotor then return end
    for _,part in ipairs({{"rotor",art.rotor},{"tail",art.tail_rotor}}) do
      core.register_entity(art.entity.."_"..part[1],{initial_properties={
        physical=false,pointable=false,collide_with_objects=false,static_save=false,
        visual="mesh",mesh=part[2],textures={art.atlas},backface_culling=true,shaded=true,
        visual_size={x=art.scale,y=art.scale,z=art.scale}}})
    end
  end
  function V.clear(body)
    if not body or not body.rotors then return end
    for _,e in ipairs(body.rotors) do if e:get_pos() then e:remove() end end
    body.rotors=nil
  end
  function V.step(body,art,pose,period,dt)
    if not art or not art.rotor then return end
    if not body.rotors then
      local a=core.add_entity(pose,art.entity.."_rotor")
      local b=core.add_entity(pose,art.entity.."_tail")
      if not a or not b then
        if a then a:remove() end
        if b then b:remove() end
        return
      end
      body.rotors={a,b}
    end
    body.rotor_repaint=(body.rotor_repaint or .06)+dt
    if period and period>0 then
      body.rotor_angle=((body.rotor_angle or 0)+dt*600/math.max(2,period)*2)%360
    elseif body.rotor_angle then
      body.rotor_angle=0
    end
    if body.rotor_repaint<.036 then return end
    body.rotor_repaint=0
    local yaw=body.rotor_angle or 0
    body.rotors[1]:set_attach(body.ref,"",art.rotor_offset,{x=0,y=yaw,z=0},true)
    body.rotors[2]:set_attach(body.ref,"",art.tail_offset,{x=-yaw*3%360,y=0,z=0},true)
  end
  return V
end
