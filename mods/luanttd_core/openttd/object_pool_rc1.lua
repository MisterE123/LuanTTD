-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 src/core/pool_func.hpp FindFirstFree/AllocateRaw/Free.
-- Lifetime belongs to the authority records; this port walks their
-- canonical occupancy at procurement. Non-simulation visual objects
-- may not reserve a simulation slot unless explicitly modelled as such.
local P={}
function P.reserve(used,count,limit)
  assert(type(count)=="number" and count>=0 and count%1==0 and type(limit)=="number")
  local ids={}
  local next_free=0
  for i=1,count do
    while next_free<limit and used[next_free] do next_free=next_free+1 end
    if next_free>=limit then return nil,"POOL_FULL" end
    ids[i]=next_free
    next_free=next_free+1
  end
  return ids
end
function P.occupy(used,id,limit)
  assert(type(id)=="number" and id>=0 and id<limit and id%1==0,"Invalid canonical pool identity")
  assert(not used[id],"Duplicate canonical pool identity")
  used[id]=true
end
return P
