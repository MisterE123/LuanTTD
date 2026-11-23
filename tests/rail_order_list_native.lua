-- Disposable Linux world: real paid rail controller and SQLite round trip.
local Rail=assert(api.rail_dispatch_controller)
local Track=dofile(mod.."/openttd/rail_track.lua")
local Owned=assert(api.rail_owned)
core.after(0,function()
  local p=S.rail_order_list_native
  local restoring=p~=nil
  local live=core.settings:get_bool("luanttd_qa_live_order_edit",false)
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
    local ordered={stations[3],stations[2],stations[1]}
    assert(Owned.start_order_list(S,owner,unit.id,live and {stations[3],stations[1]} or ordered))
    p={unit=unit.id,stations=live and {stations[2],stations[1],stations[3]} or ordered,ordered=ordered,count=0,owner=owner}
    if live then
      assert(Owned.edit_orders(S,owner,unit.id,0,"add",2,stations[2]))
      assert(not Owned.edit_orders(S,owner,unit.id,0,"move",2,3))
    end
  end
  local run=assert(Rail.current_paid(S,p.unit))
  if restoring then
    assert(p.count==2 and run.order_cursor.real==p.cursor and run.order_cursor.implicit==p.cursor)
    for i,station in ipairs(p.ordered) do assert(run.orders[i].station==station) end
    if live then assert(Owned.order_state(S,p.owner,p.unit).revision==2) end
  end
  for _=1,150 do
    Sim.daily(S)
    local d=assert(Rail.current(S))
    assert(not d.failure,d.failure)
    if live and not p.edited and run.phase=="running" then
      local head,serial=run.consist.parts[1],run.consist.serial
      local x=Sim.xy(head.tile)
      if x>=8 and x<15 then
        assert(Owned.edit_orders(S,p.owner,p.unit,1,"skip",2))
        assert(run.consist.parts[1]==head and run.consist.serial==serial and run.station==p.ordered[2])
        p.edited=true
      end
    end
    for _,event in ipairs(Sim.rail_paid_motion_events(S)) do
      if event.kind=="arrived" then
        assert(event.station==p.stations[p.count%3+1],("wrong station at order %d: %s"):format(p.count+1,event.station))
        p.count=p.count+1
      end
    end
    if not restoring and p.count==2 then
      if live then assert(p.edited and run.order_revision==2) end
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
      core.log("action",("RAIL_ORDER_LIST_NATIVE_PASS %d ordered arrivals, loop and $%d fare after SQLite restart%s"):format(
        p.count,status.fare,live and " with live edits" or ""))
      core.request_shutdown("Three-station train paid and looped",false,0)
      return
    end
  end
  error("Three-station train failed to reach expected arrivals")
end)
