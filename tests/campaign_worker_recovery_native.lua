-- Real native async owner and session; no fake time, viewport requests,
-- keepalives or manually reopening the world while the host is asleep.
local Owner="worker-recovery-probe.chk"
local Check=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),Owner)
local controller=dofile(mod.."/campaign_worker_session.lua")(core,mod,api,ui,render,Check,Owner,true,{
  open=function() end,wait=function() end,connection=function() end})
local company="WorkerRecoveryQA"
local cap={autoplay=true,seconds_per_day=.20,durable_actions=true}
for k,v in pairs(api.capabilities) do if cap[k]==nil then cap[k]=v end end
local function state(ready)
  if controller.status()~="owned" then core.after(.08,state,ready);return end
  ready()
end
local function ask(message,receive)
  message.player=company
  assert(controller.query(message,receive))
end
local function clock(cb)
  ask({kind="clock"},function(r) assert(r.ok,r.why);cb(r) end)
end
core.after(0,function()
  assert(controller.start(cap,Sim.W,Sim.H))
  state(function()
    ask({kind="command",command={kind="company_open"}},function(c)
      assert(c.ok,c.why)
      clock(function(before)
        -- Do not call controller.step at all. It is the callback a
        -- locally paused/unfocused engine can stop dispatching.
        core.after(8.2,function()
          assert(controller.status()=="owned","worker ended when the native host was quiet")
          clock(function(after)
            assert(after.day>=before.day+5 and after.tick>before.tick,"worker stopped advancing with a quiet host")
            core.log("action","WORKER_QUIET_HOST_PASS durable campaign advanced without a viewport or heartbeat")
            if not core.settings:get_bool("qa_worker_crash",false) then
              core.request_shutdown("Worker quiet-host test passed",false,0);return
            end
            ask({kind="command",command={kind="company_loan",revision=after.revision,amount=10000}},function(paid)
              assert(paid.ok,paid.why)
              local on_file=assert(Check.read())
              local good_cash=on_file.companies[company].cash
              local failed_receipts=0
              local function interrupted(r)
                assert(not r.ok and r.interrupted,"Interrupted action must not be replayed or report success")
                failed_receipts=failed_receipts+1
              end
              ask({kind="qa_crash"},interrupted)
              ask({kind="command",command={kind="company_loan",revision=paid.revision,amount=10000}},interrupted)
              core.after(.80,function()
                state(function()
                  assert(failed_receipts==2)
                  local live=assert(Check.read())
                  assert(live.companies[company].cash==good_cash,"Lost or repeated charge across recovery")
                  ask({kind="company"},function(result)
                    assert(result.ok and result.value.cash==good_cash,"Reopened stale in-memory campaign")
                    clock(function(recovered)
                      assert(recovered.day>=on_file.day)
                      ask({kind="command",command={kind="company_loan",revision=recovered.revision,amount=-10000}},function(post)
                        assert(post.ok,post.why)
                        assert(assert(Check.read()).companies[company].cash==good_cash-10000)
                        core.log("action","WORKER_IN_PLACE_RECOVERY_PASS preserved durable funds, canceled both outstanding actions and accepted new input without reopening")
                        core.request_shutdown("Worker recovered in place",false,0)
                      end)
                    end)
                  end)
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end)
