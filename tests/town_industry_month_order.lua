-- A fresh stock landscape with functioning coal and other industries,
-- and the real 74-tick authority loop. Keep industry's actual histories
-- compared by identity to locate the exact rollover tick.
local root="mods/luanttd_core/"
local function m(name) return dofile(root..name..".lua") end
local Sim=m("sim")
local generation=m("campaign_generation")({settings={get=function() return nil end},
  get_dir_list=function(path)
    local files={}
    local proc=assert(io.popen("ls -1 "..path))
    for name in proc:lines() do files[#files+1]=name end
    proc:close()
    return files
  end},root:sub(1,-2),Sim,m("world_setup"))
local s=generation.run({width=64,depth=64,seed=1751})
-- Native host enables its verified road/industry assets at authority
-- mount; this structural replay has no engine filesystem capability.
for _,chain in ipairs({"coal","timber","farm","oil","heavy","bank"}) do
  if next(s["stock_"..chain.."_industries"] or {}) then s["road_"..chain]=true end
end
assert(Sim.road_coal_active(s) and (Sim.road_farm_active(s) or Sim.road_timber_active(s)))
for _=1,30 do Sim.daily(s) end
local y,month,day=Sim.date(s)
assert(y==1950 and month==1 and day==31)
local histories={}
local function add(row)
  if row and row.last and row.current then histories[#histories+1]={row,row.last,row.current} end
end
for _,i in pairs(s.stock_coal_industries) do add(i.produced) end
local coal_count=#histories
assert(coal_count>=1)
for _,chain in ipairs({"timber","farm","oil","heavy","bank"}) do
  for _,i in pairs(s["stock_"..chain.."_industries"] or {}) do
    if i.produced and i.produced.last then
      add(i.produced)
    else
      for _,p in ipairs(i.produced or {}) do if p.cargo then add(p) end end
    end
  end
end
assert(#histories>coal_count)
local old_month=s.stock_town_growth.last_month
local rotate=Sim.stock_station_acceptance_history.rotate_host
Sim.stock_station_acceptance_history.rotate_host=function(world,kinds)
  assert(world.stock_town_growth.last_month==old_month,"Town ran before Station's monthly timer")
  for _,r in ipairs(histories) do
    assert(r[1].last==r[3],"Station ran before Industry's monthly timer")
  end
  return rotate(world,kinds)
end
local before=s.passenger_house_clock.counter
local seen=0
Sim.daily(s,nil,function(tick)
  seen=seen+1
  assert(tick==before+seen)
  for _,r in ipairs(histories) do
    if seen<74 then
      assert(r[1].last==r[2] and r[1].current==r[3],"Industry rolled before economy date changed")
    else
      assert(r[1].last==r[3] and r[1].current~=r[3],"Industry did not roll on the stock economy tick")
    end
  end
end)
assert(seen==74)
print(("PASS %d actual generated industry cargo ledgers roll at the February boundary"):format(#histories))
