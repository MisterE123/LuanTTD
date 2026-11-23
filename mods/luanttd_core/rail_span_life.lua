-- Owner-attributed stock portal reservation overlay. Ordinary behavior
-- remains delegated to the stock lifecycle; both physical portal
-- flags are accounted together when a native wormhole is traversed.
return function(T,PBS,Life)
  local L={}
  local ordinary_traction={[0]=true,[1]=true}
  for k,v in pairs(Life) do L[k]=v end
  local function copy(x)
    local r={}
    for k,v in pairs(x) do r[k]=v end
    return r
  end
  local function span(t) return t and (t.kind=="bridge" or t.kind=="tunnel") and t.transport=="rail" end
  local function ordinary_view(board)
    local out=copy(board)
    function out.tile(id)
      local t=id~=nil and board.tile(id)
      if not span(t) then return t end
      local u=copy(t);u.kind="rail"
      return u
    end
    return out
  end
  function L.valid_state(board,state)
    local ok,why=Life.valid_state(ordinary_view(board),state)
    if not ok then return ok,why end
    for id,claims in pairs(state.claims) do
      local t=board.tile(id)
      if span(t) then
        local pair=board.tile(t.other)
        if not span(pair) or pair.kind~=t.kind or pair.other~=id or
            claims[t.axis]~=Life.claim_owner(state,t.other,t.axis) then return false,"unpaired_span" end
      end
    end
    return true
  end

  -- Stock ReserveRailTrack visits individual portal tiles through YAPF.
  -- This preview requires a route which covers both endpoints; publish
  -- after attribution succeeds so one invalid end leaves no partial path.
  function L.reserve_path(board,state,id,target,settings)
    local train=state.trains[id]
    if not train then return false,"invalid_train" end
    if not board.span_enabled then return Life.reserve_path(board,state,id,target,settings) end
    local bits=copy(state.bits)
    local v={owner=train.owner,railtype=train.engine_railtype or 0,compatible=train.traction_railtypes or ordinary_traction}
    local ok,claims,at=PBS.try_path(board,bits,v,target,settings)
    if not ok then return false,claims,at end
    local incoming={}
    for _,c in ipairs(claims) do
      local record=board.tile(c.tile)
      if not record or record.owner~=train.owner or not (record.railtype==0 or record.railtype==1 or record.railtype==2 or record.railtype==3) or Life.claim_owner(state,c.tile,c.track) or
          (record.kind~="rail" and record.kind~="signals" and record.kind~="station" and
           record.kind~="depot" and record.kind~="crossing" and record.kind~="waypoint" and not span(record)) then return false,"unsupported_claim",c.tile end
      local bucket=incoming[c.tile] or {};incoming[c.tile]=bucket;bucket[c.track]=true
    end
    for tile,claims_ in pairs(incoming) do
      local record=board.tile(tile)
      if span(record) then
        local other=incoming[record.other]
        if not (other and other[record.axis]) and Life.claim_owner(state,record.other,record.axis)~=id then
          return false,"unpaired_span",tile
        end
      end
    end
    for _,c in ipairs(claims) do
      local bucket=state.claims[c.tile] or {}
      state.claims[c.tile]=bucket
      bucket[c.track]=id
      state.bits[c.tile]=bits[c.tile]
    end
    return true,claims
  end

  function L.enter(board,state,id,index,new,td,settings,observe,permit_unreserved)
    if not board.span_enabled then return Life.enter(board,state,id,index,new,td,settings,observe,permit_unreserved) end
    local train=state.trains[id]
    local old=train and train.parts[index]
    if not old then return false,"invalid_part" end
    local p,q=board.tile(old.tile),board.tile(new)
    local from_span,to_span=span(p),span(q)
    if not from_span and not to_span then return Life.enter(board,state,id,index,new,td,settings,observe,permit_unreserved) end
    local own=function(tile,track) return Life.claim_owner(state,tile,track)==id end
    if from_span and new==p.other then
      if not to_span or q.other~=old.tile or p.kind~=q.kind or td~=old.td or
          T.exit_side(td)~=p.dir or not own(old.tile,p.axis) or not own(new,p.axis) then return false,"invalid_wormhole_exit" end
      train.parts[index]={tile=new,td=td}
      return true,{{kind="span_exited",phase="after_position",tile=new,from=old.tile,td=td,train=id,index=index}}
    end
    if to_span then
      if T.exit_side(td)~=q.dir then return false,"invalid_wormhole_entry" end
      local compatible=train.traction_railtypes or ordinary_traction
      if index==1 and not compatible[q.railtype] then return false,"incompatible_railtype" end
      if not own(new,q.axis) or not own(q.other,q.axis) then
        if not permit_unreserved or index~=1 then return false,"unreserved_span" end
        -- Ordinary RC1 approaches do not reserve an empty route ahead.
        -- The stock TrainController writes the approached span flag
        -- underneath the front; maintain the paired portal accounting
        -- when the same physical train enters the native wormhole.
        local other=board.tile(q.other)
        if not span(other) or other.other~=new or other.axis~=q.axis then return false,"invalid_wormhole_pair" end
        for _,tile in ipairs({new,q.other}) do
          if not own(tile,q.axis) then
            local ok=PBS.try_reserve(board,state.bits,tile,q.axis,false)
            if not ok then return false,"span_occupied" end
            state.claims[tile]={[q.axis]=id}
          end
        end
      end
    end
    local last_exiting=from_span and index==#train.parts and T.exit_side(old.td)==T.reverse_side(p.dir)
    if last_exiting then
      for i=1,#train.parts-1 do
        local part=train.parts[i]
        if part.tile==old.tile or part.tile==p.other then return false,"span_still_occupied" end
      end
      if not own(p.other,p.axis) then return false,"unpaired_span" end
    end
    local ok,events=Life.enter(ordinary_view(board),state,id,index,new,td,settings,observe,permit_unreserved and not to_span)
    if not ok then return ok,events end
    if last_exiting then
      -- ClearPathReservation's tunnel/bridge branch clears BOTH flags
      -- when the last unit has safely left the outbound portal.
      assert(PBS.unreserve(board,state.bits,p.other,p.axis))
      state.claims[p.other]=nil
      table.insert(events,#events,{kind="tail_released",phase="before_position",tile=p.other,track=p.axis,train=id})
      events[#events+1]={kind="span_released",phase="after_position",tile=old.tile,from=p.other,track=p.axis,train=id}
    end
    return ok,events
  end
  return L
end
