-- SPDX-License-Identifier: GPL-2.0-only
-- Native worker adapter for stock OpenTTD industry_cmd.cpp (create,
-- construction, closure) and station_cmd.cpp (BuildOilRig/DeleteOilRig).
-- Calendar opening and order/ledger adapters are mounted independently.
return function(Sim,Terrain,Rig,Oil)
  local W={VISUAL="industry_oil_rig",KIND="stock_oil_rig",ID_MIN=0x3000,ID_LIMIT=0x4000}
  local function host(s,x,z)
    local id=Sim.id(x+1,z+1)
    local t=id and s.tiles[id]
    if not t or t.stock_void then return end
    return t,id
  end
  local function water(t)
    if t.build=="canal" or t.stock_canal then return "canal" end
    if t.terrain=="water" then return t.water_class or "sea" end
  end
  local function blocked(t)
    return t.site or t.owner and not (t.build=="canal" or t.stock_canal) or t.ship or t.airfield or t.house or
      t.wood or t.tram or t.stock_industry or t.stock_landmark or t.rail_tracks or
      t.road_tunnel_id or t.rail_depot_dir or t.rail_station_id or t.build and t.build~="canal"
  end
  local function board(s,ctx)
    local out={width=Sim.W,height=Sim.H,
      freeform=s.corner_grid.freeform_edges or s.stock_freeform_edges,industries={}}
    for _,i in pairs(s.stock_oil_placements or {}) do
      if not i.closed then
        out.industries[#out.industries+1]={type=i.source_type,x=i.x-1,z=i.z-1}
      end
    end
    function out.tile(x,z)
      local t,id=host(s,x,z)
      if not t then return end
      local slope,h=Terrain.tile(s.corner_grid,x+1,z+1)
      local cls=water(t)
      local kind=(t.ship and (t.ship.kind=="lock" or t.ship.kind=="ship_depot") or not t.ship and cls and not blocked(t))
        and "water" or t.ship and "station" or t.stock_industry and "industry" or "land"
      return {id=id,kind=kind,base=h,slope=slope,water_class=cls,is_water_tile=not t.stock_water_rocks,
        bridge=(s.bridge_above and s.bridge_above[id]~=nil) or (s.rail_bridge_above and s.rail_bridge_above[id]~=nil)
          or (s.aqueduct_above and s.aqueduct_above[id]~=nil),
        vehicle=ctx.vehicle_on_ground and ctx.vehicle_on_ground(id)}
    end
    function out.clear(x,z,p)
      local t=host(s,x,z)
      if not t or blocked(t) or t.coastal_water then return false end
      return not ctx.clear_water_quote or ctx.clear_water_quote(p.id,t)
    end
    return out
  end
  local function same(a,b)
    if a.origin~=b.origin or a.town~=b.town or a.topology~=b.topology or a.seed~=b.seed or #a.cells~=#b.cells then return false end
    for k,d in ipairs(a.cells) do
      local e=b.cells[k]
      if type(e)~="table" or d.id~=e.id or d.gfx~=e.gfx or d.water_class~=e.water_class then return false end
    end
    return true
  end
  function W.quote(s,origin,ctx)
    if not s.corner_grid or not s.tiles[origin] then return nil,"INVALID_RIG_SITE" end
    local x,z=Sim.xy(origin)
    local p,reason=Rig.quote(board(s,ctx),x-1,z-1,ctx)
    if not p then return nil,reason end
    local town=Sim.nearest_town(s,origin)
    if not town then return nil,"NO_TOWN" end
    if not ctx.multiple_per_town then
      for _,ind in pairs(s.stock_oil_industries or {}) do
        if not ind.removed and ind.kind=="oil_rig" and ind.town==town.id then return nil,"ONLY_ONE_ALLOWED_PER_TOWN" end
      end
    end
    p.origin,p.town,p.topology,p.seed=origin,town.id,s.topology,s.seed
    for _,v in ipairs(p.cells) do
      v.id=assert(Sim.id(v.x+1,v.z+1))
      v.tile=v.id
      v.offset_x,v.offset_z=v.x-p.x,v.z-p.z
    end
    return p
  end
  function W.place(s,quote,ctx)
    if type(quote)~="table" or type(quote.cells)~="table" then return nil,"STALE_RIG_QUOTE" end
    local fresh,reason=W.quote(s,quote.origin,ctx)
    if not fresh then return nil,reason end
    if not same(fresh,quote) then return nil,"STALE_RIG_QUOTE" end
    local id=s.next_stock_oil_industry or W.ID_MIN
    if id<W.ID_MIN or id>=W.ID_LIMIT then return nil,"OIL_INDUSTRY_IDS_EXHAUSTED" end
    local all=s.stock_oil_industries or {}
    local records=s.stock_oil_placements or {}
    local sites=s.sites
    if all[id] or records[id] or (ctx.can_allocate and not ctx.can_allocate(id)) then return nil,"OIL_INDUSTRY_IDS_EXHAUSTED" end
    local sid=#sites+1
    local rc1=ctx.opening_seed_bits~=nil
    local source=Oil.new("oil_rig",id,fresh.x,fresh.z,
      {layout=0,original=rc1 or ctx.original,random_u32=not rc1 and ctx.random or nil,
       initial_random=ctx.initial_random,economy_year=ctx.economy_year})
    if rc1 then
      local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
      dofile(mod.."/openttd/industry_gameplay_construction.lua")(source,ctx.opening_seed_bits,ctx.random,ctx.original)
    end
    source.town,source.site=fresh.town,sid
    local sight={id=sid,name=ctx.name or "Oil Rig",kind=W.KIND,tile=fresh.origin,stock={},produced={},received={},
      service=0,stock_industry=id,industry_chain="oil",town=fresh.town}
    local rec={id=id,kind="rig",source_type=Rig.spec.id,site=sid,x=fresh.x+1,z=fresh.z+1,level=0,
      cells=fresh.cells,style=W.VISUAL}
    -- Allocation and all quotes are complete; only this writer mutates.
    local dirty={}
    all[id],records[id],sites[sid]=source,rec,sight
    for i,p in ipairs(fresh.cells) do
      local t=s.tiles[p.id]
      source.tiles[i].water_class=p.water_class
      t.stock_industry={id=id,chain="oil",kind="rig",style=W.VISUAL,x=p.offset_x,z=p.offset_z,gfx=p.gfx,
        site=sid,origin=fresh.origin}
      if i==1 then t.site=sid end
      dirty[#dirty+1]=p.id
    end
    s.stock_oil_placements,s.stock_oil_industries=records,all
    s.next_stock_oil_industry,s.topology=id+1,s.topology+1
    return source,dirty
  end
  function W.complete(s,ind,tile,ctx)
    if ind.neutral_station or ind.removed then return end
    local function lookup(x,z)
      local t,id=host(s,x,z)
      local p=t and t.stock_industry
      if p then return {kind="industry",gfx=p.gfx,industry=p.id,x=x,z=z,id=id} end
    end
    local added=lookup(tile.x,tile.z)
    if not added or added.industry~=ind.id then return end
    added.completed,added.water_class=tile.completed,tile.water_class
    local child=lookup(tile.x,tile.z+1)
    -- IDs are shared across the two typed native registries; never
    -- confuse a terminal with an available purchase depot.
    local id=math.max(s.next_stock_ship_station or 1,s.next_small_airport or 1)
    local station=Rig.completed_station(added,child,id<0x4000 and (not ctx.can_station or ctx.can_station(id)))
    if not station then return end
    local ship=s.stock_ship_stations or {}
    local air=s.stock_small_airports or {}
    if ship[id] or air[id] or s.stock_ship_buoys and s.stock_ship_buoys[id] then return end
    local cell=added.id
    local rec=s.stock_oil_placements[ind.id]
    local pool=Sim.stock_station_slot and Sim.stock_station_slot(s)
    local key={id=id,stock_station_id=pool,type="oilrig",tile=cell,industry=ind.id,name=s.sites[ind.site].name,town=ind.town,
      water_class=station.water_class}
    ship[id]={id=id,stock_station_id=pool,neutral=true,oil_rig=ind.id,land=cell,water=cell,water_class=station.water_class,
      town=ind.town,name=key.name,station_area={{x=rec.x,z=rec.z}}}
    air[id]={id=id,stock_station_id=pool,neutral=true,oil_rig=ind.id,origin=cell,x=(tile.x+1)*16,z=(tile.z+1)*16,
      layout="oilrig",rotation=0,width=1,height=1,ground=0,delta_z=Rig.airport.delta_z,flags=0,
      town=ind.town,name=key.name,tiles={{id=cell,x=0,z=0}}}
    s.stock_neutral_stations=s.stock_neutral_stations or {}
    s.stock_neutral_stations[id]=key
    s.stock_ship_stations,s.stock_small_airports=ship,air
    s.tiles[cell].ship={kind="oilrig",station=id,water_class=station.water_class,water_ground=true}
    s.tiles[cell].airfield={airport=id,x=0,z=0,layout="oilrig"}
    s.next_stock_ship_station,s.next_small_airport=id+1,id+1
    s.topology,ind.neutral_station=s.topology+1,id
    tile.neutral_platform=true
    return key
  end
  function W.docking_tiles(s,id,is_possible_docking)
    local key=(s.stock_neutral_stations or {})[id]
    local rec=key and (s.stock_oil_placements or {})[key.industry]
    if not rec or rec.closed then return {} end
    local present,out={},{}
    for _,c in ipairs(rec.cells) do present[c.id]=true end
    -- UpdateStationDockingTiles checks the expanded area; the only
    -- candidates attached to this rig are adjacent to one occupied cell.
    for z=rec.z-1,rec.z+3 do for x=rec.x-1,rec.x+2 do
      local cell=Sim.id(x,z)
      if cell and not present[cell] and is_possible_docking(cell) then
        for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
          if present[Sim.id(x+offset[1],z+offset[2])] then out[#out+1]=cell;break end
        end
      end
    end end
    return out
  end
  function W.close(s,ind)
    local rec=s.stock_oil_placements[ind.id]
    if not ind.removed or not rec or rec.closed then return {} end
    rec.closed=true; s.sites[ind.site].closed=true
    local dirty={}
    for _,c in ipairs(rec.cells) do
      local t=s.tiles[c.id]
      if t and t.stock_industry and t.stock_industry.id==ind.id then
        t.stock_industry=nil
        if t.site==ind.site then t.site=nil end
        dirty[#dirty+1]=c.id
      end
    end
    local st=ind.neutral_station
    if st then
      local n=s.stock_neutral_stations[st]
      local t=n and s.tiles[n.tile]
      if t and t.ship and t.ship.station==st and t.ship.kind=="oilrig" then t.ship=nil end
      if t and t.airfield and t.airfield.airport==st and t.airfield.layout=="oilrig" then t.airfield=nil end
      s.stock_small_airports[st],s.stock_ship_stations[st],s.stock_neutral_stations[st]=nil,nil,nil
      ind.neutral_station=nil
    end
    s.topology=s.topology+1
    return dirty,st
  end
  return W
end
