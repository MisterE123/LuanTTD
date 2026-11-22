local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local T=dofile(root.."openttd/rail_track.lua")
local F=dofile(root.."openttd/rail_follow.lua")(T)
local Y=dofile(root.."openttd/rail_yapf_cost.lua")(T,F)
local Search=dofile(root.."openttd/rail_yapf_search.lua")(T,F,Y)
local M=dofile(root.."openttd/rail_motion.lua")(T)
local Q=dofile(root.."openttd/rail_station_speed.lua")(T,F)
local Slope=dofile(root.."openttd/slope.lua")
local Pose=dofile(root.."rail_pose.lua")(T)
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,Slope,Y,Search,function()return 0 end)
local function new_run()
  return dofile(root.."rail_platform_run.lua")(Sim,T,M,Q,Lab)
end
local R=new_run()
local owner="pilot"
local function place(s,x,y,track)
  local id=assert(Sim.id(x,y))
  if not s.tiles[id] then s.tiles[id]={terrain="grass",h=0} end
  local okay,reason=Lab.change(s,owner,id,track,false,0)
  assert(okay,reason)
  return id
end
local function line(dir)
  local s={tiles={},topology=0}
  local vectors={[0]={-1,0},{0,1},{1,0},{0,-1}}
  local d=vectors[dir]
  local ids={}
  for i=0,4 do ids[i]=place(s,18+i*d[1],18+i*d[2],dir%2) end
  assert(Lab.depot(s,owner,ids[0],dir))
  assert(Lab.station(s,owner,ids[2],ids[4]))
  return s,ids
end
local function snapshot(value)
  if type(value)~="table" then
    assert(type(value)~="function" and type(value)~="userdata","snapshot contains non-save data")
    return value
  end
  local copy={}
  for k,v in pairs(value) do copy[k]=snapshot(v) end
  return copy
end
local function finish(runner,s)
  local event
  for _=1,12000 do
    event=runner.tick(s)
    if event then break end
  end
  assert(event and event.kind=="arrived",event and event.reason or "train failed to reach platform")
  return event
end

local initial_x,initial_y={[0]=10,8,4,8},{[0]=8,4,8,10}
for dir=0,3 do
  local s,ids=line(dir)
  assert(not R.start(s,"other",ids[0],1))
  assert(not R.start(s,owner,ids[1],1),"ordinary rail accepted as a depot")
  local ok,why,v=R.start(s,owner,ids[0],1)
  assert(ok,why)
  assert(v.max_track_speed==80 and v.acceleration==36 and v.total_length==8 and v.engine==1)
  assert(v.pose.x%16==initial_x[dir] and v.pose.y%16==initial_y[dir] and v.phase=="depot")
  assert(not R.sample(v) and not R.start(s,owner,ids[0],1))
  assert(not R.clear(s,"other"))
  assert(not R.tick(s,18))
  assert(v.phase=="depot" and v.wait_counter==36 and v.stock_steps==0)
  assert(not R.tick(s))
  assert(v.phase=="running" and v.wait_counter==0 and v.stock_steps==0)
  local e=finish(R,s)
  local id,td,f=R.sample(v)
  assert(id==ids[4] and td==T.diagonal_trackdir(dir) and f==.75 and e.steps==76-((dir==0 or dir==3) and 5 or 4))
  assert(e.station==1 and e.tile==ids[4] and e.pose.direction==dir*2+1 and v.speed==0)
  local along=(dir==0 or dir==3) and 3 or 12
  assert(e.pose.x%16==(dir%2==0 and along or 8) and e.pose.y%16==(dir%2==0 and 8 or along))
  assert(v.last_station==1 and v.phase=="arrived")
  assert(not R.tick(s,100) and R.current(s).arrival.tick==e.tick)
  assert(R.clear(s,owner) and not R.current(s))
end

local s={tiles={},topology=0}
local depot=place(s,12,12,T.X)
place(s,13,12,T.X)
local corner=place(s,14,12,T.RIGHT)
place(s,14,13,T.Y)
local first=place(s,14,14,T.Y)
local last=place(s,14,15,T.Y)
assert(Lab.depot(s,owner,depot,T.SW))
assert(Lab.station(s,owner,first,last))
assert(R.start(s,owner,depot,1))
local run=R.current(s)
assert(#run.route==6 and run.route[3].tile==corner and run.route[3].td==5)
local pre,seen
for _=1,2000 do
  assert(not R.tick(s))
  local id,td,f=R.sample(run)
  if id==corner and f>0 and f<1 then
    assert(td==5 and run.pose.direction==4 and math.abs(f*8-run.tile_step)<1e-9)
    local x,z,dx,dz=Pose.sample(td,f)
    assert(x<0 and z>0 and dx>0 and dz>0,"rail pose does not bend into the through piece")
    pre=run.stock_steps;seen=true
    break
  end
end
assert(seen)
local reloaded=snapshot(s)
local restarted=new_run()
local a,b=finish(R,s),finish(restarted,reloaded)
assert(a.steps==b.steps and a.tick==b.tick and a.pose.x==b.pose.x and a.pose.y==b.pose.y and a.steps>pre)
assert(a.tile==last and b.tile==last and a.pose.x%16==8 and a.pose.y%16==12)
local oldtick=b.tick
reloaded=snapshot(reloaded)
assert(not restarted.tick(reloaded,100) and restarted.current(reloaded).arrival.tick==oldtick)

local blocked,ids=line(T.SW)
assert(R.start(blocked,owner,ids[0],1))
assert(not R.tick(blocked,25))
-- An unrelated layout edit is accepted without resetting raw speed/pose.
place(blocked,25,29,T.X)
local ticks=R.current(blocked).simulation_ticks
assert(not R.tick(blocked) and R.current(blocked).simulation_ticks==ticks+1)
assert(Lab.change(blocked,owner,ids[1],T.X,true,0))
local event=R.tick(blocked)
assert(event and event.kind=="blocked" and R.current(blocked).phase=="blocked")
assert(not R.sample(R.current(blocked)) and not R.tick(blocked,3600),"pilot passed through deleted track")
print("PASS: stock depot wait, 4 departures, exact real-platform stops, curved rail, save/reload, and removed-track guard")
