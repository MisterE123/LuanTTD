-- Appended only to a disposable installation's real init.lua. Start the
-- ordinary generated campaign; build a road service without scenario flags,
-- fabricated freight, altered terrain or injected industries.
core.after(0,function()
  local owner="Generated Oil QA"
  local profile=assert(S.stock_generated_profile)
  assert(api.generated_world and Sim.W==64 and Sim.H==64 and S.seed==1751)
  assert(api.oil_tools and api.rail_oil_tools and api.farm_tools and api.timber_tools and api.ship_coal_tools,
    "Not all ordinary freight systems mounted together")
  local refinery,wells
  for _,r in ipairs(profile.industries) do
    if r.kind=="oil_refinery" then refinery=r elseif r.kind=="oil_well" then wells=r end
  end
  assert(refinery and wells,"Seeded map must generate an oil refinery and wells")
  assert(core.settings:get("bayline_scenario")==nil)
  local saved=S.generated_oil_freight_test
  if not saved then
    Sim.company(S,owner)
    -- Survey real roadside candidates using the worker's build quotes. Keep
    -- temporary station probes in a private copy: nothing is placed until
    -- one continuous legal route with all three catchments has been found.
    local radius=S.stock_modified_catchment==false and 4 or 3
    local function near(a,b,r)
      local x,z=Sim.xy(a)
      local u,v=Sim.xy(b)
      return math.abs(x-u)<=r and math.abs(z-v)<=r
    end
    local well_gates,refinery_gates,town_gates={},{},{}
    local probe=assert(core.deserialize(core.serialize(S)))
    local function usable(id)
      local t=id and S.tiles[id]
      return t and not (t.stock_void or t.terrain=="water" or t.stock_industry or t.stock_landmark
        or t.house or t.site or t.build and t.build~="road")
    end
    local candidates={}
    for id in ipairs(S.tiles) do
      local town=Sim.nearest_town(S,id)
      if usable(id) and (near(id,wells.tile,radius+3) or near(id,refinery.tile,radius+3)
          or town and near(id,town.tile,8)) and api.terrain.tile(id)==0 then
        local opt={}
        for d=1,4 do
          local out=Sim.adjacent(id,d)
          local back=Sim.adjacent(id,(d+1)%4+1)
          if usable(out) and usable(back) and Sim.stock_road_terminal_plan(S,owner,id,
              {kind="truck",dir=d%2,through=true,area=true}) then
            opt[#opt+1]={id=id,out=out,back=back}
          end
        end
        if #opt>0 then
          local p={id=1000+#candidates,tile=id,mode="road",stop_type="truck",stock={},owner=owner,
            site=town and town.id,served={}}
          probe.stations[p.id]=p
          candidates[#candidates+1]={probe=p,gates=opt}
        end
      end
    end
    for _,candidate in ipairs(candidates) do
      local p,gates=candidate.probe,candidate.gates
      local _,oil=Sim.oil_stop_status(probe,p,"oil")
      local _,goods=Sim.oil_stop_status(probe,p,"goods")
      if #oil.sources==1 and oil.sources[1]==wells.industry then
        well_gates[p.tile]=gates
      elseif oil.accepts and #goods.sources==1 and goods.sources[1]==refinery.industry then
        for _,gate in ipairs(gates) do refinery_gates[#refinery_gates+1]=gate end
      elseif goods.accepts and next(goods.house_eighths_by_town or {}) and #goods.sources==0 then
        town_gates[p.tile]=gates
      end
    end
    table.sort(refinery_gates,function(p,q)
      local u,v=Sim.distance(p.id,refinery.tile),Sim.distance(q.id,refinery.tile)
      if u~=v then return u<v end
      return p.id<q.id or p.id==q.id and p.out<q.out
    end)
    local legal,tile_count={},Sim.W*Sim.H
    -- Keep the arrival heading in the search state. A legal straight slope
    -- is not necessarily a legal bend, so quote each incoming/outgoing pair.
    local function allows(prev,id,next)
      local low,high=math.min(prev,next),math.max(prev,next)
      local k=(id*tile_count+low)*tile_count+high
      if legal[k]==nil then legal[k]=not not Sim.plan(S,owner,"road",{prev,id,next}) end
      return legal[k]
    end
    local function scout(start,targets,avoid)
      local root={id=start.out,parent={id=start.id,parent={id=start.back}}}
      local queue,head,seen={root},1,{[start.id*tile_count+start.out]=true}
      while head<=#queue do
        local p=queue[head]
        head=head+1
        local id,prev=p.id,p.parent.id
        for _,g in ipairs(targets[id] or {}) do
          if g.back==prev and usable(g.out) and allows(prev,id,g.out) then
            local reversed={g.out}
            repeat reversed[#reversed+1]=p.id;p=p.parent until not p
            local path={}
            for i=#reversed,1,-1 do path[#path+1]=reversed[i] end
            return path,id
          end
        end
        for d=1,4 do
          local dest=Sim.adjacent(id,d)
          local key=dest and id*tile_count+dest
          if dest~=prev and dest~=start.id and dest~=start.back and dest~=avoid and usable(dest)
              and not seen[key] and allows(prev,id,dest) then
            queue[#queue+1]={id=dest,parent=p}
            seen[key]=true
          end
        end
      end
    end
    local function turnarounds(tail,...)
      local avoid,out={},{}
      for _,id in ipairs({...}) do avoid[id]=true end
      for d=1,4 do
        local e=Sim.adjacent(tail,d)
        for _,p in ipairs({d%4+1,(d+2)%4+1}) do
          local f=Sim.adjacent(tail,p)
          local middle=e and Sim.adjacent(e,p)
          if usable(e) and usable(f) and usable(middle) and not (avoid[e] or avoid[f] or avoid[middle]) then
            out[#out+1]={e,middle,f}
          end
        end
      end
      return out
    end
    local road,well_tile,refinery_tile,town_tile
    for _,g in ipairs(refinery_gates) do
      local left,well_stop=scout({id=g.id,out=g.back,back=g.out},well_gates)
      if left then
        local right,town_stop=scout(g,town_gates,well_stop)
        if right then
          local well_end,town_end=left[#left],right[#right]
          -- Both through stops preserve the heading of a loaded truck.
          -- Two topology-only paths are not proof of a repeatable
          -- service. Lay a real turnaround beyond each end platform
          -- so a released truck can keep moving, then reverse via road.
          for _,w in ipairs(turnarounds(well_end,well_stop,g.id,town_stop)) do
            for _,t in ipairs(turnarounds(town_end,town_stop,g.id,well_stop)) do
              local path={well_end,w[1],w[2],w[3]}
              for i=#left,1,-1 do path[#path+1]=left[i] end
              for i=4,#right do path[#path+1]=right[i] end
              for _,id in ipairs(t) do path[#path+1]=id end
              path[#path+1]=town_end
              if Sim.plan(S,owner,"road",path) then
                road,well_tile,refinery_tile,town_tile=path,well_stop,g.id,town_stop
                break
              end
            end
            if road then break end
          end
          if road then break end
        end
      end
    end
    local function count(rows)
      local n=0
      for _ in pairs(rows) do n=n+1 end
      return n
    end
    assert(road,("No legal corridor between %d well tiles, %d refinery gates and %d accepting town tiles")
      :format(count(well_gates),#refinery_gates,count(town_gates)))
    assert(Sim.build(S,owner,"road",road))
    local function stop(id)
      local ok,why=Sim.build_truck_stop(S,owner,id)
      local x,z=Sim.xy(id)
      assert(ok,("Loading stop (%d,%d): %s"):format(x,z,tostring(why)))
      return assert(S.stations[S.tiles[id].station])
    end
    local function location(id)
      local x,z=Sim.xy(id)
      return ("(%d,%d)"):format(x,z)
    end
    core.log("action",("GENERATED_OIL_ROUTE %s → %s → %s, %d road pieces in route")
      :format(location(well_tile),location(refinery_tile),location(town_tile),#road-1))
    local a,b,c=stop(well_tile),stop(refinery_tile),stop(town_tile)
    local depot
    for i=2,#road-1 do
      local t=road[i]
      if t~=well_tile and t~=refinery_tile and t~=town_tile then
        for d=1,4 do
          local id=Sim.adjacent(t,d)
          if usable(id) and Sim.plan(S,owner,"road_depot",{id}) then depot=id;break end
        end
      end
      if depot then break end
    end
    assert(depot and Sim.build(S,owner,"road_depot",{depot}),"No legal depot by the freight corridor")
    local _,well_catch=Sim.oil_stop_status(S,a,"oil")
    local _,crude_catch=Sim.oil_stop_status(S,b,"oil")
    local _,refinery_catch=Sim.oil_stop_status(S,b,"goods")
    local _,town=Sim.oil_stop_status(S,c,"goods")
    assert(well_catch.sources[1]==wells.industry and crude_catch.accepts and crude_catch.eighths>=8 and
      #refinery_catch.sources==1 and refinery_catch.sources[1]==refinery.industry and town.accepts,
      core.serialize({well_catch,crude_catch,refinery_catch,town}))
    local function buy(engine,cargo,a,b)
      local id=assert(Sim.purchase(S,owner,engine,cargo,nil,depot))
      local v=S.fleet[id]
      assert(Sim.path(S,a,b,"road",owner,nil,v) and Sim.path(S,b,a,"road",owner,nil,v))
      assert(Sim.add_order(S,owner,id,a.id) and Sim.add_order(S,owner,id,b.id))
      assert(Sim.toggle(S,owner,id))
      return v
    end
    local tanker=buy("oil_tanker","oil",a,b)
    local goods=buy("goods_truck","goods",b,c)
    for _=1,350 do
      Sim.daily(S)
      if tanker.delivered>0 and goods.delivered==0 then
        local ledger=assert(S.stock_oil_industries[refinery.industry])
        assert(ledger.received.oil==tanker.delivered)
        S.generated_oil_freight_test={oil=tanker.id,goods=goods.id,liters=tanker.delivered,refinery=b.id,town=c.id}
        api.save()
        core.log("action","GENERATED_OIL_FREIGHT_SAVED")
        core.request_shutdown("Generated oil tanker delivered to its stock refinery",false,0)
        return
      end
    end
    error(("No pre-restart crude delivery: tanker=%s (%d paid), Goods truck=%s (%d paid)")
      :format(tanker.status,tanker.delivered,goods.status,goods.delivered))
  end
  local tanker,goods=S.fleet[saved.oil],S.fleet[saved.goods]
  assert(tanker.delivered==saved.liters and goods.delivered==0)
  for _=1,500 do
    Sim.daily(S)
    assert(tanker.status~="No path" and goods.status~="No path","The real arrival heading lost its legal return route")
    if tanker.delivered>saved.liters and goods.delivered>0 then
      local company=S.companies[owner]
      assert(company.revenue==tanker.revenue+goods.revenue)
      assert(company.paid_units==tanker.delivered+goods.delivered and S.passenger_house_clock.counter==S.stock_load_tick)
      local firm=assert(S.stock_oil_industries[refinery.industry])
      assert(firm.received.oil==tanker.delivered and tanker.expense>0 and goods.expense>0)
      core.log("action",("GENERATED_OIL_FREIGHT_PASS stock default seed: %d thousand L/$%d plus %d Goods/$%d after SQLite restart")
        :format(tanker.delivered,tanker.revenue,goods.delivered,goods.revenue))
      core.request_shutdown("Generated oil refinery paid delivered Goods",false,0)
      return
    end
  end
  error(("Generated oil route did not repeat: crude=%d %s, Goods=%d %s")
    :format(tanker.delivered,tanker.status,goods.delivered,goods.status))
end)
