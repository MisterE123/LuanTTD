-- The engine owns materialized terrain, not the simulation. Keep at most
-- one in-flight repair, and forget jobs for sectors that left the viewport.
return function(render,on_result)
  local P={}
  local current,completed={},{}
  local busy
  local function key(w) return w.x..":"..w.z end
  local function same(a,b)
    return a and b and (a.scene and a.scene==b.scene or a==b)
  end
  function P.present(projection)
    local next_,changed={},false
    for _,receipt in ipairs(projection.windows()) do
      local w=receipt.value
      if w.tiles then
        local id=key(w)
        next_[id]=w
        if not same(w,current[id]) then changed=true end
      end
    end
    for id in pairs(current) do
      if not next_[id] then completed[id]=nil;changed=true end
    end
    current=next_
    if changed then render.use_worker_projection(projection) end
  end
  function P.step()
    if busy then return false end
    local next_,id
    for k,w in pairs(current) do
      if not same(w,completed[k]) and (not next_ or w.z<next_.z or w.z==next_.z and w.x<next_.x) then
        next_,id=w,k
      end
    end
    if not next_ then return false end
    busy=next_
    render.place_projected(next_.x,next_.z,next_.width,next_.height,function(ok,why)
      busy=nil
      -- An emerge job can finish after a newer reply or after leaving.
      -- Its completion cannot acknowledge terrain that it never drew.
      if ok and same(next_,current[id]) then completed[id]=next_ end
      if on_result then on_result(next_,ok,why) end
    end)
    return true
  end
  return P
end
