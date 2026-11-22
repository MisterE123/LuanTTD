-- Executed in two fresh Luanti server processes sharing the real SQLite store.
local path=core.get_modpath(core.get_current_modname())
local setup=dofile(path.."/road_overtake_fixture.lua")(path.."/")
local storage=core.get_mod_storage()
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
core.register_on_mods_loaded(function()
  core.after(0,function()
    for _,kind in ipairs{"stopped","moving"} do
      local raw=storage:get_string(kind)
      if raw=="" then
        assert(core.settings:get_bool("luanttd_overtake_write",false))
        local snapshot=setup.checkpoint(kind)
        storage:set_string(kind,core.serialize(snapshot))
        core.log("action","OVERTAKE SQLITE CHECKPOINT "..kind)
      else
        assert(not core.settings:get_bool("luanttd_overtake_write",false))
        local snapshot=assert(core.deserialize(raw,true))
        assert(snapshot.kind==kind and not setup.Sim.road_motion_timeline(snapshot.s,snapshot.follow))
        setup.resume(snapshot)
        core.log("action","OVERTAKE SQLITE RESTORE "..kind)
      end
    end
    core.request_shutdown("Overtake SQLite assertions completed",false,0)
  end)
end)
