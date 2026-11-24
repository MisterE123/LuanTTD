-- Native bridge to the 16.0-RC1 TileLoop_Road reconstruction states.
-- The caller is the single simulation owner; no drawing or player object
-- access, and no world scan on a landscape visit.
return function(Sim,Terrain,G,Core,Slope,Rail,Surface)
  local W={}
  local function work_state(s)
    local towns=s.stock_town_growth
    return towns and towns.reconstruction
  end
  local function normal(t)
    return t and (t.build=="road" or not t.build and t.tram and t.tram.kind=="road") and
      not (t.level_crossing or t.road_waypoint_id or t.road_tunnel_id or t.road_bridge_id or
        t.stock_void)
  end
  local function roadside(t)
    return t.roadside or (t.road_town and "paved" or "grass")
  end
  function W.view(s,id,owner)
    local account,town=s.companies[owner],s.stock_town_growth and s.stock_town_growth.towns[id]
    local policy=s.stock_road_town_policy or {}
    if not account or not town or policy.fund_roads==false then return end
    return {cost=Core.cost,months=town.road_build_months,affordable=account.cash>=Core.cost}
  end
  function W.fund(s,id)
    local source=s.stock_town_growth
    local town=source and source.towns[id]
    if not town then return end
    local record=source.reconstruction or {funded=0,active=0,started=0,completed=0}
    source.reconstruction=record
    if town.road_build_months==0 then record.funded=record.funded+1 end
    Core.fund(town)
    return town
  end
  function W.expired(s)
    local state=work_state(s)
    if state then state.funded=math.max(0,state.funded-1) end
  end
  local function nearby(s,t,id)
    local state=s.stock_town_growth
    local town=t.road_town and state.towns[t.road_town]
    if not town then
      local site=Sim.road_tree_authority().nearest(s,id)
      town=site and state.towns[site.id]
    end
    return town
  end
  local function neighbor(s,id,d)
    local at=Sim.adjacent(id,d)
    local t=at and s.tiles[at]
    if not t or t.stock_void then return end
    if normal(t) then return {kind="road"} end
    if t.build=="stock_rail" and t.rail_tracks then
      local x,z=Sim.xy(at)
      local mask=Terrain.tile(s.corner_grid,x,z)
      local grade=mask
      if Rail and Surface and (t.rail_tracks==1 or t.rail_tracks==2) then
        local foundation=Rail.foundation(mask,t.rail_tracks)
        if foundation~="invalid" then grade=Surface.foundation(mask,foundation) end
      end
      return {kind="rail",normal=not (t.rail_station_id or t.rail_depot_dir or t.rail_span_id),
        track_bits=t.rail_tracks,grade=grade}
    end
    if t.level_crossing or t.build=="road_station" or t.build=="road_depot" or t.road_waypoint_id or
        t.road_bridge_id or t.road_tunnel_id or t.tram then
      return {kind="road_facility",road_bits=Sim.road_bits(s,at),
        tram_bits=t.tram and t.tram.tram_bits or t.level_crossing and t.level_crossing.tram_bits}
    end
    if t.terrain=="water" or t.stock_canal then return {kind="water",real_water=not t.coastal_water} end
    if t.build or t.house or t.stock_landmark or t.stock_industry or t.site or t.airfield or t.ship then return end
    return {kind=t.wood and "trees" or "clear"}
  end
  local function clear_unconnected(s,id,t,clear)
    local policy=s.stock_road_town_policy or {}
    if policy.mod_road_rebuild==false or not clear() then return end
    local before=Sim.road_bits(s,id)
    local after=Core.cleanup(before,function(d) return neighbor(s,id,d) end)
    if after==before then return end
    local x,z=Sim.xy(id)
    local mask=Terrain.tile(s.corner_grid,x,z)
    local other=t.tram and t.tram.tram_bits or 0
    local edit=Slope.remove(mask,before-after,before,other,policy.build_on_slopes~=false)
    if not edit then return end
    t.road_disallowed,t.disallowed=nil,nil
    -- Guard any already-compiled route whose original movement row
    -- depended on a removed piece, not just vehicles arriving mid-work.
    s.road_oneway_removed=s.road_oneway_removed or {}
    s.road_oneway_removed[id]=true
    s.road_oneway_revision=(s.road_oneway_revision or 0)+1
    if edit.road_bits==0 then t.build,t.owner,t.road_town,t.road_bits=nil,nil,nil,nil
    else t.road_bits=edit.road_bits end
  end
  function W.visit(s,x,z,random,ground)
    local record=work_state(s)
    if not record or record.funded==0 and record.active==0 then return end
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not normal(t) then return end
    local town,grade,dist,zone
    if not t.roadworks then
      if record.funded==0 then return end
      town=nearby(s,t,id)
      if not town or town.road_build_months==0 then return end
      grade=Sim.road_surface(s,id)
      if grade==nil and t.tram then
        local shape=Terrain.tile(s.corner_grid,x,z)
        grade=shape==0 and 0 or 1
      end
      if grade~=0 then return end
      dist=math.abs(town.x-x)+math.abs(town.z-z)
      zone=G.zone(town,x,z)
    end
    local function clear() return ground(id) end
    local q=Core.visit({kind="road",grade=grade,roadside=roadside(t),works=t.roadworks,
      counter=t.roadworks_counter,road_bits=Sim.road_bits(s,id),tram_bits=t.tram and t.tram.tram_bits},
      town,dist,zone,clear,random)
    if not q then return end
    t.roadworks,t.roadworks_counter,t.roadside=q.works,q.works and q.counter or nil,q.roadside
    if q.effect=="progress" then return q.effect end
    if q.effect=="start" then record.active,record.started=record.active+1,record.started+1
    else
      record.active,record.completed=record.active-1,record.completed+1
      clear_unconnected(s,id,t,clear)
    end
    s.changed=s.changed or {}
    s.changed[#s.changed+1]=id
    s.topology=s.topology+1
    s.roadworks_revision=(s.roadworks_revision or 0)+1
    return q.effect
  end
  return W
end
