-- Read-only coaching over real campaign state. Opening a lesson never
-- builds infrastructure, buys a vehicle, pays a fare, or alters orders.
return function(api)
  local S,Sim=api.s,api.Sim
  local Track=dofile(core.get_modpath("luanttd_core").."/openttd/rail_track.lua")
  local T={form="luanttd_core:business_tutorials"}
  local sessions={}
  local courses={
    road={name="Road business",steps={
      {"Build a bus corridor","roads","Choose two neighborhoods with houses. Use AutoRoad to lay a continuous, two-way road between them. Roadworks → Bus stop places a stop on straight road; put one by each neighborhood. Use Inspect to make sure both can accept passengers."},
      {"Build a road depot","roads","Use Road depot on a flat tile beside your road. The garage door must connect to the route. A straight, two-way road with room to turn around is easiest for a first service."},
      {"Buy a bus",nil,"Right-click your road depot and buy an available passenger bus. In a 1950 start, try the MPS Regal. Buying opens the bus card; you can reopen it from Inventory → Fleet."},
      {"Add stops and start service",nil,"From the bus card choose Add stops. Aim at each of your bus stops and use Pick stop, then select and use Done. Back on the bus card, press Start service. If the route is rejected, check both stops have a continuous two-way road and a route back to the depot."},
      {"Earn a passenger fare",nil,"Unpause and let time run. The bus earns when it drops passengers at a stop that accepts them, not when it boards them. Inspect the stops for queues and open Fleet to see the bus's operating profit."},
    }},
    rail={name="Train business",steps={
      {"Lay a straight passenger line","railworks","Choose two places near houses on one level east–west corridor. Drag AutoRail to lay continuous track. Add two Rail stations of 2–3 tiles each. Use plain track between the two platforms and the depot. Start with one train and no signals; it reverses at each stop."},
      {"Connect the rail depot","railworks","For the example, put the depot at the WEST end on a clear tile with its door facing EAST onto the line. Rotate railway fitting is under Rail Tools & Operations → Rail Engineering. A depot is a dead end, not a through platform."},
      {"Signals are optional on a simple line","railsignals","One train can serve both stations without signals. If you add a signal to the example, read the line west to east:\n[Depot →] - plain track - [← PBS] - [Near] ===== [Far end]\nChoose the normal Path signal, not One-way or Block. Click the plain track WEST of Near, then select East → West in the direction picker. It faces the train heading back toward the depot, not the outbound train. One-way would block the outbound trip."},
      {"Buy a passenger train",nil,"Inspect the depot and buy an available locomotive with a Passenger Carriage, such as Kirby Paul Tank in 1950. A freight wagon will not take passengers. Keep the consist short enough to fit both platforms."},
      {"Order Far first, then Near",nil,"Inspect the depot and choose the train's two platform orders. Pick Far first and Near second. Select Dispatch on the route hotbar. If the route is rejected, check for gaps, a depot facing away from the line or a one-way signal blocking the return. Start without signals on your first line."},
      {"Earn your first rail fare",nil,"Unpause. The train may reach Far empty, then board for the return to Near. Both stations need nearby houses so passengers can be delivered. Inspect either platform to see waiting passengers and shuttle fares."},
    }},
    boat={name="Boat business",steps={
      {"Build two passenger docks","harbor","Find two neighborhoods near the same connected waterway. Build Dock on a straight shoreline slope facing two flat water tiles. Each dock needs nearby houses and clear water beside the pier for boarding. Do not build the pier on the open-water tile itself."},
      {"Build a ship depot","harbor","Place a Ship depot on two adjacent open-water tiles connected to both docks. Use Rotate ship depot if the footprint is wrong. Leave water around the entrance; the ferry must be able to depart and turn."},
      {"Buy a passenger ferry",nil,"Inspect your ship depot, open Passenger ferries and buy an available vessel. In a 1950 start, try the MPS Passenger Ferry. In 1980, you can buy the faster FFP. It stays in the depot until you give it orders."},
      {"Order the ferry","harbor_ops","Open Passenger ferries at the depot and choose its orders, then pick your two docks and select Dispatch. If navigation fails, check both water approaches connect and the vessel can travel both directions. A sloping river needs a lock."},
      {"Earn a passenger fare",nil,"Unpause. Wait for the ferry to board and deliver to the other dock. Inspect a dock for passenger acceptance, waiting people and total fares. A scenic pier with no house catchment can be connected but earn nothing."},
    }},
  }
  local keys={"road","rail","boat"}
  local function own_count(records,n,predicate)
    local count=0
    for _,r in pairs(records or {}) do
      if r.owner==n and (not predicate or predicate(r)) then count=count+1 end
    end
    return count
  end
  local function depots(n,rail)
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
  function T.progress(n,key)
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
  local function player(p)
    local n=p:get_player_name()
    local q=sessions[n]
    if not q then
      local meta=p.get_meta and p:get_meta()
      local key=meta and meta:get_string("luanttd_tutorial")
      q={key=courses[key] and key or nil}
      sessions[n]=q
    end
    return n,q
  end
  local function refresh(n,q,force)
    if not q.key then return end
    local now=core.get_us_time()
    if force or not q.updated or now-q.updated>=1400000 then
      q.step,q.fare,q.warning=T.progress(n,q.key)
      q.updated=now
    end
    return q.step,q.fare
  end
  function T.hint(p)
    local n,q=player(p)
    local step=refresh(n,q)
    if not step then return "" end
    local c=courses[q.key]
    return ("Tutorial: %s  ·  %s"):format(c.name,c.steps[step] and c.steps[step][1] or "First fare earned!")
  end
  function T.open(p)
    local n,q=player(p)
    q.open=true
    local esc=core.formspec_escape
    local b={"formspec_version[7]size[13.2,8.4]bgcolor[#152334;false]",
      "style_type[label;textcolor=#E5ECEA]style_type[button;bgimg=bl_button.png;bgimg_middle=6;textcolor=#E5ECEA]"}
    local function add(s) b[#b+1]=s end
    local function label(x,y,t) add(("label[%g,%g;%s]"):format(x,y,esc(t))) end
    local function btn(x,y,w,id,t) add(("button[%g,%g;%g,.62;%s;%s]"):format(x,y,w,id,esc(t))) end
    label(.42,.42,"LuanTTD / Start a transport business")
    for i,k in ipairs(keys) do
      if k==q.key then add("style[lesson_"..k..";textcolor=#FFE6A5]") end
      btn(.42+(i-1)*4.23,1,3.90,"lesson_"..k,courses[k].name)
    end
    local c=courses[q.key]
    if c then
      local step,fare=refresh(n,q,true)
      local shown=q.page or step
      local entry=c.steps[shown]
      label(.42,2.13,entry and ("Step %d of %d: %s"):format(shown,#c.steps,entry[1]) or "Business started: first fare earned")
      local text=entry and entry[3] or ("Your %s earned $%d in fares. Use Finance to compare revenue and running costs. Repeat the same pattern for other routes."):format(q.key=="boat" and "ferry" or q.key=="rail" and "train" or "bus",fare or 0)
      if shown==step and q.warning then text=text.."\n\n"..q.warning end
      add("textarea[.42,2.62;12.33,2.94;;;"..esc(text).."]")
      label(.42,5.72,c.steps[step] and "Current goal: "..c.steps[step][1] or "All milestones complete.")
      if shown>1 then btn(.42,6.22,2.62,"lesson_prev","Previous step") end
      btn(3.24,6.22,2.82,"lesson_current","Current goal")
      if shown<#c.steps then btn(6.26,6.22,2.42,"lesson_next","Next step") end
      if entry and entry[2] then btn(8.88,6.22,3.86,"lesson_tools","Open hotbar") end
      btn(.42,7.25,4.04,"lesson_stop","Stop coaching")
    else
      add("textarea[.42,2.17;12.33,3.45;;;Choose a lesson above. Build and operate the route yourself using the real campaign tools. The lesson moves to your next goal as you build, order and earn. You can review any step from Inventory → Tutorials.]")
    end
    btn(8.88,7.25,3.86,"lesson_world","Back to world")
    if q.notice then label(.42,7.02,q.notice) end
    core.show_formspec(n,T.form,table.concat(b))
    return true
  end
  function T.fields(p,f)
    local n,q=player(p)
    if not q.open then return true end
    local function close()
      q.open=false
      core.close_formspec(n,T.form)
      return true
    end
    if f.quit or f.lesson_world then return close() end
    local function choose(k)
      q.key,q.page,q.updated,q.notice=k,nil,nil,nil
      if p.get_meta then p:get_meta():set_string("luanttd_tutorial",k or "") end
      return T.open(p)
    end
    for _,k in ipairs(keys) do if f["lesson_"..k] then return choose(k) end end
    if f.lesson_stop then return choose(nil) end
    local c=courses[q.key]
    if not c then return T.open(p) end
    local step=refresh(n,q,true)
    local shown=q.page or step
    q.notice=nil
    if f.lesson_prev then q.page=math.max(1,shown-1)
    elseif f.lesson_next then q.page=math.min(#c.steps,shown+1)
    elseif f.lesson_current then q.page=nil
    elseif f.lesson_tools then
      local e=c.steps[shown]
      if e and e[2] then
        local ok,why=api.world.go_menu(p,e[2])
        if ok then return close() end
        q.notice=why
      end
    end
    return T.open(p)
  end
  function T.leave(n) sessions[n]=nil end
  return T
end
