-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright OpenTTD contributors. Port of OpenTTD 14.1 src/signal.cpp
-- SmallSet, ExploreSegment, UpdateSignalsAroundSegment and buffer drivers.
-- Map and physical train parts are provided by the host; no vehicle movement.
return function(T,Signal)
  local B={FREE="free",FULL="full",PBS="pbs",INVALID_SIDE=255,DEPOT=128,WORMHOLE=64}
  local U,D,G,FLUSH=64,256,128,64 -- SIG_TBU/TBD/GLOB_SIZE and SIG_GLOB_UPDATE
  local TRAIN,EXIT,EXIT2,GREEN,GREEN2,FULL,PBS=0,1,2,3,4,5,6
  local has,band,bor,reverse=T.has,T.intersect,T.union,T.reverse_side
  local first_side={[0]=0,1,0,1,2,1}
  local second_side={[0]=2,3,3,2,3,0}
  local incoming,incoming_tracks={},{}
  for side=0,3 do
    incoming[side]=T.reachable(reverse(side))
    incoming_tracks[side]=T.trackbits(incoming[side])
  end
  local function first(mask,max)
    for i=0,max do if has(mask,i) then return i end end
  end
  local function add(set,max,tile,dir)
    if #set==max then return false end
    set[#set+1]={tile,dir}
    return true
  end
  local function remove(set,tile,dir)
    for i,item in ipairs(set) do
      if item[1]==tile and item[2]==dir then
        set[i]=set[#set]
        set[#set]=nil
        return true
      end
    end
    return false
  end
  local function presignal_exit(sig) return sig==Signal.EXIT or sig==Signal.COMBO end
  local function presignal_entry(sig) return sig==Signal.ENTRY or sig==Signal.COMBO end
  local function rail(t) return t.kind=="rail" or t.kind=="signals" end
  local function station(t) return t.kind=="station" or t.kind=="waypoint" end
  local function span(t) return t.kind=="tunnel" or t.kind=="bridge" end

  -- train_tracks(tile) enumerates the *physical* parts on that tile (stock train
  -- TrackBits per part, including depot hidden and wormhole where applicable).
  -- Not a reservation mask: the block remains occupied by a tail even after
  -- its engine leaves. No train row is synthesized for ordinary road vehicles.
  -- vehicle.cpp EnsureNoTrainOnTrackProc is used for parallel half-tracks; in
  -- all other cases TrainOnTileEnum ignores only trains wholly inside a depot.
  local function occupied(train_tracks,tile,bits)
    local list=train_tracks(tile)
    for _,actual in ipairs(list or {}) do
      if bits==nil then
        if actual~=B.DEPOT then return true end
      elseif actual==bits or T.tracks_overlap(bor(actual,bits)) then
        return true
      end
    end
    return false
  end

  -- These three bounded work-sets retain the source order: popping is LIFO;
  -- removing a match swaps in the last element rather than rotating the array.
  local function scan(view,owner,train_tracks,glob,todo,update)
    local flags=0
    local function mark(bit) flags=bor(flags,2^bit) end
    local function detect(tile,bits)
      if not has(flags,TRAIN) and occupied(train_tracks,tile,bits) then mark(TRAIN) end
    end
    local function push(tile,dir,old,exit)
      remove(glob,tile,dir)
      remove(glob,old,exit)
      if remove(todo,old,exit) then return true end
      return add(todo,D,tile,dir)
    end
    while #todo>0 do
      local item=table.remove(todo)
      local tile,enter=item[1],item[2]
      local t=tile~=nil and view.tile(tile)
      if t and t.owner==owner then
        local exit=enter==B.INVALID_SIDE and enter or reverse(enter)
        local old=tile
        local advance=false
        if t.kind=="depot" then
          if enter==B.INVALID_SIDE then
            detect(tile)
            exit=t.dir
            tile,enter=view.adjacent(tile,exit),reverse(exit)
            advance=true
          elseif enter==t.dir then
            detect(tile)
          end
        elseif rail(t) then
          local tracks=t.trackbits
          local masked=band(tracks,assert(incoming_tracks[enter]))
          local connected=true
          if tracks==12 or tracks==48 then
            tracks=masked
            detect(tile,tracks)
          elseif masked==0 then
            connected=false
          else
            detect(tile)
          end
          if connected then
            local track=first(masked,5)
            if Signal.on_track(t,track) then
              local td=first(band(T.trackdirs(tracks),incoming[enter]),13)
              local rev=T.reverse_trackdir(td)
              local sig=Signal.signal_type(t,td)
              if Signal.along(t,rev) then
                if Signal.pbs(sig) then mark(PBS)
                elseif not add(update,U,tile,rev) then return bor(flags,2^FULL) end
              end
              if Signal.along(t,td) and sig==Signal.PBS then mark(PBS) end
              if not has(flags,GREEN2) and presignal_exit(sig) and Signal.along(t,td) then
                if has(flags,EXIT) then mark(EXIT2) end
                mark(EXIT)
                if Signal.aspect(t,td)=="green" then
                  if has(flags,GREEN) then mark(GREEN2) end
                  mark(GREEN)
                end
              end
            else
              for dir=0,3 do
                if dir~=enter and band(tracks,incoming_tracks[dir])~=0 then
                  if not push(view.adjacent(tile,dir),reverse(dir),tile,dir) then return bor(flags,2^FULL) end
                end
              end
            end
          end
        elseif (station(t) and not t.blocked or t.kind=="crossing") and enter%2==t.axis then
          detect(tile)
          tile=view.adjacent(tile,exit)
          advance=true
        elseif span(t) then
          if enter==B.INVALID_SIDE then
            detect(tile)
            enter,exit=t.dir,reverse(t.dir)
            tile=view.adjacent(tile,exit)
            advance=true
          elseif reverse(enter)==t.dir then
            detect(tile)
            tile,enter,exit=t.other,B.INVALID_SIDE,B.INVALID_SIDE
            advance=true
          end
        end
        if advance and not push(tile,enter,old,exit) then return bor(flags,2^FULL) end
      end
    end
    return flags
  end

  local function around(board,state,view,glob,update,flags,changes)
    while #update>0 do
      local item=table.remove(update)
      local id,td=item[1],item[2]
      local t=view.tile(id)
      local rev=T.reverse_trackdir(td)
      local kind=Signal.signal_type(t,td)
      local green=true
      if has(flags,TRAIN) then
        green=false
      elseif kind==Signal.COMBO and Signal.along(t,rev) then
        if has(flags,EXIT2) and (not has(flags,GREEN) or not has(flags,GREEN2) and Signal.aspect(t,rev)=="green") then
          green=false
        end
      elseif presignal_entry(kind) and has(flags,EXIT) and not has(flags,GREEN) then
        green=false
      end
      if green~=(Signal.aspect(t,td)=="green") then
        if presignal_exit(kind) then add(glob,G,id,T.exit_side(rev)) end
        Signal.set_aspect(board,state,id,td,green)
        changes[#changes+1]={tile=id,td=td,green=green}
      end
    end
  end

  local function update_all(board,state,owner,train_tracks,glob)
    local view=Signal.view(board,state)
    local changes,result,first_flags={},B.FREE,nil
    local function relevant(tile,side)
      if tile==nil then return false end
      return band(T.trackbits(T.status(view.tile(tile))),assert(incoming_tracks[side]))~=0
    end
    while #glob>0 do
      local item=table.remove(glob)
      local tile,dir=item[1],item[2]
      local t=tile~=nil and view.tile(tile)
      local todo,update={},{}
      if t and span(t) then
        assert(dir==B.INVALID_SIDE or dir==reverse(t.dir),"span update must start on the outward side")
        add(todo,D,tile,B.INVALID_SIDE)
        add(todo,D,t.other,B.INVALID_SIDE)
      elseif t and t.kind=="depot" then
        assert(dir==B.INVALID_SIDE or dir==t.dir,"depot update must start on the mouth side")
        add(todo,D,tile,B.INVALID_SIDE)
      elseif t and (rail(t) or station(t) or t.kind=="crossing") and relevant(tile,dir) then
        add(todo,D,tile,dir)
        add(todo,D,view.adjacent(tile,dir),reverse(dir))
      else
        assert(dir>=0 and dir<=3,"expected an ordinary tile side")
        local next_tile=tile~=nil and view.adjacent(tile,dir) or nil
        dir=reverse(dir)
        if relevant(next_tile,dir) then add(todo,D,next_tile,dir) end
      end
      if #todo>0 then
        local flags=scan(view,owner,train_tracks,glob,todo,update)
        if first_flags==nil then
          first_flags=flags
          if has(flags,PBS) then result=B.PBS
          elseif has(flags,TRAIN) or has(flags,EXIT) and not has(flags,GREEN) or has(flags,FULL) then result=B.FULL end
        end
        if has(flags,FULL) then
          -- ResetSets: no partial updates for the overflowing block.
          for i=#glob,1,-1 do glob[i]=nil end
          return result,changes,true,first_flags
        end
        around(board,state,view,glob,update,flags,changes)
      end
    end
    return result,changes,false,first_flags
  end

  -- UpdateSignalsOnSegment, e.g. after first/last part crosses a signal.
  -- 'side' is the tile edge, not travel direction into the tile. Start at
  -- exit_side(td) to update the block guarded by that signal head.
  -- On buffer overflow stock leaves existing aspects alone; admission must
  -- not read a stale green as success if the host sees an overflow.
  function B.update_segment(board,state,owner,train_tracks,tile,side)
    return update_all(board,state,owner,train_tracks,{{tile,side}})
  end

  -- TrainMovedChangeSignals: call after the first vehicle moves onto the
  -- new signal tile (travel direction), or after the last vehicle moves off
  -- the old signal tile (reverse travel direction). The occupancy snapshot
  -- must already reflect that physical move. The first return is stock's
  -- request to try PBS from a conventional signal in a mixed block.
  function B.train_moved_change_signals(board,state,train_tracks,tile,travel)
    local t=Signal.view(board,state).tile(tile)
    if not t or t.kind~="signals" then return false,{},false end
    local td=assert(first(band(T.trackdirs(t.trackbits),T.reachable(travel)),13),
      "train move did not reach a physical track on the signal tile")
    local segment,changes,overflow=B.update_segment(board,state,t.owner,train_tracks,tile,T.exit_side(td))
    return segment==B.PBS and Signal.along(t,td) and not Signal.pbs(Signal.signal_type(t,td)),changes,overflow
  end

  -- SetSignalsOnBothDir: used by stock build/remove operations.
  function B.update_track(board,state,owner,train_tracks,tile,track)
    return update_all(board,state,owner,train_tracks,{{tile,first_side[track]},{tile,second_side[track]}})
  end

  -- Source queued topology updates. Work-buffer state is transient; save the
  -- ordinary signal states after flushing a complete simulation step instead.
  -- entries[i]={tile=...,side=...} OR {tile=...,track=...}; a single stock owner.
  function B.update_buffer(board,state,owner,train_tracks,entries)
    local glob,changes,overflow={},{},false
    local function flush()
      local _,changed,over=update_all(board,state,owner,train_tracks,glob)
      overflow=overflow or over
      for _,c in ipairs(changed) do changes[#changes+1]=c end
    end
    for _,e in ipairs(entries) do
      if e.track~=nil then
        add(glob,G,e.tile,first_side[e.track])
        add(glob,G,e.tile,second_side[e.track])
      else add(glob,G,e.tile,e.side) end
      if #glob>=FLUSH then flush() end
    end
    flush()
    return changes,overflow
  end

  return B
end
