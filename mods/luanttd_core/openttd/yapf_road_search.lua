-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- Road specialization of OpenTTD 14.1 CYapfBaseT, CYapfOriginTileT,
-- CYapfRoadNodeT, CNodeList_HashTableT and CBinaryHeapT. Lua tables replace
-- the C++ arena and hash tables; preserve the exact heap comparisons,
-- removal order and in-place open-node update for equal-cost behavior.
return function(F,C)
  local S={}
  local function new_node(parent,tile,td,is_choice)
    return {parent=parent,tile=tile,td=td,last_tile=tile,last_td=td,
      cost=0,estimate=0,is_choice=is_choice}
  end

  local function new_open()
    local heap,by_tile={},{}
    local function at(tile)
      local t=by_tile[tile]
      if not t then t={};by_tile[tile]=t end
      return t
    end
    local function move(i,node) heap[i]=node;node.heap_index=i end
    local function up(gap,node)
      while gap>1 do
        local parent=math.floor(gap/2)
        if node.estimate>=heap[parent].estimate then break end
        move(gap,heap[parent]);gap=parent
      end
      return gap
    end
    local function down(gap,node)
      local child=gap*2
      while child<=#heap do
        if child<#heap and heap[child+1].estimate<heap[child].estimate then child=child+1 end
        if heap[child].estimate>=node.estimate then break end
        move(gap,heap[child]);gap=child;child=gap*2
      end
      return gap
    end
    local function include(node)
      at(node.tile)[node.key]=node
      move(up(#heap+1,node),node)
    end
    local function remove(node)
      local index,n=assert(node.heap_index),#heap
      at(node.tile)[node.key]=nil
      if index<n then
        local last=heap[n]
        heap[n]=nil
        move(down(up(index,last),last),last)
      else heap[n]=nil end
      node.heap_index=nil
    end
    return heap,by_tile,include,remove
  end

  -- The startup nodes are deliberately not charged or tested as
  -- destinations. Their first child receives normal segment evaluation.
  function S.find(board,vehicle,origin,trackdirs,destination,settings,options)
    settings=settings or {}
    options=options or {}
    local cap=settings.max_search_nodes or 10000
    local heap,open,include,remove=new_open()
    local closed,closed_count={},0
    local best_dest,best_intermediate
    local function key(td)
      return settings.disable_node_optimization and td or F.exit_direction(td)
    end
    local starts=F.trackdirs(trackdirs)
    for _,td in ipairs(starts) do
      local n=new_node(nil,origin,td,#starts>1)
      n.key=key(td)
      if not (open[origin] and open[origin][n.key]) then include(n) end
    end
    local function add(n,follower)
      -- RC1 CYapfBaseT::AddNewNode passes the existing track follower
      -- to PfCalcCost; road cost can still follow its longer segment.
      if not C.calc(board,vehicle,destination,n,settings,options.max_cost,nil,follower) then return end
      n.estimate=C.estimate(board,destination,n)
      if C.detect(board,destination,n.last_tile,n.last_td) then
        if not best_dest or n.estimate<best_dest.estimate then best_dest=n end
        return
      end
      local improve=cap>0 and (not best_intermediate or
        best_intermediate.estimate-best_intermediate.cost>n.estimate-n.cost)
      local on=open[n.tile] and open[n.tile][n.key]
      if on then
        if n.estimate<on.estimate then
          remove(on)
          for k,v in pairs(n) do on[k]=v end
          include(on)
          if improve then best_intermediate=on end
        end
        return
      end
      local cn=closed[n.tile] and closed[n.tile][n.key]
      if cn then
        assert(n.estimate>=cn.estimate,"YAPF: a closed node received a lower estimate")
        return
      end
      include(n)
      if improve then best_intermediate=n end
    end

    local capped=false
    while heap[1] do
      local n=heap[1]
      if best_dest and best_dest.cost<n.estimate then break end
      local f=F.follow(board,vehicle,n.last_tile,n.last_td)
      if f.ok then
        local tds=F.trackdirs(f.trackdirs)
        for _,td in ipairs(tds) do
          local child=new_node(n,f.tile,td,#tds>1)
          child.key=key(td)
          add(child,f)
        end
      end
      if cap==0 or closed_count<cap then
        remove(n)
        closed[n.tile]=closed[n.tile] or {}
        closed[n.tile][n.key]=n
        closed_count=closed_count+1
      else
        capped=true
        break
      end
    end
    return not capped and best_dest~=nil,best_dest or best_intermediate,
      {closed_count=closed_count,capped=capped}
  end

  -- Reconstruct computed segments for verification and a 3D motion
  -- adapter. Not the stock eight-choice vehicle cache; the game adapter
  -- must make its junction decision with the live movement state.
  function S.trace(board,vehicle,destination,best,settings,options)
    local chain,course={},{}
    while best do chain[#chain+1]=best;best=best.parent end
    for i=#chain,1,-1 do
      local n=chain[i]
      if not n.parent then course[#course+1]={tile=n.tile,td=n.td}
      else
        local scratch=new_node(n.parent,n.tile,n.td,n.is_choice)
        assert(C.calc(board,vehicle,destination,scratch,settings,options and options.max_cost,
          function(tile,td) course[#course+1]={tile=tile,td=td} end))
      end
    end
    return course
  end
  return S
end
