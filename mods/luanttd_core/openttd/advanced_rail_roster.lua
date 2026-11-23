-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 table/engines.h MT/MW and RVI rows, Temperate.
-- Detached facts for monorail and maglev. There are no catalogue offers
-- until the host supplies the correct rolling stock and guideway assets.
local A={}
local motors={
  [54]={"'X2001'",2,25,52,304,9000,95,230,0,28490},
  [55]={"'Millennium Z1'",2,26,60,336,10000,85,240,25,31047,true},
  [84]={"Lev1 'Leviathan'",3,28,70,400,10000,105,250,0,36525},
  [85]={"Lev2 'Cyclops'",3,29,74,448,12000,120,253,0,39447},
  [86]={"Lev3 'Pegasus'",3,30,82,480,15000,130,254,0,42004},
  [87]={"Lev4 'Chimaera'",3,31,95,640,20000,150,255,0,42735,true},
}
local trailers={
  {"Passenger Carriage","passenger",60,247,25,45,47,15},
  {"Mail Van","mail",62,228,21,35,37,15},
  {"Coal Truck","coal",61,176,18,35,37,3},
  {"Oil Tanker","oil",63,200,24,35,37,7},
  {"Livestock Van","livestock",64,192,20,30,32,3},
  {"Goods Van","goods",65,190,21,30,32,7},
  {"Grain Hopper","grain",66,182,19,35,37,7},
  {"Wood Truck","wood",67,181,16,35,37,7},
  {"Iron Ore Hopper","iron_ore",68,179,19,35,37,1},
  {"Steel Truck","steel",69,196,18,25,27,1},
  {"Armoured Van","valuables",70,255,30,25,27,7},
}
function A.entry(id)
  if type(id)~="number" or id%1~=0 then return end
  local row=motors[id]
  if row then
    local name,gauge,image,buy,max,power,tare,operating,per_head,intro,twin=unpack(row)
    return {stock_id=id,name=name,kind="engine",railtype=gauge,image_index=image,cost_factor=buy,
      speed=max,power=power,tare=tare,running_factor=operating,running_class="run_electric",
      capacity=per_head,cargo=per_head>0 and "passenger" or nil,
      climates=7,base_intro=intro,decay_speed=20,vehicle_life=20,model_life=50,multiheaded=twin or nil}
  end
  local gauge=id>=57 and id<=67 and 2 or id>=89 and id<=99 and 3
  if not gauge then return end
  row=trailers[id-(gauge==2 and 56 or 88)]
  local name,cargo,image,buy,tare,mono,mag,climates=unpack(row)
  return {stock_id=id,name=name,kind="wagon",railtype=gauge,image_index=image,cost_factor=buy,
    speed=0,power=0,tare=tare,running_factor=0,capacity=gauge==2 and mono or mag,cargo=cargo,
    climates=climates,base_intro=1827,decay_speed=20,vehicle_life=20,source_model_life=50}
end
function A.catalog()
  local out={}
  for id=54,99 do
    local row=A.entry(id)
    if row then out[#out+1]=row end
  end
  return out
end
return A
