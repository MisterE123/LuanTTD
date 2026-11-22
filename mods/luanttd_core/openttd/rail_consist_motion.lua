-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- Ordinary consist movement from OpenTTD 14.1 TrainController,
-- Train::CalcNextVehicleOffset, and VehicleEnter_Track/TicksToLeaveDepot.
-- No rail-reservation writes, signal propagation, routing, reversals or spans.
return function(T,Motion,Follow,Lifecycle)
  local R={VERSION=1,MAX_PART_LENGTH=8}
  local floor,abs,max=math.floor,math.abs,math.max
  local spawn_x,spawn_y={[0]=10,8,4,8},{[0]=8,4,8,10}
  local dx,dy={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  local function legal_length(n) return type(n)=="number" and n%1==0 and n>=1 and n<=R.MAX_PART_LENGTH end

  -- Stock treats odd lengths asymmetrically, at the coupling boundary.
  function R.next_offset(length,next_length)
    return floor(length/2)+floor(((next_length or -1)+1)/2)
  end

  function R.chebyshev(a,b) return max(abs(a.x-b.x),abs(a.y-b.y)) end

  -- Called for the active part preceding a hidden part in an outbound
  -- depot. Positive means the count of steps before the predecessor
  -- proposed position flips the following wagon's DEPOT mode.
  function R.ticks_to_leave_depot(direction,x,y,length,next_length)
    local n=R.next_offset(length,next_length)+1
    return (spawn_x[direction]+n*dx[direction]-x%16)*dx[direction]+
      (spawn_y[direction]+n*dy[direction]-y%16)*dy[direction]
  end

  -- Stock VehicleEnter_Track compares both axes of the proposed position
  -- against the byte-coded leaving point, not just longitudinal distance.
  function R.depot_activation(direction,x,y,length,next_length)
    if not next_length then return false end
    local n=R.next_offset(length,next_length)+1
    return x%16==spawn_x[direction]+n*dx[direction] and
      y%16==spawn_y[direction]+n*dy[direction]
  end

  function R.seed_depot(board,id,lengths)
    local depot=board.tile(id)
    if not depot or depot.kind~="depot" or not depot.dir then return nil,"invalid_depot" end
    if #lengths==0 then return nil,"empty_consist" end
    local tx,ty=board.xy(id)
    local dir=depot.dir
    local out={version=R.VERSION,serial=0,parts={},owner=depot.owner}
    for i,n in ipairs(lengths) do
      if not legal_length(n) then return nil,"invalid_length" end
      out.parts[i]={tile=id,length=n,hidden=true,pose={x=16*tx+spawn_x[dir],y=16*ty+spawn_y[dir],
        tx=tx,ty=ty,td=T.diagonal_trackdir(dir),direction=dir*2+1}}
    end
    return out
  end

  -- Caller handles CheckTrainStayInDepot (wait, block, order, reservations)
  -- before releasing the front. Hidden following parts leave on their own
  -- stock positional trigger in the same movement pass as their predecessor.
  function R.release_front(consist)
    local p=consist.parts[1]
    if not p.hidden then return false end
    p.hidden=false
    consist.serial=consist.serial+1
    return true
  end

  local function same_position(p,q)
    return p.x==q.x and p.y==q.y and p.tx==q.tx and p.ty==q.ty and
      p.td==q.td and p.direction==q.direction
  end

  -- Corresponds to CheckTrainsLengths's ordinary, non-crashed diagnostic.
  -- A hidden wagon in an outbound depot has not yet separated, except
  -- that the active predecessor cannot have missed its departure trigger.
  function R.check_spacing(board,consist)
    for i=1,#consist.parts-1 do
      local a,b=consist.parts[i],consist.parts[i+1]
      if not a.hidden then
        if b.hidden then
          local tile=board.tile(a.tile)
          if a.tile~=b.tile or not tile or tile.kind~="depot" or
              R.ticks_to_leave_depot(tile.dir,a.pose.x,a.pose.y,a.length,b.length)<=0 then
            return false,i,"missed_depot_activation"
          end
        elseif R.chebyshev(a.pose,b.pose)~=R.next_offset(a.length,b.length) then
          return false,i,"spacing"
        end
      elseif not b.hidden or a.tile~=b.tile or not same_position(a.pose,b.pose) then
        return false,i,"hidden_consist"
      end
    end
    return true
  end

  local function stock_tile(t)
    return t and (t.kind=="rail" or t.kind=="signals" or t.kind=="crossing" or
      t.kind=="station" or t.kind=="waypoint" or t.kind=="depot")
  end

  local function clone(parts)
    local out={}
    for i,p in ipairs(parts) do
      out[i]={tile=p.tile,length=p.length,hidden=p.hidden,pose=p.pose}
    end
    return out
  end

  -- Initialize ordinary already-separated units on a plain section for
  -- tests or imported positions. Poses are real ordered stock subcoords.
  function R.place(board,owner,parts)
    if #parts==0 then return nil,"empty_consist" end
    local found={version=R.VERSION,owner=owner,serial=0,parts=clone(parts)}
    for _,p in ipairs(found.parts) do
      if p.hidden or not legal_length(p.length) or not p.pose or not T.valid_trackdir(p.pose.td) or
          board.tile_at(p.pose.tx,p.pose.ty)~=p.tile or
          p.pose.tx~=floor(p.pose.x/16) or p.pose.ty~=floor(p.pose.y/16) then
        return nil,"invalid_position"
      end
      local record=board.tile(p.tile)
      if not stock_tile(record) or record.owner~=owner or
          not T.has(T.status(record),p.pose.td) or T.heading(p.pose.td)~=p.pose.direction then
        return nil,"invalid_track"
      end
    end
    local ok,_,why=R.check_spacing(board,found)
    if not ok then return nil,why end
    return found
  end

  local function stock_wagon_td(board,prior,next_tile,enterdir)
    local mask=0
    if prior.tile==next_tile then
      mask=T.trackbit(T.track(prior.pose.td))
    else
      for dir=0,3 do
        if board.adjacent(next_tile,dir)==prior.tile then
          mask=Lifecycle.connecting_track(enterdir,dir)
          break
        end
      end
    end
    if mask==0 then return end
    for index=0,5 do
      if T.has(mask,index) then return T.trackdir_for_entry(index,enterdir) end
    end
  end

  -- Proposes one TrainController movement step, in stock front-to-back
  -- order (not one elapsed tick). head_choice(from,next_tile,enterdir,
  -- reachable_trackdirs) is read-only. Wagon track choice never calls it.
  -- A denied/invalid boundary leaves all input poses, visibility and event
  -- state unchanged. Advance the reservation lifecycle in the same order
  -- as transitions before committing this proposal. Station loading is a
  -- caller reaction to a successful front sample and does not skip wagons.
  function R.plan(board,consist,head_choice,settings)
    if consist.version~=R.VERSION or consist.parts[1].hidden then return nil,"held_in_depot" end
    local parts=clone(consist.parts)
    local transitions,reveals={},{}
    for i,v in ipairs(parts) do
      if not v.hidden then
        local old=v.pose
        local candidate=Motion.advance(old)
        if candidate.invalid then return nil,"invalid_boundary",i end
        if candidate.crossing then
          local into=board.tile_at(candidate.tx,candidate.ty)
          if not into or board.adjacent(v.tile,candidate.enterdir)~=into then
            return nil,"invalid_boundary",i
          end
          local a,b=board.tile(v.tile),board.tile(into)
          if not stock_tile(a) or not stock_tile(b) or b.owner~=consist.owner or
              b.kind=="depot" then
            return nil,"unsupported_track",i
          end
          local travel=candidate.enterdir
          local reachable=T.intersect(T.status(b,T.reverse_side(travel)),T.reachable(travel))
          if i==1 and Follow.disallow_90(board,a.railtype,b.railtype,settings and settings.forbid_90 or false) then
            reachable=T.remove(reachable,T.crossing_trackdirs(old.td))
          end
          local td
          if i==1 then td=head_choice and head_choice(v.tile,into,travel,reachable)
          else td=stock_wagon_td(board,parts[i-1],into,travel) end
          if not T.valid_trackdir(td) or not T.has(reachable,td) then
            return nil,i==1 and "blocked_front" or "wagon_off_consist_path",i
          end
          local p=Motion.entry(candidate.tx,candidate.ty,T.track(td),travel)
          if not p or p.td~=td then return nil,"invalid_boundary",i end
          transitions[#transitions+1]={index=i,old_tile=v.tile,old_td=old.td,tile=into,td=td,
            enterdir=travel,front=i==1,tail=i==#parts}
          v.tile=into
          v.pose=p
        else
          local tile=board.tile(v.tile)
          if not stock_tile(tile) or tile.owner~=consist.owner then return nil,"unsupported_track",i end
          if tile.kind=="depot" then
            -- Outbound only. Entering/hiding the chain is a depot order
            -- with a different lifecycle and is not enabled here.
            if old.direction~=2*tile.dir+1 then return nil,"inbound_depot",i end
            local next_=parts[i+1]
            if next_ and next_.hidden and R.depot_activation(tile.dir,candidate.x,candidate.y,v.length,next_.length) then
              next_.hidden=false
              reveals[#reveals+1]={index=i+1,tile=next_.tile}
            end
          end
          v.pose=candidate
        end
      end
    end
    return {base_serial=consist.serial,parts=parts,transitions=transitions,reveals=reveals}
  end

  function R.commit(consist,proposal)
    if proposal.base_serial~=consist.serial then return false,"stale_proposal" end
    consist.parts=proposal.parts
    consist.serial=consist.serial+1
    return true
  end

  return R
end
