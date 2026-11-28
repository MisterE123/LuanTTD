-- Dedicated Luanti + real async campaign authority, not a Lua emulator.
-- The fixture sets only stock world parameters and known road locations.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local client=m("campaign_authority_client")(core,mod)
local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},ferry={},air={},oil_tanker=true}
local owner="Stock Native Goods"
local ref=m("qa_native_goods")
local passengers,wood,goods=unpack(ref.world[28290][1],6)
for _,kind in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..kind,"air") end
local initial=Checkpoint.read()
local function tile(x,z) return z*128+x+1 end
if not initial then
  local gen=m("campaign_generation")(core,mod,Sim,m("world_setup"))
  local s=gen.run({width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,
    trees=2,towns=4,custom_towns=4,larger_towns=3,industries=4,variety=0,smooth=1,layout="original",growth_rate=2})
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  s.road_mail,s.road_junction_clearance=true,true
  Checkpoint.write_state(s)
end
local thread,revision,proof
local function resume(reply)
  local ok,query=coroutine.resume(thread,reply)
  assert(ok,query)
  if query then assert(client.query(query,resume)) end
end
local function ask(kind,fields)
  fields=fields or {}
  fields.kind,fields.player=kind,owner
  local reply=assert(coroutine.yield(fields))
  revision=reply.revision or revision
  assert(reply.ok,reply.why)
  return reply.value
end
local function command(kind,fields)
  fields=fields or {}
  fields.kind,fields.revision=kind,revision
  return ask("command",{command=fields})
end
local function road(x,z,u,v)
  command("road_build",{first=tile(x,z),last=tile(u,v)})
end
local function terminal(kind,x,z,direction,through)
  local first=tile(x,z)
  local request={tool="stock_terminal",first=first,kind=kind,direction=direction,through=through}
  local quote=ask("road_quote",{request=request})
  command("road_commit",{request=request,quote=quote})
  return first
end
local function state()
  ask("checkpoint")
  return assert(Checkpoint.read())
end
local function serve(model,cargo,home,a,b,cost)
  local id=command("road_buy",{engine=model,cargo=cargo,depot=home,cost=cost})
  command("road_order_add",{vehicle=id,station=a})
  command("road_order_add",{vehicle=id,station=b})
  command("road_toggle",{vehicle=id})
  return id
end
local function run()
  if not initial then
    command("company_open")
    road(45,44,46,44)
    local bd=terminal("depot",47,44,0)
    terminal("bus",41,44,0,true)
    terminal("bus",43,47,3,true)
    assert(serve("bus","passenger",bd,1,2,6562)==1)
    road(47,58,47,87)
    road(47,87,22,87)
    local wd=terminal("depot",47,57,1)
    terminal("truck",47,59,3,true)
    terminal("truck",23,87,0,true)
    assert(serve("wood_truck","wood",wd,3,4,6453)==2)
    terminal("truck",49,89,0,true)
    local gg=ref.shared and wd or terminal("depot",21,87,2)
    assert(serve("goods_truck","goods",gg,4,5,5851)==3)
    local s=state()
    assert(s.companies[owner].cash==(ref.shared and 66224 or 65609) and s.fleet[3].stock_pool_id==4)
    for _=1,32 do ask("advance",{days=4}) end
    s=state()
    assert(s.day==128 and s.fleet[2].delivered>0 and s.fleet[3].delivered==0)
    proof="ORDINARY_GOODS_SAVED: three paid vehicles at day 128, before first Goods delivery"
  else
    assert(initial.day==128 and initial.fleet[3].stock_road_freight)
    for _=1,59 do ask("advance",{days=4}) end
    ask("advance",{days=1})
    local s=state()
    assert(s.day==365 and s.fleet[1].delivered==passengers and s.fleet[2].delivered==wood and s.fleet[3].delivered==goods)
    local year=ref.world[28290][3]
    local town=s.stock_town_growth.towns[2]
    assert(town.grow_counter==year[4] and town.growth_rate==year[5])
    proof=("ORDINARY_GOODS_PASS: %d passengers, %d wood and %d Goods after SQLite restart; exact RC1 town clock"):format(passengers,wood,goods)
  end
  return {kind="stop"}
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(run)
  assert(client.start(cap,function(reply)
    assert(reply.ready)
    revision=reply.revision
    resume(reply)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and proof,tostring(detail or reason))
    core.log("action",proof)
    core.request_shutdown("Ordinary Goods QA complete",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
