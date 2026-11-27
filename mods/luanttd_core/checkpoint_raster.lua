-- Save projection, not a second simulation. Serialize at an exact
-- authority boundary. Only the stock owner may carry compact values
-- between boundaries, using its own receipts rather than renderer dirtiness.
return function(record,decode_cell,encode,decode)
  local M={}
  local min,floor=math.min,math.floor
  local char,byte,sub=string.char,string.byte,string.sub
  local concat=table.concat
  local width,block=13,2048
  local blank,pad=string.rep("\0",width),string.rep("\0",width-6)
  local function u32(n)
    assert(n>=0 and n<4294967296 and n==floor(n))
    return char(n%256,floor(n/256)%256,floor(n/65536)%256,floor(n/16777216))
  end
  local function read_u32(source,at)
    local a,b,c,d=byte(source,at,at+3)
    assert(d,"Truncated raster checkpoint")
    return a+256*b+65536*c+16777216*d
  end

  function M.prepare(root,n,observer)
    local slots=root.tiles
    if type(slots)~="table" or slots==root or getmetatable(root)~=nil or getmetatable(slots)~=nil or #slots~=n then return end
    local witness,duplicate,seen={},{},{}
    for i=1,n do
      local tile=rawget(slots,i)
      if type(tile)~="table" or getmetatable(tile)~=nil then return end
      witness[i]=tile
      local previous=seen[tile]
      if previous then duplicate[i]=previous else seen[tile]=i end
    end
    -- Only the array's pointer sequence is pinned. This does not pin a
    -- tile's fields or nested woodland. First and synchronous captures
    -- still reclassify the whole surface. Only the autonomous owner can
    -- advance an already exact immutable page set between checkpoints.
    local surface
    if observer and not next(duplicate) then
      local mod=core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
      local pages=dofile(mod.."/checkpoint_pages.lua")
      surface=dofile(mod.."/checkpoint_surface_pages.lua")(pages,record).new(root,slots,witness,n,74)
      observer.touch,observer.finish,observer.invalidate=surface.touch,surface.finish,surface.invalidate
    end
    return function(current,pulse)
      if current~=root or current.tiles~=slots or #slots~=n or getmetatable(slots)~=nil then return end
      local pages,cells={""},{}
      local rich,shared_wood,seen_wood={},{},{}
      local external_tile,external_wood={},{}
      local tick=current.passenger_house_clock and current.passenger_house_clock.counter
      local staged=pulse and surface and not observer.disabled
      local reused=staged and surface.capture(tick,pages,rich)
      if not reused then
        for first=1,n,block do
          local last=min(first+block-1,n)
          for i=first,last do
            local t=slots[i]
            if t~=witness[i] or getmetatable(t)~=nil then return end
            local raw
            if not duplicate[i] then
              if type(t.wood)=="table" and getmetatable(t.wood)~=nil then return end
              raw=record(t)
              if raw then
                if #raw==width then
                  local tree=t.wood
                  local other=seen_wood[tree]
                  if other then shared_wood[i]=other else seen_wood[tree]=i end
                else raw=raw..pad end
              else rich[i]=t end
            end
            cells[i-first+1]=raw or blank
          end
          pages[#pages+1]=concat(cells,"",1,last-first+1)
          if pulse then pulse() end
        end
      end
      -- Dense vectors may still carry non-array fields. Preserve them in
      -- the same graph object that will become the restored tile vector.
      local scanned=0
      for key,value in pairs(slots) do
        if type(key)~="number" or key<1 or key>n or key~=floor(key) then rich[key]=value end
        scanned=scanned+1
        if pulse and scanned%8192==0 then pulse() end
      end
      local view={}
      for key,value in pairs(root) do if key~="tiles" then view[key]=value end end
      local graph,ids=encode({campaign=view,rich=rich},pulse,function(value)
        if value==root then return view end
        if value==slots then return rich end
        return value
      end)
      -- The rich graph already interned references from stations,
      -- routes, or any other data that share a literal tile/tree. Use
      -- those exact identities rather than reconstructing a second object.
      for i=1,n do
        local t=witness[i]
        if reused and (rawget(slots,i)~=t or getmetatable(t)~=nil or
          type(t.wood)=="table" and getmetatable(t.wood)~=nil) then
          surface.invalidate();return nil
        end
        if not rich[i] and not duplicate[i] then
          local key=ids[t]
          if key then external_tile[i]=key
          elseif type(t.wood)=="table" then
            key=ids[t.wood]
            if key then external_wood[i]=key end
          end
        end
        if pulse and i%8192==0 then pulse() end
      end
      local links=encode({external_tile,external_wood,duplicate,shared_wood},pulse)
      if staged and not reused and not next(shared_wood) then
        surface.adopt(tick,pages,block,rich,seen_wood)
      end
      pages[1]=u32(n*width)..u32(#graph)
      pages[#pages+1]=graph
      pages[#pages+1]=links
      return concat(pages)
    end
  end

  function M.restore(source)
    assert(type(source)=="string" and #source>=8,"Missing raster checkpoint")
    local n,g=read_u32(source,1),read_u32(source,5)
    assert(n>=width and n<=1048576*width and n%width==0 and g>0 and n+g+8<#source,
      "Invalid raster checkpoint extent")
    local at=9+n
    local root,ids=decode(sub(source,at,at+g-1),true)
    local links=decode(sub(source,at+g))
    local s,tiles=root.campaign,root.rich
    assert(type(s)=="table" and type(tiles)=="table","Invalid raster checkpoint graph")
    local grid=s.corner_grid
    assert(type(grid)=="table" and grid.width*grid.depth==n/width,"Raster dimensions do not match campaign")
    local external_tile,external_wood,duplicate,shared_wood=unpack(links)
    assert(type(external_tile)=="table" and type(external_wood)=="table" and
      type(duplicate)=="table" and type(shared_wood)=="table","Invalid raster checkpoint links")
    for i=1,n/width do
      local pos=9+(i-1)*width
      local tag=byte(source,pos)
      if not tiles[i] and not duplicate[i] then
        assert(tag==12 or tag==13,"Missing raster checkpoint tile")
        local alias=external_tile[i]
        local t=alias and assert(ids[alias]) or decode_cell(source,pos+1,tag)
        if external_wood[i] then t.wood=assert(ids[external_wood[i]]) end
        tiles[i]=t
      else
        assert(tag==0,"Duplicate raster checkpoint tile")
      end
    end
    for i,j in pairs(duplicate) do
      assert(type(i)=="number" and i%1==0 and i>=1 and i<=n/width and
        type(j)=="number" and j%1==0 and j>=1 and j<i and not tiles[i],"Invalid shared checkpoint tile")
      tiles[i]=assert(tiles[j])
    end
    for i,j in pairs(shared_wood) do
      assert(type(i)=="number" and i%1==0 and i>=1 and i<=n/width and
        type(j)=="number" and j%1==0 and j>=1 and j<i,"Invalid shared checkpoint tree")
      tiles[i].wood=assert(tiles[j].wood)
    end
    s.tiles=tiles
    return s
  end
  return M
end
