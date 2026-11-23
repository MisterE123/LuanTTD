-- Appended to a disposable copy of the regular LuanTTD bootstrap.
-- No alternative game setup or per-feature settings.
local authority_test=dofile(mod.."/campaign_authority_client.lua")(core,mod)
local function transfer_ordinary()
  assert(api.generated_world and S.road_stock_clock and S.rail_paid_service and S.ship_paid_service and S.air_paid_service)
  assert(S.stock_generated_profile.width==64 and S.stock_generated_profile.depth==64)
  local owner="OrdinaryWorker"
  Sim.company(S,owner)
  local clock=S.passenger_house_clock
  local expected={day=S.day,cash=S.companies[owner].cash,h=S.tiles[Sim.id(3,3)].h}
  local assets=dofile(mod.."/airport_manifest.lua")(core,mod)
  local caps={road={start_year=1950,foster=true,craighead=true,breakdowns=api.bus_breakdowns,
    service_interval=api.bus_service_interval},air={},ferry={[206]=true,[207]=true},oil_tanker=true,
    rail=dofile(mod.."/rail_dispatch_manifest.lua").scan(mod,S.stock_electrification,api.rail_bridge_wire_art~=nil),
    autoplay=true,seconds_per_day=.16}
  for id in pairs(assets) do caps.air[id]=true end
  local filename="ordinary-worker-qa.chk"
  dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),filename).write_state(S)
  -- Sim and save cannot execute on the host during this QA handoff.
  S.speed=0
  api.save=function() end
  assert(authority_test.start(caps,function(ready)
    assert(ready.ready and ready.day==expected.day)
    core.after(.75,function()
      assert(authority_test.query({kind="company",player=owner},function(first)
        assert(first.ok and first.day>expected.day and first.tick==first.day*74 and first.value.cash==expected.cash)
        assert(authority_test.query({kind="snapshots",windows={{x=1,z=1,w=16,h=16},{x=33,z=33,w=16,h=16}}},function(near)
          assert(near.ok and #near.value==2 and #near.value[1].tiles==256 and #near.value[2].tiles==256)
          assert(near.value[1].tiles[35].id==Sim.id(3,3) and near.value[1].tiles[35].level==expected.h)
          assert(authority_test.query({kind="stop"},function() end))
        end))
      end))
    end)
  end,function(reason,seq,day,detail)
    assert(reason=="stopped" and seq==3 and day>expected.day,detail or reason)
    assert(S.day==expected.day and (not clock or clock.counter==expected.day*74))
    local state=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),filename).read()
    assert(state.day==day and state.passenger_house_clock.counter==day*74 and state.stock_generated_profile.width==64)
    core.log("action",("PASS NATIVE ORDINARY HANDOFF: regular 64-square world advanced from day %d to %d on the worker, host day stayed %d")
      :format(expected.day,day,S.day))
    core.request_shutdown("Ordinary authority handoff proof passed",false,0)
  end,filename))
end
core.after(.2,transfer_ordinary)
