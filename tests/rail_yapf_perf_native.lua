-- Rail YAPF A/B using allocating gameplay board, signal and PBS adapters.
local dir=core.get_modpath("luanttd_core")
local function lib(n)return dofile(dir.."/"..n..".lua")end
local function stock(n)return lib("openttd/"..n)end
if not core.register_node then
  function core.rail_yapf_bench()
    local Sim=lib("sim")
    Sim.W,Sim.H=256,64
    local T=stock("rail_track")
    local Signals=stock("rail_signals")(T)
    local s={tiles={},topology=0}
    local a=Signals.new()
    local owner="Bench"
    local id=Sim.id
    local old,new=lib("old_rail_follow")(T),stock("rail_follow")(T)
    local old_cost,new_cost=lib("old_rail_yapf_cost")(T,old),stock("rail_yapf_cost")(T,new)
    local initial=lib("trackworks")(Sim,T,new,{},new_cost,stock("rail_yapf_search")(T,new,new_cost)).board(s)
    local rows={}
    local function track(x,z,bits,fields)
      local key=id(x,z)
      local t={owner=owner,rail_tracks=bits}
      for k,v in pairs(fields or {}) do t[k]=v end
      s.tiles[key]=t
      return key
    end
    for i=1,16 do
      local z=2*i
      for x=2,240 do track(x,z,1) end
      local home=track(2,z,1,{rail_depot_dir=T.SW})
      track(52,z,33);track(63,z,9)
      track(52,z+1,16);track(63,z+1,4)
      for x=53,62 do track(x,z+1,1) end
      for x=237,240 do track(x,z,1,{rail_station_id=i,rail_station_axis=0}) end
      s.stock_rail_stations=s.stock_rail_stations or {}
      s.stock_rail_stations[i]={tiles={id(237,z),id(238,z),id(239,z),id(240,z)}}
      local signal=id(54,z)
      assert(Signals.place(initial,a,owner,signal,T.X,{kind=Signals.PBS,copy_mask=T.signal_along(8)}))
      if i%2==0 then
        assert(Signals.place(initial,a,owner,id(57,z),T.X,{kind=Signals.BLOCK,copy_mask=T.signal_along(0)}))
      end
      assert(Signals.place(initial,a,owner,id(130,z),T.X,{kind=Signals.BLOCK}))
      rows[i]={home=home,reserved=id(55,z),detour=id(56,z+1)}
    end
    local signed=Signals.view(initial,a)
    local PBS=stock("rail_reservation")(T,new,new_cost)
    local Life=stock("rail_consist_reservation")(T,new,PBS)
    local reservation=Life.new()
    for i,r in ipairs(rows) do
      assert(Life.register(signed,reservation,i,owner,{{tile=r.reserved,td=8}}))
    end
    local live=Life.view(signed,reservation)
    local reads=0
    local board=setmetatable({tile=function(k) reads=reads+1;return live.tile(k) end},{__index=live})
    local opts={forbid_90=true}
    local expected={}
    local function run(f,c)
      local y=stock("rail_yapf_search")(T,f,c)
      local t0=core.get_us_time()
      reads=0
      local exact,nodes=0,0
      for cycle=1,3 do
        for i,row in ipairs(rows) do
          local from={tile=row.home,td=8}
          local v={owner=owner,tile=from.tile,length=32,max_speed=132,railtype=0,compatible={[0]=true}}
          for j,order in ipairs({{kind="station",station=i},{kind="safe"}}) do
            local d=c.destination(board,v,order)
            local found,n,stats=y.find(board,v,from,d,opts)
            assert(found and n and not stats.capped,("no route for %d / %s"):format(i,order.kind))
            local trace=y.trace(board,v,n,opts)
            if j==1 then
              assert(#trace>=230 and trace[#trace].follow.skip==3)
              local detoured=false
              for _,r in ipairs(trace) do if r.tile==row.detour then detoured=true end end
              if i%2==0 then assert(detoured,"Back of one-way signal was not avoided") end
            end
            nodes=nodes+#trace
            local key={n.cost,n.estimate,n.reason,stats.closed_count,stats.steps,tostring(stats.stopped_on_first_two_way)}
            for _,r in ipairs(trace) do
              local f=r.follow
              key[#key+1]=r.tile;key[#key+1]=r.td;key[#key+1]=f and f.skip or 0
            end
            local nkey=table.concat(key,",")
            exact=exact+1
            if expected[exact] then assert(expected[exact]==nkey,"route or stock score changed") else expected[exact]=nkey end
          end
        end
      end
      return (core.get_us_time()-t0)/1000,reads,nodes,exact
    end
    run(old,old_cost);run(new,new_cost)
    local report={}
    for i=1,12 do
      local a,b,ra,rb,na,nb,ea,eb
      collectgarbage("collect")
      if i%2==1 then a,ra,na,ea=run(old,old_cost);b,rb,nb,eb=run(new,new_cost)
      else b,rb,nb,eb=run(new,new_cost);a,ra,na,ea=run(old,old_cost) end
      assert(ra>rb and ea==eb and na==nb)
      report[i]=("RAIL ROUTE NATIVE batch=%d baseline_ms=%.2f candidate_ms=%.2f reads=%d/%d nodes=%d exact=%d")
        :format(i,a,b,ra,rb,na,ea)
    end
    -- A second search on the very same adapter must observe a changed
    -- one-way head, without a topology revision or any cache invalidation.
    local row=rows[2]
    local v={owner=owner,tile=row.home,length=32,max_speed=132,railtype=0,compatible={[0]=true}}
    local y=stock("rail_yapf_search")(T,new,new_cost)
    local d=new_cost.destination(board,v,{kind="station",station=2})
    local from={tile=row.home,td=8}
    local function cost()
      local found,n=y.find(board,v,from,d,opts)
      assert(found)
      return n.cost
    end
    local forced=cost()
    assert(Signals.remove_track(initial,a,id(57,4),T.X))
    local released=cost()
    assert(released<forced,"new search did not reflect removal of one-way signal")
    return report
  end
  return
end
for _,n in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..n,"air") end
core.register_async_dofile(dir.."/init.lua")
core.after(0,function()
  assert(core.handle_async(function()return core.rail_yapf_bench()end,function(report)
    for _,line in ipairs(report) do core.log("action",line) end
    core.request_shutdown("Rail route profiling complete",false,0)
  end))
end)
