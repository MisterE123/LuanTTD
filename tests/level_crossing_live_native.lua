-- Appended only to an isolated game fixture by level_crossing_live_native.sh.
local owner="Crossing QA"
local cross=Sim.id(14,12)
local cross_pos={x=28,y=1,z=24}
local function gate(barred)
  api.render.crossing_gates()
  local wanted="bayline:level_crossing_1_"..(barred and "closed" or "open")
  local actual=core.get_node(cross_pos).name
  assert(actual==wanted,actual.." != "..wanted)
  local def=assert(core.registered_nodes[actual])
  assert(def.drawtype=="mesh" and def.mesh=="bl_level_crossing_1_"..(barred and "closed" or "open")..".obj")
end
local function phase(expect)
  api.crossings.refresh(S,api.trackworks.board(S))
  local r=assert(api.crossings.world.record(S,cross))
  assert(r.phase==expect,r.phase.." != "..expect)
end
local function test()
  local R=assert(api.rail_dispatch_controller)
  assert(S.road_stock_clock and S.road_economy)
  local qa=S.level_crossing_native_qa
  assert(not not api.crossing_tools==(qa==nil))
  if not qa then
    Sim.company(S,owner)
    S.road_stock_loading=true
    local a,b=Sim.id(11,12),Sim.id(17,12)
    local ok,why=Sim.build(S,owner,"road",Sim.line(a,b));assert(ok,why)
    assert(Sim.build(S,owner,"road_station",{a,b}))
    local q=assert(api.crossing_quote(owner,cross,{kind="rail",track=1}))
    local okay,cost=api.crossing_commit(owner,q);assert(okay,cost);assert(cost==100)
    assert(not Sim.build(S,owner,"clear",{cross}))
    assert(not Sim.build(S,owner,"road_station",{cross}))
    assert(not Sim.build(S,owner,"road",{cross,Sim.id(14,11)}))
    assert(not Sim.landscape(S,owner,"raise",14,12))
    phase("open");gate(false)
    -- Lonely N/S railway perpendicular to the existing E/W road.
    local g=S.corner_grid
    for z=4,21 do
      for x=14,15 do g.levels[(z-1)*(g.width+1)+x]=0 end
    end
    for z=4,20 do
      if z~=12 and (z<6 or z>9) then
        S.tiles[Sim.id(14,z)]={build="stock_rail",owner=owner,rail_tracks=2,terrain="grass",h=0,variant=1}
      end
    end
    assert(api.trackworks.depot(S,owner,Sim.id(14,4),Track.SE))
    assert(api.trackworks.station(S,owner,Sim.id(14,18),Sim.id(14,20)))
    local station=S.tiles[Sim.id(14,18)].rail_station_id
    -- One and the same dispatch order also traverses a real mounted timber span.
    for z=6,9 do S.tiles[Sim.id(14,z)]={terrain="grass",h=0,variant=1} end
    local bridge=assert(api.rail_spans.quote_bridge(S,owner,Sim.id(14,6),Sim.id(14,9)))
    local built,description=api.rail_spans.commit(S,owner,bridge)
    assert(built,description)
    local sa,sb=S.tiles[a].station,S.tiles[b].station
    local bus=assert(Sim.purchase(S,owner,"bus","passenger",sa))
    assert(Sim.add_order(S,owner,bus,sb))
    assert(Sim.toggle(S,owner,bus))
    local v=S.fleet[bus]
    local seen
    for _=1,24 do
      Sim.daily(S)
      local f=Sim.road_motion_frame(S,v)
      if f and f[4]==cross and v.road_speed_state then seen=true;break end
    end
    assert(seen,"No real committed road frame on crossing after twenty-four days")
    v.running=false -- isolate safety if a road actor cannot leave immediately
    local ok,note=R.start_span(S,owner,Sim.id(14,4),station)
    assert(ok,note)
    local held,span_exited
    for _=1,1800 do
      local events=R.tick(S)
      assert(not R.current(S).failure,R.current(S).failure)
      for _,e in ipairs(events) do
        if core.settings:get_bool("bayline_crossing_qa_debug",false) then
          core.log("action",("crossing QA event %s %s %s"):format(e.kind,tostring(e.tile),tostring(e.reason)))
        end
        if e.kind=="waiting" and e.reason=="ROAD_DRAINING" then held=true end
        if e.kind=="span_exited" then span_exited=true end
      end
      if held then break end
    end
    local train=R.current(S).runs[1]
    assert(span_exited,"Train did not traverse timber bridge before the road crossing: "..train.phase..
      " head="..tostring(train.consist.parts[1].tile).." ticks="..R.current(S).ticks)
    assert(held,"Real rail journal never hit the road-draining gate")
    phase("road_draining");gate(true)
    S.level_crossing_native_qa={bus=bus,holding_tick=R.current(S).ticks,first=sa,last=sb}
    api.save()
    core.log("action","CROSSING_SAVE_HOLD")
    core.request_shutdown("Saved real crossing occupancy",false,0)
    return
  end
  assert(R.current(S).ticks==qa.holding_tick)
  assert(Sim.road_motion_frame(S,S.fleet[qa.bus])[4]==cross)
  phase("road_draining");gate(true)
  -- Road resumes and can finish the crossed leg while barriers prevent
  -- any new outside road admissions. Only then may the train advance.
  local second=assert(Sim.purchase(S,owner,"bus","passenger",qa.last))
  assert(Sim.add_order(S,owner,second,qa.first) and Sim.toggle(S,owner,second))
  local saw_road_denied
  for _=1,16 do
    Sim.daily(S)
    local v=S.fleet[second]
    if v.road_speed_state and v.road_speed_state.waiting=="crossing" then
      assert(Sim.road_motion_frame(S,v)[4]~=cross)
      saw_road_denied=true;break
    end
  end
  assert(saw_road_denied,"Opposite-direction bus did not stop outside the barred crossing")
  S.fleet[qa.bus].running=true
  S.fleet[qa.bus].stop_requested=true
  local source=S.fleet[qa.bus].dest
  for _=1,10 do
    Sim.daily(S)
    local v=S.fleet[qa.bus]
    if not v.route and v.station==source and not v.running then break end
  end
  assert(S.fleet[qa.bus].station==source and not S.fleet[qa.bus].running)
  local tail_only,arrived
  local before=R.current(S).runs[1].stock_steps
  for _=1,1800 do
    local events=R.tick(S)
    local d=R.current(S)
    assert(not d.failure,d.failure)
    local train=d.runs[1]
    if train.consist.parts[1].tile~=cross and train.consist.parts[2].tile==cross then
      phase("rail_occupied");gate(true);tail_only=true
    end
    for _,e in ipairs(events) do if e.kind=="arrived" then arrived=true end end
    if arrived then break end
  end
  assert(tail_only and arrived and R.current(S).runs[1].stock_steps>before)
  phase("open");gate(false)
  S.fleet[second].stop_requested=true
  for _=1,20 do
    Sim.daily(S)
    local v=S.fleet[second]
    if not v.running and v.station==qa.first then break end
  end
  assert(not S.fleet[second].running and S.fleet[second].station==qa.first,
    "The denied bus did not continue after the last train wagon left")
  core.log("action","CROSSING_LIVE_NATIVE_PASS")
  core.request_shutdown("Native rail crossing test complete",false,0)
end
core.after(0,function()
  core.emerge_area({x=20,y=0,z=6},{x=35,y=3,z=41},function(_,_,remaining)
    if remaining==0 then core.after(0,test) end
  end)
end)
