-- Geometry scope for the initial native RC1 support mount. Leave roofs,
-- transitions, terrain grades and signal masts to their own art.
return function(Sim,Track,Kernel,terrain)
  local V={}
  local edges={[1]={0,2},[2]={1,3},[4]={0,3},[8]={1,2},[16]={2,3},[32]={0,1}}
  V.poles={{},{}}
  local place={{0,3,0,0},{1,5,0,1},{2,7,1,2},{3,1,1,3},
    {0,4,0},{0,6,0},{1,0,0},{1,5,1},{1,6,1},{2,0,1},{2,2,0},{2,7,0},{3,2,1},{3,4,1}}
  for _,rule in ipairs(place) do
    local edge,dir,slot,standard=unpack(rule)
    V.poles[slot+1][edge*8+dir+1]=standard and "rail_edge_pylon_"..standard or
      ("rail_curve_pylon_%d_%d_%d"):format(edge,dir,slot)
  end
  function V.at(s,id,t)
    if not t or t.rail_type~=1 or not edges[t.rail_tracks] then return end
    local d=s.stock_rail_dispatch
    local signals=d and d.signals and d.signals.records
    local function plain(i,b)
      if not i or not b or b.build~="stock_rail" or b.rail_type~=1 or not edges[b.rail_tracks]
          or b.rail_station_id or b.rail_depot_dir~=nil or b.rail_waypoint_id or b.level_crossing or b.rail_span_id
          or b.signal or signals and signals[i] then return end
      if Sim.bridge_deck_at(s,i) then return end
      local slope,h=terrain.tile(i)
      if slope~=0 then return end
      return {tracks=b.rail_tracks,wires=b.rail_tracks,z=h*8,grade=0}
    end
    local home=plain(id,t)
    if not home then return end
    local x,z=Sim.xy(id)
    local group=(x-1)%2*2+(z-1)%2
    local bits=0
    for slot,edge in ipairs(edges[t.rail_tracks]) do
      local j=Sim.adjacent(id,4-edge)
      local n=j and s.tiles[j]
      local other=plain(j,n)
      if n and (n.rail_type==1 and not other or n.rail_span_id or n.level_crossing) then return end
      if j and terrain.tile(j)~=0 then return end
      local dir=Kernel.choose(edge,group,home,other)
      if dir~=nil then
        local code=edge*8+dir+1
        if not V.poles[slot][code] then return end
        bits=bits+code*(slot==1 and 1 or 33)
      end
    end
    return bits
  end
  return V
end
