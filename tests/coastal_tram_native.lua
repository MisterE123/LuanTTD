do
  local F=dofile(mod.."/qa_coastal_tram.lua")(Sim,mod)
  core.after(0,function()
    local proof=S.coastal_tram_native
    if not proof then
      S.coastal_tram_native=F.start(S)
      api.save()
      core.log("action","TRAM_FLOOD_NATIVE_SAVED_WRECK")
      core.request_shutdown("Saved a paid flooded streetcar and a separate tram service",false,0)
      return
    end
    assert(F.finish(S,proof))
    api.save()
    core.log("action","TRAM_FLOOD_NATIVE_PASS paid tram wreck and native station retired while the separate fleet continued")
    core.request_shutdown("Only the tram and the reached platform retired",false,0)
  end)
end
