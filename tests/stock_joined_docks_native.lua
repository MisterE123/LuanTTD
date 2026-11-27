-- A real Luanti client and the ordinary worker. No installed docks,
-- fixture houses, or added navigable water.
local owner="StockResidentialQA"
local function ask(req,cb)
  req.player=owner
  assert(authority.query(req,function(r)
    assert(r.ok,req.kind..": "..tostring(r.why));cb(r)
  end))
end
local function action(request,cb)
  ask({kind="transport_quote",request=request},function(q)
    assert(q.value.cost>0)
    ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},cb)
  end)
end
local function dock(id,opts,cb)
  local r={mode="ship",operation="build",kind="dock",tile=id}
  for k,v in pairs(opts or {}) do r[k]=v end
  action(r,cb)
end
local function shot(player,origin,ext)
  local ax,az=Sim.xy(origin)
  local bx,bz=Sim.xy(ext)
  local look={x=ax+bx+.5,y=1.1,z=az+bz+.5}
  local pos={x=look.x+8,y=6,z=look.z+6.5}
  local aim=vector.direction(vector.add(pos,{x=0,y=1.625,z=0}),look)
  player:set_pos(pos);player:set_look_horizontal(core.dir_to_yaw(aim));player:set_look_vertical(-math.asin(aim.y))
end
local function begin()
  local player=core.get_player_by_name(owner)
  if not (player and authority and authority.status()=="owned" and #world.hotbar_layout(player)>0) then core.after(.25,begin);return end
  local Track=dofile(mod.."/openttd/rail_track.lua")
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local Water=dofile(mod.."/openttd/ship_follow.lua")(Track)
  local F=dofile(mod.."/openttd/ship_facilities.lua")(Track,Water)
  local N=dofile(mod.."/ship_network.lua")(Sim,Terrain,Water,F)
  local reopened=core.settings:get_bool("luanttd_qa_joined_docks_reopen",false)
  local partial=core.settings:get_bool("luanttd_qa_joined_active_remove",false)
  local saved=reopened and assert(core.deserialize(storage:get_string("joined_docks_qa"),true))
  local function checkpoint() return assert(OwnerCheckpoint.read()) end
  if core.settings:get_bool("luanttd_qa_retired_dock",false) then
    local function proof()
      local s=checkpoint()
      local reopen=core.settings:get_bool("luanttd_qa_retired_dock_reopen",false)
      if reopen then
        local saved=assert(core.deserialize(storage:get_string("retired_dock_qa"),true))
        assert(s.speed==0 and not s.stock_ship_stations[saved.id] and
          s.retired_ship_stations[saved.id].row.tile==saved.a)
        ask({kind="dock_join_choices",request={tile=saved.b}},function(options)
          local offered
          for _,row in ipairs(options.value.choices) do
            if row.id==saved.id then offered=row.name end
          end
          assert(offered and offered:find("Reopen",1,true)==1)
          dock(saved.b,{join=saved.id,adjacent=true},function(r)
            local after=checkpoint()
            local station=assert(after.stock_ship_stations[saved.id])
            assert(r.value.id==saved.id and station.land==saved.b and #station.docks==1
              and not after.retired_ship_stations[saved.id])
            local view=N.board(after)
            assert(#view.station_dock_tiles(saved.id)>0 and not after.tiles[saved.a].ship)
            core.log("action",("PASS NATIVE RETIRED DOCK REOPEN: %d retained and moved from %d to %d")
              :format(saved.id,saved.a,saved.b))
          end)
        end)
        return
      end
      local legal,a,b={}
      for id,t in ipairs(s.tiles) do
        if t.coastal_water and N.quote(s,owner,"dock",id) then legal[#legal+1]=id end
      end
      for i,one in ipairs(legal) do
        for j=i+1,#legal do
          local other=legal[j]
          if Sim.distance(one,other)==2 then a,b=one,other;break end
        end
        if a then break end
      end
      assert(a and b,"No pair of legal natural shores")
      dock(a,nil,function(built)
        local id=assert(built.value.id)
        ask({kind="demolition",tile=a},function(d)
          local layer
          for _,o in ipairs(d.value.options) do if o.key=="harbor" and o.ok then layer=o.key end end
          assert(layer,"Bulldozer did not permit unoccupied dock")
          ask({kind="command",command={kind="demolition",token=d.value.token,layer=layer,revision=d.revision}},function()
            local after=checkpoint()
            assert(not after.stock_ship_stations[id] and not after.tiles[a].ship and
              after.retired_ship_stations[id].row.tile==a and #N.board(after).station_dock_tiles(id)==0)
            storage:set_string("retired_dock_qa",core.serialize({id=id,a=a,b=b}))
            core.log("action","PASS NATIVE RETIRED DOCK SAVE: removed from route destinations, identity saved")
          end)
        end)
      end)
    end
    if reopened or checkpoint().speed==0 then proof()
    else
      ask({kind="clock"},function(q)
        ask({kind="command",command={kind="speed",speed=0,revision=q.revision}},proof)
      end)
    end
    return
  end
  local function visit(n,station,base,ext,last)
    local s=checkpoint()
    local st=assert(s.stock_ship_stations[station])
    if partial and reopened then
      assert(#st.docks==1 and st.land==saved.retained and not s.tiles[saved.removed].ship)
    else assert(#st.docks==2 and st.docks[1].land==base and st.docks[2].land==ext) end
    local boat=s.ship_pilot
    local c=s.companies[owner]
    if boat then
      assert(not boat.failure,boat.failure)
      assert(boat.first==station and boat.second==last and boat.owned,"Ferry orders must use the original station identity")
    end
    local paid=c.paid_units or 0
    if boat and paid>(saved and saved.paid or 0) and boat.arrivals>=(saved and saved.arrivals+1 or 2) then
      assert(c.revenue>0)
      if partial and reopened then
        assert(not boat.dock_forced_leave and boat.vehicle.tile~=saved.berth,"Pending removed berth did not leave")
      end
      if not reopened then storage:set_string("joined_docks_qa",core.serialize({station=station,base=base,
        extension=ext,last=last,paid=paid,arrivals=boat.arrivals})) end
      core.log("action",("PASS NATIVE JOINED DOCK %s: station %d, continued with %d visits and %d paid passengers")
        :format(reopened and "REOPEN" or "SERVICE",station,boat.arrivals,paid))
      return
    end
    assert(n>0,("No continued paid ferry service: %s visits, %s paid"):format(boat and boat.arrivals or "-",paid))
    core.after(.35,function()visit(n-1,station,base,ext,last)end)
  end
  if reopened then
    if partial then
      local s=checkpoint()
      assert(s.speed==0 and s.ship_pilot.dock_forced_leave and s.ship_pilot.vehicle.loading)
      ask({kind="town_authority",town=assert(Sim.nearest_town(s,saved.retained)).id},function(q)
        ask({kind="command",command={kind="speed",speed=4,revision=q.revision}},function()
          visit(330,saved.station,saved.base,saved.extension,saved.last)
        end)
      end)
    else visit(330,saved.station,saved.base,saved.extension,saved.last) end
    return
  end
  local function remove_loading(n,station,base,ext,last)
    local s=checkpoint()
    local boat=s.ship_pilot
    assert(not boat or not boat.failure,boat and boat.failure)
    local function unique_berth()
      local b=boat and boat.vehicle
      if not (b and b.loading and b.last_station==station) then return end
      local cells={}
      local B=N.board(s)
      for dir=0,3 do
        local at=B.adjacent(b.tile,dir)
        local t=at and s.tiles[at].ship
        if t and t.kind=="dock" and t.station==station and t.water_part then cells[#cells+1]=at end
      end
      return #cells==1 and cells[1] or nil
    end
    local pier=unique_berth()
    if pier then
      local probe=Sim.nearest_town(s,base)
      ask({kind="town_authority",town=probe.id},function(q)
        ask({kind="command",command={kind="speed",speed=0,revision=q.revision}},function(pause)
          s=checkpoint();boat=s.ship_pilot
          local now=unique_berth()
          local service=s.stock_ship_commercial and s.stock_ship_commercial.service
          local passenger=service and service.vehicles[boat.paid_clock]
          if not (now and passenger and passenger.load_state and (passenger.units or 0)>0) then
            ask({kind="command",command={kind="speed",speed=1,revision=pause.revision}},function()
              core.after(.24,function()remove_loading(n-1,station,base,ext,last)end)
            end)
            return
          end
          local st=assert(s.stock_ship_stations[station])
          local retired,remaining
          for _,p in ipairs(st.docks) do
            if p.water==now then retired=p.land else remaining=p.land end
          end
          assert(retired and remaining)
          ask({kind="demolition",tile=retired},function(d)
            local found
            for _,o in ipairs(d.value.options) do if o.key=="harbor" and o.ok then found=o;break end end
            assert(found,"Partial active berth must be available in the ordinary Bulldozer")
            ask({kind="command",command={kind="demolition",token=d.value.token,layer=found.key,revision=d.revision}},function()
              local after=checkpoint()
              local run=after.ship_pilot
              assert(run.dock_forced_leave and run.vehicle.loading,"Lost loaded berth must defer safe departure")
              assert(#after.stock_ship_stations[station].docks==1 and after.stock_ship_stations[station].land==remaining)
              assert(not after.tiles[now].ship and not after.tiles[retired].ship)
              local waiting=after.stock_ship_commercial.service.vehicles[run.paid_clock]
              assert(waiting.load_state and waiting.units==passenger.units,"Do not lose or create passengers at demolition")
              storage:set_string("joined_docks_qa",core.serialize({station=station,base=base,extension=ext,
                last=last,paid=after.companies[owner].paid_units or 0,arrivals=boat.arrivals,retained=remaining,
                removed=retired,berth=boat.vehicle.tile}))
              shot(player,retired,remaining)
              if api.cinematic and not api.cinematic.active(player) then api.cinematic.toggle(player) end
              core.after(2,function()
                core.log("action",("PASS NATIVE JOINED DOCK ACTIVE REMOVAL: %d aboard, station %d persists, former shore %d")
                  :format(waiting.units,station,retired))
              end)
            end)
          end)
        end)
      end)
      return
    end
    assert(n>0,"No uniquely moored boarding visit")
    core.after(.12,function()remove_loading(n-1,station,base,ext,last)end)
  end

  local seed=checkpoint()
  local shore,by_id={},{}
  local Catchment=dofile(mod.."/openttd/station_catchment.lua")(nil,nil,
    dofile(mod.."/road_station_service.lua")().house_passenger_acceptance)
  local function demand(plan)
    local cells={}
    for _,id in ipairs(plan.tiles) do
      local x,z=Sim.xy(id)
      cells[#cells+1]={x=x-1,y=z-1,kind="dock"}
    end
    local c=Catchment.build({tiles=cells},Sim.W,Sim.H,seed.stock_modified_catchment)
    return Catchment.acceptance(c,"passenger",function(x,z)
      local t=seed.tiles[Sim.id(x+1,z+1)]
      return t and t.house and t.source_house or nil
    end).eighths
  end
  for id,t in pairs(seed.tiles) do
    if t.coastal_water then
      local q=N.quote(seed,owner,"dock",id)
      if q then
        q.score=demand(q)
        shore[#shore+1]=q;by_id[id]=q
      end
    end
  end
  table.sort(shore,function(a,b) return a.score==b.score and a.land<b.land or a.score>b.score end)
  core.log("action",("JOINED DOCK SCAN: %d legal coastal slips, best passenger acceptance %d"):format(#shore,shore[1] and shore[1].score or -1))
  -- Require two real house catchments and an existing navigable lane. A
  -- path against the natural map is screened before any tools are used.
  local B=N.board(seed)
  local Y=dofile(mod.."/openttd/ship_yapf.lua")(Track,Water,dofile(mod.."/openttd/yapf_road_search.lua"))
  local function connects(a,b)
    local v={ocean_speed_frac=0,canal_speed_frac=0}
    local goal=Y.destination(B,v,{kind="tile",tile=b.approach})
    return Y.find(B,v,a.approach,Water.at(B,a.approach),goal)
  end
  local a,b,e,dep,axis
  for i=1,math.min(#shore,30) do
    local base=shore[i]
    if base.score<12 then break end
    local x,z=Sim.xy(base.land)
    local best_ext
    for dv=-6,6 do for du=-6,6 do
      local candidate=by_id[Sim.id(x+du,z+dv)]
      local gap=math.abs(dv)+math.abs(du)
      if candidate and gap>1 and candidate.water~=base.approach and candidate.approach~=base.water
        and (not partial or Sim.distance(base.water,candidate.water)>=3)
        and (not best_ext or gap<Sim.distance(best_ext.land,base.land)) then best_ext=candidate end
    end end
    if best_ext then
      for j=1,math.min(#shore,45) do
        local dest=shore[j]
        if dest.score<12 then break end
        local gap=Sim.distance(base.land,dest.land)
        if gap>=10 and gap<=75 and Sim.distance(best_ext.land,dest.land)>3 and connects(base,dest) then
          for dz=-3,3 do for dx=-3,3 do
            local id=Sim.id(x+dx,z+dz)
            for d=0,1 do
              local q=N.quote(seed,owner,"depot",id,d)
              if q and not dep then
                local clear=true
                for _,tile in ipairs(q.tiles) do
                  if tile==base.water or tile==base.approach or tile==best_ext.water or tile==best_ext.approach
                      or Sim.distance(tile,base.land)<=2 or seed.tiles[tile].stock_water_rocks then clear=false end
                end
                if clear then a,b,e,dep,axis=base,dest,best_ext,id,d end
              end
            end
          end end
          if dep then break end
        end
      end
    end
    if dep then break end
  end
  assert(dep,"Could not find two actual coastal catchments, an extension and a depot")
  dock(a.land,nil,function(first)
    local station=assert(first.value.id)
    ask({kind="dock_join_choices",request={tile=e.land}},function(picker)
      assert(picker.value.choices[1].id==nil)
      local found=false
      for _,row in ipairs(picker.value.choices) do if row.id==station then found=true end end
      assert(found,"The existing dock was not offered")
      local function ready()
        local after=checkpoint()
        local st=after.stock_ship_stations[station]
        if st and #st.docks==2 then
          assert(st.docks[2].water==e.water)
          shot(player,a.land,e.land)
          core.after(3,function()
            core.log("action",("NATIVE JOINED DOCK FRAME %d and %d id=%d"):format(a.land,e.land,station))
            core.after(1.5,function()
              dock(b.land,{adjacent=true},function(other)
                assert(other.value.id~=station)
                action({mode="ship",operation="build",kind="depot",tile=dep,axis=axis},function(d)
                  action({mode="ship",operation="buy",depot=d.value.id,engine=206},function(owned)
                    assert(owned.value.id=="ferry")
                    ask({kind="command",command={kind="transport_start",mode="ship",vehicle="ferry",depot=d.value.id,
                      first=station,second=other.value.id,revision=owned.revision}},function(started)
                      ask({kind="command",command={kind="speed",speed=partial and 1 or 4,revision=started.revision}},function()
                        if partial then remove_loading(450,station,a.land,e.land,other.value.id)
                        else visit(330,station,a.land,e.land,other.value.id) end
                      end)
                    end)
                  end)
                end)
              end)
            end)
          end)
          return
        end
        core.after(.25,ready)
      end
      if not core.settings:get_bool("luanttd_qa_joined_docks_ui",false) then
        dock(e.land,{adjacent=true,join=station,picker_cost=picker.value.cost},function(extension)
          assert(extension.value.id==station); ready()
        end)
        return
      end
      local visible=core.show_formspec
      core.show_formspec=function(n,form,def)
        if n==owner and form=="luanttd_core:road_join_picker" and def~="" then
          assert(def:find("Join a dock station",1,true) and def:find("Build a separate station",1,true)
            and def:find("Dock "..station,1,true),"The real picker must expose both choices.")
          core.log("action","JOINED DOCK PICKER VISIBLE")
        end
        return visible(n,form,def)
      end
      local function slot(key)
        local inv=player:get_inventory()
        for i=1,10 do if inv:get_stack("main",i):get_name()=="luanttd_core:menu_"..key then return i end end
      end
      local x,z=Sim.xy(e.land)
      local _,level=Terrain.tile(seed.corner_grid,x,z)
      local tx,tz=x*2+.5,z*2+.5
      player:set_pos({x=tx-1.8,y=level+4.8,z=tz+2.15})
      player:set_look_horizontal(math.atan2(-1.8,-2.15));player:set_look_vertical(math.atan2(5.5,2.8))
      local seen={}
      local function observe(n)
        local menu=world.menu(player)
        local target=world.target(player)
        if menu=="home" and target==e.land and not seen.home then
          seen.home=true;core.log("action","JOINED DOCK HOME SLOT "..assert(slot("section_harbor")))
        elseif menu=="harbor" and target==e.land and not seen.harbor then
          seen.harbor=true;core.log("action","JOINED DOCK TOOL SLOT "..assert(slot("ship_join_dock")))
          ready()
          return
        end
        assert(n>0,("Harbor aim mismatch: %s/%s, expected %s"):format(menu,tostring(target),e.land))
        core.after(.25,function()observe(n-1)end)
      end
      core.after(.45,function()observe(110)end)

    end)
  end)
end
core.after(.25,begin)
