-- Bounded station counts and exact boarding events for the cosmetic crowd
-- renderer. Never ships raw passenger queues or lets the view advance them.
return function(Sim,s)
  local Q={}
  local modes={"road","rail","ship","air"}
  local events={}
  local sequence=0
  local now=0
  local function id(mode,id_)
    return mode..":"..id_
  end
  function Q.counts(cells)
    local values={}
    local function observe(mode,terminal)
      if not terminal then return end
      local key=id(mode,terminal)
      if values[key]~=nil then return end
      local count
      if mode=="road" then
        local stop=s.stations[terminal]
        if stop and stop.mode=="road" and stop.stop_type~="truck" then count=Sim.waiting_passengers(s,stop) end
      else count=Sim.commercial_passengers_waiting(s,mode,terminal) end
      values[key]=count or 0
    end
    for _,row in ipairs(cells) do
      local t=s.tiles[row.id]
      observe("road",t.station or Sim.tram_stop_id(t))
      observe("rail",t.rail_station_id)
      if t.ship and t.ship.kind=="dock" then observe("ship",t.ship.station) end
      if t.airfield then observe("air",t.airfield.airport) end
    end
    return values
  end
  local function add(mode,terminal,units,tile,owner)
    if not (terminal or owner) or not tile or not units or units<=0 then return end
    sequence=sequence+1
    local x,z=Sim.xy(tile)
    events[#events+1]={seq=sequence,time=now,mode=mode,id=terminal,units=units,x=x,z=z,owner=owner,tile=tile}
    if #events>256 then table.remove(events,1) end
  end
  function Q.frame(dt)
    now=now+dt
    while events[1] and now-events[1].time>1.2 do table.remove(events,1) end
  end
  function Q.collect()
    local road=Sim.road_loading_events(s)
    for _,e in ipairs(road) do
      if e.kind=="board" and e.cargo=="passenger" then
        local t=s.tiles[e.data.tile]
        add("road",t and (t.station or Sim.tram_stop_id(t)),e.data.units,e.data.tile)
      elseif e.kind=="fare" and e.owner then
        add("road",nil,e.data.amount,e.data.tile,e.owner)
      end
    end
    local sources={rail=Sim.rail_loading_events,ship=Sim.ferry_loading_events,air=Sim.air_loading_events}
    for _,mode in ipairs(modes) do
      if sources[mode] then
        for _,e in ipairs(sources[mode](s)) do
          if e.kind=="board" then add(mode,e.station_local,e.units,e.tile)
          elseif e.kind=="fare" and e.owner then add(mode,nil,e.amount,e.tile,e.owner) end
        end
      end
    end
  end
  function Q.collect_fares(events,mode)
    for _,e in ipairs(events) do
      if e.kind=="fare" and e.owner then add(mode,nil,e.amount,e.tile,e.owner) end
    end
  end
  function Q.events(windows,after)
    local result,fares={},{}
    after=type(after)=="number" and after or 0
    for _,e in ipairs(events) do
      if e.seq>after then
        for _,w in ipairs(windows) do
          if e.x>=w.x and e.x<w.x+w.w and e.z>=w.z and e.z<w.z+w.h then
            if e.owner then fares[#fares+1]={seq=e.seq,owner=e.owner,tile=e.tile}
            else result[#result+1]={seq=e.seq,mode=e.mode,id=e.id,units=e.units} end
            break
          end
        end
      end
    end
    return result,sequence,fares
  end
  return Q
end
