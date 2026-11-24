-- Appended exclusively to the disposable native Airport QA game.
local begun=false
local function heliport_scene(p)
  local owner=p:get_player_name()
  local cap=api.capabilities
  assert(cap.heliport and cap.air[253],"Complete native Heliport and Tricario media required")
  local function view(id)
    local x,z=Sim.xy(id)
    local _,h=api.terrain.tile(id)
    p:set_pos({x=x*2-.3,y=h+11,z=z*2-9})
    p:set_look_horizontal(0)
    p:set_look_vertical(.49)
    return x,z,h
  end
  local function read()
    return assert(OwnerCheckpoint.read())
  end
  local function route(saved)
    if not saved.airport_owned_runs then return end
    local _,run=next(saved.airport_owned_runs)
    local pad=run and saved.stock_small_airports[run.second]
    if pad then assert(pad.layout=="heliport" and pad.delta_z==60 and #pad.tiles==1) end
    return run,pad
  end
  local function wait_landing(pad_id,last,marker)
    local x,z,h=view(pad_id)
    local pad_pos={x=x*2+.125,y=h+8,z=z*2+.625}
    local function watch()
      local mesh=core.get_node({x=x*2,y=h+1,z=z*2})
      if mesh.name=="luanttd_core:heliport_0_0" then
        local run=route(read())
        assert(not run or run.phase~="blocked",run and run.failure)
        if run and run.arrivals>last then
          for _,ref in ipairs(core.get_objects_inside_radius(pad_pos,1.5)) do
            local e,at=ref:get_luaentity(),ref:get_pos()
            if at and e and e.name=="luanttd_core:stock_tricario_heli" and
               math.abs(at.y-pad_pos.y)<.12 and math.abs(at.x-pad_pos.x)<.31 and
               math.abs(at.z-pad_pos.z)<.27 then
              core.log("action",marker.." mounted one-tile roof, live Tricario at the stock pad height and new arrival")
              return
            end
          end
        end
      end
      core.after(.14,watch)
    end
    core.after(.16,watch)
  end
  if core.settings:get_bool("luanttd_qa_air_restart",false) then
    local run,pad=route(read())
    assert(run and pad and run.engine_id==253)
    wait_landing(pad.origin,run.arrivals,"PASS NATIVE HELIPORT RESTART")
    return
  end
  local h,pad
  local net=api.airfield.network
  for z=7,Sim.H-9 do
    for x=7,Sim.W-9 do
      local id=Sim.id(x,z)
      if not h and net.quote(S,owner,id,"country") then h=id end
      if h and Sim.distance(h,id)>=16 and Sim.distance(h,id)<=28 and net.quote(S,owner,id,"heliport") then
        pad=id;break
      end
    end
    if pad then break end
  end
  assert(h and pad,"No native test footprint")
  view(pad)
  assert(world.go_menu(p,"airfields"))
  local has=false
  for _,slot in ipairs(world.hotbar_layout(p)) do if slot==6 then has=true end end
  assert(has,"Heliport not accessible in Airfields hotbar")
  local function ask(query,accept)
    query.player=owner
    assert(authority.query(query,function(r) accept(r) end))
  end
  local function yes(query,accept)
    ask(query,function(r) assert(r.ok,query.kind..": "..tostring(r.why or r.value));accept(r) end)
  end
  local function transport(data,footprint,accept)
    yes({kind="transport_quote",request=data},function(q)
      assert(#q.value.tiles==footprint)
      yes({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},accept)
    end)
  end
  transport({mode="air",operation="build",layout="country",tile=h},12,function(a)
    transport({mode="air",operation="build",layout="heliport",tile=pad},1,function(b)
      local first,second=a.value.id,b.value.id
      ask({kind="depot",mode="air",depot=second},function(no)
        assert(not no.ok and tostring(no.why):match("does not have a hangar"))
        transport({mode="air",operation="buy",depot=first,engine=253},0,function(owned)
          yes({kind="depot",mode="air",depot=first},function(list)
            local found=false
            for _,row in ipairs(list.value.targets) do
              if row.id==second and row.label:match("^Heliport ") then found=true end
            end
            assert(found)
            yes({kind="command",command={kind="transport_start",mode="air",first=first,second=second,
                revision=list.revision or owned.revision}},function()
              wait_landing(pad,0,"PASS NATIVE HELIPORT:")
            end)
          end)
        end)
      end)
    end)
  end)
end
core.after(.22,function()
  local function begin()
    local p=core.get_player_by_name("CityReview")
    if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
      if not begun then begun=true;heliport_scene(p) end
    else core.after(.22,begin) end
  end
  begin()
end)
