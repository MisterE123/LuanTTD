-- The normal worker buys, orders and renders a stock tanker, loads genuine
-- oil and pays a refinery cargo delivery; no injected receipts or actors.
local oil_native_started=false
local function oil_native_scene(p)
  local stock=tonumber(core.settings:get("luanttd_qa_other_ship")) or 212
  local stem=({[208]="stock_bakewell_300_hovercraft",[211]="stock_yate_cargo_ship",[212]="stock_bakewell_cargo_ship"})[stock]
  local mesh=stock==211 and "bl_yate_cargo_ship.obj" or "bl_"..stem..".obj"
  local ids={ [208]="ferry",[211]="coal",[212]="coal" }
  local kind=assert(ids[stock])
  local capacity=({[208]=1,[211]=160,[212]=190})[stock]
  local price=({[208]=37578,[211]=32500,[212]=36562})[stock]
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
        assert(ref:get_properties().mesh==mesh)
        seen=true
      end
    end
    local disk=assert(OwnerCheckpoint.read())
    local v=kind=="coal" and disk.stock_ship_coal and disk.stock_ship_coal.vehicle
    local company=disk.companies[name]
    local delivered=kind=="coal" and v and v.delivered or kind=="ferry" and company.paid_units
    if seen and delivered and delivered>=capacity then
      assert(company.revenue>0)
      if kind=="coal" then
        assert(v.engine==stock and disk.stock_coal_ship.expense>0 and v.delivered>=capacity)
      else
        assert(disk.stock_owned_ferry.engine_id==stock and disk.stock_owned_ferry.expense>0)
      end
      core.log("action",("PASS NATIVE STOCK SHIP #%d: depot, weather, actual projected hull and %d paid units/$%d"):format(stock,delivered,company.revenue))
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
            assert(bought.value.id==kind)
            local function sail(receipt)
              ask({kind="command",command={kind="transport_start",mode="ship",vehicle=kind,cargo=kind=="coal" and "coal" or nil,
                depot=d.value.id,first=a.value.id,second=b.value.id,revision=receipt.revision}},function()
                  core.after(.20,observe)
                end)
            end
            if kind=="coal" then use({mode="ship",operation="refit",depot=d.value.id,cargo="coal"},sail)
            else sail(bought) end
          end)
        end)
      end)
    end)
  end)
end
local function oil_native_begin()
  local p=core.get_player_by_name("ShipReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
    if not oil_native_started then oil_native_started=true;oil_native_scene(p) end
  else core.after(.22,oil_native_begin) end
end
core.after(.22,oil_native_begin)
