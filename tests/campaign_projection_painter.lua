local shows,maps,callbacks=0,{},{}
local M=dofile("mods/luanttd_core/campaign_projection_painter.lua")({
  use_worker_projection=function() shows=shows+1 end,
  place_projected=function(x,z,w,h,done)
    maps[#maps+1]={x=x,z=z,w=w,h=h};callbacks[#maps]=done
  end,
})
local function tile(x,scene)
  return {value={x=x,z=1,width=32,height=32,scene=scene,tiles={{}}}}
end
local function present(...) local rows={...};M.present({windows=function() return rows end}) end
present(tile(1,1),tile(33,2))
assert(M.step() and not M.step() and maps[1].x==1)
present(tile(1,1),tile(33,2)) -- fresh actor packets but unchanged surface
assert(shows==1)
callbacks[1](true)
assert(M.step() and maps[2].x==33)
present(tile(1,3)) -- old region leaves and original region changes
callbacks[2](true)
assert(M.step() and maps[3].x==1)
callbacks[3](true)
assert(not M.step())
present(tile(1,3),tile(33,2)) -- re-entry is rehydrated even with same scene
assert(M.step() and maps[4].x==33 and shows==3)
print("PASS one bounded engine paint at a time, no redraw on actor refresh, re-entry and stale repairs safe")
-- The first zone is continuously changing while it is rendered, like an
-- active town. It may get another pass, but not ahead of untouched sectors.
present(tile(1,4),tile(33,2),tile(65,3))
callbacks[4](true)
assert(M.step() and maps[5].x==1)
present(tile(1,5),tile(33,2),tile(65,4))
callbacks[5](true)
assert(M.step() and maps[6].x==65)
present(tile(1,6),tile(33,2),tile(65,4))
callbacks[6](true)
assert(M.step() and maps[7].x==1)
callbacks[7](false,"retry")
present(tile(1,7),tile(33,3),tile(65,4))
assert(M.step() and maps[8].x==1)
present(tile(1,8),tile(33,3),tile(65,4))
callbacks[8](false,"retry")
assert(M.step() and maps[9].x==33)
print("PASS continuous neighbor changes and failed paints cannot starve older waiting sectors")

-- A cancellation caused by two emerge threads on one mapchunk is not
-- success until the affected block is loaded. Actual errors still fail.
local function emerge_case(actions,loaded_at,expected,reads)
  local queue,t,checked,actual,progress={},0,0,nil,{}
  local core={EMERGE_CANCELLED=0,EMERGE_ERRORED=1}
  function core.after(dt,fn,...)
    queue[#queue+1]={dt=dt,fn=fn,args={...}}
  end
  function core.emerge_area(_,_,on_block)
    for i,action in ipairs(actions) do
      on_block({x=-1,y=0,z=1},action,#actions-i)
    end
  end
  function core.get_node_or_nil(pos)
    assert(pos.x==-7 and pos.y==2 and pos.z==16)
    checked=checked+1
    if checked<loaded_at then return checked%2==1 and {name="ignore"} or nil end
    return {name="air"} -- legitimate loaded air also counts
  end
  local emerge=dofile("mods/luanttd_core/campaign_emerge_region.lua")(core)
  emerge({x=-7,y=2,z=2},{x=0,y=3,z=20},function(ok)
    assert(actual==nil)
    actual=ok
  end,function(left) progress[#progress+1]=left end)
  assert(actual==nil and #progress==#actions and progress[#actions]==0)
  for i=1,4 do
    local q=table.remove(queue,1)
    if not q then break end
    t=t+q.dt;q.fn(unpack(q.args))
  end
  assert(actual==expected and checked==reads and #queue==0 and t<.23)
end
emerge_case({3,2},0,true,0)
emerge_case({0,3},1,true,1)
emerge_case({3,0},3,true,3)
emerge_case({0,0},4,true,5) -- one canceled block may appear ahead of another
emerge_case({3,0},99,false,3)
emerge_case({0,1,3},1,false,0)
print("PASS canceled mapblocks are verified after the callback; missing blocks and engine errors retain retry")
