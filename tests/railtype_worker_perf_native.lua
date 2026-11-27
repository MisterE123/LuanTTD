-- Observe the real company endpoint from the Luanti async VM. The same
-- world sees repeated view polls and both gauges queried per company.
local mod=assert(core.get_modpath("luanttd_core"))
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core")).."/"
    local F=dofile(m.."rail_depot_fleet.lua")
    local Roster=dofile(m.."openttd/rail_roster.lua")
    local Types=dofile(m.."openttd/rail_types.lua")
    local Endpoint=dofile(m.."campaign_authority_endpoint.lua")
    local Cargo=dofile(m.."sim.lua")
    local function prepare(source)
      local source_owned=dofile(m..source..".lua")
      local s={day=0,companies={},stock_electrification=true,sites={},speed=1}
      for i=1,4 do s.companies["Company "..i]={cash=200000,loan=100000} end
      local Fleet=F(Cargo,{},Roster)
      assert(Fleet.initialize(s,{starting_year=1980,climate="temperate",generation_seed=1751,startup_random=9001}))
      local native_get=Fleet.railtype_mask
      local count=0
      Fleet.railtype_mask=function(...) count=count+1;return native_get(...) end
      local ok=function() return true end
      local owned=source_owned(Fleet,Roster,{mount_advanced_wagon=ok,mount_owned_model=ok})
      assert(owned.mount_advanced(Types,{[54]=true,[57]=true,[58]=true,[84]=true,[89]=true,[90]=true}))
      local A=Endpoint(Cargo,{world=s,rail={railtype_available=function(who,gauge)
        return Types.available(gauge,owned.railtype_mask(s,who,Types))
      end}})
      return A,s,function() return count end
    end
    local function measure(source,first)
      local A,s,count=prepare(source)
      collectgarbage("collect")
      local t=os.clock()
      local seen={}
      for day=first,first+31 do
        s.day=day
        for poll=1,8 do
          for operator=1,4 do
            local reply=A.company("Company "..operator)
            local v=assert(reply.ok and reply.value)
            seen[#seen+1]=(v.rail_mono and 1 or 0)+(v.rail_maglev and 2 or 0)
          end
        end
      end
      return (os.clock()-t)*1000,count(),table.concat(seen,",")
    end
    local rows={}
    local a,ac,trace,b,bc,next_trace
    for i=1,12 do
      local d=(i-1)*2300
      if i%2==0 then
        b,bc,next_trace=measure("rail_owned_service",d)
        a,ac,trace=measure("baseline_owned",d)
      else
        a,ac,trace=measure("baseline_owned",d)
        b,bc,next_trace=measure("rail_owned_service",d)
      end
      assert(trace==next_trace and ac==2048 and bc==32)
      rows[i]={a,b,ac,bc}
    end
    return rows
  end,function(rows)
    assert(rows and #rows==12)
    local a,b={},{}
    for i,r in ipairs(rows) do
      a[i],b[i]=r[1],r[2]
      core.log("action",("RAILTYPE PERF pair=%d cpu_ms=%.3f->%.3f roster_reads=%d->%d"):format(i,unpack(r)))
    end
    table.sort(a);table.sort(b)
    core.log("action",("RAILTYPE PERF median cpu_ms=%.3f->%.3f"):format((a[6]+a[7])/2,(b[6]+b[7])/2))
    core.request_shutdown("Railtype worker profile finished",false,0)
  end))
end)
