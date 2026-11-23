-- Appended to a disposable ordinary Linux world; all authority is native.
local started=false
local stock=tonumber(core.settings:get("luanttd_qa_airframe")) or 226
local models={
  [220]={visual="bakewell_luckett_lb8",price=49218},[228]={visual="darwin_300",price=82031},
  [217]={visual="ffp_dart",price=43750},[225]={visual="yate_yac_1_11",price=43750},[226]={visual="darwin_100",price=49218},
}
local model=assert(models[stock])
local function scene(viewer)
  assert(api.capabilities.city_airport and api.capabilities.air[stock],"Complete stock media required")
  local owner=viewer:get_player_name()
  local positions={}
  for v=3,Sim.H-9 do
    for u=3,Sim.W-9 do
      local enabled,level=true,nil
      for dz=0,5 do for dx=0,5 do
        local id=Sim.id(u+dx,v+dz)
        local t=S.tiles[id]
        local slope,h=api.terrain.tile(id)
        if slope~=0 or level and h~=level or t.wood or t.house or t.site or t.owner or t.stock_industry or
            t.stock_landmark or t.stock_void or t.terrain=="water" or t.build then enabled=false end
        level=h
      end end
      if enabled and (#positions==0 or math.abs(positions[1].x-u)+math.abs(positions[1].z-v)>=25) then
        positions[#positions+1]={x=u,z=v,h=level,id=Sim.id(u,v)}
        if #positions==2 then break end
      end
    end
    if #positions==2 then break end
  end
  assert(#positions==2)
  local focus=positions[1]
  viewer:set_pos({x=2*focus.x+5,y=focus.h+9,z=2*focus.z-10})
  viewer:set_look_horizontal(0)
  viewer:set_look_vertical(.55)
  assert(world.go_menu(viewer,"airfields"))
  local has=false
  for _,slot in ipairs(world.hotbar_layout(viewer)) do if slot==4 then has=true end end
  assert(has,"The airport has no native hotbar item")
  local function ask(value,cb)
    value.player=owner
    local yes,why=authority.query(value,function(r)
      assert(r.ok,value.kind..": "..tostring(r.why or r.value));cb(r)
    end)
    assert(yes,why)
  end
  local function use(req,cb)
    ask({kind="transport_quote",request=req},function(q)
      if req.operation=="build" then assert(#q.value.tiles==36 and q.value.cost==21600) end
      ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},cb)
    end)
  end
  local function observe()
    local paint=core.get_node({x=focus.x*2+10,y=focus.h+1,z=focus.z*2})
    if paint.name~="luanttd_core:city_airport_5_0" then core.after(.18,observe);return end
    for _,ref in ipairs(core.get_objects_inside_radius({x=focus.x*2+5,y=focus.h+2,z=focus.z*2+5},12)) do
      local actor=ref:get_luaentity()
      local pos=ref:get_pos()
      if actor and actor.name=="luanttd_core:stock_"..model.visual and pos.z>focus.z*2+2.6 and pos.y<focus.h+1.1 then
        assert(ref:get_properties().mesh=="bl_stock_"..model.visual..".obj")
        core.log("action","PASS NATIVE CITY: worker built and painted 36 stock tiles; taxi by airframe #"..stock)
        return
      end
    end
    core.after(.18,observe)
  end
  local loans=stock==228 and 3 or 0
  local function airports()
    use({mode="air",operation="build",layout="city",tile=positions[1].id},function(one)
      use({mode="air",operation="build",layout="city",tile=positions[2].id},function(two)
        local first,second=one.value.id,two.value.id
        ask({kind="depot",mode="air",depot=first},function(q)
          local chosen
          for _,entry in ipairs(q.value.offers) do if entry.request.engine==stock then chosen=entry end end
          assert(chosen and chosen.price==model.price)
          use(chosen.request,function(bought)
            ask({kind="command",command={kind="transport_start",mode="air",first=first,second=second,
                revision=bought.revision}},function()
              local disk=assert(OwnerCheckpoint.read())
              assert(disk.stock_small_airports[first].layout=="city" and disk.stock_owned_air_fleet[bought.value.id].stock_id==stock)
              assert(disk.companies[owner].cash==100000+loans*10000-43200-model.price)
              core.after(.22,observe)
            end)
          end)
        end)
      end)
    end)
  end
  local function lend(left)
    if left==0 then airports();return end
    ask({kind="company"},function(q)
      ask({kind="command",command={kind="company_loan",amount=10000,revision=q.revision}},function()
        lend(left-1)
      end)
    end)
  end
  lend(loans)
end
local function begin()
  local p=core.get_player_by_name("CityReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
    if not started then started=true;scene(p) end
  else core.after(.22,begin) end
end
core.after(.22,begin)
