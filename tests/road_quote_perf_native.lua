core.set_mapgen_setting("mg_name","singlenode",true)
for _,n in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..n,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=core.get_modpath("luanttd_core").."/"
    local S=dofile(m.."sim.lua")
    S.W,S.H=512,512
    local s=S.new(1751)
    s.sites={}
    for _,t in ipairs(s.tiles) do t.terrain,t.h,t.wood,t.site,t.house="grass",1,nil,nil,nil end
    s.corner_grid=dofile(m.."openttd/terrain.lua").new(S.W,S.H,function()return 1 end)
    for who=1,8 do S.company(s,"Bench "..who).cash=123456789 end
    local id=S.id
    local variants={}
    for _,name in ipairs({"baseline_road_construction.lua","campaign_road_construction.lua"}) do
      variants[#variants+1]=dofile(m..name)(S,s)
    end
    local tests={}
    for i=1,256 do
      local x,z=20+i%11,20+i
      local opp=i%7==0 and 5 or 0
      local x2=x+18+i%100
      tests[i]={"Bench "..(1+i%8),{first=id(x,z),last=id(x2,z+opp),
        tool=opp==0 and "drag" or "bend",axis=0,start_half=false,end_half=true}}
    end
    local stats={}
    local out={}
    for i=1,10 do
      for leg=1,2 do
        local side=i%2==1 and leg or 3-leg
        collectgarbage("collect")
        local tm,cpu=core.get_us_time(),os.clock()
        local terms=0
        for j,case in ipairs(tests) do
          local result,err=variants[side].quote(unpack(case))
          assert(result,err)
          if out[j] then
            local b=out[j]
            assert(result.ticket==b.ticket and result.cost==b.cost and #result.tiles==#b.tiles and
              result.depot_direction==b.depot_direction and result.stopped_at==b.stopped_at)
            for k,t in ipairs(result.tiles) do assert(t==b.tiles[k]) end
          else out[j]=result end
          terms=terms+#result.tiles
        end
        stats[#stats+1]={side,i,core.get_us_time()-tm,(os.clock()-cpu)*1e6,terms}
      end
    end
    return stats
  end,function(rows)
    assert(rows)
    for _,r in ipairs(rows) do core.log("action",("QUOTE BENCH side=%d run=%d wall_us=%d cpu_us=%.3f tiles=%d"):format(unpack(r))) end
    core.request_shutdown("Road quote profile complete",false,0)
  end))
end)
