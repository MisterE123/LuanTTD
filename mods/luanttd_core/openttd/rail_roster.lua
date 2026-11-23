-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright the OpenTTD contributors; no warranty.
-- OpenTTD 14.1 stock ordinary rail slice: table/engines.h,
-- table/pricebase.h, table/cargo_const.h, engine.cpp, train_cmd.cpp,
-- train.h, ground_vehicle.cpp, economy.cpp and company_cmd.cpp.
-- Quotes and cached stats only. No fleet mutation, calendar invention,
-- autoreplace, packet ownership or company ledger side effects.
local R={VEHICLE_LENGTH=8,TILE_SIZE=16,DAY_TICKS=74,DAYS_IN_YEAR=365,CARGO_AGE_TICKS=185,
  GRADUAL_WAIT=40,RETRY_WAIT=20,DEFAULT_MAX_TRAIN_TILES=7}
local floor,min,max=math.floor,math.min,math.max
local order={0,1,8,9,10,11,13,14,15,22,27,28,29,30,32}
local rows={
  [0]={name="Kirby Paul Tank",kind="engine",visual="steam",image_index=2,engine_class="steam",
    cost_factor=7,speed=64,power=300,tare=47,running_factor=50,running_class="run_steam",
    capacity=0,climates=1,base_intro=1827,decay_speed=20,vehicle_life=15,model_life=30},
  [1]={name="MJS 250",kind="engine",visual="diesel",image_index=19,engine_class="diesel",
    cost_factor=8,speed=80,power=600,tare=65,running_factor=65,running_class="run_diesel",
    capacity=0,climates=6,base_intro=12784,decay_speed=20,vehicle_life=22,model_life=30},
  [8]={name="Chaney 'Jubilee'",kind="engine",visual="jubilee",image_index=0,engine_class="steam",
    cost_factor=13,speed=112,power=1000,tare=131,running_factor=120,running_class="run_steam",
    capacity=0,climates=1,base_intro=5114,decay_speed=20,vehicle_life=21,model_life=30},
  [9]={name="Ginzu 'A4'",kind="engine",visual="a4",image_index=1,engine_class="steam",
    cost_factor=19,speed=128,power=1200,tare=162,running_factor=140,running_class="run_steam",
    capacity=0,climates=1,base_intro=5479,decay_speed=20,vehicle_life=20,model_life=30},
  [10]={name="SH '8P'",kind="engine",visual="sh_8p",image_index=0,engine_class="steam",
    cost_factor=22,speed=144,power=1600,tare=170,running_factor=130,running_class="run_steam",
    capacity=0,climates=1,base_intro=12419,decay_speed=20,vehicle_life=23,model_life=25},
  [11]={name="Manley-Morel DMU",kind="engine",visual="manley_morel",image_index=8,engine_class="diesel",
    multiheaded=true,multiple_unit=true,cost_factor=11,speed=112,power=600,tare=32,
    running_factor=85,running_class="run_diesel",capacity=38,cargo="passenger",
    climates=1,base_intro=13149,decay_speed=20,vehicle_life=12,model_life=30,purchase_enabled=false},
  -- OpenTTD 16.0-RC1 table/engines.h: MT and RVI rows #13 and #14.
  [13]={name="SH/Hendry '25'",kind="engine",visual="hendry_25",image_index=4,engine_class="diesel",
    cost_factor=15,speed=128,power=1250,tare=72,running_factor=95,running_class="run_diesel",
    capacity=0,climates=1,base_intro=14976,decay_speed=20,vehicle_life=18,model_life=28},
  [14]={name="UU '37'",kind="engine",visual="uu_37",image_index=5,engine_class="diesel",
    cost_factor=17,speed=144,power=1750,tare=101,running_factor=120,running_class="run_diesel",
    capacity=0,climates=1,base_intro=14245,decay_speed=20,vehicle_life=20,model_life=30},
  [15]={name="Floss '47'",kind="engine",visual="floss47",image_index=4,engine_class="diesel",
    cost_factor=18,speed=160,power=2580,tare=112,running_factor=140,running_class="run_diesel",
    capacity=0,climates=1,base_intro=15341,decay_speed=20,vehicle_life=22,model_life=33},
  [22]={name="SH '125'",kind="engine",visual="sh_125",image_index=6,engine_class="diesel",
    multiheaded=true,cost_factor=20,speed=200,power=4500,tare=70,running_factor=190,
    running_class="run_diesel",capacity=4,cargo="mail",climates=1,base_intro=20820,
    decay_speed=20,vehicle_life=20,model_life=25,purchase_enabled=false},
  [23]={name="SH '30'",kind="engine",visual="sh_30",image_index=20,engine_class="electric",railtype=1,
    cost_factor=26,speed=160,power=3600,tare=84,running_factor=180,running_class="run_electric",
    capacity=0,climates=1,base_intro=16437,decay_speed=20,vehicle_life=23,model_life=30,purchase_enabled=false},
  [24]={name="SH '40'",kind="engine",visual="sh_40",image_index=20,engine_class="electric",railtype=1,
    cost_factor=30,speed=176,power=5000,tare=82,running_factor=205,running_class="run_electric",
    capacity=0,climates=1,base_intro=19359,decay_speed=20,vehicle_life=23,model_life=80,purchase_enabled=false},
  [27]={name="Passenger Carriage",kind="wagon",visual="passenger_wagon",image_index=33,engine_class="steam",
    cost_factor=247,speed=0,power=0,tare=25,running_factor=0,
    capacity=40,cargo="passenger",climates=15,base_intro=1827,decay_speed=20,vehicle_life=20,model_life=255},
  [28]={name="Mail Van",kind="wagon",visual="mail_van",image_index=35,engine_class="steam",
    cost_factor=228,speed=0,power=0,tare=21,running_factor=0,capacity=30,cargo="mail",
    climates=15,base_intro=1827,decay_speed=20,vehicle_life=20,model_life=255,source_model_life=50,
    purchase_enabled=false},
  [29]={name="Coal Truck",kind="wagon",visual="coal_wagon",image_index=34,engine_class="steam",
    cost_factor=176,speed=0,power=0,tare=18,running_factor=0,
    capacity=30,cargo="coal",climates=3,base_intro=1827,decay_speed=20,vehicle_life=20,model_life=255},
  [30]={name="Oil Tanker",kind="wagon",visual="oil_wagon",image_index=36,engine_class="steam",
    cost_factor=200,speed=0,power=0,tare=24,running_factor=0,
    capacity=30,cargo="oil",cargo_id=3,liters_per_unit=1000,
    climates=7,base_intro=1827,decay_speed=20,vehicle_life=20,model_life=255,purchase_enabled=false},
  [32]={name="Goods Van",kind="wagon",visual="goods_van",image_index=38,engine_class="steam",
    cost_factor=190,speed=0,power=0,tare=21,running_factor=0,
    capacity=25,cargo="goods",cargo_id=5,
    climates=7,base_intro=1827,decay_speed=20,vehicle_life=20,model_life=255,purchase_enabled=false},
}
for id,row in pairs(rows) do
  row.stock_id=id;row.railtype=row.railtype or 0;row.shorten_factor=0
  row.length=R.VEHICLE_LENGTH;row.load_amount=5;row.tractive_effort=76;row.air_drag=0
  row.cargo_age_ticks=R.CARGO_AGE_TICKS
end
local cargo={
  passenger={weight=1,freight=false},mail={weight=4,freight=false},
  coal={weight=16,freight=true},
  oil={weight=16,freight=true},
  goods={weight=8,freight=true},
}
local base_prices={build_engine=400000,build_wagon=2000,run_steam=5600,run_diesel=5200,run_electric=4800}
local factors={[0]=6,8,9}
local climates={temperate=0,arctic=1,tropic=2,toyland=3}
local function uint(num,limit) return type(num)=="number" and num%1==0 and num>=0 and num<=limit end
local function copy(t)
  local a={}
  for k,v in pairs(t) do a[k]=v end
  return a
end
local function get(part)
  if type(part)=="table" then return rows[part.stock_id],part.cargo_count or 0 end
  return rows[part],0
end

function R.entry(id) return rows[id] and copy(rows[id]) end
function R.catalog(electric)
  local out={}
  for i,id in ipairs(order) do out[i]=copy(rows[id]) end
  if electric==true then table.insert(out,8,copy(rows[23]));table.insert(out,9,copy(rows[24])) end
  return out
end
function R.dual_head(id) return not not (rows[id] and rows[id].multiheaded) end
function R.electric_engine(id)
  local row=rows[id]
  return not not (row and row.kind=="engine" and row.railtype==1)
end
function R.base_prices() return copy(base_prices) end

-- Price bases on medium/no inflation default. Caller may supply the
-- game's already recomputed _price subset instead of a configuration.
function R.prices(opts)
  opts=opts or {}
  local cfg,run=opts.construction_difficulty or 1,opts.running_difficulty or 1
  local cf,rf=factors[cfg],factors[run]
  local inflation=opts.inflation or 65536
  if not cf or not rf or not uint(inflation,2^32-1) then return nil,"INVALID_PRICE_SETTINGS" end
  local result={}
  for key,base in pairs(base_prices) do
    local factor=key:sub(1,4)=="run_" and rf or cf
    local value=opts.prices and opts.prices[key]
    if value~=nil and not uint(value,2^53-1) then return nil,"INVALID_PRICE_SETTINGS" end
    local scaled=base*factor
    local shifted=scaled*floor(inflation/2^19)+floor(scaled*(inflation%2^19)/2^19)
    result[key]=value or max(1,shifted)
  end
  return result
end
local function purchase(r,prices)
  return floor(prices[r.kind=="wagon" and "build_wagon" or "build_engine"]*r.cost_factor/256)
end
function R.purchase_price(id,opts)
  local row=rows[id]
  if not row then return nil,"UNKNOWN_RAIL_VEHICLE" end
  local prices,why=R.prices(opts)
  if not prices then return nil,why end
  return purchase(row,prices)
end

local function calc_offset(length,next_length)
  return floor(length/2)+floor((next_length+1)/2)
end
function R.next_offset(length,next_length) return calc_offset(length,next_length or -1) end

-- OpenTTD AddRearEngineToMultiheadedTrain/NormaliseDualHeads: the two
-- actual bodies are one purchased design. Keep the rear as the last
-- part before the next independent engine, behind any intervening wagons.
-- Never interpret two logical #11 selections as the two halves of one.
function R.physical_parts(parts)
  if type(parts)~="table" or #parts==0 then return nil,"EMPTY_CONSIST" end
  local explicit=false
  for _,p in ipairs(parts) do
    if type(p)=="table" and (p.role~=nil or p.mate~=nil) then explicit=true;break end
  end
  local out,pending={},nil
  local function close()
    if not pending then return end
    local i=#out+1
    out[i]=pending.tail
    out[pending.front].mate=i
    out[i].mate=pending.front
    pending=nil
  end
  for i,p in ipairs(parts) do
    local row,count=get(p)
    if not row then return nil,"UNKNOWN_RAIL_VEHICLE",i end
    local part=type(p)=="table" and copy(p) or {stock_id=p,cargo_count=count}
    if explicit then
      if row.multiheaded then
        if part.rear_cargo_count~=nil or not uint(part.mate or -1,#parts) then
          return nil,"INVALID_DUAL_HEAD_LINK",i
        end
        if part.role=="front" then
          if pending or part.mate<=i then return nil,"INVALID_DUAL_HEAD_LINK",i end
          pending={front=i,tail=part.mate,id=part.stock_id}
        elseif part.role=="rear" then
          local next_row=get(parts[i+1])
          if not pending or pending.front~=part.mate or pending.tail~=i or pending.id~=part.stock_id or
              next_row and next_row.kind~="engine" then return nil,"INVALID_DUAL_HEAD_LINK",i end
          pending=nil
        else return nil,"INVALID_DUAL_HEAD_LINK",i end
      elseif part.role~=nil or part.mate~=nil or part.rear_cargo_count~=nil or pending and row.kind=="engine" then
        return nil,"INVALID_DUAL_HEAD_LINK",i
      end
      out[i]=part
    else
      if row.kind=="engine" then close() end
      if row.multiheaded then
        local rear={stock_id=part.stock_id,cargo=part.cargo,cargo_count=part.rear_cargo_count or 0,role="rear"}
        part.role,part.rear_cargo_count="front",nil
        pending={front=#out+1,tail=rear}
      elseif part.rear_cargo_count~=nil then return nil,"INVALID_DUAL_HEAD_LINK",i end
      out[#out+1]=part
    end
  end
  if explicit then
    if pending then return nil,"INVALID_DUAL_HEAD_LINK",pending.front end
  else close() end
  return out
end

function R.display(id)
  local row=rows[id]
  if not row then return end
  local mult=row.multiheaded and 2 or 1
  return {weight=row.tare*mult,capacity=row.capacity*mult,power=row.power,
    tractive_effort=floor(row.tare*mult*row.tractive_effort*9800/256),vehicles=mult}
end
local function count_valid(row,count)
  return row and uint(count,row.capacity)
end
local function cargo_weight(row,count,freight)
  local spec=cargo[row.cargo]
  if not spec then return 0 end
  return floor(count*(spec.freight and freight or 1)*spec.weight/16)
end
local function rail_limit(track_limits,limit)
  for _,cap in ipairs(track_limits or {}) do if cap>0 then limit=min(limit,cap) end end
  return limit
end

-- Accept logical stock IDs, or the explicit physical predecessor order with
-- reciprocal role/mate fields returned by physical_parts. ConsistChanged
-- rounds cargo weight per body, including both actual powered DMU halves.
function R.stats(parts,opts)
  opts=opts or {}
  local physical,reason,invalid=R.physical_parts(parts)
  if not physical then return nil,reason,invalid end
  local prices,why=R.prices(opts)
  if not prices then return nil,why end
  local freight,steepness=opts.freight_trains or 1,opts.slope_steepness or 3
  if not uint(freight,255) or freight==0 or not uint(steepness,10) then return nil,"INVALID_RAIL_SETTINGS" end
  local out={
    parts={},lengths={},offsets={},coupling={},cargo_capacity={},cargo_count={},cargo_load_per_pulse={},
    length=0,total_length=0,weight=0,tare=0,max_weight=0,power=0,compatible={},
    freight_trains=freight,
    display_max_speed=65535,running_year_fp=0,price=0,tractive_effort=0,
  }
  local engines=0
  for i,p in ipairs(physical) do
    local row,count=get(p)
    if not count_valid(row,count) then return nil,"INVALID_CARGO_COUNT",i end
    if type(p)=="table" and p.cargo and p.cargo~=row.cargo then return nil,"UNSUPPORTED_REFIT",i end
    local item=copy(row)
    item.cargo_count=count
    item.cargo_weight=cargo_weight(row,count,freight)
    item.weight=row.tare+item.cargo_weight
    item.max_weight=row.tare+cargo_weight(row,row.capacity,freight)
    item.slope_resistance=item.weight*steepness*100
    local original=purchase(row,prices)
    item.price,item.purchase_charge=original,original
    item.powered=row.kind=="engine"
    if row.multiheaded then
      item.role,item.mate=p.role,p.mate
      if item.role=="rear" then
        item.kind,item.image_index,item.purchase_charge="rear_engine",row.image_index+1,0
      end
      -- Constructor shares value by an integer shift. Charge the untouched
      -- buy price once, even when the two stored resale values round down.
      item.price=floor(original/2)
      item.power=floor(row.power/2)
      item.running_factor=floor(row.running_factor/2)
    end
    item.running_year_fp=row.running_class and prices[row.running_class]*item.running_factor or 0
    if item.kind=="engine" then engines=engines+1 end
    if item.powered then
      out.tractive_effort=out.tractive_effort+item.weight*row.tractive_effort
      -- 14.1 ConsistChanged accumulates the physical powered parts'
      -- railtypes. An ordinary unpowered wagon cannot give an electric
      -- locomotive permission to route on an unpowered tile.
      out.compatible[1]=true
      if row.railtype==0 then out.compatible[0]=true end
    end
    if i==1 then out.offsets[i]=0
    else
      local distance=calc_offset(out.lengths[i-1],row.length)
      out.coupling[i-1]=distance
      out.offsets[i]=out.offsets[i-1]+distance
    end
    local k=row.cargo
    if k then
      out.cargo_capacity[k]=(out.cargo_capacity[k] or 0)+row.capacity
      out.cargo_count[k]=(out.cargo_count[k] or 0)+count
      out.cargo_load_per_pulse[k]=(out.cargo_load_per_pulse[k] or 0)+row.load_amount
    end
    out.parts[i]=item;out.lengths[i]=row.length
    out.total_length=out.total_length+row.length
    out.weight=out.weight+item.weight;out.tare=out.tare+row.tare
    out.max_weight=out.max_weight+item.max_weight;out.power=out.power+item.power
    out.price=out.price+item.purchase_charge;out.running_year_fp=out.running_year_fp+item.running_year_fp
    if row.speed~=0 and (item.powered or opts.wagon_speed_limits~=false) then
      out.display_max_speed=min(out.display_max_speed,row.speed)
    end
  end
  out.coupling[#physical]=R.next_offset(out.lengths[#physical])
  out.length=out.total_length
  out.front_length=out.lengths[1]
  out.tail_length=out.lengths[#physical]
  out.front_overhang=floor((out.front_length+1)/2)
  out.rear_overhang=floor(out.tail_length/2)
  out.max_track_speed=rail_limit(opts.track_limits,out.display_max_speed)
  out.running_year=floor(out.running_year_fp/256)
  -- GroundVehicle::PowerChanged does its ground-acceleration
  -- multiplication in uint32_t before dividing the 8-bit coefficient.
  out.tractive_effort=floor((out.tractive_effort*9800)%2^32/256)
  out.axle_resistance=out.weight*10
  out.acceleration=max(1,min(255,4*floor(out.power/max(1,out.weight))))
  local drag=out.display_max_speed<=10 and 192 or max(1,floor(2048/out.display_max_speed))
  out.air_drag=drag+floor(3*drag*#physical/20)
  out.engine_count=engines
  out.can_run=out.parts[1].kind=="engine" and engines>0
  local limit=opts.max_train_tiles or R.DEFAULT_MAX_TRAIN_TILES
  if not uint(limit,64) or limit==0 then return nil,"INVALID_RAIL_SETTINGS" end
  out.too_long=out.total_length>limit*R.TILE_SIZE
  return out
end

-- Base intro and startup randomization (seed supplied by the real stock
-- world generator); this is NOT the company's ongoing ENGINE_AVAILABLE
-- or preview/retirement state. Expose both independently.
local function year_start(year)
  if year==0 then return 0 end
  return 365*year+floor((year-1)/4)-floor((year-1)/100)+floor((year-1)/400)+1
end
local function xor12(a,b,c)
  local out,p=0,1
  for _=1,12 do
    if (a+b+c)%2==1 then out=out+p end
    a,b,c=floor(a/2),floor(b/2),floor(c/2)
    p=p*2
  end
  return out
end
function R.introduction(id,starting_year,generation_seed,startup_random)
  local row=rows[id]
  if not row or not uint(starting_year,5000000) or not uint(generation_seed,2^32-1) or
      not uint(startup_random,2^32-1) then return nil,"INVALID_INTRO_PARAMETERS" end
  local base=year_start(1920)+row.base_intro
  if base<=year_start(starting_year+2) then return base end
  -- VehicleType::VEH_TRAIN and vanilla GRFID are zero. The low nine
  -- output bits of rotr(seed,3)-1 depend only on the low 12 seed bits.
  local delta=(floor(xor12(generation_seed,startup_random,base)/8)-1)%512
  return base+delta
end
function R.vehicle_life_days(id,extension_years)
  local row=rows[id]
  if not row or not uint(extension_years or 0,255) then return end
  return (row.vehicle_life+(extension_years or 0))*366
end

function R.climate_ok(id,climate)
  local row=rows[id]
  local c=type(climate)=="number" and climate or climates[climate or "temperate"]
  return not not (row and uint(c,3) and floor(row.climates/2^c)%2==1)
end

-- The host's dedicated freight service handles a single powered locomotive
-- and one wagon. Passenger DMUs add a second powered body and require a
-- different freight layout; leave them to passenger operations.
function R.freight_engine(id)
  local row=rows[id]
  return not not (row and row.kind=="engine" and not row.multiheaded and row.capacity==0)
end
local function supported_single_wagon(id)
  return id==27 or id==29 or id==30 or id==32
end

-- Combined quote for explicit purchases at an owned depot; opts.available
-- supplies the stock company engine-mask result. No silent free-wagon
-- attachment, null-stock retirement guess, or fake climate override.
-- roster_preview=true is explicit cross-climate testing, not stock sale.
function R.quote(depot,owner,parts,opts)
  opts=opts or {}
  if not depot or depot.kind~="depot" or depot.owner~=owner or owner==nil then return nil,"INVALID_OWNED_DEPOT" end
  local stats,why,i=R.stats(parts,opts)
  if not stats then return nil,why,i end
  for index,row in ipairs(stats.parts) do
    -- This stock row can be inspected/priced without licensing a live
    -- purchase until its actual freight orders and asset are mounted.
    if row.purchase_enabled==false and
        not (row.stock_id==30 and opts.mount_oil_wagon==true and
            (opts.separate_depot_purchase and #parts==1 or #parts==2 and R.freight_engine(stats.parts[1].stock_id))) and
        not (row.stock_id==32 and opts.mount_goods_wagon==true and
            (opts.separate_depot_purchase and #parts==1 or #parts==2 and R.freight_engine(stats.parts[1].stock_id))) and
        not (R.electric_engine(row.stock_id) and opts.mounted_electric and opts.mounted_electric[row.stock_id]==true and
            index==1 and (opts.separate_depot_purchase and #parts==1 or
              #parts==2 and supported_single_wagon(stats.parts[2].stock_id))) and
        not (row.stock_id==22 and opts.mount_sh_125==true and stats.parts[1].stock_id==22 and
            (#parts==1 and #stats.parts==2 or #parts==2 and #stats.parts==3 and stats.parts[2].stock_id==27)) and
        not (row.stock_id==11 and opts.mount_manley==true and stats.parts[1].stock_id==11 and
            (#parts==1 and #stats.parts==2 or #parts==2 and #stats.parts==3 and stats.parts[2].stock_id==27)) then
      return nil,"RAIL_VEHICLE_NOT_MOUNTED",index
    end
    if not opts.roster_preview then
      if not R.climate_ok(row.stock_id,opts.climate) then return nil,"RAIL_VEHICLE_NOT_AVAILABLE",index end
      if not opts.available then return nil,"ENGINE_AVAILABILITY_REQUIRED",index end
      if not opts.available(row.stock_id,owner) then return nil,"RAIL_VEHICLE_NOT_AVAILABLE",index end
      local allowed=opts.company_railtypes
      if row.railtype==1 and (not allowed or not allowed[1]) then return nil,"RAIL_VEHICLE_NOT_AVAILABLE",index end
      if allowed and not (allowed[0] or allowed[1]) then return nil,"RAIL_VEHICLE_NOT_AVAILABLE",index end
    end
    if depot.railtype~=0 and depot.railtype~=1 then return nil,"INCOMPATIBLE_DEPOT_RAIL",index end
    if row.powered and row.railtype==1 and depot.railtype~=1 then return nil,"INCOMPATIBLE_DEPOT_RAIL",index end
  end
  if stats.too_long then return nil,"TRAIN_TOO_LONG" end
  if stats.engine_count>0 and not stats.can_run then return nil,"LOCOMOTIVE_MUST_LEAD" end
  if (opts.vehicle_slots and #stats.parts>opts.vehicle_slots) or
      (opts.free_locomotive_numbers and not opts.query and stats.engine_count>opts.free_locomotive_numbers) then
    return nil,"TOO_MANY_VEHICLES_IN_GAME"
  end
  if opts.cash~=nil and stats.price>opts.cash then return nil,"NOT_ENOUGH_CASH" end
  return {owner=owner,depot=depot.id,kind="rail_purchase",price=stats.price,
    parts=stats.parts,stats=stats,expense="new_vehicles",preview=not not opts.roster_preview}
end

function R.current_speed_cap(stats,order_limit,visible_bridge_limits)
  local limit=stats.max_track_speed
  for _,speed in ipairs(visible_bridge_limits or {}) do limit=min(limit,speed) end
  return min(limit,order_limit or 65535)
end

function R.load_slice(part,waiting,gradual)
  local row,count=get(part)
  if not count_valid(row,count) or not uint(waiting,2^32-1) then return nil,"INVALID_CARGO_COUNT" end
  return min(waiting,row.capacity-count,gradual==false and row.capacity or row.load_amount)
end
function R.unload_slice(part,gradual)
  local row,count=get(part)
  if not count_valid(row,count) then return nil,"INVALID_CARGO_COUNT" end
  return gradual==false and count or min(count,row.load_amount)
end
function R.loading_wait(total_length,platform_tiles,loaded,unloaded,opts)
  opts=opts or {}
  local amount=loaded+unloaded
  local ticks=amount==0 and R.RETRY_WAIT or opts.gradual_loading==false and amount or R.GRADUAL_WAIT
  local overhang=total_length-platform_tiles*R.TILE_SIZE
  if opts.platform_penalty~=false and overhang>0 then
    ticks=ticks*2
    ticks=ticks+floor(overhang*ticks/8)
  end
  return max(1,ticks)
end

-- Train::Tick is once per stock tick, before its two movement passes.
-- A not-manually-stopped train at red, loading or in a depot still runs.
function R.running_tick(counter,stopped,speed)
  return counter+((not stopped or speed>0) and 1 or 0)
end
function R.day_running_charge(running_year_fp,running_ticks)
  return floor(running_year_fp*running_ticks/(R.DAYS_IN_YEAR*R.DAY_TICKS))
end
function R.debit_fraction(company_fraction,cost_fp)
  local leftover=(company_fraction-cost_fp%256)%256
  return floor(cost_fp/256)+(leftover>company_fraction and 1 or 0),leftover
end
return R
