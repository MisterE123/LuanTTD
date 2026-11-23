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
