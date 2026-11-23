-- Appended only to a disposable copy of init.lua. The real server lifecycle
-- creates the owner, starts it after startup, and admits the client.
local player_name="SessionWorker"
local final,seed,requested,input
local function finish()
  if final then return end
  final=true
  core.request_shutdown("Native session check complete",false,0)
end
local function check()
  if final then return end
  local p=core.get_player_by_name(player_name)
  if authority and authority.status()=="owned" and p and #world.hotbar_layout(p)>0 then
    local pos=p:get_pos()
    if not seed then
      seed=pos
      assert(p:get_physics_override().speed==1)
      core.log("action",resumed_owner and "NATIVE OWNER SESSION REOPENED" or "NATIVE OWNER SESSION CLIENT READY")
    end
    local keys=p:get_player_control()
    if not input and (keys.right or keys.up) then
      input=true;core.log("action","NATIVE OWNER SESSION INPUT")
    end
    if not requested and (resumed_owner or (pos.x-seed.x)^2+(pos.z-seed.z)^2>2) then
      requested=true
      assert(authority.query({kind="company",player=player_name},function(r)
        assert(r.ok and r.value and r.value.world_day>S.day,r.why)
        if resumed_owner then
          assert(S.companies[player_name].loan==60000 and r.value.loan==60000 and r.revision==2)
          core.log("action","PASS NATIVE OWNER SESSION: reopen reused the durable company, clock and command revision")
          finish()
        else
          assert(S.companies[player_name]==nil and r.value.loan==50000 and r.revision==1)
          assert(authority.query({kind="command",player=player_name,command={
            kind="company_loan",amount=10000,revision=r.revision}},function(loan)
            assert(loan.ok and loan.revision==2,loan.why)
            local persisted=assert(OwnerCheckpoint.read())
            assert(persisted.companies[player_name].loan==60000 and S.companies[player_name]==nil)
            core.log("action","PASS NATIVE OWNER SESSION: real join, horizontal input and durable command without a host company")
            finish()
          end))
        end
      end))
    end
  end
  core.after(.38,check)
end
core.after(.45,check)
