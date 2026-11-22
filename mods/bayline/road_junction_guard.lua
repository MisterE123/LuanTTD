-- Native 3D junction protection for fresh campaigns. Original 14.1 tracks,
-- speed, lookahead and following remain untouched. Its viewport
-- proximity rule allows differently headed vehicles to overlap
-- during some tight merges; this host policy gates whole junction
-- clusters until the first vehicle's swept model envelope is clear.
return function(Sim,Presentation)
  local G={}
  local cache=setmetatable({},{__mode="k"})
  local abs,sqrt,floor=math.abs,math.sqrt,math.floor
  -- Max horizontal extents of the shipped coach and freight meshes,
  -- rounded upward; the extra margin covers in-between render yaw.
  local radius=sqrt(.38*.38+.14*.14)+.065
  local function is_junction(s,id)
    local t=s.tiles[id]
    if not t or t.build~="road" or t.level_crossing or t.road_disallowed or t.road_bridge_id or t.road_tunnel_id then return false end
    local bits=Sim.road_bits(s,id)
    local n=0
    for i=1,4 do n=n+floor(bits/2^(i-1))%2 end
    return n>=3
  end
  local function board(s)
    local prev=cache[s]
    if prev and prev.topology==s.topology then return prev end
    local junctions,I={},{}
    for id in ipairs(s.tiles) do
      if is_junction(s,id) then junctions[id]=true end
    end
    for id in ipairs(s.tiles) do if junctions[id] and not I[id] then
      local cluster={tile={},scan={}}
      local queue={id}
      I[id]=cluster
      local q=1
      while queue[q] do
        local at=queue[q];q=q+1
        local x,z=Sim.xy(at)
        cluster.tile[#cluster.tile+1]={x=x*2+.5,z=z*2+.5}
        for nx=x-1,x+1 do for nz=z-1,z+1 do
          local n=Sim.id(nx,nz);if n then cluster.scan[n]=true end
        end end
        for d=1,4 do
          local n=Sim.adjacent(at,d)
          if n and junctions[n] and not I[n] and Sim.road_geometry_connected(s,at,d,n) then
            queue[#queue+1]=n;I[n]=cluster
          end
        end
      end
    end end
    prev={topology=s.topology,junctions=I,aprons={}}
    cache[s]=prev
    return prev
  end
  local function center(f)
    return Presentation.xy(f[1],f[2],f[5])
  end
  local function touches(posx,posz,cell)
    local nearx=math.max(0,abs(posx-cell.x)-1)
    local nearz=math.max(0,abs(posz-cell.z)-1)
    return nearx*nearx+nearz*nearz<radius*radius
  end
  local function touches_cluster(posx,posz,g)
    for _,cell in ipairs(g.tile) do
      if touches(posx,posz,cell) then return true end
    end
    return false
  end
  local function apron(s,id)
    local map=board(s)
    local current=map.aprons[id]
    if current~=nil then return current or nil end
    local t=s.tiles[id]
    if not t or not t.road_stop_pair then map.aprons[id]=false;return end
    local road
    for dir=1,4 do
      local adj=Sim.adjacent(id,dir)
      if adj and Sim.road_edge(s,id,dir) then road=map.junctions[adj];break end
    end
    local x,z=Sim.xy(id)
    local place={tile={{x=x*2+.5,z=z*2+.5}},scan={}}
    for nx=x-1,x+1 do for nz=z-1,z+1 do
      local n=Sim.id(nx,nz)
      if n then place.scan[n]=true end
    end end
    if road then
      for _,cell in ipairs(road.tile) do place.tile[#place.tile+1]=cell end
      for n in pairs(road.scan) do place.scan[n]=true end
    end
    map.aprons[id]=place
    return place
  end
  local function inbound_in_apron(s,W,area,stop_id,except)
    for tile in pairs(area.scan) do
      for _,r in ipairs(W.vehicles_at(tile)) do
        if r.id~=except then
          local vehicle=s.fleet[r.id]
          local branch=vehicle and vehicle.road_bay_branch
          if branch and branch.tile==stop_id and not vehicle.road_bay_claim then
            local x,z=center(r.frame)
            if touches_cluster(x,z,area) then return true end
          end
        end
      end
    end
    return false
  end
  -- A stock bay queue waits just outside its tile. The full 3D model can
  -- reach into its turning apron there, especially when the immediately
  -- connected road is also a junction. Hold approaching buses before
  -- that shared area. An already-admitted arrival has priority over a
  -- new departure if an actual stock bay is free. No extra saved claim:
  -- the admitted arrival is derived from the live/saved route and pose.
  function G.bay_clearance(s,W,v,previous,wanted,action,Bay)
    if not s.road_junction_clearance then return true end
    if action=="depart" then
      local id=v.road_bay_claim.tile
      local place=apron(s,id)
      local status=place and Bay.report(s,id)
      return not (status and not (status.first and status.second) and inbound_in_apron(s,W,place,id,v.id))
    end
    local branch=not v.road_bay_claim and v.road_bay_branch
    if not branch then return true end
    local place=apron(s,branch.tile)
    if not place then return true end
    local x,z=center(wanted)
    if not touches_cluster(x,z,place) then return true end
    x,z=center(previous)
    if touches_cluster(x,z,place) then return true end
    local status=Bay.report(s,branch.tile)
    return not status or not (status.entrance or status.first and status.second or
      inbound_in_apron(s,W,place,branch.tile,v.id))
  end
  function G.check(s,W,v,prev,next_pose,z)
    if not s.road_junction_clearance or prev[12] or next_pose[12] then return true end
    local groups=board(s).junctions
    if not next(groups) then return true end
    local x,y=center(next_pose)
    local tilex,tilez=floor((x+.5)/2),floor((y+.5)/2)
    local oldx,oldz=center(prev)
    local tested={}
    for nx=tilex-1,tilex+1 do for nz=tilez-1,tilez+1 do
      local id=Sim.id(nx,nz)
      local g=id and groups[id]
      -- A vehicle already inside the cluster must be able to clear.
      -- Separate clusters cannot both touch a model of this radius.
      if g and not tested[g] and touches_cluster(x,y,g) and not touches_cluster(oldx,oldz,g) then
        tested[g]=true
        for scan in pairs(g.scan) do
          for _,other in ipairs(W.vehicles_at(scan)) do
            if other.id~=v.id and not other.frame[12] and abs(other.z-z)<6 then
              local a,b=center(other.frame)
              if touches_cluster(a,b,g) then return false end
            end
          end
        end
      end
    end end
    return true
  end
  return G
end
