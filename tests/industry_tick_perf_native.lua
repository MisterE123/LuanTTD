local m=core.get_modpath("luanttd_core").."/"
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.after(0,function()
 local ordinary=core.settings:get_bool("luanttd_qa_industry_ordinary",false)
 assert(core.handle_async(function(ordinary)
  local m=core.get_modpath("luanttd_core").."/"
  local function D(k) return dofile(m..k..".lua") end
  local P,Ra,I=D("openttd/passengers"),D("openttd/station_rating"),D("openttd/income")
  local C=D("openttd/station_catchment")(P,Ra)
  local Coal=D("openttd/coal_industry")(P,Ra,C,I)
  local Timber=D("openttd/timber_industry")(P,C,Ra,I,Coal,D("openttd/town_goods"))
  local Fields=D("openttd/farm_factory_fields")(Coal)
  local function prepare(base)
    local Runtime=D(base and "baseline-runtime" or "timber_industry_runtime")
    local FarmCtor=D(base and "baseline-farm" or "openttd/farm_factory_industry")
    local Oil=D(base and "baseline-oil" or "openttd/oil_industry")(FarmCtor,P,C,Ra,I,Coal,Timber)
    local Farm=FarmCtor(P,C,Ra,I,Coal,Timber)
    local _,Adapter=D(base and "baseline-combined" or "combined_industry_runtime")(Timber,Farm,Oil,Fields,Runtime,C)
    local s={industry={},random=1751,draws=0,ambient=0,attempts=0}
    local function rnd()
      s.random=(1664525*s.random+1013904223)%4294967296
      s.draws=s.draws+1;return s.random
    end
    local rows={{"forest",Timber},{"sawmill",Timber},{"farm",Farm},{"factory",Farm},{"oil_well",Oil},{"oil_refinery",Oil}}
    for id=1,768 do
      local p=rows[(id-1)%#rows+1]
      local counter=id%256
      if ordinary and id%2==1 then counter=65535-counter end
      s.industry[id]=p[2].new(p[1],id,((id-1)%32)*16+8,math.floor((id-1)/32)*16+8,
        {completed=true,counter=counter,original=true,generating_world=true})
      if ordinary and id%51==0 then s.industry[id].removed=true end
    end
    s.ledger=Adapter.new()
    local B=Adapter.bind(s,s.ledger,{width=512,height=512,xy=function(id)return id%512,math.floor(id/512)end,
      industries=s.industry,stations={},random_u32=rnd,
      field_board={width=512,height=512,tile=function() s.attempts=s.attempts+1;return {kind="protected"} end},
      ambient=function()s.ambient=s.ambient+1 end,
      opts=ordinary and {} or {editor=function(_,tick)return tick%131==0 end,scale=function(_,tick)return 90+tick%21 end}})
    return s,B
  end
  local function same(a,b)
    if a==b then return true end
    if type(a)~="table" or type(b)~="table" then return false end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  local before,base=prepare(true)
  local after,candidate=prepare(false)
  local output={}
  local tick=0
  local function measure(B,start)
    collectgarbage("collect")
    local t=os.clock()
    for u=start+1,start+256 do
      if B.produce_all then B.produce_all(u)
      else for _,i in ipairs(B.industries) do B.produce(i.id,u) end end
    end
    return (os.clock()-t)*1000
  end
  for i=1,12 do
    local a,b
    if i%2==1 then a=measure(base,tick);b=measure(candidate,tick)
    else b=measure(candidate,tick);a=measure(base,tick) end
    tick=tick+256
    assert(same(before,after) and after.draws>0 and after.ambient>0 and after.attempts>0)
    output[i]={a,b,after.draws,after.ambient,after.attempts}
  end
  -- Mixed standalone/replayed pulses must never produce twice or leave
  -- the batch replay ledger different from the baseline per-ID dispatch.
  local id=before.industry[1].id
  for _,B in ipairs({base,candidate}) do
    B.produce(id,tick+1)
    if B.produce_all then B.produce_all(tick+1);B.produce_all(tick+1)
    else for _,i in ipairs(B.industries) do B.produce(i.id,tick+1) end end
  end
  assert(same(before,after),"Ordered industry batch changed replay state")
  return output
 end,function(rows)
  assert(rows and #rows==12)
  for i,r in ipairs(rows) do core.log("action",("INDUSTRY PERF %d cpu=%.3f->%.3f draws=%d ambient=%d tiles_seen=%d"):format(i,unpack(r))) end
  core.request_shutdown("Industry profile complete",false,0)
 end,ordinary))
end)
