-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 14.1 src/landscape.cpp RunTileLoop feedback terms
-- and tile-zero rule. General GF(2) jumps, bounded cycle index and static
-- active-window scheduling are detached LuanTTD utilities.
-- See COPYING.OpenTTD.md. This does not change the live landscape clock.
local MAX_TICKS,MAX_ACTIVE=4294967295,65536
local M={MAX_TICKS=MAX_TICKS,MAX_ACTIVE=MAX_ACTIVE,TILE_PERIOD=256}
local floor,ceil,max,min,sqrt=math.floor,math.ceil,math.max,math.min,math.sqrt
local MAX_SAFE=9007199254740991
local feedback={0xD8F,0x1296,0x2496,0x4357,0x8679,0x1030E,0x206CD,0x403FE,
                0x807B8,0x1004B2,0x2006A8,0x4004B2,0x800B87}
local function int(v,lo,hi)
  return type(v)=="number" and v>=lo and v<=hi and v==floor(v)
end

local xor8
local function build_xor8()
  local nibble={}
  for a=0,15 do for b=0,15 do
    local x,y=a,b
    local value,place=0,1
    for _=1,4 do
      if x%2~=y%2 then value=value+place end
      x,y,place=floor(x/2),floor(y/2),place*2
    end
    nibble[a*16+b]=value
  end end
  local char=string.char
  local rows={}
  for a=0,255 do
    local row={}
    local low,high=a%16*16,floor(a/16)*16
    for b=0,255 do row[b+1]=char(nibble[low+b%16]+16*nibble[high+floor(b/16)]) end
    rows[a]=table.concat(row)
  end
  return rows
end
local native_xor=bit and bit.bxor or bit32 and bit32.bxor
local function xor(a,b)
  -- All inputs are at most 24 bits, including on LuaJIT with signed bit ops.
  if native_xor then return native_xor(a,b) end
  local byte=string.byte
  local a0,b0=a%256,b%256
  local ah,bh=floor(a/256),floor(b/256)
  local low=byte(xor8[a0],b0+1)
  local mid=byte(xor8[ah%256],bh%256+1)
  return low+256*mid+65536*byte(xor8[floor(ah/256)],floor(bh/256)+1)
end

-- Generate a linear transform in GF(2) using its image on each basis
-- vector. The n×n power tables do not depend on map area as a Lua array.
local function mul_cols(cols,value)
  local acc,i=0,1
  while value>0 do
    if value%2==1 then acc=xor(acc,cols[i]) end
    value,i=floor(value/2),i+1
  end
  return acc
end

function M.new(log_x,log_z)
  assert(int(log_x,6,12) and int(log_z,6,12),"OpenTTD landscape axes require exponents 6 to 12")
  if not native_xor and not xor8 then xor8=build_xor8() end
  local bits=log_x+log_z
  local mask=feedback[bits-11]
  local area=2^bits
  local period=area-1
  local top=area/2
  local width=2^log_x
  local tiles_per_tick=area/256
  local X={period=period,tiles_per_tick=tiles_per_tick}
  local state=setmetatable({},{__mode="k"})
  local rank_babies,giant,span
  local forward,backward
  local resume_head,resume_index

  local function step(tile)
    local half=floor(tile/2)
    return tile%2==0 and half or xor(half,mask)
  end
  local function unstep(tile)
    if tile<top then return 2*tile end
    -- The feedback has its top bit set; that bit reveals the old low bit.
    return 2*xor(tile,mask)+1
  end
  local function powers(transition)
    local out={}
    local cols={}
    for i=1,bits do cols[i]=transition(2^(i-1)) end
    for i=1,bits do
      out[i]=cols
      if i<bits then
        local double={}
        for j=1,bits do double[j]=mul_cols(cols,cols[j]) end
        cols=double
      end
    end
    return out
  end
  local function reduce(steps)
    -- Lua 5.1's general floating-point modulo can round a quotient
    -- near a large exact integer. For this Mersenne period, fold
    -- power-of-two digits first; each addition stays well below 2^53.
    local low=0
    repeat
      low=low+steps%area
      steps=floor(steps/area)
    until steps==0
    return low%period
  end
  local function jump(tile,steps)
    local p
    if steps<0 then
      backward=backward or powers(unstep)
      steps,p=reduce(-steps),backward
    else
      forward=forward or powers(step)
      steps,p=reduce(steps),forward
    end
    local i=1
    while steps>0 do
      if steps%2==1 then tile=mul_cols(p[i],tile) end
      steps,i=floor(steps/2),i+1
    end
    return tile
  end
  local function nonzero(tile)
    assert(int(tile,1,period),"Expected a valid nonzero stock tile index")
    return tile
  end
  function X.step(tile) return step(nonzero(tile)) end
  function X.unstep(tile) return unstep(nonzero(tile)) end
  function X.jump(tile,steps)
    assert(int(steps,-MAX_SAFE,MAX_SAFE),"Landscape jump must be an exact signed step count")
    tile=nonzero(tile)
    return steps==0 and tile or jump(tile,steps)
  end
  function X.at(index)
    assert(int(index,0,period-1),"Canonical index must be within one nonzero cycle")
    return index==0 and 1 or jump(1,index)
  end

  local function build_index()
    span=ceil(sqrt(period))
    local babies,t={},1
    for i=0,span-1 do
      assert(babies[t]==nil,"Invalid stock nonzero cycle")
      babies[t],t=i,step(t)
    end
    -- One inverse giant step compiled as six (at most) four-bit lookups.
    local groups={}
    for off=0,bits-1,4 do
      local values={}
      local count=min(4,bits-off)
      values[0]=0
      for n=1,count do
        local block=2^(n-1)
        local base=jump(2^(off+n-1),-span)
        for digit=0,block-1 do values[block+digit]=xor(values[digit],base) end
      end
      groups[#groups+1]=values
    end
    rank_babies,giant=babies,groups
  end
  local function rank(tile)
    if tile==1 then return 0 end
    if not rank_babies then build_index() end
    for i=0,span-1 do
      local seen=rank_babies[tile]
      if seen then
        local index=span*i+seen
        if index<period then return index end
      end
      local v=giant[1][tile%16]
      local div=floor(tile/16)
      for g=2,#giant do
        v=xor(v,giant[g][div%16])
        div=floor(div/16)
      end
      tile=v
    end
    error("Stock nonzero tile missing from cycle")
  end
  function X.index(tile) return rank(nonzero(tile)) end
  function X.stats()
    return {bits=bits,visit_stride=width,tiles_per_tick=tiles_per_tick,
      baby_steps=rank_babies and span or 0,giant_slots=giant and 16*#giant or 0,
      max_rank_steps=ceil(sqrt(period)),jump_columns=bits*bits*((forward and 1 or 0)+(backward and 1 or 0))}
  end

  local function bounds(clock,ticks)
    assert(type(clock)=="table" and clock.log_x==log_x and clock.log_y==log_z,"Landscape clock dimensions mismatch")
    assert(int(clock.counter,0,MAX_SAFE),"Landscape clock needs an exact absolute counter")
    assert(int(ticks,0,min(MAX_TICKS,MAX_SAFE-clock.counter)),"Landscape window too long or over exact counter limit")
    return nonzero(clock.head),clock.counter,clock.counter+ticks
  end
  local function before_grid(start)
    local zeros=floor(start/256)
    return function(n) return n*tiles_per_tick-(floor((start+n)/256)-zeros) end
  end
  local function next_clock(head,stop,count)
    return {log_x=log_x,log_y=log_z,counter=stop,head=count==0 and head or jump(head,count)}
  end
  function X.skip(clock,ticks)
    local head,start,stop=bounds(clock,ticks)
    local count=before_grid(start)(ticks)
    return next_clock(head,stop,count),count
  end

  -- A compiled set is immutable and owned by this exact index. Workers
  -- may instead transfer plain tile IDs and compile on their own index.
  function X.compile(ids,previous)
    assert(type(ids)=="table" and getmetatable(ids)==nil,"An ordinary dense array of active tile IDs is required")
    local limit=min(MAX_ACTIVE,area)
    local size=0
    for k in pairs(ids) do
      assert(int(k,1,limit),"Active tile set exceeds bounds")
      size=size+1
    end
    local prior
    if previous~=nil then
      prior={}
      for _,record in ipairs(assert(state[previous],"Prior active set belongs to another landscape index")) do
        prior[record.tile]=record
      end
    end
    local ordered,seen={},{}
    for i=1,size do
      local tile=ids[i]
      assert(int(tile,0,period) and not seen[tile],"Invalid, sparse or duplicate active tile ID")
      seen[tile]=true
      ordered[i]=prior and prior[tile] or {tile=tile,index=tile~=0 and rank(tile) or nil}
    end
    local handle={}
    state[handle]=ordered
    return handle
  end

  local function less(a,b)
    return a.tick<b.tick or a.tick==b.tick and a.slot<b.slot
  end
  local function push(heap,q)
    local i=#heap+1
    while i>1 do
      local j=floor(i/2)
      if not less(q,heap[j]) then break end
      heap[i],i=heap[j],j
    end
    heap[i]=q
  end
  local function remove(heap)
    local q=heap[1]
    local count=#heap
    local tail=heap[count]
    heap[count]=nil
    count=count-1
    if count>0 then
      local i=1
      while 2*i<=count do
        local c=2*i
        if c<count and less(heap[c+1],heap[c]) then c=c+1 end
        if not less(heap[c],tail) then break end
        heap[i],i=heap[c],c
      end
      heap[i]=tail
    end
    return q
  end

  -- Schedule one occurrence per active record in the heap, even when the
  -- window covers many complete cycles. No skipped tile or empty tick is
  -- walked when the caller asks for a pure iterator.
  function X.window(clock,ticks,active)
    local head,start,stop=bounds(clock,ticks)
    local records=state[active]
    assert(records,"Active set must be compiled by this landscape index")
    local prefix=before_grid(start)
    local count=prefix(ticks)
    local final=next_clock(head,stop,count)
    local head_index
    local heap={}
    local function position(q)
      -- Locate first tick whose nonzero prefix is greater than this
      -- offset. Nonzero ordinal 0 in a tile-zero tick starts at slot 1.
      local lo=max(1,floor(q.offset/tiles_per_tick)+1)
      local hi=ticks
      while lo<hi do
        local mid=floor((lo+hi)/2)
        if prefix(mid)<=q.offset then lo=mid+1 else hi=mid end
      end
      local tick=start+lo
      q.tick,q.slot=tick,q.offset-prefix(lo-1)+(tick%256==0 and 1 or 0)
    end
    if ticks>0 then
      for _,record in ipairs(records) do
        if record.tile==0 then
          local tick=(floor(start/256)+1)*256
          if tick<=stop then push(heap,{tile=0,tick=tick,slot=0}) end
        else
          head_index=head_index or (head==resume_head and resume_index or rank(head))
          local offset=(record.index-head_index)%period
          if offset<count then
            local q={tile=record.tile,offset=offset}
            position(q)
            push(heap,q)
          end
        end
      end
    end
    -- One coherent cursor hint per index. Sequential windows do not
    -- repeat the giant-step lookup. Arbitrary restored branches still
    -- work because a mismatched head can always be ranked from scratch.
    if head_index then
      resume_head,resume_index=final.head,(head_index+reduce(count))%period
    end
    local function iter()
      if #heap==0 then return end
      local q=remove(heap)
      local tile,tick,slot=q.tile,q.tick,q.slot
      if tile==0 then
        if stop-tick>=256 then q.tick=tick+256;push(heap,q) end
      else
        q.offset=q.offset+period
        if q.offset<count then position(q);push(heap,q) end
      end
      return tile,tick,slot,tile%width,floor(tile/width)
    end
    return iter,final
  end

  -- Use only when inactive callbacks would have no effects or RNG
  -- draws. Membership must stay valid for the whole scheduled window.
  -- before_tick (if supplied) is still called for every source tick.
  function X.advance_active(clock,ticks,active,visit,before_tick)
    assert(type(visit)=="function" and (not before_tick or type(before_tick)=="function"),"Invalid landscape callback")
    local next_visit,final=X.window(clock,ticks,active)
    if before_tick then
      local tile,t,slot,x,z=next_visit()
      for tick=clock.counter+1,final.counter do
        before_tick(tick)
        while t==tick do
          visit(tile,t,slot,x,z)
          tile,t,slot,x,z=next_visit()
        end
      end
    else
      for tile,tick,slot,x,z in next_visit do visit(tile,tick,slot,x,z) end
    end
    clock.head,clock.counter=final.head,final.counter
  end
  return X
end
return M
