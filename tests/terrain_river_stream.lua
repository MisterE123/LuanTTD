local path="mods/bayline"
local F=dofile("tests/terrain_river_fixture.lua")(path)
local W,D,T,P=F.storage,F.words,F.stream,F.protocol
local worker=dofile(path.."/world_async_worker.lua")(P,F.slope,F.terrain)
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local same,width=F.rivers,128
local world=W.new(width,width,F.options)
eq(W.stats(world).chunks,0); eq(#W.encode(world),139)
local source=T.for_storage(W,world,D.describe)
local view=T.new(source,{size=16,capacity=4})
local flat,graded,changed=0,0,0
for z=1,width do for x=1,width do
  if F.raw.corner(x,z)~=same.corner(x,z) then changed=changed+1 end
end end
eq(changed,3)
for z=1,width,16 do for x=1,width,16 do
  local frame=assert(view.update(x,z,0,1))
  eq(frame.schema,"luanttd-terrain-view/2")
  local ch=assert(frame.chunks[1]);eq(ch.schema,"luanttd-terrain-chunk/2")
  for v=z,z+15 do for u=x,x+15 do
    local p=assert(T.profile(ch,u,v))
    local raw=same.tile(u,v)
    local native_mask,base=F.slope.classify(same.corner(u,v),same.corner(u+1,v),same.corner(u,v+1),same.corner(u+1,v+1))
    eq(p.mask,native_mask);eq(p.base,base)
    if raw==54 then
      local r=assert(same.river_bits(u,v))
      eq(p.class,6);eq(p.ground,3);eq(p.water_class,"river");eq(p.river_bits,r)
      eq(p.cover,native_mask==0 and T.cover.RIVER_FLAT or T.cover.RIVER_GRADED)
      eq(p.river_flat,native_mask==0);eq(p.word,D.river(r))
      assert(p.shore_land_mask==nil and p.shore_water_mask==nil)
      if p.river_flat then flat=flat+1 else graded=graded+1 end
    else
      eq(p.word,raw); assert(p.water_class~="river" and p.river_bits==nil)
    end
  end end
end end
eq(flat,194);eq(graded,18)
-- One real river crosses the X=80/81 chunk boundary on an inclined tile;
-- still read the two shared north/south corners on both sides.
local x,z=80,63
local before=assert(view.update(x,z,4,4))
local left,right
for _,c in ipairs(before.chunks) do
  if T.profile(c,x,z) then left=c elseif T.profile(c,x+1,z) then right=c end
end
local a,b=assert(T.profile(left,x,z)),assert(T.profile(right,x+1,z))
eq(a.cover,T.cover.RIVER_GRADED);eq(a.mask,12);eq(a.river_bits,26)
eq(b.cover,T.cover.RIVER_FLAT);eq(b.mask,0)
for i=0,8 do eq(T.height(left,x,z,1,i/8),T.height(right,x+1,z,0,i/8)) end

local snap,ticket=assert(W.snapshot(world,65,49,96,80))
eq(#snap.tiles+#snap.corners,P.max_input());eq(P.max_input(),5185)
eq(W.snapshot_tile(snap,x,z),D.river(26))
assert(P.snapshot(snap) and ticket)
local j=assert(P.job(snap,{kind="river_raster"}))
local response=worker(snap,j,9)
eq(response.schema,"luanttd-world-async-result/2")
eq(#response.profiles,7168);assert(not response.tiles)
local report=assert(P.result(snap,j,9,response))
eq(P.terrain_profile(report,x,z).river_bits,26)
eq(report.tiles,snap.tiles)
for v=49,80 do for u=65,96 do
  local p=assert(P.terrain_profile(report,u,v))
  local expected=same.tile(u,v)
  eq(p.word,expected==54 and D.river(same.river_bits(u,v)) or expected)
  eq(p.river_bits,same.river_bits(u,v))
end end
local function corrupt_reply(change)
  local r=worker(snap,j,9);change(r)
  assert(not P.result(snap,j,9,r))
end
corrupt_reply(function(r)r.schema="luanttd-world-async-result/1" end)
corrupt_reply(function(r)r.profiles=r.profiles:sub(2) end)
corrupt_reply(function(r)r.tiles=snap.tiles end)
corrupt_reply(function(r)
  -- Correct ID, shape syntax and length, but wrong height for owner corners.
  local m,b,h=r.profiles:byte(1,3)
  r.profiles=string.char(m,b+1,h+1)..r.profiles:sub(4)
end)
local before_bytes=snap.tiles
local i=4*((z-49)*32+x-65)+1
snap.tiles=before_bytes:sub(1,i-1)..string.char(54,0,0,0)..before_bytes:sub(i+4)
local _,why=P.result(snap,j,9,worker(snap,j,9))
eq(why,"INVALID_TERRAIN_WORD")
snap.tiles=before_bytes

-- Explicit zero is not absence. One typed tile change costs 8 save bytes
-- and updates only its existing chunk; invalid raw river writes cost none.
assert(not view.commit(0,{{kind="tile",x=x,z=z,value=54}}))
eq(W.stats(world).revision,0)
eq(view.commit(0,{{kind="tile",x=x,z=z,value=D.river(0)}}),1)
local updated=assert(view.update(x,z,4,4))
local zero
for _,c in ipairs(updated.chunks) do zero=zero or T.profile(c,x,z) end
eq(zero.river_bits,0);eq(a.river_bits,26);eq(zero.mask,12)
eq(W.stats(world).chunks,1);eq(W.stats(world).tiles,1)
local bytes=W.encode(world);eq(#bytes,147)
local rebuilt=assert(W.decode(bytes,F.options))
eq(W.get_tile(rebuilt,x,z),D.river(0));eq(W.encode(rebuilt),bytes)
assert(not W.decode(bytes,same.storage_options()))
assert(not W.decode(bytes:sub(1,-5)..string.char(54,0,0,0),F.options))

local legacy=W.new(128,128,same.storage_options())
local old=T.new(T.for_storage(W,legacy,D.describe),{size=16,capacity=1})
local old_chunk=assert(old.update(x,z,0,1).chunks[1])
local old_river=assert(T.profile(old_chunk,x,z))
eq(old_river.cover,T.cover.RIVER_GRADED)
assert(old_river.river_bits==nil and old_river.word==54)
local old_snapshot=assert(W.snapshot(legacy,65,49,96,80))
assert(not P.job(old_snapshot,{kind="river_raster"}))
assert(P.job(old_snapshot,{kind="raster"}))
eq(#W.encode(legacy),134)
print(("RIVER STREAM PASS: %d flat/%d graded widened source rivers; grade seam; typed reply/patch rejection; %d/%d byte pristine/edited saves, %d input/%d output bytes")
  :format(flat,graded,139,#bytes,P.max_input(),#response.profiles))
