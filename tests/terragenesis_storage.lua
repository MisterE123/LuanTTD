local p="mods/luanttd_core/"
local Slope=dofile(p.."openttd/slope.lua")
local G=dofile(p.."openttd/terragenesis.lua")(Slope)
local Clear=dofile(p.."openttd/terragenesis_clear.lua")
local Storage=dofile(p.."world_storage.lua")
local Stream=dofile(p.."terrain_stream.lua")(Slope)
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local seed=1751
local config={differential_version="14.1",width=64,depth=64,seed=seed,terrain_type=3,rng_state=G.startup_rng(seed)}
local function generate() return Clear.generate(G.generate(config),G.next_random) end
local base=generate()
eq(base.rng_after[1],3351320871);eq(base.rng_after[2],3998776434)
eq(config.rng_state[1],0x50246f79);eq(config.rng_state[2],0xe00000d9)
local t={};local cov={}
for z=1,64 do for x=1,64 do
  local word=base.tile(x,z)
  local class,wet,cover=Clear.describe(word)
  local k=class+16*wet
  t[k]=(t[k] or 0)+1
  if class==0 then cov[cover]=(cov[cover] or 0)+1 end
  assert(Slope.valid(base.corner(x,z),base.corner(x+1,z),base.corner(x,z+1),base.corner(x+1,z+1)))
end end
eq(t[0],1966);eq(t[22],1580);eq(t[38],298);eq(t[7],252)
eq(cov[0],1859);eq(cov[1],53);eq(cov[2],54)
eq(base.corner(65,65),base.corner(64,64));assert(not base.corner(66,65))
assert(not base.tile(65,65) and not base.clear_ground(65,65))
local handle=Storage.new(base.width,base.depth,base.storage_options())
local view=Stream.new(Stream.for_storage(Storage,handle,Clear.describe),{size=16,capacity=4})
local frame=assert(view.update(16,16,16,4))
local left,right
for _,c in ipairs(frame.chunks) do
  if c.x==1 and c.z==1 then left=c end
  if c.x==17 and c.z==1 then right=c end
end
assert(left and right)
for z=1,16 do
  eq(Stream.corner(left,17,z),Stream.corner(right,17,z))
  local a,b=Stream.profile(left,16,z),Stream.profile(right,17,z)
  if a.class~=7 and b.class~=7 then
    eq(Stream.height(left,16,z,1,.5),Stream.height(right,17,z,0,.5))
  end
  eq(b.word,base.tile(17,z))
end
eq(Storage.stats(handle).chunks,0)
assert(#Storage.encode(handle)<150)
local saved=Storage.encode(handle)
local same=generate()
eq(Storage.encode(assert(Storage.decode(saved,same.storage_options()))),saved)
config.rng_state=nil
local no_prelude=generate()
assert(not Storage.decode(saved,no_prelude.storage_options()),"stock startup RNG state is part of world identity")
config.rng_state=G.startup_rng(seed)
config.variety=2
assert(not Storage.decode(saved,generate().storage_options()),"terrain variety is part of world identity")
config.width=96
assert(not pcall(generate),"nonstock map width")
print("PASS seeded stock terrain+clear immutable storage, source tide/land counts, stream seam, cursor and identity")
