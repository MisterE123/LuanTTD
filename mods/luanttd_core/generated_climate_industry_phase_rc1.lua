-- SPDX-License-Identifier: GPL-2.0-only
-- Headless stock industry construction for generated and economy sites.
-- The host owns renderer, company authorization, and station callbacks.
return function(Sim,Terrain,random_next)
  local dir=(core and core.get_modpath and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  local function stock(n)return dofile(dir.."openttd/"..n..".lua") end
  local Schedule,Specs,Layout=stock("industry_generation_schedule_rc1"),stock("industry_spec_rc1"),stock("stock_industry_layouts_rc1")
  local Admission,Init=stock("industry_admission_rc1"),stock("industry_initial_record_rc1")
  local Platform=stock("industry_platform_level")(Terrain)
  local common=stock("coal_industry")()
  local PlatformQuote=stock("industry_worldgen")(common)
  local Fields=stock("farm_factory_fields")(common)
  local FieldWorld=dofile(dir.."farm_factory_world.lua")(Sim,Terrain,nil,Fields)
  local floor,abs,max=math.floor,math.abs,math.max
  local M={}
  local function mount(s,options,generating)
    local p=assert(s.stock_generated_profile)
    assert(s.stock_climate and p.town_rng)
    local w,h=Sim.W,Sim.H
    local climate=s.stock_climate.landscape
    local corners=s.corner_grid
    local state=generating and {p.town_rng[1],p.town_rng[2]} or assert(s.passenger_rating_rng)
    local function random()return random_next(state)end
    local result={firms=generating and {} or assert(s.stock_worldgen_climate_firms),
      attempts={},selections={},failures={}}
    local by_id={}
    for _,firm in ipairs(result.firms) do by_id[firm.id]=firm end
    local board={width=w,height=h,initial_land_count=p.initial_land_count,freeform=corners.freeform_edges}
    local function id(x,z)
      return Sim.id(x+1,z+1)
    end
    local function town(i)
      return i and s.stock_town_growth.towns[i]
    end
    function board.town(x,z)
      local native=s.tiles[id(x,z)]
      local t=native and (native.source_house and town(native.source_house.town) or town(native.road_town))
      if not t then
        local d
        for _,i in ipairs(s.stock_town_growth.order) do
          local a=town(i)
          local length=abs(a.x-1-x)+abs(a.z-1-z)
          if not d or length<d or length==d and a.id<t.id then t,d=a,length end
        end
      end
      if t then return {id=t.id,x=t.x-1,z=t.z-1,population=t.population} end
    end
    function board.tile(x,z)
      local i=id(x,z)
      local t=i and s.tiles[i]
      if not t then return end
      if t.stock_void then return {kind="void",valid=false} end
      local slope,base=Terrain.tile(corners,x+1,z+1)
      local water=t.terrain=="water"
      local kind=water and "water" or t.stock_industry and "industry" or t.house and "house" or
        t.build and (t.build=="road" and "road" or "object") or t.wood and "trees" or "clear"
      return {kind=kind,valid=true,slope=slope,base=base,north=Terrain.corner(corners,x+1,z+1),
        corner_height=Terrain.corner(corners,x+1,z+1),house=not not t.house,zone=t.stock_tropic_zone,
        water=water,on_water=water,coast=not not t.coastal_water,owner=t.owner,bridge_above=Sim.bridge_deck_at(s,i)~=nil,
        protected=t.source_house and t.source_house.player_protected}
    end
    function board.clear(_,_,t,who)
      if t.kind=="clear" or t.kind=="trees" or t.kind=="house" and who=="town" and not t.protected or
          t.kind=="water" and t.coast then return true end
      return false,"FOOTPRINT_OCCUPIED"
    end
    function board.can_allocate()return #result.firms<64000 end
    local function terra_options()
      return {capture_stock_tops=true,void=function(x,z)return s.tiles[Sim.id(x,z)].stock_void end,
        validate_tile=function(_,x,z)
          local t=board.tile(x-1,z-1)
          return t and (t.kind=="clear" or t.kind=="trees" or t.coast) and not t.owner and not t.bridge_above and 0 or nil
        end}
    end
    function board.terraform_quote(x,z,raise)
      return Terrain.plan(corners,x+1,z+1,8,raise,terra_options())~=nil
    end
    function board.platform(x,z,layout,cells)
      local area,why=PlatformQuote.platform(board,x,z,layout,options)
      if not area then return nil,why end
      local receipt,shadow=Platform.plan(corners,area,terra_options)
      for _,c in ipairs(cells) do
        local slope,base=Terrain.tile(shadow,c.x+1,c.z+1)
        if slope~=0 or base~=area.level then return nil,"PLATFORM_NOT_LEVEL" end
      end
      return receipt
    end
    local function apply_platform(receipt)
      local ground={}
      for _,cmd in ipairs(receipt.commands) do
        for pass=0,1 do
          for _,t in ipairs(cmd.touched or {}) do
            local rocky=floor(random()*p.map_height_limit/4294967296)<=t.top
            if pass==1 then ground[Sim.id(t.x,t.z)]=not cmd.raise and rocky and 2 or nil end
          end
        end
      end
      assert(Platform.apply(corners,receipt))
      for _,t in ipairs(receipt.dirty) do
        local tid=Sim.id(t.x,t.z)
        local a=s.tiles[tid]
        local _,base=Terrain.tile(corners,t.x,t.z)
        a.h,a.terrain,a.wood,a.stock_clear_ground=base,base>0 and "hill" or "grass",nil,ground[tid]
        a.coastal_water,a.water_class,a.stock_water_rocks,a.stock_river_bits=nil,nil,nil,nil
        if s.stock_farm_fields then s.stock_farm_fields[tid]=nil end
      end
    end
    local quote_opts={landscape=climate,terragenesis=true,generating_world=generating,width=w,height=h,freeform=board.freeform,
      multiple=options.multiple,highest_snowline=s.stock_climate.snowline,oil_refinery_limit=options.oil_refinery_limit}
    local function place(type,water,forced)
      local spec=assert(Specs.get(type,climate))
      local plans=assert(Layout[type])
      for attempt=1,forced and 10000 or 2000 do
        local x,z,seed,bits,variant=Schedule.candidate(w,h,#plans+1,random)
        local q,why=Admission.quote(spec,plans[variant],Layout.slope_refused,x,z,board,quote_opts,result.firms)
        if q then
          local n=generating and #result.firms or 0
          while by_id[n]~=nil do n=n+1 end
          local firm={id=n,type=type,kind=type==24 and "maize_farm" or spec.kind,x=x,z=z,town=q.town,seed=seed,random=bits,layout=variant,cells=q.cells,
            width=1,height=1,prod_level=16,produced={},accepted={}}
          for _,c in ipairs(q.cells) do
            firm.width,firm.height=max(firm.width,c.x-x+1),max(firm.height,c.z-z+1)
          end
          -- Creation requires a proven platform only during initial
          -- TerraGenesis. Live placement attempts it after legal slopes
          -- are checked; an unavailable apron does not veto that site.
          local platform=q.platform or (not generating and board.platform(x,z,plans[variant],q.cells))
          if platform then apply_platform(platform) end
          firm.before_rng={state[1],state[2]}
          Init.draw(firm,spec,random,options.original,generating)
          firm.after_tiles_rng={state[1],state[2]}
          for i,c in ipairs(spec.produce) do
            if c.cargo then
              local rate=Init.rate(c.value,firm.production_raw[i])
              firm.produced[#firm.produced+1]={id=c.cargo.id,rate=rate,waiting=0,last_production=generating and rate*8 or 0}
            end
          end
          for _,c in ipairs(spec.accept) do if c.cargo then firm.accepted[#firm.accepted+1]={id=c.cargo.id,waiting=0} end end
          for _,c in ipairs(q.cells) do
            local cell_id=id(c.x,c.z)
            local a=s.tiles[cell_id]
            if a.house then
              local town_runtime=assert(options.town_runtime,"Native house replacement requires the town clearance adapter")
              local h=assert(a.source_house)
              local parts=h.asset_root and assert(town_runtime.footprint(s,h)) or {{id=cell_id,record=h}}
              for _,part in ipairs(parts) do
                local tile=s.tiles[part.id]
                town_runtime.remove(s,part.record)
                tile.house,tile.source_house,tile.parcel=nil,nil,nil
                Sim.mark_clear_land(s,part.id)
              end
            end
            a.wood,a.stock_clear_ground=nil,nil
            a.stock_industry={id=n,type=type,gfx=c.gfx,chain="climate_source"}
            if s.stock_farm_fields then s.stock_farm_fields[cell_id]=nil end
          end
          by_id[n]=firm
          if not generating then firm.created_year=Sim.date(s) end
          if spec.behavior.PlantOnBuild then
            Fields.on_built(firm,FieldWorld.field_board(s,{industries=by_id,exact_grid=true}),random)
          end
          result.firms[#result.firms+1]=firm
          if not generating then table.sort(result.firms,function(a,b)return a.id<b.id end) end
          result.attempts[#result.attempts+1]={type,attempt}
          return firm
        end
        result.failures[why]=(result.failures[why] or 0)+1
      end
      result.attempts[#result.attempts+1]={type,false}
    end
    return result,place,state,board,random
  end
  function M.generate(s,options)
    options=options or {}
    local p=assert(s.stock_generated_profile)
    assert(not p.climate_industry_rng,"Native climate industries are generated once")
    local result,place,state,board,random=mount(s,options,true)
    local climate=s.stock_climate.landscape
    Schedule.generate(board,{landscape=climate,density=options.density or 4,custom_count=options.custom_count},random,
      function(type,water,forced)
        result.selections[#result.selections+1]={type,water,forced,state[1],state[2]}
        place(type,water,forced)
      end)
    p.climate_industry_rng={state[1],state[2]}
    s.stock_worldgen_climate_firms=result.firms
    return result
  end
  function M.open(s,kind,options)
    local result,place=mount(s,options or {},false)
    return place(kind,false,false),result
  end
  return M
end
