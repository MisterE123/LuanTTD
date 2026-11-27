-- SPDX-License-Identifier: GPL-2.0-only
-- Mutable host for the stock 16.0-RC1 IndustryBuildData scheduler.
-- Mounted in the authority VM only; follows the existing verified land
-- industry adapters, including their available physical mesh layouts.
return function(Sim,mod,s,adapters,Industry,ctx)
  local source=mod.."/openttd/"
  local Schedule=dofile(source.."industry_build_scheduler.lua")
  local Rig=dofile(source.."oil_rig.lua")
  local init=dofile(source.."industry_gameplay_construction.lua")
  local Terrain=ctx.terrain
  local view={width=Sim.W,height=Sim.H,freeform=s.corner_grid.freeform_edges,towns={}}
  local stock={
    [0]={kind="coal_mine",chain="coal",prob=2},
    [1]={kind="power_station",chain="coal",prob=2},
    [2]={kind="sawmill",chain="timber",prob=2},
    [3]={kind="forest",chain="timber",prob=3},
    [4]={kind="oil_refinery",chain="oil",prob=2},
    [5]={kind="oil_rig",chain="oil",prob=6},
    [6]={kind="factory",chain="farm",prob=2},
    [8]={kind="steel_mill",chain="heavy",prob=2},
    [9]={kind="farm",chain="farm",prob=2},
    [11]={kind="oil_well",chain="oil",prob=0},
    [12]={kind="temperate_bank",chain="bank",prob=7},
    [18]={kind="iron_mine",chain="heavy",prob=2},
  }
  local by_kind={}
  for id,row in pairs(stock) do by_kind[row.kind]=id end
  local chains={"coal","timber","oil","farm","heavy","bank"}
  local function contents()
    local counts,ordered,desc,global={},{},{},{}
    for _,chain in ipairs(chains) do
      for _,f in pairs(s["stock_"..chain.."_industries"] or {}) do
        local id=by_kind[f.kind]
        if id and not f.removed then
          counts[id]=(counts[id] or 0)+1
          ordered[#ordered+1]=f
          global[f]=ctx.industry_id and ctx.industry_id(chain,f.id) or nil
          desc[#desc+1]={type=id,x=f.x,z=f.z,town=f.town}
        end
      end
    end
    table.sort(ordered,function(a,b)
      local x,y=global[a],global[b]
      if x~=nil and y~=nil then return x<y end
      if x~=nil then return true end
      if y~=nil then return false end
      return a.id<b.id
    end)
    return counts,ordered,desc
  end
  local function refresh_towns()
    view.towns={}
    for _,site in ipairs(s.sites) do
      if site.kind=="town" then
        local x,z=Sim.xy(site.tile)
        view.towns[#view.towns+1]={id=site.id,x=x-1,z=z-1}
      end
    end
  end
  function view.tile(x,z)
    local id=Sim.id(x+1,z+1)
    local t=id and s.tiles[id]
    if not t or t.stock_void then return {kind="void"} end
    local slope,base=Terrain.tile(s.corner_grid,x+1,z+1)
    local occupied=t.site or t.house or t.build or t.rail_tracks or t.tram or t.ship or t.airfield or t.stock_industry
      or t.stock_landmark or t.road_tunnel_id or t.rail_tunnel_below
    local kind=occupied and "occupied" or t.terrain=="water" and "water" or t.wood and "trees" or "clear"
    return {kind=kind,owner=t.owner,slope=slope,base=base,
      corner_height=Terrain.corner(s.corner_grid,x+1,z+1),water_ground=t.terrain=="water",
      bridge=s.bridge_above and s.bridge_above[id] or s.rail_bridge_above and s.rail_bridge_above[id]
        or s.aqueduct_above and s.aqueduct_above[id]}
  end
  local function random() return Sim.stock_random_u32(s) end
  local rng=ctx.random or random -- exact injected raw stream in fixed-source tests
  local counts,ordered,desc=contents()
  local state=s.stock_industry_builder or Schedule.reset(240,#ordered)
  s.stock_industry_builder=state
  local opened
  local function add(f,cells)
    opened=true
    s.changed=s.changed or {}
    for _,cell in ipairs(cells) do
      local id=type(cell)=="table" and cell.id or cell
      if id then s.changed[#s.changed+1]=id end
    end
    if ctx.placed then ctx.placed(stock[by_kind[f.kind]].chain,f.id) end
    if ctx.advertise then ctx.advertise(f) end
    return f
  end
  local function active(id)
    local row=stock[id]
    if not row then return false end
    return id==5 and adapters.oil and adapters.oil.offshore or
      id~=5 and adapters[row.chain] and (id==12 or Industry.specs[id]~=nil)
  end
  local function construct(id,x,z,variant,seed,seed_bits)
    local row=stock[id]
    local name=Sim.id(x+1,z+1)
    if not name then return end
    if id==5 then
      local world=adapters.oil.offshore
      local o={economy_year=Sim.date(s),multiple_per_town=s.stock_multiple_industry_per_town,
        vehicle_on_ground=ctx.vehicle_on_ground,oil_refinery_limit=s.stock_oil_refinery_limit,random=rng,
        opening_seed_bits=seed_bits, original=s.stock_industry_original_economy==true}
      local q=world.quote(s,name,o)
      if not q then return end
      o.name=s.sites[q.town].name.." Oil Rig"
      local f,cells=world.place(s,q,o)
      if not f then return end
      s.road_oil=true
      return add(f,cells)
    end
    if id==12 then
      local b=adapters.bank
      local q=b.plan(s,name)
      if not q then return end
      local f,cells=b.execute(s,nil,name,q,{seed_bits=seed_bits,random=rng,original=s.stock_industry_original_economy==true})
      if not f then return end
      return add(f,cells)
    end
    local row_spec=Industry.specs[id]
    if not row_spec then return end
    local plan=Industry.quote(view,id,x,z,variant,{terragenesis=false,
      oil_refinery_limit=s.stock_oil_refinery_limit,multiple_per_town=s.stock_multiple_industry_per_town},desc)
    if not plan then return end
    local kernel=row_spec.kernel or ctx.coal
    local f=kernel.new(row.kind,0,x,z,{layout=variant,original=true,completed=false,economy_year=Sim.date(s)})
    -- Existing native asset coverage restricts the selected variants and
    -- rejects non-flat runtime landscapes the engine would also refuse.
    local town=s.sites[plan.town]
    f.town=town.id
    local proposed={record=f,name=town.name.." "..plan.name}
    local old={}
    for _,cell in ipairs(plan.cells) do
      local k=Sim.id(cell.x+1,cell.z+1)
      local t=s.tiles[k]
      if t.wood then old[k]=t.wood;t.wood=nil end
    end
    local w=adapters[row.chain]
    local placed,cells
    if row.chain=="coal" then placed,cells=w.place(s,row.kind,name,proposed)
    else placed,cells=w.place_generated(s,row.kind,name,proposed,rng) end
    if not placed then for k,wood in pairs(old) do s.tiles[k].wood=wood end;return end
    init(placed,seed_bits,rng,s.stock_industry_original_economy==true)
    s["road_"..row.chain]=true
    for _,c in ipairs(cells) do
      local t=s.tiles[c.id]
      t.stock_clear_ground=nil
    end
    return add(placed,cells)
  end
  local last_month
  -- The authority will invoke daily opening on the real date tick,
  -- then apply its monthly quotas before each industry rolls production.
  -- Old direct harnesses may call both phases together.
  return function(phase)
    assert(phase==nil or phase=="day" or phase=="month")
    opened=false
    counts,ordered,desc=contents()
    local year,month,day=Sim.date(s)
    local ordinal=year*12+month
    local api={width=Sim.W,height=Sim.H,random=rng,
      funded_only=ctx.density==0,recession=s.stock_recession==true,
      total=function() return #ordered end,count=function(id) return counts[id] or 0 end}
    function api.available(id)
      if api.funded_only or not active(id) then return 0,0 end
      if id==5 then return Rig.weight("random",{year=year}),0 end
      return stock[id].prob,0
    end
    function api.layout_count(id)
      if id==5 or id==12 then return 1 end
      return #Industry.specs[id].layout+1
    end
    function api.place(id)
      refresh_towns()
      api.create=construct
      local industry=Schedule.place_attempts(api,id,false)
      if industry then counts,ordered,desc=contents() end
      return industry
    end
    function api.change_random_industry()
      if #ordered==0 then return end
      local firm=ordered[1+math.floor(rng()*#ordered/4294967296)]
      -- Smooth production is processed by the existing monthly currency
      -- and industry clock. Only the source Original setting changes it
      -- on this daily branch.
      if s.stock_industry_original_economy==true and ctx.change then ctx.change(firm,year) end
    end
    -- TimerGameEconomy::IncreaseDate dispatches Day before Month
    -- even when both fire at the same date boundary.
    if phase~="month" and state.last_economy_day~=s.day then
      state.last_economy_day=s.day
      Schedule.day(state,api)
    end
    if phase~="day" and day==1 and state.month~=ordinal and ordinal~=last_month then
      last_month,state.month=ordinal,ordinal
      Schedule.month(state,api)
    end
    return opened
  end
end
