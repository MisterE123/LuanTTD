-- Shared read-only depot vehicle and service guide. Capacity and top speed
-- are optional values from the actual mounted roster, not invented stats.
local H={}
local cargo_names={passenger="Passengers",mail="Mail",coal="Coal",grain="Grain",livestock="Livestock",
  wood="Wood",oil="Oil",steel="Steel",goods="Goods",iron_ore="Iron Ore",ore="Iron Ore",
  valuables="Valuables",food="Food",water="Water",fruit="Fruit",rubber="Rubber",copper_ore="Copper Ore"}
local ends={coal={"a Coal Mine","a Power Station"},grain={"a Farm","a Factory"},livestock={"a Farm","a Factory"},
  wood={"a Forest","a Sawmill"},oil={"Oil Wells","an Oil Refinery"},
  steel={"a Steel Mill","a Factory"},iron_ore={"an Iron Ore Mine","a Steel Mill"},
  copper_ore={"a Copper Ore Mine","a Factory"},valuables={"a Bank","another Bank"},
  food={"a Food Processing Plant","an accepting town"},water={"a Water Supply","a Water Tower"},
  fruit={"a Fruit Plantation","a Food Processing Plant"},rubber={"a Rubber Plantation","a Factory"}}
ends.ore=ends.iron_ore
local roles={road="Road freight truck",rail="Freight train",ship="Cargo ship",air="Aircraft"}
local capacity_units={passenger="seats",mail="mail bags",coal="t of coal",grain="t of grain",livestock="animals",
  wood="t of wood",oil="kL of oil",steel="t of steel",goods="crates",valuables="bags",iron_ore="t of ore",ore="t of ore"}
local rail_wagons={[27]="passenger",[28]="mail",[29]="coal",[30]="oil",[31]="livestock",[32]="goods",
  [33]="grain",[34]="wood",[35]="iron_ore",[36]="steel",[37]="valuables",[38]="food",
  [40]="copper_ore",[41]="water",[42]="fruit",[43]="rubber"}
function H.rail_cargo(id) return rail_wagons[id] end

local function service(m,c,part,refit,needs_refit)
  if m=="tram" then return "Streetcar test", "Connect the tram depot by tram track to two through tram platforms. This test car does not carry passengers." end
  if m=="rail" and part=="engine" then
    return "Locomotive", "Couple it to a passenger coach or freight wagon. Use that wagon's guide to choose stations, then connect the depot and platforms by compatible track."
  end
  if m=="rail" and part=="dmu" then
    return "Passenger train", "Connect the depot and two passenger rail platforms near towns with continuous track, then add both stops to the orders."
  end
  local prefix=m=="rail" and part=="wagon" and "Couple to a locomotive. " or ""
  if not c or c=="passenger" then
    if m=="road" then return "Passenger bus", "Connect two passenger bus stops near town homes by road. Connect the depot to that road, then give the bus both stops as orders."
    elseif m=="rail" then return part=="wagon" and "Passenger coach" or "Passenger train",
      prefix.."Connect the depot and two passenger rail platforms near towns by track, then add both stops to the orders."
    elseif m=="ship" then return "Passenger ferry", "Build passenger docks near homes in two towns. Connect both docks and the ship depot by navigable water, then order the ferry to both docks."
    elseif m=="air" then return "Passenger aircraft", "Connect two airports near town homes. Use airports with a compatible runway, and order the plane from this hangar to the other airport." end
  end
  if m=="air" and c=="mixed" then
    return "Passenger and Mail aircraft","Order two airports near homes with compatible runways. The cabin and Mail hold earn their own fares. Full load any requires a full passenger cabin."
  end
  if m=="rail" and c=="mixed" then
    return "Coach and Mail train","Use two ordinary town rail stations. Each physical wagon serves its own cargo. Full load any waits for all wagons of one cargo kind; full load all needs every wagon."
  end
  if m=="rail" and c=="mail" then
    return "Rail Mail",prefix.."Order two different town rail platforms. Mail uses the houses in each platform's real catchment. No dedicated freight stage is needed."
  end
  if m=="road" and c=="mail" then
    return "Mail van", "Place truck stops in two towns that produce and accept mail. Connect them and the depot by road, then order the van to both stops."
  end
  local name=cargo_names[c] or (c and c:gsub("_"," ")) or "Cargo"
  local label=(part=="wagon" and "Freight wagon" or roles[m] or "Vehicle").." / "..name
  if m=="ship" and (refit or needs_refit) then
    return "Cargo ship / Coal refit",(refit and "" or "Refit the ship to Coal in the depot first. ")..
      "Connect a dock near a Coal Mine to a dock near a Power Station by navigable water."
  end
  local a,b
  if c=="goods" then
    if m=="rail" then a,b="a Sawmill","a town that accepts Goods"
    else a,b="a Factory, Sawmill or Oil Refinery","a town that accepts Goods" end
  elseif ends[c] then a,b=ends[c][1],ends[c][2]
  elseif c=="mail" then a,b="a town producing mail","a town accepting mail"
  else a,b="a "..name.." producer","an industry or town that accepts "..name end
  if m=="road" then
    return label,"Use a truck stop near "..a.." for loading and another near "..b.." for unloading. Connect both and the depot by road."
  elseif m=="rail" then
    return label,prefix.."Designate a freight platform near "..a.." for loading and another near "..b.." for unloading. Connect them by track."
  elseif m=="ship" then
    return label,"Place a dock near "..a.." and another near "..b..". Connect them and the depot by navigable water."
  elseif m=="air" then
    return label,"Use airports with compatible runways and catchments that produce and accept "..name.."."
  end
  return label,"Connect a "..name.." source and an accepting destination."
end

function H.describe(m,c,model,stats,part,refit,needs_refit)
  stats=stats or {}
  local title,connections=service(m,c,part,refit,needs_refit)
  local info={}
  local capacity=tonumber(stats.capacity)
  if capacity and capacity>0 then
    info[#info+1]=("%g %s"):format(capacity,stats.capacity_unit or capacity_units[c or "passenger"] or "cargo units")
  end
  if stats.mail_capacity and stats.mail_capacity>0 then info[#info+1]=("%d Mail bags"):format(stats.mail_capacity) end
  local speed=tonumber(stats.speed)
  if speed and speed>0 then info[#info+1]=("%g km/h"):format(speed) end
  if part=="dmu" then info[#info+1]="self-powered; no separate engine needed"
  elseif part=="engine" then info[#info+1]="powers the train"
  elseif part=="wagon" then info[#info+1]="unpowered wagon"
  elseif refit then info[#info+1]="changes the existing ship's cargo" end
  if stats.runway then info[#info+1]=stats.runway end
  return {model=(model or title)..(#info>0 and ("  ·  "..table.concat(info,"  ·  ")) or ""),
    service=title,connections=connections}
end

-- Count glyphs, not UTF-8 bytes, and allow for the common wide Latin
-- characters. Native clipping is still the last guarantee at the scroll
-- rectangle; the chosen card and hover show the unabridged information.
local glyphs="[%z\1-\127\194-\244][\128-\191]*"
local function width(c)
  if #c>1 then return c=="·" and .55 or 1.35 end
  return c:match("[ilI%.,:! |]") and .57 or c:match("[mwMW@]") and 1.38 or 1
end
function H.fit(value,limit)
  local out,n={},0
  for c in tostring(value or ""):gmatch(glyphs) do
    local w=width(c)
    if n+w>limit then
      while #out>0 and n+1.4>limit do n=n-width(table.remove(out)) end
      return table.concat(out):gsub("%s+$","").."…"
    end
    out[#out+1]=c;n=n+w
  end
  return table.concat(out)
end
local function wrap(s,limit)
  local lines={}
  for paragraph in (s.."\n"):gmatch("(.-)\n") do
    local row,w={},0
    for word in paragraph:gmatch("%S+") do
      local length=0
      for c in word:gmatch(glyphs) do length=length+width(c) end
      if #row>0 and w+1+length>limit then
        lines[#lines+1]=table.concat(row);row={};w=0
      end
      if w>0 then row[#row+1]=" ";w=w+1 end
      for c in word:gmatch(glyphs) do
        local cw=width(c)
        if w+cw>limit then lines[#lines+1]=table.concat(row);row={};w=0 end
        row[#row+1]=c;w=w+cw
      end
    end
    lines[#lines+1]=table.concat(row)
  end
  return table.concat(lines,"\n")
end
function H.tooltip(esc,key,h)
  return "tooltip["..key..";"..esc(wrap(h.model.."\n"..h.service.."\n"..h.connections,38))..";#18374B;#F4FAFF]"
end
function H.card(b,esc,x,y,w,h,help)
  b[#b+1]=("box[%g,%g;%g,%g;#0F1C28]"):format(x,y,w,h)
  local text=help and (help.model.."\n"..help.service..": "..help.connections) or
    "Tap or click a vehicle to see what it carries and which stops to connect."
  b[#b+1]=("textarea[%g,%g;%g,%g;;;%s]"):format(x+.16,y+.11,w-.32,h-.19,
    esc(wrap(text,math.floor((w-.55)*6.4))))
end
local row_step=.69
function H.scroll_to(index)
  return math.floor(math.max(0,(index or 1)-2)*row_step*10+.5)
end
function H.scroll_fields(core,fields,key,offset)
  local value=core.explode_scrollbar_event and fields[key] and core.explode_scrollbar_event(fields[key])
  return value and (value.type=="CHG" or value.type=="VAL") and value.value or offset
end
function H.selected(fields,prefix,count)
  -- Validate the clicked row against the list shown in this instance.
  for key in pairs(fields) do
    if key:sub(1,#prefix)==prefix then
      local i=tonumber(key:sub(#prefix+1))
      if i and i%1==0 and i>=1 and i<=count then return i end
    end
  end
end
function H.rows(b,esc,o)
  local thumb=.31
  local name=o.prefix.."scroll"
  local height=o.h or 3.35
  local max=math.max(0,math.ceil((#o.items*row_step+.02-height)*10))
  local x,w=.07,o.w-thumb-.16
  local value=math.max(0,math.min(max,o.scroll or 0))
  b[#b+1]=("box[%g,%g;%g,%g;#102237]"):format(o.x,o.y,o.w,height)
  b[#b+1]=("scroll_container[%g,%g;%g,%g;%s;vertical;0.1]"):format(o.x,o.y,o.w-thumb,height,name)
  local limit=math.floor((w-.25)*5.7)
  for i,row in ipairs(o.items) do
    local key=o.prefix.."row"..i
    local main,sub=o.label(row)
    local y=(i-1)*row_step+.03
    local text=H.fit(main,limit)
    if sub and sub~="" then text=text.."\n"..H.fit(sub,limit) end
    if i==o.selected then
      b[#b+1]="style["..key..";bgcolor=#366884;textcolor=#FFFFFF]"
    end
    b[#b+1]=("button[%g,%g;%g,.62;%s;%s]"):format(x,y,w,key,esc(text))
    b[#b+1]=H.tooltip(esc,key,o.help(row))
  end
  b[#b+1]="scroll_container_end[]"
  b[#b+1]=("scrollbaroptions[min=0;max=%d;smallstep=7;largestep=%d;thumbsize=%d;arrows=hide]"):
    format(max,math.floor(height*7),math.floor(height*10))
  b[#b+1]=("scrollbar[%g,%g;%g,%g;vertical;%s;%d]"):format(o.x+o.w-thumb,o.y,thumb,height,name,value)
  b[#b+1]="scrollbaroptions[]"
end

return H
