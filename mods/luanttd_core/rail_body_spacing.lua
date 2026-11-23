-- Reproject an already-sampled consist onto the measured 3D rail centerline.
-- OpenTTD measures coupled vehicles in max(dx, dz) map pixels. That is the
-- correct simulation metric but becomes sqrt(2) longer on a rendered 45°
-- rail; the stock-length mesh couplers would be left hanging in midair.
return function(Sim,Track,diagonal,stock)
  local sides={[0]={-1,0},{0,1},{1,0},{0,-1}}
  local function xyz(p,f)
    local x,z,dx,dz=diagonal(p.id,p.td,f)
    if x==nil then x,z,dx,dz=stock(p.td,f) end
    local u,v=Sim.xy(p.id)
    return 2*u+x,2*v+z,dx,dz
  end
  local function next_on_known_path(a,b)
    -- We may cross only the directly observed boundary, proving both
    -- endpoints with directed poses. Do not infer a turn via fresh routing.
    local exit=Track.exit_side(a.td)
    if Track.entry_side(b.td)~=Track.reverse_side(exit) then return false end
    local from_x,from_z=Sim.xy(a.id)
    local to_x,to_z=Sim.xy(b.id)
    local d=sides[exit]
    return to_x==from_x+d[1] and to_z==from_z+d[2]
  end
  local function outgoing(p,f,d)
    return {id=p.id,td=p.td,progress=f,total=d,reversed=p.reversed}
  end
  local function extend(p,distance,sign)
    -- The outermost wheelbase can reach beyond the observed consist.
    -- Follow its own segment to the edge, then continue the port tangent.
    -- This never picks an unobserved track at a switch.
    local f=p.progress
    local x,z,dx,dz=xyz(p,f)
    while distance>0 do
      local step=math.max(0,math.min(1,f+sign/64))
      if step==f then return x+sign*distance*dx,z+sign*distance*dz end
      local u,v,ux,uz=xyz(p,step)
      local length=math.sqrt((u-x)^2+(v-z)^2)
      if length>=distance then return x+(u-x)*distance/length,z+(v-z)*distance/length end
      distance=distance-length
      f,x,z,dx,dz=step,u,v,ux,uz
    end
    return x,z
  end
  return function(poses,parts,centered)
    if #parts<2 then return end
    local eased=false
    for i=1,#parts do
      local p=poses[i]
      if not p or p.wormhole then return end
      if not eased then eased=diagonal(p.id,p.td,p.progress)~=nil end
    end
    if not eased then return end
    local head=poses[1]
    local points={outgoing(head,head.progress,0)}
    local x,z=xyz(head,head.progress)
    points[1].x,points[1].z=x,z
    local total=0
    local function append(p,first,last)
      local n=math.max(1,math.ceil(math.abs(first-last)*12))
      for k=0,n do
        local f=first+(last-first)*k/n
        local u,v=xyz(p,f)
        total=total+math.sqrt((u-x)^2+(v-z)^2)
        local q=outgoing(p,f,total)
        q.x,q.z=u,v;points[#points+1]=q
        x,z=u,v
      end
    end
    local raw_dist={0}
    for i=2,#parts do
      local a,b=poses[i-1],poses[i]
      if b.reversed~=a.reversed then return end
      if a.id==b.id and a.td==b.td and a.progress>=b.progress then
        append(a,a.progress,b.progress)
      elseif next_on_known_path(b,a) then
        append(a,a.progress,0);append(b,1,b.progress)
      else return end
      raw_dist[i]=total
    end
    local targets={0}
    for i=2,#parts do
      -- All current shipped body envelopes use the scaled stock 8/16
      -- length. Preserve stock integer rounding for any shorter consist.
      targets[i]=targets[i-1]+(math.floor((parts[i-1].length or 8)/2)+math.floor(((parts[i].length or 8)+1)/2))/8
      if targets[i]>raw_dist[i]+.015 and not centered then return end
    end
    local left=total-targets[#parts]
    if left<-.015 then return end
    -- A double-ended set changes driving cabs, not physical ends.
    -- Compress about its center, giving the same positions both ways.
    local lead=centered and math.max(0,left)/2 or 0
    local function at_distance(where)
      if where<0 then return extend(head,-where,1) end
      if where>total then return extend(poses[#parts],where-total,-1) end
      local l,r=1,#points
      while r-l>1 do
        local h=math.floor((l+r)/2)
        if points[h].total<=where then l=h else r=h end
      end
      local a,b=points[l],points[r]
      if b.total<=a.total then return a.x,a.z end
      local k=(where-a.total)/(b.total-a.total)
      return a.x+(b.x-a.x)*k,a.z+(b.z-a.z)*k
    end
    local p=1
    local fitted={}
    for i=1,#parts do
      local where=targets[i]+lead
      while p<#points and points[p+1].total<=where do p=p+1 end
      local a,b=points[p],points[p+1]
      local f=a.progress
      if b and a.id==b.id and a.td==b.td and b.total>a.total then
        f=f+(b.progress-f)*(where-a.total)/(b.total-a.total)
      end
      if i==1 and lead==0 then a,f=head,head.progress end
      local body=outgoing(a,f,where)
      -- A rigid body follows the chord across its wheelbase, not the
      -- instantaneous rail tangent under its center. Averaging these
      -- positions also puts the wheels on the curve instead of letting
      -- the vehicle and coupler ends swing off the alignment.
      local half=(parts[i].length or 8)/16-.04
      local fx,fz=at_distance(where-half)
      local rx,rz=at_distance(where+half)
      local dx,dz=fx-rx,fz-rz
      local length=math.sqrt(dx*dx+dz*dz)
      if length>0 then
        body.x,body.z,body.dx,body.dz=(fx+rx)/2,(fz+rz)/2,dx/length,dz/length
      end
      fitted[i]=body
    end
    return fitted
  end
end
