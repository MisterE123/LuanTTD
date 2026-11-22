-- Scenario authoring for exact OpenTTD 14.1 temperate layout-0 Forest
-- and Sawmill footprints. Completed map-generation facilities only,
-- not a player-funded industry, terrain clearing or engine spawn.
return function(Sim,Terrain,Timber)
  local W={VERSION=1,INDUSTRY_ID_BASE=0x1000,INDUSTRY_ID_LIMIT=0x2000,MIN_SEPARATION=15}
  local styles={
    forest={kind="stock_forest",name="Alder Timber Forest",art="forest_0"},
    sawmill={kind="stock_sawmill",name="Tidewater Sawmill",art="sawmill_0"},
  }
  -- Add these two nonproductive facility descriptors in Sim only when
  -- mounting. Their output/input belongs to real source cargo packets.
  W.facilities={stock_forest={name="Forest",produces={},takes={}},stock_sawmill={name="Sawmill",produces={},takes={}}}
  local function valid_id(id)
    return type(id)=="number" and id>=1 and id%1==0 and id<=Sim.W*Sim.H
  end
  local function occupied(s,id,t)
    return t.terrain=="water" or t.owner or t.site or t.house or t.source_house or t.build or
      t.wood or t.rail_tracks or t.rail_station_id or t.rail_depot_dir or t.tram or t.ship or
      t.airfield or t.stock_industry or t.stock_landmark or t.level_crossing or t.road_bridge_id or t.road_tunnel_id or
      t.rail_span_id or t.stock_canal or s.bridge_above and s.bridge_above[id] or
      s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
      s.rail_tunnel_below and s.rail_tunnel_below[id] or s.aqueduct_above and s.aqueduct_above[id]
  end
  local function max_distance(x,z,u,v) return math.max(math.abs(x-u),math.abs(z-v)) end
  local function conflicts(s,kind,x,z)
    for _,i in pairs(s.stock_timber_industries or {}) do
      if not i.removed and i.kind~=kind and max_distance(x,z,i.x+1,i.z+1)<W.MIN_SEPARATION then return true end
    end
    return false
  end

  function W.quote(s,kind,origin)
    if not (styles[kind] and s.corner_grid and valid_id(origin) and s.tiles[origin]) then
      return nil,"INVALID_INDUSTRY_ORIGIN",origin
    end
    local x,z=Sim.xy(origin)
    local cells,level={},nil
    -- The layout list includes only authored cells, not its holes.
    for n,q in ipairs(Timber.layout[kind][0]) do
      local tx,tz=x+q[1],z+q[2]
      local id=Sim.id(tx,tz)
      local t=id and s.tiles[id]
      if not t then return nil,"INDUSTRY_OUTSIDE_REGION" end
      if occupied(s,id,t) then return nil,"INDUSTRY_SITE_OCCUPIED",id end
      local slope,h=Terrain.tile(s.corner_grid,tx,tz)
      if slope~=0 or level and level~=h then return nil,"INDUSTRY_NEEDS_LEVEL_LAND",id end
      level=h
      cells[n]={id=id,x=q[1],z=q[2],gfx=q[3]}
    end
    if conflicts(s,kind,x,z) then return nil,"INDUSTRIES_TOO_CLOSE",origin end
    return {version=W.VERSION,kind=kind,layout=0,origin=origin,x=x,z=z,level=level,cells=cells,
      topology=s.topology,seed=s.seed}
  end

  function W.quote_pair(s,forest,sawmill)
    local a,error_,bad=W.quote(s,"forest",forest)
    if not a then return nil,error_,bad end
    local b,why,at=W.quote(s,"sawmill",sawmill)
    if not b then return nil,why,at end
    local footprint={}
    for _,q in ipairs(a.cells) do footprint[q.id]=true end
    for _,q in ipairs(b.cells) do if footprint[q.id] then return nil,"INDUSTRIES_OVERLAP",q.id end end
    if max_distance(a.x,a.z,b.x,b.z)<W.MIN_SEPARATION then return nil,"INDUSTRIES_TOO_CLOSE",b.origin end
    return {version=W.VERSION,kind="pair",forest=a,sawmill=b,topology=s.topology,seed=s.seed}
  end

  local function same(s,p)
    return type(p)=="table" and p.version==W.VERSION and p.topology==s.topology and p.seed==s.seed
  end
  local function matches(a,b)
    if not b or a.origin~=b.origin or a.kind~=b.kind or a.layout~=b.layout or a.level~=b.level or
        type(b.cells)~="table" or #a.cells~=#b.cells then return false end
    for i,p in ipairs(a.cells) do
      local q=b.cells[i]
      if type(q)~="table" or p.id~=q.id or p.x~=q.x or p.z~=q.z or p.gfx~=q.gfx then return false end
    end
    return true
  end
  local function writes(s,plans,generation)
    local start=s.next_stock_timber_industry or W.INDUSTRY_ID_BASE
    if type(start)~="number" or start%1~=0 or start<W.INDUSTRY_ID_BASE or
        start+#plans>W.INDUSTRY_ID_LIMIT then return nil,"TIMBER_INDUSTRY_IDS_EXHAUSTED" end
    local dirty,records,site_start={},{},#s.sites+1
    -- No mutation until IDs and both source records are ready.
    for k,p in ipairs(plans) do
      local id=start+k-1
      if s.stock_coal_industries and s.stock_coal_industries[id] or
          s.stock_timber_industries and s.stock_timber_industries[id] then return nil,"INDUSTRY_ID_COLLISION" end
      local style=styles[p.kind]
      local ind=generation and generation.record or Timber.new(p.kind,id,p.x-1,p.z-1,{completed=true,original=true,generating_world=true,
        counter=1,economy_year=Sim.date(s)})
      if generation then
        assert(#plans==1 and ind.kind==p.kind and ind.x==p.x-1 and ind.z==p.z-1 and #ind.tiles==#p.cells)
        for i,part in ipairs(ind.tiles) do
          local q=p.cells[i]
          assert(part.x==ind.x+q.x and part.z==ind.z+q.z and part.gfx==q.gfx,
            "Generated timber footprint does not match authored art")
        end
        ind.id=id
      end
      local sid=site_start+k-1
      ind.site=sid
      local site={id=sid,tile=p.origin,name=generation and generation.name or style.name,kind=style.kind,produced={},received={},stock={},
        service=0,stock_industry=id,industry_chain="timber"}
      records[k]={ind=ind,site=site,p=p,style=style}
      for _,cell in ipairs(p.cells) do dirty[#dirty+1]=cell.id end
    end
    s.stock_timber_industries=s.stock_timber_industries or {}
    for _,r in ipairs(records) do
      s.stock_timber_industries[r.ind.id]=r.ind
      s.sites[r.site.id]=r.site
      for _,cell in ipairs(r.p.cells) do
        local t=s.tiles[cell.id]
        t.stock_industry={id=r.ind.id,chain="timber",kind=r.ind.kind,layout=0,
          style=r.style.art,x=cell.x,z=cell.z,gfx=cell.gfx,site=r.site.id,origin=r.p.origin}
        if cell.id==r.p.origin then t.site=r.site.id end
      end
    end
    s.topology=s.topology+1
    s.next_stock_timber_industry=start+#plans
    return records,dirty
  end
  function W.commit(s,p)
    if not same(s,p) then return nil,"STALE_INDUSTRY_QUOTE" end
    local q,why,id=W.quote(s,p.kind,p.origin)
    if not q then return nil,why,id end
    if not matches(q,p) then return nil,"STALE_INDUSTRY_QUOTE" end
    local r,dirty=writes(s,{q})
    if not r then return nil,dirty end
    return r[1].ind,dirty,r[1].site
  end
  function W.place_generated(s,kind,origin,opts)
    local q,why,id=W.quote(s,kind,origin)
    if not q then return nil,why,id end
    assert(opts and opts.record and type(opts.name)=="string")
    local records,dirty=writes(s,{q},opts)
    if not records then return nil,dirty end
    return records[1].ind,q.cells,records[1].site
  end
  function W.commit_pair(s,p)
    if not (same(s,p) and p.kind=="pair" and type(p.forest)=="table" and type(p.sawmill)=="table") then
      return nil,"STALE_INDUSTRY_QUOTE"
    end
    local q,why,id=W.quote_pair(s,p.forest.origin,p.sawmill.origin)
    if not q then return nil,why,id end
    if not matches(q.forest,p.forest) or not matches(q.sawmill,p.sawmill) then return nil,"STALE_INDUSTRY_QUOTE" end
    local r,dirty=writes(s,{q.forest,q.sawmill})
    if not r then return nil,dirty end
    return {forest=r[1].ind.id,sawmill=r[2].ind.id,forest_site=r[1].site.id,sawmill_site=r[2].site.id,tiles=dirty}
  end
  function W.seed(s,forest,sawmill)
    local p,why,id=W.quote_pair(s,forest,sawmill)
    if not p then return nil,why,id end
    return W.commit_pair(s,p)
  end
  function W.record(s,id)
    local t=valid_id(id) and s.tiles[id]
    local ref=t and t.stock_industry
    if ref and ref.chain=="timber" then
      return ref,s.stock_timber_industries and s.stock_timber_industries[ref.id]
    end
  end
  function W.protected(s,id) return W.record(s,id)~=nil end
  function W.scenario_1751(s)
    if s.seed~=1751 then return nil,"TIMBER_SCENARIO_REQUIRES_SEED_1751" end
    local id=Sim.id
    return {
      forest=id(12,1),sawmill=id(12,16),forest_stop=id(16,2),sawmill_stop=id(15,17),
      sawmill_intake=id(14,17),mill_goods_stop=id(12,15),goods_stop=id(14,8),depot=id(11,12),
      mill_goods_spur={id(12,14),id(12,15)},
      road_waypoints={
        {id(16,2),id(16,7),id(15,7),id(15,8),id(12,8),id(12,14),id(13,14),id(13,15),id(15,15),id(15,17)},
        {id(15,8),id(15,12),id(12,12)},
      },
    }
  end
  function W.default_1751(s)
    local p,why=W.scenario_1751(s)
    if not p then return nil,why end
    return W.seed(s,p.forest,p.sawmill)
  end
  return W
end
