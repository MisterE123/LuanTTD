for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local mod=core.get_modpath("luanttd_core").."/"
    local Sim=dofile(mod.."sim.lua")
    local T=dofile(mod.."openttd/terrain.lua")
    local W=dofile(mod.."water_flood_world.lua")(Sim,T,dofile(mod.."openttd/water_flood.lua"))
    local M=dofile(mod.."river_presentation.lua")(Sim)
    Sim.W,Sim.H=512,512
    local function state()
      local s={tiles={},corner_grid=T.new(512,512),topology=0}
      local land={terrain="grass",h=0}
      for i=1,512*512 do s.tiles[i]=land end
      local function row(x,z,to,klass)
        for i=x,to do s.tiles[Sim.id(i,z)]={terrain="water",water_class=klass,h=0} end
      end
      row(100,9,165,"river")
      row(166,9,166,"sea")
      for z=8,84 do
        row(400,z,400,"sea")
        local function ground(x)
          s.tiles[Sim.id(x,z)]={terrain="grass",h=0}
        end
        ground(401);ground(399)
      end
      return s
    end
    local function run(tuned)
      local s=state()
      local c=tuned and M.cached()
      if tuned then c.at(s,Sim.id(100,9)) end
      local t=0
      local result={}
      for z=10,82 do
        local previous=s.topology
        local n,plain,first=W.visit(s,400,z)
        assert(n>0 and plain)
        if tuned then c.after_plain_flood(s,previous,first) end
        local start=os.clock()
        local p=not tuned and M.routes(s)
        for x=100,165 do
          local id=Sim.id(x,9)
          result[#result+1]=assert(tuned and c.at(s,id) or p and p[id])
        end
        t=t+os.clock()-start
      end
      return t*1000,table.concat(result)
    end
    local rows={}
    for j=1,4 do
      local a,b,x,y
      if j%2==1 then a,x=run(false);b,y=run(true) else b,y=run(true);a,x=run(false) end
      assert(x==y and #x>0)
      rows[j]=("NATIVE RIVER 73 REAL TIDES baseline_cpu=%.3f candidate_cpu=%.3f"):format(a,b)
    end
    return rows
  end,function(out)
    assert(#out==4)
    for _,line in ipairs(out) do core.log("action",line) end
    core.request_shutdown("Exact river directions",false,0)
  end))
end)
