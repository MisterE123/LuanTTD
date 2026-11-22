-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 CYapfBaseT, CYapfOriginTileTwoWayT,
-- CYapfFollowRailT, CYapfFollowAnyDepotRailT, CYapfFollowAnySafeTileRailT,
-- CYapfNodeKeyTrackDir and CBinaryHeapT.
-- Local-cache specialization: every node's segment cost is fresh. Passing a
-- board snapshot makes search independent of live occupancy writes.
return function(T,F,C)
local S={}
local function at(map,tile)
  local bucket=map[tile]
  if not bucket then bucket={};map[tile]=bucket end
  return bucket
end

local function open_list()
  local heap,map={},{}
  local function move(i,n) heap[i]=n;n.heap_index=i end
  local function up(gap,n)
    while gap>1 do
      local parent=math.floor(gap/2)
      if n.estimate>=heap[parent].estimate then break end
      move(gap,heap[parent]);gap=parent
    end
    return gap
  end
  local function down(gap,n)
    local c=gap*2
    while c<=#heap do
      if c<#heap and heap[c+1].estimate<heap[c].estimate then c=c+1 end
      if heap[c].estimate>=n.estimate then break end
      move(gap,heap[c]);gap=c;c=gap*2
    end
    return gap
  end
  local function include(n)
    at(map,n.tile)[n.td]=n
    move(up(#heap+1,n),n)
  end
  local function remove(n)
    local i,len=n.heap_index,#heap
    map[n.tile][n.td]=nil
    if i<len then
      local tail=heap[len]
      heap[len]=nil
      move(down(up(i,tail),tail),tail)
    else heap[len]=nil end
    n.heap_index=nil
  end
  return heap,map,include,remove
end

-- origin and reverse_origin are {tile,td}; upstream leaves both startup
-- estimates zero, but charges the reversed train's cost to its descendants.
-- Each ordinary rail node key includes the full trackdir, even if callers
-- choose an exit-direction optimization for other modes.
function S.find(board,v,origin,dest,s,opts)
  opts=opts or {}
  local cap=s and s.max_search_nodes or 10000
  local heap,open,include,remove=open_list()
  local closed,closed_count={},0
  local best_dest,best_intermediate
  local flags={closed_count=0,capped=false,stopped_on_first_two_way=false,steps=0}
  local use_mask=dest.kind=="safe"
  local view=v
  if use_mask and opts.override_railtype then
    view={}
    for k,val in pairs(v) do view[k]=val end
    view.compatible={}
    for k,val in pairs(v.compatible) do view.compatible[k]=val end
    local t=board.railtype and board.railtype(v.railtype)
    if t and t.compatible then
      for k,val in pairs(t.compatible) do if val then view.compatible[k]=true end end
    end
  end
  local function start(place,cost)
    if not place or place.tile==nil or not T.valid_trackdir(place.td) then return end
    if open[place.tile] and open[place.tile][place.td] then return end
    local n=C.node(nil,place.tile,place.td,false)
    n.cost=cost
    n.reason=0
    include(n)
  end
  start(origin,0)
  start(opts.reverse_origin,opts.reverse_penalty or 0)
  local function prune(n)
    local selected=false
    while n and T.intersect(n.reason,C.CHOICE_FOLLOWS)==0 do
      if n==best_intermediate then selected=true end
      n=n.parent
    end
    if selected then best_intermediate=n end
  end
  local controls={mask_reserved=use_mask,max_cost=opts.max_cost,treat_first_red=opts.treat_first_red,prune=prune}
  local function add(n,follow)
    -- Store the incoming follow result for deterministic trace reconstruction
    -- and avoid re-reading a previous platform after a route is chosen.
    n.incoming=follow
    if view~=v then n.route_vehicle=view end
    local valid=C.calc(board,view,dest,n,follow,s,controls)
    if n.stopped_on_first_two_way then flags.stopped_on_first_two_way=true end
    if not valid then return end
    n.estimate=C.estimate(board,dest,n,s)
    if C.detect(board,dest,n.last_tile,n.last_td,s) then
      if not best_dest or n.estimate<best_dest.estimate then best_dest=n end
      return
    end
    local improve=cap>0 and (not best_intermediate or
      best_intermediate.estimate-best_intermediate.cost>n.estimate-n.cost)
    local other=open[n.tile] and open[n.tile][n.td]
    if other then
      if n.estimate<other.estimate then
        remove(other)
        -- Upstream copies the whole node. Clear state that is nil in the
        -- replacement, e.g. an older path's just-passed signal location.
        for k in pairs(other) do other[k]=nil end
        for k,val in pairs(n) do other[k]=val end
        include(other)
        if improve then best_intermediate=other end
      end
      return
    end
    local previous=closed[n.tile] and closed[n.tile][n.td]
    if previous then
      assert(n.estimate>=previous.estimate,"rail YAPF: closed node received a smaller estimate")
      return
    end
    include(n)
    if improve then best_intermediate=n end
  end

  while true do
    flags.steps=flags.steps+1
    local n=heap[1]
    if not n or best_dest and best_dest.cost<n.estimate then break end
    if opts.visit then opts.visit(n) end
    local f=F.follow(board,view,n.last_tile,n.last_td,s)
    if use_mask and f.ok then f=F.mask_reserved(board,f) end
    if f.ok then
      local count=0
      for td=0,13 do if T.has(f.trackdirs,td) then count=count+1 end end
      for td=0,13 do if T.has(f.trackdirs,td) then add(C.node(n,f.tile,td,count>1),f) end end
    end
    if cap==0 or closed_count<cap then
      remove(n)
      at(closed,n.tile)[n.td]=n
      closed_count=closed_count+1
    else
      flags.capped=true
      break
    end
  end
  flags.closed_count=closed_count
  return not flags.capped and best_dest~=nil,best_dest or best_intermediate,flags
end

-- ChooseRailTrack normally gets origin from the train's existing PBS
-- reservation. The caller provides that origin here. Reservation extension,
-- backoff, and train movement are intentionally not part of this API.
function S.choose(board,v,origin,dest,s,opts)
  local found,best,stats=S.find(board,v,origin,dest,s,opts)
  local child=best
  while child and child.parent and child.parent.parent do child=child.parent end
  local td=child and child.parent and child.td or nil
  return td,found or stats.stopped_on_first_two_way,best,stats
end

-- IterateTiles in CYapfRailNodeT expands single-choice segments. The
-- result emits real segment vertices including station/portal end tiles;
-- intermediate platform/span mapping is the motion adapter's job.
function S.trace(board,v,best,s)
  local path,chain={},{}
  v=best and best.route_vehicle or v
  while best do chain[#chain+1]=best;best=best.parent end
  for i=#chain,1,-1 do
    local n=chain[i]
    local tile,td=n.tile,n.td
    path[#path+1]={tile=tile,td=td,follow=n.incoming}
    while tile~=n.last_tile or td~=n.last_td do
      local f=F.follow(board,v,tile,td,s)
      assert(f.ok and f.trackdirs>0)
      local selected
      for t=0,13 do
        if T.has(f.trackdirs,t) then assert(selected==nil);selected=t end
      end
      tile,td=f.tile,selected
      path[#path+1]={tile=tile,td=td,follow=f}
    end
  end
  return path
end

return S
end
