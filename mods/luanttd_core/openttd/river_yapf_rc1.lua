-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 (07b339c):
-- pathfinder/yapf/yapf_river_builder.cpp, yapf_base.hpp, yapf_node.hpp,
-- nodelist.hpp and misc/binaryheap.hpp. Trackdir::Invalid everywhere, so
-- TileIndex alone is the node key. The board supplies RiverFlowsDown.
local R={}
local floor=math.floor
local function priority()
  local heap,open={},{}
  local function place(i,n) heap[i]=n;n.index=i end
  local function up(i,n)
    while i>1 do
      local j=floor(i/2)
      if n.estimate>=heap[j].estimate then break end
      place(i,heap[j]);i=j
    end
    return i
  end
  local function down(i,n)
    local j=i*2
    while j<=#heap do
      if j<#heap and heap[j+1].estimate<heap[j].estimate then j=j+1 end
      if heap[j].estimate>=n.estimate then break end
      place(i,heap[j]);i,j=j,j*2
    end
    return i
  end
  local function include(n)
    open[n.tile]=n
    place(up(#heap+1,n),n)
  end
  local function remove(n)
    local i,j=n.index,#heap
    local last=heap[j]
    heap[j],open[n.tile]=nil,nil
    if i<j then place(down(up(i,last),last),last) end
  end
  return heap,open,include,remove
end

function R.route(B,begin,finish,random,route_random,max_nodes,valid,flows_down,offset,distance)
  local heap,open,include,remove=priority()
  local closed={}
  local limit=max_nodes or 10000
  local random_limit=route_random or 5
  local count,draws=0,0
  include({tile=begin,cost=0,estimate=0})
  while heap[1] do
    local current=heap[1]
    local i=current.tile
    -- FindPath tests a destination before expanding; the current node
    -- stays in the open list until all four PfFollowNode children finish.
    if i==finish then
      local path={}
      while current do path[#path+1]=current.tile;current=current.parent end
      return path,{expanded=count,draws=draws,cost=heap[1].cost}
    end
    for d=1,4 do
      local j=offset(B,i,d)
      if valid(B,j) and flows_down(B,i,j) then
        -- AddNewNode computes PfCalcCost before open/closed checks.
        -- Both duplicate and closed neighbors consume a random draw,
        -- even when the selected randomisation range is zero.
        local cost=current.cost+1+floor(random()*random_limit/4294967296)
        local estimate=cost+distance(B,j,finish)
        draws=draws+1
        local old=open[j]
        if old then
          if estimate<old.estimate then
            remove(old)
            old.parent,old.cost,old.estimate=current,cost,estimate
            include(old)
          end
        elseif not closed[j] then
          include({tile=j,parent=current,cost=cost,estimate=estimate})
        end
      end
    end
    if limit~=0 and count>=limit then return nil,{expanded=count,draws=draws,limit=true} end
    remove(current);closed[i]=true;count=count+1
  end
  return nil,{expanded=count,draws=draws}
end
return R
