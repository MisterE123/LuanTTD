-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 temperate land Oil Wells (11) -> Oil Refinery (4).
-- Source: table/build_industry.h, industry_cmd.cpp, clear/map checks,
-- economy.cpp, industry.h, cargo_const.h, engines.h. Oil Rig #5 spec,
-- placement and construction completion verified in 16.0-RC1.
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local Rig=dofile(mod.."/openttd/oil_rig.lua")
return function(SharedFactory,Packets,Catchment,Rating,Income,Commons,Timber)
  -- Private instance of the shared fixed-slot and ordinary processing
  -- flow; the installed Farm/Factory rules and queues are untouched.
  local O=SharedFactory(Packets,Catchment,Rating,Income,Commons,Timber)
  local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
  local shared_change,shared_loop,shared_produce=O.change,O.tile_loop,O.production_tick
  local shared_acceptance,shared_distribution=O.acceptance,O.distribute
  O.layout={
    oil_rig={[0]=Rig.cells},
    oil_well={
      [0]={{0,0,29},{1,0,29},{2,0,29},{0,1,29},{0,2,29}},
      {{0,0,29},{1,0,29},{1,1,29},{2,2,29},{2,3,29}},
    },
    oil_refinery={
      [0]={{0,0,20},{0,1,21},{0,2,22},{0,3,21},{1,0,20},{1,1,19},{1,2,22},{1,3,20},
        {2,1,18},{2,2,18},{2,3,18},{3,2,18},{3,3,18},{2,0,23},{3,1,23}},
      {{0,0,18},{0,1,18},{0,2,21},{0,3,22},{0,4,20},{1,0,18},{1,1,18},{1,2,19},{1,3,20},
        {2,0,18},{2,1,18},{2,2,19},{2,3,22},{1,4,23},{2,4,23}},
    },
  }
  O.spec={
    oil_rig=Rig.spec,
    oil_well={id=11,life="extractive",minimum=5,cost_factor=220,procurement_probability=0x99999999,
      out={"oil"},rates={12},input={},multiplier={},sounds=0,climates=7,
      appearance={0,5,3,0},generation={4,5,5,0},map_colour=152,only_decreases=true,before_1950=true,
      conflict="oil_refinery"},
    oil_refinery={id=4,life="processing",minimum=5,cost_factor=244,procurement_probability=0xFFFFFFFF,
      out={"goods"},rates={0},input={"oil"},multiplier={256},sounds=0,climates=7,
      appearance={2,2,2,0},generation={4,4,4,0},map_colour=191,edge_check=true,conflict="oil_rig"},
  }
  O.cargo={goods=O.cargo.goods,passenger=O.cargo.passenger or {id=0,label="PASS",class="passengers",weight_16=1,capacity_multiplier=1024,payment=3185,days1=0,days2=24,unit="passengers"},oil={id=3,label="OIL_",class="liquid",weight_16=16,capacity_multiplier=256,
    payment=4437,days1=25,days2=255,unit="1000 L"}}
  O.trucks={goods=O.trucks.goods,oil={id=132,index=16,image=3,name="Witcombe Oil Tanker",cargo="oil",
    capacity=21,buy_factor=110,running_factor=90,speed=96,climates=7,weight_quarters=38,power_tens_hp=12,
    intro_days_after_1920=5479,life=15,base_life=55,decay=20,load_amount=5,age_ticks=185}}
  O.EDGE_LIMIT=32
  function O.cost(kind,raw_setting,base,raw_base)
    local s=assert(O.spec[kind])
    return floor((s.life=="extractive" and raw_setting==1 and (raw_base or 8000000) or (base or 1000000))*s.cost_factor/256)
  end
  function O.tile_acceptance(gfx,cargo)
    if gfx>=24 and gfx<=28 then return Rig.acceptance(gfx,cargo) end
    if gfx==20 and cargo=="oil" then return 8 end
    if gfx==23 and cargo=="passenger" then return 1 end
    return 0
  end
  -- CheckNewIndustry_OilRefinery checks offset (1,1), the distance
  -- strictly less than the independent stock edge distances. This is
  -- not a navigable water or adjacency requirement.
  function O.refinery_edge(x,z,width,height,opts)
    opts=opts or {}
    if opts.editor then return true end
    local limit=opts.limit or O.EDGE_LIMIT
    x,z=x+1,z+1
    if x<0 or z<0 or x>=width-1 or z>=height-1 then return false end
    local north=opts.freeform and 1 or 0
    local lx,lz=limit*max(1,floor(width/256)),limit*max(1,floor(height/256))
    return x-north<lx or z-north<lz or width-2-x<lx or height-2-z<lz
  end
  -- Every stock Oil Wells / Refinery tile's slopes_refused is SLOPE_STEEP.
  -- The source normal industry command consequently refuses all nonflat
  -- corners; separate TerraGenesis site leveling is not part of this API.
  function O.slope_allowed(gfx,slope)
    return (gfx>=18 and gfx<=32) and slope==0
  end
  function O.conflicts(kind,other_kind,dx,dz)
    return (kind=="oil_rig" and other_kind=="oil_refinery" or O.spec[kind].conflict==other_kind) and max(math.abs(dx),math.abs(dz))<=14
  end
  -- The ordinary original appearance weights. Funding/prospecting uses
  -- its own command; map generation is not the random during-game path.
  function O.appearance(kind,context,opts)
    opts=opts or {}
    local s=assert(O.spec[kind])
    if kind=="oil_rig" then return Rig.weight(context,opts) end
    if opts.enabled==false or opts.fund_only and (context~="mapgen" or not opts.editor) then return 0 end
    if context=="mapgen" then return s.generation[1] end
    assert(context=="random","Use random or mapgen appearance")
    if s.before_1950 and (opts.year or 1950)>1950 then return 0 end
    return s.appearance[1]
  end

  function O.allowed_source(st,ind)
    if st.serve_neutral~=false then return true end
    if st.neutral_rig then return st.neutral_rig==ind.id end
    return ind.neutral_station==nil
  end
  function O.distribute(ind,cargo,amount,stations,covers,opts)
    local list={}
    for _,st in ipairs(stations) do
      if O.allowed_source(st,ind) then list[#list+1]=st end
    end
    return shared_distribution(ind,cargo,amount,list,covers,opts)
  end
  function O.acceptance(st,c,cargo,industries,house_at)
    if st.serve_neutral~=false then return shared_acceptance(st,c,cargo,industries,house_at) end
    local list={}
    for _,ind in pairs(industries) do
      if O.allowed_source(st,ind) then list[#list+1]=ind end
    end
    return shared_acceptance(st,c,cargo,list,house_at)
  end

  function O.production_tick(ind,opts)
    -- Source draws the ambient sample on schedule even if an industry
    -- has no sounds; suppress emission only, not the shared RNG draw.
    return shared_produce(ind,opts,true)
  end
  function O.tile_loop(ind,tile,opts,offer)
    opts=opts or {}
    local completed=tile.completed
    local n,moved,detail=shared_loop(ind,tile,opts,offer)
    if ind.kind=="oil_rig" and not completed and tile.completed and not ind.removed and opts.complete_rig then
      opts.complete_rig(ind,tile)
    end
    if opts.stock_tile_animation and ind.kind=="oil_well" and completed and not ind.removed and not opts.editor then
      opts.random_u32() -- TriggerIndustryTileAnimation precedes the pump lottery.
    end
    if ind.kind=="oil_well" and completed and not ind.removed and not opts.editor and tile.gfx==29 and opts.random_u32 then
      if Commons.chance(6,opts.random_u32()) then
        tile.gfx,tile.animation_frame=30,0
        if opts.animated then opts.animated(ind,tile,true) end
      end
    end
    return n,moved,detail
  end
  -- AnimateTile_Industry dispatches every 8th absolute world tick. All
  -- animated tiles draw once, even at the intermediate frames which
  -- cannot actually stop until another 12-frame cycle completes.
  function O.animate(tile,tick,random)
    if tile.gfx<30 or tile.gfx>32 or tick%8~=0 then return false end
    local will_stop=Commons.chance(7,assert(random)())
    local frame=(tile.animation_frame or 0)+1
    local gfx=tile.gfx
    if frame==4 then
      frame=0
      gfx=gfx+1
      if gfx==33 then
        if will_stop then
          tile.gfx,tile.stage=29,3
          -- Source leaves the stored previous frame when removing it
          -- from the animation list; first activation resets to zero.
          return true,false
        end
        gfx=30
      end
    end
    tile.gfx,tile.animation_frame=gfx,frame
    return true,true
  end

  function O.trigger(ind)
    if ind.removed or ind.kind~="oil_refinery" then return 0,0,{} end
    local input,output=ind.accepted[1],ind.produced[1]
    assert(input.cargo=="oil" and output.cargo=="goods")
    ind.was_cargo_delivered=true
    local before,used=output.waiting,input.waiting
    output.waiting=min(O.MAX_WAITING,before+used)
    input.waiting=0
    return output.waiting-before,used,{oil=used}
  end

  function O.change(ind,year,opts)
    opts=opts or {}
    if ind.kind~="oil_well" then return shared_change(ind,year,opts) end
    if ind.removed or (not not opts.monthly)==(not not opts.original) or opts.frozen and not opts.original then return end
    local out=ind.produced[1]
    local before,close=out.rate,false
    if opts.original then
      -- In temperate original mode the decline is unconditional when
      -- this well is selected. There is no 1-in-3 RNG draw to consume.
      if opts.no_decrease or opts.external_prod_level then return end
      if ind.prod_level==4 then close=true
      else
        ind.prod_level=max(4,floor(ind.prod_level/2))
        out.rate=min(255,ceil(O.spec.oil_well.rates[1]*ind.prod_level/16))
      end
    else
      local random=assert(opts.random_u32)
      local r=random()
      local next=before
      if Commons.chance(22,floor(r/65536)) then
        next=next-max(floor((floor(random()*50/4294967296)+10)*before/256),1)
      end
      next=max(1,min(255,next))
      close=not (opts.no_closure or opts.no_decrease)
      if not (opts.no_decrease and next<before or opts.no_increase and next>before) then
        out.rate=next
        if next>1 then close=false end
      end
    end
    local changes={}
    if out.rate~=before then
      changes[1]={cargo="oil",before=before,rate=out.rate,
        percent=before==0 and 100 or floor(out.rate*100/before)-100}
    end
    -- OpenTTD explicitly exempts declining temperate oil wells from
    -- last-industry closure protection even when this is the last one.
    if close and not opts.no_closure then
      ind.prod_level=0
      return "closure",changes
    end
    if #changes>0 then return "rate",changes end
  end
  return O
end
