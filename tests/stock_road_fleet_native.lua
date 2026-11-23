-- Production worker road commands and native mesh projection on generated terrain.
local road_native_started=false
local function road_native_scene(viewer)
  local owner=viewer:get_player_name()
  local models={
    {engine="foster_mk2_bus",stem="stock_foster_mk2_bus",cargo="passenger",price=8750},
    {engine="wood_moreland",stem="stock_moreland_wood_truck",cargo="wood",price=8039},
    {engine="grain_goss",stem="stock_goss_grain_truck",cargo="grain",price=7820},
    {engine="livestock_foster",stem="stock_foster_livestock_van",cargo="livestock",price=7656},
  }
  local profile=core.settings:get("luanttd_qa_fleet_wave")
  local motion_test=profile=="worker_motion" or profile=="worker_motion_baseline"
  local end_tile=motion_test and 22 or 10
  if profile=="mid_industry" then models={
    {engine="coal_uhl",stem="stock_uhl_coal_truck",cargo="coal",price=7000},
    {engine="mail_reynard",stem="stock_reynard_mail_truck",cargo="mail",price=7382},
    {engine="oil_foster",stem="stock_foster_oil_tanker",cargo="oil",price=7656},
  } elseif profile=="late_industry" then models={
    {engine="coal_dw",stem="stock_dw_coal_truck",cargo="coal",price=7546},
    {engine="goods_goss",stem="stock_goss_goods_truck",cargo="goods",price=7656},
    {engine="oil_perry",stem="stock_perry_oil_tanker",cargo="oil",price=8203},
    {engine="mail_perry",stem="stock_perry_mail_truck",cargo="mail",price=7929},
  } elseif profile=="early_mail" then models={
    {engine="mail_mps",stem="stock_mps_mail_truck",cargo="mail",price=6289},
  } elseif motion_test then
    models={models[1]}
  end
  local sites={}
  for j=4,Sim.H-4 do
    for i=4,Sim.W-end_tile-2 do
      local ready,level=true,nil
      for _,site in ipairs(sites) do
        if math.abs(site.x-i)+math.abs(site.z-j)<20 then ready=false;break end
      end
      if ready then
        for dz=0,1 do for dx=0,end_tile do
          local id=Sim.id(i+dx,j+dz)
          local t=S.tiles[id]
          local slope,height=api.terrain.tile(id)
          if slope~=0 or level and height~=level or t.wood or t.house or t.site or t.owner or
              t.stock_industry or t.stock_landmark or t.stock_void or t.terrain=="water" or t.build then ready=false end
          level=height
        end end
      end
      if ready then
        sites[#sites+1]={x=i,z=j,h=level}
        if #sites==#models then break end
      end
    end
    if #sites==#models then break end
  end
  assert(#sites==#models,"Generated terrain has no stock road previews")
  local function ask(req,callback)
    req.player=owner
    local ok,why=authority.query(req,function(r)
      assert(r.ok,(req.request and req.request.tool or req.command and req.command.kind or req.kind)..": "..tostring(r.why))
      callback(r)
    end)
    assert(ok,why)
  end
  local revision
  local function command(c,cb)
    c.revision=revision
    ask({kind="command",command=c},function(r) revision=r.revision;cb(r) end)
  end
  local motion_probe
  if motion_test then
    core.register_globalstep(function()
      if motion_probe then motion_probe() end
    end)
  end
  local function run(i)
    local m,site=models[i],sites[i]
    if not m then
      core.log("action","PASS NATIVE ROAD FLEET: ordinary worker offered, purchased, routed and projected all installed "..(profile or "farm/timber").." vehicles")
      return
    end
    local x,z,h=site.x,site.z,site.h
    local function tile(u,v) return assert(Sim.id(x+u,z+v)) end
    viewer:set_pos({x=2*x+end_tile,y=h+10,z=2*z-8})
    viewer:set_look_horizontal(0);viewer:set_look_vertical(.61)
    local depot,a,b=tile(5,1),tile(2,0),tile(end_tile-2,0)
    local stop=m.cargo=="passenger" and "road_station" or "truck_stop"
    local tasks={
      {tool="drag",first=tile(0,0),last=tile(end_tile,0),axis=0,start_half=false,end_half=true},
      {tool="road_depot",first=depot},
      {tool=stop,first=a},{tool=stop,first=b},
    }
    local function observe()
      for _,ref in ipairs(core.get_objects_inside_radius({x=2*x+end_tile,y=h+1,z=2*z},end_tile+6)) do
        local actor,p=ref:get_luaentity(),ref:get_pos()
        local mesh=ref:get_properties().mesh
        if actor and p and math.abs(p.z-2*z)<1 and actor.name=="luanttd_core:vehicle_"..m.engine and
            (mesh=="bl_"..m.stem..".obj" or mesh=="bl_"..m.stem.."_loaded.obj") then
          core.log("action",("Verified stock road actor %s on the running line at %.2f, %.2f"):format(m.engine,p.x,p.z))
          if motion_test then
            local positions={}
            local attempts=0
            motion_probe=function()
              attempts=attempts+1
              local v=ref:get_pos()
              assert(v and attempts<350,"No sustained worker road movement was observed")
              -- A single direction of travel on the through lane,
              -- excluding stationary schedules and reverse shunts.
              if math.abs(v.z-2*z)>=1 or v.x<=2*x+1 or v.x>=2*x+2*end_tile-1 then
                positions={};return
              end
              positions[#positions+1]=v.x
              if #positions<12 then return end
              if #positions>12 then table.remove(positions,1) end
              local same,largest,travel=0,0,0
              for k=2,#positions do
                local dx=math.abs(positions[k]-positions[k-1])
                if dx<.002 then same=same+1 end
                largest=math.max(largest,dx);travel=travel+dx
              end
              local span=math.abs(positions[#positions]-positions[1])
              if span<2 or travel>span+.015 then return end
              local ratio=same/(#positions-1)
              core.log("action",("WORKER_ROAD_MOTION native frames=%d repeat_ratio=%.3f max_sample_jump=%.3f traverse=%.3f"):format(
                #positions,ratio,largest,span))
              if profile=="worker_motion" then
                assert(ratio<.30,"Road actor still pauses during a moving straight run")
              end
              motion_probe=nil
              core.after(.35,run,i+1)
            end
          else core.after(.35,run,i+1) end
          return
        end
      end
      core.after(.1,observe)
    end
    local function shop()
      ask({kind="depot",mode="road",depot=depot},function(q)
        revision=q.revision
        local selected
        for _,offer in ipairs(q.value.offers) do
          if offer.request.engine==m.engine then
            assert(offer.price==m.price and offer.request.cargo==m.cargo);selected=offer.request
          end
        end
        assert(selected,"Normal road depot did not expose "..m.engine)
        command(selected,function(r)
          local id=assert(r.value)
          local disk=assert(OwnerCheckpoint.read())
          command({kind="road_order_add",vehicle=id,station=assert(disk.tiles[a].station)},function()
            command({kind="road_order_add",vehicle=id,station=assert(disk.tiles[b].station)},function()
              command({kind="road_toggle",vehicle=id},observe)
            end)
          end)
        end)
      end)
    end
    local function construction(n)
      local req=tasks[n]
      if not req then shop();return end
      ask({kind="road_quote",request=req},function(q)
        revision=q.revision
        command({kind="road_commit",request=req,quote=q.value},function() construction(n+1) end)
      end)
    end
    construction(1)
  end
  run(1)
end
local function road_native_begin()
  local p=core.get_player_by_name("RoadReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
    if not road_native_started then road_native_started=true;road_native_scene(p) end
  else core.after(.22,road_native_begin) end
end
core.after(.22,road_native_begin)
