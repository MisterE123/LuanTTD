local dir=(arg and arg[1]) or "."
local function load(name) return dofile(dir.."/mods/luanttd_core/"..name..".lua") end
local W,S=load("world_storage"),load("openttd/slope")
local T=load("terrain_stream")(S)
local C=T.cover
local samples=0
local function make(w,h)
  return W.new(w,h,{base_id="test.terrain/1",seed=77,
    corner=function(seed,x,z) samples=samples+1
      return seed%10+math.floor((x-1)/9)%2+math.floor((z-1)/7)%2
    end,
    tile=function(_,x,z) samples=samples+1
      return x==1 and 7 or (x==8 and 4 or (z==6 and 6 or 0))
    end})
end
local function desc(word,x)
  if word==4 then return word,3 end
  if word==6 then return word,x%4==0 and 2 or x%4==1 and 1 or x%4==2 and 4 or nil end
  return word,0
end
local function by_tile(view,x,z)
  for _,ch in ipairs(view.chunks) do if T.profile(ch,x,z) then return ch end end
end
local function evictable_count(record)
  return #record.chunks+record.pending
end
local function edit(kind,x,z,value) return {kind=kind,x=x,z=z,value=value} end
local function approx(a,b) assert(math.abs(a-b)<1e-9,string.format("%.10f != %.10f",a,b)) end

collectgarbage("collect")
local before=collectgarbage("count")
local huge=make(4096,4096)
local stream=T.new(T.for_storage(W,huge,desc),{size=16,capacity=8})
assert(samples==0 and stream.stats().cached==0)
local view=assert(stream.update(2049,2049,64,1))
assert(view.built==1 and view.pending==7 and view.excluded>0 and #view.chunks==1)
assert(view.chunks[1].x==2049 and view.chunks[1].z==2049)
local same=stream.update(2049,2049,64,0)
assert(same.built==0 and same.pending==7 and samples==16*16+17*17)
local done=stream.update(2049,2049,64,16)
assert(done.built==7 and done.pending==0 and #done.chunks==8)
local count=samples
view,same,done=nil,nil,nil
collectgarbage("collect")
local alloc=collectgarbage("count")-before
assert(W.stats(huge).chunks==0 and stream.stats().cached==8 and alloc<80)
assert(count==8*(16*16+17*17))
local at_edge=stream.update(4096,4096,0,1)
assert(at_edge.chunks[1].x==4081 and T.corner(at_edge.chunks[1],4097,4097)==W.get_corner(huge,4097,4097))
assert(T.profile(at_edge.chunks[1],4097,4097)==nil and stream.stats().cached==1)
assert(stream.update(4097,1,1,1)==nil and stream.update(1,1,65,1)==nil and stream.update(1,1,8,17)==nil)
local tiny=make(64,64)
stream=T.new(T.for_storage(W,tiny,desc),{size=8,capacity=48})
local view1=stream.update(16,16,16,16)
local view2=stream.update(16,16,16,16)
assert(view2.pending==0 and evictable_count(view1)==evictable_count(view2) and #view2.chunks==16)
for i=1,#view1.chunks do assert(view2.chunks[i].id==view1.chunks[i].id) end
assert(view1.chunks[1].id==9 and view1.chunks[2].id==10 and view1.chunks[3].id==17 and view1.chunks[4].id==18)
local x,z=17,17
local nw,ne,sw,se=by_tile(view2,x-1,z-1),by_tile(view2,x,z-1),by_tile(view2,x-1,z),by_tile(view2,x,z)
local same_corner=T.corner(nw,x,z)
for _,ch in ipairs({ne,sw,se}) do assert(T.corner(ch,x,z)==same_corner) end
for i=0,8 do
  approx(T.height(nw,x-1,z-1,1,i/8),T.height(ne,x,z-1,0,i/8))
  approx(T.height(nw,x-1,z-1,i/8,1),T.height(sw,x-1,z,i/8,0))
end

-- Mutating a detached wrapper cannot rewrite latest windows or the cache.
nw.profiles="bad"; nw.x=99
local fixed=stream.update(16,16,16,0)
assert(T.corner(by_tile(fixed,x-1,z-1),x,z)==same_corner)
local old_window=fixed.chunks
local _,ticket=W.snapshot(tiny,16,16,18,18)
-- Changing (17,17) affects four 8x8 chunks. Its native baseline is level 8
-- with all four neighbours also level 8, so this one-step edit is legal.
assert(stream.apply_job(ticket,{edit("corner",x,z,same_corner+1)})==1)
local dirty=stream.update(16,16,16,0)
assert(dirty.pending==4 and #dirty.chunks==12)
for _,ch in ipairs(dirty.chunks) do
  assert(T.corner(ch,x,z)==nil)
end
assert(T.corner(by_tile({chunks=old_window},x,z),x,z)==same_corner)
local repaired=stream.update(16,16,16,4)
assert(repaired.pending==0 and repaired.built==4 and stream.stats().cached==16)
for _,p in ipairs({{x-1,z-1},{x,z-1},{x-1,z},{x,z}}) do
  assert(T.corner(by_tile(repaired,p[1],p[2]),x,z)==same_corner+1)
end
local rev,changed=stream.commit(1,{edit("corner",x,z,same_corner+1)})
assert(rev==1 and not changed and stream.stats().cached==16)
assert(stream.commit(1,{edit("tile",x,z,6),edit("corner",x,z,same_corner+1)})==2 and stream.stats().cached==15)
assert(stream.update(16,16,16,1).built==1)
assert(W.commit(tiny,2,{edit("tile",29,29,4)})==3)
assert(stream.update(16,16,16,0).pending==16,"missed revision left stale geometry")
local shore=stream.update(5,6,6,16)
local function profile(x,z0) return T.profile(by_tile(shore,x,z0),x,z0) end
assert(profile(1,6).cover==C.VOID and T.mesh(by_tile(shore,1,6),1,6)==nil)
assert(profile(4,6).cover==C.COAST and profile(5,6).cover==C.WATER_FLAT)
assert(profile(6,6).cover==C.LOCK and profile(7,6).cover==C.WATER_UNRESOLVED)
assert(profile(8,6).cover==C.COAST_TREES)
local p=profile(8,6)
assert(p.shore_land_mask==p.mask%16 and p.shore_land_mask+p.shore_water_mask==15)

-- Every valid stock corner combination and fractional surface on both faces.
local shapes={}
for n=0,2 do for w=0,2 do for e=0,2 do for s=0,2 do
  if S.valid(n,w,e,s) then
    local mask,base=S.classify(n,w,e,s)
    shapes[mask]=true
    local chunk={schema="luanttd-terrain-chunk/1",x=1,z=1,width=1,depth=1,
      corners=string.char(n,w,e,s),tiles=string.rep(string.char(0),4),
      profiles=string.char(mask,base,math.max(n,w,e,s),0,C.LAND_GRADED,0)}
    local vertices,faces=T.mesh(chunk,1,1)
    for _,f in ipairs(faces) do
      local a,b,c=vertices[f[1]],vertices[f[2]],vertices[f[3]]
      assert((b.z-a.z)*(c.x-a.x)-(b.x-a.x)*(c.z-a.z)>0)
      for i=0,8 do for j=0,8-i do
        local r,t=i/8,j/8
        local u,v=(a.x*(1-r-t)+b.x*r+c.x*t-1.5)/2,(a.z*(1-r-t)+b.z*r+c.z*t-1.5)/2
        approx(a.y*(1-r-t)+b.y*r+c.y*t,T.height(chunk,1,1,u,v))
      end end
    end
  end
end end end end
local shape_count=0
for _ in pairs(shapes) do shape_count=shape_count+1 end
assert(shape_count==19)
print(string.format("Terrain stream passed: %d stock mesh shapes, 4-chunk edit fence, %d map samples and %.1f KiB retained for 8/4096² chunks",
  shape_count,count,alloc))
