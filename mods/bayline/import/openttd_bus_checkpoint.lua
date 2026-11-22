-- Isolated acceptance boundary, not a world restore or simulation entry point.
-- The passed dependencies are the same pinned terrain, road frame and YAPF
-- kernels used elsewhere; no hard-coded campaign dimensions or copied game.
return function(Sparse,Slope,RoadSlope,Motion,F,Cost,Yapf)
  local M={}
  local floor,min,max,abs=math.floor,math.min,math.max,math.abs
  local function int(n,lo,hi)
    return type(n)=="number" and n>=lo and n<=hi and n==floor(n)
  end
  local function must(n,lo,hi,label)
    assert(int(n,lo,hi),"invalid stock "..label)
    return n
  end
  local function decimal(s,limit,label,negative)
    assert(type(s)=="string","expected exact decimal stock "..label)
    local digits=s
    if negative and s:sub(1,1)=="-" then digits=s:sub(2); limit="9223372036854775808" end
    assert((digits=="0" and s=="0") or
      (digits:match("^[1-9][0-9]*$") and (#digits<#limit or (#digits==#limit and digits<=limit))),
      "invalid or overflowing stock "..label)
    return s
  end
  local function clone(v)
    if type(v)~="table" then return v end
    local t={}
    for k,r in pairs(v) do t[k]=clone(r) end
    return t
  end
  local function array(a,limit,label)
    assert(type(a)=="table" and getmetatable(a)==nil,"invalid stock "..label)
    local count=0
    for i in pairs(a) do
      assert(int(i,1,limit),"invalid stock "..label.." array index")
      count=count+1
    end
    for i=1,count do assert(a[i]~=nil,"sparse stock "..label) end
    return count
  end
  local function indexed(data,limit,label)
    assert(type(data)=="table" and getmetatable(data)==nil,"invalid stock "..label)
    local result,count={},0
    for k,v in pairs(data) do
      local id=tonumber(k)
      assert(type(k)=="string" and int(id,0,limit) and tostring(id)==k and type(v)=="table",
        "invalid stock "..label.." index")
      result[id]=v
      count=count+1
    end
    return result,count
  end
  local function money(s,label) return decimal(s,"9223372036854775807",label,true) end
  local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  local function route_board(base,world,stops)
    local B={}
    local function xy(id)
      local x,z=base.source_tile_xy(id)
      if x then return x-1,z-1 end
    end
    function B.xy(id) return xy(id) end
    function B.tile_at(x,z) return base.source_tile_id(x+1,z+1) end
    function B.adjacent(id,d)
      local x,z=xy(id)
      if x and dx[d] then return B.tile_at(x+dx[d],z+dz[d]) end
    end
    function B.tile(id)
      local x,z=base.source_tile_xy(id)
      if not x then return nil end
      local src=base.source_road_tile(x,z)
      if not src or src.road_type~=0 or #src.unsupported_for_initial_bus_world>0 then return nil end
      if src.kind=="road" then
        return {kind="road",roadtype=0,road_bits=src.road_bits,owner=src.road_owner,disallowed=src.disallowed}
      elseif src.kind=="depot" then
        return {kind="depot",roadtype=0,dir=src.direction,owner=src.depot_owner}
      elseif stops[id] then
        return {kind=src.kind,roadtype=0,dir=src.direction or (src.axis==0 and F.NE or F.SE),
          owner=src.station_owner,station=src.station_id,stop_type="bus"}
      end
    end
    function B.center_z(id)
      local x,z=base.source_tile_xy(id)
      local slope,alt=Slope.classify(world.tile_corners(x,z))
      local src=base.source_road_tile(x,z)
      local raise=0
      if src and src.road_bits then slope,raise=Slope.foundation(slope,RoadSlope.foundation(slope,src.road_bits)) end
      return 8*(alt+raise)+Slope.pixel(8,8,slope)
    end
    function B.station_area(id,facility)
      if facility=="bus" then
        for tile,stop in pairs(stops) do
          if stop.station==id then return {tile=tile,w=1,h=1},tile end
        end
      end
    end
    function B.stop_continues()
      return false -- accepted scope is one tile per station
    end
    function B.stop_entry()
      return 0,16 -- the unique saved bus is on an ordinary road tile
    end
    function B.bay_free(tile,bay)
      return floor(assert(stops[tile]).status/(2^bay))%2==1
    end
    return B
  end

  function M.prepare(input,third_station,reserve_id)
    assert(type(input)=="table" and input.schema=="luanttd-openttd-bus-checkpoint/1"
      and input.status=="paused-validation-only" and input.can_resume_in_luanti==false,"not a paused bus checkpoint")
    local raw=input.bus_state
    assert(raw.schema=="luanttd-openttd-bus-state/1" and raw.can_resume_in_luanti==false
      and raw.source.sha256==input.map.source.sha256 and raw.source.save_version==334
      and input.map.source.save_version==334,"stock map and bus provenance disagree")
    local base=Sparse.prepare(input.map)
    assert(base.source_width==256 and base.source_depth==256,"unsupported stock fixture dimensions")
    local world=base.new_world()
    local function tile(id,why)
      must(id,0,65535,why.." tile ID")
      local x,z=base.source_tile_xy(id)
      assert(x and world.tile(x,z)~=7,"void or invalid stock "..why.." tile")
      return {source_id=id,logical_id=base.logical_tile_id(x,z),x=x,z=z}
    end

    local vset=input.settings
    assert(vset["game_creation.landscape"]==0 and vset["economy.timekeeping_units"]==0
      and vset["economy.minutes_per_calendar_year"]==12 and vset["economy.inflation"]==0
      and vset["linkgraph.distribution_pax"]==0 and vset["pf.pathfinder_for_roadvehs"]==2,
      "unsupported stock checkpoint settings")
    local side=must(vset["vehicle.road_side"],0,1,"driving side")
    must(vset["vehicle.roadveh_acceleration_model"],0,1,"road acceleration model")
    local opts={disable_node_optimization=must(vset["pf.yapf.disable_node_optimization"],0,1,"YAPF node optimization flag")==1}
    opts.max_search_nodes=must(vset["pf.yapf.max_search_nodes"],1,100000,"YAPF search limit")
    for _,k in ipairs({"road_slope_penalty","road_curve_penalty","road_crossing_penalty","road_stop_penalty",
                       "road_stop_occupied_penalty","road_stop_bay_occupied_penalty"}) do
      opts[k]=must(vset["pf.yapf."..k],0,65535,"pathfinder setting "..k)
    end

    local clk=raw.game_clock
    assert(clk.pause_mode==1,"stock source is not manually paused")
    decimal(clk.tick_counter,"18446744073709551615","tick count")
    for _,k in ipairs({"date","economy_date"}) do must(clk[k],0,2147483647,k) end
    for _,k in ipairs({"date_fract","economy_date_fract","calendar_sub_date_fract"}) do must(clk[k],0,73,k) end
    for _,k in ipairs({"random_state[0]","random_state[1]","next_disaster_start","competitors_interval",
                       "competitors_interval_elapsed"}) do must(clk[k],0,4294967295,k) end
    for _,k in ipairs({"company_tick_counter","trees_tick_counter"}) do must(clk[k],0,255,k) end
    must(clk.competitors_interval_fired,0,1,"competitor firing flag")
    must(clk.cur_tileloop_tile,0,65535,"tile loop cursor")

    local companies,nc=indexed(raw.company_balances,14,"company")
    assert(nc==1,"expected one company")
    local company_id,finance=next(companies)
    money(finance.money,"cash")
    decimal(finance.loan,"9223372036854775807","loan")
    money(finance.max_loan,"maximum loan")
    must(finance.money_fraction,0,255,"cash fraction")
    assert(type(finance.is_ai)=="boolean","invalid stock company ownership flag")

    local in_towns=indexed(raw.town_anchors,65534,"town")
    local towns={}
    for id,v in pairs(in_towns) do towns[id]={id=id,tile=tile(v.tile,"town")} end
    local raw_stations,ns=indexed(raw.stations,63999,"station")
    local stations,stops,stop_ids={},{},{}
    assert(ns==(third_station~=nil and 3 or 2),"expected one pair of bus stations in the selected scope")
    for id,rec in pairs(raw_stations) do
      assert(rec.owner==company_id and towns[rec.town_id],"invalid stock station owner or town")
      assert(array(rec.road_stops,1,"station stops")==1,"expected one bus tile per station")
      local pos=tile(rec.tile,"station")
      local desc=base.source_road_tile(pos.x,pos.z)
      local s=rec.road_stops[1]
      local sid=must(s.road_stop_id,0,63999,"road stop ID")
      assert(not stops[s.tile] and not stop_ids[sid] and s.tile==rec.tile and s.type=="bus"
        and desc and (desc.kind=="bay_stop" or desc.kind=="drive_stop") and desc.road_type==0
        and desc.station_id==id and desc.station_owner==rec.owner and desc.stop_type=="bus"
        and #desc.unsupported_for_initial_bus_world==0,"invalid stock station/stop link")
      local status=must(s.status,0,255,"road stop status")
      if desc.kind=="bay_stop" then assert(status==3,"occupied stock bay in isolated checkpoint")
      else assert(status==67,"unsupported stock through-stop occupancy") end
      local entry={id=sid,status=status,station=id,tile=pos,kind=desc.kind,source=desc}
      stations[id]={id=id,owner=rec.owner,town=rec.town_id,tile=pos,stop=entry}
      stops[s.tile],stop_ids[sid]=entry,true
    end

    local raw_depots,nd=indexed(raw.depots,65534,"depot")
    assert(nd==1,"expected one stock road depot")
    local depot_id,depot=next(raw_depots)
    local depot_pos=tile(depot.tile,"depot")
    local depot_map=base.source_road_tile(depot_pos.x,depot_pos.z)
    assert(depot.owner==company_id and towns[depot.town_id] and depot_map and depot_map.kind=="depot"
      and depot_map.depot_id==depot_id and depot_map.depot_owner==depot.owner
      and #depot_map.unsupported_for_initial_bus_world==0,"invalid stock depot link")

    local roster,nv=indexed(raw.road_vehicles,1048575,"vehicle")
    assert(nv==1,"expected one in-flight stock bus")
    local vid,b=next(roster)
    assert(b.owner==company_id and b.engine_type==116 and b.cargo_type==0 and b.cargo_cap==31
      and b.vehstatus==8,"unsupported stock vehicle class or status")
    must(b.cur_speed,1,112,"stock MPS Regal speed")
    must(b.subspeed,0,255,"vehicle sub-speed")
    must(b.progress,0,255,"vehicle progress")
    must(b.cargo_age_counter,1,185,"vehicle cargo age counter")
    money(b.profit_this_year,"vehicle profit")
    local timers=b.vehicle_timers
    for _,k in ipairs({"tick_counter","breakdown_ctr","breakdown_delay","breakdowns_since_last_service","breakdown_chance"}) do
      must(timers[k],0,255,"vehicle timer "..k)
    end
    must(timers.load_unload_ticks,0,65535,"vehicle load-unload clock")
    must(timers.running_ticks,0,4294967295,"vehicle running ticks")
    must(timers.last_loading_tick,0,4294967295,"vehicle last load tick")
    assert(timers.breakdown_ctr==0 and timers.breakdown_delay==0,"unsupported in-progress stock breakdown")
    local origin=tile(b.tile,"vehicle")
    must(b.x_pos,0,4095,"vehicle x pixel")
    must(b.y_pos,0,4095,"vehicle y pixel")
    must(b.z_pos,0,2040,"vehicle z pixel")
    assert(floor(b.x_pos/16)+1==origin.x and floor(b.y_pos/16)+1==origin.z,"vehicle pixel/tile mismatch")
    must(b.direction,0,7,"vehicle direction")
    local m=b.motion
    must(m.state,0,13,"vehicle trackdir")
    must(m.frame,0,255,"vehicle cursor frame")
    assert(m.overtaking==0 and m.overtaking_ctr==0 and m.blocked_ctr==0 and m.crashed_ctr==0
      and m.reverse_ctr==0,"unsupported blocked/overtaking/reversing vehicle state")
    must(m.gv_flags,0,65535,"vehicle ground flags")
    local kind,sx,sz=Motion.sample(m.state,side,m.frame)
    assert(kind=="position" and sx==b.x_pos%16 and sz==b.y_pos%16,"stock road frame/pixel mismatch")
    local road=base.source_road_tile(origin.x,origin.z)
    local slope,alt=Slope.classify(world.tile_corners(origin.x,origin.z))
    assert(road and road.kind=="road" and road.road_type==0 and #road.unsupported_for_initial_bus_world==0
      and slope==0 and b.z_pos==8*alt,"unsupported current road geometry or height")
    local path_count=array(m["path.td"],8,"stock choice cache")
    assert(path_count==array(m["path.tile"],8,"stock choice-cache locations"),"vehicle choice-cache arrays disagree")
    for i=1,path_count do
      assert(F.exit_direction(m["path.td"][i]),"invalid cached stock trackdir")
      tile(m["path.tile"][i],"cached road choice")
    end

    local no=array(b.orders,32,"vehicle orders")
    assert(no==2,"expected exactly two explicit station orders")
    local orderlist=must(b.order_list_id,0,1048575,"order list ID")
    local ids,orders={},{}
    for i,o in ipairs(b.orders) do
      local id=must(o.order_id,0,1048575,"order ID")
      assert(not ids[id] and o.type==97 and o.flags==0 and o.refit_cargo==254
        and stations[o.dest],"unsupported stock non-stop station order")
      ids[id]=true
      local next_id=b.orders[i+1] and b.orders[i+1].order_id
      assert(o.next==(next_id and next_id+1 or 0),"invalid stock encoded order link")
      must(o.max_speed,1,65535,"timetable speed")
      must(o.travel_time,0,65535,"timetable travel time")
      must(o.wait_time,0,65535,"timetable wait time")
      orders[i]={id=id,next_id=next_id,station=o.dest,raw=clone(o)}
    end
    local cursor=must(b.cur_real_order_index,0,no-1,"real order index")
    local active=orders[cursor+1]
    assert(active.station~=orders[2-cursor].station and b.cur_implicit_order_index==cursor
      and b["current_order.type"]==active.raw.type and b["current_order.flags"]==active.raw.flags
      and b["current_order.dest"]==active.station and b.dest_tile==stations[active.station].tile.source_id
      and b.last_loading_station==orders[2-cursor].station,"active stock destination or loading station disagreement")

    for _,k in ipairs({"max_speed","refit_cargo","travel_time","wait_time"}) do
      assert(b.active_timetable[k]==active.raw[k],"current timetable differs from its supported explicit order")
    end

    local reserve=raw.depot_reserve
    assert((reserve~=nil)==(reserve_id~=nil),"wrong reserve scope for the paused bus")
    if reserve then
      assert(third_station~=nil and reserve_id==reserve.id and reserve_id~=vid
        and reserve.owner==company_id and reserve.depot_id==depot_id and reserve.depot_tile==depot.tile
        and reserve.order_list_id~=orderlist and not ids[reserve.order_id]
        and reserve.order_station==orders[2-cursor].station and #reserve.raw_sha256==64
        and reserve.raw_sha256:match("^[0-9a-f]+$"),"unsupported depot reserve identity")
      local r=reserve.raw
      local road=r.vehicle.roadveh[1]
      local v=road.common[1]
      assert(r.id==reserve.id and r.order_list_id==reserve.order_list_id and r.order_id==reserve.order_id
        and v.orders==reserve.order_list_id+1 and r.order_list.first==reserve.order_id+1
        and r.order.dest==reserve.order_station and r.order.type==97 and r.order.flags==0 and r.order.next==0
        and v.tile==depot.tile and v.owner==company_id and v.engine_type==116 and v.vehstatus==11
        and v.cur_speed==0 and v.subspeed==0 and v.progress==0 and v.running_ticks==0
        and v.x_pos==reserve.x16 and v.y_pos==reserve.z16 and v.z_pos==reserve.y8 and v.direction==reserve.heading
        and #v["cargo.packets"]==0 and v["current_order.type"]==0 and v.next_shared==0
        and road.state==254 and road.frame==0 and road.gv_flags==4
        and #road["path.tile"]==0 and #road["path.td"]==0,"unsupported parked reserve state")
      assert(v.x_pos==(depot_pos.x-1)*16+8 and v.y_pos==(depot_pos.z-1)*16+8,
        "reserve is not at the depot's stock pixel center")
    end

    if third_station~=nil then
      local alternate=assert(stations[must(third_station,0,63999,"unused third station")])
      assert(alternate.stop.kind=="bay_stop" and alternate.id~=active.station
        and alternate.id~=orders[2-cursor].station,"third station is not a distinct existing bay")
    end

    local packet_ids,total,aged={},0,false
    assert(array(b.packets,31,"onboard packets")>=1,"expected loaded passengers")
    local packets={}
    for _,p in ipairs(b.packets) do
      local id=must(p.packet_id,0,1048575,"cargo packet ID")
      local station=stations[p.source]
      assert(not packet_ids[id] and station and p.source==b.last_loading_station
        and p.source_xy==station.tile.source_id and p.source_type==1 and p.source_id==station.town,
        "invalid stock onboard passenger origin")
      packet_ids[id]=true
      total=total+must(p.count,1,31,"packet count")
      aged=must(p.periods_in_transit,0,65535,"packet age")>0 or aged
      money(p.feeder_share,"packet feeder share")
      must(p.loaded_at_xy,0,4294967295,"legacy packet position field")
      for _,k in ipairs({"travelled.x","travelled.y"}) do must(p[k],-32768,32767,k) end
      packets[#packets+1]=clone(p)
    end
    assert(aged and b.onboard==total and total<=31,"inconsistent or non-aged passenger load")
    local actions=b["cargo.action_counts"]
    assert(array(actions,4,"cargo action counters")==4 and actions[1]==0 and actions[2]==0
      and actions[3]==total and actions[4]==0,"vehicle cargo not in a safe in-flight KEEP state")

    local B=route_board(base,world,stops)
    local station=stations[active.station]
    local v={tile=b.tile,owner=b.owner,bus=true,tram=false,articulated=false,
      display_max_speed=56,order_max_speed=active.raw.max_speed}
    assert(F.has_trackdir(F.status(B.tile(b.tile),false),m.state),"current trackdir not on source pavement")
    local target=Cost.destination(B,v,{kind="station",station=active.station})
    local found,chosen=Yapf.find(B,v,b.tile,2^m.state,target,opts)
    assert(found,"stock route is not reachable on the verified sparse board")
    local trace=Yapf.trace(B,v,target,chosen,opts)
    assert(#trace>1 and trace[1].tile==b.tile and trace[#trace].tile==station.tile.source_id,
      "wrong stock YAPF route endpoints")
    for _,step in ipairs(trace) do
      local xy=tile(step.tile,"route")
      local mask=Slope.classify(world.tile_corners(xy.x,xy.z))
      assert(mask==0,"graded route restoration not in this checkpoint's accepted scope")
      step.position=xy
    end
    local view={schema="luanttd-paused-stock-bus/1",paused=true,can_resume_in_luanti=false,
      source=clone(raw.source),base_id=base.base_id,settings=clone(vset),clock=clone(clk),towns=towns,
      companies={[company_id]=clone(finance)},stations=stations,reserve=clone(reserve),
      depots={[depot_id]={id=depot_id,tile=depot_pos,town=depot.town_id,owner=depot.owner}},
      vehicle={id=vid,tile=origin,dest=station.tile,engine=b.engine_type,owner=b.owner,
        cursor={state=m.state,frame=m.frame,direction=b.direction,side=side,progress=b.progress,speed=b.cur_speed,
          subspeed=b.subspeed,age_countdown=b.cargo_age_counter,
          x16=b.x_pos,z16=b.y_pos,y8=b.z_pos,native={x=1.5+b.x_pos/8,y=.5+b.z_pos/8,z=1.5+b.y_pos/8}},
        order_list_id=orderlist,order_index=cursor,current_order_id=active.id,
        orders=orders,onboard=total,packets=packets,route_trace=trace,timers=clone(timers),raw=clone(b)}}
    local function next_station(id)
      assert(third_station~=nil and id==third_station,"route proof is limited to the selected third bay")
      local depart,dest=station.tile.source_id,stations[id].tile.source_id
      local from=B.tile(depart)
      assert(from.kind=="bay_stop","next station proof requires the direction of the current bay")
      local td=F.direction_trackdir(from.dir)
      local bus={tile=depart,owner=b.owner,bus=true,tram=false,articulated=false,
        display_max_speed=56,order_max_speed=orders[2-cursor].raw.max_speed}
      local target=Cost.destination(B,bus,{kind="station",station=id})
      local found,node=Yapf.find(B,bus,depart,2^td,target,opts)
      assert(found,"the third bay has no stock YAPF route for this bus")
      local output={}
      for _,step in ipairs(Yapf.trace(B,bus,target,node,opts)) do output[#output+1]=step.tile end
      assert(output[1]==depart and output[#output]==dest and #output>1,"wrong stock third route endpoints")
      return output
    end
    return {
      paused=true,can_resume_in_luanti=false,
      checkpoint=function() return clone(view) end,next_station=third_station~=nil and next_station or nil,
      board={tile=world.tile,corner=world.corner,tile_corners=world.tile_corners,stats=world.stats,
        source_id=base.source_tile_id,source_xy=base.source_tile_xy,logical_id=base.logical_tile_id},
    }
  end
  return M
end
