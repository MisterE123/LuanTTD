-- Road movement is interleaved in vehicle-id order once for each logical
-- tick. Terrain setters, company finance, loads and delivery remain external.
local source=debug and debug.getinfo(1,"S").source
local base=source and source:match("^@(.*/)road_speed_runtime%.lua$")
base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
local Wormhole=dofile(base.."road_bridge_motion.lua")
local Accel=dofile(base.."openttd/road_acceleration.lua")
local Buses=dofile(base.."openttd/road_bus_catalog.lua")
local realistic={}
for _,engine in ipairs(Buses.order) do
  realistic[engine]=Accel.vehicle(Buses.quote(nil,nil,Buses.stock_id(engine)))
end
return function(Speed,Proximity,road_z,bay_tile,is_depot,make_overtake_board,crossing_step,oneway_guard,oneway_replan,Bay,Junction,tile_xy)
  local R={bay=Bay,preserve_after_tide=Junction and Junction.preserve_after_tide}
  local Pass,Motion
  if make_overtake_board then
    local m=base.."openttd/"
    Motion=dofile(m.."road_motion.lua")(dofile(m.."road_motion_data.lua"))
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
    local borrowed={}
    local buckets,bay,by_tile,wormholes,exposed={},{},{},{},0
    local W={}
    local heights=stable_surface and {}
    local empty={}
    local nearby={}
    -- This table belongs to one movement tick, after landscape and
    -- station callbacks. No height survives a later world mutation.
    function W.height(_,frame) return road_z(s,frame,heights) end
    function W.put(record,f,opposite,z)
      local x,y,direction,tile=f[1],f[2],f[3],f[4]
      if record.companion then borrowed[record]=true end
      opposite=not not opposite
      if opposite~=not not record.opposite_lane then
        exposed=exposed+(opposite and 1 or -1)
        record.opposite_lane=opposite
      end
      record.frame=f
      local cell=record.x==x and record.y==y and record.cell or floor(x/16)*stride+floor(y/16)
      if record.cell~=cell then
        if record.bucket then record.bucket[record.id]=nil end
        local bucket=buckets[cell]
        if not bucket then bucket={};buckets[cell]=bucket end
        bucket[record.id]=record
        record.bucket,record.cell=bucket,cell
      end
      -- Ground traffic does not need the special portal memberships.
      -- Still visit them on the first ground pixel after leaving a span.
      if f[12] or record.opposite_portal then
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
      else
        record.stock_tile=tile
      end
      if record.tile~=tile then
        if bay[record.tile]==record.id then bay[record.tile]=nil end
        if record.tile and by_tile[record.tile] then by_tile[record.tile][record.id]=nil end
        by_tile[tile]=by_tile[tile] or {}
        by_tile[tile][record.id]=record
      end
      local occupant=bay[tile]
      if (not occupant or record.id<occupant) and bay_tile(s,tile) then bay[tile]=record.id end
      record.x,record.y,record.z,record.direction,record.tile=x,y,z or W.height(s,f),direction,tile
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
    function W.begin_tick()
      -- RC1 UpdateVehicleTileHash only changes membership when a
      -- vehicle changes its index. Positions still update immediately.
      -- Companion records are rebuilt by their controller. Drop precisely
      -- those temporary records; ordinary road records keep memberships.
      for record in pairs(borrowed) do W.erase(record);borrowed[record]=nil end
      -- The previous tick cannot retain surface or bay eligibility. A
      -- construction/tide/roadworks update may have run before this call.
      bay,heights={},stable_surface and {}
    end
    function W.vehicles_at(tile)
      local list={}
      for _,item in pairs(by_tile[tile] or empty) do list[#list+1]=item end
      return list
    end
    function W.near(x,y,r,check,id,z,d,horizontal,exposed,changed)
      local bottom,top=floor((y-r)/16),floor((y+r)/16)
      for ix=floor((x-r)/16),floor((x+r)/16) do
        local key=ix*stride
        for iy=bottom,top do
          local bucket=buckets[key+iy]
          if bucket then for _,item in pairs(bucket) do if check(item,id,x,y,z,d,horizontal,exposed,changed) then return true end end end
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
    local moving=v and not leader.stopped and leader.clock
    return moving and leader.clock.speed or 0
  end
  local function board_for(s,W)
    if Pass then return Pass.board(s,W) end
  end

  -- Movement consumes zero or more pixels synchronously. Share the
  -- callbacks instead of allocating them for every moving vehicle and
  -- every pixel; keep the old pose current between pixels in one budget.
  -- Straight stock road tracks may be inclined; turns, depot interiors
  -- and flat bay tiles cannot. The height sampler already accounts for
  -- the road foundation or an elevated bore cutting through other nodes.
  local function prepare_incline(s,W,state,b,z)
    -- RC1 RoadVehicle::TileMayHaveSlopedTrack checks the underlying
    -- TrackBits, not the vehicle's motion state. A reversing vehicle
    -- on a straight sloped road still faces grade resistance.
    local tile=s.tiles[b[4]]
    local mask=tile.road_bits
    if mask==5 or mask==10 or b[10] or b[14] then
      local mid={b[1]-b[1]%16+8,b[2]-b[2]%16+8,b[3],b[4]}
      mid[10],mid[12],mid[14]=b[10],b[12],b[14]
      state.incline=Accel.inclination(z or W.height(s,b),W.height(s,mid))
      return
    end
    state.incline=0
  end
  local function commit_frame(a,state,b,nominal,actual_z,bay_commit,entering)
    local s,W,v,frames,record,old=a.s,a.W,a.v,a.frames,a.record,a.old
    if bay_commit then Bay.commit(s,v,old,b,bay_commit,frames,state.index+1) end
    state.waiting,state.oneway_reason,state.oneway_tile=nil,nil,nil
    if v.status=="Waiting at one-way road" or v.status=="Waiting for roadworks" or v.status=="Waiting for junction clearance" then v.status="En route" end
    local span_limit=bridge_limit(s,b)
    local permitted=math.min(limit[v.engine],span_limit or math.huge)
    if span_limit and not a.realistic then state.speed=math.min(state.speed,permitted) end
    if state.heading~=b[3] then
      state.heading=b[3]
      if not a.realistic then Speed.turn(state) end
    end
    if old[1]~=b[1] or old[2]~=b[2] then
      actual_z=actual_z or W.height(s,b)
      if not a.realistic then Speed.grade(state,record.z,actual_z,permitted) end
    end
    -- RC1 also refreshes inclination when the same-tile U-turn starts
    -- (RDE_NEXT_TILE, frame 0) or completes (RDE_TURNED, frame 1).
    if a.realistic and (entering or old[6]~=b[6] and (b[15]==0 or b[15]==1)) then
      prepare_incline(s,W,state,b,actual_z)
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
    a.old=b
    if Pass then Pass.accept(state,b,nominal) end
    if b[16] then
      W.erase(record)
      state.speed=0
      if a.entered_transit then a.entered_transit(v) end
      return false -- stop this movement budget until the stock depot-exit tick
    end
    W.put(record,b,state.lane_pose~=nil,actual_z)
    if state.index==#frames and not (a.stock_stop or a.depot_stop) then state.speed=0 end
    return true
  end

  local function move_frame(state,a)
    local s,W,v,frames,record,old,roof,board=a.s,a.W,a.v,a.frames,a.record,a.old,a.roof,a.board
    local nominal=frames[state.index+1]
    if not nominal then
      if a.depot_stop then
        -- VehicleEnterTile_Road checks the *current* frame 11 on the
        -- next step. VehicleEnterDepot hides/reverses the head and
        -- stops it, but the rest of this tick's progress is retained.
        if not state.arrival_ready then
          state.arrival_ready=true
          state.heading=(state.heading+4)%8
          state.speed=0
        end
        return true
      end
      if a.stock_stop then
        if Motion and old[6]>=64 and old[6]<80 then
          -- IndividualRoadVehicleController checks proximity before
          -- handling frame 11, even at the designated platform. A
          -- rolling leader delays loading; a stationary one doesn't.
          local kind,dx,dy=Motion.sample(old[6],1,old[15]+1)
          if kind=="position" then
            local x=old[1]-old[1]%16+dx
            local y=old[2]-old[2]%16+dy
            local leader=W.find(record,state,x,y,old[3])
            if leader then
              state.waiting,state.speed="road",leader_speed(s,leader)
              if state.speed>0 then return false end
            end
          end
        end
        state.arrival_ready=true;state.speed=0
      end
      return false
    end
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
        -- IndividualRoadVehicleController may begin loading while
        -- queued behind a stopped bus, before reaching frame 11.
        -- Preserve the actual pixel; the next order departs from here.
        local tile=s.tiles[old[4]]
        if a.stock_stop and state.speed==0 and not entering and old[6]>=64 and old[6]<80
            and tile.station==v.dest then
          state.arrival_pose=old
        end
        return false
      end
    end
    if crossing_step and old[4]~=b[4] then
      -- A crossing transaction owns the movement callback until it
      -- returns; ordinary pixels have no transaction to allocate.
      local ok=crossing_step(s,W,old[4],b[4],b[6],function()
        return commit_frame(a,state,b,nominal,actual_z,bay_commit,entering)
      end)
      if not ok then state.waiting="crossing";state.speed=0 end
      return ok
    end
    return commit_frame(a,state,b,nominal,actual_z,bay_commit,entering)
  end

  local function stock_realistic(s,v)
    return s.stock_generated_profile and s.stock_bus_market and
      s.stock_road_acceleration_model~=0 and v.stock_bus and realistic[v.engine]
  end
  local function step(s,W,a,board,on_exit,tick,stock_stop,realistic_profile,depot_stop)
    local v,c,frames,record=a.v,a.c,a.frames,a.record
    if c.index>=#frames and not (stock_stop or depot_stop) then return end
    local old=pose(c,frames)
    local use_realistic=realistic_profile
    if use_realistic==nil then use_realistic=stock_realistic(s,v) end
    a.stock_stop,a.depot_stop=stock_stop,depot_stop
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
      if use_realistic then c.ticks=c.ticks+1;return end
    end
    if oneway_replan then
      local fresh=oneway_replan(s,v,c,frames,old,limit[v.engine])
      if fresh then
        frames,a.frames,old=fresh,fresh,fresh[c.index]
      end
    end
    local span_max=bridge_limit(s,old)
    local roof=math.min(limit[v.engine],span_max or math.huge)
    local passing=Pass and Pass.active(c)
    local acceleration,minimum
    if use_realistic then
      if c.incline==nil then
        local entry=c.index
        while entry>1 and frames[entry-1][4]==old[4] do entry=entry-1 end
        prepare_incline(s,W,c,frames[entry])
      end
      roof=Accel.limit(limit[v.engine],c.heading,old[6],old[12] and span_max or nil)
      acceleration=Accel.force(use_realistic,c.speed,v.cargo,v.units or 0,c.incline,s.stock_road_slope_steepness)
        +(passing and 256 or 0)
      minimum=4
    end
    a.old,a.roof,a.board,a.realistic=old,roof,board,use_realistic
    Speed.tick(c,roof,passing,move_frame,a,acceleration,minimum)
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
        active[#active+1]={v=v,c=c,frames=frames,record=record,trail=path,s=s,W=W}
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
    local ids,worked={},{}
    local keep=not hooks.live_projection
    local view,timelines=keep and {} or nil,keep and {} or nil
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
        if keep then frame=visible(c,route) end
      elseif v and keep then frame=v.road_stop_pose end
      -- Preserve route-state initialization: the first economy step
      -- must see the same controller, even with no playback history.
      if not keep then return end
      local a=view[id]
      if not a then a={frames={},cursors={}};view[id]=a end
      a.frames[k]=frame or blank
      a.cursors[k]=frame and k or 0
      if frame then timelines[id]=a end
    end
    for _,id in ipairs(ids) do sample(id,1) end
    local k=1
    -- step consumes this argument synchronously; only the poses and
    -- cursors are published. Do not allocate a wrapper per vehicle/tick.
    local W,records=world(s,true),{}
    local moving={s=s,W=W,entered_transit=hooks.entered_transit}
    clock(function(tick)
      local ready=hooks.economy(tick)
      W.begin_tick()
      local board=board_for(s,W)
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
          local rec=records[id]
          if not rec then rec=record_for(v,c);records[id]=rec
          else rec.clock,rec.stopped,rec.max_speed=c,v.running==false,limit[v.engine] end
          if f then W.put(rec,f,c and c.lane_pose~=nil)
          else
            if rec.tile then W.erase(rec) end
            rec.x,rec.y,rec.z,rec.direction=nil,nil,nil,nil
          end
        elseif records[id] then
          W.erase(records[id])
          records[id]=nil
        end
      end
      local companion=hooks.companion
      local external=companion and companion.seed(s,W,tick,k,keep)
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
            -- RoadVehController reaches the stock stop frame on one
            -- movement step, then enters loading on the next attempted
            -- step from that frame. Both can fit in the same tick.
            local realistic_profile=stock_realistic(s,v)
            local stock_stop=v.dest~=nil and not v.road_return_depot and not not realistic_profile
            local depot_stop=v.road_return_depot~=nil and not not realistic_profile
            if v.running and not held then
              moving.v,moving.c,moving.frames,moving.record=v,c,frames,rec
              step(s,W,moving,board,hooks.exited,tick,stock_stop,realistic_profile or false,depot_stop)
              frames=moving.frames
            end
            v.progress=1+(#v.route-1)*(c.index-1)/math.max(1,#frames-1)
            local arrived_pose=c.arrival_pose
            if not held and (arrived_pose or c.index>=#frames and (not (stock_stop or depot_stop) or c.arrival_ready)) then
              local stop=arrived_pose or frames[#frames]
              local arrived,hidden=hooks.arrive(v,tick,stop,(stock_stop or depot_stop) and c or nil)
              if arrived then
                rec.clock=nil
                -- Loading occupies the station. Stock depot entry hides the
                -- vehicle immediately and removes its visible lane obstacle.
                if hidden then W.erase(rec) else W.put(rec,stop) end
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
