-- A local, reversible sightseeing car. It consumes the live road topology
-- but never buys a vehicle, changes a route, or writes to the company ledger.
return function(api,W)
  local Sim,S=api.Sim,api.s
  local function refresh_board()
    if api.authority_handoff and api.render.host_state then S=api.render.host_state()
    else S=api.s end
  end
  local path=core.get_modpath("luanttd_core")
  local Follow=dofile(path.."/openttd/yapf_road_follow.lua")
  local Lanes=dofile(path.."/road_lanes.lua")
  local C,players={},{}
  local entity="luanttd_core:sightseeing_car"
  local cabin,shell=entity.."_interior",entity.."_third_person"
  local function exterior_observers(q,join,leave)
    if not q.object:get_pos() or not q.interior:get_pos() or not q.shell:get_pos() then return end
    local keep={}
    for _,p in ipairs(core.get_connected_players()) do
      local n=p:get_player_name()
      if n~=q.name and n~=leave then keep[n]=true end
    end
    if join and join~=q.name then keep[join]=true end
    q.object:set_observers(keep)
  end
  -- World nodes per real second, calibrated against the stock MPS bus and
  -- mail truck on a straight road at normal simulation speed. Driving is
  -- local sightseeing, so pausing/fast-forwarding and builder E do not
  -- change the car's speed.
  local cruise_speed,reverse_speed=3.0,1.2
  local acceleration,reverse_acceleration,braking,coast=4.25,3.0,9.0,4.0
  local two_pi=2*math.pi
  local function wrap(y) return (y+math.pi)%two_pi-math.pi end
  local function opposite(d) return (d+1)%4+1 end
  local function yaw(d) local v=Sim.dir[d];return math.atan2(v[1],v[2]) end
  local function center(id) local x,z=Sim.xy(id);return 2*x+.5,2*z+.5 end
  local function tile(x,z) return Sim.id(math.floor((x+.5)/2),math.floor((z+.5)/2)) end
  local function span(id)
    local t=S.tiles[id]
    local b=t and t.road_bridge_id
    local u=t and t.road_tunnel_id
    if b then return S.stock_road_bridges[b],b,"bridge" end
    if u then return S.stock_road_tunnels[u],u,"tunnel" end
  end
  local function ordinary(id)
    local t=id and S.tiles[id]
    if not t then return false end
    return t.build=="road" or t.level_crossing
      or (t.build=="road_station" and t.stop_axis and not t.road_stop_pair)
  end
  local function access(id,d)
    local t=S.tiles[id]
    local restriction=t.road_disallowed or t.disallowed or 0
    if restriction==0 then return true end
    local td=Follow.direction_trackdir((4-d)%4)
    return Follow.has_trackdir(Follow.status({kind="road",roadtype=0,
      road_bits=Sim.road_bits(S,id),disallowed=restriction},false),td)
  end
  local function edge(id,d,active_span,check_gate)
    local t=S.tiles[id]
    if not t then return end
    local j=Sim.adjacent(id,d)
    if not j then return end
    if active_span then
      local book=active_span.kind=="bridge" and S.stock_road_bridges or S.stock_road_tunnels
      local p=book and book[active_span.key]
      local old=active_span.record
      if p and (p==old or api.authority_handoff and p.start==old.start and p["end"]==old["end"] and
        p.base==old.base and p.deck==old.deck and p.axis==old.axis)
        and (j==p.start or j==p["end"] or p.middle_by_tile and p.middle_by_tile[j]) then
        return j,{record=p,key=active_span.key,kind=active_span.kind}
      end
      return
    end
    local p,key,kind=span(id)
    if p then
      local head=id==p.start and p.head or p.tail
      if d==4-head.inside_direction then return j,{record=p,key=key,kind=kind} end
    end
    local n=S.tiles[j]
    if not (ordinary(j) or span(j)) or not (ordinary(id) or p)
      or not Sim.road_geometry_connected(S,id,d,j) or not access(id,d) or not access(j,d) then return end
    if check_gate and n.level_crossing and n.level_crossing.barred then return end
    return j
  end
  local function legal_tile(id)
    if not ordinary(id) or (S.tiles[id].level_crossing and S.tiles[id].level_crossing.barred) then return false end
    for d=1,4 do if edge(id,d) then return true end end
    return false
  end
  local function locate(p)
    local at=p:get_pos()
    local gaze=W.target(p)
    if gaze and legal_tile(gaze) then return gaze end
    local nearby=tile(at.x,at.z)
    if not nearby then return end
    local px,pz=Sim.xy(nearby)
    local found,best
    -- Bound the fallback to the nearby streets instead of teleporting
    -- across a huge map, and never spawn into an isolated road half-piece.
    for dz=-10,10 do
      for dx=-10,10 do
        local d=dx*dx+dz*dz
        if d<=100 and (not best or d<best) then
          local id=Sim.id(px+dx,pz+dz)
          if id and legal_tile(id) then found,best=id,d end
        end
      end
    end
    return found
  end
  local function first_heading(id,p)
    local look=p:get_look_dir()
    local forward,score
    for d,v in ipairs(Sim.dir) do
      local dot=v[1]*look.x+v[2]*look.z
      if (not score or dot>score) and edge(id,d) then forward,score=d,dot end
    end
    return forward
  end
  local function choose(q,keys,back)
    if q.span then
      local d=back and opposite(q.heading) or q.heading
      local next_id,next_span=edge(q.id,d,q.span,true)
      return d,next_id,next_span
    end
    local left=q.heading%4+1
    local right=(q.heading+2)%4+1
    local preferred=back and opposite(q.heading) or keys.left and left or keys.right and right or q.heading
    local id,structure=edge(q.id,preferred,nil,true)
    if id then return preferred,id,structure end
    if back then return end
    if preferred~=q.heading then
      id,structure=edge(q.id,q.heading,nil,true)
      if id then return q.heading,id,structure end
      return
    end
    -- Automatically follow a single bend, never choose an arbitrary exit
    -- at a junction. A driver can queue A or D before reaching its center.
    local l,ls=edge(q.id,left,nil,true)
    local r,rs=edge(q.id,right,nil,true)
    if l and not r then return left,l,ls end
    if r and not l then return right,r,rs end
  end
  local function height(id,x,z,layer)
    if layer then
      local s=layer.record
      if layer.kind=="tunnel" then return s.base+.52 end
      if s.middle_by_tile[id] then return s.deck+.52 end
    end
    return api.render.surface(id,x,z)+.02
  end
  local function pose(q)
    local x,z=center(q.id)
    local dx,dz=0,0
    local ground,layer=q.id,q.span
    if q.next_id then
      local bx,bz=center(q.next_id)
      dx,dz=bx-x,bz-z
      x,z=x+dx*q.progress,z+dz*q.progress
      ground=q.progress<.5 and q.id or q.next_id
      layer=q.next_span
    end
    local y=q.look
    local shiftx,shiftz=Lanes.offset(math.sin(y),math.cos(y))
    x,z=x+shiftx,z+shiftz
    local center_height=height(ground,x,z,layer)
    local fx,fz=math.sin(y),math.cos(y)
    -- Sample the actual front/rear contact patches of the .416-node
    -- wheelbase. Do not sample bare terrain beside an end of road and
    -- do not let an underlying road pull the car off a bridge deck.
    local axle=.2075
    local function contact(d)
      local ax,az=x+fx*d,z+fz*d
      local id=tile(ax,az)
      if id and (id==ground or ordinary(id) or layer and
          (id==layer.record.start or id==layer.record["end"] or layer.record.middle_by_tile[id])) then
        return height(id,ax,az,layer)
      end
    end
    local rear,front=contact(-axle),contact(axle)
    rear,front=rear or center_height,front or center_height
    return {x=x,y=(front+rear)*.5,z=z},math.atan2(front-rear,2*axle)
  end
  -- This private mesh has its pivot at the driver's eye, not the floor.
  -- Using a vertical eye_height would slide the eye through the dashboard
  -- in local space on grades. Keep it centered under the headliner and
  -- transform the exact seat offset with the chassis instead.
  local seat_x,seat_y,seat_z=-.007,.189,-.075
  local function seated(at,yaw,pitch)
    local x,z=math.sin(yaw),math.cos(yaw)
    local sin,cos=math.sin(pitch),math.cos(pitch)
    local depth=seat_z*cos-seat_y*sin
    return {x=at.x+depth*x+seat_x*z,y=at.y+seat_z*sin+seat_y*cos,z=at.z+depth*z-seat_x*x}
  end
  local function mount_pose(q,pitch)
    -- The car meshes point along local +Z. Positive Luanti object pitch
    -- raises that axis; player-look pitch below uses the opposite sign.
    local rotation={x=pitch,y=-q.look,z=0}
    q.object:set_rotation(rotation)
    q.interior:set_rotation(rotation)
  end
  local function status(p,q,waiting)
    local speed=math.floor(q.speed*14+.5)
    local msg=("Sightseeing car  ·  %d km/h%s  |  W drive  ·  A/D steer  ·  S brake/reverse  ·  Right-click or /car to exit"):
      format(speed,waiting and "  ·  No open road in that direction" or "")
    if msg~=q.message then
      q.message=msg
      if q.hud then p:hud_change(q.hud,"text",msg) end
    end
  end
  local function release(q,p)
    if q.shell and q.shell:get_pos() then q.shell:remove() end
    if p and q.attached and p:get_attach()==q.interior then p:set_detach() end
    if p and q.avatar_graphics then p:set_properties(q.avatar_graphics) end
    if p and q.hud then p:hud_remove(q.hud) end
    if q.interior and q.interior:get_pos() then q.interior:remove() end
    if q.object and q.object:get_pos() then q.object:remove() end
  end
  function C.active(p) return players[p:get_player_name()]~=nil end
  function C.leave(n)
    local q=players[n]
    if q then release(q,core.get_player_by_name(n));players[n]=nil end
  end
  local function toggle(p,selected,strict)
    refresh_board()
    local n=p:get_player_name()
    local existing=players[n]
    if existing then
      release(existing,p)
      players[n]=nil
      W.end_avatar(p,"car")
      return true,"Returned to builder view."
    end
    local id
    if strict then if selected and legal_tile(selected) then id=selected end
    else id=locate(p) end
    if not id then return false,"Aim at a connected road before entering the sightseeing car." end
    local state,why=W.begin_avatar(p,"car")
    if not state then return false,why or "Return to builder view before driving." end
    local heading=first_heading(id,p)
    local q={id=id,name=n,heading=heading,look=yaw(heading),progress=0,speed=0}
    local at,pitch=pose(q)
    q.object=core.add_entity(at,entity)
    q.interior=q.object and core.add_entity(seated(at,q.look,pitch),cabin)
    q.shell=q.interior and core.add_entity(at,shell)
    if not q.shell or not q.shell.set_observers or not q.interior.set_observers or not q.object.set_observers then
      release(q,p);W.end_avatar(p,"car")
      return false,"Could not create the private car cabin. Try again from a loaded road."
    end
    exterior_observers(q)
    q.interior:set_observers({[n]=true})
    q.shell:set_observers({[n]=true})
    mount_pose(q,pitch)
    q.pitch=pitch
    p:set_physics_override({gravity=0,speed=0,jump=0,sneak=false,speed_walk=0,speed_crouch=0})
    p:set_eye_offset({x=0,y=0,z=0},{x=.07,y=2.86,z=0},{x=.07,y=1.36,z=4})
    p:set_attach(q.interior,"",{x=0,y=0,z=0},{x=0,y=0,z=0},true)
    q.attached=true
    local graphics=p:get_properties()
    q.avatar_graphics={visual=graphics.visual,textures=graphics.textures,visual_size=graphics.visual_size}
    -- PlayerSAO keeps its own visual enabled for camera/attachment. Give it
    -- no visible pixels while mounted instead of hiding the parent/car.
    p:set_properties({eye_height=0,visual="sprite",textures={"bl_sightseeing_hidden_player.png"},
      visual_size={x=.001,y=.001,z=.001}})
    -- A non-forced child of the local player is hidden by Luanti only
    -- in first person; F7 shows the full exterior without a server poll.
    q.shell:set_attach(p,"",{x=-seat_x*10,y=-seat_y*10,z=-seat_z*10},{x=0,y=0,z=0},false)
    p:set_look_horizontal(-q.look);p:set_look_vertical(.07-pitch)
    q.hud=p:hud_add({type="text",position={x=.5,y=.94},alignment={x=0,y=0},
      text="",number=0xffe3a3,z_index=105})
    players[n]=q
    status(p,q)
    return true,"You're in a car. W drives, A/D steer, S brakes or reverses; right-click or /car to get out."
  end
  function C.toggle(p) return toggle(p,nil,false) end
  function C.toggle_at(p,tile) return toggle(p,tile,true) end
  function C.step(p,_,keys,dt)
    refresh_board()
    local name=p:get_player_name()
    local q=players[name]
    if not q then return end
    if api.authority_handoff and (not S.tiles[q.id] or q.next_id and not S.tiles[q.next_id]) then
      q.speed=0;status(p,q,true);return
    end
    if not q.object:get_pos() or not q.interior:get_pos() or not q.shell:get_pos() then
      C.toggle(p)
      core.chat_send_player(name,"The car disappeared; returned to builder view.")
      return
    end
    local drive=keys.up and not keys.down
    local brake=keys.down and not keys.up
    local waiting=false
    if not drive and not brake then
      q.speed=math.max(0,q.speed-coast*dt)
    elseif brake and not q.reversing and q.speed>0 then
      q.speed=math.max(0,q.speed-braking*dt)
    elseif drive and q.reversing and q.next_id then
      -- Break out of reverse without cutting across a corner or teleporting.
      q.speed=math.max(.65,q.speed-braking*dt)
    else
      q.speed=math.min(brake and reverse_speed or cruise_speed,q.speed+(brake and reverse_acceleration or acceleration)*dt)
    end
    local distance=q.speed*dt
    while distance>0 do
      if not q.next_id then
        if not drive and not brake then break end
        local reverse=not not brake
        local d,id,layer=choose(q,keys,reverse)
        if not id then q.speed=0;waiting=true;break end
        q.next_id,q.next_span,q.progress=id,layer,0
        q.reversing=reverse
        if not reverse then q.heading=d end
        q.direction=d
      else
        -- A pedestrian can edit this world while driving. If a segment is
        -- removed mid-drive, return to builder, not onto dirt or into water.
        local expect=edge(q.id,q.direction,q.span,false)
        if expect~=q.next_id then
          C.toggle(p)
          core.chat_send_player(name,"Road changed under the car; returned to builder view.")
          return
        end
        if q.progress<.5 and not q.next_span and not edge(q.id,q.direction,q.span,true) then
          q.speed=0;waiting=true;break
        end
      end
      local remaining=2*(1-q.progress)
      local amount=math.min(distance,remaining)
      q.progress=q.progress+amount/2
      if q.progress>=1-1e-8 then
        q.id=q.next_id
        q.span=q.next_span
        if q.span and (q.id==q.span.record.start or q.id==q.span.record["end"]) then q.span=nil end
        q.next_id,q.next_span,q.progress=nil,nil,0
      end
      distance=distance-amount
    end
    local delta=wrap(yaw(q.heading)-q.look)
    local change=math.max(-7*dt,math.min(7*dt,delta))
    q.look=wrap(q.look+change)
    local at,pitch=pose(q)
    q.object:move_to(at,true)
    q.interior:move_to(seated(at,q.look,pitch),true)
    mount_pose(q,pitch)
    -- Turn the driver's view with the chassis while retaining mouse look.
    if math.abs(change)>.0001 then p:set_look_horizontal((p:get_look_horizontal()-change)%two_pi) end
    if math.abs(pitch-q.pitch)>.0001 then
      local tilt=math.max(-math.pi/2,math.min(math.pi/2,p:get_look_vertical()+q.pitch-pitch))
      p:set_look_vertical(tilt)
    end
    q.pitch=pitch
    status(p,q,waiting)
  end
  local function register_exterior(id)
    core.register_entity(id,{initial_properties={
      physical=false,collide_with_objects=false,pointable=false,visual="mesh",
      mesh="bl_sightseeing_car.obj",textures={"bl_sightseeing_car_palette.png"},
      visual_size={x=1,y=1,z=1},static_save=false}})
  end
  register_exterior(entity)
  register_exterior(shell)
  core.register_entity(cabin,{initial_properties={
    physical=false,collide_with_objects=false,pointable=false,visual="mesh",
    mesh="bl_sightseeing_car_interior.obj",textures={"bl_sightseeing_car_interior_atlas.png"},
    backface_culling=false,visual_size={x=1,y=1,z=1},static_save=false}})
  core.register_on_joinplayer(function(p)
    for _,q in pairs(players) do exterior_observers(q,p:get_player_name()) end
  end)
  core.register_on_leaveplayer(function(p)
    local n=p:get_player_name()
    for other,q in pairs(players) do if other~=n then exterior_observers(q,nil,n) end end
  end)
  core.register_chatcommand("car",{description="Drive a sightseeing car on the roads; use again to return to building.",
    func=function(name)
      local p=core.get_player_by_name(name)
      if not p then return false,"Join the world before driving." end
      return C.toggle(p)
    end})
  return C
end
