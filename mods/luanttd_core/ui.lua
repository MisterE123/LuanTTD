return function(api)
local Sim,S,R=api.Sim,api.s,api.render
local U={}
local moddir=(core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Freight=dofile(moddir.."/rail_freight_kinds.lua")
local worker_action
local worker_jump_fields
local worker_jump_form="luanttd_core:worker_jump"
local tram_offer_form="luanttd_core:tram_service_offer"
local TramMarket=dofile(moddir.."/tram_market.lua")
local DepotFacing=dofile(moddir.."/depot_orientation.lua").facing
local esc=core.formspec_escape
local session,hud={},{}
local Workbenches=api.road_first and dofile(core.get_modpath("luanttd_core").."/workbench_index.lua")(api)
local Tutorials=api.road_first and dofile(core.get_modpath("luanttd_core").."/business_tutorials.lua")(api)
local JumpMap=api.road_first and dofile(core.get_modpath("luanttd_core").."/jump_map.lua")(api)

local function view(name)
  if not session[name] then
    session[name]={tab="fleet",x=6,z=4,chosen=Sim.id(9,9),tool="inspect",status=api.road_first and "" or "Build a route, buy a vehicle, and deliver your first cargo.",
      engine=1,cargo=1,buy_st=1,add_st=1,action=1,order=1,selected_vehicle=nil}
  end
  return session[name]
end
local function number(n)
  local i=math.floor(math.abs(n))
  local s=tostring(i):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
  return (n<0 and "-" or "")..s
end
local function dollars(n) return n<0 and "-$"..number(-n) or "$"..number(n) end
local function formatted_date(y,m,d)
  return ("%02d %s %d"):format(d,({"JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"})[m],y)
end
local function date() return formatted_date(Sim.date(S)) end
local company_projection
function U.use_worker_projection(view) company_projection=view end
function U.install_worker_controls(client)
  local mod=core.get_modpath("luanttd_core")
  local Stop=dofile(mod.."/campaign_worker_truck_stop_ui.lua")
  api.worker_truck_stop=Stop(core,client,number)
  api.worker_rail_mail_station=Stop(core,client,number,true)
  api.worker_layer_client=client
  api.worker_bridge_client=client
  api.worker_signal_client=client
  api.worker_rail_assembly=client
  api.worker_tutorial_client=client
  api.worker_town_founding=dofile(mod.."/town_founding_ui.lua")(core,client,dollars,
    function(p)
      local id=api.world.target(p)
      if id then local x,z=Sim.xy(id);return id,x-1,z-1 end
    end,function(p) return api.worker_finance.show(p) end)
  api.worker_finance=dofile(mod.."/campaign_worker_finance_ui.lua")(core,client,formatted_date,dollars,
    function(p,id) U.teleport_tile(p,id) end,api.worker_town_founding.open)
  api.worker_news=dofile(mod.."/campaign_news_ui.lua")(core,mod,client,formatted_date,
    api.stock_audio and api.stock_audio.effect)
  api.worker_build=api.worker_build or dofile(mod.."/campaign_build_proxy.lua")(client)
  api.worker_depot=dofile(mod.."/campaign_worker_depot_ui.lua")(core,client,api.worker_build,dollars,function(p,id)
    return api.owned_rail_ui and api.owned_rail_ui.assemble(p,id)
  end)
  if api.vehicle_ui then
    api.vehicle_ui.install_worker(client)
    local proxy=dofile(mod.."/campaign_authority_order_proxy.lua")
    for _,mode in ipairs({"road","rail","ship","air","tram"}) do api.vehicle_ui.orders[mode]=proxy(client,mode) end
    api.worker_fleet=dofile(mod.."/campaign_worker_fleet_ui.lua")(core,client,api.vehicle_ui)
  end
end
local mode_label={rail="RAIL",road="ROAD",water="WATER",air="AIR"}
local orders={"normal","full","transfer","unload"}
local order_labels={"Load / deliver","Full load","Transfer only","Unload only"}
local tabs={{"map","Jump map"},{"fleet","Fleet & orders"},{"ledger","Finance"},{"directory","Directory"},{"help","Help"}}
local function sorted(t,owner,predicate)
  local out={}
  for id,v in pairs(t) do if (not owner or v.owner==owner) and (not predicate or predicate(v)) then out[#out+1]=id end end
  table.sort(out);return out
end
local function limit(a,min,max) return math.max(min,math.min(max,a)) end
local function index_of(a,n)
  for i,v in ipairs(a) do if v==n then return i end end
end
local function title_case(s) return s:sub(1,1):upper()..s:sub(2) end

local function jump_nav(V,f)
  if f.map_zoom then
    V.map_zoom,V.map_inspect,V.map_center=not V.map_zoom,nil,nil
    return true
  elseif f.map_inspect and not V.map_zoom then
    V.map_inspect=not V.map_inspect
    return true
  end
  for _,dir in ipairs({"map_west","map_east","map_north","map_south"}) do
    if f[dir] and JumpMap.pan(V,dir) then return true end
  end
  local id=JumpMap.pick(V,f)
  if id and V.map_inspect and not V.map_zoom then
    V.map_zoom,V.map_inspect,V.map_center=true,nil,id
    return true
  end
end
local function form()
  local b={"formspec_version[7]size[20.7,14.25]bgcolor[#101C2B;true]"}
  local function push(s) b[#b+1]=s end
  local function rect(x,y,w,h,color)
    push(("box[%g,%g;%g,%g;%s]"):format(x,y,w,h,color))
  end
  local function label(x,y,s,color)
    if color then s=core.colorize(color,s) end
    push(("label[%g,%g;%s]"):format(x,y,esc(s)))
  end
  local function button(x,y,w,h,id,s,kind)
    if kind=="active" then push("style["..id..";bgimg=bl_button_active.png;textcolor=#FCF4D6]")
    elseif kind=="primary" then push("style["..id..";bgimg=bl_button_primary.png;textcolor=#101C2B]") end
    push(("button[%g,%g;%g,%g;%s;%s]"):format(x,y,w,h,id,esc(s)))
  end
  local function words(x,y,w,h,s,color)
    push(("textarea[%g,%g;%g,%g;;; %s]"):format(x,y,w,h,esc(color and core.colorize(color,s) or s)))
  end
  local function dropdown(x,y,w,h,id,a,i)
    local records={}
    for j,s in ipairs(a) do records[j]=esc(s) end
    if #records==0 then records[1]="(none)" end
    push(("dropdown[%g,%g;%g,%g;%s;%s;%d;true]"):format(x,y,w,h,id,table.concat(records,","),limit(i or 1,1,#records)))
  end
  local function list(x,y,w,h,id,a,i)
    local rows={}
    for j,s in ipairs(a) do rows[j]=esc(s) end
    push(("textlist[%g,%g;%g,%g;%s;%s;%d;false]"):format(x,y,w,h,id,table.concat(rows,","),i or 1))
  end
  push("style_type[button;font=bold;bgimg=bl_button.png;bgimg_middle=6;textcolor=#E5ECEA;border=false]style_type[button:hovered;bgimg=bl_button_hover.png]style_type[label;textcolor=#E6ECE6]style_type[image_button;border=false;sound=]")
  return b,push,rect,label,button,words,dropdown,list
end

function U.open(p)
  if api.authority_handoff then
    if view(p:get_player_name()).tab=="map" then return U.open_jump(p) end
    return U.open_company(p)
  end
  local n=p:get_player_name();local V=view(n);local c=Sim.company(S,n)
  local b,push,rect,label,button,words,drop,list=form()
  rect(0,0,20.7,1,"#172C3B")
  push("style_type[label;font_size=+4;font=bold]")
  label(0.45,0.49,"LuanTTD","#FFE6A5")
  push("style_type[label;font_size=;font=normal]")
  label(6.15,0.49,date().."    /    "..(S.speed==0 and "PAUSED" or S.speed.."×").."    /    Cash  "..dollars(c.cash),"#D8E5D8")
  label(15.25,0.49,"COMPANY  "..n,"#9ABCB5")
  local visible_tabs=api.road_first and {{"map","Jump map"},{"ledger","Finances"}} or tabs
  for i,t in ipairs(visible_tabs) do button(.42+(i-1)*2.55,1.14,2.42,.51,"tab_"..t[1],t[2],V.tab==t[1] and "active") end
  button(13.55,1.14,1.02,.51,"speed_0","Pause",S.speed==0 and "active")
  for i,speed in ipairs({1,2,4}) do button(14.6+(i-1)*.71,1.14,.68,.51,"speed_"..speed,speed.."×",S.speed==speed and "active") end
  button(16.85,1.14,1.58,.51,"refresh","Refresh")
  button(18.52,1.14,1.75,.51,"survey","3D Survey")
  rect(.30,13.54,20.1,.48,"#203A48")
  label(.56,13.78,V.status,"#EAF3D8")

  if V.tab=="map" and JumpMap then
    JumpMap.draw(V,p,{push=push,rect=rect,label=label,button=button})
  elseif V.tab=="map" then
    local cols,rows,step=20,15,.68
    rect(.32,1.88,14.12,11.45,"#20394A")
    label(.55,2.09,("REGION MAP   /   X %02d–%02d  Z %02d–%02d   /   N ↑"):format(V.x,V.x+cols-1,V.z,V.z+rows-1),"#AACCC2")
    local markers={}
    for _,id in ipairs(sorted(S.fleet)) do
      local veh=S.fleet[id]
      local tile=Sim.position(S,veh)
      if tile and (not markers[tile] or veh.owner==n) then markers[tile]=Sim.vehicles[veh.engine].mode end
    end
    local site_labels={}
    local cst=S.tiles[V.chosen] and S.stations[S.tiles[V.chosen].station]
    for rz=0,rows-1 do for cx=0,cols-1 do
      local id=Sim.id(V.x+cx,V.z+rz)
      local x,y=.55+cx*step,2.38+rz*step
      local cov=cst and Sim.distance(cst.tile,id)<=5
      local tex=R.texture(id,markers[id],V.chosen==id,V.anchor==id,cov)
      push(("image_button[%g,%g;%g,%g;%s;t_%d;;false;false;%s]"):format(x,y,step,step,tex,id,tex))
      local t=S.tiles[id]
      if t.site then
        local name=S.sites[t.site].name
        local lx=math.min(x+.48,12.0)
        site_labels[#site_labels+1]={x=lx,y=y+.10,name=name}
        push("tooltip[t_"..id..";"..esc(name).."]")
      end
    end end
    push("style_type[label;font_size=-4;font=bold]")
    for _,tag in ipairs(site_labels) do
      rect(tag.x,tag.y-.115,#tag.name*.105+.15,.24,"#1B2938E8")
      label(tag.x+.055,tag.y,tag.name,"#FFF1BE")
    end
    push("style_type[label;font_size=;font=normal]")
    button(.58,12.7,1.47,.42,"west","← West")
    button(2.19,12.7,1.47,.42,"east","East →")
    button(3.8,12.7,1.47,.42,"north","↑ North")
    button(5.41,12.7,1.47,.42,"south","↓ South")
    button(7.1,12.7,2.7,.42,"home","Port Alder")
    button(10.01,12.7,3.88,.42,"live",V.live and "Live map: on" or "Live map: off",V.live and "active")
    rect(14.65,1.88,5.73,11.45,"#182C3D")
    label(14.92,2.13,"WORLD NAVIGATION","#FFE1A0")
    words(14.92,2.61,5.1,2.15,"Click a tile to fly there. This map is for navigation only. Build and inspect directly in the world.","#ACCBC9")
    button(14.94,5.10,5.12,.55,"survey","Return to 3D world","primary")
    rect(14.91,8.15,5.15,.02,"#4C6674")
    local tx,tz=Sim.xy(V.chosen)
    label(14.94,8.44,("TILE %02d / %02d"):format(tx,tz),"#FFE1A0")
    local tile=S.tiles[V.chosen]
    local tx,tz=Sim.xy(V.chosen)
    label(14.94,8.44,("TILE %02d / %02d"):format(tx,tz),"#FFE1A0")
    local desc={title_case(tile.terrain).."  /  Elev. "..tile.h}
    local st=tile.station and S.stations[tile.station]
    local site=tile.site and S.sites[tile.site]
    if tile.owner then desc[#desc+1]="Owner: "..tile.owner end
    if tile.house then desc[#desc+1]="Town building" end
    if site then
      desc[#desc+1]=site.name.."  /  "..Sim.facilities[site.kind].name
      if site.population then
        desc[#desc+1]="Population: "..number(site.population)
        desc[#desc+1]="Town approval: "..(c.rating[site.id] or 48).."%"
      end
      for _,cid in ipairs(Sim.cargo_order) do
        local amount=site.stock[cid]
        if amount then desc[#desc+1]=Sim.cargo[cid].name.." waiting: "..amount end
      end
    end
    if st then
      desc[#desc+1]=st.name;desc[#desc+1]="Serves:"
      for _,sid in ipairs(st.served) do desc[#desc+1]="• "..S.sites[sid].name end
      for _,cid in ipairs(Sim.cargo_order) do
        local waiting=0
        for _,batch in ipairs(st.stock[cid] or {}) do waiting=waiting+batch.units end
        if waiting>0 then desc[#desc+1]=Sim.cargo[cid].name.." transferred: "..waiting end
      end
    elseif tile.build then desc[#desc+1]=Sim.tools[tile.build].name end
    for _,id in ipairs(sorted(S.fleet)) do
      local v=S.fleet[id]
      if Sim.position(S,v)==V.chosen then desc[#desc+1]=v.name..": "..v.status end
    end
    words(14.92,8.69,5.24,2.8,table.concat(desc,"\n"))
  elseif V.tab=="fleet" then
    rect(.37,1.93,8.79,11.38,"#182C3D")
    rect(9.39,1.93,10.94,11.38,"#182C3D")
    local fleet=sorted(S.fleet,n)
    if not index_of(fleet,V.selected_vehicle) then V.selected_vehicle=fleet[1];V.order=1 end
    V.fleet_ids=fleet
    label(.7,2.22,"YOUR FLEET  /  "..#fleet.." VEHICLES","#FFE1A0")
    local names={}
    for i,id in ipairs(fleet) do local v=S.fleet[id];names[i]=v.name.." • "..v.status end
    if #names==0 then names[1]="No vehicles yet. Buy one below." end
    list(.7,2.63,8.08,2.9,"fleet_list",names,index_of(fleet,V.selected_vehicle))
    label(.7,5.95,"PROCUREMENT","#FFE1A0")
    label(.7,6.35,"MODEL / PRICE / CAPACITY")
    local available={}
    for _,id in ipairs(Sim.vehicle_order) do if Sim.vehicle_available(S,id) then available[#available+1]=id end end
    V.engines=available;V.engine=limit(V.engine,1,#available)
    local eng=available[V.engine]
    local modelnames={}
    for i,id in ipairs(available) do
      local e=Sim.vehicle_offer(S,id)
      modelnames[i]=mode_label[e.mode].." • "..e.name.." • "..dollars(e.cost).." • "..e.capacity.." units"
    end
    drop(.7,6.59,8.08,.57,"buy_engine",modelnames,V.engine)
    local cargos,cn={},{}
    for _,k in ipairs(Sim.cargo_order) do if Sim.allowed(eng,k) then cargos[#cargos+1]=k;cn[#cn+1]=Sim.cargo[k].name end end
    V.cargos=cargos;V.cargo=limit(V.cargo,1,#cargos)
    label(.7,7.48,"REFIT / CARGO")
    drop(.7,7.72,8.08,.57,"buy_cargo",cn,V.cargo)
    local buy=sorted(S.stations,n,function(st)return st.mode==Sim.vehicles[eng].mode end)
    if V.pin_buy then V.buy_st=index_of(buy,V.pin_buy) or 1;V.pin_buy=nil end
    V.buy_ids=buy;V.buy_st=limit(V.buy_st,1,math.max(1,#buy))
    local bn={};for i,id in ipairs(buy) do bn[i]=S.stations[id].name end
    label(.7,8.6,"DELIVER TO TERMINAL")
    drop(.7,8.85,8.08,.57,"buy_station",bn,V.buy_st)
    button(.7,9.74,8.08,.58,"buy","Purchase vehicle",#buy>0 and "primary")
    words(.7,10.72,8.02,2.1,"Vehicles are delivered to a compatible terminal. Add two or more station orders, then dispatch. See Directory to match a cargo producer with a receiver.","#ACCBCA")
    local v=S.fleet[V.selected_vehicle]
    label(9.68,2.23,v and v.name or "VEHICLE OPERATIONS","#FFE1A0")
    if v then
      local e=Sim.vehicles[v.engine]
      label(9.69,2.69,mode_label[e.mode].."  /  "..Sim.cargo[v.cargo].name.."  /  "..v.status,"#CADFD7")
      label(9.69,3.08,v.units.." / "..Sim.vehicle_capacity(v).." aboard"..((v.stock_regal or v.stock_bus) and "" or "    •    Condition "..math.floor(v.condition).."%"))
      label(9.69,3.48,"Delivered "..number(v.delivered).."    •    Operating profit "..dollars(v.revenue-v.expense))
      local os={}
      for i,o in ipairs(v.orders) do
        os[i]=("%02d  %s  /  %s"):format(i,S.stations[o.station].name,order_labels[index_of(orders,o.action) or 1])
      end
      label(9.68,4.03,"CYCLIC ORDERS","#AECBC5")
      list(9.68,4.35,10.31,2.22,"order_list",#os>0 and os or {"No orders"},math.min(V.order,#os))
      button(9.68,6.83,2.36,.48,"order_up","↑ Move up")
      button(12.17,6.83,2.36,.48,"order_down","↓ Move down")
      button(14.7,6.83,2.54,.48,"order_remove","Remove order")
      button(17.37,6.83,2.62,.48,"locate","Locate vehicle")
      local add=sorted(S.stations,n,function(st)return st.mode==e.mode end)
      if V.pin_add then V.add_st=index_of(add,V.pin_add) or 1;V.pin_add=nil end
      V.add_ids=add;V.add_st=limit(V.add_st,1,math.max(1,#add))
      local an={};for i,id in ipairs(add) do an[i]=S.stations[id].name end
      label(9.68,7.62,"ADD STOP / ACTION")
      drop(9.68,7.92,6.2,.56,"add_station",an,V.add_st)
      drop(16.02,7.92,3.97,.56,"add_action",order_labels,V.action)
      button(9.68,8.72,10.31,.5,"order_add","Add terminal to orders")
      button(9.68,9.61,4.64,.62,"toggle",v.stop_requested and "Cancel scheduled stop" or v.running and "Stop at next terminal" or "Dispatch",not v.running and "primary")
      button(14.48,9.61,2.55,.62,"service","Service")
      button(17.15,9.61,2.84,.62,"sell","Sell vehicle")
      local ra,rn={},{}
      for _,cargo in ipairs(Sim.cargo_order) do if Sim.allowed(v.engine,cargo) then
        ra[#ra+1]=cargo;rn[#rn+1]=Sim.cargo[cargo].name
      end end
      V.refit_ids=ra
      drop(9.68,10.63,4.64,.54,"refit_cargo",rn,V.refit or index_of(ra,v.cargo) or 1)
      button(14.48,10.63,2.55,.53,"refit","Refit")
      button(17.15,10.63,2.84,.53,"empty","Empty cargo")
      words(9.65,11.47,10.28,1.35,"Transfer puts cargo into this terminal's warehouse without payment. Your other terminals within two tiles can pick it up.","#ACCBC9")
    else
      words(9.65,3.02,10.22,2.6,"Select a vehicle to write its timetable. The quickest start is the starter bus line in the right-click world menu, or build and connect two stations yourself.","#ACCBC9")
    end
  elseif V.tab=="ledger" then
    rect(.37,1.93,19.96,11.38,"#182C3D")
    label(.72,2.3,"COMPANY LEDGER  /  "..n,"#FFE1A0")
    for i,p in ipairs({{"CASH",dollars(c.cash)},{"BANK LOAN",dollars(c.loan)},{"LIFETIME REVENUE",dollars(c.revenue)},{"CARGO DELIVERED",number(c.units)}}) do
      local x=.72+(i-1)*4.84;rect(x,2.76,4.58,1.25,"#263E50")
      label(x+.22,3.05,p[1],"#AAD1C6");label(x+.22,3.62,p[2],"#FFF0BA")
    end
    button(.72,4.28,3.45,.57,"borrow","Borrow $10,000")
    button(4.32,4.28,3.45,.57,"repay","Repay $10,000")
    label(8.01,4.56,"Monthly interest: 0.4% of outstanding loan. Credit limit: $200,000.","#A6CBC4")
    label(.73,5.45,"REVENUE / EXPENSES / PROFIT / CASH","#FFE1A0")
    local lines={"Current month  •  "..dollars(c.month_rev).."  /  "..dollars(c.month_exp).."  /  "..dollars(c.month_rev-c.month_exp).."  /  "..dollars(c.cash)}
    for _,m in ipairs(c.history) do
      local year,month=Sim.date(S,math.max(0,m.day-1))
      lines[#lines+1]=("%04d-%02d  •  %s  /  %s  /  %s  /  %s"):format(year,month,dollars(m.revenue),dollars(m.expenses),dollars(m.revenue-m.expenses),dollars(m.cash))
    end
    list(.72,5.81,11.06,6.82,"ledger_list",lines)
    label(12.08,5.45,"DISPATCH WIRE","#FFE1A0")
    words(12.0,5.79,7.94,3.0,table.concat(S.news,"\n\n"),"#ACCBC9")
    label(12.08,9.10,"ROUTE SUBSIDIES  /  +50%","#FFE1A0")
    local offers={}
    for _,offer in ipairs(S.subsidies or {}) do
      if offer.until_day>=S.day then
        offers[#offers+1]=S.sites[offer.src].name.." → "..S.sites[offer.dst].name.." / "..Sim.cargo[offer.cargo].name.." / "..(offer.owner or "Open").." / "..(offer.until_day-S.day).." days"
      end
    end
    words(12.0,9.45,7.94,2.1,#offers>0 and table.concat(offers,"\n\n") or "No offers remain.","#ACCBC9")
    local score={}
    for name,cc in pairs(S.companies) do score[#score+1]={name=name,value=cc.cash-cc.loan} end
    table.sort(score,function(a,b)return a.value==b.value and a.name<b.name or a.value>b.value end)
    local lead=score[1]
    label(12.08,12.15,"Cash less debt leader: "..lead.name.." ("..dollars(lead.value)..")","#A6CBC4")
  elseif V.tab=="directory" then
    rect(.37,1.93,19.96,11.38,"#182C3D")
    label(.72,2.29,"REGION DIRECTORY / SELECT A SITE TO LOCATE IT","#FFE1A0")
    local a={}
    for i,p in ipairs(S.sites) do
      local x,z=Sim.xy(p.tile)
      local f=Sim.facilities[p.kind]
      local make,take={},{}
      for _,k in ipairs(Sim.cargo_order) do
        if f.produces[k] or f.output==k then make[#make+1]=Sim.cargo[k].name end
        if f.takes[k] then take[#take+1]=Sim.cargo[k].name end
      end
      a[i]=("%02d,%02d  •  %s  [%s]  •  Ships: %s  •  Receives: %s"):format(x,z,p.name,f.name,#make>0 and table.concat(make," / ") or "—",#take>0 and table.concat(take," / ") or "—")
    end
    list(.72,2.72,18.54,6.27,"sites",a,V.site or 1)
    button(.72,9.24,3.6,.55,"site_go","Centre on selected site")
    label(.73,10.32,"SUPPLY CHAIN","#FFE1A0")
    words(.73,10.66,18.39,2,"Coal mine → Steel mill → Factory → Town. Farms also supply Grain to the factory. Towns exchange Passengers and Mail. Deliveries to a town grow its population and boost production.","#ACCBC9")
  else
    rect(.37,1.93,19.96,11.38,"#182C3D")
    label(.72,2.34,"FIELD MANUAL","#FFE1A0")
    words(.72,2.8,18.65,9.45,[[FIRST PAYDAY
Right-click in the 3D world and click Build starter bus line once. A bus leaves Port Alder for Mason Quay and brings back passengers on its return trip. Watch the bus move in the world and open Fleet from Inventory for company operations. Running at 4× gets your first fare in a few seconds. Check Finance and Fleet to see it paid.

BUILD IT YOURSELF
Inspect a town or industry, then choose a terminal within five map tiles of it. Bulldoze any houses in the way. Build another compatible terminal near a receiver. Choose Road or Track and select its start then end (same tile for a single piece). Use Z then X to choose the elbow, and build per segment with a bridge across water or a tunnel through hills. A signal lets trains on the same directed route follow at a safe distance. Opposing trains wait their turn. Inspect a signal and choose Hold departures to block new use.

RUN THE SERVICE
Fleet & orders lets you choose a model, cargo, and starting terminal. The purchase includes a starting order. Add at least one other order, and Dispatch. Routes repeat. At terminals you can transfer, wait for a full load, or unload without boarding. Multi-mode transfers require same-company terminals within two tiles, and only a final delivery earns a fare. Boats use navigable water and canals. Planes fly direct between airports.

CONTROLS & PERSISTENCE
WASD flies; Space and Shift raise/lower altitude. Hold E (Aux1) to fly faster. Directory, Locate Vehicle and the optional Jump Map teleport directly to a site. Close sheets to return to the world. Inventory opens company operations. Right-click for tools, and left-click aimed at the ground to inspect or apply your selected tool. Your company, construction, orders, and economy save with the Luanti world. The first company controls speed on multiplayer; the simulation waits when nobody is online.

Models become available over time, loans accrue interest monthly, and each type of service uses its own facilities.]],"#C0D5D2")
    button(.73,12.48,3.18,.5,"go_map","Return to map","primary")
  end
  core.show_formspec(n,"luanttd_core:dispatch",table.concat(b))
end
local function center(V,id)
  local x,z=Sim.xy(id)
  V.x=limit(x-9,1,Sim.W-19);V.z=limit(z-7,1,Sim.H-14)
  V.chosen=id;V.anchor=nil;V.tab="map"
end
function U.survey(p,id)
  local n=p:get_player_name();local V=view(n)
  V.live=false
  local tile=id or V.chosen
  local x,z=Sim.xy(tile)
  local level=20
  local pitch=1.10
  if api.generated_world and Sim.W>64 and api.terrain then
    local h=api.terrain.sample(tile,x*2+.5,z*2+.5)
    level=math.max(20,h+12)
    pitch=math.atan2(level+1.625-h,8.5)
  end
  p:set_pos({x=x*2+0.5,y=level,z=z*2-8})
  p:set_look_horizontal(0);p:set_look_vertical(pitch)
  core.close_formspec(n,"luanttd_core:dispatch");core.close_formspec(n,"luanttd_core:context")
end
function U.teleport_tile(p,id)
  local t
  if api.authority_handoff and R.host_tile then t=R.host_tile(id) else t=id and S.tiles[id] end
  if not t or t.stock_void then return false end
  local x,z=Sim.xy(id)
  local cx,cz=x*2+.5,z*2+.5
  local h=(t.h or 0)+.5
  if api.terrain and R.uses_slope(id) then h=math.max(h,R.surface(id,cx,cz)) end
  local function higher(index,spans)
    local span=index and spans and spans[index[id]]
    if span and span.deck then h=math.max(h,span.deck+1) end
  end
  if api.authority_handoff and R.host_deck then
    local deck=R.host_deck(id);if deck then h=math.max(h,deck+1) end
  else
    higher(S.bridge_above,S.stock_road_bridges)
    higher(S.rail_bridge_above,S.stock_rail_spans)
    higher(S.aqueduct_above,S.stock_aqueducts)
  end
  local V=view(p:get_player_name())
  V.chosen=id
  V.status=("Moved above tile %d,%d."):format(x,z)
  p:set_pos({x=cx,y=h+8,z=cz})
  return true
end
function U.leave(n)
  session[n]=nil;hud[n]=nil
  if Workbenches then Workbenches.leave(n) end
  if Tutorials then Tutorials.leave(n) end
  if U.layer_bulldozer then U.layer_bulldozer.leave(n) end
  if api.worker_fleet then api.worker_fleet.leave(n) end
  if api.worker_town_founding then api.worker_town_founding.leave(n) end
  if api.worker_news then api.worker_news.leave(n) end
  if api.worker_build then api.worker_build.leave(n) end
  if U.signal_ui then U.signal_ui.leave(n) end
end
function U.cinematic(p,active)
  local name=p:get_player_name()
  if api.worker_news then api.worker_news.cinematic(p,active) end
  if active and hud[name] then p:hud_remove(hud[name]);hud[name]=nil
  elseif not active then U.hud() end
end
function U.hud()
  for _,p in ipairs(core.get_connected_players()) do
    local n=p:get_player_name()
    local c
    if company_projection then c=company_projection.company(n)
    else c=S.companies[n] end
    if c and not (api.cinematic and api.cinematic.active(p)) and
        not (api.world and api.world.avatar_state and api.world.avatar_state(p)) then
      local stamp=company_projection and formatted_date(c.year,c.month,c.day_of_month) or date()
      local message="LuanTTD   •   "..stamp.."   •   "..dollars(c.cash).."   •   Inventory: Control desk"
      local V=view(n)
      if not hud[n] then
        hud[n]=p:hud_add({type="text",position={x=.5,y=.05},alignment={x=0,y=0},offset={x=0,y=0},
          text=message,number=0xffffff,z_index=100,scale={x=100,y=100}})
      elseif message~=V.hud_line then p:hud_change(hud[n],"text",message) end
      V.hud_line=message
      if api.worker_news then api.worker_news.observe(p,c) end
      if not company_projection and V.live and V.tab=="map" and S.day-(V.last_live or -10)>=math.max(1,S.speed) then
        V.last_live=S.day;U.open(p)
      end
    end
  end
end
local function pick(fields,id,a,prior)
  local i=tonumber(fields[id])
  if a and i and a[i] then return i end
  return prior
end
local tree_palette_form="luanttd_core:plant_tree_palette"
local function tree_species_name(species)
  return (not species or species==255) and "Mixed Temperate" or ("Temperate tree %02d"):format(species+1)
end
function U.open_tree_palette(p)
  local v=view(p:get_player_name())
  local choices={"Mixed Temperate"}
  for species=0,11 do choices[#choices+1]=tree_species_name(species) end
  local selected=not v.tree_species and 1 or v.tree_species==255 and 1 or v.tree_species+2
  core.show_formspec(p:get_player_name(),tree_palette_form,
    "formspec_version[4]size[8,4.1]label[.44,.42;Plant trees]"..
    "label[.44,.83;Choose a tree type. Mixed uses the original random mix.]"..
    "dropdown[.44,1.36;7.1,.65;tree_choice;"..table.concat(choices,",")..";"..selected..";true]"..
    "label[.44,2.25;Click to plant one tile or drag to plant an area.]"..
    "label[.44,2.61;Hold Aux1 for a diagonal area. Right-click to change type.]"..
    "button_exit[4.8,3.2;2.75,.55;tree_confirm;Use tree type]")
end
function U.fields(p,formname,f)
  if formname==tree_palette_form then
    local n=tonumber(f.tree_choice)
    if f.tree_confirm and n and n%1==0 and n>=1 and n<=13 then
      local v=view(p:get_player_name())
      v.tree_species=n==1 and 255 or n-2
      v.tree_press=nil
      v.status=tree_species_name(v.tree_species).." · Click or drag to plant."
    end
    return true
  end
  if formname==tram_offer_form then
    local n=p:get_player_name()
    local v=view(n)
    local offer=v.tram_offer
    v.tram_offer=nil
    if not offer then return true end
    if not (f.tram_paid or f.tram_test) then
      v.status="Streetcar setup canceled. Nothing was bought."
      return true
    end
    if f.tram_paid and f.tram_test then return true end
    offer.paid=f.tram_paid~=nil
    if offer.paid then offer.cost=TramMarket.price end
    worker_action(n,v,offer,function(ok)
      if not ok then return end
      v.anchor,v.tram_first,v.fixed_route=nil,nil,nil
      if api.world and api.world.end_order_selection then api.world.end_order_selection(p) end
    end)
    return true
  end
  if formname=="luanttd_core:town_council_campaigns" then
    return U.town_council_fields(p,f)
  end
  if formname=="luanttd_core:town_advertising" then
    return U.town_advertising_fields(p,f)
  end
  if formname=="luanttd_core:town_authority" then
    if f.town_council then U.open_town_council(p)
    elseif f.town_advertising then U.open_town_advertising(p)
    elseif f.build_statue then U.fund_town_from_panel(p,"statue")
    elseif f.fund_buildings or f.fund_roads then U.fund_town_from_panel(p,f.fund_roads and "roads" or "buildings")
    else
      local v=view(p:get_player_name());v.town_funding=nil;v.road_funding=nil;v.statue_offer=nil;v.advertising_offer=nil;v.council_offer=nil;v.authority_context=nil
    end
    return true
  end
  if api.authority_handoff and formname==worker_jump_form then return worker_jump_fields(p,f) end
  if api.worker_fleet and formname==api.worker_fleet.form then return api.worker_fleet.fields(p,f) end
  if api.worker_finance and formname==api.worker_finance.form then return api.worker_finance.fields(p,f) end
  if api.worker_town_founding and formname==api.worker_town_founding.form then return api.worker_town_founding.fields(p,f) end
  if api.worker_news and formname==api.worker_news.form then return api.worker_news.fields(p,f) end
  if api.worker_depot and formname==api.worker_depot.form then return api.worker_depot.fields(p,f) end
  if api.worker_truck_stop and formname==api.worker_truck_stop.form then return api.worker_truck_stop.fields(p,f) end
  if api.worker_rail_mail_station and formname==api.worker_rail_mail_station.form then return api.worker_rail_mail_station.fields(p,f) end
  if api.world and api.world.avatar_state and api.world.avatar_state(p) then return false end
  if formname=="luanttd_core:station_layout" then return U.station_layout_fields(p,f) end
  if formname=="luanttd_core:rail_depot_direction" then return U.depot_direction_fields(p,f) end
  if formname=="luanttd_core:road_terminal_layout" then return U.road_terminal_fields(p,f) end
  if formname=="luanttd_core:road_join_picker" then return U.road_join_picker_fields(p,f) end
  if U.signal_ui and formname==U.signal_ui.form then
    return U.signal_ui.fields(p,f,U.layer_bulldozer.open)
  end
  if U.layer_bulldozer and formname==U.layer_bulldozer.form then return U.layer_bulldozer.fields(p,f) end
  if Tutorials and formname==Tutorials.form then return Tutorials.fields(p,f) end
  if Workbenches and formname==Workbenches.form then return Workbenches.fields(p,f) end
  if formname=="" then
    if f.bl_sections and api.world.home_menu then api.world.home_menu(p);return true end
    if f.bl_palette then U.context(p,api.world.target(p));return true end
    if f.bl_company then U.open_company(p);return true end
    if f.bl_jump then U.open_jump(p);return true end
    if f.bl_finance then U.open_finance(p);return true end
    if f.bl_newspaper and api.worker_news then return api.worker_news.open(p) end
    if f.bl_tutorials and Tutorials then return Tutorials.open(p) end
    if f.bl_guide then return U.open_workbenches(p) end
    if f.bl_help then U.open_controls(p);return true end
    return false
  end
  if api.authority_handoff then
    -- All old economy forms are invalid after authority moves away.
    -- Independent engine-owned panels have their own handlers.
    if formname=="luanttd_core:service" or formname=="luanttd_core:dispatch" or formname=="luanttd_core:context" then return true end
    return false
  end
  if formname=="luanttd_core:context" then return U.context_fields(p,f) end
  if formname=="luanttd_core:service" then return U.service_fields(p,f) end
  if formname~="luanttd_core:dispatch" then return false end
  local n=p:get_player_name();local V=view(n)
  if f.quit then V.live=false;return true end
  local note
  local ok,changed
  local action=f.tab_map and "map" or f.tab_fleet and "fleet" or f.tab_ledger and "ledger"
      or f.tab_directory and "directory" or f.tab_help and "help" or f.go_map and "map"
  if action and (not api.road_first or action=="map" or action=="ledger") then V.tab=action;V.anchor=nil end
  if f.map_return and JumpMap then
    core.close_formspec(n,"luanttd_core:dispatch");return true
  end
  if f.survey then U.survey(p);return true end
  if V.tab=="map" and JumpMap then
    if f.map_coordinates or (f.key_enter and (f.key_enter_field=="map_x" or f.key_enter_field=="map_z")) then
      local id=JumpMap.pick_coordinates(f.map_x,f.map_z)
      if id and U.teleport_tile(p,id) then
        V.live=false
        core.close_formspec(n,"luanttd_core:dispatch")
        return true
      end
      V.status=("Choose a playable tile: X 1–%d, Z 1–%d."):format(Sim.W,Sim.H)
      U.open(p);return true
    end
    if jump_nav(V,f) then U.open(p);return true end
    local id=JumpMap.pick(V,f)
    if id and U.teleport_tile(p,id) then
      V.live=false;core.close_formspec(n,"luanttd_core:dispatch");return true
    end
  end
  if f.home then center(V,Sim.id(9,9)) end
  if f.west then V.x=math.max(1,V.x-9) end
  if f.east then V.x=math.min(Sim.W-19,V.x+9) end
  if f.north then V.z=math.max(1,V.z-7) end
  if f.south then V.z=math.min(Sim.H-14,V.z+7) end
  if f.live then V.live=not V.live end
  if f.axis then V.zfirst=not V.zfirst end
  if f.cancel then V.anchor=nil;note="Line cleared." end
  for _,speed in ipairs({0,1,2,4}) do
    if f["speed_"..speed] then
      if S.chair==n or core.check_player_privs(n,{server=true}) then S.speed=speed;note=speed==0 and "Simulation paused." or "Simulation at "..speed.."×."
      else note="Only the first company or server admin can change speed." end
    end
  end
  if V.tab=="map" then
    for k in pairs(f) do
      local id=tonumber(k:match("^t_(%d+)$"))
      if id and S.tiles[id] then
        local x,z=Sim.xy(id)
        if x>=V.x and x<V.x+20 and z>=V.z and z<V.z+15 then
          center(V,id);U.survey(p,id);return true
        end
      end
    end
  elseif V.tab=="fleet" then
    if f.fleet_list then
      local e=core.explode_textlist_event(f.fleet_list)
      if V.fleet_ids and V.fleet_ids[e.index] then V.selected_vehicle=V.fleet_ids[e.index];V.order=1;V.refit=nil end
    end
    if f.order_list then
      local e=core.explode_textlist_event(f.order_list)
      if e.index>0 then V.order=e.index end
    end
    local engine=pick(f,"buy_engine",V.engines,V.engine)
    if engine~=V.engine then V.engine=engine;V.cargo=1;V.buy_st=1 else
      V.cargo=pick(f,"buy_cargo",V.cargos,V.cargo)
      V.buy_st=pick(f,"buy_station",V.buy_ids,V.buy_st)
    end
    V.add_st=pick(f,"add_station",V.add_ids,V.add_st)
    V.action=pick(f,"add_action",orders,V.action)
    V.refit=pick(f,"refit_cargo",V.refit_ids,V.refit)
    local v=V.selected_vehicle
    if f.buy and V.engines and V.cargos and V.buy_ids then
      local new
      new,note=Sim.purchase(S,n,V.engines[V.engine],V.cargos[V.cargo],V.buy_ids[V.buy_st])
      if new then V.selected_vehicle=new;V.order=1;V.add_st=1;V.refit=nil end
    elseif f.order_add and V.add_ids then ok,note=Sim.add_order(S,n,v,V.add_ids[V.add_st],orders[V.action])
    elseif f.order_up or f.order_down or f.order_remove then
      ok,note=Sim.edit_order(S,n,v,V.order,f.order_up and "up" or f.order_down and "down" or "remove")
      if ok and f.order_up then V.order=V.order-1 elseif ok and f.order_down then V.order=V.order+1 end
    elseif f.toggle then ok,note=Sim.toggle(S,n,v)
    elseif f.sell then ok,note=Sim.sell(S,n,v)
    elseif f.service then ok,note=Sim.service(S,n,v)
    elseif f.empty then ok,note=Sim.empty(S,n,v)
    elseif f.refit and V.refit_ids then ok,note=Sim.refit(S,n,v,V.refit_ids[V.refit or 0])
    elseif f.locate and S.fleet[v] then
      local id=Sim.position(S,S.fleet[v])
      if id then center(V,id);U.survey(p,id);return true end
    end
  elseif V.tab=="ledger" then
    if f.borrow or f.repay then ok,note=Sim.loan(S,n,f.borrow and 10000 or -10000) end
  elseif V.tab=="directory" then
    if f.sites then
      local e=core.explode_textlist_event(f.sites)
      if S.sites[e.index] then V.site=e.index;if e.type=="DCL" then f.site_go=true end end
    end
    if f.site_go then local st=S.sites[V.site or 1];center(V,st.tile);U.survey(p,st.tile);return true end
  end
  if changed then R.update(changed) end
  if note then V.status=note;api.save() end
  U.open(p)
  return true
end
function U.inventory(p)
  if api.road_first then
    p:set_inventory_formspec("formspec_version[7]size[9.4,4.9]bgcolor[#152334;false]"..
      "label[.4,.5;LuanTTD   /   Control desk]"..
      "button[.4,1.05;4.18,.62;bl_company;Fleet]"..
      "button[4.8,1.05;4.18,.62;bl_finance;Finances]"..
      "button[.4,1.88;4.18,.62;bl_jump;Jump map]"..
      "button[4.8,1.88;4.18,.62;bl_sections;Reset hotbar to sections]"..
      "button[.4,2.71;4.18,.62;bl_help;Controls]"..
      "button[4.8,2.71;4.18,.62;bl_guide;Transport & World Guide]"..
      "button[.4,3.54;4.18,.67;bl_tutorials;Tutorials: Road, Train & Boat]"..
      "button[4.8,3.54;4.18,.67;bl_newspaper;Newspaper]")
    return
  end
  p:set_inventory_formspec("formspec_version[7]size[11,5.8]bgcolor[#101C2B;false]"..
    "label[.42,.42;LuanTTD / CONTROL DESK]"..
    "label[.42,1.02;The hotbar is your toolkit. These controls stay out of the 3D view.]"..
    "button[.42,1.58;5,.62;bl_palette;Choose extra build tool]"..
    "button[5.57,1.58;5,.62;bl_company;Fleet and orders]"..
    "button[.42,2.40;5,.62;bl_finance;Finance ledger]"..
    "button[5.57,2.40;5,.62;bl_jump;Jump map]"..
    "button[.42,3.23;5,.62;bl_help;Field manual]"..
    "label[.42,4.18;1 Inspect   /   2 Road   /   3 Track   /   4 Road stop]"..
    "label[.42,4.61;5 Rail station   /   6 Custom   /   7 Company   /   8 Jump]")
end
function U.tutorial_hint(p) return Tutorials and Tutorials.hint(p) or "" end
function U.open_jump(p)
  local n=p:get_player_name()
  local V=view(n)
  if api.authority_handoff then
    local client=api.worker_bridge_client
    if not client or not JumpMap then return false end
    local ticket={}
    V.worker_jump=ticket
    core.show_formspec(n,worker_jump_form,"formspec_version[7]size[9,2.2]label[.48,.67;Reading the map…]"..
      "button_exit[.48,1.27;8.03,.55;map_return;Return to 3D world]")
    local where=p:get_pos()
    local here=where and Sim.id(math.floor((where.x+.5)/2),math.floor((where.z+.5)/2))
    local sent,why=client.query({kind="jump_map",player=n,zoom=V.map_zoom==true,here=here,focus=V.map_center},function(r)
      if session[n]~=V or V.worker_jump~=ticket then return end
      if not r.ok then core.close_formspec(n,worker_jump_form);V.status=r.why;return end
      local b,push,rect,label,button=form()
      label(.45,.58,"LuanTTD / Jump map","#FFE3A3")
      JumpMap.draw(V,p,{push=push,rect=rect,label=label,button=button},r.value)
      ticket.hydrated=true
      core.show_formspec(n,worker_jump_form,table.concat(b))
    end)
    if not sent then V.worker_jump=nil;V.status=why;core.close_formspec(n,worker_jump_form) end
    return true
  end
  V.tab="map"
  U.open(p)
end
function worker_jump_fields(p,f)
  local n=p:get_player_name()
  local V=view(n)
  local q=V.worker_jump
  if f.quit or f.map_return then
    V.worker_jump=nil;core.close_formspec(n,worker_jump_form);return true
  end
  if not q or not q.hydrated or q.pending then return true end
  if jump_nav(V,f) then return U.open_jump(p) end
  local id=JumpMap.pick(V,f)
  local coordinates=f.map_coordinates or f.key_enter and (f.key_enter_field=="map_x" or f.key_enter_field=="map_z")
  if not id and not coordinates then return true end
  local client=api.worker_bridge_client
  q.pending=true
  local sent,why=client.query({kind="jump_tile",player=n,tile=id,x=tonumber(f.map_x),z=tonumber(f.map_z)},function(r)
    if session[n]~=V or V.worker_jump~=q then return end
    V.worker_jump=nil
    core.close_formspec(n,worker_jump_form)
    if r.ok then
      local point=r.value
      V.chosen=point.tile
      p:set_pos({x=point.x,y=point.y,z=point.z})
      V.status="Moved above the selected tile."
    else V.status=r.why end
  end)
  if not sent then q.pending=nil;V.status=why end
  return true
end
function U.select_tool(p,tool)
  local V=view(p:get_player_name())
  if V.tool~=tool then
    V.tool=tool;V.tram_offer=nil;V.road_press=nil;V.tree_press=nil;V.demolition_anchor=nil;V.anchor=nil;V.rail_press=nil;V.rail_ghost=nil;V.rail_first=nil;V.airport_first=nil;V.ferry_depot=nil;V.ferry_first=nil;V.ship_coal_first=nil;V.tram_first=nil;V.ferry_via=nil
  end
end
function U.select_rail_gauge(p,gauge)
  local n=p:get_player_name()
  local V=view(n)
  local title=gauge==3 and "Maglev" or gauge==2 and "Monorail"
  local function equip(value)
    V.rail_gauge=value
    V.anchor,V.rail_press,V.rail_ghost=nil,nil,nil
    V.status=title and (title.." selected. Use AutoRail, Platform or Depot.") or "Standard rail selected."
  end
  if not title then V.rail_gauge_request=nil;equip(nil);return end
  local client=api.worker_bridge_client
  if not client then V.status="The campaign worker is not ready.";return end
  local ticket={}
  V.rail_gauge_request=ticket
  local sent,why=client.query({kind="company",player=n},function(r)
    if session[n]~=V or V.rail_gauge_request~=ticket then return end
    V.rail_gauge_request=nil
    local field=gauge==3 and "rail_maglev" or "rail_mono"
    if r.ok and r.value[field] then equip(gauge)
    else V.status=r.why or ("Your company does not have "..title:lower().." yet.") end
  end)
  if not sent then V.rail_gauge_request=nil;V.status=why end
end
function U.rail_gauge_request(V,kind,request)
  if kind=="rail" and (request.tool=="autotrack" or request.tool=="track" or request.tool=="station" or request.tool=="depot") then
    request.railtype=V.rail_gauge
  elseif kind=="transport" and request.mode=="rail" and (request.operation=="bridge" or request.operation=="tunnel") then
    request.railtype=V.rail_gauge
  end
  return request
end
function U.open_finance(p)
  if api.authority_handoff then
    if api.worker_finance then return api.worker_finance.show(p) end
    return false
  end
  view(p:get_player_name()).tab="ledger";U.open(p)
end
function U.open_workbenches(p)
  if Workbenches then return Workbenches.open(p) end
  return false
end
function U.open_controls(p)
  if api.authority_handoff then
    local lighting=api.lighting
    local mode=lighting and lighting.is_always_day() and "Always day" or "Cycle"
    local sky=lighting and lighting.allowed(p) and
      ("button[.45,4.22;4.65,.55;luanttd_daylight_toggle;Daylight: "..mode.."]") or
      ("label[.45,4.49;Daylight: "..mode.." (server setting)]")
    core.show_formspec(p:get_player_name(),"luanttd_core:worker_controls",
      "formspec_version[7]size[10.5,6.55]bgcolor[#152334;false]label[.45,.48;Controls]"..
      [[textarea[.45,1.07;9.6,2.15;;;WASD moves. Space and Shift adjust altitude. Hold E to fly faster.
Select a toolbar section and use it. Open depot or Open hangar buys vehicles and edits orders.
]]..      "Inventory opens Fleet, Finances, and the Jump map.]"..
      "button[.45,3.33;4.65,.55;luanttd_candy_toggle;"..
      (api.wildlife and api.wildlife.enabled(p) and "Hide decorative scenery" or "Show decorative scenery").."]"..
      "button_exit[5.40,3.33;4.65,.55;luanttd_cine_toggle;Cinematic view]"..
      sky..
      "button[5.40,4.22;4.65,.55;luanttd_audio_open;Music & sound]"..
      "label[.45,5.08;Godrays use Luanti's Volumetric Lighting setting.]"..
      "button_exit[.45,5.58;9.60,.55;close;Back to world]")
    return true
  end
  if api.road_first then U.service(p,"controls");return end
  view(p:get_player_name()).tab="help";U.open(p)
end
function U.open_company(p)
  if api.authority_handoff then return api.worker_fleet and api.worker_fleet.open(p) end
  if api.road_first then U.service(p,"fleet");return end
  view(p:get_player_name()).tab="fleet"
  U.open(p)
end
function U.phase(p)
  local n=p:get_player_name()
  if api.authority_handoff then
    local stats=company_projection and company_projection.company(n)
    return stats and stats.guide or 2
  end
  local c=S.companies[n]
  if c and c.paid_units>0 then return 8 end
  local count=0
  for _,v in pairs(S.fleet) do
    if v.owner==n then
      if v.running then return 7 end
      count=math.max(count,#v.orders+1)
    end
  end
  if count>0 then return count>=3 and 6 or 5 end
  local V=view(n)
  if V.guide_topology==S.topology and V.guide_build_phase then return V.guide_build_phase end
  local stops,roads,depot=0,0,false
  for _,v in pairs(S.stations) do
    if v.mode=="road" and v.owner==n and v.stop_type~="truck" then
      local linked=not api.generated_world
      if not linked then
        for dir=1,4 do if Sim.road_connected(S,v.tile,dir) then linked=true;break end end
      end
      if linked then stops=stops+1 end
    end
  end
  for _,t in pairs(S.tiles) do
    if t.owner==n then
      if t.build=="road_depot" then depot=true elseif t.build=="road" then roads=roads+1 end
    end
  end
  V.guide_topology=S.topology
  V.guide_build_phase=depot and 4 or stops>=2 and 3 or (api.generated_world or roads>=2) and 2 or 1
  return V.guide_build_phase
end
function U.guide(p,menu)
  local n=p:get_player_name()
  local V=view(n)
  if V.pick_order then return "Click your stops in order. Right-click when done." end
  if menu=="railworks" or menu=="railops" then
    return "Connect track, two stations and a depot. Use Open depot to buy a train, then choose its orders."
  end
  if menu=="survey" then return "Use Jump map to find a place, or choose how to explore the world." end
  if menu=="harbor" then return "Build docks and a ship depot. Use Open depot to buy and order a vessel." end
  if menu=="airfields" then return "Build two airfields. Use Open hangar to buy and order aircraft." end
  if menu=="freight" then
    if api.authority_handoff then
      return "Inspect truck stops to see the cargo they supply or accept. Buy the matching vehicle at a road depot."
    end
    for _,id in ipairs(sorted(S.fleet,n)) do
      local v=S.fleet[id]
      if v.cargo=="coal" and v.running then
        local next_order=#v.orders>0 and v.orders[v.index%#v.orders+1]
        local stop=S.stations[v.dest or next_order and next_order.station]
        return v.units.." t coal aboard"..(stop and ("   ·   Next: "..U.stop_label(stop)) or "")
      end
    end
    if api.farm_tools or api.oil_tools or api.timber_tools then
      return "Inspect truck stops to see each cargo they supply or accept. Buy the matching vehicle at a road depot."
    end
    return "Build truck stops near the mine and power station, then buy a coal tipper at the depot."
  end
  if menu=="tramway" and api.tram then
    if api.authority_handoff then return "Choose Streetcar orders. Use two electrified bus platforms for a paid route, or run a free test." end
    local running,summary=api.tram.status(n)
    return running and summary or "Build a dedicated line, depot and two through stops. Then choose Order test streetcar."
  end
  if V.tool=="company_hq" then return "Aim at the first corner of a 2×2 site. Click to build or relocate your headquarters." end
  if menu=="terrain" then
    if V.tool=="landscape_plant_tree" then return "Click or drag to plant. Hold Aux1 (usually E) for diagonal planting. Right-click to change type." end
    if V.tool=="landscape_purchase_land" then return "Click or drag to buy. Hold Aux1 for a diagonal area. Bulldoze your marker to sell." end
    return "Area tools take two corners. Hold Aux1 (usually E) on the second click for a diagonal selection."
  end
  if menu=="road_stops" then
    if U.phase(p)>=3 then return "Back returns to Roadworks. Then choose Road depot." end
    return "For a connected first route, put two Roadside stops on straight town streets."
  end
  if menu and menu~="home" and menu~="roads" and menu~="fleet" then return "" end
  local phase=U.phase(p)
  if api.road_first and api.world.menu(p)=="home" and phase<=4 then
    return "Choose Roadworks, then click to open its hotbar."
  elseif api.road_first and api.world.menu(p)=="home" and phase<=6 then
    return "Open Fleet to keep working with your bus."
  end
  if phase==7 and S.road_economy then
    if api.authority_handoff then return "Service is running. Open Fleet to inspect your vehicles and orders." end
    local service,passenger_bus=false,false
    for _,v in pairs(S.fleet) do
      if v.owner==n and v.running and v.cargo=="passenger" then
        passenger_bus=true
        if v.units>0 then
          local next_order=#v.orders>0 and v.orders[v.index%#v.orders+1]
          local dest=v.dest or next_order and next_order.station
          local stop=S.stations[dest]
          return v.units.." aboard"..(stop and ("   ·   Next stop: "..stop.name) or "")
        end
        if v.last_arrival then service=true end
      end
    end
    if service then return "Service has started. Riders are gathering at your stops." end
    return passenger_bus and "First bus is on its way. Stops start attracting riders after the first visit." or ""
  end
  local guide={
    api.generated_world and "Build a road between two towns. Inspect house catchments before placing stops."
      or "1 / 6   Choose AutoRoad, then drag to build a road between the two towns.",
    api.road_bay_tools and (api.task_hotbar and "2 / 6   Choose Bus stop. Place two stops on straight streets." or "2 / 6   Open Bus Stops. Place two roadside stops on existing straight streets.")
      or "2 / 6   Choose Bus stop and build one at each end.",
    "3 / 6   Choose Road depot. Aim at flat land beside the same street network.",
    api.task_hotbar and "4 / 6   Aim at the depot, then use Open depot to buy a bus." or "4 / 6   Right-click the depot and buy a bus.",
    "5 / 6   Click Add stops, then pick your two bus stops in the world.",
    "6 / 6   Start service in the bus window, or open Fleet from Sections.",
    "Bus dispatched. Watch it pick up and deliver passengers.",
    "",
  }
  return guide[phase]
end
function U.status(p,text) view(p:get_player_name()).status=text end
function U.anchor(p)
  local V=view(p:get_player_name())
  return V.demolition_anchor or (V.road_press and V.road_press.id) or (V.rail_press and V.rail_press.id) or V.tree_press or V.anchor
end
function U.road_action(p,key)
  local V=view(p:get_player_name())
  if key=="cancel" then
    V.anchor=nil;V.status="Selection canceled."
  elseif key=="bend" then
    V.zfirst=not V.zfirst
    V.status=V.zfirst and "Tramways bend Z then X." or
      "Tramways bend X then Z."
  end
end
function U.speed(p,key)
  local n=p:get_player_name()
  if api.authority_handoff then
    local speed=({pause=0,normal_speed=1,fast=4})[key]
    if speed then
      worker_action(n,view(n),{kind="speed",speed=speed,admin=core.check_player_privs(n,{server=true})})
    end
    return
  end
  if S.chair~=n and not core.check_player_privs(n,{server=true}) then
    U.status(p,"Only the first company or server admin can change time.");return
  end
  local speed=({pause=0,normal_speed=1,fast=4})[key]
  if speed then
    S.speed=speed;api.save()
    U.status(p,speed==0 and "Simulation paused." or ("Simulation speed: "..speed.."×"))
  end
end
local function asset_details(p,tile,hit)
  local t=tile and S.tiles[tile]
  if not t then return false end
  local dispatch=S.stock_rail_dispatch
  if U.signal_ui and dispatch and dispatch.signals and dispatch.signals.records[tile] and api.rail_build and
      U.signal_ui.inspect(p,tile,hit) then return true end
  if t.rail_depot_dir~=nil and api.owned_rail_ui and api.owned_rail_ui.open(p,tile) then return true end
  if t.house and t.source_house and t.source_house.town_growth then U.service(p,"growth_house",tile)
  elseif t.stock_object and t.stock_object.kind=="owned_land" then
    U.status(p,("Company land · %s · Bulldoze to sell for $%d"):format(t.owner or "Unknown",Sim.owned_land_resale()))
  elseif t.stock_landmark then
    local record=t.stock_landmark
    local town=S.sites[record.town]
    local label=record.kind=="lighthouse" and "Lighthouse" or record.kind=="statue" and "Company statue" or "Radio transmitter"
    U.status(p,(town and (town.name.." · ") or "")..label.." · Protected landmark")
  elseif t.stock_industry then
    local chain=t.stock_industry.chain
    U.service(p,chain=="farm" and "farm_industry" or chain=="timber" and "timber_industry" or
      chain=="oil" and "oil_industry" or "industry",
      t.stock_industry.id)
  elseif t.rail_span_id and api.rail_spans then U.service(p,"rail_span_status",t.rail_span_id)
  elseif t.level_crossing and api.crossings then U.service(p,"level_crossing_status",tile)
  elseif t.airfield then U.service(p,"airfield_status",t.airfield.airport)
  elseif api.tram and api.tram.facility(p:get_player_name(),tile,"depot") then U.service(p,"tram_depot_status",tile)
  elseif t.ship and t.ship.kind=="buoy" then U.status(p,("Public buoy %d · Ship route marker"):format(t.ship.station))
  elseif t.ship then U.service(p,"harbor_status",tile)
  elseif t.rail_waypoint_id then
    U.status(p,("Rail waypoint %d · Trains pass without stopping"):format(t.rail_waypoint_id))
  elseif t.rail_station_id then U.service(p,"rail_platform_state",t.rail_station_id)
  else return false end
  return true
end
function U.inspect(p,tile)
  if api.authority_handoff then
    local v=api.vehicle_ui and api.vehicle_ui.pick(p,90)
    if v then return api.vehicle_ui.open(p,v.kind,v.id) end
    return U.context(p,tile)
  end
  local n=p:get_player_name()
  local vehicle=R.pick(p)
  if vehicle then U.service(p,"vehicle",vehicle);return end
  if asset_details(p,tile) then return end
  local t=S.tiles[tile]
  if t and t.build=="road_depot" then U.service(p,"depot",tile)
  elseif t and t.station then U.service(p,"stop",t.station)
  else U.context(p,tile) end
end
local landscape_tools={
  company_hq={mode="company_hq",name="Company headquarters"},
  landscape_raise={mode="raise",name="Raise corner"},landscape_lower={mode="lower",name="Lower corner"},
  landscape_level={mode="level",name="Level area",area=true},
  landscape_raise_area={mode="raise",name="Raise area",area=true},
  landscape_lower_area={mode="lower",name="Lower area",area=true},
}
local function landscape_request(V,id,p)
  local tool=landscape_tools[V.tool]
  if not tool then return end
  local anchor=tool.area and V.anchor
  local x,z=Sim.xy(anchor or id)
  local u,v
  if anchor then u,v=Sim.xy(id) end
  local diagonal=tool.area and p:get_player_control().aux1 or false
  return tool.mode,x,z,u,v,tool.area,diagonal
end
local pick_bridges={road_bridge_picker="road",rail_bridge_picker="rail"}
local function bridge_tool(name)
  local mode=pick_bridges[name]
  return mode and api.bridge_picker and
    ((mode=="road" and api.structure_tools) or (mode=="rail" and api.rail_span_tools)) and mode or nil
end
local function bridge_label(mode)
  return mode=="road" and "Road bridge" or "Rail bridge"
end
local function structure_request(V)
  return V.tool:match("^structure_(%a+)$")
end
local function structure_build(n,V,id,mode,quote_only)
  if mode=="tunnel" then return Sim.road_tunnel(S,n,id,quote_only) end
  return Sim.road_bridge(S,n,V.anchor,id,({wood=0,concrete=1,steel=2})[mode],quote_only)
end
local tram_mode={tram_track="road",tram_depot="depot",tram_stop="drive_stop",tram_bit="road"}
local tram_dir={[0]="West","South","East","North"}
function U.rotate_tram(p)
  local V=view(p:get_player_name())
  V.tram_dir=((V.tram_dir or 2)+1)%4
  V.status="Tram tool direction: "..tram_dir[V.tram_dir].."."
end
local tram_order={name="Order test streetcar"}
local function tram_order_target(n,V,id)
  if not V.anchor then
    return api.tram.facility(n,id,"depot"),"Click your tram depot first."
  end
  if not api.tram.facility(n,id,"drive_stop") then return false,"Choose an owned through tram stop." end
  if V.tram_first==id then return false,"Choose a different second tram stop." end
  return true,V.tram_first and "Pick the second through tram stop." or "Click the first through tram stop."
end
function U.clear_tram_run(p)
  if not api.tram then return end
  local V=view(p:get_player_name())
  if api.authority_handoff then
    if api.worker_fleet then return api.worker_fleet.open(p,1,"tram") end
    V.status="The streetcar roster is not ready."
    return
  end
  local ok,msg=api.tram.clear(p:get_player_name())
  V.status=msg
  if ok then V.anchor,V.tram_first=nil,nil end
end
local function tram_request(p,V,id)
  local mode=tram_mode[V.tool]
  local d=V.tram_dir or 2
  if not mode then return end
  if V.tool=="tram_track" then return mode,V.anchor and Sim.line(V.anchor,id,V.zfirst) or {id} end
  if V.tool=="tram_bit" then return mode,{id},8/2^d,tram_dir[d] end
  if V.tool=="tram_stop" then return mode,{id},d%2,d%2==0 and "East–West" or "North–South" end
  d=V.tram_depot_dir or DepotFacing(p)
  return mode,{id},d,"Door faces "..tram_dir[d]
end
local ship_mode={ship_dock="dock",ship_join_dock="dock",ship_depot="depot",ship_remove="remove",ship_aqueduct="aqueduct",ship_canal="canal",ship_lock="lock"}
local buoy_tools={ship_buoy="Place public buoy",ship_buoy_remove="Remove buoy, keep water"}
local function buoy_quote(n,tool,id)
  local N=api.shipyard.network
  if tool=="ship_buoy_remove" then
    local part=S.tiles[id].ship
    if not part or part.kind~="buoy" then return nil,"SELECT_PUBLIC_BUOY" end
    local tiles,cost=N.remove(S,n,id,nil,true)
    return tiles and {tiles=tiles,cost=cost} or nil,cost
  end
  return N.quote(S,n,"buoy",id)
end
local function aquatic_remove(name,id,quote)
  local p=S.tiles[id].ship
  if p and p.aqueduct then return api.aqueduct.remove(S,name,id,quote) end
  if p and p.kind=="lock" then return api.waterworks.remove_lock(S,name,id,quote) end
  if not p and S.tiles[id].stock_canal then return api.waterworks.remove(S,name,id,quote) end
  return api.shipyard.network.remove(S,name,id,nil,quote)
end
local function ship_span(plan)
  local ids={plan.start,plan["end"]}
  for _,tile in ipairs(plan.middle) do ids[#ids+1]=tile end
  return ids
end
function U.rotate_ship(p)
  local V=view(p:get_player_name())
  V.ship_axis=1-(V.ship_axis or DepotFacing(p)%2)
  V.status=V.ship_axis==0 and "Ship depot: East–West." or "Ship depot: North–South."
end
function U.ship_depot_axis(p,V,kind)
  return V.ship_axis or (kind=="depot" and DepotFacing(p)%2 or 0)
end
function U.rail_depot_request(p,V,id)
  return {tool="depot",first=id,direction=V.rail_depot_dir or DepotFacing(p)}
end
local rail_tool_code={rail_track_x=0,rail_track_y=1,rail_track_upper=2,rail_track_lower=3,
  rail_track_left=4,rail_track_right=5}
local waypoint_tools={rail_waypoint_place="Place railway waypoint",rail_waypoint_remove="Remove railway waypoint"}
local function waypoint_quote(n,tool,id)
  local B=api.rail_build
  if not B or not B.quote_waypoint then return nil,"Rail waypoints are unavailable in this world." end
  return B.quote_waypoint(n,id,tool=="rail_waypoint_remove")
end
local rail_tool_labels={
  rail_autotrack="AutoRail",
  rail_track_x="East–West track",rail_track_y="North–South track",rail_track_upper="Upper curve",
  rail_track_lower="Lower curve",rail_track_left="Left curve",rail_track_right="Right curve",
  rail_platform="Rail platform",rail_depot_tool="Rail depot",rail_signal_pbs="Path signal",
  rail_signal_oneway="One-way path signal",rail_signal_block="Conventional block signal",rail_signal_remove="Remove signal",
  rail_electrify="Electrify railway",rail_deelectrify="Convert to ordinary rail"}
local electric_tools={rail_electrify=1,rail_deelectrify=0}
local function wire_quote(n,V,id)
  local x,z=Sim.xy(V.anchor or id)
  local u,v=Sim.xy(id)
  if (math.abs(x-u)+1)*(math.abs(z-v)+1)>256 then return nil,"Select up to 256 tiles at a time." end
  local ids={}
  for row=math.min(z,v),math.max(z,v) do
    for column=math.min(x,u),math.max(x,u) do ids[#ids+1]=Sim.id(column,row) end
  end
  local ticket,why=api.electric_quote(n,ids,electric_tools[V.tool])
  return ticket,why,ids
end
local wire_errors={
  RAILTYPE_NOT_AVAILABLE="Electrified rail becomes available when an electric locomotive enters the stock company roster.",
  FLAT_RAIL_REQUIRED="Ordinary track must be flat. Timber rail bridge ramps are part of the bridge.",
  SINGLE_RAIL_PIECE_REQUIRED="Electrification currently supports one rail piece per tile.",
  COMPLETE_PLATFORM_REQUIRED="Select the entire owned platform.",
  RAIL_OCCUPIED="Move the train out of the selected section first.",
  RAIL_ROUTE_ACTIVE="An active train uses this section. Clear the route before converting it.",
  RAIL_RESERVED="A train has reserved this section.",
  PROTECTED_RAIL_STRUCTURE="This structure or lower layer cannot be converted. Try an owned timber rail bridge portal.",
  INVALID_RAIL_SPAN="Both bridge portals and the deck must share valid railway records.",
}
local function wire_error(reason)
  return wire_errors[reason] or tostring(reason or "Cannot convert this railway selection.")
end
function U.rotate_rail(p)
  local V=view(p:get_player_name())
  V.rail_dir=((V.rail_dir or 2)+1)%4
  V.status="Rail fitting direction: "..tram_dir[V.rail_dir].."."
end
function U.open_depot_direction(p,tool)
  local n=p:get_player_name()
  local V=view(n)
  local tram=tool=="tram_depot"
  local setting=tram and "tram_depot_dir" or "rail_depot_dir"
  local choice=V[setting]
  V.depot_direction_open=setting
  local b={"formspec_version[7]size[8.2,4.22]bgcolor[#152334;false]",
    "label[.4,.45;"..(tram and "Tram" or "Rail").." depot / Door direction]",
    "label[.4,1.06;Choose the side that connects to the track.]"}
  if choice==nil then b[#b+1]="style[rail_door_auto;bgimg=bl_button_active.png]" end
  b[#b+1]="button[2.94,2.34;2.31,.64;rail_door_auto;Face me]"
  for _,dir in ipairs({3,0,2,1}) do
    local x,y=dir==0 and .42 or dir==2 and 5.47 or 2.94,dir==3 and 1.48 or dir==1 and 3.18 or 2.34
    local active=choice==dir
    local key="rail_door_"..dir
    if active then b[#b+1]="style["..key..";bgimg=bl_button_active.png]" end
    b[#b+1]=("button[%g,%g;2.31,.64;%s;%s]"):format(x,y,key,esc(tram_dir[dir]))
  end
  core.show_formspec(n,"luanttd_core:rail_depot_direction",table.concat(b))
  return true
end
function U.depot_direction_fields(p,f)
  local n=p:get_player_name()
  local V=view(n)
  if not V.depot_direction_open then return true end
  if f.quit then V.depot_direction_open=nil;return true end
  local chosen
  for d=0,3 do
    if f["rail_door_"..d] then
      if chosen then return true end
      chosen=d
    end
  end
  if chosen==nil and not f.rail_door_auto or chosen~=nil and f.rail_door_auto then return true end
  V[V.depot_direction_open],V.depot_direction_open=chosen,nil
  core.close_formspec(n,"luanttd_core:rail_depot_direction")
  U.status(p,chosen~=nil and ("Depot door faces "..tram_dir[chosen]..".") or "Depot door faces you.")
  return true
end
local road_terminal_kind={road_station="bus",truck_stop_tool="truck",road_depot="depot"}
U.stop_area_geometry=dofile(moddir.."/openttd/road_stop_area.lua")()
local road_terminal_title={bus="Bus stop",truck="Truck stop",depot="Road depot"}
function U.road_terminal_tool(tool) return road_terminal_kind[tool]~=nil end
local function road_terminal_request(V,id)
  local kind=road_terminal_kind[V.tool]
  local spec=kind and V.road_terminal_layout and V.road_terminal_layout[kind]
  if spec then return {tool="stock_terminal",first=id,kind=kind,direction=spec.dir,through=spec.through} end
end
function U.road_auto_terminal(p,tool,id)
  local kind=road_terminal_kind[tool]
  if kind then return {tool="stock_terminal_auto",kind=kind,first=id,
    adjacent=kind~="depot" and p:get_player_control().aux1==true,
    preferred_direction=kind=="depot" and DepotFacing(p) or nil} end
end
function U.road_stop_gesture(p,tool)
  if not api.authority_handoff then return false end
  if tool=="road_stop_remove" then return true end
  if not p or tool~="road_station" and tool~="truck_stop_tool" then return false end
  local V=view(p:get_player_name())
  return V.road_terminal_layout and V.road_terminal_layout[road_terminal_kind[tool]]~=nil
end
function U.road_stop_request(p,V,first,last)
  if V.tool=="road_stop_remove" then return {tool="stock_stop_remove",first=first,last=last} end
  local r=road_terminal_request(V,first)
  r.tool,r.last,r.adjacent="stock_stop_area",
    U.stop_area_geometry.drag_end(Sim,first,last,r.direction,r.through,12),p:get_player_control().aux1==true
  return r
end
local function road_terminal_label(req)
  local kind=req.kind
  local layout=req.through and (req.direction==0 and "east–west through" or "north–south through")
    or ("door "..tram_dir[req.direction]:lower())
  return road_terminal_title[kind].." · "..layout
end
function U.open_road_terminal(p,tool)
  local kind=road_terminal_kind[tool]
  if not kind then return false end
  local name=p:get_player_name()
  local V=view(name)
  V.current_road_terminal=kind
  V.road_terminal_layout=V.road_terminal_layout or {}
  local spec=V.road_terminal_layout[kind]
  local form={"formspec_version[7]size[9.6,5.35]bgcolor[#152334;false]",
    "label[.46,.38;"..road_terminal_title[kind].." layout]",
    kind=="depot" and "label[.46,.91;Choose an entrance, then click a tile in the world.]" or
      "label[.46,.91;Choose a layout, then click or drag in the world. Hold E for join choices.]"}
  local coords={[0]={.5,2.13},[1]={3.57,2.94},[2]={6.65,2.13},[3]={3.57,1.39}}
  local function button(key,text,x,y,active)
    if active then form[#form+1]="style["..key..";bgimg=bl_button_active.png]" end
    form[#form+1]=("button[%g,%g;2.45,.61;%s;%s]"):format(x,y,key,esc(text))
  end
  for dir=0,3 do
    local pos=coords[dir]
    button("door_"..dir,tram_dir[dir],pos[1],pos[2],spec and not spec.through and spec.dir==dir)
  end
  if kind~="depot" then
    button("through_0","East–west through",.5,3.93,spec and spec.through and spec.dir==0)
    button("through_1","North–south through",3.57,3.93,spec and spec.through and spec.dir==1)
    button("auto","Auto orientation",6.65,3.93,not spec)
  else
    button("auto","Auto orientation",3.57,3.93,not spec)
  end
  core.show_formspec(name,"luanttd_core:road_terminal_layout",table.concat(form))
  return true
end
function U.road_terminal_fields(p,f)
  local name=p:get_player_name()
  local V=view(name)
  local kind=V.current_road_terminal
  if not kind then return true end
  if f.quit then V.current_road_terminal=nil;return true end
  local chosen,n=nil,f.auto and 1 or 0
  for dir=0,3 do if f["door_"..dir] then chosen={dir=dir};n=n+1 end end
  if kind~="depot" then
    for axis=0,1 do if f["through_"..axis] then chosen={dir=axis,through=true};n=n+1 end end
  end
  if n~=1 then return true end
  V.road_terminal_layout[kind]=chosen
  V.current_road_terminal=nil
  core.close_formspec(name,"luanttd_core:road_terminal_layout")
  U.status(p,chosen and road_terminal_label({kind=kind,direction=chosen.dir,through=chosen.through}) or
    "Auto orientation. Click a site in the world.")
  return true
end
function U.toggle_rail_remove(p)
  local V=view(p:get_player_name())
  V.rail_remove=not V.rail_remove
  V.anchor=nil
  V.status=V.rail_remove and "Click a track piece to remove it." or "Track placement active."
end
local coal_stage_tools={
  rail_coal_load={name="Coal loading stage",role="load"},
  rail_coal_unload={name="Coal unloading stage",role="unload"},
}
local function coal_stage_target(n,tool,id)
  local t=S.tiles[id]
  local st=t and t.rail_station_id and S.stock_rail_stations[t.rail_station_id]
  if not st or st.owner~=n then return nil,"Choose one of your existing rail platforms." end
  if Freight.role(st,"coal") then return nil,"Choose a platform without another freight stage." end
  if st.coal_role and st.coal_role~=tool.role then return nil,"Choose a platform without a different coal stage." end
  local details=Sim.rail_coal_stop_status(S,st.id)
  if tool.role=="load" and (not details or #details.sources==0) then
    return nil,"This platform must cover a real coal mine."
  elseif tool.role=="unload" and (not details or not details.accepts) then
    return nil,"This platform needs a real power station in its catchment."
  end
  return st,tool.name.."  |  Use this tile for the equipment"
end
local oil_stage_tools={
  rail_oil_load={name="Oil wells loading stage",role="load"},
  rail_oil_unload={name="Oil refinery unloading stage",role="unload"},
}
local function oil_stage_target(n,tool,id)
  local t=S.tiles[id]
  local st=t and t.rail_station_id and S.stock_rail_stations and S.stock_rail_stations[t.rail_station_id]
  if not st or st.owner~=n then return nil,"Choose one of your existing rail platforms." end
  if Freight.role(st,"oil") then return nil,"Choose a platform without another freight stage." end
  if st.oil_role and st.oil_role~=tool.role then
    return nil,"This platform already has the other oil stage."
  end
  local details=Sim.rail_oil_stop_status and Sim.rail_oil_stop_status(S,st.id)
  if tool.role=="load" and (not details or #(details.sources or {})==0) then
    return nil,"This platform must cover working Oil Wells."
  elseif tool.role=="unload" and (not details or not details.accepts) then
    return nil,"This platform must accept oil at an Oil Refinery."
  end
  return st,st.oil_role==tool.role and tool.name.."  |  Already designated" or
    tool.name.."  |  Click to designate"
end
local goods_stage_tools={
  rail_goods_load={name="Sawmill Goods loading stage",role="load"},
  rail_goods_unload={name="Town Goods receiving stage",role="unload"},
}
local function goods_stage_target(n,tool,id)
  local t=S.tiles[id]
  local st=t and t.rail_station_id and S.stock_rail_stations and S.stock_rail_stations[t.rail_station_id]
  if not st or st.owner~=n then return nil,"Choose one of your existing rail platforms." end
  if Freight.role(st,"goods") or st.goods_role and st.goods_role~=tool.role then
    return nil,"This platform already serves another freight stage."
  end
  local details=Sim.rail_goods_stop_status(S,st.id)
  if tool.role=="load" and (not details or #(details.sources or {})==0) then
    return nil,"This platform must cover a working sawmill."
  elseif tool.role=="unload" and (not details or not details.accepts) then
    return nil,"This platform must accept Goods from nearby town buildings."
  end
  return st,st.goods_role==tool.role and tool.name.."  |  Already designated" or tool.name.."  |  Click to designate"
end
local profile_stage_tools={
  rail_iron_ore_load={cargo="iron_ore",role="load",name="Iron Ore Mine · loading platform"},
  rail_iron_ore_unload={cargo="iron_ore",role="unload",name="Steel Mill · ore unloading platform"},
  rail_steel_load={cargo="steel",role="load",name="Steel Mill · steel loading platform"},
  rail_steel_unload={cargo="steel",role="unload",name="Factory · steel unloading platform"},
  rail_valuables_load={cargo="valuables",role="load",name="Bank · Valuables loading platform"},
  rail_valuables_unload={cargo="valuables",role="unload",name="Different Bank · Valuables delivery platform"},
  rail_livestock_load={cargo="livestock",role="load",name="Farm · Livestock loading platform"},
  rail_livestock_unload={cargo="livestock",role="unload",name="Factory · Livestock delivery platform"},
  rail_grain_load={cargo="grain",role="load",name="Farm · Grain loading platform"},
  rail_grain_unload={cargo="grain",role="unload",name="Factory · Grain delivery platform"},
  rail_wood_load={cargo="wood",role="load",name="Forest · Wood loading platform"},
  rail_wood_unload={cargo="wood",role="unload",name="Sawmill · Wood delivery platform"},
}
local function profile_stage_target(n,tool,id,projection)
  local t=projection and R.host_tile(id) or S.tiles[id]
  local key=t and t.rail_station_id
  local st=key and (projection and R.host_record("stock_rail_stations",key) or S.stock_rail_stations and S.stock_rail_stations[key])
  if not st or st.owner~=n then return nil,"Choose one of your existing rail platforms." end
  for _,cargo in ipairs(Freight.all) do
    local role=st[cargo.."_role"]
    if role and (cargo~=tool.cargo or role~=tool.role) then return nil,"This platform already serves another freight stage." end
  end
  if not projection then
    local get=Sim["rail_"..tool.cargo.."_stop_status"]
    local details=get and get(S,st.id)
    if not details or tool.role=="load" and #(details.sources or {})==0 or tool.role=="unload" and not details.accepts then
      return nil,"This platform is outside the required industry's catchment."
    end
  end
  return st,tool.name.."  |  Click to designate"
end
function U.flip_rail_coal(p)
  local V=view(p:get_player_name())
  V.coal_side=V.coal_side==false
  V.status=V.coal_side and "Equipment side: north or west." or "Equipment side: south or east."
end
local one_way_tool={name="Paint a one-way route"}
local one_way_errors={
  OWNED_BY="The town or another company owns this road.",
  ONEWAY_JUNCTION="One-way signs go on straight roads, not junctions.",
  VEHICLE_IN_THE_WAY="Wait for the vehicle to leave the road.",
  ONEWAY_REQUIRES_STOCK_ROAD_CLOCK="One-way roads require stock road movement.",
  ROAD_EDGE_HEIGHT_MISMATCH="The new road would not join continuously at its edge.",
  LEGACY_ROAD_ROUTE_IN_THE_WAY="A non-stock vehicle is already using this route.",
  NOT_ENOUGH_MONEY="Your company cannot afford this road.",
  NOT_ENOUGH_CASH="Your company cannot afford this road.",
  STALE_ONEWAY_QUOTE="The road changed. Aim at it again.",
  STALE_QUOTE="The road changed. Aim at it again.",
  PARAMETERS="Choose two points on one straight axis.",
}
local function one_way_text(err)
  return one_way_errors[err] or ("One-way road unavailable: "..tostring(err))
end
local function one_way_quote(n,V,id)
  if not V.anchor then return nil,"Click the start of the intended travel direction." end
  local x,z=Sim.xy(V.anchor)
  local u,v=Sim.xy(id)
  if V.anchor==id or (x~=u and z~=v) then return nil,one_way_errors.PARAMETERS end
  local q,why=api.oneway.quote(S,n,V.anchor,id,z==v and 0 or 1,{})
  if not q then return nil,one_way_text(why) end
  return q
end
local crossing_tool={name="Road / rail level crossing"}
local crossing_errors={
  LEVEL_CROSSING_DISABLED="Enable the level crossings preview first.",
  NEEDS_PLAIN_ROAD_OR_RAIL="Choose your ordinary straight road or railway.",
  OWNED_BY_ANOTHER="Choose a straight section owned by your company.",
  PROTECTED_TILE="A stop, structure, signal or other protected layer occupies this tile.",
  LAND_SLOPED_IN_WRONG_DIRECTION="This slope cannot support a level crossing.",
  OCCUPANCY_UNKNOWN="Cannot verify the tile is clear yet.",
  RESERVATION_UNKNOWN="Cannot verify the track reservation yet.",
  VEHICLE_IN_THE_WAY="Wait for the vehicle to leave the crossing site.",
  ALREADY_BUILT="A crossing already occupies that tile.",
  STALE_QUOTE="The crossing site changed. Aim at it again.",
  CROSSING_ON_ONEWAY_ROAD="Remove the one-way restriction before building a crossing.",
  NOT_ENOUGH_MONEY="Your company cannot afford the crossing.",
}
local crossing_gesture=dofile(moddir.."/crossing_gesture.lua")
local function crossing_quote(n,id)
  local request,error_=crossing_gesture(Sim,S,id)
  if not request then return nil,crossing_errors[error_] end
  local plan,why=api.crossing_quote(n,id,request)
  return plan,why and (crossing_errors[why] or ("Crossing unavailable: "..tostring(why)))
end
local rail_orders={rail_order_one={name="Order train pilot"},rail_order_shuttle={name="Order rail shuttle"},
  rail_order_block={name="Order block-signal pilot"},
  rail_order_span={name="Order train through spans"}}
local rail_spans={rail_span_bridge={name="Timber rail bridge"},rail_span_tunnel={name="Rail tunnel"},
  rail_span_clear={name="Remove rail span"}}
local function rail_span_tiles(p)
  local ids={p.start}
  for _,id in ipairs(p.middle) do ids[#ids+1]=id end
  ids[#ids+1]=p["end"]
  return ids
end
local function rail_span_quote(n,V,id)
  local tool=V.tool
  local api_span=api.rail_spans
  if tool=="rail_span_bridge" then
    if not V.anchor then return nil,"Click the first bridge abutment.",true end
    return api_span.quote_bridge(S,n,V.anchor,id)
  elseif tool=="rail_span_tunnel" then
    return api_span.quote_tunnel(S,n,id)
  elseif tool=="rail_span_clear" then
    local span=api_span.by_portal(S,id)
    if not span or span.owner~=n then return nil,"Choose a portal of your rail bridge or tunnel." end
    return span
  end
end
local function rail_order_target(n,V,id)
  local cell=S.tiles[id]
  if not V.anchor then
    return cell.owner==n and cell.rail_depot_dir~=nil,"Click your rail depot first."
  end
  local st=cell.rail_station_id
  if not st or cell.owner~=n then return false,"Choose an owned rail platform." end
  if V.rail_first==st then return false,"The second platform must be different." end
  return true,V.rail_first and "Choose the second platform." or "Click first destination platform."
end
function U.clear_rail_run(p)
  local n=p:get_player_name()
  local V=view(n)
  if not api.rail_build then return end
  if api.authority_handoff then
    worker_action(n,V,{kind="transport_start",mode="rail_pilot",clear=true},function(ok)
      if ok then V.anchor,V.rail_first=nil,nil end
    end)
    return
  end
  local ok,msg=api.rail_build.clear_order(n)
  V.status=msg
  if ok then V.anchor=nil;V.rail_first=nil end
end
function U.cancel_build_selection(p)
  local V=view(p:get_player_name())
  if V.tool=="ship_order" and V.ferry_depot then
    V.ferry_depot,V.ferry_first,V.ferry_via=nil,nil,nil
    V.status="Ferry orders canceled."
    return true
  end
  local rail=rail_tool_labels[V.tool] or rail_spans[V.tool]
  local tram=V.tool=="tram_order" or V.tool=="tram_track"
  if not V.anchor or not (rail or tram or bridge_tool(V.tool) or V.tool=="road" or V.tool=="oneway_drag"
      or landscape_tools[V.tool] or structure_request(V)) then return false end
  V.anchor,V.rail_ghost,V.tram_first=nil,nil,nil
  V.status=rail and "Rail selection canceled." or "Build selection canceled."
  return true
end
U.cancel_rail_selection=U.cancel_build_selection
local function rail_point(id,hit)
  local x,z=Sim.xy(id)
  local function pixel(value,tile)
    if not value then return tile*16+8 end
    return math.max(tile*16,math.min(tile*16+15,math.floor((value+.5)*8)))
  end
  return {x=pixel(hit and hit.x,x),z=pixel(hit and hit.z,z)}
end
-- OpenTTD 14.1 rail_gui.cpp: VPM_RAILDIRS starts on press; DDSP_PLACE_RAIL
-- dispatches the one-piece or snapped line command only on mouse-up.
function U.rail_gesture(tool)
  return tool=="rail_autotrack" and api.rail_build~=nil
end
function U.begin_autorail(p,id,hit)
  local V=view(p:get_player_name())
  if V.pick_order or not U.rail_gesture(V.tool) or not hit then return false end
  if api.worker_build and api.worker_build.begin_rail then api.worker_build.begin_rail(p:get_player_name()) end
  V.rail_press={id=id,point=rail_point(id,hit)}
  return true
end
function U.cancel_autorail(p)
  local V=view(p:get_player_name())
  if not V.rail_press then return end
  V.rail_press,V.rail_ghost=nil,nil
  if api.worker_build and api.worker_build.begin_rail then api.worker_build.begin_rail(p:get_player_name()) end
  V.status="Rail drag canceled."
end
function worker_action(n,V,command,complete)
  local client=api.worker_bridge_client
  if not client then V.status="The campaign worker is not ready.";return false end
  local function finish(ok,msg)
    V.status=msg or (ok and "Completed." or "Operation not accepted.")
    if complete then complete(ok) end
  end
  local sent,why=client.query({kind="company",player=n},function(r)
    if not r.ok then finish(false,r.why);return end
    command.revision=r.revision
    local ok,message=client.query({kind="command",player=n,command=command},function(result)
      finish(result.ok,result.why)
    end)
    if not ok then finish(false,message) end
  end)
  if not sent then finish(false,why) end
  return not not sent
end
local tree_build_errors={
  TREE_ALREADY_HERE="This grove already has four trees.",
  TREE_PLANT_LIMIT_REACHED="Tree planting limit reached. Let the game advance.",
  CLEARING_LIMIT_REACHED="Clearing limit reached. Let the game advance.",
  CANT_BUILD_ON_WATER="Plant on land or a suitable shore, not open water.",
  SITE_UNSUITABLE="A structure, bridge, or unsuitable terrain blocks planting.",
  INVALID_TREE_TYPE="Choose a Temperate tree type.",
  TERRAIN_QUOTE_CHANGED="The landscape changed. Check the new planting area.",
  NOT_ENOUGH_MONEY="Not enough money for this construction.",
  MUST_FOUND_TOWN_FIRST="A town must exist before buying land.",
  BUILD_OBJECT_LIMIT_REACHED="Land-purchase limit reached. Let the game advance.",
  YOU_ALREADY_OWN_IT="Your company already owns this land.",
  OWNED_BY_ANOTHER="That land belongs to another company.",
  MUST_DEMOLISH_BRIDGE_FIRST="Remove the bridge above before buying.",
  TOO_CLOSE_TO_EDGE_OF_MAP="That land is beyond the playable map.",
}
local function worker_build(n,V,kind,request)
  if not api.authority_handoff then return false end
  if not api.worker_build then V.status="The campaign worker is not ready.";return true end
  V.status="Checking construction…"
  request=U.rail_gauge_request(V,kind,request)
  local ok,why=api.worker_build.commit(n,kind,request,function(built,note,quote,tiles)
    if not built and note and request.mode=="air" and api.airfield then note=api.airfield.reason(note) end
    if not built and note and request.kind=="dock" and api.shipyard then note=api.shipyard.reason(note) end
    if not built and (request.operation=="plant_tree" or request.operation=="purchase_land") then note=tree_build_errors[note] or note end
    V.status=note or (built and "Construction complete." or "That construction was not accepted.")
    if built and api.on_worker_build then api.on_worker_build(n,tiles,quote) end
    if kind=="terrain" and request.operation=="bulldoze" then
      if api.demolition_effects then api.demolition_effects.receipt(built,tiles,request.first) end
    elseif built and api.stock_audio then
      local id=request.first or request.tile or request.start and request.start.tile
      local host=id and R.host_tile and R.host_tile(id)
      local location
      if host then
        local x,z=Sim.xy(id)
        location={x=2*x+.5,y=(host.top or host.h or 0)+.6,z=2*z+.5}
      end
      api.stock_audio.construction(kind,request,n,location)
    end
  end)
  if not ok then V.status=why end
  return true
end
-- OpenTTD 16.0-RC1 ShowSelectBaseStationIfNeeded. The survey
-- auxiliary key fills the role of Ctrl without taking over movement.
function U.open_station_join_picker(p,V,request,mode)
  local is_dock,is_air,is_rail=mode=="dock",mode=="air",mode=="rail"
  local n=p:get_player_name()
  local client=api.worker_bridge_client
  if not client then V.status="The campaign worker is not ready.";return end
  local pending={request=request,tool=V.tool,selected=1,mode=mode}
  V.road_join_picker=pending
  V.status="Finding stations that can join…"
  local sent,why=client.query({kind=is_rail and "rail_join_choices" or is_air and "airport_join_choices" or is_dock and "dock_join_choices" or "road_join_choices",player=n,request=request},function(r)
    if session[n]~=V or V.road_join_picker~=pending then return end
    if V.tool~=pending.tool then V.road_join_picker=nil;return end
    if not r.ok then
      V.road_join_picker=nil;V.status=is_dock and api.shipyard.reason(r.why) or r.why
      return
    end
    pending.choices,pending.cost=r.value.choices,r.value.cost
    if (is_rail or is_air and not request.separate) and #pending.choices==1 then
      V.road_join_picker=nil
      worker_build(n,V,is_rail and "rail" or "transport",request)
      return
    end
    local labels={}
    for _,choice in ipairs(pending.choices) do labels[#labels+1]=esc(choice.name) end
    local title=is_rail and "Build rail platforms: choose station" or is_air and "Build an airport: choose station" or is_dock and "Join a dock station" or request.tool=="road_waypoint" and "Join a road waypoint" or "Join a road station"
    V.status="Choose a station or build separately."
    core.show_formspec(n,"luanttd_core:road_join_picker",
      "formspec_version[7]size[9,6.4]bgcolor[#152334;false]"..
      "label[.45,.40;"..title.."]label[.45,1.02;Construction: "..dollars(pending.cost).."]"..
      "textlist[.44,1.53;8.12,3.95;target;"..table.concat(labels,",")..";1;false]"..
      "button[4.68,5.61;1.73,.55;cancel;Cancel]button[6.79,5.61;1.73,.55;place;Build]")
  end)
  if not sent then V.road_join_picker=nil;V.status=why end
end
function U.road_join_picker_fields(p,f)
  local n=p:get_player_name()
  local V=view(n)
  local pending=V.road_join_picker
  if not pending or not pending.choices then return true end
  if f.quit or f.cancel then
    V.road_join_picker=nil;V.status="Construction canceled."
    if f.cancel then core.close_formspec(n,"luanttd_core:road_join_picker") end
    return true
  end
  local e=f.target and core.explode_textlist_event(f.target)
  if e and pending.choices[e.index] then pending.selected=e.index end
  if not (f.place or e and e.type=="DCL") then return true end
  local choice=pending.choices[pending.selected]
  if V.tool~=pending.tool or not choice then return true end
  V.road_join_picker=nil
  core.close_formspec(n,"luanttd_core:road_join_picker")
  local r=pending.request
  if pending.mode=="rail" then
    r.road_station_id,r.separate=choice.id,true
    worker_build(n,V,"rail",r)
  elseif pending.mode=="air" then
    r.air_join,r.separate=choice.id,choice.id==nil
    worker_build(n,V,"transport",r)
  elseif pending.mode=="dock" then
    r.join,r.picker_cost=choice.id,pending.cost
    worker_build(n,V,"transport",r)
  else
    r.join,r.join_picker_cost=choice.id,pending.cost
    worker_build(n,V,"road",r)
  end
  return true
end
function U.end_autorail(p,id,hit)
  local n=p:get_player_name()
  local V=view(n)
  if not V.rail_press or not U.rail_gesture(V.tool) then return end
  if not hit then U.cancel_autorail(p);return end
  local start=V.rail_press.point
  V.rail_press,V.rail_ghost=nil,nil
  local finish=rail_point(id,hit)
  if worker_build(n,V,"rail",{tool="autotrack",start=start,finish=finish}) then return end
  local plan,why=api.rail_build.quote_autotrack(n,start,finish)
  if not plan then V.status=why;return end
  local ok,msg=api.rail_build.build(n,plan)
  V.status=msg
  if ok then
    if plan.stopped_at then V.status=V.status.." Stopped before an obstruction." end
    if (plan.skipped_start or 0)>0 then
      V.status=V.status..(" Skipped %d obstructed at the start."):format(plan.skipped_start)
    end
    R.float(n,plan.ids[#plan.ids] or id,"−"..dollars(plan.price),0xf89171)
  end
end
local StationPlacement=api.road_first and dofile(core.get_modpath("luanttd_core").."/openttd/rail_station_placement.lua")
local function station_layout(V)
  return V.station_layout or StationPlacement.default
end
function U.open_station_layout(p)
  local n=p:get_player_name()
  local V=view(n)
  local l=station_layout(V)
  V.station_layout_open=true
  local numbers="1,2,3,4,5,6,7"
  core.show_formspec(n,"luanttd_core:station_layout",
    "formspec_version[7]size[10.4,6.1]bgcolor[#152334;false]"..
    "label[.4,.48;Rail station builder]"..
    "label[.4,1.12;Orientation]dropdown[.4,1.42;4.5,.62;rail_axis;East-West,North-South;"..(l.axis+1)..";true]"..
    "label[5.17,1.12;Placement]dropdown[5.17,1.42;4.82,.62;rail_place;Drag rectangle,Fixed size;"..(l.drag and 1 or 2)..";true]"..
    "label[.4,2.49;Number of tracks]dropdown[.4,2.81;4.5,.62;rail_count;"..numbers..";"..l.tracks..";true]"..
    "label[5.17,2.49;Platform length]dropdown[5.17,2.81;4.82,.62;rail_length;"..numbers..";"..l.length..";true]"..
    "label[.4,3.86;Fixed size uses the track and length settings.]"..
    "checkbox[.4,4.27;rail_separate;Build separate from adjacent station;"..tostring(l.separate or false).."]"..
    "button[.4,5.03;9.59,.69;rail_layout_apply;Use layout]")
  return true
end
function U.station_layout_fields(p,f)
  local n=p:get_player_name()
  local V=view(n)
  if not V.station_layout_open then return true end
  if f.quit then V.station_layout_open=nil;return true end
  if not f.rail_layout_apply then return true end
  local ax,dm=tonumber(f.rail_axis),tonumber(f.rail_place)
  local l=ax and (dm==1 or dm==2) and StationPlacement.layout(ax-1,dm==1,tonumber(f.rail_count),tonumber(f.rail_length),f.rail_separate=="true")
  if not l then return true end
  V.station_layout,V.station_layout_open=l,nil
  core.close_formspec(n,"luanttd_core:station_layout")
  U.status(p,l.drag and "Drag out the station footprint." or "Click the northwest tile of the station.")
  return true
end
function U.station_gesture(tool) return tool=="rail_platform" and api.rail_build and api.rail_build.quote_station~=nil end
function U.begin_station(p,id)
  local V=view(p:get_player_name())
  if not U.station_gesture(V.tool) or V.pick_order then return false end
  V.anchor=id
  return true
end
function U.cancel_station(p)
  local V=view(p:get_player_name())
  if V.anchor then V.anchor=nil;V.status="Station placement canceled." end
end
function U.end_station(p,id)
  local n=p:get_player_name()
  local V=view(n)
  local first=V.anchor
  V.anchor=nil
  if not first or not U.station_gesture(V.tool) then return end
  local layout=station_layout(V)
  if api.authority_handoff then
    U.open_station_join_picker(p,V,{tool="station",first=first,last=id,axis=layout.axis,
      length=layout.length,tracks=layout.tracks,separate=layout.separate,drag=layout.drag},"rail")
    return
  end
  local plan,why=api.rail_build.quote_station(n,first,id,layout)
  if not plan then V.status=why;return end
  local ok,msg=api.rail_build.build(n,plan)
  V.status=msg
  if ok and R.float then R.float(n,first,"−"..dollars(plan.price),0xf89171) end
end
function U.rail_overlay(p,id)
  local V=view(p:get_player_name())
  if V.tool~="rail_autotrack" or not id or V.pick_order or
      api.owned_rail_ui and api.owned_rail_ui.active(p) then return end
  local ghost=V.rail_ghost
  if ghost and ghost.id==id then return ghost.pieces end
end
local function quote_rail(p,n,V,id)
  local r=api.rail_build
  local tool=V.tool
  local code=rail_tool_code[tool]
  local d=V.rail_dir or 2
  if code~=nil then
    if code<2 and not V.anchor then return nil,"Mark first tile of the straight railway.",true end
    return r.quote_track(n,V.anchor or id,id,code,not not V.rail_remove)
  elseif tool=="rail_platform" then
    if not V.anchor then return nil,"Mark first end of the railway platform.",true end
    return r.quote_platform(n,V.anchor,id,d)
  elseif tool=="rail_depot_tool" then return r.quote_depot(n,id,U.rail_depot_request(p,V,id).direction)
  elseif tool=="rail_signal_remove" then return r.quote_remove_signal(n,id)
  else return r.quote_signal(n,id,d,tool=="rail_signal_oneway",tool=="rail_signal_block") end
end
local ship_order={name="Order ferry"}
local ship_coal_order={name="Order Yate coal ship"}
local function ship_coal_target(n,V,id)
  local controller=api.ship_coal
  local state=controller and controller.status()
  if not state or state.owner~=n then return nil,"Buy a Yate in your ship depot first." end
  if state.cargo~="coal" and state.cargo~=1 then return nil,"Refit the Yate for coal in its depot first." end
  if state.mine then return nil,"Inspect the ship depot to control your active coal service." end
  local part=S.tiles[id].ship
  if not part or part.kind~="dock" or part.owner~=n then return nil,"Choose one of your docks." end
  if V.ship_coal_first==part.station then return nil,"Choose a different dock for the power station order." end
  local report=controller.dock(part.station)
  if not report then return nil,"This dock has no active coal catchment." end
  if V.ship_coal_first and not report.accepts then return nil,"This dock does not accept at a power station." end
  if not V.ship_coal_first and report.sources and #report.sources==0 then return nil,"Choose a dock serving the mine." end
  return part.station,V.ship_coal_first and "Pick the power station dock." or "Click the coal mine loading dock."
end
local function ship_order_target(n,V,id)
  if api.shipyard.current() then return nil,"Clear the existing ferry before ordering another." end
  local part=S.tiles[id].ship
  if not V.ferry_depot then
    local valid=part and part.owner==n and part.depot
    if valid and api.passenger_ferry and not api.passenger_ferry.staged(n,valid) then
      return nil,"Inspect this depot and buy a passenger ferry first."
    end
    return valid,valid and "Click your ship depot." or "Choose one of your two-tile ship depots."
  end
  if V.ferry_first and part and part.kind=="buoy" then
    return id,"Click this public buoy to sail via it without stopping.","buoy"
  end
  if not part or part.kind~="dock" or part.owner~=n then
    return nil,V.ferry_first and "Choose the second dock or a public buoy." or "Choose one of your docks."
  end
  if V.ferry_first==part.station then return nil,"Choose a different dock for the second order." end
  return part.station,V.ferry_first and "Pick the second dock." or "Click the first dock."
end
function U.clear_ship_run(p)
  if not api.shipyard then return end
  local n=p:get_player_name()
  local V=view(n)
  if api.authority_handoff then
    worker_action(n,V,{kind="transport_start",mode="ship",clear=true},function(ok)
      if ok then V.ferry_depot,V.ferry_first,V.ferry_via=nil,nil,nil end
    end)
    return
  end
  local ok,msg=api.shipyard.clear(n)
  if ok then V.ferry_depot,V.ferry_first,V.ferry_via=nil,nil,nil end
  V.status=msg
end
local airfield_tools={airfield_build={name="Build country airfield"},city_airport_build={name="Build City Airport",layout="city"},
  commuter_airport_build={name="Build Commuter Airport",layout="commuter"},
  international_airport_build={name="Build International Airport",layout="international"},
  intercontinental_airport_build={name="Build Intercontinental Airport",layout="intercontinental"},
  metropolitan_airport_build={name="Build Metropolitan Airport",layout="metropolitan"},
  heliport_build={name="Build Heliport",layout="heliport"},helidepot_build={name="Build Helidepot",layout="helidepot"},
  helistation_build={name="Build Helistation",layout="helistation"},airfield_remove={name="Dismantle airfield"}}
local airfield_order={name=S.air_owned_preview and "Order aircraft" or "Order trimotor"}
local function airport_order_target(n,V,id)
  if not S.air_fleet_preview and api.airfield.current() then
    return nil,S.air_owned_preview and "This aircraft already has its route." or "Clear the active flight before ordering another."
  end
  local field=api.airfield.network.airport_for(S,id)
  if not field or field.owner~=n then return nil,"Choose one of your airfields." end
  if field.id==V.airport_first then return nil,"The destination must be a different airfield." end
  if S.air_owned_preview and not V.airport_first then
    local unit=api.airfield.owned(field.id)
    if not unit or unit.owner~=n then return nil,"Select an airfield with one of your purchased aircraft." end
    if unit.status~="hangar" then return nil,"This aircraft already has its route." end
  end
  return field,V.airport_first and "Click a destination airfield. The aircraft will fly both ways." or
    "Click your departure airfield."
end
function U.clear_airfield_run(p)
  if not api.airfield then return end
  local n=p:get_player_name()
  local V=view(n)
  if api.authority_handoff then
    worker_action(n,V,{kind="transport_start",mode="air",clear=true},function(ok)
      if ok then V.airport_first=nil end
    end)
    return
  end
  local ok,msg=api.airfield.clear(n)
  if ok then V.airport_first=nil end
  V.status=msg
end
local fixed_route_titles={rail_order_one="Depot-to-platform pilot orders",rail_order_shuttle="Rail shuttle pilot orders",
  rail_order_block="Block-signal pilot orders",rail_order_span="Rail span pilot orders",ship_order="Ferry orders",
  ship_coal_order="Coal ship orders",airfield_order="Aircraft orders",tram_order="Streetcar orders"}
function U.begin_fixed_route(p,tool)
  local title=fixed_route_titles[tool]
  if not title then return end
  local V=view(p:get_player_name())
  V.anchor,V.rail_first,V.airport_first,V.ferry_depot,V.ferry_first,V.ferry_via,V.ship_coal_first,V.tram_first=
    nil,nil,nil,nil,nil,nil,nil,nil
  V.fixed_route={tool=tool}
  V.status=({ship_coal_order="Pick your designated coal loading dock.",
    airfield_order="Pick the departure airfield with your aircraft."})[tool] or "Pick your depot first."
  return title
end
function U.fixed_route_active(p) return view(p:get_player_name()).fixed_route~=nil end
function U.fixed_route_ready(p)
  local q=view(p:get_player_name()).fixed_route
  return q and q.pending~=nil
end
function U.cancel_fixed_route(p)
  local V=view(p:get_player_name())
  if not V.fixed_route then return end
  V.fixed_route=nil
  U.select_tool(p,"inspect")
  V.status="Route setup canceled. No vehicle was dispatched."
end
local function stage_fixed_destination(V,id)
  if not V.fixed_route or V.fixed_route.confirming then return false end
  V.fixed_route.pending=id
  V.status="Destination selected. Choose Dispatch to start, or pick a different destination."
  return true
end
function U.confirm_fixed_route(p)
  local V=view(p:get_player_name())
  local q=V.fixed_route
  if not q then return end
  if not q.pending then V.status="Pick all required terminals before dispatch.";return end
  q.confirming=true
  U.build_world(p,q.pending)
  q.confirming=nil
end
local function airfields(s,name,tool,origin,quote)
  if tool=="airfield_remove" then
    return api.airfield.network.remove(s,name,origin,quote,api.airfield.busy)
  end
  local field,why,bad
  local layout=airfield_tools[tool].layout
  if quote then field,why,bad=api.airfield.network.quote(s,name,origin,layout)
  else field,why,bad=api.airfield.network.build(s,name,origin,layout) end
  if not field then return nil,why,bad end
  local tiles={}
  for i,tile in ipairs(field.tiles) do tiles[i]=tile.id end
  return tiles,field.price,field.ground/8
end
-- Use the same ownership/occupancy-aware demolition authority regardless of
-- the active construction toolbar. Do not clear a span or descriptor by
-- erasing one tile record; the specialised command owns the entire structure.
local clear_structure=dofile(moddir.."/demolition_structures.lua")(api,aquatic_remove,dollars)

U.signal_ui=api.road_first and dofile(core.get_modpath("luanttd_core").."/rail_signal_ui.lua")(api,U.status)
function U.signal_arrow(p,id,hit)
  if not U.signal_ui or not api.rail_build or not id then return end
  local V=view(p:get_player_name())
  if V.pick_order or not U.signal_ui.tool(V.tool) then return end
  local q,_,dir=U.signal_ui.preview(p,V.tool,id,hit)
  if q then return dir end
end
U.layer_bulldozer=api.road_first and dofile(core.get_modpath("luanttd_core").."/layer_bulldozer.lua")(api,clear_structure,U.status)
local function clear_error(why)
  return why=="CLEARING_LIMIT_REACHED" and "Clearing limit reached. Let the game advance." or why
end
function U.tree_gesture(tool)
  return api.authority_handoff and (tool=="landscape_plant_tree" or tool=="landscape_purchase_land")
end
function U.begin_tree(p,id)
  local v=view(p:get_player_name())
  if not U.tree_gesture(v.tool) or v.pick_order then return false end
  v.tree_press=id
  return true
end
function U.cancel_tree(p)
  local v=view(p:get_player_name())
  v.tree_press=nil
  v.status=v.tool=="landscape_purchase_land" and "Land purchase canceled." or "Tree planting canceled."
end
local function tree_request(p,v,id)
  local land=v.tool=="landscape_purchase_land"
  return {operation=land and "purchase_land" or "plant_tree",first=v.tree_press or id,last=id,
    species=not land and (v.tree_species or 255) or nil,diagonal=p:get_player_control().aux1==true}
end
function U.end_tree(p,id)
  local n=p:get_player_name()
  local v=view(n)
  if not v.tree_press then return end
  local request=tree_request(p,v,id)
  v.tree_press=nil
  if U.tree_gesture(v.tool) then worker_build(n,v,"terrain",request) end
end
local function clear_ticket(q)
  local noun=q.passed==1 and " tile" or " tiles"
  local text=("%s  ·  %d%s"):format(dollars(q.cost),q.passed,noun)
  if q.skipped>0 then text=text.."  ·  "..q.skipped.." skipped" end
  if q.extra>0 then text=text.."  ·  Next costs "..dollars(q.extra)
  elseif q.limit_reached then text=text.."  ·  Clearing limit reached" end
  return text
end
function U.begin_demolition(p,id)
  local V=view(p:get_player_name())
  if V.pick_order or V.tool~="clear" or not Sim.clear_area then return false end
  V.demolition_anchor=id
  return true
end
function U.cancel_demolition(p)
  local V=view(p:get_player_name())
  if not V.demolition_anchor then return false end
  V.demolition_anchor=nil
  V.status="Demolition canceled."
  return true
end
function U.end_demolition(p,id,diagonal)
  local n=p:get_player_name()
  local V=view(n)
  local start=V.demolition_anchor
  V.demolition_anchor=nil
  if not start or V.tool~="clear" then return end
  if api.authority_handoff and start~=id then
    worker_build(n,V,"terrain",{operation="bulldoze",first=start,last=id,diagonal=diagonal==true})
    return
  end
  if api.authority_handoff then
    if U.layer_bulldozer then
      U.layer_bulldozer.open(p,id,function()
        worker_build(n,V,"terrain",{operation="bulldoze",first=id})
      end)
    end
    return
  end
  if start==id then
    if U.layer_bulldozer and U.layer_bulldozer.open(p,id) then return end
  end
  local q,why=Sim.clear_area(S,n,start,id,diagonal,true)
  if not q then V.status=clear_error(why);return end
  V.status=(q.passed==0 and "Nothing cleared  ·  " or "Bulldozed  ·  ")..clear_ticket(q)
  if #q.dirty>0 then R.update(q.dirty) end
  if q.passed>0 then
    if api.demolition_effects then api.demolition_effects.receipt(true,q.dirty,start) end
    api.save()
  end
end
-- OpenTTD 16.0-RC1 road_gui.cpp: dedicated sizing pins the axis after
-- pointer-down, while AutoRoad chooses from the pointer coordinates.
local fixed_road_axes={road_axis_x=0,road_axis_y=1}
local fixed_road_labels={road_axis_x="East–west road",road_axis_y="North–south road",road_remove="Remove road",tram_track="Lay tramway",tram_remove="Remove tram track",road_stop_remove="Remove road stop",road_waypoint="Road waypoint",road_waypoint_remove="Remove road waypoint"}
local function road_gesture_op(tool)
  return tool=="oneway_drag" and "oneway" or tool=="road_remove" and "remove" or tool=="tram_remove" and "tram_remove" or tool=="tram_track" and "tram_lay" or "drag"
end
function U.waypoint_tool(tool)
  return tool=="road_waypoint" or tool=="road_waypoint_remove"
end
function U.waypoint_request(p,tool,first,last)
  -- The projected tile may be behind a worker edit. The authority locks
  -- the drag perpendicular to the current pavement, not this scene.
  return {tool="road_waypoint",first=first,last=last,remove=tool=="road_waypoint_remove",
    separate=p:get_player_control().aux1==true}
end
function U.road_gesture(tool,p)
  return S.corner_grid and (U.road_stop_gesture(p,tool) or (tool=="tram_remove" or tool=="tram_track") and (api.tram or api.authority_handoff) or tool=="road" or tool=="road_remove" or U.waypoint_tool(tool) or fixed_road_axes[tool]~=nil or tool=="oneway_drag" and api.oneway_tools)
end
function U.begin_autoroad(p,id,hit)
  local V=view(p:get_player_name())
  if V.pick_order or not U.road_gesture(V.tool,p) or not hit then return false end
  V.road_press={id=id,hit=hit}
  return true
end
function U.cancel_autoroad(p)
  local V=view(p:get_player_name())
  if not V.road_press then return end
  V.road_press=nil
  V.status="Road drag canceled."
end
local function autoroad_args(V,id,hit)
  return Sim.autoroad_selection(V.road_press.id,V.road_press.hit,id,hit,fixed_road_axes[V.tool])
end
local function autoroad_bend(p,V,start,last)
  if V.tool~="road" or not p:get_player_control().aux1 then return false end
  local x,z=Sim.xy(start)
  local u,v=Sim.xy(last)
  return x~=u and z~=v
end
function U.commit_oneway(n,V,id,q)
  local ok,cost,dirty,plan=api.oneway.commit(S,n,q)
  if not ok then V.status=one_way_text(cost);return end
  local update,seen={},{}
  local function mark(i)
    if i and not seen[i] then update[#update+1]=i;seen[i]=true end
  end
  for _,tile in ipairs(dirty) do
    mark(tile)
    for d=1,4 do mark(Sim.adjacent(tile,d)) end
  end
  V.anchor=nil
  V.status=("%d road tiles updated  ·  %s"):format(#dirty,dollars(cost))
  if #plan.skipped>0 then V.status=V.status..("  ·  %d skipped"):format(#plan.skipped) end
  if cost>0 then R.float(n,id,"−"..dollars(cost),0xf89171) end
  R.update(update);api.save()
end
function U.end_autoroad(p,id,hit)
  local n=p:get_player_name()
  local V=view(n)
  if not V.road_press or not U.road_gesture(V.tool,p) then return end
  if not hit then U.cancel_autoroad(p);return end
  local first=V.road_press.id
  if U.road_stop_gesture(p,V.tool) then
    V.road_press=nil
    local req=U.road_stop_request(p,V,first,id)
    if req.adjacent then U.open_station_join_picker(p,V,req)
    else worker_build(n,V,"road",req) end
    return
  end
  if U.waypoint_tool(V.tool) then
    local req=U.waypoint_request(p,V.tool,first,id)
    V.road_press=nil
    if api.authority_handoff then
      if req.separate and not req.remove then U.open_station_join_picker(p,V,req)
      else worker_build(n,V,"road",req) end
      return
    end
    local q,why=Sim.road_waypoint_plan(S,n,req)
    if not q then V.status=why;return end
    local ok,note,tiles=Sim.apply_road_waypoint(S,n,q)
    V.status=note
    if ok then R.update(tiles);api.save() end
    return
  end
  local last,axis,start_half,end_half=autoroad_args(V,id,hit)
  V.road_press=nil
  local bend=autoroad_bend(p,V,first,id)
  if api.authority_handoff then
    worker_build(n,V,"road",bend and {tool="bend",first=first,last=id} or
      {tool=road_gesture_op(V.tool),first=first,last=last,axis=axis,start_half=start_half,end_half=end_half})
    return
  end
  if bend then
    local ok,note,ids=Sim.autoroad_bend_build(S,n,first,id)
    V.status=note
    if ok and #ids>0 then R.update(ids);api.save() end
    return
  end
  if V.tool=="oneway_drag" then
    local q,why=api.oneway.quote(S,n,first,last,axis,{start_half=start_half,end_half=end_half})
    if not q then V.status=one_way_text(why);return end
    U.commit_oneway(n,V,id,q)
    return
  end
  if V.tool=="tram_remove" or V.tool=="tram_track" then
    local tr=api.tram
    local req={tool=road_gesture_op(V.tool),first=first,last=last,axis=axis,start_half=start_half,end_half=end_half}
    local lay=V.tool=="tram_track"
    local plan=lay and tr.network.drag_plan or tr.network.remove_plan
    local q,why=plan(S,n,req,tr.busy_probe and tr.busy_probe() or tr.busy)
    if not q then V.status=tr.reason(why);return end
    local apply=lay and tr.network.apply_drag or tr.network.apply_remove
    local ok,note,ids=apply(S,n,q)
    V.status=note
    if ok then R.update(ids);api.save() end
    return
  end
  if V.tool=="road_remove" then
    local q,why=Sim.road_remove_plan(S,n,first,last,axis,start_half,end_half)
    if not q then V.status=Sim.road_removal_error(why);return end
    local ok,note,ids=Sim.apply_road_removal(S,n,q)
    V.status=note
    if ok then R.update(ids);api.save() end
    return
  end
  local ok,note,ids,q=Sim.autoroad_build(S,n,first,last,axis,start_half,end_half)
  V.status=ok and q.stopped_at and (note.." Stopped at an obstruction.") or note
  if ok and #ids>0 then R.update(ids);api.save() end
end
function U.order_picking(p)
  return view(p:get_player_name()).pick_order~=nil
end
local function order_stop_target(n,V,id)
  local v=S.fleet[V.pick_order]
  if not v or v.owner~=n then return nil,"This vehicle is no longer available." end
  if v.running or v.route then return nil,"Stop at a terminal before changing orders." end
  local t=id and S.tiles[id]
  local st=t and S.stations[t.station]
  local engine=Sim.vehicles[v.engine]
  if not st or st.owner~=n or st.mode~=engine.mode then
    return nil,engine.mode=="road" and v.cargo=="passenger" and "Choose one of your bus stops." or
      "Choose one of your compatible stops."
  end
  if S.road_economy and engine.mode=="road" and v.cargo=="passenger" and not Sim.road_stop_has(st,"bus") then
    return nil,"Buses need passenger stops, not loading stops."
  end
  if S.road_economy and engine.mode=="road" and Sim.road_freight_cargo(v.engine) and not Sim.road_stop_has(st,"truck") then
    return nil,"This vehicle needs a truck loading stop."
  end
  if #v.orders>=16 then return nil,"Limit of 16 orders." end
  local prior=v.orders[#v.orders]
  if prior and prior.station==st.id then return nil,"That stop is already last in the schedule." end
  return st,("Add stop %d: %s"):format(#v.orders+1,U.stop_label(st))
end
function U.choose_order_stop(p,id)
  local n=p:get_player_name()
  local V=view(n)
  if not V.pick_order then return end
  local st,hint=order_stop_target(n,V,id)
  if not st then V.order_feedback=hint;return end
  local ok,note=Sim.add_order(S,n,V.pick_order,st.id,"normal")
  V.order_feedback=note
  if ok then api.save() end
end
function U.finish_order_pick(p)
  local n=p:get_player_name()
  local V=view(n)
  local id=V.pick_order
  if not id then return end
  V.pick_order,V.order_feedback=nil,nil
  if api.world and api.world.end_order_selection then api.world.end_order_selection(p) end
  local v=S.fleet[id]
  if v and v.owner==n then
    V.service_note=("%d stop%s saved."):format(#v.orders,#v.orders==1 and "" or "s")
    U.service(p,"vehicle",id)
  end
end
local function authority_preview(p,id,hit)
  local n=p:get_player_name()
  local V=view(n)
  local tool=V.tool
  local client=api.worker_build
  if not client then return {id},false,"Opening the simulation worker…" end
  local label=(Sim.tools[tool] and Sim.tools[tool].name) or rail_tool_labels[tool] or tool
  local kind,request,ids="road",nil,{id}
  local dock=ship_mode[tool]
  local bridge=bridge_tool(tool)
  local land=landscape_tools[tool]
  if tool=="inspect" then return end
  if tool=="teleport_tile" then return {id},true,"Teleport above this tile" end
  local freight=profile_stage_tools[tool]
  if freight then
    local st,hint=profile_stage_target(n,freight,id,true)
    return {id},st~=nil,hint
  end
  if bridge then
    if not V.anchor then return {id},true,"Click the first bridgehead. Right-click cancels." end
    local q,why=api.bridge_picker.quote(bridge,n,V.anchor,id,bridge=="rail" and V.rail_gauge or nil)
    return q and q.ids or {V.anchor,id},q~=nil,
      q and (bridge_label(bridge).." · From "..dollars(q.minimum).." · Choose a bridge type") or why
  end
  if U.signal_ui and U.signal_ui.tool(tool) then
    local q,hint=U.signal_ui.preview(p,tool,id,hit)
    return {id},q~=nil,hint
  end
  if U.road_stop_gesture(p,tool) and hit then
    local first=V.road_press and V.road_press.id or id
    request=U.road_stop_request(p,V,first,id)
    label=request.kind and road_terminal_label(request) or fixed_road_labels[tool]
    ids=first==id and {id} or {first,id}
    if request.kind and first~=request.last then
      local outline=V.road_stop_outline
      if not outline or outline.first~=first or outline.last~=request.last then
        local _,footprint=U.stop_area_geometry.footprint(Sim,first,request.last,request.direction,request.through,12)
        outline={first=first,last=request.last,ids=footprint}
        V.road_stop_outline=outline
      end
      ids=outline.ids
    elseif request.kind then ids={first} end
  elseif U.waypoint_tool(tool) and hit then
    local first=V.road_press and V.road_press.id or id
    label=fixed_road_labels[tool]
    request=U.waypoint_request(p,tool,first,id)
    ids={first,request.last}
  elseif U.road_gesture(tool,p) and hit then
    label=fixed_road_labels[tool] or label
    local press=V.road_press or {id=id,hit=hit}
    if autoroad_bend(p,V,press.id,id) then request={tool="bend",first=press.id,last=id}
    else
      local last,axis,first_half,last_half=Sim.autoroad_selection(press.id,press.hit,id,hit,fixed_road_axes[V.tool])
      request={tool=road_gesture_op(tool),first=press.id,last=last,
        axis=axis,start_half=first_half,end_half=last_half}
    end
    ids=Sim.line(request.first,request.last)
  elseif tool=="rail_autotrack" then
    local point=rail_point(id,hit)
    kind,request="rail",{tool="autotrack",start=V.rail_press and V.rail_press.point or point,finish=point}
  elseif rail_tool_code[tool]~=nil then
    local track=rail_tool_code[tool]
    if track<2 and not V.anchor then return ids,true,"Mark the first end of the straight railway." end
    kind,request="rail",{tool="track",first=V.anchor or id,last=id,track=track,remove=V.rail_remove==true}
  elseif electric_tools[tool]~=nil then
    if not V.anchor then return ids,true,"Click the first corner. Right-click cancels." end
    kind,request="rail",{tool="wire",first=V.anchor,last=id,target=electric_tools[tool]}
  elseif U.station_gesture(tool) then
    local l=station_layout(V)
    kind,request="rail",{tool="station",first=V.anchor or id,last=id,axis=l.axis,
      tracks=l.tracks,length=l.length,separate=l.separate,drag=l.drag}
  elseif tool=="rail_depot_tool" then
    kind,request="rail",U.rail_depot_request(p,V,id)
    label=label.." · Door faces "..tram_dir[request.direction]
  elseif tool=="rail_crossing_tool" or tool=="rail_waypoint_place" then
    kind,request="rail",{tool=tool=="rail_crossing_tool" and "crossing" or "waypoint",first=id}
  elseif U.tree_gesture(tool) then
    kind,request="terrain",tree_request(p,V,id)
    label=tool=="landscape_purchase_land" and "Buy land" or tree_species_name(V.tree_species)
    if request.first~=id then
      local ax,az=Sim.xy(request.first)
      local bx,bz=Sim.xy(id)
      -- Use the stock area iterator for the immediate, neutral gesture
      -- preview. The worker still decides which tiles can be purchased.
      if (math.abs(bx-ax)+1)*(math.abs(bz-az)+1)<=256 then
        if not U.tree_area_geometry then
          U.tree_area_geometry=dofile(core.get_modpath("luanttd_core").."/openttd/landscaping.lua")({
            corner=function(_,x,z) return Sim.id(x,z) end,
          })
        end
        -- Owned-land and tree commands iterate from the release tile.
        ids={}
        for x,z in U.tree_area_geometry.points({},bx,bz,ax,az,request.diagonal) do
          ids[#ids+1]=Sim.id(x,z)
        end
      end
    end
  elseif land then
    label=land.name
    if land.area and not V.anchor then return ids,true,"Mark the first terrain corner." end
    kind,request="terrain",{operation=land.mode,first=V.anchor or id,last=land.area and id or nil,
      diagonal=p:get_player_control().aux1==true}
  elseif tool=="clear" then
    if not V.demolition_anchor or V.demolition_anchor==id then return ids,true,"Bulldoze · Click to review layers or drag an area." end
    kind,request="terrain",{operation="bulldoze",first=V.demolition_anchor,last=id,diagonal=p:get_player_control().aux1==true}
  elseif tool=="fund_bank" then
    label="Fund Bank";request={tool=tool,first=id}
  elseif road_terminal_kind[tool] or tool=="road_bay_pair" then
    request=road_terminal_request(V,id) or U.road_auto_terminal(p,tool,id) or {tool=tool,first=id}
    if request.tool=="stock_terminal" then label=road_terminal_label(request)
    elseif request.tool=="stock_terminal_auto" then label=road_terminal_title[request.kind].." · Auto orientation" end
  elseif dock=="dock" or dock=="depot" or tool=="ship_buoy" then
    kind,request="transport",{mode="ship",operation="build",kind=dock or "buoy",tile=id,axis=U.ship_depot_axis(p,V,dock)}
    if dock=="depot" then label="Ship depot"..(request.axis==0 and " · East–West" or " · North–South") end
    if dock=="dock" then
      request.adjacent=tool=="ship_join_dock" or p:get_player_control().aux1==true
      if request.adjacent then label="Dock · Choose station" end
    end
  elseif dock=="lock" or dock=="canal" or dock=="aqueduct" then
    if dock~="lock" and not V.anchor then return ids,true,"Mark the first waterway tile." end
    kind,request="transport",{mode="ship",operation="waterwork",kind=dock,tile=V.anchor or id,last=id}
  elseif airfield_tools[tool] and tool~="airfield_remove" then
    label=airfield_tools[tool].name
    local separate=p:get_player_control().aux1==true
    if separate then label=label.." · Choose station" end
    kind,request="transport",{mode="air",operation="build",tile=id,layout=airfield_tools[tool].layout,separate=separate}
  elseif tool=="structure_tunnel" or tool=="rail_span_tunnel" then
    kind,request="transport",{mode=tool=="rail_span_tunnel" and "rail" or "road",operation="tunnel",tile=id}
  else
    local tram,cells,direction,face=tram_request(p,V,id)
    if tram then
      if tool=="tram_track" and not V.anchor then return ids,true,"Mark the first tramway tile." end
      if tool=="tram_depot" then label="Tram depot" end
      if face then label=label.." · "..face end
      if tool=="tram_track" then
        kind,request="transport",{mode="tram",operation="build",kind=tram,cells=cells,direction=direction}
      else
        request={tool="tram_facility",first=id,kind=tram,direction=direction}
      end
    end
  end
  if not request then return ids,false,label end
  request=U.rail_gauge_request(V,kind,request)
  if request.railtype==2 or request.railtype==3 then
    label=(request.railtype==3 and "Maglev" or "Monorail").." · "..label
  end
  local q,why,pending=client.preview(n,kind,request,core.get_us_time())
  if tool=="rail_autotrack" then V.rail_ghost=q and {id=id,pieces=q.draw and {records=q.draw} or q.pieces} or nil end
  -- A new hover is neither approved nor obstructed. Don't flash red
  -- while the worker validates the shape the player just selected.
  if not q then
    local tram=request.mode=="tram" or request.tool=="tram_facility"
    if (kind=="road" or tool=="rail_autotrack" or tram or request.mode=="air" or request.operation=="plant_tree" or
        request.operation=="purchase_land" or request.operation=="company_hq") and pending then return ids,nil,why end
    if tram and api.tram and why then why=api.tram.reason(why) end
    if request.mode=="air" and api.airfield and why then why=api.airfield.reason(why) end
    if request.operation=="plant_tree" or request.operation=="purchase_land" then why=tree_build_errors[why] or why end
    if request.operation=="company_hq" and why then
      local labels={OWNED_BY_ANOTHER="Another company owns part of this site.",PROTECTED_TILE="Choose a clear, unoccupied site.",
        CAN_T_BUILD_ON_WATER="All four parcels must be on land.",FLAT_LAND_REQUIRED="Choose four tiles at the same foundation height.",
        ALREADY_BUILT="Your headquarters already stands here.",NOT_ENOUGH_CASH="Your company cannot afford this site.",
        TOO_CLOSE_TO_EDGE_OF_MAP="The entire 2×2 site must fit inside the map."}
      why=labels[why] or tree_build_errors[why] or why
    end
    return ids,false,why
  end
  local cells=q.tiles or ids
  if request.tool=="stock_terminal_auto" and q.depot_direction~=nil then
    label="Road depot · Door faces "..tram_dir[q.depot_direction]
  end
  local description=("%s  |  %s  ·  %d tile%s"):format(label,dollars(q.cost or 0),#cells,#cells==1 and "" or "s")
  if request.mode=="air" and q.noise then
    local a=q.noise
    description=description..("  ·  %s noise: %d → %d / %d"):format(a.name,a.used,a.used+a.add,a.limit)
  end
  return cells,true,description
end
function U.preview(p,id,hit)
  if api.authority_handoff then return authority_preview(p,id,hit) end
  if api.owned_rail_ui and api.owned_rail_ui.active(p) then return api.owned_rail_ui.preview(p,id) end
  local n=p:get_player_name()
  local V=view(n)
  if V.pick_order then
    local target,hint=order_stop_target(n,V,id)
    return {id},not not target,hint
  end
  if V.tool=="teleport_tile" then return {id},true,"Teleport above this tile" end
  local oriented=road_terminal_request(V,id)
  if oriented then
    local q,why=Sim.stock_road_terminal_plan(S,n,id,{kind=oriented.kind,dir=oriented.direction,through=oriented.through})
    if not q then return {id},false,Sim.stock_road_terminal_error(why) end
    local ids={}
    for _,e in ipairs(q.changes) do ids[#ids+1]=e.id end
    return ids,true,road_terminal_label(oriented).."  |  "..dollars(q.cost)
  end
  if U.waypoint_tool(V.tool) and hit then
    local q,why=Sim.road_waypoint_plan(S,n,U.waypoint_request(p,V.tool,V.road_press and V.road_press.id or id,id))
    if not q then return {id},false,why end
    local ids={}
    for i,e in ipairs(q.changes) do ids[i]=e.id end
    return ids,true,fixed_road_labels[V.tool].."  |  "..dollars(q.cost)
  end
  if (V.tool=="tram_remove" or V.tool=="tram_track") and api.tram and hit then
    local tr=api.tram
    local press=V.road_press or {id=id,hit=hit}
    local last,axis,a,b=Sim.autoroad_selection(press.id,press.hit,id,hit)
    local plan=V.tool=="tram_track" and tr.network.drag_plan or tr.network.remove_plan
    local q,why=plan(S,n,{first=press.id,last=last,axis=axis,start_half=a,end_half=b},
      tr.busy_probe and tr.busy_probe() or tr.busy)
    if not q then return {id},false,tr.reason(why) end
    local ids={}
    for i,e in ipairs(q.changes) do ids[i]=e.id end
    return ids,true,fixed_road_labels[V.tool].."  |  "..dollars(q.cost)
  end
  if api.road_first and U.road_gesture(V.tool,p) and hit then
    local press=V.road_press or {id=id,hit=hit}
    if autoroad_bend(p,V,press.id,id) then
      local q,why,path=Sim.autoroad_bend_plan(S,n,press.id,id)
      if not q then return path or {id},false,why end
      return q.path,true,("Road bend  |  %s  ·  %d new tiles  ·  Release to build"):format(dollars(q.cost),#q.changes)
    end
    local last,axis,start_half,end_half=Sim.autoroad_selection(press.id,press.hit,id,hit,fixed_road_axes[V.tool])
    if V.tool=="oneway_drag" then
      local q,why=api.oneway.quote(S,n,press.id,last,axis,{start_half=start_half,end_half=end_half})
      if not q then return Sim.line(press.id,last),false,one_way_text(why) end
      local ids={}
      for _,edit in ipairs(q.changes) do ids[#ids+1]=edit.tile end
      return ids,q.affordable,("One-way road  |  %s  ·  %d tiles%s"):format(dollars(q.cost),#ids,
        not V.road_press and "  ·  Hold and drag in travel direction" or
        q.stopped_at and "  ·  Stops at an obstruction" or "")
    end
    if V.tool=="road_remove" then
      local q,why=Sim.road_remove_plan(S,n,press.id,last,axis,start_half,end_half)
      if not q then return Sim.line(press.id,last),false,Sim.road_removal_error(why) end
      local ids={}
      for i,edit in ipairs(q.changes) do ids[i]=edit.id end
      return ids,true,("Remove road  |  %s  ·  %d tiles"):format(dollars(q.cost),#ids)
    end
    local q,why=Sim.autoroad_plan(S,n,press.id,last,axis,start_half,end_half)
    local path=Sim.line(press.id,last)
    if not q then return path,false,why end
    local info=q.stopped_at and "  ·  Stops at an obstruction" or
      (fixed_road_labels[V.tool] and "  ·  Axis locked") or
      (not V.road_press and "  ·  Drag straight · E for a bend" or "  ·  Hold E for a bend")
    return q.ids,true,("%s  |  %s  ·  %d tiles%s"):format(fixed_road_labels[V.tool] or "AutoRoad",dollars(q.cost),#q.ids,info)
  end
  if api.road_first and V.tool=="clear" then
    if V.demolition_anchor and V.demolition_anchor~=id and Sim.clear_area then
      local diagonal=p:get_player_control().aux1==true
      local q,why=Sim.clear_area(S,n,V.demolition_anchor,id,diagonal,false)
      if not q then return {V.demolition_anchor,id},false,clear_error(why) end
      return #q.ids>0 and q.ids or {V.demolition_anchor,id},q.passed>0,
        (diagonal and "Diagonal demolition  |  " or "Area demolition  |  ")..clear_ticket(q)
    end
    local choices=U.layer_bulldozer.choices(n,id)
    if #choices>0 then return {id},true,"Bulldozer  |  Click to review removable layers" end
    if S.corner_grid and Sim.clear_area then
      local q,why=Sim.clear_area(S,n,id,id,false,false)
      return {id},q and q.passed>0 or false,
        q and ("Bulldoze  |  "..clear_ticket(q).."  ·  Click or hold to drag") or clear_error(why)
    end
  end
  local bridge=bridge_tool(V.tool)
  if bridge then
    if not V.anchor then return {id},true,"Click the first bridgehead. Right-click cancels." end
    local q,why=api.bridge_picker.quote(bridge,n,V.anchor,id,bridge=="rail" and V.rail_gauge or nil)
    if not q then return {V.anchor,id},false,why or "No bridge can join these heads." end
    return q.ids or {V.anchor,id},true,bridge_label(bridge)..
      (q.minimum and ("  |  From "..dollars(q.minimum)) or "").."  ·  Click to choose a bridge type."
  end
  if electric_tools[V.tool]~=nil and api.electric_tools then
    if electric_tools[V.tool]==1 and not api.electric_available(n) then return {id},false,wire_errors.RAILTYPE_NOT_AVAILABLE end
    if not V.anchor then return {id},true,"Click the first corner. Right-click cancels." end
    local ticket,why,ids=wire_quote(n,V,id)
    return ticket and ticket.ids or ids or {id},ticket~=nil,
      ticket and (rail_tool_labels[V.tool].."  |  "..dollars(ticket.price)) or wire_error(why)
  end
  if V.tool=="ship_coal_order" and api.ship_coal_tools then
    local dock,why=ship_coal_target(n,V,id)
    return {id},dock~=nil,why
  end
  if V.tool=="truck_stop_tool" and api.freight_tools then
    if S.tiles[id].station then return {id},false,"Build a new truck stop rather than converting a station." end
    local plan,cost=Sim.plan(S,n,"road_station",{id})
    if not plan then return {id},false,cost end
    return {id},true,(plan[1] and plan[1].road_bits==0 and "Unconnected truck stop  |  "..dollars(cost)..
      "  ·  Connect a road before ordering trucks" or "Truck stop  |  "..dollars(cost))
  end
  if coal_stage_tools[V.tool] and api.rail_coal_tools then
    local st,hint=coal_stage_target(n,coal_stage_tools[V.tool],id)
    return {id},not not st,hint
  end
  if goods_stage_tools[V.tool] and api.rail_goods_tools then
    local st,hint=goods_stage_target(n,goods_stage_tools[V.tool],id)
    return {id},st~=nil,hint
  end
  if oil_stage_tools[V.tool] and api.rail_oil_tools then
    local st,hint=oil_stage_target(n,oil_stage_tools[V.tool],id)
    return {id},not not st,hint
  end
  if profile_stage_tools[V.tool] then
    local st,hint=profile_stage_target(n,profile_stage_tools[V.tool],id,false)
    return {id},st~=nil,hint
  end
  if V.tool=="oneway_drag" and api.oneway_tools then
    local q,why=one_way_quote(n,V,id)
    if not q then return {id},not V.anchor,why end
    local ids={}
    for _,edit in ipairs(q.changes) do ids[#ids+1]=edit.tile end
    local miss=#q.skipped
    return #ids>0 and ids or {id},q.affordable,
      ("One-way drag  |  %s  ·  %d tiles%s"):format(dollars(q.cost),#ids,
        miss>0 and ("  ·  "..miss.." skipped") or "")
  end
  if V.tool=="rail_crossing_tool" and api.crossing_tools then
    local q,why=crossing_quote(n,id)
    return {id},not not q,q and ("Level crossing  |  "..dollars(q.price)) or why
  end
  if rail_spans[V.tool] and api.rail_spans then
    local span,why,wait=rail_span_quote(n,V,id)
    if not span then return {id},wait==true,why end
    local span_tool=rail_spans[V.tool]
    local hint=V.tool=="rail_span_clear" and (span_tool.name.."  |  "..span.total_length.." tiles") or
      (span_tool.name.."  |  "..dollars(span.price).."  ·  "..span.total_length.." tiles")
    return rail_span_tiles(span),true,hint
  end
  if rail_orders[V.tool] and api.rail_build then
    local valid,hint=rail_order_target(n,V,id)
    return {id},valid,hint
  end
  if V.tool=="rail_autotrack" and api.rail_build then
    local current=rail_point(id,hit)
    local start=V.rail_press and V.rail_press.point or current
    local plan,why,path=api.rail_build.quote_autotrack(n,start,current)
    V.rail_ghost=plan and {id=id,pieces=plan.pieces} or nil
    local ids=plan and plan.ids or {}
    if not plan then
      for _,piece in ipairs(path or {}) do ids[#ids+1]=piece.id end
      if #ids==0 then ids[1]=id end
      return ids,false,why
    end
    local hint=V.rail_press and "Release to build · Right-click cancels" or "Click or hold to drag"
    if plan.stopped_at then hint="Stops before obstruction · "..hint end
    if plan.tree_count>0 then hint=("Clears %d trees · "):format(plan.tree_count)..hint end
    if (plan.skipped_start or 0)>0 then hint=("Skips %d at start · "):format(plan.skipped_start)..hint end
    return ids,true,("AutoRail  |  %s  ·  %d tiles  ·  %s"):format(dollars(plan.price),#plan.ids,hint)
  end
  if waypoint_tools[V.tool] then
    local plan,why=waypoint_quote(n,V.tool,id)
    return {id},plan~=nil,plan and (waypoint_tools[V.tool].."  |  "..dollars(plan.price)) or why
  end
  if U.station_gesture(V.tool) then
    local plan,why,preview=api.rail_build.quote_station(n,V.anchor or id,id,station_layout(V))
    if not plan then return preview and #preview>0 and preview or {id},false,why end
    local area=plan.area
    return plan.ids,true,("Rail station · %d tracks × %d tiles · %s"):format(area.tracks,area.length,dollars(plan.price))
      .. (plan.join and (" · Joins #%d"):format(plan.join) or " · Right-click for layout")
  end
  if U.signal_ui and api.rail_build and U.signal_ui.tool(V.tool) then
    local q,hint=U.signal_ui.preview(p,V.tool,id,hit)
    return {id},q~=nil,hint
  end
  if rail_tool_labels[V.tool] and api.rail_build then
    local plan,msg,anchor=quote_rail(p,n,V,id)
    if not plan then return {id},not not anchor,msg end
    local title=rail_tool_labels[V.tool]
    if plan.kind=="depot" then
      title=(plan.rotate and "Rotate depot" or title).."  ·  Door faces "..tram_dir[U.rail_depot_request(p,V,id).direction]
        ..(plan.foundation=="leveled" and "  ·  Level foundation" or "").."  ·  Right-click for direction"
    elseif plan.kind=="signal" then title=title.."  ·  Train travels "..tram_dir[V.rail_dir or 2] end
    if V.rail_remove and plan.kind=="track" then title="Remove "..title:lower() end
    return plan.ids,true,("%s  |  %s  ·  %d tiles"):format(title,dollars(plan.price),#plan.ids)
  end
  if buoy_tools[V.tool] and api.shipyard then
    local q,why=buoy_quote(n,V.tool,id)
    return {id},q~=nil,q and (buoy_tools[V.tool].."  |  "..dollars(q.cost)) or api.shipyard.reason(why,V.tool)
  end
  if V.tool=="ship_order" and api.shipyard then
    local valid,hint=ship_order_target(n,V,id)
    return {id},not not valid,hint
  end
  if V.tool=="airfield_order" and api.airfield then
    local field,hint=airport_order_target(n,V,id)
    local ids={}
    for _,record in ipairs(field and field.tiles or {}) do ids[#ids+1]=record.id end
    return field and ids or {id},not not field,hint
  end
  if airfield_tools[V.tool] and api.airfield then
    local tiles,price,bad=airfields(S,n,V.tool,id,true)
    if not tiles then
      local why=api.airfield.reason(price)
      if bad then
        local x,z=Sim.xy(bad)
        why=("Tile %d,%d: %s"):format(x,z,why)
      end
      local footprint=api.airfield.network.footprint
      return V.tool~="airfield_remove" and footprint and footprint(id,airfield_tools[V.tool].layout) or {id},false,why
    end
    return tiles,true,("%s  |  %s  ·  %d tiles"):format(airfield_tools[V.tool].name,dollars(price),#tiles)
  end
  local ship=ship_mode[V.tool]
  if ship and api.shipyard then
    if api.shipyard.busy() then return {id},false,"Clear the running ferry pilot before editing facilities." end
    if ship=="remove" then
      local tiles,cost=aquatic_remove(n,id,true)
      return tiles or {id},tiles~=nil,tiles and ("Dismantle complete structure  |  "..dollars(cost)) or api.shipyard.reason(cost)
    end
    if ship=="lock" then
      local plan,reason=api.waterworks.quote_lock(S,n,id)
      if not plan then return {id},false,api.shipyard.reason(reason) end
      return plan.dirty,true,"Three-tile lock  |  "..dollars(plan.cost)
    end
    if ship=="canal" then
      if not V.anchor then return {id},true,"Mark the first canal tile." end
      local plan,reason=api.waterworks.quote(S,n,V.anchor,id,false)
      if not plan then return {id},false,api.shipyard.reason(reason) end
      return plan.dirty,true,("Canal  |  %s  ·  %d tiles"):format(dollars(plan.cost),#plan.tiles)
    end
    if ship=="aqueduct" then
      if not V.anchor then return {id},true,"Mark the first aqueduct head." end
      local plan,reason=api.aqueduct.quote(S,n,V.anchor,id)
      if not plan then return {id},false,api.shipyard.reason(reason) end
      return ship_span(plan),true,("Aqueduct  |  %s  ·  %d tiles"):format(dollars(plan.price),plan.total_length)
    end
    local plan,reason=api.shipyard.network.quote(S,n,ship,id,U.ship_depot_axis(p,V,ship))
    if not plan then return {id},false,api.shipyard.reason(reason) end
    local label=ship=="dock" and "Dock" or ("Ship depot  ·  "..(plan.axis==0 and "East–West" or "North–South"))
    return plan.tiles,true,label.."  |  "..dollars(plan.cost)
  end
  if V.tool=="tram_order" and api.tram then
    local valid,hint=tram_order_target(n,V,id)
    return {id},not not valid,hint
  end
  local tram,tram_ids,direction,face=tram_request(p,V,id)
  if tram and api.tram then
    if V.tool=="tram_track" and not V.anchor then return tram_ids,true,"Mark start of tramway." end
    local proposed,price=api.tram.network.plan(S,n,tram,tram_ids,direction,api.tram.busy)
    if not proposed then return tram_ids,false,api.tram.reason(price) end
    if price>Sim.company(S,n).cash then return tram_ids,false,"Not enough cash." end
    local label=Sim.tools[V.tool].name..(face and ("  ·  "..face) or "")
    return tram_ids,true,("%s  |  %s  ·  %d tiles"):format(label,dollars(price),#proposed)
  end
  local structure=structure_request(V)
  if structure then
    if not api.structure_tools then return {id},false,"Structure tools are not enabled." end
    if structure~="tunnel" and not V.anchor then return {id},true,"Click to mark the first bridgehead." end
    local ok,price,p=structure_build(n,V,id,structure,true)
    if not ok then return {id},false,price end
    local tiles={p.start,p["end"]}
    for _,tile in ipairs(p.middle) do tiles[#tiles+1]=tile end
    return tiles,true,("%s  |  %s  •  %d tiles"):format(Sim.tools[V.tool].name,dollars(price),#tiles)
  end
  local mode,x,z,u,v,area,diagonal=landscape_request(V,id,p)
  if mode then
    if not api.terrain then return {id},false,"Shared terrain is disabled." end
    if area and not u then return {id},true,"Mark the first corner; its height sets the grade." end
    local valid,cost=Sim.landscape(S,n,mode,x,z,u,v,diagonal,true)
    local selection=area and ("Area %d,%d to %d,%d%s"):format(x,z,u,v,diagonal and " (diagonal)" or "") or
      ("Corner %d,%d"):format(x,z)
    local label=selection.."  |  "..(valid and dollars(cost) or cost)
    return area and api.landscape_tiles(x,z,u,v,diagonal) or {id},valid,label
  end
  if not Sim.tools[V.tool].price then return end
  local ids=V.anchor and Sim.linear[V.tool] and Sim.line(V.anchor,id,V.zfirst) or {id}
  local changes,cost=Sim.plan(S,n,V.tool,ids)
  if not changes then return ids,false,cost end
  local action=V.tool=="clear" and "Bulldoze" or Sim.linear[V.tool] and not V.anchor and "Mark start" or "Build"
  if #changes==0 then return ids,true,action.."   |   Already built" end
  if api.road_first and (V.tool=="road_station" or V.tool=="road_bay_pair") then
    local part=changes[1]
    local site=part and S.sites[part.station_site]
    local kind=V.tool=="road_bay_pair" and "Two-bay bus terminus" or
      part and (part.stop_axis and "Through bus stop" or part.road_bits==0 and "Unconnected bus stop") or "Bus stop"
    if part and part.road_bits==0 then
      return ids,true,kind.."  |  "..dollars(cost).."  ·  Connect a road before ordering buses"
    end
    local acceptance=Sim.road_passenger_acceptance and Sim.road_passenger_acceptance(S,id)
    if acceptance then
      return ids,true,("%s  |  %s  ·  %s"):format(kind,dollars(cost),
        acceptance>=8 and "Accepts passengers" or "No passenger acceptance here")
    end
    if site then return ids,true,("%s  |  %s  ·  Serves %s"):format(kind,dollars(cost),site.name) end
  elseif api.road_first and V.tool=="road_depot" then
    for _,edit in ipairs(changes) do
      if edit.id==id and edit.depot_dir then
        local side=({"north","east","south","west"})[edit.depot_dir]
        if side then return ids,true,"Road depot  |  "..dollars(cost).."  ·  Entrance: "..side end
      end
    end
    return ids,true,"Road depot    |    "..dollars(cost)
  end
  return ids,true,("%s   |   %s   •   %d tile%s"):format(action,dollars(cost),#changes,#changes==1 and "" or "s")
end
function U.is_world_tool(tool)
  if type(tool)~="string" or tool=="company" or tool=="jump" then return false end
  return not not (Sim.tools[tool] or rail_orders[tool] or rail_tool_labels[tool] or waypoint_tools[tool] or rail_spans[tool] or coal_stage_tools[tool] or
    (api.rail_oil_tools and oil_stage_tools[tool]) or (api.rail_goods_tools and goods_stage_tools[tool]) or profile_stage_tools[tool] or airfield_tools[tool] or ship_mode[tool] or buoy_tools[tool] or tram_mode[tool] or
    tool=="fund_bank" or tool=="teleport_tile" or tool=="tram_order" or tool=="airfield_order" or tool=="ship_order" or tool=="ship_coal_order" or tool=="truck_stop_tool" or tool=="rail_crossing_tool" or tool=="oneway_drag" or
    fixed_road_labels[tool] or U.tree_gesture(tool) or landscape_tools[tool] or bridge_tool(tool) or tool:match("^structure_"))
end
function U.stop_label(st)
  if st.freight_art and (api.timber_tools or api.farm_tools or api.oil_tools) then return "Truck stop #"..st.id end
  if st.coal_art then return "Coal stop #"..st.id end
  if st.stop_type=="truck" then return "Mail stop #"..st.id end
  if S.tiles[st.tile].road_stop_pair then return "Bus terminus #"..st.id end
  if st.mode=="road" then return "Bus stop #"..st.id end
  return st.name
end
function U.world_status(p,tile,show_preview,hit)
  local V=view(p:get_player_name())
  local tool=Sim.tools[V.tool] or (V.tool=="tram_order" and tram_order) or airfield_tools[V.tool] or rail_orders[V.tool] or rail_spans[V.tool] or coal_stage_tools[V.tool] or
    oil_stage_tools[V.tool] or goods_stage_tools[V.tool] or profile_stage_tools[V.tool] or landscape_tools[V.tool] or (V.tool=="airfield_order" and airfield_order) or (V.tool=="ship_order" and ship_order) or
    (buoy_tools[V.tool] and {name=buoy_tools[V.tool]}) or
    (V.tool=="ship_coal_order" and ship_coal_order) or
    (V.tool=="rail_crossing_tool" and crossing_tool) or (V.tool=="oneway_drag" and one_way_tool) or
    (rail_tool_labels[V.tool] and {name=rail_tool_labels[V.tool]}) or
    (waypoint_tools[V.tool] and {name=waypoint_tools[V.tool]}) or
    (V.tool=="fund_bank" and {name="Fund Bank"}) or
    (V.tool=="truck_stop_tool" and {name="Freight loading stop"}) or
    (V.tool=="teleport_tile" and {name="Teleport to tile"}) or
    (fixed_road_labels[V.tool] and {name=fixed_road_labels[V.tool]}) or
    (bridge_tool(V.tool) and {name=bridge_label(bridge_tool(V.tool))}) or Sim.tools.inspect
  if U.tree_gesture(V.tool) then
    tool={name=V.tool=="landscape_purchase_land" and "Buy land" or "Plant trees"}
  end
  local target="Aim at the ground"
  if tile and api.authority_handoff and R.host_tile then
    local a=R.host_tile(tile)
    local x,z=Sim.xy(tile)
    if a then
      local site=R.host_record and R.host_record("sites",a.site)
      local st=R.host_record and R.host_record("stations",a.station)
      local build=Sim.tools[a.build]
      target=("%d,%d  %s"):format(x,z,st and ("Station #"..st.id) or site and site.name or
        build and build.name or a.water_class=="river" and "River" or a.terrain or "")
    end
  elseif tile then
    local a=S.tiles[tile];local x,z=Sim.xy(tile)
    local st,build=S.stations[a.station],Sim.tools[a.build]
    local mark=a.stock_industry
    local registry=mark and (mark.chain=="farm" and S.stock_farm_industries or
      mark.chain=="timber" and S.stock_timber_industries or
      mark.chain=="oil" and S.stock_oil_industries or S.stock_coal_industries)
    local facility=registry and registry[mark.id]
    local site=S.sites[facility and facility.site or a.site]
    local landmark=a.stock_landmark and (a.stock_landmark.kind=="lighthouse" and "Lighthouse" or
      a.stock_landmark.kind=="statue" and "Company statue" or
      a.stock_landmark.kind=="headquarters" and "Company headquarters" or "Radio transmitter")
    local stake=a.stock_object and a.stock_object.kind=="owned_land" and ("Company land · "..(a.owner or "Unknown"))
    local channel=a.ship and a.ship.kind=="lock" and "Ship lock" or
      a.water_class=="river" and "River" or nil
    target=("%d,%d  %s"):format(x,z,st and U.stop_label(st) or site and site.name or landmark or stake or
      a.road_town and (S.sites[a.road_town].name.." street") or build and build.name or channel or a.terrain)
    if api.oneway and a.road_disallowed then
      local m=api.oneway.marking(S,tile)
      if m then target=target.."  ·  "..(m.kind=="no-entry" and "No entry in either direction" or
        ("One-way "..(({[0]="west","south","east","north"})[m.dir] or ""))) end
    end
  end
  local ids,valid,bid
  if tile and show_preview then ids,valid,bid=U.preview(p,tile,hit) end
  local status=V.status
  if V.pick_order then
    local v=S.fleet[V.pick_order]
    status=(v and (v.name.."  ·  "..#v.orders.." saved") or "Vehicle orders")..
      (V.order_feedback and ("  ·  "..V.order_feedback) or "")
    if not tile then local _,hint=order_stop_target(p:get_player_name(),V);bid=hint end
  end
  return (bid or (tool.name.."   |   "..target)),status,ids,valid
end
function U.build_world(p,id,hit)
  local n=p:get_player_name();local V=view(n)
  V.chosen=id
  local bridge=bridge_tool(V.tool)
  if bridge then
    if not V.anchor then V.anchor=id;V.status="First bridgehead selected. Click the opposite end.";return end
    V.status="Choose a bridge type."
    local ok,why=api.bridge_picker.open(p,bridge,V.anchor,id,function(built,note)
      if note then V.status=note
      elseif built then V.status="Bridge built." end
    end,bridge=="rail" and V.rail_gauge or nil)
    if ok then V.anchor=nil else V.status=why or "No bridge can join these heads." end
    return
  end
  if U.road_stop_gesture(p,V.tool) then return end
  local oriented=road_terminal_request(V,id)
  if oriented then
    if api.authority_handoff then worker_build(n,V,"road",oriented);return end
    local q,why=Sim.stock_road_terminal_plan(S,n,id,{kind=oriented.kind,dir=oriented.direction,through=oriented.through})
    if not q then V.status=Sim.stock_road_terminal_error(why);return end
    local ok,note,tiles=Sim.apply_road_construction(S,n,q)
    V.status=note
    if ok then R.update(tiles);api.save() end
    return
  end
  if api.authority_handoff then
    local auto=U.road_auto_terminal(p,V.tool,id)
    if auto then
      if auto.adjacent then U.open_station_join_picker(p,V,auto)
      else worker_build(n,V,"road",auto) end
      return
    end
    if V.tool=="teleport_tile" then U.teleport_tile(p,id);return end
    if V.tool=="inspect" then U.inspect(p,id);return end
    if U.signal_ui and U.signal_ui.tool(V.tool) then U.signal_ui.open(p,id,V.tool,hit);return end
    if V.tool=="rail_signal_remove" or V.tool=="rail_span_clear" or V.tool=="ship_remove"
      or V.tool=="ship_buoy_remove" or V.tool=="airfield_remove" then
      if U.layer_bulldozer then U.layer_bulldozer.open(p,id) end
      return
    end
    if U.rail_gesture(V.tool) or U.road_gesture(V.tool,p) then return end
    local land=landscape_tools[V.tool]
    if land then
      if land.area and not V.anchor then V.anchor=id;V.status="Choose the opposite terrain corner.";return end
      local first,last=V.anchor or id,land.area and id or nil
      V.anchor=nil
      worker_build(n,V,"terrain",{operation=land.mode,first=first,last=last,
        diagonal=land.area and p:get_player_control().aux1 or false})
      return
    end
    if V.tool=="road_station" or V.tool=="road_depot" or V.tool=="road_bay_pair" then
      worker_build(n,V,"road",{tool=V.tool,first=id});return
    end
    local stage=coal_stage_tools[V.tool] or oil_stage_tools[V.tool] or goods_stage_tools[V.tool] or profile_stage_tools[V.tool]
    if stage then
      local cargo=stage.cargo or (coal_stage_tools[V.tool] and "coal" or oil_stage_tools[V.tool] and "oil" or "goods")
      worker_action(n,V,{kind="rail_freight_stage",tile=id,cargo=cargo,role=stage.role,mirror=V.coal_side~=false})
      return
    end
    if V.tool=="fund_bank" then
      worker_build(n,V,"road",{tool=V.tool,first=id});return
    end
    if V.tool=="truck_stop_tool" then
      worker_build(n,V,"road",{tool="truck_stop",first=id});return
    end
    if V.tool=="rail_crossing_tool" then
      worker_build(n,V,"rail",{tool="crossing",first=id});return
    end
    if V.tool=="rail_waypoint_place" then
      worker_build(n,V,"rail",{tool="waypoint",first=id});return
    elseif V.tool=="rail_waypoint_remove" then
      if U.layer_bulldozer then U.layer_bulldozer.open(p,id) end
      return
    end
    if rail_tool_code[V.tool]~=nil then
      local track=rail_tool_code[V.tool]
      if track<2 and not V.anchor then V.anchor=id;V.status="Mark the last tile.";return end
      local first=V.anchor or id
      V.anchor=nil
      worker_build(n,V,"rail",{tool="track",first=first,last=id,track=track,remove=V.rail_remove==true})
      return
    end
    if electric_tools[V.tool]~=nil then
      if not V.anchor then V.anchor=id;V.status="Click the opposite corner, or click this tile again.";return end
      local first=V.anchor
      V.anchor=nil
      worker_build(n,V,"rail",{tool="wire",first=first,last=id,target=electric_tools[V.tool]})
      return
    end
    if V.tool=="rail_depot_tool" then
      worker_build(n,V,"rail",U.rail_depot_request(p,V,id));return
    end
    local surface=R.host_tile and R.host_tile(id)
    if rail_orders[V.tool] then
      if not surface or surface.owner~=n then V.status="Choose one of your railway facilities.";return end
      if not V.anchor then
        if surface.rail_depot_dir==nil then V.status="Choose your rail depot first.";return end
        V.anchor=id;V.status="Depot selected. Click the first platform.";return
      end
      local platform=surface.rail_station_id
      if not platform then V.status="Choose an owned rail platform.";return end
      if V.tool=="rail_order_shuttle" and not V.rail_first then
        V.rail_first=platform;V.status="First platform selected. Choose the second platform.";return
      end
      if platform==V.rail_first then V.status="Choose a different rail platform.";return end
      if stage_fixed_destination(V,id) then return end
      local operation=({rail_order_one="station",rail_order_block="block",rail_order_span="span",rail_order_shuttle="shuttle"})[V.tool]
      worker_action(n,V,{kind="transport_start",mode="rail_pilot",operation=operation,depot=V.anchor,
        first=V.rail_first or platform,second=V.rail_first and platform or nil},function(ok)
        if ok then V.anchor,V.rail_first,V.fixed_route=nil,nil,nil end
      end)
      return
    end
    if V.tool=="ship_order" then
      local part=surface and surface.ship
      if not V.ferry_depot then
        if not part or part.owner~=n or not part.depot then V.status="Choose your ship depot first.";return end
        V.ferry_depot=part.depot;V.status="Depot selected. Click the first dock.";return
      end
      if V.ferry_first and part and part.kind=="buoy" then
        V.ferry_via=id;V.status="Buoy selected. Click the second dock.";return
      end
      if not part or part.owner~=n or part.kind~="dock" then V.status="Choose an owned dock.";return end
      if not V.ferry_first then
        V.ferry_first=part.station;V.status="First dock selected. Click a buoy or the second dock.";return
      end
      if V.ferry_first==part.station then V.status="Choose a different dock.";return end
      if stage_fixed_destination(V,id) then return end
      worker_action(n,V,{kind="transport_start",mode="ship",depot=V.ferry_depot,first=V.ferry_first,
        second=part.station,via=V.ferry_via},function(ok)
        if ok then V.ferry_depot,V.ferry_first,V.ferry_via,V.fixed_route=nil,nil,nil,nil end
      end)
      return
    end
    if V.tool=="airfield_order" then
      local part=surface and surface.airfield
      local field=part and (part.owner or surface.owner)==n and part.airport
      if not field then V.status="Choose one of your airfields.";return end
      if not V.airport_first and part.layout=="heliport" then
        V.status="Choose your helicopter's purchase hangar first. The Heliport is a destination.";return
      end
      if not V.airport_first then V.airport_first=field;V.status="Departure selected. Pick a destination.";return end
      if field==V.airport_first then V.status="Choose a different airfield.";return end
      if stage_fixed_destination(V,id) then return end
      worker_action(n,V,{kind="transport_start",mode="air",first=V.airport_first,second=field},function(ok)
        if ok then V.airport_first,V.fixed_route=nil,nil end
      end)
      return
    end
    if V.tool=="tram_order" then
      local t=R.host_tile and R.host_tile(id)
      local record=t and t.tram
      if not record or record.owner~=n then V.status="Choose one of your tramway facilities.";return end
      if not V.anchor then
        if record.kind~="depot" then V.status="Choose your tram depot first.";return end
        V.anchor=id;V.status="Depot selected. Click the first through tram stop.";return
      end
      if record.kind~="drive_stop" then V.status="Choose an owned through tram stop.";return end
      if not V.tram_first then V.tram_first=id;V.status="First stop selected. Click a different through stop.";return end
      if id==V.tram_first then V.status="Choose a different through stop.";return end
      if stage_fixed_destination(V,id) then return end
      local request={kind="transport_start",mode="tram",depot=V.anchor,first=V.tram_first,second=id}
      local first=R.host_tile and R.host_tile(V.tram_first)
      local left,right=Sim.tram_stop_id(first),Sim.tram_stop_id(t)
      if left and right and left~=right then
        V.tram_offer=request
        core.show_formspec(n,tram_offer_form,("formspec_version[4]size[10,4]"..
          "label[.5,.5;%s]label[.5,1.1;%d passengers  |  %d km/h  |  %s]"..
          "label[.5,1.7;Paid service carries passengers and earns fares.]"..
          "button_exit[.5,2.5;4.2,.8;tram_paid;Buy and dispatch]"..
          "button_exit[5,2.5;4.5,.8;tram_test;Run a free test]"):format(
          esc(TramMarket.name),TramMarket.capacity,TramMarket.speed/2,dollars(TramMarket.price)))
        return
      end
      worker_action(n,V,request,function(ok)
        if ok then V.anchor,V.tram_first,V.fixed_route=nil,nil,nil end
      end)
      return
    end
    local tram,cells,direction=tram_request(p,V,id)
    if tram then
      if V.tool=="tram_track" and not V.anchor then V.anchor=id;V.status="Choose the end of the tramway.";return end
      V.anchor=nil
      if V.tool=="tram_track" then
        worker_build(n,V,"transport",{mode="tram",operation="build",kind=tram,cells=cells,direction=direction})
      else
        worker_build(n,V,"road",{tool="tram_facility",first=id,kind=tram,direction=direction})
      end
      return
    end
    local dock=ship_mode[V.tool]
    if dock=="lock" or dock=="canal" or dock=="aqueduct" then
      if dock~="lock" and not V.anchor then V.anchor=id;V.status="Choose the opposite end of the waterway.";return end
      local first=V.anchor or id
      V.anchor=nil
      worker_build(n,V,"transport",{mode="ship",operation="waterwork",kind=dock,tile=first,last=id})
      return
    end
    if dock=="dock" or dock=="depot" or V.tool=="ship_buoy" then
      local req={mode="ship",operation="build",kind=dock or "buoy",tile=id,axis=U.ship_depot_axis(p,V,dock)}
      if dock=="dock" and (V.tool=="ship_join_dock" or p:get_player_control().aux1) then
        req.adjacent=true
        U.open_station_join_picker(p,V,req,"dock")
      else worker_build(n,V,"transport",req) end
      return
    end
    if airfield_tools[V.tool] and V.tool~="airfield_remove" then
      U.open_station_join_picker(p,V,{mode="air",operation="build",tile=id,layout=airfield_tools[V.tool].layout,
        separate=p:get_player_control().aux1==true},"air");return
    end
    if V.tool=="structure_tunnel" or V.tool=="rail_span_tunnel" then
      worker_build(n,V,"transport",{mode=V.tool=="rail_span_tunnel" and "rail" or "road",operation="tunnel",tile=id})
      return
    end
    V.status="That tool is not connected to the campaign worker yet."
    return
  end
  if V.pick_order then U.choose_order_stop(p,id);return end
  if V.tool=="inspect" then U.inspect(p,id);return end
  if V.tool=="clear" and U.layer_bulldozer and U.layer_bulldozer.open(p,id) then return end
  if electric_tools[V.tool]~=nil and api.electric_tools then
    if electric_tools[V.tool]==1 and not api.electric_available(n) then V.status=wire_errors.RAILTYPE_NOT_AVAILABLE;return end
    if not V.anchor then V.anchor=id;V.status="Click the opposite corner, or click this tile again.";return end
    local ticket,why=wire_quote(n,V,id)
    if not ticket then V.status=wire_error(why);return end
    local ok,price,ids=api.electric_commit(n,ticket)
    if ok then
      V.anchor=nil
      V.status=("Converted %d rail tile(s) for %s."):format(#ids,dollars(price))
    else V.status=wire_error(price) end
    return
  end
  if V.tool=="truck_stop_tool" and api.freight_tools then
    local ok,msg,changed=Sim.build_truck_stop(S,n,id)
    V.status=msg
    if ok then
      if Sim.road_bits(S,id)==0 then V.status="Truck stop built. Connect it to the road before ordering trucks." end
      local st=S.stations[S.tiles[id].station]
      if st then st.freight_art=true;st.coal_art=Sim.road_coal_active(S) or nil end
      R.update(changed);api.save()
    end
    return
  end
  if coal_stage_tools[V.tool] and api.rail_coal_tools then
    local tool=coal_stage_tools[V.tool]
    local st,hint=coal_stage_target(n,tool,id)
    if not st then V.status=hint;return end
    if st.coal_stage_tile and st.coal_stage_tile~=id then
      V.status="This platform already has its equipment tile."
      return
    end
    local ok,note,dirty=Sim.rail_coal_designate(S,n,st.id,tool.role)
    V.status=note
    if ok then
      st.coal_stage_tile=id
      st.coal_stage_mirror=V.coal_side~=false
      R.update(dirty);api.save()
    end
    return
  end
  if goods_stage_tools[V.tool] and api.rail_goods_tools then
    local tool=goods_stage_tools[V.tool]
    local st,hint=goods_stage_target(n,tool,id)
    if not st then V.status=hint;return end
    local ok,note,dirty=Sim.rail_goods_designate(S,n,st.id,tool.role)
    V.status=note
    if ok then R.update(dirty);api.save() end
    return
  end
  if oil_stage_tools[V.tool] and api.rail_oil_tools then
    local tool=oil_stage_tools[V.tool]
    local st,hint=oil_stage_target(n,tool,id)
    if not st then V.status=hint;return end
    if not Sim.rail_oil_designate then V.status="Rail Oil service is not available.";return end
    local ok,note,dirty=Sim.rail_oil_designate(S,n,st.id,tool.role)
    V.status=note
    if ok then R.update(dirty or st.tiles);api.save() end
    return
  end
  if profile_stage_tools[V.tool] then
    local tool=profile_stage_tools[V.tool]
    local st,hint=profile_stage_target(n,tool,id,false)
    if not st then V.status=hint;return end
    local ok,note,dirty=Sim["rail_"..tool.cargo.."_designate"](S,n,st.id,tool.role)
    V.status=note
    if ok then R.update(dirty or st.tiles);api.save() end
    return
  end
  if V.tool=="oneway_drag" and api.oneway_tools then
    if not V.anchor then V.anchor=id;V.status="Start selected. Click the end in the travel direction.";return end
    local q,why=one_way_quote(n,V,id)
    if not q then V.status=why;return end
    U.commit_oneway(n,V,id,q)
    return
  end
  if V.tool=="rail_crossing_tool" and api.crossing_tools then
    local plan,why=crossing_quote(n,id)
    if not plan then V.status=why;return end
    local ok,result=api.crossing_commit(n,plan)
    if ok then
      V.status="Built level crossing for "..dollars(result).."."
      R.float(n,id,"−"..dollars(result),0xf89171)
    else V.status=crossing_errors[result] or ("Crossing unavailable: "..tostring(result)) end
    return
  end
  if rail_spans[V.tool] and api.rail_spans then
    local span,why,wait=rail_span_quote(n,V,id)
    if not span and wait==true then V.anchor=id;V.status="First abutment selected. Click the opposite end.";return end
    if not span then V.status=why;return end
    local ok,note,dirty,deck
    if V.tool=="rail_span_clear" then ok,note,dirty,deck=api.rail_spans.clear(S,n,id)
    else ok,note,dirty,deck=api.rail_spans.commit(S,n,span) end
    V.status=note
    if ok then
      V.anchor=nil
      if deck then R.raise_bound(deck) end
      if dirty then R.update(dirty) end
      if V.tool~="rail_span_clear" then R.float(n,id,"−"..dollars(span.price),0xf89171) end
      api.save()
    end
    return
  end
  if rail_orders[V.tool] and api.rail_build then
    local valid,hint=rail_order_target(n,V,id)
    if not valid then V.status=hint;return end
    if not V.anchor then V.anchor=id;V.status="Depot selected. Choose the first platform.";return end
    local st=S.tiles[id].rail_station_id
    if V.tool=="rail_order_shuttle" and not V.rail_first then
      V.rail_first=st;V.status="First platform selected. Choose the second platform.";return
    end
    if stage_fixed_destination(V,id) then return end
    local ok,msg
    if V.tool=="rail_order_span" and api.rail_spans then ok,msg=api.rail_spans.start(S,n,V.anchor,st)
    elseif V.tool=="rail_order_block" then ok,msg=api.rail_build.order_block(n,V.anchor,st)
    else ok,msg=api.rail_build.order(n,V.anchor,V.rail_first or st,V.rail_first and st or nil) end
    V.status=msg
    if ok then V.anchor=nil;V.rail_first=nil;V.fixed_route=nil end
    return
  end
  if waypoint_tools[V.tool] then
    local plan,why=waypoint_quote(n,V.tool,id)
    if not plan then V.status=why;return end
    local ok,status=api.rail_build.build(n,plan)
    V.status=status
    if ok then R.float(n,id,"−"..dollars(plan.price),0xf89171) end
    return
  end
  if U.rail_gesture(V.tool) then return end -- physical release owns the command
  if U.signal_ui and api.rail_build and U.signal_ui.tool(V.tool) then U.signal_ui.open(p,id,V.tool,hit);return end
  if V.tool=="rail_signal_remove" and U.layer_bulldozer then
    if not U.layer_bulldozer.open(p,id) then V.status="Aim at a signal to review removal." end
    return
  end
  if rail_tool_labels[V.tool] and api.rail_build then
    local plan,note,anchor=quote_rail(p,n,V,id)
    if anchor then V.anchor=id;V.status="Mark the last tile.";return end
    if not plan then V.status=note;return end
    local ok,msg=api.rail_build.build(n,plan)
    V.status=msg
    if ok then
      V.anchor=nil
      local sign=plan.price<0 and "+" or "−"
      R.float(n,id,sign..dollars(math.abs(plan.price)),plan.price<0 and 0xa6ee89 or 0xf89171)
    end
    return
  end
  if V.tool=="ship_coal_order" and api.ship_coal_tools then
    local selected,why=ship_coal_target(n,V,id)
    if not selected then V.status=why;return end
    if not V.ship_coal_first then V.ship_coal_first=selected;V.status="Mine dock selected. Click the power station dock.";return end
    if stage_fixed_destination(V,id) then return end
    local result,note=api.ship_coal.start(n,V.ship_coal_first,selected)
    if result then V.ship_coal_first=nil;V.fixed_route=nil;api.save() end
    V.status=note
    return
  end
  if V.tool=="ship_order" and api.shipyard then
    local target,hint,kind=ship_order_target(n,V,id)
    if not target then V.status=hint;return end
    if not V.ferry_depot then V.ferry_depot=target;V.status="Depot selected. Click the first dock.";return end
    if not V.ferry_first then
      V.ferry_first=target;V.status="First dock selected. Click a public buoy or the second dock.";return
    end
    if kind=="buoy" then V.ferry_via=target;V.status="Buoy selected. Click the second dock.";return end
    if stage_fixed_destination(V,id) then return end
    local run,msg=api.shipyard.start(n,V.ferry_depot,V.ferry_first,target,V.ferry_via)
    if run then V.ferry_depot,V.ferry_first,V.ferry_via,V.fixed_route=nil,nil,nil,nil end
    V.status=msg
    return
  end
  if V.tool=="airfield_order" and api.airfield then
    local field,hint=airport_order_target(n,V,id)
    if not field then V.status=hint;return end
    if not V.airport_first then V.airport_first=field.id;V.status="Departure selected. Click a different airfield.";return end
    if stage_fixed_destination(V,id) then return end
    local flight,msg=api.airfield.start(n,V.airport_first,field.id)
    if flight then V.airport_first=nil;V.fixed_route=nil end
    V.status=msg
    return
  end
  if airfield_tools[V.tool] and api.airfield then
    local tiles,price,level=airfields(S,n,V.tool,id,false)
    if not tiles then V.status=api.airfield.reason(price);return end
    if level then R.raise_bound(level) end
    V.status=("Airfield work: $%d."):format(price)
    R.float(n,id,"−"..dollars(price),0xf89171)
    R.update(tiles);api.save()
    return
  end
  if buoy_tools[V.tool] and api.shipyard then
    local q,why=buoy_quote(n,V.tool,id)
    if not q then V.status=api.shipyard.reason(why,V.tool);return end
    local N=api.shipyard.network
    local result,cost
    if V.tool=="ship_buoy_remove" then
      result,cost=N.remove(S,n,id)
    else
      local buoy,why=N.build(S,n,"buoy",id)
      if buoy then result,cost=buoy.tiles,buoy.cost else cost=why end
    end
    if not result then V.status=api.shipyard.reason(cost,V.tool);return end
    V.status=("%s · $%d"):format(V.tool=="ship_buoy_remove" and "Buoy removed; water remains" or "Public buoy placed",cost)
    R.float(n,id,"−"..dollars(cost),0xf89171)
    R.update(result);api.save()
    return
  end
  local ship=ship_mode[V.tool]
  if ship and api.shipyard then
    if api.shipyard.busy() then V.status="An active vessel protects these harbor facilities.";return end
    local dirty,cost
    if ship=="remove" then dirty,cost=aquatic_remove(n,id,false)
    elseif ship=="lock" then
      local plan,reason=api.waterworks.build_lock(S,n,id)
      if plan then dirty,cost=plan.dirty,plan.cost else cost=reason end
    elseif ship=="canal" then
      if not V.anchor then V.anchor=id;V.status="Choose the opposite corner of the canal area.";return end
      local plan,reason=api.waterworks.build(S,n,V.anchor,id,false)
      if plan then dirty,cost=plan.dirty,plan.cost else cost=reason end
    elseif ship=="aqueduct" then
      if not V.anchor then V.anchor=id;V.status="Choose the opposite aqueduct head.";return end
      local plan,changed=api.aqueduct.build(S,n,V.anchor,id)
      if plan then dirty,cost=changed,plan.price;R.raise_bound(plan.deck) else cost=changed end
    else
      local plan,reason=api.shipyard.network.build(S,n,ship,id,U.ship_depot_axis(p,V,ship))
      if plan then dirty,cost=plan.tiles,plan.cost else cost=reason end
    end
    if not dirty then V.status=api.shipyard.reason(cost);return end
    V.anchor=nil;V.status=("Harbor work: $%d."):format(cost)
    R.float(n,id,"−"..dollars(cost),0xf89171)
    R.update(dirty);api.save()
    return
  end
  if V.tool=="tram_order" and api.tram then
    local valid,hint=tram_order_target(n,V,id)
    if not valid then V.status=hint;return end
    if not V.anchor then V.anchor=id;V.status="Depot selected. Click the first through tram stop.";return end
    if not V.tram_first then V.tram_first=id;V.status="First stop selected. Click a different through stop.";return end
    if stage_fixed_destination(V,id) then return end
    local ok,msg=api.tram.start(n,V.anchor,V.tram_first,id)
    if ok then V.anchor,V.tram_first,V.fixed_route=nil,nil,nil end
    V.status=msg
    return
  end
  local tram,tiles,direction=tram_request(p,V,id)
  if tram and api.tram then
    if V.tool=="tram_track" and not V.anchor then
      V.anchor=id;V.status="Choose the end of the tramway.";return
    end
    local changed,cost=api.tram.network.construct(S,n,tram,tiles,direction,api.tram.busy)
    if not changed then V.status=api.tram.reason(cost);return end
    V.anchor=nil;V.status=("$%d for tram construction."):format(cost)
    R.float(n,id,"−"..dollars(cost),0xf89171)
    R.update(changed);api.save()
    return
  end
  local structure=structure_request(V)
  if structure then
    if not api.structure_tools then V.status="Structure tools are not enabled.";return end
    if structure~="tunnel" and not V.anchor then V.anchor=id;V.status="Choose the second bridgehead.";return end
    local ok,msg,changed,peak=structure_build(n,V,id,structure,false)
    V.status=msg
    if ok then
      V.anchor=nil
      if peak then R.raise_bound(peak) end
      R.update(changed);api.save()
    end
    return
  end
  local mode,x,z,u,v,area,diagonal=landscape_request(V,id,p)
  if mode then
    if not api.terrain then V.status="Shared terrain is disabled.";return end
    if area and not u then V.anchor=id;V.status="First corner marked. Select the opposite corner.";return end
    local ok,msg,changed,peak=Sim.landscape(S,n,mode,x,z,u,v,diagonal)
    V.status=msg
    if ok then V.anchor=nil;R.raise_bound(peak);R.update(changed);api.save() end
    return
  end
  if Sim.linear[V.tool] and not V.anchor then
    V.anchor=id;V.status="Start marked. Aim and click to build to a second tile.";return
  end
  local ids=Sim.linear[V.tool] and Sim.line(V.anchor,id,V.zfirst) or {id}
  local ok,note,changed=Sim.build(S,n,V.tool,ids)
  V.status=note
  if ok then
    if V.tool=="road_station" and api.road_first and Sim.road_bits(S,id)==0 then
      V.status=note.." Stop is unconnected: lay a road before adding orders."
    end
    local cost=tonumber(note:match("^%$(%d+)"))
    if cost then R.float(n,id,"−"..dollars(cost),0xf89171) end
    V.anchor=nil;R.update(changed);api.save()
  end
end
function U.open_town_authority(p,town)
  local n=p:get_player_name()
  local v=view(n)
  local client=api.worker_bridge_client
  if not client then return false end
  local token={}
  v.authority_context=token
  v.town_funding,v.road_funding,v.statue_offer,v.advertising_offer,v.council_offer=nil,nil,nil,nil,nil
  local queued=client.query({kind="town_authority",player=n,town=town},function(result)
    if v.authority_context~=token or not core.get_player_by_name(n) then return end
    if not result.ok then U.status(p,"Town authority information is unavailable.");return end
    local row=result.value
    local road=row.road_minimum and row.rating<row.road_minimum and
      "The council refuses municipal road removals at your current rating." or
      "Your rating meets the minimum for requesting municipal road removal."
    local junction=row.extra_dynamite and
      "Connected streets still require an unobstructed demolition site." or
      "Connected streets still require Extra Dynamite."
    local action=""
    local funding=row.funding
    if funding then
      local status=funding.months>0 and ("Building funding active for %d more month%s."):format(
        funding.months,funding.months==1 and "" or "s") or "No building funding is active."
      action="label[.45,3.63;"..esc(status).."]"
      if funding.affordable then
        v.town_funding={town=row.id,cost=funding.cost,revision=result.revision,token=token}
        action=action.."button[.45,4.04;9.7,.57;fund_buildings;"..
          esc("Fund new buildings for 3 months · "..dollars(funding.cost)).."]"
      else
        action=action.."label[.45,4.30;"..esc("Fund new buildings · "..dollars(funding.cost).." required").."]"
      end
    end
    local exit=funding and 4.99 or 3.78
    local rebuild=row.reconstruction
    if rebuild then
      local y=funding and 4.92 or 3.63
      local status=rebuild.months>0 and ("Street reconstruction: %d month%s left."):format(
        rebuild.months,rebuild.months==1 and "" or "s") or "No street reconstruction is active."
      action=action..("label[.45,%g;%s]"):format(y,esc(status))
      if rebuild.affordable then
        v.road_funding={town=row.id,cost=rebuild.cost,revision=result.revision,token=token}
        action=action..("button[.45,%g;9.7,.57;fund_roads;%s]"):format(y+.41,
          esc("Fund road reconstruction for 6 months · "..dollars(rebuild.cost)))
      else
        action=action..("label[.45,%g;%s]"):format(y+.67,
          esc("Fund road reconstruction · "..dollars(rebuild.cost).." required"))
      end
      exit=y+1.36
    end
    local statue=row.statue
    if statue then
      local y=exit
      if statue.existing then
        action=action..("label[.45,%g;Your company already has a statue here.]"):format(y+.27)
      elseif statue.affordable then
        v.statue_offer={town=row.id,tile=statue.tile,cost=statue.cost,revision=result.revision,token=token}
        action=action..("button[.45,%g;9.7,.57;build_statue;%s]"):format(y,
          esc("Commission a statue · "..dollars(statue.cost)))..
          "tooltip[build_statue;The council chooses the site. Your stations in this town get a cargo rating bonus.]"
      else
        action=action..("label[.45,%g;%s]"):format(y+.27,esc(statue.why or
          ("Commission a statue · "..dollars(statue.cost).." required")))
      end
      exit=exit+.85
    end
    if row.advertising and #row.advertising>0 then
      v.advertising_offer={town=row.id,name=row.town,offers=row.advertising,revision=result.revision,token=token}
      action=action..("button[.45,%g;9.7,.57;town_advertising;Advertising campaigns…]"):format(exit)
      exit=exit+.80
    end
    if row.council then
      v.council_offer={town=row.id,name=row.town,state=row.council,revision=result.revision,token=token}
      action=action..("button[.45,%g;9.7,.57;town_council;Transport rights and council actions…]"):format(exit)
      exit=exit+.80
    end
    if row.new_stations~=nil then
      local station=row.new_stations and "New stations: your rating allows construction." or
        "New stations: refused at your current rating."
      action=action..("label[.45,%g;%s]"):format(exit+.22,esc(station))
      exit=exit+.61
    end
    if row.airport_noise then
      local noise=row.airport_noise
      action=action..("label[.45,%g;%s]"):format(exit+.22,
        esc(("Airport noise: %d / %d"):format(noise.used,noise.limit)))
      exit=exit+.63
    end
    if row.last_month then
      local pax,mail=row.last_month.passenger,row.last_month.mail
      action=action..("label[.45,%g;Passengers last month: %d of %d transported]"):format(exit+.22,pax.transported,pax.generated)
      action=action..("label[.45,%g;Mail last month: %d of %d bags transported]"):format(exit+.64,mail.transported,mail.generated)
      exit=exit+1.03
    end
    local size=exit+.92
    core.show_formspec(n,"luanttd_core:town_authority",
      ("formspec_version[7]size[10.6,%g]bgcolor[#152334;false]"):format(size)..
      "label[.45,.48;LOCAL AUTHORITY]label[.45,.98;"..esc(row.town).."]"..
      "box[.45,1.44;9.7,.72;#2F4758]label[.63,1.80;"..
      esc(("Your company's rating: %s (%+d)"):format(row.grade,row.rating)).."]"..
      "textarea[.45,2.34;9.7,1.15;;;"..esc(road.."\n"..junction).."]"..action..
      ("button_exit[.45,%g;9.7,.57;close;Back to world]"):format(exit))
  end)
  return not not queued
end
function U.open_town_advertising(p)
  local n=p:get_player_name()
  local v=view(n)
  local q=v.advertising_offer
  if not q or q.token~=v.authority_context then return end
  local body={"formspec_version[7]size[8.7,5.28]bgcolor[#152334;false]",
    "label[.45,.45;TOWN ADVERTISING]label[.45,.93;"..esc(q.name).."]",
    "label[.45,1.43;Boost cargo ratings at your stations around this town.]"}
  for i,offer in ipairs(q.offers) do
    local y=1.93+(i-1)*.76
    local label=("%s · %d tiles · %s"):format(offer.name,offer.radius,dollars(offer.cost))
    if offer.affordable then
      body[#body+1]=("button[.45,%g;7.8,.59;advertise_%s;%s]"):format(y,offer.key,esc(label))
      body[#body+1]=("tooltip[advertise_%s;Adds up to %g%% to active cargo ratings within %d tiles.]"):format(
        offer.key,math.floor(offer.bonus*100/255+.5),offer.radius)
    else
      body[#body+1]=("label[.58,%g;%s]"):format(y+.28,esc(label.." required"))
    end
  end
  body[#body+1]="button_exit[.45,4.36;7.8,.58;authority_back;Back to Local Authority]"
  core.show_formspec(n,"luanttd_core:town_advertising",table.concat(body))
end
function U.town_advertising_fields(p,f)
  local n=p:get_player_name()
  local v=view(n)
  local q=v.advertising_offer
  local client=api.worker_bridge_client
  if not (q and q.token==v.authority_context and client) then return true end
  if f.authority_back then U.open_town_authority(p,q.town);return true end
  if f.quit then v.advertising_offer=nil;return true end
  local chosen
  for _,offer in ipairs(q.offers) do
    if f["advertise_"..offer.key] then
      if chosen then return true end
      chosen=offer
    end
  end
  if not (chosen and chosen.affordable) then return true end
  v.advertising_offer=nil
  local ok,why=client.query({kind="command",player=n,command={kind="town_advertise",
    town=q.town,size=chosen.key,cost=chosen.cost,revision=q.revision}},function(result)
    if v.authority_context~=q.token or not core.get_player_by_name(n) then return end
    U.status(p,result.why or (result.ok and "Advertising campaign launched." or "Advertising unavailable."))
    U.open_town_authority(p,q.town)
  end)
  if not ok then v.advertising_offer=q;U.status(p,why or "Advertising request could not be sent.") end
  return true
end
function U.open_town_council(p)
  local n=p:get_player_name()
  local v=view(n)
  local q=v.council_offer
  if not (q and q.token==v.authority_context) then return end
  local labels={exclusive_rights="Buy exclusive rights for 12 months",bribe="Bribe the town council"}
  local reasons={RIGHTS_UNAVAILABLE="Exclusive rights unavailable",BRIBE_UNAVAILABLE="Bribery unavailable",
    UNWANTED_COMPANY="The council is refusing applications",NOT_ENOUGH_CASH="Not enough cash"}
  local overview=q.state.holder and ("%s holds exclusive transport rights for %d more months."):format(q.state.holder,q.state.months)
    or "No company holds exclusive transport rights."
  local ban=q.state.unwanted>0 and ("The council won't take your applications for %d more months."):format(q.state.unwanted) or ""
  local body={"formspec_version[7]size[9.5,5.52]bgcolor[#152334;false]",
    "label[.45,.45;TRANSPORT RIGHTS AND COUNCIL ACTIONS]label[.45,.90;"..esc(q.name).."]",
    "textarea[.45,1.34;8.6,1.1;;;"..esc(overview.."\n"..ban).."]"}
  for i,o in ipairs(q.state.offers) do
    local y=2.42+(i-1)*.82
    local name=labels[o.key]
    if o.affordable then
      body[#body+1]=("button[.45,%g;8.6,.58;council_%s;%s]"):format(y,o.key,esc(name.." · "..dollars(o.cost)))
    else
      body[#body+1]=("label[.52,%g;%s]"):format(y+.28,esc((reasons[o.why] or name).." · "..dollars(o.cost)))
    end
  end
  body[#body+1]="tooltip[council_exclusive_rights;Rival stations in this town lose access to locally produced cargo.]"
  body[#body+1]="tooltip[council_bribe;A failed bribe has a one in fourteen chance and blocks company actions for six months.]"
  body[#body+1]="button_exit[.45,4.55;8.6,.58;authority_back;Back to Local Authority]"
  core.show_formspec(n,"luanttd_core:town_council_campaigns",table.concat(body))
end
function U.town_council_fields(p,f)
  local n=p:get_player_name()
  local v=view(n)
  local q=v.council_offer
  local client=api.worker_bridge_client
  if not (q and q.token==v.authority_context and client) then return true end
  if f.authority_back then U.open_town_authority(p,q.town);return true end
  if f.quit then v.council_offer=nil;return true end
  local chosen
  for _,o in ipairs(q.state.offers) do
    if f["council_"..o.key] then
      if chosen then return true end
      chosen=o
    end
  end
  if not (chosen and chosen.affordable) then return true end
  v.council_offer=nil
  local ok,why=client.query({kind="command",player=n,command={kind="town_council_campaign",
    town=q.town,action=chosen.key,cost=chosen.cost,revision=q.revision}},function(result)
    if v.authority_context~=q.token or not core.get_player_by_name(n) then return end
    U.status(p,result.why or (result.ok and "Council action completed." or "This action is unavailable."))
    U.open_town_authority(p,q.town)
  end)
  if not ok then v.council_offer=q;U.status(p,why or "Council request could not be sent.") end
  return true
end
function U.fund_town_from_panel(p,action)
  local name=p:get_player_name()
  local v=view(name)
  local q=action=="roads" and v.road_funding or action=="buildings" and v.town_funding or action=="statue" and v.statue_offer
  local client=api.worker_bridge_client
  if not q or q.token~=v.authority_context or not client then return end
  v.town_funding,v.road_funding,v.statue_offer=nil,nil,nil
  local ok,why=client.query({kind="command",player=name,command={
    kind=action=="statue" and "town_build_statue" or "town_fund_"..action,town=q.town,tile=q.tile,cost=q.cost,revision=q.revision}},function(result)
    if v.authority_context~=q.token or not core.get_player_by_name(name) then return end
    U.status(p,result.why=="STALE_COMMAND" and "The town changed. Review the latest funding offer." or result.why)
    U.open_town_authority(p,q.town)
  end)
  if not ok then U.status(p,why or "The town funding request could not be sent.") end
end
-- A first-class primary-use action between building and ordering: no
-- secondary mouse button or chat command is required to reach a depot.
function U.open_mode_depot(p,id,hit,mode)
  local t
  if id then
    if api.authority_handoff then t=R.host_tile and R.host_tile(id) else t=S.tiles[id] end
  end
  local name=p:get_player_name()
  local names={road="road depot",rail="rail depot",ship="ship depot",air="airport hangar"}
  local facility=t and (mode=="road" and t.build=="road_depot" and t.owner==name or
    mode=="rail" and t.rail_depot_dir~=nil and (t.owner==name or t.rail_owner==name) or
    mode=="ship" and t.ship and t.ship.kind=="ship_depot" and t.ship.owner==name or
    mode=="air" and t.airfield and t.airfield.layout~="heliport" and t.airfield.owner==name)
  if not facility then U.status(p,"Aim at your "..(names[mode] or "depot").." to manage vehicles.");return false end
  return U.context(p,id,hit)
end

function U.context(p,tile,hit)
  local n=p:get_player_name();local V=view(n)
  V.authority_context=nil;V.town_funding=nil;V.road_funding=nil;V.statue_offer=nil
  if V.pick_order then U.finish_order_pick(p);return end
  if api.authority_handoff and company_projection and api.worker_depot and tile then
    local x,z=Sim.xy(tile)
    local row=company_projection.terrain(x,z)
    local t=row and row.surface
    if t then
      if t.airfield and t.airfield.layout=="heliport" then
        local waiting=R.waiting_at and R.waiting_at("air",t.airfield.airport) or 0
        local title=("Heliport #%d  ·  %s"):format(t.airfield.airport,t.airfield.owner or "Company")
        core.show_formspec(n,"luanttd_core:heliport_status",
          "formspec_version[7]size[10.3,3.7]bgcolor[#152334;false]label[.45,.55;"..esc(title).."]"..
          "label[.45,1.28;Helicopters only. Buy and order from an airport hangar.]"..
          "label[.45,1.93;"..number(waiting).." passengers waiting]"..
          "button_exit[.45,2.72;9.4,.55;close;Back to world]")
        return true
      end
      if R.host_signal and R.host_signal(tile) then return U.signal_ui.inspect(p,tile,hit) end
      local mode,key
      if t.rail_depot_dir~=nil then mode,key="rail",tile
      elseif t.build=="road_depot" then mode,key="road",tile
      elseif t.ship and t.ship.kind=="ship_depot" then mode,key="ship",t.ship.depot
      elseif t.airfield then mode,key="air",t.airfield.airport end
      if mode then
        return api.worker_depot.open(p,mode,key,nil,function(kind,id,back) return api.vehicle_ui.open(p,kind,id,back) end,nil,nil,mode=="air" and tile or nil)
      end
    end
  end
  if api.authority_handoff then
    local t=tile and R.host_tile and R.host_tile(tile)
    local label="LuanTTD / 3D survey"
    if t then
      local x,z=Sim.xy(tile)
      local site=R.host_record and R.host_record("sites",t.site)
      local st=R.host_record and R.host_record("stations",t.station)
      if Sim.road_stop_tile_kind(st,tile,t)=="truck" and api.worker_truck_stop then
        return api.worker_truck_stop.open(p,tile)
      end
      if t.rail_station_id and api.rail_mail_tools and api.worker_rail_mail_station then
        local platform=R.host_record and R.host_record("stock_rail_stations",t.rail_station_id)
        if platform and not Freight.role(platform) then return api.worker_rail_mail_station.open(p,tile) end
      end
      if t.stock_landmark and t.stock_landmark.kind=="headquarters" then return U.open_finance(p) end
      local town=site and site.kind=="town" and t.site or t.road_town or
        t.stock_landmark and t.stock_landmark.kind=="statue" and t.stock_landmark.town
      if town and U.open_town_authority(p,town) then return true end
      local name=st and st.name or site and site.name or t.terrain or "Tile"
      label=("%s · %d,%d"):format(name,x,z)
      if Sim.road_stop_tile_kind(st,tile,t)=="bus" and R.waiting_at then
        label=label..(" · %d waiting"):format(R.waiting_at("road",st.id) or 0)
      end
    end
    core.show_formspec(n,"luanttd_core:worker_inspect",
      "formspec_version[7]size[10.5,3.1]bgcolor[#152334;false]label[.45,.55;"..esc(label).."]"..
      "label[.45,1.3;Open Inventory for your fleet and construction tools.]"..
      "button_exit[.45,2.2;9.6,.55;close;Back to world]")
    return true
  end
  V.context_tile=tile
  if api.road_first then
    local t=tile and S.tiles[tile]
    if t and t.build=="road_depot" then U.service(p,"depot",tile)
    elseif t and t.station and S.stations[t.station] and S.stations[t.station].stop_type=="truck" then
      U.service(p,"stop",t.station)
    elseif not asset_details(p,tile,hit) then U.service(p,"context",tile) end
    return
  end
  if tile then V.chosen=tile end
  local t=tile and S.tiles[tile]
  local st=t and S.stations[t.station]
  local a=t and S.sites[t.site]
  local desc=st and st.name or a and a.name or t and title_case(t.terrain) or "Survey controls"
  local b={"formspec_version[7]size[11.4,9.17]bgcolor[#101C2B;false]style_type[button;font=bold;bgimg=bl_button.png;bgimg_middle=6;textcolor=#E5ECEA;border=false]"}
  local function add(s)b[#b+1]=s end
  local function button(x,y,w,id,label,active)
    if active then add("style["..id..";bgimg=bl_button_active.png]") end
    add(("button[%g,%g;%g,.51;%s;%s]"):format(x,y,w,id,esc(label)))
  end
  add("label[.35,.32;"..esc("LuanTTD   /   "..desc).."]")
  for i,tool in ipairs(Sim.tool_order) do
    button(.35+((i-1)%3)*3.59,.85+math.floor((i-1)/3)*.59,3.45,"tool_"..tool,Sim.tools[tool].name,V.tool==tool)
  end
  button(.35,4.57,3.45,"cancel","Cancel line")
  button(3.94,4.57,3.45,"axis",V.zfirst and "Z then X" or "X then Z")
  button(7.53,4.57,3.45,"company","Company")
  if st and st.owner==n then
    button(.35,5.25,3.45,"buy_here","Buy here")
    button(3.94,5.25,3.45,"order_here","Use for order")
  elseif t and t.signal and t.owner==n then
    button(.35,5.25,7.05,"hold",t.closed and "Reopen signal" or "Hold departures")
  else
    button(.35,5.25,7.05,"demo","Build starter bus line")
  end
  button(7.53,5.25,3.45,"jump","Jump map")
  if S.chair==n or core.check_player_privs(n,{server=true}) then
    for i,speed in ipairs({0,1,2,4}) do
      button(.35+(i-1)*2.2,5.99,2.06,"time_"..speed,speed==0 and "Pause" or speed.."×",speed==S.speed)
    end
  end
  if st then
    local places={}
    for _,sid in ipairs(st.served) do places[#places+1]=S.sites[sid].name end
    add("label[.36,6.90;"..esc("Catchment: "..table.concat(places,", ")).."]")
  elseif a then
    add("label[.36,6.90;"..esc(Sim.facilities[a.kind].name..(a.population and ("   •   "..a.population.." people") or "")).."]")
  end
  add("label[.36,7.51;"..esc("Pick an extra tool for hotbar 6; then aim and left-click.").."]")
  add("label[.36,7.83;"..esc(V.status).."]")
  button(.35,8.29,10.63,"back","Back to 3D")
  core.show_formspec(n,"luanttd_core:context",table.concat(b))
end
function U.context_fields(p,f)
  if f.quit then return true end
  local n=p:get_player_name();local V=view(n);local tile=V.context_tile
  local st=tile and S.stations[S.tiles[tile].station]
  for _,tool in ipairs(Sim.tool_order) do
    if f["tool_"..tool] then
      api.world.custom(p,tool);V.anchor=nil;V.status="Slot 6: "..Sim.tools[tool].name..". Select 6 to use it."
      core.close_formspec(n,"luanttd_core:context");return true
    end
  end
  if f.back then core.close_formspec(n,"luanttd_core:context");return true end
  if f.cancel then V.anchor=nil;V.status="Line cleared." end
  if f.axis then V.zfirst=not V.zfirst end
  if f.company then U.open_company(p);return true end
  if f.jump then V.tab="map";U.open(p);return true end
  if st and st.owner==n then
    if f.buy_here then
      V.pin_buy=st.id
      local available={}
      for _,id in ipairs(Sim.vehicle_order) do if Sim.vehicle_available(S,id) then available[#available+1]=id end end
      for i,id in ipairs(available) do if Sim.vehicles[id].mode==st.mode then V.engine=i;break end end
      U.open_company(p);return true
    elseif f.order_here then V.pin_add=st.id;U.open_company(p);return true end
  end
  if f.hold and tile then local ok,msg=Sim.signal(S,n,tile);V.status=msg;if ok then R.update({tile}) end end
  if f.demo then local ok,msg,ids=Sim.demo(S,n);V.status=msg;if ok then R.update(ids) end end
  if S.chair==n or core.check_player_privs(n,{server=true}) then
    for _,speed in ipairs({0,1,2,4}) do if f["time_"..speed] then S.speed=speed end end
  end
  api.save()
  U.context(p,tile)
  return true
end
-- Small world-context windows. Ordinary operations resume in 3D, without the
-- company-wide spreadsheet. Server resolves every submitted object and owner.
-- One cargo readout across all mounted chains. Goods has one shared
-- station queue; listing it once avoids implying two independent stocks.
function U.freight_snapshot(st)
  local rows={}
  local function add(cargo,n,accepted,sources,rating)
    if n~=nil then rows[#rows+1]={cargo=cargo,count=n,accepts=accepted,collects=sources,rating=rating} end
  end
  local function report(cargo,fn)
    local n,r=fn(S,st,cargo)
    add(cargo,n,r and r.accepts,r and r.sources and #r.sources>0,r and r.rating)
  end
  if api.farm_tools then
    report("grain",Sim.farm_stop_status)
    report("livestock",Sim.farm_stop_status)
  end
  if api.timber_tools then report("wood",Sim.timber_stop_status) end
  if api.oil_tools then report("oil",Sim.oil_stop_status) end
  if api.farm_tools then report("goods",Sim.farm_stop_status)
  elseif api.timber_tools then report("goods",Sim.timber_stop_status)
  elseif api.oil_tools then report("goods",Sim.oil_stop_status) end
  if Sim.road_coal_active(S) then
    local n,accepted,rating=Sim.coal_stop_status(S,st)
    add("coal",n,accepted,n and n>0,rating)
  end
  if S.road_mail then
    local n,a,r,known=Sim.mail_stop_status(S,st)
    add("mail",n,a,n and n>0,known and r or nil)
  end
  return rows
end
function U.service(p,kind,id)
  if api.authority_handoff then
    if kind=="vehicle" then return api.vehicle_ui.open(p,"road",id) end
    if kind=="fleet" then return U.open_company(p) end
    if kind=="controls" then return U.open_controls(p) end
    if kind=="depot" or kind=="context" then return U.context(p,id) end
    return U.context(p)
  end
  local n=p:get_player_name();local V=view(n)
  local tall=kind=="vehicle"
  local room=kind=="depot" and api.farm_tools and api.oil_tools
  local b={("formspec_version[7]size[9.4,%g]bgcolor[#152334;false]"):format(room and 8.3 or tall and 7.08 or 6.6),
    "style_type[button;bgimg=bl_button.png;bgimg_middle=6;border=false;textcolor=#E5ECEA]",
    "style_type[label;textcolor=#E5ECEA]"}
  local function label(x,y,t)
    b[#b+1]=("label[%g,%g;%s]"):format(x,y,esc(t))
  end
  local function button(x,y,w,k,t)
    b[#b+1]=("button[%g,%g;%g,.56;%s;%s]"):format(x,y,w,k,esc(t))
  end
  local function vehicle_depot(n_,kind_,id_)
    local t=S.tiles[id_]
    if kind_=="depot" then return t and t.owner==n_ and "road",id_ end
    if kind_=="tram_depot_status" then return t and t.tram and t.tram.owner==n_ and "tram",id_ end
    if kind_=="airfield_status" then
      local f=S.stock_small_airports and S.stock_small_airports[id_]
      return f and f.owner==n_ and f.layout~="heliport" and "air",id_
    end
    if kind_=="harbor_status" or kind_=="passenger_depot" or kind_=="cargo_depot" then
      local r=t and t.ship
      return r and r.kind=="ship_depot" and r.owner==n_ and "ship",r and r.depot
    end
  end
  if api.vehicle_ui and vehicle_depot(n,kind,id) then
    V.vehicle_depot_kind,V.vehicle_depot_id=vehicle_depot(n,kind,id)
  else V.vehicle_depot_kind,V.vehicle_depot_id=nil,nil end
  if kind=="vehicle" and (V.service_kind~=kind or V.service_id~=id) then V.service_order=1 end
  V.service_kind=kind;V.service_id=id
  if kind=="controls" or kind=="context" then
    local tile=S.tiles[id]
    if kind=="context" and tile then
      local parcel_name=({market="Market square",shop="The corner grocer",green="Civic green"})[tile.parcel]
      local title=tile.site and S.sites[tile.site].name or
        tile.road_town and (S.sites[tile.road_town].name.." street") or
        tile.build and Sim.tools[tile.build].name or tile.house and (parcel_name or "Town home") or title_case(tile.terrain)
      local x,z=Sim.xy(id)
      label(.4,.45,("%s  ·  %d, %d"):format(title,x,z))
    else label(.4,.45,"LuanTTD   /   Controls") end
    label(.4,1.18,"WASD fly  ·  Space / Shift altitude  ·  Hold E to fly faster")
    label(.4,1.66,"Select a section and left-click to open it.")
    label(.4,2.14,"Inside a section: select a tool, then left-click to use it.")
    label(.4,2.62,kind=="controls" and
      "/walk: street view  ·  /car: drive  ·  Right-click: return to building" or
      "Back returns to the previous hotbar.")
    if kind=="controls" and Workbenches then
      button(.4,3.35,8.6,"service_workbenches","Transport & World Guide")
    end
    if kind=="context" then
      if V.anchor then
        button(.4,3.35,4.14,"service_cancel","Cancel road line")
        button(4.86,3.35,4.14,"service_axis","Switch bend")
      elseif tile and tile.owner==n and tile.build then
        local changes,cost=Sim.plan(S,n,"clear",{id})
        if changes and #changes>0 then
          button(.4,3.35,8.6,"service_clear","Bulldoze "..Sim.tools[tile.build].name:lower().."   ·   "..dollars(cost))
        elseif not changes then label(.4,3.60,cost) end
      end
      if S.chair==n or core.check_player_privs(n,{server=true}) then
        for i,speed in ipairs({0,1,2,4}) do
          button(.4+(i-1)*2.15,4.12,2.0,"service_time_"..speed,speed==0 and "Pause" or speed.."×")
        end
      end
    end
  elseif kind=="growth_house" then
    local tile=S.tiles[id]
    local h=tile and tile.source_house
    if not h or not h.town_growth then return end
    local town=S.sites[h.town]
    label(.4,.45,(town and town.name or "Town").."   /   New building")
    if h.completed then
      label(.4,1.22,"Finished and occupied.")
      label(.4,1.74,h.first_cargo_tick and "Contributes to the town's transport demand." or
        "Passengers and mail are produced on later town ticks.")
    else
      local names={[0]="Preparing foundations",[1]="Framing walls",[2]="Roofing"}
      label(.4,1.22,names[h.stage] or "Under construction")
      label(.4,1.74,"No occupants, passengers or mail until construction is complete.")
    end
  elseif kind=="farm_industry" then
    local ind=S.stock_farm_industries and S.stock_farm_industries[id]
    if not ind then return end
    local site=S.sites[ind.site]
    label(.4,.45,site and site.name or (ind.kind=="farm" and "Highfield Farm" or "Westfield Factory"))
    if ind.removed then label(.4,1.18,"Industry closed.")
    else
      local rows={}
      for _,e in ipairs(ind.produced) do if e.cargo then rows[#rows+1]=e end end
      for i,e in ipairs(rows) do
        local y=.75+i*.63
        label(.4,y,("%s: %s ready on site  •  %s sent to stops this month"):format(
          Sim.cargo[e.cargo].name,number(e.waiting or 0),number(e.current and e.current.transported or 0)))
      end
      if ind.kind=="factory" then
        local r=ind.received or {}
        label(.4,2.18,("Delivered: %s t grain   •   %s head of livestock"):format(number(r.grain or 0),number(r.livestock or 0)))
        label(.4,2.72,"Freight delivery pays separately from taking Goods into town.")
      end
    end
  elseif kind=="oil_industry" then
    local ind=S.stock_oil_industries and S.stock_oil_industries[id]
    if not ind then return end
    local site=S.sites[ind.site]
    label(.4,.45,site and site.name or "Stock oil industry")
    if ind.removed then label(.4,1.18,"Industry closed.")
    else
      local e=ind.produced[1]
      local oil=e.cargo=="oil"
      label(.4,1.25,number(e.waiting or 0)..(oil and " thousand L of crude on site" or " Goods crates awaiting collection"))
      label(.4,1.83,("This month: %s produced  ·  %s sent to loading stops"):format(
        number(e.current and e.current.production or 0),number(e.current and e.current.transported or 0)))
      if not oil then
        label(.4,2.38,number(ind.received and ind.received.oil or 0).." thousand L of crude received")
        label(.4,2.89,"Crude delivery pays here; ship the processed Goods to town for another fare.")
      end
    end
  elseif kind=="timber_industry" then
    local ind=S.stock_timber_industries and S.stock_timber_industries[id]
    if not ind then return end
    local site=S.sites[ind.site]
    label(.4,.45,site and site.name or (ind.kind=="forest" and "Forest" or "Sawmill"))
    local goods=ind.kind=="sawmill"
    label(.4,1.22,number(ind.produced.waiting or 0)..(goods and " goods crates on site" or " tons of wood on site"))
    label(.4,1.72,("This month: %s produced  •  %s collected"):format(
      number(ind.produced.current.production or 0),number(ind.produced.current.transported or 0)))
    if goods then
      local total=(ind.wood_received or 0)+(ind.received and ind.received.wood or 0)
      label(.4,2.28,number(total).." tons of wood received in total.")
    end
    if not api.timber_tools then label(.4,2.84,"Timber service is paused in settings.") end
  elseif kind=="industry" then
    local ind=S.stock_coal_industries and S.stock_coal_industries[id]
    if not ind then return end
    local site=S.sites[ind.site]
    label(.4,.45,site and site.name or "Coal industry")
    if ind.removed then label(.4,1.2,"Industry closed.")
    elseif ind.produced then
      local now=ind.produced.current or {}
      local prior=ind.produced.last or {}
      label(.4,1.2,number(ind.produced.waiting).." tons at the mine, before pickup allocation")
      label(.4,1.74,("This month: %s produced  •  %s sent to stops"):format(number(now.production or 0),number(now.transported or 0)))
      label(.4,2.25,("Last month: %s produced  •  %s sent to stops"):format(number(prior.production or 0),number(prior.transported or 0)))
    elseif ind.accepted then
      label(.4,1.2,number(site and site.received.coal or 0).." tons of coal delivered")
      label(.4,1.74,"Coal is consumed to generate power, with no outbound cargo.")
    end
  elseif kind=="level_crossing_status" then
    local crossing=api.crossings and api.crossings.world.record(S,id)
    if not crossing then return end
    label(.4,.45,"Road / rail level crossing")
    label(.4,1.22,crossing.barred and "Road gates closed." or "Road gates open.")
    label(.4,1.76,crossing.rail_axis==0 and "Rail east–west  ·  Road north–south" or
      "Rail north–south  ·  Road east–west")
    label(.4,2.30,"Vehicles already on the crossing clear before rail enters.")
  elseif kind=="rail_span_status" then
    local span=S.stock_rail_spans and S.stock_rail_spans[id]
    if not span then return end
    local name=span.kind=="bridge" and "Timber railway bridge" or "Railway tunnel"
    label(.4,.45,name.."  ·  "..span.owner)
    label(.4,1.22,span.total_length.." tiles including both portals")
    if span.kind=="bridge" then
      label(.4,1.73,("Rail elevation %d  ·  stock limit 64 km/h"):format(span.deck))
    else label(.4,1.73,("Rail elevation %d  ·  underground"):format(span.base)) end
  elseif kind=="rail_platform_state" then
    local platform=S.stock_rail_stations and S.stock_rail_stations[id]
    if not platform then return end
    label(.4,.45,("Rail platform #%d  ·  %s"):format(id,platform.owner))
    label(.4,1.15,#platform.tiles.." tiles of continuous platform")
    if platform.owner==n and api.trackworks and api.rail_build and not api.rail_build.busy() then
      button(.4,4.32,8.6,"remove_rail_platform","Remove platform, keep the track")
    end
    if platform.coal_role then
      local coal=Sim.rail_coal_stop_status and Sim.rail_coal_stop_status(S,id)
      label(.4,1.68,platform.coal_role=="load" and "Coal loading stage" or "Coal unloading stage")
      if coal then
        label(.4,2.23,number(coal.waiting or 0).." tons waiting")
        label(.4,2.80,coal.accepts and "Accepts coal." or "Serves a coal-producing mine.")
      else label(.4,2.23,"Coal workbench paused in settings.") end
    elseif platform.goods_role then
      local goods=Sim.rail_goods_stop_status(S,id)
      label(.4,1.68,platform.goods_role=="load" and "Goods loading stage · Sawmill" or "Goods receiving stage · Town")
      if goods then
        label(.4,2.23,number(goods.waiting or 0).." crates waiting")
        label(.4,2.80,goods.accepts and "Accepts Goods." or "Loads finished Goods.")
      end
    elseif platform.oil_role then
      local oil=Sim.rail_oil_stop_status and Sim.rail_oil_stop_status(S,id)
      label(.4,1.68,platform.oil_role=="load" and "Oil loading stage · Oil Wells" or "Oil unloading stage · Oil Refinery")
      if oil then
        label(.4,2.23,number((oil.waiting or 0)*1000).." L waiting")
        label(.4,2.80,platform.oil_role=="load" and "Loads oil for the refinery." or
          oil.accepts and "Accepts oil. The refinery makes Goods for road freight." or "The refinery no longer accepts oil here.")
      else label(.4,2.23,"Rail Oil workbench paused in settings.") end
    elseif Freight.role(platform) then
      local cargo=Freight.role(platform)
      local stage=profile_stage_tools["rail_"..cargo.."_"..platform[cargo.."_role"]]
      local q=Sim["rail_"..cargo.."_stop_status"](S,id)
      label(.4,1.68,stage.name)
      if q then label(.4,2.23,number(q.waiting or 0)..(" "..(Freight.profiles[cargo].unit or "tons").." waiting")) end
    end
    local paid=Sim.rail_paid_status and Sim.rail_paid_status(S)
    local waiting=paid and paid.cargo~="mail" and paid.waiting and paid.waiting[id]
    local mail=Sim.rail_mail_stop_status and Sim.rail_mail_stop_status(S,id)
    if mail and not Freight.role(platform) then
      label(.4,3.19,("%s mail bags waiting · %s"):format(number(mail.waiting),
        mail.accepts and "Accepts Mail" or "Not enough nearby houses to accept Mail"))
    end
    if waiting and not Freight.role(platform) then
      label(.4,1.71,number(waiting.waiting or 0).." passengers waiting")
      label(.4,2.28,waiting.accepts and "Accepts passengers." or "Not enough nearby houses to accept passengers.")
      label(.4,2.82,("Shuttle: %d/%d aboard  ·  %s in fares"):format(paid.onboard,paid.capacity,dollars(paid.fare)))
    end
  elseif kind=="tram_depot_status" then
    local running,summary=api.tram.status(n)
    label(.4,.45,"Tram depot")
    if running then label(.4,1.18,summary or "Test streetcar in service.")
    else
      label(.4,1.18,"Connect this depot to two through platforms.")
      button(.4,1.77,8.6,"order_tram_here","Choose streetcar orders")
    end
  elseif kind=="harbor_status" then
    local t=S.tiles[id]
    local r=t and t.ship
    if not r then return end
    local name=({dock="Dock",ship_depot="Ship depot",lock="Ship lock",aqueduct="Aqueduct"})[r.kind] or "Harbor"
    label(.4,.45,name..(r.station and ("  #%d"):format(r.station) or ""))
    if r.kind=="dock" then
      local paid=Sim.ferry_paid_status and Sim.ferry_paid_status(S)
      local waiting=paid and paid.waiting[r.station]
      if waiting then
        label(.4,1.18,number(waiting.waiting or 0).." passengers waiting")
        label(.4,1.72,waiting.accepts and "Accepts passengers." or "Not enough nearby houses to accept passengers.")
        label(.4,2.28,("Ferry: %d/%d aboard  ·  %s in fares"):format(paid.onboard,paid.capacity,dollars(paid.fare)))
      else label(.4,1.18,"Ships use the navigable water alongside the pier.") end
      local coal=api.ship_coal_tools and api.ship_coal.dock(r.station)
      if coal then
        label(.4,3.02,number(coal.waiting or 0).." t of coal waiting")
        label(.4,3.55,coal.accepts and "Accepts coal at a power station." or "No coal recipient in this catchment.")
      end
    elseif r.kind=="ship_depot" and r.owner==n and api.passenger_ferry then
      label(.4,1.22,"Build two docks on the same waterway, near houses.")
      button(.4,1.77,8.6,"open_passenger_depot","Passenger ferries")
      if api.ship_coal_tools then button(.4,2.49,8.6,"open_cargo_depot","Yate cargo ships") end
    elseif r.kind=="ship_depot" and r.owner==n and api.shipyard then
      if api.shipyard.current() then
        label(.4,1.18,"A passenger ferry already has orders in this world.")
      else
        label(.4,1.18,"Build two connected docks near houses.")
        button(.4,1.77,8.6,"order_ferry_here","Choose passenger ferry orders")
      end
    elseif r.kind=="lock" then
      local lock=S.stock_ship_locks and S.stock_ship_locks[r.lock_middle]
      local frame=lock and api.ship_lock_view and api.ship_lock_view.frame(r.lock_middle)
      if frame then
        label(.4,1.18,("Chamber level %d%%  ·  %s"):format(math.floor(frame.phase*100+.5),
          frame.lower and "lower gates open" or frame.upper and "upper gates open" or "both gates closed"))
      end
    end
  elseif kind=="cargo_depot" then
    local r=S.tiles[id] and S.tiles[id].ship
    if not r or r.kind~="ship_depot" or r.owner~=n or not api.ship_coal_tools then return end
    label(.4,.45,"Ship depot / Cargo ships")
      local vessel=api.ship_coal.status()
      if not vessel then
        label(.4,1.20,"Yate Cargo Ship   /   160 cargo units   /   24 km/h")
        local price=math.floor((S.stock_ship_purchase_base or 65000)*128/256)
        if r.owner==n then button(.4,1.77,8.6,"buy_yate","Buy Yate Cargo Ship   /   "..dollars(price)) end
      elseif vessel.owner==n and vessel.depot==r.depot then
        label(.4,1.20,("Yate Cargo Ship   /   %s"):format(vessel.phase or "In depot"))
        if not vessel.mine and vessel.cargo~="coal" and vessel.cargo~=1 then
          local fee=math.floor((S.stock_ship_purchase_base or 65000)*8/1024)
          button(.4,2.10,8.6,"refit_yate","Refit hold for 160 tons of coal   /   "..dollars(fee))
        elseif not vessel.mine then
          label(.4,1.74,"Coal hold ready. Use two docks serving a mine and a power station.")
          button(.4,2.12,8.6,"order_yate_here","Choose coal ship orders")
        else
          label(.4,1.74,("%s/%s t aboard  •  %s in coal revenue"):format(number(vessel.onboard or 0),
            number(vessel.capacity or 160),dollars(vessel.fare or 0)))
          label(.4,2.30,number(vessel.delivered or 0).." tons actually delivered")
          if vessel.failure then label(.4,2.86,tostring(vessel.failure))
          else button(.4,3.07,8.6,vessel.stopped and "resume_yate" or "stop_yate",
            vessel.stopped and "Resume this coal ship" or "Stop this coal ship") end
        end
      else label(.4,1.20,"The cargo preview already has one Yate assigned to another depot.") end
    button(.4,4.32,8.6,"back_to_harbor","Back to ship depot")
  elseif kind=="passenger_depot" then
    local r=S.tiles[id] and S.tiles[id].ship
    local service=api.passenger_ferry
    if not r or r.kind~="ship_depot" or r.owner~=n or not service then return end
    label(.4,.45,"Ship depot / Passenger ferries")
    local u=S.stock_owned_ferry
    local run=api.shipyard.current()
    if u and u.owner==n and u.depot==r.depot then
      local model=service.model(u.engine_id)
      label(.4,1.23,model.name.."  ·  "..model.capacity.." seats")
      if not run and service.staged(n,r.depot) then
        button(.4,1.77,8.6,"order_ferry_here","Choose passenger ferry orders")
      elseif run and run.owned then
        local paid=Sim.ferry_paid_status(S)
        label(.4,1.92,("Passenger fares %s  ·  Operating costs %s"):format(
          dollars(paid and paid.fare or 0),dollars(u.expense or 0)))
        label(.4,2.52,run.failure and ("Route blocked: "..api.shipyard.reason(run.failure))
          or run.stopped and "Stopped" or "In service")
        if not run.failure then button(.4,3.05,8.6,run.stopped and "resume_ferry" or "stop_ferry",
          run.stopped and "Resume passenger ferry" or "Stop passenger ferry") end
      else label(.4,1.90,"The ferry model is not available in this installation.") end
    elseif u or run then
      label(.4,1.22,"This world currently supports one owned passenger ferry.")
    else
      local count=0
      for _,engine in ipairs(service.catalog) do
        local model=service.quote(n,r.depot,engine)
        if model then
          button(.4,1.12+count*.71,8.6,"buy_passenger_ferry_"..engine,
            ("Buy %s  /  %d seats  /  %s"):format(model.name,model.capacity,dollars(model.price)))
          count=count+1
        end
      end
      if count==0 then label(.4,1.22,"No passenger ferry is available at this depot.") end
    end
    button(.4,4.32,8.6,"back_to_harbor","Back to ship depot")
  elseif kind=="airfield_status" then
    local field=S.stock_small_airports and S.stock_small_airports[id]
    if not field then return end
    local heliport=field.layout=="heliport"
    local title=({city="City Airport",metropolitan="Metropolitan Airport",commuter="Commuter Airport",international="International Airport",intercontinental="Intercontinental Airport",heliport="Heliport",helidepot="Helidepot",helistation="Helistation"})[field.layout] or "Country airfield"
    label(.4,.45,("%s #%d  ·  %s"):format(title,id,field.owner))
    if heliport or field.layout=="helidepot" or field.layout=="helistation" then label(.4,1.20,field.flags~=0 and "Helicopter facilities reserved." or "Helicopter facilities clear.")
    else label(.4,1.20,math.floor(field.flags/256)%2==1 and "Runway reserved." or "Runway clear.") end
    local flights=api.airfield.at(id)
    local function air_load(stats)
      local a,b=stats.cargo_onboard,stats.cargo_capacity
      if a then return ("%d/%d passengers, %d/%d Mail bags"):format(a.passenger,b.passenger,a.mail,b.mail) end
      return ("%d/%d passengers"):format(stats.onboard,stats.capacity)
    end
    local unit=api.airfield.owned(id)
    local flight=flights[1]
    if #flights>=2 then
      for i,f in ipairs(flights) do
        local stats=Sim.air_paid_status(S,f.paid_clock)
        local row=1.82+(i-1)*1.09
        label(.4,row,("#%d  %s  ·  %s"):format(f.paid_clock,api.airfield.engine_name(f),f.phase))
        if stats then label(.4,row+.5,("%s  ·  %s fares"):format(air_load(stats),dollars(stats.fare))) end
      end
      local e=Sim.air_paid_status(S,flight.paid_clock)
      if e and e.waiting[id] then
        local stop=e.waiting[id]
        label(.4,4.10,number(stop.waiting or 0).." passengers"..(stop.mail and (" and "..number(stop.mail.waiting).." Mail bags") or "").." waiting")
      end
    elseif flight and (not unit or unit.status=="dispatched") then
      label(.4,1.78,("%s %s  ·  %d terminal stops"):format(api.airfield.engine_name(flight),flight.phase,flight.arrivals))
      local paid=Sim.air_paid_status and Sim.air_paid_status(S,flight.paid_clock)
      local stop=paid and paid.waiting[id]
      if stop then
        label(.4,2.35,number(stop.waiting or 0).." passengers"..(stop.mail and (" and "..number(stop.mail.waiting).." Mail bags") or "").." waiting")
        label(.4,2.90,("Accepts passengers: %s%s"):format(stop.accepts and "yes" or "no",
          stop.mail and ("   Mail: "..(stop.mail.accepts and "yes" or "no")) or ""))
        label(.4,3.49,("%s  ·  %s fares"):format(air_load(paid),dollars(paid.fare)))
        if paid.paused then label(.4,4.04,"Paid air service paused or aircraft model missing.")
        elseif paid.running_expense then label(.4,4.04,dollars(paid.running_expense).." in running costs") end
      end
    elseif heliport then
      label(.4,1.78,"Helicopters only. This station has no hangar.")
      label(.4,2.31,"Buy and order a helicopter from another airport's hangar.")
    elseif S.air_owned_preview then
      if unit then
        if unit.owner==n and unit.hangar==id then
          label(.4,1.78,"Aircraft ready in this hangar.")
          button(.4,2.28,8.6,"order_aircraft_here","Choose destination airfield")
        else label(.4,1.78,"The preview aircraft belongs to another hangar.") end
      elseif field.owner==n then
        local shown=0
        for _,e in ipairs(api.airfield.catalog()) do
          local quote=api.airfield.quote(n,id,e.stock_id)
          if quote then
            button(.4,1.60+shown*.67,8.6,"buy_aircraft_"..e.stock_id,
              ("Buy %s / %d seats + %d Mail / %s"):format(e.name,quote.passengers,quote.mail,dollars(quote.price)))
            shown=shown+1
          end
        end
        if shown==0 then label(.4,1.78,"No aircraft available for this hangar.") end
        label(.4,3.82,S.air_fleet_preview and "Two Sampsons can share. Other aircraft fly solo."
          or "One aircraft per preview. Carries passengers and Mail.")
      end
    else label(.4,1.78,"Use Order trimotor in the Airfields hotbar.") end
  elseif kind=="fleet" then
    label(.4,.45,"YOUR ROAD FLEET")
    local rows=sorted(S.fleet,n)
    if #rows==0 then label(.4,1.2,"Build a road depot, then click it to buy your first bus.") end
    local max_page=math.max(1,math.ceil(#rows/6))
    V.fleet_page=limit(V.fleet_page or 1,1,max_page)
    local first=(V.fleet_page-1)*6
    for j=1,math.min(6,#rows-first) do
      local v=S.fleet[rows[first+j]]
      button(.4,1.0+(j-1)*.59,8.6,"vehicle_"..v.id,v.name.."  /  "..v.status.."  /  "..dollars(v.revenue-v.expense))
    end
    if max_page>1 then
      if V.fleet_page>1 then button(.4,4.73,2.3,"fleet_previous","Previous") end
      label(3.19,5.0,("Page %d of %d"):format(V.fleet_page,max_page))
      if V.fleet_page<max_page then button(6.7,4.73,2.3,"fleet_next","Next") end
    end
  elseif kind=="depot" then
    local t=S.tiles[id]
    if not t or t.build~="road_depot" then return end
    label(.4,.45,"ROAD DEPOT   /   "..t.owner)
    if S.stock_bus_market then
      local options={}
      for _,v in ipairs({{"bus","depot_buy","Regal"},{"leopard_bus","depot_buy_leopard","Leopard"},
          {"foster_bus","depot_buy_foster","Foster"},{"foster_mk2_bus","depot_buy_superbus","Superbus"}}) do
        if Sim.vehicle_available(S,v[1]) then options[#options+1]=v end
      end
      if #options==0 then label(.4,1.25,"No original buses are on sale right now.") end
      local width=math.min(4.15,(8.65-.18*math.max(0,#options-1))/math.max(1,#options))
      for i,v in ipairs(options) do
        local x=.4+(i-1)*(width+.18)
        local bus=Sim.vehicle_offer(S,v[1])
        label(x,1.22,#options>2 and v[3] or bus.name)
        label(x,1.68,bus.capacity.." seats  •  "..dollars(bus.cost))
        if t.owner==n then button(x,2.08,width,v[2],"Buy "..v[3]) end
      end
    else
      local bus=Sim.vehicle_offer(S,"bus")
      label(.4,1.22,bus.name)
      label(.4,1.68,bus.capacity.." passengers   •   "..dollars(bus.cost))
      if t.owner==n then
        button(.4,2.08,4.1,"depot_buy","Buy bus")
        local leopard=Sim.vehicles.leopard_bus
        if Sim.date(S)>=leopard.year then
          label(4.75,1.22,leopard.name)
          label(4.75,1.68,leopard.capacity.." passengers   •   "..dollars(leopard.cost))
          button(4.75,2.08,4.1,"depot_buy_leopard","Buy Leopard")
        end
      end
    end
    local y,options=2.72,{}
    local function offer(enabled,key,engine,short)
      if not enabled or t.owner~=n or not Sim.vehicle_available(S,engine) then return end
      local model=Sim.vehicle_offer(S,engine)
      options[#options+1]={key=key,label=short.." / "..dollars(model.cost)}
    end
    offer(api.farm_tools,"grain","grain_truck","Buy grain truck")
    offer(api.farm_tools,"livestock","livestock_van","Buy livestock van")
    offer(api.oil_tools,"oil","oil_tanker","Buy oil tanker")
    offer(api.timber_tools,"wood","wood_truck","Buy wood truck")
    for _,engine in ipairs(Sim.road_extra_freight()) do
      local e=Sim.vehicles[engine]
      offer(true,"extra_"..engine,engine,"Buy "..e.name)
    end
    offer(api.timber_tools or api.farm_tools or api.oil_tools,"goods","goods_truck","Buy goods truck")
    offer(S.road_mail,"mail","mail_van","Buy post van")
    offer(Sim.road_coal_active(S),"coal","coal_tipper","Buy coal tipper")
    offer(true,"craighead","craighead_goods_truck","Buy Craighead Goods Truck")
    local short=options[#options]
    if short and short.key=="craighead" then options[#options]=nil end
    for i,opt in ipairs(options) do
      button(i%2==1 and .4 or 4.86,y+math.floor((i-1)/2)*.60,4.14,"depot_buy_"..opt.key,opt.label)
    end
    y=y+math.ceil(#options/2)*.60
    if short and short.key=="craighead" then
      button(.4,y,8.6,"depot_buy_craighead",short.label)
      y=y+.60
    end
    local parked={}
    for _,i in ipairs(sorted(S.fleet)) do
      local v=S.fleet[i]
      if v.depot==id then parked[#parked+1]=i end
    end
    for j=1,math.min(math.floor(((room and 6.50 or 4.45)-y)/.57)+1,#parked) do
      local i=parked[j]
      button(.4,y+.08+(j-1)*.57,8.45,"vehicle_"..i,S.fleet[i].name.."   /   "..S.fleet[i].status)
    end
  elseif kind=="stop" then
    local st=S.stations[id]
    if not st then return end
    label(.4,.45,st.name)
    local waiting=0
    if st.stop_type=="truck" then
      for i,row in ipairs(U.freight_snapshot(st)) do
        local note=row.accepts and "Accepts" or row.collects and "Collects" or "No supplier or receiver"
        local rating=row.rating and ("  ·  Rating "..math.floor(row.rating*100/255+.5).."%") or ""
        label(.4,.60+i*.52,("%s: %s waiting   •   %s%s"):format(Sim.cargo[row.cargo].name,
          number(row.count),note,rating))
      end
    elseif S.road_economy and Sim.waiting_passengers then
      waiting=Sim.waiting_passengers(S,st)
      label(.4,1.22,number(waiting).." passengers waiting")
      local rating,known,active=Sim.passenger_rating(S,st)
      if known then label(.4,2.68,("Passenger rating: %d%%"):format(math.floor(rating*100/255+.5))) end
      if not st.passenger_service_day then
        label(.4,2.20,"Waiting for its first scheduled bus.")
      elseif not active then
        label(.4,2.20,"No recent service. Resume pickups to attract passengers.")
      elseif st.last_service.passenger then
        label(.4,2.20,"Last pickup: "..number(S.day-st.last_service.passenger).." days ago")
      else label(.4,2.20,"Service started; passengers are gathering.") end
    else
      for _,sid in ipairs(st.served) do waiting=waiting+(S.sites[sid].stock.passenger or 0) end
      label(.4,1.22,number(waiting).." passengers available in catchment")
    end
    local town=S.sites[st.site]
    local acceptance=Sim.road_passenger_acceptance and Sim.road_passenger_acceptance(S,st.tile)
    if acceptance and st.stop_type~="truck" then
      label(.4,1.7,(town and "Near "..town.name.."  ·  " or "")..
        (acceptance>=8 and "Accepts passengers" or "No passenger acceptance"))
    elseif town and st.stop_type~="truck" then
      label(.4,1.7,"Serves: "..town.name)
    end
    local bay=Sim.road_bay_status and Sim.road_bay_status(S,st.tile)
    if bay and st.stop_type~="truck" then
      label(.4,3.26,("Bay 1: %s   /   Bay 2: %s"):format(bay.first and "occupied" or "free",bay.second and "occupied" or "free"))
      label(.4,3.72,bay.entrance and "Shared entrance occupied." or "Shared entrance clear.")
    end
  elseif kind=="order_list" then
    local v=S.fleet[id]
    if not v or v.owner~=n then return end
    label(.4,.45,"ORDER LIST   /   "..v.name)
    local peers,rows={},{}
    for _,i in ipairs(sorted(S.fleet,n)) do
      local other=S.fleet[i]
      if i~=id and Sim.vehicles[other.engine].mode=="road" then
        peers[#peers+1]=i
        local shared=v.order_group and v.order_group==other.order_group
        rows[#rows+1]=esc(("%s   /   %d orders%s"):format(other.name,#other.orders,shared and "   ·   linked" or ""))
      end
    end
    V.order_list_peers=peers
    V.order_list_selected=limit(V.order_list_selected or 1,1,math.max(1,#peers))
    label(.4,1.03,"Select a source. Copy is independent; Share links later edits.")
    b[#b+1]="textlist[.4,1.55;8.6,2.06;order_list_sources;"..
      (#rows>0 and table.concat(rows,",") or "No other vehicles")..";"..V.order_list_selected..";false]"
    if #peers>0 then
      button(.4,3.87,2.67,"order_list_copy","Copy orders")
      button(3.2,3.87,2.76,"order_list_share","Share orders")
    end
    if v.order_group then button(6.1,3.87,2.90,"order_list_unshare","Stop sharing") end
    button(.4,4.49,8.6,"order_list_return","Back to vehicle orders")
  elseif kind=="vehicle" then
    local v=S.fleet[id]
    if not v then return end
    local reliability=Sim.road_fault_rating(S,v)
    label(.4,.45,v.name.."   /   "..v.status..
      (reliability and ("   ·   Reliability "..reliability.."%") or ""))
    label(.4,1.00,number(v.units).." / "..Sim.vehicle_capacity(v).." aboard    •    Operating profit "..dollars(v.revenue-v.expense))
    local linked=v.order_group and #Sim.road_order_members(S,id) or 1
    label(.4,1.6,linked>1 and ("ORDERS   ·   Shared with "..(linked-1).." other vehicle"..(linked==2 and "" or "s")) or "ORDERS")
    if v.owner==n and not v.running and not v.route and not v.road_return_depot and
        Sim.vehicles[v.engine].mode=="road" then
      button(6.26,.91,2.74,"order_list_open","Copy / share…")
    end
    if api.vehicle_ui and v.owner==n then button(6.26,1.43,2.74,"common_vehicle","Orders & follow") end
    local rows={}
    for i,o in ipairs(v.orders) do
      local st=S.stations[o.station]
      local action=({full="   /   Full load",unload="   /   Unload only",transfer="   /   Transfer"})[o.action] or ""
      rows[#rows+1]=esc(("%d   Go to %s%s"):format(i,st and st.name or "Missing stop",action))
    end
    b[#b+1]="textlist[.4,1.92;8.6,1.86;service_orders;"..(#rows>0 and table.concat(rows,",") or "No stops selected")..";"..(V.service_order or 1)..";false]"
    if v.owner==n then
      if not v.running and not v.route then
        button(.4,4.04,3.04,"service_pick","Add stops")
        button(3.59,4.04,2.53,"service_delete","Remove order")
        if #v.orders>0 then button(.4,4.59,5.72,"service_cycle_load","Selected order: toggle full load") end
        if Sim.road_can_park(S,n,v.id) then button(6.26,4.59,2.74,"service_park","Park in depot") end
      end
      if not v.road_return_depot then
        button(6.26,4.04,2.74,"service_toggle",v.stop_requested and "Cancel stop" or v.running and "Stop service" or "Start service")
      end
    end
  end
  label(.4,room and 6.90 or tall and 5.49 or 5.02,V.service_note or "")
  local footer=room and 7.51 or tall and 6.10 or 5.61
  if V.vehicle_depot_kind then button(.4,footer,4.14,"depot_vehicle_list","Depot vehicles / Follow") end
  local narrow=not not V.vehicle_depot_kind
  button(narrow and 4.86 or .4,footer,narrow and 4.14 or 8.6,"service_back","Back to world")
  core.show_formspec(n,"luanttd_core:service",table.concat(b))
end
function U.service_fields(p,f)
  local n=p:get_player_name();local V=view(n)
  local kind,id=V.service_kind,V.service_id
  if f.quit or f.service_back then core.close_formspec(n,"luanttd_core:service");return true end
  if f.depot_vehicle_list and api.vehicle_ui and V.vehicle_depot_kind then
    core.close_formspec(n,"luanttd_core:service")
    return api.vehicle_ui.depot(p,V.vehicle_depot_kind,V.vehicle_depot_id,function() U.service(p,kind,id) end)
  end
  if f.common_vehicle and kind=="vehicle" and api.vehicle_ui then
    core.close_formspec(n,"luanttd_core:service")
    return api.vehicle_ui.open(p,"road",id)
  end
  if kind=="controls" and f.service_workbenches and Workbenches then
    core.close_formspec(n,"luanttd_core:service")
    return U.open_workbenches(p)
  end
  if kind=="context" then
    if f.service_cancel then V.anchor=nil; V.status="Road line canceled." end
    if f.service_axis then V.zfirst=not V.zfirst;V.status=V.zfirst and "Road bends Z then X." or "Road bends X then Z." end
    if f.service_clear and id and S.tiles[id] and S.tiles[id].owner==n then
      local ok,note,changed=Sim.build(S,n,"clear",{id})
      V.status=note
      if ok then R.update(changed);api.save() end
    end
    if S.chair==n or core.check_player_privs(n,{server=true}) then
      for _,speed in ipairs({0,1,2,4}) do if f["service_time_"..speed] then S.speed=speed;api.save() end end
    end
    core.close_formspec(n,"luanttd_core:service");return true
  elseif kind=="rail_platform_state" and f.remove_rail_platform then
    local platform=S.stock_rail_stations and S.stock_rail_stations[id]
    if platform and platform.owner==n and U.layer_bulldozer then return U.layer_bulldozer.open(p,platform.tiles[1]) end
    return true
  elseif kind=="tram_depot_status" then
    if f.order_tram_here and api.tram and api.tram.facility(n,id,"depot") and not api.tram.status(n) and
        api.world and api.world.begin_order_selection then
      U.select_tool(p,"tram_order")
      local label=U.begin_fixed_route(p,"tram_order")
      V.anchor=id
      V.status="Depot selected. Pick the first through platform."
      api.world.begin_order_selection(p,"fixed",label)
      core.close_formspec(n,"luanttd_core:service")
      return true
    end
  elseif kind=="harbor_status" or kind=="passenger_depot" or kind=="cargo_depot" then
    local part=id and S.tiles[id] and S.tiles[id].ship
    if part and part.kind=="ship_depot" and part.owner==n then
      if kind=="harbor_status" then
        if f.open_passenger_depot and api.passenger_ferry then V.service_note=nil;U.service(p,"passenger_depot",id);return true end
        if f.open_cargo_depot and api.ship_coal_tools then V.service_note=nil;U.service(p,"cargo_depot",id);return true end
      elseif f.back_to_harbor then V.service_note=nil;U.service(p,"harbor_status",id);return true end
      local ferry=api.passenger_ferry
      local c=kind=="cargo_depot" and api.ship_coal_tools and api.ship_coal
      local vessel=c and c.status()
      local can_order=ferry and kind=="passenger_depot" and ferry.staged(n,part.depot)
        or not ferry and kind=="harbor_status" and api.shipyard and not api.shipyard.current()
      local order=f.order_ferry_here and can_order and "ship_order" or
        f.order_yate_here and vessel and vessel.owner==n and vessel.depot==part.depot and not vessel.mine and
        (vessel.cargo=="coal" or vessel.cargo==1) and "ship_coal_order"
      if order and api.world and api.world.begin_order_selection then
        U.select_tool(p,order)
        local label=U.begin_fixed_route(p,order)
        if order=="ship_order" then V.ferry_depot=part.depot;V.status="Depot selected. Pick your first dock." end
        api.world.begin_order_selection(p,"fixed",label)
        core.close_formspec(n,"luanttd_core:service")
        return true
      end
      local receipt,note
      if kind=="passenger_depot" and ferry then
        for _,engine in ipairs(ferry.catalog) do
          if f["buy_passenger_ferry_"..engine] then receipt,note=ferry.buy(n,part.depot,engine);break end
        end
        local u=S.stock_owned_ferry
        if (f.stop_ferry or f.resume_ferry) and u and u.depot==part.depot then
          receipt,note=ferry.stop(n,not not f.stop_ferry)
        end
      elseif c and f.buy_yate then receipt,note=c.buy(n,part.depot)
      elseif vessel and vessel.owner==n and vessel.depot==part.depot then
        if f.refit_yate then receipt,note=c.refit(n)
        elseif f.stop_yate then receipt,note=c.set_stopped(n,true)
        elseif f.resume_yate then receipt,note=c.set_stopped(n,false) end
      end
      if note then V.service_note=tostring(note) end
      if receipt then api.save() end
    end
  elseif kind=="airfield_status" and S.air_owned_preview then
    if f.order_aircraft_here and api.world and api.world.begin_order_selection then
      local function air_load(stats)
      local a,b=stats.cargo_onboard,stats.cargo_capacity
      if a then return ("%d/%d passengers, %d/%d Mail bags"):format(a.passenger,b.passenger,a.mail,b.mail) end
      return ("%d/%d passengers"):format(stats.onboard,stats.capacity)
    end
    local unit=api.airfield.owned(id)
      if unit and unit.owner==n and unit.hangar==id and unit.status=="hangar" then
        U.select_tool(p,"airfield_order")
        U.begin_fixed_route(p,"airfield_order")
        V.airport_first=id
        V.status="Departure selected. Pick a different airfield."
        api.world.begin_order_selection(p,"fixed","Aircraft orders")
        core.close_formspec(n,"luanttd_core:service")
        return true
      end
    end
    for _,engine in ipairs(api.airfield.catalog()) do
      if f["buy_aircraft_"..engine.stock_id] then
        local unit,note=api.airfield.buy(n,id,engine.stock_id)
        V.service_note=unit and "Aircraft purchased. Choose a destination to start orders." or note
        break
      end
    end
  elseif kind=="fleet" then
    if f.fleet_previous or f.fleet_next then
      V.fleet_page=(V.fleet_page or 1)+(f.fleet_next and 1 or -1)
    end
    for k in pairs(f) do
      local v=S.fleet[tonumber(k:match("^vehicle_(%d+)$"))]
      if v and v.owner==n then V.service_note=nil;U.service(p,"vehicle",v.id);return true end
    end
  elseif kind=="depot" then
    local t=S.tiles[id]
    if not t or t.owner~=n or t.build~="road_depot" then return true end
    local extra
    for _,engine in ipairs(Sim.road_extra_freight()) do
      if f["depot_buy_extra_"..engine] then extra=engine;break end
    end
    if extra or f.depot_buy_superbus or f.depot_buy or f.depot_buy_leopard or f.depot_buy_foster or f.depot_buy_mail or f.depot_buy_coal or
        f.depot_buy_wood or f.depot_buy_goods or f.depot_buy_grain or f.depot_buy_livestock or f.depot_buy_oil or f.depot_buy_craighead then
      local model=extra or f.depot_buy_superbus and "foster_mk2_bus" or f.depot_buy_craighead and "craighead_goods_truck" or f.depot_buy_oil and "oil_tanker" or f.depot_buy_grain and "grain_truck" or f.depot_buy_livestock and "livestock_van" or
        f.depot_buy_wood and "wood_truck" or f.depot_buy_goods and "goods_truck" or
        f.depot_buy_coal and "coal_tipper" or f.depot_buy_mail and "mail_van" or f.depot_buy_leopard and "leopard_bus" or
        f.depot_buy_foster and "foster_bus" or "bus"
      local cargo=Sim.road_freight_cargo(model) or "passenger"
      local v,note=Sim.purchase(S,n,model,cargo,nil,id)
      V.service_note=note
      if v then api.save();U.service(p,"vehicle",v);return true end
    end
    for k in pairs(f) do
      local v=S.fleet[tonumber(k:match("^vehicle_(%d+)$"))]
      if v and v.depot==id then V.service_note=nil;U.service(p,"vehicle",v.id);return true end
    end
  elseif kind=="order_list" then
    local v=S.fleet[id]
    if not v or v.owner~=n then return true end
    if f.order_list_return then V.service_note=nil;U.service(p,"vehicle",id);return true end
    if f.order_list_sources then
      local e=core.explode_textlist_event(f.order_list_sources)
      if e and e.index and V.order_list_peers and V.order_list_peers[e.index] then
        V.order_list_selected=e.index
      end
      return true
    end
    local action=f.order_list_copy and "copy" or f.order_list_share and "share" or f.order_list_unshare and "unshare"
    if action then
      local from=V.order_list_peers and V.order_list_peers[V.order_list_selected]
      local ok,note=Sim.clone_road_orders(S,n,id,from,action)
      V.service_note=note
      if ok then
        V.service_order=1;api.save();U.service(p,"vehicle",id);return true
      end
    end
  elseif kind=="vehicle" then
    local v=S.fleet[id]
    if not v or v.owner~=n then return true end
    if f.order_list_open and not v.running and not v.route and not v.road_return_depot and
        Sim.vehicles[v.engine].mode=="road" then
      V.order_list_selected=1;V.service_note=nil;U.service(p,"order_list",id);return true
    end
    if f.service_orders then
      local e=core.explode_textlist_event(f.service_orders)
      if not e or not e.index or e.index<1 or e.index>#v.orders then return true end
      V.service_order=e.index
      return true
    end
    if f.service_pick and not v.running and not v.route then
      V.pick_order=id;V.order_feedback=nil
      V.anchor,V.rail_press,V.rail_ghost,V.road_press,V.demolition_anchor=nil,nil,nil,nil,nil
      if api.world and api.world.begin_order_selection then api.world.begin_order_selection(p) end
      core.close_formspec(n,"luanttd_core:service");return true
    end
    local ok,note
    if f.service_delete then ok,note=Sim.edit_order(S,n,id,V.service_order or 1,"remove") end
    if f.service_cycle_load then ok,note=Sim.edit_order(S,n,id,V.service_order or 1,"cycle_load") end
    if f.service_toggle then ok,note=Sim.toggle(S,n,id) end
    if f.service_park then ok,note=Sim.park_road_vehicle(S,n,id) end
    if note then V.service_note=note end
    if ok then api.save() end
    if ok and (f.service_toggle or f.service_park) then
      V.status=note;core.close_formspec(n,"luanttd_core:service");return true
    end
  end
  U.service(p,kind,id)
  return true
end

return U
end
