-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 16.0-RC1 train_cmd.cpp ReverseTrainDirection, ReverseTrainSwapVehicles,
-- AdvanceWagons{Before,After}Swap and FreeTrainTrackReservation.
-- Ordinary, stopped, fully visible consists only. Fully hidden same-depot
-- consists are a no-op; partially hidden consists and spans are excluded.
return function(T,Raw,Consist,Life,Signal,Follow,PBS)
  local R={}
  local ordinary_traction={[0]=true,[1]=true}
  local function copy(source)
    local out={}
    for k,v in pairs(source) do out[k]=v end
    return out
  end
  local function ordinary(t)
    return t and (t.railtype==0 or t.railtype==1) and
      (t.kind=="rail" or t.kind=="signals" or t.kind=="crossing" or t.kind=="station" or t.kind=="waypoint")
  end
  local function stock_advance(board,parts,first,last,owner,adjustments,phase)
    for i=first,last do
      local v,prev=parts[i],parts[i-1]
      local candidate=Raw.advance(v.pose)
      if candidate.invalid then return false end
      if not candidate.crossing then v.pose=candidate
      else
        local id=board.tile_at(candidate.tx,candidate.ty)
        local tile=id and board.tile(id)
        if not ordinary(tile) or tile.owner~=owner or board.adjacent(v.tile,candidate.enterdir)~=id then return false end
        local mask=0
        if prev.tile==id then mask=2^T.track(prev.pose.td)
        else
          for d=0,3 do
            if board.adjacent(id,d)==prev.tile then mask=Life.connecting_track(candidate.enterdir,d);break end
          end
        end
        local previous=v.tile
        local has_track=false
        for track=0,5 do
          if mask==2^track then
            local p=Raw.entry(candidate.tx,candidate.ty,track,candidate.enterdir)
            if not p or not T.has(T.status(tile,T.reverse_side(candidate.enterdir)),p.td) then return false end
            v.pose=p;v.tile=id;has_track=true
            adjustments[#adjustments+1]={index=i,from=previous,tile=id,td=p.td,phase=phase}
            break
          end
        end
        if not has_track then return false end
      end
    end
    return true
  end
  local function next_offset(parts,i)
    return Consist.next_offset(parts[i].length,parts[i+1] and parts[i+1].length)
  end
  local function snake_adjust(board,v,owner,after,out)
    local base,first,last,length=1,1,#v,#v
    while length>2 do
      last=last-1;first=first+1
      local diff=next_offset(v,base)-next_offset(v,last)
      if after then diff=-diff end
      for _=1,diff do
        if not stock_advance(board,v,first,last,owner,out,after and "after_swap" or "before_swap") then return false end
      end
      base=first;length=length-2
    end
    return true
  end

  function R.plan(board,consist,opts)
    if not consist or consist.version~=Consist.VERSION or #consist.parts==0 or
        opts and opts.speed and opts.speed~=0 then return nil,"not_stopped" end
    local old,tiles=consist.parts,{}
    local start=board.tile(old[1].tile)
    if start and start.kind=="depot" and old[1].hidden then
      for _,p in ipairs(old) do
        if not p.hidden or p.tile~=old[1].tile then return nil,"unsupported_partial_depot" end
      end
      return {base_serial=consist.serial,noop=true}
    end
    for i,p in ipairs(old) do
      local t=board.tile(p.tile)
      if p.hidden or not ordinary(t) or t.owner~=consist.owner then return nil,"unsupported_tile",i end
      tiles[i]=copy(p)
    end
    local checked,err=Consist.place(board,consist.owner,old)
    if not checked then return nil,err end
    local out={base_serial=consist.serial,parts=tiles,adjustments={},reversed=not consist.reversed}
    local back_up=consist.driving_backwards or consist.last_can_lead or opts and opts.flip_allowed=="none"
    if back_up then
      -- The simulation stores moving-front order. Reverse the iteration
      -- order, not the wagons' physical positions or their identities.
      -- Pose directions are travelling headings, so the movement
      -- adapter needs their reverse even though the bodies do not turn.
      for i,src in ipairs(old) do
        local part=copy(src)
        part.pose=copy(src.pose)
        part.pose.direction=(src.pose.direction+4)%8
        part.pose.td=T.reverse_trackdir(src.pose.td)
        part.pose.enterdir=nil
        tiles[#old-i+1]=part
      end
      out.driving_backwards=not consist.driving_backwards
    else
      if not snake_adjust(board,tiles,consist.owner,false,out.adjustments) then return nil,"before_swap" end

      -- Stock swaps physical state, not vehicle IDs, length, cargo, or
      -- predecessor links. In simulated chain order the locomotive remains
      -- the locomotive, and the new head uses the old rear's location.
      local place={}
      for i,p in ipairs(tiles) do place[i]={tile=p.tile,pose=p.pose,hidden=p.hidden} end
      for i,p in ipairs(tiles) do
        local src=place[#tiles-i+1]
        p.tile=src.tile;p.hidden=src.hidden
        local pose=copy(src.pose)
        pose.direction=(pose.direction+4)%8
        pose.td=T.reverse_trackdir(pose.td)
        pose.enterdir=nil
        p.pose=pose
      end
      if not snake_adjust(board,tiles,consist.owner,true,out.adjustments) then return nil,"after_swap" end
    end
    -- CheckTrainsLengths is a separate diagnostic, not part of the
    -- source's swap. Report its result rather than rewriting the poses.
    local head=tiles[1]
    out.spacing_ok=Consist.check_spacing(board,{parts=tiles})
    out.origin={tile=head.tile,td=head.pose.td}
    local t=board.tile(head.tile)
    out.first_tile_okay=not (Signal.along(t,head.pose.td) and not Signal.pbs(Signal.signal_type(t,head.pose.td)))
    return out
  end

  -- Run only when the order controller reports a new destination,
  -- matching TrainLocoHandler -> CheckReverseTrain. The 1-unit reverse
  -- origin penalty distinguishes branches and favors forward on a tie.
  -- Stock's in-wormhole distance adjustments are outside this adapter.
  function R.check_order(board,consist,order,Costs,Search,settings)
    settings=settings or {}
    local head,tail=consist.parts[1],consist.parts[#consist.parts]
    if not head or (settings.line_reverse_mode or 0)~=0 or head.pose.direction%2==0 then return false end
    local length=0
    for _,part in ipairs(consist.parts) do
      if part.hidden or not ordinary(board.tile(part.tile)) then return false end
      length=length+part.length
    end
    local v={owner=consist.owner,tile=head.tile,railtype=consist.engine_railtype or 0,
      compatible=consist.traction_railtypes or ordinary_traction,
      length=length,max_speed=settings.max_speed or 80}
    if order.kind=="station" or order.kind=="waypoint" then
      local box,sign=board.station_area(order.station,order.kind)
      if not box and sign==nil then return false end
    elseif order.tile==nil or not board.tile(order.tile) then return false end
    local dest=Costs.destination(board,v,order)
    local found,best=Search.find(board,v,{tile=head.tile,td=head.pose.td},dest,settings,
      {reverse_origin={tile=tail.tile,td=T.reverse_trackdir(tail.pose.td)},reverse_penalty=1})
    if not found then return false end
    local origin=best
    while origin.parent do origin=origin.parent end
    return origin.cost~=0,best
  end

  function R.commit(consist,proposal)
    if not proposal or consist.serial~=proposal.base_serial then return false,"stale_proposal" end
    if proposal.noop then return true end
    consist.parts=proposal.parts;consist.reversed=proposal.reversed;consist.serial=consist.serial+1
    consist.driving_backwards=proposal.driving_backwards or nil
    return true
  end

  local function first_dir(bits)
    for i=0,13 do if T.has(bits,i) then return i end end
  end
  local function check_registered(consist,state,id)
    local train=state.trains[id]
    if not train or #train.parts~=#consist.parts or train.owner~=consist.owner then return end
    for i,p in ipairs(consist.parts) do
      local r=train.parts[i]
      if p.tile~=r.tile or p.pose.td~=r.td or Life.claim_owner(state,p.tile,T.track(p.pose.td))~=id then return end
    end
    return train
  end

  -- FreeTrainTrackReservation starts strictly in front of the OLD head.
  -- Keep occupancy and old platform protected; stop at someone else's
  -- reservation, a facing red path signal, a blocking one-way signal, or
  -- just after clearing the first conventional signal.
  local function free_front(board,consist,state,id)
    local released,red,visited,removed={},{},{},{}
    local head=consist.parts[1]
    local at,td=head.tile,head.pose.td
    local t=board.tile(at)
    local old_station=t.kind=="station" and t.station or nil
    local free_tile=old_station==nil
    local v={tile=at,owner=consist.owner,railtype=consist.engine_railtype or 0,
      compatible=consist.traction_railtypes or ordinary_traction}
    if T.tracks_overlap(T.union(PBS.bits(board,state.bits,at),2^T.track(td))) then return released,red end
    local function drop(tile,track)
      local claims=removed[tile]
      if claims and claims[track] then return true end
      if Life.claim_owner(state,tile,track)~=id then return false end
      for _,p in ipairs(consist.parts) do
        if p.tile==tile and T.track(p.pose.td)==track then return false end
      end
      if not claims then claims={};removed[tile]=claims end
      claims[track]=true
      released[#released+1]={tile=tile,track=track}
      return true
    end
    while true do
      local f=Follow.follow(board,v,at,td)
      if not f.ok then break end
      at=f.tile;t=board.tile(at)
      if not ordinary(t) then break end
      local bits=T.intersect(f.trackdirs,T.trackdirs(PBS.bits(board,state.bits,at)))
      td=first_dir(bits)
      if td==nil then break end
      if bits~=2^td or visited[at] then return nil,"ambiguous_reserved_path" end
      visited[at]=true
      local track=T.track(td)
      if Life.claim_owner(state,at,track)~=id then break end
      if Signal.along(t,td) then
        if not Signal.pbs(Signal.signal_type(t,td)) then
          if not drop(at,track) then return nil,"occupied_old_path" end
          break
        end
        if Signal.aspect(t,td)=="red" then break end
        red[#red+1]={tile=at,td=td}
      elseif Signal.oneway_blocking(t,td) then break end

      if free_tile or not (f.station and t.station==old_station) then
        if t.kind=="station" then
          if Follow.platform(board,at,T.exit_side(td))==1 then
            local back=T.reverse_side(T.exit_side(td))
            local it=at
            for _=1,Follow.platform(board,at,back) do
              local claimant=Life.claim_owner(state,it,track)
              if claimant==id and not drop(it,track) or claimant and claimant~=id then return nil,"occupied_old_platform" end
              it=board.adjacent(it,back)
            end
          end
        elseif not drop(at,track) then return nil,"occupied_old_path" end
      end
      free_tile=true
    end
    return released,red
  end

  -- Integrates exact motion with the application's persisted ownership
  -- overlay. Path release and the replacement stock positions are staged;
  -- invalid imported occupancy leaves poses, signals and claims unchanged.
  function R.apply(base,consist,state,id,signals,opts)
    local board=Signal.view(base,signals)
    local plan,why,i=R.plan(board,consist,opts)
    if not plan then return nil,why,i end
    if plan.noop then return plan end
    local train=check_registered(consist,state,id)
    if not train then return nil,"inconsistent_train" end
    local released,red={},{}
    if not (opts and opts.stuck) then
      released,red=free_front(board,consist,state,id)
      if not released then return nil,red end
    end
    for _,step in ipairs(plan.adjustments) do
      if Life.claim_owner(state,step.tile,T.track(step.td))~=id then return nil,"unreserved_correction" end
    end
    local staged=copy(state)
    staged.trains=copy(state.trains)
    staged.bits=copy(state.bits)
    staged.claims=copy(state.claims)
    staged.trains[id]=copy(train)
    local latest={}
    for j,p in ipairs(plan.parts) do latest[j]={tile=p.tile,td=p.pose.td} end
    staged.trains[id].parts=latest
    for _,x in ipairs(released) do
      local claim=copy(staged.claims[x.tile])
      claim[x.track]=nil
      staged.claims[x.tile]=next(claim) and claim or nil
      if not PBS.unreserve(board,staged.bits,x.tile,x.track) then return nil,"invalid_release" end
    end
    local valid,reason=Life.valid_state(board,staged)
    if not valid then return nil,reason end
    local ok,err=R.commit(consist,plan)
    if not ok then return nil,err end
    state.trains=staged.trains;state.claims=staged.claims;state.bits=staged.bits
    for _,x in ipairs(red) do assert(Signal.set_aspect(base,signals,x.tile,x.td,false)) end
    plan.released=released;plan.signals_red=red
    return plan
  end
  return R
end
