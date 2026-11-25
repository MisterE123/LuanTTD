-- A visual-only ambient effect. Workers still own the stock town tile;
-- the renderer may inspect only its current view of the town.
return function(core,Sim,frontage,house_deck)
  local F={}
  local enter,leave,cap=26,32,6
  local active,elapsed={},0
  local texture="bl_fountain_droplet.png"
  local function spray(x,y,z,player)
    return core.add_particlespawner({
      playername=player,time=0,amount=48,glow=1,
      pos={min={x=x-.034,y=y-.01,z=z-.034},max={x=x+.034,y=y+.02,z=z+.034}},
      vel={min={x=-.54,y=1.50,z=-.54},max={x=.54,y=1.88,z=.54}},
      acc={x=0,y=-6.8,z=0},exptime={min=.48,max=.70},size={min=.25,max=.60},
      texture={name=texture,alpha_tween={.92,0},scale_tween={1,.72}},
    })
  end
  function F.leave(name)
    local refs=active[name]
    if not refs then return end
    for _,ref in pairs(refs) do core.delete_particlespawner(ref.handle,name) end
    active[name]=nil
  end
  function F.step(dt,s,viewers)
    elapsed=elapsed+dt
    if elapsed<.35 then return end
    elapsed=0
    local present={}
    for _,p in ipairs(viewers) do
      local name=p.name
      local refs=active[name] or {}
      active[name],present[name]=refs,true
      local choices,keep={},{}
      for z=math.max(1,math.ceil((p.z-.5-leave)/2)),math.min(Sim.H,math.floor((p.z-.5+leave)/2)) do
        for x=math.max(1,math.ceil((p.x-.5-leave)/2)),math.min(Sim.W,math.floor((p.x-.5+leave)/2)) do
          local id=Sim.id(x,z)
          local tile=s.tiles[id]
          local h=tile and tile.house and tile.source_house
          if h and h.id==0x0A and (h.completed or h.stage==2) then
            -- The stone nozzle is centered on the 2x2 parcel, 0.86
            -- nodes above its floor. Facedir moves the mesh anchor, not
            -- the nozzle: it remains over the center of the same parcel.
            local deck=house_deck and house_deck(id,tile) or tile.h
            local px,py,pz=2*x+.5,deck+1.375,2*z+.5
            local d=(p.x-px)^2+(p.y-py)^2+(p.z-pz)^2
            local old=refs[id]
            local retain=old~=nil and old.y==py
            if d<=(retain and leave or enter)^2 then
              local dx,dz=frontage.placement(Sim,s,id,tile,nil,h.render_parcel or tile.parcel)
              local node=core.get_node_or_nil({x=2*x+dx,y=deck+1,z=2*z+dz})
              -- A projected tile can precede painting/emerge. Never
              -- emit over unpainted terrain or a different town model.
              if node and node.name=="luanttd_core:town_stock_0a" then
                choices[#choices+1]={id=id,x=px,y=py,z=pz,dist=d,retain=retain}
              end
            end
          end
        end
      end
      table.sort(choices,function(a,b)
        if a.retain~=b.retain then return a.retain end
        if a.dist==b.dist then return a.id<b.id end
        return a.dist<b.dist
      end)
      for i=1,math.min(#choices,cap) do
        local v=choices[i]
        keep[v.id]=v
      end
      for id,ref in pairs(refs) do
        local v=keep[id]
        if not v or not v.retain then
          core.delete_particlespawner(ref.handle,name)
          refs[id]=nil
        end
      end
      for id,v in pairs(keep) do
        if not refs[id] then
          local handle=spray(v.x,v.y,v.z,name)
          if handle and handle>=0 then refs[id]={handle=handle,y=v.y} end
        end
      end
    end
    for name in pairs(active) do if not present[name] then F.leave(name) end end
  end
  return F
end
