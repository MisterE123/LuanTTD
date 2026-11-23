-- Actual City Airport FTA, fixed-wing motion and native pose trace for art.
-- Run from the game root: lua5.1 tests/darwin_city_art_trace.lua > ground.txt
local core="mods/luanttd_core/openttd/"
local A=dofile(core.."airport_city.lua")
local M=dofile(core.."airport_motion.lua")(A)
local B=A.block
for slot=1,3 do
  local a={id=1,owner="QA",x=320,z=320,ground=0,rotation=0,width=6,height=6,flags=0}
  local b={id=2,owner="QA",x=880,z=352,ground=0,rotation=0,width=6,height=6,
    flags=slot==1 and 0 or slot==2 and B.TERM1 or B.TERM1+B.TERM2}
  local host={airports={a,b}}
  local v=A.new(a,{owner=a.owner,order={kind="station",id=b.id},acceleration=40,max_speed=947})
  local field=a
  local function write(f,leg)
    local x,z=v.x-f.x,v.z-f.z
    if x>=-22 and x<=118 and z>=-22 and z<=118 then
      print(leg,x,z,v.y-f.ground-1,v.direction,v.pos,f.id,v.hidden and 1 or 0)
    end
  end
  local function drive(goal,leg)
    write(field,leg)
    for tick=1,30000 do
      local done,issue=M.move(field,v)
      assert(done~=nil,issue)
      if done then
        local action,nextfield=A.arrive(field,v,host)
        assert(action,nextfield)
        if nextfield then field=nextfield end
        if action==goal then
          write(field,leg)
          return
        end
      end
      write(field,leg)
    end
    error("Did not reach "..goal.." on route "..leg)
  end
  drive("terminal",slot)
  assert(field==b and v.pos==slot+1 and v.state==A.terminal_states[slot])
  v.loading=nil
  v.order={kind="depot",id=b.id}
  drive("hangar",slot+3)
  assert(v.x==b.x+85 and v.z==b.z+3 and v.hidden)
end
