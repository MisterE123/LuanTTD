-- SPDX-License-Identifier: GPL-2.0-only
-- Visual adapter for independently pivoting straddle bogies. Does not
-- alter source track topology, movement, ownership, or switch state.
return function(Sim,T,diagonal,stock,surface,read)
  local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local Guide=dofile(mod.."/rail_guideway_profiles.lua")
  local pi=math.pi
  local sqrt,sin,atan2=math.sqrt,math.sin,math.atan2
  local function pose(id,td,f,gauge)
    local x,z,dx,dz=diagonal(id,td,f)
    if not x then x,z,dx,dz=stock(td,f) end
    local u,v=Sim.xy(id)
    local level,tilt=surface(id,td,f)
    if level==nil then return end
    return {x=2*u+.5+x,y=level+Guide.by_gauge[gauge].offset,z=2*v+.5+z},dx,dz,tilt or 0
  end
  local function neighbor(train,id,td,gauge)
    local exit=T.exit_side(td)
    local n=Sim.adjacent(id,4-exit)
    local tile=n and read(n)
    if not (tile and tile.rail_tracks and tile.rail_type==gauge) then return end
    -- At a split, choose only a link actually recorded by the authority.
    -- Follow the plan either way; reversing the visual chassis does not
    -- replan the stock route or guess at a switch it hasn't crossed.
    local tm=train.route or {}
    local function along(before,after)
      if before and before.tile==id and before.td==td and after and after.tile==n and
          T.entry_side(after.td)==T.reverse_side(exit) and T.has(tile.rail_tracks,T.track(after.td)) then
        return after.td
      end
    end
    local index=math.min(train.index or 1,#tm)
    for j=math.max(1,index-4),math.min(#tm,index+4) do
      local a,b=tm[j],tm[j+1]
      local route=along(a,b)
      if route then return n,route end
      if j>1 and a.tile==id and T.reverse_trackdir(a.td)==td then
        local previous=tm[j-1]
        route=T.reverse_trackdir(previous.td)
        if previous.tile==n and T.entry_side(route)==T.reverse_side(exit) and T.has(tile.rail_tracks,T.track(route)) then
          return n,route
        end
      end
    end
    local way
    for track=0,5 do
      if T.has(tile.rail_tracks,track) then
        local q=T.trackdir_for_entry(track,exit)
        if q then
          if way then return end
          way=q
        end
      end
    end
    if way then return n,way end
  end

  local function at_distance(train,id,td,f,distance,gauge)
    local back=distance<0
    if back then td,f,distance=T.reverse_trackdir(td),1-f,-distance end
    local p,dx,dz,pitch=pose(id,td,f,gauge)
    if not p then return end
    -- Parametric tracks can be curved, eased or bank-height transitions.
    -- Measure horizontally like existing stock spacing; read the exact
    -- height and tangent again at the solved sample, not interpolated nodes.
    while distance>1e-8 do
      local nextf=math.min(1,f+1/64)
      if nextf==f then
        local nextid,nexttd=neighbor(train,id,td,gauge)
        local q
        if nextid then q=pose(nextid,nexttd,0,gauge) end
        if not q then
          p={x=p.x+dx*distance,y=p.y+sin(pitch)*distance,z=p.z+dz*distance}
          break
        end
        id,td,f=nextid,nexttd,0
        p,dx,dz,pitch=pose(id,td,f,gauge)
      else
        local q=pose(id,td,nextf,gauge)
        if not q then return end
        local len=sqrt((q.x-p.x)^2+(q.z-p.z)^2)
        if len>=distance then
          p,dx,dz,pitch=pose(id,td,f+(nextf-f)*distance/len,gauge)
          break
        end
        distance=distance-len
        f=nextf
        p,dx,dz,pitch=pose(id,td,f,gauge)
      end
    end
    local sign=back and -1 or 1
    return p,dx*sign,dz*sign,pitch*sign
  end

  return function(train,p,flipped)
    local tile=read(p.id)
    local gauge=train.advanced_gauge or tile and tile.rail_type
    if p.wormhole or not Guide.by_gauge[gauge] then return end
    local sign=flipped and -1 or 1
    local front,fdx,fdz,fp=at_distance(train,p.id,p.td,p.progress,.259*sign,gauge)
    local back,bdx,bdz,bp=at_distance(train,p.id,p.td,p.progress,-.246*sign,gauge)
    if not (front and back) then return end
    local dx,dz=front.x-back.x,front.z-back.z
    local length=sqrt(dx*dx+dz*dz)
    if length<1e-8 then return end
    -- Keep the two authored mounting pins on the guideway's chord.
    local k=.246/(.246+.259)
    local center={x=back.x+dx*k,y=back.y+(front.y-back.y)*k,z=back.z+dz*k}
    local body={x=-atan2(front.y-back.y,length),y=pi-atan2(dx,dz),z=0}
    local gear={
      {pos=front,rotation={x=-fp*sign,y=pi-atan2(fdx*sign,fdz*sign),z=0}},
      {pos=back,rotation={x=-bp*sign,y=pi-atan2(bdx*sign,bdz*sign),z=0}},
    }
    return center,body,gear
  end
end
