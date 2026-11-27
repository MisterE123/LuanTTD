-- Applies the stock passing row to the live actor. The normal route
-- samples retain pathfinding, station, grade and structure metadata.
-- This adapter only enables starts whose full active window can be run
-- through aligned, straight, ordinary pavement with live occupancy.
return function(Motion,O,Follow,make_board)
  local P={}
  local abs,floor=math.abs,math.floor
  local function straight(td) return td==0 or td==1 or td==8 or td==9 end
  local function same(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
  local function complete(f)
    return f and f[15]~=nil and straight(f[6]) and f[7]==nil and f[8]==nil and
      f[10]==nil and not f[12] and not f[14] and f[3]%2==1
  end
  local function coordinates(frame)
    return floor(frame[1]/16),floor(frame[2]/16)
  end
  local function candidate(before,after)
    if not complete(after) or before[6]~=after[6] or before[3]~=after[3] then return false end
    if before[4]==after[4] then return after[15]==before[15]+1 end
    return after[15]==Motion.DEFAULT_START and
      Motion.sample(before[6],1,before[15]+1)=="next_tile"
  end
  local function play(actor,target,side)
    local kind,x,y,d,f
    if target[4]==actor.tile then
      kind,x,y,d,f=O.next_pose(Motion,actor,side)
    else
      local tx,ty=coordinates(target)
      kind,x,y,d,f=O.enter_pose(Motion,actor,tx,ty,target[6],side,target[15])
    end
    if (kind=="move" or kind=="enter") and f==target[15] and d==target[3] then
      return x,y,d
    end
  end
  local function actor(v,c,old,max_speed)
    return {id=v.id,first=v.id,type="road",tile=old[4],x=old[1],y=old[2],direction=old[3],state=old[6],
      frame=old[15],speed=c.speed,max_speed=max_speed,overtaking=c.overtaking,overtaking_ctr=c.overtaking_ctr,
      articulated=v.articulated or v.has_articulated,compatible={[0]=true}}
  end
  function P.board(s,W)
    local real=make_board(s)
    return {real=real,rule=O.plain_board(Follow,real,W.vehicles_at)}
  end
  function P.active(c) return O.active(c) end
  local function verified_step(board,previous,wanted)
    if not candidate(previous,wanted) then return false end
    local t=board.real.tile(wanted[4])
    if not t or t.kind~="road" or t.roadtype~=0 then return false end
    local td=wanted[6]
    local bits=Follow.status(t,false)
    if not Follow.has_trackdir(bits,td) or floor(bits/4)%16~=0 or floor(bits/1024)%16~=0 then return false end
    if previous[4]~=wanted[4] then
      local dir=floor(previous[3]/2)
      return board.real.adjacent(previous[4],dir)==wanted[4] and
        (not board.real.edge_available or board.real.edge_available(previous[4],wanted[4],dir))
    end
    return true
  end
  function P.control(v,c,board,frames,base,max_speed,leader,leader_speed,leader_limit)
    -- The early exact controller copied speed only if no pass was active
    -- when the probe gate ran. Keep the normal runtime's same rule.
    if P.active(c) then return false end
    if not board or not complete(base) or not leader.frame or not leader.max_speed or
       not complete(leader.frame) or c.lane_pose then
      c.speed=leader_speed
      return false
    end
    local a=actor(v,c,base,max_speed)
    local b={id=leader.id,tile=leader.tile,direction=leader.direction,speed=leader_speed,
      max_speed=leader_limit,stopped=leader.stopped}
    local allowed,seed=O.check(board.rule,a,b,true)
    if not allowed then c.speed=leader_speed;return false end

    -- The 14.1 predicate only checks current and next for traffic. Require
    -- aligned ordinary drive frames through the worst-case step horizon
    -- before entering the native passing phase, so the adapter cannot run
    -- active into a missing row, a stop, a span, or an unsupported corner.
    local last=base
    for i=c.index+1,c.index+O.TIMEOUT-seed do
      local next=frames[i]
      if not verified_step(board,last,next) then c.speed=leader_speed;return false end
      last=next
    end
    c.overtaking,c.overtaking_ctr=O.DRIVE_SIDE,seed
    c.last_overtake_kind=seed==0 and "moving" or "stopped"
    c.overtakes=(c.overtakes or 0)+1
    return true
  end

  function P.next(v,c,previous,wanted,max_speed,board)
    local passing=O.active(c)
    if not passing and not c.lane_pose then return wanted end
    local a=actor(v,c,previous,max_speed)
    if passing then O.before_step(a,board.rule.is_station(previous[4])) end
    c.overtaking,c.overtaking_ctr=a.overtaking,a.overtaking_ctr
    if not O.active(a) and not c.lane_pose then return wanted end
    if not verified_step(board,previous,wanted) then
      -- Save migration or external topology change invalidated the
      -- straight run. Stop rather than silently teleport across lanes.
      return nil
    end
    local x,y,d=play(a,wanted,1)
    if not x then return nil end
    if x==wanted[1] and y==wanted[2] and d==wanted[3] then return wanted end
    local out={}
    for k,value in pairs(wanted) do out[k]=value end
    out[1],out[2],out[3]=x,y,d
    return out
  end
  function P.accept(c,pose,base)
    if same(pose,base) then
      if c.lane_pose then c.overtake_returns=(c.overtake_returns or 0)+1 end
      c.lane_pose=nil
    else
      c.lane_pose=pose
    end
  end

  -- Host-only anti-overlap guard. Stock never predicts a road user
  -- arriving beyond the two initial tiles; don't let one occupy the
  -- wrong-way actor's same lane. Returning also checks the blind side.
  local function obstruct(u,id,x,y,z,d,horizontal,exposed,changed)
    if u.id==id or u.type~="road" or abs(u.z-z)>=6 then return false end
    local along=horizontal and abs(u.x-x) or abs(u.y-y)
    local across=horizontal and abs(u.y-y) or abs(u.x-x)
    if along>=8 or across>1 then return false end
    return ((exposed or u.opposite_lane) and (u.direction-d)%8==4) or
      (changed and u.direction==d)
  end
  function P.clear(W,record,from,to,nominal,z)
    local changed=not same(from,to) and
      (to[3]%4==1 and from[2]~=to[2] or to[3]%4==3 and from[1]~=to[1])
    local exposed=not same(to,nominal)
    local d=to[3]
    if d%2~=1 then return true end
    local x,y=to[1],to[2]
    return not W.near(x,y,8,obstruct,record.id,z,d,d%4==1,exposed,changed)
  end

  return P
end
