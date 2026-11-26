-- Geometry scope for the initial native RC1 support mount. Leave roofs,
-- transitions, terrain grades and signal masts to their own art.
return function(Sim,Track,Kernel,terrain)
  local V={}
  V.directions={[0]=3,[1]=5,[2]=7,[3]=1}
  function V.at(s,id,t)
    if not t or t.rail_type~=1 or t.rail_tracks~=1 and t.rail_tracks~=2 then return end
    local d=s.stock_rail_dispatch
    local signals=d and d.signals and d.signals.records
    local function plain(i,b)
      if not i or not b or b.build~="stock_rail" or b.rail_type~=1 or b.rail_tracks~=1 and b.rail_tracks~=2
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
    local axis=t.rail_tracks==1 and 0 or 1
    for i=0,1 do
      local edge=axis+i*2
      local j=Sim.adjacent(id,4-edge)
      local n=j and s.tiles[j]
      local other=plain(j,n)
      if n and (n.rail_type==1 and not other or n.rail_span_id or n.level_crossing) then return end
      if j and terrain.tile(j)~=0 then return end
      local dir=Kernel.choose(edge,group,home,other)
      if dir~=nil then
        if dir~=V.directions[edge] then return end
        bits=bits+2^i
      end
    end
    return bits
  end
  return V
end
