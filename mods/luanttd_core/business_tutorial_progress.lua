-- Stock tutorial milestones without a player, map handle, or UI.
return function(api,Track,depot_lookup)
  local S,Sim=api.s,api.Sim
  local function own_count(records,n,predicate)
    local count=0
    for _,r in pairs(records or {}) do
      if r.owner==n and (not predicate or predicate(r)) then count=count+1 end
    end
    return count
  end
  local function depots(n,rail)
    if depot_lookup then return depot_lookup(n,rail) end
    local out={}
    for id,t in ipairs(S.tiles or {}) do
      if t.owner==n and (rail and t.rail_depot_dir~=nil or not rail and t.build=="road_depot") then
        out[#out+1]={id=id,dir=t.rail_depot_dir}
      end
    end
    return out
  end
  local function rail_signal(n,dep)
    local d=S.stock_rail_dispatch
    if not d or d.owner~=n then return false end
    local delta=({[0]={-1,0},[1]={0,1},[2]={1,0},[3]={0,-1}})[dep.dir]
    if not delta then return false end
    local x,z=Sim.xy(dep.id)
    local mask=Track.signal_along(Track.diagonal_trackdir(Track.reverse_side(dep.dir)))
    local saw_return,problem=false,nil
    local heading=({[0]="west",[1]="south",[2]="east",[3]="north"})[Track.reverse_side(dep.dir)]
    for i=1,math.max(Sim.W,Sim.H) do
      local id=Sim.id(x+i*delta[1],z+i*delta[2])
      local t=id and S.tiles[id]
      if not t or t.owner~=n or t.rail_tracks~=2^(dep.dir%2) or t.rail_depot_dir~=nil then return false end
      if t.rail_station_id then return saw_return,problem end
      local records=d.signals and d.signals.records
      local rec=records and records[id]
      -- Normal PBS type 4, with a head for the direction toward the depot.
      if rec and rec.upper_signal_type==4 and math.floor((rec.present_signals or 0)/mask)%2==1 then
        saw_return=true
      elseif rec then
        problem=rec.upper_signal_type~=4
          and "There is a different signal type between the station and depot. Use Remove rail signal, then place a normal Path signal."
          or ("The signal between the station and depot faces the wrong way. Remove it and place a normal Path signal facing "..heading..".")
      end
    end
    return false
  end
  local function progress(n,key)
    if key=="road" then
      local bought,started=false,false
      for _,v in pairs(S.fleet or {}) do
        local e=Sim.vehicles[v.engine]
        if v.owner==n and v.cargo=="passenger" and e and e.mode=="road" then
          if (v.delivered or 0)>0 and (v.revenue or 0)>0 then return 6,v.revenue end
          bought=true;started=started or v.running or v.route~=nil
        end
      end
      if started then return 5 end
      if own_count(S.stations,n,function(r) return r.mode=="road" and r.stop_type~="truck" end)<2 then return 1 end
      if #depots(n,false)==0 then return 2 end
      return bought and 4 or 3
    elseif key=="rail" then
      local bought,started=false,false
      for _,u in ipairs(api.rail_owned and api.rail_owned.list(S,n) or {}) do
        local paid=Sim.rail_paid_status and Sim.rail_paid_status(S,u.id)
        if paid and paid.owner==n then
          if paid.delivered>0 and paid.fare>0 then return 7,paid.fare end
          started=true
        end
        for _,stock in ipairs(u.stock_ids or {}) do if stock==27 then bought=true end end
        if u.stock_ids and u.stock_ids[1]==11 then bought=true end -- Manley Morel carries passengers without a coach
      end
      if started then return 6 end
      if own_count(S.stock_rail_stations,n)<2 then return 1 end
      local dep=depots(n,true)
      if #dep==0 then return 2 end
      local sign,problem=false,nil
      for _,d in ipairs(dep) do
        local valid,reason=rail_signal(n,d)
        if valid then sign=true;break end
        problem=problem or reason
      end
      if not sign and problem then return 3,nil,problem end
      return bought and 5 or 4
    else
      local paid=Sim.ferry_paid_status and Sim.ferry_paid_status(S)
      if paid and paid.owner==n then
        if paid.delivered>0 and paid.fare>0 then return 6,paid.fare end
        return 5
      end
      if own_count(S.stock_ship_stations,n)<2 then return 1 end
      if own_count(S.stock_ship_depots,n)==0 then return 2 end
      return S.stock_owned_ferry and S.stock_owned_ferry.owner==n and 4 or 3
    end
  end
  return progress
end
