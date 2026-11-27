-- Data-only terrain staging. The authorized campaign owner enumerates
-- every autonomous surface mutation and calls finish at a stable tick
-- boundary. A presentation dirty set alone is not an ownership lease.
-- No background job may dereference the world or a rich tile record.
return function(Pages,record)
  local M={}
  local floor=math.floor
  local width,batch=13,64
  local blank,pad=string.rep("\0",width),string.rep("\0",width-6)
  local function id_valid(i,n)
    return type(i)=="number" and i>=1 and i<=n and i==floor(i)
  end
  local function stamp(v)
    return type(v)=="number" and v>=0 and v==floor(v) and v<9007199254740992
  end
  function M.new(root,slots,witness,n,step)
    local S={}
    local plane,rich,tree_by_id,tree_slot,pending,last_tick
    local changes=0
    local function unmapped()
      plane,rich,tree_by_id,tree_slot,pending,last_tick=nil,nil,nil,nil,nil,nil
      changes=0
    end
    function S.invalidate()
      -- Discard the in-memory accelerator only. A durable payment
      -- always publishes the independent exact checkpoint.
      unmapped()
    end
    local function stable_vector()
      return root.tiles==slots and #slots==n and getmetatable(slots)==nil
    end
    local function read(i)
      local t=rawget(slots,i)
      if t~=witness[i] or getmetatable(t)~=nil then return nil end
      local tree=t.wood
      if type(tree)=="table" and getmetatable(tree)~=nil then return nil end
      local raw=record(t)
      if not raw then rich[i]=t;return blank end
      rich[i]=nil
      if #raw==width then
        if tree_slot[tree] then return nil end
        tree_by_id[i],tree_slot[tree]=tree,i
        return raw
      end
      if #raw~=6 then return nil end
      return raw..pad
    end
    -- The preceding full codec already used the authoritative tile
    -- array, classified every row and found all plain tree identities.
    -- Borrow only its immutable bytes and rebuild our private indexes.
    function S.adopt(tick,coarse,lo,detail,wood)
      unmapped()
      if not stamp(tick) or not stable_vector() or lo<=0 or lo%batch~=0 then return false end
      local rows={}
      for i=1,#coarse do
        local encoded=coarse[i]
        for at=1,#encoded,batch*width do rows[#rows+1]=encoded:sub(at,at+batch*width-1) end
      end
      local p=Pages.from_pages(n,batch,width,rows)
      if not p then return false end
      rich,tree_by_id,tree_slot,pending={},{},wood,{}
      for id,t in pairs(detail) do
        if id_valid(id,n) then rich[id]=t end
      end
      for tree,id in pairs(wood) do
        tree_by_id[id]=tree
      end
      plane,last_tick=p,tick
      return true
    end
    function S.touch(id)
      if not pending then return end
      if not id_valid(id,n) then unmapped();return end
      if not pending[id] then pending[id]=true;changes=changes+1 end
    end
    function S.finish(tick)
      if not plane then return false end
      if not stamp(tick) or tick~=last_tick+step or not stable_vector() then unmapped();return false end
      if changes==0 then last_tick=tick;return true end
      -- Remove prior membership for all changed IDs before installing
      -- new trees. This supports moving a record without interpreting
      -- temporary source/destination overlap as a persistent alias.
      for id in pairs(pending) do
        local old=tree_by_id[id]
        if old then tree_slot[old],tree_by_id[id]=nil,nil end
      end
      local patch={}
      for id in pairs(pending) do
        local raw=read(id)
        if not raw then unmapped();return false end
        if raw~=Pages.get(plane,id) then patch[id]=raw end
      end
      local next_plane=Pages.patch(plane,Pages.revision(plane),patch)
      if not next_plane then unmapped();return false end
      plane,last_tick,pending,changes=next_plane,tick,{},0
      return true
    end
    function S.capture(tick,output,details)
      if not plane or tick~=last_tick or changes~=0 or not stable_vector() then return false end
      for i=1,Pages.page_count(plane) do output[#output+1]=Pages.page(plane,i) end
      for id,v in pairs(rich) do details[id]=v end
      return true
    end
    return S
  end
  return M
end
