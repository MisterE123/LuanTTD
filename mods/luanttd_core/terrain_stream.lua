-- Bounded detached terrain profiles for a future renderer, not live nodes.
-- Use openttd/slope.lua, the pinned continuous form of GetPartialPixelZ.
local self=debug and debug.getinfo(1,"S").source
local here=self and self:match("^@(.*/)terrain_stream%.lua$")
local D=dofile((here or (core and core.get_modpath(core.get_current_modname() or "luanttd_core").."/") or
  "mods/luanttd_core/").."terrain_word.lua")
return function(Slope)
  local M={}
  local floor,min,max,abs=math.floor,math.min,math.max,math.abs
  local byte=string.byte
  local MAX_RADIUS,MAX_BUDGET=64,16
  local schema,legacy="luanttd-terrain-chunk/2","luanttd-terrain-chunk/1"
  local function int(v,lo,hi)
    return type(v)=="number" and v>=lo and v<=hi and v==floor(v)
  end
  local function version(c)
    return c.schema==schema and 2 or c.schema==legacy and 1 or nil
  end
  local byte_word=D.word
  local C=D.cover
  M.cover={}
  for k,v in pairs(D.cover) do M.cover[k]=v end

  function M.for_storage(W,handle,describe)
    return {stats=function() return W.stats(handle) end,
      snapshot=function(...) return W.snapshot(handle,...) end,
      commit=function(...) return W.commit(handle,...) end,
      apply_job=function(...) return W.apply_job(handle,...) end,
      describe=describe}
  end

  function M.for_overlay(world,unpack_tile,ground)
    return {stats=world.stats,snapshot=world.snapshot,commit=world.commit,apply_job=world.apply_job,
      describe=function(word,x,z) return unpack_tile(word),ground and ground(x,z) or nil end}
  end

  local function build(source,revision,chunk)
    local s,why=source.snapshot(chunk.x1,chunk.z1,chunk.x2,chunk.z2)
    if not s then return nil,why end
    local w,h=chunk.x2-chunk.x1+1,chunk.z2-chunk.z1+1
    assert(s.width==w and s.depth==h and s.revision==revision
      and s.x==chunk.x1 and s.z==chunk.z1 and type(s.tiles)=="string" and type(s.corners)=="string"
      and #s.tiles==w*h*4 and #s.corners==(w+1)*(h+1),"inconsistent terrain source snapshot")
    local rows={}
    for z=0,h-1 do
      local row={}
      for x=0,w-1 do
        local i=z*(w+1)+x+1
        local n,a,b,d=byte(s.corners,i),byte(s.corners,i+1),byte(s.corners,i+w+1),byte(s.corners,i+w+2)
        assert(Slope.valid(n,a,b,d),"invalid terrain source corner edge")
        local slope,base=Slope.classify(n,a,b,d)
        local class,ground=source.describe(byte_word(s.tiles,4*(z*w+x)+1),chunk.x1+x,chunk.z1+z)
        assert(D.valid_descriptor(class,ground),"invalid terrain tile descriptor")
        row[#row+1]=D.profile_bytes(slope,base,max(n,a,b,d),class,ground)
      end
      rows[#rows+1]=table.concat(row)
    end
    return {schema=schema,id=chunk.id,x=chunk.x1,z=chunk.z1,width=w,depth=h,
      corners=s.corners,tiles=s.tiles,profiles=table.concat(rows)}
  end

  function M.new(source,opts)
    assert(type(source)=="table" and type(source.stats)=="function"
      and type(source.snapshot)=="function" and type(source.describe)=="function","terrain source required")
    opts=opts or {}
    local size,capacity=opts.size or 16,opts.capacity or 32
    assert(int(size,8,32) and int(capacity,1,64),"invalid terrain streamer size or capacity")
    local stats=source.stats()
    local w,h,revision=stats.width,stats.depth,stats.revision
    -- Imported stock minimum 64 includes the non-gameplay far boundary.
    assert(int(w,63,4096) and int(h,63,4096) and int(revision,0,9007199254740991),"invalid source dimensions or revision")
    local chunks_x=floor((w-1)/size)+1
    local cache={}
    local cached,total_built,total_evicted=0,0,0
    local V={}
    local function pop(id)
      if cache[id] then cache[id]=nil;cached=cached-1;total_evicted=total_evicted+1 end
    end
    local function id_for(x,z)
      return floor((z-1)/size)*chunks_x+floor((x-1)/size)
    end
    local function sync()
      local state=source.stats()
      assert(state.width==w and state.depth==h,"terrain source dimensions changed")
      if state.revision~=revision then
        -- Bypass detected: never publish stale geometry when edit details are missing.
        total_evicted=total_evicted+cached
        cache,cached,revision={},0,state.revision
      end
    end
    local function invalidate(patch)
      for _,e in ipairs(patch) do
        local fringe=e.kind=="corner" and 1 or 0
        for z=max(1,e.z-fringe),min(h,e.z) do
          for x=max(1,e.x-fringe),min(w,e.x) do
            local id=id_for(x,z)
            local ch=cache[id]
            if ch then
              local i=(e.z-ch.z)*(ch.width+fringe)+e.x-ch.x
              local prior=fringe==1 and byte(ch.corners,i+1) or byte_word(ch.tiles,4*i+1)
              if prior~=e.value then pop(id) end
            end
          end
        end
      end
    end
    local function change(method,argument,patch)
      sync()
      local f=source[method]
      if type(f)~="function" then return nil,"read-only terrain source" end
      local rev,changed=f(argument,patch)
      if rev~=nil then
        if changed then invalidate(patch) end
        revision=rev
      end
      return rev,changed
    end
    function V.commit(expected,patch) return change("commit",expected,patch) end
    function V.apply_job(ticket,patch) return change("apply_job",ticket,patch) end

    function V.update(x,z,radius,budget)
      if not int(x,1,w) or not int(z,1,h) or not int(radius,0,MAX_RADIUS) or not int(budget,0,MAX_BUDGET) then
        return nil,"invalid terrain view or work budget"
      end
      sync()
      local wanted={}
      for cz=floor((max(1,z-radius)-1)/size),floor((min(h,z+radius)-1)/size) do
        for cx=floor((max(1,x-radius)-1)/size),floor((min(w,x+radius)-1)/size) do
          local x1,z1=cx*size+1,cz*size+1
          local x2,z2=min(w,x1+size-1),min(h,z1+size-1)
          local dx=max(x1-x,x-x2,0)
          local dz=max(z1-z,z-z2,0)
          wanted[#wanted+1]={id=cz*chunks_x+cx,x1=x1,z1=z1,x2=x2,z2=z2,ring=max(dx,dz),distance=dx+dz}
        end
      end
      table.sort(wanted,function(a,b)
        if a.ring~=b.ring then return a.ring<b.ring end
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.id<b.id
      end)
      local count=min(#wanted,capacity)
      local retained={}
      for i=1,count do retained[wanted[i].id]=true end
      for id in pairs(cache) do if not retained[id] then pop(id) end end
      local chunks,built={},0
      for i=1,count do
        local c=wanted[i]
        local record=cache[c.id]
        if not record and built<budget then
          local reason
          record,reason=build(source,revision,c)
          if not record then return nil,reason end
          cache[c.id]=record
          cached,built,total_built=cached+1,built+1,total_built+1
        end
        if record then
          local copy={}
          for k,v in pairs(record) do copy[k]=v end
          chunks[#chunks+1]=copy
        end
      end
      return {schema="luanttd-terrain-view/2",x=x,z=z,radius=radius,revision=revision,
        chunks=chunks,built=built,pending=count-#chunks,excluded=#wanted-count}
    end
    function V.stats()
      sync()
      return {width=w,depth=h,revision=revision,cached=cached,built=total_built,evicted=total_evicted,
        size=size,capacity=capacity}
    end
    return V
  end

  local function chunk_index(c,x,z,fringe)
    if type(c)~="table" or not version(c) or not int(c.width,1,32) or not int(c.depth,1,32)
      or not int(c.x,1,4096) or not int(c.z,1,4096)
      or not int(x,c.x,c.x+c.width-1+fringe) or not int(z,c.z,c.z+c.depth-1+fringe) then return nil end
    return (z-c.z)*(c.width+fringe)+x-c.x
  end

  function M.corner(chunk,x,z)
    local i=chunk_index(chunk,x,z,1)
    if i and type(chunk.corners)=="string" and #chunk.corners==(chunk.width+1)*(chunk.depth+1) then
      return byte(chunk.corners,i+1)
    end
  end

  function M.profile(chunk,x,z)
    local i=chunk_index(chunk,x,z,0)
    if not i then return end
    local v=version(chunk)
    local stride=v==2 and D.stride or 6
    if type(chunk.profiles)~="string" or #chunk.profiles~=stride*chunk.width*chunk.depth
      or type(chunk.tiles)~="string" or #chunk.tiles~=4*chunk.width*chunk.depth then return end
    return D.entry(chunk.profiles,stride*i+1,byte_word(chunk.tiles,4*i+1),x,z,v)
  end

  -- These are stock's piecewise-planar diagonals from openttd/slope.lua.
  -- Face windings have upward normals in Luanti's X,Y,Z coordinates.
  local break_ns={[1]=true,[4]=true,[5]=true,[11]=true,[14]=true}
  function M.mesh(chunk,x,z)
    local p=M.profile(chunk,x,z)
    if not p or p.cover==C.VOID then return nil end
    local n,w,e,s=M.corner(chunk,x,z),M.corner(chunk,x+1,z),M.corner(chunk,x,z+1),M.corner(chunk,x+1,z+1)
    if not s then return nil end
    local x0,z0=2*x-.5,2*z-.5
    local points={{x=x0,y=n+.5,z=z0},{x=x0+2,y=w+.5,z=z0},
      {x=x0,y=e+.5,z=z0+2},{x=x0+2,y=s+.5,z=z0+2}}
    local faces=break_ns[p.mask] and {{1,3,4},{1,4,2}} or {{1,3,2},{3,4,2}}
    return points,faces,p
  end

  function M.height(chunk,x,z,u,v)
    local p=M.profile(chunk,x,z)
    if p and p.cover~=C.VOID and type(u)=="number" and u>=0 and u<=1 and type(v)=="number" and v>=0 and v<=1 then
      return .5+p.base+Slope.surface(u,v,p.mask)
    end
  end
  return M
end
