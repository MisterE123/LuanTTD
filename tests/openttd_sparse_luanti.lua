local path=core.get_modpath(core.get_current_modname())
local function json(name)
  local f=assert(io.open(path.."/"..name,"rb"))
  local text=f:read("*a")
  f:close()
  return assert(core.parse_json(text))
end
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
local Slope=dofile(path.."/slope.lua")
local Terrain=dofile(path.."/terrain.lua")
local Map=dofile(path.."/openttd_map.lua")
local W=dofile(path.."/world_storage.lua")
local S=dofile(path.."/openttd_sparse.lua")(W,Map,core.sha256)
local source=json("snapshot.json")
local official=json("official.json")
local original=Map(Terrain).prepare(source)
local base=S.prepare(source)
local world=base.new_world()
local stats=world.stats()
local w,h=source.width,source.height
assert(w==256 and h==256 and not base.can_resume_in_luanti)
assert(base.width==w-1 and base.depth==h-1 and stats.chunks==0 and stats.corners==0 and stats.tiles==0)
assert(base.source_tile_id(1,2)==256 and base.logical_tile_id(1,2)==255)
assert(base.source_tile_id(w,5)==nil and base.source_tile_xy(w-1)==nil)
assert(base.logical_tile_id(w,5)==nil and base.logical_tile_xy((w-1)*(h-1))==nil)
local last=base.source_tile_id(w-1,h-1)
local lx,lz=base.source_tile_xy(last)
assert(last==65278 and lx==w-1 and lz==h-1)
lx,lz=base.logical_tile_xy(base.logical_tile_id(w-1,h-1))
assert(lx==w-1 and lz==h-1)

local checked,roads=0,0
for z=1,h do for x=1,w do
  assert(world.corner(x,z)==Terrain.corner(original.corner_grid,x,z))
  if x<w and z<h then
    local class,road,tram=world.tile(x,z)
    local expect=original.road_tile(x,z)
    assert(class==original.tile_type(x,z))
    assert(road==(expect and expect.road_bits) and tram==(expect and expect.tram_bits))
    if expect then
      local actual=assert(base.source_road_tile(x,z))
      for k,v in pairs(expect) do
        if type(v)=="table" then assert(table.concat(v,",")==table.concat(actual[k],","))
        else assert(actual[k]==v) end
      end
      roads=roads+1
    end
  else assert(world.tile(x,z)==nil) end
end end
for _,point in ipairs(official) do
  local tag,v=point[1],point[2]
  if tag=="SLOPE" then
    local x,z=base.source_tile_xy(v[1])
    local mask,alt=Slope.classify(world.tile_corners(x,z))
    assert(mask==v[3] and alt==v[2],"stock terrain slope mismatch")
    checked=checked+1
  end
end
assert(checked>=300 and roads>0 and world.stats().chunks==0)

local function c(x,z,v) return {kind="corner",x=x,z=z,value=v} end
local function t(x,z,v) return {kind="tile",x=x,z=z,value=v} end
local initial=world.encode()
assert(#initial==21+#base.base_id)
-- Pick adjacent real corners in different 32-tile chunks which can both rise.
local seam_x,seam_z
for z=3,h-2 do
  for x=32,w-2,32 do
    local a=world.corner(x,z)
    local ok=a<255
    for _,p in ipairs({{x-1,z},{x+1,z},{x+2,z},{x,z-1},{x,z+1},{x+1,z-1},{x+1,z+1}}) do
      ok=ok and world.corner(p[1],p[2])==a
    end
    if ok then seam_x,seam_z=x,z;break end
  end
  if seam_x then break end
end
assert(seam_x)
local a=world.corner(seam_x,seam_z)
local roads_edit_x,roads_edit_z,old,changed
for key,rec in pairs(source.road_tiles) do
  if rec.kind=="road" and rec.road_bits~=nil then
    roads_edit_x,roads_edit_z=base.source_tile_xy(tonumber(key))
    old=rec.road_bits
    changed=(old+1)%16
    break
  end
end
assert(roads_edit_x)
local stored_class,_,stored_tram=world.tile(roads_edit_x,roads_edit_z)
local patch={c(seam_x,seam_z,a+1),c(seam_x+1,seam_z,a+1),
  t(roads_edit_x,roads_edit_z,S.pack_tile(stored_class,changed,stored_tram))}
local frozen,stale=world.snapshot(seam_x-1,seam_z-1,seam_x+1,seam_z+1)
assert(W.snapshot_corner(frozen,seam_x,seam_z)==a)
assert(world.commit(0,patch)==1)
local lost,why=world.apply_job(stale,{c(seam_x,seam_z,a)})
assert(not lost and why:find("stale",1,true))
assert(W.snapshot_corner(frozen,seam_x,seam_z)==a)
local n,e=world.tile_corners(seam_x+1,seam_z)
assert(n==a+1 and e~=nil and world.corner(seam_x+1,seam_z)==a+1)
local _,shared=world.tile_corners(seam_x,seam_z)
assert(shared==n and world.stats().chunks>=2)
local bytes=world.encode()
assert(#bytes==#initial+18 and world.stats().corners==2 and world.stats().tiles==1)
local reload=assert(base.load_world(bytes))
assert(reload.stats().revision==0 and reload.encode()==bytes)
assert(reload.corner(seam_x,seam_z)==a+1 and reload.corner(seam_x+1,seam_z)==a+1)
assert(reload.corner(w,h)==world.corner(w,h) and reload.corner(5,6)==world.corner(5,6))
local _,new=reload.tile(roads_edit_x,roads_edit_z)
assert(new==changed and base.source_road_tile(roads_edit_x,roads_edit_z).road_bits==old)
assert(reload.commit(0,{t(roads_edit_x,roads_edit_z,S.pack_tile(stored_class,old,stored_tram)),
  c(seam_x,seam_z,a),c(seam_x+1,seam_z,a)})==1)
assert(reload.encode()==initial and reload.stats().chunks==0)

-- Metadata provenance is copied, and road flag arrays returned to consumers
-- are detached. Modifying only SHA or JSON ordering does not alter identity.
local fresh=json("snapshot.json")
fresh.source.sha256=string.rep("0",64)
assert(S.prepare(fresh).base_id==base.base_id)
local key=tostring(base.source_tile_id(roads_edit_x,roads_edit_z))
local road_copy=base.source_road_tile(roads_edit_x,roads_edit_z)
local new_owner=(road_copy.road_owner+1)%32
road_copy.road_owner=new_owner
road_copy.unsupported_for_initial_bus_world[1]="fake"
assert(base.source_road_tile(roads_edit_x,roads_edit_z).road_owner~=new_owner)
local same_incoming=source.road_tiles[key]
same_incoming.road_bits=changed
source.corner_rows_hex[seam_z]=string.rep("ff",w)
assert(select(2,base.new_world().tile(roads_edit_x,roads_edit_z))==old)
assert(base.new_world().corner(seam_x,seam_z)==a)
fresh.road_tiles[key].road_owner=new_owner
local different=S.prepare(fresh)
assert(different.base_id~=base.base_id)
local blocked,why=different.load_world(bytes)
assert(not blocked and why:find("matching base_id",1,true))
fresh.road_tiles[key].bad_field=9001
assert(not pcall(S.prepare,fresh))
local near="07"..("00"):rep(62).."07"
local src64={
  schema="luanttd-openttd-map/1",can_resume_in_luanti=false,
  width=64,height=64,tile_columns=63,tile_rows=63,freeform_edges=true,
  source={save_version=334,sha256=string.rep("1",64)},
  road_tiles={},corner_rows_hex={},tile_type_rows_hex={},
}
for z=1,64 do
  src64.corner_rows_hex[z]=("00"):rep(64)
  src64.tile_type_rows_hex[z]=(z==1 or z==64) and ("07"):rep(64) or near
end
local minbase=S.prepare(src64)
local small=minbase.new_world()
assert(minbase.width==63 and minbase.depth==63 and small.corner(64,64)==0)
assert(small.tile(64,64)==nil and small.corner(65,65)==nil and small.tile(1,1)==7)
assert(small.stats().width==63 and small.stats().depth==63 and small.snapshot(63,63,64,64)==nil)
assert(minbase.source_tile_id(1,2)==64 and minbase.logical_tile_id(1,2)==63)
assert(small.commit(0,{t(1,2,S.pack_tile(2,10))})==nil)
assert(small.commit(0,{t(64,2,S.pack_tile(2,10))})==nil)
assert(small.commit(0,{c(64,20,1)})==nil)
local fringe,ticket=small.snapshot(63,63,63,63)
assert(fringe.map_width==63 and fringe.map_depth==63 and W.snapshot_corner(fringe,64,64)==0)
assert(small.apply_job(ticket,{c(64,64,1)})==nil)
assert(small.apply_job(ticket,{c(63,63,1),t(63,63,S.pack_tile(2,0,15))})==1)
local unboxed=assert(minbase.load_world(small.encode()))
local cl,road,tram=unboxed.tile(63,63)
assert(cl==2 and road==0 and tram==15)
local forged=small.encode()
local function replace(b,i,v) return b:sub(1,i-1)..v..b:sub(i+#v) end
-- 63rd logical tile is valid; its next private padded slot is invisible.
forged=replace(forged,22+#minbase.base_id+5,string.char(63,15,0,0))
blocked,why=minbase.load_world(forged)
assert(not blocked and why:find("invalid or void",1,true))
local heights2=("00"):rep(1).."01"..("00"):rep(62)
src64.corner_rows_hex[2]=heights2
local changed_base=S.prepare(src64)
assert(changed_base.base_id~=minbase.base_id)
assert(changed_base.new_world().corner(2,2)==1)
assert(changed_base.load_world(small.encode())==nil)
src64.corner_rows_hex[2]=heights2:gsub("01","06")
assert(not pcall(S.prepare,src64))
core.log("action",string.format("LUANTTD STOCK SPARSE OVERLAY PASS: %d corners, %d road records, %d official slopes",w*h,roads,checked))
core.after(0,function() core.request_shutdown("Sparse overlay assertions finished",false,0) end)
