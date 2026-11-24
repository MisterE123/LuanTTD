-- Presentation only: read the same local terrain projection as the water
-- meshes. No particles are saved or inserted into the simulation.
return function(core,Sim)
  local P={}
  local elapsed=0
  local steep_flow={[3]={-1,0},[6]={0,-1},[9]={0,1},[12]={1,0}}
  local range,cap,period=24,6,.42
  local function spray(viewer,terrain,v)
    local flow=steep_flow[v.mask]
    local fx,fz=flow[1],flow[2]
    -- Downstream shoulders of the riverbed blocks (the art is mirrored
    -- in X by the OBJ loader, hence using world, not mesh, coordinates).
    for _,at in ipairs({{-.63,.13},{.58,.39},{-.13,.41},{.22,-.19}}) do
      local x=v.x-fz*at[1]+fx*at[2]
      local z=v.z+fx*at[1]+fz*at[2]
      local y=terrain.sample(v.id,x,z)
      if y then
        local p={x=x,y=y+.034,z=z}
        local function speed(a)
          return {x=fx*a,y=.17-a*.5,z=fz*a}
        end
        local a,b=speed(.57),speed(1.11)
        local function limits(fn)
          return {x=fn(a.x,b.x)-(fn==math.min and .035 or -.035),
            y=fn(a.y,b.y),z=fn(a.z,b.z)-(fn==math.min and .035 or -.035)}
        end
        core.add_particlespawner({
          playername=viewer,time=period,amount=5,
          pos={min={x=x-.045,y=p.y-.01,z=z-.045},max={x=x+.045,y=p.y+.03,z=z+.045}},
          vel={min=limits(math.min),max=limits(math.max)},
          acc={x=0,y=-.60,z=0},size={min=.62,max=1.29},exptime={min=.21,max=.43},
          texture={name="bl_river_foam.png",alpha_tween={.86,0},scale_tween={1,.67}},
        })
      end
    end
  end
  function P.step(dt,s,terrain,viewers)
    elapsed=elapsed+dt
    if elapsed<period then return end
    elapsed=elapsed%period
    for _,p in ipairs(viewers) do
      local choices={}
      for z=math.max(1,math.ceil((p.z-.5-range)/2)),math.min(Sim.H,math.floor((p.z-.5+range)/2)) do
        for x=math.max(1,math.ceil((p.x-.5-range)/2)),math.min(Sim.W,math.floor((p.x-.5+range)/2)) do
          local id=Sim.id(x,z)
          local t=s.tiles[id]
          if t and t.water_class=="river" and not t.ship and not t.build then
            local mask,base=terrain.tile(id)
            if steep_flow[mask] then
              local px,pz=2*x+.5,2*z+.5
              local d=(p.x-px)^2+(p.z-pz)^2+(p.y-base-1)^2
              if d<=range^2 then
                local node=core.get_node_or_nil({x=2*x,y=base+1,z=2*z})
                if node and node.name:find("^luanttd_core:stock_river_"..mask.."[_a-z]*$") then
                  choices[#choices+1]={id=id,x=px,z=pz,mask=mask,dist=d}
                end
              end
            end
          end
        end
      end
      table.sort(choices,function(a,b) return a.dist==b.dist and a.id<b.id or a.dist<b.dist end)
      for i=1,math.min(#choices,cap) do spray(p.name,terrain,choices[i]) end
    end
  end
  return P
end
