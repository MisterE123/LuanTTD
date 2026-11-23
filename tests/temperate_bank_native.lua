-- Disposable native world: real generated houses, normal stock funding
-- quote, worker-signed receipt, native projected Bank nodes.
local hooks={}
local authority=dofile(mod.."/campaign_authority_host.lua")(core,mod,hooks)
core.after(.2,function()
  assert(api.generated_world and api.capabilities.temperate_bank)
  local p1,p2,town
  for id,t in ipairs(S.tiles) do
    local record=t.source_house
    if record and record.town_growth and t.house and not t.site then
      local x,z=Sim.xy(id)
      local right=Sim.id(x+1,z)
      local other=right and S.tiles[right]
      local direct=other and other.source_house
      if direct and direct.town_growth and other.house and not other.site and other.h==t.h then
        local closest=Sim.nearest_town(S,id)
        if closest and closest.id==record.town and closest.id==direct.town then
          town,p1,p2=closest,id,right
          break
        end
      end
    end
  end
  assert(p1 and p2,"No valid adjacent house sites")
  -- Set only the town's population precondition in the test; we still
  -- replace real source-generated houses and all their native footprint.
  town.population=1400
  S.stock_town_growth.towns[town.id].population=1400
  local owner="BankFixture"
  local cash=2300000
  Sim.company(S,owner).cash=cash
  local checkpoint_file="bank-native-probe.chk"
  local checkpoint=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),checkpoint_file)
  function hooks.freeze_host() api.authority_handoff=true end
  function hooks.ready() end
  function hooks.stopped(why,_,_,detail) error(detail or why) end
  function hooks.seal_checkpoint() checkpoint.write_state(S);return checkpoint_file end
  local function ask(req,cb)
    req.player=owner
    assert(authority.query(req,function(r)
      assert(r.ok,r.why)
      cb(r)
    end))
  end
  local function painted()
    local x,z=Sim.xy(p1)
    local h=S.tiles[p1].h
    for i=0,1 do
      local suffix="industry_temperate_bank_"..i.."_0"
      local def=core.registered_nodes["luanttd_core:"..suffix]
      assert(def and def.mesh=="bl_"..suffix..".obj")
      if core.get_node({x=2*(x+i),y=h+1,z=2*z}).name~="luanttd_core:"..suffix then return false end
    end
    return true
  end
  local commit,done
  local function render_receipt()
    if not commit then
      commit=true
      local req={tool="fund_bank",first=p1}
      ask({kind="road_quote",request=req},function(q)
        assert(q.value.cost==996093 and #q.value.tiles>=2)
        ask({kind="command",command={kind="road_commit",request=req,revision=q.revision,quote=q.value}},function(r)
          local live=assert(checkpoint.read())
          assert(live.companies[owner].cash==cash-996093 and #r.value>=2)
          assert(not live.tiles[p1].house and not live.tiles[p2].house)
          assert(live.tiles[p1].stock_industry.gfx==58 and live.tiles[p2].stock_industry.gfx==59)
          local bank=assert(live.stock_bank_industries[live.tiles[p1].stock_industry.id])
          assert(bank.town==town.id and bank.produced[1].cargo=="valuables")
          done=true
        end)
      end)
    elseif done and painted() then
      core.log("action","STOCK_BANK_NATIVE_OK actual generated houses replaced by both native Bank assets, worker receipt and debit durable")
      core.request_shutdown("Stock bank QA passed",false,0)
    end
  end
  local painter=dofile(mod.."/campaign_projection_painter.lua")(render,function(_,ok,reason)
    assert(ok,reason);render_receipt()
  end)
  hooks.present=painter.present
  local function tick()
    local x,z=Sim.xy(p1)
    authority.step(.25,{{x=2*x,z=2*z,name=owner}},1)
    painter.step()
    core.after(.14,tick)
  end
  local caps={autoplay=true,seconds_per_day=.18,durable_actions=true}
  for k,value in pairs(api.capabilities) do if caps[k]==nil then caps[k]=value end end
  assert(authority.start(caps,Sim.W,Sim.H))
  tick()
end)
