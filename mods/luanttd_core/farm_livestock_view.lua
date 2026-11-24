-- SPDX-License-Identifier: GPL-2.0-only
-- The livestock are part of the authored farm presentation, not stock,
-- cargo, collision, or an additional simulation/worker subscription.
return function(core,Sim,view)
  local V={}
  local sin,cos,pi=math.sin,math.cos,math.pi
  local tau=2*pi
  local cap,enter,leave,details=4,28,34,19
  local timer,clock,next_scan=0,0,0
  local by_pen={}
  local styles={"cream","brown","pig"}
  local palette="bl_industry_farm_atlas.png"
  local function mesh(style,pose) return "bl_farm_animal_"..style.."_"..pose..".obj" end
  local function entity(style) return "luanttd_core:farm_livestock_"..style end
  -- These ellipses follow the two north/south fenced paddocks authored
  -- in build_stock_farm_art.py. Each ranges over its own piece of pasture
  -- and keeps hoof/head clearance from the fence, troughs, and neighbors.
  local lanes={
    {kind="cream",x=4.27,z=2.18,rx=.25,rz=.14,seconds=15.8,offset=.08},
    {kind="brown",x=4.76,z=2.94,rx=.22,rz=.085,seconds=16.9,offset=.53},
    {kind="cream",x=4.92,z=4.76,rx=.10,rz=.29,seconds=17.7,offset=.31},
    {kind="pig",x=4.18,z=4.23,rx=.20,rz=.16,seconds=13.2,offset=.69},
    {kind="pig",x=4.16,z=4.86,rx=.21,rz=.16,seconds=12.5,offset=.38},
  }
  for _,style in ipairs(styles) do
    core.register_entity(entity(style),{initial_properties={
      visual="mesh",mesh=mesh(style,"idle"),textures={palette},
      visual_size={x=1,y=1,z=1},shaded=true,physical=false,
      collide_with_objects=false,pointable=false,static_save=false,
    }})
  end
  local function close(at,h,r)
    local dx,dz=at.x-h.x-4.5,at.z-h.z-3.5
    return dx*dx+dz*dz<r*r and math.abs(at.y-h.y)<r
  end
  local function sample(row,time,offset)
    -- Alternate grazing pauses and eased departures; the pace, timing,
    -- orientation, and separate footprints make a non-marching herd.
    local t=((time/row.seconds+row.offset+offset)%1)*4
    local q=math.floor(t)
    local f=t-q
    local run=math.min(1,f/.78)
    local smooth=run*run*(3-2*run)
    local a=(q+smooth)*tau/4
    local dx,dz=-row.rx*sin(a),row.rz*cos(a)
    local gait="idle"
    if run>.05 and run<.95 then
      gait=math.floor((f*row.seconds*.25+.069*offset)*4)%2==0 and "step_a" or "step_b"
    end
    return row.x+row.rx*cos(a),row.z+row.rz*sin(a),-math.atan2(dx,dz),gait
  end
  local function advance(herd,member,near)
    local dx,dz,yaw,gait=sample(member.lane,clock,herd.offset)
    local pos={x=herd.x+dx,y=herd.y,z=herd.z+dz}
    local ref=member.ref
    if not ref or not ref:get_pos() then
      ref=core.add_entity(pos,entity(member.lane.kind))
      if not ref then return false end
      member.ref,member.gait=ref,"idle"
      ref:set_yaw(yaw)
    else
      ref:move_to(pos,true)
      ref:set_yaw(yaw)
    end
    if not near then gait="idle" end
    if member.gait~=gait then
      ref:set_properties({mesh=mesh(member.lane.kind,gait)})
      member.gait=gait
    end
    return true
  end
  local function stop(id)
    for _,member in ipairs(by_pen[id].members) do
      local ref=member.ref
      if ref and ref:get_pos() then ref:remove() end
    end
    by_pen[id]=nil
  end
  local function pen(id,tx,tz)
    local row=view.host_tile(id)
    local b=row and row.stock_industry
    if not b or b.chain~="farm" or b.kind~="farm" or b.style~="industry_farm" or b.x~=2 or b.z~=1 then return end
    local owner=view.host_record("stock_farm_industries",b.id)
    if not owner or owner.removed then return end
    local level=view.host_terrain_top(id)
    if not level then return end
    -- An authority projection can arrive before its local mapblocks.
    -- Never draw cattle floating over a farm that is not yet painted.
    local north=core.get_node_or_nil({x=2*tx,y=level+1,z=2*tz})
    local south=core.get_node_or_nil({x=2*tx,y=level+1,z=2*tz+2})
    if not north or north.name~="luanttd_core:industry_farm_2_1" or
       not south or south.name~="luanttd_core:industry_farm_2_2" then return end
    return {key=b.id,tx=tx,tz=tz,x=2*(tx-2),y=level+.5+.026,z=2*(tz-1),offset=(id%1249)/1249}
  end
  local function scan(players)
    local count=0
    for id,herd in pairs(by_pen) do
      local near=false
      for _,p in ipairs(players) do
        if close(p,herd,leave) then near=true;break end
      end
      local current=near and pen(id,herd.tx,herd.tz)
      if not current or current.key~=herd.key or current.y~=herd.y then stop(id)
      else count=count+1 end
    end
    if count>=cap or #players==0 then return end
    local candidates,seen={},{}
    -- Terrain is already loaded around the viewers. A hard local scan
    -- budget counts both failed tiles and successful pens, and rotates
    -- which viewers seed discovery on busy multiplayer worlds.
    for j=1,math.min(4,#players) do
      local p=players[(j+next_scan-1)%#players+1]
      local u,v=math.floor((p.x+.5)/2),math.floor((p.z+.5)/2)
      for z=math.max(1,v-15),math.min(Sim.H,v+15) do
        for x=math.max(1,u-15),math.min(Sim.W,u+15) do
          local id=Sim.id(x,z)
          if not by_pen[id] and not seen[id] then
            seen[id]=true
            local t=pen(id,x,z)
            if t then candidates[#candidates+1]={id=id,pen=t} end
          end
        end
      end
    end
    next_scan=(next_scan+4)%#players
    local nearby={}
    for _,q in ipairs(candidates) do
      local best=math.huge
      for _,p in ipairs(players) do
        if close(p,q.pen,enter) then
          local dx,dz=p.x-q.pen.x-4.5,p.z-q.pen.z-3.5
          best=math.min(best,dx*dx+dz*dz+(p.y-q.pen.y)^2)
        end
      end
      if best<math.huge then q.distance=best;nearby[#nearby+1]=q end
    end
    table.sort(nearby,function(a,b)
      return a.distance<b.distance or a.distance==b.distance and a.id<b.id
    end)
    for i=1,math.min(cap-count,#nearby) do
      local q=nearby[i]
      q.pen.members={}
      for _,lane in ipairs(lanes) do q.pen.members[#q.pen.members+1]={lane=lane} end
      by_pen[q.id]=q.pen
    end
  end
  local function positions(players)
    local out={}
    for _,p in ipairs(players) do
      local at=p:get_pos()
      if at then out[#out+1]=at end
    end
    return out
  end
  local scan_timer=1
  function V.step(dt,players)
    if #players==0 then
      for id in pairs(by_pen) do stop(id) end
      scan_timer=1;timer=0
      return
    end
    dt=math.min(.4,math.max(0,dt))
    clock=clock+dt;timer=timer+dt;scan_timer=scan_timer+dt
    if timer<.17 then return end
    timer=0
    local at=positions(players)
    if scan_timer>=.85 then scan_timer=0;scan(at) end
    for _,herd in pairs(by_pen) do
      local near=false
      for _,p in ipairs(at) do if close(p,herd,details) then near=true;break end end
      for _,member in ipairs(herd.members) do advance(herd,member,near) end
    end
  end
  return V
end
