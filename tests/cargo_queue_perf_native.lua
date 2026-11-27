core.set_mapgen_setting("mg_name","singlenode",true)
for _,node in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..node,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=core.get_modpath("bench")
    local Clock=dofile(m.."/openttd/loading_timing.lua")
    local Packets=dofile(m.."/openttd/passengers.lua")
    local old=dofile(m.."/baseline.lua")(Clock,Packets)
    local new=dofile(m.."/road_loading_runtime.lua")(Clock,Packets)
    local function same(a,b,fwd,rev)
      if type(a)~="table" or type(b)~="table" then return a==b end
      if fwd[a] or rev[b] then return fwd[a]==b and rev[b]==a end
      fwd[a],rev[b]=b,a
      for k,v in pairs(a) do if not same(v,b[k],fwd,rev) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    local xy=function(i) return i%64,math.floor(i/64) end
    local function make(L,size,full,cargo)
      local q={}
      local st={id=9,tile=211,stock={[cargo]=q}}
      for i=1,size do
        local age=(i-1)%27
        q[i]={units=i%3+1,origin_station=31+i%28,source=(i-1)%96,source_type="town",
          age=age,origin_tile=319+i%64,travel_x=i%3,travel_z=i%5,
          feeder_share=i%7==0 and 31*i or i%9==0 and -i or nil}
      end
      local v={id=37,cargo=cargo,batches={},units=0}
      local rec={st=st,v=v,events={}}
      local flags={full=full or nil}
      local ops={gradual=true,xy=xy,slice=5,
        pickup=function(_,_,p) Packets.pickup(p,st,xy);rec.events[#rec.events+1]=p.source end,
        loaded=function(_,_,n) rec.events[#rec.events+1]=n end}
      L.begin(st,v,64,flags,ops)
      return {rec=rec,step=function()
        if full then L.body_reserve(st,v,ops) end
        local result=L.body_round(st,v,ops)
        return result
      end}
    end
    for _,n in ipairs({0,1,2,13,31,32,48,512,1536}) do
      for _,full in ipairs({false,true}) do
        for _,cargo in ipairs({"passenger","mail","goods"}) do
          local a,b=make(old,n,full,cargo),make(new,n,full,cargo)
          for _=1,13 do
            local l,r=a.step(),b.step()
            assert(same(l,r,{}, {}) and same(a.rec,b.rec,{}, {}),"packet loading parity failed "..n)
          end
        end
      end
    end
    local rows={}
    for _,n in ipairs({8,128,768,1536}) do
      for i=1,12 do
        local base=i%4<=1
        local L=base and old or new
        local cases={}
        local total=math.floor(48000/n)
        for j=1,total do cases[j]=make(L,n,i%2==0,j%2==0 and "mail" or "passenger") end
        collectgarbage("collect")
        local t,c=core.get_us_time(),os.clock()
        local moved=0
        for _,b in ipairs(cases) do local v=b.step();moved=moved+(v.loaded or 0)+(v.reservations or 0) end
        rows[#rows+1]={n,base and "baseline" or "candidate",i,(core.get_us_time()-t)/1000,(os.clock()-c)*1000,total,moved}
      end
    end
    return rows
  end,function(rows)
    assert(rows)
    for _,r in ipairs(rows) do core.log("action",("CARGO QUEUE PROFILE n=%d %s i=%d wall=%.3f cpu=%.3f stations=%d moved=%d"):format(unpack(r))) end
    core.request_shutdown("Cargo queue benchmark complete",false,0)
  end))
end)
