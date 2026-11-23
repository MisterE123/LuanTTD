local signal_free=core.settings:get_bool("luanttd_qa_signal_free",false)
-- Appended only in isolated native QA. Purchase, move, board, save,
-- reload, turn the true steam consist and deliver from the same receipt.
local jubilee=core.settings:get_bool("bayline_native_jubilee_probe",false)
local sh=core.settings:get_bool("bayline_native_sh_8p_probe",false)
local sh40=core.settings:get_bool("bayline_native_sh_40_probe",false)
local electric=sh40 or core.settings:get_bool("bayline_native_electric_probe",false)
local bridge=core.settings:get_bool("bayline_native_electric_bridge_probe",false)
local lookahead=core.settings:get_bool("bayline_native_platform_lookahead_probe",false)
local branch=lookahead or core.settings:get_bool("bayline_native_rail_branch_probe",false)
assert(not bridge or electric)
assert(not branch or not bridge and not electric)
local coach=core.settings:get_bool("bayline_native_manley_coach_probe",false)
local manley=coach or core.settings:get_bool("bayline_native_manley_probe",false)
assert(not (jubilee and sh or manley and (jubilee or sh)))
local design=sh40 and {24,48804,176,984000,"sh_40","bl_rail_sh_40"}
  or electric and {23,42554,160,864000,"sh_30","bl_rail_sh_30"}
  or manley and {11,coach and 19116 or 17187,112,436800,"manley","bl_rail_manley_morel"}
  or sh and {10,36304,144,728000,"sh_8p","bl_rail_sh_8p"}
  or jubilee and {8,22241,112,672000,"jubilee","bl_rail_chaney_jubilee"}
  or {0,12866,64,280000,"steam","bl_rail_kirby_paul_tank"}
local engine,cost,vmax,annual,kind,art=unpack(design)
local physical_count=coach and 3 or 2
local capacity=coach and 116 or 76
local roles=coach and {"front","carriage","rear"} or {"front","rear"}
local owner="Owned Rail QA"
local function id(x,z) return Sim.id(x,z or 10) end
local function stamp()
  local Owned,Run=assert(api.rail_owned),assert(api.rail_dispatch_controller)
  local qa=S.rail_owned_native_qa
  local function current() return assert(Run.current_paid(S)) end
  local function forward_claims()
    local run,d=current(),Run.current(S)
    assert(run.platform_lookahead and run.phase=="dwell" and run.arrival.tile==id(24) and run.order.station==run.station)
    local function claimed(x,z,track)
      local row=d.life.claims[id(x,z)]
      return row and row[track]
    end
    assert(claimed(25,10,0)==run.id and claimed(26,10,5)==run.id and claimed(23,15,0)==run.id)
    assert(not claimed(22,15,0),"Should stop reserving before the next PBS signal")
  end
  local evidence={fits=0,low=10,high=0,ramps={},before={},after={}}
  if bridge then
    assert(api.rail_dispatch_view.split_electric_ready())
    api.rail_dispatch_view.observe_collector=function(run,tile,mount,wire,scale,td)
      if not wire then return end
      assert(mount,"The physical shoe lost the wired route at "..tile)
      if td==8 then evidence.before[tile]=true
      elseif td==0 then evidence.after[tile]=true end
      evidence.fits=evidence.fits+1
      evidence.low,evidence.high=math.min(evidence.low,scale),math.max(evidence.high,scale)
      if tile==id(15) or tile==id(19) then evidence.ramps[tile]=true end
    end
  end
  local function day()
    Sim.daily(S)
    assert(not Run.current(S).failure,Run.current(S).failure)
    if bridge then
      for t=0,74 do api.rail_dispatch_view.step(.05,true,t/74) end
    end
    if manley then
      local st=assert(Sim.rail_paid_status(S))
      local r=current()
      local mass=coach and 89 or 64
      for i,p in ipairs(st.carrying_parts) do
        mass=mass+math.floor(p.onboard/16)
        if st.loading then assert(p.tile==r.arrival.cargo_tiles[i]) end
      end
      assert(r.consist_mass==mass and r.acceleration==4*math.floor(600/mass))
    end
  end
  local function entity_at(run,i,fraction)
    local tile,td,f,_,wormhole=Sim.rail_paid_pose(S,i,fraction)
    assert(tile and td and f and not wormhole)
    api.rail_dispatch_view.step(.1,true,fraction)
    local tx,tz=Sim.xy(tile)
    local powered=i==1 or manley and i==physical_count
    local expected=powered and ("luanttd_core:dispatch_"..kind..(bridge and "_body" or "")) or "luanttd_core:dispatch_wagon"
    local mesh=powered and (art..(bridge and "_body" or "")..".obj") or "bl_rail_passenger_wagon.obj"
    local _,level=api.terrain.tile(tile)
    for _,obj in ipairs(core.get_objects_inside_radius({x=2*tx+.5,y=level+.614,z=2*tz+.5},1.7)) do
      local info=obj:get_luaentity()
      if info and info.name==expected then
        local prop=obj:get_properties()
        assert(prop.mesh==mesh)
        if powered then assert(prop.textures[1]==art..".png") end
        assert(math.abs(obj:get_pos().y-(level+.614))<.002)
        assert(prop.visual_size.z==1)
        return
      end
    end
    error("Native stock train part not spawned: "..mesh)
  end
  local function facing()
    if not manley then return end
    api.rail_dispatch_view.step(.1,true,1)
    local head=select(1,Sim.rail_paid_pose(S,1,1))
    local x,z=Sim.xy(head)
    local _,level=api.terrain.tile(head)
    local cabs,coaches={},0
    for _,obj in ipairs(core.get_objects_inside_radius({x=2*x+.5,y=level+.614,z=2*z+.5},4)) do
      local ent=obj:get_luaentity()
      if ent and ent.name=="luanttd_core:dispatch_manley" then cabs[#cabs+1]=obj
      elseif ent and ent.name=="luanttd_core:dispatch_wagon" then coaches=coaches+1 end
    end
    assert(#cabs==2 and coaches==(coach and 1 or 0),"Incorrect independent native body meshes")
    local yaw=cabs[1]:get_rotation().y-cabs[2]:get_rotation().y
    assert(math.abs(math.cos(yaw)+1)<.03,"Its two native driver cabs must face outward")
    assert(vector.distance(cabs[1]:get_pos(),cabs[2]:get_pos())>.95,"The two physical bodies overlap")
  end
  if qa then
    if lookahead then forward_claims() end
    local record=assert(Owned.get(S,owner,qa.unit))
    assert(record.status=="dispatched" and record.id==current().fleet_id and record.parts[1].stock_id==engine)
    assert(current().running_year_fp==annual and current().max_track_speed==vmax)
    if electric then
      assert(Sim.date(S,0)==(sh40 and 1978 or 1970) and current().engine_railtype==1 and current().traction_railtypes[1] and
        not current().traction_railtypes[0])
      assert(S.tiles[id(20)].rail_type==1 and S.tiles[id(2)].rail_type==1)
      assert(core.get_node({x=40,y=bridge and 3 or 2,z=20}).name=="luanttd_core:rail_catenary_1_1")
      assert(core.get_node({x=44,y=bridge and 3 or 2,z=20}).name=="luanttd_core:rail_catenary_1_0")
      if bridge then
        assert(current().bridge_collectors and api.rail_spans.by_portal(S,id(15)).railtype==1)
        assert(core.get_node({x=34,y=3,z=20}).name:find("rail_bridge_catenary",1,true))
      end
    end
    if sh or manley then assert(Sim.date(S,0)==1960 and current().stock_steps>100) end
    if manley then
      assert(#record.stock_ids==(coach and 2 or 1) and #record.parts==physical_count and
        record.parts[1].mate==physical_count and record.parts[physical_count].mate==1)
      local actor=Sim.rail_paid_status(S)
      assert(actor.capacity==capacity and actor.carrying_parts[1].onboard==qa.front
        and actor.carrying_parts[physical_count].onboard==qa.rear)
      if coach then assert(actor.carrying_parts[2].onboard==qa.coach and qa.coach>0) end
      facing()
    end
    local present=Sim.rail_paid_status(S)
    assert(present.onboard==qa.passengers and S.companies[owner].cash==qa.cash,
      ("Saved/train ledger mismatch: passengers %s/%s, cash %s/%s, day %s/%s"):
        format(present.onboard,qa.passengers,S.companies[owner].cash,qa.cash,S.day,qa.day or "?"))
    local previous=assert(Owned.running(S,owner,qa.unit))
    assert(previous.running_expense==qa.running_expense and previous.running_cost_fp==qa.cost_fp)
    assert(previous.charged_running_ticks==qa.charged_running_ticks)
    assert(S.companies[owner].stock_money_fraction==qa.fraction)
    assert(Run.settle_passenger_running_day(S)==nil)
    assert(not Owned.commit(S,owner,qa.quote))
    entity_at(current(),1,1)
    for i=2,physical_count do entity_at(current(),i,1) end
    local fare=0
    local delivered,F,part_visits=0,{},{}
    local saw_extension_tail
    for _=1,120 do
      day()
      if lookahead then
        for _,event in ipairs(Sim.rail_paid_motion_events(S)) do
          if event.kind=="tail_released" and event.tile==id(25) then saw_extension_tail=true end
        end
      end
      for _,e in ipairs(Sim.rail_loading_events(S)) do
        if e.kind=="fare" then
          assert(not F[e.visit],"A reciprocal train paid twice for one loading visit")
          F[e.visit]=true;fare=fare+e.amount
        elseif manley and e.kind=="deliver" then
          assert(roles[e.part]==e.role)
          delivered=delivered+e.units;part_visits[e.part]=(part_visits[e.part] or 0)+e.units
        end
      end
      if fare>0 and (lookahead and current().shuttle.arrivals>=3 or not lookahead and current().shuttle.reversals>=2) then break end
    end
    assert(fare>0 and S.companies[owner].revenue==fare)
    if lookahead then
      assert(saw_extension_tail and current().shuttle.arrivals>=3 and current().shuttle.reversals==0)
      core.log("action","OWNED_RAIL_THROUGH_NATIVE_PASS first platform claims survive SQLite reload; released tail, paid second station and repeated")
    else assert(current().shuttle.reversals>=2) end
    if manley then
      for i=1,physical_count do
        assert(part_visits[i] and part_visits[i]>0,"Missing a native body delivery")
        entity_at(current(),i,1)
      end
      assert(S.companies[owner].paid_units==delivered)
      assert(current().max_track_speed==112 and current().running_year_fp==436800)
      facing()
    end
    assert(Owned.get(S,owner,qa.unit).price==cost)
    local after=assert(Owned.running(S,owner,qa.unit))
    assert(after.running_expense>previous.running_expense and after.charged_running_ticks>previous.charged_running_ticks)
    assert(S.companies[owner].cash==qa.cash+fare-(S.companies[owner].expense-qa.expense))
    if branch then
      assert(current().branch_pbs and S.tiles[id(6)].rail_tracks==41)
      core.log("action","OWNED_RAIL_BRANCH_NATIVE_PASS closed loop, two through platforms and PBS junction; paid route retained")
    end
    if bridge then
      assert(qa.fits>35 and evidence.fits>35 and evidence.ramps[id(15)] and evidence.ramps[id(19)])
      assert(evidence.after[id(17)],"No restored westbound native contact across the bridge center")
      core.log("action",("POWERED_BRIDGE_NATIVE_PASS engine=%d ascent_fit_before=%d return_fit_after=%d min=%.3f max=%.3f"):
        format(engine,qa.fits,evidence.fits,evidence.low,evidence.high))
    end
    core.log("action",("OWNED_RAIL_LIVE_NATIVE_PASS engine=%d fare=$%d operating_cost=$%d peak=%d bodies=%d"):
      format(engine,fare,after.running_expense,qa.peak,physical_count))
    core.request_shutdown("Native steam ride survived restart and earned its first fare",false,0)
    return
  end
  local g=S.corner_grid
  for z=1,g.depth+1 do
    for x=1,g.width+1 do g.levels[(z-1)*(g.width+1)+x]=bridge and ((x==17 or x==18) and 0 or 1) or 0 end
  end
  for x=1,27 do
    S.tiles[id(x)]={h=0,terrain="grass",variant=1}
  end
  for x=2,signal_free and 26 or 24 do
    if not bridge or x<15 or x>19 then
      local t=S.tiles[id(x)];t.owner=owner;t.rail_tracks=1;t.build="stock_rail"
    end
  end
  local c=Sim.company(S,owner)
  local bridge_wire
  if bridge then
    local w=assert(api.rail_spans)
    local p=assert(w.quote_bridge(S,owner,id(15),id(19)))
    assert(p.deck==2 and not p.head.flat_ramp and not p.tail.flat_ramp)
    local ok,o,foot,d=w.commit(S,owner,p);assert(ok,o)
    api.render.raise_bound(d)
    bridge_wire=function()
      local both=assert(api.electric_quote(owner,{id(15),id(19)},1))
      local one=assert(api.electric_quote(owner,{id(15)},1))
      assert(one.cost==340 and both.cost==one.cost)
      local ok,cost,area=api.electric_commit(owner,one)
      assert(ok and cost==340 and #area==5)
    end
  end
  assert(api.trackworks.depot(S,owner,id(2),2))
  assert(api.trackworks.station(S,owner,id(11),id(12)))
  assert(api.trackworks.station(S,owner,id(22),id(24)))
  if not signal_free then assert(Run.place_signal(S,owner,id(10),0,4)) end
  local west,east=S.tiles[id(11)].rail_station_id,S.tiles[id(22)].rail_station_id
  S.sites[1].tile=id(10,13);S.sites[2].tile=id(24,13)
  for _,z in ipairs({7,8,12,13}) do
    for _,x in ipairs({8,9,10,11,12,21,22,23,24,25}) do
      local t=S.tiles[id(x,z)]
      t.terrain,t.h,t.build,t.owner,t.site,t.wood="grass",0,nil,nil,nil,nil
      t.house,t.parcel,t.variant=true,"shop",2
    end
  end
  assert(not Owned.quote(S,owner,id(2),{1,27}))
  if jubilee or sh or manley or electric then
    local catalog=assert(Owned.catalog(S))
    local found=false
    for _,row in ipairs(catalog) do
      if row.stock_id==engine then
        assert(row.availability.public and row.passenger_model_ready)
        found=true
      end
    end
    assert(found)
  end
  if electric then
    assert(api.electric_available(owner) and api.rail_owned.passenger_engine(engine))
    local missing,why=Owned.quote(S,owner,id(2),{engine,27})
    assert(not missing and why=="INCOMPATIBLE_DEPOT_RAIL",why)
    local line={}
    for x=2,24 do if x~=20 and (not bridge or x<15 or x>19) then line[#line+1]=id(x) end end
    local quote=assert(api.electric_quote(owner,line,1))
    assert(quote.price==(bridge and 17 or 22)*68)
    assert(api.electric_commit(owner,quote))
    assert(S.tiles[id(20)].rail_type==nil and S.tiles[id(2)].rail_type==1)
  end
  if manley then
    local saved=core.show_formspec
    local ticket
    core.show_formspec=function(_,form,body) if form=="luanttd_core:rail_fleet" then ticket=body end end
    assert(api.owned_rail_ui.open({get_player_name=function() return owner end},id(2)))
    core.show_formspec=saved
    assert(ticket and ticket:find("purchase_manley",1,true) and ticket:find("76 seats",1,true))
    assert(ticket:find("purchase_manley_coach",1,true) and ticket:find("116 seats",1,true))
    assert(not Owned.quote(S,owner,id(2),{11,27,27}))
  end
  local q=assert(Owned.quote(S,owner,id(2),manley and not coach and {engine} or {engine,27}))
  local initial_cash=c.cash
  local r=assert(Owned.commit(S,owner,q))
  assert(r.price==cost and c.cash==initial_cash-r.price)
  if branch then
    S.tiles[id(25)]={owner=owner,rail_tracks=1,build="stock_rail",h=0,terrain="grass",variant=1}
    local bad,reason=Owned.start(S,owner,r.id,east,west)
    assert(not bad and reason:find("Platform (24,10) has no safe exit",1,true),reason)
    assert(Owned.get(S,owner,r.id).status=="depot")
    local rail=api.trackworks
    local function loop(x,z,piece)
      local tile=id(x,z)
      if tile~=id(6) then S.tiles[tile]={h=0,terrain="grass",variant=1} end
      assert(rail.change(S,owner,tile,piece,false,0))
    end
    loop(6,10,3);loop(6,10,5)
    loop(26,10,5);loop(26,15,2);loop(6,15,4)
    for z=11,14 do loop(6,z,1);loop(26,z,1) end
    for x=7,25 do loop(x,15,0) end
    if lookahead then
      assert(Run.place_signal(S,owner,id(18),8,5))
      assert(Run.place_signal(S,owner,id(22,15),0,4))
      assert(Run.place_signal(S,owner,id(13),8,4))
    else assert(Run.place_signal(S,owner,id(25),8,4)) end
  end
  if electric then
    local blocked=Owned.start(S,owner,r.id,east,west)
    assert(not blocked,"SH '30' must not route over the unpowered gap")
    assert(api.electric_commit(owner,assert(api.electric_quote(owner,{id(20)},1))))
    assert(S.tiles[id(20)].rail_type==1)
    if bridge then
      assert(not Owned.start(S,owner,r.id,east,west),"an unelectrified bridge is not a powered route")
      bridge_wire()
    end
  end
  local ok,note=Owned.start(S,owner,r.id,east,west);assert(ok,note)
  if signal_free then assert(current().ordinary_unreserved and not next(S.stock_rail_dispatch.signals.records)) end
  if bridge then assert(current().bridge_collectors) end
  assert(current().stock_engine==engine and current().max_track_speed==vmax)
  local peak=0
  for _=1,100 do
    day()
    peak=math.max(peak,current().speed)
    local s=assert(Sim.rail_paid_status(S))
    local both=not manley or (s.carrying_parts[1].onboard>0 and
      s.carrying_parts[physical_count].onboard>0 and (not coach or s.carrying_parts[2].onboard>0))
    if s.loading and s.onboard>0 and both then
      if lookahead then forward_claims() end
      for i=1,physical_count do entity_at(current(),i,1) end
      if jubilee or sh or manley then assert(peak>64,"Native source locomotive did not exceed the Kirby maximum") end
      local bill=assert(Owned.running(S,owner,r.id))
      assert(bill.running_expense>0 and bill.charged_running_ticks>0)
      S.rail_owned_native_qa={unit=r.id,quote=q,passengers=s.onboard,cash=c.cash,expense=c.expense,day=S.day,
        running_expense=bill.running_expense,cost_fp=bill.running_cost_fp,fraction=c.stock_money_fraction,
        charged_running_ticks=bill.charged_running_ticks,peak=peak,
        front=manley and s.carrying_parts[1].onboard,rear=manley and s.carrying_parts[physical_count].onboard,
        coach=coach and s.carrying_parts[2].onboard}
      if bridge then
        assert(evidence.before[id(17)],"No eastbound native contact across the bridge center")
        S.rail_owned_native_qa.fits=evidence.fits
      end
      api.save()
      core.log("action","OWNED_RAIL_SAVE_LOADING")
      core.request_shutdown("Saved a real owned steam train while passengers boarded",false,0)
      return
    end
  end
  error("No paid owned carriage boarded")
end
core.after(0,function()
  core.emerge_area({x=0,y=-1,z=18},{x=54,y=5,z=23},function(_,_,remaining)
    if remaining==0 then core.after(0,stamp) end
  end)
end)
