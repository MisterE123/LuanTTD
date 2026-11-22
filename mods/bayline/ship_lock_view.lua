-- Dynamic native lock surfaces and gates, synchronized to the saved ferry.
return function(api,Art)
  local V={}
  local Sim,S=api.Sim,api.s
  local pieces={}
  local function register(name)
    core.register_entity("bayline:ship_lock_"..name,{
      initial_properties={physical=false,pointable=false,collide_with_objects=false,static_save=false,
        visual="mesh",mesh="bl_ship_lock_"..name..".obj",textures={"bl_ship_lock_atlas.png"},
        shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1}},
    })
  end
  register("chamber_water")
  for _,part in ipairs({"lower","upper"}) do register("gate_"..part.."_open");register("gate_"..part.."_closed") end
  local function remove(row,i)
    local a=row[i]
    if a and a.ref and a.ref:get_pos() then a.ref:remove() end
    row[i]=nil
  end
  local function draw(row,i,label,pos,rotation)
    local a=row[i]
    if a and a.name~=label then remove(row,i);a=nil end
    if not a or not a.ref or not a.ref:get_pos() then
      a={name=label,ref=core.add_entity(pos,"bayline:ship_lock_"..label)}
      row[i]=a
    end
    if a.ref then
      if not a.xyz or a.xyz.y~=pos.y then a.ref:set_pos(pos);a.xyz=pos end
      if not a.rot or a.rot~=rotation then a.ref:set_yaw(rotation);a.rot=rotation end
    end
  end
  function V.step(online,fraction)
    if not online then return end
    local show={}
    local p=S.ship_pilot
    local v=p and p.vehicle
    if p and p.paid_clock then
      local ship,yaw=Sim.ferry_paid_pose(S,fraction)
      if ship and yaw then
        local x,z=(ship.x+.5)*8,(ship.z+.5)*8
        v={x=x,y=z,z=(ship.y-.5)*8,tile=Sim.id(math.floor(x/16),math.floor(z/16)),
          direction=math.floor(yaw*4/math.pi+3.5)%8}
      else v=nil end
    end
    local part=v and S.tiles[v.tile] and S.tiles[v.tile].ship
    for id,lock in pairs(S.stock_ship_locks or {}) do
      local x,z=Sim.xy(id)
      local _,base=api.terrain.tile(id)
      local frame=Art.frame(lock,part,v,x,z,base)
      if frame~=lock.presentation then lock.presentation=frame end
      for _,p in ipairs(core.get_connected_players()) do
        local pos=p:get_pos()
        if pos and (pos.x-(2*x+.5))^2+(pos.z-(2*z+.5))^2<86^2 then
          show[id]=true;break
        end
      end
      if show[id] then
        local water,lower,upper,turn=Art.pose(lock.dir,x,z,base,frame.phase)
        local row=pieces[id] or {};pieces[id]=row
        draw(row,1,"chamber_water",water,turn)
        draw(row,2,"gate_lower_"..(frame.lower and "open" or "closed"),lower,turn)
        draw(row,3,"gate_upper_"..(frame.upper and "open" or "closed"),upper,turn)
      end
    end
    for id,row in pairs(pieces) do
      if not show[id] then
        for i=1,3 do remove(row,i) end
        pieces[id]=nil
      end
    end
  end
  return V
end
