-- Road pavement and vehicle paths must not be bisected by a visual pier.
-- Let the bridge span between the neighboring bearings instead. This
-- deliberately does not change OpenTTD construction or road admission.
return function(architecture,prefix)
  local R={}
  for axis=0,1 do
    local asset=("%s_span_%d_road_clear"):format(prefix,axis)
    R[axis]=architecture("stock_"..asset,asset,prefix)
  end
  function R.under(t)
    return t and (t.build=="road" or t.build=="road_station" or t.build=="road_depot" or
      t.level_crossing~=nil or t.tram~=nil)
  end
  return R
end
