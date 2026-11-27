-- Test-only fixture appended to a disposable copy of the real game.
-- Use the same worker command endpoint as the HUD, not a direct save.
local owner="PaidCrashQA"
local filename="qa-paid-process-crash.chk"
local disk=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),filename)
local witness_path=core.get_worldpath().."/qa-paid-process-crash.txt"
local phase=assert(core.settings:get("luanttd_qa_paid_crash_phase"))
local hooks={}
local worker=dofile(mod.."/campaign_authority_host.lua")(core,mod,hooks)
local caps={autoplay=true,seconds_per_day=1.25,durable_actions=true}
for k,v in pairs(api.capabilities) do if caps[k]==nil then caps[k]=v end end
local function read_witness()
  local file=assert(io.open(witness_path,"r"))
  local out=assert(core.deserialize(file:read("*a"),true))
  file:close()
  return out
end
local function write_witness(out)
  assert(core.safe_file_write(witness_path,core.serialize(out)))
end
local function ask(q,done)
  q.player=owner
  assert(worker.query(q,function(r)
    assert(r.ok,r.why)
    done(r)
  end))
end
local function verify(w,stage,done)
  local charge=stage=="unpublished" and 0 or w.build+(stage=="removed" and w.remove or 0)
  ask({kind="company"},function(receipt)
    assert(receipt.value.cash==w.before-charge,"paid action was lost or charged twice")
    ask({kind="snapshot",x=w.x,z=w.z,w=5,h=1},function(response)
      assert(#response.value.tiles==5)
      for i,t in ipairs(response.value.tiles) do
        assert(t.id==w.first+i-1)
        assert((t.build=="road")== (stage=="placed"),"durable surface differs from acknowledged construction")
      end
      done()
    end)
  end)
end
local freeze=false
function hooks.freeze_host()
  freeze=true
  api.authority_handoff=true
end
function hooks.seal_checkpoint()
  assert(freeze)
  if phase=="abort" then
    -- The stock pregame clock has already run. Pause here so the
    -- process dies without an intervening autosave or extra time.
    assert(not disk.read())
    S.speed=0
    disk.write_state(S)
  else
    assert(disk.read(),"reopen must load the canonical file, not host state")
  end
  return filename
end
local function receive_ready()
  if phase=="verify" then
    verify(read_witness(),"removed",function()
      core.log("action","PAID_PROCESS_CRASH_PASS unpublished road rolled back; acknowledged build and removal survived with exact debits")
      core.request_shutdown("Paid process crash QA passed",false,0)
    end)
  elseif phase=="place" then
    local w=read_witness()
    verify(w,"unpublished",function()
      core.log("action","PAID_PROCESS_CRASH_OLD previous stock terrain and balance survived")
      local req={tool="drag",first=w.first,last=w.first+4,axis=0,start_half=false,end_half=true}
      ask({kind="road_quote",request=req},function(q)
        assert(q.value.cost==w.build)
        ask({kind="command",command={kind="road_commit",revision=q.revision,request=req,quote=q.value}},
          function()core.log("action","PAID_PROCESS_CRASH_ACK place")end)
      end)
    end)
  elseif phase=="remove" then
    local w=read_witness()
    verify(w,"placed",function()
      local req={tool="remove",first=w.first,last=w.first+4,axis=0,start_half=false,end_half=true}
      ask({kind="road_quote",request=req},function(q)
        w.remove=q.value.cost
        assert(w.remove>0)
        write_witness(w)
        ask({kind="command",command={kind="road_commit",revision=q.revision,request=req,quote=q.value}},
          function()core.log("action","PAID_PROCESS_CRASH_ACK remove")end)
      end)
    end)
  else
    assert(phase=="abort")
    ask({kind="command",command={kind="company_open"}},function()
      ask({kind="company"},function(c)
        local w
        for z=2,62 do
          for x=2,57 do
            local first=Sim.id(x,z)
            local good=true
            for d=0,4 do
              local t=S.tiles[first+d]
              if not t or t.terrain=="water" or t.wood or t.house or t.build or t.site or t.stock_industry
                  or api.terrain.tile(first+d)~=0 then good=false;break end
            end
            if good then w={x=x,z=z,first=first,before=c.value.cash};break end
          end
          if w then break end
        end
        assert(w,"no flat unoccupied generated corridor")
        local req={tool="drag",first=w.first,last=w.first+4,axis=0,start_half=false,end_half=true}
        ask({kind="road_quote",request=req},function(q)
          w.build=q.value.cost
          assert(w.build>0 and #q.value.tiles==5)
          write_witness(w)
          ask({kind="command",command={kind="road_commit",revision=q.revision,request=req,quote=q.value}},
            function()error("unpublished fixture unexpectedly acknowledged placement")end)
        end)
      end)
    end)
  end
end
function hooks.ready(r)
  assert(r.ready,r.why)
  receive_ready()
end
function hooks.stopped(why,_,_,detail)
  assert(why=="stopped" or why=="cancelled",detail or why)
end
core.after(0,function()
  assert(S.stock_generated_profile and S.stock_generated_profile.width==64)
  assert(worker.start(caps,Sim.W,Sim.H))
end)
