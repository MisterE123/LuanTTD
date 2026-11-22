-- Owner-thread broker for Luanti's isolated async Lua workers.
-- Only an ordinary table of bounded byte planes crosses the thread boundary.
local M={}
local registered=setmetatable({},{__mode="k"})
local function worker_entry(snapshot,job,id)
  -- No captures: Luanti serializes this function, not the owning VM.
  return core.luanttd_world_async_run(snapshot,job,id)
end
local function copy(t)
  local a={}
  for k,v in pairs(t) do a[k]=v end
  return a
end

function M.new(core,path,Storage,options)
  if type(core.register_async_dofile)~="function" or type(core.handle_async)~="function" then
    return nil,"Luanti server async APIs unavailable"
  end
  options=options or {}
  local limit=options.inflight or 4
  local capacity=options.proposals or 16
  assert(type(limit)=="number" and limit>=1 and limit<=8 and limit%1==0)
  assert(type(capacity)=="number" and capacity>=1 and capacity<=32 and capacity%1==0)
  local P=dofile(path.."/world_async_protocol.lua")
  if registered[core]~=path then
    local ok,why=pcall(core.register_async_dofile,path.."/world_async_worker.lua")
    if not ok then return nil,"async preloader registration failed: "..tostring(why) end
    registered[core]=path
  end
  local Q={}
  local active,serial=0,0
  local pending={}
  local proposals=setmetatable({},{__mode="k"})
  local function matches(world,s)
    local a=Storage.stats(world)
    return a and a.revision==s.revision and a.width==s.map_width and a.depth==s.map_depth and
      a.seed==s.seed and a.base_id==s.base_id
  end
  local function outstanding()
    local n=0
    for _ in pairs(proposals) do n=n+1 end
    return n
  end
  function Q.stats()
    return {inflight=active,proposals=outstanding(),max_input=P.max_input(),submitted=serial}
  end
  function Q.cancel(id)
    local part=pending[id]
    if not part or part.cancelled then return false end
    part.cancelled=true
    -- Do not reclaim the true worker slot until its callback drains.
    return true
  end
  function Q.submit(world,x1,z1,x2,z2,job,done)
    if type(done)~="function" then return nil,"owner completion callback required" end
    if active>=limit then return nil,"async terrain queue full" end
    if not P.region(x1,z1,x2,z2) then return nil,"invalid bounded async region" end
    local s,ticket=Storage.snapshot(world,x1,z1,x2,z2)
    if not s then return nil,ticket end
    if not P.snapshot(s) or not ticket or not matches(world,s) or
       s.x~=x1 or s.z~=z1 or s.width~=x2-x1+1 or s.depth~=z2-z1+1 then return nil,"invalid owner snapshot" end
    job=P.job(s,job)
    if not job then return nil,"invalid terrain job" end
    if serial>=P.MAX_REVISION then return nil,"async terrain IDs exhausted" end
    serial=serial+1
    local id=serial
    pending[id]={}
    active=active+1
    local function completed(reply)
      local part=pending[id]
      if not part then return end
      pending[id]=nil
      active=active-1
      if part.cancelled then return end
      if not matches(world,s) then return done(nil,"stale world revision") end
      local result,err,patch=P.result(s,job,id,reply)
      if not result then return done(nil,err) end
      if patch then
        if outstanding()>=capacity then return done(nil,"owner terrain proposal queue full") end
        -- Keep the retained ticket and accepted patch private in this
        -- broker. Caller-facing result fields and tokens are not authority.
        proposals[result]={world=world,s=s,job=job,ticket=ticket,patch=patch,cost=result.cost}
      end
      done(result)
    end
    local ok,why=pcall(core.handle_async,worker_entry,completed,s,job,id)
    if not ok or not why then
      if pending[id] then pending[id]=nil;active=active-1 end
      return nil,"async terrain dispatch failed: "..tostring(why)
    end
    return id
  end

  -- Authorization and commit must run in the authoritative simulation VM.
  -- The owner can reread occupancy, stock world policy and company budget.
  -- The callback should only validate: finance/publication work follows
  -- a successful return without yielding, never before this atomic apply.
  function Q.apply(world,proposal,authorize)
    local record=proposals[proposal]
    if not record or record.world~=world then return nil,"invalid owner terrain proposal" end
    if type(authorize)~="function" then return nil,"owner terrain authorization required" end
    proposals[proposal]=nil -- an authorized apply attempt is single-use even on refusal
    if not matches(world,record.s) then return nil,"stale world revision" end
    local s=record.s
    local edits={}
    for i,e in ipairs(record.patch) do edits[i]=copy(e) end
    local context={revision=s.revision,x=s.x,z=s.z,width=s.width,depth=s.depth,
      map_width=s.map_width,map_depth=s.map_depth,cost=record.cost,job=copy(record.job),edits=edits}
    local worked,allowed,reason=pcall(authorize,world,context)
    if not worked then return nil,"owner terrain authorization failed" end
    if allowed~=true then return nil,type(reason)=="string" and reason or "owner rejected terrain proposal" end
    -- WorldStorage validates the real ticket again after authorization,
    -- including current revision, region, edge legality and atomicity.
    return Storage.apply_job(world,record.ticket,record.patch)
  end
  Q.profile=P.profile
  Q.terrain_profile=P.terrain_profile
  return Q
end
return M
