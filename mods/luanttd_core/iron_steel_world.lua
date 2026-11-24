-- Native mounting of exact OpenTTD RC1 industry footprints. Producers
-- and the calendar are supplied by ordinary generated-campaign authority.
-- Both original Steel Mill layouts use the same tracked industry type.
return function(Sim,Terrain,Rules)
  local W={BASE=0x4000,LIMIT=0x5000}
  local style={iron_mine="industry_iron_mine",steel_mill="industry_steel_mill"}
  local steel_alt="industry_steel_mill_l1"
  local names={iron_mine="Iron Ore Mine",steel_mill="Steel Mill"}
  W.facilities={stock_iron_mine={name=names.iron_mine,produces={},takes={}},
    stock_steel_mill={name=names.steel_mill,produces={},takes={}}}
  local registries={"stock_coal_industries","stock_timber_industries","stock_farm_industries","stock_oil_industries"}
  local overlays={"bridge_above","tunnel_below","rail_bridge_above","rail_tunnel_below","aqueduct_above"}
  local function occupied(s,id,t)
    if t.stock_void or t.terrain=="water" or t.owner or t.site or t.house or t.source_house or t.build or
        t.wood or t.stock_industry or t.rail_tracks or t.tram or t.airfield or t.ship or t.level_crossing or
        t.stock_canal then return true end
    for _,key in ipairs(overlays) do if s[key] and s[key][id] then return true end end
    return false
  end
  function W.plan(s,kind,tile,layout)
    if not style[kind] or not s.corner_grid or type(tile)~="number" or tile%1~=0 or not s.tiles[tile] then
      return nil,"INVALID_HEAVY_INDUSTRY_SITE"
    end
    local x,z=Sim.xy(tile)
    local footprint=Rules.layout[kind][layout]
    if not footprint then return nil,"HEAVY_INDUSTRY_LAYOUT_NOT_MOUNTED" end
    local cells,level={},nil
    for _,row in ipairs(footprint) do
      local a,b=x+row[1],z+row[2]
      local id=Sim.id(a,b)
      local t=id and s.tiles[id]
      if not t then return nil,"HEAVY_INDUSTRY_OFF_MAP" end
      if occupied(s,id,t) then return nil,"HEAVY_INDUSTRY_OCCUPIED",id end
      local slope,h=Terrain.tile(s.corner_grid,a,b)
      if slope~=0 or level and level~=h then return nil,"HEAVY_INDUSTRY_NEEDS_FLAT_FOUNDATION",id end
      level=h
      cells[#cells+1]={id=id,x=a,z=b,gfx=row[3],offset_x=row[1],offset_z=row[2]}
    end
    return {kind=kind,x=x,z=z,level=level,cells=cells,layout=layout}
  end
  function W.place_generated(s,kind,tile,opts)
    local source=opts and opts.record
    if not source or type(opts.name)~="string" then return nil,"STOCK_SOURCE_RECORD_REQUIRED" end
    local plan,why,at=W.plan(s,kind,tile,source.layout)
    if not plan then return nil,why,at end
    if source.kind~=kind or source.x~=plan.x-1 or source.z~=plan.z-1 or #source.tiles~=#plan.cells then
      return nil,"HEAVY_INDUSTRY_FOOTPRINT_MISMATCH"
    end
    for i,c in ipairs(plan.cells) do
      local row=source.tiles[i]
      if row.x~=c.x-1 or row.z~=c.z-1 or row.gfx~=c.gfx then return nil,"HEAVY_INDUSTRY_FOOTPRINT_MISMATCH" end
    end
    local id=s.next_stock_heavy_industry or W.BASE
    if id<W.BASE or id>=W.LIMIT or id%1~=0 then return nil,"HEAVY_INDUSTRY_IDS_EXHAUSTED" end
    for _,name in ipairs(registries) do
      if s[name] and s[name][id] then return nil,"STOCK_INDUSTRY_ID_COLLISION" end
    end
    local industries,records=s.stock_heavy_industries or {},s.stock_heavy_placements or {}
    if industries[id] then return nil,"HEAVY_INDUSTRY_ID_COLLISION" end
    local site_id=#s.sites+1
    local site={id=site_id,name=opts.name,kind="stock_"..kind,tile=tile,stock={},produced={},received={},
      service=0,stock_industry=id,industry_chain="heavy",town=source.town}
    plan.id,plan.site,plan.style,plan.source_type=id,site_id,
      kind=="steel_mill" and plan.layout==1 and steel_alt or style[kind],Rules.spec[kind].id
    source.id,source.site=id,site_id
    for _,c in ipairs(plan.cells) do
      local ground=s.tiles[c.id]
      ground.stock_industry={id=id,chain="heavy",kind=kind,style=plan.style,x=c.offset_x,z=c.offset_z,
        gfx=c.gfx,site=site_id,origin=tile}
    end
    s.tiles[tile].site=site_id
    s.sites[site_id],records[id],industries[id]=site,plan,source
    s.stock_heavy_industries,s.stock_heavy_placements,s.next_stock_heavy_industry=industries,records,id+1
    s.topology=s.topology+1
    return source,plan.cells,site
  end
  function W.sweep_closed(s)
    local dirty={}
    for id,i in pairs(s.stock_heavy_industries or {}) do
      local p=s.stock_heavy_placements[id]
      if i.removed and p and not p.cleared then
        local tile=Sim.id(p.x,p.z)
        if s.tiles[tile].site==p.site then s.tiles[tile].site=nil end
        local site=s.sites[p.site]
        if site then site.closed=true end
        for _,c in ipairs(p.cells) do
          local t=s.tiles[c.id]
          if t.stock_industry and t.stock_industry.id==id then
            t.stock_industry=nil
            dirty[#dirty+1]=c.id
          end
        end
        p.cleared=true
        s.topology=s.topology+1
      end
    end
    return dirty
  end
  function W.visual_sources()
    return {[style.iron_mine]=Rules.layout.iron_mine[0],[style.steel_mill]=Rules.layout.steel_mill[0],
      [steel_alt]=Rules.layout.steel_mill[1]}
  end
  return W
end
