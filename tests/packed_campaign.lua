local P=dofile("mods/luanttd_core/packed_campaign.lua")
local key={}
local shared={wood={class=4,type=0,count=2,water_class="sea"}, h=4}
local root={tiles={},corners={},numbers={0,-1,127,128,-128,65535,65536,4294967295,9007199254740991,
  -.125,1/3,math.huge,-math.huge,0/0},nil_holes={[7]="\0 alpha\n",[40000]="\0 alpha\n",[false]=false},
  identity=shared, root_key=key}
root.self=root
root[key]="table key"
root.tiles[1]=shared
for i=2,128*128 do
  root.tiles[i]={h=i%87, variant=i%4, terrain=i%3==0 and "grass" or "water"}
  root.corners[i]=i%87
end
root.tiles[#root.tiles]=shared
-- A two-byte array length leaves 2,044 one-byte values plus headers
-- and terminator in exactly one 2,048-fragment output block.
for n=2043,2045 do
  local a={}
  for i=1,n do a[i]=i%2==1 end
  local bytes=P.encode(a)
  assert(#bytes==n+4)
  local b=P.decode(bytes)
  assert(#b==n and b[1] and b[n]==a[n])
end
local enc=P.encode(root)
local result=P.decode(enc)
assert(type(result)=="table" and result==result.self and result.identity==result.tiles[1]
  and result.tiles[#root.tiles]==result.identity and result[result.root_key]=="table key")
assert(#result.tiles==#root.tiles and #result.corners==#root.corners)
for i=2,#root.tiles-1 do
  assert(result.tiles[i].h==root.tiles[i].h and result.tiles[i].variant==root.tiles[i].variant
    and result.tiles[i].terrain==root.tiles[i].terrain)
  assert(result.corners[i]==root.corners[i])
end
for i=1,#root.numbers-1 do assert(root.numbers[i]==result.numbers[i]) end
local nan=result.numbers[#root.numbers]
assert(nan~=nan)
assert(result.nil_holes[1]==nil and result.nil_holes[7]=="\0 alpha\n" and
  result.nil_holes[40000]==result.nil_holes[7] and result.nil_holes[false]==false)
assert(not pcall(P.decode,enc:sub(1,#enc-1)))
assert(not pcall(P.decode,enc.."\0"))
assert(not pcall(P.decode,"\10\1")) -- unknown table reference
assert(not pcall(P.encode,{bad=function() end}))
print(("PASS packed campaign graph without Lua recompilation: %d cells, %d bytes before compression"):format(#root.tiles,#enc))
-- Precombined UINT fragments still use the original tag and base-128
-- representation at the one-byte, two-byte and uncached boundaries.
local values={0,127,128,8191,8192,16383,16384,1,-1,1.5,false,"1"}
local expected={11,12,4,0,4,127,4,128,1,4,255,63,4,128,64,4,255,127,4,128,128,1,
  4,1,5,1,6,3,49,46,53,2,7,1,49,0}
assert(P.encode(values)==string.char(unpack(expected)))
local numeric={}
for n=0,25000 do numeric[n]=(n%7==0 and -n or n) end
local roundtrip=P.decode(P.encode(numeric))
for n=0,25000 do assert(roundtrip[n]==numeric[n]) end
print("PASS packed integer fragment cache retains exact existing checkpoint bytes and numeric keys")

-- Exercise graph aliases using a real paid and routed stock fleet.
dofile("tests/road_route_geometry_cache.lua")

-- Stock woodland has two adjacent table IDs in the compact form.
local w={class=4,type=3,count=1,ground=0,density=3,growth=6}
local shore={class=4,type=4,count=2,ground=3,density=3,growth=0,water_class="sea"}
local odd={class=4,type=4,count=2,ground=3,density=3,growth=0,water_class="river",extra={1}}
local first={h=16,terrain="hill",variant=2,wood=w}
local second={h=0,terrain="water",variant=0,water_class="sea",wood=shore,coastal_water=true}
local third={h=0,terrain="water",variant=0,water_class="sea",wood=odd,coastal_water=true}
local t={tiles={first,second,third,first,{h=1,terrain="grass",variant=2,wood=w}}}
t.tiles[0]=shore
t.tiles[shore]=first
odd.cycle=t
local enc=P.encode(t);assert(enc:find(string.char(13,16,9,0,0,0,4,3,1,0,3,6,0),1,true))
local function check(new)
  assert(new.tiles[1]==new.tiles[4])
  assert(new.tiles[1].wood==new.tiles[5].wood and new.tiles[2].wood==new.tiles[0])
  assert(new.tiles[new.tiles[2].wood]==new.tiles[1])
  assert(new.tiles[2].wood.water_class=="sea" and new.tiles[3].wood.water_class=="river")
  assert(new.tiles[3].wood.cycle==new and new.tiles[3].wood.extra[1]==1)
end
check(P.decode(enc))
local prelinked={w,tiles={first}}
local new=P.decode(P.encode(prelinked))
assert(new[1]==new.tiles[1].wood)
print("PASS compact woodland keeps nested graph IDs, restored sea-ground, aliases, unsupported fields")
