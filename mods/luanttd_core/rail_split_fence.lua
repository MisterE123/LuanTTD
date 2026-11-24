-- OpenTTD 16.0-RC1 DrawTrackDetails: use the stock ground's directional
-- fence and its diagonal corner height reference on modified ground.
-- The native cardinal mesh follows each real 3D foundation edge. Fence
-- anchoring is +1 X/Z at original base+1, independent of rails and risers.
return function(Slope)
  local F={}
  local quantize=512
  local bands={
    [2]={-.480,-.375,1.480,-.375},[3]={-.480,1.375,1.480,1.375},
    [5]={-.375,-.480,-.375,1.480},[6]={1.375,-.480,1.375,1.480},
    [8]={-.475,-.475,1.475,1.475},[9]={-.475,-.475,1.475,1.475},
    [10]={-.475,1.475,1.475,-.475},[11]={-.475,1.475,1.475,-.475},
  }
  local corners={[8]={1,0},[9]={0,1},[10]={0,0},[11]={1,1}}
  local wet_for_bit={[4]=10,[8]=11,[16]=8,[32]=9}
  function F.design(profile,ground,tracks,raw_base)
    if ground==13 then ground=wet_for_bit[tracks] end
    if not ground or not bands[ground] then return end
    local edge=bands[ground]
    local corner=corners[ground]
    local elevations={}
    local lift=profile.base_level-raw_base
    if corner then
      local h=lift+Slope.surface(corner[1],corner[2],profile.surface%32)
      for i=1,5 do elevations[i]=math.floor(h*quantize+.5) end
    else
      for i=0,4 do
        local x,z=edge[1]+(edge[3]-edge[1])*i/4,edge[2]+(edge[4]-edge[2])*i/4
        local h=lift+Slope.surface((x+.5)/2,(z+.5)/2,profile.surface)
        elevations[i+1]=math.floor(h*quantize+.5)
      end
    end
    return ("%d_%s"):format(ground,table.concat(elevations,"_")),edge,elevations,quantize
  end
  return F
end
