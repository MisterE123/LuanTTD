-- Stock simulation samples are unchanged. This view maps cross-track
-- samples 5 and 9 to the modeled street's lane centers, not its shoulders.
-- Pixel centers lie inside each 16-sample tile; half-pixel edges meet.
return function(lanes)
  local M={}
  local function axis(sample)
    local tile=math.floor((sample+.5)/16)
    local p=sample-tile*16
    local span=lanes.right_offset
    local q
    if p<5 then q=-1+(p+.5)*(1-span)/5.5
    elseif p<=9 then q=(p-7)*span/2
    else q=span+(p-9)*(1-span)/6.5 end
    return tile*2+.5+q
  end
  local function lerp(a,b,t) return a+(b-a)*t end
  function M.xy(x,y,f)
    -- Keep the longitudinal axis metrically linear on straight roads.
    -- Cross-track compression blends only across actual curve frames.
    f=f or .5
    return lerp(axis(x),x/8-.4375,f),lerp(y/8-.4375,axis(y),f)
  end
  function M.yaw(direction) return (direction-3)*math.pi/4 end
  function M.pose(f,g,t)
    local ax,az=M.xy(f[1],f[2],f[5])
    local bx,bz=M.xy(g[1],g[2],g[5])
    local x,z=lerp(ax,bx,t),lerp(az,bz,t)
    local delta=(g[3]-f[3]+4)%8-4
    return x,z,M.yaw(f[3]+delta*t)
  end
  function M.at(frames,progress,length)
    local k=length>1 and (progress-1)/(length-1) or 1
    k=1+(#frames-1)*math.max(0,math.min(1,k))
    local i=math.floor(k)
    local a,b=frames[i],frames[math.min(#frames,i+1)]
    local x,z,yaw=M.pose(a,b,k-i)
    local f=k-i<.5 and a or b
    return x,z,yaw,a[10] or b[10],f[13],f[14]
  end
  return M
end
