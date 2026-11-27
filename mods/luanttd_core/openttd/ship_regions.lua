-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Pin 14.1: pathfinder/water_regions.cpp,
-- pathfinder/water_regions.h, pathfinder/yapf/yapf_ship_regions.cpp and
-- CYapfBaseT/CBinaryHeapT. Authoritative edges come from CFollowTrackWater.
-- Requires a board with tile(id), xy(id), tile_at(x,z), adjacent(id,dir).
return function(Track,Water,board,layout)
  local M={SIZE=16, INVALID_PATCH=0, NODE_COST=100, PATH_LOOKAHEAD=5}
  local floor,ceil,abs,min=math.floor,math.ceil,math.abs,math.min
  local width,height=assert(layout.width),assert(layout.height)
  local x0,z0=layout.x0 or 0,layout.z0 or 0
  assert(width>0 and height>0 and width%1==0 and height%1==0)
  local rw,rh=ceil(width/16),ceil(height/16)
  local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  local cache={}
  local function in_map(x,z) return x>=x0 and x<x0+width and z>=z0 and z<z0+height end
  local function region_xy(id)
    if id==nil then return nil end
    local x,z=board.xy(id)
    if x==nil or not in_map(x,z) then return nil end
    return floor((x-x0)/16),floor((z-z0)/16)
  end
  local function region_index(x,z) return z*rw+x end
  local function desc(x,z,label)
    local region=region_index(x,z)
    return {x=x,z=z,label=label,region=region,key=256*region+label}
  end
  local function local_coords(id,rx,rz)
    local x,z=board.xy(id)
    return x-x0-rx*16,z-z0-rz*16
  end
  local function local_index(id,rx,rz)
    local x,z=local_coords(id,rx,rz)
    return z*16+x
  end
  local function local_tile(rx,rz,x,z)
    local gx,gz=x0+rx*16+x,z0+rz*16+z
    if in_map(gx,gz) then return board.tile_at(gx,gz) end
  end
  local function edge_tile(rx,rz,side,i)
    if side==0 then return local_tile(rx,rz,0,i) end
    if side==1 then return local_tile(rx,rz,i,15) end
    if side==2 then return local_tile(rx,rz,15,i) end
    return local_tile(rx,rz,i,0)
  end

  local function solid_region(rx,rz)
    if not board.solid_plain_sea or (rx+1)*16>width or (rz+1)*16>height or
        not board:solid_plain_sea(x0+rx*16,z0+rz*16,16) then return end
    -- All 256 flat sea tiles offer every track. No interior cycle or
    -- separate component can exist. Every outgoing direction uses the
    -- same stock follower, including one-way aqueduct heads at the edge.
    local r={edge={[0]=0,0,0,0},cross_aqueduct=false,count=1,x=rx,z=rz}
    for side=0,3 do
      local td=Track.diagonal_trackdir(side)
      local bits=0
      for i=0,15 do
        local id=edge_tile(rx,rz,side,i)
        local f=Water.follow(board,nil,id,td)
        if f.ok then
          local nx,nz=region_xy(f.tile)
          if nx~=nil and (nx~=rx or nz~=rz) then bits=bits+2^i end
        end
      end
      r.edge[side]=bits
    end
    cache[region_index(rx,rz)]=r
    return r
  end

  local function force_update(rx,rz)
    local full=solid_region(rx,rz)
    if full then return full end
    local r={labels={},edge={[0]=0,0,0,0},cross_aqueduct=false,count=0,x=rx,z=rz}
    -- ForceUpdate is a synchronous read-only walk over this board.
    -- DFS order, stock follower, edges and aqueduct handling stay as-is.
    local sample=Water.region_sampler and Water.region_sampler(board)
    local stack={}
    for y=0,15 do for x=0,15 do
      local start=local_tile(rx,rz,x,y)
      local label=r.count+1
      if start~=nil then stack[1]=start end
      while #stack>0 do
        local id=stack[#stack];stack[#stack]=nil
        local i=local_index(id,rx,rz)
        if not r.labels[i] then
          local status=sample and sample(id) or Water.at(board,id)
          if status~=0 then
            r.labels[i]=label
            r.count=label
            for _,td in ipairs(Water.trackdirs(status)) do
              local f=Water.follow(board,nil,id,td,sample)
              local fx,fz=region_xy(f.tile)
              if f.ok and fx~=nil then
                if fx==rx and fz==rz then
                  stack[#stack+1]=f.tile
                elseif f.bridge then
                  r.cross_aqueduct=true
                else
                  local a,b=local_coords(id,rx,rz)
                  local j=f.exit%2==0 and b or a
                  r.edge[f.exit]=Track.union(r.edge[f.exit],2^j)
                end
              end
            end
          end
        end
      end
    end end
    local full=r.count==1
    if full then for i=0,255 do if r.labels[i]~=1 then full=false;break end end end
    if full or r.count==0 then r.labels=nil end
    cache[region_index(rx,rz)]=r
    return r
  end

  local function fetch(rx,rz)
    if rx<0 or rz<0 or rx>=rw or rz>=rh then return nil end
    return cache[region_index(rx,rz)] or force_update(rx,rz)
  end
  local function label(r,id)
    if id==nil then return 0 end
    if not r.labels then return r.count==1 and 1 or 0 end
    return r.labels[local_index(id,r.x,r.z)] or 0
  end
  function M.region(id)
    local rx,rz=region_xy(id)
    return rx~=nil and region_index(rx,rz) or nil
  end
  function M.region_patch(id)
    local rx,rz=region_xy(id)
    return rx~=nil and label(fetch(rx,rz),id) or 0
  end
  function M.patch_info(id)
    local rx,rz=region_xy(id)
    if rx~=nil then return desc(rx,rz,label(fetch(rx,rz),id)) end
  end
  function M.center(p)
    -- Stock maps are multiples of 16. Clamp only for the game's partial
    -- last region, where the exact stock center can lie outside its map.
    local x=min(x0+p.x*16+8,x0+width-1)
    local z=min(z0+p.z*16+8,z0+height-1)
    return board.tile_at(x,z)
  end
  function M.info(rx,rz)
    local r=fetch(rx,rz)
    if not r then return end
    return {count=r.count,cross_aqueduct=r.cross_aqueduct,edge={[0]=r.edge[0],r.edge[1],r.edge[2],r.edge[3]}}
  end

  -- Exact lazy invalidation: edge changes refresh both adjacent regions.
  -- When placing/removing an aqueduct call invalidate for BOTH mouths.
  function M.invalidate(id)
    local key=M.region(id)
    if key==nil then return end
    cache[key]=nil
    for d=0,3 do
      local other=M.region(board.adjacent(id,d))
      if other~=nil then cache[other]=nil end
    end
  end
  function M.invalidate_all() cache={} end

  -- Standard edge crossings require matching bits from both sides.
  -- Follow source callback order: NE,SE,SW,NW; ascending edge coordinate;
  -- then every matching aqueduct mouth in row-major order.
  function M.neighbors(p,callback)
    local out={}
    local visit=callback or function(q) out[#out+1]=q end
    if not p or p.label==0 then return out end
    local r=fetch(p.x,p.z)
    for d=0,3 do
      local nx,nz=p.x+dx[d],p.z+dz[d]
      -- An empty outward edge cannot intersect anything on its far
      -- side. Leave that region cold; a real terrain edit still dirties
      -- both sides through the same boundary invalidation.
      local outward=r.edge[d]
      local nr=outward~=0 and fetch(nx,nz)
      if nr then
        local opp=Track.reverse_side(d)
        local bits=Track.intersect(outward,nr.edge[opp])
        if bits~=0 then
          if r.count==1 and nr.count==1 then visit(desc(nx,nz,1))
          else
            local seen={}
            for j=0,15 do
              if Track.has(bits,j) and label(r,edge_tile(p.x,p.z,d,j))==p.label then
                local l=label(nr,edge_tile(nx,nz,opp,j))
                if l~=0 and not seen[l] then
                  visit(desc(nx,nz,l))
                  seen[l]=true
                end
              end
            end
          end
        end
      end
    end
    if r.cross_aqueduct then
      for z=0,15 do for x=0,15 do
        local id=local_tile(p.x,p.z,x,z)
        if id~=nil and label(r,id)==p.label then
          local t=board.tile(id)
          if t and t.kind=="aqueduct" and t.other~=nil then
            local q=M.patch_info(t.other)
            if q and q.region~=p.region then visit(q) end
          end
        end
      end end
    end
    return out
  end

  local function direction(a,b)
    if a.z==b.z and a.x~=b.x then return b.x>a.x and 2 or 0 end
    if a.x==b.x and a.z~=b.z then return b.z>a.z and 1 or 3 end
    return 255 -- stock INVALID_DIAGDIR (impossible on a valid straight aqueduct)
  end
  function M.manhattan(a,b) return (abs(a.x-b.x)+abs(a.z-b.z))*M.NODE_COST end
  function M.cost(grand,prior,p)
    local n=M.manhattan(prior,p)
    if grand then
      local d=(direction(grand,prior)-direction(prior,p))%4
      if d~=1 and d~=3 then n=n+1 end
    end
    return n
  end

  -- Stock CBinaryHeapT tie/move behavior including removal and replacement.
  local function queue()
    local heap,open={},{}
    local function move(i,n) heap[i]=n;n.index=i end
    local function up(i,n)
      while i>1 do
        local p=math.floor(i/2)
        if n.estimate>=heap[p].estimate then break end
        move(i,heap[p]);i=p
      end
      return i
    end
    local function down(i,n)
      local ch=i*2
      while ch<=#heap do
        if ch<#heap and heap[ch+1].estimate<heap[ch].estimate then ch=ch+1 end
        if heap[ch].estimate>=n.estimate then break end
        move(i,heap[ch]);i=ch;ch=i*2
      end
      return i
    end
    local function add(n)
      open[n.patch.key]=n
      move(up(#heap+1,n),n)
    end
    local function remove(n)
      local i,last=n.index,heap[#heap]
      open[n.patch.key]=nil
      heap[#heap]=nil
      if i<=#heap then
        move(down(up(i,last),last),last)
      end
      n.index=nil
    end
    return heap,open,add,remove
  end

  -- Source searches backwards from the candidate docks, not forwards
  -- from the ship. target_tiles must be in row-major tile-area order,
  -- retaining that order for equal-cost multi-origin ties.
  function M.find(start_tile,target_tiles,max_len,settings)
    local dest=M.patch_info(start_tile)
    local limit=settings and settings.max_region_nodes or min(floor(width*height*4/256),65536)
    max_len=max_len or M.PATH_LOOKAHEAD
    local attempts={closed=0,capped=false}
    if max_len<1 or not dest or dest.label==0 then return {},attempts end
    local heap,open,include,remove=queue()
    local closed={}
    for _,id in ipairs(target_tiles) do
      local p=M.patch_info(id)
      if p and p.label~=0 and not open[p.key] then
        if p.key==dest.key then return {dest},attempts end
        include({patch=p,cost=0,estimate=0})
      end
    end
    local best
    local function consider(n,p)
      if p.label==0 then return end
      local cost=n.cost+M.cost(n.parent and n.parent.patch,n.patch,p)
      local estimate=cost+M.manhattan(dest,p)
      if p.key==dest.key then
        if not best or estimate<best.estimate then
          best={patch=p,parent=n,cost=cost,estimate=estimate}
        end
        return
      end
      local old=open[p.key]
      if old then
        if estimate<old.estimate then
          remove(old)
          old.parent,old.cost,old.estimate=n,cost,estimate
          include(old)
        end
      elseif not closed[p.key] then
        include({patch=p,parent=n,cost=cost,estimate=estimate})
      end
    end
    while heap[1] do
      local n=heap[1]
      if best and best.cost<n.estimate then break end
      M.neighbors(n.patch,function(p) consider(n,p) end)
      if limit~=0 and attempts.closed>=limit then attempts.capped=true;return {},attempts end
      remove(n)
      closed[n.patch.key]=n
      attempts.closed=attempts.closed+1
    end
    local out={}
    attempts.cost=best and best.cost or nil
    while best and #out<max_len do
      out[#out+1]=best.patch
      best=best.parent
    end
    return out,attempts
  end

  function M.target_tiles(order)
    if order.kind~="station" then return order.tile~=nil and {order.tile} or {} end
    local candidates=order.dock_tiles or (board.station_dock_tiles and board.station_dock_tiles(order.station))
    local out={}
    for _,id in ipairs(candidates or {}) do
      if Water.ship_destination(board,id,order.station) then out[#out+1]=id end
    end
    table.sort(out,function(a,b)
      local x,z=board.xy(a)
      local u,v=board.xy(b)
      return z<v or z==v and x<u
    end)
    return out
  end

  function M.bind(path)
    local corridor
    if path then
      corridor={}
      for _,p in ipairs(path) do corridor[p.region]=true end
    end
    return setmetatable({region=M.region,region_patch=M.region_patch,region_corridor=corridor},
      {__index=function(_,k) if k~="region_corridor" then return board[k] end end})
  end

  -- Stock ChooseShipTrack's two low-level attempts / intermediate target
  -- selection, returning the exact low-level trace. Not the controller's
  -- random-lost fallback, reverse choice or path-cache trimming policy.
  -- candidate_tile is the tile being considered, distinct from origin.
  function M.find_route(Y,v,origin,start_bits,candidate_tile,order,settings)
    local path,info=M.find(candidate_tile,M.target_tiles(order),M.PATH_LOOKAHEAD,settings)
    if #path==0 then return nil,"no_region_path",path,info end
    local free=M.bind()
    local d
    if #path>=M.PATH_LOOKAHEAD then
      local p=path[#path]
      d=Y.destination(free,v,{kind="region",tile=M.center(p),region=p.region,patch=p.label})
    else
      d=Y.destination(free,v,order)
    end
    local yes,node,stats=Y.find(free,v,origin,start_bits,d,settings)
    local route_board=free
    if not yes then
      route_board=M.bind(path)
      yes,node,stats=Y.find(route_board,v,origin,start_bits,d,settings)
    end
    if not yes then return nil,"no_tile_path",path,stats end
    return Y.trace(route_board,v,d,node,settings),node.cost,path,stats
  end
  return M
end
