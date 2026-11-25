-- Oil industry placement in an ordinary generated map or fixed test site.
-- No enabled game mode, production clock, renderer or fare authority here.
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
return function(Sim,Terrain,Rules)
  local Offshore=dofile(mod.."/offshore_rig_world.lua")(Sim,Terrain,dofile(mod.."/openttd/oil_rig.lua"),Rules)
  local W={VERSION=1,BASE=0x3000,LIMIT=0x4000,MIN_SEPARATION=15}
  W.offshore=Offshore
  local layouts={wells=Rules.layout.oil_well,refinery=Rules.layout.oil_refinery}
  local specs={
    wells={kind="stock_oil_wells",source="oil_well",name="Northfield Oil Wells",art="industry_oil_well",industry=11},
    refinery={kind="stock_oil_refinery",source="oil_refinery",name="Westhaven Refinery",art="industry_oil_refinery",industry=4},
  }
  W.facilities={
    stock_oil_wells={name="Oil Wells",produces={},takes={}},
    stock_oil_rig={name="Oil Rig",produces={},takes={}},
    stock_oil_refinery={name="Oil Refinery",produces={},takes={}},
  }
  local function point(x,z)
    return type(x)=="number" and x%1==0 and type(z)=="number" and z%1==0 and x>=1 and z>=1
  end
  -- Use the original zero-based site permission; host origins start
  -- at one. Source distance-to-edge and void handling stay in Rules.
  function W.refinery_edge(x,z,w,h,limit,editor,freeform)
    if not point(x,z) or not point(w,h) or type(limit)~="number" or limit<0 or limit%1~=0 then return false end
    return Rules.refinery_edge(x-1,z-1,w,h,{limit=limit,editor=editor,freeform=freeform})
  end
  local overlays={"bridge_above","tunnel_below","rail_bridge_above","rail_tunnel_below","aqueduct_above"}
  local function occupied(s,id,t)
    if t.stock_void or t.terrain=="water" or t.owner or t.site or t.house or t.source_house or t.build or
       t.wood or t.stock_industry or t.tram or t.ship or t.airfield or t.rail_tracks or
       t.rail_station_id or t.rail_depot_dir or t.rail_span_id or t.level_crossing or
       t.stock_canal or t.road_bridge_id or t.road_tunnel_id then return true end
    for _,k in ipairs(overlays) do if s[k] and s[k][id] then return true end end
    return false
  end
  local function quote(s,kind,x,z,variant)
    if not s.corner_grid or not specs[kind] or not point(x,z) then return nil,"INVALID_OIL_SITE" end
    if kind=="refinery" and not W.refinery_edge(x,z,Sim.W,Sim.H,Rules.EDGE_LIMIT,false,not not (s.corner_grid.freeform_edges or s.stock_freeform_edges)) then return nil,"REFINERY_NOT_NEAR_EDGE" end
    variant=variant or 0
    local footprint=layouts[kind][variant]
    if not footprint then return nil,"INDUSTRY_LAYOUT_UNPORTED" end
    local cells,level={},nil
    for _,r in ipairs(footprint) do
      local a,b=x+r[1],z+r[2]
      local id=Sim.id(a,b)
      local t=id and s.tiles[id]
      if not t then return nil,"OIL_FOOTPRINT_OFF_MAP" end
      if occupied(s,id,t) then return nil,"OIL_FOOTPRINT_OCCUPIED",id end
      local slope,h=Terrain.tile(s.corner_grid,a,b)
      if not Rules.slope_allowed(r[3],slope) or level and level~=h then return nil,"OIL_FOOTPRINT_NEEDS_FLAT_GROUND",id end
      level=h
      cells[#cells+1]={tile=id,x=a,z=b,gfx=r[3],offset_x=r[1],offset_z=r[2]}
    end
    return {kind=kind,x=x,z=z,level=level,cells=cells,layout=variant}
  end
  function W.plan(s,wx,wz,rx,rz)
    if s.stock_oil_placements then return nil,"OIL_ALREADY_PLACED" end
    if s.road_farm or s.road_timber or s.stock_farm_industries or s.stock_timber_industries then
      return nil,"USE_SEPARATE_FREIGHT_SCENARIO"
    end
    local a,err,id=quote(s,"wells",wx,wz)
    if not a then return nil,err,id end
    local b,why,spot=quote(s,"refinery",rx,rz)
    if not b then return nil,why,spot end
    if math.max(math.abs(wx-rx),math.abs(wz-rz))<W.MIN_SEPARATION then return nil,"OIL_INDUSTRIES_TOO_CLOSE" end
    return {version=W.VERSION,seed=s.seed,topology=s.topology,wells=a,refinery=b}
  end
  local function same(a,b)
    if not b or a.kind~=b.kind or a.layout~=b.layout or a.x~=b.x or a.z~=b.z or a.level~=b.level or type(b.cells)~="table" or
       #a.cells~=#b.cells then return false end
    for i,c in ipairs(a.cells) do
      local d=b.cells[i]
      if type(d)~="table" or c.tile~=d.tile or c.gfx~=d.gfx or c.offset_x~=d.offset_x or c.offset_z~=d.offset_z or
         c.x~=d.x or c.z~=d.z then return false end
    end
    return true
  end
  function W.place(s,q)
    if type(q)~="table" or q.version~=W.VERSION or q.seed~=s.seed or q.topology~=s.topology or
       type(q.wells)~="table" or type(q.refinery)~="table" then return nil,"STALE_OIL_PLACEMENT" end
    local fresh,why,id=W.plan(s,q.wells.x,q.wells.z,q.refinery.x,q.refinery.z)
    if not fresh then return nil,why,id end
    if not same(fresh.wells,q.wells) or not same(fresh.refinery,q.refinery) then return nil,"STALE_OIL_PLACEMENT" end
    local records,industries,dirty={},{},{}
    for i,kind in ipairs({"wells","refinery"}) do
      local value,desc=fresh[kind],specs[kind]
      local stock_id=W.BASE+i-1
      local sid=#s.sites+1
      local origin=Sim.id(value.x,value.z)
      local source=Rules.new(desc.source,stock_id,value.x-1,value.z-1,
        {original=true,completed=true,generating_world=true,counter=i,economy_year=1950})
      source.site=sid
      industries[stock_id]=source
      for _,c in ipairs(value.cells) do
        local t=s.tiles[c.tile]
        t.stock_industry={id=stock_id,chain="oil",kind=kind,style=desc.art,x=c.offset_x,z=c.offset_z,gfx=c.gfx}
        dirty[#dirty+1]=c.tile
      end
      s.tiles[origin].site=sid
      s.sites[sid]={id=sid,name=desc.name,kind=desc.kind,tile=origin,
        stock={},produced={},received={},service=0}
      records[stock_id]={id=stock_id,kind=kind,source_type=desc.industry,site=sid,
        x=value.x,z=value.z,level=value.level,cells=value.cells,style=desc.art}
    end
    s.stock_oil_placements,s.stock_oil_industries=records,industries
    s.topology=s.topology+1
    return records,dirty
  end
  -- The upstream generator owns RNG, selected layout, initial cargo
  -- history, industry counter, town and tile construction state. Install
  -- the exact record it produced, rather than rerunning the authored pair
  -- initializer or rewriting another chain's data.
  function W.place_generated(s,kind,origin,opts)
    local key=kind=="oil_well" and "wells" or kind=="oil_refinery" and "refinery" or nil
    if not key or type(origin)~="number" or origin%1~=0 or not s.tiles[origin] then return nil,"INVALID_OIL_SITE" end
    local x,z=Sim.xy(origin)
    local ind=opts and opts.record
    if not ind or type(opts.name)~="string" or ind.kind~=kind or ind.x~=x-1 or ind.z~=z-1 then
      return nil,"GENERATED_OIL_FOOTPRINT_MISMATCH"
    end
    local p,why,tile=quote(s,key,x,z,ind.layout)
    if not p then return nil,why,tile end
    if #ind.tiles~=#p.cells then return nil,"GENERATED_OIL_FOOTPRINT_MISMATCH" end
    for i,c in ipairs(p.cells) do
      local t=ind.tiles[i]
      if t.x~=c.x-1 or t.z~=c.z-1 or t.gfx~=c.gfx then return nil,"GENERATED_OIL_FOOTPRINT_MISMATCH" end
      c.id=c.tile -- common generated map host; closure uses c.tile
    end
    local id=s.next_stock_oil_industry or W.BASE
    if type(id)~="number" or id%1~=0 or id<W.BASE or id>=W.LIMIT then return nil,"OIL_INDUSTRY_IDS_EXHAUSTED" end
    local industries,records=s.stock_oil_industries or {},s.stock_oil_placements or {}
    for _,map in ipairs({industries,s.stock_coal_industries or {},s.stock_farm_industries or {},s.stock_timber_industries or {}}) do
      if map[id] then return nil,"INDUSTRY_ID_COLLISION" end
    end
    local desc,sid=specs[key],#s.sites+1
    local site={id=sid,name=opts.name,kind=desc.kind,tile=origin,stock={},produced={},received={},
      service=0,stock_industry=id,industry_chain="oil",town=ind.town}
    local art=p.layout==0 and desc.art or desc.art.."_l"..p.layout
    local record={id=id,kind=key,source_type=desc.industry,site=sid,x=x,z=z,level=p.level,cells=p.cells,style=art}
    ind.id,ind.site=id,sid
    records[id],industries[id],s.sites[sid]=record,ind,site
    for _,c in ipairs(p.cells) do
      local t=s.tiles[c.tile]
      t.stock_industry={id=id,chain="oil",kind=key,style=art,layout=p.layout,x=c.offset_x,z=c.offset_z,gfx=c.gfx,
        site=sid,origin=origin}
    end
    s.tiles[origin].site=sid
    s.stock_oil_placements,s.stock_oil_industries=records,industries
    s.next_stock_oil_industry,s.topology=id+1,s.topology+1
    return ind,p.cells,site
  end
  function W.default_1751(s)
    if s.seed~=1751 then return nil,"OIL_PROFILE_REQUIRES_SEED_1751" end
    local quote,why,id=W.plan(s,11,2,15,17)
    if not quote then return nil,why,id end
    return W.place(s,quote)
  end
  function W.record(s,id)
    local t=s.tiles[id]
    local mark=t and t.stock_industry
    local r=mark and mark.chain=="oil" and s.stock_oil_placements and s.stock_oil_placements[mark.id]
    local active=r and s.stock_oil_industries[mark.id]
    if not active or active.removed then return end
    return {kind=r.kind,style=r.style,site=r.site,gfx=mark.gfx,
      offset_x=mark.x,offset_z=mark.z}
  end
  -- A stock closure restores exactly the cells of that original
  -- footprint. Keep the indexed site record as a tombstone so existing
  -- station/receipt IDs remain meaningful; never erase their routes.
  function W.sweep_closed(s)
    local dirty,land={},false
    for id,record in pairs(s.stock_oil_placements or {}) do
      local active=s.stock_oil_industries[id]
      if active and active.removed and not record.closed then
        if record.kind=="rig" then
          local done=Offshore.close(s,active)
          for _,tile in ipairs(done) do dirty[#dirty+1]=tile end
        else
          record.closed=true
          s.sites[record.site].closed=true
          for _,cell in ipairs(record.cells) do
            local t=s.tiles[cell.tile]
            local mark=t and t.stock_industry
            if mark and mark.chain=="oil" and mark.id==id then
              t.stock_industry=nil
              if t.site==record.site then t.site=nil end
              if s.stock_oil_animated then s.stock_oil_animated[cell.tile]=nil end
              dirty[#dirty+1]=cell.tile
              land=true
            end
          end
        end
      end
    end
    table.sort(dirty)
    if land then s.topology=s.topology+1 end
    return dirty
  end
  function W.visual_sources()
    return {industry_oil_well=layouts.wells[0],industry_oil_well_l1=layouts.wells[1],
      industry_oil_refinery=layouts.refinery[0],industry_oil_refinery_l1=layouts.refinery[1],industry_oil_rig=Rules.layout.oil_rig[0]}
  end
  function W.visual_asset(style,cell,index)
    -- All five stock well tiles have GFX29, with the same machinery and
    -- ordinal phase on either footprint. Share the existing genuine
    -- pumpjacks; only their placement in the generated field changes.
    if style=="industry_oil_well_l1" then
      style,cell="industry_oil_well",layouts.wells[0][index]
    end
    return ("%s_%d_%d"):format(style,cell[1],cell[2]),style.."_atlas"
  end
  return W
end
