-- Worker-side four-parcel headquarters transaction. Quotes are read-only;
-- all ownership and clearance are revalidated before any occupied cell changes.
return function(Sim,Terrain,Rules,Limits)
  local H={}
  local protected={"stock_industry","house","site","build","rail_tracks","ship","tram","airfield","station","level_crossing"}
  local function head(s,owner)
    return s.stock_company_hqs and s.stock_company_hqs[owner]
  end
  local function mark_tiles(d,id)
    if not d[id] then d[id]=true end
  end
  function H.quote(s,owner,origin,stats,occupied)
    local company=s.companies[owner]
    if not (company and s.stock_generated_profile and s.corner_grid and s.tiles[origin]) then
      return nil,"HEADQUARTERS_UNAVAILABLE"
    end
    local x,z=Sim.xy(origin)
    local old=head(s,owner)
    local state=s.stock_town_growth
    local function tile(id)
      local v=s.tiles[id]
      if not v then return end
      local a,b=Sim.xy(id)
      local slope,base=Terrain.tile(s.corner_grid,a,b)
      local in_use
      if type(occupied)=="function" then in_use=occupied(id,false,true)
      elseif occupied then in_use=occupied[id] end
      return {slope=slope,base=base,void=v.stock_void,water=v.terrain=="water" or v.stock_canal~=nil,
        bridge_above=s.bridge_above and s.bridge_above[id] or s.rail_bridge_above and s.rail_bridge_above[id]
          or s.aqueduct_above and s.aqueduct_above[id],
        hq=v.stock_landmark and v.stock_landmark.kind=="headquarters" and v.stock_landmark.hq,owner=v.owner,
        occupied=in_use or false}
    end
    local function clear(id)
      local v=s.tiles[id]
      if v.owner and v.owner~=owner then return nil,"OWNED_BY_ANOTHER" end
      if v.stock_landmark or v.rail_span_id or v.road_bridge_id or v.road_tunnel_id or
          s.tunnel_below and s.tunnel_below[id] or s.rail_tunnel_below and s.rail_tunnel_below[id] then
        return nil,"PROTECTED_TILE"
      end
      for _,key in ipairs(protected) do if v[key] then return nil,"PROTECTED_TILE" end end
      return Sim.road_site_clear_cost(v,s.stock_farm_fields and s.stock_farm_fields[id])
    end
    local cash=company.cash
    local value=old and Rules.value(company,stats.vehicles,stats.stations)
    local plan,why=Rules.site({id=Sim.id,tile=tile,clear=clear},x,z,company,{
      towns=state and next(state.towns),owner=owner,old_hq=old and old.origin,company_value=value,
      object_limit=company.stock_object_limit,
      build_on_slopes=not (s.stock_road_town_policy and s.stock_road_town_policy.build_on_slopes==false)})
    if not plan then return nil,why end
    local score=Rules.score(company,stats.vehicles,stats.stations,company.stock_quarters or {},stats.min_age)
    plan.stage=Rules.stage(score)
    plan.affordable=plan.cost<=cash
    plan.topology=s.topology
    return plan
  end
  local function erase(s,owner,existing,dirty)
    for _,at in ipairs(existing.tiles) do
      local t=s.tiles[at]
      t.owner,t.stock_landmark=nil,nil
      t.stock_clear_density=0
      mark_tiles(dirty,at)
    end
    s.stock_company_hqs[owner]=nil
    if Sim.invalidate_hq_cargo then Sim.invalidate_hq_cargo(s,owner) end
  end
  function H.flood_clear(s,owner,origin)
    local current=head(s,owner)
    if not current or current.origin~=origin then return {} end
    local dirty={}
    erase(s,owner,current,dirty)
    local ids={}
    for id in pairs(dirty) do ids[#ids+1]=id end
    table.sort(ids)
    return ids
  end
  function H.apply(s,owner,origin,seen,stats,occupied)
    local q,e=H.quote(s,owner,origin,stats,occupied)
    if not q then return nil,e end
    if q.cost~=seen.cost or q.topology~=seen.topology or q.level~=seen.level then return nil,"HEADQUARTERS_QUOTE_CHANGED" end
    if not q.affordable then return nil,"NOT_ENOUGH_CASH" end
    local old=head(s,owner)
    local dirty={}
    if old then erase(s,owner,old,dirty) end
    local tiles={}
    for i,tile in ipairs(q.tiles) do
      local at=tile.id
      local t=s.tiles[at]
      if t.wood then
        local authority=Sim.road_tree_authority()
        authority.clear_road_trees(s.companies[owner],authority.tree_town(s,at))
      end
      if s.stock_farm_fields then s.stock_farm_fields[at]=nil end
      t.wood,t.stock_clear_ground,t.stock_clear_density,t.stock_object=nil,nil,nil,nil
      t.owner=owner
      t.stock_landmark={kind="headquarters",hq=q.head,owner=owner,part=i,level=q.level,stage=q.stage}
      tiles[i]=at
      mark_tiles(dirty,at)
    end
    s.stock_company_hqs=s.stock_company_hqs or {}
    s.stock_company_hqs[owner]={origin=q.head,level=q.level,stage=q.stage,tiles=tiles}
    local c=s.companies[owner]
    c.stock_object_limit=Limits.replenish(c.stock_object_limit,0)-Limits.unit
    s.topology=s.topology+1
    local changed={}
    for id in pairs(dirty) do changed[#changed+1]=id end
    table.sort(changed)
    return changed,q
  end
  function H.upgrade(s,owner,score)
    local q=head(s,owner)
    if not q then return end
    local stage=Rules.stage(score,q.stage)
    if stage==q.stage then return end
    q.stage=stage
    s.changed=s.changed or {}
    for _,at in ipairs(q.tiles) do
      s.tiles[at].stock_landmark.stage=stage
      s.changed[#s.changed+1]=at
    end
    s.topology=s.topology+1
  end
  return H
end
