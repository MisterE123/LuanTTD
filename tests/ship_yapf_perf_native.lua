local dir=core.get_modpath("luanttd_core")
local function lib(n)return dofile(dir.."/"..n..".lua")end
local function stock(n)return lib("openttd/"..n)end
if not core.register_node then
  function core.follow_bench()
    local Sim,T=lib("sim"),stock("terrain")
    local Track,Fac,Net,Yapf,Search=stock("rail_track"),stock("ship_facilities"),lib("ship_network"),
      stock("ship_yapf"),stock("yapf_road_search")
    local s={tiles={},corner_grid=T.new(96,64),topology=1}
    Sim.W,Sim.H=96,64
    for z=1,64 do for x=1,96 do
      local island=(x>38 and x<54 and z>15 and z<45) or (x>60 and x<70 and z<24)
      s.tiles[Sim.id(x,z)]={terrain=island and "grass" or "water",h=0,
        water_class=not island and (z%8==1 and "river" or "sea") or nil}
    end end
    local ship={ocean_speed_frac=0,canal_speed_frac=26}
    local sw=Track.diagonal_trackdir(Track.SW)
    local old,new=lib("old_follow")(Track),stock("ship_follow")(Track)
    local answers={}
    local function batch(w)
      local y=w==old and lib("old_yapf")(Track,w,lib("old_search")) or Yapf(Track,w,Search)
      local b=Net(Sim,T,w,Fac(Track,w)).board(s)
      local t0=core.get_us_time()
      local total=0
      for i=1,22 do
        local start,goal=Sim.id(19,11+i),Sim.id(79,39-i)
        local dst=y.destination(b,ship,{kind="tile",tile=goal})
        local hit,node,stats=y.find(b,ship,start,Track.trackdirbit(sw),dst)
        assert(hit and node)
        local list=y.trace(b,ship,dst,node)
        total=total+#list
        local key=node.cost..":"..stats.closed_count..":"..tostring(stats.capped)
        for _,r in ipairs(list) do key=key.." "..r.tile..":"..r.td end
        if answers[i] then assert(answers[i]==key) else answers[i]=key end
      end
      return (core.get_us_time()-t0)/1000,total
    end
    -- Warm both paths before the alternating samples.
    batch(old);batch(new)
    local report={}
    for i=1,8 do
      collectgarbage("collect")
      local before=i%4==1 or i%4==0
      local ms,total=batch(before and old or new)
      report[i]=("WATER FOLLOW %s %.2f ms %d route nodes"):format(before and "baseline" or "candidate",ms,total)
    end
    return report
  end
  return
end
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
core.register_alias("mapgen_river_water_source","air")
core.register_async_dofile(dir.."/init.lua")
core.after(0,function()
  assert(core.handle_async(function()return core.follow_bench()end,function(r)
    for _,line in ipairs(r) do core.log("action",line) end
    core.request_shutdown("Routing benchmark complete",false,0)
  end))
end)
