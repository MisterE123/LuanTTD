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
  local saved=reopened and assert(core.deserialize(storage:get_string("joined_docks_qa"),true))
  local function checkpoint() return assert(OwnerCheckpoint.read()) end
  local function visit(n,station,base,ext,last)
    local s=checkpoint()
    local st=assert(s.stock_ship_stations[station])
    assert(#st.docks==2 and st.docks[1].land==base and st.docks[2].land==ext)
    local boat=s.ship_pilot
    local c=s.companies[owner]
    if boat then
      assert(not boat.failure,boat.failure)
      assert(boat.first==station and boat.second==last and boat.owned,"Ferry orders must use the original station identity")
    end
    local paid=c.paid_units or 0
    if boat and paid>(saved and saved.paid or 0) and boat.arrivals>=(saved and saved.arrivals+1 or 2) then
      assert(c.revenue>0)
      if not reopened then storage:set_string("joined_docks_qa",core.serialize({station=station,base=base,
        extension=ext,last=last,paid=paid,arrivals=boat.arrivals})) end
      core.log("action",("PASS NATIVE JOINED DOCK %s: station %d, continued with %d visits and %d paid passengers")
        :format(reopened and "REOPEN" or "SERVICE",station,boat.arrivals,paid))
      return
    end
    assert(n>0,("No continued paid ferry service: %s visits, %s paid"):format(boat and boat.arrivals or "-",paid))
    core.after(.35,function()visit(n-1,station,base,ext,last)end)
  end
  if reopened then visit(330,saved.station,saved.base,saved.extension,saved.last);return end

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
                      ask({kind="command",command={kind="speed",speed=4,revision=started.revision}},function()
                        visit(330,station,a.land,e.land,other.value.id)
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
