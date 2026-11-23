-- Setup uses the real worker command path. Selection, scrolling and
-- copying come only from the Luanti client's actual formspec input.
local identity="DepotCopyQA"
local function wait_for(check,run,n)
  if check() then run()
  elseif n<125 then core.after(.2,function() wait_for(check,run,n+1) end)
  else error("Native depot QA did not receive the expected result") end
end
local function test()
  local p=core.get_player_by_name(identity)
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,test);return
  end
  local first,last,depot,st1,st2
  for z=4,58 do
    for x=2,52 do
      local flat,base=true
      for i=0,8 do
        local id=Sim.id(x+i,z)
        local t=S.tiles[id]
        local mask,h=api.terrain.tile(id)
        if mask~=0 or base and h~=base or t.wood or t.house or t.site or t.owner or
            t.stock_industry or t.terrain=="water" then flat=false;break end
        base=h
      end
      if flat then
        first,last,depot=Sim.id(x+1,z),Sim.id(x+8,z),Sim.id(x,z)
        st1,st2=Sim.id(x+2,z),Sim.id(x+7,z)
        break
      end
    end
    if depot then break end
  end
  assert(depot,"There is no flat 9-tile stretch of test terrain")
  local function ask(req,done)
    req.player=identity
    assert(authority.query(req,function(r) assert(r.ok,r.why);done(r) end))
  end
  local function command(c,done)
    ask({kind="company"},function(company)
      c.revision=company.revision
      ask({kind="command",command=c},done)
    end)
  end
  local actions={{tool="road_depot",first=depot},{tool="road_station",first=st1},{tool="road_station",first=st2}}
  local function purchase()
    ask({kind="depot",mode="road",depot=depot},function(data)
      local buy
      assert(#data.value.offers>=8,"Native QA needs a full, scrollable depot catalogue")
      for _,offer in ipairs(data.value.offers) do if offer.request.cargo=="passenger" then buy=offer.request;break end end
      assert(buy)
      command(buy,function(r)
        local target=r.value
        command(buy,function(r2)
          local source=r2.value
          local disk=assert(OwnerCheckpoint.read())
          local a,b=disk.tiles[st1].station,disk.tiles[st2].station
          command({kind="road_order_add",vehicle=source,station=b},function()
            command({kind="road_order_add",vehicle=source,station=a},function()
              local draw=core.show_formspec
              function core.show_formspec(n,form,body)
                draw(n,form,body)
                if n~=identity or form~=api.worker_depot.form then return end
                if body:find("Copy selected orders",1,true) then
                  core.log("action","DEPOT_COPY_SOURCE_READY")
                elseif body:find("Orders copied.",1,true) then
                  local saved=assert(OwnerCheckpoint.read())
                  local src,dst=saved.fleet[source],saved.fleet[target]
                  assert(not S.fleet[source] and not S.fleet[target] and #dst.orders==2 and #src.orders==2)
                  assert(dst.orders[1].station==b and dst.orders[2].station==a)
                  assert(src.orders[1].station==b and src.orders[2].station==a)
                  assert(not dst.order_group and not src.order_group)
                  core.log("action","PASS NATIVE DEPOT COPY: mouse selection copied the ordered route to the other vehicle in the real worker checkpoint")
                  core.show_formspec=draw
                elseif body:find("Copy orders…",1,true) then
                  assert(body:find("scroll_container[",1,true) and body:find("offer_row8",1,true))
                  core.log("action","DEPOT_COPY_ROSTER_READY")
                end
              end
              local fields=api.worker_depot.fields
              function api.worker_depot.fields(player,f)
                for k,v in pairs(f) do
                  if k:match("_offer_scroll$") and core.explode_scrollbar_event(v).value>5 then
                    core.log("action","DEPOT_COPY_SCROLLED")
                  elseif (tonumber(k:match("_offer_row(%d+)$")) or 0)>5 then
                    core.log("action","DEPOT_COPY_LATER_ROW_SELECTED "..k)
                  end
                end
                return fields(player,f)
              end
              api.worker_depot.open(p,"road",depot,nil,function(mode,vehicle)
                api.vehicle_ui.open(p,mode,vehicle)
              end)
              wait_for(function()
                return #assert(OwnerCheckpoint.read()).fleet[target].orders==2
              end,function() core.log("action","DEPOT_COPY_PERSISTED") end,1)
            end)
          end)
        end)
      end)
    end)
  end
  local function build(i)
    local q=actions[i]
    if not q then return purchase() end
    ask({kind="road_quote",request=q},function(offer)
      ask({kind="command",command={kind="road_commit",request=q,quote=offer.value,revision=offer.revision}},
        function() build(i+1) end)
    end)
  end
  command({kind="road_build",first=first,last=last},function() build(1) end)
end
core.after(.2,test)
