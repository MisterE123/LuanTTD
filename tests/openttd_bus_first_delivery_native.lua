local path=core.get_modpath(core.get_current_modname())
local function lua(name) return dofile(path.."/"..name..".lua") end
local function bytes(path)
  local f=assert(io.open(path,"rb"))
  local s=f:read("*a");f:close()
  return s
end
local function json(name) return assert(core.parse_json(bytes(path.."/"..name..".json"))) end
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
local W,S=lua("world_storage"),lua("slope")
local Sparse=lua("openttd_sparse")(W,lua("openttd_map"),core.sha256)
local Motion=lua("road_motion")(lua("road_motion_data"))
local F=lua("yapf_road_follow")
local Cost=lua("yapf_road_cost")(F)
local Yapf=lua("yapf_road_search")(F,Cost)
local Check=lua("openttd_bus_checkpoint")(Sparse,S,lua("road_slope"),Motion,F,Cost,Yapf)
local P=lua("passengers")
local Loading=lua("road_loading_runtime")(lua("loading_timing"),P)
local Import=lua("openttd_bus_first_delivery")(Check,Motion,lua("road_speed"),F,Loading,P,lua("income"),core.sha256)
local data,reference=json("input"),json("reference")
local journal=core.get_worldpath().."/isolated-trip.journal"
local mode=core.settings:get("bus_first_delivery_mode")

local function sample(s)
  return {s.pixels.x,s.pixels.z,s.pixels.y,s.heading,s.speed,s.subspeed,s.progress,s.age_counter,s.trackdir,s.frame}
end
local function same_calc(r,ref)
  local s=r.state()
  while s.tick<ref[1] and not s.settlement_tick do s=r.step(math.min(74,ref[1]-s.tick)) end
  if s.tick~=ref[1] then return false end
  assert(s.tile==ref[2],"tile mismatch at "..s.tick)
  assert(table.concat(sample(s),",")==table.concat(ref[3],",",1,10),
    ("cursor mismatch at %d\nreplay %s\nstock  %s"):format(s.tick,table.concat(sample(s),","),table.concat(ref[3],",",1,10)))
  if ref[3][11]%16==3 then assert(s.loading_ticks==ref[3][12],"station pulse timer mismatch at "..s.tick) end
  assert(s.units==ref[4] and s.delivered==ref[5] and s.payment==ref[6],"delivery or fare mismatch at "..s.tick)
  return true
end

local r=Import.open(data)
if mode=="visual" then
  dofile(path.."/visual.lua")(r,Check.prepare(data.checkpoint,data.resume.existing_third_station,data.resume.depot_reserve_id),S,lua("road_slope"))
  return
end
local start=r.state()
assert(start.phase=="paused" and start.tick==(data.resume.existing_third_station and reference.starting_tick or 2541) and start.units==5 and start.waiting_initial==(data.resume.depot_reserve_id and 17 or 14))
assert(reference.source_sha256==start.source_sha256 and reference.source_sha_unchanged)
assert(not pcall(r.step,1))
if mode=="verify" then
  assert(r.resume())
  local checked=0
  for _,ref in ipairs(reference.samples) do if same_calc(r,ref) then checked=checked+1 end end
  local result=r.state()
  core.log("action","LUANTTD STOCK TRIP CALC "..core.write_json(result))
  assert(checked>=13 and result.delivered==5 and result.payment==9 and result.unload_pulses==1 and result.payment_pulses==1)
  assert(result.delivery_tick>reference.last_pre_delivery_tick and result.delivery_tick<=reference.delivery_observed_by_tick)
  assert(result.settlement_tick>result.delivery_tick and result.settlement_tick<=reference.fare_observed_by_tick)
  assert(result.delivered_packets[1].age==reference.pre_delivery_age)
  core.log("action","LUANTTD STOCK TRIP CURSOR MATCH "..checked)
elseif mode=="record" then
  assert(r.resume())
  local s=r.state()
  while not s.delivery_tick do s=r.step(1) end
  assert(s.arrived_tick<s.delivery_tick and s.delivered==5 and s.payment==0)
  assert(s.scratch_cash==tonumber(s.opening_cash) and s.staged_fare==9)
  assert(s.delivered_packets[1].age==3 and s.unload_pulses==1 and s.payment_pulses==0)
  assert(core.safe_file_write(journal,r.journal()))
  core.log("action","LUANTTD STOCK TRIP NATIVE BEFORE RESTART "..core.write_json(s))
elseif mode=="restore" then
  local saved=bytes(journal)
  local corrupt=saved:gsub("L","X",1)
  assert(not pcall(Import.open,data,corrupt))
  local altered=json("input")
  altered.resume.queue[1].count=altered.resume.queue[1].count+1
  assert(pcall(Import.open,altered))
  assert(not pcall(Import.open,altered,saved),"journal should bind queue contents as well as source hash")
  r=Import.open(data,saved)
  local s=r.state()
  assert(s.phase=="paused" and s.delivered==5 and s.payment==0 and s.staged_fare==9)
  assert(s.unload_pulses==1 and s.delivered_packets[1].age==3)
  assert(not pcall(r.step,1))
  assert(r.resume())
  while not s.settlement_tick do s=r.step(1) end
  assert(s.scratch_cash==tonumber(s.opening_cash)+9)
  assert(s.delivered==5 and s.payment==9 and s.payment_pulses==1 and s.settlement_tick>s.delivery_tick)
  assert(s.loaded_at_destination==8 and s.waiting==start.waiting_initial-8 and s.units==8)
  assert(r.step(74).payment_pulses==1 and r.state().tick==s.tick,"first-trip guard must not tick the return leg")
  core.log("action","LUANTTD STOCK TRIP NATIVE AFTER RESTART "..core.write_json(s))
elseif mode=="intent" then
  r=Import.open(data,bytes(journal))
  local Intent=lua("openttd_bus_order_intent")(Import,Check,core.sha256)
  local third=data.resume.existing_third_station
  local reserve=data.resume.depot_reserve_id
  local action=reserve and "reroute_next_with_parked_reserve"
    or third and "reroute_next_to_existing_third_stop" or "no_loading_on_next_stop"
  if reserve then
    assert(reserve==5 and start.reserve_id==reserve and start.reserve_depot_tile==44128)
    assert(not pcall(Intent.from_played,data,r.journal(),"reroute_next_to_existing_third_stop"))
    local invalid=json("input")
    invalid.checkpoint.bus_state.depot_reserve.raw.vehicle.roadveh[1].state=8
    assert(not pcall(Import.open,invalid))
  end
  assert(not pcall(Intent.from_played,data,Import.open(data).journal(),action))
  if third then
    assert(not pcall(Intent.from_played,data,r.journal(),"no_loading_on_next_stop"))
    local invalid=json("input")
    invalid.resume.existing_third_station=1
    assert(not pcall(Intent.from_played,invalid,r.journal(),action))
  end
  local receipt=Intent.from_played(data,r.journal(),action)
  if reserve then assert(receipt.reserve.id==5 and receipt.reserve.order_list_id==1 and receipt.reserve.order_id==2) end
  if third then assert(receipt.third.station==2 and receipt.third.tile==44642 and #receipt.third.route>5) end
  assert(r.state().tick==receipt.authored_tick and receipt.upcoming.order_id==0 and receipt.fare_pending==9)
  assert(core.safe_file_write(core.get_worldpath().."/stock-order-intent.json",core.write_json(receipt)))
  core.log("action","LUANTTD PLAYED STOCK ORDER INTENT READY")
else error("unknown resume fixture mode") end
core.after(0,function() core.request_shutdown("First delivery fixture complete",false,0) end)
