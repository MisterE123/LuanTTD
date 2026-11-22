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
  local regular_power={[0]=true,[1]=true}

  local function ordinary(t)
    return t and (t.railtype==0 or t.railtype==1) and (t.kind=="rail" or t.kind=="signals" or t.kind=="crossing" or
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
      if train.id~=id or #train.parts==0 then return false,"train" end
      for _,p in ipairs(train.parts) do
        if not T.valid_trackdir(p.td) or R.claim_owner(state,p.tile,T.track(p.td))~=id then
          return false,"unclaimed_part"
        end
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
      local ok,why,new=claim(board,state,train,p.tile,track)
      if not ok then return fail(why) end
      if new then acquired[#acquired+1]={tile=p.tile,track=track} end
      train.parts[#train.parts+1]={tile=p.tile,td=p.td}
    end
    state.trains[id]=train
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
    local v={owner=train.owner,railtype=train.engine_railtype or 0,compatible=train.traction_railtypes or regular_power}
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
  function R.enter(board,state,train_id,index,new_id,new_td,settings,observe)
    local train=state.trains[train_id]
    local old=train and train.parts[index]
    if not old then return false,"invalid_part" end
    if not T.valid_trackdir(new_td) then return false,"invalid_track" end
    local prev,new=tile(board,old.tile),tile(board,new_id)
    if not ordinary(prev) or not ordinary(new) then return false,"unsupported_tile" end
    if new.owner~=train.owner or prev.owner~=train.owner then return false,"foreign_tile" end
    local old_track=T.track(old.td)
    if R.claim_owner(state,old.tile,old_track)~=train_id or
        not has(PBS.bits(board,state.bits,old.tile),old_track) then return false,"missing_claim" end
    local exit=T.exit_side(old.td)
    if board.adjacent(old.tile,exit)~=new_id or T.entry_side(new_td)~=rev(exit) or
        not has(T.status(new,rev(exit)),new_td) then return false,"incompatible_boundary" end
    if index==1 and F.disallow_90(board,prev.railtype,new.railtype,settings and settings.forbid_90 or false) and
        has(T.crossing_trackdirs(old.td),new_td) then return false,"turn_disallowed" end
    local track=T.track(new_td)
    if index~=1 then
      if band(wagon_choice(board,train.parts[index-1],new_id,exit),T.trackbit(track))==0 then
        return false,"wagon_off_consist_path"
      end
      if R.claim_owner(state,new_id,track)~=train.id then return false,"wagon_unreserved" end
    else
      local ok,why=claim(board,state,train,new_id,track)
      if not ok then return false,why end
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
    train.parts[index]={tile=new_id,td=new_td}
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

  return R
end
