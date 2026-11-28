-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 14.1 industry_cmd.cpp GenerateIndustries,
-- GetScaledIndustryGenerationProbability, GetNumberOfIndustries,
-- PlaceIndustry, CreateNewIndustry and built-in location checks; map.cpp
-- TileAddWrap; table/build_industry.h temperate Coal Mine, Power Station,
-- Sawmill and Forest. Farm, Factory, Wells and Refinery tables/checks
-- also verified against OpenTTD 16.0-RC1 (table/build_industry.h).
-- Native initial manifest excludes industry kinds / art layouts not ported.
return function(Coal,Timber,Oil,Farm,Heavy,NativeLayouts)
  local W={POOL_MAX=64000,HARD_ATTEMPTS=10000,SOFT_ATTEMPTS=2000}
  local floor,ceil,min,max,abs=math.floor,math.ceil,math.min,math.max,math.abs
  local U32=4294967296
  local quantities={[0]=0,0,10,25,55,80,0}
  local function correct(n,lo,hi)
    return type(n)=="number" and n==floor(n) and n>=lo and n<=hi
  end
  local function uint(n,lo,hi,msg)
    assert(correct(n,lo,hi),msg)
    return n
  end
  local function axis(n)
    uint(n,64,4096,"Industry generation requires stock map axis sizes.")
    while n>1 and n%2==0 do n=n/2 end
    assert(n==1,"Industry generation requires power-of-two map axes.")
  end
  local function range(n,raw) return floor(n*raw/U32) end
  local function density(opts)
    -- Editor's Random Industries button uses Very Low even when the
    -- normal map-generation density is set to Funding Only.
    if opts.editor then return 2 end
    return uint(opts.density or 4,0,6,"Invalid stock industry density.")
  end
  W.specs={
    [0]={kind="coal_mine",name="Coal Mine",layout=Coal.mine_layouts,weight=8,conflict={[1]=true},
      available={[0]=true},picture="coal_mine_0"},
    [1]={kind="power_station",name="Power Station",layout=Coal.power_layouts,weight=5,conflict={[0]=true},
      available={[0]=true},picture="power_station"},
  }
  local last_type=1
  if Timber then
    assert(type(Timber.new)=="function" and Timber.layout and Timber.layout.sawmill and Timber.layout.forest,
      "Timber worldgen requires the stock Timber industry kernel.")
    W.specs[2]={kind="sawmill",name="Sawmill",layout=Timber.layout.sawmill,weight=5,
      conflict={[3]=true},available={[0]=true},picture="sawmill_0",kernel=Timber}
    W.specs[3]={kind="forest",name="Forest",layout=Timber.layout.forest,weight=5,
      conflict={[2]=true,[14]=true},available={[0]=true},picture="forest_0",kernel=Timber,check="forest"}
    last_type=3
  end
  if Oil then
    assert(Oil.layout.oil_refinery and Oil.layout.oil_well and Oil.refinery_edge)
    W.specs[4]={kind="oil_refinery",name="Oil Refinery",layout=Oil.layout.oil_refinery,
      weight=Oil.spec.oil_refinery.generation[1],conflict={[5]=true},available={[0]=true},
      picture="industry_oil_refinery",kernel=Oil,check="refinery",coastal=true}
    W.specs[11]={kind="oil_well",name="Oil Wells",layout=Oil.layout.oil_well,
      weight=Oil.spec.oil_well.generation[1],conflict={[4]=true},available={[0]=true},
      picture="industry_oil_well",kernel=Oil}
    last_type=11
  end
  if Farm then
    assert(Farm.layout.factory and Farm.layout.farm)
    W.specs[6]={kind="factory",name="Factory",layout=Farm.layout.factory,
      weight=Farm.spec.factory.generation[1],conflict={[8]=true,[9]=true},available={[0]=true},
      picture="industry_factory",kernel=Farm}
    W.specs[9]={kind="farm",name="Farm",layout=Farm.layout.farm,
      weight=Farm.spec.farm.generation[1],conflict={[6]=true,[13]=true},available={[0]=true},
      picture="industry_farm",kernel=Farm}
    last_type=max(last_type,9)
  end
  if Heavy then
    for kind,id in pairs({iron_mine=18,steel_mill=8}) do
      local def=assert(Farm.spec[kind])
      W.specs[id]={kind=kind,name=id==18 and "Iron Ore Mine" or "Steel Mill",layout=Farm.layout[kind],
        weight=def.generation[1],conflict=id==18 and {[8]=true} or {[18]=true,[6]=true},
        available=id==8 and {[0]=true,[1]=true} or {[0]=true},picture="industry_"..kind,kernel=Farm}
    end
    last_type=max(last_type,18)
  end
  for id,variants in pairs(NativeLayouts or {}) do
    local spec=W.specs[id]
    if spec then
      for variant,visible in pairs(variants) do
        if visible and spec.layout[variant] then spec.available[variant]=true end
      end
    end
  end
  local temperate=Timber or Oil or Farm
  function W.scale_area(n,width,height) return ceil(n*width*height/65536) end
  function W.scale_coast(n,width,height) return ceil(n*(width+height)/512) end
  function W.count(board,opts)
    local level=density(opts)
    if level==6 then return min(W.POOL_MAX,uint(opts.custom_count or 1,1,W.POOL_MAX,"Invalid custom industry count.")) end
    return min(W.POOL_MAX,W.scale_area(quantities[level],board.width,board.height))
  end

  function W.probability(board,id,opts)
    opts=opts or {}
    local s=W.specs[id]
    if not s or not s.layout[0] or opts.enabled and opts.enabled[id]~=true or density(opts)==0
        or temperate and opts.landscape and opts.landscape~="temperate" then
      return 0,false
    end
    local probability=s.weight*16 -- multiply before scaling, not after
    probability=(s.coastal and W.scale_coast or W.scale_area)(probability,board.width,board.height)
    return probability,probability>0 and not opts.editor
  end
  local function inside(board,x,z)
    local a=board.freeform and 1 or 0
    return correct(x,a,board.width-2) and correct(z,a,board.height-2)
  end
  local function read(board,x,z)
    if not correct(x,0,board.width-1) or not correct(z,0,board.height-1) then return end
    return board.tile(x,z)
  end
  local function grade(t)
    if t then
      if t.corner_height~=nil then return t.corner_height end
      if t.base~=nil and t.slope==0 then return t.base end
    end
  end
  local function clear_kind(t)
    return t and (t.kind=="clear" or t.kind=="trees") and not t.protected
  end
  local function off_limits(t)
    return not clear_kind(t) or t.owner~=nil or t.vehicle or t.bridge or t.industry or t.water_ground
  end
  local function nearest(board,x,z)
    local best,value
    for _,t in ipairs(board.towns or {}) do
      local d=abs(x-t.x)+abs(z-t.z)
      if not best or d<value or d==value and t.id<best.id then best,value=t,d end
    end
    return best
  end

  -- Source CheckNewIndustry_Forest. The only additional geography check
  -- is Arctic's highest possible snow line plus two; this game's
  -- placement catalog is temperate and must not add a height or tree-count
  -- requirement there. Kept callable to qualify the literal source rule.
  function W.forest_site(landscape,base,highest_snowline)
    if landscape=="arctic" then
      if not correct(base,0,255) or not correct(highest_snowline,0,255) then
        return nil,"FOREST_SITE_HEIGHT_UNKNOWN"
      end
      if base<highest_snowline+2 then return nil,"FOREST_CAN_ONLY_BE_PLANTED_ABOVE_SNOW_LINE" end
    end
    return true
  end

  -- Source CheckCanTerraformSurroundingTiles: one recursive sub-tier,
  -- no unlimited flood of terraform queries, and no destructive mutation.
  local function surrounding(board,x,z,target,internal)
    local here=read(board,x,z)
    if x<=0 or z<=0 or not here or here.kind=="void" then return false end
    for zz=z-1,z do for xx=x-1,x do
      local t=read(board,xx,zz)
      if not clear_kind(t) then return false end
      local h=grade(t)
      if h==nil then return false end
      if internal then
        if abs(h-target)>1 then return false end
      elseif h~=target and (xx==0 or zz==0 or not surrounding(board,xx-1,zz-1,target,true)) then
        return false
      end
    end end
    return true
  end

  -- Follows the source industry's expanded platform area, including
  -- max offset + 2 (corners), map edge guards and the caller's platform.
  -- A host that cannot perform terrain writes must reject affected cells.
  function W.platform(board,x,z,layout,opts,industry)
    opts=opts or {}
    local p=uint(opts.platform or 1,0,4,"Invalid stock industry platform border.")
    if x<=p+1 or z<=p+1 then return nil,"PLATFORM_TOO_CLOSE_TO_EDGE" end
    local mx,mz=0,0
    for _,part in ipairs(layout) do
      mx=max(mx,part[1]);mz=max(mz,part[2])
    end
    local a,b=x-p,z-p
    local w,h=mx+2+2*p,mz+2+2*p
    if a+w>=board.width-1 or b+h>=board.height-1 then return nil,"PLATFORM_TOO_CLOSE_TO_EDGE" end
    local level=grade(read(board,x,z))
    if level==nil then return nil,"PLATFORM_HEIGHT_UNKNOWN" end
    local work={}
    for zz=b,b+h-1 do for xx=a,a+w-1 do
      local n=grade(read(board,xx,zz))
      if n==nil then return nil,"PLATFORM_HEIGHT_UNKNOWN" end
      if n~=level then
        if not surrounding(board,xx,zz,level,false) then return nil,"PLATFORM_SURROUNDINGS_REFUSED" end
        if not board.terraform_quote or board.can_level_industry and not board.can_level_industry(industry) then
          return nil,"PLATFORM_TERRAFORM_UNPORTED"
        end
        -- Stock DC_NO_WATER queries one SLOPE_N corner change from the
        -- original map (not a mutation or a full leveling guarantee).
        if not board.terraform_quote(xx,zz,n<level) then return nil,"PLATFORM_TERRAFORM_REFUSED" end
        work[#work+1]={x=xx,z=zz,from=n,to=level}
      end
    end end
    return {x=a,z=b,width=w,height=h,level=level,changes=work}
  end

  -- Immutable check of one stock candidate. Geography, current
  -- industries, town affiliation, and exact occupied vs hole cells.
  function W.quote(board,id,x,z,variant,opts,placed)
    opts,placed=opts or {},placed or board.industries or {}
    if temperate and opts.landscape and opts.landscape~="temperate" then return nil,"INDUSTRY_CLIMATE_UNPORTED" end
    local spec=W.specs[id]
    if not spec or opts.enabled and opts.enabled[id]~=true then return nil,"INDUSTRY_TYPE_UNPORTED" end
    local layout=spec.layout[variant]
    if not layout or not spec.available[variant] then return nil,"INDUSTRY_LAYOUT_UNPORTED" end
    if not correct(x,0,board.width-1) or not correct(z,0,board.height-1) then return nil,"OFF_MAP" end
    for _,other in ipairs(placed) do
      if spec.conflict[other.type] and max(abs(x-other.x),abs(z-other.z))<=14 then
        return nil,"INDUSTRY_TOO_CLOSE"
      end
    end
    local town=nearest(board,x,z)
    if not town then return nil,"NO_TOWN" end
    if not opts.multiple_per_town then
      for _,other in ipairs(placed) do
        if other.type==id and other.town==town.id then return nil,"ONLY_ONE_ALLOWED_PER_TOWN" end
      end
    end
    if spec.check=="forest" then
      local ok,why=W.forest_site(opts.landscape or "temperate")
      if not ok then return nil,why end
    elseif spec.check=="refinery" then
      if not spec.kernel.refinery_edge(x,z,board.width,board.height,
          {freeform=board.freeform,editor=opts.editor,limit=opts.oil_refinery_limit}) then
        return nil,"REFINERY_NOT_NEAR_EDGE"
      end
    end
    local cells,level,needs_leveling={},nil,false
    for _,q in ipairs(layout) do
      local u,v=x+q[1],z+q[2]
      if not inside(board,u,v) then return nil,"FOOTPRINT_OFF_MAP" end
      local t=read(board,u,v)
      if off_limits(t) then return nil,"FOOTPRINT_OCCUPIED" end
      local h=grade(t)
      if h==nil then return nil,"PLATFORM_HEIGHT_UNKNOWN" end
      if t.slope~=0 or level~=nil and h~=level then needs_leveling=true end
      level=level or h
      cells[#cells+1]={x=u,z=v,offset_x=q[1],offset_z=q[2],gfx=q[3]}
    end
    local platform,why=W.platform(board,x,z,layout,opts,id)
    if not platform and (opts.terragenesis~=false or needs_leveling) then return nil,why end
    local leveling
    if needs_leveling or platform and #platform.changes>0 then
      if not (platform and board.level_platform) then return nil,"PLATFORM_TERRAFORM_UNPORTED" end
      leveling,why=board.level_platform(id,platform,cells)
      if not leveling then return nil,why or "PLATFORM_TERRAFORM_REFUSED" end
      level=platform.level
    end
    if #placed>=W.POOL_MAX or board.can_allocate and not board.can_allocate(#placed) then
      return nil,"TOO_MANY_INDUSTRIES"
    end
    return {type=id,kind=spec.kind,name=spec.name,style=spec.picture,x=x,z=z,layout=variant,
      town=town.id,level=level,cells=cells,platform=platform,leveling=leveling}
  end

  -- Translate DoCreateNewIndustry's accepted-candidate draws to explicit
  -- fields (no draws during quotes). RC1 smooth production consumes one
  -- draw through the last valid output slot, not all sixteen (14.1).
  function W.initialize(plan,seed,initial_bits,random,opts)
    opts=opts or {}
    plan.seed,plan.initial_random=seed,initial_bits
    if opts.rc1 then
      local counts={[0]=1,0,1,1,1,2,1,[8]=1,[9]=2,[11]=1,[12]=1,[18]=1}
      plan.production_raw={}
      for j=1,counts[plan.type] or 0 do plan.production_raw[j]=random() end
    elseif opts.original==false then
      for j=1,16 do
        local r=random()
        if j==1 then plan.production_random=r end
      end
    end
    local rr=random()%65536
    plan.random_colour,plan.counter=rr%16,floor(rr/16)
    plan.selected_layout=plan.layout+1
    for _,c in ipairs(plan.cells) do
      c.random_bits=random()%256
      c.stage,c.construction_counter,c.completed=2,3,false
    end
    -- RC1's unconditional trigger argument draw happens after every
    -- tile has been placed (row-major sorted physical footprint).
    if opts.rc1 then
      for _=1,#plan.cells do random() end
    end
    return plan
  end

  -- Existing stock industry kernel receives source position and rates;
  -- the host chooses whether to mount the true initial stage or a separate
  -- post-tile-loop snapshot. No ownership or out-of-band RNG is supplied.
  function W.record(plan,id,opts)
    opts=opts or {}
    local spec=W.specs[plan.type]
    local kernel=spec and spec.kernel or Coal
    local rec=kernel.new(plan.kind,id,plan.x,plan.z,{layout=plan.layout,completed=opts.after_first_visit,
      original=opts.original~=false,production_random=plan.production_random,
      generating_world=true,counter=plan.counter,economy_year=opts.year,
      scale=opts.cargo_scale,random_u32=opts.random})
    if plan.production_raw and rec.produced then
      local by_slot=rec.produced.rate and {rec.produced} or rec.produced
      for i,draw in ipairs(plan.production_raw) do
        local q=assert(by_slot[i],"Stock produced cargo slot absent from the host record")
        q.rate=min(255,floor((128+range(256,draw))*q.rate/256))
        if q.last then q.last.production=floor(q.rate*8*(opts.cargo_scale or 100)/100) end
      end
    end
    rec.town,rec.random,rec.random_colour,rec.selected_layout=
      plan.town,plan.initial_random,plan.random_colour,plan.selected_layout
    for j,t in ipairs(rec.tiles) do t.random_bits=plan.cells[j].random_bits end
    return rec
  end

  function W.generate(board,opts)
    opts=opts or {}
    assert(not temperate or opts.landscape==nil or opts.landscape=="temperate","Only temperate stock industry generation is mounted.")
    axis(board.width);axis(board.height)
    local random=assert(opts.random,"Industry worldgen requires the shared raw uint32 stream.")
    assert(type(board.tile)=="function" and type(opts.commit)=="function")
    local result={target=0,shortfall=0,attempted=0,selected=0,forced=0,placed={},failures={},choices={}}
    if density(opts)==0 then return result end
    local used={}
    for _,v in ipairs(board.industries or {}) do used[#used+1]=v end
    local prob,force,total_prob,forced={},{},0,0
    for id=0,last_type do
      prob[id],force[id]=W.probability(board,id,opts)
      total_prob=total_prob+prob[id]
      if force[id] then forced=forced+1 end
    end
    local target=W.count(board,opts)
    if opts.rc1 and density(opts)~=6 and board.initial_land_count then
      target=floor(target*board.initial_land_count/(board.width*board.height))
    end
    if total_prob==0 or target<forced then target=forced end
    result.target,result.forced=target,forced
    if opts.progress then opts.progress(0,target) end
    local function attempt(id,hard)
      result.selected=result.selected+1
      result.choices[#result.choices+1]={type=id,forced=hard}
      if opts.progress then opts.progress(result.selected,target) end
      local l=W.specs[id].layout
      for _=1,hard and W.HARD_ATTEMPTS or W.SOFT_ATTEMPTS do
        result.attempted=result.attempted+1
        local r=random()%(board.width*board.height)
        local x,z=r%board.width,floor(r/board.width)
        local a,b=random(),random()%65536
        local variant=range(#l+1,random())
        local plan,why=W.quote(board,id,x,z,variant,opts,used)
        if plan then
          if opts.prepare then opts.prepare(plan,random) end
          W.initialize(plan,a,b,random,opts)
          -- The host owns the one authoritative commit; a commit failure
          -- is not a stock failed quote and must not silently burn more RNG
          -- or result in a partially selected scenario.
          assert(opts.commit(plan),"Authorized map-generation commit failed")
          used[#used+1]=plan
          result.placed[#result.placed+1]=plan
          return
        end
        result.failures[why]=(result.failures[why] or 0)+1
      end
    end
    for id=0,last_type do if force[id] then attempt(id,true) end end
    for _=1,target-forced do
      local r,id=range(total_prob,random()),0
      while r>=prob[id] do r,id=r-prob[id],id+1 end
      attempt(id,false)
    end
    result.shortfall=target-#result.placed
    result.wanted_inds=#used*65536
    if opts.reset then opts.reset(result.wanted_inds) end
    return result
  end
  return W
end
