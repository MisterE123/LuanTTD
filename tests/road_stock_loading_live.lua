local root="mods/bayline/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local function ck(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function copy(x)
  if type(x)~="table" then return x end
  local t={}
  for k,v in pairs(x) do t[k]=copy(v) end
  return t
end
local function campaign(active,mail)
  local s=S.new(1751)
  dofile(root.."town_layout.lua")(S,s)
  s.corner_grid=dofile(root.."terrain_preview.lua")(S,T,s)
  s.road_economy=true;s.road_stock_clock=true;s.road_stock_house_supply=true
  s.road_stock_loading=active or nil;s.road_mail=mail or nil
  local a,b,d=S.id(11,12),S.id(17,12),S.id(12,13)
  assert(S.build(s,"Test","road",S.line(a,b)))
  if mail then assert(S.build_truck_stop(s,"Test",a) and S.build_truck_stop(s,"Test",b))
  else assert(S.build(s,"Test","road_station",{a,b})) end
  assert(S.build(s,"Test","road_depot",{d}))
  local function order(action)
    local id=assert(S.purchase(s,"Test",mail and "mail_van" or "bus",mail and "mail" or "passenger",nil,d))
    assert(S.add_order(s,"Test",id,s.tiles[a].station,action))
    assert(S.add_order(s,"Test",id,s.tiles[b].station) and S.toggle(s,"Test",id))
    return id
  end
  return s,a,b,order
end

-- The flag is strictly opt-in: all other stock settings still use the
-- old arrival schedule and original day-aggregate age field.
local old,a,b,order=campaign(false,true)
local id=order("full")
for _=1,100 do S.daily(old);if old.fleet[id].last_fare then break end end
assert(not S.road_stock_service_active(old))
assert(old.fleet[id].last_fare.amount>0 and old.fleet[id].passenger_age_ticks)
assert(not old.stock_load_tick and not old.fleet[id].stock_aged_tick)
ck(#S.road_loading_events(old),0)

-- Both actual buses start in one depot. The second must respect the
-- stopped first vehicle's used bay until it physically exits the box,
-- including after serialized reload in mid full-load waiting.
local s,A,B,spawn=campaign(true,false)
local one,two=spawn("full"),spawn("normal")
local departed,reloaded,blocked,boarding,arrival_tick,first_fare_tick=false,false,false,0
local same_day=false
local function earlier(t) return math.floor((t-1)/74) end
for _=1,225 do
  S.daily(s)
  local v,w=s.fleet[one],s.fleet[two]
  local tick=s.stock_load_tick
  ck(tick,s.day*74)
  ck(v.stock_aged_tick,tick);ck(w.stock_aged_tick,tick)
  assert(not v.passenger_age_ticks and not w.passenger_age_ticks)
  for _,effect in ipairs(S.road_loading_events(s)) do
    if effect.vehicle==one and effect.kind=="board" then
      if effect.data.tile==A and not departed then boarding=boarding+effect.data.units end
      assert(effect.data.tick>v.last_road_arrival_tick or effect.data.tile~=S.position(s,v))
    elseif effect.vehicle==one and effect.kind=="fare" and not first_fare_tick then
      first_fare_tick=effect.data.tick
    end
  end
  if v.load_state and v.road_stop_pose and v.road_stop_pose[4]==A then
    arrival_tick=arrival_tick or v.load_state.arrived_tick
    assert(v.units<S.vehicles.bus.capacity)
    local va=S.road_motion_timeline(s,one)
    local c=va.cursors[#va.cursors]
    ck(va.frames[c][1],v.road_stop_pose[1])
    ck(va.frames[c][2],v.road_stop_pose[2])
    ck(va.frames[c][3],v.road_stop_pose[3])
    if w.road_speed_state and w.road_speed_state.waiting=="bay" then
      blocked=true
      assert(S.position(s,w)~=A)
      if not reloaded then
        s=copy(s)
        ck(#S.road_loading_events(s),0)
        ck(s.fleet[one].load_state.arrived_tick,arrival_tick)
        reloaded=true
      end
    end
  end
  if v.last_departure_tick and arrival_tick and v.last_departure_tick>arrival_tick then
    departed=true
    if (v.last_road_arrival_tick or 0)<v.last_departure_tick
       and earlier(v.last_departure_tick)==earlier(v.last_road_arrival_tick) then same_day=true end
  end
  if w.last_departure_tick and w.last_road_arrival_tick
     and w.last_departure_tick>w.last_road_arrival_tick
     and earlier(w.last_departure_tick)==earlier(w.last_road_arrival_tick) then same_day=true end
  local va,vb=S.road_motion_timeline(s,one),S.road_motion_timeline(s,two)
  if va and vb then
    ck(#va.cursors,75);ck(#vb.cursors,75)
    for i=1,75 do
      local x,y=va.cursors[i],vb.cursors[i]
      if x>0 and y>0 then
        assert(va.frames[x][4]~=A or vb.frames[y][4]~=A,
               "Two buses cannot physically occupy the modeled bay")
      end
    end
  end
  if first_fare_tick and w.last_road_arrival_tick and departed and same_day then break end
end
assert(blocked and reloaded and departed and arrival_tick and same_day and first_fare_tick)
assert(boarding>=S.vehicles.bus.capacity)
local v,w=s.fleet[one],s.fleet[two]
assert(v.delivered>=S.vehicles.bus.capacity and v.last_fare.amount>0)
assert(w.last_road_arrival_tick>arrival_tick and s.companies.Test.paid_units>=v.delivered)
print(("PASS: native 74-tick clock one bay blocked across reload, bus arrival %d, payout %d, and same-day onward departure")
  :format(arrival_tick,first_fare_tick))

-- The explicit preview setting may be switched off between saved sessions.
-- Cancel the stock service cleanly and translate the remaining age phase.
local tick=s.stock_load_tick
s.road_stock_loading=nil
S.daily(s)
assert(not s.stock_load_tick)
assert(not v.cargo_age_counter and v.passenger_age_ticks and not v.load_state)
s.road_stock_loading=true
S.daily(s)
ck(s.stock_load_tick,tick+148)
ck(v.stock_aged_tick,s.stock_load_tick)
