-- Sparse storage, not world generation or an OpenTTD save-file decoder.
-- Logical X/Z axes and north-corner order match openttd/terrain.lua.
local M={}
local floor,abs,min,max=math.floor,math.abs,math.min,math.max
local byte,char=string.byte,string.char
local CHUNK,MAX_SIDE,MAX_PATCH=32,64,8448
local U32=4294967295
local states=setmetatable({},{__mode="k"})
local tickets=setmetatable({},{__mode="k"})

local function integer(n,lo,hi)
  return type(n)=="number" and n>=lo and n<=hi and n==floor(n)
end

local function plain(t) return type(t)=="table" and getmetatable(t)==nil end
local function state(handle) return states[handle] end
local function xy(stride,id) return id%stride+1,floor(id/stride)+1 end
local function index(w,h,x,z)
  if integer(x,1,w) and integer(z,1,h) then return (z-1)*w+x-1 end
end

local function chunk(s,x,z)
  -- The inclusive extra corner is owned by the last chunk, never an extra chunk.
  return floor((min(z,s.depth)-1)/CHUNK)*s.chunks_x+floor((min(x,s.width)-1)/CHUNK)
end

local function base(s,corner,x,z)
  local callback=corner and s.sample_corner or s.sample_tile
  local value=callback(s.seed,x,z)
  assert(integer(value,0,corner and 255 or U32),"invalid procedural base sample")
  assert(corner or not s.validate_tile_word or s.validate_tile_word(value),"invalid typed procedural tile word")
  return value
end

local function read(s,corner,x,z,id)
  local part=s.chunks[chunk(s,x,z)]
  local value=part and (corner and part.corners or part.tiles)[id]
  if value~=nil then return value end
  return base(s,corner,x,z)
end

function M.new(width,depth,opts)
  assert(integer(width,64,4096) and integer(depth,64,4096),"dimensions must be 64–4096")
  assert(plain(opts) and type(opts.base_id)=="string" and #opts.base_id<=127
    and opts.base_id:match("^[A-Za-z0-9_.:/%-]+$"),"a versioned base_id is required")
  assert(integer(opts.seed,0,U32),"uint32 base seed required")
  assert(type(opts.corner)=="function" and type(opts.tile)=="function","base callbacks required")
  assert(opts.validate_tile_word==nil or type(opts.validate_tile_word)=="function","invalid typed tile validator")
  local handle={}
  states[handle]={width=width,depth=depth,seed=opts.seed,base_id=opts.base_id,
    sample_corner=opts.corner,sample_tile=opts.tile,validate_tile_word=opts.validate_tile_word,
    chunks={},chunks_x=floor((width-1)/CHUNK)+1,
    revision=0,nchunks=0,ncorners=0,ntiles=0}
  return handle
end

function M.tile_id(handle,x,z)
  local s=state(handle)
  return s and index(s.width,s.depth,x,z)
end

function M.tile_xy(handle,id)
  local s=state(handle)
  if s and integer(id,0,s.width*s.depth-1) then return xy(s.width,id) end
end

function M.corner_id(handle,x,z)
  local s=state(handle)
  return s and index(s.width+1,s.depth+1,x,z)
end

function M.corner_xy(handle,id)
  local s=state(handle)
  if s and integer(id,0,(s.width+1)*(s.depth+1)-1) then return xy(s.width+1,id) end
end

function M.get_tile(handle,x,z)
  local id=M.tile_id(handle,x,z)
  if id then return read(state(handle),false,x,z,id) end
end

function M.get_corner(handle,x,z)
  local id=M.corner_id(handle,x,z)
  if id then return read(state(handle),true,x,z,id) end
end

function M.tile_corners(handle,x,z)
  if not M.tile_id(handle,x,z) then return nil end
  return M.get_corner(handle,x,z),M.get_corner(handle,x+1,z),
    M.get_corner(handle,x,z+1),M.get_corner(handle,x+1,z+1)
end

function M.stats(handle)
  local s=state(handle)
  if not s then return nil end
  return {width=s.width,depth=s.depth,chunk_size=CHUNK,seed=s.seed,base_id=s.base_id,
    revision=s.revision,chunks=s.nchunks,corners=s.ncorners,tiles=s.ntiles}
end

-- Iterate count, rather than trusting the undefined length of sparse arrays.
local function read_patch(s,patch,region)
  if not plain(patch) then return nil,"patch must be a plain dense array" end
  local count=0
  for key in pairs(patch) do
    if not integer(key,1,MAX_PATCH) then return nil,"patch exceeds limit or has non-array keys" end
    count=count+1
  end
  local result={corners={},tiles={}}
  for i=1,count do
    local edit=patch[i]
    if not plain(edit) then return nil,"patch must be a plain dense array of edits" end
    local corner=edit.kind=="corner"
    if not corner and edit.kind~="tile" then return nil,"invalid edit kind" end
    local fringe=corner and 1 or 0
    local x,z,v=edit.x,edit.z,edit.value
    local id=index(s.width+fringe,s.depth+fringe,x,z)
    if not id or not integer(v,0,corner and 255 or U32) then return nil,"invalid edit coordinate or value" end
    if not corner and s.validate_tile_word and not s.validate_tile_word(v) then
      return nil,"invalid typed tile word"
    end
    if region and (x<region.x1 or x>region.x2+fringe or z<region.z1 or z>region.z2+fringe) then
      return nil,"edit is outside the job snapshot"
    end
    local plane=corner and result.corners or result.tiles
    if plane[id]~=nil then return nil,"duplicate edit" end
    plane[id]=v
  end
  return result
end

local function valid_edges(s,edits)
  local w,h=s.width+1,s.depth+1
  local function edge(x,z,id,v)
    local n=edits[id]
    if n==nil then n=read(s,true,x,z,id) end
    return abs(v-n)<=1
  end
  for id,v in pairs(edits) do
    local x,z=xy(w,id)
    if (x>1 and not edge(x-1,z,id-1,v))
      or (x<w and not edge(x+1,z,id+1,v))
      or (z>1 and not edge(x,z-1,id-w,v))
      or (z<h and not edge(x,z+1,id+w,v)) then
      return false
    end
  end
  return true
end

local function duplicate(src)
  local dst={}
  if src then for id,v in pairs(src) do dst[id]=v end end
  return dst
end

local function publish(s,edits)
  if not valid_edges(s,edits.corners) then return nil,"corner edge exceeds one level" end
  local staged={}
  local function stage(plane,corner,label)
    local stride=s.width+(corner and 1 or 0)
    for id,v in pairs(plane) do
      local x,z=xy(stride,id)
      local c=chunk(s,x,z)
      local old=s.chunks[c]
      local prior=old and old[label][id]
      local fallback=base(s,corner,x,z)
      local current=prior
      if current==nil then current=fallback end
      if v~=current then
        local copy=staged[c]
        if not copy then
          copy={corners=duplicate(old and old.corners),tiles=duplicate(old and old.tiles),
            ncorners=old and old.ncorners or 0,ntiles=old and old.ntiles or 0}
          staged[c]=copy
        end
        local k="n"..label
        if v==fallback then
          copy[label][id]=nil
          copy[k]=copy[k]-1
        else
          copy[label][id]=v
          if prior==nil then copy[k]=copy[k]+1 end
        end
      end
    end
  end
  stage(edits.corners,true,"corners")
  stage(edits.tiles,false,"tiles")
  if next(staged)==nil then return s.revision,false end
  -- No callbacks, yields or observers during publication in the owning VM.
  for id,part in pairs(staged) do
    local current=s.chunks[id]
    s.ncorners=s.ncorners+part.ncorners-(current and current.ncorners or 0)
    s.ntiles=s.ntiles+part.ntiles-(current and current.ntiles or 0)
    if part.ncorners+part.ntiles==0 then
      s.chunks[id]=nil
      s.nchunks=s.nchunks-1
    else
      s.chunks[id]=part
      if not current then s.nchunks=s.nchunks+1 end
    end
  end
  s.revision=s.revision+1
  return s.revision,true
end

local function commit(s,patch,revision,region)
  if not s then return nil,"unknown world" end
  if s.busy then return nil,"world is already committing" end
  if revision~=s.revision then return nil,"stale world revision" end
  local edits,err=read_patch(s,patch,region)
  if not edits then return nil,err end
  s.busy=true
  local ok,a,b=pcall(publish,s,edits)
  s.busy=false
  if not ok then return nil,"could not prepare patch: "..tostring(a) end
  return a,b
end

-- The supplying VM is the sole writer. Callbacks must be pure and not yield.
-- Return revision, changed; or nil, error. No-op patches do not advance revision.
function M.commit(handle,revision,patch)
  return commit(state(handle),patch,revision)
end

local function u16(n) return char(n%256,floor(n/256)%256) end
local function u32(n) return u16(n)..u16(floor(n/65536)) end
local function get16(data,i)
  local a,b=byte(data,i,i+1)
  return a+b*256
end
local function get32(data,i)
  return get16(data,i)+65536*get16(data,i+2)
end

-- The snapshot contains no callbacks or references. Send only its detached
-- data to a worker; retain the opaque ticket on the main thread.
function M.snapshot(handle,x1,z1,x2,z2)
  local s=state(handle)
  if not s or not index(s.width,s.depth,x1,z1) or not index(s.width,s.depth,x2,z2)
    or not integer(x2-x1+1,1,MAX_SIDE) or not integer(z2-z1+1,1,MAX_SIDE) then
    return nil,"invalid snapshot bounds"
  end
  local rev=s.revision
  local corner_rows,tile_rows={},{}
  for z=z1,z2+1 do
    local c,t={},{}
    for x=x1,x2+1 do
      c[#c+1]=char(M.get_corner(handle,x,z))
      if z<=z2 and x<=x2 then t[#t+1]=u32(M.get_tile(handle,x,z)) end
    end
    corner_rows[#corner_rows+1]=table.concat(c)
    tile_rows[#tile_rows+1]=table.concat(t)
  end
  local ticket={}
  tickets[ticket]={world=handle,revision=rev,x1=x1,z1=z1,x2=x2,z2=z2}
  return {schema="luanttd-world-job/1",revision=rev,base_id=s.base_id,seed=s.seed,
    map_width=s.width,map_depth=s.depth,x=x1,z=z1,width=x2-x1+1,depth=z2-z1+1,
    corners=table.concat(corner_rows),tiles=table.concat(tile_rows)},ticket
end

local function snapshot_index(snapshot,x,z,fringe)
  if not plain(snapshot) or snapshot.schema~="luanttd-world-job/1"
    or not integer(snapshot.width,1,MAX_SIDE) or not integer(snapshot.depth,1,MAX_SIDE)
    or not integer(snapshot.x,1,4096) or not integer(snapshot.z,1,4096)
    or not integer(x,snapshot.x,snapshot.x+snapshot.width-1+fringe)
    or not integer(z,snapshot.z,snapshot.z+snapshot.depth-1+fringe) then return nil end
  return (z-snapshot.z)*(snapshot.width+fringe)+x-snapshot.x
end

-- Pure worker-side readers. Coordinates stay absolute; nil means outside/malformed.
function M.snapshot_tile(snapshot,x,z)
  local id=snapshot_index(snapshot,x,z,0)
  if id and type(snapshot.tiles)=="string" and #snapshot.tiles==4*snapshot.width*snapshot.depth then
    return get32(snapshot.tiles,4*id+1)
  end
end

function M.snapshot_corner(snapshot,x,z)
  local id=snapshot_index(snapshot,x,z,1)
  if id and type(snapshot.corners)=="string" and #snapshot.corners==(snapshot.width+1)*(snapshot.depth+1) then
    return byte(snapshot.corners,id+1)
  end
end

function M.apply_job(handle,ticket,patch)
  local region=tickets[ticket]
  if not region or region.world~=handle then return nil,"invalid job ticket" end
  local revision,changed=commit(state(handle),patch,region.revision,region)
  if revision~=nil then tickets[ticket]=nil end
  return revision,changed
end

local function saved_plane(s,label,corner)
  local values,ids={},{}
  for _,part in pairs(s.chunks) do
    for id,value in pairs(part[label]) do
      values[id]=value
      ids[#ids+1]=id
    end
  end
  table.sort(ids)
  -- Avoid one transient string per record for the whole map at once.
  local out,block={},{}
  for i,id in ipairs(ids) do
    block[#block+1]=u32(id)..(corner and char(values[id]) or u32(values[id]))
    if i%1024==0 then out[#out+1]=table.concat(block); block={} end
  end
  out[#out+1]=table.concat(block)
  return table.concat(out)
end

function M.encode(handle)
  local s=state(handle)
  assert(s,"unknown world")
  return "BLS\1"..u16(s.width)..u16(s.depth)..u32(s.seed)..char(#s.base_id)..s.base_id
    ..u32(s.ncorners)..u32(s.ntiles)..saved_plane(s,"corners",true)..saved_plane(s,"tiles",false)
end

function M.decode(data,opts)
  if type(data)~="string" or #data<22 or data:sub(1,4)~="BLS\1" then return nil,"unsupported world save format" end
  local w,h=get16(data,5),get16(data,7)
  local seed,n=get32(data,9),byte(data,13)
  if not integer(w,64,4096) or not integer(h,64,4096) or not integer(n,1,127) or #data<21+n then
    return nil,"invalid world save header"
  end
  local id=data:sub(14,13+n)
  if not plain(opts) or opts.base_id~=id or not id:match("^[A-Za-z0-9_.:/%-]+$")
    or type(opts.corner)~="function" or type(opts.tile)~="function"
    or opts.validate_tile_word~=nil and type(opts.validate_tile_word)~="function" then
    return nil,"matching base_id and both base callbacks are required"
  end
  local nc,nt=get32(data,14+n),get32(data,18+n)
  if nc>(w+1)*(h+1) or nt>w*h or #data~=21+n+5*nc+8*nt then return nil,"invalid world save size" end
  local handle=M.new(w,h,{seed=seed,base_id=id,corner=opts.corner,tile=opts.tile,
    validate_tile_word=opts.validate_tile_word})
  local s=state(handle)
  local edits={corners={},tiles={}}
  local k=22+n
  local function load_plane(plane,corner,count,stride,limit)
    local previous=-1
    for _=1,count do
      local i=get32(data,k)
      if i<=previous or i>=limit then return nil,"unsorted, duplicate or out-of-bounds save record" end
      local v=corner and byte(data,k+4) or get32(data,k+4)
      local x,z=xy(stride,i)
      if not corner and s.validate_tile_word and not s.validate_tile_word(v) then
        return nil,"invalid typed tile word in save"
      end
      if v==base(s,corner,x,z) then return nil,"redundant base-equivalent save record" end
      plane[i],previous=v,i
      k=k+(corner and 5 or 8)
    end
    return true
  end
  local worked,ok,err=pcall(function()
    local loaded,why=load_plane(edits.corners,true,nc,w+1,(w+1)*(h+1))
    if not loaded then return nil,why end
    loaded,why=load_plane(edits.tiles,false,nt,w,w*h)
    if not loaded then return nil,why end
    return publish(s,edits)
  end)
  if not worked then return nil,"could not load save: "..tostring(ok) end
  if ok==nil then return nil,err end
  s.revision=0
  return handle
end

return M
