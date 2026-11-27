-- SPDX-License-Identifier: GPL-2.0-only
-- One physical train on the common host clock with shared industry supply.
return function(profile,Sim,Service,RailStation,Roster,debit,credit)
  local R={}
  local cargo, role, storage = profile.cargo,profile.cargo.."_role","stock_rail_"..profile.cargo
  local mod=(core and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local Freight=dofile(mod.."/rail_freight_kinds.lua")
  local function other_role(st) return Freight.role(st,cargo) end
  local frames=setmetatable({},{__mode="k"})
  local function frame(s)
    local f=frames[s]
    if not f then f={events={},motion={}};frames[s]=f end
    return f
  end
  local function push(list,value)
    list[#list+1]=value
    if #list>4096 then table.remove(list,1) end
  end
  local function run_of(s,Run)
    local r=Run and (Run.freight_paid and Run.freight_paid(s,cargo) or Run.current_paid(s))
    return r and r.freight and r.freight.cargo==cargo and r or nil
  end
  function R.present(s,Run) return run_of(s,Run)~=nil end
  function R.active(s,Run)
    return not not (Run and s["rail_"..cargo.."_service"] and s.rail_owned_service and s.stock_rail_fleet and profile.enabled(s))
  end
  local function raw(s,id)
    if type(id)=="number" and id>=0 and id<RailStation.rail_index and id%1==0 then
      return s.stock_rail_stations and s.stock_rail_stations[id]
    end
  end
  function R.union(s,Run,probe)
    if not R.active(s,Run) then return end
    local roles={}
    for id,st in pairs(s.stock_rail_stations or {}) do
      if not other_role(st) and (st[role]=="load" or st[role]=="unload") then roles[id]=st[role] end
    end
    local state
    if probe then
      roles[probe]="load"
      state=Service.new()
    else
      state=s[storage] or Service.new();s[storage]=state
    end
    return function(roads,open,scan,rating)
      return Service.bind(s,state,{roles=roles,road_stations=roads,pipeline=open,credit=credit,
        platform_penalty=s.stock_station_length_penalty,post_scan=scan,rating=rating,
        emit=function(e)
          e.day=s.day
          local v=state.vehicle
          if e.kind=="fare" then v.last_fare=e.amount
          elseif e.kind=="board" then v.boarded=(v.boarded or 0)+e.units end
          push(frame(s).events,e)
        end})
    end
  end
  function R.report(s,Run,id,binding)
    if not R.active(s,Run) then return end
    local st=raw(s,id)
    if not st or other_role(st) then return end
    local b
    if st[role] then b=binding() else b=binding(id) end
    local report=b and b.rail and b.rail.report(id)
    if report and not st[role] then report.role=nil end
    return report
  end
  function R.designate(s,Run,owner,id,request,binding)
    if not R.active(s,Run) then return false,profile.name.." service is disabled." end
    local st=raw(s,id)
    if not st or st.owner~=owner or request~="load" and request~="unload" then
      return false,"Choose an owned platform and a loading or unloading stage for "..cargo.."."
    end
    local other=other_role(st)
    if other then return false,"This platform already has a "..other.." stage." end
    if st[role]==request then return true,"That platform already has this "..cargo.." stage.",st.tiles end
    if st[role] then return false,"This platform already has a different "..cargo.." stage." end
    local d=Run.current(s)
    for _,run in ipairs(d and d.runs or {}) do
      local hit=run.station==id or run.shuttle and (run.shuttle.first==id or run.shuttle.second==id) or
        run.paired and (run.paired.first==id or run.paired.second==id) or
        run.freight and (run.freight.mine==id or run.freight.power==id)
      if not hit then
        for _,o in ipairs(run.orders or {}) do if o.station==id then hit=true;break end end
      end
      if not hit then
        for _,v in ipairs(run.route or {}) do
          local t=s.tiles[v.tile]
          if t and t.rail_station_id==id then hit=true;break end
        end
      end
      if hit then return false,"That platform is part of an active rail route." end
    end
    if s.stock_rail_run and s.stock_rail_run.station==id then return false,"That platform serves an active rail pilot." end
    local q=R.report(s,Run,id,binding)
    if not q or request=="load" and #q.sources==0 or request=="unload" and not q.accepts then
      return false,request=="load" and profile.choose_source or profile.choose_sink
    end
    st[role]=request
    return true,profile.name..(request=="load" and " loading stage designated." or " unloading stage designated."),st.tiles
  end
  local function distinct(from,to)
    if not profile.distinct_industries then return true end
    local source={}
    for _,id in ipairs(from.sources) do source[id]=true end
    -- Refuse overlapping bank catchments; otherwise a still-loaded
    -- producing bank can see its own packets again at the unloader.
    if not to.near or #to.near==0 then return false end
    for _,dest in ipairs(to.near) do if source[dest.id] then return false end end
    return true
  end
  local distinct_error="Choose platforms covering different banks without a shared bank in their catchments."
  function R.validate(s,Run,owner,well,refinery,binding)
    if not R.active(s,Run) then return false,"Enable purchased rail, the stock roads and "..profile.name.." service first." end
    local a,b=raw(s,well),raw(s,refinery)
    if not a or not b or well==refinery or a.owner~=owner or b.owner~=owner then
      return false,"Choose two different owned rail platforms."
    end
    if other_role(a) or a[role]~="load" then return false,"Designate the first platform as a "..cargo.." loading stage." end
    if other_role(b) or b[role]~="unload" then return false,"Designate the destination platform as a "..cargo.." unloading stage." end
    local bound=binding()
    local q,p=bound.rail.report(well),bound.rail.report(refinery)
    if not q or #q.sources==0 then return false,profile.choose_source end
    if not p or not p.accepts then return false,profile.choose_sink end
    if not distinct(q,p) then return false,distinct_error end
    return true
  end
  local function samples(s,Run,r)
    local out={}
    if r then
      for i=1,#r.consist.parts do
        local a,b,c,w,subsurface
        if Run.presentation_sample then a,b,c,w,subsurface=Run.presentation_sample(s,r,i)
        else a,b,c,w=Run.sample(r,i) end
        if a then out[i]={a,b,c,not not r.consist.reversed,w,subsurface} end
      end
    end
    return out
  end
  local function charge(s,r)
    local ticks=r.running_ticks_total or 0
    local previous=r.freight.charged_running_ticks or 0
    assert(ticks>=previous)
    if ticks==previous then return end
    local amount=Roster.day_running_charge(r.running_year_fp,ticks-previous)
    local c=Sim.company(s,r.owner)
    local whole,fraction=Roster.debit_fraction(c.stock_money_fraction or 0,amount)
    c.stock_money_fraction=fraction
    if whole~=0 then
      debit(c,whole,"rail_run")
      if Sim.stock_vehicle_operating then
        Sim.stock_vehicle_operating(s,s.stock_rail_fleet and s.stock_rail_fleet.units[r.fleet_id],-whole)
      end
    end
    r.freight.charged_running_ticks=ticks
    r.freight.running_expense=(r.freight.running_expense or 0)+whole
  end
  function R.day(s,Run,first_tick,b,live,refresh)
    if not (R.active(s,Run) and b) then return end
    local state=assert(s[storage])
    local r=run_of(s,Run)
    local f=frame(s)
    local id=r and r.fleet_id
    f.serial=id
    if not refresh then f.samples=not live and {samples(s,Run,r)} or nil end
    local function motion(list,tick)
      for _,e in ipairs(list or {}) do
        e.world_tick,e.cargo=tick,cargo;push(f.motion,e)
      end
    end
    local blocked=false
    local function block(why,tick)
      blocked=true
      if r and not r.failure then motion(Run[profile.block](s,why),tick) end
    end
    if r then
      if not state.vehicle then
        local v,why=b.vehicle({id=id,wagon=r.stock_wagon,owner=r.owner,length=r.total_length,
          speed=r.max_track_speed,built=r.paid_build_year,parts=r.freight_parts})
        assert(v,why)
      end
      assert(state.vehicle.id==id and state.vehicle.owner==r.owner,"Only one bought "..cargo.." carrier can own this save")
      if not refresh then charge(s,r) end
      if not (r.freight.complete or r.failure) then
        local a,z=b.report(r.freight.mine),b.report(r.freight.power)
        if not a or a.role~="load" or a.station.owner~=r.owner then
          block("The ordered "..cargo.." loading platform is unavailable.",first_tick)
        elseif #a.sources==0 then
          block(profile.source_lost,first_tick)
        elseif not z or z.role~="unload" or z.station.owner~=r.owner then
          block("The ordered "..cargo.." unloading platform is unavailable.",first_tick)
        elseif not z.accepts then
          block(profile.sink_lost,first_tick)
        elseif not distinct(a,z) then
          block(distinct_error,first_tick)
        end
      end
    end
    if state.tick and state.tick<first_tick-1 then
      -- Retain reservations/timer residues while the optional mode is off.
      state.tick,state.aged_tick=first_tick-1,first_tick-1
    end
    return {
      before=function(tick)
        local v=state.vehicle
        if v then
          v.broken=r and r.breakdown or nil
          v.crashed=r and r.crashed or nil
        end
        local fault=blocked or r and r.failure
        local ok,ready=b.loading_tick(tick,not r or r.stopped or fault or r.phase=="blocked",fault)
        if ok==nil then
          block("The "..cargo.." train lost its occupied platform: "..tostring(ready),tick)
          assert(b.loading_tick(tick,true,true))
          return false
        end
        return ready or false
      end,
      after=function(tick,ready,register)
        local function finish(moved)
          motion(moved,tick)
          if f.samples then f.samples[#f.samples+1]=samples(s,Run,r) end
        end
        if not r or blocked or r.failure then return finish() end
        local v=state.vehicle
        local callbacks={
          leave=function() return ready and b.leave(v.visit,tick) or false end,
          cargo_count=function()
            if not v.carrying_parts then return v.units end
            local units={}
            for i,p in ipairs(v.carrying_parts) do units[i]=p.units end
            return v.units,nil,nil,nil,units
          end,
          arrive=function(q,wagon,_,cargo_tiles)
            local head=q.consist.parts[1].tile
            return not not b.arrive(q.station,q.freight.visits,tick,head,wagon,cargo_tiles)
          end,
        }
        if register then register(cargo,callbacks,finish)
        else finish(Run.advance_paid(s,callbacks)) end
      end,
      post=function(tick) if state.tick==tick then assert(b.after_motion(tick)) end end,
    }
  end
  function R.status(s,Run)
    local r=run_of(s,Run)
    if not r then return end
    local state=s[storage]
    local v=state and state.vehicle
    local l=v and v.load_state
    local stock=assert(Service.wagon_spec(r.stock_wagon))
    local wagons
    if r.freight_parts then
      wagons={}
      for i,p in ipairs(r.freight_parts) do
        local vpart=v and v.carrying_parts[i]
        wagons[i]={index=p.index,body_id=p.body_id,stock_id=p.stock,tile=vpart and vpart.cargo_tile,
          capacity=stock.capacity,onboard=vpart and vpart.units or 0}
      end
    end
    return {cargo=cargo,owner=r.owner,capacity=stock.capacity*(wagons and #wagons or 1),
      wagons=wagons,onboard=v and v.units or 0,
      boarded=v and v.boarded or 0,delivered=v and v.delivered or 0,fare=v and v.revenue or 0,
      last_fare=v and v.last_fare,phase=r.phase,loading=l~=nil,finished=not not r.freight.complete,
      cargo_tile=v and v.cargo_tile,head_tile=v and v.head_tile,platform_tiles=l and l.platform_tiles,
      last_platform=r.last_paid_platform,mine=r.freight.mine,power=r.freight.power,
      source=r.freight.mine,destination=r.freight.power,
      fleet_id=r.fleet_id,tick=state and state.aged_tick,paused=not R.active(s,Run),
      repeating=not not r.freight.repeat_route,cycles=r.freight.cycles or 0,
      parking=not not r.freight.park_after_delivery,failure=r.failure,
      running_ticks=r.running_ticks_total,running_expense=r.freight.running_expense or 0}
  end
  function R.pose(s,Run,part,fraction,native)
    local r=run_of(s,Run)
    if not r then return end
    local f=frames[s]
    if not R.active(s,Run) or not f or f.serial~=r.fleet_id or not f.samples or #f.samples<2 then
      local a,b,c,w
      if native and Run.presentation_sample then a,b,c,w=Run.presentation_sample(s,r,part)
      else a,b,c,w=Run.sample(r,part) end
      return a,b,c,not not r.consist.reversed,w
    end
    local x=1+math.min(1,math.max(0,fraction or 1))*(#f.samples-1)
    local i=math.floor(x)
    local a,b=f.samples[i][part],f.samples[i+1] and f.samples[i+1][part]
    if not a or a[6] and not native then return end
    local p=a[3]
    if b and a[1]==b[1] and a[2]==b[2] and a[4]==b[4] and a[5]==b[5] and (native or not b[6]) then p=p+(b[3]-p)*(x-i) end
    return a[1],a[2],p,a[4],a[5]
  end
  function R.take(s,key)
    local f=frame(s)
    local out=f[key];f[key]={}
    return out
  end
  return R
end
