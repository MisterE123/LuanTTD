-- Native process-crash fixture. Only appended to a disposable test game.
local function with_far_mapblocks(fn)
  local low,high={x=204,y=-1,z=140},{x=222,y=8,z=140}
  core.emerge_area(low,high,function(_,_,remaining)
    if remaining~=0 then return end
    core.after(0,function()
      for x=192,208,16 do for y=-16,0,16 do
        assert(core.forceload_block({x=x,y=y,z=128},true))
      end end
      core.after(2,fn)
    end)
  end)
end
core.after(0,function()
  local phase=core.settings:get("bayline_native_atomic_phase")
  local id=Sim.id(110,70)
  local owner="CheckpointQA"
  local function rendered_stop()
    local y=S.tiles[id].h+1
    local node=core.get_node({x=220,y=y,z=140}).name
    assert(node~="ignore","The far mapblock must have activated")
    return node:find("stop_shelter",1,true)~=nil
  end
  assert(Sim.W==128 and Sim.H==128 and S.passenger_house_clock.log_x==7)
  if phase=="baseline" then
    assert(Sim.build(S,owner,"road",Sim.line(Sim.id(102,70),Sim.id(111,70))))
    assert(Sim.build(S,owner,"road_station",{Sim.id(103,70)}))
    assert(S.next_station==2 and not S.tiles[id].station)
    with_far_mapblocks(function()
      assert(not rendered_stop())
      api.save()
      core.request_shutdown("Committed baseline",false,0)
    end)
  elseif phase=="crash" then
    assert(S.next_station==2 and not S.tiles[id].station)
    assert(not checkpoint,"An existing SQLite-only 128-square world must migrate cleanly")
    with_far_mapblocks(function()
      assert(not rendered_stop())
      assert(Sim.build(S,owner,"road_station",{id}))
      assert(S.next_station==3 and S.tiles[id].station==2)
      api.save()
      core.log("action","STOCK_WIDE_CRASH_READY checkpoint includes second stop")
      -- The shell kills this process before any SQLite or mapblock commit.
      -- Intentionally omit renderer.update: persisted old mapblocks must
      -- recover the visual stop from authoritative campaign state.
    end)
  elseif phase=="restore" then
    assert(S.next_station==3 and S.tiles[id].station==2 and S.stations[2].tile==id)
    local mirror=assert(core.deserialize(storage:get_string("campaign"),true))
    assert(mirror.next_station==2 and not mirror.tiles[id].station,
      "The rollback test needs an intentionally older committed SQL mirror")
    with_far_mapblocks(function()
      assert(rendered_stop(),"A recovered stop must reproject onto the saved mapblock")
      local route=Sim.path(S,S.stations[1],S.stations[2],"road",owner)
      assert(route and route[#route]==id)
      assert(S.companies[owner].cash==97774)
      core.log("action","STOCK_WIDE_ATOMIC_PASS restored visible second stop, route and $97,774; SQL mirror had only one stop")
      core.request_shutdown("Verified checkpoint recovery",false,0)
    end)
  elseif phase=="remove_crash" then
    with_far_mapblocks(function()
      assert(S.stations[2] and rendered_stop())
      local _,price=Sim.plan(S,owner,"clear",{id})
      assert(type(price)=="number" and price>0)
      assert(Sim.build(S,owner,"clear",{id}))
      assert(not S.stations[2] and not S.tiles[id].station and S.companies[owner].cash==97774-price)
      S.wide_atomic_expected_clear=price -- test-only expected financial record
      api.save()
      core.log("action","STOCK_WIDE_CRASH_READY checkpoint includes stop removal")
    end)
  else
    assert(phase=="remove_restore" or phase=="reopen")
    if phase=="remove_restore" then
      local mirror=assert(core.deserialize(storage:get_string("campaign"),true))
      assert(mirror.stations[2] and mirror.tiles[id].station==2)
    end
    with_far_mapblocks(function()
      assert(not rendered_stop(),"A recovered clearing must remove the old station mesh")
      assert(not S.stations[2] and not S.tiles[id].station and S.stations[1])
      assert(S.next_station==3 and S.companies[owner].cash==97774-S.wide_atomic_expected_clear)
      core.log("action","STOCK_WIDE_ATOMIC_PASS "..phase.." removed the stale physical stop with no duplicate debit")
      core.request_shutdown("Verified checkpoint removal",false,0)
    end)
  end
end)
