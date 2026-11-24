-- SPDX-License-Identifier: GPL-2.0-only
-- Native, ephemeral scenery. Reads only already-projected nearby tiles;
-- doesn't own a terrain subscription, touch the clock, or draw sim RNG.
return function(core,Sim,view,media)
  local V={}
  local path=debug and debug.getinfo(1,"S").source:match("^@(.*/)ambient_wildlife%.lua$")
  local Audience=dofile((path or (core.get_modpath and core.get_modpath("luanttd_core").."/")
    or "mods/luanttd_core/").."ambient_audience.lua")
  local pi,sin,cos=math.pi,math.sin,math.cos
  local tau=2*pi
  local defs={
    whale={radius=6.5,velocity=.83,lifetime=84,view=56,min=11,rest=3*84},
    porpoise={radius=3.4,velocity=1.35,lifetime=52,view=52,min=8},
    seagull={radius=4.8,velocity=2.9,lifetime=58,view=53,min=8,variants={"wing_up","wing_down"}},
    eagle={radius=7.5,velocity=3.8,lifetime=72,view=62,min=12,rest=3*72,variants={"wing_up","wing_down"}},
    fox={scale=.5,radius=.69,velocity=.55,lifetime=52,view=36,min=5,rest=52,variants={"stride"}},
  }
  local ordered={"whale","porpoise","seagull","eagle","fox"}
  local texture="bl_wildlife_atlas.png"
  local name=function(kind) return "luanttd_core:wildlife_"..kind end
  local mesh=function(kind,variant) return "bl_wildlife_"..kind..(variant and "_"..variant or "")..".obj" end
  for _,kind in ipairs(ordered) do
    local d=defs[kind]
    d.ready=media[mesh(kind)] and media[texture]
    if d.ready then
      core.register_entity(name(kind),{initial_properties={
        physical=false,collide_with_objects=false,pointable=false,static_save=false,
        visual="mesh",mesh=mesh(kind),textures={texture},shaded=true,backface_culling=true,
        visual_size={x=d.scale or 1,y=d.scale or 1,z=d.scale or 1},
      }})
    end
  end
  local animals,cursors,observers,encounters={},{},{},{}
  local age,update,scans=0,0,1
  local sector_cursor=0
  local function tile(x,z)
    local id=Sim.id(math.floor((x+.5)/2),math.floor((z+.5)/2))
    return id and view.host_tile(id),id
  end
  local function distance(p,x,z)
    return (p.x-x)^2+(p.z-z)^2
  end
  local function sea(t,offshore)
    return t and not t.stock_void and not t.ship and not t.road_bridge_id and not t.rail_span_id and
      t.terrain=="water" and (not t.water_class or t.water_class=="sea") and not t.stock_canal and
      not t.build and (not offshore or not t.coastal_water)
  end
  local function field(t,id)
    return t and t.terrain~="water" and not t.build and not t.house and not t.wood and
      not t.stock_industry and view.host_record("stock_farm_fields",id)
  end
  local function habitat(kind,x,z)
    local t,id=tile(x,z)
    if not t or t.stock_void then return false end
    if kind=="whale" or kind=="porpoise" then
      if not sea(t,true) then return false end
      local clear=defs[kind].radius+(kind=="whale" and 2.15 or .65)
      for i=0,7 do
        local a=tau*i/8
        if not sea(tile(x+clear*cos(a),z+clear*sin(a)),true) then return false end
      end
      return true
    elseif kind=="fox" then
      return not not field(t,id)
    elseif kind=="seagull" then
      if (t.coastal_water or sea(t,false)) then return true end
      return sea(tile(x+4,z),false) or sea(tile(x-4,z),false) or
        sea(tile(x,z+4),false) or sea(tile(x,z-4),false)
    end
    return t.terrain~="water" and not t.house and not t.build and
      (t.wood or (t.h or 0)>=2)
  end
  function V.habitat(kind,x,z) return not not (defs[kind] and habitat(kind,x,z)) end
  local function remove(i)
    local a=animals[i]
    if a.ref:get_pos() then a.ref:remove() end
    table.remove(animals,i)
  end
  local function height_at(x,z,fallback)
    local t,id=tile(x,z)
    return t and not t.stock_void and ((view.uses_slope and view.uses_slope(id) and view.surface(id,x,z)) or
      (t.h or 0)+.5) or fallback
  end
  local function ramp(t,span,first,last)
    local u=t/span
    return first+(last-first)*u*u*(3-2*u),(last-first)*6*u*(1-u)/span
  end
  local function arch(t,span,deep,peak)
    local f=pi*t/span
    return deep+(peak-deep)*sin(f)^2,(peak-deep)*pi*sin(2*f)/span
  end
  -- Measured from the sea plane, not the animal's spawning height.
  -- Nose follows the tangent of the breach; approach and re-entry are
  -- continuous with underwater travel, not repeated shallow bobbing.
  local function swim(kind,elapsed,phase,d)
    local seed=phase/tau
    local whale=kind=="whale"
    local period=(whale and 21 or 6.7)+seed*(whale and 5.3 or 2.4)
    local full=elapsed+seed*period
    local t=full%period
    local y,speed,surfaced
    if whale then
      local rare=math.floor(full/period)%5==math.floor(seed*10)%5
      if rare then
        y,speed=-1.12,0
        if t>=4 and t<8.5 then y,speed=arch(t-4,4.5,-1.12,1.04) end
      elseif t>=4 and t<7.5 then
        y,speed=ramp(t-4,3.5,-1.12,-.097)
      elseif t>=7.5 and t<10.3 then
        y,speed=ramp(t-7.5,2.8,-.097,-.135)
        surfaced=true
      elseif t>=10.3 and t<14.5 then
        y,speed=ramp(t-10.3,4.2,-.135,-1.12)
      else y,speed=-1.12,0 end
    elseif t<2.18 then
      y,speed=arch(t,2.18,-.49,.73)
    else y,speed=-.49,0 end
    local limit=whale and .48 or .76
    local pitch=math.max(-limit,math.min(limit,-math.atan2(speed,d.velocity)))
    return y,pitch,surfaced
  end
  local function blow(x,y,z,yaw,pitch,d)
    if not core.add_particlespawner then return end
    -- Local blowholes are .825 forward and .18 above the model's
    -- origin, with the model pitching around its lateral axis.
    local forward=.825*cos(pitch)+.18*sin(pitch)
    y=y-.825*sin(pitch)+.18*cos(pitch)
    x,z=x-forward*sin(yaw),z+forward*cos(yaw)
    for watcher in pairs(observers) do
      local p=core.get_player_by_name(watcher)
      local viewer=p and p:get_pos()
      if viewer and distance(viewer,x,z)<d.view^2 then
        core.add_particlespawner({playername=watcher,amount=9,time=.17,collisiondetection=false,
          pos={min={x=x-.12,y=y+.045,z=z-.12},max={x=x+.12,y=y+.095,z=z+.12}},
          vel={min={x=-.2,y=.56,z=-.2},max={x=.2,y=1.1,z=.2}},
          acc={min={x=0,y=-1.8,z=0},max={x=0,y=-1.4,z=0}},
          exptime={min=.35,max=.65},size={min=.8,max=1.5},
          texture={name="bl_fountain_droplet.png",alpha_tween={.8,0}}})
      end
    end
  end
  local function render(a,dt,initial)
    local d=defs[a.kind]
    local elapsed=age-a.created
    local t=a.phase+elapsed*d.velocity/d.radius
    local radius=d.radius
    local yaw=math.atan2(-sin(t),cos(t))
    local x,z=a.x+radius*cos(t),a.z+radius*sin(t)
    local y,pitch,roll,variant=a.y,0,0,nil
    if a.kind=="whale" or a.kind=="porpoise" then
      local sea_tile=tile(x,z)
      if not sea(sea_tile,true) then return false end
      local offset,surfaced
      offset,pitch,surfaced=swim(a.kind,elapsed,a.phase,d)
      y=(sea_tile.h or 0)+.5+offset
      if surfaced and not a.surfaced then blow(x,y,z,yaw,pitch,d) end
      a.surfaced=surfaced
    elseif a.kind=="fox" then
      local ground,id=tile(x,z)
      if not field(ground,id) then return false end
      y=view.surface(id,x,z)+.012
      if math.floor(elapsed*4)%2==1 then variant="stride" end
    else
      local floor=height_at(x,z,a.y-5)
      local altitude=a.kind=="eagle" and 8.2 or 3.3
      local want=floor+altitude+(a.kind=="eagle" and 1.2 or .54)*sin(t*1.6)
      if a.previous_y then y=a.previous_y+math.max(-dt*.95,math.min(dt*.95,want-a.previous_y)) else y=want end
      y=math.max(y,floor+2.4)
      a.previous_y=y
      roll=a.kind=="eagle" and -.14 or -.23
      local cycle=elapsed% (a.kind=="eagle" and 4.4 or 2.4)
      if cycle<(a.kind=="eagle" and .92 or 1.25) then
        variant=math.floor(cycle*5)%2==0 and "wing_up" or "wing_down"
      end
    end
    if variant and not media[mesh(a.kind,variant)] then variant=nil end
    if variant~=a.variant then a.ref:set_properties({mesh=mesh(a.kind,variant)});a.variant=variant end
    a.ref:set_rotation({x=pitch,y=-yaw,z=roll})
    a.ref:move_to({x=x,y=y,z=z},not initial)
    return true
  end
  local function spawn(kind,x,z,phase)
    if kind=="fox" then
      local tx,tz=Sim.xy(select(2,tile(x,z)))
      x,z=2*tx+.5,2*tz+.5
    end
    local base=height_at(x,z,.5)
    if kind=="whale" or kind=="porpoise" then
      local t=tile(x,z)
      base=(t.h or 0)+.5
    elseif kind=="fox" then
      base=view.surface(select(2,tile(x,z)),x,z)
    else base=base+(kind=="eagle" and 8.2 or 3.3) end
    local ref=core.add_entity({x=x,y=base,z=z},name(kind))
    if not ref then return end
    if ref.set_observers then ref:set_observers(observers) end
    local a={ref=ref,x=x,z=z,y=base,kind=kind,created=age,phase=phase}
    if render(a,.2,true) then
      animals[#animals+1]=a
      local d=defs[kind]
      if d.rest then
        -- Longer pauses for individually scarce animals. Keep the
        -- cooldown local to where the encounter occurred, not the save
        -- or the viewer: sailing to new waters can reveal another one.
        encounters[#encounters+1]={x=x,z=z,kind=kind,until_=age+d.lifetime+d.rest}
        if #encounters>64 then table.remove(encounters,1) end
      end
      return true
    end
    ref:remove()
  end
  local function resting(kind,x,z,at,d)
    if not d.rest then return false end
    for _,e in ipairs(encounters) do
      if e.kind==kind and (distance(e,x,z)<d.view^2 or distance(e,at.x,at.z)<d.view^2) then return true end
    end
    return false
  end
  local function find(player,at)
    local n=player:get_player_name()
    local cursor=cursors[n] or 0
    local local_counts={}
    for _,a in ipairs(animals) do
      if distance(at,a.x,a.z)<defs[a.kind].view^2 then
        local_counts[a.kind]=(local_counts[a.kind] or 0)+1
      end
    end
    -- Sample a deterministic local ring. No map scans or network sector
    -- requests, and the next phase changes the tested offsets.
    for i=1,15 do
      local k=cursor+i
      local kind=ordered[(k-1)%#ordered+1]
      local d=defs[kind]
      local r=d.min+(d.view-d.min-9)*(((k*131)%89)/89)
      local theta=k*2.3999632297
      local x,z=at.x+r*cos(theta),at.z+r*sin(theta)
      if d.ready and #animals<7 and not local_counts[kind] and
          not resting(kind,x,z,at,d) and habitat(kind,x,z) and spawn(kind,x,z,theta%tau) then
        local_counts[kind]=1
      end
    end
    cursors[n]=(cursor+15)%445
  end
  function V.step(dt,players)
    age=age+math.min(.5,math.max(0,dt));update=update+dt;scans=scans+dt
    if update<.16 then return end
    local step=math.min(.4,update)
    update=0
    local viewers,active=Audience.capture(players,V.enabled)
    if not Audience.same_set(observers,active) then
      observers=active
      for _,a in ipairs(animals) do if a.ref:get_pos() and a.ref.set_observers then a.ref:set_observers(observers) end end
    end
    for n in pairs(cursors) do if not active[n] then cursors[n]=nil end end
    for i=#animals,1,-1 do
      local a=animals[i];local near=false
      local d=defs[a.kind]
      for _,p in ipairs(viewers) do
        if distance(p.at,a.x,a.z)<(d.view+9)^2 and math.abs(p.at.y-a.y)<60 then near=true;break end
      end
      local at=a.ref:get_pos()
      local retiring=not near or age-a.created>d.lifetime
      if not retiring then a.ambient_unseen=0 end
      if not at or retiring and Audience.retire(a,viewers,at,d.view+38,step) or not render(a,step) then remove(i) end
    end
    if scans<1.15 or #viewers==0 then return end
    scans=0
    for i=#encounters,1,-1 do
      if encounters[i].until_<=age then table.remove(encounters,i) end
    end
    for i=1,math.min(6,#viewers) do
      local p=viewers[(sector_cursor+i-1)%#viewers+1]
      find(p.player,p.at)
    end
    sector_cursor=(sector_cursor+6)%#viewers
  end
  local key="wildlife_hidden"
  function V.enabled(p) return p:get_meta():get_int(key)==0 end
  function V.toggle(p)
    local off=V.enabled(p)
    p:get_meta():set_int(key,off and 1 or 0)
    V.step(.16,core.get_connected_players())
    return true,off and "Decorative scenery hidden." or "Decorative scenery shown."
  end
  if core.register_chatcommand then core.register_chatcommand("candy",{
    description="Show or hide decorative wildlife, traffic and storms for yourself",
    func=function(n)
      local p=core.get_player_by_name(n)
      if p then return V.toggle(p) end
      return false,"Join the world first."
    end,
  }) end
  function V.count() return #animals end
  return V
end
