-- Decorative only. Read the painted local view; never draw from the
-- simulation RNG or trigger industry production by observing a chimney.
local root=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local layouts=dofile(root.."/industry_layout_art.lua")
return function(core,Sim,ground)
  local V={}
  local enter,leave,cap=36,44,16
  local refs,elapsed={},.46
  local texture="bl_industry_smoke.png"
  -- Offsets in node units from the overlay node. Verified against the
  -- actual rim/nozzle geometry (Luanti's OBJ loader reflects X).
  -- OpenTTD 16.0-RC1 industry_cmd.cpp CreateChimneySmoke: stock power
  -- plant exhaust originates at the completed chimney, not the factory
  -- center or coal intake. Other native flues get smaller optical plumes.
  local profile={
    power={amount=3,size=2.55,life=3.00,vel=.66,alpha=.72,tint="#D2CBBB"},
    large={amount=3,size=1.90,life=2.85,vel=.63,alpha=.68,tint="#B2ACA4"},
    stove={amount=2,size=1.42,life=2.55,vel=.55,alpha=.65,tint="#BDB7B0"},
    factory={amount=2,size=1.60,life=2.55,vel=.55,alpha=.64,tint="#D5CEC3"},
    vent={amount=2,size=1.08,life=1.85,vel=.59,alpha=.55,tint="#DCE0DB"},
  }
  local function chimney(x,y,z,kind) return {x=x,y=y+.034,z=z,p=profile[kind]} end
  local function factory(low,high)
    return {chimney(.04,low,.137,"factory"),chimney(.76,high,.245,"factory")}
  end
  local outlets={
    industry_layout_gfx_8={chimney(.06,2.14,.10,"power")},
    power_station_1_1={chimney(.48,2.88,.10,"power")},
    power_station_2_1={chimney(.34,3.02,.10,"power")},
    industry_factory_1_0=factory(1.355,1.609),
    industry_factory_1_2=factory(1.477,1.731),
    industry_factory_3_1=factory(1.599,1.853),
    industry_steel_mill_2_1={chimney(1.40,2.159,-.18,"stove")},
    industry_steel_mill_3_1={chimney(1.08,2.602,.28,"large")},
    industry_steel_mill_l1_0_0={chimney(1.40,2.159,-.18,"stove")},
    industry_steel_mill_l1_1_0={chimney(1.08,2.602,.28,"large")},
    industry_steel_mill_l1_2_0={chimney(1.40,2.159,-.18,"stove")},
    industry_steel_mill_l1_3_0={chimney(1.08,2.602,.28,"large")},
    industry_oil_refinery_0_0={chimney(-.233,1.506,.998,"vent")},
    industry_oil_refinery_1_0={chimney(-.233,1.563,.998,"vent")},
    industry_oil_refinery_1_3={chimney(-.233,1.734,.222,"vent")},
  }
  local function start(name,o,px,py,pz)
    local p=o.p
    local scatter=p.size*.008
    return core.add_particlespawner({
      playername=name,time=0,amount=p.amount,
      pos={min={x=px-scatter,y=py,z=pz-scatter},max={x=px+scatter,y=py+.018,z=pz+scatter}},
      vel={min={x=.025,y=p.vel*.82,z=-.045},max={x=.102,y=p.vel*1.13,z=.052}},
      acc={min={x=.18,y=-.04,z=.038},max={x=.27,y=.06,z=.081}},
      exptime={min=p.life*.78,max=p.life*1.13},
      size={min=p.size*.83,max=p.size*1.15},collisiondetection=false,
      texture={name=texture.."^[multiply:"..p.tint,alpha_tween={p.alpha,0},
        scale_tween={{x=.82,y=.90},{x=3.0,y=2.65}}},
    })
  end
  function V.leave(name)
    local active=refs[name]
    if not active then return end
    for _,old in pairs(active) do core.delete_particlespawner(old.handle,name) end
    refs[name]=nil
  end
  function V.step(dt,s,viewers)
    elapsed=elapsed+dt
    if elapsed<.46 then return end
    elapsed=0
    local present={}
    local painted={}
    for _,p in ipairs(viewers) do
      local name=p.name
      local active=refs[name] or {}
      refs[name],present[name]=active,true
      local nearby,keep={},{}
      for z=math.max(1,math.ceil((p.z-leave-1.5)/2)),math.min(Sim.H,math.floor((p.z+leave+1.5)/2)) do
        for x=math.max(1,math.ceil((p.x-leave-1.5)/2)),math.min(Sim.W,math.floor((p.x+leave+1.5)/2)) do
          local id=Sim.id(x,z)
          local t=s.tiles[id]
          local b=t and t.stock_industry
          if b then
            local key=layouts.alternate(b) or ("%s_%d_%d"):format(b.style,b.x,b.z)
            local flues=outlets[key]
            if flues then
              -- Tiles may enter the view before the renderer has placed
              -- their model. Don't let a plume hang over bare ground.
              local node_y=painted[id]
              if node_y==nil then
                local registry=s["stock_"..(b.chain or "coal").."_industries"]
                local stock=registry and registry[b.id]
                if stock and not stock.removed then
                  local _,base=ground.tile(id)
                  local n=base and core.get_node_or_nil({x=2*x,y=base+1,z=2*z})
                  if n and n.name=="luanttd_core:"..key then node_y=base+1 end
                end
                painted[id]=node_y or false
              end
              if node_y then
                for i,o in ipairs(flues) do
                  local k=id*2+i
                  local px,py,pz=2*x+o.x,node_y+o.y,2*z+o.z
                  local old=active[k]
                  local retain=old~=nil and old.y==py and old.key==key
                  local dist=(px-p.x)^2+(py-p.y)^2+(pz-p.z)^2
                  if dist<=(retain and leave or enter)^2 then
                    nearby[#nearby+1]={k=k,key=key,dist=dist,retain=retain,x=px,y=py,z=pz,outlet=o}
                  end
                end
              end
            end
          end
        end
      end
      table.sort(nearby,function(a,b)
        if a.retain~=b.retain then return a.retain end
        if a.dist==b.dist then return a.k<b.k end
        return a.dist<b.dist
      end)
      for i=1,math.min(cap,#nearby) do local n=nearby[i];keep[n.k]=n end
      for k,old in pairs(active) do
        if not keep[k] or not keep[k].retain then
          core.delete_particlespawner(old.handle,name);active[k]=nil
        end
      end
      for k,n in pairs(keep) do
        if not active[k] then
          local handle=start(name,n.outlet,n.x,n.y,n.z)
          if handle and handle>=0 then active[k]={key=n.key,handle=handle,y=n.y} end
        end
      end
    end
    for name in pairs(refs) do if not present[name] then V.leave(name) end end
  end
  return V
end
