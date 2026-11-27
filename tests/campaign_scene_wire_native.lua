for _,n in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..n,"air") end
core.after(0,function()
 assert(core.handle_async(function()
  local root=assert(core.get_modpath("luanttd_core")).."/"
  local full,delta=dofile(root.."wire_fixture.lua")
  local k="luanttd_native_wire_benchmark"
  local function check(value)
    core.ipc_set(k,value)
    local r=assert(core.ipc_get(k))
    core.ipc_set(k,nil)
    assert(r.seq==value.seq and r.value[1].scene==value.value[1].scene)
  end
  local function time(value)
   check(value)
   collectgarbage("collect");local begin=core.get_us_time()
   for i=1,30 do check(value) end
   return (core.get_us_time()-begin)/1000
  end
  local out={full_bytes=#core.serialize(full),delta_bytes=#core.serialize(delta)}
  assert(out.delta_bytes<out.full_bytes/20,"Sparse edited scenes must substantially reduce the transfer")
  for i=1,4 do
   local a,b
   if i%2==1 then a=time(full);b=time(delta) else b=time(delta);a=time(full) end
   out[i]={a,b}
  end
  return out
 end,function(out)
  assert(out and #out==4)
  core.log("action",("NATIVE SCENE WIRE serialized %d/%d bytes"):format(out.full_bytes,out.delta_bytes))
  for i,row in ipairs(out) do
   core.log("action",("NATIVE SCENE WIRE pair %d: %.2f/%.2f ms"):format(i,unpack(row)))
  end
  core.request_shutdown("Native scene wire verified",false,0)
 end))
end)
