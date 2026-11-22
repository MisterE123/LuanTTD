-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 rail_map.h, rail_cmd.cpp CmdBuildSingleSignal,
-- train_cmd.cpp ChooseTrainTrack, CheckNextTrainTile, TrainController and
-- TrainApproachingLineEnd. Pure stock direction/aspect/admission rules.
-- Segment propagation, timers executing reversals, and live AI not here.
return function(T)
  local R={VERSION=1,BLOCK=0,ENTRY=1,EXIT=2,COMBO=3,PBS=4,PBS_ONEWAY=5,
    FORCE_NONE=0,FORCE_STUCK=1,FORCE_SIGNAL=2,ELECTRIC=0,SEMAPHORE=1,DAY_TICKS=74}
  local band,bor,remove,has=T.intersect,T.union,T.remove,T.has
  local floor,min,max=math.floor,math.min,math.max
  local on_track={[0]=12,12,12,3,12,3}
  local function copy(source)
    local out={}
    for k,v in pairs(source) do out[k]=v end
    return out
  end
  local function secondary(track) return track==T.LOWER or track==T.RIGHT end
  local function first_dir(mask)
    for td=0,13 do if has(mask,td) then return td end end
  end
  local function first_track(mask)
    for track=0,5 do if has(mask,track) then return track end end
  end
  local function kill_first(mask)
    local low=first_track(mask)
    return low and mask-2^low or 0
  end

  function R.pbs(kind) return kind==R.PBS or kind==R.PBS_ONEWAY end

  function R.signal_type(t,td)
    if secondary(T.track(td)) then return t.lower_signal_type or (t.lower_pbs and R.PBS or R.BLOCK) end
    return t.upper_signal_type or (t.upper_pbs and R.PBS or R.BLOCK)
  end

  function R.along(t,td)
    return t~=nil and t.kind=="signals" and band(t.present_signals or 0,T.signal_along(td))~=0
  end

  function R.on_track(t,track)
    return t~=nil and t.kind=="signals" and band(t.present_signals or 0,on_track[track])~=0
  end

  function R.pbs_along(t,td)
    return R.along(t,td) and R.pbs(R.signal_type(t,td))
  end

  function R.oneway_blocking(t,td)
    return R.along(t,T.reverse_trackdir(td)) and not R.along(t,td) and R.signal_type(t,td)~=R.PBS
  end

  function R.aspect(t,td)
    if not R.along(t,td) then return nil end
    return band(t.green_signals or 0,T.signal_along(td))~=0 and "green" or "red"
  end

  local function normalized(t)
    if not t or t.kind~="signals" then return t end
    local out=copy(t)
    -- TrackStatus's two booleans encode ordinary, pass-from-behind PBS,
    -- not PBS_ONEWAY. Keep the aspect metadata in directional raw bits.
    out.upper_pbs=R.signal_type(t,T.UPPER)==R.PBS
    out.lower_pbs=R.signal_type(t,T.LOWER)==R.PBS
    return out
  end

  function R.status(tile,side)
    return T.status(normalized(tile),side)
  end

  function R.new() return {version=R.VERSION,records={}} end

  local function metadata(t)
    return {present_signals=t.present_signals or 0,green_signals=t.green_signals or 0,
      upper_signal_type=R.signal_type(t,T.UPPER),lower_signal_type=R.signal_type(t,T.LOWER),
      upper_variant=t.upper_variant or 0,lower_variant=t.lower_variant or 0}
  end

  -- Combine with the reservation overlay from the existing PBS adapter.
  -- Signal presence/type and signal aspect otherwise live independently.
  function R.view(board,state)
    local view=copy(board)
    function view.tile(id)
      local t=id~=nil and board.tile(id) or nil
      local rec=id~=nil and state.records[id] or nil
      if not rec or not t or (t.kind~="rail" and t.kind~="signals") then return normalized(t) end
      local out=copy(t)
      out.kind="signals"
      for k,v in pairs(rec) do out[k]=v end
      return normalized(out)
    end
    return view
  end

  -- The initial validation part of CmdBuildSingleSignal. Its conversion,
  -- side-cycle and financial branches are deliberately independent.
  function R.eligible(tile,owner,track,args)
    args=args or {}
    local kind,var=args.kind or R.PBS,args.variant or R.ELECTRIC
    local cycle_first,cycle_last=args.cycle_start or 0,args.cycle_stop or 5
    if kind<0 or kind>5 or var<0 or var>1 or
        cycle_first<0 or cycle_first>cycle_last or cycle_last>5 then return false,"parameter" end
    if not tile or (tile.kind~="rail" and tile.kind~="signals") or not on_track[track] or
        not has(tile.trackbits,track) then return false,"no_track" end
    local mask=args.copy_mask or 0
    if mask~=0 and band(mask,on_track[track])==0 then return false,"parameter" end
    if tile.owner~=owner then return false,"owner" end
    if T.tracks_overlap(tile.trackbits) then return false,"overlap" end
    local exists=R.on_track(tile,track)
    if args.skip and exists then return true,"skip" end
    if args.convert and not exists then return false,"no_signal" end
    return true,exists and "existing" or "new"
  end

  -- Stock CmdBuildSingleSignal initialization of a PBS aspect:
  -- reserve THIS physical track, and no vehicle anywhere on the tile.
  -- Changes only the present signals belonging to that track group.
  function R.placed_pbs_state(tile,track,reserved_bits,vehicle_on_ground)
    local mask=band(tile.present_signals or 0,on_track[track])
    local green=remove(tile.green_signals or 0,mask)
    if has(reserved_bits or 0,track) and not vehicle_on_ground then green=bor(green,mask) end
    return green
  end

  -- Build new signals only; does not perform infrastructure charging or
  -- mutate an existing signal's side/type. Passing copy_mask models stock
  -- same-track side copying for the command's facing mask.
  function R.place(board,state,owner,id,track,args,reserved_bits,occupied)
    args=args or {}
    local tile=R.view(board,state).tile(id)
    local ok,reason=R.eligible(tile,owner,track,args)
    if not ok or reason=="skip" then return ok,reason end
    if reason~="new" or args.convert then return false,"existing" end
    local kind,var=args.kind or R.PBS,args.variant or R.ELECTRIC
    local rec=metadata(tile)
    if tile.kind~="signals" then rec.green_signals=15 end
    local mask=args.copy_mask or 0
    if mask~=0 then mask=band(mask,on_track[track])
    elseif R.pbs(kind) then mask=kill_first(on_track[track])
    else mask=on_track[track] end
    rec.present_signals=bor(rec.present_signals,mask)
    local prefix=secondary(track) and "lower" or "upper"
    rec[prefix.."_signal_type"]=kind
    rec[prefix.."_variant"]=args.ctrl and 1-var or var
    if R.pbs(kind) then rec.green_signals=R.placed_pbs_state(rec,track,reserved_bits,occupied) end
    state.records[id]=rec
    return true
  end

  function R.set_aspect(board,state,id,td,green)
    local t=R.view(board,state).tile(id)
    if not R.along(t,td) then return false end
    local rec=metadata(t)
    local mask=T.signal_along(td)
    rec.green_signals=green and bor(rec.green_signals,mask) or remove(rec.green_signals,mask)
    state.records[id]=rec
    return true
  end

  function R.apply_consist_event(board,state,event)
    if event.kind~="front_passed_pbs" then return false end
    local t=R.view(board,state).tile(event.tile)
    return R.pbs_along(t,event.td) and R.set_aspect(board,state,event.tile,event.td,false)
  end

  -- Single facing PBS branch of ChooseTrainTrack. Existing reachable
  -- reservations bypass temporary aspect changes. Otherwise OpenTTD
  -- opens a facing PBS signal before the reservation attempt so the
  -- search can see through it, and restores red if the attempt fails.
  -- reserve() must report a path already acquired to a SAFE position.
  -- Handling intermediate choices/order fallbacks is the caller's job.
  function R.try_single_path_signal(board,state,id,enterdir,tracks,reserved_bits,reserve)
    local reachable=T.trackbits(T.reachable(enterdir))
    local existing=band(reserved_bits or 0,reachable)
    if existing~=0 then return first_track(existing),"already_reserved" end
    if tracks==0 or kill_first(tracks)~=0 then return nil,"junction" end
    local track=first_track(tracks)
    local td=T.trackdir_for_entry(track,enterdir)
    local t=R.view(board,state).tile(id)
    if not td or not R.pbs_along(t,td) then return track,"no_facing_pbs" end
    assert(R.set_aspect(board,state,id,td,true))
    local acquired=reserve(R.view(board,state),track,td)
    if not acquired then assert(R.set_aspect(board,state,id,td,false)) end
    return track,acquired and "reserved" or "reservation_failed"
  end

  -- Cache this BEFORE choosing track / making a PBS reservation on entry,
  -- as TrainController does. The raw red set is separate from the tracks
  -- after filtering unreachable 90-degree turns for the leading engine.
  function R.capture_entry(t,enterdir,old_td,forbid_90)
    local td,red=R.status(t,T.reverse_side(enterdir))
    local reachable=T.reachable(enterdir)
    td,red=band(td,reachable),band(red,reachable)
    local tracks=T.trackbits(td)
    if forbid_90 and old_td~=nil then tracks=remove(tracks,T.trackbits(T.crossing_trackdirs(old_td))) end
    return {trackdirs=td,tracks=tracks,red_tracks=T.trackbits(red)}
  end

  -- Front-engine gate after track choice. keep reverse execution and the
  -- opposing-train search / PBS segment classifier in the caller.
  -- Returns enter/wait/reverse; mutates only stock speed, force and wait
  -- fields on v. Uses the captured red result, NOT newly staged green.
  function R.entry_wait(t,entry,chosen_track,v,opts)
    opts=opts or {}
    local force=v.force or R.FORCE_NONE
    local along,against,first
    if force~=R.FORCE_NONE and t and t.kind=="signals" then
      first=first_dir(entry.trackdirs)
      if first~=nil then
        along,against=R.along(t,first),R.along(t,T.reverse_trackdir(first))
        if along or (against and R.signal_type(t,first)~=R.PBS) then
          force=force==R.FORCE_SIGNAL and R.FORCE_STUCK or R.FORCE_NONE
          v.force=force
        end
      end
    end
    if not has(entry.red_tracks,chosen_track) or force~=R.FORCE_NONE then return "enter" end
    if v.stuck then return "wait" end
    first=first or first_dir(entry.trackdirs)
    if first==nil then return "wait" end
    along,against=R.along(t,first),R.along(t,T.reverse_trackdir(first))
    local allow_reverse=opts.reverse_at_signals
    local function stop()
      v.speed=0;v.subspeed=0;v.progress=255
    end
    local function waited_less(days)
      if not allow_reverse then return true end
      v.wait_counter=((v.wait_counter or 0)+1)%65536
      return v.wait_counter<days*R.DAY_TICKS*2
    end
    if not against then
      stop()
      if waited_less(opts.wait_oneway_signal or 15) then return "wait" end
    elseif along then
      stop()
      if waited_less(opts.wait_twoway_signal or 41) and not opts.opposing_waiting then return "wait" end
    end
    if not allow_reverse and not R.oneway_blocking(t,first) and opts.pbs_segment then
      v.wait_counter=0
      return "wait"
    end
    if opts.execute_reverse~=false then
      v.wait_counter=0;v.speed=0;v.subspeed=0
    end
    return "reverse"
  end

  local approach={[0]=225,210,195,180,165,150,135,120,105,90,75,60,45,30,15,15}
  -- TrainApproachingLineEnd: red signal approach slows but doesn't turn
  -- here. A physical line end turns when the front reaches the tile edge.
  function R.approaching_end(v,signal)
    local dir=v.direction
    local x,y=v.x%16,v.y%16
    if dir==0 then x=23-x-y
    elseif dir==7 then x=15-y
    elseif dir==1 then x=15-x
    elseif dir==2 then x=8-x+y
    elseif dir==3 then x=y
    elseif dir==4 then x=x+y-7
    elseif dir==6 then x=8-y+x end
    x=x%4294967296
    local front=floor((v.front_length+1)/2)*(dir%2==1 and 1 or 2)
    if not signal and (x+front)%4294967296>=16 then
      v.speed=0
      return "reverse"
    end
    v.slowing=true
    local cap=approach[x%16]
    if cap<v.speed then v.speed=cap end
    return "approach",cap
  end

  return R
end
