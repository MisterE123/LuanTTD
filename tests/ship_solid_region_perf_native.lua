for _,n in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..n,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local base=core.get_modpath("luanttd_core").."/"
    local function lib(n) return dofile(base..n..".lua") end
    local S,Track,T=lib("sim"),lib("openttd/rail_track"),lib("openttd/terrain")
    S.W,S.H=256,256
    local W=lib("openttd/ship_follow")(Track)
    local Net=lib("ship_network")(S,T,W,lib("openttd/ship_facilities")(Track,W))
    local Regions=lib("openttd/ship_regions")
    local s={tiles={},topology=0,corner_grid=T.new(S.W,S.H)}
    local id=S.id
    for i=1,S.W*S.H do s.tiles[i]={terrain="water",water_class="sea",h=0} end
    local function t(x,z) return s.tiles[id(x,z)] end
    -- Usable/cut boundaries, isolated patches, rocks and active coast.
    for x=33,50 do t(x,17).terrain="grass" end
    for z=33,49 do t(49,z).terrain="grass" end
    t(17,20).stock_water_rocks=true
    t(18,33).coastal_water=true
    t(129,80).stock_void=true
    s.corner_grid.levels[(90-1)*257+90]=1
    t(97,65).ship={kind="lock",dir=1,part="middle",water_class="canal"}
    local a,b=id(33,65),id(80,65)
    t(33,65).ship={kind="aqueduct",dir=2,other=b,skip=46,water_class="canal"}
    t(80,65).ship={kind="aqueduct",dir=0,other=a,skip=46,water_class="canal"}
    local calls,fast=0,0
    local f0=W.follow
    function W.follow(...) calls=calls+1;return f0(...) end
    local function build(opt,w,h)
      local B=Net.board(s)
      if opt then
        local found=B.solid_plain_sea
        function B.solid_plain_sea(...) if found(...) then fast=fast+1;return true end;return false end
      else B.solid_plain_sea=nil end
      return Regions(Track,W,B,{width=w,height=h,x0=1,z0=1})
    end
    local function equal(a,b,w,h)
      for z=1,h do for x=1,w do
        assert(a.region_patch(id(x,z))==b.region_patch(id(x,z)))
      end end
      local rx,rz=math.ceil(w/16),math.ceil(h/16)
      for z=0,rz-1 do for x=0,rx-1 do
        local p,q=a.info(x,z),b.info(x,z)
        assert(p.count==q.count and p.cross_aqueduct==q.cross_aqueduct)
        for i=0,3 do assert(p.edge[i]==q.edge[i],("edge %d, %d, %d"):format(x,z,i)) end
        for lab=1,p.count do
          local desc={x=x,z=z,label=lab}
          local l,r=a.neighbors(desc),b.neighbors(desc)
          assert(#l==#r)
          for i,v in ipairs(l) do assert(v.key==r[i].key) end
        end
      end end
    end
    local baseline,checked=build(false,256,256),build(true,256,256)
    equal(baseline,checked,256,256)
    local rock=id(145,145)
    assert(checked.region_patch(rock)==1)
    t(145,145).stock_water_rocks=true
    baseline.invalidate(rock);checked.invalidate(rock)
    assert(checked.region_patch(rock)==0)
    equal(baseline,checked,256,256)
    t(145,145).stock_water_rocks=nil
    equal(build(false,249,251),build(true,249,251),249,251)
    local out={}
    for i=1,4 do
      local function run(opt)
        local M=build(opt,256,256)
        collectgarbage("collect")
        calls,fast=0,0
        local time=os.clock()
        for z=0,15 do for x=0,15 do assert(M.info(x,z)) end end
        return (os.clock()-time)*1e3,calls,fast
      end
      local a,b,n,m,c,e
      if i%2==0 then b,m,e=run(true);a,n,c=run(false) else a,n,c=run(false);b,m,e=run(true) end
      assert(n>m and e>200 and c==0)
      out[i]=("NATIVE SOLID SEA REGIONS batch=%d baseline=%.3f candidate=%.3f followers=%d/%d flat=%d"):format(i,a,b,n,m,e)
    end
    -- A mixed 128x128 board in which every region contains a rocky
    -- shallows, slope, coast, or artificial waterway. In each build the
    -- stock follower may examine one physical tile from several headings
    -- and both sides of a region boundary. Count raw descriptor reads.
    for z=1,128,16 do for x=1,128,16 do
      t(x+6,z+6).stock_water_rocks=true
      if (x+z)%32==2 then t(x+7,z+6).terrain="grass" end
    end end
    local sampler=W.region_sampler
    assert(sampler)
    local function coastal(opt)
      W.region_sampler=opt and sampler or nil
      local board=Net.board(s)
      local reads=0
      local tile=board.tile
      board.tile=function(i) reads=reads+1;return tile(i) end
      local regions=Regions(Track,W,board,{width=128,height=128,x0=1,z0=1})
      collectgarbage("collect")
      local start=os.clock()
      for z=0,7 do for x=0,7 do regions.info(x,z) end end
      local elapsed=(os.clock()-start)*1000
      W.region_sampler=sampler
      return regions,elapsed,reads
    end
    for i=1,4 do
      local a,b,p,q,n,m
      if i%2==0 then b,q,m=coastal(true);a,p,n=coastal(false)
      else a,p,n=coastal(false);b,q,m=coastal(true) end
      assert(m*4<n,"cold shoreline descriptor reads were not reduced")
      equal(a,b,128,128)
      out[#out+1]=("NATIVE MIXED SHIP REGIONS batch=%d baseline=%.3f candidate=%.3f reads=%d/%d"):format(i,p,q,n,m)
    end
    local a=coastal(false)
    local b=coastal(true)
    local point=id(32,32)
    t(32,32).stock_water_rocks=true
    W.region_sampler=nil
    a.invalidate(point)
    a.region_patch(point)
    -- The bridge crosses region boundaries; trust only the rebuilt
    -- source and neighboring patches, never the preceding sampler.
    a.info(2,1);a.info(1,2)
    W.region_sampler=sampler
    b.invalidate(point)
    equal(a,b,128,128)
    assert(b.region_patch(point)==0)

    -- Rebuild the controller per query, as when planning its first
    -- voyage. The route crosses open water rather than hugging a coast.
    S.W,S.H=128,128
    local s2={tiles={},topology=0,sites={},stations={},fleet={},companies={},news={},
      corner_grid=T.new(S.W,S.H,function(x) return (x<9 or x>=120) and 1 or 0 end)}
    for z=1,S.H do for x=1,S.W do
      local grass=x<9 or x>=119
      s2.tiles[id(x,z)]={terrain=grass and "grass" or "water",
        water_class=not grass and "sea" or nil,h=(x<8 or x>=120) and 1 or 0}
    end end
    local owner="Fleet QA"
    local a=assert(Net.build(s2,owner,"dock",id(119,82)))
    local b=assert(Net.build(s2,owner,"dock",id(8,12)))
    local depot=assert(Net.build(s2,owner,"depot",id(12,11),0))
    local Y=lib("openttd/ship_yapf")(Track,W,lib("openttd/yapf_road_search"))
    local Move=lib("openttd/ship_motion")(Track,W)
    local Runner=lib("ship_preview_run")
    local expected
    local function same(a,b)
      if type(a)~="table" then return a==b end
      if type(b)~="table" then return false end
      for k,v in pairs(a) do if not same(v,b[k]) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    local function quotes(opt)
      local network=setmetatable({board=function(...)
        local board=Net.board(...)
        if not opt then board.solid_plain_sea=nil end
        return board
      end},{__index=Net})
      local time=0
      calls=0
      for _=1,20 do
        local R=Runner(network,Track,W,Y,Move,Regions,{width=128,height=128,x0=1,z0=1})
        local now=os.clock()
        local q,why=R.quote(s2,owner,depot.id,a.id,b.id)
        time=time+os.clock()-now
        assert(q and q.vehicle,why)
        if expected then assert(same(expected,q),"cold ferry quote changed") else expected=q end
      end
      return time*1000,calls
    end
    for i=1,4 do
      local a,b,n,m
      if i%2==0 then b,m=quotes(true);a,n=quotes(false) else a,n=quotes(false);b,m=quotes(true) end
      assert(n>m)
      out[#out+1]=("NATIVE FIRST FERRY ROUTE batch=%d baseline=%.3f candidate=%.3f followers=%d/%d"):format(i,a,b,n,m)
    end
    return out
  end,function(out)
    assert(out and #out==12)
    for _,l in ipairs(out) do core.log("action",l) end
    core.request_shutdown("Water regions match cold and mixed cases",false,0)
  end))
end)
