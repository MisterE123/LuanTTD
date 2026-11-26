-- Road movement is interleaved in vehicle-id order once for each logical
-- tick. Terrain setters, company finance, loads and delivery remain external.
local source=debug and debug.getinfo(1,"S").source
local base=source and source:match("^@(.*/)road_speed_runtime%.lua$")
base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
local Wormhole=dofile(base.."road_bridge_motion.lua")
return function(Speed,Proximity,road_z,bay_tile,is_depot,make_overtake_board,crossing_step,oneway_guard,oneway_replan,Bay,Junction,tile_xy)
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
  local function visible(c,frames)
    local f=c and not c.depot_wait and pose(c,frames)
    return f and not f[16] and f or nil
  end
  -- The route keeps the span ID, not the authoritative speed limit.
  -- RC1 reads the current GetBridgeSpec on the portal and in the
  -- wormhole. A rebuild must not regenerate or scan traveling routes.
  local function bridge_limit(s,f)
    if f[10] then
      local live=s.stock_road_bridges and s.stock_road_bridges[f[10]]
      local spec=live and live.spec
      return spec and spec.speed*2
    end
  end
  R.bridge_limit=bridge_limit
  local limit=dofile(base.."road_stock_speeds.lua")
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
  -- RC1 queries within ±8 pixels, using the logical tile hash. While
  -- inside a bridge or tunnel, query only its two logical portals.
  -- A legal world is at most 4,096 tiles per axis, including a
  -- small signed margin for radius checks/near-edge pixel poses. Keep
  -- a power-of-two stride well beyond that range, with exact Lua numbers.
  local stride=131072
  local function world(s,stable_surface)
    local buckets,bay,by_tile,wormholes,exposed={},{},{},{},0
    local W={}
    local heights=stable_surface and {}
    local empty={}
    local nearby={}
    -- This table belongs to one movement tick, after landscape and
    -- station callbacks. No height survives a later world mutation.
    function W.height(_,frame) return road_z(s,frame,heights) end
    function W.put(record,f,opposite,z)
      opposite=not not opposite
      if opposite~=not not record.opposite_lane then exposed=exposed+(opposite and 1 or -1) end
      record.opposite_lane=opposite
      record.frame=f
      local cell=floor(f[1]/16)*stride+floor(f[2]/16)
      if record.cell~=cell then
        if record.bucket then record.bucket[record.id]=nil end
        local bucket=buckets[cell]
        if not bucket then bucket={};buckets[cell]=bucket end
        bucket[record.id]=record
        record.bucket,record.cell=bucket,cell
      end
      local tile=f[4]
      local stock_tile,opposite_portal=tile
      if f[12] then stock_tile,opposite_portal=Wormhole.frame_bucket(s,f) end
      if record.opposite_portal and (not opposite_portal or record.stock_tile~=stock_tile) then
        wormholes[record.stock_tile][record.id]=nil
      end
      if opposite_portal and (not record.opposite_portal or record.stock_tile~=stock_tile) then
        wormholes[stock_tile]=wormholes[stock_tile] or {}
        wormholes[stock_tile][record.id]=record
      end
      if opposite_portal and tile_xy and (not record.opposite_portal or record.stock_tile~=stock_tile) then
        record.stock_x,record.stock_y=tile_xy(stock_tile)
      end
      record.stock_tile,record.opposite_portal=stock_tile,opposite_portal
      if record.tile~=tile then
        if bay[record.tile]==record.id then bay[record.tile]=nil end
        if record.tile and by_tile[record.tile] then by_tile[record.tile][record.id]=nil end
        by_tile[tile]=by_tile[tile] or {}
        by_tile[tile][record.id]=record
      end
      if bay_tile(s,tile) and (not bay[tile] or record.id<bay[tile]) then bay[tile]=record.id end
      record.x,record.y,record.z,record.direction,record.tile=f[1],f[2],z or W.height(s,f),f[3],tile
    end
    function W.bay(id) return bay[id] end
    function W.exposed() return exposed>0 end
    function W.erase(record)
      if record.bucket then record.bucket[record.id]=nil end
      if record.tile and by_tile[record.tile] then by_tile[record.tile][record.id]=nil end
      if bay[record.tile]==record.id then bay[record.tile]=nil end
      if record.opposite_portal then wormholes[record.stock_tile][record.id]=nil end
      record.stock_tile,record.opposite_portal,record.stock_x,record.stock_y=nil,nil,nil,nil
      if record.opposite_lane then exposed=exposed-1 end
      record.bucket,record.cell=nil,nil
      record.tile,record.frame,record.opposite_lane=nil,nil,nil
    end
    function W.vehicles_at(tile)
      local list={}
      for _,item in pairs(by_tile[tile] or empty) do list[#list+1]=item end
      return list
    end
    function W.near(x,y,r,check)
      local bottom,top=floor((y-r)/16),floor((y+r)/16)
      for ix=floor((x-r)/16),floor((x+r)/16) do
        local key=ix*stride
        for iy=bottom,top do
          local bucket=buckets[key+iy]
          if bucket then for _,item in pairs(bucket) do if check(item) then return true end end end
        end
      end
      return false
    end
    local function stock_candidates(tile,out,n)
      for _,item in pairs(by_tile[tile] or empty) do
        if not item.opposite_portal then n=n+1;out[n]=item end
      end
      for _,item in pairs(wormholes[tile] or empty) do n=n+1;out[n]=item end
      return n
    end
    function W.stock_vehicles_at(tile)
      local out={}
      stock_candidates(tile,out,0)
      return out
    end
    function W.find(record,c,x,y,dir,update)
      if (c.reverse_ctr or 0)~=0 then return end
      local n=0
      if record.opposite_portal then
        n=stock_candidates(record.stock_tile,nearby,n)
        n=stock_candidates(record.opposite_portal,nearby,n)
      else
        local left,right,bottom,top=floor((x-8)/16),floor((x+8)/16),floor((y-8)/16),floor((y+8)/16)
        for ix=left,right do
          local key=ix*stride
          for iy=bottom,top do
            local bucket=buckets[key+iy]
            if bucket then
              for _,item in pairs(bucket) do
                if not item.opposite_portal or not tile_xy or
                    item.stock_x>=left and item.stock_x<=right and item.stock_y>=bottom and item.stock_y<=top then
                  n=n+1;nearby[n]=item
                end
              end
            end
          end
        end
      end
      local leader=Proximity.find(record,c,x,y,dir,nearby,update)
      for i=1,n do nearby[i]=nil end
      return leader
    end
    return W
  end

  R.traffic_world=world

  local function record_for(v,c)
    return {id=v.id,first=v.id,type="road",clock=c,max_speed=limit[v.engine],stopped=v.running==false}
  end
  local function leader_speed(s,leader)
    if leader.companion then
      return not leader.stopped and leader.clock and leader.clock.speed or 0
    end
    local v=s.fleet[leader.id]
    local moving=v and not leader.stopped and leader.clock and
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
    if old[16] then
      -- RoadVehLeaveDepot (RC1) checks the proposed outward point before
      -- unhiding, services the same physical vehicle, sets its speed to
      -- zero and consumes this tick without normal road acceleration.
      local next=frames[c.index+1]
      assert(next and next[4]==old[4] and not next[16] and is_depot(s,next[4]),
        "Corrupt transit-depot departure")
      record.z=W.height(s,next)
      if W.find(record,c,next[1],next[2],next[3],false) then c.waiting="depot";return end
      c.index,c.speed,c.heading,c.waiting=c.index+1,0,next[3],nil
      c.overtaking,c.overtaking_ctr,c.lane_pose=nil,nil,nil
      W.put(record,next)
      if on_exit then on_exit(v,tick) end
      c.ticks=c.ticks+1
      return
    end
    if c.depot_wait then
      record.z=W.height(s,old)
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
    local roof=math.min(limit[v.engine],bridge_limit(s,old) or math.huge)
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
          local works=why=="ROADWORKS_IN_PROGRESS"
          state.waiting,state.speed,state.oneway_reason,state.oneway_tile=works and "roadworks" or "oneway",0,why,tile
          v.status=works and "Waiting for roadworks" or "Waiting at one-way road"
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
        local clear
        clear,actual_z=Junction.check(s,W,record,old,b,nil,W.height)
        if not clear then
          state.waiting,state.speed="junction",0
          v.status="Waiting for junction clearance"
          v.road_junction_waits=(v.road_junction_waits or 0)+1
          return false
        end
      end
      if Pass and (state.lane_pose or b~=nominal or W.exposed()) then
        actual_z=actual_z or W.height(s,b)
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
              math.min(leader.max_speed,bridge_limit(s,leader.frame) or math.huge))
          else
            state.speed=speed
          end
          return false
        end
      end
      local function commit()
        if bay_commit then Bay.commit(s,v,old,b,bay_commit,frames,state.index+1) end
        state.waiting,state.oneway_reason,state.oneway_tile=nil,nil,nil
        if v.status=="Waiting at one-way road" or v.status=="Waiting for roadworks" or v.status=="Waiting for junction clearance" then v.status="En route" end
        local span_limit=bridge_limit(s,b)
        local permitted=math.min(limit[v.engine],span_limit or math.huge)
        if span_limit then state.speed=math.min(state.speed,permitted) end
        if state.heading~=b[3] then state.heading=b[3];Speed.turn(state) end
        if old[1]~=b[1] or old[2]~=b[2] then
          actual_z=actual_z or W.height(s,b)
          Speed.grade(state,record.z,actual_z,permitted)
        end
        state.index=state.index+1
        if entering and v.road_via_pending then
          local wp=s.tiles[b[4]].road_waypoint_id
          local pending=v.road_via_pending
          if wp and pending[1]==wp then
            v.last_road_waypoint=wp
            repeat table.remove(pending,1) until pending[1]~=wp
            if #pending==0 then v.road_via_pending=nil end
          end
        end
        old=b
        if Pass then Pass.accept(state,b,nominal) end
        if b[16] then
          W.erase(record)
          state.speed=0
          return false -- stop this movement budget until the stock depot-exit tick
        end
        W.put(record,b,state.lane_pose~=nil,actual_z)
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
      local f=visible(c,frames)
      if actual then path.frames[k]=f or blank end
      path.cursors[k]=f and (actual and k or c.index) or 0
    end
    for _,id in ipairs(moving) do
      local v=s.fleet[id]
      local frames=v.road_motion_frames
      if frames and limit[v.engine] then
        local c=init(s,v,frames)
        local f=visible(c,frames)
        local record=record_for(v,c)
        if f then W.put(record,f,c.lane_pose~=nil) end
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
      local route,c=v and v.road_motion_frames,v and v.road_speed_state
      local frame
      if v and v.route and route then
        c=c or init(s,v,route)
        frame=visible(c,route)
      elseif v then frame=v.road_stop_pose end
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
      local W=world(s,true)
      local board=board_for(s,W)
      local records={}
      for _,id in ipairs(ids) do
        local v=s.fleet[id]
        if v and hooks.retire then
          if hooks.retire(v,tick) then s.fleet[id]=nil;v=nil end
        end
        if v then
          local f,c
          if v.route and v.road_motion_frames then
            c=init(s,v,v.road_motion_frames)
            f=visible(c,v.road_motion_frames)
          else f=v.road_stop_pose end
          local rec=record_for(v,c)
          records[id]=rec
          if f then W.put(rec,f,c and c.lane_pose~=nil) end
        end
      end
      local companion=hooks.companion
      local external=companion and companion.seed(s,W,tick,k)
      if external and external.id then external={external} end
      local next_external=1
      k=k+1
      for _,id in ipairs(ids) do
        while external and external[next_external] and external[next_external].id<id do
          companion.advance(s,W,tick,external[next_external],k,ready)
          next_external=next_external+1
        end
        local v=s.fleet[id]
        if v then
          local held=hooks.before(v,tick,ready[id])==true
          local frames=v.road_motion_frames
          if v.route and frames then
            local c=init(s,v,frames)
            local rec=records[id]
            rec.clock=c
            rec.stopped=v.running==false
            local front=visible(c,frames)
            if front and not rec.tile then W.put(rec,front,c.lane_pose~=nil) end
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
        end
        sample(id,k)
      end
      while external and external[next_external] do
        companion.advance(s,W,tick,external[next_external],k,ready)
        next_external=next_external+1
      end
    end)
    return worked,timelines
  end
  return R
end
