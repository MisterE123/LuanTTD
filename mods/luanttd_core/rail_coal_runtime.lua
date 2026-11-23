-- SPDX-License-Identifier: GPL-2.0-only
-- Mount one explicitly bought Kirby + coal wagon onto the stock shared
-- producer and one continuous 74-tick world clock. No second producer,
-- free train, fake fare or view-driven movement.
return function(Sim,Service,Roster,debit,credit,receive)
  local R={distribute=Service.distribute}
  local frames=setmetatable({},{__mode="k"})
  local function cache(s)
    local a=frames[s]
    if not a then a={events={},motion={}};frames[s]=a end
    return a
  end
  local function push(list,item)
    list[#list+1]=item
    if #list>4096 then table.remove(list,1) end
  end
  local function model(s,add)
    if not s.stock_rail_coal and add then s.stock_rail_coal=Service.new() end
    return s.stock_rail_coal
  end
  local function run_of(s,Run)
    local r=Run and (Run.freight_paid and Run.freight_paid(s,"coal") or Run.current_paid(s))
    return r and r.freight and (r.freight.cargo==nil or r.freight.cargo=="coal") and r or nil
  end
  function R.active(s,Run)
    return not not (Run and s.rail_coal_service and s.rail_owned_service and s.stock_rail_fleet and
      s.road_stock_house_supply and Sim.road_stock_service_active(s) and s.stock_coal_industries)
  end
  local function bind(s)
    local state=model(s,true)
    local frame=cache(s)
    local function receive_(world,plant,n) if receive then receive(world,plant,n) end end
    return Service.bind(s,state,{only_marked=true,select_goods=s.stock_select_goods,current_payment=s.stock_coal_payment,
      loading_penalty=s.stock_station_length_penalty,credit=credit,received=receive_,
      emit=function(e)
        e.day=s.day
        if e.kind=="fare" then
          local v=state.vehicles[e.vehicle]
          v.last_fare=e.amount
        elseif e.kind=="board" then
          local v=state.vehicles[e.vehicle]
          v.boarded=(v.boarded or 0)+e.units
        end
        push(frame.events,e)
      end}),state
  end
  local function raw_station(s,id)
    if type(id)~="number" or id<0 or id>=Service.rail_index or id%1~=0 then return end
    return s.stock_rail_stations and s.stock_rail_stations[id]
  end
  function R.report(s,Run,id)
    if not R.active(s,Run) then return end
    local raw=raw_station(s,id)
    if not raw then return end
    local b=raw.coal_role and bind(s) or Service.bind(s,Service.new(),{only_id=id})
    local report=b.report(id)
    if report then report.waiting,report.available=b.waiting(id) end
    return report
  end
  function R.designate(s,Run,owner,id,role)
    if not R.active(s,Run) then return false,"Rail Coal service is disabled." end
    local raw=raw_station(s,id)
    if not raw or raw.owner~=owner or (role~="load" and role~="unload") then
      return false,"Choose an owned rail platform and a coal loading or unloading stage."
    end
    if raw.oil_role then return false,"This platform already has an oil stage." end
    if raw.goods_role or raw.iron_ore_role or raw.steel_role then return false,"This platform already has another freight stage." end
    if raw.coal_role==role then return true,"That platform already has this coal stage.",raw.tiles end
    if raw.coal_role then return false,"This platform already has a different coal stage." end
    local d=Run.current(s)
    for _,r in ipairs(d and d.runs or {}) do
      local hit=r.station==id or r.shuttle and (r.shuttle.first==id or r.shuttle.second==id) or
        r.freight and (r.freight.mine==id or r.freight.power==id)
      if not hit then
        for _,o in ipairs(r.orders or {}) do if o.station==id then hit=true;break end end
      end
      if not hit then
        for _,v in ipairs(r.route or {}) do
          local t=s.tiles[v.tile]
          if t and t.rail_station_id==id then hit=true;break end
        end
      end
      if hit then return false,"That platform is part of an active rail route." end
    end
    local demo=s.stock_rail_run
    if demo and demo.station==id then return false,"That platform serves an active rail pilot." end
    local report=R.report(s,Run,id)
    if not report or (role=="load" and #report.sources==0) or (role=="unload" and not report.accepts) then
      return false,role=="load" and "Choose a platform in a real coal mine's catchment."
        or "Choose a platform accepting at a real power station."
    end
    raw.coal_role=role
    -- The physical platform and its independent passenger queue are not
    -- rebuilt or moved. Marking a new idle stage may now admit stock coal.
    return true,role=="load" and "Coal loading stage designated." or "Coal unloading stage designated.",raw.tiles
  end
  function R.validate(s,Run,owner,mine,plant)
    if not R.active(s,Run) then return false,"Enable purchased rail, stock road/house clocks and Rail Coal first." end
    if type(mine)~="number" or type(plant)~="number" or mine==plant or mine<0 or plant<0 or
        mine>=Service.rail_index or plant>=Service.rail_index or mine%1~=0 or plant%1~=0 then
      return false,"Choose two different owned rail platforms."
    end
    local b=bind(s)
    local a,z=b.report(mine),b.report(plant)
    if not (a and z and a.station.owner==owner and z.station.owner==owner) then
      return false,"Choose two different owned rail platforms."
    end
    if a.role~="load" or #a.sources==0 then return false,"Designate the first platform as a coal loading stage near a mine." end
    if z.role~="unload" or not z.accepts then return false,"Designate the last platform as an accepting coal unloading stage." end
    return true
  end
  local function debit_previous_day(s,run)
    if not run then return end
    local total=run.running_ticks_total or 0
    local paid=run.freight.charged_running_ticks or 0
    assert(total>=paid)
    if total==paid then return end
    local fixed=Roster.day_running_charge(run.running_year_fp,total-paid)
    local company=Sim.company(s,run.owner)
    local whole,rest=Roster.debit_fraction(company.stock_money_fraction or 0,fixed)
    company.stock_money_fraction=rest
    if whole~=0 then debit(company,whole) end
    run.freight.charged_running_ticks=total
    run.freight.running_expense=(run.freight.running_expense or 0)+whole
  end
  local function sample(s,Run,run)
    local out={}
    if run then
      for i=1,2 do
        local a,b,c,w,subsurface
        if Run.presentation_sample then a,b,c,w,subsurface=Run.presentation_sample(s,run,i)
        else a,b,c,w=Run.sample(run,i) end
        if a then out[i]={a,b,c,not not run.consist.reversed,w,subsurface} end
      end
    end
    return out
  end

  function R.day(s,Run,first_tick)
    if not R.active(s,Run) then return end
    local b,state=bind(s)
    local run=run_of(s,Run)
    local frame=cache(s)
    frame.serial=run and run.fleet_id
    frame.samples={sample(s,Run,run)}
    local id=frame.serial
    if id and not state.vehicles[id] then
      assert(b.vehicle({id=id,owner=run.owner,stock_id=run.stock_wagon,length=run.total_length,
        speed=run.max_track_speed,built=run.paid_build_year}))
    end
    if state.loading_tick and state.loading_tick<first_tick-1 then
      -- Disabled optional service keeps its saved timer residues and
      -- cargo ages, without simulating fictional paused movement.
      state.loading_tick,state.post_tick=first_tick-1,first_tick-1
    end
    debit_previous_day(s,run)
    if run and run.freight.repeat_route and not (run.freight.complete or run.failure) then
      local a,z=b.report(run.freight.mine),b.report(run.freight.power)
      local why
      if not a or a.role~="load" or a.station.owner~=run.owner then
        why="The ordered coal loading platform is unavailable."
      elseif #a.sources==0 then why="The ordered coal mine has closed or moved out of catchment."
      elseif not z or z.role~="unload" or z.station.owner~=run.owner then
        why="The ordered power platform is unavailable."
      elseif z.eighths<8 then why="The ordered power station no longer accepts coal in catchment." end
      if why then
        for _,e in ipairs(Run.block_coal(s,why)) do e.cargo="coal";push(frame.motion,e) end
      end
    end
    local function before(tick)
      local v=id and state.vehicles[id]
      if v then
        v.stopped=run.stopped or run.phase=="blocked" or nil
        v.broken=run.breakdown or nil
        v.crashed=run.crashed or nil
      end
      local ids,problem=b.loading_tick(tick)
      assert(ids,problem)
      for _,who in ipairs(ids) do if who==id then return true end end
      return false
    end
    local function after(tick,ready,register)
      local function finish(moved)
        for _,e in ipairs(moved or {}) do
          e.world_tick,e.cargo=tick,"coal";push(frame.motion,e)
        end
        frame.samples[#frame.samples+1]=sample(s,Run,run)
      end
      if not id then return finish() end
      local v=state.vehicles[id]
      local callbacks={
        leave=function() return ready and b.leave(id,v.visit,tick) or false end,
        cargo_count=function() return v.units end,
        arrive=function(q,wagon)
          local head=q.consist.parts[1]
          local used=b.arrive(id,q.station,q.freight.visits,tick,head.tile,wagon,
            q.station==q.freight.mine and {full=true} or {no_load=true})
          return not not used
        end,
      }
      if register then register("coal",callbacks,finish)
      else finish(Run.advance_paid(s,callbacks)) end
    end
    local function post(tick) assert(b.after_motion(tick)) end
    return {extend=b.extend,before=before,after=after,post=post}
  end

  function R.present(s,Run) return run_of(s,Run)~=nil end
  function R.status(s,Run)
    local r=run_of(s,Run)
    if not r then return end
    local state=model(s,false)
    local v=state and state.vehicles[r.fleet_id]
    local l=v and v.load_state
    return {cargo="coal",capacity=Service.wagon.capacity,onboard=v and v.units or 0,
      boarded=v and v.boarded or 0,delivered=v and v.delivered or 0,fare=v and v.revenue or 0,
      last_fare=v and v.last_fare,phase=r.phase,loading=l~=nil,finished=not not r.freight.complete,
      cargo_tile=v and v.cargo_tile,head_tile=v and v.head_tile,platform_tiles=l and l.platform_tiles,
      last_platform=r.last_paid_platform,mine=r.freight.mine,power=r.freight.power,
      fleet_id=r.fleet_id,tick=state and state.post_tick,paused=not R.active(s,Run),
      repeating=not not r.freight.repeat_route,cycles=r.freight.cycles or 0,
      parking=not not r.freight.park_after_delivery,failure=r.failure,
      running_ticks=r.running_ticks_total,running_expense=r.freight.running_expense or 0}
  end
  function R.pose(s,Run,part,fraction,native)
    local r=run_of(s,Run)
    if not r then return end
    local frame=frames[s]
    if not R.active(s,Run) or not frame or frame.serial~=r.fleet_id or #frame.samples<2 then
      local a,b,c,w
      if native and Run.presentation_sample then a,b,c,w=Run.presentation_sample(s,r,part)
      else a,b,c,w=Run.sample(r,part) end
      return a,b,c,not not r.consist.reversed,w
    end
    local x=1+math.min(1,math.max(0,fraction or 1))*(#frame.samples-1)
    local i=math.floor(x)
    local a,b=frame.samples[i][part],frame.samples[i+1] and frame.samples[i+1][part]
    if not a or a[6] and not native then return end
    local f=a[3]
    if b and a[1]==b[1] and a[2]==b[2] and a[4]==b[4] and a[5]==b[5] and (native or not b[6]) then f=f+(b[3]-f)*(x-i) end
    return a[1],a[2],f,a[4],a[5]
  end
  function R.take(s,kind)
    local f=cache(s)
    local list=f[kind]
    f[kind]={}
    return list
  end
  return R
end
