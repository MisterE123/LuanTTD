-- SPDX-License-Identifier: GPL-2.0-only
-- Native bridge for original Farm and Factory footprints.
-- Ordinary map generation provides the source record; the seed-1751
-- workbench remains available as a controlled fixture.
return function(Sim,Terrain,Rules,Fields,Catchment)
  local W={VERSION=1,INDUSTRY_ID_BASE=0x2000,INDUSTRY_ID_LIMIT=0x3000,MIN_SEPARATION=15}
  local styles={
    farm={kind="stock_farm",name="Highfield Farm",art="industry_farm"},
    factory={kind="stock_factory",name="Westfield Factory",art="industry_factory"},
  }
  -- Deliberately empty legacy production/acceptance descriptors. Cargo
  -- only exists in the exact industry/pickup and installed station path.
  W.facilities={stock_farm={name="Farm",produces={},takes={}},stock_factory={name="Factory",produces={},takes={}}}
  local function valid_id(id)
    return type(id)=="number" and id>=1 and id%1==0 and id<=Sim.W*Sim.H
  end
  local function occupied(s,id,t,allow_tree,ground_only)
    return t.terrain=="water" or t.owner or t.site or t.house or t.source_house or t.build or
      (t.wood and not allow_tree) or t.rail_tracks or t.rail_station_id or t.rail_depot_dir or t.tram or t.ship or
      t.airfield or t.stock_industry or t.stock_landmark or t.level_crossing or t.road_bridge_id or t.road_tunnel_id or
      t.rail_span_id or t.stock_canal or not ground_only and
      (s.bridge_above and s.bridge_above[id] or s.tunnel_below and s.tunnel_below[id] or
       s.rail_bridge_above and s.rail_bridge_above[id] or s.rail_tunnel_below and s.rail_tunnel_below[id] or
       s.aqueduct_above and s.aqueduct_above[id])
  end
  local function max_distance(x,z,u,v) return math.max(math.abs(x-u),math.abs(z-v)) end
  local function conflicts(s,kind,x,z)
    for _,i in pairs(s.stock_farm_industries or {}) do
      if not i.removed and i.kind~=kind and max_distance(x,z,i.x+1,i.z+1)<W.MIN_SEPARATION then return true end
    end
    return false
  end

  function W.quote(s,kind,origin,generated,layout)
    if not generated and (s.road_timber or next(s.stock_timber_industries or {})) then return nil,"TIMBER_GOODS_WORKBENCH_ACTIVE" end
    if not (styles[kind] and s.corner_grid and valid_id(origin) and s.tiles[origin]) then
      return nil,"INVALID_INDUSTRY_ORIGIN",origin
    end
    layout=layout or 0
    local footprint=Rules.layout[kind][layout]
    if not footprint then return nil,"INDUSTRY_LAYOUT_UNPORTED",origin end
    local x,z=Sim.xy(origin)
    local cells,level={},nil
    -- The layout list includes only authored cells, not its holes.
    for n,q in ipairs(footprint) do
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
    return {version=W.VERSION,kind=kind,layout=layout,origin=origin,x=x,z=z,level=level,cells=cells,
      topology=s.topology,seed=s.seed}
  end

  function W.quote_pair(s,farm,factory)
    local a,error_,bad=W.quote(s,"farm",farm)
    if not a then return nil,error_,bad end
    local b,why,at=W.quote(s,"factory",factory)
    if not b then return nil,why,at end
    local footprint={}
    for _,q in ipairs(a.cells) do footprint[q.id]=true end
    for _,q in ipairs(b.cells) do if footprint[q.id] then return nil,"INDUSTRIES_OVERLAP",q.id end end
    if max_distance(a.x,a.z,b.x,b.z)<W.MIN_SEPARATION then return nil,"INDUSTRIES_TOO_CLOSE",b.origin end
    return {version=W.VERSION,kind="pair",farm=a,factory=b,topology=s.topology,seed=s.seed}
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
  -- Only the read-only kind/ground classification is shared. Field
  -- records, ownership and corner heights are still read live.
  local empty,protected={kind="void"},{kind="protected"}
  local trees,shore,rough_trees={kind="trees",ground="grass"},{kind="trees",ground="shore"},{kind="trees",ground="rough"}
  local grass,snow,dry={kind="clear",ground="grass"},{kind="clear",ground="snow",snow=true},{kind="clear",ground="desert"}
  local rough,rocks={kind="clear",ground="rough"},{kind="clear",ground="rocks"}
  function W.field_board(s,opts)
    opts=opts or {}
    local climate=s.stock_climate
    -- Stock maps use a power-of-two board with void at the edge. Expose
    -- only existing LuanTTD tiles; unused columns/rows remain void.
    local width,height=64,64
    local stock=s.stock_generated_profile or opts.exact_grid
    local freeform
    if stock then
      -- Generated stock axes already include the boundary void tiles.
      width,height,freeform=Sim.W,Sim.H,s.corner_grid.freeform_edges
    else
      while width<=Sim.W do width=width*2 end
      while height<=Sim.H do height=height*2 end
      freeform=s.stock_freeform_edges
    end
    s.stock_farm_fields=s.stock_farm_fields or {}
    local records=s.stock_farm_fields
    local regrowth=s.stock_farm_grass
    local function in_map(x,z)
      return x>=0 and z>=0 and x<Sim.W and z<Sim.H and not (freeform and (x==0 or z==0))
        and not (stock and (x==width-1 or z==height-1))
    end
    local function valid_field(id,t,x,z,r)
      return t and not t.stock_void and not occupied(s,id,t,true,true)
        and Terrain.matches(s.corner_grid,x+1,z+1,r.slope,r.base)
    end
    local function base(x,z)
      local id=Sim.id(x+1,z+1)
      if not id or not s.tiles[id] then return nil end
      local t=s.tiles[id]
      -- RC1 PlantFarmField / TileLoop_Clear inspect the surface tile
      -- type. A bridge-middle flag or an underground bore is not a
      -- replacement for that tile; growth and fences must continue.
      if t.stock_void or occupied(s,id,t,true,true) then return nil end
      if t.wood then
        local cover=type(t.wood)=="table" and t.wood.ground
        return id,(cover==3 or t.terrain=="shore") and shore or cover==1 and rough_trees or trees
      end
      local g=t.stock_clear_ground
      return id,t.terrain=="snow" and snow or (g==5 or t.terrain=="desert") and dry or g==1 and rough or g==2 and rocks or grass
    end
    local function dirty(id)
      s.changed=s.changed or {};s.changed[#s.changed+1]=id
    end
    local b={width=width,height=height,freeform=not not freeform,
      landscape_fields=records,landscape_regrowth=regrowth,
      climate=climate and climate.landscape,snowline=climate and climate.snowline}
    function b.height_at(x,z) local _,base=Terrain.tile(s.corner_grid,x+1,z+1);return base end
    function b.tile(x,z)
      if not in_map(x,z) then return empty end
      local id,t=base(x,z)
      if not id then return protected end
      local r=records[id]
      if r then
        if Terrain.matches(s.corner_grid,x+1,z+1,r.slope,r.base) then return r end
      end
      return t
    end
    function b.make_field(x,z,variant,industry,counter)
      local id,t=base(x,z)
      assert(id and Fields.suitable(t,true,true))
      if regrowth then regrowth[id]=nil end
      s.tiles[id].wood,s.tiles[id].stock_clear_ground=nil,nil
      local slope,base=Terrain.tile(s.corner_grid,x+1,z+1)
      records[id]={kind="clear",ground="field",variant=variant,industry=industry,counter=counter,
        fences={},slope=slope,base=base}
      dirty(id)
    end
    function b.set_fence(x,z,side,style)
      local id=assert(Sim.id(x+1,z+1))
      local field=assert(records[id]);field.fences[side]=style
      dirty(id)
    end
    local function edge(r,id,other,x,z,side)
      if r.fences[side] then return end
      -- No other native surface can describe itself as a field. Avoid
      -- reading/classifying a neighbor we already know has no crop.
      local n=records[other]
      if n and n.kind=="clear" and n.ground=="field" and in_map(x,z)
          and valid_field(other,s.tiles[other],x,z,n) then return end
      r.fences[side]=3;dirty(id)
    end
    function b.visit(x,z,tick,editor,id)
      id=id or Sim.id(x+1,z+1)
      local r=id and records[id]
      if not r then
        local grow=id and regrowth and regrowth[id]
        if grow==nil or editor then return end
        local _,ground=base(x,z)
        if ground~=grass then regrowth[id]=nil
        elseif grow<7 then regrowth[id]=grow+1
        else regrowth[id]=nil;dirty(id) end
        return
      end
      if r.last_tick==tick then return end
      if not in_map(x,z) or not valid_field(id,s.tiles[id],x,z,r) then records[id]=nil;dirty(id);return end
      r.last_tick=tick
      -- Stock clear_cmd.cpp UpdateFences and the ordinary CLEAR_FIELDS
      -- TileLoop_Clear. Same physical landscape revisit as any tile.
      local stride=Sim.W
      edge(r,id,id+1,x+1,z,2);edge(r,id,id+stride,x,z+1,1)
      edge(r,id,id-1,x-1,z,0);edge(r,id,id-stride,x,z-1,3)
      if editor then return end
      if r.counter<7 then r.counter=r.counter+1;return end
      r.counter=0
      local producers=opts.industries or s.stock_farm_industries
      local producer=producers and producers[r.industry]
      if not producer or producer.removed then r.industry=nil end
      if r.industry==nil and r.variant>=7 then
        records[id]=nil
        s.tiles[id].stock_clear_ground=nil
        -- RC1 MakeClear(Grass, 2): the ordinary counter reaches density
        -- 3 eight visits later. Store only active regrowth, not each tile.
        if not regrowth then regrowth={};s.stock_farm_grass=regrowth end
        regrowth[id]=0
      else r.variant=(r.variant+1)%9 end
      dirty(id)
    end
    return b
  end

  function W.field(s,id)
    local r=s.stock_farm_fields and s.stock_farm_fields[id]
    local t=valid_id(id) and s.tiles[id]
    if not r or not t or t.stock_void or occupied(s,id,t,true,true) then return end
    local x,z=Sim.xy(id)
    if Terrain.matches(s.corner_grid,x,z,r.slope,r.base) then return r end
  end

  local function writes(s,plans,random_u32,generation)
    if type(random_u32)~="function" then return nil,"SHARED_INDUSTRY_RNG_REQUIRED" end
    local start=s.next_stock_farm_industry or W.INDUSTRY_ID_BASE
    if type(start)~="number" or start%1~=0 or start<W.INDUSTRY_ID_BASE or
        start+#plans>W.INDUSTRY_ID_LIMIT then return nil,"FARM_INDUSTRY_IDS_EXHAUSTED" end
    local dirty,records,site_start={},{},#s.sites+1
    -- No mutation until IDs and both source records are ready.
    for k,p in ipairs(plans) do
      local id=start+k-1
      if s.stock_coal_industries and s.stock_coal_industries[id] or
          s.stock_timber_industries and s.stock_timber_industries[id] or
          s.stock_farm_industries and s.stock_farm_industries[id] then return nil,"INDUSTRY_ID_COLLISION" end
    end
    local function rnd() return random_u32(s) end
    for k,p in ipairs(plans) do
      local id=start+k-1
      local style=styles[p.kind]
      local ind=generation and generation.record or Rules.new(p.kind,id,p.x-1,p.z-1,{layout=p.layout,completed=true,
        original=s.stock_original_industry_economy~=false,generating_world=true,random_u32=rnd,economy_year=Sim.date(s)})
      if generation then
        assert(#plans==1 and ind.kind==p.kind and ind.x==p.x-1 and ind.z==p.z-1 and #ind.tiles==#p.cells)
        for i,cell in ipairs(ind.tiles) do
          local q=p.cells[i]
          assert(cell.x==ind.x+q.x and cell.z==ind.z+q.z and cell.gfx==q.gfx,
            "Generated farm/factory must match the native art footprint")
        end
        ind.id=id
      end
      local sid=site_start+k-1
      ind.site=sid
      local site={id=sid,tile=p.origin,name=generation and generation.name or style.name,kind=style.kind,produced={},received={},stock={},
        service=0,stock_industry=id,industry_chain="farm"}
      records[k]={ind=ind,site=site,p=p,style=style}
      for _,cell in ipairs(p.cells) do dirty[#dirty+1]=cell.id end
    end
    s.stock_farm_industries=s.stock_farm_industries or {}
    for _,r in ipairs(records) do
      s.stock_farm_industries[r.ind.id]=r.ind
      s.sites[r.site.id]=r.site
      for _,cell in ipairs(r.p.cells) do
        local t=s.tiles[cell.id]
        t.stock_industry={id=r.ind.id,chain="farm",kind=r.ind.kind,layout=r.p.layout,
          style=r.p.layout==0 and r.style.art or r.style.art.."_l"..r.p.layout,x=cell.x,z=cell.z,gfx=cell.gfx,site=r.site.id,origin=r.p.origin}
        if cell.id==r.p.origin then t.site=r.site.id end
      end
    end
    s.topology=s.topology+1
    s.next_stock_farm_industry=start+#plans
    local fields=W.field_board(s)
    for _,r in ipairs(records) do
      if r.ind.kind=="farm" then Fields.on_built(r.ind,fields,rnd) end
    end
    return records,dirty
  end
  function W.commit(s,p,random_u32)
    if not same(s,p) then return nil,"STALE_INDUSTRY_QUOTE" end
    local q,why,id=W.quote(s,p.kind,p.origin,nil,p.layout)
    if not q then return nil,why,id end
    if not matches(q,p) then return nil,"STALE_INDUSTRY_QUOTE" end
    local r,dirty=writes(s,{q},random_u32)
    if not r then return nil,dirty end
    return r[1].ind,dirty,r[1].site
  end
  function W.place_generated(s,kind,origin,opts,rng)
    assert(opts and opts.record and type(opts.name)=="string")
    local q,why,id=W.quote(s,kind,origin,true,opts.record.layout)
    if not q then return nil,why,id end
    local r,dirty=writes(s,{q},rng or Sim.stock_random_u32,opts)
    if not r then return nil,dirty end
    return r[1].ind,q.cells,r[1].site
  end
  function W.commit_pair(s,p,random_u32)
    if not (same(s,p) and p.kind=="pair" and type(p.farm)=="table" and type(p.factory)=="table") then
      return nil,"STALE_INDUSTRY_QUOTE"
    end
    local q,why,id=W.quote_pair(s,p.farm.origin,p.factory.origin)
    if not q then return nil,why,id end
    if not matches(q.farm,p.farm) or not matches(q.factory,p.factory) then return nil,"STALE_INDUSTRY_QUOTE" end
    local r,dirty=writes(s,{q.farm,q.factory},random_u32)
    if not r then return nil,dirty end
    return {farm=r[1].ind.id,factory=r[2].ind.id,farm_site=r[1].site.id,factory_site=r[2].site.id,tiles=dirty}
  end
  function W.seed(s,farm,factory,random_u32)
    local p,why,id=W.quote_pair(s,farm,factory)
    if not p then return nil,why,id end
    return W.commit_pair(s,p,random_u32)
  end
  function W.record(s,id)
    local t=valid_id(id) and s.tiles[id]
    local ref=t and t.stock_industry
    if ref and ref.chain=="farm" then
      return ref,s.stock_farm_industries and s.stock_farm_industries[ref.id]
    end
  end
  function W.protected(s,id) return W.record(s,id)~=nil end
  function W.sweep_closed(s)
    local dirty={}
    for _,i in pairs(s.stock_farm_industries or {}) do
      local site=s.sites[i.site]
      if i.removed and site and not site.closed then
        site.closed=true
        for _,p in ipairs(i.tiles) do
          local id=Sim.id(p.x+1,p.z+1)
          local t=id and s.tiles[id]
          if t and t.stock_industry and t.stock_industry.chain=="farm" and t.stock_industry.id==i.id then
            t.stock_industry=nil
            if t.site==site.id then t.site=nil end
            dirty[#dirty+1]=id
          end
        end
      end
    end
    table.sort(dirty)
    if #dirty>0 then s.topology=s.topology+1 end
    return dirty
  end
  function W.scenario_1751(s)
    if s.seed~=1751 then return nil,"FARM_SCENARIO_REQUIRES_SEED_1751" end
    local id=Sim.id
    return {
      farm=id(12,1),factory=id(15,16),farm_stop=id(13,4),factory_stop=id(19,17),
      factory_intake=id(18,17),goods_stop=id(14,8),depot=id(11,12),
      road_waypoints={
        {id(11,4),id(16,4),id(16,7),id(15,7),id(15,8),id(12,8),id(12,14),id(13,14),id(13,15),id(19,15),id(19,20)},
        {id(11,4),id(11,5),id(16,5)},
        {id(15,8),id(15,12),id(12,12)},
        {id(19,15),id(20,15),id(20,20),id(19,20)},
      },
    }
  end
  function W.check_catchments(s,scene)
    local fx,fz=Sim.xy(scene.farm)
    local ix,iz=Sim.xy(scene.factory)
    local farm=Rules.new("farm",0,fx-1,fz-1)
    local factory=Rules.new("factory",1,ix-1,iz-1)
    local function station(i)
      local x,z=Sim.xy(i)
      local p={id=i,x=x-1,z=z-1,tiles={{x=x-1,y=z-1,kind="truck"}}}
      return p,Catchment.build(p,Sim.W,Sim.H,s.stock_modified_catchment)
    end
    local a,ca=station(scene.farm_stop)
    local covered=false
    for _,t in ipairs(farm.tiles) do
      if Catchment.contains(ca,t.x,t.z) then covered=true;break end
    end
    if not covered then return nil,"FARM_STOP_OUTSIDE_CATCHMENT" end
    local b,cb=station(scene.factory_stop)
    if not Rules.acceptance(b,cb,"grain",{factory}).accepts or not Rules.acceptance(b,cb,"livestock",{factory}).accepts then
      return nil,"FACTORY_STOP_OUTSIDE_CATCHMENT"
    end
    local function house_at(x,z)
      local p=Sim.id(x+1,z+1)
      local t=p and s.tiles[p]
      return t and t.house and t.source_house
    end
    local g,cg=station(scene.goods_stop)
    local goods=Rules.acceptance(g,cg,"goods",{},house_at)
    if not goods.accepts then return nil,"TOWN_GOODS_REQUIRES_STOCK_HOUSE_LAYOUT" end
    return goods
  end
  function W.default_1751(s,random_u32)
    local p,why=W.scenario_1751(s)
    if not p then return nil,why end
    local routes,reason=W.check_catchments(s,p)
    if not routes then return nil,reason end
    local result,code,id=W.seed(s,p.farm,p.factory,random_u32)
    if result then s.stock_farm_scenario="seed_1751" end
    return result,code,id
  end
  return W
end
