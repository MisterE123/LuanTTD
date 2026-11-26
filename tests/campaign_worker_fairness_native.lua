-- Appended only to a disposable copy of the ordinary native game's init.
-- Measure the host's actual elapsed time, not timestamps from the owner.
core.register_on_mods_loaded(function()
  assert(authority,"This benchmark needs a generated worker-owned campaign")
  local t0,done
  local seconds=(tonumber(core.settings:get("qa_fairness_seconds")) or 32)*1e6
  local function report(receipt,sent)
    local now=core.get_us_time()
    if not t0 then t0=now end
    assert(receipt.ok,tostring(receipt.why))
    core.log("action",("FAIRNESS SAMPLE ms=%.2f elapsed=%.2f"):format((now-sent)/1e3,(now-t0)/1e3))
  end
  local function poll()
    if done then return end
    local sent=core.get_us_time()
    local ok=authority.query({kind="actor_frames",windows={{x=120,z=120,w=9,h=9}}},function(r)
      report(r,sent)
      core.after(.075,poll)
      if core.get_us_time()-t0>=seconds and not done then
        done=true
        local left=core.get_us_time()
        authority.query({kind="clock"},function(r)
          assert(r.ok)
          core.log("action",("FAIRNESS FINISH day=%d tick=%d ms=%.2f"):format(r.day,r.tick,(core.get_us_time()-left)/1e3))
          core.request_shutdown("Worker fairness captured",false,0)
        end)
      end
    end)
    if not ok then core.after(.05,poll) end
  end
  core.after(.05,poll)
  local function create()
    if done then return end
    local sent=core.get_us_time()
    if not authority.query({kind="command",player="Native Fairness QA",command={kind="company_open"}},function(r)
      assert(r.ok,tostring(r.why))
      core.log("action",("FAIRNESS DURABLE ms=%.2f"):format((core.get_us_time()-sent)/1e3))
    end) then core.after(.15,create) end
  end
  core.after(9,create)
end)
