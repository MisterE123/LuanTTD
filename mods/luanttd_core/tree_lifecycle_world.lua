-- Native owner adapter for the RC1 landscape tile-loop tree rules.
return function(Sim,Terrain,Rules)
  local W={}
  local dx,dz={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
  local function clean(t)
    return t and not (t.stock_void or t.wood or t.build or t.house or t.site or t.stock_industry or t.rail_tracks
      or t.stock_landmark or t.station or t.ship or t.tram or t.airfield or t.owner or (t.road_bits or 0)~=0)
  end
  local function tile(s,x,z,id)
    local t=s.tiles[id]
    if not clean(t) then return end
    local field=s.stock_farm_fields and s.stock_farm_fields[id]
    local ground=field and 3 or t.stock_clear_ground or 0
    if t.terrain=="water" then
      return {class=6,zone=t.stock_tropic_zone,coast=t.coastal_water,rocky=t.stock_water_rocks,slope=Terrain.tile(s.corner_grid,x,z),
        bridge_above=s.bridge_above and s.bridge_above[id] or s.rail_bridge_above and s.rail_bridge_above[id]
          or s.aqueduct_above and s.aqueduct_above[id]}
    end
    return {class=0,ground=ground,zone=t.stock_tropic_zone,snow=t.stock_arctic_snow~=nil,
      density=t.stock_arctic_snow or t.stock_clear_density or 3,
      bridge_above=s.bridge_above and s.bridge_above[id] or s.rail_bridge_above and s.rail_bridge_above[id]
        or s.aqueduct_above and s.aqueduct_above[id]}
  end
  local function visit_neighbor(d,s,x,z)
    local u,v=x+1+dx[d],z+1+dz[d]
    local key=Sim.id(u,v)
    return key and tile(s,u,v,key)
  end
  function W.visit(s,x,z,tick,random,surface)
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not t then return end
    if type(t.wood)~="table" then
      -- RC1 ClearTile_Clear: eight actual landscape visits per
      -- density increment, independent of placement date and tile phase.
      if t.stock_clear_density and clean(t) and t.terrain~="water"
          and (t.stock_clear_ground or 0)==0 and not (s.stock_farm_fields and s.stock_farm_fields[id]) then
        if surface then surface(id) end
        local n=(t.stock_clear_visits or 0)+1
        if n==8 then
          local density=t.stock_clear_density+1
          t.stock_clear_density,t.stock_clear_visits=density<3 and density or nil,nil
          s.changed=s.changed or {}
          s.changed[#s.changed+1]=id
        else
          t.stock_clear_visits=n
        end
      end
      return
    end
    -- The RC1 RNG chooses a neighbor only on actual spread attempts.
    -- Pass the shared resolver rather than allocating one closure per tree.
    local climate=s.stock_climate
    local zone=climate and climate.landscape=="tropic" and (t.stock_tropic_zone or 0) or nil
    local height
    if climate and climate.landscape=="arctic" then
      local _,base=Terrain.tile(s.corner_grid,x,z)
      height=base
    end
    local next_tree,event=Rules.visit(t.wood,x-1,z-1,tick,s.stock_extra_tree_placement,random,visit_neighbor,s,
      zone,height,climate and climate.snowline)
    if surface and next_tree~=t.wood then surface(id) end
    t.wood=next_tree
    if event and event.kind=="plant" then
      local d=event.direction
      local destination=Sim.id(x+dx[d],z+dz[d])
      local next_tile=assert(s.tiles[destination])
      if surface then surface(destination) end
      next_tile.stock_clear_density,next_tile.stock_clear_visits,next_tile.stock_arctic_snow=nil,nil,nil
      next_tile.wood=event.tree
    elseif event and event.kind=="clear" and event.ground~=3 then
      local rough=event.ground==1 or event.ground==4
      local desert=event.ground==2 and climate and climate.landscape=="tropic"
      t.stock_clear_ground=rough and 1 or desert and 5 or nil
      t.stock_arctic_snow=height~=nil and (event.ground==2 or event.ground==4) and event.density or nil
      t.stock_clear_density=(event.ground==0 or desert) and event.density<3 and event.density or nil
      t.stock_clear_visits=nil
    end
    return event
  end
  function W.global_tick(s,tick,random,surface)
    local function plant(i,tree)
      local t=s.tiles[i+1]
      t.stock_clear_density,t.stock_clear_visits,t.stock_arctic_snow=nil,nil,nil
      t.wood=tree
      if surface then surface(i+1) end
    end
    local next_counter,i,tree=Rules.global_tick(s.stock_tree_tick_counter or 0,Sim.W*Sim.H,tick,
      s.stock_extra_tree_placement,random,function(i)
        local x,z=Sim.xy(i+1)
        return tile(s,x,z,i+1)
      end,s.stock_climate and s.stock_climate.landscape,plant)
    s.stock_tree_tick_counter=next_counter
    return i and i+1,tree
  end
  return W
end
