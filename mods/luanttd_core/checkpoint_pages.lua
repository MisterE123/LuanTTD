-- Immutable, copy-on-write fixed-record pages for checkpoint experiments.
-- The owner passes encoded scalar records, never live mutable tile tables.
-- Rich tile objects and their cross-references are outside this primitive.
local M={}
local data=setmetatable({},{__mode="k"})
local function snapshot(state)
  local handle={}
  data[handle]=state
  return handle
end
local floor,min=math.floor,math.min
local cat,sub=table.concat,string.sub
local function int(x,lo,hi)
  return type(x)=="number" and x>=lo and x<=hi and x==floor(x)
end
local function address(page_size,id)
  local zero=id-1
  return floor(zero/page_size)+1,zero%page_size+1
end
-- Adopt immutable bytes from the existing exact capture at page
-- boundaries, without rescanning the physical terrain or cloning tiles.
function M.from_pages(count,page_size,width,strings)
  if not int(count,1,4096*4096) or not int(page_size,1,65536) or not int(width,1,64)
      or type(strings)~="table" or #strings~=math.ceil(count/page_size) then return nil end
  local pages={}
  for p=1,#strings do
    local bytes=rawget(strings,p)
    local cells=min(page_size,count-(p-1)*page_size)
    if type(bytes)~="string" or #bytes~=cells*width then return nil end
    pages[p]=bytes
  end
  return snapshot({count=count,page_size=page_size,width=width,pages=pages,revision=0})
end
local function get(s,id)
  if not int(id,1,s.count) then return end
  local page,slot=address(s.page_size,id)
  local first=(slot-1)*s.width+1
  return sub(s.pages[page],first,first+s.width-1)
end
function M.get(handle,id) return get(assert(data[handle]),id) end
function M.revision(handle) return assert(data[handle]).revision end
function M.page(handle,p) return assert(data[handle]).pages[p] end
function M.page_count(handle) return #assert(data[handle]).pages end
-- Validate first; a malformed or superseded batch must not alter an
-- existing read snapshot or the owner. Sorted slots are coalesced into
-- bounded row copies; publication is a caller-owned pointer swap.
function M.patch(handle,revision,values)
  local s=assert(data[handle])
  if revision~=s.revision then return nil,"STALE" end
  local pending={}
  for id,bytes in pairs(values) do
    if not int(id,1,s.count) or type(bytes)~="string" or #bytes~=s.width then return nil,"BAD_RECORD" end
    if bytes~=get(s,id) then
      local p,slot=address(s.page_size,id)
      local page=pending[p]
      if not page then page={};pending[p]=page end
      page[#page+1]={slot,bytes}
    end
  end
  if next(pending)==nil then return handle,{pages=0,bytes=0} end
  local copy,modified,allocated={},0,0
  for p,string_ in ipairs(s.pages) do copy[p]=string_ end
  for p,rows in pairs(pending) do
    table.sort(rows,function(a,b)return a[1]<b[1] end)
    local current,out,at=copy[p],{},1
    for _,row in ipairs(rows) do
      local first=(row[1]-1)*s.width+1
      if first>at then out[#out+1]=sub(current,at,first-1) end
      out[#out+1]=row[2]
      at=first+s.width
    end
    if at<=#current then out[#out+1]=sub(current,at) end
    copy[p]=cat(out)
    assert(#copy[p]==#current)
    modified,allocated=modified+1,allocated+#current
  end
  return snapshot({count=s.count,page_size=s.page_size,width=s.width,pages=copy,revision=revision+1}),
    {pages=modified,bytes=allocated}
end
return M
