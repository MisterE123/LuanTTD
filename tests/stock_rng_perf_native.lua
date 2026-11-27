for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core")).."/"
    assert(bit and bit.ror and bit.bxor,"Test needs native LuaJIT bit operations")
    local base=dofile(m.."baseline.lua")({}, {day_ticks=74},{})
    local patch=dofile(m.."station_rating_runtime.lua")({}, {day_ticks=74},{})
    local function measure(R,init)
      local s={passenger_rating_rng={init[1],init[2]}}
      local run=R.random_u32
      local checksum=0
      local cpu=os.clock()
      for _=1,262144 do checksum=(checksum+run(s))%4294967296 end
      return (os.clock()-cpu)*1000,s.passenger_rating_rng,checksum
    end
    dofile(m.."stock_rng_rc1_vectors.lua")(patch)
    local cases={{0,0},{4294967295,4294967295},{2147483648,2147483647},{2147483647,2147483648},{1,0},{0,1}}
    local rows={}
    for i=1,12 do
      local a,sta,ca,b,stb,cb
      local seed=cases[(i-1)%#cases+1]
      if i%2==0 then b,stb,cb=measure(patch,seed);a,sta,ca=measure(base,seed)
      else a,sta,ca=measure(base,seed);b,stb,cb=measure(patch,seed) end
      assert(sta[1]==stb[1] and sta[2]==stb[2] and ca==cb)
      rows[i]={a,b}
    end
    local left,right={seed=1751},{seed=1751}
    for i=1,65536 do
      assert(base.random_u32(left)==patch.random_u32(right))
      assert(left.passenger_rating_rng[1]==right.passenger_rating_rng[1])
    end
    return rows
  end,function(rows)
    assert(rows and #rows==12)
    local a,b={},{}
    for i,r in ipairs(rows) do a[i],b[i]=r[1],r[2] end
    table.sort(a);table.sort(b)
    core.log("action",("RNG PERF median cpu_ms=%.3f->%.3f individual_steps=65536 comparable_batch_checksums=12"):format((a[6]+a[7])/2,(b[6]+b[7])/2))
    core.request_shutdown("Native RNG benchmark complete",false,0)
  end))
end)
