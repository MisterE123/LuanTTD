-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, updated for 16.0-RC1: town_cmd.cpp GrowTown*, CanFollowRoad,
-- GetTownRoadGridElement and BuildTownHouse; ordinary temperate branch.
-- Host provides deterministic planning and site authorization.
return function(G,catalog,climate_catalog)
  local B={}
  local floor=math.floor
  local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  local bits={[0]=8,4,2,1}
  local grid={grid2=3,grid3=4}
  local walk_seed={{-1,0},{1,1},{1,-1},{-1,-1},{-1,0},{0,2},{2,0},{0,-2},{-1,-1},{-2,2},{2,2},{2,-2},{0,0}}
  local corner={[9]={1,1},[6]={-1,-1},[12]={1,-1},[3]={-1,1}}
  local slopes={[1]=3,[3]=7,[2]=6,[6]=14,[4]=12,[12]=13,[8]=9,[9]=11}
  local function rev(d) return (d+2)%4 end
  local function has(n,b) return floor(n/b)%2==1 end
  local function join(a,b)
    for _,i in pairs(bits) do if has(b,i) and not has(a,i) then a=a+i end end
    return a
  end
  local function within(board,x,z) return x~=nil and z~=nil and board.tile(x,z) end
  local function per(board,x,z,d) return x+dx[d],z+dz[d] end
  local function road(t)
    return t and (t.kind=="road" or t.kind=="drive_stop" or t.kind=="bridge" or t.kind=="tunnel") and (t.road_bits or 0) or 0
  end
  local function disallowed(t)
    return not t or t.kind=="void" or (t.kind=="water" and not t.coast) or t.water or t.protected
  end
  local function random_dir(random)
    return G.range(4,random())
  end

  function B.grid_bits(t,x,z,d,slope)
    local n=assert(grid[t.layout])
    local bits2=((x-t.x)%n==0 and 5 or 0)+((z-t.z)%n==0 and 10 or 0)
    if bits2~=15 then return bits2 end
    local template=slopes[slope or 0] or ((slope or 0)>=16 and 0 or 15)
    if d~=nil and not has(template,bits[rev(d)]) then return bits[d]+bits[rev(d)] end
    return template
  end
  function B.house_on_layout(t,x,z,roads,square)
    if not roads then return true end
    if t.layout=="grid2" and square then return (t.x-x)%3==2 and (t.z-z)%3==2 end
    if t.layout=="grid3" and square then return (t.x-x)%4>=2 and (t.z-z)%4>=2 end
    local n=grid[t.layout]
    return not n or ((x-t.x)%n~=0 and (z-t.z)%n~=0)
  end
  local function may_house(board,x,z,noslope,maxz)
    local t=within(board,x,z)
    if disallowed(t) or t.bridge_above or (t.slope or 0)>=16 or noslope and (t.slope or 0)~=0 then return false end
    if board.house_roadtypes and not board.house_roadtypes(x,z) then return false end
    if maxz~=nil and t.max_z~=maxz then return false end
    -- RC1 CanBuildHouseHere quotes LandscapeClear with Auto and NoWater.
    -- The host can explicitly admit ordinary trees without allowing
    -- demolition of buildings or owned property.
    if t.kind=="road" then return not t.occupied and board.clear_quote and board.clear_quote(x,z,"house") end
    local wooded=t.kind=="trees" and board.clear_quote~=nil
    if t.kind~="clear" and not t.coast and not wooded or t.occupied or t.owner then return false end
    return not board.clear_quote or board.clear_quote(x,z,"house")
  end
  local function footprint(board,t,x,z,roads,spec,first,noslope)
    local w,d=spec[6],spec[7]
    if w==1 and d==1 then return x,z end
    local maxz=first.max_z
    if maxz==nil then return end
    if w*d==2 then
      local ox,oz=w==2 and 1 or 0,d==2 and 1 or 0
      if B.house_on_layout(t,x+ox,z+oz,roads) and may_house(board,x+ox,z+oz,noslope,maxz) then return x,z end
      if B.house_on_layout(t,x-ox,z-oz,roads) and may_house(board,x-ox,z-oz,noslope,maxz) then return x-ox,z-oz end
      return
    end
    for _,root in ipairs{{x,z},{x,z-1},{x-1,z-1},{x-1,z}} do
      local u,v=root[1],root[2]
      if B.house_on_layout(t,u,v,roads,true) and may_house(board,u,v,noslope,maxz) and may_house(board,u,v+1,noslope,maxz)
          and may_house(board,u+1,v+1,noslope,maxz) and may_house(board,u+1,v,noslope,maxz) then return u,v end
    end
  end

  function B.house(t,board,x,z,opts,random)
    if not B.house_on_layout(t,x,z,opts.allow_roads) or not may_house(board,x,z,false) then return end
    local zone,first=G.zone(t,x,z),board.tile(x,z)
    local pool,total={},0
    local climate_bit
    if opts.landscape then
      if opts.landscape=="arctic" then
        -- Board max_z is expressed in internal pixel-height units; the
        -- stock snowline is in tile height levels. Equality is below.
        climate_bit=first.max_z>8*assert(opts.highest_snowline) and 1 or 4
      else
        local stock={temperate=2,tropic=8,toyland=16}
        climate_bit=assert(stock[opts.landscape],"Invalid stock house climate")
      end
    end
    local specs=climate_bit and assert(climate_catalog,"RC1 full climate house catalog required") or catalog
    for _,spec in ipairs(specs) do
      if (not climate_bit or has(spec[10],climate_bit)) and has(spec[2],2^zone) and (not t.house_counts or (t.house_counts[spec[1]] or 0)<65535) then
        pool[#pool+1]=spec
        total=total+spec[9]
      end
    end
    while total>0 do
      local q=G.range(total,random())
      local idx=1
      while q>=pool[idx][9] do q=q-pool[idx][9];idx=idx+1 end
      local spec=pool[idx]
      total=total-spec[9]
      pool[idx]=pool[#pool];pool[#pool]=nil -- exact swap-remove order
      local noslope=spec[11]
      if opts.year>=spec[3] and opts.year<=spec[4] and (not spec[8] or not (t.unique and t.unique[spec[8]]))
          and (not noslope or (first.slope or 0)==0) then
        local u,v=footprint(board,t,x,z,opts.allow_roads,spec,first,noslope)
        if u~=nil and (not board.house_supported or board.house_supported(spec[1],u,v,spec)) then
          local h=spec[1]
          local props={kind="house",x=u,z=v,id=h,town=t.id,root_population=spec[5],
            unique=spec[8],random_bits=random()%256,parts={{x=u,z=v,id=h,root=true}}}
          if spec[7]==2 then h=h+1;props.parts[#props.parts+1]={x=u,z=v+1,id=h} end
          if spec[6]==2 then h=h+1;props.parts[#props.parts+1]={x=u+1,z=v,id=h} end
          if spec[6]*spec[7]==4 then h=h+1;props.parts[#props.parts+1]={x=u+1,z=v+1,id=h} end
          for _,p in ipairs(props.parts) do
            p.town,p.completed,p.stage,p.counter,p.root_x,p.root_z=t.id,false,0,0,u,v
          end
          return props
        end
      end
    end
  end

  function B.can_follow(board,x,z,d,roads)
    local a,b=per(board,x,z,d)
    local t=within(board,a,b)
    if disallowed(t) then return false end
    local rb=road(t)
    if not roads then
      local back=bits[rev(d)]
      return has(rb,back) and rb~=back
    end
    if t.kind=="road" then return rb~=0 end
    if t.kind=="drive_stop" then return true end
    if t.kind=="house" or t.kind=="industry" or t.kind=="object" or
        t.kind=="bay_stop" or t.kind=="station" or t.kind=="depot" or t.kind=="rail_portal" then return false end
    if t.kind=="bridge" or t.kind=="tunnel" then return true end
    return true
  end
  local function plan_road(t,board,x,z,rb,d,random)
    if rb==0 or not board.road_quote then return end
    local current=board.tile(x,z)
    local rail=current and current.kind=="rail"
    if disallowed(current) or current.occupied or
      current.kind~="road" and current.kind~="clear" and current.kind~="trees" and not current.coast and not rail or
      current.road_town and current.road_town~=t.id or current.owner and not rail and not current.company_road then return end
    if d~=nil then
      if not board.clean_road_bits then return end
      rb=board.clean_road_bits(t,x,z,rb,d)
    end
    if rb==0 then return end
    if d~=nil and board.road_span then
      local span=board.road_span(t,x,z,d,random)
      if span then return span end
    end
    local q=board.road_quote(t,x,z,rb)
    if q then return {kind="road",town=t.id,x=x,z=z,bits=rb,quote=q} end
  end
  local function extra(t,board,x,z,opts,random)
    if not board.distance_to_edge or board.distance_to_edge(x,z)==0 then return end
    local n=0
    for d=0,3 do
      local u,v=per(board,x,z,d)
      local q=board.tile(u,v)
      if not q or q.kind=="house" or q.kind=="void" then n=n+1 end
      if n>=3 then return B.house(t,board,x,z,opts,random) end
    end
  end

  local function grow_here(t,board,x,z,rb,from,opts,random)
    local q=board.tile(x,z)
    local roads=opts.allow_roads
    if disallowed(q) then return nil,true end
    local function allowed(a,b,d)
      return board.road_allowed and board.road_allowed(t,a,b,d,random)
    end
    if rb==0 then
      if not roads or from==nil then return nil,true end
      if q.kind=="rail" and opts.allow_level_crossings==false then return nil,true end
      if opts.build_on_slopes==false or G.chance(1,6,random()) then
        if board.level_land then board.level_land(x,z,random);q=board.tile(x,z) end
      end
      local rcmd
      if grid[t.layout] then rcmd=B.grid_bits(t,x,z,from,q.slope)
      else
        if not allowed(x,z,from) then return nil,true end
        local src=rev(from)
        if G.chance(1,4,random()) then
          repeat from=random_dir(random) until from~=src
        end
        local u,v=per(board,x,z,from)
        if not allowed(u,v,from) then
          if from~=rev(src) then return nil,true end
          local a,b=per(board,x,z,(from+1)%4)
          local c,d=per(board,x,z,(from+3)%4)
          local l,r=board.tile(a,b),board.tile(c,d)
          if not (l and l.kind=="house" or r and r.kind=="house") then return nil,true end
        end
        rcmd=bits[from]+bits[src]
      end
      return plan_road(t,board,x,z,rcmd,from,random),true
    end
    if from~=nil and not has(rb,bits[rev(from)]) then
      if not roads then return nil,true end
      local rcmd=grid[t.layout] and B.grid_bits(t,x,z,from,q.slope) or bits[rev(from)]
      return plan_road(t,board,x,z,rcmd,from,random),true
    end

    local d=random_dir(random)
    local u,v
    local b=bits[d]
    if has(rb,b) then
      if not has(10,b) or not corner[rb] then return end
      local delta=corner[rb]
      u,v,d=x+delta[1],z+delta[2],nil
    else
      u,v=per(board,x,z,d)
    end
    local h=board.tile(u,v)
    if disallowed(h) then return end
    local permit,rcmd,extra_built=true,0,false
    if d~=nil and roads then
      if t.layout=="grid3" or t.layout=="better" then
        local hx,hz=per(board,u,v,d)
        local plan=extra(t,board,hx,hz,opts,random)
        if plan then
          if opts.extra_house then
            extra_built=not not opts.extra_house(plan)
          else return plan end
        end
      end
      if grid[t.layout] then rcmd=B.grid_bits(t,x,z,d,q.slope);permit=not has(rcmd,b)
      else rcmd=b;permit=not allowed(u,v,d) or G.chance(6,10,random()) end
    end
    if board.house_roadtypes and not board.house_roadtypes(u,v) then permit=false end
    if permit then
      if h.kind~="house" then
        if G.chance(1,6,random()) and board.level_land then board.level_land(u,v,random) end
        return B.house(t,board,u,v,opts,random),false,extra_built
      end
      return nil,false,extra_built
    end
    return plan_road(t,board,x,z,rcmd,d,random),true
  end

  -- The command adapters quote on the same snapshot as the road walk.
  function B.visit(t,b,u,v,q,rb,from,opts,rand)
    local portal=q.inside~=nil and (q.kind=="bridge" or q.kind=="tunnel")
    if portal and (from==nil or has(rb,bits[rev(from)])) then
      if from~=nil or G.chance(1,2,rand()) then return nil,false,false,q.other_x,q.other_z end
      return
    end
    return grow_here(t,b,u,v,rb,from,opts,rand)
  end

  -- RC1 GrowTownAtRoad: construction is distinct from the traversal.
  -- The visit may move the current tile through a road bridge/tunnel.
  function B.walk(t,board,x,z,roads,random,visit)
    local from
    local m=t.layout=="better" and 2 or grid[t.layout] and 1 or 4
    local budget=10+floor(t.num_houses*m/9)
    for _=0,budget do
      local q=board.tile(x,z)
      if disallowed(q) then return end
      local rb=road(q)
      local plan,stop,extra_built,u,v=visit(t,board,x,z,q,rb,from,random)
      if plan or extra_built then return plan,extra_built end
      if u~=nil then x,z=u,v end
      if from and has(rb,bits[rev(from)]) then rb=rb-bits[rev(from)] end
      if rb==0 then return end
      local next_dir
      q=board.tile(x,z)
      local portal=q and q.inside~=nil and (q.kind=="bridge" or q.kind=="tunnel")
      if portal then
        next_dir=rev(q.inside)
      else
        while rb~=0 do
          local b
          repeat next_dir=random_dir(random);b=bits[next_dir] until has(rb,b)
          rb=rb-b
          if B.can_follow(board,x,z,next_dir,roads) then break end
          next_dir=nil
        end
      end
      if next_dir==nil then return end
      x,z=per(board,x,z,next_dir)
      q=board.tile(x,z)
      -- Stock checks foreign municipal ownership on landing, not on the
      -- seed tile. A neighboring town's initial road can host house search.
      if q and q.kind=="road" and road(q)~=0 and q.road_town and q.road_town~=t.id then return end
      if stop then return end
      from=next_dir
    end
  end

  function B.grow(t,board,opts,random)
    opts=opts or {}
    assert(opts.year,"Calendar year required for house availability")
    local startx,startz=t.x,t.z
    local x,z=startx,startz
    for _,delta in ipairs(walk_seed) do
      if road(board.tile(x,z))~=0 then
        return B.walk(t,board,x,z,opts.allow_roads,random,function(t,b,u,v,q,rb,from,rand)
          return B.visit(t,b,u,v,q,rb,from,opts,rand)
        end)
      end
      x,z=x+delta[1],z+delta[2]
    end
    if not opts.allow_roads then return end
    x,z=startx,startz
    for _,delta in ipairs(walk_seed) do
      local q=board.tile(x,z)
      -- GrowTown's roadless fallback uses the natural flatness, not
      -- the foundation that an ordinary road command could build.
      local seed_quote=board.seed_road_clear_quote or board.clear_quote
      if not disallowed(q) and q.slope==0 and (q.kind=="clear" or q.kind=="trees" or q.coast) and
          not q.owner and not q.occupied and (not seed_quote or seed_quote(x,z,"road")) then
        local r=random()
        local a,b=r%4,floor(r/256)%4
        if a==b then b=(b+2)%4 end
        return plan_road(t,board,x,z,2^a+2^b,nil)
      end
      x,z=x+delta[1],z+delta[2]
    end
  end

  function B.house_committed(t,proposal,stations,setting)
    assert(proposal.town==t.id and proposal.kind=="house")
    t.house_counts=t.house_counts or {}
    for _,part in ipairs(proposal.parts) do t.house_counts[part.id]=(t.house_counts[part.id] or 0)+1 end
    if proposal.unique then t.unique=t.unique or {};t.unique[proposal.unique]=true end
    G.house_added(t,stations,setting)
  end

  -- RC1 keeps a 3-bit counter: eight visits per construction stage.
  -- Root tile alone advances all the parts; the host calls this on the
  -- physical RunTileLoop visit BEFORE ordinary completed-house production.
  -- Returning true means this visit was construction-only, including the
  -- visit that completes stage 3. Do not produce cargo until a later visit.
  function B.advance_house(h,parts,house_specs,on_complete)
    if h.completed then return false end
    if not h.root then return true end
    for _,p in ipairs(parts) do
      p.counter=(p.counter+1)%8
      if p.counter==0 then
        p.stage=p.stage+1
        if p.stage==3 then
          p.completed,p.age=true,0
          if on_complete then on_complete(p,assert(house_specs[p.id])[1]) end
        end
      end
    end
    return true
  end
  return B
end
