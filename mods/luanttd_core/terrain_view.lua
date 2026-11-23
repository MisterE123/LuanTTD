-- 3D view over a canonical OpenTTD corner grid. Rendering and ray
-- intersection use the same continuous slope field, with model units
-- supplied by the restore/scene adapter.
return function(Sim,Terrain,grid,projection)
  local V={}
  function V.tile(id)
    local x,z=Sim.xy(id)
    if projection then
      local row=projection.terrain(x,z)
      if row then return row.slope,row.level,row.top end
      return nil
    end
    return Terrain.tile(grid,x,z)
  end
  function V.sample(id,x,z)
    local a,b=Sim.xy(id)
    local u,v=(x-a*2+.5)/2,(z-b*2+.5)/2
    if projection then
      local row=projection.terrain(a,b)
      if row then return .5+Terrain.normalized_height(row.slope,row.level,u,v) end
      return nil
    end
    return .5+Terrain.height(grid,a,b,u,v)
  end
  function V.pick(origin,direction,allowed,max_dist,surface)
    -- Horizontal DDA gives exact entry and exit parameters for each tile.
    -- Split each segment at both diagonals, so each interval is planar for
    -- every one of OpenTTD's corner shapes (including ridges and valleys).
    local sample=surface or V.sample
    local dx,dz=direction.x,direction.z
    local limit=max_dist or 90
    local x,z=math.floor((origin.x+.5)/2),math.floor((origin.z+.5)/2)
    local function next_edge(pos,v,i)
      if v==0 then return 0,math.huge,math.huge end
      local step=v>0 and 1 or -1
      return step,((i+(step==1 and 1 or 0))*2-.5-pos)/v,math.abs(2/v)
    end
    local sx,tx,stepx=next_edge(origin.x,dx,x)
    local sz,tz,stepz=next_edge(origin.z,dz,z)
    local entry=0
    for _=1,math.ceil(limit*math.sqrt(2)/2)+3 do
      local leave=math.min(tx,tz,limit)
      local id=Sim.id(x,z)
      if id and (not allowed or allowed(id)) then
        local params={entry,leave}
        local u,v=(origin.x-2*x+.5)/2,(origin.z-2*z+.5)/2
        local du,dv=dx/2,dz/2
        local function crossing(c,m)
          if m==0 then return end
          local t=c/m
          if t>entry and t<leave then params[#params+1]=t end
        end
        crossing(1-u-v,du+dv)
        crossing(v-u,du-dv)
        table.sort(params)
        local function offset(t)
          local level=sample(id,origin.x+dx*t,origin.z+dz*t)
          return level and origin.y+direction.y*t-level
        end
        local last=offset(params[1])
        for i=2,#params do
          local cur=offset(params[i])
          if last and cur and last>=0 and cur<=0 then
            local a,b=params[i-1],params[i]
            local hit=(last==cur) and a or a+(b-a)*last/(last-cur)
            return id,hit,{x=origin.x+dx*hit,y=origin.y+direction.y*hit,z=origin.z+dz*hit}
          end
          last=cur
        end
      end
      if leave>=limit then break end
      if tx<=leave then x,tx=x+sx,tx+stepx end
      if tz<=leave then z,tz=z+sz,tz+stepz end
      entry=leave
    end
  end
  return V
end
