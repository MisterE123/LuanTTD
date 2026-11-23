-- Native test runs actual ordered and physically simulated trains.
-- The fixture removes two signal heads after both engines have left.
local Rail=assert(api.rail_dispatch_controller)
local StockTrack=dofile(mod.."/openttd/rail_track.lua")
local StockSignal=dofile(mod.."/openttd/rail_signals.lua")(StockTrack)
core.after(0,function()
  local proof=S.rail_collision_native
  if not proof then
    local g=assert(S.corner_grid)
    for i=1,#g.levels do g.levels[i]=0 end
    for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
    local f=dofile(mod.."/qa_rail_collision.lua")
    S.rail_collision_native=f(Sim,S,api.trackworks,assert(api.rail_owned),Rail,StockTrack,StockSignal)
    api.save()
    core.log("action","COLLISION_NATIVE_SAVED_APPROACH")
    core.request_shutdown("Saved opposite approaches before impact",false,0)
    return
  end
  local d=assert(Rail.current(S))
  local hit
  for _=1,20 do
    Sim.daily(S)
    assert(not d.failure,d.failure)
    for _,e in ipairs(Sim.rail_paid_motion_events(S)) do
      if e.kind=="rail_collision" then assert(not hit and e.victims==4);hit=e end
    end
    if hit then break end
  end
  assert(hit and d.runs[1].crashed and d.runs[2].crashed and d.life.bits[hit.tile])
  local a,b=d.runs[1].consist.parts[1].pose,d.runs[2].consist.parts[1].pose
  assert(math.abs(a.x-b.x)==7 and a.y==b.y)
  local news=S.stock_rail_accidents
  assert(news and #news==1 and news[1].tile==hit.tile and news[1].victims==4)
  local ratings=0
  for _,st in pairs(S.stock_ship_commercial.service.stations) do
    if st.host_mode=="rail" and st.owner==proof.owner then
      assert(st.passenger_rating_state.rating<=17)
      ratings=ratings+1
    end
  end
  assert(ratings==2)
  for i=1,10 do
    Sim.daily(S)
    assert(d.runs[1].consist.parts[1].pose==a and d.runs[2].consist.parts[1].pose==b)
    assert(d.life.bits[hit.tile])
  end
  for _=1,65 do Sim.daily(S) end
  assert(not next(d.life.bits) and #d.runs[1].consist.parts==0 and #d.runs[2].consist.parts==0)
  core.log("action","COLLISION_NATIVE_PASS 7 stock pixels, two stopped consists, debris held then released track")
  core.request_shutdown("Stock first contact and wreck disposal verified",false,0)
end)
