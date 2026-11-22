-- 3D projection onto the same surveyed curves used to build the track
-- meshes (tools/build_rail_art.py). Stock tile entry/progress stays separate.
return function(Track)
  local R={}
  local axes={[0]={-1,0},{0,1},{1,0},{0,-1}}
  local pi=math.pi
  local atan2=math.atan2
  function R.sample(td,f)
    local a,b=axes[Track.entry_side(td)],axes[Track.exit_side(td)]
    if Track.track(td)<2 then return a[1]*(1-2*f),a[2]*(1-2*f),b[1],b[2] end
    local x,z=a[1]+b[1],a[2]+b[2]
    local angle=atan2(a[2]-z,a[1]-x)
    local finish=atan2(b[2]-z,b[1]-x)
    local sign=(finish-angle)%(2*pi)<pi and 1 or -1
    local t=angle+sign*pi*.5*f
    local sn,cs=math.sin(t),math.cos(t)
    return x+cs,z+sn,-sn*sign,cs*sign
  end
  return R
end
