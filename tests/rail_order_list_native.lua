-- Disposable Linux world: real paid rail controller and SQLite round trip.
local Rail=assert(api.rail_dispatch_controller)
local Track=dofile(mod.."/openttd/rail_track.lua")
local Owned=assert(api.rail_owned)
core.after(0,function()
  local p=S.rail_order_list_native
  local restoring=p~=nil
  if not restoring then
    local owner="Order Loop Railways"
    Sim.company(S,owner)
    for i in ipairs(S.corner_grid.levels) do S.corner_grid.levels[i]=0 end
    for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
    local function id(x,z) return Sim.id(x,z or 15) end
    for x=2,25 do
      local t=S.tiles[id(x)]
      t.owner,t.rail_tracks,t.build=owner,1,"stock_rail"
    end
    assert(api.trackworks.depot(S,owner,id(2),Track.SW))
    local stations={}
    for _,ends in ipairs({{11,12},{16,17},{22,24}}) do
      assert(api.trackworks.station(S,owner,id(ends[1]),id(ends[2])))
      stations[#stations+1]=S.tiles[id(ends[1])].rail_station_id
      for x=ends[1]-1,ends[2]+1 do
        for _,z in ipairs({13,14,16,17}) do
          local t=S.tiles[id(x,z)]
          t.house,t.parcel,t.variant=true,"shop",2
        end
      end
    end
    local unit=assert(Owned.commit(S,owner,assert(Owned.quote(S,owner,id(2),{0,27}))))
    assert(Owned.start_order_list(S,owner,unit.id,{stations[3],stations[2],stations[1]}))
    p={unit=unit.id,stations={stations[3],stations[2],stations[1]},count=0}
  end
  local run=assert(Rail.current_paid(S,p.unit))
  if restoring then
    assert(p.count==2 and run.order_cursor.real==p.cursor and run.order_cursor.implicit==p.cursor)
    for i,station in ipairs(p.stations) do assert(run.orders[i].station==station) end
  end
  for _=1,150 do
    Sim.daily(S)
    local d=assert(Rail.current(S))
    assert(not d.failure,d.failure)
    for _,event in ipairs(Sim.rail_paid_motion_events(S)) do
      if event.kind=="arrived" then
        assert(event.station==p.stations[p.count%3+1],("wrong station at order %d: %s"):format(p.count+1,event.station))
        p.count=p.count+1
      end
    end
    if not restoring and p.count==2 then
      p.cursor=run.order_cursor.real
      S.rail_order_list_native=p
      api.save()
      core.log("action","RAIL_ORDER_LIST_NATIVE_SAVED")
      core.request_shutdown("Three-station train saved",false,0)
      return
    end
    local status=assert(Sim.rail_paid_status(S,p.unit))
    if restoring and p.count>=6 and status.fare>0 then
      assert(run.shuttle.reversals>=2)
      core.log("action",("RAIL_ORDER_LIST_NATIVE_PASS %d ordered arrivals, loop and $%d fare after SQLite restart"):format(p.count,status.fare))
      core.request_shutdown("Three-station train paid and looped",false,0)
      return
    end
  end
  error("Three-station train failed to reach expected arrivals")
end)
