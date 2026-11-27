-- SPDX-License-Identifier: GPL-2.0-only
-- One ordinary 1950 Yate delivering coal, pure host-side station adapter.
-- Uses existing stock packets, loading, catches and mine/plant authority.
-- No movement/production clock. Host calls one phase of its stock tick.
local dock_path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local DockMembers=dofile(dock_path.."dock_station_members.lua")
return function(Sim,Coal,Catchment,Roster,Packets,Rating,Station,Income,LoadingFactory,BaseTiming)
  local M={version=1,station_base=0x8000}
  local Timing=Roster.timing(BaseTiming)
  local Loader=LoadingFactory(Timing,Packets)
  local function ids(t)
    local list={};for k in pairs(t or {}) do list[#list+1]=k end
    table.sort(list);return list
  end
  function M.index(id)
    assert(type(id)=="number" and id>=0 and id%1==0 and id<M.station_base/2,"Dock station ID out of range")
    return M.station_base+id
  end
  function M.new() return {version=M.version,stations={}} end
  function M.bind(s,state,ctx)
    assert(state.version==M.version,"Unsupported coal vessel state")
    local ship_board=assert(ctx.board,"A real stock ship board is required")
    local xy=ctx.xy or Sim.xy
    local real=s.stock_ship_stations or {}
    local industries=ctx.industries or s.stock_coal_industries or {}
    local list,coverage={},{}
    for _,local_id in ipairs(ids(real)) do
      local d=real[local_id]
      local shore,wet=ship_board.tile(d.land),ship_board.tile(d.water)
      if (not ctx.dock_filter or ctx.dock_filter(local_id)) and d.id==local_id and shore and wet and shore.kind=="dock" and wet.kind=="dock" and
          shore.station==local_id and wet.station==local_id and shore.owner==d.owner and wet.owner==d.owner and
          not shore.water_part and wet.water_part then
        local x,z=xy(d.land)
        local id=M.index(local_id)
        local st=state.stations[id] or {id=id,mode="ship",host_id=local_id,owner=d.owner,
          stock={coal={}},loading_order={},time_since_load=255,time_since_unload=255,rating_phase=0}
        assert(st.owner==d.owner,"Coal dock ownership changed")
        local tiles,rev=DockMembers.footprint(d,xy)
        local changed=st.footprint_rev~=rev
        st.land,st.water,st.x,st.z,st.tile=d.land,d.water,x-1,z-1,d.land
        st.tiles,st.footprint_rev=tiles,rev
        local town=ctx.town and ctx.town(st) or Sim.nearest_town(s,d.land)
        st.town=type(town)=="table" and town.id or town
        local c=Catchment.build(st,ctx.width or Sim.W,ctx.height or Sim.H,ctx.modified_catchment)
        Coal.goods(st);coverage[id]=c;list[#list+1]=st;state.stations[id]=st
        if changed or st.last_acceptance==nil then st.last_acceptance=Coal.acceptance(st,c,industries).accepts end
      end
    end
    for id,st in pairs(state.stations) do
      -- An active controller must notice loss of the berth, without
      -- deleting its in-flight ledger or offering it any further cargo.
      if not coverage[id] and #st.loading_order==0 then state.stations[id]=nil end
    end
    local B={stations=list,coverage=coverage}
    function B.extend(stations,covers)
      local seen={}
      for _,st in ipairs(stations) do seen[st.id]=true end
      for _,st in ipairs(list) do
        assert(not seen[st.id] and not covers[st.id],"Duplicate global dock coal station")
      end
      for _,st in ipairs(list) do
        stations[#stations+1]=st;covers[st.id]=coverage[st.id]
      end
      table.sort(stations,function(a,b) return a.id<b.id end)
    end
    function B.report(local_id)
      local id=M.index(local_id)
      local st,c=state.stations[id],coverage[id]
      if not c then return end
      local r=Coal.acceptance(st,c,industries)
      r.accepts,r.station,r.sources,r.waiting=st.last_acceptance,st,{},Coal.waiting(st)
      for _,id_ in ipairs(ids(industries)) do
        local ind=industries[id_]
        if ind.produced and not ind.removed then
          for _,t in ipairs(ind.tiles) do
            if Catchment.contains(c,t.x,t.z) then r.sources[#r.sources+1]=ind.id;break end
          end
        end
      end
      return r
    end
    function B.update_acceptance(st)
      local c=coverage[st.id]
      if not c then return false end
      st.last_acceptance=Coal.acceptance(st,c,industries).accepts
      return true
    end
    function B.vehicle(def)
      if state.vehicle or not def.engine or not Roster.model(def.engine) or def.cargo~=Roster.coal or
          type(def.id)~="number" or type(def.built)~="number" or not def.owner then
        return nil,"OWN_YATE_REFITTED_TO_COAL_REQUIRED"
      end
      local v={id=def.id,owner=def.owner,mode="ship",engine=def.engine,cargo="coal",built=def.built,
        units=0,batches={},cargo_age_counter=1,delivered=0,revenue=0,
        profit_with_feeders=0,running_ticks=0,running_fixed=0}
      state.vehicle=v
      return v
    end
    local function emit(kind,st,v,tick,e)
      e=e or {}
      e.kind,e.cargo,e.mode,e.vehicle,e.owner=kind,"coal","ship",v.id,v.owner
      e.station,e.station_local,e.tile,e.tick,e.visit=st.id,st.host_id,v.cargo_tile,tick,v.visit
      if ctx.emit then ctx.emit(e) end
    end
    local function option(k,tick)
      local v=ctx[k]
      return type(v)=="function" and v(s,tick) or v
    end
    local function options(tick)
      local pending={}
      local function carrier(st,v) return {id=st.id,tile=v.cargo_tile} end
      local function delivery(st,v,p)
        local distance=Packets.distance(p,v.cargo_tile,xy)
        local result=Coal.delivery(st,B.report(st.host_id),p,{distance=distance,
          current_payment=option("current_payment",tick),date=option("economy_date",tick) or s.day,refused=ctx.refused})
        if Sim.stock_town_accept then Sim.stock_town_accept(s,st.town,"coal",result.accepted,0) end
        if result.accepted>0 and Sim.stock_subsidy_active and Sim.stock_subsidy_active(s) then
          result.payment=Sim.stock_subsidy_pay(s,"coal",v.owner,p,result.payment,coverage[st.id].tiles,"coal")
        end
        local l=v.load_state
        l.coal_accepted=(l.coal_accepted or 0)+result.accepted
        for _,plant in ipairs(result.plants) do
          pending[plant.industry.id]=plant.industry
          if plant.amount>0 then
            if ctx.received then ctx.received(s,plant.industry,plant.amount) end
            emit("deliver",st,v,tick,{units=plant.amount,distance=distance,age=p.age or 0,
              source_industry=p.source,destination_industry=plant.industry.id})
          end
        end
        return result.payment
      end
      return {
        slice=Roster.load_amount,gradual=s.stock_gradual_loading~=false,feeder_percent=s.stock_feeder_percent,
        accepts=function(st) return st.last_acceptance end,
        can_load=function(st,v) return Catchment.may_load(st,v.owner,ctx.town_rights and ctx.town_rights(st.town),ctx.neutral_owner) end,
        pickup=function(st,v,p) Packets.pickup(p,carrier(st,v),xy) end,
        drop=function(st,v,p) Packets.drop(p,carrier(st,v),xy) end,
        attempt=function(st,v,left)
          Coal.observe_loading(st,{mode="ship",build_year=v.built,max_speed=Roster.max_speed},
            left,option("year",tick) or Sim.date(s))
        end,
        loaded=function(st,v,n)
          Catchment.loaded(st,"ship",n)
          local common=ctx.stationwide and ctx.stationwide(st)
          if common and common~=st then Catchment.loaded(common,"ship",n) end
          emit("board",st,v,tick,{units=n})
        end,
        unloaded=function(st)
          Station.unloaded(st)
          local common=ctx.stationwide and ctx.stationwide(st)
          if common and common~=st then Station.unloaded(common) end
        end,
        deliver=delivery,
        payment=function(st,v,p)
          local l=v.load_state
          local n=l.coal_accepted or 0;l.coal_accepted=nil
          assert(n<=p.delivered)
          if n>0 then
            v.delivered,v.revenue=v.delivered+n,v.revenue+p.route
            if ctx.credit then ctx.credit(s,v.owner,p.route,n) end
            emit("fare",st,v,tick,{units=n,amount=p.route})
          end
          v.profit_with_feeders=v.profit_with_feeders+p.visual+p.transfer
        end,
        pending=pending,
      }
    end
    local function finish(ops)
      local plants={}
      for _,i in ipairs(ids(ops.pending)) do plants[#plants+1]={industry=ops.pending[i]} end
      Coal.trigger_delivery({plants=plants})
    end
    local function berth(local_id,tile)
      for _,id in ipairs(ship_board.station_dock_tiles(local_id)) do if id==tile then return true end end
      return false
    end
    function B.arrive(local_id,visit,tick,tile,order)
      local v=state.vehicle
      if not v or state.loading_tick~=tick or state.post_tick==tick then return nil,"WRONG_SHIP_TICK_PHASE" end
      if v.visit==visit and v.load_state and v.load_state.station==M.index(local_id) and v.cargo_tile==tile then
        return v.load_state
      end
      if not (type(visit)=="number" and visit>(v.visit or 0)) or v.load_state then return nil,"STALE_VISIT" end
      local id=M.index(local_id)
      local st=state.stations[id]
      if not coverage[id] or st.owner~=v.owner then return nil,"OWN_DOCK_REQUIRED" end
      if not berth(local_id,tile) then return nil,"ACTUAL_WATER_BERTH_REQUIRED" end
      -- Ordinary manual coal shuttle only: full loading on the outward
      -- leg, no load at power, and no forced transfer or auto refit.
      if order~="full" and order~="no_load" then return nil,"UNSUPPORTED_SHIP_ORDER" end
      v.visit,v.cargo_tile=visit,tile
      local l=Loader.begin(st,v,Roster.model(v.engine).capacity,{full=order=="full",no_load=order=="no_load"},options(tick))
      l.arrived_tick=tick
      emit("arrive",st,v,tick)
      return l
    end
    function B.loading_tick(tick,stopped,removed_berth)
      if state.loading_tick==tick then return false end
      if state.loading_tick and (state.post_tick~=state.loading_tick or tick~=state.loading_tick+1) then
        return nil,"NONCONTIGUOUS_COAL_SHIP_TICK"
      end
      local v=state.vehicle
      local l=v and v.load_state
      if l and (not coverage[l.station] or not removed_berth and not berth(state.stations[l.station].host_id,v.cargo_tile)) then
        return nil,"COAL_SHIP_BERTH_LOST"
      end
      if v then v.stopped=not not stopped end
      state.loading_tick=tick
      if not l or removed_berth then return true end
      local ops=options(tick)
      local _,departures=Loader.tick(state.stations[l.station],{[v.id]=v},ops)
      finish(ops)
      if #departures>0 then l.ready_tick=tick end
      return true
    end
    function B.leave(visit,tick,force)
      local v=state.vehicle
      local l=v and v.load_state
      if not l or v.visit~=visit or not force and l.ready_tick~=tick or state.loading_tick~=tick or state.post_tick==tick then
        return false
      end
      local st=state.stations[l.station]
      local ops=options(tick)
      Loader.leave(st,v,ops);finish(ops)
      emit("leave",st,v,tick)
      v.cargo_tile=nil
      return true
    end
    function B.cancel_full()
      local v=state.vehicle
      if v and v.load_state then v.load_state.full=false end
    end
    function B.after_motion(tick)
      if state.loading_tick~=tick then return nil,"WRONG_SHIP_TICK_PHASE" end
      if state.post_tick==tick then return false end
      local v=state.vehicle
      if v then
        Loader.age_vehicle(v,1,Roster.cargo_age_ticks)
        if not v.stopped then v.running_ticks=v.running_ticks+1 end
      end
      state.post_tick=tick
      return true
    end
    -- Called inside the shared ordinary rating phase, by CargoID, after
    -- the host advanced this dock's station-wide timers exactly once.
    -- A passenger dock view sharing this physical station supplies the
    -- same station-wide last_vehicle_type/timers through ctx.stationwide.
    function B.rating(st,tick)
      if not coverage[st.id] then return end
      local common=(ctx.stationwide and ctx.stationwide(st)) or st
      return Coal.rating_tick(st,{select_goods=s.stock_select_goods,ship=common.last_vehicle_type=="ship",
        statue=Sim.station_has_town_statue and Sim.station_has_town_statue(s,common),
        truncate=Station.truncate,random_u32=ctx.random_u32 or function() return Station.random_u32(s) end,
        station_at=function(i) return state.stations[i] or (ctx.station_at and ctx.station_at(i)) end})
    end
    -- Source ship running_ticks advance while unstopped, including while
    -- moored/loading. Charge on economy day, in 1/256 of cash. Never
    -- convert costs to whole dollars before the shared company debit.
    function B.economy_day(day)
      if state.settled_day and day<=state.settled_day then return 0 end
      state.settled_day=day
      local v=state.vehicle
      if not v then return 0 end
      local cost=Roster.running_fixed(v.running_ticks,option("running_base",day),v.engine)
      v.running_ticks=0;v.running_fixed=v.running_fixed+cost
      if cost>0 and ctx.charge_fixed then ctx.charge_fixed(s,v.owner,cost) end
      return cost
    end
    return B
  end
  return M
end
