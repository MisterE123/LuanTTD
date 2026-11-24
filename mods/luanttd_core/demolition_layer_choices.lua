-- Shared ownership/occupancy-aware layer options for native and worker UI.
return function(api,clear_structure)
  local S,Sim=api.s,api.Sim
  local function money(n) return (n<0 and "-$" or "$")..math.abs(n) end
  local function choices(n,id)
    local t=S.tiles[id]
    local opts,seen={},{}
    if not t then return opts end
    local function add(key,title,ok,detail,apply)
      if seen[key] then return end
      seen[key]=true
      opts[#opts+1]={key=key,title=title,ok=not not ok,detail=detail or "",apply=apply}
    end
    local function structure(key,title,at)
      if not at then return end
      local handled,tiles,note=clear_structure(n,at,true)
      if handled then add(key,title,tiles,note,function() return clear_structure(n,at,false) end) end
    end
    local function span(index,records,title,key)
      local q=index and records and records[index[id]]
      if q then structure(key,title,q.start) end
    end
    span(S.bridge_above,S.stock_road_bridges,"Remove overhead road bridge, keep surface","road_bridge")
    span(S.rail_bridge_above,S.stock_rail_spans,"Remove overhead rail bridge, keep surface","rail_bridge")
    span(S.aqueduct_above,S.stock_aqueducts,"Remove overhead aqueduct, keep surface","aqueduct")
    span(S.tunnel_below,S.stock_road_tunnels,"Remove road tunnel below, keep surface","road_tunnel")
    span(S.rail_tunnel_below,S.stock_rail_spans,"Remove rail tunnel below, keep surface","rail_tunnel")
    if api.tram and api.tram.span_busy then
      local tr=api.tram
      local span=tr.network.span_at(S,id,true)
      if span and span.tramtype~=nil then
        local quote,why=tr.network.span_plan(S,n,span.id,span.axis,"remove",tr.span_busy)
        local detail=quote and (quote.cost<0 and "Refund: "..money(-quote.cost) or "Cost: "..money(quote.cost))
          or why=="VEHICLE_IN_THE_WAY" and "Clear the span and stop any tram route using it first." or tostring(why)
        add("tram_span","Remove tramway from "..span.kind..", keep road pavement",quote,detail,function()
          local ok,note,tiles=tr.network.apply_span(S,n,quote,tr.span_busy)
          return true,ok and tiles or nil,note
        end)
      end
    end
    if t.tram then
      local tr=api.tram
      if t.tram.shared_station and tr and tr.network then
        local function plan()
          local busy=tr.busy_probe and tr.busy_probe() or tr.busy
          return tr.network.remove_plan(S,n,{first=id,last=id,axis=t.tram.dir,start_half=false,end_half=true},busy)
        end
        local q,why=plan()
        add("tram_shared_stop","Remove tram tracks, keep the shared bus platform",q,
          q and ("Refund: "..money(-q.cost)) or Sim.road_removal_error(why),function()
            local fresh,note=plan()
            if not fresh then return true,nil,Sim.road_removal_error(note) end
            local ok,result,tiles=tr.network.apply_remove(S,n,fresh)
            return true,ok and tiles or nil,result
          end)
      elseif (t.tram.kind=="depot" or t.tram.kind=="drive_stop") and tr and tr.network and tr.network.facility_removal_plan then
        local function busy()
          return tr.busy_probe and tr.busy_probe() or tr.busy
        end
        local q,why=tr.network.facility_removal_plan(S,n,id,busy())
        local label=t.tram.kind=="depot" and "Remove tram depot" or "Remove tram platform, keep tracks and pavement"
        local detail=q and ("Cost: "..money(q.cost)) or
          why=="VEHICLE_IN_THE_WAY" and "Stop the tram service using this facility before removing it." or
          why=="OWNED_BY_ANOTHER" and "This facility belongs to another company." or
          why=="NOT_ENOUGH_MONEY" and "Not enough cash." or tostring(why)
        add("tram_facility",label,q,detail,function()
          local ok,note,tiles=tr.network.apply_facility_removal(S,n,q,busy())
          return true,ok and tiles or nil,note
        end)
      else
        add("tramway","Tram tracks",false,"Use Remove Tram Track to remove the selected tramway without affecting roads.")
      end
    end
    local crossing=t.level_crossing
    if crossing then
      local axis=crossing.road_axis
      if crossing.roadtype~=nil and Sim.road_remove_plan then
        local q,why=Sim.road_remove_plan(S,n,id,id,axis,false,true)
        add("crossing_road","Remove road pavement, keep rails and any tramway",q,
          q and ("Cost: "..money(q.cost)) or Sim.road_removal_error(why),function()
            local ok,note,tiles=Sim.apply_road_removal(S,n,q)
            return true,ok and tiles or nil,note
          end)
      end
      if crossing.tramtype~=nil and api.tram and api.tram.network then
        local busy=api.tram.busy_probe and api.tram.busy_probe() or api.tram.busy
        local q,why=api.tram.network.remove_plan(S,n,{first=id,last=id,axis=axis,
          start_half=false,end_half=true},busy)
        add("crossing_tram","Remove tram tracks, keep rails and any pavement",q,
          q and (q.cost<0 and ("Refund: "..money(-q.cost)) or ("Cost: "..money(q.cost))) or
            (api.tram.reason and api.tram.reason(why) or tostring(why)),function()
            local ok,note,tiles=api.tram.network.apply_remove(S,n,q)
            return true,ok and tiles or nil,note
          end)
      end
      if Sim.crossing_rail_remove_plan then
        local q,why=Sim.crossing_rail_remove_plan(S,n,id)
        local rule=why=="WAIT_RAIL_RESERVATION" and "Wait for the rail reservation to be released."
          or why=="OWNED_BY" and "The railway belongs to another company."
          or why=="VEHICLE_IN_THE_WAY" and "Wait for vehicles to clear the crossing."
          or why and Sim.crossing_construction_error(why)
        add("crossing_rail","Remove the railway, keep road and tramway",q,
          q and ("Refund: "..money(-q.cost)) or rule,function()
            local ok,note,tiles=Sim.apply_crossing_rail_removal(S,n,q)
            return true,ok and tiles or nil,note
          end)
      end
      if not (seen.crossing_road or seen.crossing_tram or seen.crossing_rail) then
        add("crossing","Level crossing",false,"No removable surface layer is available on this crossing.")
      end
    end
    if t.rail_station_id or t.rail_depot_dir~=nil then
      local title=t.rail_station_id and "Remove entire station platform, keep rails" or "Remove railway depot, keep rails"
      local free=t.owner==n and api.rail_build and not api.rail_build.busy() and api.trackworks
        and (not api.trackworks.span_protected or not api.trackworks.span_protected(S,id))
      local occupied=t.rail_depot_dir~=nil and api.trackworks and api.trackworks.owned_depot_occupied
        and api.trackworks.owned_depot_occupied(S,id)
      add("rail_facility",title,free and not occupied,occupied and "The depot contains a purchased train."
        or not free and "Only clear, owned facilities can be changed while no train is using this railway."
        or "Underlying track stays in place. You can bulldoze it separately afterward.",function()
        local ok,note,tiles=api.trackworks.remove_facility(S,n,id)
        return true,ok and tiles or nil,note
      end)
    end
    local d=S.stock_rail_dispatch
    local function rail_action(key,title,plan,why)
      add(key,title,plan,plan and ("Cost: "..money(plan.price)) or why,function()
        local ok,note=api.rail_build.build(n,plan)
        return true,ok and {} or nil,note
      end)
    end
    if api.rail_build and t.rail_waypoint_id then
      rail_action("waypoint","Remove waypoint, keep rails",api.rail_build.quote_waypoint(n,id,true))
    end
    if api.rail_build and d and d.signals and d.signals.records[id] then
      if api.rail_build.signal_details then
        local track_name={[2]="upper curve",[3]="lower curve",[4]="left curve",[5]="right curve"}
        for track=0,5 do
          if api.rail_build.signal_details(id,track) then
            local title=track_name[track] and ("Remove signal on "..track_name[track]..", keep rails") or "Remove signal, keep rails"
            rail_action("signal_"..track,title,api.rail_build.quote_remove_signal(n,id,track))
          end
        end
      else rail_action("signal","Remove signal, keep rails",api.rail_build.quote_remove_signal(n,id)) end
    end
    if t.build=="road_station" and t.stop_axis and not t.road_stop_pair and Sim.remove_through_road_stop then
      local can,cost=Sim.remove_through_road_stop(S,n,id,true)
      add("through_stop","Remove stop, keep road",can,can and ("Cost: "..money(cost)) or cost,function()
        local ok,note,tiles=Sim.remove_through_road_stop(S,n,id)
        return true,ok and tiles or nil,note
      end)
    end
    if t.station or t.build=="road_depot" then
      if not t.road_town then
        local plan,cost=Sim.plan(S,n,"clear",{id},true)
        local balance=S.companies[n] and S.companies[n].cash or 100000
        local title=t.build=="road_depot" and "Remove road depot" or "Remove stop and its road"
        add("ground_facility",title,plan and balance>=cost,plan and ("Cost: "..money(cost)) or cost,function()
          local ok,note,tiles=Sim.build(S,n,"clear",{id})
          return true,ok and tiles or nil,note
        end)
      end
    end
    if t.road_bridge_id then structure("road_bridge","Remove the full road bridge",id)
    elseif t.road_tunnel_id then structure("road_tunnel","Remove both road tunnel portals",id)
    elseif t.rail_span_id then structure("rail_span","Remove the full rail bridge or tunnel",id)
    elseif t.airfield then structure("airfield","Remove the entire airfield",id)
    elseif t.ship then structure("harbor","Remove the full harbor structure",id) end
    if t.rail_type==1 and not t.rail_station_id and not t.rail_depot_dir and not t.rail_span_id and
        not t.level_crossing and api.electric_quote and api.electric_commit then
      local q,why=api.electric_quote(n,{id},0)
      add("wire","Remove electrification, keep rails",q,q and ("Cost: "..money(q.cost)) or why,function()
        local ok,note=api.electric_commit(n,q)
        return true,ok and {} or nil,note
      end)
    end
    return opts
  end
  return choices
end
