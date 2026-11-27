for _,n in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..n,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local base=core.get_modpath("luanttd_core").."/"
    local function lib(n) return dofile(base..n..".lua") end
    local S,Track,T=lib("sim"),lib("openttd/rail_track"),lib("openttd/terrain")
    S.W,S.H=128,128
    local shapes=0
    local terrain_tile=T.tile
    function T.tile(...) shapes=shapes+1;return terrain_tile(...) end
    local W=lib("openttd/ship_follow")(Track)
    local Fac=lib("openttd/ship_facilities")(Track,W)
    local Net=lib("ship_network")(S,T,W,Fac)
    local Y=lib("openttd/ship_yapf")(Track,W,lib("openttd/yapf_road_search"))
    local Move=lib("openttd/ship_motion")(Track,W)
    local Regions=lib("openttd/ship_regions")
    local extents={width=S.W,height=S.H,x0=1,z0=1}
    local region_builds=0
    local function regions(...)
      region_builds=region_builds+1
      return Regions(...)
    end
    local owner="Fleet QA"
    local ids=S.id
    local function fixture()
      local s={tiles={},topology=0,sites={},stations={},fleet={},companies={},news={},
        corner_grid=T.new(S.W,S.H,function(x) return (x<9 or x>=120) and 1 or 0 end)}
      for z=1,S.H do for x=1,S.W do
        local grass=x<9 or x>=119
        s.tiles[ids(x,z)]={terrain=grass and "grass" or "water",water_class=not grass and "sea" or nil,h=(x<8 or x>=120) and 1 or 0}
      end end
      local a=assert(Net.build(s,owner,"dock",ids(119,82)))
      local b=assert(Net.build(s,owner,"dock",ids(8,12)))
      local d=assert(Net.build(s,owner,"depot",ids(12,11),0))
      return s,d.id,a.id,b.id
    end
    local follows=0
    local oldfollow=W.follow
    function W.follow(...) follows=follows+1;return oldfollow(...) end
    local function run(opt)
      local Network=opt and Net or lib("ship_network_baseline")(S,T,W,Fac)
      local R=lib("ship_preview_run")(Network,Track,W,Y,Move,regions,extents)
      local s,depot,first,second=fixture()
      local p=assert(R.start(s,owner,depot,first,second))
      for _=1,500 do
        R.tick(s,1)
        if p.vehicle.path and #p.vehicle.path>=35 then break end
      end
      assert(p.vehicle.path and #p.vehicle.path>=35,"No live long water leg")
      follows,region_builds,shapes=0,0,0
      local results={}
      local clock=0
      for i=1,8800 do
        local t=os.clock()
        R.tick(s,1)
        clock=clock+os.clock()-t
        assert(p.phase~="blocked",p.failure)
        if i%20==0 or p.arrivals>=1 then results[#results+1]=core.serialize(p) end
        if p.arrivals>=1 then break end
      end
      assert(p.arrivals==1,"Native ferry failed to arrive")
      return clock*1000,results,follows,region_builds,shapes
    end
    local function same(a,b)
      if type(a)~="table" then return a==b end
      if type(b)~="table" then return false end
      for k,v in pairs(a) do if not same(v,b[k]) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    local out={}
    for i=1,4 do
      local a,b,q,p,n,m,x,y,c,d
      if i%2==0 then b,p,m,y,d=run(true);a,q,n,x,c=run(false) else a,q,n,x,c=run(false);b,p,m,y,d=run(true) end
      assert(x==y and n==m and #q==#p and c>d)
      for j=1,#q do assert(same(core.deserialize(q[j]),core.deserialize(p[j]))) end
      out[i]=("NATIVE BERTH ELIGIBILITY batch=%d baseline=%.3f candidate=%.3f followers=%d/%d samples=%d terrain_reads=%d/%d"):format(i,a,b,n,m,#q,c,d)
    end
    return out
  end,function(out)
    assert(out and #out==4)
    for _,line in ipairs(out) do core.log("action",line) end
    core.request_shutdown("Ship region tidal invalidation",false,0)
  end))
end)
