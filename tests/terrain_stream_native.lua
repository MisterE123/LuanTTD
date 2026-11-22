-- Real stock corner/ground planes, in a disposable Luanti process.
local path=core.get_modpath(core.get_current_modname())
local function lua(name) return dofile(path.."/"..name..".lua") end
local function json(name)
  local f=assert(io.open(path.."/"..name..".json","rb"))
  local s=f:read("*a")
  f:close()
  return assert(core.parse_json(s))
end
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
local W,S=lua("world_storage"),lua("slope")
local Stream=lua("terrain_stream")(S)
local Sparse=lua("openttd_sparse")(W,lua("openttd_map"),core.sha256)
local data,sidecar=json("snapshot"),json("ground")
local base=Sparse.prepare(data)
local Ground=lua("openttd_ground")
local ground=Ground.prepare(sidecar,base)
local world=base.new_world()
local view=Stream.new(Stream.for_overlay(world,Sparse.unpack_tile,ground),{size=16,capacity=8})
local C=Stream.cover
local counts,checked={},0
local function expect(x,z,m,h)
  local c=view.update(x,z,0,1).chunks[1]
  local p=Stream.profile(c,x,z)
  assert(p.mask==m and p.base==h)
  checked=checked+1
end

-- The unmodified stock 14.1 executable supplied these AI slope observations.
for _,rec in ipairs(json("official")) do
  if rec[1]=="SLOPE" then
    local item=rec[2]
    local x,z=base.source_tile_xy(item[1])
    expect(x,z,item[3],item[2])
  end
end
assert(checked>=300)
local total=0
local first_water
collectgarbage("collect")
local memory=collectgarbage("count")
for z1=1,base.depth,16 do for x1=1,base.width,16 do
  local result=view.update(x1,z1,0,1)
  local c=result.chunks[1]
  assert(#result.chunks==1 and result.pending==0 and view.stats().cached==1)
  for z=z1,z1+c.depth-1 do for x=x1,x1+c.width-1 do
    local p=Stream.profile(c,x,z)
    local n,w,e,s=world.tile_corners(x,z)
    assert(Stream.corner(c,x,z)==n and Stream.corner(c,x+1,z)==w and
      Stream.corner(c,x,z+1)==e and Stream.corner(c,x+1,z+1)==s)
    local kind=ground(x,z)
    if kind==2 or kind==3 then
      assert(p.cover==(kind==2 and C.COAST or C.COAST_TREES))
      assert(p.shore_land_mask==p.mask%16 and p.shore_water_mask==15-p.mask%16)
    elseif kind==1 then
      assert(p.cover==(p.mask==0 and C.WATER_FLAT or C.WATER_GRADED))
      first_water=first_water or {x,z}
    elseif p.class==7 then assert(p.cover==C.VOID) end
    local q=p.cover
    counts[q]=(counts[q] or 0)+1
    total=total+1
  end end
end end
collectgarbage("collect")
assert(view.stats().cached==1 and world.stats().chunks==0 and collectgarbage("count")-memory<100)
assert(total==255^2 and (counts[C.COAST] or 0)>100 and (counts[C.COAST_TREES] or 0)>0)
assert((counts[C.LAND_GRADED] or 0)>100 and (counts[C.WATER_FLAT] or 0)>100)
assert(not counts[C.WATER_UNRESOLVED])
sidecar.source_sha256=string.rep("0",64)
assert(not pcall(Ground.prepare,sidecar,base))
assert(ground(first_water[1],first_water[2])==1)
local without=Stream.new(Stream.for_overlay(world,Sparse.unpack_tile,false))
local patch=without.update(first_water[1],first_water[2],0,1)
assert(Stream.profile(patch.chunks[1],first_water[1],first_water[2]).cover==C.WATER_UNRESOLVED)
core.log("action",string.format("LUANTTD STOCK TERRAIN STREAM PASS: %d profiles; %d stock slopes; %d coasts and %d coastal trees",
  total,checked,counts[C.COAST],counts[C.COAST_TREES]))
core.after(0,function() core.request_shutdown("Terrain stream assertions finished",false,0) end)
