-- SPDX-License-Identifier: GPL-2.0-only
-- Presentation-only visits between stock shopping frontages. Never a
-- company vehicle, never has an order, and never blocks the real road.
return function(core,Sim,view,Lanes,Motion,enabled)
  local V={}
  local path=debug and debug.getinfo(1,"S").source:match("^@(.*/)ambient_shop_traffic%.lua$")
  local Audience=dofile((path or (core.get_modpath and core.get_modpath("luanttd_core").."/")
    or "mods/luanttd_core/").."ambient_audience.lua")
  local refname="luanttd_core:scenic_shop_car"
  local shops={[0x0e]=true,[0x0f]=true,[0x10]=true,[0x1d]=true,[0x1e]=true,[0x28]=true}
  local cars, observers={},{}
  local elapsed,scan,serial,age=0,0,0,0
  local function townroad(id)
    local t=id and view.host_tile(id)
    return t and t.build=="road" and (t.road_town or t.town_road) and
      (t.road_disallowed or t.disallowed or 0)==0 and not t.roadworks and not t.level_crossing and
      not t.road_bridge_id and not t.road_tunnel_id and t.road_bits and t
  end
  local function shop(id)
    for d=1,4 do
      local next_=Sim.adjacent(id,d)
      local t=next_ and view.host_tile(next_)
      local source=t and t.source_house
      if source and source.completed and shops[source.id] then return next_
      elseif t and t.parcel=="shop" then return next_ end
    end
  end
  local function offers(bits,d) return math.floor(bits/2^(d-1))%2==1 end
  function V.plan(id)
    local start=townroad(id)
    local first=start and shop(id)
    if not first then return end
    local waiting={id}
    local back={[id]=false}
    local distance={[id]=0}
    for index=1,42 do
      local current=waiting[index]
      if not current then break end
      if distance[current]>=3 then
        local target=shop(current)
        if target and target~=first then
          local path={current}
          current=back[current]
          while current do table.insert(path,1,current);current=back[current] end
          return path
        end
      end
      if distance[current]<9 then
        local road=townroad(current)
        if road then
          for d=1,4 do
            if offers(road.road_bits,d) then
              local next_=Sim.adjacent(current,d)
              local target=townroad(next_)
              if target and distance[next_]==nil and offers(target.road_bits,(d+1)%4+1) then
                waiting[#waiting+1]=next_;distance[next_]=distance[current]+1;back[next_]=current
              end
            end
          end
        end
      end
    end
  end
  local function protected(pos,r)
    for _,o in ipairs(core.get_objects_inside_radius(pos,r)) do
      local e=o:get_luaentity()
      local p=e and e.luanttd_vehicle
      if e and ((p and p.kind=="road") or e.name=="luanttd_core:sightseeing_car") then return true end
    end
    return false
  end
  function V.clear(pos,r) return not protected(pos,r) end
  local function pose(path,i,part)
    local a,b=path[i],path[i+1]
    local from,to=townroad(a),townroad(b)
    if not from or not to then return end
    local direction
    for d=1,4 do if Sim.adjacent(a,d)==b then direction=d;break end end
    if not direction or not offers(from.road_bits,direction) or not offers(to.road_bits,(direction+1)%4+1) then return end
    local rx,rz,tx,tz,turn=Motion.corner(path,i+part,Sim.xy,townroad)
    if rx then
      rx,rz=Lanes.position(rx,rz,tx,tz,Lanes.outside_phase(path,i+part,Sim.xy))
      return {x=rx,y=view.surface(turn,rx,rz)+.018,z=rz},-math.atan2(tx,tz)
    end
    local ax,az=Sim.xy(a);local bx,bz=Sim.xy(b)
    local dx,dz=bx-ax,bz-az
    local x,z=2*(ax+dx*part)+.5,2*(az+dz*part)+.5
    local near=part<.5 and a or b
    local px,pz=Lanes.position(x,z,dx,dz,nil,math.min(1,i==1 and part*4 or 1))
    if i==#path-1 and part>.48 then
      -- Pull onto the verge at the shop rather than popping in the lane.
      local f=(part-.48)/.52
      local side=.34*f*f*(3-2*f)
      px,pz=px+side*dz,pz-side*dx
    end
    return {x=px,y=view.surface(near,px,pz)+.018,z=pz},-math.atan2(dx,dz)
  end
  core.register_entity(refname,{initial_properties={
    visual="mesh",mesh="bl_sightseeing_car.obj",textures={"bl_sightseeing_car_palette.png^[multiply:#b5d4ff"},
    physical=false,collide_with_objects=false,pointable=false,static_save=false,
    visual_size={x=.92,y=.92,z=.92},shaded=true,
  }})
  function V.step(dt,players)
    elapsed=elapsed+dt;scan=scan+dt
    if elapsed<.21 then return end
    local dtime=math.min(.40,elapsed)
    elapsed=0
    age=age+dtime
    local viewers,watchers=Audience.capture(players,enabled)
    local audience_changed=not Audience.same_set(observers,watchers)
    if audience_changed then observers=watchers end
    local function distance(p,x,z) return (p.x-x)^2+(p.z-z)^2 end
    for i=#cars,1,-1 do
      local c=cars[i];local alive=c.ref:get_pos()
      local next_i,next_part=c.i,c.part
      if not c.arrived then
        next_part=next_part+dtime*.53
        if next_part>=1 then
          if next_i+1==#c.path then next_part=1
          else next_i,next_part=next_i+1,next_part-1 end
        end
      end
      local pos,yaw=pose(c.path,next_i,next_part)
      local near=false
      if alive then
        for _,v in ipairs(viewers) do
          if distance(v.at,alive.x,alive.z)<44^2 and math.abs(v.at.y-alive.y)<60 then near=true;break end
        end
      end
      local retiring=not near or c.arrived and age-c.arrived>=4 or c.yielding and age-c.yielding>=2
      if not retiring then c.ambient_unseen=0 end
      -- A visible car waits for traffic where possible. If an actual vehicle
      -- is about to overlap it, the real route takes precedence.
      if not alive or not pos or #viewers==0 or protected(alive,1.05)
         or retiring and Audience.retire(c,viewers,alive,96,dtime) then
        if alive then c.ref:remove() end
        table.remove(cars,i)
      else
        if audience_changed and c.ref.set_observers then c.ref:set_observers(observers) end
        if not c.arrived then
          if protected(pos,4.75) then c.yielding=c.yielding or age
          else
            c.yielding=nil
            c.i,c.part=next_i,next_part
            if c.part==1 then c.arrived=age end
            c.ref:set_yaw(yaw)
            c.ref:move_to(pos,true)
          end
        end
      end
    end
    if scan<1.65 or #cars>=4 then return end
    scan=0
    for i=1,math.min(#viewers,4) do
      local viewer=viewers[i].at
      for _=1,9 do
        serial=(serial+1)%1013
        local r=8+(serial*17)%21
        local angle=serial*2.39996323
        local px,pz=viewer.x+r*math.cos(angle),viewer.z+r*math.sin(angle)
        local id=Sim.id(math.floor((px+.5)/2),math.floor((pz+.5)/2))
        local close=false
        for _,c in ipairs(cars) do
          local p=c.ref:get_pos();if p and distance(p,px,pz)<13^2 then close=true;break end
        end
        local path=id and not close and V.plan(id)
        if path then
          local pos=pose(path,1,0)
          if pos and not protected(pos,8) then
            local ref=core.add_entity(pos,refname)
            if ref then
              if ref.set_observers then ref:set_observers(observers) end
              cars[#cars+1]={ref=ref,path=path,i=1,part=0}
              return
            end
          end
        end
      end
    end
  end
  return V
end
