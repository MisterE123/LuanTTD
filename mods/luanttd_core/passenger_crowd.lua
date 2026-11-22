-- Viewer-local sprites for the real stop queue. Cosmetic randomness never
-- feeds the simulation. A sprite is stationary for its entire lifetime.
return function(api)
  local Crowd={}
  local Sim,S=api.Sim,api.s
  local state_by_player={}
  local clock,scan_due=0,0
  local platforms={}
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
    return {p=p,slots=result,along=along,side=side}
  end

  local function scan()
    platforms={}
    for id,st in pairs(S.stations) do
      local tile=S.tiles[st.tile]
      if st.mode=="road" and tile and tile.build=="road_station" and tile.station==id then
        local count=Sim.waiting_passengers(S,st)
        local map=count>0 and layout(api.render.platform(st))
        if map then
          platforms[#platforms+1]={id=id,map=map,count=math.min(math.floor(count),#map.slots)}
        end
      end
    end
  end

  -- Local, reproducible dispersion not affected by engine RNG or gameplay.
  local function rand(seed)
    return ((seed*48271)%2147483647+1)/2147483647
  end

  local function spawn(name,id,index,rec,map,fade)
    if not fade then
      local seat=map.slots[index]
      local p,a,b=map.p,map.along,map.side
      rec.generation=rec.generation+1
      local seed=((id*7480739+index*747323+rec.generation*111200423)%2147483646)+1
      local f=seat.forward+(rand(seed)-.5)*.044
      local s=seat.across+(rand((seed*16807)%2147483647)-.5)*.032
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
      local p=entry.map.p
      local dx,dy,dz=p.x-from.x,p.y-from.y,p.z-from.z
      local distance=dx*dx+dy*dy+dz*dz
      if math.abs(dy)<=DRAW_HEIGHT and distance<=DRAW_RADIUS*DRAW_RADIUS then
        nearby[#nearby+1]={dist=distance,entry=entry}
      end
    end
    table.sort(nearby,function(a,b)
      return a.dist<b.dist or (a.dist==b.dist and a.entry.id<b.entry.id)
    end)
    local targets={}
    for i=1,math.min(MAX_VISIBLE_STOPS,#nearby) do
      local station=nearby[i].entry
      targets[station.id]=station
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
      local bucket=tracked[station.id] or {}
      tracked[station.id]=bucket
      for seat=1,station.count do
        local rec=bucket[seat]
        if active<MAX_ACTIVE and (not rec or not rec.boarded and clock>=rec.expires) then
          if not rec then
            local kind=(station.id*31+seat*11)%6
            rec={generation=0,tall=.18+kind*.006,texture="bl_waiting_"..(kind+1)..".png"}
            bucket[seat]=rec
          end
          spawn(name,station.id,seat,rec,station.map,false)
          active=active+1
        end
      end
    end
    for _,p in ipairs(departed) do
      local st=S.stations[p.id]
      if st and active<MAX_ACTIVE then
        local pos=p.rec.pos
        local dx,dy,dz=pos.x-from.x,pos.y-from.y,pos.z-from.z
        if dx*dx+dy*dy+dz*dz<=DRAW_RADIUS*DRAW_RADIUS and math.abs(dy)<=DRAW_HEIGHT and
            (p.rec.boarded or Sim.waiting_passengers(S,st)<p.seat) then
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

  function Crowd.board(station,units)
    local remaining=Sim.waiting_passengers(S,station)
    for _,tracked in pairs(state_by_player) do
      local bucket=tracked[station.id]
      if bucket then
        local active={}
        for seat,rec in pairs(bucket) do
          if not rec.fading then active[#active+1]=seat end
        end
        local sampled=#active
        if sampled>0 then
          -- Draw a proportional boarding sample even when hundreds are
          -- waiting and the finite curb remains full after a bus visit.
          local fraction=units/math.max(1,remaining+units)
          local n=math.max(sampled-remaining,math.floor(sampled*fraction+.5),1)
          table.sort(active,function(a,b) return a>b end)
          for _,seat in ipairs(active) do
            if n<=0 then break end
            if not bucket[seat].boarded then bucket[seat].boarded=true;n=n-1 end
          end
        end
      end
    end
    scan_due=clock
  end

  function Crowd.update(players,dt)
    clock=clock+dt
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
