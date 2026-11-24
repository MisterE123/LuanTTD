-- Presentation only. A stationary emitter follows the local render projection;
-- the authoritative river and its occupants are never edited by this effect.
return function(core,Sim)
  local P={}
  local active,elapsed={},0
  local slopes={[3]={-1,0},[6]={0,-1},[9]={0,1},[12]={1,0}}
  local enter,leave,cap,period=22,26,5,.35
  -- Major boulders in build_stock_rocky_water_art.py, mirrored into
  -- world coordinates by the OBJ importer. Small adjacent chips share wakes.
  local blocks={{.68,-.19,.22},{-.69,.15,.21},{.16,.18,.16},{-.24,-.40,.125}}
  local function emitter(player,terrain,tile,block,splash)
    local d=slopes[tile.mask]
    local fx,fz=d[1],d[2]
    local side,down,side_radius=block[1],block[2],block[3]
    -- Start spray off the upstream shoulder, not inside the rock.
    -- Wake starts beyond its downstream edge, in the separated current.
    down=down+(splash and -.14 or .15)
    local outward=side>=0 and 1 or -1
    side=side+outward*side_radius*.55
    local x=tile.x-fz*side+fx*down
    local z=tile.z+fx*side+fz*down
    local y=terrain.sample(tile.id,x,z)
    if not y then return end
    local function envelope(lo,hi,spread,rise_lo,rise_hi)
      return {
        min={x=math.min(fx*lo,fx*hi)-spread*math.abs(fz),
          y=rise_lo-hi*.5,z=math.min(fz*lo,fz*hi)-spread*math.abs(fx)},
        max={x=math.max(fx*lo,fx*hi)+spread*math.abs(fz),
          y=rise_hi-lo*.5,z=math.max(fz*lo,fz*hi)+spread*math.abs(fx)},
      }
    end
    local spec={playername=player,time=0,amount=splash and 12 or 16,
      pos={min={x=x-.048,y=y+.036,z=z-.048},max={x=x+.048,y=y+.062,z=z+.048}},
      collisiondetection=false}
    if splash then
      spec.vel=envelope(.26,.67,.35,.56,.97)
      spec.acc={x=0,y=-2.9,z=0}
      spec.size={min=.55,max=1.12}
      spec.exptime={min=.24,max=.43}
      spec.texture={name="bl_river_spray.png",alpha_tween={.86,0},scale_tween={{x=.74,y=.92},{x=.73,y=1.13}}}
    else
      -- Each emitter uses one downstream speed; keeping vy coupled to it
      -- makes the foam skim the surface instead of levitating or sinking.
      local speed=.92
      spec.vel=envelope(speed,speed,.26,.035,.044)
      spec.acc={x=0,y=-.13,z=0}
      spec.size={min=1.3,max=2.1}
      spec.exptime={min=.43,max=.73}
      spec.texture={name="bl_river_wake.png",alpha_tween={.74,0},scale_tween={{x=.74,y=.60},{x=1.18,y=.48}}}
    end
    return core.add_particlespawner(spec)
  end
  local function release(name,v)
    for _,handle in ipairs(v.handles) do core.delete_particlespawner(handle,name) end
  end
  function P.leave(name)
    for _,v in pairs(active[name] or {}) do release(name,v) end
    active[name]=nil
  end
  function P.step(dt,s,terrain,viewers)
    elapsed=elapsed+dt
    if elapsed<period then return end
    elapsed=elapsed%period
    local present={}
    for _,p in ipairs(viewers) do
      local name=p.name
      local previous=active[name] or {}
      local next_,choices={},{}
      present[name]=true
      for z=math.max(1,math.ceil((p.z-.5-leave)/2)),math.min(Sim.H,math.floor((p.z-.5+leave)/2)) do
        for x=math.max(1,math.ceil((p.x-.5-leave)/2)),math.min(Sim.W,math.floor((p.x-.5+leave)/2)) do
          local id=Sim.id(x,z)
          local t=s.tiles[id]
          if t and t.water_class=="river" and not t.ship and not t.build then
            local mask,base=terrain.tile(id)
            if slopes[mask] then
              local px,pz=2*x+.5,2*z+.5
              local d=(p.x-px)^2+(p.z-pz)^2+(p.y-base-1)^2
              local old=previous[id]
              local keep=old and old.mask==mask and old.base==base
              if d<=(keep and leave or enter)^2 then
                local node=core.get_node_or_nil({x=2*x,y=base+1,z=2*z})
                if node and node.name:find("^luanttd_core:stock_river_"..mask.."[_a-z]*$") then
                  choices[#choices+1]={id=id,x=px,z=pz,mask=mask,base=base,dist=d,keep=keep}
                end
              end
            end
          end
        end
      end
      table.sort(choices,function(a,b)
        if a.dist==b.dist then return a.id<b.id end
        return a.dist<b.dist
      end)
      for i=1,math.min(#choices,cap) do
        local t=choices[i]
        if t.keep then next_[t.id]=previous[t.id];previous[t.id]=nil
        else
          t.handles={}
          for _,block in ipairs(blocks) do
            for phase=1,2 do
              local handle=emitter(name,terrain,t,block,phase==1)
              if handle and handle>=0 then t.handles[#t.handles+1]=handle end
            end
          end
          next_[t.id]=t
        end
      end
      for _,v in pairs(previous) do release(name,v) end
      active[name]=next_
    end
    for name in pairs(active) do if not present[name] then P.leave(name) end end
  end
  return P
end
