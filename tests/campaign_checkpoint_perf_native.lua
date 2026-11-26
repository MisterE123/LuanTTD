-- Compare both encoders in native Lua, using a copied synthetic campaign.
local mod=core.get_modpath("bench")
core.register_on_mods_loaded(function()
  core.after(0,function()
    local baseline=dofile(mod.."/baseline.lua")
    local candidate=dofile(mod.."/packed_campaign.lua")
    local Checkpoints=dofile(mod.."/campaign_checkpoint.lua")
    local old,new=Checkpoints(core,baseline),Checkpoints(core,candidate)
    local state=assert(old.read(),"Expected a copied synthetic checkpoint")
    local expected
    for i=1,16 do
      local before=i%4==1 or i%4==0
      collectgarbage("collect")
      local wall,cpu=core.get_us_time(),os.clock()
      local raw=(before and baseline or candidate).encode(state)
      local wall_ms,cpu_ms=(core.get_us_time()-wall)/1000,(os.clock()-cpu)*1000
      if expected then assert(expected==raw,"Checkpoint bytes changed") else expected=raw end
      core.log("action",("CHECKPOINT BENCH %s wall_ms=%.2f cpu_ms=%.2f bytes=%d"):format(
        before and "baseline" or "candidate",wall_ms,cpu_ms,#raw))
    end
    new.write_state(state)
    assert(new.read() and old.read(),"Both codecs must reopen the newly saved campaign")
    core.request_shutdown("Checkpoint benchmark complete",false,0)
  end)
end)
