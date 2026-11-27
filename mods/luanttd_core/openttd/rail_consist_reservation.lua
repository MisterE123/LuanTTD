-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 train_cmd.cpp TrainController and ClearPathReservation.
-- The adapter owns persisted claim attribution; stock tile reservations
-- themselves are track bits, not train identifiers. Never operates the live
-- game. Caller handles real movement, signal aspects, arbitration and time.
return function(T,F,PBS)
  local R={VERSION=1}
  local band,has,rev=T.intersect,T.has,T.reverse_side
  local connect={[0]={[0]=1,8,0,16},{[0]=4,2,16,0},{[0]=0,32,1,4},{[0]=32,0,8,2}}

  local function ordinary(t)
    return t and F.stock_railtype(t.railtype) and (t.kind=="rail" or t.kind=="signals" or t.kind=="crossing" or
      t.kind=="station" or t.kind=="waypoint" or t.kind=="depot")
  end
  local function tile(board,id) return id~=nil and board.tile(id) or nil end
  local function set_owner(state,id,track,train)
    local claims=state.claims[id]
    if train~=nil then
      if not claims then claims={};state.claims[id]=claims end
      claims[track]=train
    elseif claims then
      claims[track]=nil
      if next(claims)==nil then state.claims[id]=nil end
    end
  end

  function R.new()
    return {version=R.VERSION,trains={},claims={},bits={}}
  end

  function R.claim_owner(state,id,track)
    local claims=state.claims[id]
    return claims and claims[track] or nil
  end

  function R.view(board,state) return PBS.view(board,state.bits) end

  -- Use at a reload boundary or in diagnostics. Keeping attribution
  -- separate never excuses a missing raw reservation under a saved part.
  function R.valid_state(board,state)
    if state.version~=R.VERSION then return false,"version" end
    for id,train in pairs(state.trains) do
      if train.id~=id or #train.parts==0 and not train.crashed then return false,"train" end
      for _,p in ipairs(train.parts) do
        if not T.valid_trackdir(p.td) then return false,"unclaimed_part" end
        local t=tile(board,p.tile)
        if not (p.in_depot and t and t.kind=="depot" and t.owner==train.owner)
          and not (p.unreserved and ordinary(t) and t.owner==train.owner and has(T.status(t),p.td))
          and R.claim_owner(state,p.tile,T.track(p.td))~=id then return false,"unclaimed_part" end
      end
    end
    for id,tracks in pairs(state.claims) do
      local t=tile(board,id)
      local bits=0
      for track,train_id in pairs(tracks) do
        local train=state.trains[train_id]
        if not ordinary(t) or not train or t.owner~=train.owner or
            not has(T.trackbits(T.status(t)),track) then return false,"orphan_claim" end
        bits=bits+T.trackbit(track)
      end
      if bits==0 or bits~=state.bits[id] or T.tracks_overlap(bits) then return false,"claim_mask" end
    end
    for id in pairs(state.bits) do if not state.claims[id] then return false,"unowned_mask" end end
    return true
  end

  -- Used for initial parts and front-engine entry. Matching claim by the
  -- same consist is allowed; another train's claim is never taken over.
  local function claim(board,state,train,id,track)
    local t=tile(board,id)
    if not ordinary(t) then return false,"unsupported_tile" end
    if t.owner~=train.owner then return false,"foreign_tile" end
    local old=R.claim_owner(state,id,track)
    if old==train.id then
      if not has(PBS.bits(board,state.bits,id),track) then return false,"missing_claim" end
      return true,nil,false
    end
    if old~=nil then return false,"reserved" end
    local ok,why=PBS.try_reserve(board,state.bits,id,track)
    if not ok then return false,why end
    set_owner(state,id,track,train.id)
    return true,nil,true
  end

  local function release(board,state,train,id,track)
    if R.claim_owner(state,id,track)~=train.id then return false,"not_owned" end
    local ok,why=PBS.unreserve(board,state.bits,id,track)
    if not ok then return false,why end
    set_owner(state,id,track,nil)
    return true
  end

  -- Registers an already placed ordinary consist, front to back. All
  -- positions and claims are serializable. Registration is atomic if one
  -- vehicle fails. The caller owns physical placement/length validation.
  function R.register(board,state,id,owner,parts,traction)
    if state.version~=R.VERSION or (type(id)~="number" and type(id)~="string") or
        state.trains[id] or type(parts)~="table" or #parts==0 then return false,"invalid_train" end
    local train={id=id,owner=owner,parts={}}
    if traction then
      train.engine_railtype=traction.engine_railtype
      train.traction_railtypes=traction.traction_railtypes
    end
    local acquired={}
    for _,p in ipairs(parts) do
      local function fail(why)
        for i=#acquired,1,-1 do
          local x=acquired[i]
          assert(release(board,state,train,x.tile,x.track))
        end
        return false,why
      end
      if not T.valid_trackdir(p.td) then return fail("invalid_track") end
      local t=tile(board,p.tile)
      if not t or not has(T.status(t),p.td) then return fail("invalid_track") end
      local track=T.track(p.td)
      local hidden=p.in_depot and t.kind=="depot" and t.owner==owner
      if not hidden then
        local ok,why,new=claim(board,state,train,p.tile,track)
        if not ok then return fail(why) end
        if new then acquired[#acquired+1]={tile=p.tile,track=track} end
      end
      train.parts[#train.parts+1]={tile=p.tile,td=p.td,in_depot=hidden or nil}
    end
    state.trains[id]=train
    return true
  end

  -- CheckTrainStayInDepot: stock only holds the depot's rail
  -- reservation when a front is actually released. Any number of
  -- consists may be wholly hidden inside the same depot beforehand.
  function R.release_depot_front(board,state,train_id)
    local train=state.trains[train_id]
    local front=train and train.parts[1]
    if not front or not front.in_depot then return false,"not_in_depot" end
    local ok,why=claim(board,state,train,front.tile,T.track(front.td))
    if not ok then return false,why end
    front.in_depot=nil
    return true
  end

  -- VehicleEnterTile_Rail hides each returning part separately. Do not
  -- release the shared depot bit until the last physical part has entered.
  function R.hide_returning(board,state,train_id,index,depot_id)
    local train=state.trains[train_id]
    local part=train and train.parts[index]
    local depot=tile(board,depot_id)
    if not part or not depot or depot.kind~="depot" or depot.owner~=train.owner or
        part.tile~=depot_id or part.in_depot or T.exit_side(part.td)~=rev(depot.dir) then
      return false,"invalid_returning_depot_part"
    end
    for i=1,index-1 do
      if not train.parts[i].in_depot or train.parts[i].tile~=depot_id then return false,"depot_entry_order" end
    end
    train.parts[index]={tile=depot_id,td=part.td,in_depot=true}
    return true
  end
  function R.finish_returning(board,state,train_id,depot_id)
    local train=state.trains[train_id]
    local depot=tile(board,depot_id)
    if not train or not depot or depot.kind~="depot" or depot.owner~=train.owner then
      return false,"invalid_depot"
    end
    for _,part in ipairs(train.parts) do
      if not part.in_depot or part.tile~=depot_id then return false,"tail_not_in_depot" end
    end
    local td=T.diagonal_trackdir(depot.dir)
    if R.claim_owner(state,depot_id,T.track(td))==train_id then
      if not release(board,state,train,depot_id,T.track(td)) then return false,"missing_depot_claim" end
    end
    for i=1,#train.parts do train.parts[i]={tile=depot_id,td=td,in_depot=true} end
    return true
  end

  -- Stock chosen_track for a wagon whose predecessor already occupies the
  -- next tile or is one tile beyond it. Only the ordinary branch is here.
  function R.connecting_track(enterdir,exitdir)
    return connect[enterdir][exitdir]
  end

  local function wagon_choice(board,prior,new_id,enterdir)
    if prior.tile==new_id then return T.trackbit(T.track(prior.td)) end
    for exit=0,3 do
      if board.adjacent(new_id,exit)==prior.tile then return R.connecting_track(enterdir,exit) end
    end
    return 0
  end

  local function pbs_along(t,td)
    if t.kind~="signals" then return false end
    local track=T.track(td)
    local second=track==T.LOWER or track==T.RIGHT
    local typ
    if second then typ=t.lower_signal_type or (t.lower_pbs and 4 or 0)
    else typ=t.upper_signal_type or (t.upper_pbs and 4 or 0) end
    return (typ==4 or typ==5) and band(t.present_signals or 0,T.signal_along(td))~=0
  end

  local function tail_clear(board,state,train,old,exitdir,publish)
    local function drop(id,track)
      if release(board,state,train,id,track) then
        publish{kind="tail_released",phase="before_position",tile=id,track=track,
          train=train.id}
      end
    end
    local t=board.tile(old.tile)
    if t.kind=="station" then
      local still_platform=F.platform(board,old.tile,exitdir)>1
      if not still_platform then
        local back=rev(exitdir)
        local count=F.platform(board,old.tile,back)
        local id=old.tile
        for _=1,count do
          drop(id,t.axis)
          id=board.adjacent(id,back)
        end
      end
    else
      drop(old.tile,T.track(old.td))
    end
  end

  -- Allocate a stock safe-target reservation chosen by PBS.choose_target.
  -- PBS first journals map bits. If any claimed tile belongs outside this
  -- ordinary consist model, restore just that successful attempt's bits.
  function R.reserve_path(board,state,id,target,settings)
    local train=state.trains[id]
    if not train then return false,"invalid_train" end
    local v={owner=train.owner,railtype=train.engine_railtype or 0,compatible=F.stock_traction(train.engine_railtype,train.traction_railtypes)}
    local ok,claims,at=PBS.try_path(board,state.bits,v,target,settings)
    if not ok then return false,claims,at end
    local bad
    for _,entry in ipairs(claims) do
      local t=tile(board,entry.tile)
      if not ordinary(t) or t.owner~=train.owner or
          R.claim_owner(state,entry.tile,entry.track)~=nil then bad=entry.tile;break end
    end
    if bad then
      for i=#claims,1,-1 do
        local entry=claims[i]
        assert(PBS.unreserve(board,state.bits,entry.tile,entry.track))
      end
      return false,"unsupported_claim",bad
    end
    for _,entry in ipairs(claims) do set_owner(state,entry.tile,entry.track,id) end
    return true,claims
  end

  -- Called only for an approved tile-boundary crossing, after route/path
  -- and signal authorization but before consuming its physics step. Same-
  -- tile movement is not an event. Entry claiming is refused on conflicts
  -- and must not touch any other occupancy or schedule state.
  --
  -- Events are returned in stock order. Apply signal mutations separately:
  -- a front engine crossing a PBS signal closes it BEFORE position commit;
  -- only the rear part releases the old track. Block/crossing recalculation
  -- comes AFTER the new position is recorded. A one-part train does both.
  -- Optional observe(event) sees the state at the event point. It must be
  -- read-only and must not throw/re-enter the adapter.
  function R.enter(board,state,train_id,index,new_id,new_td,settings,observe,permit_unreserved)
    local train=state.trains[train_id]
    local old=train and train.parts[index]
    if not old then return false,"invalid_part" end
    if not T.valid_trackdir(new_td) then return false,"invalid_track" end
    local prev,new=tile(board,old.tile),tile(board,new_id)
    if not ordinary(prev) or not ordinary(new) then return false,"unsupported_tile" end
    if new.owner~=train.owner or prev.owner~=train.owner then return false,"foreign_tile" end
    -- TrainController calls CheckCompatibleRail on the first unit with
    -- IsMovingFront(). Trailing wagons follow the precedent unit's track.
    if index==1 then
      local powered=F.stock_traction(train.engine_railtype,train.traction_railtypes)
      if not powered or not powered[new.railtype] then return false,"incompatible_railtype" end
    end
    local old_track=T.track(old.td)
    if not old.unreserved and (R.claim_owner(state,old.tile,old_track)~=train_id or
        not has(PBS.bits(board,state.bits,old.tile),old_track)) then return false,"missing_claim" end
    local exit=T.exit_side(old.td)
    if board.adjacent(old.tile,exit)~=new_id or T.entry_side(new_td)~=rev(exit) or
        not has(T.status(new,rev(exit)),new_td) then return false,"incompatible_boundary" end
    if index==1 and F.disallow_90(board,prev.railtype,new.railtype,settings and settings.forbid_90 or false) and
        has(T.crossing_trackdirs(old.td),new_td) then return false,"turn_disallowed" end
    local track=T.track(new_td)
    local unreserved
    if index~=1 then
      if band(wagon_choice(board,train.parts[index-1],new_id,exit),T.trackbit(track))==0 then
        return false,"wagon_off_consist_path"
      end
      if R.claim_owner(state,new_id,track)~=train.id then
        if not permit_unreserved then return false,"wagon_unreserved" end
        unreserved=true
      end
    else
      local ok,why=claim(board,state,train,new_id,track)
      -- RC1 TrainController tries to set a raw track reservation on a
      -- non-red approach, but a failed write does not cancel the step.
      -- This is distinct from passing a PBS head, which needs a path.
      if not ok then
        if not (permit_unreserved and (why=="reserved" or why=="overlap")) then return false,why end
        unreserved=true
      end
    end
    local events={}
    local function publish(event)
      events[#events+1]=event
      if observe then observe(event) end
    end
    if index==1 and pbs_along(new,new_td) then
      publish{kind="front_passed_pbs",phase="before_position",tile=new_id,td=new_td,
        train=train_id,aspect="red"}
    end
    if index==#train.parts then tail_clear(board,state,train,old,exit,publish) end
    train.parts[index]={tile=new_id,td=new_td,unreserved=unreserved}
    if index==1 then
      publish{kind="front_entered",phase="after_position",tile=new_id,enterdir=exit,
        td=new_td,train=train_id}
    end
    if index==#train.parts then
      publish{kind="tail_left",phase="after_position",tile=old.tile,enterdir=rev(exit),
        td=old.td,train=train_id,refresh_crossing=prev.kind=="crossing"}
    end
    return true,events
  end

  -- Crash clears the path beyond real bodies and then reserves the track
  -- under the consist. Disjoint parts and other trains' raw claims stay.
  function R.crash(board,state,train_id)
    local train=assert(state.trains[train_id])
    train.crashed=true
    local occupied={}
    for _,p in ipairs(train.parts) do
      if not p.in_depot then
        local track=T.track(p.td)
        occupied[p.tile]=T.union(occupied[p.tile] or 0,2^track)
        local tile_record=board.tile(p.tile)
        if tile_record and tile_record.other and (tile_record.kind=="bridge" or tile_record.kind=="tunnel") then
          occupied[tile_record.other]=T.union(occupied[tile_record.other] or 0,2^track)
        end
      end
    end
    local released={}
    for id,tracks in pairs(state.claims) do
      for track,owner in pairs(tracks) do
        if owner==train_id and not has(occupied[id] or 0,track) then
          released[#released+1]={tile=id,track=track}
        end
      end
    end
    table.sort(released,function(a,b)return a.tile<b.tile or a.tile==b.tile and a.track<b.track end)
    for _,p in ipairs(released) do assert(release(board,state,train,p.tile,p.track)) end
    for _,p in ipairs(train.parts) do
      if not p.in_depot and p.unreserved and ordinary(board.tile(p.tile)) then
        local ok=claim(board,state,train,p.tile,T.track(p.td))
        p.unreserved=not ok or nil
      end
    end
    return released
  end

  -- DeleteLastWagon: keep the rail blocked until the last wreck on
  -- that track is gone. An underlapping train can re-acquire afterward.
  function R.remove_wreck_tail(board,state,train_id)
    local train=state.trains[train_id]
    if not (train and train.crashed) or #train.parts==0 then return end
    local gone=table.remove(train.parts)
    R.crash(board,state,train_id)
    local track=T.track(gone.td)
    for id,other in pairs(state.trains) do
      if id~=train_id then
        for _,p in ipairs(other.parts) do
          if p.unreserved and p.tile==gone.tile and T.track(p.td)==track then
            local ok=claim(board,state,other,p.tile,track)
            p.unreserved=not ok or nil
          end
        end
      end
    end
    return gone
  end
  return R
end
