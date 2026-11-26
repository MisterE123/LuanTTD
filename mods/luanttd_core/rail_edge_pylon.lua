-- Geometry scope for the initial native RC1 support mount. Leave roofs,
-- transitions, terrain grades and signal masts to their own art.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
return function(Sim,Track,Kernel,terrain,Wire)
  local V={}
  Wire=Wire or dofile(mod.."rail_turnout_wire.lua")(Sim,Track,dofile(mod.."openttd/rail_wire_mask.lua")(Track))
  local Compound=dofile(mod.."rail_compound_pylon_scope.lua")(Sim,Track,Kernel,Wire,terrain)
  local OPTIONS={{3,4,6},{0,5,6},{0,2,7},{1,2,4}}
  local TAG=2048 -- separate from the original two base-33 slots
  V.distributed={}
  for edge,directions in ipairs(OPTIONS) do
    V.distributed[edge]={}
    for index,dir in ipairs(directions) do
      V.distributed[edge][index]=("rail_distributed_pylon_%d_%d"):format(edge-1,dir)
    end
  end
  function V.is_distributed(profile) return profile~=nil and profile>=TAG end
  function V.decode(profile,slot)
    return V.is_distributed(profile) and math.floor((profile-TAG)/4^(slot-1))%4 or 0
  end
  local edges={[1]={0,2},[2]={1,3},[4]={0,3},[8]={1,2},[16]={2,3},[32]={0,1}}
  V.poles={{},{}}
  local place={{0,3,0,0},{1,5,0,1},{2,7,1,2},{3,1,1,3},
    {0,4,0},{0,6,0},{1,0,0},{1,5,1},{1,6,1},{2,0,1},{2,2,0},{2,7,0},{3,2,1},{3,4,1}}
  for _,rule in ipairs(place) do
    local edge,dir,slot,standard=unpack(rule)
    V.poles[slot+1][edge*8+dir+1]=standard and "rail_edge_pylon_"..standard or
      ("rail_curve_pylon_%d_%d_%d"):format(edge,dir,slot)
  end
  local function simple(s,id,t)
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
  function V.at(s,id,t)
    if not t or t.rail_type~=1 or not t.rail_tracks then return end
    local complex=Wire.supported(t.rail_tracks)
    if not complex then
      for edge=0,3 do
        local mate=Sim.adjacent(id,4-edge)
        local n=mate and s.tiles[mate]
        if n and n.rail_type==1 and Wire.supported(n.rail_tracks) then complex=true;break end
      end
    end
    if complex then
      local all=Compound.at(s,id,t)
      if all then
        local code=TAG
        for _,v in ipairs(all) do
          local known=false
          for i,dir in ipairs(OPTIONS[v.edge+1]) do
            if v.dir==dir then code=code+i*4^v.edge;known=true;break end
          end
          -- Keep fallback geometry for any future unmodeled position.
          if not known then return end
        end
        return code
      end
    end
    return simple(s,id,t)
  end
  return V
end
