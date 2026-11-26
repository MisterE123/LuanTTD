-- Appended to an isolated Luanti world; there are no synthetic vehicles.
local Rail=assert(api.rail_dispatch_controller)
local Owned=assert(api.rail_owned)
local T=dofile(mod.."/openttd/rail_track.lua")
local Signals=dofile(mod.."/openttd/rail_signals.lua")(T)
local signed=core.settings:get_bool("luanttd_qa_coastal_signed_rail",false)
local at=Sim.id
local owner="Rail flood QA"
local function insert_line(z)
  for x=4,38 do
    local t=S.tiles[at(x,z)]
    t.owner,t.rail_tracks,t.build=owner,1,"stock_rail"
  end
  assert(api.trackworks.depot(S,owner,at(4,z),T.SW))
  assert(api.trackworks.station(S,owner,at(19,z),at(20,z)))
  assert(api.trackworks.station(S,owner,at(33,z),at(34,z)))
  if signed then
    for x=6,10 do
      assert(Rail.place_signal(S,owner,at(x,z),T.trackdir_for_exit(T.X,T.SW),Signals.BLOCK,true))
    end
  end
  local A=S.tiles[at(19,z)].rail_station_id
  local B=S.tiles[at(33,z)].rail_station_id
  local q=assert(Owned.quote(S,owner,at(4,z),{0,27}))
  local u=assert(Owned.commit(S,owner,q))
  assert(Owned.start(S,owner,u.id,A,B))
  return u.id,A,B
end
core.after(0,function()
  Sim.mount_coastal_flood(S)
  local proof=S.rail_flood_native
  if not proof then
    local g=assert(S.corner_grid)
    for i in ipairs(g.levels) do g.levels[i]=0 end
    for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
    local wd=g.width+1
    for z=20,29 do for x=1,40 do g.levels[(z-1)*wd+x]=1 end end
    Sim.company(S,owner)
    local wet=insert_line(13)
    local dry,A,B=insert_line(24)
    assert(Rail.current_paid(S,wet).id==1 and Rail.current_paid(S,dry).id==2)
    local w=assert(Rail.current_paid(S,wet))
    for _=1,10 do
      Sim.daily(S)
      local x=Sim.xy(w.consist.parts[1].tile)
      if x>=6 and x<=16 then break end
    end
    local move_at=Sim.xy(w.consist.parts[1].tile)
    assert(move_at>=6 and move_at<=16,"expected moving train on an ordinary parcel")
    assert(Owned.toggle(S,owner,wet))
    for day=1,6 do
      if w.speed==0 and not w.consist.parts[1].hidden then break end
      Sim.daily(S)
    end
    assert(w.speed==0 and not w.consist.parts[1].hidden)
    if signed then assert(Rail.current(S).signals.records[w.consist.parts[1].tile],"Target was not signed") end
    local at_wreck=w.consist.parts[1].tile
    local x,z=Sim.xy(at_wreck)
    assert(S.tiles[at_wreck].build=="stock_rail" and not S.tiles[at_wreck].rail_station_id and S.tiles[at_wreck].rail_depot_dir==nil)
    local water=at(x,z+1)
    S.tiles[water]={terrain="water",water_class="sea",h=0,variant=1}
    local terrain=dofile(mod.."/openttd/terrain.lua")
    local a,b=terrain.tile(S.corner_grid,x,z)
    core.log("action",("FLOOD_START %d %d %d %d z=%s span=%s height=%s railground=%s clock=%s"):format(x,z,a,b,
      tostring(w.consist.parts[1].z),tostring(w.span),tostring(w.z),tostring(S.tiles[at_wreck].rail_ground),tostring(S.passenger_house_clock and S.passenger_house_clock.counter)))
    for day=1,30 do
      Sim.daily(S)
      assert(not Rail.current(S).failure,Rail.current(S).failure)
      if w.crashed then break end
    end
    assert(w.flood_wreck and w.crash_age>=4000 and w.crash_age<4440,("stock tide never reached the paid train: id=%d head=%d age=%s tide=%s"):format(at_wreck,w.consist.parts[1].tile,tostring(w.crash_age),tostring(S.stock_coastal_flood)))
    assert(#w.consist.parts==2 and S.tiles[at_wreck].rail_tracks and not Rail.current_paid(S,dry).crashed)
    if signed then assert(Rail.current(S).signals.records[at_wreck],"Signalling must remain until clearing the wreck") end
    S.rail_flood_native={owner=owner,wet=wet,dry=dry,target=at_wreck,A=A,B=B,dry_ticks=Rail.current_paid(S,dry).vehicle_ticks}
    api.save()
    core.log("action","RAIL_FLOOD_NATIVE_SAVED_WRECK")
    core.request_shutdown("Saved a paid flooded train alongside an independent operating service",false,0)
    return
  end
  local wet=assert(Rail.current_paid(S,proof.wet))
  local dry=assert(Rail.current_paid(S,proof.dry))
  assert(wet.flood_wreck and #wet.consist.parts==2 and dry.id==2 and not dry.crashed)
  assert(S.stock_rail_fleet.units[proof.wet] and S.stock_rail_fleet.units[proof.dry])
  for day=1,45 do
    Sim.daily(S)
    assert(not Rail.current(S).failure,Rail.current(S).failure)
    if not Rail.current_paid(S,proof.wet) and S.tiles[proof.target].terrain=="water" then break end
  end
  assert(not Rail.current_paid(S,proof.wet) and not S.stock_rail_fleet.units[proof.wet])
  assert(S.tiles[proof.target].terrain=="water" and not S.tiles[proof.target].rail_tracks)
  assert(Rail.current_paid(S,proof.dry)==dry and dry.id==2 and dry.vehicle_ticks>proof.dry_ticks and not dry.crashed)
  if signed then
    local signals=Rail.current(S).signals.records
    assert(not signals[proof.target] and signals[at(7,24)],"Removed cleared head without touching the dry counterpart")
  end
  local depot=at(4,24)
  local q=assert(Owned.quote(S,owner,depot,{0,27}))
  local new=assert(Owned.commit(S,owner,q))
  assert(Owned.start(S,owner,new.id,proof.A,proof.B))
  assert(Rail.current_paid(S,new.id).id==3 and Rail.by_id(S,2)==dry)
  api.save()
  core.log("action","RAIL_FLOOD_NATIVE_PASS flooded paid stock train, seafloor after tail retirement and unaffected train ID retained")
  core.request_shutdown("Restored responsive coastline and independent train fleets",false,0)
end)
