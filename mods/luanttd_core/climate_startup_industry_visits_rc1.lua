-- SPDX-License-Identifier: GPL-2.0-only
-- Vanilla RC1 industry_cmd.cpp: MakeIndustryTileBigger, TileLoop_Industry,
-- ProduceIndustryGoods and the monthly production roll. Pregame runs only
-- the tile visits; the isolated climate lane also runs the live phases.
return function(Sim,Terrain,s,live_economy,town_runtime)
  local live=live_economy~=nil
  local dir=(core and core.get_modpath and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  local function o(n)return dofile(dir.."openttd/"..n..".lua")end
  local Rules,Layout=o("industry_machinery_rc1"),o("stock_industry_layouts_rc1")
  local Commons=o("coal_industry")()
  local Fields=o("farm_factory_fields")(Commons)
  local Specs=o("industry_spec_rc1")
  local Anim=o("world_animation_rc1")
  local Change=live and o("industry_production_change_rc1")
  local hub=s.stock_world_animations
  local by_spec={}
  local FieldWorld=dofile(dir.."farm_factory_world.lua")(Sim,Terrain,nil,Fields)
  local records,by_id={},{}
  local function index_firm(firm)
    by_id[firm.id]=firm
    by_spec[firm.id]=assert(Specs.get(firm.type,s.stock_climate.landscape))
    for _,tile in ipairs(firm.cells) do records[Sim.id(tile.x+1,tile.z+1)]={tile,firm} end
  end
  for _,firm in ipairs(assert(s.stock_worldgen_climate_firms)) do index_firm(firm) end
  local Field={}
  function Field.field_board(state) return FieldWorld.field_board(state,{industries=by_id,exact_grid=true}) end
  function Field.field(state,id) return FieldWorld.field(state,id) end
  local M={}
  local function random() return Sim.stock_random_u32(s) end
  local function update_registration(id,t,was)
    if not hub then return end
    if t.animated then Anim.add(hub,id,"industry")
    elseif was then Anim.delete(hub,id,false) end
  end
  if live then
    local tropic_freight=s.stock_climate.landscape=="tropic"
    for _,v in pairs(s.fleet) do
      assert((v.stock_bus or v.stock_regal) and v.cargo=="passenger"
        or tropic_freight and v.stock_road_freight and
          (v.cargo=="water" or v.cargo=="food" or v.cargo=="fruit" or v.cargo=="maize"),
        "Unsupported vehicle in the climate industry authority")
    end
    for _,st in pairs(s.stations) do
      assert(st.mode=="road" and (Sim.road_stop_has(st,"bus") or tropic_freight and Sim.road_stop_has(st,"truck")),
        "Unsupported station in the climate industry authority")
    end
    assert(live_economy=="frozen" or live_economy=="smooth","Choose a supported climate economy")
    if live_economy~="frozen" then
      local start=Sim.date(s)
      for _,firm in ipairs(s.stock_worldgen_climate_firms) do firm.created_year=firm.created_year or start end
    end
  end
  local Bubble=s.stock_climate.landscape=="toyland" and o("bubble_effect_rc1")
  local spawn_bubble
  if Bubble then
    local Slope=o("slope")
    s.stock_climate_bubbles=s.stock_climate_bubbles or {}
    local pool=s.stock_climate_bubbles
    local function height(x,z)
      x=math.max(0,math.min(x,(Sim.W-1)*16))
      z=math.max(0,math.min(z,(Sim.H-1)*16))
      local u,v=math.floor(x/16)+1,math.floor(z/16)+1
      local slope,base,highest=Terrain.tile(s.corner_grid,u,v)
      local cell=s.tiles[Sim.id(u,v)]
      if cell and (cell.stock_industry or cell.house) then
        return highest*8
      end
      return base*8+Slope.pixel(x%16,z%16,slope)
    end
    spawn_bubble=function(x,z,direction)
      local id=0
      while pool[id] do id=id+1 end
      pool[id]=Bubble.new(x,z,direction,height)
    end
    local function catcher(x,z)
      local id=Sim.id(x+1,z+1)
      local r=records[id]
      if r and r[1].gfx==Rules.BUBBLE_CATCHER then
        r[1].animated=true
        update_registration(id,r[1],false)
      end
    end
    function M.effects()
      local order={}
      for id in pairs(pool) do order[#order+1]=id end
      table.sort(order)
      for _,id in ipairs(order) do
        if not Bubble.tick(pool[id],random,catcher) then pool[id]=nil end
      end
    end
  end
  local tropic,arctic=s.stock_climate.landscape=="tropic",s.stock_climate.landscape=="arctic"
  local Climate=(tropic or arctic) and o("town_climate_landscape_rc1")
  local ground_name={[0]="grass","rough","rocks","fields",[5]="desert"}
  local ground_code={rocks=2,desert=5}
  local function valid(id) local t=s.tiles[id];return t and not t.stock_void end
  local function desert(id) return s.tiles[id].stock_tropic_zone==Climate.DESERT end
  local function sea(id)
    local t=s.tiles[id]
    return t.water_class=="sea" and not t.coastal_water
  end
  local function clear_surface(t)
    return t and not (t.stock_void or t.wood or t.house or t.stock_industry or t.terrain=="water"
          or t.build or t.stock_landmark or t.owner or t.site or t.station or t.rail_tracks
          or t.tram or t.ship or t.airfield or t.road_bridge_id or t.road_tunnel_id)
  end
  if tropic then
    -- clear_cmd.cpp restores desert by physical tile visit, not at
    -- demolition time. Farm eligibility reads the physical ground.
    function M.clear(id)
      local t=s.tiles[id]
      if not clear_surface(t) then return end
      local plots=s.stock_farm_fields
      local ground=plots and plots[id] and "fields" or ground_name[t.stock_clear_ground or 0]
      if t.stock_tropic_zone~=Climate.DESERT and ground~="desert" and ground~="rocks" then return end
      local cover,density=Climate.clear_desert(ground,t.stock_clear_density or 3,t.stock_tropic_zone,function()
        return Climate.normal_neighbor(Sim.W,id,valid,desert,sea)
      end)
      if not cover then return end
      t.stock_clear_ground=ground_code[cover]
      t.stock_clear_density,t.stock_clear_visits=density~=3 and density or nil,nil
      if plots then plots[id]=nil end
      if s.stock_farm_grass then s.stock_farm_grass[id]=nil end
    end
  elseif arctic then
    function M.clear(id)
      local t=s.tiles[id]
      if not clear_surface(t) then return end
      local x,z=Sim.xy(id)
      local _,base=Terrain.tile(s.corner_grid,x,z)
      local action,density=Climate.clear_snow(base,s.stock_climate.snowline,t.stock_arctic_snow~=nil,t.stock_arctic_snow)
      if action then t.stock_arctic_snow=density end
    end
  end
  local fields=live and Field.field_board(s)
  local market,market_api,Scheduler
  if live then
    Scheduler=o("industry_build_scheduler")
    local firms=s.stock_worldgen_climate_firms
    market=s.stock_climate_market or Scheduler.reset(37,#firms)
    s.stock_climate_market=market
    market_api={width=Sim.W,height=Sim.H,random=random,total=function() return #firms end}
    local climate=s.stock_climate.landscape
    local slot=assert(({temperate=1,arctic=2,tropic=3,toyland=4})[climate])
    function market_api.count(kind)
      local n=0
      for _,firm in ipairs(firms) do if firm.type==kind then n=n+1 end end
      return n
    end
    function market_api.available(kind)
      local spec=Specs.get(kind,climate)
      if not spec or not Layout[kind] then return 0,0 end
      local year=market_api.year
      local flags=spec.behavior
      if flags.Before1950 and year>1950 or flags.After1960 and year<1960 then return 0,0 end
      local probability=spec.appearance[slot]
      return probability,probability>0 and flags.CanCloseLastInstance and 1 or 0
    end
    local Builder=dofile(dir.."generated_climate_industry_phase_rc1.lua")(Sim,Terrain,random)
    function market_api.place(kind)
      local firm=Builder.open(s,kind,{town_runtime=town_runtime,original=live_economy=="original"})
      if firm then
        index_firm(firm)
        s.topology=s.topology+1
      end
      return firm
    end
    M.open=market_api.place
    function market_api.change_random_industry()
      if #firms==0 then return end
      local firm=firms[1+math.floor(random()*#firms/4294967296)]
      Change.change(firm,by_spec[firm.id],climate,live_economy,false,market_api.year,random,market_api.count(firm.type))
    end
    function M.day(year)
      market_api.year=year
      Scheduler.day(market,market_api)
    end
  end
  function M.landscape(x,z,tick,offer)
    local id=Sim.id(x+1,z+1)
    if records[id] then return M.visit(id,tick,offer) end
    if M.clear then M.clear(id) end
    if s.tiles[id].stock_arctic_snow==nil and ((s.stock_farm_fields and s.stock_farm_fields[id])
       or (s.stock_farm_grass and s.stock_farm_grass[id]~=nil)) then
      fields.visit(x,z,tick,false,id)
    end
  end
  function M.frame(id,tick)
    local r=records[id]
    if not r then return false end
    Rules.animate(r[1],tick,random)
    return not not r[1].animated
  end
  function M.produce()
    for _,firm in ipairs(s.stock_worldgen_climate_firms) do
      if firm.counter%64==0 then random() end -- unconditional ambient lottery input
      firm.counter=(firm.counter-1)%65536
      if firm.counter%256==0 then
        for _,p in ipairs(firm.produced) do
          p.waiting=math.min(65535,p.waiting+Commons.scale(p.rate,s.stock_cargo_scale_percent,random))
        end
        if by_spec[firm.id].behavior.PlantFields and Commons.chance(8,random()) then Fields.random(firm,fields,random) end
        random() -- TriggerIndustryAnimation(IndustryTick)
      end
    end
  end
  -- Industry::~Industry and MakeWaterKeepingClass for dry buildings.
  -- The test authority has no stations, so no catchment/packet graph
  -- owns these rows. Their pool slot becomes available only on removal.
  local function finish_closure(firm)
    for _,c in ipairs(firm.cells) do
      local id=assert(Sim.id(c.x+1,c.z+1))
      local t=s.tiles[id]
      if t.stock_industry and t.stock_industry.id==firm.id then
        assert(t.terrain~="water","Native water-class restoration needs a wet closure case")
        t.stock_industry=nil
        records[id]=nil
        Anim.delete(hub,id,false)
        Sim.mark_clear_land(s,id)
      end
    end
    if by_spec[firm.id].behavior.PlantFields then
      for id,plot in pairs(s.stock_farm_fields or {}) do
        if plot.industry==firm.id then
          local x,z=Sim.xy(id)
          x,z=x-1,z-1
          if x>=firm.x-21 and x<firm.x+21 and z>=firm.z-21 and z<firm.z+21 then plot.industry=nil end
        end
      end
    end
    by_id[firm.id],by_spec[firm.id]=nil,nil
    s.topology=s.topology+1
  end
  function M.month(year)
    if market then Scheduler.month(market,market_api) end
    local firms=s.stock_worldgen_climate_firms
    local count={}
    for _,firm in ipairs(firms) do count[firm.type]=(count[firm.type] or 0)+1 end
    local i=1
    while i<=#firms do
      local firm=firms[i]
      Change.roll(firm,year)
      if firm.prod_level==0 then
        finish_closure(firm)
        table.remove(firms,i)
        count[firm.type]=count[firm.type]-1
      else
        Change.change(firm,by_spec[firm.id],s.stock_climate.landscape,live_economy,true,year,random,count[firm.type])
        i=i+1
      end
    end
  end
  local function reset_stage(t)
    t.completed,t.stage,t.construction_counter=false,0,0
  end
  function M.visit(id,tick,offer)
    local r=records[id]
    if not r then return false end
    local t,firm=r[1],r[2]
    if not t.completed then
      local count=t.construction_counter+1
      if count~=4 then t.construction_counter=count;return false end
      t.stage,t.construction_counter=t.stage+1,0
      random() -- TriggerIndustryTileAnimation_ConstructionStageChanged
      if t.stage==3 then
        t.completed=true
        if t.gfx==8 then
          -- A fresh unplayed map has room for this puff. Its sprite phase
          -- consumes one word even though the controlled board has no art.
          t.stock_chimney_start=random()
        elseif t.gfx==Rules.TOY_FACTORY or t.gfx==Rules.BUBBLE_CATCHER or t.gfx==Rules.TOFFEE then
          t.animation_frame,t.animation_loop=0,0
        elseif t.gfx>=Rules.PLASTIC_FIRST and t.gfx<=Rules.PLASTIC_LAST then
          t.animated=true
          update_registration(id,t,false)
        end
      end
      return true
    end
    if live then
      -- TransportIndustryGoods consumes the completed tile's lot even
      -- if there are no collecting stations.
      local min=by_spec[firm.id].minimum
      local moved=false
      for _,p in ipairs(firm.produced) do
        local lot=math.min(p.waiting,255)
        if lot>min then
          p.waiting=p.waiting-lot
          local amount=s.stock_recession and math.floor((lot+1)/2) or lot
          p.current_production=((p.current_production or 0)+amount)%65536
          if offer and p.cargo then
            local units=offer(firm.id,p.cargo,amount)
            p.current_transported=((p.current_transported or 0)+units)%65536
            moved=moved or units>0
          end
        end
      end
      if moved then
        random() -- TriggerIndustryAnimation(CargoDistributed)
        local gfx=Layout.anim_production[t.gfx]
        if gfx then t.gfx,t.stage,t.construction_counter=gfx,0,0;return true end
      end
    end
    random() -- TriggerIndustryTileAnimation(TileLoop)
    local next=Layout.anim_next[t.gfx]
    if next~=nil then reset_stage(t);t.gfx=next;return true end
    local g,f,a=t.gfx,t.animation_frame,t.animated
    local changed,_,fx=Rules.visit(t,tick,random,firm)
    update_registration(id,t,a)
    if fx and fx.effect=="bubble" and spawn_bubble then spawn_bubble(t.x,t.z,fx.direction) end
    if fx and not live then
      M.events=M.events or {}
      M.events[#M.events+1]={id=id,tick=tick,effect=fx.effect,direction=fx.direction}
    end
    return changed or t.gfx~=g or t.animation_frame~=f or t.animated~=a
  end
  return M,Field
end
