-- Viewer-local sprites for the real stop queue. Cosmetic randomness never
-- feeds the simulation. A sprite is stationary for its entire lifetime.
return function(api)
  local Crowd={}
  local Sim,S=api.Sim,api.s
  local Zones=Sim.commercial_passengers_waiting and
    dofile(core.get_modpath("luanttd_core").."/passenger_waiting_zones.lua")(api)
  local worker_projection
  local state_by_player={}
  local clock,scan_due=0,0
  local platforms={}
  local pending_boardings={}
  local SCAN_INTERVAL=.10
  local DRAW_RADIUS=32
  local DRAW_HEIGHT=24
  local MAX_VISIBLE_STOPS=4
  local MAX_ACTIVE=128
  local ALONG_SPACING=.102
  local SIDE_SPACING=.090
  local END_MARGIN=.048
  local SIDE_MARGIN=.036
  local FADE_TIME=.36
  local offsets={road=0,rail=1048576,ship=2097152,air=3145728}

  local function normalize(v)
    if not v then return nil end
    local norm=math.sqrt(v.x*v.x+v.z*v.z)
    if norm==0 then return nil end
    return {x=v.x/norm,z=v.z/norm}
  end

  local function layout(p)
    if not p or p.length<2*END_MARGIN or p.width<2*SIDE_MARGIN then return nil end
    local along,side=normalize(p.along),normalize(p.side)
    if not along or not side or math.abs(along.x*side.x+along.z*side.z)>.001 then return nil end
    local cols=math.floor((p.length-2*END_MARGIN)/ALONG_SPACING)+1
    local rows=math.floor((p.width-2*SIDE_MARGIN)/SIDE_SPACING)+1
    local result={}
    for row=1,rows do
      local across=(row-(rows+1)/2)*SIDE_SPACING
      for col=1,cols do
        local forward=(col-(cols+1)/2)*ALONG_SPACING
        if not p.slot_ok or p.slot_ok(forward,across) then
          result[#result+1]={forward=forward,across=across,order=0}
        end
      end
    end
    -- Mix both rows, but start near the visible center. Keep the seat
    -- ordering fixed so a queue change only adds/removes its tail.
    for _,slot in ipairs(result) do
      slot.order=math.abs(slot.forward)+math.abs(slot.across)*.52+slot.across*.20
    end
    table.sort(result,function(a,b)
      return a.order<b.order or (a.order==b.order and a.forward<b.forward)
    end)
    for _,seat in ipairs(result) do seat.p,seat.along,seat.side=p,along,side end
    return result
  end

  local function waiting(mode,id)
    if worker_projection then return worker_projection.waiting(mode,id) end
    if mode=="road" then
      local st=S.stations[id]
      local at=st and (st.bus_tile or st.tile)
      local tile=at and S.tiles[at]
      if st and st.mode=="road" and st.stop_type~="truck" and tile and tile.build=="road_station" and tile.station==id then
        return Sim.waiting_passengers(S,st)
      end
    elseif Zones then
      local records=mode=="rail" and S.stock_rail_stations or mode=="ship" and S.stock_ship_stations or S.stock_small_airports
      if records and records[id] then return Sim.commercial_passengers_waiting(S,mode,id) end
    end
    return 0
  end
  local function add(mode,id,rectangles,count)
    local rows,positions,slots={},{},{}
    for _,rect in ipairs(rectangles or {}) do
      local seats=layout(rect)
      if seats and #seats>0 then
        rows[#rows+1]=seats
        positions[#positions+1]=rect
      end
    end
    -- Use the whole waiting area on a long station by filling the
    -- rows evenly. A viewer's hard cap also bounds each station's sample.
    count=math.min(MAX_ACTIVE,math.floor(count))
    local index=1
    while #slots<count do
      local before=#slots
      for _,r in ipairs(rows) do
        if r[index] then slots[#slots+1]=r[index] end
        if #slots==count then break end
      end
      if #slots==before then break end
      index=index+1
    end
    if #slots>0 then
      platforms[#platforms+1]={id=id,key=offsets[mode]+id,mode=mode,slots=slots,positions=positions,count=#slots}
    end
  end
  local function scan()
    platforms={}
    for id,st in pairs(S.stations) do
      local count=waiting("road",id)
      if count>0 then add("road",id,{api.render.platform(st)},count) end
    end
    if not Zones then return end
    for _,m in ipairs({{"rail",S.stock_rail_stations},{"ship",S.stock_ship_stations},{"air",S.stock_small_airports}}) do
      for id in pairs(m[2] or {}) do
        local count=waiting(m[1],id)
        if count>0 then add(m[1],id,Zones[m[1]](id),count) end
      end
    end
  end

  -- Local, reproducible dispersion not affected by engine RNG or gameplay.
  local function rand(seed)
    return ((seed*48271)%2147483647+1)/2147483647
  end

  local function spawn(name,id,index,rec,slot,fade)
    if not fade then
      local p,a,b=slot.p,slot.along,slot.side
      rec.generation=rec.generation+1
      local seed=((id*7480739+index*747323+rec.generation*111200423)%2147483646)+1
      local f=slot.forward+(rand(seed)-.5)*.044
      local s=slot.across+(rand((seed*16807)%2147483647)-.5)*.032
      rec.pos={x=p.x+f*a.x+s*b.x,y=p.y+.004+rec.tall*.5,z=p.z+f*a.z+s*b.z}
    end
    local life=fade and FADE_TIME or .41+rand(id*23017+index*5129+rec.generation*977)*.15
    -- Single Luanti particles cannot be removed or edited. At the end of
    -- its opaque lease a removed rider is replaced exactly once, in the
    -- same spot, by a short fading particle instead of another live one.
    local texture=rec.texture
    if fade then texture={name=texture,alpha_tween={1,0}} end
    core.add_particle({
      pos=rec.pos,velocity={x=0,y=0,z=0},acceleration={x=0,y=0,z=0},
      expirationtime=life,size=rec.tall*10,vertical=true,
      collisiondetection=false,glow=1,texture=texture,playername=name,
    })
    rec.expires=clock+life
    rec.fading=fade
    rec.boarded=nil
  end

  local function render(player)
    local name=player:get_player_name()
    local from=player:get_pos()
    if not from then return end
    local tracked=state_by_player[name]
    if not tracked then tracked={};state_by_player[name]=tracked end

    local nearby={}
    for _,entry in ipairs(platforms) do
      local distance=math.huge
      for _,p in ipairs(entry.positions) do
        local dx,dy,dz=p.x-from.x,p.y-from.y,p.z-from.z
        if math.abs(dy)<=DRAW_HEIGHT then distance=math.min(distance,dx*dx+dy*dy+dz*dz) end
      end
      if distance<=DRAW_RADIUS*DRAW_RADIUS then
        nearby[#nearby+1]={dist=distance,entry=entry}
      end
    end
    table.sort(nearby,function(a,b)
      return a.dist<b.dist or (a.dist==b.dist and a.entry.key<b.entry.key)
    end)
    local targets={}
    for i=1,math.min(MAX_VISIBLE_STOPS,#nearby) do
      local station=nearby[i].entry
      targets[station.key]=station
    end

    local active,departed=0,{}
    for id,bucket in pairs(tracked) do
      local target=targets[id]
      for seat,rec in pairs(bucket) do
        if clock<rec.expires then active=active+1
        elseif rec.boarded and not rec.fading then
          departed[#departed+1]={id=id,seat=seat,rec=rec}
        elseif not target or seat>target.count then
          if not rec.fading then departed[#departed+1]={id=id,seat=seat,rec=rec} end
          bucket[seat]=nil
        end
      end
      if not next(bucket) then tracked[id]=nil end
    end

    -- Live queues take precedence over transient fades and distant stops.
    for i=1,math.min(MAX_VISIBLE_STOPS,#nearby) do
      local station=nearby[i].entry
      local bucket=tracked[station.key] or {}
      tracked[station.key]=bucket
      for seat=1,station.count do
        local rec=bucket[seat]
        if active<MAX_ACTIVE and (not rec or not rec.boarded and clock>=rec.expires) then
          if not rec then
            local kind=(station.key*31+seat*11)%6
            rec={generation=0,tall=.18+kind*.006,texture="bl_waiting_"..(kind+1)..".png",
              mode=station.mode,id=station.id}
            bucket[seat]=rec
          end
          spawn(name,station.key,seat,rec,station.slots[seat],false)
          active=active+1
        end
      end
    end
    for _,p in ipairs(departed) do
      if active<MAX_ACTIVE then
        local pos=p.rec.pos
        local dx,dy,dz=pos.x-from.x,pos.y-from.y,pos.z-from.z
        if dx*dx+dy*dy+dz*dz<=DRAW_RADIUS*DRAW_RADIUS and math.abs(dy)<=DRAW_HEIGHT and
            (p.rec.boarded or waiting(p.rec.mode,p.rec.id)<p.seat) then
          local bucket=tracked[p.id] or {}
          tracked[p.id]=bucket
          bucket[p.seat]=p.rec
          spawn(name,p.id,p.seat,p.rec,nil,true)
          active=active+1
        else
          p.rec.boarded=nil
        end
      else
        p.rec.boarded=nil
      end
    end
  end

  local function apply_boarding(event)
    local remaining=waiting(event.mode,event.id)
    for _,tracked in pairs(state_by_player) do
      local bucket=tracked[event.key]
      if bucket then
        local active,pending={},0
        for seat,rec in pairs(bucket) do
          if not rec.fading then
            if rec.boarded then pending=pending+1 else active[#active+1]=seat end
          end
        end
        if #active>0 then
          -- Draw a proportional boarding sample even when hundreds are
          -- waiting and the finite curb remains full after a bus visit.
          local fraction=event.units/math.max(1,remaining+event.units)
          local n=math.max(#active-remaining,math.floor((#active+pending)*fraction+.5),1)
          table.sort(active,function(a,b) return a>b end)
          for i=1,math.min(n,#active) do bucket[active[i]].boarded=true end
        end
      end
    end
  end
  function Crowd.board_terminal(mode,id,units)
    if not id or units<=0 then return end
    local key=offsets[mode]+id
    local event=pending_boardings[key]
    if event then event.units=event.units+units
    else pending_boardings[key]={key=key,mode=mode,id=id,units=units} end
  end
  function Crowd.board(station,units) Crowd.board_terminal("road",station.id,units) end

  function Crowd.use_worker_projection(projection,scene,terrain)
    if not worker_projection and Zones then
      Zones=dofile(core.get_modpath("luanttd_core").."/passenger_waiting_zones.lua")({
        s=scene,Sim=Sim,terrain=terrain,trackworks=api.trackworks,
      })
    end
    worker_projection=projection
    S=scene
    for _,e in ipairs(projection.take_boardings()) do Crowd.board_terminal(e.mode,e.id,e.units) end
    scan_due=clock
  end
  function Crowd.update(players,dt)
    clock=clock+dt
    -- Gradual loading can emit many pulses in one render frame. They
    -- share its final queue count, so sampling each separately would
    -- fade the same reduced crowd multiple times.
    if next(pending_boardings) then
      for _,event in pairs(pending_boardings) do apply_boarding(event) end
      pending_boardings={}
      scan_due=clock
    end
    if clock>=scan_due then
      scan_due=clock+SCAN_INTERVAL
      scan()
    end
    for _,player in ipairs(players) do render(player) end
  end

  function Crowd.leave(name)
    state_by_player[name]=nil
  end
  return Crowd
end
