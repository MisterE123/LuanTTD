-- The disposition that LuanTTD can author after its isolated trip.
-- A stock-assisted tool consumes this receipt; this module never writes .sav.
return function(Import,Check,sha256)
  local M={}
  function M.from_played(input,journal,action)
    local reserve_mode=action=="reroute_next_with_parked_reserve"
    local to_third=action=="reroute_next_to_existing_third_stop" or reserve_mode
    assert(action=="no_loading_on_next_stop" or to_third,"only tested ordinary next-order changes are supported")
    local additional=input.resume.existing_third_station
    local reserve_id=input.resume.depot_reserve_id
    assert(to_third==(additional~=nil) and reserve_mode==(reserve_id~=nil),"wrong station or roster scope for the requested edit")
    local r=Import.open(input,journal)
    local s=r.state()
    assert(s.phase=="paused" and s.delivery_tick==s.tick and s.arrived_tick
      and s.arrived_tick<s.delivery_tick and s.payment_pulses==0 and s.unload_pulses==1
      and s.payment==0 and s.staged_fare>0 and s.units==0,
      "first trip must be saved exactly after delivery with the payment still pending")
    local accepted=Check.prepare(input.checkpoint,additional,reserve_id)
    local paused=accepted.checkpoint()
    local v=paused.vehicle
    local idx=(v.order_index+1)%#v.orders
    local current,next_order=v.orders[v.order_index+1],v.orders[idx+1]
    assert(next_order.id~=current.id and next_order.station~=current.station
      and next_order.raw.type==97 and next_order.raw.flags==0 and next_order.raw.refit_cargo==254,
      "unsupported upcoming stock order")
    local out={schema="luanttd-stock-order-intent/1",action=action,
      source_sha256=paused.source.sha256,journal=journal,journal_sha256=sha256(journal),
      start_tick=tonumber(paused.clock.tick_counter),authored_tick=s.tick,arrival_tick=s.arrived_tick,delivery_tick=s.delivery_tick,
      vehicle_id=v.id,company_id=v.owner,order_list_id=v.order_list_id,
      current={index=v.order_index,order_id=current.id,station=current.station,tile=v.dest.source_id},
      upcoming={index=idx,order_id=next_order.id,station=next_order.station},fare_pending=s.staged_fare,
      delivered=s.delivered,loaded=s.units,
      stock_motion={s.pixels.x,s.pixels.z,s.pixels.y,s.heading,s.speed,s.subspeed,s.progress,s.age_counter,s.trackdir,s.frame,s.loading_ticks},
    }
    if to_third then
      local station=paused.stations[additional]
      assert(station.id~=current.station and station.id~=next_order.station,"the reroute must be a genuinely third station")
      out.third={station=station.id,tile=station.tile.source_id,route=accepted.next_station(additional)}
    end
    if reserve_mode then
      local r=paused.reserve
      out.reserve={id=r.id,order_list_id=r.order_list_id,order_id=r.order_id,order_station=r.order_station,
        depot_id=r.depot_id,depot_tile=r.depot_tile,raw_sha256=r.raw_sha256}
    end
    return out
  end
  return M
end
