-- Bayline's simulation does not depend on Luanti. The game adapter owns UI and storage.
local M = {}
local module_src=debug and debug.getinfo(1,"S").source
local module_root=module_src and module_src:match("^@(.*/)sim%.lua$") or
  (core and core.get_modpath and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
local TramIndex=dofile(module_root.."tram_fleet_index.lua")
local CompanyQuarter=dofile(module_root.."openttd/company_quarters_rc1.lua")
M.stock_joined_station=dofile(module_root.."stock_joined_station.lua")
local HQStats=dofile(module_root.."company_hq_stats.lua")(M)
M.each_tram,M.tram_frame,M.tram_serial=TramIndex.each,TramIndex.frame,TramIndex.serial

M.W,M.H = 48,36
M.modes = {"rail","road","water","air"}
M.dir = {{0,-1},{1,0},{0,1},{-1,0}}
local town_growth_mount=setmetatable({},{__mode="k"})
local foster_art_mount=setmetatable({},{__mode="k"})
local road_faults_mount=setmetatable({},{__mode="k"})
local news_mount,road_flood_news=setmetatable({},{__mode="k"}),setmetatable({},{__mode="k"})
function M.mount_news(s,arrival,road_flood) news_mount[s],road_flood_news[s]=arrival,road_flood end
M.month_days = 30
M.cargo = {
  mail={name="Mail",rate=11}, passenger={name="Passengers",rate=9},
  coal={name="Coal",rate=8}, grain={name="Grain",rate=8},
  steel={name="Steel",rate=13}, goods={name="Goods",rate=15},wood={name="Wood",rate=9},
}
M.cargo.livestock={name="Livestock",rate=10}
M.cargo.iron_ore={name="Iron Ore",rate=0}
M.cargo.valuables={name="Valuables",rate=0}
M.cargo.oil={name="Oil",rate=0} -- Actual stock pressure uses a dedicated loader.
M.cargo_order={"passenger","mail","coal","grain","steel","goods","wood","livestock","oil","iron_ore","valuables"}
M.vehicles = {
  steam={name="4-4-0 Atlantic",mode="rail",cost=12500,speed=1.45,capacity=72,daily=45,year=1950},
  diesel={name="Bayliner Diesel",mode="rail",cost=20500,speed=2.35,capacity=104,daily=61,year=1958},
  electric={name="Twin Coast Express",mode="rail",cost=36000,speed=3.7,capacity=155,daily=112,year=1970},
  bus={name="Town Flyer Bus",mode="road",cost=3500,speed=1.6,capacity=30,daily=15,year=1950},
  truck={name="Mack Freight Truck",mode="road",cost=4600,speed=1.3,capacity=35,daily=17,year=1950},
  coach={name="Intercity Coach",mode="road",cost=8000,speed=2.7,capacity=50,daily=25,year=1956},
  leopard_bus={name="Coastal Leopard",mode="road",cost=5400,speed=2.5,capacity=35,daily=21,year=1964},
  foster_bus={name="Foster Bus",mode="road",cost=8203,speed=224,capacity=37,year=1986,development=true},
  mail_van={name="Harbor Post Van",mode="road",cost=4200,speed=1.3,capacity=22,daily=15,year=1935,development=true},
  coal_tipper={name="Kestrel Coal Tipper",mode="road",cost=5906,speed=96,capacity=20,daily=2,year=1935,
    development=true,stock_engine_id=123,display_speed=48,load_amount=5,cargo_age_ticks=185,
    weight_quarters=38,power_tens_hp=12,buy_factor=108,running_factor=90,
    tractive_effort=76,air_drag=0,life_years=15,intro_days_after_1920=5479},
  goods_truck={name="Balogh Goods Truck",mode="road",cost=5851,speed=96,capacity=14,daily=2,year=1950,
    development=true,stock_engine_id=138,display_speed=48,load_amount=5,cargo_age_ticks=185,
    weight_quarters=38,power_tens_hp=12,buy_factor=107,running_factor=90,intro_days_after_1920=5479},
  wood_truck={name="Witcombe Wood Truck",mode="road",cost=6453,speed=96,capacity=20,daily=2,year=1950,
    development=true,stock_engine_id=144,display_speed=48,load_amount=5,cargo_age_ticks=185,
    weight_quarters=38,power_tens_hp=12,buy_factor=118,running_factor=90,intro_days_after_1920=5479},
  grain_truck={name="Hereford Grain Truck",mode="road",cost=6234,speed=96,capacity=20,year=1935,
    development=true,stock_engine_id=141,display_speed=48,load_amount=5,cargo_age_ticks=185,
    weight_quarters=38,power_tens_hp=12,buy_factor=114,running_factor=90,intro_days_after_1920=5479},
  livestock_van={name="Talbott Livestock Van",mode="road",cost=5742,speed=96,capacity=14,year=1935,
    development=true,stock_engine_id=135,display_speed=48,load_amount=5,cargo_age_ticks=185,
    weight_quarters=38,power_tens_hp=12,buy_factor=105,running_factor=90,intro_days_after_1920=5479},
  oil_tanker={name="Witcombe Oil Tanker",mode="road",cost=6015,speed=96,capacity=21,year=1935,
    development=true,stock_engine_id=132,display_speed=48,load_amount=5,cargo_age_ticks=185,
    weight_quarters=38,power_tens_hp=12,buy_factor=110,running_factor=90,intro_days_after_1920=5479},
  ferry={name="Sound Ferry",mode="water",cost=10500,speed=1.2,capacity=95,daily=44,year=1950},
  freighter={name="Coastal Freighter",mode="water",cost=15300,speed=1.05,capacity=155,daily=55,year=1950},
  prop={name="Island Hopper",mode="air",cost=24000,speed=6,capacity=60,daily=110,year=1950},
  jet={name="Bayline Jet",mode="air",cost=49000,speed=9,capacity=120,daily=175,year=1962},
}
M.vehicle_order={"steam","diesel","electric","bus","truck","coach","leopard_bus","foster_bus","coal_tipper","wood_truck","grain_truck","livestock_van","goods_truck","oil_tanker","ferry","freighter","prop","jet"}
M.facilities={
  town={name="Town",produces={passenger=14,mail=6},takes={passenger=true,mail=true,goods=true}},
  mine={name="Coal mine",produces={coal=24},takes={}},
  farm={name="Farm",produces={grain=19},takes={}},
  mill={name="Steel mill",produces={},takes={coal=true},output="steel",ratio=0.6},
  factory={name="Factory",produces={},takes={grain=true,steel=true},output="goods",ratio=0.8},
  stock_coal_mine={name="Coal Mine",produces={},takes={}},
  stock_power_station={name="Coal Power Station",produces={},takes={}},
  stock_forest={name="Forest",produces={},takes={}},
  stock_sawmill={name="Sawmill",produces={},takes={}},
}
M.tools={
  inspect={name="Inspect"}, tram_track={name="Tramway"}, tram_stop={name="Tram platform"},
  tram_depot={name="Tram depot"},tram_bit={name="Tramway half-piece"},
  ship_dock={name="Build dock"},ship_join_dock={name="Join dock or build separately"},ship_depot={name="Ship depot"},ship_aqueduct={name="Aqueduct"},ship_canal={name="Canal"},ship_lock={name="Ship lock"},ship_remove={name="Dismantle facility"}, landscape_raise={name="Raise corner"},
  landscape_lower={name="Lower corner"}, landscape_level={name="Level area"},
  structure_wood={name="Timber bridge"}, structure_concrete={name="Concrete bridge"}, structure_steel={name="Steel girder"}, structure_tunnel={name="Road tunnel"}, stock_rail={name="Trackworks",price=220}, stock_road_bridge={name="Road bridge",price=1200,mode="road"}, stock_road_tunnel={name="Road tunnel",price=450,mode="road"}, rail={name="Track",price=220,mode="rail"}, road={name="Road",price=190,mode="road"},
  rail_bridge={name="Rail bridge",price=620,mode="rail"}, road_bridge={name="Road bridge",price=440,mode="road"},
  rail_tunnel={name="Rail tunnel",price=680,mode="rail"}, road_tunnel={name="Road tunnel",price=510,mode="road"},
  rail_station={name="Rail station",price=1400,mode="rail"}, road_station={name="Road stop",price=550,mode="road"},
  road_bay_pair={name="Two-bay bus terminus",price=550,mode="road"},
  road_depot={name="Road depot",price=950,mode="road"},
  dock={name="Dock",price=1200,mode="water"}, airport={name="Airport",price=7200,mode="air"},
  signal={name="Rail signal",price=90,mode="rail"}, canal={name="Canal",price=500,mode="water"},
  grade={name="Grade hillside",price=350}, clear={name="Bulldoze",price=80},
}
M.tool_order={"inspect","rail","road","rail_bridge","road_bridge","rail_tunnel","road_tunnel","rail_station","road_station","dock","airport","signal","canal","grade","clear","road_depot"}
local station_tools={rail_station=true,road_station=true,dock=true,airport=true}
local linear={rail=true,road=true,rail_bridge=true,road_bridge=true,rail_tunnel=true,road_tunnel=true,canal=true}
M.linear=linear
local function rng(seed)
  local s=seed%2147483647
  if s<1 then s=1 end
  return function(n) s=s*16807%2147483647; return s%n end
end
function M.id(x,z)
  if x<1 or z<1 or x>M.W or z>M.H then return nil end
  return (z-1)*M.W+x
end
function M.xy(id)
  return (id-1)%M.W+1,math.floor((id-1)/M.W)+1
end
function M.distance(a,b)
  local x,z=M.xy(a);local u,v=M.xy(b)
  return math.abs(x-u)+math.abs(z-v)
end
local function adjacent(id, direction)
  local x,z=M.xy(id)
  local d=M.dir[direction]
  return M.id(x+d[1],z+d[2])
end
M.adjacent=adjacent
local function push(s,msg)
  table.insert(s.news,1,msg)
  if #s.news>24 then table.remove(s.news) end
end
function M.date(s,at_day)
  local day=at_day or s.day
  if s.stock_bus_market then return M.engine_calendar.ymd(s.stock_bus_market.epoch+day) end
  local month=math.floor(day/30)
  return 1950+math.floor(month/12),month%12+1,day%30+1
end
function M.new(seed)
  seed=math.floor(tonumber(seed) or 1751)
  local rand=rng(seed)
  local s={version=1, seed=seed, day=0, tiles={}, sites={}, companies={}, stations={}, fleet={}, next_station=1,next_vehicle=1,
    topology=0,subsidies={},news={"1950: A new transportation charter opens on the coast."},speed=1,chair=nil}
  local shift=rand(3)-1
  for z=1,M.H do
    for x=1,M.W do
      local river=24+math.floor(2.8*math.sin(z/7))+shift
      local coastal=z>=32+math.floor(2*math.sin(x/6))
      local water= coastal or math.abs(x-river)<=2
      local height=0
      if not water then
        local hills=math.sin(x/4+0.5)*math.sin(z/5+0.6)+0.41*math.sin(x/3+z/6)
        if (z>=20 or x>=29) and hills>0.62 then height=1 end
        if (z>=20 or x>=29) and hills>0.87 then height=2 end
      end
      local wood=(not water and height==0 and (math.sin(x/2.8+seed%9)*math.cos(z/3.7)>0.43 or x<5)) or nil
      s.tiles[M.id(x,z)]={terrain=water and "water" or height>0 and "hill" or "grass",h=height,variant=rand(4),wood=wood}
    end
  end
  local function site(name,kind,x,z)
    local id=#s.sites+1
    local a=M.id(x,z)
    local info={id=id,name=name,kind=kind,tile=a,stock={},produced={},received={},population=kind=="town" and 270+rand(250) or nil,service=0}
    s.sites[id]=info
    local t=s.tiles[a]; t.terrain="grass";t.h=0;t.site=id
    for dz=-3,3 do for dx=-3,3 do
      local i=M.id(x+dx,z+dz);local q=i and s.tiles[i]
      if q and q.terrain~="water" and math.abs(dx)+math.abs(dz)<=5 then q.terrain="grass";q.h=0;q.wood=nil end
      if kind=="town" and q and q.terrain~="water" and not q.site and math.abs(dx)+math.abs(dz)<=3 and rand(3)==0 then q.house=true end
    end end
    for k,n in pairs(M.facilities[kind].produces) do info.stock[k]=n*3 end
  end
  site("Port Alder","town",9,9)
  site("Mason Quay","town",18,9)
  site("Eastport","town",31,9)
  site("Tern Island","town",37,27)
  site("Copper Ridge","town",12,24)
  site("Old Quarry","mine",6,19)
  site("Alder Steel","mill",17,21)
  site("Meridian Farms","farm",34,16)
  site("Harbor Works","factory",42,10)
  site("Southwick Farms","farm",15,28)
  site("Cedar Coal","mine",42,23)
  site("Tern Steel","mill",32,25)
  -- Reserve the original charter’s proposed demonstration right of way.
  for x=9,18 do s.tiles[M.id(x,12)].house=nil end
  s.subsidies={
    {src=1,dst=2,cargo="passenger",until_day=360},
    {src=6,dst=7,cargo="coal",until_day=540},
    {src=8,dst=9,cargo="grain",until_day=720},
  }
  return s
end
function M.company(s,owner)
  if not s.companies[owner] then
    s.companies[owner]={cash=100000,loan=50000,revenue=0,expense=0,month_rev=0,month_exp=0,history={},units=0,paid_units=0,rating={},tutorial=false}
    if not s.chair then s.chair=owner end
    push(s,owner.." opened a transport company.")
  end
  return s.companies[owner]
end
-- An explicit player admission, not a UI read or a detached test account.
-- Stock company creation precedes that player's first action and consumes
-- the authoritative world RNG exactly once, including after a worker rebind.
function M.open_company(s,owner)
  if s.companies[owner] then return s.companies[owner] end
  if not s.stock_generated_profile then return M.company(s,owner) end
  local existing={}
  for _,c in pairs(s.companies) do
    if c.stock_start then existing[#existing+1]=c.stock_start end
  end
  table.sort(existing,function(a,b) return a.id<b.id end)
  local stock=dofile(module_root.."openttd/company_start_rc1.lua").open(function() return M.stock_random_u32(s) end,existing)
  if not stock then return nil,"Every company slot is occupied." end
  local c=M.company(s,owner)
  c.stock_start=stock
  stock.year=M.date(s)
  -- Base game creation loan at uninflated costs and the stock default
  -- maximum loan. Inflation-aware company joining is a separate gap.
  c.loan,c.cash=100000,100000
  return c
end
M.stock_economy_money=CompanyQuarter.money
M.stock_economy_delivered=CompanyQuarter.delivered
M.stock_vehicle_operating=HQStats.record
local function debit(c,amount,expense)
  c.cash=c.cash-amount;c.expense=c.expense+amount;c.month_exp=c.month_exp+amount
  if expense then CompanyQuarter.money(c,expense,amount) end
end
local function credit(c,amount)
  c.cash=c.cash+amount;c.revenue=c.revenue+amount;c.month_rev=c.month_rev+amount
  -- This callback is used by ordinary transport payments, not borrowing.
  CompanyQuarter.money(c,"road_income",-amount)
end
function M.loan(s,owner,amount)
  local c=M.company(s,owner)
  if amount==10000 and c.loan+amount<=200000 or amount==-10000 and c.cash>=10000 and c.loan>=10000 then
    c.loan=c.loan+amount;c.cash=c.cash+amount
    return true, amount>0 and "Borrowed $10,000." or "Repaid $10,000."
  end
  return false,"Loan limit reached or no money to repay."
end
-- Station ownership and ownership of the underlying street can differ.
local function road_access(t,owner)
  return t and (t.road_town~=nil or t.owner==owner)
end
local function compatible_road_owners(a,b)
  return a.road_town~=nil or b.road_town~=nil or a.owner==b.owner
end
local function mode_on(s,id,mode,owner)
  local t=s.tiles[id]
  if not t or t.stock_void then return false end
  if mode=="water" and (t.terrain=="water" or t.build=="canal") then return not t.coastal_water end
  local b=M.tools[t.build]
  return b and b.mode==mode and (t.owner==owner or t.build=="canal" or (mode=="road" and t.road_town~=nil)) or false
end
M.mode_on=mode_on
local function wet(s,id)
  local t=s.tiles[id]
  return t.terrain=="water" or t.build=="canal"
end
-- The shared-corner branch is opt-in. Version 1 saves without a grid keep
-- the original adjacency-only construction and route behavior.
local terrain_rules, slope_rules, road_rules, landscape_rules, bridge_rules, bridge_underlay, bridge_assets, tunnel_rules, coastal_world, clear_area_rules, long_road_rules
local function load_road_rules()
  if terrain_rules then return end
  local source=debug and debug.getinfo(1,"S").source
  local base=source and source:match("^@(.*/)sim%.lua$")
  base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  terrain_rules=dofile(base.."openttd/terrain.lua")
  slope_rules=dofile(base.."openttd/slope.lua")
  road_rules=dofile(base.."openttd/road_slope.lua")
  road_rules.autoslope=dofile(base.."openttd/road_autoslope.lua")(road_rules,slope_rules,
    dofile(base.."openttd/road_stop_build.lua"))
  long_road_rules=dofile(base.."openttd/road_oneway.lua")(road_rules)
  landscape_rules=dofile(base.."openttd/landscaping.lua")(terrain_rules)
  clear_area_rules=dofile(base.."openttd/clear_area.lua")
  local rail_track=dofile(base.."openttd/rail_track.lua")
  road_rules.union=rail_track.union
  road_rules.rail_autoslope=dofile(base.."openttd/rail_autoslope.lua")(rail_track,slope_rules)
  road_rules.rail_height=dofile(base.."openttd/rail_height.lua")(rail_track,slope_rules)
  road_rules.town_foundation=dofile(base.."openttd/town_foundation.lua")
  road_rules.object_autoslope=dofile(base.."openttd/object_autoslope.lua")
  local rail_water=dofile(base.."openttd/rail_half_water.lua")(rail_track,slope_rules)
  coastal_world=dofile(base.."water_flood_world.lua")(M,terrain_rules,dofile(base.."openttd/water_flood.lua"),
    rail_track,slope_rules,rail_water)
  bridge_rules=dofile(base.."openttd/road_bridge.lua")(slope_rules)
  bridge_underlay=dofile(base.."openttd/bridge_underlay.lua")
  bridge_assets=dofile(base.."bridge_style_assets.lua")
  tunnel_rules=dofile(base.."openttd/road_tunnel.lua")
end
local crossing_bindings=setmetatable({},{__mode="k"})
function M.mount_crossings(s,Runtime,rail,survey_clear)
  crossing_bindings[s]={runtime=Runtime,rail=rail,survey_clear=survey_clear}
end
local crossing_errors={
  FALLBACK_CLEAR="Road and rail must cross at right angles on straight track.",
  PROTECTED_TILE="A station, roadworks, signal or protected structure blocks the crossing.",
  LAND_SLOPED_IN_WRONG_DIRECTION="This slope cannot support a level crossing.",
  VEHICLE_IN_THE_WAY="Wait for the vehicle to clear the crossing.",
  OWNED_BY_ANOTHER="This crossing requires an existing way owned by your company.",
  ROAD_POSE_UNKNOWN="Wait for road traffic position to be confirmed.",
  RESERVATION_UNKNOWN="Wait for the rail reservation to be confirmed.",
  OCCUPANCY_UNKNOWN="Wait for crossing traffic position to be confirmed.",
  ELECTRIC_CROSSING_NOT_MOUNTED="Electrified crossings are not available yet.",
  GUIDEWAY_CROSSING_NOT_MOUNTED="This guideway needs a bridge to cross a road.",
  CROSSING_ON_ONEWAY_ROAD="Remove the one-way restriction before building a crossing.",
  CLEAR_EXCLUSIVE_RAIL_PILOT="Clear the running train pilot before building the crossing.",
  CLEAR_SURVEYED_TRAIN="Clear the surveyed train before building the crossing.",
  NEEDS_STOCK_ROAD_CLOCK="The crossing needs the stock road traffic clock.",
  NOT_ENOUGH_MONEY="Not enough cash.",
}
function M.crossing_construction_error(why)
  return crossing_errors[why] or ("Cannot build level crossing: "..tostring(why))
end
function M.crossing_construction_quote(s,owner,id,request)
  local c=crossing_bindings[s]
  if not c or not s.level_crossing_enabled then return nil,"LEVEL_CROSSING_DISABLED" end
  if c.survey_clear and not c.survey_clear() then return nil,"CLEAR_SURVEYED_TRAIN" end
  return c.runtime.quote(s,owner,id,request,c.rail(s))
end
function M.apply_crossing_construction(s,p)
  local c=assert(crossing_bindings[s])
  return c.runtime.apply(s,p,c.rail(s))
end
function M.refresh_crossing_construction(s)
  local c=crossing_bindings[s]
  if c then c.runtime.refresh(s,c.rail(s)) end
end
function M.crossing_protected(s,id)
  local t=id~=nil and s.tiles[id]
  return t and t.level_crossing~=nil or false
end
local function crossing_road_board(s,b)
  local c=crossing_bindings[s]
  return c and c.runtime.road_board(s,b) or b
end
local function crossing_road_step(s,world,from,to,td,commit)
  if not (M.crossing_protected(s,from) or M.crossing_protected(s,to)) then return commit() end
  local c=crossing_bindings[s]
  if not c then return false end
  return c.runtime.road_step(s,c.rail(s),world,from,to,td,commit)
end
function M.tram_crossing_step(s,from,to,commit)
  if not (M.crossing_protected(s,from[4]) or M.crossing_protected(s,to[4])) then return commit() end
  local c=crossing_bindings[s]
  if not c then return false,"CROSSING_UNOBSERVED" end
  return c.runtime.tram_step(s,c.rail(s),from[4],to[4],to[6],commit)
end
function M.tram_crossing_remove_quote(s,owner,id,bits,piece_price)
  local c=crossing_bindings[s]
  if not c then return nil,"TRAM_FACILITY_PROTECTED" end
  if s.stock_rail_run or c.survey_clear and not c.survey_clear() then return nil,"CLEAR_SURVEYED_TRAIN" end
  return c.runtime.world.surface_remove_quote(s,owner,id,bits,c.runtime.context(s,c.rail(s)),true,piece_price)
end
function M.tram_crossing_remove_apply(s,edit)
  return assert(crossing_bindings[s]).runtime.world.surface_remove_apply(s,edit)
end
function M.crossing_rail_remove_plan(s,owner,id)
  local c=crossing_bindings[s]
  if not c or not s.companies[owner] then return nil,"NO_RAIL_ON_CROSSING" end
  if s.stock_rail_run or c.survey_clear and not c.survey_clear() then return nil,"CLEAR_SURVEYED_TRAIN" end
  return c.runtime.world.rail_remove_quote(s,owner,id,c.runtime.context(s,c.rail(s)))
end
function M.apply_crossing_rail_removal(s,owner,quote)
  local now,why=M.crossing_rail_remove_plan(s,owner,quote.id)
  if not now then return false,why end
  for _,field in ipairs{"rail_axis","roadtype","road_bits","road_owner","tramtype","tram_bits","tram_owner","cost"} do
    if now[field]~=quote[field] then return false,"STALE_QUOTE" end
  end
  local c=crossing_bindings[s]
  c.runtime.world.rail_remove_apply(s,now)
  debit(s.companies[owner],now.cost)
  s.topology=s.topology+1
  M.refresh_crossing_construction(s)
  return true,"Removed the railway. Road and tram layers remain; recovered $70.",{now.id}
end
local oneway_bindings=setmetatable({},{__mode="k"})
local auto_oneway
function M.mount_road_oneway(s,W)
  oneway_bindings[s]=W
end
local function default_oneway()
  -- Persisted traffic rules remain authoritative even with the UI disabled
  -- or after the campaign is deserialized into a fresh Sim instance.
  if not auto_oneway then
    load_road_rules()
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    local Follow=dofile(base.."openttd/yapf_road_follow.lua")
    local OneWay=dofile(base.."openttd/road_oneway.lua")(road_rules,Follow)
    auto_oneway=dofile(base.."road_oneway_world.lua")(M,terrain_rules,Follow,OneWay)
  end
  return auto_oneway
end
local function oneway_world(s)
  return oneway_bindings[s] or s.road_oneway_revision and default_oneway() or nil
end
local function road_traffic_board(s,b)
  b=crossing_road_board(s,b)
  local w=oneway_world(s)
  return w and w.path_board(s,b) or b
end
local function road_sign(t)
  return t and t.build=="road" and (t.road_disallowed or t.disallowed or 0) or 0
end
local function one_way_pose(s,from,to)
  if from and to and from[4]~=to[4] and not (to[12] or to[13] or to[14]) then
    local t=s.tiles[to[4]]
    if t and t.roadworks then return false,"ROADWORKS_IN_PROGRESS",to[4] end
  end
  local w=oneway_world(s)
  if w then
    local ok,why,at=w.guard(s,from,to)
    if not ok then return false,why,at end
    if s.road_oneway_removed and w.removal_blocks(s,to) then return false,"ONEWAY_ROAD_LAYOUT_CHANGED",to[4] end
  end
  return true
end
local function one_way_edit(s,id,removed)
  s.road_oneway_revision=(s.road_oneway_revision or 0)+1
  if removed then
    s.road_oneway_removed=s.road_oneway_removed or {}
    s.road_oneway_removed[id]=true
  elseif s.road_oneway_removed then
    s.road_oneway_removed[id]=nil
  end
end
local road_remove_world,town_road_authority
local road_removal_errors={
  ROAD_STOP_IN_ORDERS="Remove this station from road vehicle orders before removing pavement.",
  NO_ROAD="No road to remove on that line.",
  NO_ROAD_PIECES="No road on the selected side of the tile.",
  WRONG_SLOPE="The remaining road cannot sit on this slope.",
  VEHICLE_IN_THE_WAY="Wait for traffic to clear the road.",
  OWNED_BY="This road belongs to another company.",
  TOWN_REFUSES="The local authority won't allow this road removal.",
  NOT_PLAIN_ROAD="This tool removes pavement; use Bulldoze to review facility or crossing layers.",
  ROAD_WORKS_IN_PROGRESS="Wait until the road works are complete.",
  CLEAR_SURVEYED_TRAIN="Stop the surveyed train before changing the crossing.",
  OCCUPANCY_UNKNOWN="Wait for traffic positions to be confirmed.",
  RESERVATION_UNKNOWN="Wait for the crossing reservation to be confirmed.",
  ROAD_DRAG_TOO_LONG="Drag across fewer than 128 tiles at a time.",
  NOT_ENOUGH_CASH="Not enough cash to remove the first road piece.",
}
function M.road_removal_error(reason)
  return road_removal_errors[reason] or ("Cannot remove this road: "..tostring(reason))
end
local function mount_road_removal()
  if road_remove_world then return road_remove_world end
  load_road_rules()
  if not road_remove_world then
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    default_oneway()
    town_road_authority=dofile(base.."town_road_authority.lua")(M,dofile(base.."openttd/road_town_permission.lua"))
    road_remove_world=dofile(base.."road_remove_world.lua")(M,terrain_rules,{
      town=town_road_authority.quote,
      context=function(state) return auto_oneway.ground_occupancy(state) end,
      occupied=function(_,id,ground) return ground[id]==true end,
      special=function(state,company,id,tile,wanted,ground,journal)
        local part=tile.tram
        if part and part.tram_shelter and part.shared_station==tile.station then
          if tile.owner~=company then return nil,"OWNED_BY" end
          local sid=tile.station
          local st=state.stations[sid]
          if not st or st.road_members then return nil,"NOT_PLAIN_ROAD" end
          if ground[id] then return nil,"VEHICLE_IN_THE_WAY" end
          local half=assert(tile.stop_axis)/5
          if math.floor(wanted/half)%2==0 and math.floor(wanted/(4*half))%2==0 then return nil,"NO_ROAD" end
          -- RC1 RemoveRoad on a two-way-type drive-through: both
          -- pavement bits are cleared; the still-used tram station and
          -- all queues remain. Make road order removal explicit first.
          if M.road_station_in_use(state,sid) then return nil,"ROAD_STOP_IN_ORDERS" end
          return {id=id,cost=80,tool="remove_tram_platform_road",build="land",road_bits=0,joined_tram_station=sid}
        end
        if not tile.level_crossing then return nil,"NOT_PLAIN_ROAD" end
        local c=crossing_bindings[state]
        if not c then return nil,"NOT_PLAIN_ROAD" end
        if state.stock_rail_run or (c.survey_clear and not c.survey_clear()) then return nil,"CLEAR_SURVEYED_TRAIN" end
        local W=c.runtime.world
        local municipal=journal~=nil and tile.road_town~=nil
        local edit,why=W.road_remove_quote(state,company,id,wanted,{vehicles_at=function(i)
          local a=W.dispatch_parts(state,i)
          if ground[i] then a[#a+1]={type="road",tile=i} end
          return a
        end},municipal)
        if not edit then return nil,why end
        if municipal then
          local allowed,reason=town_road_authority.quote(state,company,id,wanted,journal)
          if not allowed then return nil,reason or "TOWN_REFUSES" end
        end
        return edit
      end,
    })
  end
  return road_remove_world
end
function M.road_remove_plan(s,owner,first,last,axis,start_half,end_half)
  if not s.corner_grid then return nil,"PARAMETERS" end
  return mount_road_removal().plan(s,owner,first,last,axis,start_half,end_half)
end
function M.road_remove_surface_plan(s,owner,id)
  if not s.corner_grid then return nil,"PARAMETERS" end
  return mount_road_removal().surface_plan(s,owner,id)
end
function M.apply_road_removal(s,owner,q)
  local c=s.companies[owner]
  local ids,total,limited,crossing_changed={},0,q.unfunded,false
  for _,edit in ipairs(q.changes) do
    if total+edit.cost>c.cash then limited=true;break end
    if edit.tool=="remove_crossing" then
      crossing_bindings[s].runtime.world.road_remove_apply(s,edit)
      crossing_changed=true
    elseif edit.tool=="remove_tram_platform_road" then
      local t=s.tiles[edit.id]
      local part=t.tram
      local st=assert(s.stations[edit.joined_tram_station])
      part.tram_station,part.shared_station,part.tram_shelter=st.id,nil,nil
      t.build,t.owner,t.station,t.stop_axis,t.road_terminal_level,t.road_bits,t.road_stop_type=nil,nil,nil,nil,nil,nil
      t.road_disallowed,t.disallowed=nil,nil
      st.tram_only=true
    else
      road_remove_world.apply_plain(s,edit)
    end
    one_way_edit(s,edit.id,true)
    -- Retain the sentinel when paving new halves. The stock path board
    -- verifies the current tile's geometry before an old cursor enters.
    s.road_oneway_removed[edit.id]=1
    total=total+edit.cost;ids[#ids+1]=edit.id
  end
  if #ids==0 then return false,"Not enough cash to remove the first road piece." end
  town_road_authority.apply(c,q.ratings)
  debit(c,total)
  s.topology=s.topology+1
  if crossing_changed then M.refresh_crossing_construction(s) end
  return true,("Removed road on %d tile%s for $%d.%s"):format(#ids,#ids==1 and "" or "s",total,
    limited and " Stopped when available cash ran out." or ""),ids
end
-- Shared clearance predicate for existing protected rail infrastructure.
-- Other construction adapters use this historical name for immutable
-- native rail layers (including supported same-tile road/rail crossings).
function M.rail_span_protected(s,id)
  local t=s.tiles[id]
  return not not (t and (t.rail_span_id or t.level_crossing or t.rail_waypoint_id) or s.rail_bridge_above and s.rail_bridge_above[id]
    or s.rail_tunnel_below and s.rail_tunnel_below[id])
end
local coastal_occupied=setmetatable({},{__mode="k"})
local stock_rail_ground,stock_tree_lifecycle,stock_tree_plant,stock_land_rules,machinery_world
function M.mount_coastal_flood(s,occupied)
  assert(s.corner_grid and s.road_economy and s.road_stock_house_supply,
    "Stock coastal flooding requires shared corners and the source landscape clock.")
  assert(occupied==nil or type(occupied)=="function")
  coastal_occupied[s]=occupied
  s.stock_coastal_flood=true
end
local function coastal_active(s)
  return s.stock_coastal_flood and s.corner_grid and s.road_economy and s.road_stock_house_supply
end
local live_sea=setmetatable({},{__mode="k"})
function M.mount_live_sea_cache(s)
  if s.stock_generated_profile and coastal_active(s) then
    live_sea[s]=dofile(module_root.."stock_open_sea_cache.lua")(M,s)
  end
end
-- The exact dirty IDs of a municipal commit cannot make distant
-- non-flooding sea recheck. Full unknown edits still use clear().
function M.invalidate_live_sea_near(s,id)
  local sea=live_sea[s]
  if sea then sea.invalidate(id) end
end
function M.clear_live_sea_cache(s)
  local sea=live_sea[s]
  if sea then sea.reset();sea.resume_day=s.day+2 end
end
M.plain_tide_observers=setmetatable({},{__mode="k"})
function M.mount_plain_tide_observer(s,observe) M.plain_tide_observers[s]=observe end
M.checkpoint_surface_observers=setmetatable({},{__mode="k"})
function M.mount_checkpoint_surface_observer(s,observer)
  M.checkpoint_surface_observers[s]=observer
end
local function coastal_visit(s)
  local observer=M.checkpoint_surface_observers[s]
  if not coastal_active(s) then return end
  load_road_rules()
  if not stock_rail_ground then
    local track=dofile(module_root.."openttd/rail_track.lua")
    local rules=dofile(module_root.."openttd/rail_ground_temperate.lua")(track)
    stock_rail_ground=dofile(module_root.."rail_ground_world.lua")(M,rules)
  end
  if s.stock_generated_profile and not stock_tree_lifecycle then
    local gen=dofile(module_root.."openttd/tree_worldgen.lua")
    local rules=dofile(module_root.."openttd/tree_lifecycle_temperate.lua")(gen)
    stock_tree_lifecycle=dofile(module_root.."tree_lifecycle_world.lua")(M,terrain_rules,rules)
  end
  local board=coastal_world.board(s)
  if M.road_stock_service_active(s) then
    board.road_stop_flood,board.clear_road_stop=M.coastal_road_stop_runtime(s)
    board.tram_stop_flood,board.clear_tram_stop,board.shared_tram_busy=M.coastal_tram_stop_runtime(s)
  end
  board.flood_vehicles=function(id,tick,other,water_z) return M.coastal_rail_flood(s,id,tick,other,water_z) end
  board.bridge_ends=function(id) return M.coastal_rail_bridge(s,id) end
  board.clear_bridge=function(id) return M.coastal_clear_rail_bridge(s,id) end
  board.clear_signals=function(id,removed,apply) return M.coastal_clear_rail_signal(s,id,removed,apply) end
  board.clear_platform=function(id,apply) return M.coastal_clear_rail_platform(s,id,apply) end
  local trees=s.stock_generated_profile and stock_tree_lifecycle
  local random=trees and function() return M.stock_random_u32(s) end
  local plain_tide=M.plain_tide_observers[s]
  local function water(x,z,tick)
    local previous=s.topology
    local changed,plain,first=coastal_world.visit(s,x+1,z+1,board,tick)
    if observer and changed>0 then observer(M.id(x+1,z+1)) end
    if plain then
      M.preserve_road_junctions_after_tide(s,previous)
      if plain_tide then plain_tide(s,previous,first) end
    end
    return changed
  end
  local sea=live_sea[s]
  if sea and sea.resume_day and s.day<sea.resume_day then sea=nil end
  local visit_tree=trees and function(x,z,tick) return trees.visit(s,x,z,tick,random,observer) end
  local new_tree=trees and function(tick) return trees.global_tick(s,tick,random,observer) end
  return function(x,z,tick)
    local u,v=x+1,z+1
    local id=M.id(u,v)
    local tile=id and s.tiles[id]
    if not tile then return end
    local was_wet=tile.rail_ground==13
    if was_wet or tile.terrain=="water" then
      if sea then sea.visit(water,x,z,tick,id,tile) else water(x,z,tick) end
      tile=s.tiles[id]
    end
    -- RC1 dispatches these tile loops by the surface record. A water
    -- visit can change it (e.g. dry up shores or flood a rail half).
    if not was_wet and tile.rail_tracks then stock_rail_ground.visit(s,u,v) end
    if visit_tree and tick and (tile.wood or tile.stock_clear_density) then visit_tree(u,v,tick) end
  end,new_tree,water,visit_tree
end
local function machine_rules()
  if not machinery_world then
    machinery_world=dofile(module_root.."industry_machinery_world.lua")(M,
      dofile(module_root.."openttd/industry_machinery_rc1.lua"),
      dofile(module_root.."oil_animation_registry.lua"),
      dofile(module_root.."openttd/world_animation_rc1.lua"),
      dofile(module_root.."openttd/industry_chimney_effect.lua"))
  end
  return machinery_world
end
function M.industry_machinery(s,pregame) return machine_rules().bind(s,pregame) end
function M.visible_machinery(s,x,z,w,h) return machine_rules().visible(s,x,z,w,h) end
function M.prepare_initial_landscape(s,growth,Farm,progress)
  assert(coastal_active(s) and s.passenger_house_clock and s.stock_town_growth)
  local _,_,water,trees=coastal_visit(s)
  local initial=dofile(module_root.."initial_landscape_world.lua")(M,
    dofile(module_root.."openttd/town_passengers.lua"),dofile(module_root.."openttd/town_lift.lua"))
  return initial.settle(s,growth,Farm,assert(water),assert(trees),
    function() return M.stock_random_u32(s) end,progress,M.industry_machinery(s,true))
end
local function coastal_tile_occupied(s,id)
  local extra=coastal_occupied[s]
  if extra and extra(id) then return true end
  local function vessel(run)
    if not run then return false end
    local v=run.vehicle
    if not v then return true end -- unknown reservation, don't invalidate it
    if v.tile==id then return true end
    -- The host validates its already-issued directed trace on a topology
    -- change. Preserve this suffix, not every unrelated sea/river tile.
    for i=math.max(1,(v.path_index or 2)-1),#(v.path or {}) do
      if v.path[i].tile==id then return true end
    end
    return false
  end
  if vessel(s.ship_pilot) or vessel(s.stock_coal_ship_run) or vessel(s.stock_oil_ship_route) then return true end
  for _,v in pairs(s.fleet) do
    local e=M.vehicles[v.engine]
    if e and e.mode=="water" and M.position(s,v)==id then return true end
  end
  return false
end
function M.coastal_in_use(s,id) return coastal_tile_occupied(s,id) end
local water_clear_errors={
  OUTSIDE_MAP="Outside the playable map.",
  TOO_CLOSE_TO_EDGE_OF_MAP="Too close to the map edge.",
  OWNED_BY_ANOTHER="Another company owns that tile.",
  CAN_T_BUILD_ON_WATER="Can't build on water.",
  VEHICLE_IN_THE_WAY="A vessel is in the way or has reserved this stretch.",
  PROTECTED_TILE="A protected structure occupies this tile.",
}
local function quote_water_clear(s,owner,id)
  load_road_rules()
  return coastal_world.clear_quote(s,owner,id,function(at) return coastal_tile_occupied(s,at) end)
end
function M.clear_water(s,owner,id,quote_only)
  local t=s.tiles[id]
  if not s.corner_grid or not t then return nil,"OUTSIDE_MAP" end
  local price,why=quote_water_clear(s,owner,id)
  if not price then return nil,why end
  local account=s.companies[owner]
  if (account and account.cash or 100000)<price then return nil,"NOT_ENOUGH_MONEY" end
  if not quote_only then
    local c=M.company(s,owner)
    coastal_world.clear_apply(s,id,c)
    s.topology=s.topology+1
    debit(c,price)
  end
  return {id},price
end
local function stock_plant_rules()
  if not stock_tree_plant then
    load_road_rules()
    stock_tree_plant=dofile(module_root.."openttd/tree_plant_temperate.lua")(
      dofile(module_root.."openttd/tree_worldgen.lua"),landscape_rules)
  end
  return stock_tree_plant
end
function M.plant_tree(s,owner,first,last,diagonal,species,execute)
  local company=s.companies[owner]
  if not (s.stock_generated_profile and s.corner_grid and company) then return nil,"TREE_PLANT_UNAVAILABLE" end
  local rules=stock_plant_rules()
  local clear_limit=clear_area_rules.replenish(company.clear_limit,0)
  local grid=s.corner_grid
  local function tile(x,z)
    local id=M.id(x,z)
    local t=id and s.tiles[id]
    if not t or t.stock_void then return end
    if type(t.wood)=="table" then return {id=id,class=4,count=t.wood.count} end
    if t.wood or t.rail_tracks or t.rail_span_id or t.house or t.site or t.stock_industry or t.stock_landmark
        or t.station or t.ship or t.tram or t.airfield or t.owner or t.build or (t.road_bits or 0)~=0 then return end
    local bridge=s.bridge_above and s.bridge_above[id] or s.rail_bridge_above and s.rail_bridge_above[id]
        or s.aqueduct_above and s.aqueduct_above[id]
    if t.terrain=="water" then
      return {id=id,class=6,coast=t.coastal_water,rocky=t.stock_water_rocks,bridge_above=bridge,
        slope=terrain_rules.tile(grid,x,z)}
    end
    local field=s.stock_farm_fields and s.stock_farm_fields[id]
    return {id=id,class=0,ground=field and 3 or t.stock_clear_ground or 0,
      density=t.stock_clear_density or 3,bridge_above=bridge}
  end
  local opts={species=species,quota=company.stock_tree_plant_limit,tile=tile,cash=company.cash}
  function opts.clear(t)
    if clear_limit<rules.unit then return nil,"CLEARING_LIMIT_REACHED" end
    local price,why
    if t.class==6 then price,why=quote_water_clear(s,owner,t.id)
    else price=M.road_site_clear_cost(s.tiles[t.id],s.stock_farm_fields and s.stock_farm_fields[t.id]) end
    if not price then return nil,why end
    clear_limit=clear_limit-rules.unit
    return price,{class=0,ground=0,density=0}
  end
  local x,z=M.xy(first)
  local u,v=M.xy(last)
  local plan,why=rules.quote(grid,x,z,u,v,diagonal,opts)
  if not plan then return nil,why end
  local ids={}
  for _,a in ipairs(plan.items) do ids[#ids+1]=a.id end
  plan.ids=ids
  if not execute then return plan end
  local policy=s.stock_road_town_policy or {}
  local authority=M.road_tree_authority()
  local function random() return M.stock_random_u32(s) end
  local ratings={}
  for _,a in ipairs(plan.items) do
    local t=s.tiles[a.id]
    if a.add then
      t.wood.count=t.wood.count+1
    else
      if a.clear then
        if t.terrain=="water" then coastal_world.clear_apply(s,a.id) end
        if s.stock_farm_fields then s.stock_farm_fields[a.id]=nil end
        t.stock_clear_ground=nil
      end
      t.stock_clear_density,t.stock_clear_visits=nil,nil
      t.wood=rules.new_tree(a,random)
      local town,d=authority.nearest(s,a.id)
      if town and d<(policy.dist_local_authority or 20) then
        local old=ratings[town.id] or company.stock_town_authority_ratings and
          company.stock_town_authority_ratings[town.id] or 500
        ratings[town.id]=rules.rating(old)
      end
    end
  end
  authority.apply(company,ratings)
  company.stock_tree_plant_limit=plan.quota_after
  company.clear_limit=clear_limit
  debit(company,plan.cost)
  s.topology=(s.topology or 0)+1
  return plan
end
local function land_rules()
  if not stock_land_rules then
    load_road_rules()
    stock_land_rules=dofile(module_root.."openttd/owned_land.lua")(landscape_rules)
  end
  return stock_land_rules
end
function M.is_owned_land(t) return t and t.stock_object and t.stock_object.kind=="owned_land" or false end
function M.owned_land_resale() return land_rules().resale() end
function M.purchase_land(s,owner,first,last,diagonal,execute)
  local company=s.companies[owner]
  if not (s.stock_generated_profile and s.corner_grid and company) then return nil,"LAND_PURCHASE_UNAVAILABLE" end
  local K=land_rules()
  local towns=s.stock_town_growth and s.stock_town_growth.towns
  local reserve=clear_area_rules.replenish(company.clear_limit,0)
  local function tile(x,z)
    local id=M.id(x,z)
    local t=id and s.tiles[id]
    if not t or t.stock_void then return nil,"TOO_CLOSE_TO_EDGE_OF_MAP" end
    if M.is_owned_land(t) then return {kind="owned_land",owner=t.owner,id=id} end
    if t.owner and t.owner~=owner then return nil,"OWNED_BY_ANOTHER" end
    if t.build or t.site or t.house or t.station or t.stock_industry or t.stock_landmark or t.stock_object or
        t.ship or t.airfield or t.tram or t.rail_tracks or t.level_crossing or t.rail_span_id
        or s.tunnel_below and s.tunnel_below[id] or s.rail_tunnel_below and s.rail_tunnel_below[id] then
      return nil,"SITE_UNSUITABLE"
    end
    return {id=id,kind=t.terrain=="water" and "water" or "clear",
      bridge_above=s.bridge_above and s.bridge_above[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.aqueduct_above and s.aqueduct_above[id]}
  end
  local x,z=M.xy(first)
  local u,v=M.xy(last)
  local p,why=K.quote(s.corner_grid,x,z,u,v,diagonal,{towns=towns and next(towns)~=nil,tile=tile,
    owner=owner,cash=company.cash,allowance=company.stock_object_limit,clear_allowance=reserve,
    clear=function(cell)
      local t=s.tiles[cell.id]
      if cell.kind=="water" then
        if t.wood then return nil,"SITE_UNSUITABLE" end
        return quote_water_clear(s,owner,cell.id)
      end
      return M.road_site_clear_cost(t,s.stock_farm_fields and s.stock_farm_fields[cell.id])
    end})
  if not p then return nil,why end
  local ids={}
  for _,a in ipairs(p.items) do
    local cell=a.tile
    ids[#ids+1]=cell.id
    if execute then
      local t=s.tiles[cell.id]
      if cell.kind=="water" then coastal_world.clear_apply(s,cell.id) end
      if t.wood then
        local authority=M.road_tree_authority()
        authority.clear_road_trees(company,authority.tree_town(s,cell.id))
      end
      if s.stock_farm_fields then s.stock_farm_fields[cell.id]=nil end
      t.wood,t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=nil,nil,0,nil
      t.owner=owner
      t.stock_object={kind="owned_land"}
    end
  end
  p.ids=ids
  if execute then
    company.stock_object_limit,company.clear_limit=p.allowance,p.clear_allowance
    debit(company,p.cost)
    s.topology=(s.topology or 0)+1
  end
  return p
end
function M.landscape(s,owner,mode,x,z,u,v,diagonal,quote_only)
  if not s.corner_grid then return false,"Enable shared-corner terrain first." end
  load_road_rules()
  -- Detached callers can request the actual command footprint without
  -- opening a company or otherwise enacting the planned land edit.
  if quote_only=="footprint" and not (s.companies and s.companies[owner]) then
    return false,"Open a company before quoting the landscape footprint."
  end
  local company=M.company(s,owner)
  local g=s.corner_grid
  local opts={cash=company.cash,allowance=landscape_rules.replenish(company.terraform_limit,0),max_height=32}
  local coast=coastal_world.terraform(s,owner,function(id) return coastal_tile_occupied(s,id) end)
  local staged_grid,barren_rail=g,{}
  local function remember_barren(step)
    for id in pairs(step.rail_barren or {}) do barren_rail[id]=true end
  end
  opts.after_step=function(step,scratch)
    coast.stage(step)
    staged_grid=scratch
    remember_barren(step)
  end
  opts.void=function(tx,tz) return s.tiles[M.id(tx,tz)].stock_void end
  opts.validate_tile=function(pass,tx,tz,mask,base,_,step)
    local id=M.id(tx,tz)
    local t=s.tiles[id]
    if coastal_world.is_water(t) then return coast.quote(tx,tz) end
    local mark=t and (t.stock_landmark or t.stock_object)
    -- RC1 founded objects keep their absolute top, independently of
    -- the builder's ownership. Stakes have no foundation but keep owner.
    if mark and not t.stock_void and not (
        s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
        s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.rail_tunnel_below and s.rail_tunnel_below[id]) then
      local old_mask,old_base=terrain_rules.tile(staged_grid,tx,tz)
      local foundation=road_rules.object_autoslope.quote(mark.kind,t.owner==owner,old_mask,old_base,mask,base,s.stock_road_town_policy)
      if foundation then return foundation end
      if mark.kind=="headquarters" or mark.kind=="statue" then return nil,"STOCK_OBJECT_SURFACE_HEIGHT" end
      if mark.kind=="owned_land" then return nil,"OWNED_BY_ANOTHER" end
    end
    local crossing=t and t.level_crossing
    local wiring=crossing and crossing_bindings[s]
    if wiring and not (
        s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
        s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.rail_tunnel_below and s.rail_tunnel_below[id]) then
      local foundation=wiring.runtime.world.foundation_quote(crossing,mask,base,s.stock_road_town_policy)
      if foundation then return foundation end
      -- The stock fallback would clear the crossing. Here a destructive
      -- action still requires the player to pick a layer with Bulldozer.
      return nil,"CROSSING_SURFACE_HEIGHT"
    end
    local field=t and t.airfield and t.airfield.layout~="oilrig" and s.stock_small_airports
      and s.stock_small_airports[t.airfield.airport]
    if field and t.terrain~="water" and not t.stock_void and not t.ship
      and not (s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
        s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.rail_tunnel_below and s.rail_tunnel_below[id]) then
      local old_mask,old_base,top=terrain_rules.tile(staged_grid,tx,tz)
      local foundation=field.ground==top*8 and road_rules.autoslope.airport(old_mask,old_base,mask,base,s.stock_road_town_policy)
      if foundation then return foundation end
      return nil,"AIRPORT_SURFACE_HEIGHT"
    end
    if t and t.house and t.source_house and not t.stock_void and not t.site
      and not (s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
        s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.rail_tunnel_below and s.rail_tunnel_below[id]) then
      local old_mask,old_base=terrain_rules.tile(staged_grid,tx,tz)
      local foundation=road_rules.town_foundation.autoslope(old_mask,old_base,mask,base,s.stock_road_town_policy)
      if foundation then return foundation end
      return nil,"TOWN_HOUSE_HEIGHT"
    end
    -- RC1 TerraformTile_Station (rail and waypoint) and the depot
    -- branch of TerraformTile_Rail. Allow an unchanged entrance or pair
    -- of ends, never reshape an active free-run track by this path.
    local rail_term=t and t.build=="stock_rail" and
      (t.rail_station_id or t.rail_waypoint_id or t.rail_depot_dir~=nil)
    if rail_term and not t.rail_span_id and t.terrain~="water" and not t.stock_void
      and not (s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
        s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.rail_tunnel_below and s.rail_tunnel_below[id]) then
      local axis=t.rail_station_axis or t.rail_waypoint_axis
      local direction=axis or t.rail_depot_dir
      if direction then
        local old_mask,old_base=terrain_rules.tile(staged_grid,tx,tz)
        local quote=road_rules.autoslope.terminal(direction,axis~=nil,old_mask,old_base,mask,base,s.stock_road_town_policy)
        if quote then return quote end
      end
      return nil,"RAIL_FACILITY_HEIGHT"
    end
    -- Preserve the running profile of ordinary rail, including signal tiles.
    -- Check flooded lower halves with the live ship clearance guard;
    -- crossings and layered spans have separate construction commands.
    if t and t.build=="stock_rail" and (t.rail_tracks or 0)>0 and not rail_term and not crossing
      and not t.rail_span_id and not t.stock_void and not t.ship and not t.airfield
      and not (s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
        s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.rail_tunnel_below and s.rail_tunnel_below[id]) then
      local old_mask,old_base=terrain_rules.tile(staged_grid,tx,tz)
      local policy=s.stock_road_town_policy or {}
      local half_water=t.rail_ground==13 and not barren_rail[id]
      local ship_in_way=half_water and (old_mask==1 or old_mask==2 or old_mask==4 or old_mask==8)
        and coastal_tile_occupied(s,id)
      local quote,why=road_rules.rail_autoslope.quote(t.rail_tracks,old_mask,old_base,mask,base,{
        autoslope=policy.autoslope,build_on_slopes=policy.build_on_slopes,foundation_price=policy.foundation_price,
        half_water=half_water,ship_in_way=ship_in_way,clear_water=policy.clear_water,
      })
      if not quote then return nil,why end
      -- Regular and inclined geometry mounts for all gauges; only
      -- ordinary RAIL has the specialized split-foundation meshes.
      if (t.rail_type or 0)~=0 then
        local H=road_rules.rail_height
        if H.split(H.profile({kind="rail",trackbits=t.rail_tracks},base,mask)) then
          return nil,"RAIL_SPLIT_UNMOUNTED"
        end
      end
      if pass==1 and quote.barren then
        step.rail_barren=step.rail_barren or {}
        step.rail_barren[id]=true
      end
      return quote.price
    end
    -- Terrain deformation is only in place when the source road surface
    -- or terminal entrance is unchanged, so active orders remain valid.
    -- Other co-located structures retain their independent validations.
    if t and (t.build or t.tram) and not crossing and not t.road_bridge_id and not t.road_tunnel_id
        and not t.rail_span_id and not t.rail_tracks and not t.wood and not t.site and not t.house and not t.stock_object
        and not t.stock_industry and not t.stock_landmark and not t.ship and not t.airfield
        and not (s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
          s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
          s.rail_tunnel_below and s.rail_tunnel_below[id]) then
      local road,tram=t.road_bits or 0,t.tram
      local trip=t.build
      local A=road_rules.autoslope
      local policy=s.stock_road_town_policy
      local old_mask,old_base
      if trip=="road" or trip=="road_station" or trip=="road_depot" or trip==nil and tram then
        old_mask,old_base=terrain_rules.tile(staged_grid,tx,tz)
      end
      local foundation
      if old_mask and t.road_waypoint_id then
        local dir=road==10 and 0 or road==5 and 1
        if dir then foundation=A.terminal(dir,true,old_mask,old_base,mask,base,policy) end
      elseif old_mask and (trip=="road" or trip==nil and tram and tram.kind=="road") and (not tram or tram.kind=="road") then
        local bits=tram and road_rules.union(road,tram.tram_bits or 0) or road
        foundation=A.normal(bits,old_mask,old_base,mask,base,policy)
      elseif old_mask and trip=="road_depot" and t.depot_dir then
        foundation=A.terminal(4-t.depot_dir,false,old_mask,old_base,mask,base,policy)
      elseif old_mask and trip=="road_station" then
        local axis=t.stop_axis or road
        local dir=({[10]=0,[5]=1,[8]=0,[4]=1,[2]=2,[1]=3})[axis]
        if dir then
          foundation=A.terminal(dir,axis==10 or axis==5,old_mask,old_base,mask,base,policy)
        end
      elseif old_mask and trip==nil and tram and (tram.kind=="depot" or tram.kind=="drive_stop") and tram.dir then
        foundation=A.terminal(tram.dir,tram.kind=="drive_stop",old_mask,old_base,mask,base,policy)
      end
      if foundation then return foundation end
    end
    if not t or t.terrain=="water" or t.wood or t.site or t.stock_industry or t.stock_landmark or t.house or t.build or t.tram or t.ship or t.airfield or
        M.rail_span_protected(s,id) or (s.bridge_above and s.bridge_above[id]) or (s.aqueduct_above and s.aqueduct_above[id]) or
        (s.tunnel_below and s.tunnel_below[id]) or (t.owner and t.owner~=owner) then
      return nil,"PROTECTED_TILE"
    end
    return 0
  end
  local plan,reason,px,pz
  if not u and (mode=="raise" or mode=="lower") then
    plan,reason,px,pz=landscape_rules.corner(g,x,z,mode=="raise",opts)
  elseif u and v then
    plan,reason,px,pz=landscape_rules.level(g,x,z,u,v,mode,diagonal,opts)
  else return false,"Select the corner(s) to change." end
  if not plan or #plan.changes==0 then
    local why=(plan and plan.halted) or reason
    local explanations={PROTECTED_TILE="Clear forest first; a building or protected infrastructure blocks this corner.",
      NOT_ENOUGH_MONEY="Not enough money for the next change.",ALREADY_AT_SEA_LEVEL="Already at sea level.",
      ALREADY_LEVELLED="Already level.",TOO_HIGH="The edit exceeds this world's height limit.",
      MUST_DEMOLISH_CANAL_FIRST="Dismantle the canal before landscaping.",
      MUST_DEMOLISH_RIVER_FIRST="Use the Bulldozer to remove the river before landscaping.",
      VEHICLE_IN_THE_WAY="A vessel is in the way or has reserved the waterway.",
      CROSSING_SURFACE_HEIGHT="Keep the crossing deck at its current height on a supported slope, or remove the crossing first.",
      AIRPORT_SURFACE_HEIGHT="Landscaping cannot change the level of an active airport.",
      TOWN_HOUSE_HEIGHT="Keep the house foundation at its current height and avoid steep slopes.",
      STOCK_OBJECT_SURFACE_HEIGHT="Landscaping must keep the statue or headquarters level and avoid steep slopes.",
      MUST_REMOVE_RAILROAD_TRACK="Landscaping would change the running surface. Remove the tracks first.",
      RAIL_SPLIT_UNMOUNTED="That split foundation is available only on ordinary rail.",
      RAIL_FACILITY_HEIGHT="Landscaping must leave the platform or depot level and its entrances unchanged."}
    return false,(explanations[why] or water_clear_errors[why] or tostring(why or "Nothing changed."))
      ..(px and pz and (" (%d,%d)"):format(px,pz) or "")
  end
  if quote_only=="footprint" then
    return true,plan.cost,{corners=plan.changes,tiles=plan.dirty,terrain_revision=g.revision,
      topology=s.topology,allowance_after=plan.allowance_after}
  end
  if quote_only then return true,plan.cost end
  local okay,msg=landscape_rules.apply(g,plan)
  if not okay then return false,msg end
  coast.commit(plan)
  remember_barren(plan)
  company.terraform_limit=plan.allowance_after
  debit(company,plan.cost)
  local changed={}
  local peak=0
  for _,corner in ipairs(plan.changes) do peak=math.max(peak,corner.height) end
  for _,d in ipairs(plan.dirty) do
    local id=M.id(d.x,d.z)
    if id then
      local mask,base=terrain_rules.tile(g,d.x,d.z)
      local t=s.tiles[id]
      t.h=base
      if barren_rail[id] then t.rail_ground=0 end
      if t.airfield and t.airfield.layout~="oilrig" then
        local field=s.stock_small_airports and s.stock_small_airports[t.airfield.airport]
        if field then t.airfield.level=field.ground/8 end
      end
      -- The planner only admits shapes with the same crossing top. Keep
      -- the same record and reservation, but repaint its new foundation.
      local crossing=t.level_crossing
      if crossing then
        crossing.slope,crossing.foundation=mask,mask==0 and "none" or "flattened"
      end
      changed[#changed+1]=id
    end
  end
  s.topology=s.topology+1
  local extra=plan.skipped and #plan.skipped or 0
  return true,("Landscaped for $%d; %d corners changed%s."):format(plan.cost,#plan.changes,
    (extra>0 or plan.halted) and " (partial selection)" or ""),changed,peak
end
function M.road_bridge(s,owner,first,last,style,quote_only,municipal)
  if not s.corner_grid or not first or not last then return false,"Select two bridgeheads on shared-corner terrain." end
  load_road_rules()
  if not bridge_assets.mounts("road",style) then return false,"This bridge style is not available for this road." end
  local c=not municipal and M.company(s,owner)
  local board={xy=M.xy,id=M.id}
  board.tile=function(id)
    local t=s.tiles[id]
    if not t then return end
    local x,z=M.xy(id)
    local slope,base,top=terrain_rules.tile(s.corner_grid,x,z)
    local bridge=s.bridge_above and s.bridge_above[id]
    local raised=s.aqueduct_above and s.aqueduct_above[id]
    local existing=(bridge and s.stock_road_bridges[bridge]) or (raised and s.stock_aqueducts[raised])
    local portal=t.road_bridge_id and s.stock_road_bridges and s.stock_road_bridges[t.road_bridge_id]
    if portal and (portal.start==id or portal["end"]==id) then
      return {slope=slope,base=base,max_z=top,kind="bridge",transport="road",
        owner=portal.owner,axis=portal.axis,deck=portal.deck,bridge_type=portal.bridge_type,
        roadtype=portal.roadtype or 0,tramtype=portal.tramtype,
        road_owner=portal.road_owner or portal.owner,tram_owner=portal.tram_owner,
        other=portal.start==id and portal["end"] or portal.start,
        overhead=existing and {axis=existing.axis,deck=existing.deck}}
    end
    local kind
    local facility=not t.stock_void and not t.level_crossing and not t.rail_span_id and
      (M.bridge_water_facility(t.ship,top) or M.bridge_rail_facility(t,top))
    if facility then
      facility.slope,facility.base,facility.owner=slope,base,t.owner
      facility.overhead=existing and {axis=existing.axis,deck=existing.deck}
      -- One mounted elevated layer per tile.
      if s.rail_bridge_above and s.rail_bridge_above[id] or s.rail_tunnel_below and s.rail_tunnel_below[id] then
        facility.kind="obstruction"
      end
      return facility
    end
    if t.stock_void or t.tram or t.ship or t.airfield or t.stock_industry or t.stock_landmark or M.rail_span_protected(s,id) then
      kind="obstruction"
    elseif M.is_owned_land(t) then kind="owned_land"
    elseif t.rail_tracks and not t.rail_station_id and t.rail_depot_dir==nil then
      -- CheckBuildAbove_Rail admits stock plain rail, including signals.
      -- The ordinary rail and its dispatch state remain independent.
      kind="plain_rail"
    elseif t.build=="road" then kind="road"
    elseif t.build=="canal" then kind="canal"
    elseif t.site or t.house or t.build then kind="obstruction"
    elseif t.wood then kind="trees"
    elseif t.terrain=="water" then kind=t.coastal_water and "coast" or "water"
    else kind="clear" end
    return {slope=slope,base=base,max_z=top,kind=kind,owner=t.owner,
      overhead=existing and {axis=existing.axis,deck=existing.deck}}
  end
  board.clear_quote=function(id,t)
    return M.bridge_ramp_clear_quote(s,owner,id,t)
  end
  function board.check_build_above(id,t,axis,deck)
    return M.bridge_check_above(s,owner,id,t,axis,deck)
  end
  local plan,why,id=bridge_rules.plan(board,first,last,style,{owner=owner,budget=c and c.cash,
    company=not municipal,year=M.date(s)})
  if not plan then
    local x,z
    if id then x,z=M.xy(id) end
    if why=="BRIDGEHEAD_NEEDS_CLEAR_LAND" then
      why="Place the ramp on a clear bank tile, not open water or an occupied tile."
    else
      why=why~="OWNED_BY_ANOTHER" and water_clear_errors[why] or why
    end
    return false,why..(x and (" (%d,%d)"):format(x,z) or "")
  end
  if M.crossing_protected(s,plan.start) or M.crossing_protected(s,plan["end"]) then
    return false,"That tile is a protected level crossing."
  end
  for _,id in ipairs(plan.middle) do
    if M.crossing_protected(s,id) then return false,"The bridge would overlap a protected level crossing." end
  end
  if quote_only then return true,plan.price,plan end
  local bridge
  if plan.replacement then
    if municipal then return false,"The town does not replace an existing span during generation." end
    bridge=s.tiles[plan.start].road_bridge_id
    if not (bridge and s.tiles[plan["end"]].road_bridge_id==bridge) then
      return false,"The bridge changed. Select its two ramps again."
    end
  else
    bridge=s.next_stock_road_bridge or 1
    s.next_stock_road_bridge=bridge+1
  end
  s.stock_road_bridges=s.stock_road_bridges or {}
  s.bridge_above=s.bridge_above or {}
  plan.town=municipal or plan.replacement and s.stock_road_bridges[bridge].town or nil
  s.stock_road_bridges[bridge]=plan
  M.bridge_apply_ground_clears(s,owner,plan.clears,municipal)
  local dirty={plan.start,plan["end"]}
  for _,head in ipairs(dirty) do
    local t=s.tiles[head]
    t.build="stock_road_bridge";t.owner=plan.owner;t.road_bridge_id=bridge
    t.road_town=plan.town
  end
  for _,tile in ipairs(plan.middle) do s.bridge_above[tile]=bridge;dirty[#dirty+1]=tile end
  s.topology=s.topology+1
  if c then debit(c,plan.price) end
  local summary=plan.replacement and "%s bridge #%d upgraded for $%d. Its road connections are unchanged."
    or "%s bridge #%d built for $%d. Connect a road to the outside of each ramp."
  return true,summary:format(bridge_assets.names[style],bridge,plan.price),
    dirty,plan.deck
end
function M.wood_bridge(s,owner,first,last) return M.road_bridge(s,owner,first,last,0) end
local function tram_uses_road_span(s,span)
  return span.tramtype~=nil and (TramIndex.uses(s,span.start) or TramIndex.uses(s,span["end"]))
end
function M.remove_wood_bridge(s,owner,id,quote_only)
  local t=s.tiles[id]
  local bridge=t and t.road_bridge_id
  local span=bridge and s.stock_road_bridges[bridge]
  if not span or (span.owner~=owner and not span.town) then return false,"Select an end of your road bridge." end
  if tram_uses_road_span(s,span) then return false,"Stop the tram route using this bridge first." end
  for _,v in pairs(s.fleet) do
    for _,route_tile in ipairs(v.route or {}) do
      if route_tile==span.start or route_tile==span["end"] then
        return false,"Wait for the current vehicle route to clear the bridge."
      end
    end
  end
  load_road_rules()
  local c=s.companies[owner]
  local ratings
  if c and span.town then
    ratings=M.road_tree_authority().span_removal(s,c,id)
    if not ratings then return false,"The local authority refuses to allow removal of this bridge." end
  end
  local price=bridge_rules.clear_cost(span.total_length,span.roadtype or 0,span.tramtype)
  if not c or c.cash<price then return false,"Not enough funds to dismantle this bridge." end
  if quote_only then
    local middle={}
    for i,tile in ipairs(span.middle) do middle[i]=tile end
    return true,price,{start=span.start,["end"]=span["end"],middle=middle,
      deck=span.deck,owner=span.owner,bridge_type=span.bridge_type,replacement=span.replacement}
  end
  local dirty={span.start,span["end"]}
  for _,head in ipairs(dirty) do
    local tile=s.tiles[head]
    tile.build=nil;tile.owner=nil;tile.road_bridge_id=nil;tile.road_town=nil
    M.mark_clear_land(s,head)
  end
  for _,tile in ipairs(span.middle) do s.bridge_above[tile]=nil;dirty[#dirty+1]=tile end
  s.stock_road_bridges[bridge]=nil
  s.topology=s.topology+1
  debit(c,price)
  M.road_tree_authority().apply(c,ratings)
  return true,("Road bridge removed for $%d; land underneath retained."):format(price),dirty,span.deck
end
function M.road_tunnel(s,owner,start,quote_only,municipal,earthworks,random)
  if not s.corner_grid or not start then return false,"Select an uphill tile for the portal." end
  load_road_rules()
  local board={xy=M.xy,id=M.id}
  board.tile=function(id)
    local t=s.tiles[id]
    if not t or t.stock_void then return end
    local x,z=M.xy(id)
    local slope,base=terrain_rules.tile(s.corner_grid,x,z)
    return {slope=slope,base=base,water=t.terrain=="water"}
  end
  board.clear=function(id)
    local t=s.tiles[id]
    if M.is_owned_land(t) and t.owner==owner and not (M.rail_span_protected(s,id) or
        s.bridge_above and s.bridge_above[id] or s.tunnel_below and s.tunnel_below[id]) then
      return -M.owned_land_resale()
    end
    if t and not (t.owner or t.build or t.tram or t.ship or t.airfield or t.site or t.stock_industry or t.stock_landmark or t.house or t.wood or t.terrain=="water"
        or M.rail_span_protected(s,id)
        or s.bridge_above and s.bridge_above[id] or s.tunnel_below and s.tunnel_below[id]) then
      if municipal and earthworks then return M.road_site_clear_cost(t,s.stock_farm_fields and s.stock_farm_fields[id]) end
      return 0
    end
  end
  board.blocked=function(id,depth)
    local key=s.tunnel_below and s.tunnel_below[id]
    return key and s.stock_road_tunnels[key].base==depth
  end
  if municipal and earthworks then board.excavate=earthworks.quote end
  local c=not municipal and M.company(s,owner)
  local plan,why,at=tunnel_rules.plan(board,start,{owner=owner,budget=c and c.cash})
  if not plan then
    local x,z
    if at then x,z=M.xy(at) end
    return false,why..(x and (" (%d,%d)"):format(x,z) or "")
  end
  -- Ground is left undisturbed and a single subsurface crossing layer is
  -- kept in this host. Do not overwrite an older tunnel on another level.
  local keys=s.tunnel_below or {}
  for _,id in ipairs(plan.middle) do
    if keys[id] or s.tiles[id].road_tunnel_id or M.rail_span_protected(s,id) then
      return false,"This preview does not layer tunnels."
    end
  end
  if quote_only then return true,plan.price,plan end
  if plan.excavation then
    assert(earthworks and type(random)=="function","Municipal excavation needs the town RNG")
    earthworks.apply(plan.excavation,random)
    plan.excavation=nil
  end
  local key=s.next_stock_road_tunnel or 1
  s.next_stock_road_tunnel=key+1
  s.stock_road_tunnels=s.stock_road_tunnels or {}
  s.tunnel_below=keys
  plan.town=municipal
  s.stock_road_tunnels[key]=plan
  local dirty={plan.start,plan["end"]}
  for _,id in ipairs(dirty) do
    local t=s.tiles[id]
    if M.is_owned_land(t) then t.stock_object=nil end
    t.build,t.owner,t.road_tunnel_id="stock_road_tunnel",owner,key
    t.road_town=plan.town
  end
  for _,id in ipairs(plan.middle) do keys[id]=key end
  s.topology=s.topology+1
  if c then debit(c,plan.price) end
  return true,("Road tunnel #%d built for $%d. Connect the outer side of both portals."):format(key,plan.price),dirty
end
function M.remove_road_tunnel(s,owner,id,quote_only)
  local t=s.tiles[id]
  local key=t and t.road_tunnel_id
  local span=key and s.stock_road_tunnels[key]
  if not span or (span.owner~=owner and not span.town) then return false,"Select one of your tunnel portals." end
  if tram_uses_road_span(s,span) then return false,"Stop the tram route using this tunnel first." end
  for _,v in pairs(s.fleet) do for _,tile in ipairs(v.route or {}) do
    if tile==span.start or tile==span["end"] then return false,"Wait for vehicles using the tunnel." end
  end end
  local c,ratings=s.companies[owner]
  local price=0
  if span.town then
    if not c then return false,"Open a transport company before removing a public tunnel." end
    ratings=M.road_tree_authority().span_removal(s,c,id)
    if not ratings then return false,"The local authority refuses to allow removal of this tunnel." end
    price=(span.middle_length+2)*(30+2*40) -- RC1 Price::ClearTunnel and RoadClearCost(ROAD)
    if c.cash<price then return false,"Not enough funds to dismantle this tunnel." end
  end
  if quote_only then return true,price,span end
  local dirty={span.start,span["end"]}
  for _,portal in ipairs(dirty) do
    local h=s.tiles[portal];h.build,h.owner,h.road_tunnel_id,h.road_town=nil,nil,nil,nil
    M.mark_clear_land(s,portal)
  end
  for _,under in ipairs(span.middle) do s.tunnel_below[under]=nil end
  s.stock_road_tunnels[key]=nil;s.topology=s.topology+1
  if ratings then debit(c,price);M.road_tree_authority().apply(c,ratings) end
  return true,"Removed both tunnel portals; surface land preserved.",dirty
end
function M.discard_generated_town_span(s,id,town)
  local t=s.tiles[id]
  local bridge=t.road_bridge_id
  local records,links,field
  if bridge then records,links,field=s.stock_road_bridges,s.bridge_above,"road_bridge_id"
  else records,links,field=s.stock_road_tunnels,s.tunnel_below,"road_tunnel_id" end
  local key=t[field]
  local span=key and records[key]
  if not span or span.town~=town then return false end
  for _,head in ipairs({span.start,span["end"]}) do
    local cell=s.tiles[head]
    assert(cell[field]==key and cell.road_town==town)
    cell[field],cell.build,cell.owner,cell.road_town=nil,nil,nil,nil
    cell.stock_clear_ground,cell.stock_clear_density,cell.stock_clear_visits=nil,nil,nil
  end
  for _,mid in ipairs(span.middle) do
    assert(links[mid]==key)
    links[mid]=nil
  end
  records[key]=nil
  s.topology=s.topology+1
  return true
end
local road_flags={1,2,4,8}
local function has_edge(bits,d)
  return math.floor(bits/road_flags[d])%2==1
end
local function add_edge(bits,d)
  return has_edge(bits,d) and bits or bits+road_flags[d]
end
local function opposite(d) return (d+1)%4+1 end
local function road_axis(bits)
  if bits==1 or bits==4 or bits==5 then return 5 end
  if bits==2 or bits==8 or bits==10 then return 10 end
end
local function bridge_head(s,id,t)
  local span=t and (t.road_bridge_id and s.stock_road_bridges[t.road_bridge_id]
    or t.road_tunnel_id and s.stock_road_tunnels[t.road_tunnel_id])
  if not span then return end
  return id==span.start and span.head or span.tail,span
end
local function road_kind(t)
  return t and M.tools[t.build] and M.tools[t.build].mode=="road"
end
local function bits_for(s,id,t)
  if not road_kind(t) then return 0 end
  local head=bridge_head(s,id,t)
  if head then return road_flags[4-(head.inside_direction+2)%4] end
  if t.build=="road_depot" and t.depot_dir then return road_flags[t.depot_dir] end
  if t.road_bits~=nil then return t.road_bits end
  -- Compatibility for a populated world newly opted into the preview.
  -- Previously-built roads on this flat-only save have no half-tile bits.
  local bits=0
  for d=1,4 do
    local near=s.tiles[adjacent(id,d)]
    if road_kind(near) and compatible_road_owners(t,near) and
       (not near.depot_dir or near.depot_dir==opposite(d)) then bits=add_edge(bits,d) end
  end
  return bits
end
local function ground_shape(s,id)
  load_road_rules()
  if not s.corner_grid then
    local h=s.tiles[id].h
    return 0,h,h
  end
  local x,z=M.xy(id)
  return terrain_rules.tile(s.corner_grid,x,z)
end
local function road_shape(s,id,t)
  if not road_kind(t) then return nil end
  if t.road_terminal_level then
    local _,base=ground_shape(s,id)
    return 0,t.road_terminal_level,t.road_terminal_level>base and "leveled" or "none"
  end
  if t.level_crossing then
    local q=t.level_crossing
    return 0,q.top,q.foundation
  end
  local head=bridge_head(s,id,t)
  if head then
    if t.road_tunnel_id then return 0,s.stock_road_tunnels[t.road_tunnel_id].base,"none" end
    return head.road_slope,head.road_base,head.foundation
  end
  if not s.corner_grid then return 0,t.h,"none" end
  local mask,base=ground_shape(s,id)
  if t.road_bits==nil or t.build=="road_bridge" or t.build=="road_tunnel" then return 0,t.h,"none" end
  local foundation=road_rules.foundation(mask,t.road_bits)
  local surface,rise=slope_rules.foundation(mask,foundation)
  return surface,base+rise,foundation
end
function M.road_surface(s,id) return road_shape(s,id,s.tiles[id]) end
function M.road_bits(s,id) return bits_for(s,id,s.tiles[id]) end
function M.road_center_z(s,id,surface)
  load_road_rules()
  local slope,base
  if surface then slope,base=surface(id) else slope,base=road_shape(s,id,s.tiles[id]) end
  return base*8+slope_rules.pixel(8,8,slope)
end
function M.road_edge(s,id,d)
  local t=s.tiles[id]
  return road_flags[d] and has_edge(bits_for(s,id,t),d) or false
end
local function profiles_match(s,a,ta,b,tb,d,surface)
  local sa,ha,sb,hb
  if surface then
    sa,ha=surface(a)
    sb,hb=surface(b)
  else
    sa,ha=road_shape(s,a,ta)
    sb,hb=road_shape(s,b,tb)
  end
  if not sa or not sb then return false end
  -- Both edges are constant on a flat surface; only the two
  -- elevations matter. Keep the original tolerance.
  if sa==0 and sb==0 then return math.abs(ha-hb)<=1e-9 end
  -- Actual road edges always have a linear height profile. Compare both
  -- ends as well as the center to catch transverse staircase joins.
  for i=0,2 do
    local p=i/2
    local u,v=d==1 and p or d==2 and 1 or d==3 and p or 0,d==1 and 0 or d==2 and p or d==3 and 1 or p
    local x,z=d==1 and p or d==2 and 0 or d==3 and p or 1,d==1 and 1 or d==2 and p or d==3 and 0 or p
    if math.abs(ha+slope_rules.surface(u,v,sa)-(hb+slope_rules.surface(x,z,sb)))>1e-9 then return false end
  end
  return true
end
local function connected(s,id,d,plan)
  local j=adjacent(id,d)
  if not j then return false end
  local a,b=plan and plan[id] or s.tiles[id],plan and plan[j] or s.tiles[j]
  if not road_kind(a) or not road_kind(b) or not compatible_road_owners(a,b) then return false end
  if not has_edge(bits_for(s,id,a),d) or not has_edge(bits_for(s,j,b),opposite(d)) then return false end
  if s.corner_grid then return profiles_match(s,id,a,j,b,d) end
  return not s.has_town_roads or a.h==b.h
end
-- Used by the YAPF adapter. This deals only with actual connected
-- surfaces; stock road-vehicle access gates belong to the stock follower.
function M.road_geometry_connected(s,id,d,j,surface)
  if not j or adjacent(id,d)~=j then return false end
  local a,b=s.tiles[id],s.tiles[j]
  if not road_kind(a) or not road_kind(b) then return false end
  if not has_edge(bits_for(s,id,a),d) or not has_edge(bits_for(s,j,b),opposite(d)) then return false end
  if s.corner_grid then return profiles_match(s,id,a,j,b,d,surface) end
  return a.h==b.h
end
function M.road_connected(s,id,d)
  return road_flags[d] and connected(s,id,d) or false
end
-- OpenTTD 16.0-RC1 table/pricebase.h and ClearTile_Clear / Trees.
-- Use the base (pre-inflation) prices for the ordinary stock ROAD type.
M.road_foundation_price=250
M.road_piece_price=95
function M.road_tree_authority()
  if not town_road_authority then
    local path=debug and debug.getinfo(1,"S").source
    local base=path and path:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    town_road_authority=dofile(base.."town_road_authority.lua")(M,dofile(base.."openttd/road_town_permission.lua"))
  end
  return town_road_authority
end
-- DoClearSquare stores density zero on cleared stock land. Width,
-- height, variant and the corner grid are untouched.
function M.mark_clear_land(s,id)
  local t=s.tiles[id]
  if not s.stock_generated_profile or not t or t.terrain=="water" or t.stock_void then return end
  t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=nil,0,nil
  if s.stock_farm_fields then s.stock_farm_fields[id]=nil end
end
function M.road_site_clear_cost(t,farm_field)
  if M.is_owned_land(t) then return -M.owned_land_resale() end
  if t.wood then return 20*(type(t.wood)=="table" and t.wood.count or 1) end
  local kind=farm_field and 3 or t.stock_clear_ground or 0
  if kind==0 then return t.stock_clear_density==0 and 0 or 20 end
  if kind==2 then return 200 end
  if kind==3 then return 500 end
  return 40
end
-- RC1 CmdBuildBridge shares the dry LandscapeClear dispatch across
-- road, rail and water bridges. Clear ramps are removed; ClearTileProcs
-- explicitly preserves existing bare, grassy, rough, rocky or farm
-- land under the middle, but Trees and stock owned-land objects clear.
local function bridge_dry_ground_kind(kind)
  return kind=="clear" or kind=="trees" or kind=="owned_land"
end
local function bridge_dry_ground_quote(s,owner,id,record)
  if record.kind=="owned_land" and record.owner~=owner then return nil,"OWNED_BY_ANOTHER" end
  if not bridge_dry_ground_kind(record.kind) or record.owner and record.owner~=owner then
    return nil,"BRIDGE_LAND_CLEAR_REQUIRED"
  end
  local t=s.tiles[id]
  if record.kind=="trees" and t.terrain=="water" then
    if not t.coastal_water then return nil,"CAN_T_BUILD_ON_WATER" end
    load_road_rules()
    return coastal_world.road_tree_coast_quote(s,owner,id,function(at) return coastal_tile_occupied(s,at) end)
  end
  return M.road_site_clear_cost(t,s.stock_farm_fields and s.stock_farm_fields[id])
end
function M.bridge_ramp_clear_quote(s,owner,id,record)
  if bridge_dry_ground_kind(record.kind) then return bridge_dry_ground_quote(s,owner,id,record) end
  -- BuildBridge uses NoWater. Coast and CoastRocks ignore that flag and
  -- run the charged shore clear. Open water never reaches that branch.
  if record.kind=="coast" then return quote_water_clear(s,owner,id) end
  if record.kind=="water" or record.kind=="sea" or record.kind=="river" or record.kind=="canal" then
    return nil,"CAN_T_BUILD_ON_WATER"
  end
  return nil,"BRIDGEHEAD_NEEDS_CLEAR_LAND"
end
-- Engine bridge tables store only the middle cells, never the heads.
-- A bare presence marker is treated as unknown geometry, not as clearance.
function M.bridge_deck_at(s,id)
  for _,layer in ipairs(M.bridge_layers) do
    local key=s[layer[1]] and s[layer[1]][id]
    if key then
      local span=s[layer[2]] and s[layer[2]][key]
      return span and span.deck or nil,true
    end
  end
  return nil,false
end
M.bridge_layers={{"bridge_above","stock_road_bridges"},{"rail_bridge_above","stock_rail_spans"},
  {"aqueduct_above","stock_aqueducts"}}
-- The native station geometry stays separate from the stock layout key:
-- paired middle buildings and platforms have different overhead masks.
function M.bridge_rail_facility(t,top)
  if t.rail_depot_dir~=nil then return {kind="rail_depot",max_z=top} end
  if t.rail_station_id or t.rail_waypoint_id then
    return {kind="station",station_type=t.rail_station_id and "rail" or "rail_waypoint",
      layout=t.rail_station_gfx or t.rail_station_axis or t.rail_waypoint_axis or 0,max_z=top}
  end
end
function M.bridge_water_facility(ship,top)
  if not ship then return end
  local k=ship.kind
  if k=="dock" or k=="buoy" then
    local layout=k=="buoy" and 0 or ship.water_part and 4+ship.dir%2 or ship.dir
    return {kind="station",station_type=k,layout=layout,max_z=top}
  elseif k=="lock" or k=="ship_depot" then
    return {kind=k,part=ship.part,max_z=top}
  end
end
function M.bridge_check_above(s,owner,id,record,axis,deck)
  load_road_rules()
  if record.kind=="trees" or record.kind=="owned_land" then
    local cost,why=bridge_dry_ground_quote(s,owner,id,record)
    return cost,why,cost~=nil
  end
  return bridge_underlay.quote(record,axis,deck)
end
function M.bridge_apply_ground_clears(s,owner,ids,municipal)
  for _,id in ipairs(ids or {}) do
    local t=s.tiles[id]
    if M.is_owned_land(t) then
      t.owner,t.stock_object=nil,nil
    elseif t.wood then
      local council=M.road_tree_authority()
      if not municipal then council.clear_road_trees(M.company(s,owner),council.tree_town(s,id)) end
      t.wood=nil
    end
    if t.coastal_water then
      load_road_rules()
      coastal_world.clear_apply(s,id)
    end
    M.mark_clear_land(s,id)
  end
end
local function new_pieces(pieces,existing)
  local added,n=existing,0
  for d=1,4 do
    if has_edge(pieces,d) and not has_edge(added,d) then added=add_edge(added,d);n=n+1 end
  end
  return added,n
end
-- Scenario authoring only: establishes public carriageway before play.
-- OpenTTD can dynamically lay/extend town roads; this seeds authored layout.
function M.seed_town_road(s,town_id,id,bits)
  local town,t=s.sites[town_id],s.tiles[id]
  if not town or town.kind~="town" or not t then return nil,"Invalid town road location." end
  if type(bits)~="number" or bits<1 or bits>15 or bits~=math.floor(bits) then
    return nil,"Invalid town road edges."
  end
  local existing=t.build=="road" and t.road_town==town_id
  if t.owner or t.site or t.stock_industry or t.stock_landmark or t.house or t.tram or t.ship or t.airfield or wet(s,id) or (t.build and not existing) then
    return nil,"The town has no clear right of way."
  end
  if (s.corner_grid and ground_shape(s,id)~=0) or (not s.corner_grid and t.h~=0) then
    return nil,"Seed town roads on flat land."
  end
  t.build="road";t.road_town=town_id
  local combined=new_pieces(bits,existing and t.road_bits or 0)
  t.road_bits=combined;t.wood=nil
  s.has_town_roads=true
  return true
end
-- A road gesture is planned synchronously by the simulation owner.
-- Snapshot positions at the first guarded tile, not once per piece;
-- unoccupied terrain, no-ops and cheap edits never need the fleet.
function M.road_piece_occupancy(s)
  local occupied,pilot_path,tram_ground
  return function(id,with_tram,actual_tram_only)
    if not occupied then
      occupied={}
      for _,v in pairs(s.fleet) do
        local at=M.position(s,v)
        if at then occupied[at]=true end
      end
    end
    if occupied[id] then return true end
    if actual_tram_only then
      if not tram_ground then
        tram_ground={}
        TramIndex.each(s,function(p)
          local f=TramIndex.frame(p)
          if f and not f[10] then tram_ground[f[4]]=true end
        end)
      end
      return tram_ground[id]==true
    end
    if not with_tram then return false end
    -- The pilot depends on an exclusive tram route, even when its
    -- mesh is out of range. Index that path only for shared-layer work.
    if not pilot_path then
      pilot_path={}
      TramIndex.each(s,function(tram)
        for _,leg in ipairs(tram.legs or {}) do
          for _,at in ipairs(leg.path or {}) do pilot_path[at]=true end
        end
      end)
    end
    return pilot_path[id]==true
  end
end
local function road_piece_plan(s,owner,id,t,request,occupied)
  if t.roadworks then return nil,"Road works block that tile." end
  if t.level_crossing then
    local q=t.level_crossing
    if q.roadtype==nil then
      if q.tramtype and occupied(id,true) then return nil,"Wait for the tram to clear its route." end
      local change,why=M.crossing_construction_quote(s,owner,id,{kind="road",pieces=request})
      if not change then return nil,M.crossing_construction_error(why) end
      return {id=id,tool="road",build="road",road_bits=change.crossing.road_bits,owner=owner,h=t.h,
        level_crossing=change.crossing,crossing_quote=change},change.price
    end
    local _,added=new_pieces(request,q.road_bits)
    if q.road_owner~=owner then return nil,M.crossing_construction_error("OWNED_BY_ANOTHER") end
    if added~=0 then return nil,M.crossing_construction_error("FALLBACK_CLEAR") end
    return {id=id,tool="road",build="road",road_bits=q.road_bits,owner=t.owner,h=t.h},0
  end
  if s.level_crossing_enabled and t.build=="stock_rail" then
    local q,why=M.crossing_construction_quote(s,owner,id,{kind="road",pieces=request})
    if not q then return nil,M.crossing_construction_error(why) end
    return {id=id,tool="road",build="road",road_bits=q.crossing.road_bits,owner=owner,h=t.h,
      level_crossing=q.crossing,crossing_quote=q},q.price
  end
  if t.airfield then return nil,"That tile is part of the country airfield." end
  if t.ship then return nil,"That tile is part of a ship facility." end
  local tram=t.tram
  if tram and tram.kind=="drive_stop" and tram.tram_station and not t.build then
    -- RC1 road_cmd.cpp CmdBuildRoad, TileType::Station. The existing
    -- through axis is the only legal road. A half request buys both
    -- halves, adds no foundation, and doesn't touch station ownership.
    local _,off_axis=new_pieces(request,tram.tram_bits)
    if off_axis>0 then return nil,"Through stops need straight road. Join on an adjacent tile." end
    if not M.tram_stop_station(s,id) then return nil,"No active tram platform." end
    if occupied(id,false,true) then return nil,"Wait for the vehicle to clear that tile." end
    return {id=id,tool="road_station",build="road_station",h=t.h,road_bits=tram.tram_bits,
      stop_axis=tram.tram_bits,road_terminal_level=tram.terminal_level,
      joined_tram_station=tram.tram_station,owner=owner},2*M.road_piece_price
  end
  if tram and tram.kind~="road" and not tram.shared_station then
    return nil,"That tile has a dedicated tramway or tram facility."
  end
  if t.stock_landmark then return nil,"This landmark is protected." end
  if t.site or t.stock_industry then return nil,"Cannot build on a town centre or industry." end
  local coast=s.corner_grid and t.terrain=="water" and t.coastal_water and not t.build
  if t.owner and t.owner~=owner and not t.road_town and not coast then
    return nil,"Another company owns that tile."
  end
  if t.house then return nil,"Bulldoze that building first." end
  local coast_cost
  if wet(s,id) then
    if not coast then return nil,"Use a bridge over open water." end
    -- RC1 CmdBuildRoad calls LandscapeClear with NoWater. That flag
    -- rejects real water, not Coast/CoastRocks (ClearTile_Water).
    -- Clearing changes the tile type, not its corner heights.
    local why
    if t.wood then
      load_road_rules()
      coast_cost,why=coastal_world.road_tree_coast_quote(s,owner,id,function(at) return coastal_tile_occupied(s,at) end)
    else
      coast_cost,why=quote_water_clear(s,owner,id)
    end
    if not coast_cost then return nil,water_clear_errors[why] or why end
  end
  local existing=bits_for(s,id,t)
  if t.road_waypoint_id then
    local _,added=new_pieces(request,existing)
    if added~=0 then return nil,"Road waypoints must stay straight. Connect on the adjacent tile." end
    return {id=id,tool="road",build="road",road_bits=existing,owner=t.owner,h=t.h},0
  end
  if road_sign(t)~=0 then
    local combined=new_pieces(request,existing)
    if combined~=5 and combined~=10 then
      return nil,"One-way roads cannot have junctions. Remove the restriction first."
    end
  end
  -- Like an OpenTTD drive-through stop, the underlying public carriageway
  -- remains usable by any company, but cannot become a junction here.
  if t.build=="road_station" and (t.stop_axis or t.road_town) then
    local _,added=new_pieces(request,existing)
    if added>0 then return nil,"Through stops need straight road. Join on an adjacent tile." end
    return {id=id,tool=t.build,build=t.build,road_bits=existing,owner=t.owner,
      road_town=t.road_town,h=t.h},0
  end
  if s.road_economy and t.build=="road_station" and existing~=0 then
    local _,added=new_pieces(request,existing)
    if added>0 then return nil,"A bay stop has one entrance. Connect the road on the adjacent tile." end
    return {id=id,tool=t.build,build=t.build,road_bits=existing,owner=t.owner,h=t.h},0
  end
  if t.road_bridge_id or t.road_tunnel_id then
    local _,added=new_pieces(request,existing)
    if added~=0 then return nil,"Connect to the outside of a bridgehead, without turns on the ramp." end
    return {id=id,tool=t.build,build=t.build,road_bits=existing,owner=t.owner,road_bridge_id=t.road_bridge_id,road_tunnel_id=t.road_tunnel_id},0
  end
  if t.build=="road_depot" then
    if existing==request then return {id=id,tool=t.build,road_bits=existing,owner=owner},0 end
    return nil,"A depot has only one entrance."
  end
  if t.build and t.build~="road" and t.build~="road_station" then
    return nil,"Different infrastructure already occupies that tile."
  end
  local mask=ground_shape(s,id)
  local other=t.tram and t.tram.tram_bits or 0
  local policy=s.stock_road_town_policy
  local pieces,foundation=request,false
  -- RC1 CmdBuildRoad: an exact copy of the other layer needs no second
  -- foundation. Other requests pass the stock slope tables and still
  -- must agree with the installed tramway's physical foundation.
  if other~=request then
    pieces,foundation=road_rules.prepare(mask,request,existing,other,not policy or policy.build_on_slopes~=false)
    if not pieces and foundation~="ALREADY_BUILT" then return nil,"Land sloped in the wrong direction." end
  end
  local combined,count=new_pieces(pieces or 0,existing)
  if other~=0 and count>0 and road_rules.foundation(mask,combined)~=road_rules.foundation(mask,other) then
    return nil,"The road and tram tracks must share the same foundation."
  end
  local clear_site=count>0 and t.build==nil and other==0
  local owned=clear_site and M.is_owned_land(t)
  local clearing=coast_cost or (owned and -M.owned_land_resale()
    or clear_site and M.road_site_clear_cost(t,s.stock_farm_fields and s.stock_farm_fields[id]) or 0)
  local cost=count*M.road_piece_price+(foundation==true and M.road_foundation_price or 0)+clearing
  local proposed={id=id,tool=t.build or "road",build=t.build or "road",
    road_bits=combined,owner=(not t.road_town and owner or nil),
    road_town=t.road_town,depot_dir=t.depot_dir,h=t.h,clear_road_site=clear_site,
    clear_road_coast=coast_cost~=nil or nil,road_site_cost=clearing,clear_owned_land=owned or nil,
    road_tree_town=clear_site and t.wood and M.road_tree_authority().tree_town(s,id) or nil}
  -- A change of foundation must not be made under a vehicle.
  if cost>0 and (other~=0 or t.build and (t.road_town or
      road_rules.foundation(mask,existing)~=road_rules.foundation(mask,combined))) then
    if occupied(id,other~=0) then return nil,"Wait for the vehicle to clear that tile." end
  end
  return proposed,cost
end
local function linking_errors(s,proposed)
  for _,id in ipairs(proposed.order) do
    local a=proposed[id]
    for d=1,4 do
      local j=adjacent(id,d)
      local b=proposed[j] or s.tiles[j]
      if j and road_kind(b) and compatible_road_owners(a,b) and
        has_edge(a.road_bits,d) and has_edge(bits_for(s,j,b),opposite(d)) and
        not connected(s,id,d,proposed) then
        return "The road edges do not meet at the same level."
      end
    end
  end
end
-- Ordinary mixed road/tram tile: adding road bits changes only the
-- road layer. Tram facilities and level crossings have separate rules.
function M.town_mixed_road(s,id)
  local t=id and s.tiles[id]
  return not not (t and t.build=="road" and t.road_bits and t.road_bits~=0 and
    t.tram and t.tram.kind=="road" and t.tram.tramtype==1 and (t.tram.tram_bits or 0)~=0 and
    not (t.stock_void or t.stock_object or t.stock_landmark or t.stock_industry or t.site or t.house or
       t.station or t.road_waypoint_id or t.level_crossing or t.rail_tracks or t.rail_span_id or
       t.road_bridge_id or t.road_tunnel_id or t.ship or t.airfield))
end

-- CmdBuildRoad can add bits to company pavement. Its existing road
-- owner is preserved (SetRoadOwner only runs when there were no bits).
function M.town_company_road(s,id)
  local t=id and s.tiles[id]
  return t and t.owner and s.companies[t.owner] and not t.road_town and t.build=="road" and
    (not t.roadtype or t.roadtype==0) and t.road_bits and t.road_bits~=0 and
    not (t.stock_void or t.stock_object or t.stock_landmark or t.stock_industry or t.site or t.house or
      t.tram and not M.town_mixed_road(s,id) or t.station or t.road_waypoint_id or t.level_crossing or
      t.rail_tracks or t.rail_span_id or t.road_bridge_id or t.road_tunnel_id or t.ship or t.airfield)
end

-- A municipal write owns its paid-free action; it may not demolish a
-- company facility. Eligible company pavement keeps its current owner.
function M.town_road_piece(s,town,id,bits,execute)
  local t=id and s.tiles[id]
  if t and t.build=="stock_rail" and t.rail_tracks then
    local c=crossing_bindings[s]
    local policy=s.stock_road_town_policy
    if not c or policy and policy.allow_town_level_crossings==false or
        c.survey_clear and not c.survey_clear() then return end
    local rail=c.rail(s)
    local quote=c.runtime.town_quote(s,town,id,bits,rail)
    if not quote then return end
    local r={id=id,build="road",road_town=town,road_bits=quote.crossing.road_bits,
      h=t.h,level_crossing=quote.crossing,crossing_quote=quote}
    if linking_errors(s,{[id]=r,order={id}}) then return end
    if execute then
      c.runtime.apply(s,quote,rail)
      s.has_town_roads=true
      s.topology=(s.topology or 0)+1
      c.runtime.refresh(s,c.rail(s))
    end
    return r
  end
  local company_road=M.town_company_road(s,id)
  local mixed=M.town_mixed_road(s,id)
  if not t or t.stock_void or t.stock_object or t.owner and not company_road or t.tram and not mixed or
      t.station or t.road_waypoint_id or t.level_crossing or t.rail_tracks or t.rail_span_id or
      t.road_bridge_id or t.road_tunnel_id or (t.build and t.build~="road") or
      (t.road_town and t.road_town~=town) then return end
  load_road_rules()
  local check=M.road_piece_occupancy(s)
  local function occupied(at,with_tram,actual_tram_only)
    return check(at,with_tram,mixed or actual_tram_only)
  end
  -- The existing tile needs EnsureNoVehicleOnGround even if the
  -- foundation doesn't change. A tram's future visits don't occupy it.
  if t.build=="road" and occupied(id,mixed) then return end
  local r,c=road_piece_plan(s,company_road and t.owner or nil,id,t,bits,occupied)
  if not r or c==0 then return end
  if not company_road then r.road_town=town end
  if linking_errors(s,{[id]=r,order={id}}) then return end
  if execute then
    if r.clear_road_coast then coastal_world.clear_apply(s,id) end
    if r.clear_road_site then
      t.wood,t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=nil,nil,nil,nil
      if s.stock_farm_fields then s.stock_farm_fields[id]=nil end
    end
    t.build,t.road_town,t.road_bits="road",r.road_town,r.road_bits
    s.has_town_roads=true
    s.topology=(s.topology or 0)+1
  end
  return r
end

-- RC1 ClearTile_Road with Auto and NoWater, used by CanBuildHouseHere.
-- OWNER_TOWN may erase the single normal road bit. Never quote a
-- crossing, depot, tram, occupied road, or road reconstruction site.
function M.town_clear_road_tip(s,id,execute)
  local t=id and s.tiles[id]
  if not t or t.build~="road" or t.roadworks or t.stock_void or t.stock_object or
      t.tram or t.station or t.road_waypoint_id or t.level_crossing or t.rail_tracks or
      t.rail_span_id or t.road_bridge_id or t.road_tunnel_id or t.road_depot_dir or t.depot_dir or
      t.site or t.house or t.stock_industry or t.stock_landmark or t.ship or t.airfield or
      M.bridge_deck_at(s,id) then return false end
  local bits=t.road_bits
  if bits~=1 and bits~=2 and bits~=4 and bits~=8 then return false end
  if M.road_piece_occupancy(s)(id,true,true) then return false end
  if execute then
    t.build,t.owner,t.road_bits,t.road_town,t.roadtype=nil,nil,nil,nil,nil
    t.roadside,t.stock_roadside_town,t.road_disallowed,t.disallowed,t.closed=nil,nil,nil,nil,nil
    M.mark_clear_land(s,id)
    s.topology=(s.topology or 0)+1
  end
  return true
end

function M.town_clear_coast(s,id,execute)
  local t=s.tiles[id]
  if not t or t.stock_void or not t.coastal_water or t.owner or t.build or t.stock_object or
      t.site or t.house or t.rail_tracks or t.ship or t.airfield or t.tram or t.stock_industry then return end
  load_road_rules()
  local cost
  if t.wood then
    cost=coastal_world.road_tree_coast_quote(s,nil,id,function(at) return coastal_tile_occupied(s,at) end)
  else
    cost=quote_water_clear(s,nil,id)
  end
  if not cost then return end
  if execute then coastal_world.clear_apply(s,id);t.wood=nil end
  return cost
end
local function road_drag_plan(s,owner,ids)
  local requested,order,proposed,result,total={}, {}, {order={}}, {}, 0
  local occupied=M.road_piece_occupancy(s)
  if #ids==0 then return result,total end
  for i,id in ipairs(ids) do
    if not s.tiles[id] then return nil,"Outside the region." end
    if requested[id]==nil then order[#order+1]=id;requested[id]=0 end
    local previous=ids[i-1]
    if previous and previous~=id then
      local direction
      for k=1,4 do if adjacent(previous,k)==id then direction=k;break end end
      if not direction then return nil,"Road drags must join neighboring tiles." end
      requested[previous]=add_edge(requested[previous],direction)
      requested[id]=add_edge(requested[id],opposite(direction))
    end
  end
  if #order==1 then
    local id=order[1]
    for d=1,4 do
      local j=adjacent(id,d)
      if j and road_kind(s.tiles[j]) and road_access(s.tiles[j],owner) and M.road_edge(s,j,opposite(d)) then
        requested[id]=add_edge(requested[id],d)
      end
    end
    if requested[id]==0 then
      local existing=bits_for(s,id,s.tiles[id])
      local mask=ground_shape(s,id)
      requested[id]=existing~=0 and existing or (road_rules.prepare(mask,10,0,0,true) and 10 or 5)
    end
  end
  for _,id in ipairs(order) do
    local proposal,cost=road_piece_plan(s,owner,id,s.tiles[id],requested[id],occupied)
    if not proposal then return nil,cost end
    -- Unchanged legacy roads keep their already-established surface.
    if cost>0 then
      total=total+cost
      result[#result+1]=proposal
      proposed[id]=proposal;proposed.order[#proposed.order+1]=id
    end
  end
  local error_message=linking_errors(s,proposed)
  if error_message then return nil,error_message end
  if total>M.company(s,owner).cash then return nil,"Not enough cash." end
  return result,total
end
-- OpenTTD 16.0-RC1 road_gui.cpp OnPlaceDrag, hotspot change #16101.
-- The 3D selector maps the click to source fractional tile coordinates.
-- Project onto one axis from the center of the pressed tile; a click on
-- one tile uses the stock fractional-coordinate tests.
function M.autoroad_selection(start,first,hover,last,fixed_axis)
  local x,z=M.xy(start)
  local u,v=M.xy(hover)
  local function fract(point,i,axis)
    return math.max(0,math.min(15,math.floor((point[axis]-(i*2-.5))*8)))
  end
  local ex,ez=fract(last,u,"x"),fract(last,v,"z")
  local gx,gz=16*(u-x)+ex-8,16*(v-z)+ez-8
  local click=hover==start
  local along_x
  if fixed_axis~=nil then
    along_x=fixed_axis==0
  elseif click then
    along_x=(ex<ez and ex+ez<=15) or (ex>ez and ex+ez>=15)
  else
    along_x=math.abs(gz)<math.abs(gx)
  end
  return along_x and M.id(u,z) or M.id(x,v),along_x and 0 or 1,
    (along_x and fract(first,x,"x") or fract(first,z,"z"))>=8,
    (along_x and ex or ez)>=8
end

-- OpenTTD 14.1 CmdBuildLongRoad (human GUI, default two-way road).
-- The shared stock sweep is also used by the one-way tool. Use the native
-- tile quote so it recognizes crossing layers, bridges and through stops.
function M.autoroad_plan(s,owner,start,last,axis,start_half,end_half)
  if not s.corner_grid or not s.tiles[start] or not s.tiles[last] then return nil,"Outside the region." end
  load_road_rules()
  if type(start_half)~="boolean" or type(end_half)~="boolean" then
    return nil,"Select a road surface."
  end
  local board={xy=M.xy}
  function board.adjacent(id,dir) return adjacent(id,4-dir) end
  function board.connects(id,dir)
    local neighbor=board.adjacent(id,dir)
    local t=neighbor and s.tiles[neighbor]
    return t and (t.roadtype or 0)==0 and M.road_edge(s,neighbor,opposite(4-dir))
  end
  local drag,why=long_road_rules.drag(board,start,last,axis,
    {toggle=0,start_half=start_half,end_half=end_half})
  if not drag then return nil,"Road drags must follow one axis." end
  local proposed={order={}}
  local occupied=M.road_piece_occupancy(s)
  local q,err=long_road_rules.sweep(drag,function(req)
    if req.bits==0 then return nil,"No road half selected." end
    local id=req.tile
    local t=s.tiles[id]
    if t.stock_void then return nil,"Outside the playable map." end
    if t.roadworks then return nil,"Road works block that tile." end
    local proposal,cost=road_piece_plan(s,owner,id,t,req.bits,occupied)
    if not proposal then return nil,cost end
    if cost==0 then return nil,"ALREADY_BUILT" end
    proposed[id]=proposal;proposed.order[#proposed.order+1]=id
    return {changed=true,cost=cost,proposal=proposal}
  end)
  if not q then return nil,err=="ALREADY_BUILT" and "Already built." or err end
  local bad=linking_errors(s,proposed)
  if bad then return nil,bad end
  local c=s.companies[owner]
  if q.cost>(c and c.cash or 100000) then return nil,"Not enough cash." end
  local changes,ids={},{}
  for _,entry in ipairs(q.changes) do
    changes[#changes+1]=entry.proposal
    ids[#ids+1]=entry.proposal.id
  end
  return {changes=changes,ids=ids,cost=q.cost,stopped_at=q.stopped_at,
    stop_reason=q.stopped_at and q.skipped[#q.skipped].reason or nil,skipped=q.skipped}
end

local function site_radius(s,id)
  local best,dist
  local served={}
  for i,a in ipairs(s.sites) do
    local d=M.distance(a.tile,id)
    if not a.closed and d<=5 then
      served[#served+1]=i
      if not dist or d<dist then best,dist=i,d end
    end
  end
  table.sort(served,function(a,b)
    local da,db=M.distance(s.sites[a].tile,id),M.distance(s.sites[b].tile,id)
    return da==db and a<b or da<db
  end)
  return best,served
end
M.site_radius=site_radius
function M.nearest_town(s,id)
  local best,distance
  for _,site in ipairs(s.sites) do
    if site.kind=="town" then
      local d=M.distance(site.tile,id)
      if not distance or d<distance then best,distance=site,d end
    end
  end
  return best,distance
end
-- Station-to-town association is not passenger catchment. OpenTTD's
-- BuildRoadStop places a station on a legal site, and its station record
-- names a nearby town regardless of which houses fall inside the stop.
local function road_stop_site(s,id)
  local near,served=site_radius(s,id)
  if not (s.road_stock_house_supply and M.road_stock_service_active(s)) then
    return near,served,false
  end
  local town=M.nearest_town(s,id)
  return town and town.id or near,served,true
end
-- RC1 BuildRoadStop: one canonical station with the bus facility and a
-- physical tile for catchment. Keep its access type distinct from road.
function M.register_tram_station(s,owner,id)
  local retirement=M.road_station_retirement()
  local previous=retirement.closest(s,"station",owner,id,function(row) return row.tram_only end)
  local best,served=road_stop_site(s,id)
  if previous then
    local station=assert(retirement.take(s,"station",previous.id))
    station.tile,station.site,station.served=id,best,served
    station.road_members=nil
    s.stations[station.id]=station
    return station.id
  end
  local sid=s.next_station
  s.next_station=sid+1
  local town=s.sites[best]
  s.stations[sid]={id=sid,tile=id,mode="road",owner=owner,tram_only=true,stop_type="bus",
    name=(town and town.name.." " or "").."Tram platform #"..sid,
    town=town and town.kind=="town" and best or nil,site=best,served=served,stock={},last_service={},
    stock_station_id=M.stock_station_slot(s)}
  return sid
end
function M.tram_stop_id(t)
  local part=t and t.tram
  if not part or part.kind~="drive_stop" then return end
  if part.shared_station and part.shared_station==t.station then return part.shared_station end
  return part.tram_station
end
function M.tram_stop_station(s,id,owner)
  local tile=s.tiles[id]
  local sid=M.tram_stop_id(tile)
  local st=sid and s.stations[sid]
  if st and (not owner or st.owner==owner) and st.owner==tile.tram.owner and
     ((st.tram_only and st.tile==id and sid==tile.tram.tram_station) or
      (not st.tram_only and sid==tile.station)) then
    return st
  end
end
function M.road_station_in_use(s,sid)
  for _,v in pairs(s.fleet) do
    if v.dest==sid or v.station==sid then return true end
    for _,o in ipairs(v.orders or {}) do if o.station==sid then return true end end
  end
  return false
end
function M.activate_tram_road_stop(s,id,road_owner)
  local t=s.tiles[id]
  local st=assert(M.tram_stop_station(s,id))
  assert(st.tram_only)
  local p=t.tram
  t.build,t.owner,t.station="road_station",road_owner,st.id
  t.stop_axis,t.road_bits,t.road_terminal_level=p.tram_bits,p.tram_bits,p.terminal_level
  t.road_stop_type="bus"
  t.road_disallowed,t.disallowed=nil,nil
  p.tram_station,p.shared_station,p.tram_shelter=nil,st.id,true
  st.tram_only=nil
end
local overhead_road_layers={
  {"bridge_above","stock_road_bridges"},
  {"rail_bridge_above","stock_rail_spans"},
  {"aqueduct_above","stock_aqueducts"},
}
-- The road construction adapter uses the limiting deck when multiple
-- raised structures cross the site. Missing/corrupt span data is never
-- interpreted as unlimited clearance.
function M.road_overhead_deck(s,id)
  local lowest
  for _,layer in ipairs(overhead_road_layers) do
    local index=s[layer[1]]
    local key=index and index[id]
    if key then
      local spans=s[layer[2]]
      local span=spans and spans[key]
      local deck=span and span.deck
      if type(deck)~="number" or deck%1~=0 or deck<0 then return nil,true end
      lowest=lowest and math.min(lowest,deck) or deck
    end
  end
  return lowest,lowest~=nil
end
local stock_road_terminals
local terminal_errors={
  PARAMETERS="Choose a valid tile and direction.",
  OWNED_BY="That tile belongs to another company.",
  PROTECTED_TERMINAL_TILE="Choose an unoccupied dry tile or a suitable straight stretch of road.",
  LAND_SLOPED_IN_WRONG_DIRECTION="That slope is too low at the chosen door.",
  FLAT_LAND_REQUIRED="That slope can't support a stop in this orientation.",
  VEHICLE_IN_THE_WAY="Wait until traffic has cleared the tile.",
  DRIVE_THROUGH_DIRECTION="Match the axis of the existing road.",
  DRIVE_THROUGH_CORNER="Drive-through stops can't go on a road corner.",
  DRIVE_THROUGH_JUNCTION="Drive-through stops can't go on a road junction.",
  DRIVE_THROUGH_ON_TOWN_ROAD="The council doesn't allow a stop on this street.",
  BRIDGE_TOO_LOW_FOR_ROADVEH_DEPOT="The road depot needs three levels below the bridge.",
  BRIDGE_TOO_LOW_FOR_ROADSTOP="The road stop needs two levels below the elevated deck.",
  BRIDGE_TOO_LOW_FOR_ROAD_WAYPOINT="The waypoint needs two levels below the elevated deck.",
  MUST_DEMOLISH_BRIDGE_FIRST="There isn't enough clearance below the bridge for this stop.",
  ALREADY_BUILT="That terminal is already built in this direction.",
  ADJOINS_MULTIPLE_STATIONS="This selection touches more than one matching station. Hold E to build separately.",
  STATION_SPREAD="A station can span at most 12 tiles in either direction. Hold E to build separately.",
  LOCAL_AUTHORITY_REFUSES="The local council won't let your company build a station here.",
  INCOMPATIBLE_STATION_TILE="That station does not accept this kind of stop.",
  ACTIVE_DEPOT_ROUTE="Wait for vehicles currently arriving at or leaving this depot.",
  ACTIVE_STOP_ROUTE="Wait for the vehicle using this part of the stop.",
  STOP_IN_ORDERS="Remove this stop from vehicle orders before clearing its last tile.",
  NO_CLEAR_ROAD_STOP="Select an empty road stop that your company owns.",
  NOT_ENOUGH_CASH="Not enough cash.",
}
function M.stock_road_terminal_error(why)
  return terminal_errors[why] or ("Cannot build the selected road terminal: "..tostring(why))
end
function M.stock_road_terminal_plan(s,owner,id,req)
  if req.kind~="depot" and id and s.tiles[id] and not M.road_tree_authority().new_station(s,owner,id) then
    return nil,"LOCAL_AUTHORITY_REFUSES"
  end
  if not stock_road_terminals then
    load_road_rules()
    local path=debug and debug.getinfo(1,"S").source
    local base=path and path:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    stock_road_terminals=dofile(base.."road_terminal_world.lua")(M,terrain_rules,
      dofile(base.."openttd/road_stop_build.lua"),bridge_underlay,{
      ground=function(s) return default_oneway().ground_occupancy(s) end,
      deck=M.road_overhead_deck,
      facility=function(s,owner,edit)
        if edit.rotate_depot then
          for _,v in pairs(s.fleet) do
            for _,at in ipairs(v.route or {}) do if at==edit.id then return nil,"ACTIVE_DEPOT_ROUTE" end end
          end
        end
        if edit.tool=="road_station" then edit.station_site,edit.station_served=road_stop_site(s,edit.id) end
        return true
      end,
      connect=function(s,owner,id,dir,terminal,occupied)
        local t=s.tiles[id]
        local wanted=road_flags[opposite(dir)]
        local proposed,cost=road_piece_plan(s,owner,id,t,wanted,occupied)
        if not proposed or cost<=0 or not profiles_match(s,terminal.id,terminal,id,proposed,dir) then return end
        return proposed,cost
      end,
    })
  end
  return stock_road_terminals.quote(s,owner,id,req)
end
-- OpenTTD 16.0-RC1 Station::RecomputeCatchment: use the union of
-- the squares around the physical station tiles, never around its sign.
local road_stop_geometry=setmetatable({},{__mode="k"})
local function stop_geometry(st)
  local record=road_stop_geometry[st]
  if record and record.members==st.road_members and record.sign==st.tile and record.kind==st.stop_type then
    return record
  end
  local members=st.road_members or {[st.tile]=st.stop_type or "bus"}
  local ids,physical={},{}
  for id in pairs(members) do ids[#ids+1]=id end
  table.sort(ids)
  for i,id in ipairs(ids) do
    local x,z=M.xy(id)
    physical[i]={x=x-1,y=z-1,kind=members[id]}
  end
  record={members=st.road_members,sign=st.tile,kind=st.stop_type,ids=ids,physical=physical}
  road_stop_geometry[st]=record
  return record
end
function M.road_stop_tiles(st) return stop_geometry(st).physical end
function M.road_stop_has(st,kind)
  if not st or st.mode~="road" then return false end
  if st.road_stop_areas then return st.road_stop_areas[kind]~=nil end
  return (st.stop_type or "bus")==kind
end
function M.road_stop_tile_kind(st,id,t)
  if not st or st.mode~="road" then return nil end
  if st.road_members then return st.road_members[id] end
  return t and t.road_stop_type or st.stop_type or "bus"
end
function M.road_stop_anchor(st,kind)
  if not st.road_members then return st.tile end
  if st.road_members[st.tile]==kind then return st.tile end
  local rec=stop_geometry(st)
  for _,id in ipairs(rec.ids) do
    if st.road_members[id]==kind then return id end
  end
end
-- economy.cpp uses the current vehicle tile when moving and settling
-- cargo; the BaseStation sign is neither a loading nor delivery point.
function M.road_loading_tile(s,st,v)
  local f=v.road_stop_pose
  local id=f and f[4]
  local t=id and s.tiles[id]
  if t and (t.station==st.id or v.stock_tram and M.tram_stop_id(t)==st.id) then return id end
  return M.road_stop_anchor(st,v.cargo=="passenger" and "bus" or "truck") or st.tile
end
function M.road_stop_catchment(s,st,r)
  local rec=stop_geometry(st)
  r=s.stock_modified_catchment==false and 4 or r
  if rec.catchment and rec.radius==r and rec.w==M.W and rec.h==M.H then return rec.catchment end
  local cells={}
  for _,id in ipairs(rec.ids) do
    local x,z=M.xy(id)
    for v=math.max(1,z-r),math.min(M.H,z+r) do
      for u=math.max(1,x-r),math.min(M.W,x+r) do cells[M.id(u,v)]=true end
    end
  end
  rec.catchment,rec.radius,rec.w,rec.h=cells,r,M.W,M.H
  return cells
end
function M.road_stop_covers(s,st,x,z,r)
  if not st.road_members then
    local a,b=M.xy(st.tile)
    r=s.stock_modified_catchment==false and 4 or r
    return math.abs(a-x)<=r and math.abs(b-z)<=r
  end
  local id=M.id(x,z)
  return id and M.road_stop_catchment(s,st,r)[id]==true or false
end
function M.road_station_retirement()
  if not M.road_retirement_kernel then
    local path=debug and debug.getinfo(1,"S").source
    local base=path and path:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    M.road_retirement_kernel=dofile(base.."openttd/road_station_retirement.lua")(M)
  end
  return M.road_retirement_kernel
end
local road_stop_area,road_stop_members
function M.stock_road_stop_area_plan(s,owner,first,last,req)
  if req.kind~="bus" and req.kind~="truck" then return nil,"PARAMETERS" end
  local company=s.companies[owner]
  if not company then return nil,"PARAMETERS" end
  if not road_stop_area then
    local path=debug and debug.getinfo(1,"S").source
    local base=path and path:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    road_stop_area=dofile(base.."openttd/road_stop_area.lua")(dofile(base.."openttd/road_stop_build.lua"))
    road_stop_members=dofile(base.."road_stop_members.lua")(M)
    town_road_authority=town_road_authority or
      dofile(base.."town_road_authority.lua")(M,dofile(base.."openttd/road_town_permission.lua"))
  end
  local board={id=M.id,xy=M.xy}
  local area,ids=road_stop_area.footprint(board,first,last,req.dir,req.through,12)
  if not area then return nil,ids end
  local policy=s.stock_road_town_policy or {}
  if not town_road_authority.new_station(s,owner,area.tile) then return nil,"LOCAL_AUTHORITY_REFUSES" end
  local function compatible(st)
    -- Road bus and truck facilities share the station; other modes
    -- have their own construction registries.
    return st and st.mode=="road" and not st.tram_only and not s.tiles[st.tile].road_stop_pair
  end
  function board.station(id)
    local st=s.stations[id] or M.road_station_retirement().get(s,"station",id)
    if st and not st.tram_only then return st end
  end
  function board.surrounding(rect)
    local x,z=M.xy(rect.tile)
    local found,seen={},{}
    for v=z-1,z+rect.h do for u=x-1,x+rect.w do
      local id=M.id(u,v)
      local t=id and s.tiles[id]
      if t and t.station and not seen[t.station] and compatible(s.stations[t.station]) then
        seen[t.station]=true;found[#found+1]=t.station
      end
    end end
    return found
  end
  local ground=req.ground or default_oneway().ground_occupancy(s)
  local changes,parts,cost,over,z={},{},0,nil,nil
  for _,id in ipairs(ids) do
    local q,why=M.stock_road_terminal_plan(s,owner,id,{kind=req.kind,dir=req.dir,through=req.through,ground=ground,area=true})
    if not q then return nil,why end
    if q.existing and over and q.existing~=over then return nil,"ADJOINS_MULTIPLE_STATIONS" end
    over=over or q.existing
    local edit=q.changes[1]
    local ht=edit and edit.road_terminal_level or q.z
    if z and z~=ht then return nil,"FLAT_LAND_REQUIRED" end
    z=ht
    if edit then
      parts[#parts+1]={id=id,kind=req.kind}
      changes[#changes+1]=edit
    end
    cost=cost+q.cost
  end
  local join,why=road_stop_area.find_join(board,area,over,owner,req.join,req.adjacent,true)
  if why then return nil,why end
  if not join and not req.adjacent and not req.join then
    join=M.road_station_retirement().closest(s,"station",owner,area.tile,function(row) return not row.tram_only end)
  end
  if join and s.stations[join.id] and not compatible(join) then return nil,"INCOMPATIBLE_STATION_TILE" end
  local group=join and join.stock_station_id~=nil and M.stock_joined_station.resolve(
    s,join.stock_station_id,"road",join.id,join)
  local facility,u,v,last_u,last_v
  if group then facility,u,v,last_u,last_v=M.stock_joined_station.commercial_bounds(s,group,M.xy) end
  if facility and req.kind~="bus" then return nil,"AIRPORT_JOIN_UNPORTED_FACILITY" end
  local result=road_stop_members.preview(join,parts)
  if join and not s.stations[join.id] then
    -- A gray sign moves to facil_xy when its first facility reopens,
    -- not to the closest corner of the new multi-tile bounding box.
    result.sign=area.tile
  end
  if not result.spread or #changes==0 then return nil,"ALREADY_BUILT" end
  local spread=s.stock_station_spread or 12
  if result.spread.w>spread or result.spread.h>spread then return nil,"STATION_SPREAD" end
  if facility then
    local x,z=M.xy(result.spread.tile)
    if math.max(x+result.spread.w,last_u+1)-math.min(x,u)>spread or
        math.max(z+result.spread.h,last_v+1)-math.min(z,v)>spread then return nil,"STATION_SPREAD" end
  end
  if cost>company.cash then return nil,"NOT_ENOUGH_CASH" end
  local sid=join and join.id or s.next_station
  local excluded,fronts={},{}
  local occupied=M.road_piece_occupancy(s)
  for _,id in ipairs(ids) do excluded[id]=true end
  for _,edit in ipairs(changes) do
    edit.join_stop=sid
    cost=cost+stock_road_terminals.frontage(s,owner,edit,req,company.cash-cost,fronts,excluded,occupied)
  end
  for _,edit in ipairs(fronts) do changes[#changes+1]=edit end
  return {cost=cost,changes=changes,stop_members=result,join_stop=sid,picker_area=area}
end
-- Luanti's Auto tool chooses a stock orientation. It must still go
-- through the same RC1 station command, rather than the early one-tile
-- prototype. Infer geometry from the authoritative ground only.
function M.auto_road_terminal_plan(s,owner,id,request)
  local t=s.tiles[id]
  local kind=request.kind
  if not t or not s.companies[owner] or kind~="bus" and kind~="truck" and kind~="depot" then return nil,"PARAMETERS" end
  local ground=default_oneway().ground_occupancy(s)
  local function propose(dir,through)
    local params={kind=kind,dir=dir,through=through,adjacent=request.adjacent,join=request.join,ground=ground}
    if kind=="depot" then return M.stock_road_terminal_plan(s,owner,id,params) end
    return M.stock_road_stop_area_plan(s,owner,id,id,params)
  end
  if t.build=="road" and kind~="depot" then
    local bits=M.road_bits(s,id)
    local axis=road_axis(bits)
    if not axis then
      local _,count=new_pieces(bits,0)
      return nil,count==2 and "DRIVE_THROUGH_CORNER" or "DRIVE_THROUGH_JUNCTION"
    end
    return propose(axis==10 and 0 or 1,true)
  end
  if t.build=="road_station" or t.build=="road_depot" then return nil,"ALREADY_BUILT" end
  local prefs={}
  for d=1,4 do
    local near=adjacent(id,d)
    local other=near and s.tiles[near]
    local score=0
    if other and road_kind(other) and road_access(other,owner) then
      local bits=M.road_bits(s,near)
      if has_edge(bits,opposite(d)) then score=2
      elseif other.build=="road" and not other.level_crossing and bits~=0 then score=1 end
    end
    prefs[#prefs+1]={dir=4-d,score=score}
  end
  local facing=kind=="depot" and request.preferred_direction
  table.sort(prefs,function(a,b)
    if a.score~=b.score then return a.score>b.score end
    if (a.dir==facing)~=(b.dir==facing) then return a.dir==facing end
    return a.dir<b.dir
  end)
  local reason
  for _,choice in ipairs(prefs) do
    local q,why=propose(choice.dir,false)
    if q then return q end
    reason=reason or why
  end
  return nil,reason
end
function M.stock_road_stop_remove_plan(s,owner,first,last)
  local company=s.companies[owner]
  if not company then return nil,"PARAMETERS" end
  if not road_stop_members then
    local path=debug and debug.getinfo(1,"S").source
    local base=path and path:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    road_stop_members=dofile(base.."road_stop_members.lua")(M)
  end
  local occupied=default_oneway().ground_occupancy(s)
  local x,z=M.xy(first)
  local u,v=M.xy(last)
  local groups,changes={},{}
  for b=math.min(z,v),math.max(z,v) do for a=math.min(x,u),math.max(x,u) do
    local id=M.id(a,b)
    local t=s.tiles[id]
    local st=t.station and s.stations[t.station]
    if st and st.owner==owner and t.build=="road_station" and not t.road_stop_pair and not occupied[id] and
        not (t.tram and t.tram.shared_station) then
      local parts=groups[st.id] or {}
      groups[st.id]=parts;parts[#parts+1]={id=id}
      changes[#changes+1]={id=id,tool="remove_stop_part",build=t.stop_axis and "road" or "land",join_stop=st.id,
        road_bits=t.stop_axis or 0}
    end
  end end
  if #changes==0 then return nil,"NO_CLEAR_ROAD_STOP" end
  local results={}
  local selected={}
  for _,row in ipairs(changes) do selected[row.id]=true end
  for id,parts in pairs(groups) do
    local st=s.stations[id]
    local result=road_stop_members.preview(st,parts)
    results[id]=result
    for _,v in pairs(s.fleet) do
      local role=v.cargo=="passenger" and "bus" or "truck"
      local was=M.road_stop_has(st,role)
      local lacks=not result.road_stop_areas[role]
      local occupied=v.road_stop_pose and selected[v.road_stop_pose[4]]
      if v.station==id and v.load_state and (occupied or lacks) or v.dest==id and v.route and selected[v.route[#v.route]] then
        return nil,"ACTIVE_STOP_ROUTE"
      end
      if not result.spread or was and lacks then
        for _,order in ipairs(v.orders or {}) do
          if order.station==id then return nil,"STOP_IN_ORDERS" end
        end
      end
    end
  end
  local cost=#changes*50
  if cost>company.cash then return nil,"NOT_ENOUGH_CASH" end
  return {changes=changes,cost=cost,remove_stop_parts=results}
end
local function refresh_road_station_sites(s,st)
  local known,served={},{}
  local primary=road_stop_site(s,st.tile)
  for id,kind in pairs(st.road_members) do
    s.tiles[id].road_stop_type=kind
    local _,sites=road_stop_site(s,id)
    for _,site in ipairs(sites or {}) do
      if not known[site] then known[site]=true;served[#served+1]=site end
    end
  end
  table.sort(served);st.served,st.site=served,primary
end
function M.retire_road_station(s,id)
  local st=s.stations[id]
  if st and st.mode=="road" then
    local Joined=M.stock_joined_station
    local group=st.stock_station_id~=nil and Joined.resolve(s,st.stock_station_id,"road",id,st)
    local facility
    if group then
      Joined.detach(s,group.id,"road",id,st)
      facility=Joined.clamp_sign(s,M,group)
    end
    if facility then
      -- UpdateStationSignCoord clamps the original sign into the new
      -- spread, not to the first tile unconditionally.
      group.facilities=group.facilities-4
      local commercial=s.stock_ship_commercial
      local ledger=commercial and group.service_station_id and commercial.service.stations[group.service_station_id]
      if ledger then
        ledger.joined_road=nil
      end
    else
      st.road_members,st.road_stop_areas,st.spread={},nil,nil
      st.bus_tile,st.truck_tile=nil,nil
      M.road_station_retirement().retire(s,"station",st)
    end
  end
  s.stations[id]=nil
end
function M.apply_road_stop_remove(s,owner,plan)
  local ids={}
  for _,row in ipairs(plan.changes) do
    local t=s.tiles[row.id]
    if row.road_bits~=0 then
      t.build,t.road_bits="road",row.road_bits
      if t.road_town then t.owner=nil end
    else
      t.build,t.owner,t.road_bits=nil,nil,nil
      t.roadside,t.stock_roadside_town=nil,nil
    end
    t.station,t.stop_axis,t.road_terminal_level,t.road_stop_type=nil,nil,nil,nil
    ids[#ids+1]=row.id
  end
  for id,result in pairs(plan.remove_stop_parts) do
    if not result.spread then
      M.retire_road_station(s,id)
    else
      local st=s.stations[id]
      local joined=M.stock_joined_station
      local group=st.stock_station_id~=nil and joined.resolve(s,st.stock_station_id,"road",id,st)
      local original_sign=group and group.tile
      road_stop_members.structural_apply(st,result)
      if original_sign then joined.clamp_sign(s,M,group) end
      refresh_road_station_sites(s,st)
    end
  end
  debit(s.companies[owner],plan.cost)
  s.topology=s.topology+1
  return true,("Removed %d road stop tile%s for $%d."):format(#ids,#ids==1 and "" or "s",plan.cost),ids
end
local road_waypoint_world
function M.road_waypoint_plan(s,owner,req)
  if not road_waypoint_world then
    load_road_rules()
    local path=debug and debug.getinfo(1,"S").source
    local base=path and path:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    local S=dofile(base.."openttd/road_stop_build.lua")
    road_waypoint_world=dofile(base.."road_waypoint_world.lua")(M,terrain_rules,dofile(base.."openttd/road_waypoint_build.lua")(S),bridge_underlay,{
      ground=function(state) return default_oneway().ground_occupancy(state) end,
      bridge=function(state,id)
        local deck,above=M.road_overhead_deck(state,id)
        return above,deck
      end,
    })
  end
  return road_waypoint_world.quote(s,owner,req)
end
function M.apply_road_waypoint(s,owner,plan)
  local dirty=road_waypoint_world.apply(s,owner,plan)
  debit(s.companies[owner],plan.cost)
  s.topology=s.topology+1
  return true,plan.id and ("Road waypoint #%d placed for $%d."):format(plan.id,plan.cost) or
    ("Road waypoint markings removed for $%d."):format(plan.cost),dirty
end
local function road_terminal_plan(s,owner,tool,ids)
  local pair=tool=="road_bay_pair"
  if pair then
    if not (s.road_bay_build and M.road_stock_service_active(s)) then
      return nil,"Enable the stock road bay workbench and road loading first."
    end
    tool="road_station"
  end
  local result,total,proposed={},0,{order={}}
  local seen={}
  local occupied=M.road_piece_occupancy(s)
  for _,id in ipairs(ids) do
    if not seen[id] then
      seen[id]=true
      local t=s.tiles[id]
      if not t then return nil,"Outside the region." end
      if t.stock_landmark then return nil,"This landmark is protected." end
      if t.site or t.stock_industry then return nil,"Cannot build on a town centre or industry." end
      if t.airfield then return nil,"Use the airfield tool on that airfield." end
      if t.ship then return nil,"That tile is part of a ship facility." end
      if t.tram then return nil,"Use the tram tool on that tramway." end
      if t.owner and t.owner~=owner then return nil,"Another company owns that tile." end
      if t.house then return nil,"Bulldoze that building first." end
      local mask=ground_shape(s,id)
      if mask~=0 or wet(s,id) then return nil,"Terminals need flat, dry ground." end
      if t.airfield then return nil,"Use the airfield tool on that airfield." end
      if t.ship then return nil,"That tile is part of a ship facility." end
      if t.tram then return nil,"Use the tram tool on that tramway." end
      if t.build and (tool~="road_station" or t.build~="road") then return nil,"Clear the existing structure first." end
      local item={id=id,tool=tool,build=tool,owner=owner,road_bits=0,road_town=t.road_town,h=t.h}
      if tool=="road_station" then
        local associated,served,stock=road_stop_site(s,id)
        if not stock and not associated then return nil,"Build within five tiles of a town or industry." end
        item.station_site,item.station_served=associated,served
        if t.build then
          item.road_bits=bits_for(s,id,t)
          -- OpenTTD 14.1 station_cmd.cpp CheckFlatLandRoadStop rejects
          -- transverse road bits, with distinct corner/junction errors.
          -- Bayline automatically chooses the axis already on the street.
          local axis=road_axis(item.road_bits)
          if item.road_bits~=0 and not axis then
            local _,count=new_pieces(item.road_bits,0)
            return nil,count==2 and "A through stop cannot go on a corner." or
              "A through stop cannot go on a junction."
          end
          if t.road_town or item.road_bits==axis then
            item.stop_axis=axis
            -- On a real through stop, OpenTTD completes a compatible half
            -- of the axis; town ownership still covers the entire road.
            if axis and item.road_bits~=axis then
              item.road_bits=axis
              total=total+math.ceil(M.tools.road.price/2)
            end
          end
          -- Preserve Bayline's private one-half end-stop separately. It
          -- is not the upstream terminal-bay model and has no through axis.
        else
          for d=1,4 do
            local j=adjacent(id,d)
            local near=proposed[j] or s.tiles[j]
            if j and road_kind(near) and road_access(near,owner) and
                has_edge(bits_for(s,j,near),opposite(d)) and profiles_match(s,id,item,j,near,d) then
              item.road_bits=add_edge(item.road_bits,d)
            end
          end
          if item.road_bits~=0 and not road_axis(item.road_bits) then
            return nil,"Place a stop beside a single road axis."
          end
          if item.road_bits==5 or item.road_bits==10 then item.stop_axis=item.road_bits end
        end
      else
        local best,best_cost
        for d=1,4 do
          local j=adjacent(id,d)
          local near=proposed[j] or s.tiles[j]
          if j and near and (near.build=="road" or near.build=="road_station") and road_access(near,owner) then
            local p,cost=road_piece_plan(s,owner,j,near,road_flags[opposite(d)],occupied)
            if p and profiles_match(s,id,item,j,p,d) and (not best_cost or cost<best_cost) then
              item.depot_dir=d;item.road_bits=road_flags[d]
              best,best_cost=p,cost
            end
          end
        end
        if not best then return nil,"The depot needs an adjacent road at the same level." end
        if best_cost>0 then
          -- Two adjacent depot purchases tapping the same road need only
          -- write its final union; the planner has accumulated each cost.
          if proposed[best.id] then
            for i,l in ipairs(result) do if l.id==best.id then result[i]=best;break end end
          else
            result[#result+1]=best
            proposed.order[#proposed.order+1]=best.id
          end
          proposed[best.id]=best
          total=total+best_cost
        end
      end
      if pair then
        local half=item.road_bits
        if item.stop_axis or t.road_town or not (half==1 or half==2 or half==4 or half==8) then
          return nil,"A two-bay terminus needs exactly one road approach, on flat ground."
        end
        for _,v in pairs(s.fleet) do
          for _,route_tile in ipairs(v.route or {}) do
            if route_tile==id then return nil,"Wait for the active road service to leave this approach." end
          end
        end
        item.road_stop_pair=true
      end
      total=total+M.tools[tool].price
      result[#result+1]=item
      proposed[id]=item;proposed.order[#proposed.order+1]=id
    end
  end
  local error_message=linking_errors(s,proposed)
  if error_message then return nil,error_message end
  if total>M.company(s,owner).cash then return nil,"Not enough cash." end
  return result,total
end
function M.plan(s,owner,tool,ids,quote_clear_only)
  for _,id in ipairs(ids or {}) do
    if s.tiles[id] and s.tiles[id].road_waypoint_id and tool~="road" then return nil,"Remove the road waypoint while keeping its pavement." end
    if M.crossing_protected(s,id) and tool~="road" then
      return nil,"That tile is a protected level crossing."
    end
  end
  if tool=="clear" then
    for _,id in ipairs(ids) do
      local t=s.tiles[id]
      local st=t and s.stations[t.station]
      local first=st and st.road_members and next(st.road_members)
      if first and next(st.road_members,first) then
        return nil,"This is a joined road stop; remove its parts using the station removal tool."
      end
    end
  end
  local w=M.tools[tool]
  if not w or not w.price then return nil,"Select a construction tool." end
  for _,id in ipairs(ids) do
    if M.rail_span_protected(s,id) and not (tool=="road" and M.crossing_protected(s,id)) then
      return nil,"Rail bridge or tunnel protected. Use Rail Engineering to remove it."
    end
  end
  if tool=="road_bay_pair" then return road_terminal_plan(s,owner,tool,ids) end
  if s.corner_grid or s.has_town_roads then
    if tool=="road" then return road_drag_plan(s,owner,ids) end
    if tool=="road_station" or tool=="road_depot" then return road_terminal_plan(s,owner,tool,ids) end
  end
  if s.corner_grid then
    if tool=="grade" then return nil,"Corner terraforming is not connected to this tool yet." end
    if tool=="road_bridge" or tool=="road_tunnel" then return nil,"This structure is not available in the corner terrain preview." end
  end
  local result,seen,total={},{},0
  for _,id in ipairs(ids) do
    local t=s.tiles[id]
    if not t or t.stock_void then return nil,"Outside the playable map." end
    if not seen[id] then
      seen[id]=true
      local house_parts
      if tool=="clear" and t.source_house and t.source_house.asset_root then
        local growth=town_growth_mount[s]
        house_parts=growth and growth.world.footprint(s,t.source_house)
        if not house_parts then return nil,"This building footprint is incomplete." end
        for _,part in ipairs(house_parts) do seen[part.id]=true end
      end
      local water=tool=="clear" and s.corner_grid and not t.wood and
        (t.terrain=="water" or t.build=="canal" or t.stock_canal)
      if M.is_owned_land(t) and tool=="clear" then
        if t.owner~=owner then return nil,"Another company owns that tile." end
        result[#result+1]={id=id,tool=tool,clear_owned_land=true}
        total=total-M.owned_land_resale()
      elseif water then
        local price,why=quote_water_clear(s,owner,id)
        if not price then return nil,water_clear_errors[why] or why end
        result[#result+1]={id=id,tool=tool,water_clear=true}
        total=total+price
      else -- existing dry-land and special-structure rules
      if t.stock_landmark then return nil,"This landmark is protected." end
      if t.site or t.stock_industry then return nil,"Cannot build on a town centre or industry." end
      if t.owner and t.owner~=owner then return nil,"Another company owns that tile." end
      if tool=="clear" and t.stock_canal then return nil,"Use the Harbor bulldozer for stock canals." end
      if tool=="clear" and t.road_tunnel_id then
        return nil,"Use Bulldozer on a tunnel portal to review both portals."
      end
      if tool=="clear" and t.road_bridge_id then
        return nil,"Use Bulldozer on a bridgehead to review the whole span."
      end
      if tool=="clear" and t.rail_tracks and s.stock_rail_dispatch then
        local d=s.stock_rail_dispatch
        if #d.runs>0 or d.signals.records[id] then
          return nil,"The rail dispatch pilot protects that track or path signal."
        end
      end
      if tool=="clear" and (t.rail_station_id or t.rail_depot_dir or t.rail_waypoint_id) then
        return nil,"Click the facility with Bulldozer to review its track layers."
      end
      if tool=="clear" and road_sign(t)~=0 then
        local w=oneway_world(s)
        if w and w.occupied(s,id) then return nil,"Wait for the vehicle to clear that one-way road." end
      end
      if tool=="clear" and t.road_town and not t.station then
        return nil,"The town owns this public road."
      end
      if tool=="clear" and t.road_stop_pair then
        local occupancy=M.road_bay_status(s,id)
        if occupancy and (occupancy.first or occupancy.second or occupancy.entrance) then
          return nil,"Wait for both bays and the shared entrance to clear."
        end
      end
      local existing=t.build
      local target=tool
      local skip=false
      local extra=t.house and 240 or 0
      if t.house and tool=="clear" then
        local town=M.nearest_town(s,id)
        if town and ((M.company(s,owner).rating[town.id] or 48)<28) then
          return nil,town.name.." refuses demolition. Deliver cargo there to rebuild your reputation."
        end
      end
      if existing and tool=="clear" then
        for _,v in pairs(s.fleet) do
          if v.route and M.vehicles[v.engine].mode==M.tools[existing].mode then
            if t.road_town then
              if M.position(s,v)==id then return nil,"Wait for the vehicle to clear that tile." end
            else
              for _,tid in ipairs(v.route) do if tid==id then return nil,"Wait for the vehicle to clear that route." end end
            end
          end
          if v.depot==id then return nil,"Sell or dispatch the vehicles parked in this depot." end
          if t.station and v.station==t.station then return nil,"A vehicle is parked at that terminal." end
        end
      end
      if t.house and tool~="clear" then return nil,"Bulldoze that building first." end
      if tool=="road_depot" then
        if t.h>0 or wet(s,id) or existing then return nil,"Build the depot on empty, flat land beside a road." end
        local access=false
        for d=1,4 do
          local j=adjacent(id,d)
          if j and s.tiles[j].build~="road_depot" and mode_on(s,j,"road",owner) then access=true end
        end
        if not access then return nil,"The depot needs an adjacent road you own." end
      elseif station_tools[tool] then
        if t.h>0 or wet(s,id) then return nil,"Terminals need flat, dry ground." end
        if existing and existing~=w.mode then return nil,"Clear the existing structure first." end
        if not site_radius(s,id) then return nil,"Build within five tiles of a town or industry." end
        if tool=="dock" then
          local shoreline=false
          for k=1,4 do local j=adjacent(id,k);if j and wet(s,j) then shoreline=true end end
          if not shoreline then return nil,"Docks need a neighboring water tile." end
        end
      elseif tool=="signal" then
        if not mode_on(s,id,"rail",owner) or t.station then return nil,"Signals go on non-station track." end
        skip=t.signal
      elseif tool=="grade" then
        if existing or wet(s,id) or t.h==0 then return nil,"Only unbuilt hills can be graded." end
      elseif tool=="clear" then
        if not existing and not t.house and s.stock_generated_profile then
          local clearing=M.road_site_clear_cost(t,s.stock_farm_fields and s.stock_farm_fields[id])
          if clearing==0 then skip=true end
          -- The stock natural-ground clear price replaces the fallback
          -- flat fee used by the small authored tool set.
          extra=clearing-w.price
        elseif not existing and not t.house and not t.wood then
          skip=true
        end
        if t.station then
          for _,v in pairs(s.fleet) do
            for _,order in ipairs(v.orders) do if order.station==t.station then return nil,"Remove the station from vehicle orders first." end end
          end
        end
      elseif tool=="canal" then
        if wet(s,id) and not existing then skip=true
        elseif t.h>0 or (existing and existing~=tool) then return nil,"Canals need clear, level ground."
        elseif existing==tool then skip=true end
      else
        if existing and M.tools[existing].mode==w.mode and not t.station then skip=true
        elseif existing and M.tools[existing].mode==w.mode and t.station then skip=true
        elseif existing then return nil,"Different infrastructure already occupies that tile."
        elseif wet(s,id) then
          if tool~=w.mode.."_bridge" or existing=="canal" then return nil,"Use a bridge over open water." end
        elseif t.h>0 then
          if tool~=w.mode.."_tunnel" then return nil,"Use a tunnel through the hill, or grade it." end
        else target=w.mode end
      end
      if not skip then
        total=total+M.tools[target].price+extra
        result[#result+1]={id=id,tool=target,house_parts=house_parts}
      end
      end
    end
  end
  if not (quote_clear_only and tool=="clear") and total>M.company(s,owner).cash then return nil,"Not enough cash." end
  return result,total
end
function M.line(a,b,zfirst)
  local x,z=M.xy(a);local u,v=M.xy(b)
  local list={a}
  local function go_x() while x~=u do x=x+(u>x and 1 or -1);list[#list+1]=M.id(x,z) end end
  local function go_z() while z~=v do z=z+(v>z and 1 or -1);list[#list+1]=M.id(x,z) end end
  if zfirst then go_z();go_x() else go_x();go_z() end
  return list
end
-- LuanTTD convenience: the stock road command is one-axis only. Build a
-- single orthogonal corner from ordinary, connected road half-pieces.
-- Unlike a straight drag, an obstructed bend has no useful partial result.
function M.autoroad_bend_plan(s,owner,start,last)
  if not s.corner_grid or not s.tiles[start] or not s.tiles[last] then return nil,"Outside the region." end
  local x,z=M.xy(start)
  local u,v=M.xy(last)
  if x==u or z==v then return nil,"Aim across both axes to make a bend." end
  local path=M.line(start,last,math.abs(v-z)>math.abs(u-x))
  for _,id in ipairs(path) do
    if s.tiles[id].stock_void then return nil,"Outside the playable map.",path end
  end
  local changes,cost=M.plan(s,owner,"road",path)
  if not changes then return nil,cost,path end
  return {changes=changes,cost=cost,path=path},nil,path
end
local function apply_build(s,owner,changes,cost)
  if #changes==0 then return true,"Nothing to change.",{} end
  local c=M.company(s,owner);debit(c,cost)
  local changed,crossing_changed,tree_rating_changed={}
  for _,item in ipairs(changes) do
    local id,k=item.id,item.tool
    local tile=s.tiles[id]
    local had_sign=road_sign(tile)~=0
    if item.clear_owned_land then tile.stock_object,tile.owner=nil,nil end
    if item.road_tree_town and M.road_tree_authority().clear_road_trees(c,item.road_tree_town) then tree_rating_changed=true end
    if item.clear_road_site then
      tile.stock_clear_ground,tile.stock_clear_density,tile.stock_clear_visits=nil,nil,nil
      if s.stock_farm_fields then s.stock_farm_fields[id]=nil end
    end
    if item.clear_road_coast then coastal_world.clear_apply(s,id) end
    if item.crossing_quote then
      M.apply_crossing_construction(s,item.crossing_quote)
      crossing_changed=true
    elseif item.joined_tram_station then
      local st=assert(M.tram_stop_station(s,id))
      assert(st.id==item.joined_tram_station and st.tram_only)
      M.activate_tram_road_stop(s,id,owner)
    elseif item.water_clear then
      coastal_world.clear_apply(s,id,c)
      M.mark_clear_land(s,id)
    elseif k=="clear" then
      if tile.road_stop_pair then
        local bs=s.stock_road_bays and s.stock_road_bays.stops[id]
        if bs then
          assert(bs.status==3,"Cleared occupied two-bay road stop")
          s.stock_road_bays.stops[id]=nil
        end
        tile.road_stop_pair=nil
      end
      if tile.station then M.retire_road_station(s,tile.station) end
      if tile.house then
        local growth=town_growth_mount[s]
        if item.house_parts then
          for _,part in ipairs(item.house_parts) do
            growth.world.remove(s,part.record)
            local parcel=s.tiles[part.id]
            parcel.house,parcel.source_house=nil,nil
            M.mark_clear_land(s,part.id)
            if part.id~=id then changed[#changed+1]=part.id end
          end
        elseif growth then growth.world.remove(s,tile.source_house) end
        local town=M.nearest_town(s,id)
        if town then c.rating[town.id]=math.max(10,(c.rating[town.id] or 48)-10) end
      end
      tile.road_terminal_level=nil
      if tile.road_town or item.keep_road then
        -- Remove the stop without erasing the selected underlying road.
        tile.build="road";tile.station=nil;tile.owner=not tile.road_town and owner or nil;tile.stop_axis=nil
      else
        if tile.wood and tile.coastal_water and s.corner_grid then
          load_road_rules()
          coastal_world.clear_apply(s,id)
        end
        if type(tile.wood)=="table" and tile.terrain~="water" then tile.stock_clear_ground,tile.stock_clear_density,tile.stock_clear_visits=nil,0,nil end
        M.mark_clear_land(s,id)
        tile.build=nil;tile.rail_tracks=nil;tile.rail_type=nil;tile.station=nil;tile.signal=nil;tile.closed=nil;tile.owner=nil;tile.depot_dir=nil;tile.road_bits=nil;tile.stop_axis=nil;tile.house=nil;tile.source_house=nil;tile.wood=nil
        tile.roadside,tile.stock_roadside_town=nil,nil
      end
    elseif k=="grade" then tile.h=tile.h-1;tile.terrain=tile.h==0 and "grass" or "hill"
    elseif k=="signal" then tile.signal=true
    elseif item.rotate_depot then
      tile.depot_dir,tile.road_bits,tile.road_terminal_level=item.depot_dir,item.road_bits,item.road_terminal_level
    elseif item.road_bits~=nil and tile.build==k then
      -- Lay additional halves without recreating terminal entities.
      tile.road_bits=item.road_bits
    else
      if k=="road" and tile.build~="road" and not (tile.tram and tile.tram.kind=="road") then
        tile.roadside,tile.stock_roadside_town=nil,nil
      end
      tile.build=k; tile.owner=owner; tile.wood=nil
      tile.road_terminal_level=item.road_terminal_level
      tile.road_bits=item.road_bits;tile.road_town=item.road_town;tile.stop_axis=item.stop_axis
      tile.road_stop_pair=item.road_stop_pair
      if k=="road_depot" then
        tile.depot_dir=item.depot_dir
        for d=1,(tile.depot_dir and 0 or 4) do
          local j=adjacent(id,d)
          if j and s.tiles[j].build~="road_depot" and mode_on(s,j,"road",owner) then tile.depot_dir=d;break end
        end
      end
      if station_tools[k] then
        local sid=item.join_stop or s.next_station
        local best,served=item.station_site,item.station_served
        if not served then best,served=site_radius(s,id) end
        local site=s.sites[best]
        local label=tile.road_stop_pair and "Bus terminus" or M.tools[k].name
        if not s.stations[sid] then
          local reused,phase
          if item.join_stop then reused,phase=M.road_station_retirement().take(s,"station",sid) end
          if reused then
            reused.passenger_rating_phase=phase
            s.stations[sid]=reused
          else
            s.next_station=s.next_station+1
            s.stations[sid]={id=sid,tile=id,mode=M.tools[k].mode,owner=owner,
              name=(site and site.name.." " or "")..label.." #"..sid,
              town=site and site.kind=="town" and best or nil,site=best,served=served,stock={},last_service={},
              stock_station_id=M.stock_station_slot(s)}
          end
          -- Station::AddFacility initializes the random bits when adding
          -- the first facility, including reopening a retired station.
          if s.stock_engine_startup_seed~=nil and M.tools[k].mode=="road" then
            s.stations[sid].stock_random_bits=M.stock_random_u32(s)%65536
          end
        end
        tile.station=sid
        tile.road_stop_type=item.stop_type
        if item.stop_type=="truck" then
          local stop=s.stations[sid]
          stop.stop_type,stop.freight_art="truck",true
          stop.coal_art=M.road_coal_active(s) or nil
        end
        if tile.road_stop_pair then M.install_road_bay(s,id) end
      end
    end
    if tile.build~="road" then
      tile.road_disallowed,tile.disallowed=nil,nil
      if had_sign then one_way_edit(s,id,k=="clear") end
    elseif s.road_oneway_removed and s.road_oneway_removed[id]==true then
      one_way_edit(s,id,false)
    end
    changed[#changed+1]=id
  end
  s.topology=s.topology+1
  if crossing_changed then M.refresh_crossing_construction(s) end
  local note=("$%d spent on %d tile%s%s."):format(cost,#changes,#changes==1 and "" or "s",
    crossing_changed and ", including level crossing work" or "")
  if tree_rating_changed then note=note.." Clearing trees lowered your local authority rating." end
  return true,note,changed
end
local function build(s,owner,tool,ids,funded_clear)
  local changes,cost=M.plan(s,owner,tool,ids,funded_clear)
  if not changes then return false,cost end
  return apply_build(s,owner,changes,cost)
end
function M.build(s,owner,tool,ids) return build(s,owner,tool,ids) end
function M.remove_through_road_stop(s,owner,id,preview)
  local t=s.tiles[id]
  if not t or t.owner~=owner or t.build~="road_station" or not t.stop_axis or t.road_stop_pair then
    return false,"Choose an owned drive-through road stop."
  end
  local changes,cost=M.plan(s,owner,"clear",{id})
  if not changes then return false,cost end
  assert(#changes==1 and changes[1].id==id)
  if preview then return true,cost end
  changes[1].keep_road=true
  return apply_build(s,owner,changes,cost)
end
-- Only the owning VM calls this with a plan it just validated. No
-- mailbox or stale preview can provide the terrain edit itself.
function M.apply_road_construction(s,owner,plan)
  local ok,why,dirty=apply_build(s,owner,plan.changes,plan.cost)
  if ok and plan.stop_members then
    local st=assert(s.stations[plan.join_stop])
    road_stop_members.structural_apply(st,plan.stop_members)
    refresh_road_station_sites(s,st)
  end
  if ok and plan.stop_reason then why=why.." Stopped: "..plan.stop_reason end
  return ok,why,dirty
end
function M.autoroad_bend_build(s,owner,start,last)
  local q,why=M.autoroad_bend_plan(s,owner,start,last)
  if not q then return false,why end
  return apply_build(s,owner,q.changes,q.cost)
end
function M.autoroad_build(s,owner,start,last,axis,start_half,end_half)
  local q,why=M.autoroad_plan(s,owner,start,last,axis,start_half,end_half)
  if not q then return false,why end
  local ok,note,ids=apply_build(s,owner,q.changes,q.cost)
  return ok,note,ids,q
end

-- Area commands share the host's exact supported per-tile quote/apply
-- adapters. Whole transport spans, footprints and persistent reservations
-- keep their separate single-click dismantle commands; don't erase a host
-- record below or on top of another transport layer via a drag.
function M.clear_area(s,owner,first,last,diagonal,execute)
  if not s.corner_grid then return nil,"Area demolition needs shared-corner terrain." end
  load_road_rules()
  local company=s.companies[owner]
  local cash=company and company.cash or 100000
  local quota=clear_area_rules.replenish(company and company.clear_limit,0)
  local ids, dirty={},{}
  local ctx,quoted,covered={},{},{}
  function ctx.quote(id)
    if covered[id] then return nil,"Building already included in this area." end
    local t=s.tiles[id]
    if not t or t.stock_void then return nil,"Outside the playable map." end
    if t.rail_span_id or t.road_bridge_id or t.road_tunnel_id or t.ship or t.airfield or t.tram or
        t.rail_station_id or t.rail_waypoint_id or t.rail_depot_dir~=nil or
        (first~=last and (t.station or t.build=="road_depot")) or
        s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id] or
        s.tunnel_below and s.tunnel_below[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
        s.rail_tunnel_below and s.rail_tunnel_below[id] then
      return nil,"A layered transport structure occupies this tile. Click it separately with Bulldozer."
    end
    local edits,cost=M.plan(s,owner,"clear",{id},true)
    if not edits then return nil,cost end
    quoted[id]=edits[1] and edits[1].house_parts
    return cost
  end
  function ctx.accepted(id)
    ids[#ids+1]=id
    for _,part in ipairs(quoted[id] or {}) do covered[part.id]=true end
  end
  if execute then
    company=M.company(s,owner)
    function ctx.apply(id)
      local ok,note,touched=build(s,owner,"clear",{id},true)
      -- The authority was quoted with live state immediately before this
      -- call. Single-threaded execution must not introduce a new denial.
      assert(ok,note)
      for _,tile in ipairs(touched) do dirty[#dirty+1]=tile end
    end
  end
  local q,why,attempt=clear_area_rules.run(M.W,M.H,first,last,diagonal,ctx,
      {execute=true,limit=quota,money=cash})
  if not q then return nil,why,attempt end
  q.ids,q.dirty=ids,dirty
  if execute and q.quota~=quota then company.clear_limit=q.quota end
  return q
end
local source_speed
local road_replan
local road_visual=setmetatable({},{__mode="k"})
function M.road_motion_timeline(s,id)
  return road_visual[s] and road_visual[s][id]
end
function M.road_hidden_depot(v)
  local c=v.road_speed_state
  return c and (c.depot_wait or c.transit_hidden) and true or false
end
function M.road_motion_frame(s,v)
  local c=v.road_speed_state
  if c and v.road_motion_frames then
    if M.road_hidden_depot(v) then return end
    return c.lane_pose or v.road_motion_frames[c.index]
  end
  return v.road_stop_pose
end
local shared_tram_clock=setmetatable({},{__mode="k"})
function M.mount_shared_road_tram(s,companion) shared_tram_clock[s]=companion end
function M.shared_road_tram_active(s)
  return shared_tram_clock[s]~=nil and M.road_stock_service_active(s)
end
function M.stock_road_frame_z(state,frame,surface_cache)
  load_road_rules()
  local id=frame[4]
  if frame[14] then return state.stock_road_tunnels[frame[14]].base*8 end
  local span=frame[10] and state.stock_road_bridges[frame[10]]
  if span and (frame[12] or span.middle_by_tile[id]) then return span.deck*8 end
  local cached=surface_cache and surface_cache[id]
  if type(cached)=="number" then return cached end
  if cached then return cached[2]+slope_rules.pixel(frame[1]%16,frame[2]%16,cached[1]) end
  local tile=state.tiles[id]
  local shape,base=road_shape(state,id,tile)
  local z=(base or tile.h)*8
  if not shape or shape==0 then
    if surface_cache then surface_cache[id]=z end
    return z
  end
  if surface_cache then surface_cache[id]={shape,z} end
  return z+slope_rules.pixel(frame[1]%16,frame[2]%16,shape)
end
local function road_clock()
  if not source_speed then
    load_road_rules()
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    local Speed=dofile(base.."openttd/road_speed.lua")
    local Proximity=dofile(base.."openttd/road_proximity.lua")
    local Follow=dofile(base.."openttd/yapf_road_follow.lua")
    local Board=dofile(base.."road_yapf_board.lua")
    local Motion=dofile(base.."openttd/road_motion.lua")(dofile(base.."openttd/road_motion_data.lua"))
    local Occupancy=dofile(base.."openttd/road_stop_occupancy.lua")(Motion)
    local Bay=dofile(base.."road_bay_runtime.lua")(Occupancy)
    local presentation=dofile(base.."road_motion_presentation.lua")(dofile(base.."road_lanes.lua"))
    local Junction=dofile(base.."road_junction_guard.lua")(M,presentation)
    source_speed=dofile(base.."road_speed_runtime.lua")(Speed,Proximity,M.stock_road_frame_z,function(state,id)
      local t=id and state.tiles[id]
      if not t or t.build~="road_station" then return false end
      local axis=t.stop_axis or M.road_bits(state,id)
      return axis~=5 and axis~=10
    end,function(state,id) return state.tiles[id].build=="road_depot" end,
      function(state) return road_traffic_board(state,Board(M,state,Follow)) end,crossing_road_step,
      one_way_pose,function(...) return road_replan(...) end,Bay,Junction,M.xy)
  end
  return source_speed
end
function M.preserve_road_junctions_after_tide(s,previous)
  if source_speed then source_speed.preserve_after_tide(s,previous) end
end
function M.install_road_bay(s,id) road_clock().bay.install(s,id) end
function M.road_bay_status(s,id) return s.stock_road_bays and road_clock().bay.report(s,id) end
local function advance_road(s,moving)
  local advance,samples=road_clock().day(s,moving)
  road_visual[s]=samples
  return advance
end
local source_route,source_routing
local function road_routing()
  if not source_routing then
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    local follow=dofile(base.."openttd/yapf_road_follow.lua")
    local cost=dofile(base.."openttd/yapf_road_cost.lua")(follow)
    local search=dofile(base.."openttd/yapf_road_search.lua")(follow,cost)
    local board=dofile(base.."road_yapf_board.lua")
    local motion=dofile(base.."openttd/road_motion.lua")(dofile(base.."openttd/road_motion_data.lua"))
    local motion_leg=dofile(base.."road_motion_leg.lua")
    local function framed_board(Sim,state,F,occupancy)
      return road_traffic_board(state,board(Sim,state,F,occupancy))
    end
    source_route=dofile(base.."road_yapf_route.lua")(M,follow,cost,search,framed_board,motion,motion_leg)
    source_routing={follow=follow,cost=cost,search=search,board=board,motion=motion,motion_leg=motion_leg,
      occupancy=dofile(base.."road_occupancy_view.lua")}
  end
  return source_routing
end
local function road_departure(s,a,b,owner,vehicle,waypoints)
  local r=road_routing()
  return source_route.route(s,a,b,owner,vehicle,r.occupancy(M,s),waypoints)
end
road_replan=function(s,v,state,frames,current,vehicle_limit)
  local revision,works=s.road_oneway_revision,s.roadworks_revision
  if (not revision and not works) or (state.oneway_checked_rev==revision and state.roadworks_checked_rev==works) then return end
  local works_changed=state.roadworks_checked_rev~=works
  if state.depot_wait or state.lane_pose or (state.overtaking or 0)~=0 then return end
  local t=s.tiles[current[4]]
  if not current[15] or current[10] or current[12] or current[13] or current[14] or not t or
      t.build~="road" or t.level_crossing then return end
  state.oneway_checked_rev,state.roadworks_checked_rev=revision,works
  local w=oneway_world(s)
  if not (w or works_changed) then return end
  local bad=false
  for i=state.index+1,#frames do
    if not one_way_pose(s,frames[i-1],frames[i]) then bad=true;break end
  end
  if not bad then return end
  local r=road_routing()
  local path,td,cost,new,bays
  if v.dest and (v.road_via_pending or works_changed) then
    local _
    path,_,td,cost,new,bays=source_route.from_live_frame(s,v,current,v.dest,r.occupancy(M,s),v.road_via_pending)
  else
    local base=crossing_road_board(s,r.board(M,s,r.follow,r.occupancy(M,s)))
    local alternate=w and w.reroute(s,v,current,base,r.search,r.cost,{display_max_speed=vehicle_limit,compatible={[0]=true}})
    if not alternate then return end
    new,bays=source_route.frames(w.path_board(s,base),alternate.trace,alternate.origin_frame)
    td,cost=alternate.last_td,alternate.cost
    path={}
    for _,n in ipairs(alternate.trace) do if path[#path]~=n.tile then path[#path+1]=n.tile end end
  end
  if v.road_bay_branch and not bays then return end
  if not new or #new<2 then return end
  -- Never replace a cursor if the road row/heading cannot meet at the
  -- actual stock pose. A held actor still owns its old leg in that case.
  local first=new[1]
  for _,i in ipairs{1,2,3,4,6,15} do if first[i]~=current[i] then return end end
  for i=2,#new do if not one_way_pose(s,new[i-1],new[i]) then return end end
  if not path or #path<2 then return end
  v.route,v.road_leg_td,v.road_route_cost,v.road_motion_frames=path,td,cost,new
  v.road_bay_branch=bays
  state.index,state.waiting,state.oneway_tile=1,nil,nil
  state.oneway_reroutes=(state.oneway_reroutes or 0)+1
  if v.status=="Waiting at one-way road" or v.status=="Waiting for roadworks" then v.status="En route" end
  return new
end
function M.path(s,a,b,mode,owner,avoid,vehicle,waypoints)
  if not a or not b or not a.tile or not b.tile or a.mode~=mode or b.mode~=mode or a.owner~=owner or b.owner~=owner then return nil end
  if mode=="road" and (a.tram_only or b.tram_only) then return nil end
  if mode=="road" and s.road_economy and s.corner_grid and not avoid then
    return road_departure(s,a,b,owner,vehicle,waypoints)
  end
  if a.tile==b.tile then return {a.tile} end
  if mode=="air" then return M.line(a.tile,b.tile) end
  local front,tail=1,1
  local queue,prev={a.tile},{[a.tile]=0}
  while front<=tail do
    local i=queue[front];front=front+1
    for k=1,4 do
      local j=adjacent(i,k)
      if j and prev[j]==nil and (not avoid or not avoid[j] or j==b.tile) then
        local pass
        if mode=="water" then pass=j==b.tile or wet(s,j)
        else
          local from,to=s.tiles[i],s.tiles[j]
          local leaves=not from.depot_dir or adjacent(i,from.depot_dir)==j
          local enters=to.build~="road_depot" or (j==b.tile and (not to.depot_dir or adjacent(j,to.depot_dir)==i))
          pass=leaves and enters and mode_on(s,j,mode,owner)
          if pass and mode=="road" and (s.corner_grid or s.has_town_roads) then
            pass=road_access(from,owner) and connected(s,i,k)
          end
          if pass and mode=="road" and s.road_oneway_revision then
            -- A legacy half-speed route cannot enforce source direction.
            pass=road_sign(from)==0 and road_sign(to)==0
          end
        end
        if pass then
          prev[j]=i
          if j==b.tile then
            local rev={j};local cur=j
            while prev[cur]~=0 do cur=prev[cur];rev[#rev+1]=cur end
            local out={}
            for m=#rev,1,-1 do out[#out+1]=rev[m] end
            return out
          end
          tail=tail+1;queue[tail]=j
        end
      end
    end
  end
end
function M.signal(s,owner,id)
  local t=s.tiles[id]
  if not t or not t.signal or t.owner~=owner then return false,"Select one of your rail signals." end
  t.closed=not t.closed
  return true,t.closed and "Signal set to hold departures." or "Signal reopened."
end
local function road_freight_catalog()
  if M.source_freight_catalog then return M.source_freight_catalog end
  local source=debug and debug.getinfo(1,"S").source
  local base=source and source:match("^@(.*/)sim%.lua$")
  base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  M.source_freight_catalog=dofile(base.."openttd/road_freight_catalog.lua")
  return M.source_freight_catalog
end
local craighead="craighead_goods_truck"
M.vehicles[craighead]=road_freight_catalog().offer(craighead)
table.insert(M.vehicle_order,#M.vehicle_order-4,craighead)
M.vehicles.foster_mk2_bus={name="Foster MkII Superbus",mode="road",cost=8750,speed=255,capacity=40,year=2008,development=true}
M.vehicle_order[#M.vehicle_order+1]="foster_mk2_bus"
for _,key in ipairs(road_freight_catalog().road_order) do
  local old=M.vehicles[key]
  M.vehicles[key]=road_freight_catalog().offer(key)
  if not old then M.vehicle_order[#M.vehicle_order+1]=key end
end
function M.road_extra_freight()
  local out={}
  for _,engine in ipairs(road_freight_catalog().road_order) do
    if not M.vehicles[engine].year then out[#out+1]=engine end
  end
  return out
end
local freight_art_mount=setmetatable({},{__mode="k"})
local extra_road_art=setmetatable({},{__mode="k"})
local function goods_engine(engine)
  return engine=="goods_truck" or engine==craighead or engine=="goods_goss"
end
local legacy_road_cargo={wood_truck="wood",goods_truck="goods",coal_tipper="coal",mail_van="mail",
  grain_truck="grain",livestock_van="livestock",oil_tanker="oil"}
function M.road_freight_cargo(engine)
  local def=M.vehicles[engine]
  return def and def.cargo or legacy_road_cargo[engine]
end
local function timber_engine(engine)
  return M.road_freight_cargo(engine)=="wood" or goods_engine(engine)
end
local function farm_engine(engine)
  local cargo=M.road_freight_cargo(engine)
  return cargo=="grain" or cargo=="livestock" or goods_engine(engine)
end
local function oil_engine(engine) return M.road_freight_cargo(engine)=="oil" or goods_engine(engine) end
local function coal_engine(engine) return M.road_freight_cargo(engine)=="coal" end
local function mail_engine(engine) return M.road_freight_cargo(engine)=="mail" end
local function priced_mail(engine) return engine~="mail_van" and mail_engine(engine) end
local function heavy_engine(engine)
  local cargo=M.road_freight_cargo(engine)
  return cargo=="steel" or cargo=="iron_ore" or cargo=="valuables" or goods_engine(engine)
end
local industry_road_cargo={wood=true,grain=true,livestock=true,oil=true,steel=true,iron_ore=true,valuables=true}
local function industry_truck(engine)
  return industry_road_cargo[M.road_freight_cargo(engine)]==true or goods_engine(engine)
end
local function allowed(engine,cargo)
  if engine=="leopard_bus" or engine=="foster_bus" or engine=="foster_mk2_bus" then return cargo=="passenger" end
  if mail_engine(engine) then return cargo=="mail" end
  if coal_engine(engine) then return cargo=="coal" end
  if road_freight_catalog().farm(engine) or road_freight_catalog().additional(engine) then return M.road_freight_cargo(engine)==cargo end
  if goods_engine(engine) then return cargo=="goods" end
  if engine=="oil_tanker" or cargo=="oil" then return engine=="oil_tanker" and cargo=="oil" end
  if engine=="bus" or engine=="coach" or engine=="ferry" or engine=="prop" or engine=="jet" then return cargo=="passenger" or cargo=="mail" end
  if engine=="truck" or engine=="freighter" then return cargo~="passenger" end
  return true
end
M.allowed=allowed
local function depot_endpoint(s,owner,id)
  local t=s.tiles[id]
  if t and t.owner==owner and t.build=="road_depot" then return {tile=id,owner=owner,mode="road"} end
end
local function road_bus_catalog()
  if not M.source_bus_catalog then
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    M.source_bus_catalog=dofile(base.."openttd/road_bus_catalog.lua")
  end
  return M.source_bus_catalog
end
function M.mount_road_bus_market(s,Calendar,starting_year,has_foster,has_craighead,extra_models)
  M.engine_calendar=Calendar
  if not s.stock_bus_market then
    assert(s.day==0 and not next(s.fleet),"Start the stock depot market in a fresh world.")
    assert(type(starting_year)=="number" and starting_year>=1950 and starting_year<=2050 and starting_year%1==0,
      "Set bayline_stock_bus_start_year to an integer from 1950 to 2050.")
    local gen=s.seed%2^32
    local startup_seed=s.stock_engine_startup_seed or (gen*1664525+1013904223)%2^32
    local settings={starting_year=starting_year,generation_seed=gen,startup_seed=startup_seed,
      climate="temperate"}
    local market={version=1,epoch=assert(Calendar.date(starting_year,1,1)),
      settings=settings,models={}}
    for _,stock_id in ipairs({116,117,118,119}) do
      market.models[stock_id]=assert(Calendar.prepare(stock_id,settings))
    end
    s.stock_bus_market=market
    s.news[1]=starting_year..": A new transportation charter opens on the coast."
  end
  assert(s.stock_bus_market.version==1,"Unsupported saved stock road market.")
  foster_art_mount[s]=not not has_foster
  freight_art_mount[s]=not not has_craighead
  extra_road_art[s]=extra_models or {}
  local market=s.stock_bus_market
  for _,key in ipairs({"goods_truck",craighead}) do
    local r=road_freight_catalog().row(key)
    market.models[r.stock_id]=market.models[r.stock_id] or assert(Calendar.prepare_original(r,market.settings))
  end
  market.models[119]=market.models[119] or assert(Calendar.prepare(119,market.settings))
  for _,key in ipairs(road_freight_catalog().road_order) do
    local row=road_freight_catalog().row(key)
    market.models[row.stock_id]=market.models[row.stock_id] or assert(Calendar.prepare_original(row,market.settings))
  end
end
function M.stock_world_launch(s,Calendar)
  assert(s.day==0 and not next(s.fleet) and s.stock_generated_profile and s.stock_generated_profile.forest)
  assert(s.stock_engine_startup_seed==nil,"Stock launch runs once, before pre-game tile visits")
  local year=s.stock_bus_market.settings.starting_year
  local rules=dofile(module_root.."openttd/world_startup_rc1.lua")
  s.stock_engine_startup_seed,s.stock_disaster_delay=rules.finish(function() return M.stock_random_u32(s) end)
  -- The scaffold before terrain generation only supplies the date. At
  -- the actual launch phase, replace it before any roster is usable.
  s.stock_bus_market=nil
  M.mount_road_bus_market(s,Calendar,year,false,false)
end
function M.foster_art_ready(s)
  return foster_art_mount[s]
end
function M.stock_road_offer(s,engine,date)
  local market=s.stock_bus_market
  local e=M.vehicles[engine]
  local id=market and (road_bus_catalog().stock_id(engine) or e and e.stock_engine_id)
  if not id or not market.models[id] then return end
  if engine=="foster_bus" and not M.foster_art_ready(s) then return end
  if engine=="foster_mk2_bus" and not (extra_road_art[s] and extra_road_art[s][engine]) then return end
  return assert(M.engine_calendar.snapshot(market.models[id],date or market.epoch+s.day))
end
function M.vehicle_offer(s,engine)
  if s.stock_bus_market and M.road_stock_service_active(s) then
    local catalog=road_bus_catalog()
    local id=catalog.stock_id(engine)
    if id then return catalog.quote(nil,nil,id) end
  elseif engine=="bus" and s.road_regal_enabled and M.road_stock_service_active(s) then
    return road_bus_catalog().quote()
  end
  return M.vehicles[engine]
end
function M.mount_road_faults(s,Kernel,Runtime,difficulty,service)
  if not s.stock_bus_market then return end
  local f=Runtime(Kernel,M,s,difficulty,function() return M.stock_random_u32(s) end)
  if service then
    assert(type(service.interval)=="number" and service.interval%1==0 and
      (service.interval==0 or service.interval>=5 and service.interval<=(service.percent and 90 or 800)),
      "Stock service interval must be 0 or within the supported day/percent range.")
    if service.interval>0 then f.auto=service end
  end
  road_faults_mount[s]=f
  return f
end
function M.road_fault_rating(s,v)
  local f=road_faults_mount[s]
  if f then return f.report(v) end
end
local function stock_bus(v) return v.stock_bus or v.stock_regal end
function M.vehicle_capacity(v)
  if v.stock_tram then return v.stock_tram.capacity end
  local s=stock_bus(v)
  return s and road_bus_catalog().capacity(s.stock_id) or M.vehicles[v.engine].capacity
end
function M.vehicle_stock_load_amount(v)
  if v.stock_tram then return v.stock_tram.slice end
  local r=stock_bus(v)
  return r and road_bus_catalog().quote(nil,nil,r.stock_id).load_amount
end
function M.vehicle_available(s,engine)
  if road_freight_catalog().additional(engine) then
    local market=s.stock_bus_market
    if not (market and extra_road_art[s] and extra_road_art[s][engine] and M.road_stock_service_active(s)) then return false end
    local cargo=M.road_freight_cargo(engine)
    local enabled=(cargo=="coal" and M.road_coal_active(s)) or
      (cargo=="oil" and M.road_oil_active(s)) or (cargo=="mail" and s.road_mail and s.road_stock_house_supply) or
      ((cargo=="steel" or cargo=="iron_ore") and M.road_heavy_active(s)) or
      (cargo=="valuables" and M.road_bank_active(s)) or
      (cargo=="goods" and (M.road_farm_active(s) or M.road_timber_active(s) or M.road_oil_active(s) or M.road_heavy_active(s)))
    return not not (enabled and M.engine_calendar.snapshot(market.models[M.vehicles[engine].stock_engine_id],market.epoch+s.day).public)
  end
  if engine=="mail_van" and s.stock_bus_market and extra_road_art[s] and extra_road_art[s].mail_mps then
    return false -- model #126 replaces the generic fallback in a complete stock game.
  end
  if road_freight_catalog().farm(engine) then
    local cargo=M.road_freight_cargo(engine)
    if cargo=="wood" then
      if not M.road_timber_active(s) then return false end
    elseif not M.road_farm_active(s) then return false end
    local early=M.vehicles[engine].year~=nil
    local market=s.stock_bus_market
    if not market then return early end
    if not early and not (extra_road_art[s] and extra_road_art[s][engine]) then return false end
    if not M.road_stock_service_active(s) then return false end
    return M.engine_calendar.snapshot(market.models[M.vehicles[engine].stock_engine_id],market.epoch+s.day).public
  end
  if engine==craighead then
    local market=s.stock_bus_market
    if not (market and freight_art_mount[s] and M.road_stock_service_active(s)) then return false end
    local model=M.engine_calendar.snapshot(market.models[139],market.epoch+s.day)
    return not not (model.public and (M.road_timber_active(s) or M.road_farm_active(s) or M.road_oil_active(s)))
  end
  if s.stock_bus_market and engine=="coach" then return false end
  if s.stock_bus_market and road_bus_catalog().stock_id(engine) then
    local model=M.stock_road_offer(s,engine)
    return not not (M.road_stock_service_active(s) and model and model.public)
  end
  local e=M.vehicles[engine]
  if not e or M.date(s)<e.year then return false end
  return not not (not e.development or
    (engine=="mail_van" and s.road_mail and s.road_stock_house_supply) or
    (engine=="coal_tipper" and M.road_coal_active(s)) or
    (timber_engine(engine) and M.road_timber_active(s)) or
    (farm_engine(engine) and M.road_farm_active(s)) or
    (oil_engine(engine) and M.road_oil_active(s)) or
    (heavy_engine(engine) and M.road_heavy_active(s)))
end
-- A road vehicle and each physical rail body occupy the same stock
-- VehicleID pool. Row IDs stay local to the UI; timers use the stock slot.
function M.stock_identity_pool()
  if not M.stock_id_pool then
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    M.stock_id_pool=dofile(base.."openttd/object_pool_rc1.lua")
  end
  return M.stock_id_pool
end
function M.stock_vehicle_slots(s,count)
  local Pool=M.stock_identity_pool()
  local used,limit={},0xFF000
  for id in pairs(s.stock_effect_vehicles or {}) do Pool.occupy(used,id,limit) end
  for id,v in pairs(s.fleet or {}) do
    Pool.occupy(used,v.stock_pool_id or id-1,limit)
  end
  local rail=s.stock_rail_fleet
  if rail then
    local function collect(group)
      for _,unit in pairs(group or {}) do
        for _,p in ipairs(unit.parts) do
          if p.stock_pool_id~=nil then Pool.occupy(used,p.stock_pool_id,limit) end
        end
      end
    end
    collect(rail.units);collect(rail.loose)
  end
  local function aircraft(unit)
    for _,id in ipairs(unit.stock_pool_ids or {}) do Pool.occupy(used,id,limit) end
  end
  local ferry=s.stock_owned_ferry
  if ferry and ferry.stock_pool_id~=nil then Pool.occupy(used,ferry.stock_pool_id,limit) end
  if s.stock_owned_aircraft then aircraft(s.stock_owned_aircraft) end
  for _,unit in pairs(s.stock_owned_air_fleet or {}) do aircraft(unit) end
  return Pool.reserve(used,count,limit)
end
-- BaseStation (stations and waypoints) shares one allocator. A neutral
-- rig contributes a single BaseStation, not one per presentation alias.
-- Retired facilities still occupy a slot until their final stock tick.
function M.stock_station_slot(s)
  if not s.stock_pool_authority and s.stock_engine_startup_seed==nil then return end
  local Pool,used,limit=M.stock_identity_pool(),{},0xFFFE
  local Joined,claimed=M.stock_joined_station,{}
  local function visit(row,mode,host)
    local id=row.stock_station_id
    if id==nil then return end
    local linked=mode and Joined.resolve(s,id,mode,host,row)
    if linked and claimed[id]==linked then return end
    Pool.occupy(used,id,limit)
    if linked then claimed[id]=linked end
  end
  for _,key in ipairs({"stations","stock_road_waypoints","stock_rail_stations","stock_rail_waypoints",
      "stock_ship_stations","stock_ship_buoys","stock_small_airports","stock_neutral_stations"}) do
    local mode=Joined.mode_by_pool[key]
    for host,row in pairs(s[key] or {}) do if not row.neutral then visit(row,mode,host) end end
  end
  for _,key in ipairs({"retired_road_stations","retired_road_waypoints","retired_ship_stations",
      "retired_rail_stations","retired_airports"}) do
    for _,entry in pairs(s[key] or {}) do
      local now=s.passenger_house_clock and s.passenger_house_clock.counter or s.stock_load_tick or s.day*74
      if now<entry.until_tick then visit(entry.row) end
    end
  end
  return assert(Pool.reserve(used,1,limit),"Stock station pool exhausted")[1]
end
function M.purchase(s,owner,engine,cargo,station,depot)
  local c=M.company(s,owner)
  local e=M.vehicle_offer(s,engine)
  local st=s.stations[station]
  if not e or not M.cargo[cargo] or not allowed(engine,cargo) then return nil,"That vehicle cannot carry this cargo." end
  if not M.vehicle_available(s,engine) then return nil,"That model is not available." end
  if e.stock_id and (cargo~="passenger" or not depot) then
    return nil,"Buy the original passenger bus in an owned road depot."
  end
  if (coal_engine(engine) or priced_mail(engine)) and not depot then return nil,"Buy the truck in an owned road depot." end
  if industry_truck(engine) and not depot then return nil,"Buy this freight vehicle in an owned road depot." end
  if depot then
    if station or e.mode~="road" or not depot_endpoint(s,owner,depot) then return nil,"Select a road depot you own." end
  elseif not st or st.tram_only or st.owner~=owner or st.mode~=e.mode then return nil,"Select a compatible terminal you own." end
  if st and s.tiles[st.tile].road_stop_pair then
    return nil,"Buy this vehicle in a road depot, then order the two-bay terminus."
  end
  if c.cash<e.cost then return nil,"Not enough cash." end
  local n=0;for _,v in pairs(s.fleet) do if v.owner==owner then n=n+1 end end
  if n>=60 then return nil,"Company fleet limit reached (60)." end
  local stock_id
  if s.stock_engine_startup_seed~=nil and e.mode=="road" then
    local slots,why=M.stock_vehicle_slots(s,1)
    if not slots then return nil,why end
    stock_id=slots[1]
  end
  debit(c,e.cost)
  local id=s.next_vehicle;s.next_vehicle=id+1
  s.fleet[id]={id=id,name=e.name.." #"..id,owner=owner,engine=engine,cargo=cargo,station=station,
    depot=depot,home_depot=depot,orders=depot and {} or {{station=station,action="normal"}},index=1,units=0,revenue=0,expense=0,delivered=0, bought=s.day,
    status="Stopped",running=false,progress=0,wait=0,condition=100,stock_purchase_value=e.cost,stock_pool_id=stock_id}
  if e.stock_id then
    local key=s.stock_bus_market and "stock_bus" or "stock_regal"
    local v=s.fleet[id]
    v[key]=road_bus_catalog().new(e)
    M.stock_road_vehicle_random(s,v,"built")
    local f=road_faults_mount[s]
    if f then f.purchased(v) end
  elseif stock_id~=nil and e.stock_engine_id and M.stock_road_offer(s,engine) then
    local v=s.fleet[id]
    v.stock_road_freight=true
    M.stock_road_vehicle_random(s,v,"built")
    local f=road_faults_mount[s]
    if f then f.purchased(v) end
  end
  return id,"Purchased "..s.fleet[id].name.."."
end
local order_lists
local function orders_module()
  if not order_lists then
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:sub(1,1)=="@" and source:sub(2):match("^(.*/)") or ""
    if core and core.get_modpath then base=core.get_modpath("luanttd_core").."/" end
    order_lists=dofile(base.."openttd/road_order_list.lua")
  end
  return order_lists
end
local function is_road_vehicle(v) return M.vehicles[v.engine].mode=="road" end
local function waypoint_destination(id)
  return type(id)=="string" and tonumber(id:match("^waypoint:(%d+)$")) or nil
end
local function road_order_location(s,id)
  local wp=waypoint_destination(id)
  if wp then return s.stock_road_waypoints and s.stock_road_waypoints[wp],wp end
  return s.stations[id]
end
function M.road_order_name(s,id)
  local row=road_order_location(s,id)
  return row and row.name
end
-- Index arrives at the next actual loading stop, collecting every
-- pinned Go via order on the way. With no cargo stop there is no run.
local function road_order_leg(s,v,first,skip_station)
  local vias={}
  if #v.orders==0 then return end
  local i=first
  for _=1,#v.orders do
    local order=v.orders[i]
    if not order then return end
    local target,waypoint=road_order_location(s,order.station)
    if not target or target.owner~=v.owner then return end
    if waypoint then vias[#vias+1]=waypoint
    elseif target.id~=skip_station or #vias>0 then return target,i,vias end
    i=i%#v.orders+1
  end
end
local function can_use_road_order(s,v,o)
  local st,waypoint=road_order_location(s,o.station)
  if waypoint then return st~=nil and st.owner==v.owner and M.road_stock_service_active(s) end
  if not st or st.tram_only or st.owner~=v.owner or st.mode~="road" then return false end
  if not s.road_economy then return true end
  if v.cargo=="passenger" then return M.road_stop_has(st,"bus") end
  if mail_engine(v.engine) or coal_engine(v.engine) or industry_truck(v.engine) then return M.road_stop_has(st,"truck") end
  return true
end
local abort_stock_stop
local function orders_changed(s,v,wipe_resume)
  if wipe_resume then v.road_depot_resume,v.road_order_override=nil,nil end
  if v.load_state then abort_stock_stop(s,v) end
  v.stock_loading_complete=nil
end
function M.restore_road_orders(s)
  if s.next_road_order_group then orders_module().restore(s) end
end
function M.road_order_members(s,id)
  local v=s.fleet[id]
  if not v or not is_road_vehicle(v) then return {} end
  return orders_module().members(s,v)
end
function M.can_copy_road_orders(s,owner,id,from)
  return orders_module().can_copy(s,owner,id,from,is_road_vehicle,
    function(v,o) return can_use_road_order(s,v,o) end)
end
function M.clone_road_orders(s,owner,id,from,action)
  local ok,note=orders_module().clone(s,owner,id,from,action,is_road_vehicle,
    function(v,o) return can_use_road_order(s,v,o) end)
  if ok then orders_changed(s,s.fleet[id],true) end
  return ok,note
end
-- RC1 order_cmd.cpp keeps per-vehicle indexes attached to the current
-- order even when the same list is shared. In-flight destinations are a
-- separate Lua motion cursor: reindex it too, or replace it through YAPF
-- from the physical front rather than teleporting to a stop/depot.
function M.road_order_target(s,owner,id,station)
  local v=s.fleet[id]
  local st,waypoint=road_order_location(s,station)
  if not v or v.crashed or not st or v.owner~=owner or st.owner~=owner or
      (waypoint and not is_road_vehicle(v) or not waypoint and st.mode~=M.vehicles[v.engine].mode) then
    return nil,"Choose a compatible terminal."
  end
  if not is_road_vehicle(v) then
    if v.running or v.route then return nil,"Stop at a terminal before changing orders." end
    if #v.orders>=16 then return nil,"Limit of 16 orders." end
    return st
  end
  for _,other in ipairs(orders_module().members(s,v)) do
    if not can_use_road_order(s,other,{station=station}) then
      return nil,other==v and (v.cargo=="passenger" and "Buses need passenger stops." or "Freight needs truck loading stops.")
        or "A vehicle sharing these orders cannot call at that stop."
    end
  end
  if #v.orders>=254 then return nil,"Limit of 254 orders." end
  if not s.road_economy and v.orders[#v.orders] and v.orders[#v.orders].station==station then
    return nil,"That order repeats the previous terminal."
  end
  return st
end
function M.add_order(s,owner,id,station,action)
  local v=s.fleet[id]
  local st,note=M.road_order_target(s,owner,id,station)
  if not st then return false,note end
  if not is_road_vehicle(v) and #v.orders>=16 then return false,"Limit of 16 orders." end
  if action~="transfer" and action~="full" and action~="unload" then action="normal" end
  local wp=waypoint_destination(station)
  v.orders[#v.orders+1]={station=station,action=wp and "via" or action}
  return true,"Added "..st.name.."."
end
function M.edit_order(s,owner,id,index,op)
  local v=s.fleet[id]
  local o=v and v.orders[index]
  if not v or v.crashed or v.owner~=owner or not o then return false,"Select one of your vehicle's orders." end
  local road=is_road_vehicle(v)
  if not road and (v.running or v.route) then return false,"Stop at a terminal before changing orders." end
  if op=="skip" then
    -- RC1 CmdSkipToOrder: reject the current order and lists shorter than
    -- two, leave a loading stop, then set both order cursors.
    if not road or #v.orders<2 or index==(type(v.road_order_override)=="number" and v.road_order_override or v.dest_index or v.road_depot_resume or v.index) then
      return false,"Choose a different order in a list of at least two stops."
    end
    if v.load_state then abort_stock_stop(s,v) end
    if v.station then v.stock_loading_complete=v.station end
    v.index=index
    if v.road_auto_service then v.road_auto_service.index,v.road_auto_service.station=index,o.station end
    if v.depot then v.road_depot_resume=index end
    v.road_order_override=index
    if v.road_speed_state then v.road_speed_state.order_retry_tile=nil end
    return true,"Next destination changed."
  end
  local members=road and orders_module().members(s,v) or {v}
  local moved
  if op=="remove" then table.remove(v.orders,index)
  elseif op=="cycle_load" and waypoint_destination(o.station) then return false,"A waypoint does not load cargo."
  elseif op=="cycle_load" then o.action=o.action=="full" and "normal" or "full"
  elseif op=="up" and index>1 then
    moved=index-1;v.orders[index],v.orders[moved]=v.orders[moved],o
  elseif op=="down" and index<#v.orders then
    moved=index+1;v.orders[index],v.orders[moved]=v.orders[moved],o
  else return false,"Cannot move this order farther." end
  for _,other in ipairs(members) do
    local function map(i)
      if type(i)~="number" then return i end
      if moved then return i==index and moved or i==moved and index or i end
      if op=="remove" then
        if i>index then return i-1 end
        if i==index and i>#v.orders then return 1 end
      end
      return i
    end
    local active=type(other.road_order_override)=="number" and other.road_order_override
        or other.dest_index or other.road_depot_resume or other.index
    if op=="cycle_load" and road and active==index and other.load_state then
      -- CmdModifyOrder updates the active loading copy, including peers
      -- on this shared list, without reclassifying cargo in flight.
      other.load_state.full=o.action=="full" and not other.stop_requested
    end
    if op=="remove" and road and active==index then
      if other.load_state then abort_stock_stop(s,other) end
      if other.station then other.stock_loading_complete=other.station end
      other.road_order_override=#v.orders>0 and map(index) or false
      if other.road_speed_state then other.road_speed_state.order_retry_tile=nil end
    else other.road_order_override=map(other.road_order_override) end
    other.index=map(other.index)
    other.dest_index=map(other.dest_index)
    other.road_depot_resume=map(other.road_depot_resume)
    if other.road_auto_service then
      other.road_auto_service.index=map(other.road_auto_service.index)
      local dest=v.orders[other.road_auto_service.index]
      if dest then other.road_auto_service.station=dest.station end
    end
  end
  return true,op=="cycle_load" and (o.action=="full" and "Order waits for a full load." or "Order loads normally.") or "Orders updated."
end
function M.toggle(s,owner,id)
  local v=s.fleet[id]
  if not v or v.owner~=owner then return false,"Select your vehicle." end
  if v.crashed then return false,"This vehicle is a wreck." end
  if v.road_return_depot then return false,"This vehicle is returning to its depot." end
  if v.stop_requested then v.stop_requested=nil;return true,"Scheduled stop cancelled." end
  if v.running then
    if v.route then v.stop_requested=true;return true,"Vehicle will stop at the next terminal." end
    v.running=false;v.status="Stopped";return true,"Vehicle stopped."
  end
  local mode=M.vehicles[v.engine].mode
  local distinct,first_station=false,nil
  for _,o in ipairs(v.orders) do
    if not waypoint_destination(o.station) then
      if first_station and o.station~=first_station then distinct=true end
      first_station=first_station or o.station
    end
  end
  if not distinct then return false,"Add at least two different terminal orders." end
  for i,o in ipairs(v.orders) do
    if not waypoint_destination(o.station) then
      local to,vias
      if mode=="road" then
        local _
        to,_,vias=road_order_leg(s,v,i%#v.orders+1,o.station)
      else to=s.stations[v.orders[i%#v.orders+1].station] end
      local actor=mode=="road" and {engine=v.engine,cargo=v.cargo} or nil
      if (not to or o.station~=to.id or vias and #vias>0) and not M.path(s,s.stations[o.station],to,mode,owner,nil,actor,vias) then
        return false,"No route from order "..i.." to its next terminal."
      end
    end
  end
  local resume=v.road_order_override or v.road_depot_resume or 1
  local to,vias
  if mode=="road" then
    local _
    to,_,vias=road_order_leg(s,v,v.orders[resume] and resume or 1)
  else to=s.stations[(v.orders[resume] or v.orders[1]).station] end
  if v.depot and not M.path(s,depot_endpoint(s,owner,v.depot),to,mode,owner,nil,v,vias) then
    return false,"The depot has no road connection to the first stop."
  end
  v.running=true;v.status=v.depot and "Leaving depot" or "Boarding";v.wait=0;v.loaded_at=nil;v.rail_wait_key=nil
  return true,"Vehicle dispatched."
end
function M.sell(s,owner,id)
  local v=s.fleet[id]
  if not v or v.owner~=owner then return false,"Select your vehicle." end
  if v.crashed then return false,"This vehicle is a wreck." end
  if v.running or v.route or v.units>0 then return false,"Stop and unload the vehicle before selling." end
  if v.road_bay_claim then return false,"A vehicle in an occupied two-bay terminus cannot be sold here." end
  local bus=stock_bus(v)
  if bus and not depot_endpoint(s,owner,v.depot) then
    return false,"The bus must be stopped in its owned depot to sell."
  end
  local amount=bus and bus.value or math.floor(M.vehicles[v.engine].cost*math.max(0.2,0.72-(s.day-v.bought)*0.00015))
  if v.load_state then abort_stock_stop(s,v) end
  if v.order_group then orders_module().release(s,v) end
  M.company(s,owner).cash=M.company(s,owner).cash+amount;s.fleet[id]=nil
  return true,"Sold for $"..amount.."."
end
function M.service(s,owner,id)
  local v=s.fleet[id]
  if not v or v.crashed or v.owner~=owner or v.route then return false,"Vehicle must be at a terminal." end
  if stock_bus(v) then return false,"Manual maintenance is not in the original-bus preview." end
  local c=M.company(s,owner);local amount=math.floor(M.vehicles[v.engine].cost*0.05)
  if c.cash<amount then return false,"Not enough cash." end
  debit(c,amount);v.expense=v.expense+amount;v.condition=100
  return true,"Vehicle serviced for $"..amount.."."
end
local passenger_rules,income_rules
M.road_station_order_should_stop=dofile(module_root.."openttd/station_stop_order.lua").should_stop
local rating_runtime,town_passengers,mail_runtime,station_service,paid_ferry,coal_service,rail_coal
local timber_service,timber_rules,ship_coal
local farm_service,farm_world
local farm={}
local oil={reports=setmetatable({},{__mode="k"})}
local goods={ready=setmetatable({},{__mode="k"})}
local FreightKinds
do
  local source=debug and debug.getinfo(1,"S").source
  local dir=source and source:match("^@(.*/)sim%.lua$") or
    (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  FreightKinds=dofile(dir.."rail_freight_kinds.lua")
end
local profiled={ready=setmetatable({},{__mode="k"}),runtime={}}
local timber_day_bindings=setmetatable({},{__mode="k"})
local coal_day_bindings=setmetatable({},{__mode="k"})
local function timber_binding(s,force)
  if timber_day_bindings[s] then return timber_day_bindings[s] end
  if goods.mixed_enabled and goods.mixed_enabled(s) then return goods.mixed_binding(s) end
  if oil.service and s.stock_oil_industries and (force or M.road_oil_active(s)) then
    return oil.binding(s)
  end
  if farm_service and farm_world and s.stock_farm_industries and (force or M.road_farm_active(s)) then
    local list,ports=goods.berths(s)
    local B=farm_service.bind(s,{credit=credit,field_board=farm_world.field_board(s),ship_stations=list})
    B.goods_ship_binding=ports
    return B
  end
  if not timber_service or not s.stock_timber_industries or not (force or M.road_timber_active(s)) then return end
  if M.rail_profile_active(s,"wood") then return profiled.timber_binding(s) end
  return goods.binding(s)
end
local function received_coal(world,plant,n)
  local site=world.sites[plant.site_id or plant.site or 0]
  if site and site.kind=="stock_power_station" then
    site.received=site.received or {}
    site.received.coal=(site.received.coal or 0)+n
  end
end
local function coal_binding(s,force,freight,freighter)
  local road=M.road_coal_active(s)
  if not force and not road then return end
  local function extend(stations,coverage)
    if freight then freight.extend(stations,coverage) end
    if freighter then freighter.extend(stations,coverage) end
  end
  local mixed=freight or freighter
  return coal_day_bindings[s] or coal_service.bind(s,{credit=credit,separate_queue=true,
    road_enabled=road or (force and not mixed) or false,
    extend=mixed and extend,distribute=mixed and rail_coal.distribute,
    select_goods=s.stock_select_goods,
    scale=s.stock_coal_scale,recession=s.stock_coal_recession,
    current_payment=s.stock_coal_payment,received=received_coal,
  })
end
local paid_ferry_runs,paid_rail_runs=setmetatable({},{__mode="k"}),setmetatable({},{__mode="k"})
local paid_air_runs=setmetatable({},{__mode="k"})
local function passenger_modules()
  if passenger_rules then return passenger_rules,income_rules end
  local source=debug and debug.getinfo(1,"S").source
  local base=source and source:match("^@(.*/)sim%.lua$")
  base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  passenger_rules=dofile(base.."openttd/passengers.lua")
  income_rules=dofile(base.."openttd/income.lua")
  M.stock_station_acceptance_history=dofile(base.."openttd/station_acceptance_history.lua")
  local kernel=dofile(base.."openttd/station_rating.lua")
  local house=dofile(base.."openttd/town_passengers.lua")
  rating_runtime=dofile(base.."station_rating_runtime.lua")(M,kernel,passenger_rules)
  mail_runtime=dofile(base.."road_mail_runtime.lua")(M,house,passenger_rules,income_rules,kernel,rating_runtime)
  town_passengers=dofile(base.."town_passenger_runtime.lua")(M,house,passenger_rules,rating_runtime,mail_runtime)
  local timing=dofile(base.."openttd/loading_timing.lua")
  local loading_factory=dofile(base.."road_loading_runtime.lua")
  local loader=loading_factory(timing,passenger_rules)
  station_service=dofile(base.."road_station_service.lua")(M,loader,passenger_rules,income_rules,rating_runtime,mail_runtime,
    {credit=credit,news=push,coal=coal_binding,
      coal_handles=function(s,v) return M.road_coal_active(s) and coal_service.supported_vehicle(v) end,
      timber=timber_binding,timber_handles=function(s,v)
        return ((M.road_heavy_active(s) or M.road_bank_active(s)) and goods.mixed and goods.mixed.supported_vehicle(v)) or (M.road_timber_active(s) and timber_service.supported_vehicle(v)) or
          (M.road_farm_active(s) and farm_service and farm_service.supported_vehicle(v)) or
          (M.road_oil_active(s) and oil.service.supported_vehicle(v))
      end})
  local catchment=dofile(base.."openttd/station_catchment.lua")(passenger_rules,kernel,
    station_service.house_passenger_acceptance,mail_runtime.house_acceptance)
  local coal=dofile(base.."openttd/coal_industry.lua")(passenger_rules,kernel,catchment,income_rules)
  coal_service=dofile(base.."road_coal_service.lua")(M,coal,catchment,passenger_rules,income_rules,kernel,rating_runtime)
  local houses=dofile(base.."openttd/town_goods.lua")
  timber_rules=dofile(base.."openttd/timber_industry.lua")(passenger_rules,catchment,kernel,income_rules,coal,houses)
  local timber_adapter=dofile(base.."timber_industry_runtime.lua")(timber_rules,catchment)
  timber_service=dofile(base.."road_timber_service.lua")(M,timber_rules,timber_adapter,passenger_rules,income_rules,kernel,rating_runtime)
  local roster=dofile(base.."openttd/rail_roster.lua")
  local freight=dofile(base.."rail_coal_service.lua")(M,coal,catchment,roster,passenger_rules,kernel,
    rating_runtime,income_rules,loading_factory,timing)
  rail_coal=dofile(base.."rail_coal_runtime.lua")(M,freight,roster,debit,credit,received_coal)
  local goods_rail=dofile(base.."rail_goods_service.lua")(M,timber_rules,catchment,roster,freight,
    passenger_rules,kernel,rating_runtime,loading_factory,timing)
  goods.runtime=dofile(base.."rail_goods_runtime.lua")(M,goods_rail,freight,roster,debit,credit,function(s)
    return goods.ready[s] and goods.ready[s]() or false
  end)
  local load_profile=dofile(base.."rail_profile_runtime.lua")
  local function new_profile(cargo,Rules)
    return load_profile(cargo,M,Rules,catchment,roster,freight,passenger_rules,kernel,rating_runtime,
      loading_factory,timing,debit,credit,function(s,key)
        local ready=profiled.ready[s]
        return ready and ready[key]==true
      end)
  end
  local function rail_union(s,order,controllers,for_cargo,probe)
    return function(roads,open,scan,rating)
      local rail={}
      local function attach(i,stations,covers)
        local cargo=order[i]
        if not cargo then return open(stations,covers) end
        local bind=controllers[cargo].union(s,paid_rail_runs[s],for_cargo==cargo and probe or nil)
        if not bind then return attach(i+1,stations,covers) end
        local b=bind(stations,function(next_stations,next_covers)
          return attach(i+1,next_stations,next_covers)
        end,scan,rating)
        rail[cargo]=b
        return b.pipeline
      end
      attach(1,roads)
      function rail.station_at(id)
        for _,cargo in ipairs(order) do
          local b=rail[cargo]
          local st=b and b.station_at(id)
          if st then return st end
        end
      end
      return rail
    end
  end
  profiled.runtime.wood=new_profile("wood",timber_rules)
  local timber_order,timber_controllers={"goods","wood"},{goods=goods.runtime,wood=profiled.runtime.wood}
  function profiled.timber_binding(s,cargo,probe)
    -- Single-chain Timber keeps its existing queues and receipt ledger.
    -- Goods and Wood share one station scan there, just as in mixed worlds.
    local list,ports=goods.berths(s)
    local B=timber_service.bind(s,{credit=credit,station_union=rail_union(s,timber_order,timber_controllers,cargo,probe),ship_stations=list})
    B.rail_multi=true;B.goods_ship_binding=ports
    return B
  end
  function goods.binding(s,probe)
    if goods.mixed_enabled and goods.mixed_enabled(s) then return {rail=goods.mixed_binding(s,"goods",probe).rail.goods} end
    if M.rail_profile_active(s,"wood") then return {rail=profiled.timber_binding(s,"goods",probe).rail.goods} end
    local list,ports=goods.berths(s)
    local B=timber_service.bind(s,{credit=credit,station_union=goods.runtime.union(s,paid_rail_runs[s],probe),ship_stations=list})
    B.goods_ship_binding=ports
    return B
  end
  oil.mount=function(Terrain)
    if oil.service then return end
    oil.rules=dofile(base.."openttd/oil_industry.lua")(dofile(base.."openttd/farm_factory_industry.lua"),
      passenger_rules,catchment,kernel,income_rules,coal,timber_rules)
    oil.world=dofile(base.."oil_industry_world.lua")(M,Terrain,oil.rules)
    oil.adapter=dofile(base.."oil_industry_runtime.lua")(oil.rules,dofile(base.."timber_industry_runtime.lua"),catchment)
    oil.service=dofile(base.."road_farm_service.lua")(M,oil.rules,oil.adapter,passenger_rules,income_rules,kernel,rating_runtime,
      {tag="oil",label="Oil chain",storage="stock_oil_industries",conflicts={"stock_timber_industries","stock_farm_industries"},
       vehicles={oil="oil_tanker",goods="goods_truck"},cargo={"oil","goods"}})
    local oil_rail=dofile(base.."rail_oil_service.lua")(M,oil.rules,catchment,roster,freight,passenger_rules,
      kernel,rating_runtime,loading_factory,timing)
    oil.runtime=dofile(base.."rail_oil_runtime.lua")(M,oil_rail,freight,roster,debit,credit)
    for kind,record in pairs(oil.world.facilities) do M.facilities[kind]=record end
    local oil_registry=dofile(base.."oil_animation_registry.lua")
    local tile_animation=dofile(base.."openttd/world_animation_rc1.lua")
    function oil.animation(s)
      if s.stock_world_animations then
        return function(_,tile,on)
          local id=M.id(tile.x+1,tile.z+1)
          if on then
            tile.animated=true
            tile_animation.add(s.stock_world_animations,id,"industry")
          else
            tile_animation.delete(s.stock_world_animations,id,false)
          end
        end
      end
      local tiles={}
      for _,firm in pairs(s.stock_oil_industries or {}) do
        if firm.kind=="oil_well" and not firm.removed then
          for _,t in ipairs(firm.tiles) do tiles[M.id(t.x+1,t.z+1)]=t end
        end
      end
      local register,step=oil_registry.bind(s,tiles,oil.rules.animate,function() return rating_runtime.random_u32(s) end)
      return function(_,tile,on) register(M.id(tile.x+1,tile.z+1),on) end,step
    end
    oil.ship=dofile(base.."ship_oil_runtime.lua")(M,
      dofile(base.."ship_oil_service.lua")(M,dofile(base.."openttd/oil_ship_roster.lua"),
        passenger_rules,kernel,loading_factory,timing),
      dofile(base.."openttd/oil_ship_roster.lua"),dofile(base.."openttd/stock_engine_calendar.lua"),oil.rules,catchment,debit)
    function oil.berths(s)
      local list,by,map=oil.ship.stations(s)
      return list,list and {by=by,map=map}
    end
    function oil.completion(s)
      return function(ind,tile)
        local station=oil.world.offshore.complete(s,ind,tile,{})
        if station then
          s.changed=s.changed or {}
          for _,part in ipairs(s.stock_oil_placements[ind.id].cells) do
            s.changed[#s.changed+1]=part.id
          end
        end
      end
    end
    function oil.binding(s,probe)
      if goods.mixed_enabled and goods.mixed_enabled(s) then return {rail=goods.mixed_binding(s,"oil",probe).rail.oil} end
      local animated,each_tick=oil.animation(s)
      local list,ports,dry=goods.join_ports(s)
      local B=oil.service.bind(s,{credit=credit,station_union=oil.runtime.union(s,paid_rail_runs[s],probe),
        animated=animated,each_tick=each_tick,ship_stations=list,complete_rig=oil.completion(s),
        stock_tile_animation=s.stock_generated_profile and s.stock_generated_profile.rc1_industry_phase})
      B.oil_ship_binding,B.goods_ship_binding=ports,dry
      return B
    end
  end
  goods.mount_mixed=function()
    if goods.mixed or not farm.rules or not oil.rules then return end
    local Rules,Adapter=dofile(base.."combined_industry_runtime.lua")(timber_rules,farm.rules,oil.rules,
      farm.fields,dofile(base.."timber_industry_runtime.lua"),catchment)
    local union=dofile(base.."road_farm_service.lua")(M,Rules,Adapter,passenger_rules,income_rules,kernel,rating_runtime,
      {tag="freight",label="Mixed industry",vehicles={wood="wood_truck",oil="oil_tanker",grain="grain_truck",
       livestock="livestock_van",goods="goods_truck",steel="steel_balogh",iron_ore="iron_mps",valuables="valuables_balogh"},
       cargo={"oil","livestock","goods","grain","wood","iron_ore","steel","valuables"}})
    goods.mixed=union
    local Freight=FreightKinds
    for _,cargo in ipairs(Freight.profile_order) do
      if not profiled.runtime[cargo] then profiled.runtime[cargo]=new_profile(cargo,Rules) end
    end
    local rail_controllers={oil=oil.runtime,goods=goods.runtime}
    for cargo,runtime in pairs(profiled.runtime) do rail_controllers[cargo]=runtime end
    function goods.mixed_enabled(s)
      local n=(M.road_timber_active(s) and 1 or 0)+(M.road_farm_active(s) and 1 or 0)+(M.road_oil_active(s) and 1 or 0)
      -- Even one local industry chain needs the shared road+rail
      -- station union when through rail freight is available.
      return n>1 or M.road_heavy_active(s) or M.road_bank_active(s) or
        M.rail_profile_active(s,"grain") or M.rail_profile_active(s,"livestock")
    end
    function goods.mixed_binding(s,for_cargo,probe)
      local all,enabled={},{}
      for _,kind in ipairs({"timber","farm","oil","heavy","bank"}) do
        if M["road_"..kind.."_active"](s) then
          enabled[kind]=true
          for id,ind in pairs(s["stock_"..kind.."_industries"] or {}) do
            assert(not all[id],"Conflicting stock industry IDs")
            all[id]=ind
          end
        end
      end
      local animated,tick
      if enabled.oil then animated,tick=oil.animation(s) end
      local station_union=rail_union(s,Freight.industry,rail_controllers,for_cargo,probe)
      local list,ports,dry=goods.join_ports(s)
      local B=union.bind(s,{credit=credit,industries=all,ship_stations=list,field_board=enabled.farm and farm_world.field_board(s),
        station_union=station_union,animated=animated,each_tick=tick,complete_rig=enabled.oil and oil.completion(s),
        stock_tile_animation=s.stock_generated_profile and s.stock_generated_profile.rc1_industry_phase,forestry_changed=function(t)
          s.changed=s.changed or {};s.changed[#s.changed+1]=M.id(t.x+1,t.z+1)
        end})
      B.mixed=true;B.oil_ship_binding,B.goods_ship_binding=ports,dry
      return B
    end
  end
  local ships=dofile(base.."openttd/ship_roster.lua")
  local coal_ship=dofile(base.."ship_coal_service.lua")(M,coal,catchment,ships,passenger_rules,kernel,
    rating_runtime,income_rules,loading_factory,timing)
  local make_dry=dofile(base.."ship_goods_service.lua")
  local dry_ports={}
  for _,cargo in ipairs({"goods","grain","livestock","wood","iron_ore","steel","valuables"}) do
    dry_ports[cargo]=make_dry(M,ships,passenger_rules,kernel,loading_factory,timing,cargo)
  end
  local dry=dofile(base.."ship_goods_runtime.lua")(M,dry_ports,timber_rules,function() return farm.rules end,catchment,debit)
  ship_coal=dofile(base.."ship_coal_runtime.lua")(M,coal_ship,ships,kernel,debit,credit,received_coal,
    dofile(base.."openttd/stock_engine_calendar.lua"),dry,
    dofile(base.."ship_mail_port.lua")(M,make_dry(M,ships,passenger_rules,kernel,loading_factory,timing,"mail"),catchment,house))
  goods.berths=ship_coal.goods_stations
  function goods.join_ports(s)
    local list,oil_ports=oil.berths(s)
    local dry_ports,goods_port=goods.berths(s)
    if dry_ports then
      list=list or {}
      for _,p in ipairs(dry_ports) do list[#list+1]=p end
    end
    return list,oil_ports,goods_port
  end
  local commercial=dofile(base.."passenger_station_service.lua")(catchment,passenger_rules,income_rules,kernel,
    rating_runtime,loading_factory,timing)
  local mux=dofile(base.."passenger_supply_mux.lua")(M,catchment,passenger_rules,rating_runtime,kernel)
  paid_ferry=dofile(base.."ship_paid_runtime.lua")(M,commercial,mux,credit,push,
    dofile(base.."rail_paid_actors.lua"),mail_runtime,catchment,rating_runtime.random_u32,ship_coal)
  return passenger_rules,income_rules
end
-- RC1 trams use the RoadVehicle station loader. Keep the custom body in
-- its streetcar run, not in the bus route planner or the general fleet.
-- The tram caller must select a real registered through platform.
function M.tram_passenger_arrive(s,v,frame,order,tick)
  local st=v and frame and M.tram_stop_station(s,frame[4],v.owner)
  if not st or not v.stock_tram then
    return nil,"INCOMPATIBLE_STATION"
  end
  passenger_modules()
  if not frame[6] or frame[6]<64 or frame[6]>=80 then return nil,"NOT_AT_PLATFORM" end
  if v.load_state then return v.load_state.station==st.id and v.load_state or nil end
  v.station,v.road_stop_pose=st.id,frame
  local state,why=station_service.begin(s,st,v,order,tick)
  if not state then v.station,v.road_stop_pose=nil,nil end
  return state,why
end
function M.tram_passenger_depart(s,v,tick,force)
  passenger_modules()
  if not v or not v.load_state or not (force or v.load_state.finished) then return false,"NOT_READY" end
  local ok=station_service.leave(s,v,tick)
  if ok then v.road_stop_pose,v.station=nil,nil end
  return ok
end
function M.tram_passenger_age(s,v,tick)
  passenger_modules()
  station_service.age_vehicle(s,v,tick)
end
function M.mount_stock_subsidies(s,event)
  passenger_modules()
  if not M.stock_subsidy_authority then
    local info=debug and debug.getinfo(1,"S").source
    local base=info and info:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    local G=dofile(base.."openttd/town_growth.lua")
    local rules=dofile(base.."openttd/subsidy.lua")(G.range,G.chance)
    local host=dofile(base.."stock_subsidy_host.lua")(M,rules,dofile(base.."openttd/town_passengers.lua"),{
      passenger=station_service.house_passenger_acceptance,
      mail=mail_runtime.house_acceptance,
      goods=dofile(base.."openttd/town_goods.lua").house_acceptance,
    },dofile(base.."openttd/town_cargo_stats.lua"))
    M.stock_subsidy_authority=dofile(base.."stock_subsidy_runtime.lua")(rules,host)
  end
  return M.stock_subsidy_authority.mount(s,{event=event})
end
function M.stock_subsidy_active(s)
  local book=s.stock_economy_subsidies
  return book and book.subsidies.count>0
end
function M.stock_subsidy_pay(s,cargo,owner,p,amount,coverage,chain,neutral)
  if not M.stock_subsidy_active(s) then return amount end
  return M.stock_subsidy_authority.pay(s,cargo,owner,p,amount,coverage,chain,neutral)
end
function M.stock_random_u32(s)
  passenger_modules()
  return rating_runtime.random_u32(s)
end
function M.stock_station_airports(s)
  passenger_modules()
  return rating_runtime.airports(s)
end
function M.stock_airport_acceptance_tick(s,row,tick)
  return rating_runtime.airport_acceptance_tick(s,row,tick)
end
-- Base engines do not change appearance here, but their original
-- triggers still participate in the RNG shared by towns and industry.
function M.stock_road_vehicle_random(s,v,trigger)
  if not (s.stock_generated_profile and s.stock_bus_market and (v.stock_bus or v.stock_road_freight)) then return end
  if not M.stock_vanilla_road_triggers then
    local info=debug and debug.getinfo(1,"S").source
    local base=info and info:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    M.stock_vanilla_road_triggers=dofile(base.."openttd/vehicle_random_trigger.lua")
  end
  local function random() return M.stock_random_u32(s) end
  if trigger=="built" then M.stock_vanilla_road_triggers.built(v,random)
  else M.stock_vanilla_road_triggers.single(v,trigger,random) end
end
function M.stock_town_accept(s,town,cargo,total,town_units)
  if not s.stock_town_growth or not town or total==0 then return end
  if not M.town_cargo_stats then
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    M.town_cargo_stats=dofile(base.."openttd/town_cargo_stats.lua")
  end
  return M.town_cargo_stats.accept(s,town,cargo,total,town_units)
end
function M.mount_oil_ship(s,net,run,ready,ferry,coal)
  if not oil.ship then return end
  oil.ship.mount(s,net,run,ready,ferry,coal)
  return oil.ship
end
function M.mount_oil_world(s,Terrain,asset_ready)
  if not asset_ready then return nil,"The native oil well, refinery or tanker assets are missing." end
  passenger_modules()
  oil.mount(Terrain)
  goods.mount_mixed()
  town_passengers.start(s)
  return oil.world
end
function M.oil_rules()
  return oil.rules
end
function M.oil_asset_shapes()
  return oil.world and oil.world.visual_sources()
end
function M.mount_farm_world(s,Terrain,asset_ready)
  if not asset_ready then return nil,"The native farm, factory or freight assets are missing." end
  passenger_modules()
  if not farm_service then
    local source=debug and debug.getinfo(1,"S").source
    local base=source and source:match("^@(.*/)sim%.lua$")
    base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
    local kernel=dofile(base.."openttd/station_rating.lua")
    local catchment=dofile(base.."openttd/station_catchment.lua")(passenger_rules,kernel,
      station_service.house_passenger_acceptance,mail_runtime.house_acceptance)
    local coal=dofile(base.."openttd/coal_industry.lua")(passenger_rules,kernel,catchment,income_rules)
    local rules=dofile(base.."openttd/farm_factory_industry.lua")(passenger_rules,catchment,kernel,
      income_rules,coal,timber_rules)
    rules=dofile(base.."openttd/iron_steel_rules.lua")(rules,dofile(base.."openttd/iron_steel_data.lua"))
    farm.heavy=dofile(base.."iron_steel_world.lua")(M,Terrain,rules)
    farm.bank_rules=dofile(base.."openttd/temperate_bank_rules.lua")(rules,dofile(base.."openttd/temperate_bank_data.lua"))
    farm.bank_factory=dofile(base.."temperate_bank_world.lua")
    local fields=dofile(base.."openttd/farm_factory_fields.lua")(coal)
    farm.rules,farm.fields=rules,fields
    local adapter=dofile(base.."farm_factory_runtime.lua")(rules,fields,
      dofile(base.."timber_industry_runtime.lua"),catchment)
    farm_service=dofile(base.."road_farm_service.lua")(M,rules,adapter,passenger_rules,income_rules,kernel,rating_runtime)
    farm_world=dofile(base.."farm_factory_world.lua")(M,Terrain,rules,fields,catchment)
  end
  goods.mount_mixed()
  for k,v in pairs(farm_world.facilities) do M.facilities[k]=v end
  town_passengers.start(s)
  return farm_world,function() return rating_runtime.random_u32(s) end,farm.rules
end
function M.mount_heavy_world(s,Terrain)
  if not farm.heavy then M.mount_farm_world(s,Terrain,true) end
  for k,v in pairs(farm.heavy.facilities) do M.facilities[k]=v end
  return farm.heavy
end
function M.mount_temperate_bank(s,Terrain,growth)
  s.road_bank=true;s.stock_bank_industries=s.stock_bank_industries or {}
  if not farm.bank_rules then M.mount_farm_world(s,Terrain,true) end
  M.facilities.stock_temperate_bank={name="Bank",produces={},takes={}}
  return farm.bank_factory(M,Terrain,farm.rules,farm.bank_rules,growth,debit,rating_runtime.random_u32)
end
function M.mount_coal_ship(s,Run,Passenger,Network,art)
  passenger_modules()
  ship_coal.mount(s,Run,Passenger,Network,art)
  return ship_coal
end
function M.ship_oil_active(s,station)
  if not oil.ship or not oil.ship.active(s) then return false end
  local Run=oil.ship.run(s)
  local voyage=Run and Run.current(s)
  return voyage and (not station or Run.ordered_dock(voyage,station)) or false
end
function M.ship_goods_active(s,station)
  return ship_coal and ship_coal.goods_running(s,station) or false
end
function M.ship_coal_active(s)
  return ship_coal and ship_coal.active(s) or false
end
function M.mount_paid_ferry(s,Run)
  paid_ferry_runs[s]=Run
  passenger_modules()
end
function M.ferry_paid_status(s)
  if not paid_ferry_runs[s] then return end
  return paid_ferry.status(s,paid_ferry_runs[s],"ship")
end
function M.ferry_paid_pose(s,fraction)
  if not paid_ferry_runs[s] then return end
  return paid_ferry.pose(s,paid_ferry_runs[s],fraction)
end
function M.ferry_loading_events(s)
  if not paid_ferry_runs[s] then return {} end
  return paid_ferry.take_effects(s,"ship")
end
function M.commercial_passengers_waiting(s,mode,id)
  if not paid_ferry or not id then return 0 end
  return paid_ferry.terminal_waiting(s,mode,id)
end
function M.coastal_rail_bridge(s,id)
  local rail=paid_rail_runs[s]
  if rail and rail.coastal_bridge then return rail.coastal_bridge(s,id) end
end
function M.coastal_clear_rail_bridge(s,id)
  local rail=paid_rail_runs[s]
  if rail and rail.coastal_clear_bridge then return rail.coastal_clear_bridge(s,id) end
end
function M.coastal_rail_flood(s,id,tick,other,water_z)
  local rail=paid_rail_runs[s]
  if not rail or not rail.flood_ground_tile or not paid_ferry then return 0 end
  return rail.flood_ground_tile(s,id,function(r) return paid_ferry.flood_train(s,r,tick) end,other,water_z)
end
function M.coastal_clear_rail_signal(s,id,removed,apply)
  local rail=paid_rail_runs[s]
  if rail and rail.coastal_clear_signal then return rail.coastal_clear_signal(s,id,removed,apply) end
  local d=s.stock_rail_dispatch
  return not (d and d.signals and d.signals.records and d.signals.records[id])
end
function M.coastal_clear_rail_platform(s,id,apply)
  local rail=paid_rail_runs[s]
  return not not (rail and rail.coastal_clear_station and rail.coastal_clear_station(s,id,apply))
end
function M.mount_paid_rail(s,Run)
  paid_rail_runs[s]=Run
  passenger_modules()
  Run.stock_random=M.stock_random_u32
end
function M.rail_coal_active(s)
  return rail_coal and rail_coal.active(s,paid_rail_runs[s]) or false
end
function M.rail_coal_validate(s,owner,mine,power)
  if not rail_coal then return false,"Rail Coal is not mounted." end
  return rail_coal.validate(s,paid_rail_runs[s],owner,mine,power)
end
function M.rail_coal_designate(s,owner,id,role)
  if not rail_coal then return false,"Rail Coal is not mounted." end
  return rail_coal.designate(s,paid_rail_runs[s],owner,id,role)
end
function M.rail_coal_stop_status(s,id)
  return rail_coal and rail_coal.report(s,paid_rail_runs[s],id)
end
function M.rail_coal_status(s)
  return rail_coal and rail_coal.status(s,paid_rail_runs[s])
end
function M.rail_coal_loading_events(s)
  return rail_coal and rail_coal.take(s,"events") or {}
end
function M.rail_oil_active(s)
  return oil.runtime and oil.runtime.active(s,paid_rail_runs[s]) or false
end
function M.rail_oil_validate(s,owner,well,refinery)
  if not oil.runtime then return false,"Rail Oil is not mounted." end
  return oil.runtime.validate(s,paid_rail_runs[s],owner,well,refinery,function(probe) return oil.binding(s,probe) end)
end
function M.rail_oil_designate(s,owner,id,role)
  if not oil.runtime then return false,"Rail Oil is not mounted." end
  return oil.runtime.designate(s,paid_rail_runs[s],owner,id,role,function(probe) return oil.binding(s,probe) end)
end
function M.rail_oil_stop_status(s,id)
  return oil.runtime and oil.runtime.report(s,paid_rail_runs[s],id,function(probe) return oil.binding(s,probe) end)
end
function M.rail_oil_status(s)
  return oil.runtime and oil.runtime.status(s,paid_rail_runs[s])
end
function M.rail_oil_loading_events(s)
  return oil.runtime and oil.runtime.take(s,"events") or {}
end
function M.mount_rail_goods(s,asset_ready)
  assert(type(asset_ready)=="function","Rail Goods requires native mesh readiness")
  passenger_modules()
  goods.ready[s]=asset_ready
end
function M.rail_goods_active(s)
  return goods.runtime and goods.runtime.active(s,paid_rail_runs[s]) or false
end
function M.rail_goods_validate(s,owner,mill,town)
  if not goods.runtime then return false,"Rail Goods is not mounted." end
  return goods.runtime.validate(s,paid_rail_runs[s],owner,mill,town,function(probe) return goods.binding(s,probe) end)
end
function M.rail_goods_designate(s,owner,id,role)
  if not goods.runtime then return false,"Rail Goods is not mounted." end
  return goods.runtime.designate(s,paid_rail_runs[s],owner,id,role,function(probe) return goods.binding(s,probe) end)
end
function M.rail_goods_stop_status(s,id)
  return goods.runtime and goods.runtime.report(s,paid_rail_runs[s],id,function(probe) return goods.binding(s,probe) end)
end
function M.rail_goods_status(s)
  return goods.runtime and goods.runtime.status(s,paid_rail_runs[s])
end
function M.rail_goods_loading_events(s)
  return goods.runtime and goods.runtime.take(s,"events") or {}
end
function M.mount_rail_freight_profiles(s,assets)
  passenger_modules()
  local ready={}
  local Freight=FreightKinds
  for _,cargo in ipairs(Freight.profile_order) do
    local p=Freight.profiles[cargo]
    local mounted=M["road_"..p.system.."_active"](s) and Freight.art_ready(p,assets)
    s["rail_"..cargo.."_service"]=not not mounted
    ready[cargo]=not not mounted
  end
  profiled.ready[s]=ready
end
function M.rail_profile_active(s,cargo)
  local r=profiled.runtime[cargo]
  return r and r.active(s,paid_rail_runs[s]) or false
end
local function profile_binding(s,cargo,probe)
  local b
  if cargo=="wood" and not (goods.mixed_enabled and goods.mixed_enabled(s)) then
    b=profiled.timber_binding(s,cargo,probe)
  else
    b=goods.mixed_binding(s,cargo,probe)
  end
  return {rail=b.rail[cargo]}
end
function M.rail_profile_validate(s,cargo,owner,first,second)
  local r=profiled.runtime[cargo]
  if not r then return false,"Rail freight is unavailable." end
  return r.validate(s,paid_rail_runs[s],owner,first,second,function(probe) return profile_binding(s,cargo,probe) end)
end
for _,key in ipairs(FreightKinds.profile_order) do
  local cargo=key
  M["rail_"..cargo.."_designate"]=function(s,owner,id,role)
    local r=profiled.runtime[cargo]
    if not r then return false,"Rail freight is unavailable." end
    return r.designate(s,paid_rail_runs[s],owner,id,role,function(probe) return profile_binding(s,cargo,probe) end)
  end
  M["rail_"..cargo.."_stop_status"]=function(s,id)
    local r=profiled.runtime[cargo]
    return r and r.report(s,paid_rail_runs[s],id,function(probe) return profile_binding(s,cargo,probe) end)
  end
  M["rail_"..cargo.."_status"]=function(s)
    local r=profiled.runtime[cargo]
    return r and r.status(s,paid_rail_runs[s])
  end
  M["rail_"..cargo.."_loading_events"]=function(s)
    local r=profiled.runtime[cargo]
    return r and r.take(s,"events") or {}
  end
end
function M.mount_rail_mail(s,asset,mixed_engines)
  s.rail_mail_service=not not (asset and s.rail_paid_service and s.rail_owned_service and
    s.road_stock_house_supply and s.corner_grid)
  s.rail_mixed_town_engines=s.rail_mail_service and mixed_engines or nil
  s.rail_mixed_town_service=not not (s.rail_mixed_town_engines and next(s.rail_mixed_town_engines))
end
function M.rail_mail_active(s)
  return not not (s.rail_mail_service and paid_rail_runs[s] and s.stock_rail_fleet)
end
function M.rail_mail_stop_status(s,id)
  return M.rail_mail_active(s) and paid_ferry.mail_station(s,id) or nil
end
function M.rail_mixed_status(s,fleet_id)
  local q=M.rail_paid_status(s,fleet_id)
  return q and q.cargo=="mixed" and q or nil
end
function M.rail_mail_status(s,fleet_id)
  local q=M.rail_paid_status(s,fleet_id)
  return q and q.cargo=="mail" and q or nil
end
function M.rail_paid_status(s,fleet_id)
  local rail=paid_rail_runs[s]
  if not rail then return end
  return paid_ferry.status(s,rail,"rail",fleet_id)
end
function M.rail_paid_pose(s,part,fraction,fleet_id,native)
  local rail=paid_rail_runs[s]
  if not rail then return end
  local carrier=rail.current_paid(s,fleet_id)
  local kind=carrier and carrier.freight and (carrier.freight.cargo or "coal")
  if kind=="goods" and goods.runtime then return goods.runtime.pose(s,rail,part,fraction,native) end
  if kind=="oil" and oil.runtime then return oil.runtime.pose(s,rail,part,fraction,native) end
  if profiled.runtime[kind] then return profiled.runtime[kind].pose(s,rail,part,fraction,native) end
  if kind=="coal" then return rail_coal.pose(s,rail,part,fraction,native) end
  return paid_ferry.rail_pose(s,rail,part,fraction,fleet_id,native)
end
function M.rail_loading_events(s)
  if not paid_rail_runs[s] then return {} end
  return paid_ferry.take_effects(s,"rail")
end
function M.rail_paid_motion_events(s)
  local rail=paid_rail_runs[s]
  if not rail then return {} end
  local out=paid_ferry.take_rail_motion(s)
  local function append(items)
    for _,e in ipairs(items) do
      -- The common frame already carries incidents for station ratings;
      -- do not report that physical impact twice to world observers.
      if e.kind~="rail_collision" then out[#out+1]=e end
    end
  end
  if goods.runtime and goods.runtime.present(s,rail) then append(goods.runtime.take(s,"motion")) end
  if oil.runtime and oil.runtime.present(s,rail) then append(oil.runtime.take(s,"motion")) end
  if rail_coal.present(s,rail) then append(rail_coal.take(s,"motion")) end
  for _,cargo in ipairs(FreightKinds.profile_order) do
    local r=profiled.runtime[cargo]
    if r and r.present(s,rail) then append(r.take(s,"motion")) end
  end
  if #out>1 then
    local seq={}
    for i,e in ipairs(out) do seq[e]=i end
    table.sort(out,function(a,b)
      local x,y=a.world_tick or a.tick or 0,b.world_tick or b.tick or 0
      if x~=y then return x<y end
      if a.train~=b.train then return (a.train or 0)<(b.train or 0) end
      return seq[a]<seq[b]
    end)
  end
  return out
end
function M.mount_paid_air(s,Run)
  paid_air_runs[s]=Run
  passenger_modules()
end
function M.air_paid_status(s,paid_clock)
  if not paid_air_runs[s] then return end
  return paid_ferry.status(s,paid_air_runs[s],"air",paid_clock)
end
function M.air_paid_pose(s,fraction,paid_clock)
  if not paid_air_runs[s] then return end
  return paid_ferry.pose(s,paid_air_runs[s],fraction,"air",paid_clock)
end
function M.air_loading_events(s)
  if not paid_air_runs[s] then return {} end
  return paid_ferry.take_effects(s,"air")
end
function M.air_paid_motion_events(s)
  if not paid_air_runs[s] then return {} end
  return paid_ferry.take_air_motion(s)
end
local function paid_transport_day(s,live,merge_road)
  local Ship,Rail,Air=paid_ferry_runs[s],paid_rail_runs[s],paid_air_runs[s]
  if not ((Ship or Rail or Air) and paid_ferry.active(s,Ship,Rail,Air)) then return end
  town_passengers.start(s)
  return paid_ferry.day(s,Ship,Rail,Air,s.passenger_house_clock.counter+1,live,merge_road and station_service or nil)
end
function M.mount_stock_town_growth(s,world,want_new)
  assert(s.corner_grid and s.road_stock_clock and s.road_stock_house_supply and s.road_stock_loading and s.road_economy,
    "Stock town growth requires the stock road/house landscape")
  passenger_modules()
  town_passengers.start(s)
  if not s.stock_town_growth then
    -- A legacy save can have houses added after the old clock started.
    for id,t in ipairs(s.tiles) do
      if t.house and not t.source_house then town_passengers.stamp(s,t,id) end
    end
  end
  local state=world.start(s)
  town_growth_mount[s]={world=world,new=want_new~=false}
  return state
end
function M.town_founding_host()
  if not M.founding_host then
    load_road_rules()
    M.founding_host=dofile(module_root.."town_founding_world.lua")(M,terrain_rules,
      dofile(module_root.."openttd/town_growth.lua"))
  end
  return M.founding_host
end
function M.quote_town_founding(s,owner,request)
  local current=town_growth_mount[s]
  if not current then return nil,"TOWN_FOUNDING_FORBIDDEN" end
  local q,why=M.town_founding_host().quote(s,owner,current.world,request)
  return q,why
end
function M.found_town(s,owner,request,cost)
  local current=town_growth_mount[s]
  if not current then return nil,"TOWN_FOUNDING_FORBIDDEN" end
  local town,why=M.town_founding_host().apply(s,owner,current.world,request,cost)
  if not town then return nil,why end
  debit(s.companies[owner],town.cost,"other")
  M.road_tree_authority().invalidate_towns(s)
  return town
end

-- RC1 TownActionFundBuildings, GetTownActionCost[FundBuildings] (53),
-- and Price::TownAction. Shares the mounted town growth state and clock.
M.town_buildings_fund_cost=math.floor(1000000*53/256)
function M.quote_town_buildings(s,owner,id)
  local company=s.companies[owner]
  local growth,town=town_growth_mount[s],s.stock_town_growth and s.stock_town_growth.towns[id]
  if not growth or not company or not town then return end
  local policy=s.stock_road_town_policy or {}
  if policy.fund_buildings==false then return end
  local cost=M.town_buildings_fund_cost
  return {cost=cost,months=town.fund_buildings_months,affordable=company.cash>=cost}
end
function M.fund_town_buildings(s,owner,id,seen)
  local q=M.quote_town_buildings(s,owner,id)
  if not q then return false,"Town funding is unavailable." end
  if q.cost~=seen then return false,"The town funding price changed." end
  if not q.affordable then return false,"Not enough cash to fund buildings." end
  local mount=town_growth_mount[s]
  local town=assert(mount.world.fund_buildings(s,id))
  debit(s.companies[owner],q.cost)
  return true,"Funded town growth for three months.",{town=id,months=town.fund_buildings_months}
end
function M.quote_road_reconstruction(s,owner,id)
  local growth=town_growth_mount[s]
  return growth and growth.world.reconstruction and growth.world.reconstruction.view(s,id,owner)
end
function M.fund_road_reconstruction(s,owner,id,seen)
  local q=M.quote_road_reconstruction(s,owner,id)
  if not q then return false,"Road reconstruction is unavailable." end
  if q.cost~=seen then return false,"The road reconstruction price changed." end
  if not q.affordable then return false,"Not enough cash to fund road reconstruction." end
  local town=assert(town_growth_mount[s].world.reconstruction.fund(s,id))
  debit(s.companies[owner],q.cost)
  return true,"Funded local road reconstruction for six months.",{town=id,months=town.road_build_months}
end
local statue_world
local function statues()
  if not statue_world then
    load_road_rules()
    local Spiral=dofile(module_root.."openttd/spiral_tile_rc1.lua")
    local K=dofile(module_root.."openttd/town_statue_rc1.lua")(Spiral)
    statue_world=dofile(module_root.."town_statue_world.lua")(M,terrain_rules,K)
  end
  return statue_world
end
function M.quote_town_statue(s,owner,id)
  local mount=town_growth_mount[s]
  if mount and s.stock_generated_profile then return statues().quote(s,owner,id,mount.world) end
end
function M.build_town_statue(s,owner,id,offer)
  local mount=town_growth_mount[s]
  if not (mount and s.stock_generated_profile) then return false,"Town statue is unavailable." end
  local ids,cost=statues().apply(s,owner,id,offer,mount.world)
  if not ids then return false,cost end
  debit(s.companies[owner],cost)
  return true,"Town statue commissioned.",ids
end
function M.town_statue_station_bonus(s,owner,town)
  local t=s.stock_town_growth and s.stock_town_growth.towns[town]
  return t and t.statues and t.statues[owner]~=nil or false
end
local statue_station_town=setmetatable({},{__mode="k"})
function M.station_has_town_statue(s,st)
  if not (s.stock_statue_count and s.stock_statue_count>0 and st.owner) then return false end
  local t=type(st.town)=="number" and st.town or st.mode=="road" and st.site
  if not t then
    local tile=st.tile or st.tiles and st.tiles[1]
    if type(tile)~="number" then return false end
    local old=statue_station_town[st]
    if not old or old.world~=s or old.tile~=tile then
      local near=M.road_tree_authority().nearest(s,tile)
      old={world=s,tile=tile,town=near and near.id}
      statue_station_town[st]=old
    end
    t=old.town
  end
  return t and M.town_statue_station_bonus(s,st.owner,t) or false
end
local hq_runtime,hq_rules
local hq_stats_cache=setmetatable({},{__mode="k"})
local function company_hqs()
  if not hq_runtime then
    load_road_rules()
    hq_rules=dofile(module_root.."openttd/company_hq_rc1.lua")
    hq_runtime=dofile(module_root.."company_hq_world.lua")(M,terrain_rules,hq_rules,land_rules())
  end
  return hq_runtime,hq_rules
end
local function company_hq_stats(s,owner)
  local row=hq_stats_cache[s]
  if not row or row.day~=s.day or row.rev~=s.authority_revision or row.topology~=s.topology then
    row={day=s.day,rev=s.authority_revision,topology=s.topology,stats=HQStats.collect(s)}
    hq_stats_cache[s]=row
  end
  return row.stats[owner] or {vehicles={},stations={},min_age=HQStats.min_age}
end
-- CargoPacket::InvalidateAllFrom(SourceType::Headquarters) does not delete
-- freight or remove its fare. Only detach the source's identity.
function M.invalidate_hq_cargo(s,owner)
  local seen={}
  local function traverse(t)
    if type(t)~="table" or seen[t] then return end
    seen[t]=true
    if t.source_type=="headquarters" and t.source==owner then t.source=nil end
    for _,value in pairs(t) do if type(value)=="table" then traverse(value) end end
  end
  for _,reg in ipairs({"stations","fleet","stock_ship_commercial","tram_pilot","stock_tram_fleet"}) do traverse(s[reg]) end
end
function M.hq_flood_clear(s,owner,origin)
  local H=company_hqs()
  return H.flood_clear(s,owner,origin)
end
function M.hq_cargo_at(s,id)
  local tile=s.tiles[id]
  local mark=tile and tile.stock_landmark
  return mark and mark.kind=="headquarters" and mark or nil
end
function M.hq_acceptance(mark,cargo)
  local _,K=company_hqs()
  local passengers,mail=K.acceptance(mark.stage)
  return cargo=="passenger" and passengers or cargo=="mail" and mail or 0
end
function M.hq_production(s,mark,random)
  local _,K=company_hqs()
  return K.produce(mark.stage,random(),s.stock_recession or s.stock_coal_recession)
end
function M.stock_company_quarter(s,owner,c,year,month)
  local quarter=CompanyQuarter.month(c,year,month)
  if quarter and s.stock_company_hqs and s.stock_company_hqs[owner] then
    local H,K=company_hqs()
    local stats=company_hq_stats(s,owner)
    local score=K.score(c,stats.vehicles,stats.stations,c.stock_quarters,stats.min_age)
    quarter.performance_history=score
    quarter.company_value=K.value(c,stats.vehicles,stats.stations)
    H.upgrade(s,owner,score)
  end
end
-- OpenTTD 16.0-RC1 Company-priority tick, before industry, station,
-- subsidy and town monthly callbacks. Default stock fees only; optional
-- inflation and infrastructure maintenance are not synthesized here.
function M.stock_company_month(s,year,month)
  for owner,c in pairs(s.companies) do
    M.stock_company_quarter(s,owner,c,year,month)
    local rate,station_value=2,100
    local interest,overhead=CompanyQuarter.monthly_fees(c.loan,c.cash,month,rate,station_value)
    debit(c,interest,"loan_interest")
    -- ExpensesType::Other is deducted from balance, but does not affect
    -- CompanyEconomyEntry's operating expense column.
    debit(c,overhead,"other")
  end
end
function M.company_hq_status(s,owner,midday)
  if not (s.stock_generated_profile and s.companies[owner]) then return end
  local _,K=company_hqs()
  local c=s.companies[owner]
  -- A UI read halfway through a stock day must not cache provisional
  -- finance inputs for a later paid headquarters decision.
  local stats=midday and (HQStats.collect(s)[owner] or {vehicles={},stations={},min_age=HQStats.min_age})
    or company_hq_stats(s,owner)
  local p=s.stock_company_hqs and s.stock_company_hqs[owner]
  local score=K.score(c,stats.vehicles,stats.stations,c.stock_quarters or {},stats.min_age)
  return {tile=p and p.origin,stage=p and p.stage,score=score,value=K.value(c,stats.vehicles,stats.stations)}
end
function M.company_hq_quote(s,owner,origin)
  local H=company_hqs()
  return H.quote(s,owner,origin,company_hq_stats(s,owner),M.road_piece_occupancy(s))
end
function M.company_hq_apply(s,owner,origin,seen)
  local had=s.stock_company_hqs and s.stock_company_hqs[owner]~=nil
  local H=company_hqs()
  local dirty,q=H.apply(s,owner,origin,seen,company_hq_stats(s,owner),M.road_piece_occupancy(s))
  if not dirty then return false,q end
  debit(s.companies[owner],q.cost)
  return true,("%s headquarters for $%d."):format(had and "Relocated" or "Built",q.cost),dirty
end
function M.road_stock_service_active(s)
  return s.road_stock_loading and s.road_stock_clock and s.road_economy and s.corner_grid~=nil
end
function M.road_coal_active(s)
  return not not (s.road_coal and s.road_stock_house_supply and M.road_stock_service_active(s))
end
function M.road_timber_active(s)
  return not not (s.road_timber and s.road_stock_house_supply and s.stock_timber_industries and M.road_stock_service_active(s))
end
function M.road_farm_active(s)
  return not not (s.road_farm and s.road_stock_house_supply and s.stock_farm_industries and farm_service and
    M.road_stock_service_active(s))
end
function M.road_heavy_active(s)
  return not not (s.road_heavy and s.road_stock_house_supply and s.stock_heavy_industries and farm.heavy and
    M.road_stock_service_active(s))
end
function M.road_bank_active(s)
  return not not (s.road_bank and s.road_stock_house_supply and s.stock_bank_industries and farm.bank_rules and
    M.road_stock_service_active(s))
end
function M.road_oil_active(s)
  return not not (s.road_oil and s.road_stock_house_supply and s.stock_oil_industries and oil.service and
    M.road_stock_service_active(s))
end
function M.oil_stop_status(s,st,cargo)
  if not M.road_oil_active(s) or not M.road_stop_has(st,"truck") or
      (cargo~="oil" and cargo~="goods") then return end
  local b=timber_day_bindings[s]
  if not b then
    local saved=oil.reports[s]
    if not saved or saved.topology~=s.topology then
      saved={topology=s.topology,binding=timber_binding(s)}
      oil.reports[s]=saved
    end
    b=saved.binding
  end
  return b.display_waiting(st,cargo),b.report(st,cargo)
end
function M.farm_stop_status(s,st,cargo)
  if not M.road_farm_active(s) or not M.road_stop_has(st,"truck") or
      not (cargo=="grain" or cargo=="livestock" or cargo=="goods") then return end
  local b=timber_binding(s)
  return b.display_waiting(st,cargo),b.report(st,cargo)
end
function M.timber_rules()
  passenger_modules()
  return timber_rules
end
function M.timber_stop_status(s,st,cargo)
  if not M.road_timber_active(s) or not M.road_stop_has(st,"truck") or
      not (cargo=="wood" or cargo=="goods") then return end
  passenger_modules()
  town_passengers.start(s)
  local b=timber_binding(s)
  return b.display_waiting(st,cargo),b.report(st,cargo)
end
function M.coal_stop_status(s,st)
  if not M.road_coal_active(s) or not M.road_stop_has(st,"truck") then return end
  passenger_modules()
  local b=coal_binding(s)
  local acceptance=b.report(st)
  return b.display_waiting(st),acceptance.accepts,st.goods.coal.rating,acceptance
end
-- One on-demand worker snapshot of the physical truck stop. No second queue
-- and no simulated cargo dataset projected to nearby clients every tick.
function M.truck_stop_cargo(s,st)
  local tick=s.passenger_house_clock and s.passenger_house_clock.counter or 0
  local rows={}
  local function add(cargo,count,accepts,collects,rating)
    if count>0 or accepts or collects then
      rows[#rows+1]={cargo=cargo,name=M.cargo[cargo].name,waiting=count,accepts=not not accepts,
        collects=not not collects,rating=rating}
    end
  end
  if s.road_mail then
    local count,accepts,rating,known=M.mail_stop_status(s,st)
    if count then add("mail",count,accepts,count>0,known and rating or nil) end
  end
  if M.road_coal_active(s) then
    local count,accepts,rating=M.coal_stop_status(s,st)
    add("coal",count,accepts,count>0,rating)
  end
  local b=timber_day_bindings[s] or timber_binding(s)
  if b then
    for _,cargo in ipairs({"oil","livestock","goods","grain","wood","iron_ore","steel","valuables"}) do
      local r=b.report(st,cargo,tick)
      if r then
        local rating=st.goods and st.goods[cargo] and st.goods[cargo].rating
        add(cargo,b.display_waiting(st,cargo),r.accepts,r.sources and #r.sources>0,rating)
      end
    end
  end
  return rows
end
function M.road_loading_events(s)
  if not M.road_stock_service_active(s) then return {} end
  passenger_modules()
  return station_service.take_effects(s)
end
function M.has_stock_road_service(s,v)
  if not M.road_stock_service_active(s) then return false end
  passenger_modules()
  return station_service.handles(s,v)
end
abort_stock_stop=function(s,v)
  passenger_modules()
  station_service.leave(s,v,s.stock_load_tick or s.day*74)
  v.stock_loading_complete=nil
  v.loaded_at=nil
end
function M.build_truck_stop(s,owner,id)
  if not (s.road_mail and s.road_stock_house_supply) and not M.road_coal_active(s) and not M.road_timber_active(s) and not M.road_farm_active(s) and not M.road_oil_active(s) and not M.road_heavy_active(s) and not M.road_bank_active(s) then
    return false,"No stock mail or freight service in this campaign."
  end
  local t=s.tiles[id]
  if not t or t.station then return false,"Build a new truck loading stop rather than converting an active terminal." end
  local ok,msg,changed=M.build(s,owner,"road_station",{id})
  if ok then
    local st=s.stations[s.tiles[id].station]
    st.stop_type="truck"
    local near=s.sites[st.site]
    st.name=(near and near.name.." " or "").."Loading Stop #"..st.id
  end
  return ok,msg,changed
end
local function road_mail(s,v)
  return s.road_economy and s.road_mail and v.cargo=="mail" and mail_engine(v.engine)
end
function M.mail_stop_status(s,st)
  if not s.road_mail or not M.road_stop_has(st,"truck") then return end
  passenger_modules()
  town_passengers.start(s)
  local waiting=M.road_stock_service_active(s) and station_service.display_waiting(s,st,"mail") or mail_runtime.waiting(st)
  return waiting,mail_runtime.accepts(s,st),mail_runtime.status(st)
end
local function road_passenger(s,v)
  return s.road_economy and v.cargo=="passenger" and M.vehicles[v.engine].mode=="road"
end
function M.road_passenger_acceptance(s,id)
  if not (s.road_stock_house_supply and M.road_stock_service_active(s)) then return end
  passenger_modules()
  return station_service.acceptance(s,{tile=id,mode="road"},"passenger")
end
function M.waiting_passengers(s,st)
  if not st then return 0 end
  if s.road_economy and st.mode=="road" then
    passenger_modules()
    if M.road_stock_service_active(s) then return station_service.display_waiting(s,st,"passenger") end
    return passenger_rules.waiting(st)
  end
  local waiting=0
  for _,id in ipairs(st.served) do waiting=waiting+(s.sites[id].stock.passenger or 0) end
  for _,batch in ipairs(st.stock.passenger or {}) do waiting=waiting+batch.units end
  return waiting
end
function M.rail_accident_ratings(s,owner,x,y)
  return rating_runtime and rating_runtime.accident(s,owner,x,y,
    s.road_mail and mail_runtime and mail_runtime.accepts) or 0
end

function M.passenger_rating(s,st)
  if not st or not s.road_economy or st.mode~="road" then return end
  passenger_modules()
  return rating_runtime.status(s,st)
end
local function visit_station(s,st,v,action)
  if not road_passenger(s,v) then return end
  local eligible=action~="transfer" and action~="unload"
  local first=eligible and st.passenger_service_day==nil
  if first then st.passenger_service_day=s.day end
  v.last_arrival={tile=st.tile,day=s.day,first=first}
end
local function generate_passengers(s,supply)
  local packets=passenger_modules()
  local stations={}
  for _,st in pairs(s.stations) do
    if rating_runtime.offer(s,st) then stations[#stations+1]=st end
  end
  table.sort(stations,function(a,b) return a.id<b.id end)
  local served={}
  for _,st in ipairs(stations) do
    local rating=rating_runtime.offer(s,st)
    if rating>0 then
      for _,id in ipairs(st.served) do
        local list=served[id] or {}
        list[#list+1]={st=st,rating=rating}
        served[id]=list
      end
    end
  end
  for id,site in ipairs(s.sites) do
    local amount,list=supply[id],served[id]
    if amount and amount>0 and list then
      packets.allocate(amount,list)
      local moved=0
      for _,entry in ipairs(list) do
        local st=entry.st
        local units=packets.whole_units(st,entry.fixed)
        if units>0 then
          packets.enqueue(st,{units=units,source=id,origin_station=st.id,age=0})
          rating_runtime.generated(s,st,units)
          moved=moved+units
        end
      end
      -- Keep the old raw pool accounting for modes outside this opt-in
      -- loop. Road passengers are distributed only from today's output.
      site.stock.passenger=math.max(0,(site.stock.passenger or 0)-moved)
    end
  end
end
local function load_passengers(s,st,v,cap)
  local packets=passenger_modules()
  rating_runtime.observe_loading(s,st,v,cap-v.units)
  local queue=st.stock.passenger or {}
  local i,boarded=1,0
  while queue[i] and v.units<cap do
    local p=queue[i]
    if p.units>0 and p.last_vehicle~=v.id then
      local take=math.min(p.units,cap-v.units)
      local board=packets.split(p,take)
      if p==board then table.remove(queue,i) else i=i+1 end
      -- Legacy save packets lacked the true loading tile. Keep their
      -- old fare fallback instead of pretending a transfer was origin.
      if board.origin_station then packets.pickup(board,st,M.xy) end
      v.batches[#v.batches+1]=board
      v.units=v.units+take;boarded=boarded+take
    else
      i=i+1
    end
  end
  if boarded>0 then
    rating_runtime.loaded(st)
    st.last_service.passenger=s.day
    v.last_board={tile=st.tile,day=s.day,units=boarded}
  end
end
local function accepts(s,st,cargo,source)
  for _,id in ipairs(st.served) do
    if source~=id and M.facilities[s.sites[id].kind].takes[cargo] then return s.sites[id] end
  end
end
local function transfer_batch(st,cargo,b)
  st.stock[cargo]=st.stock[cargo] or {}
  local stock=st.stock[cargo]
  if #stock>=200 then
    for _,prev in ipairs(stock) do
      if prev.source==b.source then prev.units=math.min(1200,prev.units+b.units);return end
    end
    return
  end
  stock[#stock+1]=b
end
local function load_at(s,st,v,cap)
  local cargo=v.cargo
  v.batches=v.batches or {}
  if road_passenger(s,v) then return load_passengers(s,st,v,cap) end
  if road_mail(s,v) then
    passenger_modules()
    local count=mail_runtime.load(s,st,v,cap)
    if count>0 then v.last_board={tile=st.tile,day=s.day,units=count} end
    return
  end
  local queue=st.stock[cargo] or {}
  for i=#queue,1,-1 do
    local b=queue[i]
    if b.units>0 and v.units<cap and b.last_vehicle~=v.id then
      local take=math.min(b.units,cap-v.units)
      b.units=b.units-take;v.units=v.units+take
      v.batches[#v.batches+1]={units=take,source=b.source,day=b.day}
      if b.units==0 then table.remove(queue,i) end
    end
  end
  local feeder_ids={}
  for id,feed in pairs(s.stations) do
    if id~=st.id and feed.owner==st.owner and M.distance(st.tile,feed.tile)<=2 and feed.stock[cargo] then
      feeder_ids[#feeder_ids+1]=id
    end
  end
  table.sort(feeder_ids)
  for _,id in ipairs(feeder_ids) do
    local source=s.stations[id].stock[cargo]
    for i=#source,1,-1 do
      local b=source[i]
      if v.units<cap and b.last_vehicle~=v.id then
        local take=math.min(b.units,cap-v.units)
        b.units=b.units-take;v.units=v.units+take
        v.batches[#v.batches+1]={units=take,source=b.source,day=b.day}
        if b.units==0 then table.remove(source,i) end
      end
    end
  end
  for _,id in ipairs(st.served) do
    if v.units>=cap then break end
    local site=s.sites[id]
    local take=math.min(site.stock[cargo] or 0,cap-v.units)
    if take>0 then
      site.stock[cargo]=site.stock[cargo]-take;v.units=v.units+take
      v.batches[#v.batches+1]={units=take,source=id,day=s.day}
      st.last_service[cargo]=s.day
    end
  end
end
local function unload_mail(s,st,v,action)
  passenger_modules()
  local keep,paid,amount,removed={},0,0,0
  for _,p in ipairs(v.batches or {}) do
    local fare
    if action~="transfer" then fare=mail_runtime.fare(s,st,p) end
    if fare~=nil then
      paid,amount,removed=paid+p.units,amount+fare,removed+p.units
    elseif (action=="transfer" or action=="unload") and mail_runtime.transfer(s,st,p,v) then
      removed=removed+p.units
    else keep[#keep+1]=p end
  end
  v.batches=keep
  v.units=v.units-removed
  if removed>0 then rating_runtime.unloaded(st) end
  if paid>0 then
    local company=M.company(s,v.owner)
    credit(company,amount)
    v.last_fare={tile=st.tile,day=s.day,amount=amount,units=paid}
    v.revenue=v.revenue+amount;v.delivered=v.delivered+paid
    company.units=company.units+paid;company.paid_units=company.paid_units+paid
    CompanyQuarter.delivered(company,"mail",paid)
    HQStats.record(s,v,amount)
    local site=s.sites[st.site]
    if site then site.received.mail=(site.received.mail or 0)+paid end
  end
end
local function unload_at(s,st,v,action)
  if road_mail(s,v) then return unload_mail(s,st,v,action) end
  local remaining,amount,delivered={},0,0
  local company=M.company(s,v.owner)
  local uses_packets=road_passenger(s,v)
  local units_before=v.units
  if uses_packets then passenger_modules() end
  for _,b in ipairs(v.batches or {}) do
    local canonical=uses_packets and b.origin_tile~=nil
    local packets,income
    local site
    if canonical then
      packets,income=passenger_modules()
      -- Stock manual distribution accepts at a different station even
      -- when both stations serve the very same town (CargoPacket::ChooseAction).
      if action~="transfer" and packets.accept_at(b,st) then
        for _,id in ipairs(st.served) do
          local candidate=s.sites[id]
          if M.facilities[candidate.kind].takes.passenger then site=candidate;break end
        end
      end
    elseif action~="transfer" then
      site=accepts(s,st,v.cargo,b.source)
    end
    if site then
      local money
      if canonical then
        local dist=packets.distance(b,st.tile,M.xy)
        local spec=income.temperate.passenger
        money=income.regular(b.units,dist,b.age,spec[1],spec[2],spec[3])
      else
        local dist=M.distance(s.sites[b.source].tile,site.tile)
        local age=math.max(1,s.day-b.day)
        local rate=math.max(0.2,1-age/250)
        money=math.floor(b.units*M.cargo[v.cargo].rate*(0.9+dist*0.12)*rate)
      end
      for _,offer in ipairs(s.subsidies or {}) do
        if s.day<=offer.until_day and offer.src==b.source and offer.dst==site.id and offer.cargo==v.cargo then
          if not offer.owner then offer.owner=v.owner;push(s,v.owner.." earned a route subsidy to "..site.name..".") end
          if offer.owner==v.owner then money=math.floor(money*1.5) end
          break
        end
      end
      amount=amount+money;delivered=delivered+b.units
      site.received[v.cargo]=(site.received[v.cargo] or 0)+b.units
      local f=M.facilities[site.kind]
      if f.output then
        local qty=math.floor(b.units*f.ratio)
        site.stock[f.output]=math.min(1200,(site.stock[f.output] or 0)+qty)
        site.produced[f.output]=(site.produced[f.output] or 0)+qty
      end
      site.service=site.service+b.units
      if site.kind=="town" then company.rating[site.id]=math.min(100,(company.rating[site.id] or 48)+math.max(1,math.floor(b.units/10))) end
    elseif action=="transfer" or action=="unload" then
      b.last_vehicle=v.id
      if uses_packets then
        packets=packets or passenger_modules()
        if canonical then packets.drop(b,st,M.xy) end
        rating_runtime.transferred(s,st)
        packets.enqueue(st,b)
      else
        transfer_batch(st,v.cargo,b)
      end
    else remaining[#remaining+1]=b end
  end
  v.batches=remaining;v.units=0;for _,b in ipairs(remaining) do v.units=v.units+b.units end
  if uses_packets and units_before>v.units then rating_runtime.unloaded(st) end
  if delivered>0 then
    credit(company,amount);v.last_fare={tile=st.tile,day=s.day,amount=amount,units=delivered};v.revenue=v.revenue+amount;v.delivered=v.delivered+delivered
    company.units=company.units+delivered
    if company.paid_units==0 then
      push(s,v.owner.." made their first paid delivery: "..delivered.." "..M.cargo[v.cargo].name:lower().." for $"..amount..".")
    end
    company.paid_units=company.paid_units+delivered
    CompanyQuarter.delivered(company,v.cargo,delivered)
    HQStats.record(s,v,amount)
  end
end
function M.empty(s,owner,id)
  local v=s.fleet[id]
  local st=v and s.stations[v.station]
  if not st or v.owner~=owner or v.running then return false,"Stop the vehicle at a terminal first." end
  if coal_engine(v.engine) then return false,"Use an Unload order: stock coal unloads in timed truck-stop slices." end
  if industry_truck(v.engine) then return false,"Use its stock truck-stop order to unload and receive payment." end
  if v.load_state then abort_stock_stop(s,v) end
  unload_at(s,st,v,"unload")
  return true,"Vehicle emptied at its terminal."
end
function M.refit(s,owner,id,cargo)
  local v=s.fleet[id]
  if not v or v.owner~=owner or v.running or v.route or v.units>0 then return false,"Stop and empty the vehicle before refitting." end
  if (stock_bus(v) and cargo~="passenger") or not M.cargo[cargo] or not allowed(v.engine,cargo) then
    return false,"This model cannot carry that cargo."
  end
  if cargo==v.cargo then return false,"Vehicle already carries that cargo." end
  local c=M.company(s,owner);local price=math.ceil(M.vehicles[v.engine].cost/25)
  if c.cash<price then return false,"Not enough cash." end
  if v.load_state then abort_stock_stop(s,v) end
  debit(c,price);v.expense=v.expense+price;v.cargo=cargo
  return true,"Refitted for "..M.cargo[cargo].name.." for $"..price.."."
end
local function vehicle_order(v,station)
  for i,o in ipairs(v.orders) do if o.station==station then return i end end
  return nil
end
local function launch(s,v,route,dest,index,arrival_td,route_cost,frames,bays)
  v.road_via_pending,v.road_implicit_leg=nil,nil
  v.home_depot=v.home_depot or v.depot
  local depart=v.road_stop_motion
  v.road_stop_motion=nil
  v.road_motion_frames=frames;v.road_stop_pose=nil;v.road_speed_state=nil;v.stock_loading_complete=nil
  if depart and frames then
    v.road_speed_state={index=1,heading=frames[1][3],speed=0,subspeed=depart.subspeed,
      progress=depart.progress,incline=depart.incline,ticks=depart.ticks,depot_wait=depart.depot}
  end
  v.road_leg_td=arrival_td;v.road_route_cost=route_cost
  v.road_bay_branch=bays
  v.route=route;v.dest=dest;v.dest_index=index;v.progress=1;v.station=nil;v.depot=nil;v.wait=0;v.loaded_at=nil;v.status="En route"
end
-- Adapts the OpenTTD concept of route reservations to Bayline's one
-- track surface per tile. This is original Lua, not a YAPF/PBS translation.
local HEADWAY=2
local function route_key(r,reverse)
  if not reverse then return table.concat(r,",") end
  local b={}
  for i=#r,1,-1 do b[#b+1]=r[i] end
  return table.concat(b,",")
end
local function reserve(s,traffic,v)
  local r=v.route
  local key=route_key(r)
  local lane=traffic.lanes[key]
  if not lane then lane={};traffic.lanes[key]=lane end
  lane[#lane+1]=v
  for i=2,#r-1 do traffic.claims[r[i]]=key end
end
local function rail_route(s,traffic,v,st,dest,r)
  local function conflict(route)
    local key=route_key(route)
    local lane=traffic.lanes[key]
    local signaled=false
    for i=2,#route-1 do if s.tiles[route[i]].signal then signaled=true end end
    local join=signaled and lane and not traffic.waiting[route_key(route,true)]
    if join then
      for _,leader in ipairs(lane) do if leader.progress<1+HEADWAY then join=false;break end end
    end
    if lane and not join then return true end
    for i=1,#route do
      local tile=route[i]
      local claim=traffic.claims[tile]
      if s.tiles[tile].closed or (claim and (claim~=key or not join)) then return true end
    end
    return false
  end
  if not conflict(r) then return r end
  -- Prefer a different route if all of its future junctions are clear.
  local avoid={}
  for tile in pairs(traffic.claims) do avoid[tile]=true end
  for id,t in ipairs(s.tiles) do if t.closed then avoid[id]=true end end
  local alternate=M.path(s,st,dest,"rail",v.owner,avoid)
  if alternate and not conflict(alternate) then return alternate end
  -- Mark this direction's waiting demand so opposite convoys cannot starve it.
  traffic.waiting[route_key(r)]=true
  v.rail_wait_key=route_key(r)
end
local function idle_or_plan(s,v,traffic)
  if not v.running then return end
  if #v.orders==0 then v.running=false;v.status="No orders";return end
  local e=M.vehicles[v.engine]
  if v.depot then
    local ix=v.road_order_override or 1
    local first=s.stations[v.orders[ix] and v.orders[ix].station]
    local route,arrival_td,cost,frames,bays=M.path(s,depot_endpoint(s,v.owner,v.depot),first,e.mode,v.owner,nil,v)
    if route then launch(s,v,route,first.id,ix,arrival_td,cost,frames,bays);v.road_order_override=nil else v.status="No road from depot" end
    return
  end
  local st=s.stations[v.station]
  if not st then v.running=false;v.status="Missing terminal";return end
  local cur=v.orders[v.index] and v.orders[v.index].station==st.id and v.index or vehicle_order(v,st.id)
  local order=cur and v.orders[cur]
  local action=order and order.action or "normal"
  if v.road_order_override==nil and v.loaded_at~=st.id then
    visit_station(s,st,v,action)
    unload_at(s,st,v,action);v.loaded_at=st.id
  end
  if v.road_order_override==nil and action~="transfer" and action~="unload" then load_at(s,st,v,e.capacity) end
  if v.stop_requested then v.stop_requested=nil;v.running=false;v.status="Stopped";return end
  if v.road_order_override==nil and action=="full" and v.units<e.capacity and v.wait<35 then
    v.wait=v.wait+1;v.status="Waiting for full load";return
  end
  local next_index=v.road_order_override or (cur and cur%#v.orders+1 or 1)
  local target=s.stations[v.orders[next_index].station]
  local route,arrival_td,cost,frames,bays=M.path(s,st,target,e.mode,v.owner,nil,v)
  if not route then v.status="No path";v.rail_wait_key=nil;return end
  if e.mode=="rail" then
    route=rail_route(s,traffic,v,st,target,route)
    if not route then v.status="Waiting for clear track";return end
  end
  launch(s,v,route,target.id,next_index,arrival_td,cost,frames,bays);v.road_order_override=nil
  v.rail_wait_key=nil
  if e.mode=="rail" then reserve(s,traffic,v) end
end
local function stock_managed(s,v)
  -- A running version-1 save may have only an old coarse route. Finish
  -- that existing leg before taking over; new stock legs require frames.
  return station_service.handles(s,v) and (not v.route or v.road_motion_frames~=nil)
end
function M.road_can_park(s,owner,id)
  local v=s.fleet[id]
  if not (v and v.owner==owner and not v.crashed and not v.running and not v.route and not v.depot and v.units==0 and
      v.road_stop_pose and s.stations[v.station] and M.road_stock_service_active(s)) then return false end
  passenger_modules()
  return stock_managed(s,v)
end
function M.park_road_vehicle(s,owner,id)
  if not M.road_can_park(s,owner,id) then
    return false,"Stop and empty the road vehicle at its terminal first."
  end
  local v=s.fleet[id]
  local r=road_routing()
  local path,tile,td,cost,frames=source_route.nearest_depot(s,s.stations[v.station],v,r.occupancy(M,s))
  if not tile then return false,"No owned road depot is reachable from the stopped position." end
  if v.load_state then abort_stock_stop(s,v) end
  local ix=v.index or 1
  v.road_depot_resume=#v.orders>0 and ix%#v.orders+1 or nil
  launch(s,v,path,nil,nil,td,cost,frames)
  v.road_return_depot=tile
  v.running=true;v.stop_requested=nil;v.status="Returning to depot"
  return true,"Returning to the nearest reachable owned road depot."
end
local function current_station_order(v,st)
  local i=v.orders[v.index] and v.orders[v.index].station==st.id and v.index or vehicle_order(v,st.id)
  return i,i and v.orders[i]
end
-- Native flat through-stop adapter for RC1 FloodVehicleProc and
-- ClearTile_Station. The authoritative landscape loop can query several
-- shore cells in one tick; read the road fleet only once on demand.
local ground_flood_rules
local function road_flood_rules()
  ground_flood_rules=ground_flood_rules or dofile(module_root.."openttd/ground_vehicle_flood.lua")
  return ground_flood_rules
end
function M.coastal_road_stop_runtime(s)
  passenger_modules()
  road_stop_members=road_stop_members or dofile(module_root.."road_stop_members.lua")(M)
  local flood=road_flood_rules()
  local stamp,by_tile
  local function physical(tick)
    if stamp==tick and by_tile then return by_tile end
    stamp,by_tile=tick,{}
    for id,v in pairs(s.fleet) do
      local engine=M.vehicles[v.engine]
      local pose=engine and engine.mode=="road" and M.road_motion_frame(s,v)
      if pose and not (pose[10] or pose[12] or pose[13] or pose[14] or pose[16]) then
        local tile=pose[4]
        local row=by_tile[tile] or {}
        by_tile[tile]=row
        row[#row+1]=id
      end
    end
    for _,row in pairs(by_tile) do table.sort(row) end
    return by_tile
  end
  local function flood_at(id,tick)
    for _,vid in ipairs(physical(tick)[id] or {}) do
      local v=s.fleet[vid]
      local t=s.tiles[id]
      -- The mounted target is a flat through-stop, so its stock running
      -- surface is at sea level; only its actual boarding body qualifies.
      if v and v.home_depot and v.cargo=="passenger" and v.load_state and not v.route and
          v.load_state.station==t.station and M.stock_road_frame_z(s,v.road_stop_pose)<=0 and
          (not t.road_stop_pair or v.road_bay_claim and v.road_bay_claim.phase=="parked") then
        local n=station_service.crash(s,v,tick)
        if n~=nil then
          v.road_flood_age=flood.road_crash_age(true)
          local victims=flood.road_victims(M.stock_random_u32(s),n,true)
          if road_flood_news[s] then road_flood_news[s](id,victims) end
        end
      end
    end
  end
  local function clear(id,apply,tick)
    local t=s.tiles[id]
    local station=t.station and s.stations[t.station]
    if not station or station.mode~="road" or station.tram_only or not road_stop_members.current(station)[id] then return false end
    if not apply and physical(tick)[id] then return false end
    if t.road_stop_pair and not road_clock().bay.coastal_clear(s,id,false) then return false end
    local result=road_stop_members.preview(station,{{id=id}})
    for _,v in pairs(s.fleet) do
      local e=M.vehicles[v.engine]
      if e and e.mode=="road" then
        for _,tile in ipairs(v.route or {}) do if tile==id then return false end end
      end
      if not result.spread or not result.road_stop_areas[v.cargo=="passenger" and "bus" or "truck"] then
        for _,order in ipairs(v.orders or {}) do
          if order.station==station.id then return false end
        end
      end
      if v.station==station.id and not result.spread then return false end
    end
    if not apply then return true end
    if result.spread then
      road_stop_members.structural_apply(station,result)
      refresh_road_station_sites(s,station)
    else
      M.retire_road_station(s,station.id)
    end
    if t.road_stop_pair then
      assert(road_clock().bay.coastal_clear(s,id,true),"A coastal bay changed during clearance")
      t.road_stop_pair=nil
    end
    t.build,t.owner,t.road_bits,t.road_town,t.roadside,t.stock_roadside_town=nil,nil,nil,nil,nil,nil
    t.station,t.stop_axis,t.road_terminal_level,t.road_stop_type=nil,nil,nil,nil
    t.road_disallowed,t.disallowed,t.roadworks,t.roadworks_counter=nil,nil,nil,nil
    -- ClearTile_Station removes both road types when the land becomes
    -- water, unlike the player's tool that removes only the tram way.
    if t.tram then t.tram=nil end
    return true
  end
  return flood_at,clear
end

-- Electric streetcars share the source road clock, but are held in the
-- canonical tram register rather than mirrored in the road-vehicle pool.
function M.coastal_tram_stop_runtime(s)
  local trams=shared_tram_clock[s]
  if not trams or not trams.coastal_index then return end
  passenger_modules()
  local stamp,index
  local function flood_at(id,tick)
    if not index or stamp~=tick then index,stamp=trams.coastal_index(s),tick end
    local st=M.tram_stop_station(s,id)
    if not st then return end
    for _,p in ipairs(index[id] or {}) do
      local passengers=trams.flood(s,p,id,tick,st.id,function(v,ticks) return station_service.crash(s,v,ticks) end)
      if passengers~=nil then
        local victims=road_flood_rules().road_victims(M.stock_random_u32(s),passengers,true)
        if road_flood_news[s] then road_flood_news[s](id,victims,true) end
      end
    end
  end
  local function clear(id,apply)
    local st=M.tram_stop_station(s,id)
    if not st or not st.tram_only or trams.coastal_in_use(s,id) or M.road_station_in_use(s,st.id) then return false end
    if apply then
      local t=s.tiles[id]
      M.retire_road_station(s,st.id)
      t.tram,t.owner,t.roadside,t.stock_roadside_town=nil,nil,nil,nil
    end
    return true
  end
  local function shared_busy(id)
    local st=M.tram_stop_station(s,id)
    return not st or st.tram_only or trams.coastal_in_use(s,id)
  end
  return flood_at,clear,shared_busy
end

local function stock_next_plan(s,v,st)
  local i=current_station_order(v,st)
  local n=v.road_order_override or (i and i%#v.orders+1 or 1)
  local target,index,vias=road_order_leg(s,v,n,st.id)
  if not target then return end
  local path,td,cost,frames,bays=M.path(s,st,target,"road",v.owner,nil,v,vias)
  if path and frames and #path>1 then return path,td,cost,frames,target.id,index,bays,vias end
end
local function stock_seed_parked_pose(s,v,st)
  if v.road_stop_pose then return end
  local _,_,_,frames=stock_next_plan(s,v,st)
  if not frames then return end
  local first=frames[1]
  v.road_stop_pose=first
  -- Drive-through origin following must keep the lane/heading with which
  -- the initially spawned vehicle first appears. Bay turns use their own
  -- approach trackdir, irrespective of the outward search origin.
  if first[6]>=64 and first[6]<80 then v.road_arrival_td=first[6]-64 end
end
-- The decision kernel only receives a representable *current* native
-- origin. Spans/special stop transitions have their own live state and
-- are not snapped onto a plain road to force an early service detour.
local function automatic_road_service(s,faults,v,f,difficulty,date,random)
  if v.road_via_pending then return end
  local cfg=faults.auto
  if not cfg or v.stop_requested or v.road_return_depot and not v.road_auto_service then return end
  local engine=M.stock_road_offer(s,v.engine,date)
  if not engine then return end
  local c=v.road_speed_state
  local frame=c and M.road_motion_frame(s,v)
  local tile=v.depot or frame and frame[4]
  -- FindClosestRoadDepot can return zero cost before the vehicle
  -- is hidden: being on the physical depot tile is already enough.
  local depot_on_tile=tile and depot_endpoint(s,v.owner,tile)
  local parked_in_depot=v.depot~=nil
  local cell=frame and s.tiles[tile]
  local routeable=cell and (cell.build=="road" or cell.build=="road_station" and frame[6]>=64 and frame[6]<80)
    and not c.depot_wait and not c.lane_pose and not frame[10] and not frame[12] and not frame[13] and not frame[14]
    and not cell.level_crossing
  if not depot_on_tile and not routeable then return end
  local order=v.load_state and {kind="loading"} or v.road_auto_service and v.road_auto_service.order
    or {kind="goto_station"}
  local routing
  local function query(station)
    routing=routing or road_routing()
    return source_route.from_live_frame(s,v,frame,station,routing.occupancy(M,s))
  end
  local old=v.road_auto_service
  local plan=cfg.kernel.plan(f,{engine_reliability=engine.reliability,interval=cfg.interval,
    percent=cfg.percent,economy_date=date,company_service_interval=cfg.interval,
    stopped=not v.running,crashed=v.crashed,difficulty=difficulty,current_order=order,
    cur_speed=c and c.speed or 0,tile_is_road_depot=not not depot_on_tile,depot_state=parked_in_depot,
    tile=tile,depot=depot_on_tile and depot_on_tile.tile,dest_tile=old and old.depot or
      v.dest and s.stations[v.dest] and s.stations[v.dest].tile,orders=v.orders},
    {random32=random,nearest=function()
      local path,nearest,td,cost,frames=query()
      if path then return {tile=nearest,depot=nearest,cost=cost,path=path,td=td,frames=frames} end
      if frame then
        return source_route.reversing_depot_choice(s,v,frame,routing.occupancy(M,s))
      end
    end})
  if plan.kind=="service_here" then
    faults.service(v,s.stock_load_tick or s.day*74,date)
  elseif plan.kind=="route" and plan.route.path then
    if old and old.depot==plan.dest_tile then return end
    local target,idx=old and old.station or v.dest,old and old.index or v.dest_index
    if not target or not idx or not v.orders[idx] or v.orders[idx].station~=target then return end
    local r=plan.route
    launch(s,v,r.path,nil,nil,r.td,r.cost,r.frames)
    v.road_speed_state=c;c.index=1
    v.road_return_depot=plan.dest_tile
    v.road_auto_service={station=target,index=idx,depot=plan.dest_tile,order=plan.order}
    v.last_auto_depot={tile=plan.dest_tile,cost=r.cost,tick=s.stock_load_tick,station=target,index=idx}
    v.status="Heading to depot for service"
  elseif plan.kind=="cancel" and old then
    local path,_,td,cost,frames,bays=query(old.station)
    if not path then return end
    launch(s,v,path,old.station,old.index,td,cost,frames,bays)
    v.road_speed_state=c;c.index=1
    v.road_auto_service,v.road_return_depot=nil,nil
  end
end
-- Station controllers prepare cargo independently; physical Run advances
-- once per source simulation tick in the Train pool's order. Do not run
-- a second world tick for freight just because its loading service differs.
local function rail_tick_broker(s,before_train)
  local run=paid_rail_runs[s]
  if not run or not run.advance_services then return end
  local handlers,finishes,flushed={},{},false
  local function register(cargo,callbacks,finish)
    assert(not handlers[cargo],"Duplicate rail cargo adapter "..cargo)
    handlers[cargo],finishes[cargo]=callbacks,finish
  end
  local function advance(passenger)
    assert(not flushed,"Rail world tick already advanced")
    flushed=true
    handlers.passenger=passenger
    if not next(handlers) then return {} end
    local moved=run.advance_services(s,handlers,before_train)
    local d=run.current(s)
    local by={passenger={}}
    for _,e in ipairs(moved) do
      local train
      if run.by_id then train=run.by_id(s,e.train) elseif d then train=d.runs[e.train] end
      local cargo=train and train.freight and (train.freight.cargo or "coal") or "passenger"
      local list=by[cargo] or {};by[cargo]=list;list[#list+1]=e
      if e.kind=="rail_collision" and cargo~="passenger" then by.passenger[#by.passenger+1]=e end
    end
    for _,name in ipairs(FreightKinds.all) do if finishes[name] then finishes[name](by[name]) end end
    return by.passenger
  end
  return register,advance,function() return flushed end
end

local function stock_station_day(s,legacy_supply,commercial,coal,freight,timber,freighter,industry_train,tanker,traverse,tick_pulse,month_tick,daily_road)
  local clock
  local faults=road_faults_mount[s]
  local initial_tick=daily_road and s.passenger_house_clock and s.passenger_house_clock.counter
  local function fault_date(tick)
    if initial_tick then return s.stock_bus_market.epoch+s.day-(tick<initial_tick+74 and 1 or 0) end
  end
  local freight_ready,ship_ready,industry_ready,tanker_ready
  local growth=town_growth_mount[s]
  local growth_random=growth and function() return rating_runtime.random_u32(s) end
  local tide,plant_trees=coastal_visit(s)
  local machines=s.stock_generated_profile and s.stock_coal_industries and M.industry_machinery(s)
  if s.road_stock_house_supply then
    town_passengers.start(s)
    clock=function(callback)
      if not commercial and not coal and not timber and not growth and not tide and not month_tick and not daily_road then return town_passengers.day(s,callback,{traverse=traverse,tick_pulse=tick_pulse}) end
      local works=growth and growth.world.reconstruction
      local work_state=works and s.stock_town_growth.reconstruction
      local road_ground,road_tick
      local function ground_available(id)
        if not road_ground then road_ground=default_oneway().ground_occupancy(s) end
        return not road_ground[id]
      end
      -- Share the exact source cursor with the sparse industry bindings.
      -- Keep visiting every stock tile in order: only proven no-op
      -- industry/farm callbacks are skipped, not town, water or rail work.
      local width,height=M.W,M.H
      local clock=s.passenger_house_clock
      local exact=width==2^clock.log_x and height==2^clock.log_y
      local industry_phase=s.stock_generated_profile and s.stock_generated_profile.rc1_industry_phase
      local physical_industries
      local coal_tiles,visit_coal
      local timber_tiles,visit_timber,fields,regrowth,visit_field
      local offer_rig=commercial and commercial.offer_rig_passengers
      local function industry_footprints()
        physical_industries=M.stock_industry_order(s,coal,timber)
        coal_tiles,visit_coal,timber_tiles,visit_timber,fields,regrowth,visit_field=nil,nil,nil,nil,nil,nil,nil
        if exact then
          if coal then coal_tiles,visit_coal=coal.landscape(width,height) end
          if timber and timber.landscape then
            timber_tiles,visit_timber,fields,regrowth,visit_field=timber.landscape(width,height)
          end
        end
      end
      industry_footprints()
      local ordered_freight_ratings={
        coal=function(st,dirty)
          if coal and M.road_stop_has(st,"truck") then
            local r=coal.step_rating(st,dirty)
            return r and r.waiting_changed
          end
        end,
        remaining=function(st,dirty)
          if timber then timber.step_rating(st,dirty) end
        end,
      }
      local function landscape(x,z,tick,source)
        local work
        if work_state and (work_state.funded>0 or work_state.active>0) then
          if tick~=road_tick then road_ground=nil;road_tick=tick end
          work=works.visit(s,x+1,z+1,growth_random,ground_available)
        end
        if works and not work then works.decorate(s,x+1,z+1) end
        if tide then tide(x,z,tick) end
        local industry_id=machines and (exact and source+1 or x+z*width+1)
        local completed,prior_gfx,prior_stage
        if industry_id then completed,prior_gfx,prior_stage=machines.phase(industry_id) end
        local _,moved
        if coal_tiles then
          local item=coal_tiles[source]
          if item then _,moved=visit_coal(item,tick) end
        elseif coal then _,moved=coal.tile_visit(x,z,tick) end
        if timber_tiles then
          -- The farm maps are live. A plot planted earlier in this
          -- same source tick must still be visited if it comes next.
          local id=source+1
          if fields and (fields[id] or regrowth and regrowth[id]~=nil) then visit_field(x,z,tick,id) end
          local item=timber_tiles[source]
          if item then _,moved=visit_timber(item,source,tick,offer_rig) end
        elseif timber then
          local _,sent=timber.tile_visit(x,z,tick,offer_rig)
          moved=(moved or 0)+(sent or 0)
        end
        if completed~=nil then
          local cell=s.tiles[industry_id] and s.tiles[industry_id].stock_industry
          if not (completed and industry_phase and timber and s.road_oil and cell
              and (cell.kind=="oil_well" or cell.kind=="wells")) then
            if industry_phase then machines.distribution(industry_id,tick,completed,prior_gfx,prior_stage,moved)
            elseif completed then machines.visit(industry_id,tick) end
          end
        end
      end
      local before_tick=clock.counter
      local month_at=month_tick and before_tick+rating_runtime.day_ticks-1
      local growth_calendar
      if growth and s.stock_generated_profile and s.stock_bus_market then
        local year,month,day=M.date(s)
        if month==1 and day==1 then
          -- The campaign has already incremented s.day, but the RC1
          -- calendar advances before RunTileLoop only on phase zero.
          local midnight=before_tick+rating_runtime.day_ticks
          growth_calendar=function(tick) return tick<midnight and year-1 or year end
        end
      end
      town_passengers.day(s,function(tick,finish_rating)
        if daily_road then daily_road((tick-before_tick)%74,false) end
        if s.stock_effect_vehicles then
          if machines then machines.effects_tick()
          else
            if not M.stock_effect_steps then M.stock_effect_steps=dofile(module_root.."openttd/industry_chimney_effect.lua") end
            M.stock_effect_steps.step(s)
          end
        end
        local ready,events
        if commercial then ready,events=commercial.before(tick) end
        if freighter then freighter.rating(tick) end
        local function vehicle_rail(before_train)
          local register,advance,flushed=rail_tick_broker(s,before_train)
          if freight then freight.after(tick,freight_ready,register) end
          if industry_train then industry_train.after(tick,industry_ready,register) end
          if commercial then commercial.after(tick,ready,events,advance) end
          if advance and not flushed() then advance() end
        end
        if commercial and commercial.interleave_road and not (freight or industry_train or freighter or tanker) then
          callback(tick,vehicle_rail)
        else
          callback(tick)
          vehicle_rail()
        end
        if freighter then freighter.after(tick,ship_ready) end
        if tanker then tanker.after(tick,tanker_ready) end
        if growth and growth.new then
          growth.world.tick(s,tick,growth_random,nil,growth_calendar and growth_calendar(tick))
        end
        if plant_trees then plant_trees(tick) end
        local merged_ratings=commercial and commercial.finish_ratings and finish_rating
        if merged_ratings then
          -- OnTick_Station visits all GoodsEntries before advancing to
          -- the next physical station, including airport acceptance RNG.
          commercial.finish_ratings(tick,finish_rating,ordered_freight_ratings)
        elseif finish_rating then finish_rating() end
        if coal then
          if not merged_ratings then
            for _,view in ipairs(coal.road_stations) do
              local st=s.stations[view.id]
              if st.passenger_rating_phase==0 then coal.step_rating(st) end
            end
          end
          if freight then freight.post(tick) end
          if not physical_industries then coal.after_vehicle_tick(tick) end
        end
        if timber then
          for _,view in ipairs(timber.stations) do
            local st=s.stations[view.id]
            if st and st.passenger_rating_phase==0 and not (merged_ratings and st.mode=="road") then timber.step_rating(st) end
          end
          -- The rail industry station ages and rates before shared
          -- production; that producer has exactly one mixed StationID list.
          if industry_train then industry_train.post(tick) end
          if not physical_industries then timber.after_vehicle_tick(tick)
          else timber.refresh_production_stations(tick) end
        end
        if physical_industries then
          -- OnTick_Industry: physical pool order, then the unconditional
          -- TriggerIndustryAnimation word at each post-decrement 256 boundary.
          for _,row in ipairs(physical_industries) do
            local f=row.firm
            if not f.removed then
              row.binding.produce_one(f,tick)
              if f.counter%256==0 then M.stock_random_u32(s) end
            end
          end
        end
      end,{passenger=commercial and commercial.hooks.passenger,
        mail=commercial and commercial.hooks.mail,landscape_tile=landscape,
        growth=growth and growth.world,growth_calendar=growth_calendar,traverse=traverse,tick_pulse=tick_pulse,
        commercial_ratings=commercial and commercial.finish_ratings,
        animate_industry=machines and function(id,tick) return machines.frame(id,tick) end,
        before_landscape=(month_tick or daily_road or machines or timber and timber.animate) and function(tick)
          if not s.stock_world_animations then
            if machines then machines.animate(tick) end
            if timber and timber.animate then timber.animate(tick) end
          end
          if daily_road then daily_road((tick-before_tick+1)%74,true) end
          if tick==month_at then
            local changed=month_tick()
            if changed then
              coal,freight,timber,freighter,industry_train,tanker=changed.coal,changed.freight,changed.timber,
                changed.freighter,changed.industry_train,changed.tanker
              machines=s.stock_generated_profile and s.stock_coal_industries and M.industry_machinery(s)
              industry_footprints()
            end
          end
        end})
    end
  else
    generate_passengers(s,legacy_supply)
    local previous=s.stock_load_tick or (s.day-1)*74
    clock=function(callback)
      for i=1,74 do
        rating_runtime.advance(s,1)
        callback(previous+i)
      end
    end
  end
  local function begin(v,st,tick)
    local _,order
    if not v.road_implicit_leg then _,order=current_station_order(v,st) end
    if v.stop_requested then
      -- Stop at the next destination after unloading, don't strand a
      -- scheduled stop indefinitely waiting for additional full cargo.
      order={action=order and order.action,no_load=true,full=false}
    end
    local ok=station_service.begin(s,st,v,order,tick)
    if not ok then v.running=false;v.status="Incompatible road stop" end
  end
  for _,v in pairs(s.fleet) do
    if stock_managed(s,v) and v.running and not v.route and not v.depot then
      local st=s.stations[v.station]
      if st then stock_seed_parked_pose(s,v,st) end
    end
  end
  local coastal_road=s.stock_coastal_flood and road_flood_rules()
  local worked,samples=road_clock().live_day(s,clock,{
    live_projection=tick_pulse~=nil,
    physical_order=commercial and commercial.interleave_road or s.stock_pool_authority and not shared_tram_clock[s],
    companion=shared_tram_clock[s],
    retire=coastal_road and function(v)
      v.road_vehicle_ticks=(v.road_vehicle_ticks or 0)+1
      if not v.road_flood_age then return false end
      local remove
      v.road_flood_age,remove=coastal_road.road_wreck_tick(v.road_flood_age,v.road_vehicle_ticks)
      if remove then
        road_clock().bay.retire_wreck(s,v)
        if v.order_group then orders_module().release(s,v) end
      end
      return remove
    end,
    economy=function(tick)
      local ready={}
      local ids=commercial and commercial.road_departures and commercial.road_departures(tick) or station_service.tick(s,tick)
      for _,id in ipairs(ids) do ready[id]=true end
      if freight then freight_ready=freight.before(tick) end
      if industry_train then industry_ready=industry_train.before(tick) end
      if freighter then ship_ready=freighter.before(tick) end
      if tanker then tanker_ready=tanker.before(tick) end
      return ready
    end,
    before=function(v,tick,leave)
      if not stock_managed(s,v) then return end
      local bus=stock_bus(v)
      if bus and v.running then road_bus_catalog().tick(bus) end
      if faults and faults.tick(v,tick) then return true end
      if not v.running then return end
      local cargo=M.road_freight_cargo(v.engine)
      if cargo=="coal" then v.stock_coal_running_ticks=(v.stock_coal_running_ticks or 0)+1 end
      if cargo=="mail" and v.engine~="mail_van" then v.stock_mail_running_ticks=(v.stock_mail_running_ticks or 0)+1 end
      if industry_road_cargo[cargo] or goods_engine(v.engine) then v.stock_timber_running_ticks=(v.stock_timber_running_ticks or 0)+1 end
      if v.route then
        local target,index,vias
        if v.road_order_override and not v.road_return_depot then
          target,index,vias=road_order_leg(s,v,v.road_order_override)
        end
        if target then
          if target.id==v.dest and #vias==0 and not v.road_via_pending then
            v.dest_index,v.road_order_override=index,nil
          else
            local state=v.road_speed_state
            local frame=state and M.road_motion_frame(s,v)
            local tile=frame and frame[4]
            if frame and not state.depot_wait and not (s.tiles[tile] and s.tiles[tile].level_crossing) and
                state.order_retry_tile~=tile then
              state.order_retry_tile=tile
              local r=road_routing()
              local route,_,td,cost,frames,bays=source_route.from_live_frame(s,v,frame,target.id,r.occupancy(M,s),vias)
              if route then
                launch(s,v,route,target.id,index,td,cost,frames,bays)
                state.index,state.waiting,state.oneway_tile,state.order_retry_tile=1,nil,nil,nil
                v.road_speed_state,v.road_order_override=state,nil
                v.road_via_pending=#vias>0 and vias or nil
              end
            end
          end
        end
        return
      end
      if #v.orders==0 then v.running=false;v.status="No orders";return end
      if v.depot then
        local order=v.road_order_override or v.road_depot_resume or 1
        if not v.orders[order] then order=1 end
        local to,index,vias=road_order_leg(s,v,order)
        local route,td,cost,frames,bays=M.path(s,depot_endpoint(s,v.owner,v.depot),to,"road",v.owner,nil,v,vias)
        if route and frames then
          launch(s,v,route,to.id,index,td,cost,frames,bays)
          v.road_via_pending=#vias>0 and vias or nil
          v.road_depot_resume,v.road_order_override=nil,nil;v.last_departure=s.day;v.last_departure_tick=tick
        else v.status="No road from depot" end
        return
      end
      local st=s.stations[v.station]
      if not st then v.running=false;v.status="Missing terminal";return end
      if leave and v.load_state then
        station_service.leave(s,v,tick)
        if not v.running then return end
      end
      if v.load_state then return end
      local resume=v.road_implicit_leg
      if resume then
        -- BeginLoading(false) leaves the manual destination intact.
        -- Reuse the actual raster cursor, heading and progress; routing
        -- from the platform center would move the vehicle backwards.
        v.road_implicit_leg=nil
        v.road_speed_state,v.road_via_pending=resume.motion,resume.vias
        v.road_motion_frames,v.road_bay_branch=resume.frames,resume.bays
        v.road_leg_td,v.road_route_cost=resume.td,resume.cost
        v.route,v.dest,v.dest_index=resume.route,resume.dest,resume.index
        v.road_stop_pose,v.road_stop_motion,v.stock_loading_complete=nil,nil,nil
        v.station,v.loaded_at,v.status=nil,nil,"En route"
        return
      end
      if v.stock_loading_complete~=st.id then
        stock_seed_parked_pose(s,v,st)
        begin(v,st,tick)
        return
      end
      local route,td,cost,frames,dest,index,bays,vias=stock_next_plan(s,v,st)
      if not route then v.status="No path";return end
      local old,new=v.road_stop_pose,frames[1]
      if old and (old[1]~=new[1] or old[2]~=new[2] or old[3]~=new[3] or old[4]~=new[4]) then
        v.status="Road exit no longer matches the stopped pose"
        return
      end
      launch(s,v,route,dest,index,td,cost,frames,bays);v.road_order_override=nil
      v.road_via_pending=#vias>0 and vias or nil
      v.last_departure=s.day;v.last_departure_tick=tick
    end,
    intermediate=function(v,f)
      if v.road_via_pending then return end -- current stock order is a non-stopping waypoint
      local tile=s.tiles[f[4]]
      local id=tile.station
      if not id or id==v.dest or tile.owner~=v.owner then return end
      local st=s.stations[id]
      if M.road_stop_tile_kind(st,f[4],tile)~=(v.cargo=="passenger" and "bus" or "truck") then return end
      local order=v.orders[v.dest_index]
      local flags=order and order.non_stop or 0
      if M.road_station_order_should_stop("goto_station",v.dest,flags,false,v.road_last_station,id) then return id end
    end,
    choose_junction=function(v,c,old,nominal)
      local id=nominal[4]
      local to=s.tiles[id]
      local bits=to and to.road_bits
      if not to or to.build~="road" or to.level_crossing or
          (bits~=7 and bits~=11 and bits~=13 and bits~=14 and bits~=15) then
        -- A planned choice reduced to a single track must be discarded.
        local expected=c.junction_cache and c.junction_cache[1]
        if expected and expected.tile==id then c.junction_cache=nil end
        return
      end
      if c.lane_pose or c.overtaking and c.overtaking~=0 then return end
      if c.junction_tile==id and c.junction_approach==old[4] and c.junction_version==s.topology then return end
      if c.junction_destination~=v.dest or not c.junction_cache then c.junction_cache={} end
      -- Town edits elsewhere do not invalidate a still-reachable choice.
      -- The chooser checks the cached tile and the actual available tracks.
      c.junction_tile,c.junction_approach,c.junction_version,c.junction_destination=id,old[4],s.topology,v.dest
      local r=road_routing()
      local path,frames,bays,td,cost=source_route.at_junction(s,v,old,id,r.occupancy(M,s),c.junction_cache)
      if not frames then return end
      v.route,v.road_motion_frames,v.road_bay_branch,v.road_leg_td,v.road_route_cost=path,frames,bays,td,cost
      c.index=1
      return frames
    end,
    entered_transit=function(v,tick)
      if faults and tick then faults.service(v,tick,fault_date(tick)) end
      M.stock_road_vehicle_random(s,v,"depot")
    end,
    exited=faults and function(v,tick) faults.service(v,tick,fault_date(tick)) end or nil,
    arrive=function(v,tick,frame,stop_motion)
      if not stock_managed(s,v) then return false end
      if v.road_return_depot then
        local depot=assert(depot_endpoint(s,v.owner,v.road_return_depot),"Ordered road depot changed during its protected approach")
        assert(frame[4]==depot.tile and frame[15]==road_routing().motion.DEPOT_STOP)
        v.depot,v.last_depot_entry_tick=depot.tile,tick
        if stop_motion then
          -- RoadVehLeaveDepot consumes a tick while unhiding and
          -- sets only cur_speed: it keeps the sub-speed and progress.
          v.road_stop_motion={subspeed=stop_motion.subspeed,progress=stop_motion.progress,
            incline=0,ticks=stop_motion.ticks,depot=true}
        end
        v.road_return_depot,v.road_stop_pose,v.road_speed_state,v.road_motion_frames=nil,nil,nil,nil
        v.road_bay_branch,v.road_leg_td,v.road_arrival_td,v.route,v.dest,v.dest_index=nil,nil,nil,nil,nil,nil
        local auto=v.road_auto_service
        v.road_auto_service=nil
        if auto then v.road_depot_resume=auto.index end
        v.progress,v.running,v.status=0,auto~=nil,auto and "Serviced; resuming route" or "Stopped in depot"
        if faults then faults.service(v,tick,fault_date(tick)) end
        M.stock_road_vehicle_random(s,v,"depot")
        return true,true
      end
      if s.stock_road_bays then road_clock().bay.arrive(s,v,frame) end
      local actual=s.tiles[frame[4]].station
      if actual~=nil and actual~=v.dest and stop_motion then
        stop_motion.arrival_pose=nil
        v.road_implicit_leg={frames=v.road_motion_frames,motion=stop_motion,route=v.route,dest=v.dest,
          index=v.dest_index,td=v.road_leg_td,cost=v.road_route_cost,bays=v.road_bay_branch,vias=v.road_via_pending}
        v.station=actual
      else
        v.station,v.index=v.dest,v.dest_index
      end
      v.road_last_station=v.station
      v.road_via_pending=nil
      v.last_road_arrival_tick=tick
      local td=frame[6]
      v.road_arrival_td,v.road_leg_td=td>=64 and td<80 and td-64 or v.road_leg_td,nil
      v.road_stop_pose=frame
      if stop_motion then
        v.road_stop_motion={subspeed=stop_motion.subspeed,progress=stop_motion.progress,
          incline=stop_motion.incline,ticks=stop_motion.ticks}
      end
      v.road_motion_frames=nil;v.road_speed_state=nil;v.road_bay_branch=nil
      v.route=nil;v.dest=nil;v.dest_index=nil;v.progress=0
      local st=s.stations[v.station]
      if st and news_mount[s] then news_mount[s]("road",v.owner,st.id,frame[4],v.cargo) end
      if st and v.road_order_override~=nil then
        -- A bridge, passing maneuver or depot exit may have prevented an
        -- exact live splice. Finish its physical approach without cargo
        -- actions, then use the selected order from the settled frame.
        v.stock_loading_complete=st.id
        if #v.orders==0 then v.running=false;v.status="No orders" end
      elseif st then begin(v,st,tick) else v.running=false;v.status="Missing terminal" end
      return true
    end,
    age=function(v,tick)
      if stock_managed(s,v) then station_service.age_vehicle(s,v,tick) end
    end,
  })
  road_visual[s]=samples
  return worked
end
function M.position(s,v)
  if v.route then
    if M.road_stock_service_active(s) and v.road_speed_state and v.road_motion_frames then
      -- The location of a hidden transit vehicle is still its depot
      -- for commands and guards, but never an exposed viewport pose.
      local c=v.road_speed_state
      local frame=c.lane_pose or v.road_motion_frames[c.index]
      if frame then return frame[4] end
    end
    if M.vehicles[v.engine].mode=="air" then
      local x,z=M.xy(v.route[1]);local u,w=M.xy(v.route[#v.route])
      local f=math.min(1,(v.progress-1)/math.max(1,#v.route-1))
      return M.id(math.floor(x+(u-x)*f+0.5),math.floor(z+(w-z)*f+0.5))
    end
    return v.route[math.min(#v.route,math.floor(v.progress))]
  end
  return v.depot or (s.stations[v.station] and s.stations[v.station].tile)
end
function M.stock_industry_order(s,coal,timber)
  local stock=s.stock_economy_subsidies
  if not (stock and s.stock_generated_profile and s.stock_generated_profile.rc1_industry_phase) then return end
  local ordered={}
  for id,key in pairs(stock.industry_slots) do
    local chain,n=key:match("^([^:]+):(%d+)$")
    local binding=chain=="coal" and coal or chain~="coal" and timber
    local registry=chain and s["stock_"..chain.."_industries"]
    local firm=registry and registry[tonumber(n)]
    if firm and binding then ordered[#ordered+1]={id=id,firm=firm,binding=binding,chain=chain} end
  end
  table.sort(ordered,function(a,b)return a.id<b.id end)
  return ordered
end
-- RC1 Industry monthly timer rolls production and closure before the
-- Station and Town timers on the same economy tick.
function M.stock_industry_month(s,coal,timber,y,month)
  local ordered=M.stock_industry_order(s,coal,timber)
  if ordered then
    local stock_options={original=s.stock_industry_original_economy==true,smooth=true}
    for _,row in ipairs(ordered) do row.binding.month_one(row.firm,y*12+month,y,stock_options) end
    s.changed=s.changed or {}
    if M.road_oil_active(s) then
      for _,id in ipairs(oil.world.sweep_closed(s)) do s.changed[#s.changed+1]=id end
    end
    if M.road_heavy_active(s) then
      for _,id in ipairs(farm.heavy.sweep_closed(s)) do s.changed[#s.changed+1]=id end
    end
    if M.road_farm_active(s) then
      for _,id in ipairs(farm_world.sweep_closed(s)) do s.changed[#s.changed+1]=id end
    end
    return
  end
  if coal then coal.month(y,{frozen=s.stock_coal_frozen}) end
  -- The placed forest/sawmill preview keeps its scenario industries
  -- active. Dynamic site opening/closure is a separate world command.
  if timber then
    if timber.mixed then
      local oil_month={smooth=true,frozen=s.stock_oil_frozen==true}
      local farm_month={smooth=s.stock_farm_smooth~=false,frozen=s.stock_farm_frozen==true}
      local timber_month={frozen=true}
      timber.month(y*12+month,y,{policy={oil_well=oil_month,oil_refinery=oil_month,
        farm=farm_month,factory=farm_month,forest=timber_month,sawmill=timber_month}})
      if M.road_oil_active(s) then
        s.changed=s.changed or {}
        for _,id in ipairs(oil.world.sweep_closed(s)) do s.changed[#s.changed+1]=id end
      end
      if M.road_heavy_active(s) then
        s.changed=s.changed or {}
        for _,id in ipairs(farm.heavy.sweep_closed(s)) do s.changed[#s.changed+1]=id end
      end
      if M.road_farm_active(s) then
        s.changed=s.changed or {}
        for _,id in ipairs(farm_world.sweep_closed(s)) do s.changed[#s.changed+1]=id end
      end
    elseif M.road_oil_active(s) then
      s.stock_oil_month=(s.stock_oil_month or 0)+1
      timber.month(s.stock_oil_month,y,{smooth=true,frozen=s.stock_oil_frozen==true})
      s.changed=s.changed or {}
      for _,id in ipairs(oil.world.sweep_closed(s)) do s.changed[#s.changed+1]=id end
    elseif M.road_farm_active(s) then
      s.stock_farm_month=(s.stock_farm_month or 0)+1
      timber.month(s.stock_farm_month,y,{smooth=s.stock_farm_smooth~=false,frozen=s.stock_farm_frozen==true})
      s.changed=s.changed or {}
      for _,id in ipairs(farm_world.sweep_closed(s)) do s.changed[#s.changed+1]=id end
    else
      -- Calendar months are not 30 days long when the stock vehicle
      -- market is mounted. One stable ordinal for the actual month.
      timber.month(y*12+month,y,{frozen=true})
    end
  end
end
-- Binding a freshly placed industry must not rerun economy-day vehicle
-- charges, nor reset the first 73 ticks of presentation samples.
function M.bind_stock_industry_day(s,first,live,refresh)
  coal_day_bindings[s],timber_day_bindings[s]=nil,nil
  local coal,freight,timber,freighter,industry_train
  if M.rail_coal_active(s) then
    town_passengers.start(s)
    freight=rail_coal.day(s,paid_rail_runs[s],first or s.passenger_house_clock.counter+1,live,refresh)
  end
  if M.ship_coal_active(s) then
    town_passengers.start(s)
    freighter=ship_coal.day(s,first or s.passenger_house_clock.counter+1,live,refresh)
  end
  if M.road_coal_active(s) or freight or freighter then
    passenger_modules()
    coal=coal_binding(s,true,freight,freighter)
    coal_day_bindings[s]=coal
  end
  if M.road_timber_active(s) or M.road_farm_active(s) or M.road_oil_active(s) or M.road_heavy_active(s) or M.road_bank_active(s) then
    passenger_modules()
    timber=timber_binding(s)
    timber_day_bindings[s]=timber
    if timber and timber.rail then
      town_passengers.start(s)
      first=first or s.passenger_house_clock.counter+1
      if timber.mixed or timber.rail_multi then
        local rail=timber.rail
        local days={}
        if rail.oil then days[#days+1]=oil.runtime.day(s,paid_rail_runs[s],first,rail.oil,live,refresh) end
        if rail.goods then days[#days+1]=goods.runtime.day(s,paid_rail_runs[s],first,rail.goods,live,refresh) end
        for _,cargo in ipairs(FreightKinds.profile_order) do
          if rail[cargo] then days[#days+1]=profiled.runtime[cargo].day(s,paid_rail_runs[s],first,rail[cargo],live,refresh) end
        end
        if #days>0 then
          industry_train={
            before=function(tick)
              local ready={}
              for i,q in ipairs(days) do ready[i]=q.before(tick) end
              return ready
            end,
            after=function(tick,ready,register)
              for i,q in ipairs(days) do q.after(tick,ready[i],register) end
            end,
            post=function(tick)
              for _,q in ipairs(days) do q.post(tick) end
            end,
          }
        end
      else
        local controller=M.rail_goods_active(s) and goods.runtime or oil.runtime
        industry_train=controller.day(s,paid_rail_runs[s],first,timber.rail,live,refresh)
      end
    end
  end
  return {coal=coal,freight=freight,timber=timber,freighter=freighter,industry_train=industry_train}
end
function M.bind_stock_industry_ships(s,industry,first,live,refresh)
  local timber=industry.timber
  local tanker=oil.ship and timber and oil.ship.day(s,timber,first,live,refresh)
  local dry=ship_coal and ship_coal.goods_day(s,timber,first,live,refresh)
  if dry and tanker then
    local oil_day=tanker
    tanker={before=function(tick) return {oil_day.before(tick),dry.before(tick)} end,
      after=function(tick,ready) oil_day.after(tick,ready[1]);dry.after(tick,ready[2]) end}
  elseif dry then tanker=dry end
  industry.tanker=tanker
end
function M.daily(s,traverse,tick_pulse,openings)
  local live=tick_pulse~=nil
  s.day=s.day+1
  if s.retired_road_stations or s.retired_road_waypoints then M.road_station_retirement().expire(s) end
  local faults=road_faults_mount[s]
  local stock_dates=s.stock_generated_profile and s.stock_bus_market and s.road_stock_house_supply
    and M.road_stock_service_active(s)
  local automatic=faults and faults.auto and function(v,f,diff,date,rnd)
    automatic_road_service(s,faults,v,f,diff,date,rnd)
  end or nil
  if faults and not stock_dates and M.road_stock_service_active(s) then
    faults.daily(automatic)
  end
  local y,month,calendar_day=M.date(s)
  local new_month=s.stock_bus_market and calendar_day==1 or not s.stock_bus_market and s.day%30==0
  local stock_service=M.road_stock_service_active(s)
  local exact_economy=s.stock_generated_profile and s.stock_bus_market and s.road_stock_house_supply and stock_service
  local growth=town_growth_mount[s]
  local town_month
  if growth then
    growth.world.prepare_day(s)
    town_month=growth.new and growth.world.month_due(s)
  end
  local function roll_town_month()
    M.stock_station_acceptance_history.rotate_host(s,FreightKinds.all)
    local random=function() return rating_runtime.random_u32(s) end
    if s.stock_economy_subsidies then M.stock_subsidy_authority.month(s,town_month,random) end
    growth.world.month(s,town_month,random)
  end
  if town_month and not exact_economy then roll_town_month() end
  if s.corner_grid then
    load_road_rules()
    for _,c in pairs(s.companies) do
      if c.terraform_limit then c.terraform_limit=landscape_rules.replenish(c.terraform_limit,74) end
      if c.clear_limit then c.clear_limit=clear_area_rules.replenish(c.clear_limit,74) end
      if c.stock_tree_plant_limit then c.stock_tree_plant_limit=stock_plant_rules().replenish(c.stock_tree_plant_limit,74) end
      if c.stock_object_limit then c.stock_object_limit=land_rules().replenish(c.stock_object_limit,74) end
    end
  end
  local road_supply=s.road_economy and {}
  for _,site in ipairs(s.sites) do
    local f=M.facilities[site.kind]
    for _,k in ipairs(M.cargo_order) do
      local n=f.produces[k]
      if n then
        if site.population then n=n+math.floor(site.population/(k=="mail" and 100 or 48)) end
        site.stock[k]=math.min(1200,(site.stock[k] or 0)+n)
        site.produced[k]=(site.produced[k] or 0)+n
        if road_supply and k=="passenger" then road_supply[site.id]=n end
      end
    end
  end
  if stock_service then passenger_modules();town_passengers.start(s) end
  local first=s.passenger_house_clock and s.passenger_house_clock.counter+1
  local industry=M.bind_stock_industry_day(s,first,live,false)
  for _,v in pairs(s.fleet) do
    if coal_engine(v.engine) or industry_truck(v.engine) or priced_mail(v.engine) then
      local is_timber=industry_truck(v.engine)
      local is_mail=priced_mail(v.engine)
      local enabled=(is_mail and road_mail(s,v)) or (not is_timber and not is_mail and industry.coal) or is_timber and industry.timber and
        (M.road_farm_active(s) and farm_engine(v.engine) or M.road_timber_active(s) and timber_engine(v.engine)
          or M.road_oil_active(s) and oil_engine(v.engine) or
            (M.road_heavy_active(s) or M.road_bank_active(s)) and heavy_engine(v.engine))
      local key=is_mail and "stock_mail_running_ticks" or is_timber and "stock_timber_running_ticks" or "stock_coal_running_ticks"
      local resume=is_mail and "stock_mail_resume" or is_timber and "stock_timber_resume" or "stock_coal_resume"
      -- Running-tick cost at the next economy day, not an invented fee
      -- for only moving. Source stores 8-bit corporate money fractions.
      if v[key] and v[key]>0 then
        local c=M.company(s,v.owner)
        local amount=math.floor(1600*M.vehicles[v.engine].running_factor*v[key]/(365*74))
        local old=c.stock_money_fraction or 0
        local remainder=(old-amount%256)%256
        c.stock_money_fraction=remainder
        local whole=math.floor(amount/256)+(remainder>old and 1 or 0)
        if whole~=0 then debit(c,whole,"road_run");v.expense=v.expense+whole;HQStats.record(s,v,-whole) end
        v[key]=0
      end
      if not enabled then
        if v.load_state then abort_stock_stop(s,v) end
        if v.running then
          v[resume]=true;v.running=false
          v.status=is_mail and "Stock mail unavailable" or is_timber and "Stock industry freight disabled" or "Stock coal disabled"
        end
        v.stock_aged_tick=nil
      elseif v[resume] then
        v[resume]=nil;v.running=true
      end
    end
  end
  if not stock_service and s.stock_load_tick then
    -- Turning a preview off between saves must not leave reserved cargo
    -- inaccessible to the legacy station path or strand an aging clock.
    for _,v in pairs(s.fleet) do
      if v.load_state then abort_stock_stop(s,v) end
      if v.stock_aged_tick then
        v.passenger_age_ticks=185-(v.cargo_age_counter or 1)
        v.stock_aged_tick=nil;v.cargo_age_counter=nil
      end
      v.stock_loading_complete=nil
    end
    s.stock_load_tick=nil
  end
  local function settle_bus(v)
    local c=M.company(s,v.owner)
    local account=stock_bus(v)
    -- economy.cpp RecomputePrices: RC1's default Low running-cost
    -- category is 6/8 of the normalised Medium base.
    local annual_fp=stock_dates and math.floor(account.annual_fp*6/8) or nil
    local whole,remainder=road_bus_catalog().day(account,c.stock_money_fraction or 0,annual_fp)
    c.stock_money_fraction=remainder
    if whole~=0 then debit(c,whole,"road_run");v.expense=v.expense+whole;HQStats.record(s,v,-whole) end
  end
  local regal_ids={}
  for id,v in pairs(s.fleet) do if stock_bus(v) then regal_ids[#regal_ids+1]=id end end
  table.sort(regal_ids)
  local daily_road
  if stock_dates then
    local slot={}
    local function add(ev)
      local phase=ev.id%74
      local group=slot[phase] or {};slot[phase]=group
      group[#group+1]=ev
    end
    for id,v in pairs(s.fleet) do
      if stock_bus(v) or v.stock_road_freight then add({id=v.stock_pool_id or id-1,road=id}) end
    end
    local rail=paid_rail_runs[s]
    if rail and rail.stock_fault_days then
      for _,ev in ipairs(rail.stock_fault_days(s)) do add(ev) end
    end
    local ship=paid_ferry_runs[s]
    if ship and ship.stock_fault_days then
      for _,ev in ipairs(ship.stock_fault_days(s)) do add(ev) end
    end
    local air=paid_air_runs[s]
    if air and air.stock_fault_days then
      for _,ev in ipairs(air.stock_fault_days(s)) do add(ev) end
    end
    for _,group in pairs(slot) do table.sort(group,function(a,b) return a.id<b.id end) end
    if next(slot) then
      -- RunCalendar/EconomyVehicleDayProc in vehicle.cpp. A campaign day
      -- represents phase 1..73 of yesterday, then phase 0 of its new date.
      -- Ordinary road IDs are one-based in this adapter.
      local new_date=s.stock_bus_market.epoch+s.day
      daily_road=function(phase,calendar)
        local group=slot[phase]
        if not group then return end
        local date=new_date-(phase==0 and 0 or 1)
        for _,entry in ipairs(group) do
          local v=entry.road and s.fleet[entry.road]
          if v then
            if calendar then
              if faults then faults.calendar(v) end
            else
              if faults then faults.economy(v,date,automatic) end
              if stock_bus(v) then settle_bus(v) end
            end
          elseif calendar and entry.calendar then entry.calendar()
          elseif not calendar and entry.economy then entry.economy(date) end
        end
      end
    end
  else
    for _,id in ipairs(regal_ids) do settle_bus(s.fleet[id]) end
  end
  local stock_work,month_tick,industries_rolled
  if exact_economy and (openings or town_month or new_month or s.stock_disaster_delay) then
    -- Advance the 74-tick batch into the new date after animation, before
    -- the same tick's tile, loading, vehicle and town work.
    month_tick=function()
      local first_on_new_date=s.passenger_house_clock.counter+1
      if s.stock_disaster_delay then
        if s.stock_disaster_delay==1 then
          local rules=dofile(module_root.."openttd/world_startup_rc1.lua")
          s.stock_disaster_delay=rules.disaster_day(1,function() return M.stock_random_u32(s) end)
        else s.stock_disaster_delay=s.stock_disaster_delay-1 end
      end
      local opened=openings and openings("day")
      if opened then
        M.clear_live_sea_cache(s)
        industry=M.bind_stock_industry_day(s,first_on_new_date,live,true)
      end
      local topology=s.topology
      if new_month then
        M.stock_company_month(s,y,month)
        if openings then openings("month") end
        M.stock_industry_month(s,industry.coal,industry.timber,y,month)
        industries_rolled=true
      end
      if s.topology~=topology then
        -- Closures can invalidate a station's accepting catchment.
        M.clear_live_sea_cache(s)
        industry=M.bind_stock_industry_day(s,first_on_new_date,live,true)
        opened=true
      end
      if opened then M.bind_stock_industry_ships(s,industry,first_on_new_date,live,true) end
      if town_month then roll_town_month() end
      return opened and industry or nil
    end
  end
  local commercial=paid_transport_day(s,live,stock_service)
  if stock_service then
    passenger_modules()
    town_passengers.start(s)
    M.bind_stock_industry_ships(s,industry,first,live,false)
    stock_work=stock_station_day(s,road_supply,commercial,industry.coal,industry.freight,industry.timber,industry.freighter,industry.industry_train,industry.tanker,traverse,tick_pulse,month_tick,daily_road)
  elseif commercial then
    town_passengers.day(s,function(tick,finish_rating)
      local ready,events=commercial.before(tick)
      commercial.after(tick,ready,events)
      if commercial.finish_ratings and finish_rating then commercial.finish_ratings(tick,finish_rating)
      elseif finish_rating then finish_rating() end
    end,{passenger=commercial.hooks.passenger,mail=commercial.hooks.mail,
      landscape_tile=coastal_visit(s),traverse=traverse,
      growth=commercial.finish_ratings and town_growth_mount[s] and town_growth_mount[s].world,
      commercial_ratings=commercial.finish_ratings})
  elseif road_supply then
    passenger_modules()
    if s.road_stock_house_supply then
      town_passengers.day(s,nil,{landscape_tile=coastal_visit(s),traverse=traverse})
    else
      rating_runtime.advance(s,rating_runtime.day_ticks)
      generate_passengers(s,road_supply)
    end
  end
  local moving,ready={},{}
  local traffic={claims={},lanes={},waiting={}}
  local limits={}
  for id,v in pairs(s.fleet) do
    if stock_service and stock_managed(s,v) then
      if stock_work[id] then
        local e=M.vehicles[v.engine]
        if not stock_bus(v) and not coal_engine(v.engine) and not priced_mail(v.engine) and not industry_truck(v.engine) then
          debit(M.company(s,v.owner),e.daily,"road_run");v.expense=v.expense+e.daily;HQStats.record(s,v,-e.daily)
        end
        if not stock_bus(v) then v.condition=math.max(30,v.condition-0.06) end
      end
    elseif not stock_bus(v) and not coal_engine(v.engine) and not priced_mail(v.engine) and not industry_truck(v.engine) then
      if road_passenger(s,v) then passenger_modules().age_vehicle(v,1)
      elseif road_mail(s,v) then passenger_modules();mail_runtime.age_vehicle(v,1) end
      if v.route then
        moving[#moving+1]=id
        if M.vehicles[v.engine].mode=="rail" then reserve(s,traffic,v) end
      elseif v.running then
        ready[#ready+1]=id
        if v.rail_wait_key then traffic.waiting[v.rail_wait_key]=true end
      end
    end
  end
  for _,lane in pairs(traffic.lanes) do
    table.sort(lane,function(a,b)
      return a.progress==b.progress and a.id<b.id or a.progress>b.progress
    end)
    for i=2,#lane do limits[lane[i].id]=lane[i-1].progress-HEADWAY end
  end
  table.sort(moving)
  table.sort(ready,function(a,b)
    local av=s.fleet[a];local bv=s.fleet[b]
    local al=av.last_departure or -1;local bl=bv.last_departure or -1
    return al==bl and a<b or al<bl
  end)
  if not s.road_stock_clock then road_visual[s]=nil end
  local road_progress={}
  if stock_service then
    -- Non-cargo road previews still use the shared movement run, but
    -- retain their own old daily arrival policy.
    for _,id in ipairs(moving) do
      if stock_work[id] then road_progress[id]=s.fleet[id].progress end
    end
  elseif s.road_stock_clock then road_progress=advance_road(s,moving) end
  for _,id in ipairs(moving) do
    local v=s.fleet[id];local e=M.vehicles[v.engine]
    local c=M.company(s,v.owner);debit(c,e.daily,e.mode=="rail" and "rail_run" or e.mode=="water" and "ship_run" or "road_run");v.expense=v.expense+e.daily;HQStats.record(s,v,-e.daily)
    v.condition=math.max(30,v.condition-0.06)
    local desired=road_progress[id] or v.progress+e.speed*(0.55+v.condition*0.0045)
    local blocked,oneway_blocked=false,false
    if e.mode=="road" and not road_progress[id] and (next(s.level_crossing_tiles or {}) or s.road_oneway_revision) then
      for _,id in ipairs(v.route) do
        if M.crossing_protected(s,id) then desired=v.progress;blocked=true;break end
        if road_sign(s.tiles[id])~=0 or s.road_oneway_removed and s.road_oneway_removed[id] then
          desired=v.progress;oneway_blocked=true;break
        end
      end
    end
    local ceiling=limits[id]
    if ceiling and desired>ceiling then
      v.progress=math.max(v.progress,ceiling)
      v.status="Following train"
    else
      v.progress=desired
      local waiting=v.road_speed_state and v.road_speed_state.waiting
      v.status=blocked and "Road crossing needs a stock motion route" or
        oneway_blocked and "One-way road needs a stock motion route" or
        waiting=="roadworks" and "Waiting for roadworks" or waiting=="oneway" and "Waiting at one-way road" or waiting=="crossing" and "Waiting at level crossing" or
        waiting=="depot" and "Waiting in depot" or waiting=="bay" and "Waiting for a free bay"
        or waiting=="junction" and "Waiting for junction clearance"
        or waiting=="road" and "Following traffic" or "En route"
    end
    if v.progress>=#v.route then
      v.station=v.dest;v.index=v.dest_index
      v.road_arrival_td=v.road_leg_td;v.road_leg_td=nil
      v.road_stop_pose=v.road_motion_frames and v.road_motion_frames[#v.road_motion_frames]
      v.road_motion_frames=nil;v.road_speed_state=nil
      v.route=nil;v.dest=nil;v.dest_index=nil;v.progress=0
      v.status="At terminal"
      local st=s.stations[v.station];local order=v.orders[v.index]
      if st and v.road_order_override==nil then
        local action=order and order.action or "normal"
        visit_station(s,st,v,action)
        unload_at(s,st,v,action);v.loaded_at=st.id
        if action~="transfer" and action~="unload" then
          if road_passenger(s,v) then rating_runtime.observe_loading(s,st,v,e.capacity-v.units)
          elseif road_mail(s,v) then mail_runtime.observe_loading(s,st,v,e.capacity-v.units) end
        end
      end
      if v.stop_requested then v.running=false;v.stop_requested=nil;v.status="Stopped" end
    end
  end
  for _,id in ipairs(ready) do
    local v=s.fleet[id];idle_or_plan(s,v,traffic)
    if v.route then v.last_departure=s.day end
  end
  if new_month then
    if not industries_rolled then M.stock_industry_month(s,industry.coal,industry.timber,y,month) end
    s.changed=s.changed or {}
    for _,site in ipairs(s.sites) do
      if not growth and site.population and site.service>=12 then
        local previous=site.population
        site.population=site.population+math.min(32,math.floor(site.service/12))
        if math.floor(site.population/90)>math.floor(previous/90) then
          local a,b=M.xy(site.tile)
          local slots={}
          for radius=1,4 do
            for dz=-radius,radius do
              for dx=-radius,radius do
                if math.abs(dx)+math.abs(dz)==radius then
                  local id=M.id(a+dx,b+dz)
                  local t=id and s.tiles[id]
                  if t and t.terrain=="grass" and not t.site and not t.stock_industry and not t.stock_landmark and not t.house and not t.build and not t.tram and not t.ship and not t.airfield then
                    slots[#slots+1]=id
                  end
                end
              end
            end
            if #slots>0 then break end
          end
          if #slots>0 then
            local at=slots[(s.seed+s.day+site.id)%#slots+1]
            s.tiles[at].house=true;s.tiles[at].wood=nil
            s.changed[#s.changed+1]=at
          end
        end
      end
      site.service=0
    end
    local upkeep
    if not exact_economy then
      upkeep={}
      for _,tile in ipairs(s.tiles) do
        local legacy=tile.build and M.tools[tile.build]
        if tile.owner and legacy and legacy.price then
          upkeep[tile.owner]=(upkeep[tile.owner] or 0)+math.max(1,math.floor(legacy.price*.003))
        end
      end
    end
    for owner,c in pairs(s.companies) do
      if upkeep then
        debit(c,math.floor(c.loan*0.004),"loan_interest")
        if upkeep[owner] then debit(c,upkeep[owner],"property") end
        M.stock_company_quarter(s,owner,c,y,month)
      end
      for sid,r in pairs(c.rating) do c.rating[sid]=math.max(10,r-2) end
      table.insert(c.history,1,{day=s.day,revenue=c.month_rev,expenses=c.month_exp,cash=c.cash})
      if #c.history>24 then table.remove(c.history) end
      c.month_rev=0;c.month_exp=0
      if c.cash<0 then push(s,owner.." is overdrawn. Review the Finance ledger.") end
    end
    if s.stock_bus_market then
      for _,id in ipairs(road_bus_catalog().order) do
        local model=M.stock_road_offer(s,id)
        local old=model and M.engine_calendar.snapshot(s.stock_bus_market.models[model.stock_id],
          s.stock_bus_market.epoch+s.day-1)
        if model and model.public and old and not old.public then
          push(s,"New model now available: "..M.vehicle_offer(s,id).name..".")
        end
      end
    end
    if month==1 and calendar_day==1 then
      for _,id in ipairs(M.vehicle_order) do
        if (not s.stock_bus_market or not road_bus_catalog().stock_id(id)) and M.vehicles[id].year==y and not M.vehicles[id].development then
          push(s,"New model now available: "..M.vehicles[id].name..".")
        end
      end
    end
  end
  if openings and not exact_economy and openings() then M.clear_live_sea_cache(s) end
  coal_day_bindings[s]=nil
  timber_day_bindings[s]=nil
  if s.retired_ship_stations or s.retired_rail_stations or s.retired_airports then
    M.road_station_retirement().expire(s)
  end
end
function M.demo(s,owner)
  if s.stock_generated_profile then return false,"Choose two of the generated towns and build a connection." end
  if s.stock_bus_market or M.vehicle_offer(s,"bus").stock_id==116 then
    return false,"Use the Roadworks walkthrough. The original bus must be purchased in a depot."
  end
  local c=M.company(s,owner)
  if c.tutorial then return false,"Starter line already built for this company." end
  local candidates={{9,18,11},{9,18,7},{9,18,12},{9,18,6},{9,18,10}}
  for _,p in ipairs(candidates) do
    local ids=M.line(M.id(p[1],p[3]),M.id(p[2],p[3]))
    local clean=true
    for _,id in ipairs(ids) do
      local t=s.tiles[id]
      if t.site or t.stock_industry or t.stock_landmark or t.house or t.build or t.h>0 or t.terrain~="grass" or
        (s.corner_grid and ground_shape(s,id)~=0) then clean=false;break end
    end
    if clean and c.cash>=6100 then
      local a,b=ids[1],ids[#ids]
      M.build(s,owner,"road",ids)
      M.build(s,owner,"road_station",{a,b})
      local va=s.tiles[a].station;local vb=s.tiles[b].station
      local id,msg=M.purchase(s,owner,"bus","passenger",va)
      if not id then return false,msg end
      M.add_order(s,owner,id,vb);M.toggle(s,owner,id)
      c.tutorial=true;push(s,owner.." opened the Port Alder–Mason Quay bus line.")
      return true,"Starter bus dispatched. Watch the road between Port Alder and Mason Quay.",ids
    end
  end
  return false,"No clean starter alignment remains, or you need $6,100. Use the manual walkthrough."
end
return M
