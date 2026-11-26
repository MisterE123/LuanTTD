local mod=core.get_modpath("luanttd_core")
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim,P,Rating,H=m("sim"),m("openttd/passengers"),m("openttd/station_rating"),m("openttd/town_passengers")
local Loader=m("station_rating_runtime")(Sim,Rating,P)
local baseline=m("baseline_mail")(Sim,H,P,m("openttd/income"),Rating,Loader)
local candidate=m("road_mail_runtime")(Sim,H,P,m("openttd/income"),Rating,Loader)
local C=m("openttd/station_catchment")(P,Rating,nil,candidate.house_acceptance)
local codec=m("packed_campaign")
for _,g in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..g,"air") end
core.after(0,function()
  local side,w=512,{}
  for i=0,511 do
    local x,z=(i%32)*16+4,math.floor(i/32)*32+6
    local typ=i%3
    local kind=typ==0 and "truck" or typ==1 and "rail" or "airport_intercontinental"
    local tiles={}
    for dx=1,typ==0 and 2 or typ==1 and 5 or 10 do tiles[#tiles+1]={x=x+dx,y=z,kind=kind} end
    w[#w+1]={id=i+1,mode=typ==0 and "road" or typ==1 and "rail" or "air",owner="Office "..i%7,
      tiles=tiles,town=i%25+1,stock={}}
  end
  local fixture=codec.encode(w)
  local warmed=core.settings:get_bool("luanttd_mail_bench_warm",false)
  local function collect()
    -- A weak-key cache can free a dead fixture's values on the second
    -- full collection. Don't count that unrelated heap in the next day.
    collectgarbage("collect")
    collectgarbage("collect")
  end
  local function run(M)
    local st=codec.decode(fixture)
    local opts=warmed and {immutable_footprints=true} or nil
    if warmed then M.shared_allocator(C,side,side,st,opts) end
    collect()
    local heap,t=collectgarbage("count"),core.get_us_time()
    local a=M.shared_allocator(C,side,side,st,opts)
    local elapsed=(core.get_us_time()-t)/1000
    collect()
    local grown=collectgarbage("count")-heap
    for _,stop in ipairs(st) do
      a.loading(stop.id,stop.mode,120,1989,1984,20)
      stop.mail_rating_state.rating=125+stop.id%110
    end
    local moved=0
    t=core.get_us_time()
    for i=1,3000 do
      moved=moved+a.offer(6+i%8,(i*107)%511,math.floor(i*42671/511)%511,{town=i%19+1,area=i%7==0 and 2 or 1})
    end
    return {elapsed,grown,(core.get_us_time()-t)/1000,moved},st
  end
  local function same(a,b)
    if type(a)~="table" then return a==b end
    if type(b)~="table" then return false end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  for i=1,8 do
    local a,as,b,bs
    if i%2==1 then a,as=run(baseline);b,bs=run(candidate)
    else b,bs=run(candidate);a,as=run(baseline) end
    assert(a[4]==b[4] and a[4]>0 and same(as,bs),"Mail allocations changed")
    core.log("action",("MAIL_INDEX trial=%d build_a=%.3f build_b=%.3f kib_a=%.1f kib_b=%.1f query_a=%.3f query_b=%.3f moved=%d"):format(i,a[1],b[1],a[2],b[2],a[3],b[3],a[4]))
  end
  core.request_shutdown("Shared Mail station index measured",false,0)
end)
