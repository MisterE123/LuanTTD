local base_dir=(arg and arg[1]) or "."
local W=dofile(base_dir.."/mods/bayline/world_storage.lua")
local samples=0
local function corner(seed,x,z)
  assert(x>=1 and z>=1 and x<=4097 and z<=4097)
  samples=samples+1
  return (seed%251)+(math.floor(x/7)+math.floor(z/11))%2
end
local function tile(seed,x,z)
  assert(x>=1 and z>=1 and x<=4096 and z<=4096)
  samples=samples+1
  return (seed+x*31+z*179)%4294967296
end
local opts={base_id="test.stripes/1",seed=65538,corner=corner,tile=tile}
local function new() return W.new(4096,4096,opts) end
local function c(x,z,value) return {kind="corner",x=x,z=z,value=value} end
local function t(x,z,value) return {kind="tile",x=x,z=z,value=value} end
local function rejected(value,err,pattern)
  assert(value==nil and err:find(pattern,1,true),tostring(value)..": "..tostring(err))
end
local function commit(g,rev,patch,want_revision,want_changed)
  local revision,changed=W.commit(g,rev,patch)
  assert(revision==want_revision and changed==want_changed,tostring(revision)..": "..tostring(changed))
end
local function corners(g,x,z)
  return table.concat({W.tile_corners(g,x,z)},",")
end

collectgarbage("collect")
local before=collectgarbage("count")
local g=new()
local original=W.encode(g)
assert(samples==0 and #original==21+#opts.base_id)
for i=1,4096 do
  assert(W.get_tile(g,4097-i,i)==(opts.seed+(4097-i)*31+i*179)%4294967296)
  assert(W.get_corner(g,i+1,4098-i)==(opts.seed%251)+(math.floor((i+1)/7)+math.floor((4098-i)/11))%2)
end
collectgarbage("collect")
local allocation=collectgarbage("count")-before
assert(samples==8192 and W.stats(g).chunks==0 and allocation<100)
assert(W.tile_id(g,1,1)==0 and W.tile_id(g,4096,4096)==16777215)
local x,z=W.tile_xy(g,4096)
assert(x==1 and z==2)
x,z=W.corner_xy(g,W.corner_id(g,4097,4097))
assert(x==4097 and z==4097 and W.tile_id(g,x,z)==nil)
assert(W.tile_id(g,1,4097)==nil and W.get_tile(g,0,1)==nil and W.get_corner(g,1/0,1)==nil)

local baseline=opts.seed%251
-- x=32/33 touch two adjacent chunk columns, while tile corner lists read
-- the x=33 coordinate only once from shared storage, in their proper order.
local across={c(32,16,baseline),c(33,16,baseline),t(32,16,0),t(33,16,4294967295)}
local snap,stale=W.snapshot(g,30,14,35,20)
assert(snap.schema=="luanttd-world-job/1" and snap.revision==0 and #snap.corners==56 and #snap.tiles==168)
assert(W.snapshot_tile(snap,33,16)==W.get_tile(g,33,16))
assert(W.snapshot_corner(snap,36,21)==W.get_corner(g,36,21))
assert(W.snapshot_tile(snap,36,21)==nil and W.snapshot_corner(snap,37,21)==nil)
commit(g,0,across,1,true)
assert(W.stats(g).chunks==2 and W.stats(g).corners==2 and W.stats(g).tiles==2)
assert(W.get_tile(g,32,16)==0 and W.get_tile(g,33,16)==4294967295)
assert(corners(g,32,16)==table.concat({baseline,baseline,baseline+1,baseline+1},","))
local n,w,e,s=W.tile_corners(g,33,16)
assert(n==baseline and w==baseline+1 and e==baseline+1 and s==baseline+1)
local encoded=W.encode(g)
assert(#encoded==#original+26)
local expected_hex="424c530100100010020001000e746573742e737472697065732f310200000002000000"
  .."2ef000001b2ff000001b1ff000000000000020f00000ffffffff"
assert((encoded:gsub(".",function(b) return string.format("%02x",b:byte()) end))==expected_hex)
assert(W.snapshot_corner(snap,33,16)==baseline+1 and W.snapshot_tile(snap,33,16)~=4294967295)
local v,err=W.apply_job(g,stale,{t(32,16,50)})
rejected(v,err,"stale")
local valid,ticket=W.snapshot(g,32,16,33,16)
assert(W.snapshot_tile(valid,32,16)==0 and W.snapshot_tile(valid,33,16)==4294967295)
assert(W.snapshot_corner(valid,34,17)==W.get_corner(g,34,17))
v,err=W.apply_job(new(),ticket,{t(32,16,50)})
rejected(v,err,"invalid job")
v,err=W.apply_job(g,ticket,{t(34,16,50)})
rejected(v,err,"outside")
v,err=W.apply_job(g,ticket,{t(32,16,0)})
assert(v==1 and err==false)
v,err=W.apply_job(g,ticket,{t(32,16,50)})
rejected(v,err,"invalid job")

-- Invalid second entries must not publish the valid first entry.
for _,test in ipairs({
  {{t(32,16,7),c(32,16,112)},"corner edge"},
  {{t(32,16,7),c(33,16,-1)},"invalid edit coordinate or value"},
  {{t(32,16,7),t(0,16,7)},"invalid edit coordinate or value"},
  {{t(32,16,7),t(32,16,7)},"duplicate"},
  {{t(32,16,7),[3]=t(34,16,7)},"dense"},
  {{t(32,16,7),n=7},"non-array"},
  {{t(32,16,7),[8449]=t(34,16,7)},"limit"},
  {{t(32,16,7),{kind="vehicle",x=4,z=1,value=7}},"invalid edit kind"},
}) do
  v,err=W.commit(g,1,test[1])
  rejected(v,err,test[2])
  assert(W.stats(g).revision==1 and W.encode(g)==encoded)
end
v,err=W.snapshot(g,1,1,65,2)
rejected(v,err,"bounds")
local max=W.snapshot(g,4033,4033,4096,4096)
assert(#max.corners==4225 and #max.tiles==16384)
assert(W.snapshot_tile(max,4096,4096)==W.get_tile(g,4096,4096))
assert(W.snapshot_corner(max,4097,4097)==W.get_corner(g,4097,4097))

-- Cross-map determinism independent of edit order and commit history.
local other=new()
commit(other,0,{across[4],across[3]},1,true)
commit(other,1,{across[2],across[1]},2,true)
assert(W.encode(other)==encoded)
local restored,problem=W.decode(encoded,opts)
assert(restored,problem)
assert(W.stats(restored).revision==0 and W.encode(restored)==encoded)
local back={c(32,16,corner(opts.seed,32,16)),c(33,16,corner(opts.seed,33,16)),
  t(32,16,tile(opts.seed,32,16)),t(33,16,tile(opts.seed,33,16))}
commit(restored,0,back,1,true)
assert(W.encode(restored)==original and W.stats(restored).chunks==0)
commit(restored,1,back,1,false)
local _,usable=W.snapshot(restored,32,16,33,16)
assert(W.apply_job(restored,usable,across)==2 and W.encode(restored)==encoded)

-- Canonical binary rejects unknown versions, trailing/truncated bytes,
-- unordered/duplicate/out-of-bounds records, invalid slopes and redundant records.
local function replace(data,i,value) return data:sub(1,i-1)..value..data:sub(i+#value) end
local start=22+#opts.base_id
for _,bad in ipairs({
  {replace(encoded,4,string.char(2)),"unsupported"},
  {encoded.."x","size"},
  {encoded:sub(1,-2),"size"},
  {replace(encoded,start+5,encoded:sub(start,start+3)),"duplicate"},
  {replace(encoded,start,string.rep(string.char(255),4)),"out-of-bounds"},
  {replace(encoded,start+4,string.char(255)),"edge exceeds"},
  {replace(encoded,start+4,string.char(baseline+1)),"redundant"},
}) do
  v,err=W.decode(bad[1],opts)
  rejected(v,err,bad[2])
end
v,err=W.decode(encoded,{base_id="test.stripes/2",corner=corner,tile=tile})
rejected(v,err,"matching base_id")

-- Non-chunk-multiple dimensions: the outer corner belongs to the existing
-- last chunk. Reverted last edit evicts it, not creating an extra chunk.
local odd=W.new(65,74,opts)
commit(odd,0,{t(65,74,4),c(66,75,baseline)},1,true)
assert(W.stats(odd).chunks==1)
assert(W.corner_id(odd,66,75)==65+74*66)
assert(W.decode(W.encode(odd),opts))
commit(odd,1,{t(65,74,tile(opts.seed,65,74)),c(66,75,corner(opts.seed,66,75))},2,true)
assert(W.stats(odd).chunks==0)
for _,wh in ipairs({{63,64},{4097,64},{64,64.5}}) do
  assert(not pcall(W.new,wh[1],wh[2],opts))
end

-- A failing deterministic tile adapter leaves no partially published chunks.
local fail=false
local bad_base=W.new(64,64,{base_id="test.error/1",seed=0,corner=corner,tile=function(_,cx)
  if cx==3 and fail then error("test provider failure") end
  return 3
end})
local empty=W.encode(bad_base)
fail=true
v,err=W.commit(bad_base,0,{t(2,1,0),t(3,1,0)})
rejected(v,err,"provider failure")
assert(W.encode(bad_base)==empty)
fail=false
commit(bad_base,0,{t(2,1,0),t(3,1,0)},1,true)
print(string.format("4096^2 lazy storage: %.1f KiB retained after 8192 samples; seam edits, corner fringe, atomic validation, stale/out-of-region jobs, and canonical bytes passed",allocation))
