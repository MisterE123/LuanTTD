-- Run the production road planners in a native worker on the same save.
local mod=core.get_modpath("luanttd_core")
local function lib(name) return dofile(mod.."/"..name..".lua") end
if not core.register_node then
  function core.road_route_profile(path)
    local Codec=lib("packed_campaign")
    local Checkpoint=lib("campaign_checkpoint")
    local disk=Checkpoint(setmetatable({get_worldpath=function()return path end},{__index=core}),Codec)
    local s=assert(disk.read())
    local old,new=lib("baseline_sim"),lib("sim")
    for _,sim in ipairs({old,new}) do sim.W,sim.H=s.corner_grid.width,s.corner_grid.depth end
    local states={Codec.decode(Codec.encode(s)),s}
    local function run(sim,st)
      collectgarbage("collect")
      local time=core.get_us_time()
      local rows={}
      for id=1,128 do
        local v=assert(st.fleet[id],"The fixture needs 128 paid buses")
        local a,b=st.stations[v.orders[1].station],st.stations[v.orders[2].station]
        local path,td,cost,frames=sim.path(st,a,b,"road",v.owner,nil,v)
        assert(path and frames and #path>60)
        rows[id]={path=path,td=td,cost=cost,frames=frames}
      end
      return (core.get_us_time()-time)/1000,rows
    end
    local function equal(a,b,seen)
      if a==b then return true end
      if type(a)~="table" or type(b)~="table" then return false end
      if seen[a] then return seen[a]==b end
      seen[a]=b
      for k,v in pairs(a) do if not equal(v,b[k],seen) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    run(old,states[1]);run(new,states[2])
    local messages={}
    for i=1,12 do
      local a,b,x,y
      if i%2==1 then a,x=run(old,states[1]);b,y=run(new,states[2])
      else b,y=run(new,states[2]);a,x=run(old,states[1]) end
      for j=1,128 do assert(equal(x[j],y[j],{}),"Road path, cost or motion differences at vehicle "..j) end
      messages[i]=("ROAD ROUTE NATIVE batch=%d baseline_ms=%.2f candidate_ms=%.2f exact=128"):format(i,a,b)
    end
    return messages
  end
  return
end
for _,node in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..node,"air") end
core.register_async_dofile(mod.."/init.lua")
core.after(0,function()
  assert(core.handle_async(function(path) return core.road_route_profile(path) end,function(messages)
    for _,line in ipairs(messages) do core.log("action",line) end
    core.request_shutdown("Road route performance comparison complete",false,0)
  end,core.get_worldpath()))
end)
