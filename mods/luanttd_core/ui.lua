return function(api)
local Sim,S,R=api.Sim,api.s,api.render
local U={}
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
local function date()
  local y,m,d=Sim.date(S)
  return ("%02d %s %d"):format(d,({"JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"})[m],y)
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
  local t=id and S.tiles[id]
  if not t or t.stock_void then return false end
  local x,z=Sim.xy(id)
  local cx,cz=x*2+.5,z*2+.5
  local h=(t.h or 0)+.5
  if api.terrain and R.uses_slope(id) then h=math.max(h,R.surface(id,cx,cz)) end
  local function higher(index,spans)
    local span=index and spans and spans[index[id]]
    if span and span.deck then h=math.max(h,span.deck+1) end
  end
  higher(S.bridge_above,S.stock_road_bridges)
  higher(S.rail_bridge_above,S.stock_rail_spans)
  higher(S.aqueduct_above,S.stock_aqueducts)
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
  if U.signal_ui then U.signal_ui.leave(n) end
end
function U.hud()
  for _,p in ipairs(core.get_connected_players()) do
    local n=p:get_player_name();local c=S.companies[n]
    if c then
      local message="LuanTTD   •   "..date().."   •   "..dollars(c.cash).."   •   Inventory: Control desk"
      local V=view(n)
      if not hud[n] then
        hud[n]=p:hud_add({type="text",position={x=.5,y=.05},alignment={x=0,y=0},offset={x=0,y=0},
          text=message,number=0xffffff,z_index=100,scale={x=100,y=100}})
      elseif message~=V.hud_line then p:hud_change(hud[n],"text",message) end
      V.hud_line=message
      if V.live and V.tab=="map" and S.day-(V.last_live or -10)>=math.max(1,S.speed) then
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
function U.fields(p,formname,f)
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
    if f.bl_tutorials and Tutorials then return Tutorials.open(p) end
    if f.bl_guide then return U.open_workbenches(p) end
    if f.bl_help then U.open_controls(p);return true end
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
    if f.map_zoom then V.map_zoom=not V.map_zoom;U.open(p);return true end
    local id=JumpMap.pick(V,f)
    if id then center(V,id);U.survey(p,id);return true end
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
      "button[.4,3.54;8.58,.67;bl_tutorials;Tutorials: Road, Train & Boat]")
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
  view(p:get_player_name()).tab="map"
  U.open(p)
end
function U.select_tool(p,tool)
  local V=view(p:get_player_name())
  if V.tool~=tool then
    V.tool=tool;V.road_press=nil;V.demolition_anchor=nil;V.anchor=nil;V.rail_press=nil;V.rail_ghost=nil;V.rail_first=nil;V.airport_first=nil;V.ferry_depot=nil;V.ferry_first=nil;V.ship_coal_first=nil;V.tram_first=nil;V.ferry_via=nil
  end
end
function U.open_finance(p)
  view(p:get_player_name()).tab="ledger";U.open(p)
end
function U.open_workbenches(p)
  if Workbenches then return Workbenches.open(p) end
  return false
end
function U.open_controls(p)
  if api.road_first then U.service(p,"controls");return end
  view(p:get_player_name()).tab="help";U.open(p)
end
function U.open_company(p)
  if api.road_first then U.service(p,"fleet");return end
  view(p:get_player_name()).tab="fleet"
  U.open(p)
end
function U.phase(p)
  local n=p:get_player_name()
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
    return "Connect track, two stations and a depot. Right-click the depot to buy a train and set its orders."
  end
  if menu=="harbor" then return "Place a dock on a straight sloping shore, and a ship depot in open water." end
  if menu=="airfields" then return "Build two airfields. Right-click one to buy an aircraft and start its orders." end
  if menu=="freight" then
    for _,id in ipairs(sorted(S.fleet,n)) do
      local v=S.fleet[id]
      if v.cargo=="coal" and v.running then
        local next_order=#v.orders>0 and v.orders[v.index%#v.orders+1]
        local stop=S.stations[v.dest or next_order and next_order.station]
        return v.units.." t coal aboard"..(stop and ("   ·   Next: "..U.stop_label(stop)) or "")
      end
    end
    if api.timber_tools then return "Connect two truck stops. Inspect each stop to see which cargo it supplies or accepts." end
    if api.oil_tools then
      return "Connect the oil wells, refinery and town. Buy the Oil Tanker and Goods Truck at a depot."
    end
    if api.farm_tools then
      return "Build freight stops at the farm, factory and town. Buy the three freight vehicles at your depot."
    end
    return "Build truck stops near the mine and power station, then buy a coal tipper at the depot."
  end
  if menu=="tramway" and api.tram then
    local running,summary=api.tram.status(n)
    return running and summary or "Build a dedicated line, depot and two through stops. Then choose Order test streetcar."
  end
  if menu=="terrain" then
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
    api.road_bay_tools and "2 / 6   Open Bus Stops. Place two roadside stops on existing straight streets."
      or "2 / 6   Choose Bus stop and build one at each end.",
    "3 / 6   Choose Road depot. Aim at flat land beside the same street network.",
    "4 / 6   Right-click the depot and buy a bus.",
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
  return V.demolition_anchor or (V.road_press and V.road_press.id) or (V.rail_press and V.rail_press.id) or V.anchor
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
  if S.chair~=n and not core.check_player_privs(n,{server=true}) then
    U.status(p,"Only the first company or server admin can change time.");return
  end
  local speed=({pause=0,normal_speed=1,fast=4})[key]
  if speed then
    S.speed=speed;api.save()
    U.status(p,speed==0 and "Simulation paused." or ("Simulation speed: "..speed.."×"))
  end
end
local function asset_details(p,tile)
  local t=tile and S.tiles[tile]
  if not t then return false end
  local dispatch=S.stock_rail_dispatch
  if U.signal_ui and dispatch and dispatch.signals and dispatch.signals.records[tile] and api.rail_build and
      U.signal_ui.inspect(p,tile) then return true end
  if t.rail_depot_dir~=nil and api.owned_rail_ui and api.owned_rail_ui.open(p,tile) then return true end
  if t.house and t.source_house and t.source_house.town_growth then U.service(p,"growth_house",tile)
  elseif t.stock_landmark then
    local record=t.stock_landmark
    local town=S.sites[record.town]
    local label=record.kind=="lighthouse" and "Lighthouse" or "Radio transmitter"
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
  local ok,msg=api.tram.clear(p:get_player_name())
  V.status=msg
  if ok then V.anchor,V.tram_first=nil,nil end
end
local function tram_request(V,id)
  local mode=tram_mode[V.tool]
  local d=V.tram_dir or 2
  if not mode then return end
  if V.tool=="tram_track" then return mode,V.anchor and Sim.line(V.anchor,id,V.zfirst) or {id} end
  if V.tool=="tram_bit" then return mode,{id},8/2^d,tram_dir[d] end
  if V.tool=="tram_stop" then return mode,{id},d%2,d%2==0 and "East–West" or "North–South" end
  return mode,{id},d,tram_dir[d]
end
local ship_mode={ship_dock="dock",ship_depot="depot",ship_remove="remove",ship_aqueduct="aqueduct",ship_canal="canal",ship_lock="lock"}
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
  V.ship_axis=1-(V.ship_axis or 0)
  V.status=V.ship_axis==0 and "Ship depot: East–West." or "Ship depot: North–South."
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
  if st.oil_role or st.goods_role then return nil,"Choose a platform without another freight stage." end
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
  if st.coal_role then return nil,"Choose a platform without a coal stage." end
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
  if st.coal_role or st.oil_role or st.goods_role and st.goods_role~=tool.role then
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
  HOST_FLAT_ONLY="This crossing preview requires a flat tile.",
  OCCUPANCY_UNKNOWN="Cannot verify the tile is clear yet.",
  RESERVATION_UNKNOWN="Cannot verify the track reservation yet.",
  VEHICLE_IN_THE_WAY="Wait for the vehicle to leave the crossing site.",
  ALREADY_BUILT="A crossing already occupies that tile.",
  STALE_QUOTE="The crossing site changed. Aim at it again.",
  CROSSING_ON_ONEWAY_ROAD="Remove the one-way restriction before building a crossing.",
  NOT_ENOUGH_MONEY="Your company cannot afford the crossing.",
}
local function crossing_quote(n,id)
  local t=S.tiles[id]
  local request
  if t and not t.level_crossing then
    if t.build=="road" and not t.rail_tracks then
      local bits=Sim.road_bits(S,id)
      local track=({[1]=0,[4]=0,[5]=0,[2]=1,[8]=1,[10]=1})[bits]
      if track~=nil then request={kind="rail",track=track} end
    elseif t.build=="stock_rail" and (t.rail_tracks==1 or t.rail_tracks==2) then
      request={kind="road",pieces=t.rail_tracks==1 and 5 or 10}
    end
  end
  if not request then
    return nil, crossing_errors[t and t.level_crossing and "ALREADY_BUILT" or "NEEDS_PLAIN_ROAD_OR_RAIL"]
  end
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
  V.rail_press={id=id,point=rail_point(id,hit)}
  return true
end
function U.cancel_autorail(p)
  local V=view(p:get_player_name())
  if not V.rail_press then return end
  V.rail_press,V.rail_ghost=nil,nil
  V.status="Rail drag canceled."
end
function U.end_autorail(p,id,hit)
  local n=p:get_player_name()
  local V=view(n)
  if not V.rail_press or not U.rail_gesture(V.tool) then return end
  if not hit then U.cancel_autorail(p);return end
  local start=V.rail_press.point
  V.rail_press,V.rail_ghost=nil,nil
  local plan,why=api.rail_build.quote_autotrack(n,start,rail_point(id,hit))
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
function U.rail_overlay(p,id)
  local V=view(p:get_player_name())
  if V.tool~="rail_autotrack" or not id or V.pick_order or
      api.owned_rail_ui and api.owned_rail_ui.active(p) then return end
  local ghost=V.rail_ghost
  if ghost and ghost.id==id then return ghost.pieces end
end
local function quote_rail(n,V,id)
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
  elseif tool=="rail_depot_tool" then return r.quote_depot(n,id,d)
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
  local ok,msg=api.shipyard.clear(n)
  if ok then V.ferry_depot,V.ferry_first,V.ferry_via=nil,nil,nil end
  V.status=msg
end
local airfield_tools={airfield_build={name="Build country airfield"},airfield_remove={name="Dismantle airfield"}}
local airfield_order={name=S.air_owned_preview and "Order aircraft" or "Order trimotor"}
local function airport_order_target(n,V,id)
  if not S.air_fleet_preview and api.airfield.current() then
    return nil,S.air_owned_preview and "This aircraft already has its route." or "Clear the active flight before ordering another."
  end
  local field=api.airfield.network.airport_for(S,id)
  if not field or field.owner~=n then return nil,"Choose one of your country airfields." end
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
  if quote then field,why,bad=api.airfield.network.quote(s,name,origin)
  else field,why,bad=api.airfield.network.build(s,name,origin) end
  if not field then return nil,why,bad end
  local tiles={}
  for i,tile in ipairs(field.tiles) do tiles[i]=tile.id end
  return tiles,field.price,field.ground/8
end
-- Use the same ownership/occupancy-aware demolition authority regardless of
-- the active construction toolbar. Do not clear a span or descriptor by
-- erasing one tile record; the specialised command owns the entire structure.
local function clear_structure(n,id,preview)
  local t=S.tiles[id]
  local function span_ids(s)
    local ids={s.start}
    for _,i in ipairs(s.middle) do ids[#ids+1]=i end
    ids[#ids+1]=s["end"]
    return ids
  end
  if t.road_bridge_id and api.structure_tools then
    local ok,msg,changed,level=Sim.remove_wood_bridge(S,n,id,preview)
    if preview then
      return true,ok and span_ids(changed) or nil,ok and "Dismantle this entire road bridge." or msg
    end
    return true,ok and changed or nil,msg,level
  elseif t.road_tunnel_id and api.structure_tools then
    if preview then
      local span=S.stock_road_tunnels and S.stock_road_tunnels[t.road_tunnel_id]
      if not span or span.owner~=n then return true,nil,"Select your own road tunnel." end
      return true,{span.start,span["end"]},"Request demolition of both road tunnel portals."
    end
    local ok,msg,changed=Sim.remove_road_tunnel(S,n,id)
    return true,ok and changed or nil,msg
  elseif t.rail_span_id and api.rail_spans then
    if preview then
      local span=api.rail_spans.by_portal(S,id)
      if not span or span.owner~=n then return true,nil,"Select your own rail bridge or tunnel." end
      return true,span_ids(span),"Request demolition of the entire rail "..span.kind.."."
    end
    local ok,msg,changed,level=api.rail_spans.clear(S,n,id)
    return true,ok and changed or nil,msg,level
  elseif t.airfield and api.airfield then
    local changed,price,level=airfields(S,n,"airfield_remove",id,preview)
    return true,changed,changed and ("Dismantle airfield  |  "..dollars(price)) or api.airfield.reason(price),level
  elseif t.ship and api.shipyard then
    if t.ship.kind~="buoy" and api.shipyard.busy() then return true,nil,"An active vessel protects these harbor facilities." end
    local changed,price=aquatic_remove(n,id,preview)
    return true,changed,changed and ("Dismantle water structure  |  "..dollars(price)) or api.shipyard.reason(price)
  end
end
U.signal_ui=api.road_first and dofile(core.get_modpath("luanttd_core").."/rail_signal_ui.lua")(api,U.status)
function U.signal_arrow(p,id)
  if not U.signal_ui or not api.rail_build or not id then return end
  local V=view(p:get_player_name())
  if V.pick_order or not U.signal_ui.tool(V.tool) then return end
  local q,_,dir=U.signal_ui.preview(p,V.tool,id)
  if q then return dir end
end
U.layer_bulldozer=api.road_first and dofile(core.get_modpath("luanttd_core").."/layer_bulldozer.lua")(api,clear_structure,U.status)
local function clear_error(why)
  return why=="CLEARING_LIMIT_REACHED" and "Clearing limit reached. Let the game advance." or why
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
  if start==id then
    if U.layer_bulldozer and U.layer_bulldozer.open(p,id) then return end
  end
  local q,why=Sim.clear_area(S,n,start,id,diagonal,true)
  if not q then V.status=clear_error(why);return end
  V.status=(q.passed==0 and "Nothing cleared  ·  " or "Bulldozed  ·  ")..clear_ticket(q)
  if #q.dirty>0 then R.update(q.dirty) end
  if q.passed>0 then api.save() end
end
function U.road_gesture(tool)
  return S.corner_grid and (tool=="road" or tool=="oneway_drag" and api.oneway_tools)
end
function U.begin_autoroad(p,id,hit)
  local V=view(p:get_player_name())
  if V.pick_order or not U.road_gesture(V.tool) or not hit then return false end
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
  return Sim.autoroad_selection(V.road_press.id,V.road_press.hit,id,hit)
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
  if not V.road_press or not U.road_gesture(V.tool) then return end
  if not hit then U.cancel_autoroad(p);return end
  local first=V.road_press.id
  local last,axis,start_half,end_half=autoroad_args(V,id,hit)
  V.road_press=nil
  if autoroad_bend(p,V,first,id) then
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
  if S.road_economy and engine.mode=="road" and v.cargo=="passenger" and st.stop_type=="truck" then
    return nil,"Buses need passenger stops, not loading stops."
  end
  if S.road_economy and engine.mode=="road" and Sim.road_freight_cargo(v.engine) and st.stop_type~="truck" then
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
function U.preview(p,id,hit)
  if api.owned_rail_ui and api.owned_rail_ui.active(p) then return api.owned_rail_ui.preview(p,id) end
  local n=p:get_player_name()
  local V=view(n)
  if V.pick_order then
    local target,hint=order_stop_target(n,V,id)
    return {id},not not target,hint
  end
  if V.tool=="teleport_tile" then return {id},true,"Teleport above this tile" end
  if api.road_first and U.road_gesture(V.tool) and hit then
    local press=V.road_press or {id=id,hit=hit}
    if autoroad_bend(p,V,press.id,id) then
      local q,why,path=Sim.autoroad_bend_plan(S,n,press.id,id)
      if not q then return path or {id},false,why end
      return q.path,true,("Road bend  |  %s  ·  %d new tiles  ·  Release to build"):format(dollars(q.cost),#q.changes)
    end
    local last,axis,start_half,end_half=Sim.autoroad_selection(press.id,press.hit,id,hit)
    if V.tool=="oneway_drag" then
      local q,why=api.oneway.quote(S,n,press.id,last,axis,{start_half=start_half,end_half=end_half})
      if not q then return Sim.line(press.id,last),false,one_way_text(why) end
      local ids={}
      for _,edit in ipairs(q.changes) do ids[#ids+1]=edit.tile end
      return ids,q.affordable,("One-way road  |  %s  ·  %d tiles%s"):format(dollars(q.cost),#ids,
        not V.road_press and "  ·  Hold and drag in travel direction" or
        q.stopped_at and "  ·  Stops at an obstruction" or "")
    end
    local q,why=Sim.autoroad_plan(S,n,press.id,last,axis,start_half,end_half)
    local path=Sim.line(press.id,last)
    if not q then return path,false,why end
    local info=q.stopped_at and "  ·  Stops at an obstruction" or
      not V.road_press and "  ·  Drag straight · E for a bend" or "  ·  Hold E for a bend"
    return q.ids,true,("AutoRoad  |  %s  ·  %d tiles%s"):format(dollars(q.cost),#q.ids,info)
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
    local q,why=api.bridge_picker.quote(bridge,n,V.anchor,id)
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
  if U.signal_ui and api.rail_build and U.signal_ui.tool(V.tool) then
    local q,hint=U.signal_ui.preview(p,V.tool,id)
    return {id},q~=nil,hint
  end
  if rail_tool_labels[V.tool] and api.rail_build then
    local plan,msg,anchor=quote_rail(n,V,id)
    if not plan then return {id},not not anchor,msg end
    local title=rail_tool_labels[V.tool]
    if plan.kind=="depot" then title=title.."  ·  Door faces "..tram_dir[V.rail_dir or 2]
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
      return V.tool=="airfield_build" and footprint and footprint(id) or {id},false,why
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
    local plan,reason=api.shipyard.network.quote(S,n,ship,id,V.ship_axis or 0)
    if not plan then return {id},false,api.shipyard.reason(reason) end
    local label=ship=="dock" and "Dock" or ("Ship depot  ·  "..(plan.axis==0 and "East–West" or "North–South"))
    return plan.tiles,true,label.."  |  "..dollars(plan.cost)
  end
  if V.tool=="tram_order" and api.tram then
    local valid,hint=tram_order_target(n,V,id)
    return {id},not not valid,hint
  end
  local tram,tram_ids,direction,face=tram_request(V,id)
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
    (api.rail_oil_tools and oil_stage_tools[tool]) or (api.rail_goods_tools and goods_stage_tools[tool]) or airfield_tools[tool] or ship_mode[tool] or buoy_tools[tool] or tram_mode[tool] or
    tool=="teleport_tile" or tool=="tram_order" or tool=="airfield_order" or tool=="ship_order" or tool=="ship_coal_order" or tool=="truck_stop_tool" or tool=="rail_crossing_tool" or tool=="oneway_drag" or
    landscape_tools[tool] or bridge_tool(tool) or tool:match("^structure_"))
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
    oil_stage_tools[V.tool] or goods_stage_tools[V.tool] or landscape_tools[V.tool] or (V.tool=="airfield_order" and airfield_order) or (V.tool=="ship_order" and ship_order) or
    (buoy_tools[V.tool] and {name=buoy_tools[V.tool]}) or
    (V.tool=="ship_coal_order" and ship_coal_order) or
    (V.tool=="rail_crossing_tool" and crossing_tool) or (V.tool=="oneway_drag" and one_way_tool) or
    (rail_tool_labels[V.tool] and {name=rail_tool_labels[V.tool]}) or
    (waypoint_tools[V.tool] and {name=waypoint_tools[V.tool]}) or
    (V.tool=="truck_stop_tool" and {name="Freight loading stop"}) or
    (V.tool=="teleport_tile" and {name="Teleport to tile"}) or
    (bridge_tool(V.tool) and {name=bridge_label(bridge_tool(V.tool))}) or Sim.tools.inspect
  local target="Aim at the ground"
  if tile then
    local a=S.tiles[tile];local x,z=Sim.xy(tile)
    local st,build=S.stations[a.station],Sim.tools[a.build]
    local mark=a.stock_industry
    local registry=mark and (mark.chain=="farm" and S.stock_farm_industries or
      mark.chain=="timber" and S.stock_timber_industries or
      mark.chain=="oil" and S.stock_oil_industries or S.stock_coal_industries)
    local facility=registry and registry[mark.id]
    local site=S.sites[facility and facility.site or a.site]
    local landmark=a.stock_landmark and (a.stock_landmark.kind=="lighthouse" and "Lighthouse" or "Radio transmitter")
    local channel=a.ship and a.ship.kind=="lock" and "Ship lock" or
      a.water_class=="river" and "River" or nil
    target=("%d,%d  %s"):format(x,z,st and U.stop_label(st) or site and site.name or landmark or
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
function U.build_world(p,id)
  local n=p:get_player_name();local V=view(n)
  V.chosen=id
  if V.pick_order then U.choose_order_stop(p,id);return end
  if V.tool=="inspect" then U.inspect(p,id);return end
  if V.tool=="clear" and U.layer_bulldozer and U.layer_bulldozer.open(p,id) then return end
  local bridge=bridge_tool(V.tool)
  if bridge then
    if not V.anchor then V.anchor=id;V.status="First bridgehead selected. Click the opposite end.";return end
    V.status="Choose a bridge type."
    local ok,why=api.bridge_picker.open(p,bridge,V.anchor,id,function(built,note)
      if note then V.status=note
      elseif built then V.status="Bridge built." end
    end)
    if ok then V.anchor=nil else V.status=why or "No bridge can join these heads." end
    return
  end
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
  if U.signal_ui and api.rail_build and U.signal_ui.tool(V.tool) then U.signal_ui.open(p,id,V.tool);return end
  if V.tool=="rail_signal_remove" and U.layer_bulldozer then
    if not U.layer_bulldozer.open(p,id) then V.status="Aim at a signal to review removal." end
    return
  end
  if rail_tool_labels[V.tool] and api.rail_build then
    local plan,note,anchor=quote_rail(n,V,id)
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
      local plan,reason=api.shipyard.network.build(S,n,ship,id,V.ship_axis or 0)
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
  local tram,tiles,direction=tram_request(V,id)
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
function U.context(p,tile)
  local n=p:get_player_name();local V=view(n)
  if V.pick_order then U.finish_order_pick(p);return end
  V.context_tile=tile
  if api.road_first then
    local t=tile and S.tiles[tile]
    if t and t.build=="road_depot" then U.service(p,"depot",tile)
    elseif t and t.station and S.stations[t.station] and S.stations[t.station].stop_type=="truck" then
      U.service(p,"stop",t.station)
    elseif not asset_details(p,tile) then U.service(p,"context",tile) end
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
function U.service(p,kind,id)
  local n=p:get_player_name();local V=view(n)
  local tall=kind=="vehicle"
  local b={tall and "formspec_version[7]size[9.4,7.08]bgcolor[#152334;false]" or
      "formspec_version[7]size[9.4,6.6]bgcolor[#152334;false]",
    "style_type[button;bgimg=bl_button.png;bgimg_middle=6;border=false;textcolor=#E5ECEA]",
    "style_type[label;textcolor=#E5ECEA]"}
  local function label(x,y,t)
    b[#b+1]=("label[%g,%g;%s]"):format(x,y,esc(t))
  end
  local function button(x,y,w,k,t)
    b[#b+1]=("button[%g,%g;%g,.56;%s;%s]"):format(x,y,w,k,esc(t))
  end
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
    label(.4,2.62,"Back returns to the previous hotbar.")
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
    if goods then label(.4,2.28,number(ind.wood_received or 0).." tons of wood received in total.") end
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
    end
    local paid=Sim.rail_paid_status and Sim.rail_paid_status(S)
    local waiting=paid and paid.waiting and paid.waiting[id]
    if waiting and not platform.coal_role and not platform.oil_role and not platform.goods_role then
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
      local frame=lock and lock.presentation
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
    label(.4,.45,("Country airfield #%d  ·  %s"):format(id,field.owner))
    label(.4,1.20,math.floor(field.flags/256)%2==1 and "Runway reserved." or "Runway clear.")
    local flights=api.airfield.at(id)
    local unit=api.airfield.owned(id)
    local flight=flights[1]
    if #flights>=2 then
      for i,f in ipairs(flights) do
        local stats=Sim.air_paid_status(S,f.paid_clock)
        local row=1.82+(i-1)*1.09
        label(.4,row,("#%d  %s  ·  %s"):format(f.paid_clock,api.airfield.engine_name(f),f.phase))
        if stats then label(.4,row+.5,("%s/%s aboard   ·   %s in fares   ·   %s running"):format(
          stats.onboard,stats.capacity,dollars(stats.fare),dollars(stats.running_expense or 0))) end
      end
      local e=Sim.air_paid_status(S,flight.paid_clock)
      if e and e.waiting[id] then label(.4,4.10,number(e.waiting[id].waiting or 0).." passengers waiting between both flights") end
    elseif flight and (not unit or unit.status=="dispatched") then
      label(.4,1.78,("%s %s  ·  %d terminal stops"):format(api.airfield.engine_name(flight),flight.phase,flight.arrivals))
      local paid=Sim.air_paid_status and Sim.air_paid_status(S,flight.paid_clock)
      local stop=paid and paid.waiting[id]
      if stop then
        label(.4,2.35,number(stop.waiting or 0).." passengers waiting")
        label(.4,2.90,stop.accepts and "Accepts passengers." or "Not enough nearby houses to accept passengers.")
        label(.4,3.49,("%d/%d aboard  ·  %s in fares"):format(paid.onboard,paid.capacity,dollars(paid.fare)))
        if paid.paused then label(.4,4.04,"Paid air service paused or aircraft model missing.")
        elseif paid.running_expense then label(.4,4.04,dollars(paid.running_expense).." in running costs") end
      end
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
              ("Buy %s  /  %d seats  /  %s"):format(e.name,quote.passengers,dollars(quote.price)))
            shown=shown+1
          end
        end
        if shown==0 then label(.4,1.78,"No aircraft available for this hangar.") end
        label(.4,3.82,S.air_fleet_preview and "Two Sampsons can share. Other aircraft fly solo."
          or "One aircraft per preview. Passenger service only.")
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
          {"foster_bus","depot_buy_foster","Foster"}}) do
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
    local freight=Sim.road_coal_active and Sim.road_coal_active(S)
    local y=2.72
    if api.farm_tools and t.owner==n then
      button(.4,y,2.70,"depot_buy_grain","Grain truck / "..dollars(Sim.vehicles.grain_truck.cost))
      button(3.30,y,2.70,"depot_buy_livestock","Livestock van / "..dollars(Sim.vehicles.livestock_van.cost))
      button(6.20,y,2.70,"depot_buy_goods","Goods truck / "..dollars(Sim.vehicles.goods_truck.cost))
      y=y+.62
    end
    if api.oil_tools and t.owner==n then
      button(.4,y,4.10,"depot_buy_oil","Oil tanker / "..dollars(Sim.vehicles.oil_tanker.cost))
      button(4.75,y,4.10,"depot_buy_goods","Goods truck / "..dollars(Sim.vehicles.goods_truck.cost))
      y=y+.62
    end
    if api.timber_tools and t.owner==n then
      button(.4,y,4.10,"depot_buy_wood","Buy wood truck / "..dollars(Sim.vehicles.wood_truck.cost))
      button(4.75,y,4.10,"depot_buy_goods","Buy goods truck / "..dollars(Sim.vehicles.goods_truck.cost))
      y=y+.62
    end
    if t.owner==n and S.road_mail then
      button(.4,y,freight and 4.10 or 8.45,"depot_buy_mail",freight and "Buy post van / 22 bags" or "Buy Harbor Post Van   /   22 mail bags")
    end
    if freight and t.owner==n then
      local truck=Sim.vehicles.coal_tipper
      button(S.road_mail and 4.75 or .4,y,S.road_mail and 4.10 or 8.45,"depot_buy_coal",
        S.road_mail and ("Buy coal tipper / "..dollars(truck.cost)) or ("Buy "..truck.name.."  /  "..truck.capacity.." tons  /  "..dollars(truck.cost)))
    end
    if S.road_mail or freight then y=y+.62 end
    if t.owner==n and Sim.vehicle_available(S,"craighead_goods_truck") then
      local truck=Sim.vehicle_offer(S,"craighead_goods_truck")
      button(.4,y,8.45,"depot_buy_craighead",("Buy Craighead Goods Truck  /  %d crates  /  %s"):format(
        truck.capacity,dollars(truck.cost)))
      y=y+.62
    end
    local parked={}
    for _,i in ipairs(sorted(S.fleet)) do
      local v=S.fleet[i]
      if v.depot==id then parked[#parked+1]=i end
    end
    for j=1,math.min(math.floor((4.45-y)/.57)+1,#parked) do
      local i=parked[j]
      button(.4,y+.08+(j-1)*.57,8.45,"vehicle_"..i,S.fleet[i].name.."   /   "..S.fleet[i].status)
    end
  elseif kind=="stop" then
    local st=S.stations[id]
    if not st then return end
    label(.4,.45,st.name)
    local waiting=0
    if api.oil_tools and st.stop_type=="truck" then
      for i,cargo in ipairs({"oil","goods"}) do
        local count,r=Sim.oil_stop_status(S,st,cargo)
        local role=r and r.accepts and "accepts" or r and #r.sources>0 and "collects" or "no nearby supplier or receiver"
        local unit=cargo=="oil" and " thousand L" or " crates"
        label(.4,.80+i*.55,("%s: %s%s waiting  ·  %s"):format(Sim.cargo[cargo].name,number(count or 0),unit,role))
      end
    elseif api.farm_tools and st.stop_type=="truck" then
      for i,cargo in ipairs({"grain","livestock","goods"}) do
        local count,report=Sim.farm_stop_status(S,st,cargo)
        local role=report and report.accepts and "accepts" or report and #report.sources>0 and "collects" or "no supplier or receiver"
        label(.4,.74+i*.57,("%s: %s waiting  •  %s"):format(Sim.cargo[cargo].name,number(count or 0),role))
      end
      local coal,accepts=Sim.coal_stop_status(S,st)
      if coal then label(.4,2.98,("Coal: %s t waiting  •  %s"):format(number(coal),accepts and "accepts" or "does not accept")) end
    elseif api.timber_tools and st.stop_type=="truck" then
      local wood,wa=Sim.timber_stop_status(S,st,"wood")
      local goods,ga=Sim.timber_stop_status(S,st,"goods")
      label(.4,1.22,number(wood or 0).." t wood  •  "..number(goods or 0).." goods crates waiting")
      label(.4,2.20,wa and wa.accepts and "Accepts wood at the sawmill." or "No wood receiver in this catchment.")
      label(.4,2.70,ga and ga.accepts and "Accepts goods for town businesses." or "Too few businesses to accept goods here.")
      local coal,accepts=Sim.coal_stop_status(S,st)
      if coal then label(.4,3.20,("Coal: %s t waiting  •  %s"):format(number(coal),accepts and "accepts" or "does not accept")) end
    elseif api.freight_tools and st.stop_type=="truck" and st.coal_art and Sim.coal_stop_status then
      local coal,accepted,rating=Sim.coal_stop_status(S,st)
      label(.4,1.22,number(coal or 0).." tons of coal waiting")
      label(.4,2.20,accepted and "Accepts coal." or "Coal supply requires an active mine in catchment.")
      if rating then label(.4,2.68,("Coal rating: %d%%"):format(math.floor(rating*100/255+.5))) end
    elseif S.road_mail and st.stop_type=="truck" then
      local mail,accepted,rating,known=Sim.mail_stop_status(S,st)
      label(.4,1.22,number(mail).." mail bags waiting")
      label(.4,2.20,accepted and "Accepts mail." or "Not enough nearby buildings to accept mail.")
      if known then label(.4,2.68,("Mail rating: %d%%"):format(math.floor(rating*100/255+.5))) end
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
    if acceptance then
      label(.4,1.7,(town and "Near "..town.name.."  ·  " or "")..
        (acceptance>=8 and "Accepts passengers" or "No passenger acceptance"))
    elseif town then
      label(.4,1.7,"Serves: "..town.name)
    end
    local bay=Sim.road_bay_status and Sim.road_bay_status(S,st.tile)
    if bay then
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
  label(.4,tall and 5.49 or 5.02,V.service_note or "")
  button(.4,tall and 6.10 or 5.61,8.6,"service_back","Back to world")
  core.show_formspec(n,"luanttd_core:service",table.concat(b))
end
function U.service_fields(p,f)
  local n=p:get_player_name();local V=view(n)
  local kind,id=V.service_kind,V.service_id
  if f.quit or f.service_back then core.close_formspec(n,"luanttd_core:service");return true end
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
    if f.depot_buy or f.depot_buy_leopard or f.depot_buy_foster or f.depot_buy_mail or f.depot_buy_coal or
        f.depot_buy_wood or f.depot_buy_goods or f.depot_buy_grain or f.depot_buy_livestock or f.depot_buy_oil or f.depot_buy_craighead then
      local model=f.depot_buy_craighead and "craighead_goods_truck" or f.depot_buy_oil and "oil_tanker" or f.depot_buy_grain and "grain_truck" or f.depot_buy_livestock and "livestock_van" or
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
