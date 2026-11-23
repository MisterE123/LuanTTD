-- Appended only by the disposable test runner. SQLite records the exact
-- commercial simulation state; a fresh Lua process runs the next month.
local mixed_journey=dofile(mod.."/qa_mixed_freight.lua")
local mixed_storage=core.get_mod_storage()
core.after(0,function()
  local saved=mixed_storage:get_string("mixed_freight_fixture")
  if saved=="" then
    local s,p=mixed_journey.setup()
    local a,units,cash=mixed_journey.verify(s,p)
    mixed_storage:set_string("mixed_freight_fixture",core.serialize({world=s,details=p,before=a,units=units,cash=cash}))
    core.log("action",("MIXED_FREIGHT_NATIVE_SAVED: %d units / $%d from seven vehicles"):format(units,cash))
  else
    local snapshot=assert(core.deserialize(saved))
    mixed_journey.remount(snapshot.world)
    local _,units,cash=mixed_journey.verify(snapshot.world,snapshot.details,snapshot.before)
    assert(units>snapshot.units and cash>snapshot.cash)
    core.log("action",("MIXED_FREIGHT_NATIVE_PASS: %d units / $%d across SQLite restart; seven freight services paid once"):format(units,cash))
  end
  core.request_shutdown("Mixed freight fixture complete",false,0)
end)
