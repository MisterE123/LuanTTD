-- SPDX-License-Identifier: GPL-2.0-only
-- Presentation hosts the prerecorded stock poses; the bay transition,
-- stop and departure bits are still decided at the real motion tick.
return function(Occupancy)
  local O=Occupancy
  local R={}
  local function board(s)
    return {tile=function(id)
      local t=s.tiles[id]
      if t and t.road_stop_pair and t.build=="road_station" and t.station then
        return {kind="bay_stop",station=t.station,owner=t.owner,stop_type="bus"}
      end
    end}
  end
  local function stop(s,id)
    local h=s.stock_road_bays
    return h and h.stops[id]
  end
  local function actor(v,f,state,speed)
    return {id=v.id,owner=v.owner,bus=v.cargo=="passenger",tile=f[4],type="road",total_length=8,
      direction=f[3],state=state or f[6],frame=f[15],speed=speed or 0}
  end
  local function order(s,id,kind)
    return {kind=kind,station=s.tiles[id].station,should_stop=true}
  end
  function R.install(s,id)
    s.stock_road_bays=s.stock_road_bays or O.new()
    O.register(s.stock_road_bays,board(s),id)
  end
  function R.report(s,id)
    local rs=stop(s,id)
    if not rs then return end
    return {first=not O.bay_free(rs,0),second=not O.bay_free(rs,1),entrance=O.entrance_busy(rs)}
  end

  -- Read-only proposal. The caller still needs lane proximity/height,
  -- crossing and one-way permission before applying any mutation.
  function R.propose(s,v,old,next_pose,index)
    local from,to=old[4],next_pose[4]
    local claim=v.road_bay_claim
    if claim and claim.tile~=from then return nil,nil,"bay state" end
    if from==to then
      if claim and claim.phase=="parked" then
        local rs=stop(s,from)
        if not rs or O.entrance_busy(rs) then return nil,nil,"bay" end
        return next_pose,{action="depart"}
      end
      return next_pose
    end
    local rs=stop(s,to)
    if rs then
      local option=v.road_bay_branch
      if not option or option.tile~=to or option.first~=index or claim or v.cargo~="passenger" then
        return nil,nil,"bay state"
      end
      if O.entrance_busy(rs) or not O.has_free(rs) then return nil,nil,"bay" end
      local chosen=O.bay_free(rs,0) and 0 or 1
      local frame=chosen==0 and next_pose or option.second[1]
      if not frame or frame[4]~=to or frame[15]~=0 then return nil,nil,"bay state" end
      local row=frame[6]-32-chosen*2
      if row~=0 and row~=1 and row~=8 and row~=9 then return nil,nil,"bay state" end
      return frame,{action="enter",bay=chosen,row=row,alternative=chosen==1 and option.second or nil}
    end
    if claim then
      if claim.phase~="exiting" then return nil,nil,"bay state" end
      return next_pose,{action="leave"}
    end
    return next_pose
  end

  function R.commit(s,v,old,next_pose,request,frames,index)
    if not request then return frames end
    local occ,B=s.stock_road_bays,board(s)
    if request.action=="enter" then
      local entered,bay=O.station_callback(occ,B,next_pose[4],actor(v,next_pose,request.row))
      assert(entered and bay==request.bay,"Bay mutated between motion proposal and commit")
      v.road_bay_claim={tile=next_pose[4],bay=bay,phase="entering"}
      v.road_bay_branch=nil
      if request.alternative then
        for n=#frames,index,-1 do frames[n]=nil end
        for n,f in ipairs(request.alternative) do frames[index+n-1]=f end
      end
    elseif request.action=="depart" then
      local a=actor(v,old,old[6]+4) -- RVSB_ROAD_STOP_ENTERED
      assert(O.at_stop(occ,B,a,1,order(s,a.tile,"leave_station"))=="depart",
        "Departure no longer matches the assigned stock bay")
      v.road_bay_claim.phase="exiting"
    elseif request.action=="leave" then
      local ok,_,why=O.transition(occ,B,actor(v,old),next_pose[4],next_pose[6])
      assert(ok and why=="left","Stop entrance released outside the stock leave transition")
      v.road_bay_claim=nil
    end
    return frames
  end

  function R.arrive(s,v,f)
    local rs=stop(s,f[4])
    if not rs then return end
    local claim=assert(v.road_bay_claim,"Arrival without a reserved stock bay")
    assert(claim.tile==f[4] and claim.phase=="entering")
    local a=actor(v,f)
    assert(O.at_stop(s.stock_road_bays,board(s),a,1,order(s,a.tile,"go_station"))=="load",
      "Arrival does not match the stock stopped frame")
    claim.phase="parked"
  end
  return R
end
