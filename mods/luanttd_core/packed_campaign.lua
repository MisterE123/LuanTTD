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
local terrains={"grass","hill","water"}
local terrain_codes={grass=1,hill=2,water=3}
local waters={"sea","river"}
local water_codes={sea=1,river=2}
local tile_fields={h=true,variant=true,terrain=true,water_class=true,stock_void=true,coastal_water=true,
  stock_clear_ground=true,stock_river_bits=true}
local function tiny_int(n,high)
  return type(n)=="number" and n>=0 and n<=high and n==floor(n)
end
-- Most cells are unimproved land/water. Skip only keys whose exact
-- representation fits this layout; every amended cell still uses the
-- general graph encoder. Fixed bytes reduce per-save GC pressure.
local function tile_bytes(t)
  local h,v,g,w=t.h,t.variant,terrain_codes[t.terrain],t.water_class
  if not (g and tiny_int(h,255) and tiny_int(v,3)) or w~=nil and not water_codes[w] then return end
  local c,r=t.stock_clear_ground,t.stock_river_bits
  if c~=nil and not tiny_int(c,255) or r~=nil and not tiny_int(r,255) then return end
  local a,b=t.stock_void,t.coastal_water
  if a~=nil and a~=true or b~=nil and b~=true then return end
  for k in next,t do if not tile_fields[k] then return end end
  local flags=g-1+4*v+16*(water_codes[w] or 0)+64*(a and 1 or 0)+128*(b and 1 or 0)
  local presence=(c~=nil and 1 or 0)+(r~=nil and 2 or 0)
  return char(TILE,h,flags,presence,c or 0,r or 0)
end

function M.encode(root,pulse)
  local chunks,fragment={},{}
  local tables,strings={},{}
  local table_count,string_count=0,0
  local tiles=type(root)=="table" and root.tiles
  local function put(value)
    fragment[#fragment+1]=value
    if #fragment==2048 then
      chunks[#chunks+1]=table.concat(fragment)
      fragment={}
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
      local id=tables[value]
      if id then tag(TABREF);uint(id);return end
      table_count=table_count+1;tables[value]=table_count
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
            local fixed=type(t)=="table" and not tables[t] and tile_bytes(t)
            if fixed then
              table_count=table_count+1;tables[t]=table_count
              put(fixed)
            else write(t) end
          end
        else
          for i=1,n do
            if pulse and i%8192==0 then pulse() end
            write(rawget(value,i))
          end
        end
      else tag(TAB) end
      for k,v in next,value do
        if not dense or type(k)~="number" or k<1 or k>n or k%1~=0 then write(k);write(v) end
      end
      tag(END)
    elseif kind=="string" then
      local id=strings[value]
      if id then tag(STRREF);uint(id);return end
      string_count=string_count+1;strings[value]=string_count
      tag(STR);str(value)
    elseif kind=="number" then
      if value==floor(value) and abs(value)<=MAX_INT then
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
  chunks[#chunks+1]=table.concat(fragment)
  return table.concat(chunks)
end

function M.decode(source)
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
    elseif tag==TILE then
      local h,flags,presence,c,r=byte(source,at,at+4)
      assert(r and presence<=3,"Invalid packed campaign ground")
      at=at+5
      local t={h=h,variant=floor(flags/4)%4,terrain=assert(terrains[flags%4+1],"Unknown packed terrain")}
      local w=floor(flags/16)%4
      if w>0 then t.water_class=assert(waters[w],"Unknown packed water") end
      if floor(flags/64)%2==1 then t.stock_void=true end
      if flags>=128 then t.coastal_water=true end
      if presence%2==1 then t.stock_clear_ground=c end
      if presence>=2 then t.stock_river_bits=r end
      tables[#tables+1]=t
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
  return root
end

return M
