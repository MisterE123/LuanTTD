-- Appended only inside native QA. Uses production constructors,
-- authority, rendering, station clock and SQLite mod storage.
local Rail=assert(api.rail_dispatch_controller)
local StockTrack=dofile(mod.."/openttd/rail_track.lua")
local StockSignal=dofile(mod.."/openttd/rail_signals.lua")(StockTrack)
local Own=assert(api.rail_owned)
local fixture=S.rail_owned_multi_native
local function tick_multi(count)
  for _=1,count do
    Sim.daily(S)
    local d=assert(Rail.current(S))
    assert(not d.failure,d.failure)
    for _,e in ipairs(Sim.rail_paid_motion_events(S)) do
      if e.kind=="front_entered" and e.tile==fixture.diamond then
        fixture.passed[e.train]=(fixture.passed[e.train] or 0)+1
      end
      if e.kind=="waiting" then
        for _,stop in ipairs(fixture.stops) do if e.tile==stop then fixture.waited=true end end
      end
    end
    if fixture.waited and not fixture.saved then return end
    local a,b=Sim.rail_paid_status(S,fixture.a),Sim.rail_paid_status(S,fixture.b)
    if (fixture.passed[1] or 0)>=2 and (fixture.passed[2] or 0)>=2 and a.fare>0 and b.fare>0 then return end
  end
end
core.after(0,function()
  if not fixture then
    local g=assert(S.corner_grid)
    for i=1,#g.levels do g.levels[i]=0 end
    for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
    fixture=dofile(mod.."/qa_rail_multi.lua")(Sim,S,api.trackworks,Own,Rail,StockTrack,StockSignal)
    fixture.passed={}
    local tool=assert(api.rail_build)
    assert(not tool.busy(), "Ordinary owned trains must not close the construction menu")
    local first,last=Sim.id(31,29),Sim.id(36,29)
    local post=Sim.id(33,29)
    assert(tool.build(fixture.owner,assert(tool.quote_track(fixture.owner,first,last,0,false))))
    assert(tool.build(fixture.owner,assert(tool.quote_signal(fixture.owner,post,2,false,false))))
    assert(tool.build(fixture.owner,assert(tool.quote_remove_signal(fixture.owner,post))))
    assert(S.tiles[post].rail_tracks==1 and not Rail.current(S).signals.records[post])
    tick_multi(130)
    assert(fixture.waited)
    fixture.saved=true
    S.rail_owned_multi_native=fixture
    api.save()
    core.log("action","MIXED_RAIL_NATIVE_SAVED_WAIT")
    core.request_shutdown("Saved native mixed junction during wait",false,0)
    return
  end
  assert(fixture.saved and fixture.waited and Rail.current_paid(S,fixture.a) and Rail.current_paid(S,fixture.b))
  tick_multi(130)
  api.rail_dispatch_view.step(.1,true,1)
  local a,b=Sim.rail_paid_status(S,fixture.a),Sim.rail_paid_status(S,fixture.b)
  assert(a and b and a.fare>0 and b.fare>0 and fixture.passed[1]>=2 and fixture.passed[2]>=2)
  assert(S.companies[fixture.owner].revenue==a.fare+b.fare)
  core.log("action",("MIXED_RAIL_NATIVE_PASS paid both independently after SQLite reload: $%d/$%d"):format(a.fare,b.fare))
  core.request_shutdown("Mixed native railway proved",false,0)
end)
