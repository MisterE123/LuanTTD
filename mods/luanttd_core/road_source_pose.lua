-- Shared source timeline interpolation. On the worker use the canonical
-- ground and translate the final pose rather than shipping vehicle routes.
return function(Sim,visual)
  local P={}
  function P.sample(s,frames,length,at,surface)
    local x,z,yaw,bridge,hidden,tunnel=visual.at(frames,at,length)
    if hidden then
      -- Keep the upstream hidden flag and vehicle controller semantics.
      -- Only the native 3D observer gets a pose inside a verified bore.
      local span=tunnel and s.stock_road_tunnels and s.stock_road_tunnels[tunnel]
      local id=Sim.id(math.floor((x+.5)/2),math.floor((z+.5)/2))
      if span and (id==span.start or id==span["end"] or span.middle_by_tile and span.middle_by_tile[id]) then
        return {x=x,y=span.base+.52,z=z},yaw,0,true
      end
      return
    end
    local function ground(px,pz)
      local id=Sim.id(math.floor((px+.5)/2),math.floor((pz+.5)/2))
      local span=bridge and s.stock_road_bridges[bridge]
      if span and span.middle_by_tile[id] then return span.deck+.52 end
      if id then return surface(id,px,pz) end
      return .52
    end
    local sy,cy=math.sin(yaw),math.cos(yaw)
    local look=.10
    local rise=ground(x+look*sy,z+look*cy)-ground(x-look*sy,z-look*cy)
    return {x=x,y=ground(x,z),z=z},yaw,-math.atan(rise/(2*look))
  end
  function P.timeline(s,v,fraction,surface)
    local timeline=Sim.road_motion_timeline(s,v.id)
    if not timeline then return false end
    local c=timeline.cursors
    local sample=1+fraction*(#c-1)
    local k=math.floor(sample)
    local a,b=c[k],c[math.min(k+1,#c)]
    if a==0 then return true end
    local i=b==0 and a or a+(b-a)*(sample-k)
    return true,P.sample(s,timeline.frames,#timeline.frames,i,surface)
  end
  return P
end
