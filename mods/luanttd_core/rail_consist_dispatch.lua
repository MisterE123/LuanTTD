-- Atomic adapter for the stock consist step and reservation lifecycle.
-- No invented path, speed, signal authority, or multiplayer scheduling.
return function(Motion,Life)
  local D={}
  local function copy(source)
    local out={}
    for k,v in pairs(source) do out[k]=v end
    return out
  end

  -- Lua 5.1 map with staged changes only at the affected tiles. Clone
  -- the per-tile ownership bucket on first use; the stock lifecycle edits
  -- those tables in place. No consumer iterates this transaction proxy.
  local function journal(source,buckets)
    local staged={}
    local proxy=setmetatable({},{
      __index=function(_,id)
        local v=staged[id]
        if v==false then return nil end
        if v~=nil then return v end
        v=source[id]
        if v~=nil and buckets then v=copy(v);staged[id]=v end
        return v
      end,
      __newindex=function(_,id,v)
        if v==nil then staged[id]=false else staged[id]=v end
      end,
    })
    local function publish()
      for id,v in pairs(staged) do
        if v==false then source[id]=nil else source[id]=v end
      end
    end
    return proxy,publish
  end

  function D.register(board,state,id,consist,waiting_in_depot)
    local parts={}
    for i,p in ipairs(consist.parts) do
      parts[i]={tile=p.tile,td=p.pose.td,in_depot=waiting_in_depot and p.hidden or nil}
    end
    return Life.register(board,state,id,consist.owner,parts,
      consist.engine_railtype and consist or nil)
  end

  -- The callback only grants permission; it cannot mutate the board,
  -- consist or the registry. Real signal aspect updates can use the
  -- returned ordered events only after this whole step succeeds.
  function D.step(board,state,id,consist,head_choice,settings,allowed,arbitrate,ordinary_train)
    local registered=state.trains[id]
    if not registered or registered.owner~=consist.owner or #registered.parts~=#consist.parts then
      return nil,"invalid_train"
    end
    for i,p in ipairs(registered.parts) do
      local part=consist.parts[i]
      if p.tile~=part.tile or p.td~=part.pose.td then return nil,"inconsistent_train",i end
    end
    local move,why,part=Motion.plan(board,consist,head_choice,settings)
    if not move then return nil,why,part end
    -- Ordinary within-tile steps do not touch occupancy, even when a
    -- hidden wagon becomes visible inside the depot.
    if #move.transitions==0 then
      local ok,reason=Motion.commit(consist,move)
      if not ok then return nil,reason end
      return {events={},reveals=move.reveals}
    end
    local train=copy(registered)
    train.parts=copy(registered.parts)
    local bits,publish_bits=journal(state.bits,false)
    local claims,publish_claims=journal(state.claims,true)
    local staged={version=state.version,trains={[id]=train},bits=bits,claims=claims}
    local events={}
    for _,t in ipairs(move.transitions) do
      local permit=ordinary_train
      if allowed and t.front then
        local ok,reason,strict=allowed(board,staged,t)
        if not ok then return nil,reason or "front_held",t.index end
        if strict then permit=false end
      end
      local ok,result=Life.enter(board,staged,id,t.index,t.tile,t.td,settings,nil,permit)
      if not ok then return nil,result,t.index end
      for _,event in ipairs(result) do events[#events+1]=event end
    end
    local function commit()
      local ok,reason=Motion.commit(consist,move)
      if not ok then return nil,reason end
      -- Commit is now infallible table bookkeeping. Until this point no
      -- early exit may leak a front claim, a wagon release, or an event.
      publish_bits();publish_claims()
      state.trains[id]=train
      return {events=events,reveals=move.reveals}
    end
    if arbitrate then return arbitrate(move.transitions,commit) end
    return commit()
  end
  return D
end
