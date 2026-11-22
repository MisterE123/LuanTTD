-- Dedicated Luanti async probe with a real widened source batch.
local path=core.get_modpath(core.get_current_modname())
local F=dofile(path.."/fixture.lua")(path)
local W,D=F.storage,F.words
local Q=assert(dofile(path.."/world_async.lua").new(core,path,W,{inflight=1}))
local disk=core.get_mod_storage()
local saved=disk:get_string("terrain")
local world=saved=="" and W.new(128,128,F.options) or assert(W.decode(saved,F.options))
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
core.register_alias("mapgen_river_water_source","air")
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local x,z=80,63
local function ask(cb)
  return assert(Q.submit(world,65,49,96,80,{kind="river_raster"},cb))
end
local function confirm(result,err)
  assert(core.get_player_by_name and not err)
  local r=assert(result)
  eq(r.schema,"luanttd-world-async-result/2");eq(#r.profiles,7168)
  eq(#r.tiles,4096)
  local graded,flat,byte0=0,0,0
  for v=49,80 do for u=65,96 do
    local p=assert(Q.terrain_profile(r,u,v))
    local n,a,b,d=W.tile_corners(world,u,v)
    local m,base=F.slope.classify(n,a,b,d)
    eq(p.mask,m);eq(p.base,base);eq(p.word,W.get_tile(world,u,v))
    if p.water_class=="river" then
      eq(p.river_bits,u==x and v==z and 0 or F.rivers.river_bits(u,v))
      if p.river_flat then flat=flat+1 else graded=graded+1 end
      if p.river_bits==0 then byte0=byte0+1 end
    end
  end end
  assert(graded>0 and flat>0 and byte0==1)
  eq(Q.terrain_profile(r,x,z).river_bits,0)
  eq(Q.terrain_profile(r,x,z).mask,12)
  eq(W.stats(world).chunks,1);eq(W.stats(world).tiles,1)
  local blob=W.encode(world)
  eq(#blob,147)
  if saved=="" then disk:set_string("terrain",blob) else eq(saved,blob) end
  core.log("action",("LUANTTD RIVER ASYNC %s PASS: %d flat/%d graded; preserved random byte zero, %d-byte save, 5185-byte input, 7168-byte worker result")
    :format(saved=="" and "SAVE" or "RESTORE",flat,graded,#blob))
  core.request_shutdown("Typed river worker proof completed",false,0)
end
core.register_on_mods_loaded(function()
  if saved~="" then
    eq(W.get_tile(world,x,z),D.river(0))
    ask(confirm)
    return
  end
  eq(#W.encode(world),139);eq(W.get_tile(world,x,z),D.river(26))
  ask(function(r,err)
    assert(not r and err=="stale world revision")
    core.log("action","LUANTTD RIVER ASYNC STALE PASS: in-flight byte-only terrain edit rejected")
    ask(confirm)
  end)
  eq(W.commit(world,0,{{kind="tile",x=x,z=z,value=D.river(0)}}),1)
end)
