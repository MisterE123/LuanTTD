-- Run at game root: lua5.1 tools/profile_farm_worker.lua WIDTH DAYS [measure]
local width, days, measure = tonumber(arg[1]), tonumber(arg[2]), arg[3]=="measure"
local clock, original = os.clock, dofile
local field_calls,field_seconds,plant_calls,plant_seconds=0,0,0,0
local farms,routes,fields
function dofile(path)
  local f=original(path)
  if not measure then return f end
  if path:match("/openttd/farm_factory_fields%.lua$") then
    return function(...)
      local F=f(...); local random=F.random
      function F.random(...)
        local t=clock();local a,b=random(...);plant_seconds=plant_seconds+clock()-t
        plant_calls=plant_calls+1;return a,b
      end
      return F
    end
  elseif path:match("/farm_factory_world%.lua$") then
    return function(Sim,...)
      local W=f(Sim,...);local board=W.field_board
      function W.field_board(s)
        local B=board(s);local visit=B.visit
        function B.visit(x,z,...)
          if not s.stock_farm_fields[Sim.id(x+1,z+1)] then return visit(x,z,...) end
          local t=clock();visit(x,z,...);field_seconds=field_seconds+clock()-t
          field_calls=field_calls+1
        end
        return B
      end
      return W
    end
  end
  return f
end
local mod="mods/luanttd_core"
local Sim=dofile(mod.."/sim.lua")
local Setup=dofile(mod.."/world_setup.lua")
local core={settings={get=function()return nil end}}
local s=dofile(mod.."/campaign_generation.lua")(core,mod,Sim,Setup).run({width=width,depth=width,seed=1751})
local function has(t,k) for _,v in pairs(t or {}) do if v.kind==k then return true end end end
s.road_farm=not not (has(s.stock_farm_industries,"farm") or has(s.stock_farm_industries,"factory"))
s.road_oil=not not (has(s.stock_oil_industries,"oil_well") or has(s.stock_oil_industries,"oil_refinery"))
s.rail_oil_service=s.road_oil
if has(s.stock_coal_industries,"coal_mine") and has(s.stock_coal_industries,"power_station") then
  s.road_coal,s.rail_coal_service,s.ship_coal_service=true,true,true
end
if has(s.stock_timber_industries,"forest") and has(s.stock_timber_industries,"sawmill") then
  s.road_timber,s.rail_goods_service=true,true
end
assert(Sim.road_farm_active(s),"Stock farm not active")
local function count(t,kind)
  local n=0;for _,v in pairs(t or {}) do if not kind or v.kind==kind then n=n+1 end end;return n
end
farms,fields=count(s.stock_farm_industries,"farm"),count(s.stock_farm_fields)
local towns=count(s.sites,"town")
for i=1,3 do Sim.daily(s);s.changed={} end
field_calls,field_seconds,plant_calls,plant_seconds=0,0,0,0
collectgarbage("collect")
local start=clock()
for i=1,days do Sim.daily(s);s.changed={} end
local cpu=clock()-start
print(("%dx%d farms=%d towns=%d fields=%d→%d fleet=%d days=%d measured=%s cpu=%.6fs day=%.3fms field_maintenance=%d/%.6fs planting=%d/%.6fs share=%.3f%%")
  :format(width,width,farms,towns,fields,count(s.stock_farm_fields),count(s.fleet),days,tostring(measure),cpu,cpu*1000/days,
    field_calls,field_seconds,plant_calls,plant_seconds,100*(field_seconds+plant_seconds)/cpu))
