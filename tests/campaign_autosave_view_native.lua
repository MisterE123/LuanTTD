core.register_on_mods_loaded(function()
  assert(authority,"Run with a wide generated worker-owned campaign")
  local seen,prev,next_scene,t0,done={},nil,nil,nil,false
  local window={{x=120,z=120,w=32,h=32}}
  local function poll()
    if done then return end
    local sent=core.get_us_time()
    local scenery=not next_scene or sent>=next_scene
    local kind=scenery and "snapshots" or "actor_frames"
    local ok=authority.query({kind=kind,windows=window},function(r)
      local now=core.get_us_time()
      assert(r.ok and #r.value==1 and (not prev or r.actor_us>prev) and not seen[r.seq])
      seen[r.seq],prev=true,r.actor_us
      if not t0 then t0=now end
      core.log("action",("PROBE_VIEW %d kind=%s send=%d sample=%d receive=%d day=%d"):format(
        r.seq,kind,sent,r.actor_us,now,r.day))
      if scenery then window[1].scene=assert(r.value[1].scene);next_scene=now+200000 end
      if now-t0>=26000000 then
        done=true
        authority.query({kind="clock"},function(r)
          core.log("action",("PROBE_FINISH day=%d tick=%d"):format(r.day,r.tick))
          core.request_shutdown("Save/view profiling done",false,0)
        end)
      else
        core.after(.075,poll)
      end
    end)
    if not ok then core.after(.050,poll) end
  end
  core.after(.05,poll)
end)
