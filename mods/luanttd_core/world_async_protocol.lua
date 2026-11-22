-- Pure byte protocol for detached authoritative-world terrain jobs.
local self=debug and debug.getinfo(1,"S").source
local here=self and self:match("^@(.*/)world_async_protocol%.lua$")
local D=dofile((here or (core and core.get_modpath(core.get_current_modname() or "luanttd_core").."/") or
  "mods/luanttd_core/").."terrain_word.lua")
local P={MAX_SIDE=32,MAX_REVISION=9007199254740991}
local floor,min,max=math.floor,math.min,math.max
local byte,char=string.byte,string.char
local function int(n,lo,hi)
  return type(n)=="number" and n>=lo and n<=hi and floor(n)==n
end
local function plain(t) return type(t)=="table" and getmetatable(t)==nil end
local function span(a,b) return int(a,1,4096) and int(b,a,4096) and b-a<P.MAX_SIDE end
function P.region(x1,z1,x2,z2) return span(x1,x2) and span(z1,z2) end

function P.snapshot(s)
  return plain(s) and s.schema=="luanttd-world-job/1" and int(s.revision,0,P.MAX_REVISION) and
    type(s.base_id)=="string" and #s.base_id>=1 and #s.base_id<=127 and s.base_id:match("^[A-Za-z0-9_.:/%-]+$") and
    int(s.seed,0,4294967295) and int(s.map_width,64,4096) and int(s.map_depth,64,4096) and
    int(s.x,1,s.map_width) and int(s.z,1,s.map_depth) and int(s.width,1,P.MAX_SIDE) and
    int(s.depth,1,P.MAX_SIDE) and s.x+s.width-1<=s.map_width and s.z+s.depth-1<=s.map_depth and
    type(s.corners)=="string" and #s.corners==(s.width+1)*(s.depth+1) and
    type(s.tiles)=="string" and #s.tiles==s.width*s.depth*4
end
function P.max_input()
  return 4*P.MAX_SIDE*P.MAX_SIDE+(P.MAX_SIDE+1)^2
end
function P.job(s,job)
  if not plain(job) then return end
  if job.kind=="raster" then return {kind="raster"} end
  if job.kind=="river_raster" and D.is_promoted(s.base_id) then return {kind="river_raster"} end
  if job.kind=="corner" and int(job.x,s.x+1,s.x+s.width-2) and int(job.z,s.z+1,s.z+s.depth-2) and
    int(job.mask,1,15) and type(job.up)=="boolean" and
    (job.max_height==nil or int(job.max_height,1,255)) and
    (job.freeform_edges==nil or type(job.freeform_edges)=="boolean") then
    return {kind="corner",x=job.x,z=job.z,mask=job.mask,up=job.up,max_height=job.max_height or 255,
      freeform_edges=job.freeform_edges~=false}
  end
end
local headers={"seed","base_id","revision","map_width","map_depth","x","z","width","depth"}
local function result_schema(kind)
  return kind=="river_raster" and "luanttd-world-async-result/2" or "luanttd-world-async-result/1"
end
function P.envelope(s,kind,id)
  local r={schema=result_schema(kind),kind=kind,id=id}
  for _,k in ipairs(headers) do r[k]=s[k] end
  return r
end
local errors={INVALID_SNAPSHOT=true,INVALID_JOB=true,INVALID_CORNERS=true,NEED_WIDER_REGION=true,
  TOO_HIGH=true,TOO_CLOSE_TO_EDGE=true,ALREADY_AT_SEA_LEVEL=true,NO_EFFECT=true,INVALID_SELECTION=true,
  INVALID_TERRAIN_WORD=true}
function P.terrain_bytes(tiles,index,mask,base,high)
  local word=D.word(tiles,4*index+1)
  if not D.valid(word) then return end
  local class,ground=D.describe(word)
  return D.profile_bytes(mask,base,high,class,ground)
end
function P.corner(s,x,z)
  return byte(s.corners,(z-s.z)*(s.width+1)+x-s.x+1)
end
function P.encode(x,z,v)
  return char(x%256,floor(x/256),z%256,floor(z/256),v)
end
function P.decode(s,bytes)
  if type(bytes)~="string" or #bytes==0 or #bytes%5~=0 or #bytes>5*(s.width-1)*(s.depth-1) then
    return nil
  end
  local patch,last={},-1
  for p=1,#bytes,5 do
    local u,a,v,b,k=byte(bytes,p,p+4)
    local x,z=u+256*a,v+256*b
    if not int(x,s.x+1,s.x+s.width-1) or not int(z,s.z+1,s.z+s.depth-1) then return nil end
    local ord=(z-s.z)*(s.width+1)+x-s.x
    if ord<=last or k==P.corner(s,x,z) then return nil end
    last=ord
    patch[#patch+1]={kind="corner",x=x,z=z,value=k}
  end
  return patch
end
local supported={[0]=true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,
  [23]=true,[27]=true,[29]=true,[30]=true}
function P.result(s,job,id,r)
  if not plain(r) or r.schema~=result_schema(job.kind) or r.kind~=job.kind or r.id~=id then
    return nil,"invalid worker reply header"
  end
  for _,k in ipairs(headers) do if s[k]~=r[k] then return nil,"invalid worker reply context" end end
  if r.error~=nil then
    if not errors[r.error] or r.profiles~=nil or r.patch~=nil or r.tiles~=nil then return nil,"invalid worker failure" end
    return nil,r.error
  end
  local out=P.envelope(s,job.kind,id)
  if job.kind=="raster" or job.kind=="river_raster" then
    local typed=job.kind=="river_raster"
    local stride=typed and D.stride or 3
    if type(r.profiles)~="string" or #r.profiles~=stride*s.width*s.depth
        or r.patch~=nil or r.cost~=nil or r.tiles~=nil then
      return nil,"invalid worker raster size"
    end
    for p=1,#r.profiles,stride do
      local m,a,b=byte(r.profiles,p,p+2)
      if not supported[m] or b-a~=(m==0 and 0 or m<16 and 1 or 2) then return nil,"invalid worker raster record" end
      if typed then
        local cell=(p-1)/stride
        local i=cell+floor(cell/s.width)+1
        local n,w=byte(s.corners,i,i+1)
        local e,d=byte(s.corners,i+s.width+1,i+s.width+2)
        local base,high=min(n,w,e,d),max(n,w,e,d)
        local mask=(n~=base and 8 or 0)+(w~=base and 1 or 0)+(e~=base and 4 or 0)+(d~=base and 2 or 0)
          +(high-base==2 and 16 or 0)
        if r.profiles:sub(p,p+stride-1)~=P.terrain_bytes(s.tiles,cell,mask,base,high) then
          return nil,"invalid worker typed terrain record"
        end
      end
    end
    out.profiles=r.profiles
    -- The owner attaches its original bounded tile bytes. The worker
    -- cannot rewrite or retransmit them, including the river RNG byte.
    if typed then out.tiles=s.tiles end
    return out
  end
  if r.profiles~=nil or not int(r.cost,1,4*(s.width+1)*(s.depth+1)) then return nil,"invalid worker proposal" end
  local patch=P.decode(s,r.patch)
  if not patch or r.cost<#patch then return nil,"invalid worker patch format" end
  for _,e in ipairs(patch) do
    if e.value>job.max_height or
       not job.freeform_edges and (e.x<=2 or e.z<=2 or e.x>=s.map_width or e.z>=s.map_depth) then
      return nil,"invalid worker patch bounds"
    end
  end
  out.cost=r.cost;out.changes=#patch
  return out,nil,patch
end
function P.profile(result,x,z)
  if type(result)~="table" or result.kind~="raster" or result.schema~=result_schema("raster")
     or type(result.profiles)~="string" or
     not int(result.width,1,P.MAX_SIDE) or not int(result.depth,1,P.MAX_SIDE) or
     not int(result.x,1,4096) or not int(result.z,1,4096) or
     not int(x,result.x,result.x+result.width-1) or not int(z,result.z,result.z+result.depth-1) or
     #result.profiles~=3*result.width*result.depth then return end
  return byte(result.profiles,3*((z-result.z)*result.width+x-result.x)+1,
    3*((z-result.z)*result.width+x-result.x)+3)
end
function P.terrain_profile(result,x,z)
  if type(result)~="table" or result.kind~="river_raster" or result.schema~=result_schema("river_raster")
    or not int(result.width,1,P.MAX_SIDE) or not int(result.depth,1,P.MAX_SIDE)
    or not int(result.x,1,4096) or not int(result.z,1,4096)
    or not int(x,result.x,result.x+result.width-1) or not int(z,result.z,result.z+result.depth-1)
    or type(result.profiles)~="string" or #result.profiles~=D.stride*result.width*result.depth
    or type(result.tiles)~="string" or #result.tiles~=4*result.width*result.depth then return end
  local i=(z-result.z)*result.width+x-result.x
  return D.entry(result.profiles,D.stride*i+1,D.word(result.tiles,4*i+1),x,z,2)
end
return P
