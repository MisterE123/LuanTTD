-- Compare both encoders in native Lua, using a copied synthetic campaign.
local mod=core.get_modpath("bench")
core.register_on_mods_loaded(function()
  core.after(0,function()
    local baseline=dofile(mod.."/baseline.lua")
    local candidate=dofile(mod.."/packed_campaign.lua")
    local Checkpoints=dofile(mod.."/campaign_checkpoint.lua")
    local old,new=Checkpoints(core,baseline),Checkpoints(core,candidate)
    local state=assert(old.read(),"Expected a copied synthetic checkpoint")
    local equivalent=core.settings:get_bool("checkpoint_bench_equivalent",false)
    local expected
    for i=1,16 do
      local before=i%4==1 or i%4==0
      collectgarbage("collect")
      local wall,cpu=core.get_us_time(),os.clock()
      local raw=(before and baseline or candidate).encode(state)
      local wall_ms,cpu_ms=(core.get_us_time()-wall)/1000,(os.clock()-cpu)*1000
      if not equivalent then
        if expected then assert(expected==raw,"Checkpoint bytes changed") else expected=raw end
      end
      core.log("action",("CHECKPOINT BENCH %s wall_ms=%.2f cpu_ms=%.2f bytes=%d"):format(
        before and "baseline" or "candidate",wall_ms,cpu_ms,#raw))
    end
    new.write_state(state)
    if equivalent then
      -- Real campaigns have only scalar keys. Table-key and cyclic
      -- fallback behavior is covered independently by packed_campaign.lua.
      local left,right={},{}
      local function same(a,b)
        if type(a)~="table" then return a==b or type(a)=="number" and type(b)=="number" and a~=a and b~=b end
        if type(b)~="table" then return false end
        if left[a] or right[b] then return left[a]==b and right[b]==a end
        left[a],right[b]=b,a
        for k,v in pairs(a) do
          if type(k)=="table" or not same(v,b[k]) then return false end
        end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
      end
      assert(same(state,new.read()),"Reopened checkpoint changed a value or graph alias")
      core.log("action","CHECKPOINT BENCH equivalent restored graph")
    else
      assert(new.read() and old.read(),"Both codecs must reopen the newly saved campaign")
    end
    core.request_shutdown("Checkpoint benchmark complete",false,0)
  end)
end)
