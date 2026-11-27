-- Supply an observer for deliberate native mesh assertions without a real client.
local function render_inspection(dt,online,fraction)
  api.interest.refresh({{get_pos=function() return {x=Sim.W+1,z=Sim.H+1} end}})
  return api.rail_dispatch_view.step(dt,online,fraction)
end
local isolated=core.settings:get_bool("luanttd_qa_disconnected_path_signal",false)
local turnout=isolated or core.settings:get_bool("luanttd_qa_depot_turnout",false)
local two_coaches=core.settings:get_bool("luanttd_qa_two_coaches",false)
local signal_free=turnout or two_coaches or core.settings:get_bool("luanttd_qa_signal_free",false)
-- Appended only in isolated native QA. Purchase, move, board, save,
-- reload, turn the true steam consist and deliver from the same receipt.
local jubilee=core.settings:get_bool("bayline_native_jubilee_probe",false)
local sh=core.settings:get_bool("bayline_native_sh_8p_probe",false)
local sh40=core.settings:get_bool("bayline_native_sh_40_probe",false)
local asiastar=core.settings:get_bool("luanttd_qa_asiastar",false)
local tim=asiastar or core.settings:get_bool("luanttd_qa_tim",false)
local electric=tim or sh40 or core.settings:get_bool("bayline_native_electric_probe",false)
local bridge=core.settings:get_bool("bayline_native_electric_bridge_probe",false)
local wire_turnout=core.settings:get_bool("luanttd_qa_electric_turnout",false)
local lookahead=core.settings:get_bool("bayline_native_platform_lookahead_probe",false)
local branch=lookahead or core.settings:get_bool("bayline_native_rail_branch_probe",false)
assert(not bridge or electric)
assert(not branch or not bridge and not electric)
local dash_coach=core.settings:get_bool("luanttd_qa_dash_coach",false)
local dash=dash_coach or core.settings:get_bool("luanttd_qa_dash",false)
local coach=dash_coach or core.settings:get_bool("bayline_native_manley_coach_probe",false)
local dmu=dash or coach or core.settings:get_bool("bayline_native_manley_probe",false)
assert(not (jubilee and sh or dmu and (jubilee or sh)))
local design=asiastar and {26,69116,264,1200000,"asiastar","bl_rail_asiastar"}
  or tim and {25,64429,240,1152000,"tim","bl_rail_tim"}
  or sh40 and {24,48804,176,984000,"sh_40","bl_rail_sh_40"}
  or electric and {23,42554,160,864000,"sh_30","bl_rail_sh_30"}
  or dash and {12,coach and 23804 or 21875,120,364000,"dash","bl_rail_dash"}
  or dmu and {11,coach and 19116 or 17187,112,436800,"manley","bl_rail_manley_morel"}
  or sh and {10,36304,144,728000,"sh_8p","bl_rail_sh_8p"}
  or jubilee and {8,22241,112,672000,"jubilee","bl_rail_chaney_jubilee"}
  or {0,12866,64,280000,"steam","bl_rail_kirby_paul_tank"}
local engine,cost,vmax,annual,kind,art=unpack(design)
local push_pull=dmu or tim
local physical_count=(coach or tim or two_coaches) and 3 or 2
local seat_count=dash and 40 or 38
local capacity=2*seat_count+(coach and 40 or 0)
local roles=coach and {"front","carriage","rear"} or {"front","rear"}
local owner="Owned Rail QA"
local mod_path=core.get_modpath("luanttd_core")
local render_pose=dofile(mod_path.."/rail_pose.lua")(dofile(mod_path.."/openttd/rail_track.lua"))
local function id(x,z) return Sim.id(x,z or 10) end
local depot=turnout and id(16,9) or id(2)
local function stamp()
  local Owned,Run=assert(api.rail_owned),assert(api.rail_dispatch_controller)
  local qa=S.rail_owned_native_qa
  local function current() return assert(Run.current_paid(S),"Expected an active paid rail consist in the test corridor") end
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
  local evidence={fits=0,low=10,high=0,ramps={},before={},after={},cab_before={},cab_after={}}
  if bridge then
    assert(api.rail_dispatch_view.split_electric_ready())
    api.rail_dispatch_view.observe_collector=function(run,tile,mount,wire,scale,td,body_index)
      if not wire then return end
      assert(mount,"The physical shoe lost the wired route at "..tile)
      if td==8 then
        evidence.before[tile]=true
        if tile==id(17) then evidence.cab_before[body_index]=true end
      elseif td==0 then
        evidence.after[tile]=true
        if tile==id(17) then evidence.cab_after[body_index]=true end
      end
      evidence.fits=evidence.fits+1
      evidence.low,evidence.high=math.min(evidence.low,scale),math.max(evidence.high,scale)
      if tile==id(15) or tile==id(19) then evidence.ramps[tile]=true end
    end
  end
  local choices={}
  local function day()
    Sim.daily(S)
    assert(not Run.current(S).failure,Run.current(S).failure)
    if turnout then
      for _,event in ipairs(Sim.rail_paid_motion_events(S)) do
        if event.kind=="front_entered" and event.tile==id(16) then choices[event.td]=true end
      end
      if isolated then
        local run,claims=current(),S.stock_rail_dispatch.life.claims
        if run.phase=="depot" or run.station==S.tiles[id(23)].rail_station_id then
          assert(not claims[id(20)] or run.consist.parts[1].tile==id(20) or
            run.consist.parts[2].tile==id(20),"Unrelated PBS must not reserve empty track ahead")
        end
      end
    end
    if bridge then
      for t=0,74 do render_inspection(.05,true,t/74) end
    end
    if dmu then
      local st=assert(Sim.rail_paid_status(S))
      local r=current()
      local mass=(dash and 76 or 64)+(coach and 25 or 0)
      for i,p in ipairs(st.carrying_parts) do
        mass=mass+math.floor(p.onboard/16)
        if st.loading then assert(p.tile==r.arrival.cargo_tiles[i]) end
      end
      assert(r.consist_mass==mass and r.acceleration==4*math.floor((dash and 700 or 600)/mass))
    end
  end
  local function entity_at(run,i,fraction)
    local tile,td,f,reversed,wormhole=Sim.rail_paid_pose(S,i,fraction)
    assert(tile and td and f and not wormhole)
    render_inspection(.1,true,fraction)
    local tx,tz=Sim.xy(tile)
    local powered=i==1 or push_pull and i==physical_count
    local expected=powered and ("luanttd_core:dispatch_"..kind..(bridge and "_body" or "")) or "luanttd_core:dispatch_wagon"
    local mesh=powered and (art..(bridge and "_body" or "")..".obj") or "bl_rail_passenger_wagon.obj"
    local _,level=api.terrain.tile(tile)
    local x,z,dx,dz=api.render.rail_diagonal_pose(tile,td,f)
    if x==nil then x,z,dx,dz=render_pose.sample(td,f) end
    local at={x=2*tx+.5+x,y=level+.614,z=2*tz+.5+z}
    for _,obj in ipairs(core.get_objects_inside_radius(at,.05)) do
      local info=obj:get_luaentity()
      if info and info.name==expected then
        local prop=obj:get_properties()
        assert(prop.mesh==mesh)
        if powered then assert(prop.textures[1]==art..".png") end
        assert(math.abs(obj:get_pos().y-(level+.614))<.002)
        assert(prop.visual_size.z==1)
        local own_direction=push_pull and (i==physical_count or (not powered and reversed))
        local wanted=math.pi-math.atan2(dx,dz)+(own_direction and math.pi or 0)
        assert(math.abs(math.cos(obj:get_rotation().y-wanted)-1)<.001,
          "Native locomotive must lead facing travel; the reciprocal tail cab must face out")
        return
      end
    end
    error("Native stock train part not spawned: "..mesh)
  end
  local function facing()
    if not push_pull then return end
    render_inspection(.1,true,1)
    local head=select(1,Sim.rail_paid_pose(S,1,1))
    local x,z=Sim.xy(head)
    local _,level=api.terrain.tile(head)
    local cabs,coaches={},0
    for _,obj in ipairs(core.get_objects_inside_radius({x=2*x+.5,y=level+.614,z=2*z+.5},4)) do
      local ent=obj:get_luaentity()
      if ent and ent.name=="luanttd_core:dispatch_"..kind..(bridge and "_body" or "") then cabs[#cabs+1]=obj
      elseif ent and ent.name=="luanttd_core:dispatch_wagon" then coaches=coaches+1 end
    end
    assert(#cabs==2 and coaches==((coach or tim) and 1 or 0),"Incorrect independent native body meshes")
    local yaw=cabs[1]:get_rotation().y-cabs[2]:get_rotation().y
    assert(math.abs(math.cos(yaw)+1)<.03,"Its two native driver cabs must face outward")
    assert(vector.distance(cabs[1]:get_pos(),cabs[2]:get_pos())>.95,"The two physical bodies overlap")
  end
  if qa then
    if two_coaches then
      cost=qa.purchase_cost
      local st=assert(Sim.rail_paid_status(S,qa.unit))
      assert(st.capacity==80 and st.carrying_parts[1].onboard==qa.coach1 and st.carrying_parts[2].onboard==qa.coach2)
      assert(qa.coach1>0 and qa.coach2>0)
      assert(#current().consist.parts==3)
    end
    if lookahead then forward_claims() end
    local record=assert(Owned.get(S,owner,qa.unit))
    assert(record.status=="dispatched" and record.id==current().fleet_id and record.parts[1].stock_id==engine)
    assert(current().running_year_fp==annual and current().max_track_speed==vmax)
    if electric then
      assert(Sim.date(S,0)==(asiastar and 1995 or tim and 1988 or sh40 and 1978 or 1970) and current().engine_railtype==1 and current().traction_railtypes[1] and
        not current().traction_railtypes[0])
      assert(S.tiles[id(20)].rail_type==1 and S.tiles[id(2)].rail_type==1)
      assert(core.get_node({x=40,y=3,z=20}).name==
        (bridge and "luanttd_core:rail_catenary_1_1" or "luanttd_core:rail_catenary_1_0"))
      if not bridge then
        assert(core.get_node({x=39,y=3,z=20}).name=="luanttd_core:rail_edge_pylon_0")
        assert(core.get_node({x=36,y=3,z=21}).name~="luanttd_core:rail_edge_pylon_2")
        assert(core.get_node({x=41,y=3,z=20}).name~="luanttd_core:rail_edge_pylon_0")
      end
      assert(core.get_node({x=44,y=3,z=20}).name=="luanttd_core:rail_catenary_1_0")
      if bridge then
        assert(current().bridge_collectors and api.rail_spans.by_portal(S,id(15)).railtype==1)
        assert(core.get_node({x=34,y=3,z=20}).name:find("rail_bridge_catenary",1,true))
      end
    end
    if sh or dmu then assert(Sim.date(S,0)==(dash and 1988 or 1960) and current().stock_steps>100) end
    if dmu then
      assert(#record.stock_ids==(coach and 2 or 1) and #record.parts==physical_count and
        record.parts[1].mate==physical_count and record.parts[physical_count].mate==1)
      local actor=Sim.rail_paid_status(S)
      assert(actor.capacity==capacity and actor.carrying_parts[1].onboard==qa.front
        and actor.carrying_parts[physical_count].onboard==qa.rear)
      if coach then assert(actor.carrying_parts[2].onboard==qa.coach and qa.coach>0) end
      facing()
    end
    if tim then
      assert(#record.parts==3 and record.parts[1].mate==3 and record.parts[3].mate==1
        and record.parts[2].stock_id==27 and current().power==(asiastar and 8000 or 7000))
      local state=Sim.rail_paid_status(S)
      assert(state.capacity==40 and #state.carrying_parts==1 and state.carrying_parts[1].role=="carriage")
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
    local saw_extension_tail,saw_return_heading
    for _=1,120 do
      day()
      if not lookahead and not saw_return_heading and current().shuttle.reversals>0 then
        -- A day can cross the turn or even a second departure; examine
        -- the historical paid-clock frames, as the live client does.
        for frame=0,74 do
          local f=frame/74
          local tile,_,_,reversed,span=Sim.rail_paid_pose(S,1,f)
          if tile and reversed and not span then
            local tail,_,_,_,between=Sim.rail_paid_pose(S,physical_count,f)
            if tail and not between then
              for i=1,physical_count do entity_at(current(),i,f) end
              saw_return_heading=true
              core.log("action","OWNED_RAIL_RETURN_HEADING_NATIVE_PASS")
              break
            end
          end
        end
      end
      if lookahead then
        for _,event in ipairs(Sim.rail_paid_motion_events(S)) do
          if event.kind=="tail_released" and event.tile==id(25) then saw_extension_tail=true end
        end
      end
      for _,e in ipairs(Sim.rail_loading_events(S)) do
        if e.kind=="fare" then
          assert(not F[e.visit],"A reciprocal train paid twice for one loading visit")
          F[e.visit]=true;fare=fare+e.amount
        elseif dmu and e.kind=="deliver" then
          assert(roles[e.part]==e.role)
          delivered=delivered+e.units;part_visits[e.part]=(part_visits[e.part] or 0)+e.units
        end
      end
      if fare>0 and (lookahead and current().shuttle.arrivals>=3 or not lookahead and current().shuttle.reversals>=2)
          and (not turnout or choices[0] and choices[8]) then break end
    end
    assert(fare>0 and S.companies[owner].revenue==fare)
    if lookahead then
      assert(saw_extension_tail and current().shuttle.arrivals>=3 and current().shuttle.reversals==0)
      core.log("action","OWNED_RAIL_THROUGH_NATIVE_PASS first platform claims survive SQLite reload; released tail, paid second station and repeated")
    else assert(current().shuttle.reversals>=2 and saw_return_heading) end
    if dmu then
      for i=1,physical_count do
        assert(part_visits[i] and part_visits[i]>0,"Missing a native body delivery")
        entity_at(current(),i,1)
      end
      assert(S.companies[owner].paid_units==delivered)
      assert(current().max_track_speed==vmax and current().running_year_fp==annual)
      facing()
    end
    assert(Owned.get(S,owner,qa.unit).price==cost)
    local after=assert(Owned.running(S,owner,qa.unit))
    assert(after.running_expense>previous.running_expense and after.charged_running_ticks>previous.charged_running_ticks)
    assert(S.companies[owner].cash==qa.cash+fare-(S.companies[owner].expense-qa.expense))
    if turnout then
      assert(qa.exit_curve and choices[0] and choices[8],"The restored train must run straight across the same turnout both ways")
      if isolated then
        assert(current().local_signals and not current().ordinary_unreserved
            and S.stock_rail_dispatch.signals.records[id(9,6)])
        core.log("action","OWNED_RAIL_UNRELATED_PBS_NATIVE_PASS no ahead reservation from a disconnected signal")
      else assert(current().ordinary_unreserved and not next(S.stock_rail_dispatch.signals.records)) end
      core.log("action","OWNED_RAIL_DEPOT_TURNOUT_NATIVE_PASS departure curve, then reciprocal main line through the same turnout after SQLite restore")
    end
    if branch then
      assert(current().branch_pbs and S.tiles[id(6)].rail_tracks==41)
      core.log("action","OWNED_RAIL_BRANCH_NATIVE_PASS closed loop, two through platforms and PBS junction; paid route retained")
    end
    if bridge then
      assert(qa.fits>35 and evidence.fits>35 and evidence.ramps[id(15)] and evidence.ramps[id(19)])
      assert(evidence.after[id(17)],"No restored westbound native contact across the bridge center")
      if tim then
        assert(qa.cab_fits and evidence.cab_after[1] and evidence.cab_after[3],
          "Both physical electric express cabs must contact real wire on the return")
        core.log("action","ELECTRIC_EXPRESS_BOTH_COLLECTORS_NATIVE_PASS exact contact for both physical heads, both directions")
      end
      core.log("action",("POWERED_BRIDGE_NATIVE_PASS engine=%d ascent_fit_before=%d return_fit_after=%d min=%.3f max=%.3f"):
        format(engine,qa.fits,evidence.fits,evidence.low,evidence.high))
    end
    if two_coaches then
      assert(#Owned.get(S,owner,qa.unit).parts==3)
      for i=1,3 do entity_at(current(),i,1) end
      core.log("action",("OWNED_RAIL_TWO_COACHES_NATIVE_PASS separately purchased 2 × 40 seats, two reversals, fare=$%d"):format(fare))
    end
    if wire_turnout then
      api.render.update({id(14),id(14,11),id(14,15)})
      assert(core.get_node({x=28,y=3,z=20}).name=="luanttd_core:rail_turnout_catenary_33")
      assert(core.get_node({x=28,y=4,z=30}).name=="luanttd_core:rail_turnout_catenary_33")
      core.log("action","ELECTRIC_TURNOUT_NATIVE_PASS branch contact, paid SH30 route, exact native mesh and restart")
    end
    core.log("action",("OWNED_RAIL_LIVE_NATIVE_PASS engine=%d fare=$%d operating_cost=$%d peak=%d bodies=%d"):
      format(engine,fare,after.running_expense,qa.peak,physical_count))
    core.request_shutdown("Native steam ride survived restart and earned its first fare",false,0)
    return
  end
  local g=S.corner_grid
  -- These inland services are not a flood test. Do not lower the whole
  -- seeded corridor to sea level while leaving its surrounding water:
  -- the stock flood loop can clear standard rail as soon as we start.
  local ground=1
  for z=1,g.depth+1 do
    for x=1,g.width+1 do g.levels[(z-1)*(g.width+1)+x]=bridge and ((x==17 or x==18) and 0 or 1) or ground end
  end
  for x=1,27 do
    S.tiles[id(x)]={h=ground,terrain="grass",variant=1}
  end
  for x=2,signal_free and 26 or 24 do
    if not bridge or x<15 or x>19 then
      local t=S.tiles[id(x)];t.owner=owner;t.rail_tracks=1;t.build="stock_rail"
    end
  end
  local c=Sim.company(S,owner)
  if wire_turnout then
    assert(electric and not bridge)
    S.tiles[id(14,11)]={h=ground,terrain="grass",variant=1,owner=owner,rail_tracks=2,build="stock_rail"}
    S.tiles[id(14)].rail_tracks=33
    S.tiles[id(14,9)]={h=ground,terrain="grass",variant=1}
    local apron=id(14,15)
    local i=(15-1)*(g.width+1)+14
    g.levels[i+1],g.levels[i+g.width+1]=ground+1,ground+1
    local T=dofile(mod_path.."/openttd/terrain.lua")
    assert(T.tile(g,14,15)==5)
    S.tiles[apron]={h=ground,terrain="hill",variant=1,owner=owner,rail_tracks=33,build="stock_rail"}
    local second=assert(api.electric_quote(owner,{apron},1))
    assert(second.price==136 and api.electric_commit(owner,second))
  end
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
  if turnout then
    S.tiles[depot]={h=ground,terrain="grass",variant=1}
    local builder=assert(api.rail_build)
    assert(builder.build(owner,assert(builder.quote_depot(owner,depot,1))))
    assert(S.tiles[id(16)].rail_tracks==21)
  else
    assert(api.trackworks.depot(S,owner,depot,2))
  end
  assert(api.trackworks.station(S,owner,id(11),id(12)))
  assert(api.trackworks.station(S,owner,id(22),id(24)))
  if isolated then
    for x=7,11 do S.tiles[id(x,6)]={owner=owner,build="stock_rail",rail_tracks=1,h=ground,terrain="grass",variant=1} end
    assert(Run.place_signal(S,owner,id(9,6),8,4))
  elseif not signal_free then assert(Run.place_signal(S,owner,id(10),0,4)) end
  local west,east=S.tiles[id(11)].rail_station_id,S.tiles[id(22)].rail_station_id
  S.sites[1].tile=id(10,13);S.sites[2].tile=id(24,13)
  for _,z in ipairs({7,8,12,13}) do
    for _,x in ipairs({8,9,10,11,12,21,22,23,24,25}) do
      local t=S.tiles[id(x,z)]
      t.terrain,t.h,t.build,t.owner,t.site,t.wood="grass",ground,nil,nil,nil,nil
      t.house,t.parcel,t.variant=true,"shop",2
    end
  end
  assert(not Owned.quote(S,owner,depot,{1,27}))
  if jubilee or sh or dmu or electric then
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
    local missing,why=Owned.quote(S,owner,depot,{engine,27})
    assert(not missing and why=="INCOMPATIBLE_DEPOT_RAIL",why)
    local line={}
    for x=2,24 do if x~=20 and (not bridge or x<15 or x>19) then line[#line+1]=id(x) end end
    local quote=assert(api.electric_quote(owner,line,1))
    assert(quote.price==((bridge and 17 or 22)+(wire_turnout and 1 or 0))*68)
    assert(api.electric_commit(owner,quote))
    if wire_turnout then
      assert(S.tiles[id(14)].rail_type==1 and S.tiles[id(14)].rail_tracks==33)
      local track=dofile(mod_path.."/openttd/rail_track.lua")
      local w=dofile(mod_path.."/rail_turnout_wire.lua")(Sim,track,dofile(mod_path.."/openttd/rail_wire_mask.lua")(track))
      assert(w.at(S,id(14),S.tiles[id(14)])==1,"Unpowered branch must not show an energized contact wire")
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{id(14,11)},1))))
      assert(w.at(S,id(14),S.tiles[id(14)])==33,"Powering the next tile must connect the second wire")
    end
    assert(S.tiles[id(20)].rail_type==nil and S.tiles[id(2)].rail_type==1)
    if not bridge then
      api.render.update({id(19)})
      assert(core.get_node({x=38,y=3,z=21}).name=="luanttd_core:rail_edge_pylon_2",
        "The gap must gain its temporary end pylon before it is powered")
    end
  end
  if dmu then
    local saved=core.show_formspec
    local ticket
    core.show_formspec=function(_,form,body) if form=="luanttd_core:rail_fleet" then ticket=body end end
    assert(api.owned_rail_ui.open({get_player_name=function() return owner end},id(2)))
    core.show_formspec=saved
    local button="purchase_"..kind
    assert(ticket and ticket:find(button,1,true) and ticket:find((2*seat_count).." seats",1,true))
    assert(ticket:find(button.."_coach",1,true) and ticket:find((2*seat_count+40).." seats",1,true))
    assert(not Owned.quote(S,owner,depot,{engine,27,27}))
  end
  local q=assert(Owned.quote(S,owner,depot,dmu and not coach and {engine} or {engine,27}))
  local initial_cash=c.cash
  local r
  if two_coaches then
    local function buy(id)
      return assert(Owned.commit(S,owner,assert(Owned.quote_part(S,owner,depot,id))))
    end
    r=buy(0)
    local a,b=buy(27),buy(27)
    r=assert(Owned.get(S,owner,r.id))
    assert(#r.parts==3 and r.parts[2].body_id==a.body_id and r.parts[3].body_id==b.body_id)
    cost=r.price
  else
    r=assert(Owned.commit(S,owner,q))
  end
  assert(r.price==cost and c.cash==initial_cash-r.price)
  if branch then
    S.tiles[id(25)]={owner=owner,rail_tracks=1,build="stock_rail",h=ground,terrain="grass",variant=1}
    -- Depot release now classifies the real signal block. A through
    -- station is a valid order even if not itself a PBS waiting point.
    local rail=api.trackworks
    local function loop(x,z,piece)
      local tile=id(x,z)
      if tile~=id(6) then S.tiles[tile]={h=ground,terrain="grass",variant=1} end
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
    if not bridge then
      api.render.update({id(20)})
      assert(core.get_node({x=38,y=3,z=21}).name~="luanttd_core:rail_edge_pylon_2",
        "Connecting the gap must remove the extra end pylon")
    end
    if bridge then
      assert(not Owned.start(S,owner,r.id,east,west),"an unelectrified bridge is not a powered route")
      bridge_wire()
    end
  end
  local ok,note=Owned.start(S,owner,r.id,east,west);assert(ok,note)
  local ledger=assert(api.vehicle_orders.rail,"Vehicle picker must mount the train orders adapter.")
  local data=assert(ledger.read(owner,r.id))
  assert(#data.items==2 and data.items[1].id==east and data.items[2].id==west)
  assert(not ledger.read("Unauthorised",r.id))
  local markup
  local show=core.show_formspec
  core.show_formspec=function(name,key,body)
    assert(name==owner and key=="luanttd_core:vehicle_details")
    markup=body
  end
  local opened,result=pcall(api.vehicle_ui.open,{get_player_name=function()return owner end},"rail",r.id)
  core.show_formspec=show
  assert(opened and result and type(markup)=="string" and markup:find("Available destinations",1,true)
    and markup:find("Skip to selected order",1,true))
  core.log("action","TRAIN_ORDER_PANEL_NATIVE_PASS renders a live train's real destinations and order tools")
  if signal_free and not isolated then assert(current().ordinary_unreserved and not next(S.stock_rail_dispatch.signals.records)) end
  if bridge then assert(current().bridge_collectors) end
  assert(current().stock_engine==engine and current().max_track_speed==vmax)
  local peak=0
  for _=1,100 do
    day()
    peak=math.max(peak,current().speed)
    local s=assert(Sim.rail_paid_status(S))
    local both=not dmu or (s.carrying_parts[1].onboard>0 and
      s.carrying_parts[physical_count].onboard>0 and (not coach or s.carrying_parts[2].onboard>0))
    if two_coaches then both=s.carrying_parts[1].onboard>0 and s.carrying_parts[2].onboard>0 end
    if s.loading and s.onboard>0 and both then
      if lookahead then forward_claims() end
      for i=1,physical_count do entity_at(current(),i,1) end
      if jubilee or sh or dmu then assert(peak>64,"Native source locomotive did not exceed the Kirby maximum") end
      local bill=assert(Owned.running(S,owner,r.id))
      assert(bill.running_expense>0 and bill.charged_running_ticks>0)
      S.rail_owned_native_qa={unit=r.id,quote=q,passengers=s.onboard,cash=c.cash,expense=c.expense,day=S.day,
        running_expense=bill.running_expense,cost_fp=bill.running_cost_fp,fraction=c.stock_money_fraction,
        charged_running_ticks=bill.charged_running_ticks,peak=peak,
        front=dmu and s.carrying_parts[1].onboard,rear=dmu and s.carrying_parts[physical_count].onboard,
        coach=coach and s.carrying_parts[2].onboard,exit_curve=turnout and choices[4],
        coach1=two_coaches and s.carrying_parts[1].onboard,coach2=two_coaches and s.carrying_parts[2].onboard,
        purchase_cost=r.price}
      if bridge then
        assert(evidence.before[id(17)],"No eastbound native contact across the bridge center")
        S.rail_owned_native_qa.fits=evidence.fits
        S.rail_owned_native_qa.cab_fits=evidence.cab_before[1] and evidence.cab_before[3]
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
