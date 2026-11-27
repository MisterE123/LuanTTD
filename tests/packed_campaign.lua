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

-- On-disk references must keep their original base-128 width even
-- after enough unique strings to cross the two- and three-byte bounds.
local dictionary={}
for i=1,16384 do dictionary[i]="key:"..i end
local offsets={127,128,16383,16384}
for i,id in ipairs(offsets) do dictionary[16384+i]=dictionary[id] end
local ref_tail=string.char(8,127,8,128,1,8,255,127,8,128,128,1,0)
local dictionary_bytes=P.encode(dictionary)
assert(dictionary_bytes:sub(-#ref_tail)==ref_tail)
local words=P.decode(dictionary_bytes)
for i,id in ipairs(offsets) do assert(words[16384+i]==words[id]) end
local repeated=P.encode({"shared",{shared="shared"}})
assert(repeated==string.char(11,2,7,6).."shared"..string.char(9,8,1,8,1,0,0))
assert(P.decode(repeated)[2].shared=="shared")
print("PASS packed string keys and references retain exact checkpoint bytes")

-- Exercise graph aliases using a real paid and routed stock fleet.
dofile("tests/road_route_geometry_cache.lua")

do
  local packed=dofile("mods/luanttd_core/packed_campaign.lua")
  local tiles={}
  for i=1,4098 do
    tiles[i]={h=i%12,variant=i%4,terrain="grass",stock_clear_ground=i%3}
  end
  tiles[8]={h=0,variant=1,terrain="water",water_class="sea",coastal_water=true,
    stock_water_rocks=true,wood={class=4,type=2,count=1,ground=3,density=3,growth=4,water_class="sea"}}
  tiles[4097]={h=2,variant=0,terrain="grass",build="road",marker={x=71}}
  local fallback=packed.host_tile_view(tiles)
  local function same(a,b)
    if a==b then return true end
    if type(a)~="table" or type(b)~="table" then return false end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  assert(not fallback[0] and not fallback[4099] and not fallback[1.2])
  for i,t in ipairs(tiles) do assert(same(t,fallback[i])) end
  assert(fallback[4097]==tiles[4097] and fallback[8].wood.water_class=="sea")
  assert(not pcall(function() fallback[8]={} end))
  assert(fallback[1].h==1 and fallback[513].h==9 and fallback[1].h==1)
  print("PASS compact host tile reads across storage pages, cache replacement and rich fallback")
end

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

-- Pin ordinary tile bytes for every supported height, variant and water class.
-- Extra keys (including false) must not be lost, and aliases must survive.
do
  local tile_matrix={}
  local expected={}
  for h=0,255 do
    for v=0,3 do
      for i,terrain in ipairs({"grass","hill","water"}) do
        for w=0,2 do
          local cell={h=h,variant=v,terrain=terrain,water_class=({"sea","river"})[w]}
          tile_matrix[#tile_matrix+1]=cell
          expected[#expected+1]=string.char(12,h,i-1+4*v+16*w,0,0,0)
        end
      end
    end
  end
  local bytes=P.encode({tiles=tile_matrix})
  local cells=table.concat(expected)
  assert(bytes:find(cells,1,true),"ordinary tile wire format changed")
  local decoded=P.decode(bytes)
  assert(decoded.tiles[1].h==0 and decoded.tiles[#tile_matrix].h==255)
  local extra={h=0,variant=1,terrain="water",water_class="sea",[false]=true}
  local dry_extra={h=1,variant=2,terrain="grass",[false]="keep"}
  local decorated=setmetatable({h=0,variant=2,terrain="water",water_class="river"},
    {__index={coastal_water=true},__metatable=false})
  local shared_cell={h=12,variant=0,terrain="grass"}
  local unusual={tiles={extra,dry_extra,decorated,shared_cell,shared_cell}}
  local round=P.decode(P.encode(unusual))
  assert(round.tiles[1][false]==true and round.tiles[2][false]=="keep")
  assert(round.tiles[3].coastal_water==true and round.tiles[3].water_class=="river")
  assert(round.tiles[4]==round.tiles[5])
end

-- The wide reference hash chooses by raw shape, not encounter path.
-- Ordinary tiles, trees and generic tables still alias across a table
-- key, direct root fields and compact slots. The read-only pulses do
-- not change a byte of the already identical graph.
do
  local wood={class=4,type=11,count=1,ground=0,density=3,growth=2}
  local cell={h=14,variant=2,terrain="grass",wood=wood}
  local other={h=14,variant=2,terrain="grass"}
  local rich=setmetatable({h=15,variant=2,terrain="grass"},
    {__index={stock_clear_ground=1},__metatable=false})
  local state={tiles={},cell=cell,wood=wood,rich=rich}
  state[cell]=wood;state.self=state
  state.tiles[1],state.tiles[2],state.tiles[3]=cell,other,rich
  for i=4,262144 do state.tiles[i]=(i%2==0 and cell or other) end
  state.tiles.aux=wood
  local pulses=0
  local bytes=P.encode(state,function() pulses=pulses+1 end)
  assert(bytes==P.encode(state) and pulses>96)
  local loaded=P.decode(bytes)
  assert(loaded.self==loaded and loaded.cell==loaded.tiles[1] and loaded.cell==loaded.tiles[262144])
  assert(loaded.cell~=loaded.tiles[2] and loaded.wood==loaded.cell.wood and loaded.wood==loaded.tiles.aux)
  assert(loaded[loaded.cell]==loaded.wood and loaded.rich==loaded.tiles[3] and loaded.rich.stock_clear_ground==1)
  print("PASS wide checkpoint references across shaped buckets and readonly pulses")
end

-- Periodic save pulses are before compression and before the one atomic
-- commit; explicit saves still use the original format and compression.
do
  local seen,committed={},nil
  local function tag(name) seen[#seen+1]=name end
  local open=dofile("mods/luanttd_core/campaign_checkpoint.lua")
  local checkpoint=open({
    get_worldpath=function() return "/disposable" end,
    compress=function(raw,format,level)
      assert(format=="zstd");tag("compress"..level)
      return raw:reverse()
    end,
    sha256=function(bytes) tag("hash");return "sum"..#bytes end,
    safe_file_write=function(path,data)
      tag("commit");assert(path=="/disposable/test.chk")
      committed=data
      return true
    end,
  },{
    encode=function(s,pulse)
      tag("encode")
      if pulse then pulse() end
      return P.encode(s)
    end,
  },"test.chk")
  local state={day=7}
  state.loop=state
  checkpoint.write_state(state,function() tag("read") end)
  assert(table.concat(seen,",")=="encode,read,read,compress1,read,hash,commit")
  local data=P.decode(assert(committed:match("^LUANTTD%-WIDE%-CAMPAIGN%-3%-STATE\nsum%d+\n(.*)$")):reverse())
  assert(data.day==7 and data.loop==data)
  seen={}
  checkpoint.write_state(state)
  assert(table.concat(seen,",")=="encode,compress3,hash,commit")
  print("PASS periodic checkpoint yields at safe phase boundaries and commits the full state once")
end
