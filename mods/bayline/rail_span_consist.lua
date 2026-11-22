-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 VehicleEnter_TunnelBridge (train), PrepareToEnterBridge,
-- and TrainController's ordinary and wormhole paths. The wormhole's
-- logical tile stays at the entrance; x/y keep advancing one real pixel.
return function(T,Raw,Follow,Consist,Life)
  local P={}
  for k,v in pairs(Consist) do P[k]=v end
  local min,abs=math.min,math.abs
  local visibility={[0]=12,8,8,12}
  local function span(t) return t and (t.kind=="bridge" or t.kind=="tunnel") and t.transport=="rail" end
  local function copy(v)
    local q={}
    for k,x in pairs(v) do q[k]=x end
    return q
  end
  local function frame(d,p)
    local f=(d%2==0 and p.x or p.y)%16
    return (d==0 or d==3) and 15-f or f
  end
  function P.max_bridge_speed(board,consist)
    local cap
    for _,p in ipairs(consist.parts) do
      if p.wormhole and not p.hidden then
        local t=board.tile(p.tile)
        if t and t.kind=="bridge" then cap=min(cap or 65535,t.bridge_speed) end
      end
    end
    return cap
  end

  function P.check_spacing(board,consist)
    for _,v in ipairs(consist.parts) do
      if v.wormhole then
        for i=2,#consist.parts do
          local a,b=consist.parts[i-1],consist.parts[i]
          if not b.hidden or b.wormhole then
            if Consist.chebyshev(a.pose,b.pose)~=Consist.next_offset(a.length,b.length) then return false,i,"spacing" end
          end
        end
        return true
      end
    end
    return Consist.check_spacing(board,consist)
  end

  local function stock_tile(t)
    return t and (t.kind=="rail" or t.kind=="signals" or t.kind=="crossing" or
      t.kind=="station" or t.kind=="waypoint" or t.kind=="depot" or span(t))
  end
  local function stock_height(board,id,p)
    return board.stock_height(id,p.x%16,p.y%16)
  end
  local function wagon_td(board,prior,new,dir)
    if prior.tile==new then return T.trackdir_for_entry(T.track(prior.pose.td),dir) end
    for d=0,3 do
      if board.adjacent(new,d)==prior.tile then
        local mask=Life.connecting_track(dir,d)
        for tr=0,5 do if mask==2^tr then return T.trackdir_for_entry(tr,dir) end end
      end
    end
  end

  function P.plan(board,consist,head_choice,settings)
    if not board.span_enabled then return Consist.plan(board,consist,head_choice,settings) end
    if not consist.parts[1] or consist.parts[1].hidden and not consist.parts[1].wormhole then return nil,"held_in_depot" end
    local parts,transitions,reveals={},{},{}
    for i,p in ipairs(consist.parts) do parts[i]=copy(p);parts[i].span_speed=nil;parts[i].span_prepared=nil end
    for i,v in ipairs(parts) do
      if not v.hidden or v.wormhole then
        local old=v.pose
        local current=board.tile(v.tile)
        if not stock_tile(current) or current.owner~=consist.owner then return nil,"invalid_initial_tile",i end
        local candidate=Raw.advance(old)
        if candidate.invalid then return nil,"invalid_boundary",i end
        local dest=board.tile_at(candidate.tx,candidate.ty)
        local travel=candidate.enterdir
        local function logical_boundary(to,pose,dir,exiting)
          transitions[#transitions+1]={index=i,old_tile=v.tile,old_td=old.td,tile=to,td=pose.td,enterdir=dir,
            front=i==1,tail=i==#parts,wormhole_exit=exiting}
          v.tile=to
        end
        local prev_z=v.z
        if prev_z==nil then prev_z=stock_height(board,v.tile,old) end
        if prev_z==nil then return nil,"missing_stock_height",i end
        if v.wormhole then
          if not span(current) or current.dir~=T.exit_side(old.td) then return nil,"bad_wormhole",i end
          local opposite=board.tile(current.other)
          local dir=current.dir
          if not span(opposite) or opposite.other~=v.tile or opposite.kind~=current.kind then return nil,"bad_wormhole_pair",i end
          if dest==current.other then
            local fresh=stock_height(board,dest,candidate)
            if fresh==nil then return nil,"missing_exit_height",i end
            local clear=abs(fresh-prev_z)<=2 and
              (current.kind=="bridge" or frame(dir,candidate)==16-visibility[opposite.dir] and fresh==prev_z)
            if clear then
              if current.kind=="bridge" then v.span_speed=current.bridge_speed end
              logical_boundary(dest,candidate,dir,true)
              v.wormhole=nil;v.hidden=false;v.draw_tile=nil;v.z=fresh
            elseif current.kind=="bridge" or frame(dir,candidate)>=16-visibility[opposite.dir] then
              return nil,"wormhole_exit_height",i
            else v.z=prev_z end
          elseif dest~=v.tile and not (board.span_middle and board.span_middle(v.tile,dest)) then
            return nil,"unexpected_wormhole_tile",i
          else v.z=prev_z end
          v.pose=candidate
          if v.wormhole then v.draw_tile=dest end
        else
          local next_=current
          if candidate.crossing then
            next_=dest and board.tile(dest)
            if not stock_tile(next_) or next_.owner~=consist.owner or next_.kind=="depot" or
                board.adjacent(v.tile,travel)~=dest then return nil,"unsupported_track",i end
            local bits=T.intersect(T.status(next_,T.reverse_side(travel)),T.reachable(travel))
            if i==1 and Follow.disallow_90(board,current.railtype,next_.railtype,settings and settings.forbid_90 or false) then
              bits=T.remove(bits,T.crossing_trackdirs(old.td))
            end
            local td
            if i==1 then td=head_choice and head_choice(v.tile,dest,travel,bits)
            else td=wagon_td(board,parts[i-1],dest,travel) end
            if not T.valid_trackdir(td) or not T.has(bits,td) then return nil,"blocked_front",i end
            candidate=Raw.entry(candidate.tx,candidate.ty,T.track(td),travel)
            if not candidate then return nil,"invalid_boundary",i end
            logical_boundary(dest,candidate,travel)
          elseif current.kind=="depot" then
            if old.direction~=2*current.dir+1 then return nil,"inbound_depot",i end
            local next_part=parts[i+1]
            if next_part and next_part.hidden and Consist.depot_activation(current.dir,candidate.x,candidate.y,v.length,next_part.length) then
              next_part.hidden=false
              reveals[#reveals+1]={index=i+1,tile=next_part.tile}
            end
          end
          local fresh=stock_height(board,v.tile,candidate)
          if fresh==nil then return nil,"missing_stock_height",i end
          if span(next_) then
            local dir=T.exit_side(candidate.td)
            if abs(fresh-prev_z)>2 then return nil,"portal_height",i end
            local travelled=frame(dir,candidate)
            if next_.kind=="bridge" then
              v.span_speed=next_.bridge_speed
              if dir==next_.dir and travelled==15 then
                -- PrepareToEnterBridge amends z BEFORE UpdateInclination
                -- reads old_z. The last rise therefore does NOT apply the
                -- original acceleration model's once-per-pixel penalty.
                local deck=next_.deck*8
                if fresh~=deck or prev_z>deck or deck-prev_z>1 then return nil,"bridge_transition_height",i end
                v.span_prepared=true;v.wormhole=true;v.draw_tile=v.tile
              end
            elseif dir==next_.dir and travelled==visibility[dir] then
              v.hidden=true;v.wormhole=true;v.draw_tile=v.tile
            end
          end
          v.z=fresh;v.pose=candidate
        end
      end
    end
    return {base_serial=consist.serial,parts=parts,transitions=transitions,reveals=reveals}
  end
  return P
end
