-- SPDX-License-Identifier: GPL-2.0-only
-- Vanilla RC1 industry_cmd.cpp: MakeIndustryTileBigger, TileLoop_Industry,
-- ProduceIndustryGoods and the monthly production roll. Pregame runs only
-- the tile visits; the isolated Frozen lane also runs the live phases.
return function(Sim,Terrain,s,live_frozen)
  local dir=(core and core.get_modpath and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  local function o(n)return dofile(dir.."openttd/"..n..".lua")end
  local Rules,Layout=o("industry_machinery_rc1"),o("stock_industry_layouts_rc1")
  local Commons=o("coal_industry")()
  local Fields=o("farm_factory_fields")(Commons)
  local Specs=o("industry_spec_rc1")
  local Anim=o("world_animation_rc1")
  local hub=s.stock_world_animations
  local by_spec={}
  local FieldWorld=dofile(dir.."farm_factory_world.lua")(Sim,Terrain,nil,Fields)
  local records,by_id={},{}
  for _,firm in ipairs(assert(s.stock_worldgen_climate_firms)) do
    by_id[firm.id]=firm
    by_spec[firm.id]=assert(Specs.get(firm.type,s.stock_climate.landscape))
    for _,tile in ipairs(firm.cells) do records[Sim.id(tile.x+1,tile.z+1)]={tile,firm} end
  end
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
  if live_frozen then
    assert(not next(s.companies) and not next(s.stations) and not next(s.fleet),
      "The no-company climate comparison does not settle player freight")
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
  local tropic=s.stock_climate.landscape=="tropic"
  local Climate=tropic and o("town_climate_landscape_rc1")
  local ground_name={[0]="grass","rough","rocks","fields",[5]="desert"}
  local ground_code={rocks=2,desert=5}
  local function valid(id) local t=s.tiles[id];return t and not t.stock_void end
  local function desert(id) return s.tiles[id].stock_tropic_zone==Climate.DESERT end
  local function sea(id)
    local t=s.tiles[id]
    return t.water_class=="sea" and not t.coastal_water
  end
  if tropic then
    -- clear_cmd.cpp restores desert by physical tile visit, not at
    -- demolition time. Farm eligibility reads the physical ground.
    function M.clear(id)
      local t=s.tiles[id]
      if not t or t.stock_void or t.wood or t.house or t.stock_industry or t.terrain=="water"
          or t.build or t.stock_landmark or t.owner or t.site or t.station or t.rail_tracks
          or t.tram or t.ship or t.airfield or t.road_bridge_id or t.road_tunnel_id then return end
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
  end
  local fields=live_frozen and Field.field_board(s)
  function M.landscape(x,z,tick)
    local id=Sim.id(x+1,z+1)
    if records[id] then return M.visit(id,tick) end
    if M.clear then M.clear(id) end
    if (s.stock_farm_fields and s.stock_farm_fields[id]) or (s.stock_farm_grass and s.stock_farm_grass[id]~=nil) then
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
  function M.month()
    for _,firm in ipairs(s.stock_worldgen_climate_firms) do
      for _,p in ipairs(firm.produced) do
        p.last_production,p.current_production=p.current_production or 0,0
      end
    end
  end
  local function reset_stage(t)
    t.completed,t.stage,t.construction_counter=false,0,0
  end
  function M.visit(id,tick)
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
    if live_frozen then
      -- TransportIndustryGoods consumes the completed tile's lot even
      -- if there are no collecting stations; only transported stays 0.
      local min=by_spec[firm.id].minimum
      for _,p in ipairs(firm.produced) do
        local lot=math.min(p.waiting,255)
        if lot>min then
          p.waiting=p.waiting-lot
          p.current_production=((p.current_production or 0)+lot)%65536
        end
      end
    end
    random() -- TriggerIndustryTileAnimation(TileLoop)
    local next=Layout.anim_next[t.gfx]
    if next~=nil then reset_stage(t);t.gfx=next;return true end
    local g,f,a=t.gfx,t.animation_frame,t.animated
    local changed,_,fx=Rules.visit(t,tick,random,firm)
    update_registration(id,t,a)
    if fx and fx.effect=="bubble" and spawn_bubble then spawn_bubble(t.x,t.z,fx.direction) end
    if fx and not live_frozen then
      M.events=M.events or {}
      M.events[#M.events+1]={id=id,tick=tick,effect=fx.effect,direction=fx.direction}
    end
    return changed or t.gfx~=g or t.animation_frame~=f or t.animated~=a
  end
  return M,Field
end
