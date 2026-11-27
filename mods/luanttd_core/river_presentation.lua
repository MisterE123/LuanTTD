-- Visual directions only. No edits to OpenTTD river bits, terrain or hydrology.
return function(Sim)
  local M={}
  local directions={"north","east","south","west"}
  local function trace(s,river,dependencies)
    local toward,seen,queue={},{},{}
    local head=1
    for _,id in ipairs(river) do
      local t=s.tiles[id]
      for d=1,4 do
        local j=Sim.adjacent(id,d)
        local n=j and s.tiles[j]
        if n and not n.stock_void and n.terrain=="water" and n.water_class~="river"
            and (n.h or 0)<=(t.h or 0) then
          toward[id]=directions[d];seen[id]=true;queue[#queue+1]=id;break
        end
      end
      if dependencies then
        dependencies[id]=true
        for d=1,4 do
          local j=Sim.adjacent(id,d)
          if j then dependencies[j]=true end
        end
      end
    end
    local function upstream()
      while queue[head] do
        local id=queue[head];head=head+1
        for d=1,4 do
          local j=Sim.adjacent(id,d)
          local n=j and s.tiles[j]
          if n and n.water_class=="river" and not seen[j] and (n.h or 0)>=(s.tiles[id].h or 0) then
            toward[j]=directions[(d+1)%4+1]
            seen[j]=true;queue[#queue+1]=j
          end
        end
      end
    end
    upstream()
    table.sort(river,function(a,b)
      local u,v=s.tiles[a].h or 0,s.tiles[b].h or 0
      return u==v and a<b or u<v
    end)
    -- Inland basins have a calm sink; upland stretches still animate
    -- toward their lowest reachable pool. No uphill arrows are invented.
    for _,id in ipairs(river) do
      if not seen[id] then
        seen[id]=true;queue[#queue+1]=id;upstream()
      end
    end
    return toward
  end
  function M.routes(s,dependencies)
    local river={}
    for id,t in ipairs(s.tiles) do
      if t.water_class=="river" then river[#river+1]=id end
    end
    return trace(s,river,dependencies)
  end
  function M.cached()
    local C={}
    local flows,dependencies,visited,tiles,grid,revision,topology
    local function current(s)
      return tiles==s.tiles and grid==s.corner_grid and revision==s.corner_grid.revision
    end
    function C.at(s,id)
      if not flows or not current(s) or topology~=s.topology then
        flows,dependencies,visited={},{},{}
        tiles,grid,revision,topology=s.tiles,s.corner_grid,s.corner_grid.revision,s.topology
      end
      if visited[id] then return flows[id] end
      local here=tiles[id]
      if not here or here.water_class~="river" then return end
      -- Any influence on these arrows comes from this component or its
      -- immediate shore. Discover it now, not every river on the map.
      -- Sorting the outlet seeds by ID reproduces the global queue's
      -- tie-break; disconnected components never exchange a queue entry.
      local river,head={id},1
      visited[id]=true
      while river[head] do
        local at=river[head];head=head+1
        for d=1,4 do
          local j=Sim.adjacent(at,d)
          local t=j and tiles[j]
          if t and not visited[j] and t.water_class=="river" then
            visited[j]=true;river[#river+1]=j
          end
        end
      end
      table.sort(river)
      for at,flow in pairs(trace(s,river,dependencies)) do flows[at]=flow end
      return flows[id]
    end
    function C.after_plain_flood(s,previous,first)
      if not flows or not current(s) or previous==nil or topology~=previous or s.topology~=previous+1 then return end
      for i=first,#s.changed do
        if dependencies[s.changed[i]] then return end
      end
      -- A plain tide cannot create a river. Alongside the river set, the
      -- only observed inputs are the actual four neighboring parcels.
      topology=s.topology
    end
    return C
  end
  return M
end
