-- SPDX-License-Identifier: GPL-2.0-only
-- Detached LuanTTD owner invalidation, not a new OpenTTD tile callback.
-- The protected layers mirror the native water_flood_world predicate.
local M={SCHEMA="luanttd-landscape-mutation/1",MAX_ENTRIES=4096,MAX_TOUCHED=16384}
local MAX_SAFE=9007199254740991
local floor,min=math.floor,math.min
local layers={level_crossing_tiles=true,bridge_above=true,aqueduct_above=true,tunnel_below=true,
  rail_bridge_above=true,rail_tunnel_below=true}
local function uint(v,lo,hi)
  return type(v)=="number" and v>=lo and v<=hi and floor(v)==v
end
local function plain(t) return type(t)=="table" and getmetatable(t)==nil end
local function keys(t,set)
  for k in pairs(t) do if not set[k] then return false end end
  return true
end
local head_fields={schema=true,world=true,revision=true,changes=true}
local cell_fields={kind=true,host=true,x=true,z=true}
local corner_fields={kind=true,x=true,z=true}
local layer_fields={kind=true,host=true,x=true,z=true,layer=true}

function M.new(cfg,scheduler,probe)
  assert(plain(cfg) and uint(cfg.log_x,6,12) and uint(cfg.log_z,6,12),"Missing stock lattice")
  local stride,rows=2^cfg.log_x,2^cfg.log_z
  local width,depth=cfg.width,cfg.depth
  assert(uint(width,1,stride) and uint(depth,1,rows),"Invalid physical world bounds")
  local id=cfg.world
  assert(type(id)=="string" and #id>=1 and #id<=96 and not id:find("[^%w_%.:/%-]"),"Invalid owner world ID")
  local revision=cfg.revision or 0
  local limit=cfg.active_limit or 65536
  assert(uint(revision,0,MAX_SAFE) and uint(limit,1,65536) and type(probe)=="function")
  limit=min(limit,stride*rows)
  assert(type(scheduler)=="table" and type(scheduler.set)=="function" and type(scheduler.contains)=="function" and
    type(scheduler.count)=="function" and scheduler.count()<=limit,"Scheduler does not satisfy the owner contract")
  if scheduler.index then
    local stats=assert(scheduler.index.stats)()
    assert(stats.visit_stride==stride and scheduler.index.period==stride*rows-1,
      "Scheduler and owner disagree on stock dimensions")
  end
  local plans=setmetatable({},{__mode="k"})
  local blocked,busy=false,false
  local O={}
  local function reject(reason,phase,can_dense)
    return nil,reason,(phase=="boundary" and can_dense~=false) and "dense" or "abort"
  end
  local function stock(x,z) return (z-1)*stride+x-1 end
  local function coord(k)
    local x,z=k%stride+1,floor(k/stride)+1
    return x,z,(z-1)*width+x
  end
  local function cell(e)
    if e.host~=nil then
      if e.x~=nil or e.z~=nil or not uint(e.host,1,width*depth) then return end
      return (e.host-1)%width+1,floor((e.host-1)/width)+1
    end
    if not uint(e.x,1,width) or not uint(e.z,1,depth) then return end
    return e.x,e.z
  end
  local function normal(entries)
    if not plain(entries) then return nil,"MISSING_CHANGES" end
    local n=0
    for k in pairs(entries) do
      if not uint(k,1,M.MAX_ENTRIES) then return nil,"INVALID_CHANGE_ARRAY" end
      n=n+1
    end
    if n==0 then return nil,"MISSING_CHANGES" end
    local grouped={tile={},field={},layer={}}
    local marked,affected={},{}
    local function touch(x,z)
      local k=stock(x,z)
      if not marked[k] then
        marked[k]=true
        affected[#affected+1]=k
      end
    end
    local function mark(set,x,z,neighbors)
      local k=stock(x,z)
      if set[k] then return end
      set[k]=true
      if not neighbors then touch(x,z);return end
      for v=math.max(z-1,1),min(z+1,depth) do
        for u=math.max(x-1,1),min(x+1,width) do touch(u,v) end
      end
    end
    for i=1,n do
      local e=entries[i]
      if not plain(e) then return nil,"INVALID_CHANGE_RECORD" end
      if e.kind=="corner" then
        if not keys(e,corner_fields) or not uint(e.x,1,width+1) or not uint(e.z,1,depth+1) then
          return nil,"INVALID_CORNER"
        end
        -- The corner at x,z touches these up-to-four real tiles. Exact
        -- dirty IDs from a physical command can attest the same footprint.
        for v=math.max(e.z-1,1),min(e.z,depth) do
          for u=math.max(e.x-1,1),min(e.x,width) do mark(grouped.tile,u,v,true) end
        end
      elseif e.kind=="tile" or e.kind=="field" then
        local x,z=cell(e)
        if not x or not keys(e,cell_fields) then return nil,"INVALID_TILE" end
        -- A field record by itself changes visit membership only here.
        -- Planting may ALSO remove a tree, which must emit a tile edit.
        mark(grouped[e.kind],x,z,e.kind=="tile")
      elseif e.kind=="layer" then
        local x,z=cell(e)
        if not x or not layers[e.layer] or not keys(e,layer_fields) then return nil,"INVALID_LAYER" end
        local set=grouped.layer[e.layer] or {}
        grouped.layer[e.layer]=set
        mark(set,x,z,true)
      else return nil,"UNSUPPORTED_CHANGE_KIND" end
      if #affected>M.MAX_TOUCHED then return nil,"TOUCHED_LIMIT" end
    end
    table.sort(affected)
    return {grouped=grouped,affected=affected}
  end
  local function same_set(a,b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
  end
  local function same_groups(a,b)
    if not same_set(a.tile,b.tile) or not same_set(a.field,b.field) then return false end
    for k,layer in pairs(a.layer) do if not b.layer[k] or not same_set(layer,b.layer[k]) then return false end end
    for k in pairs(b.layer) do if not a.layer[k] then return false end end
    return true
  end
  local function reserve(ids)
    local n=scheduler.count()
    for _,k in ipairs(ids) do
      if not scheduler.contains(k) then
        n=n+1
        if n>limit then return false end
      end
    end
    return true
  end
  local function membership(k)
    local x,z,host=coord(k)
    local ok,on=pcall(probe,k,x,z,host)
    if ok and type(on)=="boolean" then return on end
  end
  local function unready(ids)
    for _,k in ipairs(ids) do
      local on=membership(k)
      if on==nil then return "MISSING_MEMBERSHIP_INPUT" end
      if on~=scheduler.contains(k) then return "STALE_MEMBERSHIP" end
    end
  end
  function O.revision() return revision end
  function O.ready() return not blocked and not busy end
  function O.abandon()
    -- Must leave sparse scheduling before doing any untracked dense
    -- mutation. Abandoned authorities are not reusable caches.
    assert(not busy,"Cannot abandon an in-flight native transaction")
    blocked=true
  end
  function O.preflight(tx,phase)
    if phase~="boundary" and phase~="slot" then return reject("INVALID_PHASE",nil,false) end
    if blocked or busy then return reject("OWNER_NOT_READY",phase,not busy) end
    if not plain(tx) or not keys(tx,head_fields) or tx.schema~=M.SCHEMA then
      return reject("INVALID_TRANSACTION",phase)
    end
    if tx.world~=id then return reject("WRONG_WORLD",phase,false) end
    if tx.revision~=revision then return reject("STALE_REVISION",phase) end
    if revision>=MAX_SAFE then return reject("REVISION_LIMIT",phase) end
    local p,err=normal(tx.changes)
    if not p then return reject(err,phase) end
    if not reserve(p.affected) then return reject("UNRESERVED_ACTIVE_CAPACITY",phase) end
    local problem=unready(p.affected)
    if problem then return reject(problem,phase) end
    local token={}
    p.revision,p.phase=revision,phase
    plans[token]=p
    return token,nil,"sparse"
  end
  function O.affected(token)
    local p=plans[token]
    if not p then return end
    local out={}
    for i,k in ipairs(p.affected) do out[i]=k end
    return out
  end
  function O.run(token,phase,write)
    local p=plans[token]
    if not p then return reject("INVALID_PLAN",nil,false) end
    plans[token]=nil
    if phase~=p.phase then return reject("PHASE_CHANGED",nil,false) end
    if blocked or busy then return reject("OWNER_NOT_READY",p.phase,not busy) end
    if p.revision~=revision then return reject("STALE_REVISION",p.phase) end
    if not reserve(p.affected) then return reject("UNRESERVED_ACTIVE_CAPACITY",p.phase) end
    if type(write)~="function" then return reject("MISSING_WRITER",p.phase) end
    local problem=unready(p.affected)
    if problem then return reject(problem,p.phase) end
    -- No board mutations are allowed outside this call while active.
    -- A bad writer may already have issued writes even if it errors.
    busy=true
    local ok,reported=pcall(write)
    local actual=ok and normal(reported)
    if not actual or not same_groups(p.grouped,actual.grouped) then
      busy,blocked=false,true
      return reject(ok and "UNATTESTED_WRITES" or "WRITER_FAILED",nil,false)
    end
    local add,remove={},{}
    for _,k in ipairs(p.affected) do
      local on=membership(k)
      if on==nil then
        busy,blocked=false,true
        return reject("UNPROVED_MEMBERSHIP",nil,false)
      end
      if on and not scheduler.contains(k) then add[#add+1]=k end
      if not on and scheduler.contains(k) then remove[#remove+1]=k end
    end
    -- No potentially failing classification after changing membership.
    -- Work serially; adding later slots during a flood is intentional.
    local updated=pcall(function()
      for _,k in ipairs(remove) do scheduler.set(k,false) end
      for _,k in ipairs(add) do scheduler.set(k,true) end
    end)
    busy=false
    if not updated then
      blocked=true
      return reject("SCHEDULER_FAILED",nil,false)
    end
    revision=revision+1
    return true,#remove+#add,"sparse"
  end
  return O
end
return M
