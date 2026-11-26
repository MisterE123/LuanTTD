-- Shared source timeline interpolation. On the worker use the canonical
-- ground and translate the final pose rather than shipping vehicle routes.
return function(Sim,visual)
  local P={}
  function P.coordinates(s,frames,length,at)
    local x,z,yaw,bridge,hidden,tunnel=visual.at(frames,at,length)
    if hidden then
      -- Keep the upstream hidden flag and vehicle controller semantics.
      -- Only the native 3D observer gets a pose inside a verified bore.
      local span=tunnel and s.stock_road_tunnels and s.stock_road_tunnels[tunnel]
      local id=Sim.id(math.floor((x+.5)/2),math.floor((z+.5)/2))
      if span and (id==span.start or id==span["end"] or span.middle_by_tile and span.middle_by_tile[id]) then
        return x,z,yaw,nil,span.base+.52
      end
      return
    end
    return x,z,yaw,bridge
  end
  local function ground(surface,bridge,px,pz)
    local id=Sim.id(math.floor((px+.5)/2),math.floor((pz+.5)/2))
    if bridge and bridge.middle_by_tile[id] then return bridge.deck+.52 end
    if id then return surface(id,px,pz) end
    return .52
  end
  function P.finish(s,surface,x,z,yaw,bridge,bore_height)
    if x==nil then return end
    if bore_height~=nil then return {x=x,y=bore_height,z=z},yaw,0,true end
    local span=bridge and s.stock_road_bridges[bridge]
    local sy,cy=math.sin(yaw),math.cos(yaw)
    local look=.10
    local rise=ground(surface,span,x+look*sy,z+look*cy)-ground(surface,span,x-look*sy,z-look*cy)
    return {x=x,y=ground(surface,span,x,z),z=z},yaw,-math.atan(rise/(2*look))
  end
  function P.sample(s,frames,length,at,surface)
    return P.finish(s,surface,P.coordinates(s,frames,length,at))
  end
  function P.timeline_coordinates(s,v,fraction)
    local timeline=Sim.road_motion_timeline(s,v.id)
    if not timeline then return false end
    local c=timeline.cursors
    local sample=1+fraction*(#c-1)
    local k=math.floor(sample)
    local a,b=c[k],c[math.min(k+1,#c)]
    if a==0 then return true end
    local i=b==0 and a or a+(b-a)*(sample-k)
    return true,P.coordinates(s,timeline.frames,#timeline.frames,i)
  end
  function P.timeline(s,v,fraction,surface)
    local computed,x,z,yaw,bridge,bore_height=P.timeline_coordinates(s,v,fraction)
    if not computed then return false end
    if x==nil then return true end
    return true,P.finish(s,surface,x,z,yaw,bridge,bore_height)
  end
  return P
end
