-- World polylines for the qualified wooden bridge art only. Sensor input
-- for a moving 3D shoe, never an independent source of electrical power.
return function(Sim,World,Art,Track,flat_height)
  local function pick(s,id,axis,wormhole)
    if not id then return end
    local span=World.by_portal(s,id)
    local name,dir
    if span then
      if span.kind~="bridge" or span.bridge_type~=0 or span.axis~=axis or span.railtype~=1 then return end
      local head=span.start==id and span.head or span.tail
      name,dir=head.flat_ramp and "head_flat" or "head_ramp",head.inside_direction
    else
      local above=World.by_bridge_middle(s,id)
      if above then
        if not wormhole or above.bridge_type~=0 or above.axis~=axis or above.railtype~=1 then return end
        span,name,dir=above,"span",axis
      end
    end
    local x,z=Sim.xy(id)
    local u=2*(axis==Track.X and x or z)+.5
    if span then
      local low=axis==Track.X and Track.NE or Track.NW
      local a,b=Art.wire_edge(name,dir,low,span.deck),Art.wire_edge(name,dir,Track.reverse_side(low),span.deck)
      if a==nil or b==nil then return end
      return {u-1,a,u+1,b},true
    end
    local tile=s.tiles[id]
    if not tile or tile.rail_type~=1 or tile.rail_tracks~=2^axis or tile.rail_depot_dir~=nil then return end
    local flat=flat_height(id,tile.rail_tracks)
    if flat==nil then return end
    local h=flat+1.398
    return {u-1,h,u+1,h},false
  end
  return function(s,id,td,wormhole)
    local axis=Track.valid_trackdir(td) and Track.track(td)
    if axis~=Track.X and axis~=Track.Y then return end
    local c,around=pick(s,id,axis,wormhole)
    if not c then return end
    local x,z=Sim.xy(id)
    local d=axis==Track.X and 1 or 0
    local left,l_bridge=pick(s,Sim.id(x-d,z-(1-d)),axis,wormhole or around)
    local right,r_bridge=pick(s,Sim.id(x+d,z+(1-d)),axis,wormhole or around)
    if not (around or l_bridge or r_bridge) then return end
    local rows={}
    if left and math.abs(left[4]-c[2])<1e-8 then rows[#rows+1]=left end
    rows[#rows+1]=c
    if right and math.abs(c[4]-right[2])<1e-8 then rows[#rows+1]=right end
    return rows,axis==Track.X and "x" or "z",2*(axis==Track.X and z or x)+.5
  end
end
