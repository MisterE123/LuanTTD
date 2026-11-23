-- Appended only in the isolated client test. Trigger commands from a
-- disposable test marker, so an unfocused GUI provides no extra requests.
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  local function probe()
    local live=core.get_player_by_name(name)
    if not live then return end
    local pos=live:get_pos()
    if pos and authority and authority.status()=="owned" then
      core.log("action",("FOCUS_NATIVE_POSITION %.4f %.4f %.4f"):format(pos.x,pos.y,pos.z))
      local stage=core.get_worldpath().."/native-focus-step"
      local f=io.open(stage,"r")
      if f then
        local label=f:read("*l");f:close()
        os.remove(stage)
        if label=="initial" or label=="focus-return" or label=="reopen" then
          assert(authority.query({kind="company",player=name},function(r)
            assert(r.ok,r.why)
            core.log("action",("FOCUS_NATIVE_RECEIPT %s day=%d cash=%d"):format(label,r.day,r.value.cash))
          end))
        end
      end
    end
    core.after(.16,probe)
  end
  core.after(.16,probe)
end)
