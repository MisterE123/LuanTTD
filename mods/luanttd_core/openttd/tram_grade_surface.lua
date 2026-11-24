-- Stock ELRL and ordinary Road types share GetRoadFoundation. The
-- renderer and route boundary should consume the same transformed
-- surface rather than either being placed on the raw terrain slope.
return function(Road,Slope)
  local G={}
  local edge={
    [1]={.5,0}, [2]={1,.5}, [3]={.5,1}, [4]={0,.5},
  }
  local planes={[3]=true,[6]=true,[9]=true,[12]=true}
  function G.surface(mask,base,tram_bits,road_bits)
    local normal=type(mask)=="number" and mask%1==0 and mask>=0 and mask<=14
    if not (normal or mask==23 or mask==27 or mask==29 or mask==30) or type(base)~="number" or
        type(tram_bits)~="number" or tram_bits%1~=0 or tram_bits<1 or tram_bits>15 or
        road_bits~=nil and (type(road_bits)~="number" or road_bits%1~=0 or road_bits<0 or road_bits>15) then
      return nil,"INVALID_TRAM_SURFACE"
    end
    local foundation=Road.foundation(mask,tram_bits)
    if road_bits and road_bits~=0 and Road.foundation(mask,road_bits)~=foundation then
      return nil,"WRONG_SLOPE"
    end
    local shape,rise=Slope.foundation(mask,foundation)
    if shape~=0 and not planes[shape] then return nil,"UNSUPPORTED_TRAM_SURFACE" end
    return {grade=shape,base=base+rise,foundation=foundation}
  end
  function G.at(surface,u,v)
    return surface.base+Slope.surface(u,v,surface.grade)
  end
  function G.edge_height(surface,d)
    local t=edge[d]
    return G.at(surface,t[1],t[2])
  end
  function G.match(a,b,d)
    return G.edge_height(a,d)==G.edge_height(b,(d+1)%4+1)
  end
  return G
end
