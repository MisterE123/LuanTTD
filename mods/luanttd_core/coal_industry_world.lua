-- Actual stock layout-0 geometry on LuanTTD's shared corner map.
-- For now this creates completed map-generation sites, not a funded
-- industry command or an approximation to stock industry creation.
return function(Sim,Terrain,Coal)
  local W={}
  local styles={
    coal_mine={name="Eastbank Coal Mine",kind="stock_coal_mine",picture="coal_mine_0"},
    power_station={name="Riverbend Power Station",kind="stock_power_station",picture="power_station"},
  }
  local function coords(u,v) return u-1,v-1 end
  function W.quote(s,kind,origin)
    local style=styles[kind]
    if not (style and s.corner_grid and origin and s.tiles[origin]) then return nil,"INVALID_INDUSTRY_ORIGIN" end
    local ox,oz=Sim.xy(origin)
    local x,z=coords(ox,oz)
    local ind=Coal.new(kind,0,x,z,{layout=0,completed=true,original=true})
    local cells={}
    local level
    for i,part in ipairs(ind.tiles) do
      local tx,tz=part.x+1,part.z+1
      local id=Sim.id(tx,tz)
      local t=id and s.tiles[id]
      if not t then return nil,"INDUSTRY_OUTSIDE_REGION" end
      local slope,h=Terrain.tile(s.corner_grid,tx,tz)
      if slope~=0 or level and level~=h then return nil,"INDUSTRY_NEEDS_LEVEL_LAND" end
      if t.terrain=="water" or t.build or t.owner or t.wood or t.house or t.site or t.airfield or
        t.ship or t.tram or t.stock_industry or (s.bridge_above and s.bridge_above[id]) or
        (s.tunnel_below and s.tunnel_below[id]) or (s.aqueduct_above and s.aqueduct_above[id]) then
        return nil,"INDUSTRY_SITE_OCCUPIED"
      end
      level=h
      cells[i]={id=id,x=part.x-x,z=part.z-z,gfx=part.gfx}
    end
    return {origin=origin,ind=ind,cells=cells,style=style,level=level}
  end
  function W.place(s,kind,origin,opts)
    local p,why=W.quote(s,kind,origin)
    if not p then return nil,why end
    opts=opts or {}
    local ind=opts.record or p.ind
    if opts.record then
      assert(ind.kind==kind and ind.x==p.ind.x and ind.z==p.ind.z and #ind.tiles==#p.cells)
      for i,part in ipairs(ind.tiles) do
        local cell=p.cells[i]
        assert(part.x==ind.x+cell.x and part.z==ind.z+cell.z and part.gfx==cell.gfx,
          "Generated coal footprint does not match native art")
      end
    end
    s.stock_coal_industries=s.stock_coal_industries or {}
    ind.id=s.next_stock_coal_industry or 1
    s.next_stock_coal_industry=ind.id+1
    s.stock_coal_industries[ind.id]=ind
    local sid=#s.sites+1
    local site={id=sid,tile=p.origin,name=opts.name or p.style.name,kind=p.style.kind,
      produced={},received={},stock={},service=0,stock_industry=ind.id}
    s.sites[sid]=site;ind.site=sid
    -- Source origin is occupied in layout 0. Other footprint cells
    -- reference one site; holes are never painted or cleared.
    for _,cell in ipairs(p.cells) do
      local t=s.tiles[cell.id]
      t.stock_industry={id=ind.id,x=cell.x,z=cell.z,gfx=cell.gfx,style=p.style.picture}
      t.coal_site=sid
      if cell.id==p.origin then t.site=sid end
    end
    s.topology=s.topology+1
    return ind,p.cells,site
  end
  function W.seed(s,mine,power)
    local first,why=W.quote(s,"coal_mine",mine)
    if not first then return nil,why end
    local second,why2=W.quote(s,"power_station",power)
    if not second then return nil,why2 end
    local used={}
    for _,tile in ipairs(first.cells) do used[tile.id]=true end
    for _,tile in ipairs(second.cells) do if used[tile.id] then return nil,"INDUSTRIES_OVERLAP" end end
    local a,cells=assert(W.place(s,"coal_mine",mine))
    local b,other=assert(W.place(s,"power_station",power))
    local dirty={}
    for _,list in ipairs({cells,other}) do
      for _,tile in ipairs(list) do dirty[#dirty+1]=tile.id end
    end
    return {mine=a.id,power=b.id,tiles=dirty}
  end
  return W
end
