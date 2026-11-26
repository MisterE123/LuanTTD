-- SPDX-License-Identifier: GPL-2.0-only
-- Original game: shared station loading/economy and exact stock ship parameters.
-- Bridge an oil ship into the real farm/oil/Goods station allocator, never
-- synthesize a shipment or allocate in a second pass. Docks use the same
-- catchment, rating, loading/acceptance and receipt adapter as other freight.
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local Rig=dofile(mod.."/openttd/oil_rig.lua")
local dock_path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local DockMembers=dofile(dock_path.."dock_station_members.lua")
return function(Sim,Roster,Packets,Rating,LoadingFactory,BaseTiming)
  local M={}
  local Timing={
    initial=BaseTiming.initial,can_leave=BaseTiming.can_leave,
    pulse=function(m)
      local wait,stop,finished,refresh=BaseTiming.pulse(m)
      if m.loaded+m.unloaded>0 or m.retry_unload then
        wait=m.gradual and 10 or math.max(1,m.loaded+m.unloaded)
      else wait=20 end
      return wait,stop,finished,refresh
    end,
  }
  local Loader=LoadingFactory(Timing,Packets)
  function M.station_id(id)
    assert(type(id)=="number" and id%1==0 and id>=1 and id<0x4000)
    -- Rail and passenger/coal dock channels already reserve ranges below this.
    return 0x10000+id
  end
  function M.bind_stations(s,state,board,owns)
    local list,by_dock={},{}
    for id,d in pairs(s.stock_ship_stations or {}) do
      if not owns or owns(id) then
        local shore,water=board.tile(d.land),board.tile(d.water)
        local neutral=Rig.neutral_ref(s,d)
        local valid_rig=neutral and shore and shore.kind=="oilrig" and shore.station==id and #board.station_dock_tiles(id)>0
        local valid_dock=shore and water and shore.kind=="dock" and water.kind=="dock" and
          shore.station==id and water.station==id and water.water_part and not shore.water_part
        if valid_dock or valid_rig then
          local x,z=Sim.xy(d.land)
          local slot=M.station_id(id)
          local st=state.stations[slot] or {id=slot,host_id=id,mode="ship",freight_cargo="oil",owner=d.owner,
            loading_order={},rating_phase=0,time_since_unload=255,time_since_load=255}
          assert(st.owner==d.owner,"Oil dock ownership changed")
          st.neutral_rig=valid_rig and neutral.industry or nil
          st.serve_neutral=s.stock_serve_neutral_industries~=false
          st.tile,st.x,st.z,st.tiles=d.land,x-1,z-1,{{x=x-1,y=z-1,kind="dock"}}
          if valid_dock then st.tiles=DockMembers.footprint(d,Sim.xy) end
          by_dock[id]=st;list[#list+1]=st;state.stations[slot]=st
        end
      end
    end
    table.sort(list,function(a,b)return a.id<b.id end)
    return list,by_dock
  end
  function M.new(craft)
    local model=assert(Roster.model(craft.engine))
    return {stations={},vehicle={id=craft.id,engine=craft.engine,owner=craft.owner,cargo="oil",mode="ship",
      built=craft.built,cached_max_speed=model.max_speed,units=0,batches={},delivered=0,revenue=0,
      running_ticks=0,running_fixed=0}}
  end
  function M.bind(state,B,stations,by_dock,board,callbacks)
    local D={}
    callbacks=callbacks or {}
    local v=state.vehicle
    local model=assert(Roster.model(v.engine))
    local function berth(local_id,tile)
      for _,id in ipairs(board.station_dock_tiles(local_id)) do if id==tile then return true end end
      return false
    end
    local function opts(tick)
      local options=B.ops(tick,callbacks.emit)
      options.gradual=callbacks.gradual~=false
      options.slice=model.load_amount
      return options
    end
    function D.report(dock)
      local st=by_dock[dock]
      if st then return B.report(st,"oil") end
    end
    function D.loading(tick,stopped)
      if state.tick==tick then return false end
      if state.tick and (state.post~=state.tick or state.tick+1~=tick) then return nil,"OIL_SHIP_CLOCK_GAP" end
      local l=v.load_state
      local st=l and stations[l.station]
      if l and (not st or by_dock[st.host_id]~=st or not berth(st.host_id,v.cargo_tile)) then return nil,"OIL_SHIP_BERTH_LOST" end
      v.stopped=not not stopped
      state.tick=tick
      if l then
        local o=opts(tick)
        local _,ready=Loader.tick(st,{[v.id]=v},o)
        o.station_done(st)
        if #ready>0 then l.ready_tick=tick end
      end
      return true
    end
    function D.arrive(dock,visit,tick,tile,order)
      local st=by_dock[dock]
      if not st or st.owner~=v.owner and not st.neutral_rig or not berth(dock,tile) then return nil,"OWN_WATER_BERTH_REQUIRED" end
      if tick~=state.tick or tick==state.post then return nil,"WRONG_OIL_SHIP_TICK_PHASE" end
      if visit==v.visit and v.load_state and v.load_state.station==st.id and v.cargo_tile==tile then return v.load_state end
      if visit<=(v.visit or 0) or v.load_state then return nil,"STALE_OIL_SHIP_VISIT" end
      if order~="full" and order~="no_load" then return nil,"UNSUPPORTED_OIL_SHIP_ORDER" end
      v.cargo_tile,v.visit=tile,visit
      local l=Loader.begin(st,v,model.capacity,{full=order=="full",no_load=order=="no_load"},opts(tick))
      l.arrived_tick=tick
      return l
    end
    function D.leave(visit,tick,force)
      local l=v.load_state
      if not l or v.visit~=visit or not force and l.ready_tick~=tick or state.tick~=tick or state.post==tick then return false end
      local st=assert(stations[l.station])
      local o=opts(tick)
      Loader.leave(st,v,o);o.station_done(st)
      v.cargo_tile=nil
      return true
    end
    function D.cancel_full() if v.load_state then v.load_state.full=false end end
    function D.after(tick)
      if state.tick~=tick then return nil,"WRONG_OIL_SHIP_TICK_PHASE" end
      if state.post==tick then return false end
      Loader.age_vehicle(v,1,model.cargo_age_ticks)
      if not v.stopped then v.running_ticks=v.running_ticks+1 end
      state.post=tick
      return true
    end
    local dock_order={}
    for id in pairs(by_dock) do dock_order[#dock_order+1]=id end
    table.sort(dock_order)
    function D.rating(tick)
      for _,id in ipairs(dock_order) do
        local st=by_dock[id]
        local phase,events=Rating.advance_clock(st.rating_phase,1)
        st.rating_phase=phase
        if events>0 then
          Rating.increment_station_timers(st)
          B.step_rating(st)
        end
      end
    end
    function D.settle(day,running_base)
      if state.settled and day<=state.settled then return 0 end
      state.settled=day
      local fixed=Roster.running_fixed(v.engine,v.running_ticks,running_base)
      v.running_ticks=0;v.running_fixed=v.running_fixed+fixed
      if fixed>0 and callbacks.charge_fixed then callbacks.charge_fixed(v.owner,fixed) end
      return fixed
    end
    return D
  end
  return M
end
