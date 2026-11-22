-- Road movement is interleaved in vehicle-id order once for each logical
-- tick. Terrain setters, company finance, loads and delivery remain external.
local source=debug and debug.getinfo(1,"S").source
local base=source and source:match("^@(.*/)road_speed_runtime%.lua$")
base=base or (core and core.get_modpath("bayline").."/") or "mods/bayline/"
return function(Speed,Proximity,road_z,bay_tile,is_depot,make_overtake_board,crossing_step,oneway_guard,oneway_replan,Bay,Junction)
  local R={bay=Bay}
  local Pass
  if make_overtake_board then
    local m=base.."openttd/"
    local Motion=dofile(m.."road_motion.lua")(dofile(m.."road_motion_data.lua"))
    Pass=dofile(base.."road_pass_runtime.lua")(Motion,dofile(m.."road_overtake.lua"),
      dofile(m.."yapf_road_follow.lua"),make_overtake_board)
  end
  local function pose(c,frames) return c and (c.lane_pose or frames[c.index]) end
  R.pose=pose
  local limit={bus=112,truck=96,coach=144,leopard_bus=176,foster_bus=224,mail_van=96,coal_tipper=96,
    wood_truck=96,goods_truck=96,grain_truck=96,livestock_van=96,oil_tanker=96}
  local floor=math.floor
  local function init(s,v,frames)
    if v.road_speed_state then return v.road_speed_state end
    local fractional=(v.progress-1)/math.max(1,#v.route-1)
    local index=math.min(#frames,math.max(1,floor((#frames-1)*fractional+1)))
    local c={index=index,speed=0,subspeed=0,progress=0,heading=frames[index][3],ticks=0}
    c.depot_wait=index==1 and is_depot(s,frames[1][4]) or nil
    v.road_speed_state=c
    return c
  end
  -- The stock candidate scan is tile-hash bounds around ±6 pixels;
  -- the predicate then applies direction-specific stricter distances.
  local function world(s)
    local buckets,bay,by_tile,exposed={},{},{},0
    local W={}
    local function at(x,y) return x..":"..y end
    local function bin(x,y) return at(floor(x/16),floor(y/16)) end
    function W.put(record,f,opposite)
      opposite=not not opposite
      if opposite~=not not record.opposite_lane then exposed=exposed+(opposite and 1 or -1) end
      record.opposite_lane=opposite
      record.frame=f
      local old=record.bucket
      local k=bin(f[1],f[2])
      if old~=k then
        if old then buckets[old][record.id]=nil end
        buckets[k]=buckets[k] or {}
        buckets[k][record.id]=record
        record.bucket=k
      end
      local tile=f[4]
      if record.tile~=tile then
        if bay[record.tile]==record.id then bay[record.tile]=nil end
        if record.tile and by_tile[record.tile] then by_tile[record.tile][record.id]=nil end
        by_tile[tile]=by_tile[tile] or {}
        by_tile[tile][record.id]=record
      end
      if bay_tile(s,tile) and (not bay[tile] or record.id<bay[tile]) then bay[tile]=record.id end
      record.x,record.y,record.z,record.direction,record.tile=f[1],f[2],road_z(s,f),f[3],tile
    end
    function W.bay(id) return bay[id] end
    function W.exposed() return exposed>0 end
    function W.erase(record)
      if record.bucket then buckets[record.bucket][record.id]=nil end
      if record.tile and by_tile[record.tile] then by_tile[record.tile][record.id]=nil end
      if bay[record.tile]==record.id then bay[record.tile]=nil end
      if record.opposite_lane then exposed=exposed-1 end
      record.bucket,record.tile,record.frame,record.opposite_lane=nil,nil,nil,nil
    end
    function W.vehicles_at(tile)
      local list={}
      for _,item in pairs(by_tile[tile] or {}) do list[#list+1]=item end
      return list
    end
    function W.near(x,y,r,check)
      for ix=floor((x-r)/16),floor((x+r)/16) do
        for iy=floor((y-r)/16),floor((y+r)/16) do
          for _,item in pairs(buckets[at(ix,iy)] or {}) do if check(item) then return true end end
        end
      end
      return false
    end
    function W.find(record,c,x,y,dir,update)
      local list={}
      W.near(x,y,6,function(item) list[#list+1]=item end)
      return Proximity.find(record,c,x,y,dir,list,update)
    end
    return W
  end

  local function record_for(v,c)
    return {id=v.id,first=v.id,type="road",clock=c,max_speed=limit[v.engine],stopped=v.running==false}
  end
  local function leader_speed(s,leader)
    local v=s.fleet[leader.id]
    local moving=not leader.stopped and leader.clock and
      leader.clock.index<#(v.road_motion_frames or {})
    return moving and leader.clock.speed or 0
  end
  local function board_for(s,W)
    if Pass then return Pass.board(s,W) end
  end

  local function step(s,W,a,board,on_exit,tick)
    local v,c,frames,record=a.v,a.c,a.frames,a.record
    if c.index>=#frames then return end
    local old=pose(c,frames)
    if c.depot_wait then
      record.z=road_z(s,old)
      if W.find(record,c,old[1],old[2],old[3],false) then c.waiting="depot";return end
      c.depot_wait=nil;c.waiting=nil
      W.put(record,old)
      if on_exit then on_exit(v,tick) end
    end
    if oneway_replan then
      local fresh=oneway_replan(s,v,c,frames,old,limit[v.engine])
      if fresh then
        frames,a.frames,old=fresh,fresh,fresh[c.index]
      end
    end
    local roof=math.min(limit[v.engine],old[11] or math.huge)
    Speed.tick(c,roof,Pass and Pass.active(c),function(state)
      local nominal=frames[state.index+1]
      if not nominal then return false end
      local b=nominal
      if Pass then
        b=Pass.next(v,state,old,nominal,roof,board)
        if not b then state.waiting="overtake geometry";return false end
      end
      local bay_commit
      local pair=Bay and s.stock_road_bays and s.stock_road_bays.stops[b[4]]
      if Bay and s.stock_road_bays and (v.road_bay_claim or pair) then
        local original,why=b
        b,bay_commit,why=Bay.propose(s,v,old,b,state.index+1)
        if not b then state.waiting=why;state.speed=0;return false end
        -- A different admissible parking row is not overtaking.
        if b~=original then nominal=b end
      end
      if oneway_guard then
        local ok,why,tile=oneway_guard(s,old,b)
        if not ok then
          state.waiting,state.speed,state.oneway_reason,state.oneway_tile="oneway",0,why,tile
          v.status="Waiting at one-way road"
          return false
        end
      end
      local entering=b[9] or old[4]~=b[4]
      if entering and not pair and bay_tile(s,b[4]) and W.bay(b[4]) and W.bay(b[4])~=v.id then
        state.waiting="bay";state.speed=0
        return false
      end
      local actual_z
      if Junction and s.road_junction_clearance then
        if Bay and not Junction.bay_clearance(s,W,v,old,b,bay_commit and bay_commit.action,Bay) then
          state.waiting,state.speed="bay",0
          v.road_bay_guard_waits=(v.road_bay_guard_waits or 0)+1
          return false
        end
        actual_z=road_z(s,b)
        if not Junction.check(s,W,record,old,b,actual_z) then
          state.waiting,state.speed="junction",0
          v.status="Waiting for junction clearance"
          v.road_junction_waits=(v.road_junction_waits or 0)+1
          return false
        end
      end
      if Pass and (state.lane_pose or b~=nominal or W.exposed()) then
        actual_z=actual_z or road_z(s,b)
        if not Pass.clear(W,record,old,b,nominal,actual_z) then
          state.waiting="road"
          return false
        end
      end
      if entering or not bay_tile(s,old[4]) then
        local leader=W.find(record,state,b[7] or b[1],b[8] or b[2],b[3])
        if leader then
          state.waiting="road"
          local speed=leader_speed(s,leader)
          if Pass and not entering then
            Pass.control(v,state,board,frames,old,roof,leader,speed,
              math.min(leader.max_speed,leader.frame[11] or math.huge))
          else
            state.speed=speed
          end
          return false
        end
      end
      local function commit()
        if bay_commit then Bay.commit(s,v,old,b,bay_commit,frames,state.index+1) end
        state.waiting,state.oneway_reason,state.oneway_tile=nil,nil,nil
        if v.status=="Waiting at one-way road" or v.status=="Waiting for junction clearance" then v.status="En route" end
        local permitted=math.min(limit[v.engine],b[11] or math.huge)
        if b[11] then state.speed=math.min(state.speed,permitted) end
        if state.heading~=b[3] then state.heading=b[3];Speed.turn(state) end
        if old[1]~=b[1] or old[2]~=b[2] then Speed.grade(state,record.z,actual_z or road_z(s,b),permitted) end
        state.index=state.index+1
        old=b
        if Pass then Pass.accept(state,b,nominal) end
        W.put(record,b,state.lane_pose~=nil)
        if state.index==#frames then state.speed=0 end
        return true
      end
      if crossing_step and old[4]~=b[4] then
        local ok=crossing_step(s,W,old[4],b[4],b[6],commit)
        if not ok then state.waiting="crossing";state.speed=0 end
        return ok
      end
      return commit()
    end)
    c.ticks=c.ticks+1
  end

  local blank={0,0,3,1,.5}
  function R.day(s,moving)
    local active,results,timelines={}, {}, {}
    local W=world(s)
    local board=board_for(s,W)
    local actual=Pass or oneway_replan~=nil
    local function append(path,k,c,frames)
      local f=not c.depot_wait and pose(c,frames)
      if actual then path.frames[k]=f or blank end
      path.cursors[k]=f and (actual and k or c.index) or 0
    end
    for _,id in ipairs(moving) do
      local v=s.fleet[id]
      local frames=v.road_motion_frames
      if frames and limit[v.engine] then
        local c=init(s,v,frames)
        local f=pose(c,frames)
        local record=record_for(v,c)
        if not c.depot_wait then W.put(record,f,c.lane_pose~=nil) end
        local path={frames=actual and {} or frames,cursors={}}
        append(path,1,c,frames)
        timelines[id]=path
        active[#active+1]={v=v,c=c,frames=frames,record=record,trail=path}
      end
    end
    for _,v in pairs(s.fleet) do
      if not v.route and v.road_stop_pose and limit[v.engine] then W.put(record_for(v),v.road_stop_pose) end
    end
    for tick=1,74 do
      for _,a in ipairs(active) do
        if not Pass or a.v.running~=false then step(s,W,a,board) end
        append(a.trail,tick+1,a.c,a.frames)
      end
    end
    for _,a in ipairs(active) do
      local v,c=a.v,a.c
      results[v.id]=1+(#v.route-1)*(c.index-1)/math.max(1,#a.frames-1)
    end
    return results,timelines
  end

  -- One road vehicle may arrive, spend its stock load ticks, and begin a
  -- new leg during the same day. A single timeline samples actual poses
  -- rather than assuming that all 74 samples reference one saved leg.
  function R.live_day(s,clock,hooks)
    local ids,worked,view,timelines={},{},{},{}
    for id,v in pairs(s.fleet) do
      if limit[v.engine] then ids[#ids+1]=id end
    end
    table.sort(ids)
    local function sample(id,k)
      local v=s.fleet[id]
      local route,c=v.road_motion_frames,v.road_speed_state
      local frame
      if v.route and route then
        c=c or init(s,v,route)
        frame=not c.depot_wait and pose(c,route) or nil
      elseif v.road_stop_pose then frame=v.road_stop_pose end
      local a=view[id]
      if not a then a={frames={},cursors={}};view[id]=a end
      a.frames[k]=frame or blank
      a.cursors[k]=frame and k or 0
      if frame then timelines[id]=a end
    end
    for _,id in ipairs(ids) do sample(id,1) end
    local k=1
    clock(function(tick)
      local ready=hooks.economy(tick)
      local W=world(s)
      local board=board_for(s,W)
      local records={}
      for _,id in ipairs(ids) do
        local v=s.fleet[id]
        local f,c
        if v.route and v.road_motion_frames then
          c=init(s,v,v.road_motion_frames)
          if not c.depot_wait then f=pose(c,v.road_motion_frames) end
        else f=v.road_stop_pose end
        local rec=record_for(v,c)
        records[id]=rec
        if f then W.put(rec,f,c and c.lane_pose~=nil) end
      end
      k=k+1
      for _,id in ipairs(ids) do
        local v=s.fleet[id]
        local held=hooks.before(v,tick,ready[id])==true
        local frames=v.road_motion_frames
        if v.route and frames then
          local c=init(s,v,frames)
          local rec=records[id]
          rec.clock=c
          rec.stopped=v.running==false
          if not c.depot_wait and not rec.tile then W.put(rec,pose(c,frames),c.lane_pose~=nil) end
          worked[id]=true
          if v.running and not held then
            local moving={v=v,c=c,frames=frames,record=rec}
            step(s,W,moving,board,hooks.exited,tick)
            frames=moving.frames
          end
          v.progress=1+(#v.route-1)*(c.index-1)/math.max(1,#frames-1)
          if c.index>=#frames and not held then
            local arrived,hidden=hooks.arrive(v,tick,frames[#frames])
            if arrived then
              rec.clock=nil
              -- Loading occupies the station. Stock depot entry hides the
              -- vehicle immediately and removes its visible lane obstacle.
              if hidden then W.erase(rec) else W.put(rec,frames[#frames]) end
            end
          end
        end
        hooks.age(v,tick)
        sample(id,k)
      end
    end)
    return worked,timelines
  end
  return R
end
