-- Test-only observer installed in the temporary game copy; never ship in mods/.
-- Only /qa_aim changes anything, and it changes camera pose, not game state.
return function(api,qa_ui)
  local Sim,S=api.Sim,api.s
  local username="NativeQA"
  local leopard=core.settings:get_bool("bayline_native_leopard",false)
  if leopard and S.day<14*360 then S.day=14*360 end
  local road_visual=S.stock_bus_market and "luanttd_core:vehicle_foster_bus" or
    leopard and "luanttd_core:vehicle_leopard_bus" or "luanttd_core:vehicle_bus"
  local trace=core.get_worldpath().."/native.json"
  local terrain_build=core.settings:get_bool("bayline_bridge_construction_preview",false)
  local Terrain=terrain_build and dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  local form,buttons,aim,last_fields=nil,{},nil,nil
  local panel
  local extended={} -- shared upvalue under Lua 5.1's per-function limit
  if core.settings:get_bool("bayline_native_water_effects",false) then
    core.set_timeofday(.35)
    core.register_chatcommand("qa_water_coast",{func=function(n)
      local p=core.get_player_by_name(n)
      if n~=username or not p then return false end
      core.emerge_area({x=-36,y=-1,z=-5},{x=48,y=16,z=88},function(_,_,left)
        if left~=0 then return end
        core.after(0,function()
          local who=core.get_player_by_name(n)
          if not who then return end
          who:set_pos({x=7,y=7,z=18})
          who:set_look_horizontal(.18);who:set_look_vertical(.23)
        end)
      end)
      return true
    end})
    function extended.water_fx(player)
      if not player then return end
      local plain=core.get_node({x=7,y=0,z=7}).name
      local river=core.get_node({x=30,y=1,z=36}).name
      local slope=core.get_node({x=18,y=1,z=36}).name
      local ocean=core.registered_nodes[plain] or {}
      local flat=core.registered_nodes[river] or {}
      local graded=core.registered_nodes[slope] or {}
      local anim=graded.tiles and graded.tiles[1] and graded.tiles[1].animation
      return {plain=plain,river=river,slope=slope,waving=ocean.waving,
        river_waving=flat.waving,fall_waving=graded.waving,fall_mesh=graded.mesh,
        fall_animation=anim and anim.type,
        alpha=ocean.use_texture_alpha,fog=player:get_sky(true).fog}
    end
  end
  if core.settings:get_bool("bayline_native_stock_water_gui",false) then
    core.register_chatcommand("qa_freeze_coast", {func=function(n)
      if n~=username or not api.generated_world then return false end
      S.speed=0
      return true,"QA paused only to separate the clear command from later flooding."
    end})
    function extended.clear_water()
      local t=S.tiles[Sim.id(2,2)]
      return {terrain=t.terrain,paused=S.speed==0,shore=t.coastal_water,owner=t.owner}
    end
  end
  if core.settings:get_bool("bayline_native_clear_area",false) then
    local cells={{33,15},{33,14},{34,14},{35,14},{36,14},{37,14},{38,14},{40,15}}
    local ids={}
    core.register_chatcommand("qa_demolition_fixture",{params="[diag]",func=function(n,arg)
      if n~=username then return false end
      local c=Sim.company(S,n)
      if arg=="diag" then
        c.cash,c.clear_limit=1000,65537
        return true,"One clear remains."
      end
      if #ids>0 then return false end
      S.speed=0
      c.cash,c.clear_limit=250,65536*100+1
      for i,xy in ipairs(cells) do
        local id=assert(Sim.id(xy[1],xy[2]))
        local t=S.tiles[id]
        assert(t and not t.house and not t.build and not t.site and not t.ship and not t.stock_industry)
        t.build,t.road_bits,t.owner,t.wood="road",10,i==3 and "OtherCompany" or n,nil
        ids[#ids+1]=id
      end
      api.render.update(ids)
      return true,"Prepared priced fixtures; use the normal native Bulldozer."
    end})
    function extended.demolition()
      if #ids==0 then return end
      local c=Sim.company(S,username)
      local u={limit=c.clear_limit,on={},height={},owner={}}
      for i,id in ipairs(ids) do
        local t=S.tiles[id]
        u.on[i]=t.build=="road"
        u.owner[i]=t.owner or "-"
        u.height[i]=t.h+.5
      end
      local p=core.get_player_by_name(username)
      if p then
        local a=qa_ui.anchor(p)
        u.anchor=a or false
        u.status=select(2,qa_ui.world_status(p,nil,false))
        u.aux=p:get_player_control().aux1
        u.dig=p:get_player_control().dig
      end
      return u
    end
  end
  if core.settings:get_bool("bayline_native_road_bend",false) then
    local a,b,path
    for z=9,19 do
      for x=28,40 do
        local start,finish=Sim.id(x,z),Sim.id(x+4,z+3)
        local q=Sim.autoroad_bend_plan(S,username,start,finish)
        local flat=q and q.cost==876 and #q.changes==8
        if flat then
          for _,id in ipairs(q.path) do
            local mask,base=api.terrain.tile(id)
            if mask~=0 or base~=1 or Sim.road_bits(S,id)~=0 then flat=false;break end
          end
        end
        if flat then a,b,path=start,finish,q.path;break end
      end
      if path then break end
    end
    assert(path,"No flat open road bend found in coastal test circuit")
    function extended.road_bend(p)
      if not p then return end
      local masks,link={},0
      for i,id in ipairs(path) do
        masks[i]=Sim.road_bits(S,id)
        if i>1 then
          for d=1,4 do
            if Sim.adjacent(path[i-1],d)==id and Sim.road_connected(S,path[i-1],d) then link=link+1 end
          end
        end
      end
      local tile,hit=api.world.target(p)
      local _,valid,hint
      if tile then _,valid,hint=qa_ui.preview(p,tile,hit) end
      local x,z=Sim.xy(a)
      local u,v=Sim.xy(b)
      local elbow=core.get_node({x=u*2,y=1,z=z*2}).name
      return {hint=hint,valid=valid,link=link,masks=masks,anchor=qa_ui.anchor(p) or false,
        a={x,z},b={u,v},elbow=elbow,aux=p:get_player_control().aux1,stock=Sim.road_bits(S,Sim.id(x,v))}
    end
  end
  if core.settings:get_bool("bayline_native_crossing_connect",false) then
    local g
    core.register_chatcommand("qa_existing_crossing", {func=function(n)
      if n~=username or g then return false end
      local from,a,b=Sim.id(11,12),Sim.id(13,12),Sim.id(14,12)
      assert(Sim.build(S,n,"road",Sim.line(from,a)))
      assert(Sim.road_bits(S,a)==8)
      local rail=assert(api.rail_build.quote_track(n,b,b,1,false))
      assert(api.rail_build.build(n,rail))
      assert(api.crossing_commit(n,assert(api.crossing_quote(n,b,{kind="road",pieces=10}))))
      local record=S.tiles[b].level_crossing
      g={a=a,b=b,state=core.serialize(record)}
      api.render.update({from,Sim.id(12,12),a,b})
      return true,"Existing crossing and adjoining half-road seeded for physical input QA."
    end})
    function extended.existing_crossing()
      if not g then return end
      local r=S.tiles[g.b].level_crossing
      local node=core.get_node({x=28,y=r.top+1,z=24})
      local p=core.get_player_by_name(username)
      return {road=Sim.road_bits(S,g.a),connected=Sim.road_connected(S,g.a,2),
        same=core.serialize(r)==g.state,mesh=node.name,anchor=p and (qa_ui.anchor(p) or false)}
    end
  end
  if api.electric_tools then
    function extended.electric(n)
      local r={available=api.electric_available(n),year=Sim.date(S,0),meshes={},bridges={}}
      for _,span in pairs(S.stock_rail_spans or {}) do
        if span.owner==n and span.kind=="bridge" then
          local x,z=Sim.xy(span.start)
          local mx,mz=Sim.xy(span.middle[math.ceil(#span.middle/2)] or span.start)
          local node=core.get_node({x=2*mx,y=span.deck+1,z=2*mz})
          r.bridges[("%d,%d"):format(x,z)]={type=span.railtype,deck=span.deck,
            level=node.name,length=span.total_length}
        end
      end
      local d=S.stock_rail_dispatch
      for _,run in ipairs(d and d.runs or {}) do
        if run.owner==n and (run.stock_engine==23 or run.stock_engine==24) then
          r.engine,r.steps,r.phase,r.speed=run.stock_engine,run.stock_steps,run.phase,run.speed
          r.arrivals=run.shuttle and run.shuttle.arrivals
          r.traction=run.traction_railtypes and run.traction_railtypes[1] and not run.traction_railtypes[0]
          r.sprung=run.bridge_collectors
        end
      end
      local p=core.get_player_by_name(n)
      if p then
        for _,obj in ipairs(core.get_objects_inside_radius(p:get_pos(),45)) do
          local e=obj:get_luaentity()
          if e and (e.name:find("^luanttd_core:dispatch_sh_[34]0") or e.name=="luanttd_core:dispatch_wagon") then
            r.meshes[#r.meshes+1]=obj:get_properties().mesh
            if e.name:sub(-10)=="_collector" then
              local pos=obj:get_pos()
              r.collector={x=pos.x,y=pos.y,z=pos.z,scale=obj:get_properties().visual_size.y}
            end
          end
        end
      end
      return r
    end
  end
  if core.settings:get_bool("bayline_rail_oil_preview",false) then
    extended.rail_oil=dofile(core.get_modpath("luanttd_core").."/native_rail_oil_probe.lua")(api,username,qa_ui)
  end
  if core.settings:get_bool("bayline_stock_coastal_flood",false) and api.coastal_flood_tools then
    extended.coast=dofile(core.get_modpath("luanttd_core").."/native_coastal_probe.lua")(api,username)
  end
  if S.qa_coastal then
    function extended.starter(n)
      local ghost={}
      local player=core.get_player_by_name(n)
      if player then
        for _,obj in ipairs(core.get_objects_inside_radius(player:get_pos(),55)) do
          local e=obj:get_luaentity()
          if e and e.name=="luanttd_core:rail_selector" then
            local pos=obj:get_pos()
            ghost[#ghost+1]={x=pos.x,z=pos.z,mesh=obj:get_properties().mesh}
          end
        end
      end
      local b
      for _,p in pairs(S.stock_road_bridges or {}) do
        if p.start==Sim.id(21,13) and p["end"]==Sim.id(27,13) then
          b={cost=p.price,span=p.total_length or #p.middle+2,style=p.style}
        end
      end
      return {bridge=b,ghost=ghost,units=api.rail_owned and api.rail_owned.list(S,n) or {}}
    end
  end
  if S.stock_generated_profile then
    function extended.generated(n)
      local p=S.stock_generated_profile
      local result={width=Sim.W,depth=Sim.H,style=p.terrain,towns={},road=0,house=0,visible_house=0,void=0,
        forest_tiles=0,forest_stems=0,forest_shore=0,visible_tree=0,industries={},visible_industry=0,
        wood_received=0,coal_received=0,freight_ready=api.freight_tools,timber_ready=api.timber_tools,
        route_heights={},landmarks={},mixed=p.timber_generation}
      local center=S.sites[1]
      if not center then return result end
      for _,town in ipairs(S.sites) do
        local x,z=Sim.xy(town.tile)
        if town.kind=="town" then
          result.towns[#result.towns+1]={name=town.name,population=town.population,x=x,z=z,h=S.tiles[town.tile].h}
        end
      end
      local c=core.get_player_by_name(n)
      if p.width==128 then
        local y={}
        for _,x in ipairs({102,103,110,111}) do y[tostring(x)]=S.tiles[Sim.id(x,70)].h end
        local clock=S.passenger_house_clock
        result.scale={industry=#p.industries,head=p.river_rng_cursor,log_x=clock.log_x,log_y=clock.log_y,
          tick=clock.counter,heights=y}
      end
      if p.river_stats then
        local q=Sim.id(25,20)
        local lock=S.stock_ship_locks and S.stock_ship_locks[q]
        local water=core.get_node_or_nil({x=30,y=1,z=36})
        local middle=core.get_node_or_nil({x=50,y=2,z=40})
        result.river={stats=p.river_stats,cursor=p.river_rng_cursor,
          flat=water and water.name,middle=middle and middle.name,
          lock=lock and {tiles=#lock.tiles,owner=lock.owner},typed=S.tiles[q].water_class}
      end
      for _,p in ipairs(p.industries or {}) do
        local registry=p.chain=="timber" and S.stock_timber_industries or S.stock_coal_industries
        local ind=registry[p.industry]
        local site=S.sites[ind.site]
        result.industries[#result.industries+1]={kind=p.kind,id=ind.id,x=ind.x+1,z=ind.z+1,name=site.name}
        result.coal_received=result.coal_received+(site.received.coal or 0)
        result.wood_received=result.wood_received+(ind.wood_received or 0)
      end
      for _,pt in ipairs(p.timber_generation and {{25,44},{47,44},{25,45},{30,45},{30,44},
          {47,46},{46,46},{46,44},{45,44},{26,44},{32,43}} or
          {{29,26},{29,45},{28,26},{28,30},{29,30},{28,45},{28,41},{29,41},{29,43},{29,28},{30,35}}) do
        local x,z=pt[1],pt[2]
        result.route_heights[x..","..z]=S.tiles[Sim.id(x,z)].h
      end
      for id,t in ipairs(S.tiles) do
        if t.road_town then result.road=result.road+1 end
        if t.stock_void then result.void=result.void+1 end
        local x,z=Sim.xy(id)
        if t.stock_landmark then
          local q=t.stock_landmark
          local n=c and core.get_node_or_nil({x=x*2,y=t.h+1,z=z*2})
          local name=n and n.name or nil
          result.landmarks[#result.landmarks+1]={x=x,z=z,h=t.h,kind=q.kind,
            visible=name=="luanttd_core:stock_"..q.kind}
        end
        if c and t.stock_industry then
          local node=core.get_node_or_nil({x=x*2,y=t.h+1,z=z*2})
          if node and (node.name:find("coal_mine_0_",1,true) or node.name:find("power_station_",1,true)
              or node.name:find("sawmill_0_",1,true) or node.name:find("forest_0_",1,true)) then
            result.visible_industry=result.visible_industry+1
          end
        end
        if type(t.wood)=="table" then
          result.forest_tiles=result.forest_tiles+1
          result.forest_stems=result.forest_stems+t.wood.count
          if t.coastal_water then result.forest_shore=result.forest_shore+1 end
          if c then
            for dz=0,1 do for dx=0,1 do
              local node=core.get_node_or_nil({x=x*2+dx,y=t.h+2,z=z*2+dz})
              if node and node.name:find("stock_forest_",1,true) then result.visible_tree=result.visible_tree+1 end
            end end
          end
        end
        if t.house then
          result.house=result.house+1
          local node=c and core.get_node_or_nil({x=x*2,y=t.h+1,z=z*2})
          if node and (node.name:find("scenery_house",1,true) or node.name:find("town_shop",1,true)
            or node.name:find("house_build",1,true)) then result.visible_house=result.visible_house+1 end
        end
        if c and t.road_town==center.id and not result.stop and Sim.distance(id,center.tile)<=3 and
            Sim.plan(S,n,"road_station",{id}) then
          result.stop={x=x,z=z,h=t.h}
        end
      end
      return result
    end
  end
  function extended.install_farm()
    if not core.settings:get_bool("bayline_road_farm_preview",false) then return end
    S.qa_farm=S.qa_farm or {}
    local q=S.qa_farm
    if not q.started then S.speed=0 end
    core.register_chatcommand("qa_farm",{func=function(n,mode)
      if n~=username then return false end
      if mode=="go" then q.started=true;S.speed=1;api.save();return true end
      local p=core.get_player_by_name(n)
      if not p then return false end
      local target=mode=="factory" and {x=34,y=.6,z=33} or {x=26.5,y=.6,z=5}
      local ox,oy,oz=-4,4.8,9.5
      if mode=="grain" and q.loaded then
        target=q.loaded.pos
        ox,oy,oz=-1.04,1.10,2.30
      end
      local x,y,z=target.x+ox,target.y+oy,target.z+oz
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-target.x,target.z-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-target.y,
        math.sqrt((x-target.x)^2+(z-target.z)^2)))
      q.framed=mode
      return true
    end})
    function extended.farm(n)
      local a,b=S.stock_farm_industries[8192],S.stock_farm_industries[8193]
      local c=S.companies[n]
      local out={ready=api.farm_tools,fields=0,mesh={},fences=0,vehicles={},receipts=b.received or {},streets={},
        tick=S.stock_load_tick,house=S.passenger_house_clock and S.passenger_house_clock.counter,
        company_paid=c and c.paid_units,company_money=c and c.revenue,loaded=q.loaded,van=q.van,framed=q.framed}
      local function model(at)
        local id=Sim.id(at[1],at[2])
        local _,base=api.terrain.tile(id)
        return core.get_node_or_nil({x=at[1]*2,y=base+1,z=at[2]*2})
      end
      out.mesh.farm=(model({12,1}) or {}).name
      out.mesh.factory=(model({15,16}) or {}).name
      for id,t in ipairs(S.tiles) do
        if t.build=="road" or t.road_town or t.station then
          local x,z=Sim.xy(id)
          if x>=11 and x<=20 and z>=4 and z<=20 then out.streets[x..","..z]=t.build or "road" end
        end
      end
      for id in pairs(S.stock_farm_fields) do
        local r=api.farm_world.field(S,id)
        if r then out.fields=out.fields+1 end
      end
      local p=core.get_player_by_name(n)
      if p then
        for _,e in ipairs(core.get_objects_inside_radius(p:get_pos(),48)) do
          local lua=e:get_luaentity()
          if lua and lua.name:match("^luanttd_core:farm_fence_") then out.fences=out.fences+1 end
        end
      end
      for id,v in pairs(S.fleet) do if v.owner==n then
        out.vehicles[v.engine]={id=id,units=v.units,cash=v.revenue,expense=v.expense,paid=v.delivered,
          last=v.last_fare,orders=#v.orders,active=v.running}
        local here=Sim.position(S,v)
        if here and (v.engine=="grain_truck" and not q.loaded and v.units>=10 or v.engine=="livestock_van" and not q.van and v.units>0) then
          local x,z=Sim.xy(here)
          for _,obj in ipairs(core.get_objects_inside_radius({x=x*2+.5,y=.52,z=z*2+.5},5)) do
            local lua=obj:get_luaentity()
            local prop=obj:get_properties()
            if lua and lua.name=="luanttd_core:vehicle_"..v.engine then
              if v.engine=="grain_truck" and prop.mesh=="bl_hereford_grain_truck_loaded.obj" then
                q.loaded={mesh=prop.mesh,pos=obj:get_pos(),units=v.units,tick=S.stock_load_tick}
                out.loaded=q.loaded;S.speed=0;api.save()
              elseif v.engine=="livestock_van" and prop.mesh=="bl_talbott_livestock_van.obj" then
                q.van={mesh=prop.mesh,pos=obj:get_pos(),units=v.units,tick=S.stock_load_tick}
                out.van=q.van
              end
            end
          end
        end
      end end
      return out
    end
  end
  extended.install_farm()
  if core.settings:get_bool("bayline_road_oil_preview",false) and not extended.rail_oil then
    S.qa_oil=S.qa_oil or {}
    local q=S.qa_oil
    if not q.started then S.speed=0 end
    core.register_chatcommand("qa_oil",{func=function(name,mode)
      if name~=username then return false end
      if mode=="go" then q.started=true;S.speed=1;api.save();return true end
      local p=core.get_player_by_name(name)
      if not p then return false end
      local target=mode=="refinery" and {x=33.7,y=.6,z=36.8} or {x=23.6,y=.55,z=5.65}
      local dx,dy,dz=-5.2,5.8,8.0
      if mode=="loaded" and q.loaded then target=q.loaded.pos;dx,dy,dz=-1.6,1.42,2.85 end
      p:set_pos({x=target.x+dx,y=target.y+dy,z=target.z+dz})
      p:set_look_horizontal(math.atan2(dx,-dz))
      p:set_look_vertical(math.atan2(dy+p:get_properties().eye_height,math.sqrt(dx*dx+dz*dz)))
      q.framed=mode
      return true
    end})
    function extended.oil(n)
      local c=S.companies[n]
      local refinery=S.stock_oil_industries[0x3001]
      local out={ready=api.oil_tools,framed=q.framed,loaded=q.loaded,stores={},working={},roads={},
        house=S.passenger_house_clock and S.passenger_house_clock.counter,tick=S.stock_load_tick,
        money=c and c.revenue,paid=c and c.paid_units,crude=refinery.received and refinery.received.oil or 0,
        output=refinery.produced[1].waiting}
      local function model(x,z)
        local _,level=api.terrain.tile(Sim.id(x,z))
        local t=core.get_node_or_nil({x=2*x,y=level+1,z=2*z})
        return t and t.name
      end
      out.stores.wells=model(11,2)
      out.stores.refinery=model(15,17)
      out.stores.refinery_gate=model(16,17)
      out.stores.refinery_hole=model(18,17)
      for id,t in ipairs(S.tiles) do
        if t.build=="road" or t.road_town or t.station then
          local x,z=Sim.xy(id)
          if x>=11 and x<=19 and z>=4 and z<=18 then out.roads[x..","..z]=t.build or "road" end
        end
      end
      for id,v in pairs(S.fleet) do if v.owner==n then
        out.working[v.engine]={id=id,units=v.units,cash=v.revenue,expense=v.expense,
          paid=v.delivered,last=v.last_fare,orders=#v.orders,active=v.running}
        if v.engine=="oil_tanker" and not q.loaded and v.units>=5 and Sim.position(S,v) then
          local x,z=Sim.xy(Sim.position(S,v))
          for _,o in ipairs(core.get_objects_inside_radius({x=2*x+.5,y=.52,z=2*z+.5},4)) do
            local e=o:get_luaentity()
            if e and e.name=="luanttd_core:vehicle_oil_tanker" and o:get_properties().mesh=="bl_witcombe_oil_tanker.obj" then
              q.loaded={mesh=o:get_properties().mesh,pos=o:get_pos(),units=v.units,tick=S.stock_load_tick}
              out.loaded=q.loaded;S.speed=0;api.save()
              break
            end
          end
        end
      end end
      return out
    end
  end
  if core.settings:get_bool("bayline_native_shared_orders",false) then
    function extended.shared_orders(name)
      local result={}
      for id,v in pairs(S.fleet) do if v.owner==name then
        local members=Sim.road_order_members(S,id)
        result["v"..id]={group=v.order_group,member_count=#members,orders=v.orders,
          index=v.index,paid=v.delivered,active=v.running,
          same=#members<=1 or v.orders==members[1].orders}
      end end
      return result
    end
  end
  if core.settings:get_bool("bayline_native_road_faults",false) then
    S.qa_road_fault=S.qa_road_fault or {}
    local q=S.qa_road_fault
    core.register_chatcommand("qa_road_fault",{func=function(name,mode)
      if name~=username then return false end
      if mode=="resume" and q.first then S.speed=1;return true end
      local v=S.fleet[1]
      if mode=="smoke" and v and Sim.position(S,v) then
        local x,z=Sim.xy(Sim.position(S,v))
        for _,o in ipairs(core.get_objects_inside_radius({x=2*x+.5,y=.52,z=2*z+.5},4)) do
          local e=o:get_luaentity()
          if e and e.name=="luanttd_core:vehicle_foster_bus" then
            local pos=o:get_pos();local p=core.get_player_by_name(name)
            local dx,dy,dz=-1.5,1.6,2.36
            p:set_pos({x=pos.x+dx,y=pos.y+dy,z=pos.z+dz})
            p:set_look_horizontal(math.atan2(dx,-dz))
            p:set_look_vertical(math.atan2(dy+p:get_properties().eye_height-.25,math.sqrt(dx*dx+dz*dz)))
            q.smoke_framed=true
            return true
          end
        end
        return false
      end
      if mode~="age" or not v or not v.road_fault then return false end
      -- Test accelerated wear, not a forced countdown. Normal live
      -- difficulty, speed/traffic checks and the global draw still decide.
      v.road_fault.reliability=1150;v.road_fault.breakdown_chance=255
      q.aged=true
      return true
    end})
    function extended.fault()
      local v=S.fleet[1]
      if not v or not v.road_fault then return end
      local f=v.road_fault
      local state=v.road_speed_state
      local frame=v.route and Sim.road_motion_frame(S,v)
      if q.aged and not q.first and f.breakdown_ctr==1 and state and frame then
        q.first={x=frame[1],z=frame[2],tile=frame[4],index=state.index,delay=f.breakdown_delay,
          started=f.last_start,phase=state.progress,billed=v.stock_bus.ticks,
          paid=v.delivered,service=f.services,tick=S.stock_load_tick,phase_counter=f.tick_counter}
        S.speed=0;api.save()
      end
      if q.first and f.breakdown_ctr==1 and f.starts==1 and frame then
        assert(frame[1]==q.first.x and frame[2]==q.first.z and state.index==q.first.index,
          "Native breakdown moved before stock recovery")
      end
      if q.first and not q.first_recovery and f.last_recovery then q.first_recovery=f.last_recovery end
      return {armed=q.aged,first=q.first,first_recovery=q.first_recovery,
        smoke_framed=q.smoke_framed,smoke=q.smoke or 0,active=f.breakdown_ctr==1,ctr=f.breakdown_ctr,delay=f.breakdown_delay,
        index=state and state.index,x=frame and frame[1],z=frame and frame[2],raw_speed=state and state.speed,
        charged=v.stock_bus.ticks,recovered=f.last_recovery,running=v.running,starts=f.starts,holds=f.recoveries,
        paid=v.delivered,revenue=v.revenue,reliability=f.reliability,
        cursor=v.index,orders=v.orders,last_service_tick=f.last_service_tick,status=v.status}
    end
  end
  if core.settings:get_bool("bayline_native_road_service",false) then
    S.qa_road_service=S.qa_road_service or {}
    local q=S.qa_road_service
    core.register_chatcommand("qa_road_service",{func=function(n,mode)
      if n~=username then return false end
      if mode=="go" then S.speed=1;return true end
      local v=S.fleet[1]
      local f=v and v.road_fault
      if mode~="age" or not f then return false end
      q.age_requested=true
      return true
    end})
    function extended.auto_service()
      local v=S.fleet[1]
      if not v or not v.road_fault then return end
      local frame=v.route and Sim.road_motion_frame(S,v)
      local x=frame and Sim.xy(frame[4])
      local ready=x and x>=12 and x<=16 and v.dest==2 and S.tiles[frame[4]].build=="road" and v.units>0
      -- After the interactive instruction arrives, age the record only
      -- on the next actual loaded eastbound frame, before the normal
      -- economy day sees that pose. GUI round-trip time cannot pick a
      -- different scheduled station or turn-around direction.
      if ready and q.age_requested and not q.armed then
        v.road_fault.date_of_last_service=S.stock_bus_market.epoch+S.day-151
        q.armed={units=v.units,frame={frame[1],frame[2],frame[4]}}
      end
      if q.armed and not q.detour and frame and v.road_auto_service and v.units>0 then
        q.detour={tile=frame[4],x=frame[1],z=frame[2],px=frame[15],units=v.units,
          fare=v.revenue,tick=S.stock_load_tick,dispatch=v.last_auto_depot,requested=q.armed}
        S.speed=0;api.save()
      end
      return {active=v.road_auto_service~=nil,armed=q.armed,pose=frame and {frame[1],frame[2],frame[4]},
        detour=q.detour,ready=not not ready,
        service=v.road_fault.last_service_tick,depot_entry=v.last_depot_entry_tick,units=v.units,
        fare=v.revenue,last=v.last_fare,orders=v.orders,last_departure=v.last_departure_tick}
    end
  end
  function extended.install_block_rail()
    if not core.settings:get_bool("bayline_rail_block_preview",false) then return end
    S.qa_block_rail=S.qa_block_rail or {events={}}
    local q=S.qa_block_rail
    if not q.started then S.speed=0 end
    local diamond,outgoing,north=Sim.id(39,7),Sim.id(41,7),Sim.id(39,6)
    api.rail_dispatch_view.observe=function(events)
      for _,e in ipairs(events) do
        if e.kind=="waiting" or e.kind=="block_aspect" or e.tile==diamond or e.tile==outgoing then
          q.events[#q.events+1]=e
        end
      end
    end
    core.register_chatcommand("qa_block_rail",{func=function(n,mode)
      if n~=username then return false end
      if mode=="go" then q.started=true;S.speed=1;api.save();return true end
      if mode=="photo" then
        local p=core.get_player_by_name(n)
        if not p then return false end
        local x,y,z,tx,ty,tz=86,12,25,79,.65,15
        p:set_pos({x=x,y=y,z=z})
        p:set_look_horizontal(math.atan2(x-tx,tz-z))
        p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
        return true
      end
      return false
    end})
    function extended.block_rail()
      local d=S.stock_rail_dispatch
      if not d then return end
      local a,b=d.runs[1],d.runs[2]
      local out={diamond=S.tiles[diamond].rail_tracks,clock=d.ticks,hold=q.hold,aspects={},events=q.events,
        ready=0,parts={},heads={},failure=d.failure,drawing=0,no_reservations=not next(d.life.bits)}
      for id in pairs(d.signals.records) do
        local x,z=Sim.xy(id)
        local td=z==7 and 8 or 1
        out.aspects[x..","..z]=api.rail_dispatch_controller.signal(S,id,td)
      end
      for _,r in ipairs(d.runs) do
        out.ready=out.ready+1
        local front,tail=r.consist.parts[1],r.consist.parts[2]
        out.parts[r.id]={phase=r.phase,head=front.tile,tail=tail.tile,
          head_xy={front.pose.x,front.pose.y},tail_xy={tail.pose.x,tail.pose.y}}
      end
      for _,e in ipairs(core.get_objects_inside_radius({x=79,y=.65,z=14.5},28)) do
        local ent=e:get_luaentity()
        if ent and (ent.name=="luanttd_core:dispatch_locomotive" or ent.name=="luanttd_core:dispatch_wagon") then
          out.drawing=out.drawing+1
        elseif ent and ent.name:match("^luanttd_core:dispatch_signal_") then
          out.heads[#out.heads+1]={name=ent.name,mesh=e:get_properties().mesh}
        end
      end
      if not q.hold and a and b and b.phase=="waiting" and
          a.consist.parts[1].tile~=diamond and a.consist.parts[2].tile==diamond then
        S.speed=0
        q.hold={parts=out.parts,tick=d.ticks,aspects=out.aspects,heads=out.heads}
        out.hold=q.hold
        api.save()
      end
      return out
    end
  end
  extended.install_block_rail()
  function extended.install_depot_return()
    if not core.settings:get_bool("bayline_native_depot_return",false) then return end
    S.qa_depot_return=S.qa_depot_return or {}
    local state=S.qa_depot_return
    core.register_chatcommand("qa_depot_return",{func=function(n,mode)
      if n~=username then return false end
      if mode=="latch" then state.want=true
      elseif mode=="go" then state.want=nil;S.speed=1
      else return false end
      return true
    end})
    function extended.depot_return(v,owner)
      if not v then return end
      if state.want and v.route and v.dest==2 and v.units>0 then
        state.want=nil;state.carrying=true;S.speed=0;api.save()
      end
      local pos=Sim.road_motion_frame(S,v)
      local mesh
      for _,ref in ipairs(core.get_objects_inside_radius({x=34.5,y=1,z=26.5},2.5)) do
        local ent=ref:get_luaentity()
        if ent and ent.name=="luanttd_core:vehicle_"..v.engine then mesh=ref:get_pos() end
      end
      return {latch=state.carrying,park=not not Sim.road_can_park(S,owner,v.id),unit_count=v.units,
        returning=v.road_return_depot,ordered=v.road_depot_resume,road_tick=v.last_depot_entry_tick,
        mesh=mesh,depot=v.depot,station=v.station,pose=pos,visited=v.last_road_arrival_tick,company_tick=S.day}
    end
  end
  extended.install_depot_return()
  function extended.market(v)
    if not S.stock_bus_market then return end
    local year,month,day=Sim.date(S)
    local q={year=year,month=month,day=day,offers={}}
    for _,engine in ipairs({"bus","leopard_bus","foster_bus"}) do
      local e=Sim.stock_road_offer(S,engine)
      if e then q.offers[engine]=e.status end
    end
    if v and v.stock_bus then
      q.finance=v.stock_bus
      q.seats=Sim.vehicle_capacity(v)
      q.load=v.load_state and v.load_state.capacity
      q.units=v.units
      local p=Sim.position(S,v)
      if p then
        local x,z=Sim.xy(p)
        for _,ref in ipairs(core.get_objects_inside_radius({x=x*2+.5,y=.52,z=z*2+.5},3)) do
          local l=ref:get_luaentity()
          if l and l.name=="luanttd_core:vehicle_"..v.engine then
            q.model=ref:get_properties().mesh;q.pose=ref:get_pos()
          end
        end
      end
    end
    return q
  end
  local junction_fixture=core.settings:get_bool("bayline_native_junction_clearance",false)
  if junction_fixture then
    S.qa_junction=S.qa_junction or {}
    if not S.qa_junction.ready then S.speed=0 end
    core.register_chatcommand("qa_junction",{func=function(n,mode)
      if n~=username then return false end
      local q=S.qa_junction
      if mode=="prepare" and not q.ready then
        q.ready=dofile(core.get_modpath("luanttd_core").."/road_junction_fixture.lua")(Sim,S,n)
        local all={}
        for id in ipairs(S.tiles) do all[#all+1]=id end
        api.render.update(all);api.save()
      elseif mode=="one" and S.speed==0 then Sim.daily(S);q.one=S.day
      elseif mode=="go" then S.speed=1
      elseif mode=="photo" then
        local p=core.get_player_by_name(n)
        local x,y,z=36.9,4.2,29.0
        p:set_pos({x=x,y=y,z=z})
        p:set_look_horizontal(math.atan2(x-30.5,24.5-z))
        p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.6,math.sqrt((x-30.5)^2+(z-24.5)^2)))
      end
      return true
    end})
  end
  function extended.junction(n)
    if not junction_fixture then return end
    local q=S.qa_junction
    local out={ready=q.ready,one=q.one,drivers={},meshes={},hold=q.hold,enabled=S.road_junction_clearance}
    for _,v in pairs(S.fleet) do
      if v.owner==n then
        out.drivers[tostring(v.id)]={waits=v.road_junction_waits or 0,
          arrival=v.last_road_arrival_tick,at=Sim.position(S,v),owner=v.owner}
      end
    end
    for _,o in ipairs(core.get_objects_inside_radius({x=30.5,y=.52,z=24.5},7.5)) do
      local e=o:get_luaentity()
      if e and e.name=="luanttd_core:vehicle_bus" then out.meshes[#out.meshes+1]=o:get_pos() end
    end
    if not q.hold and #out.meshes==2 and ((out.drivers["1"] or {}).waits or 0)+((out.drivers["2"] or {}).waits or 0)>0 then
      S.speed=0
      q.hold={day=S.day,positions=out.meshes,vehicles=out.drivers}
      api.save()
    end
    out.hold=q.hold
    return out
  end
  local growth_fixture=core.settings:get_bool("bayline_native_town_growth",false)
  if growth_fixture then
    S.qa_growth=S.qa_growth or {}
    core.register_chatcommand("qa_growth",{func=function(n,mode)
      if n~=username then return false end
      if mode=="go" then S.speed=1;return true end
      local id=S.qa_growth.tile
      if not id then return false,"No stock construction started." end
      local p=core.get_player_by_name(n)
      local tx,tz=Sim.xy(id);tx,tz=tx*2+.5,tz*2+.5
      local x,y,z=tx+3.8,2.0,tz+4.4
      p:set_pos({x=x,y=y,z=z});p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.90,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  function extended.growth()
    if not growth_fixture then return end
    local q=S.qa_growth
    local towns=S.stock_town_growth and S.stock_town_growth.towns
    if not towns then return {} end
    if not q.tile then
      for _,town in pairs(towns) do
        if town.last_build then q.tile=town.last_build.tile;break end
      end
    end
    local house=q.tile and S.tiles[q.tile].source_house
    if not house then return {} end
    local x,z=Sim.xy(q.tile)
    local node=core.get_node_or_nil({x=x*2,y=S.tiles[q.tile].h+1,z=z*2})
    if not q.paused and house.stage==1 then S.speed=0;q.paused=true;api.save() end
    local town=towns[house.town]
    return {tile=q.tile,x=x,z=z,node=node and node.name,stage=house.stage,completed=house.completed,
      population=town and town.population,reason=town and town.reason,built=house.built_tick,
      completion=house.completed_tick,first_cargo=house.first_cargo_tick,paused=q.paused}
  end
  local tunnel_run=core.settings:get_bool("bayline_native_tunnel_run",false)
  local bridge_run=tunnel_run or core.settings:get_bool("bayline_native_bridge_run",false)
  local bridge_pass,tunnel_hidden,tunnel_exit
  if bridge_run then
    local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
    local concrete=core.settings:get_bool("bayline_native_concrete",false)
    local east=concrete and 26 or 27
    local function at(x,z) return Sim.id(x,z or 12) end
    if not S.bridge_run_fixture then
      S.bridge_run_fixture=true
      for _,tile in ipairs(S.tiles) do
        tile.terrain="grass";tile.h=0;tile.wood=nil;tile.house=nil;tile.site=nil;tile.build=nil;tile.owner=nil
      end
      S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x)
        return tunnel_run and x>=24 and x<=27 and 1 or 0
      end).levels
      S.road_stock_house_supply=false
      local function town(id,x)
        return {id=id,tile=at(x,11),name="Bridge Town "..id,kind="town",population=360,
          produced={},received={},stock={},service=0}
      end
      S.sites={town(1,19),town(2,32)}
      S.tiles[S.sites[1].tile].site=1;S.tiles[S.sites[2].tile].site=2
      if not tunnel_run then for x=24,east-1 do S.tiles[at(x)].terrain="water" end end
    end
    core.register_chatcommand("qa_bridge_service",{func=function(name)
      if name~=username or S.bridge_service_id then return false end
      local changed={}
      local function add(ok,msg,ids)
        assert(ok,msg)
        for _,id in ipairs(ids) do changed[#changed+1]=id end
      end
      local steel=core.settings:get_bool("bayline_native_steel",false)
      if tunnel_run then add(Sim.road_tunnel(S,name,at(23)))
      else add(Sim.road_bridge(S,name,at(23),at(east),concrete and 1 or (steel and 2 or 0))) end
      add(Sim.build(S,name,"road",Sim.line(at(18),at(23))))
      add(Sim.build(S,name,"road",Sim.line(at(east),at(33))))
      add(Sim.build(S,name,"road_station",{at(18)}))
      add(Sim.build(S,name,"road_station",{at(33)}))
      add(Sim.build(S,name,"road_depot",{at(20,13)}))
      local a,b=S.tiles[at(18)].station,S.tiles[at(33)].station
      local id=assert(Sim.purchase(S,name,"bus","passenger",nil,at(20,13)))
      assert(Sim.add_order(S,name,id,a));assert(Sim.add_order(S,name,id,b))
      assert(Sim.toggle(S,name,id))
      S.bridge_service_id=id
      api.render.raise_bound(1);api.render.update(changed);api.save()
      return true
    end})
  end
  local coal_fixture=core.settings:get_bool("bayline_preview_coal_industry",false)
  if coal_fixture then
    core.register_chatcommand("qa_coal_view",{func=function(name,what)
      if name~=username then return false end
      local p=core.get_player_by_name(name)
      local x,y,z,tx,tz=71,9.5,18,72,27.5
      if what=="freight" then x,y,z,tx,tz=79,4,35,81,28.5 end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.8,
        math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  local air_fixture=core.settings:get_bool("bayline_airport_preview",false)
  local air_paid=core.settings:get_bool("bayline_preview_paid_air",false)
  if air_fixture then
    S.qa_air=S.qa_air or {events={}}
    api.airport_view.observe=function(ev,p,a)
      if ev=="takeoff" or ev=="liftoff" or ev=="departed" or ev=="approach" or
          ev=="touchdown" or ev=="terminal" then
        S.qa_air.events[#S.qa_air.events+1]={kind=ev,id=a.id,x=p.vehicle.x,z=p.vehicle.z,
          y=p.vehicle.y,tick=p.vehicle.tick}
      end
    end
    core.register_chatcommand("qa_airfield_photo",{func=function(name,what)
      if name~=username then return false end
      local player=core.get_player_by_name(name)
      local a=S.airport_pilot or api.airfield.current()
      local x,y,z,tx,ty,tz=59,4.8,36,62,.65,35
      if air_paid then
        x,y,z,tx,ty,tz=25,8,20,27,.65,25
        if what=="runway" then x,y,z,tx,ty,tz=39,4.8,27,42,.65,27 end
      end
      if what=="flight" and a then
        local v=a.vehicle
        tx,ty,tz=v.x/8-.5,(v.y-1)/8+.65,v.z/8-.5
        x,y,z=tx-4,ty+2,tz+4
      end
      player:set_pos({x=x,y=y,z=z})
      player:set_look_horizontal(math.atan2(x-tx,tz-z))
      player:set_look_vertical(math.atan2(y+player:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
    core.register_chatcommand("qa_airfield_resume",{func=function(name)
      if name~=username then return false end
      S.speed=1;return true
    end})
  end
  function extended.install_air_fleet()
    if not core.settings:get_bool("bayline_air_fleet_preview",false) then return end
    S.qa_air_fleet=S.qa_air_fleet or {}
    local q=S.qa_air_fleet
    if not q.launched then S.speed=0 end
    core.register_chatcommand("qa_air_fleet",{func=function(n,mode)
      if n~=username then return false end
      if mode=="go" then q.launched=true;S.speed=1;api.save();return true end
      if mode=="photo" then
        local p=core.get_player_by_name(n)
        if not p then return false end
        local x,y,z,tx,ty,tz=43,18,55,51,12,28
        p:set_pos({x=x,y=y,z=z})
        p:set_look_horizontal(math.atan2(x-tx,tz-z))
        p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
        return true
      end
      return false
    end})
    function extended.air_fleet(n)
      local company=S.companies[n]
      local state={airports=0,owned=S.stock_owned_air_fleet or {},
        fields={},runs={},models={},timed=q.hold,cash=company and company.cash,expense=company and company.expense,
        money=company and company.revenue,paid=company and company.paid_units,
        world_tick=S.passenger_house_clock and S.passenger_house_clock.counter}
      for id,field in pairs(S.stock_small_airports or {}) do
        state.airports=state.airports+1
        state.fields[id]={flags=field.flags,origin=field.origin}
      end
      for _,r in ipairs(api.airfield.all()) do
        local v=r.vehicle
        state.runs[r.paid_clock]={in_air=not not v.airborne,phase=r.phase,holds=r.hold_ticks or 0,
          first=r.first,second=r.second,last=r.last_airfield,arrivals=r.arrivals,x=v.x,y=v.y,z=v.z,tick=v.tick,
          terminal=r.last_terminal_tile,stats=Sim.air_paid_status(S,r.paid_clock)}
        local point={x=v.x/8-.5,y=(v.y-1)/8+.5,z=v.z/8-.5}
        for _,ent in ipairs(core.get_objects_inside_radius(point,8)) do
          local lua=ent:get_luaentity()
          if lua and lua.name=="luanttd_core:stock_bayshore_trimotor" and lua.paid_clock==r.paid_clock then
            state.models[r.paid_clock]={pos=ent:get_pos(),mesh=ent:get_properties().mesh}
          end
        end
      end
      local a,b=state.runs[1],state.runs[2]
      if a and b and not q.hold and (a.holds>0 or b.holds>0) then
        S.speed=0
        q.hold={runs=state.runs,tick=state.world_tick,fields=state.fields}
        -- Snapshot only raw state, not a delayed render interpolation.
        state.timed=q.hold
        api.save()
      end
      return state
    end
  end
  extended.install_air_fleet()
  local lock_fixture=core.settings:get_bool("bayline_native_lock",false)
  if lock_fixture and not S.qa_lock then
    local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
    S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x,z)
      return (x>=23 and 1 or 0)+(z<=18 and 1 or 0)
    end).levels
    for z=16,24 do for x=13,33 do
      local id=Sim.id(x,z)
      local a=S.tiles[id]
      local _,base=api.terrain.tile(id)
      a.h=base;a.terrain="grass";a.wood=nil;a.house=nil;a.site=nil;a.build=nil
      a.road_town=nil;a.road_bits=nil;a.owner=nil
      if z>=19 and z<=23 and ((x>=14 and x<=20) or (x>=24 and x<=32)) then
        a.terrain="water";a.water_class="canal"
      end
    end end
    S.road_stock_house_supply=false;S.qa_lock={levels={}}
  end
  if lock_fixture then
    core.register_chatcommand("qa_lock_resume",{func=function(name)
      if name~=username then return false end
      S.speed=1;return true
    end})
  end
  local aqua_fixture=core.settings:get_bool("bayline_native_aqueduct",false)
  if aqua_fixture and not S.qa_aqua_setup then
    local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
    S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x,z)
      return ((x<=20 or x>=25) and 1 or 0)+(z<=18 and 1 or 0)
    end).levels
    for z=16,24 do for x=13,33 do
      local id=Sim.id(x,z)
      local a=S.tiles[id]
      local _,base=api.terrain.tile(id)
      a.h=base;a.terrain="grass";a.wood=nil;a.house=nil;a.site=nil;a.build=nil
      a.road_town=nil;a.road_bits=nil;a.owner=nil
      if z>=19 and z<=23 and ((x>=14 and x<=19) or (x>=25 and x<=32)) and not (x==19 and z==20) then
        a.terrain="water";a.water_class="canal"
      elseif z>=19 and z<=21 and x==23 then
        a.terrain="water";a.water_class="river"
      elseif x==22 and z>=19 and z<=21 then
        a.build="road";a.road_bits=5;a.owner=username
      end
    end end
    S.road_stock_house_supply=false
    S.qa_aqua_setup=true
  end
  local paid_rail_fixture=core.settings:get_bool("bayline_preview_paid_rail",false)
  local paid_ferry_fixture=core.settings:get_bool("bayline_preview_paid_ferry",false)
  local buoy_fixture=core.settings:get_bool("bayline_native_buoy",false)
  if paid_ferry_fixture and not paid_rail_fixture and not S.qa_paid_ferry then
    local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
    S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x) return x<9 and 1 or 0 end).levels
    for id,a in ipairs(S.tiles) do
      local x=Sim.xy(id)
      local _,base=api.terrain.tile(id)
      a.h=base;a.terrain=x>=9 and "water" or "grass"
      a.wood=nil;a.house=nil;a.site=nil;a.build=nil;a.road_town=nil;a.road_bits=nil
      a.owner=nil;a.source_house=nil
    end
    for _,z in ipairs({5,6,7,8,9,17,18,19,20,21}) do
      local c=S.tiles[Sim.id(6,z)];c.house,c.parcel,c.variant=true,"shop",2
    end
    S.road_stock_house_supply=true;S.road_stock_loading=true;S.road_stock_clock=true
    S.speed=buoy_fixture and 0 or 4;S.qa_paid_ferry=true
  end
  local ship_fixture=core.settings:get_bool("bayline_ship_preview",false)
  local yate_fixture=core.settings:get_bool("bayline_ship_coal_coastal_scenario",false)
  if yate_fixture then
    S.qa_yate=S.qa_yate or {}
    if not S.qa_yate.begun then S.speed=0 end
    core.register_chatcommand("qa_yate",{func=function(n,mode)
      if n~=username then return false end
      local q=S.qa_yate
      if mode=="go" then q.begun=true;S.speed=1;return true end
      local p=core.get_player_by_name(n)
      if mode=="survey" then
        p:set_pos({x=17,y=17,z=57})
        return true
      end
      local tx,ty,tz=11.1,.51,66.5
      if mode=="loaded" and q.loaded then
        local a=q.loaded.mesh;tx,ty,tz=a.x,a.y,a.z
      end
      local x,y,z=tx+4,ty+2.2,tz+4.8
      p:set_pos({x=x,y=y,z=z});p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  function extended.yate()
    if not yate_fixture then return end
    local q=S.qa_yate
    local c=api.ship_coal
    local out={enabled=api.ship_coal_tools,coast=S.stock_coal_scenario}
    local craft=c and c.status()
    out.vessel=craft
    for _,obj in ipairs(core.get_objects_inside_radius({x=18,y=.7,z=65},26)) do
      local e=obj:get_luaentity()
      if e and e.name=="luanttd_core:stock_yate_cargo_ship" then out.mesh=obj:get_pos();out.model=obj:get_properties().mesh end
    end
    if not q.loaded and craft and craft.loading and craft.onboard>=10 and craft.delivered==0 and out.mesh then
      S.speed=0
      q.loaded={mesh=out.mesh,units=craft.onboard,tick=craft.tick,berth=craft.last_berth}
      api.save()
    end
    out.loaded=q.loaded
    local received=0
    for _,site in ipairs(S.sites) do
      if site.kind=="stock_power_station" then received=received+(site.received.coal or 0) end
    end
    out.received=received
    out.tick=S.passenger_house_clock and S.passenger_house_clock.counter
    return out
  end
  if ship_fixture then
    core.register_chatcommand("qa_ship_photo",{func=function(name,angle)
      if name~=username then return false end
      local p=core.get_player_by_name(name)
      local x,y,z,tx,tz=8,3.7,69,13.5,66.7
      if angle=="east" then x,y,z,tx,tz=18.4,2.4,70.2,16.3,67.2 end
      if angle=="aqueduct" then x,y,z,tx,tz=45.8,6.0,34.0,45.5,40.2 end
      if angle=="lock" then x,y,z,tx,tz=44.8,4.8,34.7,44.5,40.5 end
      if angle=="pay" then x,y,z,tx,tz=25.0,3.85,27.0,19.0,23.0 end
      if buoy_fixture then
        if angle=="go" then S.speed=4;return true end
        if angle=="buoy" then x,y,z,tx,tz=37.0,2.3,27.1,38.5,24.5 end
        if angle=="buoy_order" then x,y,z,tx,tz=27.0,14.0,12.0,22.0,28.0 end
      end
      if angle=="ferry" and S.ship_pilot then
        local boat=S.ship_pilot.vehicle
        tx,tz=boat.x/8-.5,boat.y/8-.5
        x,y,z=tx-2.8,2.8,tz+3.2
      end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.65,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  -- The separate dispatch fixture clears a large rectangle while waiting
  -- for /qa_dispatch_layout. Do not let it erase a built/restored waypoint.
  local dispatch_fixture=core.settings:get_bool("bayline_rail_dispatch_preview",false)
    and not core.settings:get_bool("bayline_native_rail_waypoint",false)
  local shuttle_fixture=core.settings:get_bool("bayline_native_shuttle",false) or paid_rail_fixture
  local rail_grade_fixture=core.settings:get_bool("bayline_rail_grade_preview",false)
  local rail_build_fixture=api.rail_build_tools
  local crossing_fixture=core.settings:get_bool("bayline_rail_crossing_preview",false)
  local cross_id=Sim.id(14,12)
  if crossing_fixture then
    local q=S.qa_crossing or {}
    S.qa_crossing=q
    local function at(x,z) return Sim.id(x,z) end
    local first,last=at(11,12),at(17,12)
    if not q.ready then
      S.speed=0;S.road_stock_loading=true
      local g=S.corner_grid
      for z=3,23 do for x=9,20 do g.levels[(z-1)*(g.width+1)+x]=0 end end
      for z=4,21 do for x=9,19 do
        S.tiles[at(x,z)]={terrain="grass",h=0,variant=(x+z)%4}
      end end
    end
    local function setup(n)
      local dirty={}
      local function build(tool,ids)
        local ok,note,next_=Sim.build(S,n,tool,ids);assert(ok,note)
        for _,i in ipairs(next_) do dirty[#dirty+1]=i end
      end
      build("road",Sim.line(first,last));build("road_station",{first,last})
      for z=4,20 do
        if z~=12 then
          local i=at(14,z)
          local t=S.tiles[i]
          t.build,t.owner,t.rail_tracks="stock_rail",n,2
          dirty[#dirty+1]=i
        end
      end
      assert(api.trackworks.depot(S,n,at(14,4),1))
      assert(api.trackworks.station(S,n,at(14,18),at(14,20)))
      q.ready=true;api.render.update(dirty);api.save()
    end
    local function bus(n,from,to)
      local id=assert(Sim.purchase(S,n,"bus","passenger",S.tiles[from].station))
      assert(Sim.add_order(S,n,id,S.tiles[to].station))
      assert(Sim.toggle(S,n,id))
      return id
    end
    core.register_chatcommand("qa_crossing",{func=function(n,mode)
      if n~=username then return false end
      if mode=="prepare" and not q.ready then setup(n) end
      if mode=="arrange" and not q.bus and api.crossings.world.record(S,cross_id) then
        q.bus=bus(n,first,last)
        local v=S.fleet[q.bus]
        for _=1,24 do
          Sim.daily(S)
          local f=Sim.road_motion_frame(S,v)
          if f and f[4]==cross_id then
            v.running=false
            q.road_tick=S.day
            break
          end
        end
        assert(q.road_tick,"Failed to drive the prepared road bus onto the real crossing")
        qa_ui.hud();api.save()
      elseif mode=="queue" and not q.opposing and q.hold then
        q.opposing=bus(n,last,first)
        for _=1,16 do
          Sim.daily(S)
          local v=S.fleet[q.opposing]
          if v.road_speed_state and v.road_speed_state.waiting=="crossing" then
            local f=assert(Sim.road_motion_frame(S,v))
            assert(f[4]~=cross_id);q.denied=true;break
          end
        end
        assert(q.denied,"Opposing bus did not wait outside the lowered arms")
        api.save()
      elseif mode=="release" and q.bus then
        S.fleet[q.bus].running=true;S.fleet[q.bus].stop_requested=true
        S.speed=1
      elseif mode=="go" or mode=="finish" then S.speed=1 end
      local p=core.get_player_by_name(n)
      local x,y,z,tx,ty,tz=26.2,2.1,19.8,28.5,.5,24.5
      if mode=="overview" or mode=="arrange" then x,y,z,tx,ty,tz=31,11,15,28.5,.5,25 end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
    api.rail_dispatch_view.observe=function(events)
      for _,e in ipairs(events) do
        if not q.hold and e.kind=="waiting" and e.reason=="ROAD_DRAINING" then
          q.hold=e.tick;S.speed=0;api.save()
        end
        if e.kind=="arrived" then q.arrived=e.tick end
      end
      if q.hold and not q.tail then
        local d=S.stock_rail_dispatch
        local run=d and d.runs[1]
        local parts=run and run.consist.parts
        if parts and parts[1].tile~=cross_id and parts[2].tile==cross_id then
          q.tail=d.ticks
          S.speed=0;api.save()
        end
      end
    end
  end
  local rail_span_fixture=core.settings:get_bool("bayline_rail_span_preview",false)
  if rail_span_fixture then
    local qa=S.qa_rail_span or {events={}}
    S.qa_rail_span=qa
    local function at(x) return Sim.id(x,10) end
    if not qa.ready then
      local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
      S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x)
        return x>=14 and x<=18 and 5 or (x==7 or x==8) and 3 or 4
      end).levels
      -- Build a disposable scenic valley, not a raised overlay on the
      -- existing towns (which would leave floating QA-only roads).
      S.sites={}
      for id in ipairs(S.tiles) do
        local x,z=Sim.xy(id)
        local _,h=api.terrain.tile(id)
        local stream=(x==7 and z>=4)
        local trees=not stream and z>13 and (x*7+z*13)%37<3
        S.tiles[id]={h=h,terrain=stream and "water" or "grass",water_class=stream and "river" or nil,
          wood=trees or nil,variant=(x+z)%4}
      end
      api.render.raise_bound(5)
      S.speed=0
    end
    local function view(p,m)
      local x,y,z,tx,ty,tz=15,9.3,11,14,4.9,20.5
      if m=="deck" then x,y,z,tx,ty,tz=12,6.1,16,15,5.45,20.5
      elseif m=="tunnel" then x,y,z,tx,ty,tz=39,7.6,12.5,34,4.9,20.5
      elseif m=="rail" then x,y,z,tx,ty,tz=23,14,10,25,4.8,20.5 end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
    end
    core.register_chatcommand("qa_rail_span",{func=function(n,mode)
      if n~=username then return false end
      if mode=="prepare" and not qa.ready then
        local d={}
        for _,x in ipairs({2,3,4,10,11,12,19,20,21,22,23,24}) do
          local tile=at(x)
          local t=S.tiles[tile];t.owner=n;t.rail_tracks=1;t.build="stock_rail";d[#d+1]=tile
        end
        assert(api.trackworks.depot(S,n,at(2),2))
        assert(api.trackworks.station(S,n,at(22),at(24)))
        qa.ready=true;api.render.update(d);api.save()
      end
      view(core.get_player_by_name(n),mode)
      if mode=="go" or mode=="tunnel" or mode=="final" then S.speed=1 end
      return true
    end})
    api.rail_dispatch_view.observe=function(events)
      for _,e in ipairs(events) do
        if e.kind=="span_exited" or e.kind=="span_released" or e.kind=="tunnel_hidden" or e.kind=="tunnel_revealed" or e.kind=="arrived" then
          qa.events[#qa.events+1]=e
          if e.kind=="tunnel_revealed" and e.index==2 and not qa.show_exit then
            qa.show_exit=e.tick
            S.speed=0;api.save()
          end
        end
      end
    end
  end
  local rail_crossing=Sim.id(9,9)
  if dispatch_fixture then
    local qa=S.qa_dispatch or {events={}}
    S.qa_dispatch=qa
    if not qa.ready then
      local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
      for z=3,17 do for x=2,17 do
        local t=S.tiles[Sim.id(x,z)]
        t.h=0;t.terrain="grass";t.wood=nil;t.house=nil;t.site=nil;t.build=nil
        t.owner=nil;t.road_town=nil;t.road_bits=nil
      end end
      S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x)
        if paid_rail_fixture then return x<19 and 1 or 0 end
        return rail_grade_fixture and x>=8 and x<=10 and 1 or 0
      end).levels
      S.road_stock_house_supply=paid_rail_fixture
      if paid_rail_fixture then
        for id,a in ipairs(S.tiles) do
          local x=Sim.xy(id)
          local _,base=api.terrain.tile(id)
          a.h=base;a.terrain=x>=19 and "water" or "grass"
          a.wood=nil;a.house=nil;a.site=nil;a.build=nil;a.road_town=nil;a.road_bits=nil
          a.owner=nil;a.source_house=nil
        end
        for _,p in ipairs({{4,7},{5,7},{6,7},{4,8},{5,8},{6,8},{14,7},{14,8},{14,9},
          {15,8},{14,10},{16,15},{16,16},{16,17},{17,17},{16,18},{17,18},{11,9},{11,13},{12,13},{14,13}}) do
          local tile=S.tiles[Sim.id(p[1],p[2])]
          tile.house,tile.parcel,tile.variant=true,"shop",2
        end
        S.road_stock_loading=true;S.road_stock_clock=true
      end
      S.speed=0
    end
    api.rail_dispatch_view.observe=function(events)
      local d=S.stock_rail_dispatch
      if not d then return end
      for _,ev in ipairs(events) do
        if ev.kind=="reversed" and shuttle_fixture and not paid_rail_fixture and not qa.frozen then
          S.speed=0;qa.frozen=d.ticks;api.save()
        end
        if ev.kind=="arrived" or ev.kind=="waiting" or ev.kind=="proceeded" or
          ev.kind=="reversed" or ev.kind=="shuttle_departed" or
          ((ev.kind=="tail_released" or ev.kind=="front_entered") and ev.tile==rail_crossing) then
          qa.events[#qa.events+1]=ev
        end
      end
      if not qa.frozen and #d.runs==2 and d.runs[1].phase=="waiting" then
        local b=d.runs[2].consist.parts
        if b[1].tile~=rail_crossing and b[2].tile==rail_crossing and d.life.bits[rail_crossing]==2 then
          S.speed=0;qa.frozen=d.ticks;api.save()
        end
      end
    end
    core.register_chatcommand("qa_dispatch_layout",{func=function(name)
      if name~=username or qa.ready then return false end
      local Lab=api.trackworks
      local dirty={}
      local function set(x,z,track)
        local id=Sim.id(x,z)
        local shape=api.terrain.tile(id)
        local ok,msg=Lab.change(S,name,id,track,false,shape)
        assert(ok,msg);dirty[#dirty+1]=id
      end
      if rail_grade_fixture then
        for x=3,16 do set(x,9,0) end
        assert(Lab.depot(S,name,Sim.id(3,9),2))
        assert(Lab.station(S,name,Sim.id(14,9),Sim.id(16,9)))
      elseif shuttle_fixture then
        for x=2,14 do set(x,5,0) end
        assert(Lab.depot(S,name,Sim.id(2,5),2))
        assert(Lab.station(S,name,Sim.id(4,5),Sim.id(6,5)))
        assert(Lab.station(S,name,Sim.id(12,5),Sim.id(14,5)))
      else
        for x=3,16 do set(x,9,0) end
        for z=4,16 do set(9,z,1) end
        assert(Lab.depot(S,name,Sim.id(3,9),2))
        assert(Lab.depot(S,name,Sim.id(9,4),1))
        assert(Lab.station(S,name,Sim.id(14,9),Sim.id(16,9)))
        assert(Lab.station(S,name,Sim.id(9,14),Sim.id(9,16)))
      end
      api.render.update(dirty);qa.ready=true;api.save();return true
    end})
    core.register_chatcommand("qa_dispatch_go",{func=function(name)
      if name~=username or not qa.ready then return false end
      S.speed=paid_rail_fixture and 3 or 1
      return true
    end})
    core.register_chatcommand("qa_dispatch_photo",{func=function(name)
      if name~=username then return false end
      local p=core.get_player_by_name(name)
      local x,y,z,tx,tz=14.5,3.2,14.8,18.3,18.4
      if shuttle_fixture then x,y,z,tx,tz=22.5,3.1,13.5,26.5,10.5 end
      if rail_grade_fixture then x,y,z,tx,tz=14.5,3.05,14.8,18.5,18.5 end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.68,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  local tram_fixture=core.settings:get_bool("bayline_tram_preview",false)
  if tram_fixture and not S.native_tram_initialized then
    local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
    for x=5,9 do for z=6,15 do
      local cell=S.tiles[Sim.id(x,z)]
      cell.terrain="grass";cell.h=0;cell.wood=nil;cell.house=nil;cell.site=nil;cell.build=nil
      cell.owner=nil;cell.road_town=nil;cell.road_bits=nil
    end end
    S.corner_grid.levels=T.new(Sim.W,Sim.H,function()return 0 end).levels
    S.native_tram_initialized=true
  end
  if tram_fixture then
    core.register_chatcommand("qa_tram_photo",{func=function(name,heading)
      if name~=username then return false end
      local player=core.get_player_by_name(name)
      local px,pz,tx,tz=13.4,14.25,16.5,16.5
      if heading=="south" then pz,tz=24.25,26.5 end
      local y=1.35
      player:set_pos({x=px,y=y,z=pz})
      player:set_look_horizontal(math.atan2(px-tx,tz-pz))
      player:set_look_vertical(math.atan2(y+player:get_properties().eye_height-.75,
        math.sqrt((px-tx)^2+(pz-tz)^2)))
      return true
    end})
  end
  local mail_stops
  local mail_mesh
  if S.road_mail then
    local function at(x,z) return Sim.id(x,z) end
    core.register_chatcommand("qa_postal_route",{func=function(name)
      if name~=username or S.native_postal_setup then return false end
      local dirty={}
      local function add(ok,why,changed)
        assert(ok,why)
        for _,tile in ipairs(changed) do dirty[#dirty+1]=tile end
      end
      add(Sim.build(S,name,"road",Sim.line(at(11,12),at(17,12))))
      add(Sim.build(S,name,"road_depot",{at(12,13)}))
      S.native_postal_setup=true
      api.render.update(dirty);api.save()
      return true
    end})
  end
  local grade=core.settings:get_bool("bayline_native_grade",false)
  local grade_samples={ascending=0,descending=0,height_error=0,pitch_error=0}
  local grade_tiles
  local vprev
  if grade then assert(api.terrain and S.corner_grid,"QA ramps require preview terrain") end
  local turns=core.settings:get_bool("bayline_native_turns",false)
  local observed_turn
  local source_motion_seen=false
  local function observe_turn()
    if not turns or observed_turn then return end
    for _,o in ipairs(core.get_objects_inside_radius({x=36.5,y=.52,z=24.5},2)) do
      local e=o:get_luaentity()
      if e and e.name==road_visual then
        local q=o:get_pos()
        local yaw=o:get_yaw()
        local quadrant=math.pi/2
        local angle=math.abs(yaw-math.floor(yaw/quadrant+.5)*quadrant)
        if (q.x-36.5)^2+(q.z-24.5)^2<1.25^2 and angle>.075 then
          observed_turn={x=q.x,z=q.z,yaw=yaw}
        end
      end
    end
  end
  local crowd_samples={count=0,fades=0,moving=0,min_life=1,max_life=0,min_size=3,max_size=0}
  local add_particle=core.add_particle
  core.add_particle=function(spec)
    if type(spec)~="table" then return add_particle(spec) end
    if S.qa_road_fault and type(spec.texture)=="table" and
        spec.texture.name=="bl_coal_haze.png^[colorize:#56565e:176" then
      assert(spec.playername==username,"Unexpected viewer for native bus fault cue")
      S.qa_road_fault.smoke=(S.qa_road_fault.smoke or 0)+1
    end
    local texture=type(spec.texture)=="table" and spec.texture.name or spec.texture
    if spec.playername==username and type(texture)=="string" and texture:match("^bl_waiting_") then
      local tween=type(spec.texture)=="table" and spec.texture.alpha_tween
      if tween and tween[1]==1 and tween[2]==0 then
        crowd_samples.fades=crowd_samples.fades+1
      else
        crowd_samples.count=crowd_samples.count+1
        crowd_samples.min_life=math.min(crowd_samples.min_life,spec.expirationtime)
        crowd_samples.max_life=math.max(crowd_samples.max_life,spec.expirationtime)
      end
      for _,value in pairs(spec.velocity) do
        if value~=0 then crowd_samples.moving=crowd_samples.moving+1 end
      end
      crowd_samples.min_size=math.min(crowd_samples.min_size,spec.size)
      crowd_samples.max_size=math.max(crowd_samples.max_size,spec.size)
    end
    return add_particle(spec)
  end
  local lane_sample
  local function observe_lane()
    if lane_sample then return end
    for _,o in ipairs(core.get_objects_inside_radius({x=27.5,y=1,z=24.5},10)) do
      local e=o:get_luaentity()
      if e and e.name==road_visual then
        local p=o:get_pos()
        local yaw=o:get_yaw()
        local lane=p.z-24.5
        if p.x>23.5 and p.x<34.5 and math.abs(math.sin(yaw))>.99 and math.abs(math.abs(lane)-.155)<.01 then
          local width=road_visual=="luanttd_core:vehicle_foster_bus" and .6444 or leopard and .6485 or .638
          lane_sample={x=p.x,z=p.z,offset=lane,visual_width=o:get_properties().visual_size.x*width,nose_x=math.sin(yaw)}
        end
      end
    end
  end
  local rail_coal_fixture=core.settings:get_bool("bayline_rail_coal_preview",false)
  local owned_rail_fixture=core.settings:get_bool("bayline_rail_owned_preview",false) and not rail_coal_fixture
    and not core.settings:get_bool("bayline_rail_pair_preview",false) and not extended.rail_oil
  local owned_default=core.settings:get_bool("bayline_native_owned_default",false)
  local owned_loco
  if core.settings:get_bool("bayline_native_floss",false) then
    owned_loco={name="luanttd_core:dispatch_floss",mesh="bl_rail_floss_47.obj"}
  elseif core.settings:get_bool("bayline_native_ginzu",false) then
    owned_loco={name="luanttd_core:dispatch_ginzu",mesh="bl_rail_ginzu_a4.obj"}
  elseif core.settings:get_bool("bayline_native_jubilee",false) then
    owned_loco={name="luanttd_core:dispatch_jubilee",mesh="bl_rail_chaney_jubilee.obj"}
  else
    owned_loco={name="luanttd_core:dispatch_steam",mesh="bl_rail_kirby_paul_tank.obj"}
  end
  local owned_z=owned_default and 5 or 10
  if owned_rail_fixture then
    local q=S.qa_owned_rail or {}
    S.qa_owned_rail=q
    local function at(x,z) return Sim.id(x,z or owned_z) end
    if not q.ready then S.speed=0 end
    if not q.ready and not owned_default then
      local h=S.corner_grid.levels
      for i=1,#h do h[i]=0 end
      for z=5,14 do for x=1,27 do S.tiles[at(x,z)]={h=0,terrain="grass",variant=(x+z)%4} end end
      S.sites[1].tile,S.sites[2].tile=at(10,13),at(24,13)
      for _,z in ipairs({7,8,12,13}) do
        for _,x in ipairs({8,9,10,11,12,21,22,23,24,25}) do
          local t=S.tiles[at(x,z)]
          t.house,t.parcel,t.variant=true,"shop",2
        end
      end
    end
    core.register_chatcommand("qa_owned_train",{func=function(n,mode)
      if n~=username then return false end
      if mode=="prepare" and not q.ready and owned_default then
        q.ready=true
        api.save()
      elseif mode=="prepare" and not q.ready then
        local dirty={}
        for x=2,24 do
          local id=at(x)
          local t=S.tiles[id]
          t.owner,t.rail_tracks,t.build=n,1,"stock_rail";dirty[#dirty+1]=id
        end
        assert(api.trackworks.depot(S,n,at(2),2))
        assert(api.trackworks.station(S,n,at(11),at(12)))
        assert(api.trackworks.station(S,n,at(22),at(24)))
        assert(api.rail_dispatch_controller.place_signal(S,n,at(10),0,4))
        q.ready=true;api.render.update(dirty);api.save()
      elseif mode=="go" or mode=="resume" then S.speed=1 end
      local p=core.get_player_by_name(n)
      local tx,ty,tz=25,.6,owned_z*2+.5
      local x,y,z=19,12,tz-9.5
      if mode=="photo" then
        local v=q.boarding and q.boarding.engine
        if v then
          x,y,z,tx,ty,tz=v.x-2.5,1.6,v.z-3.8,v.x-.2,.75,v.z
          if owned_loco.name=="luanttd_core:dispatch_ginzu" or owned_loco.name=="luanttd_core:dispatch_floss" then
            x,y,z,tx,ty,tz=v.x+2.15,1.35,v.z-2.4,v.x-.36,.82,v.z
          end
        end
      end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  if S.stock_road_bays or api.road_bay_tools then
    core.register_chatcommand("qa_bay_photo",{func=function(n)
      if n~=username then return false end
      local p=core.get_player_by_name(n)
      local x,y,z,tx,ty,tz=25.55,1.18,27.2,22.5,.70,24.5
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  local function owned_rail_view(username)
    if not owned_rail_fixture then return end
    local q=S.qa_owned_rail
    local fleet=api.rail_owned.list(S,username)
    local unit=fleet[1]
    local run=unit and api.rail_dispatch_controller.current_paid(S)
    local service=unit and api.rail_owned.running(S,username,unit.id)
    local paid=Sim.rail_paid_status(S)
    local engine,wagon,model
    for _,o in ipairs(core.get_objects_inside_radius({x=29,y=.62,z=owned_z*2+.5},50)) do
      local e=o:get_luaentity()
      if e and e.name==owned_loco.name and o:get_properties().mesh==owned_loco.mesh then
        engine=o:get_pos();model=o:get_properties().mesh
      elseif e and e.name=="luanttd_core:dispatch_wagon" then wagon=o:get_pos() end
    end
    if not q.boarding and service and paid and paid.loading and (service.passengers or 0)>0 and engine and wagon then
      S.speed=0
      q.boarding={unit=unit.id,units=service.passengers,engine=engine,carriage=wagon,tick=paid.tick,mass=service.mass,model=model}
      api.save()
    end
    local wp
    if core.settings:get_bool("bayline_native_rail_waypoint",false) then
      local id=Sim.id(16,owned_z)
      local t=S.tiles[id]
      wp={id=t.rail_waypoint_id,track=t.rail_tracks,node=core.get_node({x=33,y=1,z=owned_z*2+1}).name}
      if run and run.via and run.via.passes>0 and run.speed>0 then
        q.first_pass_speed=q.first_pass_speed or run.speed
      end
    end
    return {ready=q.ready,count=#fleet,unit=unit,boarded=q.boarding,engine=engine,wagon=wagon,paid=paid,moving=service,
      waypoint=wp,via=run and run.via,first_pass_speed=q.first_pass_speed,
      phase=run and run.phase,stock=run and run.stock_engine,max=run and run.max_track_speed,
      reversals=run and run.shuttle.reversals,house_tick=S.passenger_house_clock and S.passenger_house_clock.counter}
  end
  local pair_fixture=core.settings:get_bool("bayline_rail_pair_preview",false)
  local timber_fixture=core.settings:get_bool("bayline_road_timber_preview",false)
  if timber_fixture then
    S.qa_timber=S.qa_timber or {}
    if not S.qa_timber.departed then S.speed=0 end
    core.register_chatcommand("qa_timber",{func=function(n,mode)
      if n~=username then return false end
      local p=core.get_player_by_name(n)
      local q=S.qa_timber
      if mode=="go" then q.departed=true;S.speed=1
      elseif mode=="north" then p:set_pos({x=35,y=16,z=14})
      elseif mode=="survey" then p:set_pos({x=27.5,y=17,z=13})
      elseif mode=="sawmill" or mode=="photo" or mode=="forest" then
        local m=mode=="photo" and q.loaded and q.loaded.mesh
        local tx,tz=(m and m.x) or (mode=="sawmill" and 27.2 or 28.5),(m and m.z) or
          (mode=="sawmill" and 34.0 or 5.0)
        local x,y,z=tx+5.3,2.4,tz+4.8
        p:set_pos({x=x,y=y,z=z});p:set_look_horizontal(math.atan2(x-tx,tz-z))
        p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.7,math.sqrt((x-tx)^2+(z-tz)^2)))
      end
      return true
    end})
  end
  function extended.timber(n)
    if not timber_fixture then return end
    local out={enabled=api.timber_tools,vehicles={},ind={},mesh={},road_tiles={}}
    local q=S.qa_timber
    for _,ind in pairs(S.stock_timber_industries or {}) do
      local x,z=ind.x+1,ind.z+1
      local node=core.get_node_or_nil({x=x*2,y=1,z=z*2})
      out.ind[ind.kind]={id=ind.id,n=#ind.tiles,mesh=node and node.name,
        received=ind.wood_received or 0,waiting=ind.produced.waiting}
    end
    for _,v in pairs(S.fleet) do
      if v.owner==n then
        out.vehicles[v.engine]={id=v.id,units=v.units,expense=v.expense,delivered=v.delivered,revenue=v.revenue,
          order=v.orders[1] and v.orders[1].action,orders=#v.orders,station=v.station}
      end
    end
    for _,obj in ipairs(core.get_objects_inside_radius({x=28,y=1,z=20},50)) do
      local e=obj:get_luaentity()
      if e and (e.name=="luanttd_core:vehicle_wood_truck" or e.name=="luanttd_core:vehicle_goods_truck") then
        out.mesh[e.name]={at=obj:get_pos(),obj=obj:get_properties().mesh}
      end
    end
    local wood=out.vehicles.wood_truck
    local art=out.mesh["luanttd_core:vehicle_wood_truck"]
    if not q.loaded and wood and wood.units>=10 and wood.delivered==0 and art and art.obj=="bl_witcombe_wood_truck_loaded.obj" then
      S.speed=0;q.loaded={mesh=art.at,units=wood.units,tick=S.passenger_house_clock.counter};api.save()
    end
    out.loaded=q.loaded
    local goods_stop=S.tiles[Sim.id(14,8)].station
    local st=goods_stop and S.stations[goods_stop]
    if st then out.town_goods=S.sites[st.site].received.goods or 0 end
    local plan=api.timber_world.scenario_1751(S)
    if plan then
      local function observe(path)
        for _,id in ipairs(path) do
          local x,z=Sim.xy(id)
          out.road_tiles[x..","..z]=S.tiles[id].build or "-"
        end
      end
      for _,path in ipairs(plan.road_waypoints) do observe(path) end
      observe(plan.mill_goods_spur)
    end
    out.tick=S.passenger_house_clock and S.passenger_house_clock.counter
    return out
  end
  if pair_fixture then
    local mod=core.get_modpath("luanttd_core").."/"
    S.qa_pair=S.qa_pair or {}
    if not S.qa_pair.ready then S.speed=0 end
    core.register_chatcommand("qa_pair",{func=function(n,mode)
      if n~=username then return false end
      local q=S.qa_pair
      if mode=="prepare" and not q.ready then
        for i=1,#S.corner_grid.levels do S.corner_grid.levels[i]=0 end
        local dirty={}
        for id,t in ipairs(S.tiles) do
          t.terrain,t.h,t.build,t.owner,t.site,t.wood,t.house,t.source_house="grass",0,nil,nil,nil,nil,nil,nil
          t.road_town,t.road_bits,t.parcel,t.rail_tracks,t.variant=nil,nil,nil,nil,t.variant or 0
          dirty[#dirty+1]=id
        end
        S.stock_select_goods=false
        local T=dofile(mod.."openttd/rail_track.lua")
        local Signal=dofile(mod.."openttd/rail_signals.lua")(T)
        local f=dofile(mod.."rail_owned_pair_fixture.lua")
        local a,b,c=f(S,Sim,T,api.trackworks,api.rail_dispatch_controller,Signal,n)
        q.ready={a,b,c}
        api.render.update(dirty)
        api.save()
      elseif mode=="go" then S.speed=1
      elseif mode=="one" and S.speed==0 then
        -- Step the ordinary shared clock once without depending on GUI
        -- round-trip timing. Actual train controls are still mouse driven.
        Sim.daily(S);q.manual_day=S.day;api.save()
      end
      if mode=="north" or mode=="survey" then
        local p=core.get_player_by_name(n)
        p:set_pos(mode=="north" and {x=56.5,y=10,z=16.0} or {x=27.5,y=17,z=13})
      end
      if mode=="photo" or mode=="finish" then
        local tx,tz=mode=="photo" and 16.6 or 60.5,mode=="photo" and 27.35 or 20.5
        local x,y,z=tx+5.5,mode=="photo" and 2.6 or 15,tz+6
        local p=core.get_player_by_name(n)
        p:set_pos({x=x,y=y,z=z})
        p:set_look_horizontal(math.atan2(x-tx,tz-z))
        p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.70,math.sqrt((x-tx)^2+(z-tz)^2)))
      end
      return true
    end})
  end
  function extended.rail_pair(n)
    if not pair_fixture then return end
    local O,R=api.rail_owned,api.rail_dispatch_controller
    local q=S.qa_pair
    local p=core.get_player_by_name(n)
    local _,line
    if p then _,line=qa_ui.world_status(p,nil,false) end
    local out={ready=q.ready,phase_hold=q.hold,manual_day=q.manual_day,guide=line}
    local a,b=R.current_paid(S,1),R.current_paid(S,2)
    if not (a and b) then return out end
    local merge=Sim.id(8,14)
    local model_mixed=a.stock_engine~=b.stock_engine
    if not q.wait_event then
      for _,e in ipairs(Sim.rail_paid_motion_events(S)) do
        if e.kind=="waiting" then q.wait_event={train=e.train,tick=e.world_tick};break end
      end
    end
    if not q.hold then
      for _,lead in ipairs({a,b}) do
        local peer=lead==a and b or a
        if lead.consist.parts[1].tile~=merge and lead.consist.parts[2].tile==merge
            and (model_mixed or lead==a and peer.phase=="waiting") then
          local guard=lead==a and Sim.id(8,13) or Sim.id(7,14)
          S.speed=0
          q.hold={before=Sim.rail_paid_status(S,1),second=Sim.rail_paid_status(S,2),
            tick=S.passenger_house_clock.counter,red=R.signal(S,guard,lead==a and 1 or 8)=="red",
            leading=lead.id,peer_phase=peer.phase,
            rail={lead.consist.parts[1].tile,lead.consist.parts[2].tile,peer.consist.parts[1].tile,peer.consist.parts[2].tile}}
          api.save()
          break
        end
      end
    end
    local locos,wagons={},{}
    for _,o in ipairs(core.get_objects_inside_radius({x=36,y=.62,z=28.5},52)) do
      local e=o:get_luaentity()
      if e and (e.name=="luanttd_core:dispatch_steam" or e.name=="luanttd_core:dispatch_jubilee" or e.name=="luanttd_core:dispatch_ginzu" or e.name=="luanttd_core:dispatch_floss") then
        local pos=o:get_pos()
        pos.mesh=o:get_properties().mesh
        locos[#locos+1]=pos
      end
      if e and e.name=="luanttd_core:dispatch_wagon" then wagons[#wagons+1]=o:get_pos() end
    end
    out.phase_hold=q.hold
    out.wait_event=q.wait_event
    out.first,out.second=Sim.rail_paid_status(S,1),Sim.rail_paid_status(S,2)
    out.finance={O.running(S,n,1).running_expense,O.running(S,n,2).running_expense}
    out.stock={a.stock_engine,b.stock_engine}
    out.max_speed={a.max_track_speed,b.max_track_speed}
    out.annual_fp={a.running_year_fp,b.running_year_fp}
    out.trains,out.wagons=locos,wagons
    return out
  end
  if rail_coal_fixture then
    S.qa_railcoal=S.qa_railcoal or {}
    if not S.qa_railcoal.ready then S.speed=0 end
    core.register_chatcommand("qa_railcoal",{func=function(n,mode)
      if n~=username then return false end
      local q=S.qa_railcoal
      if mode=="ready" then q.ready=true end
      if mode=="go" or mode=="resume" then S.speed=1 end
      local p=core.get_player_by_name(n)
      local x,y,z,tx,ty,tz=75,10,38,75,.52,30.5
      if mode=="photo" and q.loaded then
        local w=q.loaded.wagon
        x,y,z,tx,ty,tz=w.x+3.9,2.7,w.z+4.6,w.x,.9,w.z
      elseif mode=="plant" then x,y,z,tx,ty,tz=87,3.1,34.8,81.5,.8,30.5 end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  local function rail_coal_view(n)
    if not rail_coal_fixture then return end
    local q=S.qa_railcoal
    local u=api.rail_owned.list(S,n)[1]
    local coal=Sim.rail_coal_status(S)
    local wagon,cart
    for _,o in ipairs(core.get_objects_inside_radius({x=74,y=.614,z=30.5},38)) do
      local e=o:get_luaentity()
      if e and e.name:match("^luanttd_core:dispatch_coal_") then
        cart=e.name;wagon=o:get_pos()
      end
    end
    if not q.loaded and coal and coal.onboard>0 and cart=="luanttd_core:dispatch_coal_loaded" then
      S.speed=0
      q.loaded={wagon=wagon,units=coal.onboard,clock=coal.tick,loading=coal.loading,tile=coal.cargo_tile}
      api.save()
    end
    if not q.second_load and coal and coal.cycles==1 and coal.onboard>0 and cart=="luanttd_core:dispatch_coal_loaded" then
      S.speed=0
      q.second_load={wagon=wagon,units=coal.onboard,clock=coal.tick,delivered=coal.delivered}
      api.save()
    end
    local st={}
    for _,r in pairs(S.stock_rail_stations or {}) do
      if r.coal_role and r.coal_stage_tile then
        local x,z=Sim.xy(r.coal_stage_tile)
        local node=core.get_node_or_nil({x=x*2,y=1,z=z*2})
        st[r.coal_role]={id=r.id,tile=r.coal_stage_tile,x=x,z=z,model=node and node.name}
      end
    end
    local ind=S.stock_coal_industries and S.stock_coal_industries[2]
    local postal=ind and S.sites[ind.site]
    return {ready=q.ready,loaded=q.loaded,second_load=q.second_load,unit=u,coal=coal,stages=st,wagon_mesh=cart,
      received=postal and postal.received.coal or 0,house_tick=S.passenger_house_clock and S.passenger_house_clock.counter}
  end
  local oneway_fixture=core.settings:get_bool("bayline_road_oneway_preview",false)
  if oneway_fixture then
    local q=S.qa_oneway or {}
    S.qa_oneway=q
    local function at(x,z) return Sim.id(x,z or 12) end
    if not q.ready then
      S.speed=0;S.road_stock_loading=true
      local g=S.corner_grid
      for z=10,15 do for x=6,23 do g.levels[(z-1)*(g.width+1)+x]=0 end end
      for z=10,14 do for x=7,22 do
        S.tiles[at(x,z)]={terrain="grass",h=0,variant=(x+z)%4}
      end end
    end
    core.register_chatcommand("qa_oneway",{func=function(n,mode)
      if n~=username then return false end
      if mode=="prepare" and not q.ready then
        local dirty={}
        local function build(tool,ids)
          local ok,msg,more=Sim.build(S,n,tool,ids);assert(ok,msg)
          for _,i in ipairs(more) do dirty[#dirty+1]=i end
        end
        build("road",Sim.line(at(8),at(20)))
        build("road_station",{at(8),at(20)})
        q.ready=true;api.render.update(dirty);api.save()
      elseif mode=="arrange" and not q.bus then
        local src,dst=S.tiles[at(20)].station,S.tiles[at(8)].station
        q.bus=assert(Sim.purchase(S,n,"bus","passenger",src))
        assert(Sim.add_order(S,n,q.bus,dst));assert(Sim.toggle(S,n,q.bus))
        local v=S.fleet[q.bus]
        for _=1,24 do
          Sim.daily(S)
          local sample=Sim.road_motion_frame(S,v)
          if sample and sample[4]==at(19) then q.started=true;break end
        end
        assert(q.started,"A genuine westbound stock road frame did not leave the eastern stop")
        qa_ui.hud();api.save()
      elseif mode=="go" or mode=="resume" then S.speed=1 end
      local p=core.get_player_by_name(n)
      local x,y,z,tx,ty,tz=28,7.3,17,29,.52,24.5
      if mode=="street" then x,y,z,tx,ty,tz=34,2.5,21.6,29,.52,24.5 end
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
      return true
    end})
  end
  local function oneway_view(n)
    if not oneway_fixture then return end
    local q=S.qa_oneway
    local a,b=Sim.id(8,12),Sim.id(20,12)
    local st,finish=S.stations[S.tiles[a].station],S.stations[S.tiles[b].station]
    local function path(o,d)
      if not o or not d then return false end
      return Sim.path(S,o,d,"road",n)~=nil
    end
    local settings=S.tiles[Sim.id(14,12)].road_disallowed
    local marking=api.oneway.marking(S,Sim.id(14,12))
    local mesh=core.get_node_or_nil({x=28,y=2,z=24})
    local end_mesh=core.get_node_or_nil({x=24,y=2,z=24})
    local ep={ready=q.ready,route_east=path(st,finish),route_west=path(finish,st),
      drd=settings or 0,dir=marking and marking.dir,quota=S.road_oneway_revision or 0,
      surface=mesh and mesh.name,entry=end_mesh and end_mesh.name}
    local v=S.fleet[q.bus]
    if v then
      local f=Sim.road_motion_frame(S,v)
      local c=v.road_speed_state
      ep.road_tile=f and f[4]
      ep.last_stop=v.last_arrival and v.last_arrival.tile
      ep.waiting=c and c.waiting
      ep.target=a
      if not q.waited and ep.waiting=="oneway" then
        S.speed=0
        q.waited={tile=ep.road_tile,day=S.day}
        api.save()
      end
      ep.held=q.waited
    end
    return ep
  end
  local overtake_kind=core.settings:get("bayline_native_overtake")
  local overtake=overtake_kind=="stopped" or overtake_kind=="moving"
  if overtake then
    local root=core.get_modpath("luanttd_core").."/"
    local Fixture=dofile(root.."road_overtake_fixture.lua")(root,Sim)
    core.register_chatcommand("qa_overtake",{func=function(name,operation)
      if name~=username then return false end
      if not S.qa_overtake and operation=="prepare" then
        S.road_stock_house_supply=false
        local cp,changed=Fixture.checkpoint(overtake_kind,S,name)
        S.qa_overtake={lead=cp.lead,follow=cp.follow,kind=cp.kind,x=cp.x,y=cp.y,ctr=cp.ctr}
        S.speed=0;api.render.update(changed);qa_ui.hud();api.save()
      end
      if not S.qa_overtake then return false end
      local p=core.get_player_by_name(name)
      local tx,tz=S.qa_overtake.x/8-.5,24.5
      if operation=="capture_after" then
        local q=S.qa_overtake
        local f=Sim.road_motion_frame(S,S.fleet[q.follow])
        local l=Sim.road_motion_frame(S,S.fleet[q.lead])
        if f and l then tx=(f[1]+l[1])/16-.5 end
        S.speed=0
      end
      local x,y,z=tx-2.4,2.2,20.6
      p:set_pos({x=x,y=y,z=z})
      p:set_look_horizontal(math.atan2(x-tx,tz-z))
      p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-.7,math.sqrt((x-tx)^2+(z-tz)^2)))
      if operation=="resume" then S.speed=1 end
      return true
    end})
  end
  local function overtake_view()
    local q=S.qa_overtake
    if not overtake or not q then return end
    local l,v=S.fleet[q.lead],S.fleet[q.follow]
    local c=v.road_speed_state or {}
    local f=Sim.road_motion_frame(S,v)
    local follower,leader
    for _,o in ipairs(core.get_objects_inside_radius({x=24,y=.55,z=24.5},48)) do
      local e=o:get_luaentity()
      if e and e.name=="luanttd_core:vehicle_"..v.engine then follower=o:get_pos()
      elseif e and e.name=="luanttd_core:vehicle_"..l.engine then leader=o:get_pos() end
    end
    local ground=core.get_node_or_nil({x=22,y=0,z=24})
    return {kind=q.kind,road=ground and ground.name,frame=f and {x=f[1],z=f[2],direction=f[3],tile=f[4],movement_frame=f[15]},
      ctr=c.overtaking_ctr,active=c.overtaking==16,
      simulation_passes=c.overtakes or 0,completed=c.overtake_returns or 0,
      timeline=Sim.road_motion_timeline(S,v.id)~=nil,lead=leader,follow=follower,
      day=S.day,speed=S.speed,engine=v.engine}
  end
  local passing=core.settings:get_bool("bayline_native_passing",false)
  local added,pass_sample
  if passing then
    core.register_chatcommand("qa_passing",{func=function(name)
      if name~=username or added then return false end
      added=true
      return true
    end})
  end
  local function observe_passing(v)
    if not passing or not added or pass_sample or not v then return end
    if added==true and v.route and v.progress>=2 and v.progress<4 then
      local start=S.stations[v.dest]
      local stop=S.stations[v.orders[v.dest_index==1 and 2 or 1].station]
      local id=assert(Sim.purchase(S,username,"bus","passenger",start.id))
      assert(Sim.add_order(S,username,id,stop.id))
      assert(Sim.toggle(S,username,id))
      added=id
    end
    local forward,back
    for _,o in ipairs(core.get_objects_inside_radius({x=26.5,y=.75,z=24.5},7.5)) do
      local ent=o:get_luaentity()
      if ent and ent.name=="luanttd_core:vehicle_bus" then
        local pos,yaw=o:get_pos(),o:get_yaw()
        local dir=math.sin(yaw)
        if math.abs(dir)>.999 and math.abs(math.abs(pos.z-24.5)-.155)<.01 then
          local bus={x=pos.x,z=pos.z,width=o:get_properties().visual_size.x*(leopard and .6485 or .638)}
          if dir>0 then forward=bus else back=bus end
        end
      end
    end
    if forward and back and math.abs(forward.x-back.x)<.30 then
      pass_sample={forward=forward,back=back,gap=math.abs(forward.z-back.z)-(forward.width+back.width)*.5}
    end
  end
  local queue=core.settings:get_bool("bayline_native_queue",false)
  local queue_state
  if queue then
    core.register_chatcommand("qa_roadqueue",{func=function(name)
      if name~=username or queue_state then return false end
      queue_state={stage="stop_leader"}
      return true
    end})
  end
  local function observe_queue(leader)
    if not queue_state or not leader then return end
    local q=queue_state
    if q.stage=="stop_leader" then
      assert(Sim.toggle(S,username,leader.id))
      q.stage="waiting_for_park"
    end
    if q.stage=="waiting_for_park" and not leader.running and leader.station then
      local depot
      for i,t in ipairs(S.tiles) do if t.build=="road_depot" and t.owner==username then depot=i;break end end
      local follower=assert(Sim.purchase(S,username,"bus","passenger",nil,depot))
      assert(Sim.add_order(S,username,follower,leader.station))
      local second=leader.orders[leader.index==1 and 2 or 1].station
      assert(Sim.add_order(S,username,follower,second))
      assert(Sim.toggle(S,username,follower))
      q.leader,q.follower,q.stop,q.stage=leader.id,follower,leader.station,"chasing"
    end
    local follower=q.follower and S.fleet[q.follower]
    local c=follower and follower.road_speed_state
    if q.stage=="chasing" and c and (c.waiting=="road" or c.waiting=="bay") then
      local f=follower.road_motion_frames[c.index]
      local p=leader.road_stop_pose
      if p and f then
        q.wait={reason=c.waiting,day=S.day,leader_tile=p[4],follower_tile=f[4],
          leader_xy={p[1],p[2]},follower_xy={f[1],f[2]}}
        q.stage="blocked"
      end
    elseif q.stage=="blocked" and S.day-q.wait.day>=2 then
      local f=c and follower.road_motion_frames[c.index]
      assert(f and f[1]==q.wait.follower_xy[1] and f[2]==q.wait.follower_xy[2],
        "queued bus advanced before leader was released")
      assert(Sim.toggle(S,username,leader.id))
      q.stage="released"
    elseif q.stage=="released" and (follower.station==q.stop or
      (S.road_stock_loading and follower.last_arrival and follower.last_arrival.tile==S.stations[q.stop].tile)) then
      q.stage="resumed";q.arrival_day=follower.last_arrival and follower.last_arrival.day or S.day
      q.arrival_tick=follower.last_road_arrival_tick
    end
  end
  local function numkeys(t)
    local n=0
    for _ in pairs(t or {}) do n=n+1 end
    return n
  end
  local function observe_grade(v)
    if not grade then return end
    grade_tiles={}
    for _,x in ipairs({12,13,14,16,17,18}) do
      local id=Sim.id(x,12)
      local shape,base,top=api.terrain.tile(id)
      local node=core.get_node_or_nil({x=x*2,y=base+1,z=24})
      local road,road_base=Sim.road_surface(S,id)
      grade_tiles[tostring(x)]={shape=shape,base=base,top=top,road=road,road_base=road_base,node=node and node.name}
    end
    grade_samples.current=nil
    if not v or not v.running then return end
    -- Single isolated test fleet: find its actual streamed scene object,
    -- not merely the intended Sim position/order or the renderer's formula.
    for _,o in ipairs(core.get_objects_inside_radius({x=27.5,y=1,z=24.5},22)) do
      local e=o:get_luaentity()
      if e and e.name==road_visual then
        local p=o:get_pos()
        local r=o:get_rotation()
        local x,y,z=p.x,p.y,p.z
        local moving=vprev and math.abs(x-vprev)>.03
        if math.abs(z-24.5)<.20 and moving then
          local ramp,expected,slope
          -- Check the exact midpoint height through both ramp and apron
          -- seams (includes the rendered contact offset of 0.02 units).
          if x>=25 and x<=36 then
            expected=.52+math.max(0,math.min(1,(x-25.5)/2,(35.5-x)/2))
            local err=math.abs(y-expected)
            grade_samples.height_error=math.max(grade_samples.height_error,err)
          end
          -- Sample pitch away from the centerline derivative transition.
          if x>25.85 and x<27.15 then slope=.5
          elseif x>33.85 and x<35.15 then slope=-.5 end
          if slope then
            local rising=(x>vprev)==(slope>0)
            ramp=rising and "ascending" or "descending"
            grade_samples[ramp]=grade_samples[ramp]+1
            -- Native Obj rotation tilts the displayed nose down for
            -- positive X. Verify the mesh convention, not merely the
            -- unsigned magnitude at the sampled surface position.
            local expect_pitch=math.atan(rising and -.5 or .5)
            grade_samples.current=ramp
            grade_samples.pitch_error=math.max(grade_samples.pitch_error,math.abs(r.x-expect_pitch))
            grade_samples["last_"..ramp]={x=x,y=y,z=z,pitch=r.x}
          end
        end
        vprev=x
        return
      end
    end
  end
  local yapf={}
  local function observe_yapf(v)
    if not v or not v.road_route_cost then return end
    yapf.route_cost=v.road_route_cost
    -- x=13 falls between the fork and rejoin, where lane shape is straight.
    for _,obj in ipairs(core.get_objects_inside_radius({x=26.5,y=.8,z=24.5},4)) do
      local e=obj:get_luaentity()
      if e and e.name==road_visual then
        local q=obj:get_pos()
        if q.x>24.8 and q.x<28.2 then
          if math.abs(q.z-24.5)<.26 then yapf.straight={x=q.x,z=q.z} end
          if math.abs(q.z-26.5)<.26 then yapf.detour={x=q.x,z=q.z} end
        end
      end
    end
  end
  local service_title
  local function write()
    local player=core.get_player_by_name(username)
    local company=S.companies[username]
    local fleet={}
    for id,v in pairs(S.fleet) do
      if v.owner==username then fleet[#fleet+1]=v end
    end
    local builds,track_nodes={},{}
    for id,t in pairs(S.tiles) do
      if t.owner==username and t.build then
        local x,z=Sim.xy(id)
        builds[x..","..z]={name=t.build,station=t.station}
        if t.rail_tracks then
          local shape,base=0,t.h
          if api.terrain then shape,base=api.terrain.tile(id) end
          local grade,level=api.trackworks.surface(shape,base,t.rail_tracks)
          local node=grade and core.get_node_or_nil({x=x*2,y=level+(grade>0 and 2 or 1),z=z*2})
          local wire=grade and core.get_node_or_nil({x=x*2,y=level+2,z=z*2})
          track_nodes[x..","..z]={mask=t.rail_tracks,node=node and node.name,
            railtype=t.rail_type or 0,wire=wire and wire.name}
          if t.rail_station_id then track_nodes[x..","..z].station=t.rail_station_id end
          if t.rail_depot_dir then track_nodes[x..","..z].depot=t.rail_depot_dir end
        end
      end
    end
    local track_route
    local start=Sim.id(14,16)
    local goal=Sim.id(14,18)
    if S.tiles[start].rail_tracks and S.tiles[goal].rail_tracks then
      local path,cost=api.trackworks.plan(S,start,goal,username)
      if path then
        track_route={cost=cost,tiles={}}
        for _,frame in ipairs(path) do
          local x,z=Sim.xy(frame.tile)
          track_route.tiles[#track_route.tiles+1]=x..","..z
        end
      end
    end
    local service_route
    local facility=S.tiles[goal].rail_station_id
    if S.tiles[start].rail_depot_dir and facility then
      local path,cost=api.trackworks.service_route(S,username,{tile=start},facility)
      if path then
        service_route={cost=cost,station=facility,tiles={}}
        for _,frame in ipairs(path) do
          local x,z=Sim.xy(frame.tile)
          service_route.tiles[#service_route.tiles+1]=x..","..z
        end
      end
    end
    local rail_state
    if track_route then
      for _,obj in ipairs(core.get_objects_inside_radius({x=31.5,y=.7,z=34.5},5)) do
        local ent=obj:get_luaentity()
        if ent and ent.name=="luanttd_core:vehicle_steam" then
          local q=obj:get_pos()
          local turning=q.x>31.65 and q.x<32.43 and q.z>32.54 and q.z<33.4
          rail_state={x=q.x,y=q.y,z=q.z,yaw=obj:get_yaw(),turning=turning,
            arc_error=math.abs(math.sqrt((q.x-31.5)^2+(q.z-33.5)^2)-1)}
          break
        end
      end
    end
    if S.road_mail then
      mail_stops={}
      for _,st in pairs(S.stations) do if st.stop_type=="truck" then
        local x,z=Sim.xy(st.tile)
        local waiting,accept=Sim.mail_stop_status(S,st)
        local at={x=2*x,y=1,z=2*z}
        local n=core.get_node_or_nil(at)
        mail_stops[x..","..z]={waiting=waiting,accept=accept,node=n and n.name}
      end end
      if not mail_mesh then
        for _,obj in ipairs(core.get_objects_inside_radius({x=28.5,y=.52,z=24.5},8)) do
          local e=obj:get_luaentity()
          local p=obj:get_pos()
          if e and e.name=="luanttd_core:vehicle_mail_van" and math.abs(p.y-.52)<.01
              and math.abs(math.abs(p.z-24.5)-.155)<.01 then mail_mesh=p;break end
        end
      end
    end
    local rail_pilot
    local pilot=api.rail_platform_run and api.rail_platform_run.current(S)
    if pilot then
      rail_pilot={phase=pilot.phase,tick=pilot.simulation_ticks,steps=pilot.stock_steps,arrival=pilot.arrival,
        failure=pilot.failure}
      for _,obj in ipairs(core.get_objects_inside_radius({x=31.5,y=.7,z=34.5},9)) do
        local ent=obj:get_luaentity()
        if ent and ent.name=="luanttd_core:vehicle_diesel" then rail_pilot.mesh=obj:get_pos();break end
      end
    end
    local constructed
    if terrain_build then
      local t=S.stock_road_bridges and S.stock_road_bridges[1]
      constructed={corner=Terrain.corner(S.corner_grid,6,15), meshes={}}
      if t then
        constructed.bridge={deck=t.deck,length=t.total_length,price=t.price}
        for x=17,29 do
          local n=core.get_node_or_nil({x=2*x,y=t.deck,z=6})
          if n then constructed.meshes[tostring(x)]=n.name end
        end
      end
    end
    if tunnel_run then
      local van=S.fleet[S.bridge_service_id]
      local idx=van and van.road_speed_state and van.road_speed_state.index
      local f=idx and van.road_motion_frames[idx]
      local inside=false
      for _,obj in ipairs(core.get_objects_inside_radius({x=51.5,y=.52,z=24.5},8)) do
        local e=obj:get_luaentity()
        if e and e.name=="luanttd_core:vehicle_bus" then
          local p=obj:get_pos()
          if p.x>47.5 and p.x<53.5 then inside=true end
          if p.x>55.5 and p.x<62 and math.abs(p.y-.52)<.02 then tunnel_exit=p end
        end
      end
      if f and f[13] and f[1]>24*16 and f[1]<27*16 and not inside then
        tunnel_hidden={stock_x=f[1],stock_z=f[2],tile=f[4]}
      end
    end
    if bridge_run and not bridge_pass then
      for _,obj in ipairs(core.get_objects_inside_radius({x=50.5,y=1.52,z=24.5},3)) do
        local ent=obj:get_luaentity()
        local pos=obj:get_pos()
        if ent and ent.name=="luanttd_core:vehicle_bus" and math.abs(pos.y-1.52)<.012
            and pos.x>=48 and pos.x<=53 and math.abs(math.abs(pos.z-24.5)-.155)<.012 then
          bridge_pass={x=pos.x,y=pos.y,z=pos.z}
          break
        end
      end
    end
    local coal_view
    if coal_fixture then
      local v
      for _,q in pairs(S.fleet) do if q.owner==username and q.engine=="coal_tipper" then v=q;break end end
      local power,production=0,0
      for _,industry in pairs(S.stock_coal_industries or {}) do
        if industry.kind=="power_station" then
          local site=S.sites[industry.site]
          power=site and (site.received.coal or 0) or 0
        elseif industry.produced then production=industry.produced.rate end
      end
      coal_view={ready=S.qa_coal_ready,mine=production,plant=power,
        revenue=v and v.revenue or 0,delivered=v and v.delivered or 0,units=v and v.units or 0,
        boarded=v and v.last_board or nil,paid=v and v.last_fare or nil,
        tick=S.stock_load_tick,stops={},meshes={}}
      for _,pos in ipairs({{31,14},{41,14}}) do
        local id=Sim.id(pos[1],pos[2])
        local st=S.stations[S.tiles[id].station]
        if st then
          local waiting,accepts=Sim.coal_stop_status(S,st)
          coal_view.stops[#coal_view.stops+1]={waiting=waiting,accepts=accepts,id=st.id,tile=id}
        end
      end
      for _,q in ipairs({{"mine",31,12},{"plant",41,13}}) do
        local _,base=api.terrain.tile(Sim.id(q[2],q[3]))
        local n=core.get_node_or_nil({x=q[2]*2,y=base+1,z=q[3]*2})
        if n then coal_view.meshes[q[1]]=n.name end
      end
      for _,o in ipairs(core.get_objects_inside_radius({x=72,y=.52,z=28.5},16)) do
        local e=o:get_luaentity()
        if e and e.name=="luanttd_core:vehicle_coal_tipper" and o:get_properties().mesh=="bl_coal_tipper_loaded.obj" then
          S.qa_coal_loaded=o:get_pos()
        elseif e and e.name=="luanttd_core:coal_winding_sheaves" then
          local angle=o:get_rotation().x
          if S.qa_coal_gears and math.abs(S.qa_coal_gears-angle)>.12 then S.qa_coal_winding=true end
          S.qa_coal_gears=angle
        end
      end
      coal_view.loaded=S.qa_coal_loaded;coal_view.winding=S.qa_coal_winding
    end
    local air_view
    if air_fixture then
      local a=S.airport_pilot or api.airfield.current()
      local state=S.qa_air
      air_view={fields=numkeys(S.stock_small_airports or {}),arrivals=a and a.arrivals or 0,
        last=a and a.last_airfield,phase=a and a.phase or "idle",departures=a and a.departures or 0,
        events=state.events,mid=state.mid,failure=a and a.failure,academy={},
        owned=S.stock_owned_aircraft or api.airfield.owned(1),engine=a and a.engine_id,cash=company and company.cash,
        expense=company and company.expense}
      local positions=air_paid and {hangar={10,12},runway_west={7,14},runway_east={23,14}} or
        {hangar={10,16},runway_west={7,18},runway_east={33,18}}
      if player and air_view.fields==0 then
        local x,z=7,air_paid and 12 or 16
        local seen={}
        for _,ref in ipairs(core.get_objects_inside_radius({x=2*x+3.5,y=.7,z=2*z+2.5},5)) do
          local ent,pos=ref:get_luaentity(),ref:get_pos()
          if ent and ent.name=="luanttd_core:tile_selector" and
            ref:get_properties().textures[1]=="bl_selector_valid.png" then
            local u,v=math.floor((pos.x+.5)/2),math.floor((pos.z+.5)/2)
            if u>=x and u<x+4 and v>=z and v<z+3 then seen[u..","..v]=true end
          end
        end
        air_view.outlines=numkeys(seen)
      end
      for k,p in pairs(positions) do
        local cell=Sim.id(p[1],p[2])
        local _,base=api.terrain.tile(cell)
        local node=core.get_node_or_nil({x=p[1]*2,y=base+1,z=p[2]*2})
        if node then air_view.academy[k]=node.name end
      end
      if air_paid then
        local paid=Sim.air_paid_status(S)
        air_view.paid=paid
        air_view.house_tick=S.passenger_house_clock and S.passenger_house_clock.counter
        air_view.revenue=company and company.revenue or 0
        air_view.paid_units=company and company.paid_units or 0
        if paid and paid.terminal_tile then
          local tile=S.tiles[paid.terminal_tile]
          local record=tile and tile.airfield
          local field=record and S.stock_small_airports[record.airport]
          air_view.terminal_valid=field and field.id==paid.last_airfield and field.origin~=paid.terminal_tile
        end
      end
      if a then
        local v=a.vehicle
        air_view.state={x=v.x,y=v.y,z=v.z,tick=v.tick,target=a.target}
        for _,o in ipairs(core.get_objects_inside_radius({x=v.x/8-.5,y=(v.y-1)/8+.5,z=v.z/8-.5},2)) do
          local e=o:get_luaentity()
          if e and (e.name=="luanttd_core:stock_bayshore_trimotor" or e.name=="luanttd_core:stock_coleman_count"
              or e.name=="luanttd_core:stock_bakewell_cotswald") then
            air_view.aircraft=o:get_pos();air_view.model=o:get_properties().mesh
          end
        end
        if not state.mid and a.phase=="flying" and air_view.aircraft and air_view.aircraft.y>6 then
          S.speed=0
          state.mid={vehicle=air_view.state,mesh=air_view.aircraft}
          air_view.mid=state.mid
          api.save()
        end
      end
    end
    local ship_view
    if ship_fixture then
      local shot=S.ship_pilot
      ship_view={depots=numkeys(S.stock_ship_depots or {}),docks=numkeys(S.stock_ship_stations or {}),
        arrivals=shot and shot.arrivals or 0,last_dock=shot and shot.last_dock,
        phase=shot and shot.phase or "inactive",steps=shot and shot.steps or 0,fail=shot and shot.failure,
        nodes={}}
      for i,at in pairs({["shore"]={5,32},["pier"]={5,33},["shed"]={11,35}}) do
        local t=S.tiles[Sim.id(at[1],at[2])]
        if t.ship then
          local _,base=api.terrain.tile(Sim.id(at[1],at[2]))
          local node=core.get_node_or_nil({x=2*at[1],y=base+1,z=2*at[2]})
          if node then ship_view.nodes[i]=node.name end
        end
      end
      local anchor=(aqua_fixture or lock_fixture) and {x=45,y=1.5,z=40} or
        paid_ferry_fixture and {x=20,y=.5,z=23} or {x=18,y=.5,z=69}
      for _,o in ipairs(core.get_objects_inside_radius(anchor,32)) do
        local ent=o:get_luaentity()
        if ent and ent.name=="luanttd_core:stock_harbor_ferry" then
          ship_view.ferry=o:get_pos();ship_view.yaw=o:get_yaw()
          if aqua_fixture and ship_view.ferry.y>1.48 and ship_view.ferry.x>43 and
              ship_view.ferry.x<48 and shot.vehicle.track==64 then
            S.qa_aqua_pass={position=ship_view.ferry,stock=shot.vehicle.track,level=shot.vehicle.z}
          end
        end
      end
    end
    if paid_ferry_fixture and ship_view then
      ship_view.paid=Sim.ferry_paid_status(S)
      local p=S.ship_pilot
      ship_view.fleet_tick=p and p.vehicle.tick
      ship_view.house_tick=S.passenger_house_clock and S.passenger_house_clock.counter
      ship_view.stock_tick=S.stock_load_tick
      if buoy_fixture then
        local target=Sim.id(19,12)
        local part=S.tiles[target].ship
        ship_view.buoy=part and part.kind=="buoy" and part.station
        ship_view.buoy_mesh=core.get_node({x=38,y=1,z=24}).name
        if p and p.via then
          ship_view.via=p.via
          ship_view.pass=p.last_buoy_pass
          ship_view.order=p.vehicle.order
          local d=Sim.distance(p.vehicle.tile,target)
          if not S.qa_buoy_stop and p.vehicle.order and p.vehicle.order.kind=="waypoint" and
              p.via.passes==0 and d==4 then
            S.qa_buoy_stop={distance=d,tile=p.vehicle.tile,tick=p.vehicle.tick}
            S.speed=0
            api.save()
          end
        end
        ship_view.buoy_stop=S.qa_buoy_stop
      end
      local company=S.companies[username]
      ship_view.revenue=company and company.revenue
      ship_view.paid_units=company and company.paid_units
    end
    if lock_fixture and ship_view then
      local id=Sim.id(22,20)
      local lock=(S.stock_ship_locks or {})[id]
      local ferry=S.ship_pilot
      ship_view.lock=lock and lock.presentation
      ship_view.midwater=S.qa_lock.mid
      ship_view.levels=S.qa_lock.levels
      if lock then
        local b=core.get_node_or_nil({x=44,y=1,z=40})
        ship_view.lock_mesh=b and b.name
      end
      if lock and ferry and ferry.vehicle.tile==id and ship_view.lock then
        local frame=ship_view.lock
        local state=tonumber(frame.phase)
        if state>0 and state<1 and not frame.lower and not frame.upper then
          local pool,gates=nil,0
          for _,o in ipairs(core.get_objects_inside_radius({x=44.5,y=1.0,z=40.5},3)) do
            local e=o:get_luaentity()
            if e and e.name=="luanttd_core:ship_lock_chamber_water" then pool=o:get_pos() end
            if e and e.name:match("^luanttd_core:ship_lock_gate_.+_closed$") then gates=gates+1 end
          end
          S.qa_lock.levels[ferry.vehicle.direction..":"..ferry.vehicle.z]={dir=ferry.vehicle.direction,phase=frame.phase}
          if not S.qa_lock.mid and pool and gates==2 and ship_view.ferry then
            S.qa_lock.mid={pool=pool,gates=gates,ferry=ship_view.ferry,stock=ferry.vehicle.z,phase=frame.phase}
            ship_view.midwater=S.qa_lock.mid
            S.speed=0;api.save()
          end
        end
      end
    end
    if aqua_fixture and ship_view then
      ship_view.aqueduct=numkeys(S.stock_aqueducts or {})
      ship_view.crossed=S.qa_aqua_pass
      local a=core.get_node_or_nil({x=46,y=1,z=40})
      local road=core.get_node_or_nil({x=44,y=0,z=40})
      local river=core.get_node_or_nil({x=46,y=0,z=40})
      ship_view.span=a and a.name
      ship_view.road=road and road.name
      ship_view.river=river and river.name
      local a=S.tiles[Sim.id(19,20)]
      ship_view.canal=a.stock_canal and a.water_class
    end
    local rail_work
    if rail_build_fixture then
      rail_work={track=0,depot=0,platforms=numkeys(S.stock_rail_stations or {}),signals=0}
      for _,t in ipairs(S.tiles) do
        if t.rail_tracks then rail_work.track=rail_work.track+1 end
        if t.rail_depot_dir then rail_work.depot=rail_work.depot+1 end
      end
      local d=S.stock_rail_dispatch
      if d then rail_work.signals=numkeys(d.signals.records) end
    end
    local crossing_view
    if crossing_fixture then
      local q=S.qa_crossing
      local r=api.crossings.world.record(S,cross_id)
      local n=core.get_node_or_nil({x=28,y=1,z=24})
      local d=S.stock_rail_dispatch
      local run=d and d.runs[1]
      local function road_tile(id)
        local v=S.fleet[id]
        local f=v and Sim.road_motion_frame(S,v)
        return f and f[4]
      end
      local road_mesh,engine_mesh,wagon_mesh
      local nearest=math.huge
      for _,o in ipairs(core.get_objects_inside_radius({x=28.5,y=.6,z=24.5},9)) do
        local e=o:get_luaentity()
        if e and e.name=="luanttd_core:vehicle_bus" then
          local p=o:get_pos()
          local dist=math.abs(p.x-28.5)+math.abs(p.z-24.5)
          if dist<nearest then road_mesh=p;nearest=dist end
        elseif e and e.name=="luanttd_core:dispatch_locomotive" then engine_mesh=o:get_pos()
        elseif e and e.name=="luanttd_core:dispatch_wagon" then wagon_mesh=o:get_pos() end
      end
      crossing_view={ready=q.ready,gate=r and r.phase,barred=r and r.barred,mesh=n and n.name,
        checked_road_tile=road_tile(q.bus),cross_tile=cross_id,denied=q.denied,opposite=road_tile(q.opposing),
        target_station=q.opposing and S.fleet[q.opposing].last_arrival and S.fleet[q.opposing].last_arrival.tile,
        held=q.hold,tail=q.tail,arrived=q.arrived,train=run and run.phase,clock=d and d.ticks,
        road_mesh=road_mesh,engine_mesh=engine_mesh,wagon_mesh=wagon_mesh,destination=Sim.id(11,12)}
    end
    local span_view
    if rail_span_fixture then
      local q=S.qa_rail_span
      local d=S.stock_rail_dispatch
      local run=d and d.runs[1]
      local stock={}
      for _,p in ipairs(S.stock_rail_spans or {}) do stock[p.kind]={price=p.price,length=p.total_length,level=p.deck or p.base} end
      local meshes={}
      for name,pt in pairs({west={x=10,y=5,z=20},deck={x=14,y=5,z=20},pier={x=14,y=4,z=20},east={x=18,y=5,z=20},
          portal={x=26,y=5,z=20},exit={x=36,y=5,z=20}}) do
        local node=core.get_node_or_nil(pt)
        if node then meshes[name]=node.name end
      end
      local engine,wagon
      for _,obj in ipairs(core.get_objects_inside_radius({x=24,y=5.6,z=20.5},38)) do
        local ent=obj:get_luaentity()
        if ent and ent.name=="luanttd_core:dispatch_locomotive" then engine=obj:get_pos()
        elseif ent and ent.name=="luanttd_core:dispatch_wagon" then wagon=obj:get_pos() end
      end
      if not q.mid and engine and wagon and engine.x>12.2 and engine.x<17.4 and engine.y>5.55 and engine.y<5.69 then
        q.mid={head=engine,tail=wagon,clock=d.ticks}
        S.speed=0;api.save()
      end
      span_view={ready=q.ready,routes=stock,meshes=meshes,phase=run and run.phase or "idle",
        failure=d and d.failure,mid=q.mid,clock=d and d.ticks,head=engine,tail=wagon,events=q.events,
        exit_visible=q.show_exit}
    end
    local dispatch_view
    if dispatch_fixture and S.stock_rail_dispatch then
      local qa,d=S.qa_dispatch,S.stock_rail_dispatch
      local a,b=d.runs[1],d.runs[2]
      local count,signals=0,{}
      for _,obj in ipairs(core.get_objects_inside_radius({x=18.5,y=.612,z=18.5},32)) do
        local ent=obj:get_luaentity()
        if ent and (ent.name=="luanttd_core:dispatch_locomotive" or ent.name=="luanttd_core:dispatch_wagon") then
          count=count+1
          if rail_grade_fixture and ent.name=="luanttd_core:dispatch_locomotive" then
            local q,r=obj:get_pos(),obj:get_rotation()
            local angle=(r.x+math.pi)%(2*math.pi)-math.pi
            local mark=math.abs(angle)>.3 and (angle<0 and "up" or "down") or nil
            if mark and q.y>.614 and q.y<1.615 then
              qa.grade=qa.grade or {}
              qa.grade[mark]=qa.grade[mark] or {p=q,pitch=angle,stock=a and a.z}
              if mark=="up" and not qa.frozen then
                S.speed=0;qa.frozen=d.ticks;api.save()
              end
            end
          end
        end
        if ent and ent.name:match("^luanttd_core:dispatch_signal_") then
          signals[#signals+1]={name=ent.name,pos=obj:get_pos()}
        end
      end
      dispatch_view={ready=qa.ready,waiting=a and a.phase,other=b and b.phase,drawing=count,signs=signals,
        reversed=a and a.consist.reversed or false,
        stock_steps=a and a.stock_steps or 0,
        grade=qa.grade,paid=paid_rail_fixture and Sim.rail_paid_status(S) or nil,
        frozen=qa.frozen,clock=d.ticks,claim=d.life.bits[rail_crossing],failure=d.failure,
        signal=api.rail_dispatch_controller.signal(S,Sim.id(8,9),8),events=qa.events,
        wagon_on_crossing=b and b.consist.parts[2].tile==rail_crossing or false,
        head_on_crossing=b and b.consist.parts[1].tile==rail_crossing or false}
    end
    local tram
    if tram_fixture then
      local p=S.tram_pilot
      tram={count=0,nodes={},arrivals=p and p.arrivals or 0,steps=p and p.steps or 0,
        phase=p and p.phase,leg=p and p.leg,ticks=p and p.ticks or 0}
      for id,t in pairs(S.tiles) do
        if t.tram then
          local x,z=Sim.xy(id)
          tram.count=tram.count+1
          local sample=core.get_node_or_nil({x=2*x,y=t.h+1,z=2*z})
          if sample then tram.nodes[x..","..z]=sample.name end
        end
      end
      for _,obj in ipairs(core.get_objects_inside_radius({x=16.5,y=.512,z=20.5},12)) do
        local ent=obj:get_luaentity()
        if ent and ent.name=="luanttd_core:tram_preview_vehicle" then tram.vehicle=obj:get_pos();tram.yaw=obj:get_yaw() end
      end
    end
    local stop_state={}
    if S.road_economy and Sim.waiting_passengers then
      for id,st in pairs(S.stations) do
        if st.owner==username then
          stop_state[tostring(id)]={waiting=Sim.waiting_passengers(S,st),service_day=st.passenger_service_day}
        end
      end
    end
    local order_ids={}
    table.sort(fleet,function(a,b) return a.id<b.id end)
    local v=fleet[1]
    local bus_bay
    if S.road_bay_build or S.stock_road_bays then
      local id=Sim.id(11,12)
      local status=Sim.road_bay_status(S,id)
      local frame={}
      local meshes={}
      for _,bus in ipairs(fleet) do
        frame[tostring(bus.id)]={claim=bus.road_bay_claim,first_order=bus.orders[1] and bus.orders[1].action,
          station=bus.station,wait=bus.road_speed_state and bus.road_speed_state.waiting,
          position=Sim.position(S,bus),arrived=bus.last_road_arrival_tick,departed=bus.last_departure_tick}
      end
      if status then
        for _,obj in ipairs(core.get_objects_inside_radius({x=22.5,y=.52,z=24.5},1.05)) do
          local e=obj:get_luaentity()
          if e and e.name=="luanttd_core:vehicle_bus" then meshes[#meshes+1]=obj:get_pos() end
        end
      end
      bus_bay={id=id,status=status,station=S.tiles[id].station,fleet=frame,meshes=meshes,
        node=core.get_node({x=22,y=1,z=24}).name}
    end
    observe_passing(v)
    observe_queue(v)
    source_motion_seen=source_motion_seen or (v and v.road_motion_frames and #v.road_motion_frames>16) or false
    observe_grade(v)
    observe_lane()
    observe_yapf(v)
    if v then for _,o in ipairs(v.orders or {}) do order_ids[#order_ids+1]=o.station end end
    local t=player and api.world.target(player)
    local px,pz
    if t then px,pz=Sim.xy(t) end
    local camera=player and {pos=player:get_pos(),eye=player:get_properties().eye_height,
      pitch=player:get_look_vertical(),yaw=player:get_look_horizontal()} or nil
    local depot_hint
    if rail_build_fixture and player and t and player:get_wielded_item():get_name()=="luanttd_core:menu_rail_depot_tool" then
      depot_hint=select(3,qa_ui.preview(player,t))
    end
    local obj={depot_hint=depot_hint,camera=camera,present=player~=nil,hotbar=player and player:get_wield_index() or 0,
      menu=player and api.world.menu(player),hotbar_layout=player and api.world.hotbar_layout and api.world.hotbar_layout(player),crowd=crowd_samples,wield_item=player and player:get_wielded_item():get_name(),
      jump_map=extended.jump_map_live,
      water_fx=extended.water_fx and extended.water_fx(player),
      form=form,buttons=buttons,panel=panel,service_title=service_title,last_fields=last_fields,aim=aim,
      target=t and (px..","..pz) or "-", day=S.day,
      road_gesture=player and qa_ui.anchor(player),
      coal_view=coal_view,air_view=air_view,overtake=overtake_view(),oneway=oneway_view(username),owned_rail=owned_rail_view(username),rail_coal=rail_coal_view(username),crossing_view=crossing_view,rail_span_view=span_view,ship_view=ship_view,rail_work=rail_work,dispatch_view=dispatch_view,tram=tram,builds=builds,track_nodes=track_nodes,track_route=track_route,rail_locomotive=rail_state,facility_route=service_route,rail_pilot=rail_pilot,terrain_construction=constructed,bridge_pass=bridge_pass,tunnel_hidden=tunnel_hidden,tunnel_exit=tunnel_exit,postal_stops=mail_stops,postal_mesh=mail_mesh,stops=numkeys(S.stations),fleets=#fleet,
      bus=v and (v.engine=="bus" or v.engine=="leopard_bus") or false, engine=v and v.engine,
      orders=order_ids,
      grade_tiles=grade_tiles,grade_samples=grade and grade_samples or nil,observed_turn=observed_turn,lane=lane_sample,source_motion=source_motion_seen,passing=pass_sample,road_queue=queue_state,
      operating=v and v.running or false, delivered=v and v.delivered or 0,
      road_stock_clock=S.road_stock_clock,road_stock_house_supply=S.road_stock_house_supply,
      road_stock_loading=S.road_stock_loading,stock_loading_tick=S.stock_load_tick,
      last_road_arrival_tick=v and v.last_road_arrival_tick,
      last_road_departure_tick=v and v.last_departure_tick,
      house_tick=S.passenger_house_clock and S.passenger_house_clock.counter,
      vehicle_revenue=v and v.revenue or 0,
      regal=v and v.stock_regal,regal_capacity=v and v.stock_regal and Sim.vehicle_capacity(v),
      regal_load_capacity=v and v.stock_regal and v.load_state and v.load_state.capacity,
      vehicle_expense=v and v.expense,regal_units=v and v.stock_regal and v.units,
      company_expense=company and company.expense,company_fraction=company and company.stock_money_fraction,
      fare=v and v.last_fare, arrival=v and v.last_arrival, boarded=v and v.last_board,
      road_economy=S.road_economy==true,stop_state=stop_state,yapf=yapf,bus_bay=bus_bay,
      rail_pair=extended.rail_pair(username),timber=extended.timber(username),growth=extended.growth(),yate=extended.yate(),
      guarded_junction=extended.junction(username),air_fleet=extended.air_fleet and extended.air_fleet(username),
      bus_market=extended.market(v),
      depot_return=extended.depot_return and extended.depot_return(v,username),
      block_rail=extended.block_rail and extended.block_rail(),
      farm=extended.farm and extended.farm(username),
      oil=extended.oil and extended.oil(username),
      rail_oil=extended.rail_oil and extended.rail_oil(),
      shared_orders=extended.shared_orders and extended.shared_orders(username),
      fault=extended.fault and extended.fault(),
      auto_service=extended.auto_service and extended.auto_service(),
      coast=extended.coast and extended.coast(),
      generated=extended.generated and extended.generated(username),
      electric=extended.electric and extended.electric(username),
      existing_crossing=extended.existing_crossing and extended.existing_crossing(),
      road_bend=extended.road_bend and extended.road_bend(player),
      clear_water=extended.clear_water and extended.clear_water(),
      demolition=extended.demolition and extended.demolition(),
      starter_map=S.qa_coastal,starter=extended.starter and extended.starter(username),
      stock_workbenches=api.stock_workbenches_active and {
        bridges=api.structure_tools,rail=api.rail_build~=nil,rail_owned=api.rail_owned~=nil,rail_goods=api.rail_goods_tools,
        rail_spans=api.rail_spans~=nil,crossings=api.crossing_tools,rail_coal=api.rail_coal_tools,
        ship=api.ship_tools,air=api.airport_tools,tram=api.tram_tools,freight=api.freight_tools,
        oneway=api.oneway_tools,bays=api.road_bay_tools,mail=S.road_mail,
        paid_air=S.air_paid_service,paid_ship=S.ship_paid_service,paid_rail=S.rail_paid_service,
        ordinary=S.qa_coastal and {coastal=api.coastal_flood_tools,growth=api.town_growth~=nil,airpair=S.air_fleet_preview,
          railpair=api.rail_owned_pair_tools,block=api.rail_block_tools,buses=S.stock_bus_market~=nil,
          maintenance=api.bus_service_interval and api.bus_service_interval>0,yate=api.ship_coal_tools,timber=api.timber_tools} or nil,
      } or nil,
      cash=company and company.cash,
      paid_units=company and company.paid_units or 0,revenue=company and company.revenue or 0}
    local fp=assert(io.open(trace..".tmp","w"))
    fp:write(core.write_json(obj))
    fp:close()
    assert(os.rename(trace..".tmp",trace))
  end
  local show,close=core.show_formspec,core.close_formspec
  core.show_formspec=function(n,key,markup)
    if n==username then
      service_title=markup:match("label%[%d%.%d+,%d%.%d+;([^%]]*)%]")
      form,buttons,panel=markup~="" and key or nil,{},nil
      local w,h=markup:match('size%[([%d%.]+),([%d%.]+)%]')
      local bg=markup:match('bgcolor%[#(%x%x%x%x%x%x)')
      if w and h and bg then panel={tonumber(w),tonumber(h),bg} end
      extended.jump_map_live=nil
      if (key=="luanttd_core:dispatch" or key=="luanttd_core:worker_jump") and markup:find(";bl_map_clear.png;",1,true) then
        local count=0
        for _ in markup:gmatch(";bl_map_clear%.png;jump_%d+;") do count=count+1 end
        local labels=0
        for _ in markup:gmatch(";bl_map_clear%.png;jump_place_%d+;") do labels=labels+1 end
        extended.jump_map_live={count=count,labels=labels,detail=markup:find("LOCAL DETAIL",1,true)~=nil}
      end
      for x,y,w,h,id in markup:gmatch("button[_a-z]*%[([%d%.]+),([%d%.]+);([%d%.]+),([%d%.]+);([%w_]+);") do
        buttons[id]={tonumber(x),tonumber(y),tonumber(w),tonumber(h)}
      end
    end
    return show(n,key,markup)
  end
  core.close_formspec=function(n,key)
    if n==username then form,buttons,panel=nil,{},nil;extended.jump_map_live=nil end
    return close(n,key)
  end
  -- Register at front in this disposable world to observe even handled forms.
  table.insert(core.registered_on_player_receive_fields,1,function(p,key,f)
    if p:get_player_name()==username then
      last_fields={form=key,fields=f}
      if f.quit then form,buttons,panel=nil,{},nil end
    end
    return false
  end)
  core.register_chatcommand("qa_aim",{params="<x> <z> [side]",func=function(name,args)
    local a,b,side=args:match("^(%d+) (%d+) *(%a*)$")
    local x,z=tonumber(a),tonumber(b)
    if api.road_first and not core.settings:get_bool("luanttd_native_depot_facing",false) or name~=username or not x or not Sim.id(x,z) then return false,"Invalid QA aim" end
    local p=core.get_player_by_name(name)
    local pitch=1.52
    local eye=p:get_properties().eye_height
    local yaw=({north=0,east=math.pi/2,south=math.pi,west=3*math.pi/2})[side] or math.pi/2
    local dist=(9+eye-.5)/math.tan(pitch)
    p:set_pos({x=x*2+.5+math.sin(yaw)*dist,y=9,z=z*2+.5-math.cos(yaw)*dist})
    p:set_look_horizontal(yaw)
    p:set_look_vertical(pitch)
    aim=x..","..z
    return true
  end})
  core.register_chatcommand("qa_gradeview",{func=function(name)
    if not grade or name~=username then return false end
    local player=core.get_player_by_name(name)
    local x,y,z,look_x,look_y,look_z=31.5,6.4,19,31,1,24.5
    player:set_pos({x=x,y=y,z=z})
    player:set_look_horizontal(math.atan2(x-look_x,look_z-z))
    player:set_look_vertical(math.atan2(y+player:get_properties().eye_height-look_y,
      math.sqrt((x-look_x)^2+(z-look_z)^2)))
    aim="gradeview"
    return true
  end})
  local elapsed=0
  core.register_globalstep(function(dt)
    observe_turn()
    elapsed=elapsed+dt
    if elapsed>=(grade and .08 or .15) then elapsed=0;write() end
  end)
end
