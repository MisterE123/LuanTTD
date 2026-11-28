-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 14.1: landscape.cpp FindSpring, FlowsDown,
-- FlowRiver, BuildRiver, MakeLake, RiverMakeWider, CreateRivers;
-- map.cpp CircularTileSearch; pathfinder/npf/aystar.cpp and queue.cpp;
-- water_cmd.cpp terrain flood/reflood, void_cmd.cpp, landscape.cpp RunTileLoop.
-- Ordinary generation injects the 16.0-RC1 spring, terminus and YAPF ports.
-- No hard-coded rivers or substituted paths.
return function(Slope,RC1,Yapf,TreeLife)
  local R={AYSTAR_LIMIT=10000}
  local floor,ceil,min,max,abs=math.floor,math.ceil,math.min,math.max,math.abs
  local dx,dz={-1,0,1,0},{0,1,0,-1} -- stock DIAGDIR_NE,SE,SW,NW
  local incline={[12]=1,[6]=2,[3]=3,[9]=4}
  local single={[1]=true,[2]=true,[4]=true,[8]=true}
  local three={[7]=true,[11]=true,[13]=true,[14]=true}
  local U32=4294967296
  local function uint(n,a,b)
    assert(type(n)=="number" and n==floor(n) and n>=a and n<=b,"Out-of-range river setting")
    return n
  end
  local function pow2(n)
    uint(n,64,4096)
    while n>1 and n%2==0 do n=n/2 end
    assert(n==1,"Stock river board axes must be powers of two")
  end
  local function range(n,draw)
    -- Multiply-high without loss of precision on 4096² candidate sets.
    local hh=n*floor(draw/65536)
    return floor(hh/65536)+floor(((hh%65536)*65536+n*(draw%65536))/U32)
  end
  local function size(B) return B.width*B.height end
  local function xy(B,i) return i%B.width,floor(i/B.width) end
  local function id(B,x,z) return x+B.width*z end
  local function wrap(B,i,du,dv)
    local x,z=xy(B,i);x,z=x+du,z+dv
    local lo=B.freeform and 1 or 0
    if x>=lo and z>=lo and x<B.width-1 and z<B.height-1 then return id(B,x,z) end
  end
  local function valid(B,i)
    if i==nil or i<0 or i>=size(B) then return false end
    local x,z=xy(B,i)
    return x<B.width-1 and z<B.height-1 and (not B.freeform or x~=0 and z~=0) and B.tile(i).kind~="void"
  end
  local function water(B,i)
    if i==nil or i<0 or i>=size(B) then return false end
    local tile=B.tile(i)
    return tile.kind=="water" and tile.class~="coast" -- IsWaterTile, not MP_WATER
  end
  local function dist(B,a,b)
    local x,z=xy(B,a)
    local u,v=xy(B,b)
    return abs(x-u)+abs(z-v)
  end
  local function offset(B,i,d) return i+dx[d]+dz[d]*B.width end
  local function level(t) return assert(t.corner_height,"Stock NW corner height missing") end

  -- Source CircularTileSearch even-size walk starts just east of center;
  -- odd shapes test the center before stepping DIR_N (-1,-1).
  function R.circular(B,i,n,f)
    local x,z=xy(B,i)
    local hole=n%2
    if hole==1 then
      if f(i) then return i end
      if B.rc1 then x,z=x+1,z-1 else x,z=xy(B,(i-1-B.width)%size(B));x=x+2 end
    end
    if hole==0 then x=x+1 end
    for ring=0,floor(n/2)-1 do
      for d=1,4 do
        for _=1,hole+2*ring+1 do
          if x>=0 and z>=0 and x<B.width and z<B.height then
            local n2=id(B,x,z)
            if f(n2) then return n2 end
          end
          x,z=x+dx[d],z+dz[d]
        end
      end
      x,z=x+1,z-1
    end
  end

  local rc1=RC1 and RC1(valid,offset,dist,water,function(...)return R.flows_down(...) end,R.circular,range)

  function R.find_spring(B,i)
    local t=B.tile(i)
    if t.slope~=0 or water(B,i) then return false end
    local h=t.base
    local higher=0
    for a=-1,1 do for b=-1,1 do
      local n=wrap(B,i,a,b)
      if n and B.tile(n).top>h then higher=higher+1 end
    end end
    if higher<4 then return false end
    for a=-16,16 do for b=-16,16 do
      local n=wrap(B,i,a,b)
      if n and B.tile(n).top>h+2 then return false end
    end end
    return true
  end

  function R.flows_down(B,a,b)
    assert(dist(B,a,b)==1,"River flows only between adjacent tiles.")
    local t,u=B.tile(a),B.tile(b)
    return u.base<=t.base and (u.slope==0 or incline[u.slope]~=nil) and
      ((u.slope==t.slope and u.base<t.base) or u.slope==0 or t.slope==0)
  end

  -- FlowRiver uses FIFO discovery for the outlet, but an ascending set
  -- (not FIFO or insert order) for the random lake-center draw.
  function R.outlet(B,begin)
    local h=level(B.tile(begin))
    local visited={[begin]=true}
    local q={begin}
    local i,count=1,0
    while q[i] do
      local j=q[i];i=i+1
      local t=B.tile(j)
      local y=level(t)
      if t.slope==0 and (y<h or (y==h and water(B,j))) then
        return j,count,visited
      end
      for d=1,4 do
        local n=offset(B,j,d)
        if not visited[n] and valid(B,n) and R.flows_down(B,j,n) then
          visited[n]=true;count=count+1;q[#q+1]=n
        end
      end
    end
    return nil,count,visited
  end

  function R.lake(B,spring,begin,min_length,count,visited,random,make)
    if count<=32 then return end
    local choices={}
    for tile in pairs(visited) do choices[#choices+1]=tile end
    table.sort(choices)
    -- Stock count excludes the begin tile, then RandomRange(count-1)
    -- indexes the ordered set which *includes* begin.
    local center=choices[range(count-1,random())+1]
    local t=B.tile(center)
    local h=level(B.tile(begin))
    if not valid(B,center) or t.slope~=0 or level(t)~=h or center==begin or
        dist(B,spring,center)<=min_length then return end
    make(center)
    local n=range(8,random())+3
    local function fill(i)
      if not valid(B,i) then return false end
      local t2=B.tile(i)
      if level(t2)~=h or t2.slope~=0 then return false end
      for d=1,4 do
        if water(B,offset(B,i,d)) then make(i);break end
      end
      return false
    end
    R.circular(B,center,n,fill)
    R.circular(B,center,n,fill)
    return center,n
  end

  -- Source BinaryHeap uses <= when bubbling up. Deletion replaces the
  -- entry with the last node, sinks only, and prefers the right child
  -- on ties. A generic priority queue with an insertion-order tiebreak
  -- or a conventional decrease-key changes subsequent RNG consumption.
  local function heap()
    local q,pos={},{}
    local function swap(i,j)
      q[i],q[j]=q[j],q[i]
      pos[q[i].tile],pos[q[j].tile]=i,j
    end
    local function push(v)
      local i=#q+1
      q[i],pos[v.tile]=v,i
      while i>1 do
        local parent=floor(i/2)
        if q[i].f>q[parent].f then break end
        swap(i,parent);i=parent
      end
    end
    local function delete(v)
      local i=assert(pos[v.tile])
      local last=#q
      pos[v.tile]=nil
      if i==last then q[last]=nil;return end
      q[i],q[last]=q[last],nil
      pos[q[i].tile]=i
      while i*2<=#q do
        local j=i
        local left,right=i*2,i*2+1
        if q[j].f>=q[left].f then j=left end
        if q[right] and q[j].f>=q[right].f then j=right end
        if j==i then break end
        swap(j,i);i=j
      end
    end
    local function pop()
      local v=q[1]
      if v then delete(v) end
      return v
    end
    return push,delete,pop
  end

  -- Stock AyStar callback for river segments. Returns downstream first,
  -- exactly River_FoundEndNode's parent walk. Only unclosed candidates
  -- draw costs; an *already open* candidate still draws, even if rejected.
  function R.route(B,begin,finish,random,route_random)
    -- BuildRiver only receives distinct positions; do not guess what
    -- CheckIgnoreFirstTile does with an uninitialized start-node payload.
    assert(begin~=finish,"Stock BuildRiver endpoints are always distinct")
    local n=uint(route_random or 5,1,255)
    local push,delete,pop=heap()
    local first={tile=begin,g=0,f=0}
    push(first)
    local open,closed={[begin]=first},{}
    local expanded,draws=0,0
    while true do
      local cur=pop()
      if not cur then return nil,{expanded=expanded,draws=draws} end
      local j=cur.tile
      open[j]=nil
      if j==finish then
        local trace={}
        while cur do trace[#trace+1]=cur.tile;cur=cur.parent end
        return trace,{expanded=expanded,draws=draws}
      end
      closed[j]=cur
      for d=1,4 do
        local v=offset(B,j,d)
        if not closed[v] and valid(B,v) and R.flows_down(B,j,v) then
          local g=cur.g+1+range(n,random())
          draws=draws+1
          local next_=open[v]
          if not next_ or g<=next_.g then
            if next_ then delete(next_) else next_={tile=v};open[v]=next_ end
            next_.g,next_.parent,next_.f=g,cur,g+dist(B,v,finish)
            push(next_)
          end
        end
      end
      expanded=expanded+1
      -- AyStar limits expansions after visiting the last node's neighbors.
      if expanded>=R.AYSTAR_LIMIT then return nil,{expanded=expanded,draws=draws,limit=true} end
    end
  end

  local function xor(a,b)
    local n,k=0,1
    while a>0 or b>0 do
      if a%2~=b%2 then n=n+k end
      a,b,k=floor(a/2),floor(b/2),k*2
    end
    return n
  end
  local function bitand(a,b)
    local n,k=0,1
    while a>0 and b>0 do
      if a%2==1 and b%2==1 then n=n+k end
      a,b,k=floor(a/2),floor(b/2),k*2
    end
    return n
  end
  local function turn(a,b) return (a-1+b)%4+1 end
  local function wrap_off(B,i,d) return (offset(B,i,d))%size(B) end
  function R.widen(B,i,origin,make)
    if not valid(B,i) or water(B,i) then return false end
    local t,o=B.tile(i),B.tile(origin)
    if t.top==0 or t.top>o.top then return false end
    local cur,want=t.slope,o.slope
    if cur~=0 and not incline[cur] then
      if cur>=16 then return false end
      local flat,sloped=false,false
      for d=1,4 do
        local neighbor=B.tile(wrap_off(B,i,d))
        local dir=incline[neighbor.slope]
        if neighbor.kind=="water" and neighbor.class=="river" then
          if dir and t.top==neighbor.top and (dir==turn(d,1) or dir==turn(d,3)) then
            want=neighbor.slope;sloped=true;break
          end
          if neighbor.slope==0 then flat=true end
        end
      end
      if not sloped and not flat then return false end
      if not sloped then want=0 end
      local function terraform(mask,raise)
        assert(B.terraform,"Stock river widening requires a terrain-command boundary")(i,mask,raise)
      end
      if want==0 and three[cur] then
        for d=1,4 do
          local n=B.tile(wrap_off(B,i,d))
          if incline[n.slope] and n.kind=="water" and n.class~="coast" then return false end
        end
        terraform(15-cur,true)
      elseif incline[want] then
        local dir=turn(incline[want],2)
        for _,turns in ipairs({1,3}) do
          local n=B.tile(wrap_off(B,i,turn(dir,turns)))
          if n.kind=="water" and n.class=="river" and n.slope==0 then return false end
        end
        local change=xor(cur,want)
        if not single[cur] then terraform(bitand(change,15-want),false) end
        cur=B.tile(i).slope
        if cur~=want and single[cur] then terraform(xor(cur,want),true) end
      end
      cur=B.tile(i).slope
    end
    if incline[cur] then
      local d=incline[cur]
      local up,down=wrap_off(B,i,d),wrap_off(B,i,turn(d,2))
      if not valid(B,up) or not valid(B,down) then return false end
      local after=B.tile(down)
      local ocean=after.base==0 and (after.slope==0 or single[after.slope])
      if not water(B,down) and not ocean then
        if after.slope~=0 then return false end
        make(down)
      end
      local before=B.tile(up)
      if not water(B,up) then
        if before.slope~=0 then return false end
        make(up)
      end
    end
    if cur==want then make(i) end
    return false -- circular visits never stop after painting a width tile
  end

  function R.build(B,begin,finish,spring,main,random,make,opts)
    local path,details
    if B.rc1 then
      path,details=Yapf.route(B,begin,finish,random,opts.river_route_random,opts.max_search_nodes,valid,R.flows_down,offset,dist)
    else
      path,details=R.route(B,begin,finish,random,opts.river_route_random)
    end
    if not path then return nil,details end
    for _,tile in ipairs(path) do if not water(B,tile) then make(tile) end end
    if main and not opts.original then
      local long=(opts.min_river_length or 16)*4
      local step=floor(long/3)
      for _,tile in ipairs(path) do
        local n=min(3,floor(dist(B,spring,tile)/step)+1)
        if n>1 then R.circular(B,tile,n,function(i)return R.widen(B,i,tile,make)end) end
      end
    end
    return path,details
  end

  -- Equivalent iterative form of recursive FlowRiver: descend until
  -- valid sea/river or a lake; build segment paths from low to high.
  -- A reachable endpoint at insufficient total length causes failure
  -- immediately, not a new BFS seeking a different potentially redrawing outlet.
  function R.flow(B,spring,begin,min_length,random,make,opts)
    opts=opts or {}
    local chain={}
    local current=begin
    local main=false
    while true do
      local tile=B.tile(current)
      if water(B,current) then
        main=tile.base==0
        if dist(B,spring,current)<=min_length then return false,main end
        break
      end
      local outlet,count,visited=R.outlet(B,current)
      if not outlet then
        local lake=R.lake(B,spring,current,min_length,count,visited,random,make)
        if not lake then return false,false end
        chain[#chain+1]={current,lake}
        break
      end
      chain[#chain+1]={current,outlet}
      current=outlet
    end
    for i=#chain,1,-1 do
      local s=chain[i]
      local path,details=R.build(B,s[1],s[2],spring,main,random,make,opts)
      if opts.segment then opts.segment(s[1],s[2],path,details) end
      -- Source BuildRiver is void. The route search limit cannot change
      -- the preceding found flag into a different well attempt.
    end
    return true,main
  end

  -- Explicit mutation hooks are required so this driver cannot be
  -- mistaken for a drop-in landscape stage with missing flood/tile rules.
  function R.create(B,random,opts)
    opts=opts or {}
    local amount=uint(opts.amount_of_rivers or 2,0,3)
    local stats={wells=0,long_wells=0,short_wells=0,attempts=0,springs=0,rivers=0,water_writes=0}
    if amount==0 then return stats end
    pow2(B.width);pow2(B.height)
    assert(type(B.make_river)=="function" and type(B.reflood)=="function" and
      type(B.run_tile_loop)=="function","Stock river stage requires map water-write, reflood and tile-loop hooks")
    local river_len=uint(opts.min_river_length or 16,2,255)
    local wells=ceil(4*2^amount*size(B)/65536)
    local long=max(1,floor(wells/10))
    stats.wells,stats.long_wells,stats.short_wells=wells,long,wells-long
    local progress=opts.progress or function()end
    progress(0,wells+4)
    local function make(tile)
      local bits=random()%256
      B.make_river(tile,bits)
      stats.water_writes=stats.water_writes+1
    end
    for well=1,wells do
      progress(well,wells+4)
      local longer=well<=long
      for _=1,longer and 512 or 128 do
        stats.attempts=stats.attempts+1
        local tile=random()%size(B)
        local spring=R.circular(B,tile,8,function(i)
          if B.rc1 then return rc1.find_spring(B,i,opts.terrain_type) end
          return R.find_spring(B,i)
        end)
        if spring~=nil then
          stats.springs=stats.springs+1
          local minimum=river_len*(longer and 4 or 1)
          local success
          if B.rc1 then success=rc1.flow(B,spring,minimum,random,make,opts,R.build)
          else success=R.flow(B,spring,spring,minimum,random,make,opts) end
          if success then
            stats.rivers=stats.rivers+1;break
          end
        end
      end
    end
    B.reflood()
    for i=0,255 do
      if i%64==0 then progress(wells+i/64+1,wells+4) end
      B.run_tile_loop(i)
    end
    return stats
  end

  -- water_cmd.cpp clear/water/void branches, before clear/tree/industry
  -- generation. MP_CLEAR has grass density 3 and no foundations.
  local flood_bits={[0]=170,10,130,2,160,0,128,131,40,8,0,14,32,56,224}
  local flood_x,flood_z={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
  local function has(mask,d) return floor(mask/2^d)%2==1 end
  local function flood_off(B,i,d) return i+flood_x[d]+flood_z[d]*B.width end
  local function flood_kind(t)
    if t.kind=="void" or t.kind=="water" and t.class=="sea" then return 1 end
    if t.kind=="water" and t.class=="coast" then return single[t.slope] and 1 or -1 end
    return 0
  end
  function R.reflood(B,set)
    for i=0,size(B)-1 do
      local t=B.tile(i)
      if t.kind=="clear" and t.base==0 then
        if t.slope==0 then set(i,22)
        elseif single[t.slope] then set(i,38)
        else
          local mask=flood_bits[t.slope%16]
          for d=0,7 do
            if has(mask,d) then
              local n=B.tile(flood_off(B,i,d)%size(B))
              local q=n.slope%16
              if q==0 or single[q] or n.kind=="void" then set(i,38);break end
            end
          end
        end
      end
    end
  end
  function R.loop_water(B,set,i)
    local tile=B.tile(i)
    local behavior=flood_kind(tile)
    if behavior==1 then
      for d=0,7 do
        local j=flood_off(B,i,d)
        if valid(B,j) then
          local dest=B.tile(j)
          if dest.kind=="clear" and dest.base==0 and has(flood_bits[dest.slope%16],(d+4)%8) then
            set(j,dest.slope==0 and 22 or 38)
          end
        end
      end
    elseif behavior==-1 then
      local mask=flood_bits[tile.slope%16]
      for d=0,7 do
        local j=flood_off(B,i,d)
        if has(mask,d) and j>=0 and j<size(B) and flood_kind(B.tile(j))==1 then return end
      end
      set(i,0)
    end
  end

  local feedback={0xD8F,0x1296,0x2496,0x4357,0x8679,0x1030E,0x206CD,0x403FE,
    0x807B8,0x1004B2,0x2006A8,0x4004B2,0x800B87}
  -- misc.cpp initializes the nonzero cursor to 1. CreateRivers calls
  -- RunTileLoop directly, without moving TimerGameTick::counter from 0.
  function R.loop_scheduler(B,visit,opts)
    opts=opts or {}
    local count=size(B)/256
    local j,s=1,size(B)/4096
    while s>1 do s=s/2;j=j+1 end
    local poly=feedback[j]
    local cursor=opts.cursor or 1
    local counter=opts.counter or 0
    uint(cursor,1,size(B)-1)
    return function()
      local n=count
      if counter%256==0 then visit(0);n=n-1 end
      for _=1,n do
        visit(cursor)
        local half=floor(cursor/2)
        cursor=cursor%2==0 and half or xor(half,poly)
      end
      return cursor
    end
  end

  -- CmdTerraformLand at the clear/water/void worldgen boundary.
  -- Duplicating the far source corner would permit fictitious recursive
  -- height edits, so the Terrain grid has one fewer cell in each axis.
  function R.terraform_boundary(B,set,Terrain,max_height,trace,random)
    assert(type(Terrain)=="table" and type(Terrain.plan)=="function","Stock Terrain.plan required")
    uint(max_height,15,255)
    local grid
    return function(i,mask,up)
      local x,z=xy(B,i)
      local success,changed,cleared,reason=false,0,0,nil
      if not valid(B,i) then reason="INVALID_SELECTION"
      elseif mask==0 then success=true -- stock empty mask is a successful no-op
      else
        if not grid then
          -- The generated board already satisfies Terrain's corner
          -- invariant. Keep its packed reader as the default level map;
          -- do not allocate another dense table for a 4096×4096 input.
          local levels=setmetatable({},{__index=function(_,n)
            return B.corner((n-1)%B.width,floor((n-1)/B.width))
          end})
          grid={width=B.width-1,depth=B.height-1,max_height=max_height,freeform_edges=B.freeform,
            unit_cost=1,revision=0,levels=levels}
        end
        local clear,rock={},{}
        local function tile_at(u,v) return id(B,u-1,v-1) end
        local plan
        plan,reason=Terrain.plan(grid,x+1,z+1,mask,up,{
          void=function(u,v)return B.tile(tile_at(u,v)).kind=="void" end,
          validate_tile=function(pass,u,v)
            local tid=tile_at(u,v)
            local t=B.tile(tid)
            if random and t.kind=="water" and t.class=="river" then return nil,"MUST_DEMOLISH_RIVER_FIRST" end
            if t.kind=="water" then
              -- Plain sea/river can be cleared by worldgen. Coast has its
              -- own command branch and does not use the edge check.
              if t.class~="coast" and not B.freeform and
                  (u<2 or v<2 or u>=B.width-1 or v>=B.height-1) then
                return nil,"TOO_CLOSE_TO_EDGE"
              end
              if pass==1 then clear[#clear+1]=tid end
            elseif t.kind~="clear" and not (random and t.kind=="trees") then
              return nil,"NOT_WORLDGEN_GROUND"
            end
            return 0 -- no paying company during world generation
          end,
        })
        if plan then
          if random then
            -- Top-level Command::Do quotes first. Only a validated
            -- TerraformLand reaches the two executing passes.
            for pass=0,1 do
              for _,t in ipairs(plan.dirty) do
                local j=tile_at(t.x,t.z)
                if B.tile(j).kind~="void" then
                  local _,_,top=Terrain.tile(grid,t.x,t.z,plan)
                  local make_rocks=range(max_height,random())<=top
                  if pass==1 and not up and make_rocks then rock[j]=true end
                end
              end
            end
            for _,t in ipairs(plan.dirty) do
              local j=tile_at(t.x,t.z)
              if B.tile(j).kind~="void" then set.word(j,rock[j] and 512 or 0) end
            end
          end
          assert(Terrain.apply(grid,plan))
          -- The actual command clears affected tiles before applying
          -- heights. Stable clear grass density/type needs no packed write.
          if not random then for _,tid in ipairs(clear) do set.word(tid,0) end end
          for _,c in ipairs(plan.changes) do set.corner(c.x-1,c.z-1,c.height) end
          success,changed,cleared=true,#plan.changes,#clear
        end
      end
      if trace then trace(i,mask,up,success,changed,cleared,reason) end
      return success,changed,cleared,reason
    end
  end

  -- Detached, sparse region wrapper for prospective host wiring. The
  -- source paths above are usable without a packed-roster adapter.
  function R.generate(base,next_random,opts)
    opts=opts or {}
    local permitted=opts.amount_of_rivers
    if permitted==0 then return base,{wells=0,rivers=0} end
    local hooks=opts.hooks
    assert(opts.original==true or opts.original==false and (opts.terrain or hooks and type(hooks.terraform)=="function"),
      "Select original-width or TerraGenesis widening with the stock Terrain kernel")
    if hooks then
      assert(type(opts.hook_id)=="string" and #opts.hook_id>0,"Custom river adapters need a cache identity")
    end
    local water_words,river_extra,corners,trees={},{},{},{}
    local B={width=base.width,height=base.depth,freeform=base.freeform==true,rc1=opts.rc1==true}
    assert(not B.rc1 or rc1 and Yapf and TreeLife,"Missing pinned RC1 river source rules")
    local tropical=base.landscape=="tropic"
    local Climate=opts.climate_rules
    local zones,densities
    local function source_word(i)
      local x,z=xy(B,i)
      return water_words[i] or base.tile(x+1,z+1)
    end
    local climate_board
    if tropical then
      assert(B.rc1 and Climate and base.tropic_zone,"Pass the prepared RC1 Tropic raster and climate rules")
      assert(opts.tree_placer==0 or opts.tree_climate,"Pass the stock wetland tree rules for a wooded Tropic map")
      zones,densities={},{}
      function B.tropic_zone(i)
        local override=zones[i]
        if override~=nil then return override end
        local x,z=xy(B,i)
        return base.tropic_zone(x+1,z+1)
      end
      climate_board={width=B.width,depth=B.height,
        zone=function(x,z) return B.tropic_zone(id(B,x,z)) end,
        set_zone=function(x,z,v) zones[id(B,x,z)]=v end,
      }
    end
    local function corner(x,z)
      local i=id(B,x,z)
      return corners[i] or base.corner(x+1,z+1)
    end
    B.corner=corner
    local rng={base.rng_after[1],base.rng_after[2]}
    function B.tile(i)
      local x,z=xy(B,i)
      local a,b=min(x+1,B.width-1),min(z+1,B.height-1)
      local hn,hw,he,hs=corner(x,z),corner(a,z),corner(x,b),corner(a,b)
      local s,h=Slope.classify(hn,hw,he,hs)
      local t=max(hn,hw,he,hs)
      local word=water_words[i] or base.tile(x+1,z+1)
      local class=floor(word/16)%16
      return {kind=word%16==7 and "void" or word%16==6 and "water" or word%16==4 and "trees" or "clear",class=class==3 and "river" or
        class==2 and "coast" or class==1 and "sea" or nil,corner_height=corner(x,z),slope=s,base=h,top=t}
    end
    local function set_word(i,v)
      water_words[uint(i,0,size(B)-1)]=v
      if v~=54 then river_extra[i]=nil end
      if v~=4 then trees[i]=nil end
      if densities then densities[i]=v%16==0 and 3 or nil end
    end
    local setter={
      word=set_word,
      corner=function(x,z,h)corners[id(B,uint(x,0,B.width-1),uint(z,0,B.height-1))]=uint(h,0,255) end,
    }
    function B.make_river(i,bits)
      -- Native TerraGenesis adapter word: kind 6, subtype 3 reserved
      -- for river (sea/coast remain 1/2). Keep gameplay random byte separate.
      water_words[i],river_extra[i],trees[i]=54,bits,nil
      if climate_board then
        densities[i]=nil
        Climate.clear_river_zone(climate_board,i)
      end
    end
    function B.roughen(i) set_word(i,256) end
    function B.place_tree(i,r)
      -- PlaceTree(..., keep_density=true) on freshly roughened land.
      if tropical then
        local tree=opts.tree_climate.place("tropic",B.tropic_zone(i),r,{class=0,ground=1,density=3},true)
        if tree then set_word(i,4);trees[i]=tree end
        return
      end
      set_word(i,4)
      trees[i]={class=4,ground=1,density=3,
        type=floor(floor(r/16777216)*12/256),count=floor(r/4194304)%4+1,
        growth=min(floor(r/65536)%8,6)}
    end
    function B.drain_sea(order)
      for _,j in ipairs(order) do
        B.terraform(j,15,false)
        B.terraform(j,15-B.tile(j).slope%16,true)
      end
    end
    local cursor=base.climate_tileloop_cursor or 1
    local function random() return next_random(rng) end
    local function dry_density(i)
      if densities[i]~=nil then return densities[i] end
      local x,z=xy(B,i)
      return base.clear_density(x+1,z+1) or 3
    end
    local function tree_neighbor(d,_,x,z)
      local i=flood_off(B,id(B,x,z),d)
      if not valid(B,i) then return end
      local word=source_word(i)
      return {class=word%16,ground=floor(word/256)%16,density=tropical and dry_density(i) or 3,
        coast=floor(word/16)%16==2,rocky=floor(word/4096)%2==1,slope=B.tile(i).slope}
    end
    local desert_ground={[0]="grass","rough","rocks","fields",[5]="desert"}
    local ground_code={grass=0,rough=1,rocks=2,fields=3,desert=5}
    local next_loop=R.loop_scheduler(B,function(i)
      local tree=trees[i]
      if not tree then
        local w=tropical and source_word(i)
        if w and w%16==0 then
          local g,den=Climate.clear_desert(desert_ground[floor(w/256)%16],dry_density(i),B.tropic_zone(i),function()
            return Climate.normal_neighbor(B.width,i,function(j) return j>=0 and j<size(B) and source_word(j)%16~=7 end,
              function(j) return B.tropic_zone(j)==Climate.DESERT end,
              function(j) local n=source_word(j);return n%16==6 and floor(n/16)%16~=3 end)
          end)
          if g then set_word(i,ground_code[g]*256);densities[i]=den end
        else
          R.loop_water(B,set_word,i)
        end
        return
      end
      local x,z=xy(B,i)
      -- CreateRivers calls RunTileLoop directly: source TimerGameTick is 0
      -- for all 256 passes. Only existing wetland trees can grow or spread.
      local next_tree,event=TreeLife.visit(tree,x,z,0,opts.extra_tree_placement,random,tree_neighbor,nil,
        tropical and B.tropic_zone(i) or nil)
      if not next_tree then
        if tropical and event.ground==2 then
          set_word(i,5*256)
          densities[i]=event.density
        else
          set_word(i,event.ground==3 and 38 or event.ground*256)
          if densities and event.ground~=3 then densities[i]=event.density end
        end
      else
        trees[i]=next_tree
      end
      if event and event.kind=="plant" then
        local j=flood_off(B,i,event.direction)
        set_word(j,4);trees[j]=event.tree
      end
    end,{cursor=cursor})
    function B.reflood()
      if hooks and hooks.reflood then return hooks.reflood(B,setter,rng) end
      R.reflood(B,set_word)
    end
    function B.run_tile_loop(i)
      if hooks and hooks.run_tile_loop then cursor=hooks.run_tile_loop(B,setter,rng,i) or cursor
      else cursor=next_loop() end
    end
    local commands,committed,edits,cleared=0,0,0,0
    local limit
    if hooks and hooks.terraform then
      function B.terraform(i,mask,up)return hooks.terraform(B,setter,i,mask,up) end
    elseif not opts.original then
      local configured=opts.map_height_limit or 0
      limit=configured~=0 and configured or max(30,min(255,assert(base.estimated_max_height,
        "Pass the active map height limit for a non-TerraGenesis input")+15))
      local function trace(i,mask,up,success,changed,n,reason)
        commands,edits,cleared=commands+1,edits+changed,cleared+n
        if success then committed=committed+1 end
        if opts.terraform_trace then opts.terraform_trace(i,mask,up,success,changed,n,reason) end
      end
      B.terraform=R.terraform_boundary(B,setter,opts.terrain,limit,trace,
        B.rc1 and function()return next_random(rng) end or nil)
    end
    local stats=R.create(B,function()return next_random(rng)end,opts)
    if limit then
      stats.terraform_commands,stats.terraform_committed=commands,committed
      stats.terraform_corner_edits,stats.terraform_cleared_water=edits,cleared
    end
    local output={}
    for k,v in pairs(base) do output[k]=v end
    output.rng_after=rng
    output.river_tileloop_cursor=cursor
    output.base_id=base.base_id..(B.rc1 and "/rivers-16.0-RC1-" or "/rivers-separate-v2-")..tostring(permitted or 2).."-"..
      tostring(opts.min_river_length or 16).."-"..tostring(opts.river_route_random or 5).."-"..(opts.original and "orig" or "tg")..(limit and "-cap"..limit or "")..(hooks and "-hook-"..opts.hook_id or "")
    function output.corner(x,z)
      if x<1 or z<1 or x>B.width+1 or z>B.height+1 then return end
      return corner(min(x-1,B.width-1),min(z-1,B.height-1))
    end
    function output.tile(x,z)
      if x<1 or z<1 or x>B.width or z>B.height then return end
      return water_words[id(B,x-1,z-1)] or base.tile(x,z)
    end
    function output.river_tree(x,z)
      if x<1 or z<1 or x>B.width or z>B.height then return end
      return trees[id(B,x-1,z-1)]
    end
    function output.river_bits(x,z)
      if x<1 or z<1 or x>B.width or z>B.height then return end
      return river_extra[id(B,x-1,z-1)]
    end
    if tropical then
      function output.tropic_zone(x,z)
        if x<1 or z<1 or x>B.width or z>B.height then return end
        return B.tropic_zone(id(B,x-1,z-1))
      end
      function output.clear_density(x,z)
        local w=output.tile(x,z)
        if w and w%16==0 then return dry_density(id(B,x-1,z-1)) end
      end
      function output.town_climate(x,z)
        local zone=output.tropic_zone(x,z)
        if zone~=nil then return {tile_height=output.corner(x,z),is_desert=zone==Climate.DESERT} end
      end
    end
    function output.storage_options()
      return {seed=base.seed,base_id=output.base_id,corner=function(_,x,z)return output.corner(x,z) end,
        tile=function(_,x,z)return output.tile(x,z) end}
    end
    return output,stats
  end
  return R
end
