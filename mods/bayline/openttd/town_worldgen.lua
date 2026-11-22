-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 14.1 src/town_cmd.cpp (GenerateTowns,
-- CreateRandomTown, TownCanBePlacedHere, InitializeLayout, DoCreateTown,
-- BuildTownHouse's generation-stage branch), src/map.cpp circular searches
-- and src/map_func.h ScaleBySize, RandomTileSeed. Temperate/no NewGRFs.
return function(Growth,Build,Names)
  local W={POOL_MAX=64000,EDGE=12,SEPARATION=20,HARD_ATTEMPTS=10000,SOFT_ATTEMPTS=20}
  local floor,min,ceil,abs=math.floor,math.min,math.ceil,math.abs
  local initial={[0]=5,11,23,46}
  local order={[0]="original","better","grid2","grid3","random"}
  local dir_x,dir_z={-1,0,1,0},{0,1,0,-1}
  local dist_x,dist_z={-1,1,1,-1},{1,1,-1,-1}
  local function enum(v,names)
    if type(v)=="number" then return assert(names[v],"Invalid numeric enum") end
    for _,value in pairs(names) do if value==v then return v end end
    error("Invalid worldgen setting: "..tostring(v))
  end
  local function uint(v,lo,hi,why)
    assert(type(v)=="number" and v==floor(v) and v>=lo and v<=hi,why)
    return v
  end
  local function xor(a,b)
    local r,k=0,1
    while a>0 or b>0 do
      if a%2~=b%2 then r=r+k end
      a,b,k=floor(a/2),floor(b/2),k*2
    end
    return r
  end
  local function log(n)
    local bits=0
    while n>1 and n%2==0 do bits,n=bits+1,n/2 end
    return n==1 and bits or nil
  end
  local function validate_board(board)
    local w,h=log(uint(board.width,64,4096,"Stock map width")),log(uint(board.height,64,4096,"Stock map height"))
    assert(w and h,"Town worldgen requires stock power-of-two map dimensions.")
    assert(type(board.tile)=="function","Board has no tile reader.")
  end

  function W.align(x,z,layout)
    layout=enum(layout,order)
    if layout=="grid2" then return x-x%3,z-z%3 end
    if layout=="grid3" then return x-x%4,z-z%4 end
    return x,z
  end
  function W.resolve_layout(x,z,layout)
    layout=enum(layout,order)
    if layout~="random" then return layout end
    local h=(xor(xor(floor(x/16),floor(x/64)),floor(z/16))-floor(z/64))%4294967296
    return order[h%4]
  end
  function W.count(board,opts,random)
    validate_board(board)
    local diff=opts.editor and 0 or opts.difficulty or 2
    uint(diff,0,4,"Unknown stock town-number setting")
    if diff==4 then return min(W.POOL_MAX,uint(opts.custom_count or 1,1,W.POOL_MAX,"Custom town count")) end
    return min(W.POOL_MAX,ceil((initial[diff]+random()%8)*board.width*board.height/65536))
  end

  function W.can_place(board,towns,x,z)
    if min(x,z,board.width-1-x,board.height-1-z)<W.EDGE then
      return false,"TOO_CLOSE_TO_EDGE"
    end
    -- Upstream's town k-d tree is exactly Manhattan, not square/radius.
    for _,t in ipairs(towns) do
      if abs(t.x-x)+abs(t.z-z)<W.SEPARATION then return false,"TOO_CLOSE_TO_ANOTHER_TOWN" end
    end
    local t=board.tile(x,z)
    if not t or (t.kind~="clear" and t.kind~="trees") or t.slope~=0 then return false,"SITE_UNSUITABLE" end
    return true
  end

  -- Source CircularTileSearch rectangular spiral. It visits no center
  -- separately for even widths, notably the production sizes 40 and 10.
  function W.circular(board,x,z,size,visit)
    local hole=0
    if size%2==1 then
      if visit(x,z) then return x,z end
      hole=1
      -- TileAddByDir(DIR_N) subtracts both coordinates in linear map space.
      local n=(x+z*board.width-1-board.width)%(board.width*board.height)
      x,z=n%board.width,floor(n/board.width)
    end
    x=x+hole+1
    for ring=0,floor(size/2)-1 do
      for d=1,4 do
        for _=1,hole+2*ring+1 do
          if x>=0 and z>=0 and x<board.width and z<board.height and visit(x,z) then return x,z end
          x,z=x+dir_x[d],z+dir_z[d]
        end
      end
      x,z=x+1,z-1
    end
  end
  local function has_water(t)
    if not t then return false end
    if t.water_ground~=nil then return t.water_ground end
    return t.kind=="water"
  end
  function W.water_distance(board,x,z)
    if board.water_distance then return board.water_distance(x,z) end
    if has_water(board.tile(x,z)) then return 0 end
    local low=board.freeform and 1 or 0
    local hi_x,hi_z=board.width-1,board.height-1
    for dist=1,126 do
      z=z-1
      for d=1,4 do
        for _=1,dist do
          if x>=low and x<hi_x and z>=low and z<hi_z and has_water(board.tile(x,z)) then return dist end
          x,z=x+dist_x[d],z+dist_z[d]
        end
      end
    end
    return 127
  end
  function W.coast(board,x,z,layout)
    local function clear(a,b)
      local t=board.tile(a,b)
      return t and t.kind=="clear"
    end
    local i,j=W.circular(board,x,z,40,clear)
    if i==nil then return end
    local bx,bz,distance=nil,nil,0
    W.circular(board,i,j,10,function(a,b)
      -- Stock scans even non-candidates, and does not stop at a success;
      -- ties must use the first tile in its spiral.
      local d=W.water_distance(board,a,b)
      local t=board.tile(a,b)
      local aa,bb=W.align(a,b,layout)
      if t and t.kind=="clear" and t.slope==0 and aa==a and bb==b and d>distance then
        bx,bz,distance=a,b,d
      end
      return false
    end)
    return bx,bz,distance
  end

  function W.initial_mass(size,city,city_size,manual,editor,random)
    local kinds={[0]="small","medium","large","random"}
    size=enum(size or "random",kinds)
    local x=size=="random" and (random()%16+8) or ({small=3,medium=19,large=35})[size]
    if city and (not manual or editor) then x=x*uint(city_size or 2,1,10,"Initial city population multiplier") end
    return x
  end

  -- Only the generation-time house branch changes proposal state. Stock
  -- always draws the construction value, *then* an independent lottery.
  function W.house_stage(p,random)
    local r=random()
    local stage=3
    if Growth.chance(1,7,random()) then stage=r%4 end
    local counter=stage==3 and 0 or floor(r/4)%4
    for _,q in ipairs(p.parts) do q.stage,q.counter,q.completed=stage,counter,stage==3 end
    p.stage,p.counter,p.completed=stage,counter,stage==3
    return stage==3 and (p.root_population or 0) or 0
  end

  -- Existing GrowTown kernel is reused for the road/house proposals.
  -- commit(proposal,town) applies records to the fresh-world board and
  -- returns true on success. This layer alone updates stock town counts.
  function W.initialize(town,board,opts,random)
    assert(Build and Growth,"Initial town growth port dependencies are missing.")
    assert(type(opts.commit)=="function" and type(opts.year)=="number")
    assert(town.num_houses==0 and town.population==0,"Initialize a fresh town record.")
    town.time_until_rebuild=10
    local mass=W.initial_mass(opts.size,town.larger_town,opts.initial_city_size,opts.manual,opts.editor,random)
    local stats={mass=mass,attempts=mass*4,roads=0,houses=0}
    town.num_houses=mass
    town.radii=Growth.radii(mass)
    local growth_settings={year=opts.year,allow_roads=opts.allow_roads~=false,
      build_on_slopes=opts.build_on_slopes}
    local stations=opts.stations or {}
    for _=1,stats.attempts do
      local p=Build.grow(town,board,growth_settings,random)
      if p then
        local delta=p.kind=="house" and W.house_stage(p,random) or 0
        if opts.commit(p,town) then
          if p.kind=="house" then
            stats.houses=stats.houses+1
            town.population=town.population+delta
            Build.house_committed(town,p,stations,opts.growth_setting)
          elseif p.kind=="road" then stats.roads=stats.roads+1 end
        end
      end
    end
    town.num_houses=town.num_houses-mass
    town.radii=Growth.radii(town.num_houses)
    Growth.update_rate(town,stations,opts.growth_setting)
    local scale=opts.scale_cargo or function(n)return n end
    local pass,mail=opts.passenger_cargo or "passenger",opts.mail_cargo or "mail"
    for _,spec in ipairs{{pass,8},{mail,16}} do
      local k=spec[1]
      town.supplied[k]=town.supplied[k] or {}
      town.supplied[k].old_max=scale(floor(town.population/spec[2]),true)
    end
    return town,stats
  end

  -- Random stock placement, names and city rolls share one supplied RNG.
  -- create(candidate,random) stages the actual small town and returns a
  -- populated record. If returning 0 population, roll back its writes
  -- before returning or supply opts.remove(town,candidate).
  function W.generate(board,opts)
    opts=opts or {}
    local random=assert(opts.random,"Shared world-generation random stream required.")
    local name=opts.name or Names and Names.generate
    assert(type(name)=="function" and type(opts.create)=="function")
    local layout=enum(opts.layout or "original",order)
    local larger=uint(opts.larger_towns or 4,0,255,"Larger towns denominator")
    local total=W.count(board,opts,random)
    local towns,created,existing_names,used={},{},{},{}
    for _,t in ipairs(board.towns or {}) do
      towns[#towns+1]=t
      if t.name then existing_names[t.name]=true;used[t.name]=true end
    end
    local result={target=total,attempted_positions=0,soft_positions=0,hard_positions=0,
      name_attempts=0,failed_growth=0,fallback=false,towns=created}
    local function create(attempts,parts,display,city)
      local room=not board.can_allocate and #towns<W.POOL_MAX or board.can_allocate and board.can_allocate(#towns)
      if not room then return end
      for _=1,attempts do
        local a=random()%(board.width*board.height)
        local x,z=W.align(a%board.width,floor(a/board.width),layout)
        result.attempted_positions=result.attempted_positions+1
        if result.fallback then result.hard_positions=result.hard_positions+1
        else result.soft_positions=result.soft_positions+1 end
        local t=board.tile(x,z)
        if t and t.kind=="water" then x,z=W.coast(board,x,z,layout) end
        if x~=nil and W.can_place(board,towns,x,z) then
          local candidate={x=x,z=z,city=city,larger_town=city,layout=W.resolve_layout(x,z,layout),
            size="random",nameparts=parts,name=display,manual=false,editor=not not opts.editor}
          local record=opts.create(candidate,random)
          if record and (record.population or 0)>0 then
            towns[#towns+1]={x=x,z=z,name=display}
            existing_names[display]=true
            created[#created+1]=record
            return record
          end
          if record and opts.remove then opts.remove(record,candidate) end
          result.failed_growth=result.failed_growth+1
        end
      end
    end
    local function label(selection)
      result.name_attempts=result.name_attempts+1
      local p,n=name(selection,random)
      if p~=nil then
        assert(type(n)=="string","Name callback returned invalid display name.")
        selection[n]=true
        return p,n
      end
    end
    if opts.progress then opts.progress(0,total) end
    for i=1,total do
      local city=larger~=0 and Growth.chance(1,larger,random())
      if opts.progress then opts.progress(i,total) end
      local parts,display=label(used)
      if parts~=nil then create(W.SOFT_ATTEMPTS,parts,display,city) end
    end
    if opts.rebuild_index then opts.rebuild_index() end
    if #created==0 then
      result.fallback=true
      local parts,display=label(existing_names)
      if parts~=nil then create(W.HARD_ATTEMPTS,parts,display,larger~=0) end
    end
    result.success=#created~=0
    return result
  end
  return W
end
