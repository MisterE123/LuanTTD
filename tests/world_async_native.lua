-- Disposable Luanti dedicated-server test. Worker registration is real.
local path=core.get_modpath(core.get_current_modname())
local W=dofile(path.."/world_storage.lua")
local S=dofile(path.."/openttd/slope.lua")
local Q=assert(dofile(path.."/world_async.lua").new(core,path,W,{inflight=2}))
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
core.register_alias("mapgen_river_water_source","air")
local reads=0
local opts={seed=1751,base_id="native.world-test/1",
  corner=function() reads=reads+1;return 0 end,
  tile=function() reads=reads+1;return 0 end}
local world=W.new(4096,4096,opts)
local foreign=W.new(4096,4096,opts)
assert(reads==0 and #W.encode(world)<80 and W.stats(world).chunks==0)
local mid=2048
local job={kind="corner",x=mid,z=mid,mask=8,up=true}
local function submit(job,cb)
  return assert(Q.submit(world,mid-15,mid-15,mid+16,mid+16,job,cb))
end
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function raster(r,err)
  assert(core.get_player_by_name and not err and r.kind=="raster" and r.revision==2)
  eq(#r.profiles,3072)
  for z=mid-15,mid+16 do for x=mid-15,mid+16 do
    local n,w,e,s=W.tile_corners(world,x,z)
    local m,b=S.classify(n,w,e,s)
    local p,q,t=Q.profile(r,x,z)
    eq(p,m);eq(q,b);eq(t,math.max(n,w,e,s))
  end end
  eq(Q.stats().inflight,0)
  eq(W.stats(world).corners,5)
  eq(W.stats(world).tiles,0)
  eq(W.stats(world).chunks,3)
  assert(reads<30000 and #W.encode(world)<100)
  core.log("action",("LUANTTD WORLD ASYNC TERRAIN PASS: 4096² sparse, overlap rejected, 5 corners committed, 1024 raster records, max input %d bytes; %d base samples")
    :format(Q.stats().max_input,reads))
  core.request_shutdown("Bounded async terrain assertions finished",false,0)
end
core.register_on_mods_loaded(function()
  assert(Q.stats().max_input==5185)
  submit(job,function(stale,why)
    assert(core.get_player_by_name and stale==nil and why=="stale world revision")
    submit(job,function(proposal,err)
      assert(proposal,err)
      eq(proposal.changes,5);eq(proposal.cost,5);eq(proposal.revision,1)
      local got,foreign_error=Q.apply(foreign,proposal,function() error("foreign authorization called") end)
      assert(not got and foreign_error=="invalid owner terrain proposal")
      local rev,changed=Q.apply(world,proposal,function(owner,ctx)
        assert(owner==world and ctx.revision==1 and ctx.job.x==mid and ctx.map_width==4096)
        eq(#ctx.edits,5)
        local before=W.get_corner(world,mid,mid)
        eq(before,1)
        ctx.edits[1].value=201
        return true
      end)
      eq(rev,2);assert(changed)
      eq(W.get_corner(world,mid,mid),2)
      for _,d in ipairs{{-1,0},{1,0},{0,-1},{0,1}} do eq(W.get_corner(world,mid+d[1],mid+d[2]),1) end
      assert(not Q.apply(world,proposal,function() return true end))
      submit({kind="raster"},raster)
    end)
  end)
  -- This is the exact corner targeted by the in-flight stock plan.
  -- The delivery callback cannot run until this owner step completes.
  eq(W.commit(world,0,{{kind="corner",x=mid,z=mid,value=1}}),1)
end)
