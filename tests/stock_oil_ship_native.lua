-- The normal worker buys, orders and renders a stock tanker, loads genuine
-- oil and pays a refinery cargo delivery; no injected receipts or actors.
local oil_native_started=false
local function oil_native_scene(p)
  local stock=tonumber(core.settings:get("luanttd_qa_oil_ship")) or 204
  local stem=stock==204 and "stock_mps_oil_tanker" or "stock_cs_inc_oil_tanker"
  local capacity,price=stock==204 and 220 or 350,stock==204 and 40625 or 44687
  assert(api.capabilities.ferry[stock])
  local name=p:get_player_name()
  p:set_pos({x=34,y=10,z=56});p:set_look_horizontal(0);p:set_look_vertical(.40)
  local function ask(value,cb)
    value.player=name
    local yes,why=authority.query(value,function(r)
      assert(r.ok,value.kind..": "..tostring(r.why));cb(r)
    end)
    assert(yes,why)
  end
  local function use(req,cb)
    ask({kind="transport_quote",request=req},function(q)
      ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},cb)
    end)
  end
  local function node(x,z) return Sim.id(x,z) end
  local seen=false
  local function observe()
    for _,ref in ipairs(core.get_objects_inside_radius({x=38,y=2,z=68},24)) do
      local actor=ref:get_luaentity()
      if actor and actor.name=="luanttd_core:"..stem then
        assert(ref:get_properties().mesh=="bl_"..stem..".obj")
        seen=true
      end
    end
    local disk=assert(OwnerCheckpoint.read())
    local v=disk.stock_oil_ship_service and disk.stock_oil_ship_service.vehicle
    if seen and v and v.delivered>=capacity then
      assert(v.revenue>0 and disk.stock_owned_oil_ship.expense>0)
      assert(disk.stock_oil_industries[0x3001].received.oil==v.delivered)
      core.log("action",("PASS NATIVE OIL SHIP #%d: ordinary owner produced, loaded, projected at real berth and delivered %d kL/$%d"):format(stock,v.delivered,v.revenue))
      return
    end
    core.after(.20,observe)
  end
  use({mode="ship",operation="build",kind="dock",tile=node(12,32)},function(a)
    use({mode="ship",operation="build",kind="dock",tile=node(31,32)},function(b)
      use({mode="ship",operation="build",kind="depot",tile=node(17,35),axis=0},function(d)
        ask({kind="depot",mode="ship",depot=d.value.id},function(q)
          local chosen
          for _,row in ipairs(q.value.offers) do if row.request.engine==stock then chosen=row end end
          assert(chosen and chosen.price==price)
          use(chosen.request,function(bought)
            assert(bought.value.id=="oil")
            ask({kind="command",command={kind="transport_start",mode="ship",vehicle="oil",cargo="oil",depot=d.value.id,
                first=a.value.id,second=b.value.id,revision=bought.revision}},function()
              core.after(.20,observe)
            end)
          end)
        end)
      end)
    end)
  end)
end
local function oil_native_begin()
  local p=core.get_player_by_name("OilReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
    if not oil_native_started then oil_native_started=true;oil_native_scene(p) end
  else core.after(.22,oil_native_begin) end
end
core.after(.22,oil_native_begin)
