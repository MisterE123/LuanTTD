-- Stock Bank funding adapter. Town ownership clears entire house instances
-- without a company rating penalty; placement and construction are atomic.
return function(Sim,Terrain,F,R,growth,debit,random)
  local W={BASE=0x5000,LIMIT=0x6000,STYLE="industry_temperate_bank"}
  local messages={
    BANK_NEEDS_TOWN_POPULATION_1200="Banks require a town of at least 1,200 people.",
    BANK_SITE_NOT_SUITABLE="That ground, bridge, or vehicle blocks the Bank.",
    BANK_NEEDS_TWO_HOUSE_TILES="Choose the west tile of two adjacent house tiles along the X axis.",
    BANK_TOWN_COULD_NOT_CLEAR_HOUSE="The town cannot clear that complete building.",
    BANK_LAND_SLOPED_WRONG_DIRECTION="These slopes do not support the Bank footprint.",
    BANK_NEEDS_SHARED_MESH_BASE="The two house tiles must be at the same level.",
    BANK_ONE_PER_TOWN="This town already has a Bank.",
    BANK_ANOTHER_BANK_TOO_CLOSE="An existing Bank is within 14 tiles.",
    BANK_NOT_ENOUGH_CASH="Your company cannot afford the Bank.",
    BANK_STALE_QUOTE="The site changed; choose it again.",
  }
  function W.reason(code) return messages[code] or code end
  local function protected(s,id,t)
    if not t or t.stock_void or t.stock_industry or t.stock_landmark or t.site or t.owner or t.build then return true end
    if t.rail_tracks or t.ship or t.airfield or t.tram or t.level_crossing or t.stock_canal then return true end
    for _,key in ipairs({"bridge_above","rail_bridge_above","aqueduct_above"}) do
      if s[key] and s[key][id] then return true end
    end
    for _,v in pairs(s.fleet or {}) do if Sim.vehicles[v.engine].mode=="road" and Sim.position(s,v)==id then return true end end
    return false
  end
  function W.plan(s,tile)
    local t=s.tiles[tile]
    if not t or not s.corner_grid then return nil,"Choose two adjacent house tiles." end
    local x,z=Sim.xy(tile)
    local second=Sim.id(x+1,z)
    local pair={tile,second or false}
    local town=Sim.nearest_town(s,tile)
    local ids,removed,views,levels={},{},{},{}
    for i,id in ipairs(pair) do
      local host=id and s.tiles[id]
      local record=host and host.house and host.source_house
      if not host or not record then views[i]={house=false};break end
      local slope,level=Terrain.tile(s.corner_grid,x+i-1,z)
      views[i]={house=true,clearable=record.town_growth and not protected(s,id,host),
        water=host.terrain=="water",slope=slope}
      levels[i]=level
      if record.asset_root then
        local parts=growth.footprint(s,record)
        if not parts then views[i].clearable=false end
        for _,part in ipairs(parts or {}) do
          local p=s.tiles[part.id]
          if protected(s,part.id,p) then views[i].clearable=false end
          if not removed[part.id] then ids[#ids+1]=part.id;removed[part.id]=part.record end
        end
      elseif not removed[id] then ids[#ids+1]=id;removed[id]=record end
    end
    local ok,why=R.site(town,views[1],views[2])
    if not ok then return nil,why end
    if levels[1]~=levels[2] then return nil,"BANK_NEEDS_SHARED_MESH_BASE" end
    for _,p in pairs(s.stock_bank_industries or {}) do
      if not p.removed then
        if p.town==town.id then return nil,"BANK_ONE_PER_TOWN" end
        if math.max(math.abs(p.x-(x-1)),math.abs(p.z-(z-1)))<=14 then return nil,"BANK_ANOTHER_BANK_TOO_CLOSE" end
      end
    end
    local next_=s.next_stock_bank_industry or W.BASE
    if next_>=W.LIMIT or (s.stock_bank_industries or {})[next_] then return nil,"BANK_INDUSTRY_POOL_FULL" end
    return {tile=tile,pair=pair,clears=ids,removed=removed,base=levels[1],town=town.id,x=x,z=z,
      price=F.cost("temperate_bank",0),revision=s.topology,terrain_revision=s.corner_grid.revision,industry=next_}
  end
  function W.execute(s,owner,tile,quote,opening)
    local verified,why=W.plan(s,tile)
    if not verified then return nil,why end
    if not quote or verified.revision~=quote.revision or verified.terrain_revision~=quote.terrain_revision or
        verified.price~=quote.price or verified.town~=quote.town then return nil,"BANK_STALE_QUOTE" end
    local c=s.companies[owner]
    if not opening and (not c or c.cash<verified.price) then return nil,"BANK_NOT_ENOUGH_CASH" end
    local town=assert(s.sites[verified.town])
    local id=verified.industry
    local site_id=#s.sites+1
    local industry=F.new("temperate_bank",id,verified.x-1,verified.z-1,{economy_year=Sim.date(s),
      original=opening and true or nil,random_u32=not opening and function() return random(s) end or nil})
    if opening then
      local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
      dofile(mod.."/openttd/industry_gameplay_construction.lua")(industry,opening.seed_bits,opening.random,opening.original)
    end
    industry.town,industry.site,industry.founder=town.id,site_id,owner
    local site={id=site_id,kind="stock_temperate_bank",name=town.name.." Bank",tile=tile,stock={},produced={},received={},
      service=0,stock_industry=id,industry_chain="bank",town=town.id}
    if not opening then debit(c,verified.price) end
    for _,part in ipairs(verified.clears) do
      growth.remove(s,verified.removed[part])
      s.tiles[part].house,s.tiles[part].source_house=nil,nil
    end
    for i,p in ipairs(verified.pair) do
      local b=s.tiles[p]
      b.stock_industry={id=id,chain="bank",kind="temperate_bank",style=W.STYLE,x=i-1,z=0,gfx=industry.tiles[i].gfx,
        site=site_id,origin=tile}
      b.stock_clear_ground=nil
    end
    s.tiles[tile].site=site_id
    s.stock_bank_industries=s.stock_bank_industries or {}
    s.stock_bank_industries[id]=industry
    s.sites[site_id]=site;s.next_stock_bank_industry=id+1
    s.topology=s.topology+1
    s.road_bank=true
    return industry,verified.clears
  end
  return W
end
