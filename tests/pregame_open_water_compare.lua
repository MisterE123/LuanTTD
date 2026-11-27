local C=dofile("mods/luanttd_core/packed_campaign.lua")
local function read(path)
  local f=assert(io.open(path,"rb"))
  local bytes=f:read("*a");f:close()
  return C.decode(bytes)
end
local a,b=read(arg[1]),read(arg[2])
local map,reverse={},{}
local path,checked={},0
local function same(a,b,depth)
  local t=type(a)
  if t~="table" then return a==b or t=="number" and type(b)=="number" and a~=a and b~=b end
  if type(b)~="table" then return false end
  if map[a] or reverse[b] then return map[a]==b and reverse[b]==a end
  map[a],reverse[b]=b,a
  checked=checked+1
  for k,v in pairs(a) do
    assert(type(k)~="table","Fixture has table keys")
    path[depth]=k
    if not same(v,b[k],depth+1) then return false end
  end
  for k in pairs(b) do
    if a[k]==nil then path[depth]=k;return false end
  end
  path[depth]=nil
  return true
end
assert(same(a,b,1),table.concat(path,"."))
print(("PASS day %d, %d table records/aliases, %d tiles, exact values"):format(a.day,checked,#a.tiles))
