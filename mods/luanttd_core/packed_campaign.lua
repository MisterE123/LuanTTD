-- Compact Lua state graph for wide checkpoints. The standard Luanti
-- serializer emits one Lua chunk, which can exceed LuaJIT's compiler
-- limits with a dense 512² map. This format never compiles saved code.
-- Integers use unsigned base-128 varints; strings/tables are interned
-- on first encounter so references and cycles survive the round trip.
local M={}
local byte,char,sub=string.byte,string.char,string.sub
local floor,abs=math.floor,math.abs
local MAX_INT=9007199254740991
local symbols={}
for n=0,255 do symbols[n]=char(n) end
local END,NIL,FALSE,TRUE,UINT,SINT,NUM,STR,STRREF,TAB,TABREF,ARRAY,TILE=0,1,2,3,4,5,6,7,8,9,10,11,12
-- Stock routes and terrain arrays contain many compact non-negative
-- integers. Reuse their exact tag+varint bytes instead of dispatching to the
-- generic emitter and appending each constituent byte one at a time.
-- This changes neither the graph ordering nor the on-disk format.
local short_uint={}
for n=0,8191 do
  short_uint[n]=n<128 and char(UINT,n) or char(UINT,128+n%128,floor(n/128))
end
-- Repeated graph keys and values share their packed string reference bytes.
-- Dictionary IDs still follow first encounter; only the emitter changes.
local function string_ref(n)
  if n<128 then return char(STRREF,n) end
  if n<16384 then return char(STRREF,128+n%128,floor(n/128)) end
  local result=symbols[STRREF]
  while n>=128 do result=result..symbols[128+n%128];n=floor(n/128) end
  return result..symbols[n]
end
local WOODED_TILE,CROP=13,14
local terrains={"grass","hill","water"}
local terrain_codes={grass=1,hill=2,water=3}
local waters={"sea","river"}
local water_codes={sea=1,river=2}
local tile_fields={h=true,variant=true,terrain=true,water_class=true,stock_void=true,coastal_water=true,
  stock_clear_ground=true,stock_river_bits=true,stock_water_rocks=true,wood=true}
local wood_fields={class=true,type=true,count=true,ground=true,density=true,growth=true,water_class=true}
local function tiny_int(n,high)
  return type(n)=="number" and n>=0 and n<=high and n==floor(n)
end
-- Most cells are unimproved land/water. Skip only keys whose exact
-- representation fits this layout; every amended cell still uses the
-- general graph encoder. Fixed bytes reduce per-save GC pressure.
local base_cells={}
for h=0,255 do
  for f=0,47 do base_cells[h*48+f]=char(TILE,h,f,0,0,0) end
end
local function tile_bytes(t,table_bucket)
  local h,v,g,w=t.h,t.variant,terrain_codes[t.terrain],t.water_class
  if not (g and tiny_int(h,255) and tiny_int(v,3)) or w~=nil and not water_codes[w] then return end
  -- These raw keys account for all fields in the ordinary record.
  -- Same bytes as the full encoder; richer or decorated cells still
  -- take the general branch so no special field disappears.
  if getmetatable(t)==nil then
    local a=next(t)
    local b=next(t,a)
    local c=next(t,b)
    local d=next(t,c)
    if d==nil and w==nil then return base_cells[h*48+g-1+4*v] end
    if w~=nil and d~=nil and next(t,d)==nil then
      return base_cells[h*48+g-1+4*v+16*water_codes[w]]
    end
  end
  local c,r=t.stock_clear_ground,t.stock_river_bits
  if c~=nil and not tiny_int(c,255) or r~=nil and not tiny_int(r,255) then return end
  local a,b,k=t.stock_void,t.coastal_water,t.stock_water_rocks
  if a~=nil and a~=true or b~=nil and b~=true or k~=nil and k~=true then return end
  for k in next,t do if not tile_fields[k] then return end end
  local flags=g-1+4*v+16*(water_codes[w] or 0)+64*(a and 1 or 0)+128*(b and 1 or 0)
  local presence=(c~=nil and 1 or 0)+(r~=nil and 2 or 0)+(k and 4 or 0)
  local wood=t.wood
  if wood~=nil then
    if type(wood)~="table" then return end
    local wood_bucket=table_bucket and table_bucket(wood)
    if wood_bucket and wood_bucket[wood] then return end
    local class,kind,count=wood.class,wood.type,wood.count
    local ground,density,growth,salt=wood.ground,wood.density,wood.growth,wood.water_class
    if not (tiny_int(class,255) and tiny_int(kind,255) and tiny_int(count,255)
      and tiny_int(ground,255) and tiny_int(density,255) and tiny_int(growth,255))
      or salt~=nil and salt~="sea" then return end
    for key in next,wood do if not wood_fields[key] then return end end
    return char(WOODED_TILE,h,flags,presence,c or 0,r or 0,class,kind,count,ground,density,growth,salt and 1 or 0),wood,wood_bucket
  end
  return char(TILE,h,flags,presence,c or 0,r or 0)
end

-- A stock crop's compact payload contains fixed kind/ground strings,
-- a small record of scalar growth state and a sparse fence table.
-- Unknown, nested or externally interned fields use the general graph.
local crop_fields={kind=true,ground=true,variant=true,industry=true,counter=true,fences=true,
  slope=true,base=true,last_tick=true}
local function crop_bytes(t,table_bucket)
  if type(t)~="table" or getmetatable(t)~=nil or t.kind~="clear" or t.ground~="field" then return end
  local bucket=table_bucket(t)
  if bucket[t] then return end
  local f=t.fences
  if type(f)~="table" or getmetatable(f)~=nil then return end
  local fences=table_bucket(f)
  if fences[f] then return end
  for k in next,t do if not crop_fields[k] then return end end
  local v,c,b,s=t.variant,t.counter,t.base,t.slope
  local i,l=t.industry,t.last_tick
  if not (tiny_int(v,255) and tiny_int(c,255) and tiny_int(b,255) and tiny_int(s,255)
      and (i==nil or tiny_int(i,65535)) and (l==nil or tiny_int(l,4294967295))) then return end
  local mask=0
  for k,value in next,f do
    if not tiny_int(k,3) or not tiny_int(value,255) then return end
    mask=mask+2^k
  end
  mask=mask+(i and 16 or 0)+(l and 32 or 0)
  i,l=i or 0,l or 0
  return char(CROP,v,c,b,s,mask,i%256,floor(i/256),l%256,floor(l/256)%256,
    floor(l/65536)%256,floor(l/16777216),f[0] or 0,f[1] or 0,f[2] or 0,f[3] or 0),bucket,f,fences
end

local function decode_cell(source,at,tag)
  local h,flags,presence,c,r=byte(source,at,at+4)
  assert(r and presence<=7,"Invalid packed campaign ground")
  at=at+5
  local t={h=h,variant=floor(flags/4)%4,terrain=assert(terrains[flags%4+1],"Unknown packed terrain")}
  local w=floor(flags/16)%4
  if w>0 then t.water_class=assert(waters[w],"Unknown packed water") end
  if floor(flags/64)%2==1 then t.stock_void=true end
  if flags>=128 then t.coastal_water=true end
  if presence%2==1 then t.stock_clear_ground=c end
  if floor(presence/2)%2==1 then t.stock_river_bits=r end
  if presence>=4 then t.stock_water_rocks=true end
  if tag==WOODED_TILE then
    local c,k,n,g,d,v,salt=byte(source,at,at+6)
    assert(salt and salt<=1,"Invalid packed woodland")
    at=at+7
    local wood={class=c,type=k,count=n,ground=g,density=d,growth=v,water_class=salt==1 and "sea" or nil}
    t.wood=wood
  end
  return t,at
end

-- The main VM no longer mutates the original campaign after handoff.
-- Keep only a coordinate fallback for bootstrap presentation until real
-- sectors arrive. Unusual tiles keep their original field tables;
-- ordinary land, water and woodland use the exact checkpoint layout.
function M.host_tile_view(tiles)
  local n=#tiles
  local pages,rows,rich={},{},{}
  local page_size,cell_size,cache_size=4096,13,512
  local empty=string.rep("\0",cell_size)
  local padding=sub(empty,1,7)
  for i=1,n do
    local tile=tiles[i]
    local encoded=type(tile)=="table" and tile_bytes(tile)
    if not encoded then
      rich[i]=tile
      encoded=empty
    elseif #encoded==6 then
      encoded=encoded..padding
    end
    local offset=(i-1)%page_size+1
    rows[offset]=encoded
    if offset==page_size or i==n then
      pages[#pages+1]=table.concat(rows,"",1,offset)
    end
  end
  local cache,ids={},{}
  return setmetatable({},{
    __index=function(_,i)
      if type(i)~="number" or i<1 or i>n or i%1~=0 then return end
      if rich[i] then return rich[i] end
      local slot=(i-1)%cache_size+1
      if ids[slot]==i then return cache[slot] end
      local page=pages[floor((i-1)/page_size)+1]
      local first=((i-1)%page_size)*cell_size+1
      local tag=byte(page,first)
      if tag~=TILE and tag~=WOODED_TILE then return end
      local tile=decode_cell(page,first+1,tag)
      ids[slot],cache[slot]=i,tile
      return tile
    end,
    __newindex=function() error("snapshot tiles are owned by the campaign worker") end,
  })
end

-- The caller owns a stable snapshot for the entire encode. Periodic
-- pulses may service read-only queries but must not mutate that graph.
local function encode(root,pulse,identity)
  local chunks,fragment={},{}
  local fragment_count=0
  local tables,strings={},{}
  local table_count,string_count=0,0
  local tiles=type(root)=="table" and root.tiles
  local campaign=identity and root.campaign
  local crops=campaign and rawget(campaign,"stock_farm_fields")
  local function table_bucket() return tables end
  if type(tiles)=="table" and #tiles>=262144 then
    -- Dense terrain used to resize one million-key reference hash in
    -- a single uninterruptible operation. Select smaller temporary
    -- buckets by stable raw shape fields, not by the path to a table.
    -- All aliases still compare by object, and a single encounter
    -- counter supplies the exact same IDs and checkpoint bytes.
    local buckets={}
    for i=0,47 do buckets[i]={} end
    table_bucket=function(value)
      local variant=rawget(value,"variant")
      if type(variant)=="number" and variant>=0 and variant<=3 and variant%1==0 then
        local h=rawget(value,"h")
        if type(h)=="number" and h>=0 and h<=255 and h%1==0 then return buckets[4*(h%8)+variant] end
      end
      local tree=rawget(value,"type")
      if type(tree)=="number" and tree>=0 and tree<=255 and tree%1==0 then return buckets[32+tree%16] end
      return tables
    end
  end
  local function put(value)
    fragment_count=fragment_count+1
    fragment[fragment_count]=value
    if fragment_count==2048 then
      -- Reuse one scratch array. Allocating another 2048-slot table per
      -- fragment leaves tens of MiB of garbage in a dense campaign save.
      chunks[#chunks+1]=table.concat(fragment)
      fragment_count=0
      -- A large sparse registry may never hit an array pulse.
      if pulse and #chunks%8==0 then pulse() end
    end
  end
  local function tag(n) put(symbols[n]) end
  local function uint(n)
    while n>=128 do tag(128+n%128);n=floor(n/128) end
    tag(n)
  end
  local function str(value)
    uint(#value);put(value)
  end
  local write
  write=function(value)
    local kind=type(value)
    if kind=="table" then
      if identity then value=identity(value) end
      local bucket=table_bucket(value)
      local id=bucket[value]
      if id then tag(TABREF);uint(id);return end
      table_count=table_count+1;bucket[value]=table_count
      local n=#value
      -- Only omit array keys when every member through #value exists.
      -- Most campaign tiles are records, not arrays.
      local dense=n>0
      if dense then
        for i=1,n do
          if pulse and i%8192==0 then pulse() end
          if rawget(value,i)==nil then dense=false;break end
        end
      end
      if dense then
        tag(ARRAY);uint(n)
        if value==tiles then
          for i=1,n do
            if pulse and i%8192==0 then pulse() end
            local t=rawget(value,i)
            local fixed,wood,tree_bucket
            local bucket=type(t)=="table" and table_bucket(t)
            if bucket and not bucket[t] then fixed,wood,tree_bucket=tile_bytes(t,table_bucket) end
            if fixed then
              table_count=table_count+1;bucket[t]=table_count
              if wood then table_count=table_count+1;tree_bucket[wood]=table_count end
              put(fixed)
            else write(t) end
          end
        else
          for i=1,n do
            if pulse and i%8192==0 then pulse() end
            local member=rawget(value,i)
            local bytes=short_uint[member]
            if bytes then put(bytes) else write(member) end
          end
        end
      else tag(TAB) end
      local keys_seen=0
      local dense_pulse=pulse and dense and n>=8192
      for k,v in next,value do
        -- Covered numeric keys do not emit fragments on this pass.
        if dense_pulse then
          keys_seen=keys_seen+1
          if keys_seen%8192==0 then pulse() end
        end
        if not dense or type(k)~="number" or k<1 or k>n or k%1~=0 then
          local key=strings[k]
          if key then put(key) else write(k) end
          local payload,bucket,f,fences
          if value==crops then payload,bucket,f,fences=crop_bytes(v,table_bucket) end
          if payload then
            table_count=table_count+1;bucket[v]=table_count
            table_count=table_count+1;fences[f]=table_count
            put(payload)
          else write(v) end
        end
      end
      tag(END)
    elseif kind=="string" then
      local ref=strings[value]
      if ref then put(ref);return end
      string_count=string_count+1;strings[value]=string_ref(string_count)
      tag(STR);str(value)
    elseif kind=="number" then
      local bytes=short_uint[value]
      if bytes then put(bytes)
      elseif value==floor(value) and abs(value)<=MAX_INT then
        tag(value<0 and SINT or UINT);uint(abs(value))
      else
        tag(NUM)
        str(value~=value and "nan" or value==math.huge and "+inf" or value==-math.huge and "-inf"
          or ("%.17g"):format(value))
      end
    elseif kind=="boolean" then tag(value and TRUE or FALSE)
    elseif kind=="nil" then tag(NIL)
    else error("Unsupported packed campaign value: "..kind) end
  end
  write(root)
  if fragment_count~=0 then
    chunks[#chunks+1]=table.concat(fragment,"",1,fragment_count)
  end
  if pulse then pulse() end
  local output=table.concat(chunks)
  if identity then
    -- Detached rich graph wrapper has no physical slot vector; this
    -- dictionary has one namespace and is only read during capture.
    assert(not tiles)
    return output,tables
  end
  return output
end

local function decode(source,identity)
  assert(type(source)=="string" and #source>0,"Missing packed campaign data")
  local tables,strings={},{}
  local at=1
  local function take()
    local n=assert(byte(source,at),"Truncated packed campaign")
    at=at+1
    return n
  end
  local function uint()
    local value,scale=0,1
    for _=1,8 do
      local n=take()
      value=value+n%128*scale
      if n<128 then
        assert(value<=MAX_INT,"Packed campaign integer overflow")
        return value
      end
      scale=scale*128
    end
    error("Packed campaign integer overflow")
  end
  local function str()
    local size=uint()
    assert(size<=#source-at+1,"Truncated packed campaign string")
    local v=sub(source,at,at+size-1);at=at+size
    return v
  end
  local read
  read=function(tag,depth)
    assert(depth<=256,"Packed campaign tables are nested too deeply")
    if tag==TAB or tag==ARRAY then
      local t,n={},0
      tables[#tables+1]=t
      if tag==ARRAY then
        n=uint()
        assert(n<=#source-at+1,"Truncated packed campaign array")
        for i=1,n do
          local value=read(take(),depth+1)
          assert(value~=nil,"Packed campaign array has a hole")
          t[i]=value
        end
      end
      while true do
        local k=take()
        if k==END then return t end
        local key=read(k,depth+1)
        assert(key~=nil and t[key]==nil,"Duplicate or empty packed campaign key")
        local value=read(take(),depth+1)
        assert(value~=nil,"Packed campaign contains a nil table value")
        t[key]=value
      end
    elseif tag==TILE or tag==WOODED_TILE then
      local t,after=decode_cell(source,at,tag)
      at=after
      tables[#tables+1]=t
      if t.wood then tables[#tables+1]=t.wood end
      return t
    elseif tag==CROP then
      local v,c,b,s,mask,i0,i1,t0,t1,t2,t3,f0,f1,f2,f3=byte(source,at,at+14)
      assert(f3 and mask<=63,"Invalid packed campaign field record")
      at=at+15
      local f={}
      if mask%2==1 then f[0]=f0 end
      if floor(mask/2)%2==1 then f[1]=f1 end
      if floor(mask/4)%2==1 then f[2]=f2 end
      if floor(mask/8)%2==1 then f[3]=f3 end
      local t={kind="clear",ground="field",variant=v,counter=c,base=b,slope=s,fences=f,
        industry=floor(mask/16)%2==1 and i0+i1*256 or nil,
        last_tick=mask>=32 and t0+t1*256+t2*65536+t3*16777216 or nil}
      tables[#tables+1]=t;tables[#tables+1]=f
      return t
    elseif tag==STR then
      local value=str()
      strings[#strings+1]=value
      return value
    elseif tag==TABREF then return assert(tables[uint()],"Unknown packed campaign table")
    elseif tag==STRREF then return assert(strings[uint()],"Unknown packed campaign string")
    elseif tag==UINT then return uint()
    elseif tag==SINT then return -uint()
    elseif tag==NUM then
      local value=str()
      if value=="nan" then return 0/0 end
      if value=="+inf" then return math.huge end
      if value=="-inf" then return -math.huge end
      return assert(tonumber(value),"Invalid packed campaign number")
    elseif tag==TRUE then return true
    elseif tag==FALSE then return false
    elseif tag==NIL then return nil
    else error("Unknown packed campaign field") end
  end
  local root=read(take(),0)
  assert(at==#source+1,"Trailing bytes in packed campaign")
  -- Resolved references already point at their decoded objects. Drop
  -- the decoder's temporary graph and input bytes explicitly: on
  -- Luanti's LuaJIT, recursive decode state can outlive this return.
  if identity then
    local key=tables
    tables,strings,source,read=nil,nil,nil,nil
    return root,key
  end
  tables,strings,source,read=nil,nil,nil,nil
  return root
end

-- The public graph primitives retain their original bytes. Only a
-- wide checkpoint chooses the independent, alias-aware raster format.
function M.encode(state,pulse) return encode(state,pulse) end
function M.decode(source) return decode(source) end
local raster
local function wide()
  if not raster then
    local path=core and core.get_modpath and core.get_modpath("luanttd_core")
      or "mods/luanttd_core"
    raster=dofile(path.."/checkpoint_raster.lua")(tile_bytes,decode_cell,encode,decode)
  end
  return raster
end
function M.prepare_wide(state)
  local grid=state.stock_generated_profile and state.corner_grid
  if type(grid)~="table" or not tiny_int(grid.width,4096) or not tiny_int(grid.depth,4096)
      or grid.width<64 or grid.depth<64 then return end
  local n=grid.width*grid.depth
  -- Leave small worlds and larger, unqualified memory footprints on the
  -- general graph path. Both paths preserve the same authoritative state.
  if n<262144 or n>1048576 then return end
  return wide().prepare(state,n)
end
function M.decode_wide(source)
  return wide().restore(source)
end
return M
