-- Development bridge from the legacy campaign to the original OpenTTD
-- height field. It is deliberately a preview, not the construction adapter.
return function(Sim,Terrain,s)
  local levels,w,d={},Sim.W+1,Sim.H+1
  local function index(x,z) return (z-1)*w+x end
  for z=1,d do for x=1,w do
    local h,cap=0,255
    for a=x-1,x do for b=z-1,z do
      local id=Sim.id(a,b)
      if id then
        local t=s.tiles[id]
        h=math.max(h,t.h)
        if t.build or t.site or t.house or t.terrain=="water" then cap=math.min(cap,t.h) end
      end
    end end
    levels[index(x,z)]=math.min(h,cap)
  end end
  -- Lower discontinuous corners to the upper envelope consistent with
  -- their neighbors; any flat water or structure corner remains flat.
  for z=1,d do for x=1,w do
    local i=index(x,z)
    levels[i]=math.min(levels[i], x>1 and levels[i-1]+1 or 255, z>1 and levels[i-w]+1 or 255)
  end end
  for z=d,1,-1 do for x=w,1,-1 do
    local i=index(x,z)
    levels[i]=math.min(levels[i],x<w and levels[i+1]+1 or 255,z<d and levels[i+w]+1 or 255)
  end end
  return Terrain.new(Sim.W,Sim.H,function(x,z) return levels[index(x,z)] end)
end
