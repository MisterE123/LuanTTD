local p="mods/luanttd_core/"
local Slope=dofile(p.."openttd/slope.lua")
local Storage=dofile(p.."world_storage.lua")
local Stream=dofile(p.."terrain_stream.lua")(Slope)
local G=dofile(p.."openttd/original_terrain.lua")(Slope)
local Host=dofile(p.."original_terrain_stream.lua")(G,Storage,Stream,Slope)
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local private_path,private_digest
local function options(seed)
  return {width=128,depth=256,seed=seed,terrain_type=3,quantity_sea_lakes=0,
    masks_sha256=private_path and private_digest or string.rep("a",64)}
end
-- Deliberately artificial in-repo test grids, not stock artwork or the
-- pinned OpenGFX differential data. Vary width/depth and high nibbles.
local bytes={"OTMAPGEN"}
for i=1,37 do
  local w,h=i%17+4,i%11+5
  bytes[#bytes+1]=string.char(w,h)
  for z=1,h do for x=1,w do
    bytes[#bytes+1]=string.char(math.min(x,w+1-x,z,h+1-z)+(i%4)*16)
  end end
end
local data=table.concat(bytes)
local masks=assert(G.read_masks(data))
private_path=arg and arg[1]
private_digest="7ff877ad58ebcdc15cb49824c5c2bab434b2c19d7e48319b38ad94434003f432"
if private_path then
  local f=assert(io.open(private_path,"rb"))
  masks=assert(G.read_masks(f:read("*a")));f:close()
end
assert(not G.read_masks(data.."X") and not G.read_masks(data:sub(1,-2)))
local opts=options(1751)
local world=assert(Host.open(opts,masks))
local view=world.view({size=16,capacity=5})
local v=assert(view.update(16,16,32,5))
eq(v.built,5);assert(v.excluded>0)
eq(view.stats().cached,5)
local left,right
for _,c in ipairs(v.chunks) do
  if c.x==1 and c.z==1 then left=c end
  if c.x==17 and c.z==1 then right=c end
end
assert(left and right)
for z=1,16 do
  eq(Stream.corner(left,17,z),Stream.corner(right,17,z))
  local a,b=Stream.profile(left,16,z),Stream.profile(right,17,z)
  local c=world.tile(17,z)
  eq(b.class,c.class);eq(b.base,c.base);eq(b.mask,c.mask)
  if a.class~=7 and b.class~=7 then eq(Stream.height(left,16,z,1,.5),Stream.height(right,17,z,0,.5)) end
end
eq(world.stats().corners,0);eq(world.stats().tiles,0)
assert(#world.save()<130,"base heightmap must not be serialized into an unedited overlay")
eq(world.tile(1,60).class,7) -- freeform void
eq(world.tile(128,255).class,7)
eq(world.tile(127,256).class,7)
eq(world.corner(129,257),0)
local seen={}
for z=1,opts.depth do for x=1,opts.width do
  local t=world.tile(x,z)
  seen[t.class+16*t.ground]=true
  assert(Slope.valid(world.corner(x,z),world.corner(x+1,z),world.corner(x,z+1),world.corner(x+1,z+1)))
end end
assert(seen[0] and seen[7] and seen[22] and seen[38])
local classic=options(1751);classic.freeform_edges=false
eq(assert(Host.open(classic,masks)).tile(1,60).class,6)

-- A detached job may modify an explicitly verified corner, not take a
-- second snapshot of the entire world. Both sides of the seam are dirty.
local chosen
for z=3,15 do
  local k=world.corner(17,z)
  if k==world.corner(16,z) and k==world.corner(18,z) and
      k==world.corner(17,z-1) and k==world.corner(17,z+1) then
    chosen=z;break
  end
end
assert(chosen)
local old=world.corner(17,chosen)
local stock_word=world.tile(16,chosen).word
local edits={{kind="corner",x=17,z=chosen,value=old+1},
             {kind="tile",x=16,z=chosen,value=stock_word+256}}
local _,job=world.snapshot(16,chosen,16,chosen)
assert(job)
local revision,applied=view.apply_job(job,edits)
eq(revision,1);assert(applied)
eq(view.stats().cached,3);eq(world.corner(17,chosen),old+1)
eq(Stream.corner(left,17,chosen),old) -- published detach is immutable
eq(world.tile(16,chosen).word,stock_word+256)
v=assert(view.update(16,16,32,5));eq(v.built,2)
eq(world.stats().corners,1);eq(world.stats().tiles,1)
local saved=world.save()
assert(#saved<150)
local reset=assert(Host.open(opts,masks,saved))
eq(reset.corner(17,chosen),old+1);eq(reset.tile(16,chosen).word,stock_word+256)
assert(saved==reset.save())
assert(not Host.open(options(1752),masks,saved),"a different seed cannot rebase a patch")
assert(not Host.open(classic,masks,saved),"different coast edges cannot rebase a patch")
print("PASS Original 128x256 source base, legal corners, coastal/void properties, detached seam invalidation and sparse replay")
-- Both last-axis directions, without allocating a second dense world or
-- requiring the slower full reference. Storage still clamps its virtual
-- last corner and reads narrow streamed windows at the far edge.
for _,dims in ipairs{{4096,64},{64,4096}} do
  local config=options(39417)
  config.width,config.depth=dims[1],dims[2]
  local source=G.generate(config,masks)
  local f=source.generation_footprint()
  eq(f.height_bytes,4096*64)
  eq(f.stamp_mutable_cells,16*dims[1])
  eq(f.sweep_mutable_cells,dims[1])
  eq(source.corner(dims[1]+1,dims[2]+1),0)
  assert(not source.corner(dims[1]+2,dims[2]+1))
  local world=assert(Host.open(config,masks))
  local view=world.view({size=8,capacity=1})
  local chunk=view.update(dims[1],dims[2],0,1).chunks[1]
  eq(Stream.profile(chunk,dims[1],dims[2]).class,7)
  eq(Stream.corner(chunk,dims[1]+1,dims[2]+1),0)
  assert(#world.save()<150 and world.stats().chunks==0)
end
local invalid=options(1751)
invalid.width=640
assert(not pcall(G.generate,invalid,masks))
print("PASS narrow 4096-axis world storage, bounded scratch and virtual far corners")
