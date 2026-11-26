-- Appended to the disposable native graphical game only. Build via
-- normal priced worker commands without editing terrain or placing nodes.
local terrain=dofile(mod.."/openttd/terrain.lua")
local player_name="StockResidentialQA"
local function begin()
  local player=core.get_player_by_name(player_name)
  if not (player and authority and authority.status()=="owned" and #world.hotbar_layout(player)>0) then
    core.after(.25,begin);return
  end
  local function wait(accept,then_,error_,n)
    if accept() then then_();return end
    assert(n<150,error_())
    core.after(.16,function() wait(accept,then_,error_,n+1) end)
  end
  local function wait_for(accept,then_,error_) wait(accept,then_,error_,0) end
  local function ask(req,callback)
    req.player=player_name
    assert(authority.query(req,function(r)
      assert(r.ok,req.kind..": "..tostring(r.why));callback(r)
    end))
  end
  local function action(req,done)
    ask({kind="transport_quote",request=req},function(q)
      assert(q.value.cost>0)
      ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},done)
    end)
  end
  local view=assert(OwnerCheckpoint.read())
  local reopen=core.settings:get_bool("luanttd_qa_canal_dikes_reopen",false)
  local site=reopen and assert(core.deserialize(storage:get_string("canal_dikes_qa"),true))
  if not site then
    local function flat(x,z,same)
      local t=view.tiles[Sim.id(x,z)]
      local slope,level=terrain.tile(view.corner_grid,x,z)
      return slope==0 and level==same and (t.terrain=="grass" or t.terrain=="hill") and not
          (t.build or t.owner or t.house or t.site or t.stock_industry or t.stock_object)
    end
    for z=5,Sim.H-10 do
      for x=5,Sim.W-5 do
        local _,level=terrain.tile(view.corner_grid,x,z)
        local dry=true
        for dz=-1,5 do for dx=-2,3 do
          if not flat(x+dx,z+dz,level) then dry=false;break end
        end if not dry then break end end
        if dry then site={x=x,z=z,level=level};break end
      end
      if site then break end
    end
    assert(site,"Need a flat dry 6x7 area for the paid canal and bridge fixture")
    storage:set_string("canal_dikes_qa",core.serialize(site))
  end
  local x,z,level=site.x,site.z,site.level
  local function id(dx,dz) return assert(Sim.id(x+dx,z+dz)) end
  local function camera(dx,dz)
    player:set_pos({x=2*x+dx,y=level+4,z=2*z+dz})
    player:set_look_horizontal(math.atan2(dx-.5,-dz+.5))
    player:set_look_vertical(.49)
  end
  camera(-3.5,-4.2)
  local function node(dx,dz,ox,oz,y)
    return core.get_node({x=2*(x+dx)+(ox or 0),z=2*(z+dz)+(oz or 0),y=level+(y or 1)}).name
  end
  local function at_mask(mask) return node(0,0,0,1)=="luanttd_core:canal_dike_"..mask end
  local function with_mask(mask,then_)
    wait_for(function()return at_mask(mask)end,then_,function()
      return "Expected canal dike "..mask..", found "..node(0,0,0,1)
    end)
  end
  local function frame(label,then_)
    core.log("action","NATIVE CANAL DIKES FRAME "..label)
    core.after(1.9,then_)
  end
  local function facilities(finished)
    wait_for(function()
      return at_mask(137) and node(0,0,0,0):find("bridge_wood",1,true)
        and node(0,0,1,0)=="luanttd_core:ship_buoy_under"
        and node(0,0,1,1,0):find("water",1,true)
        and node(0,4,0,0):find("ship_depot",1,true)
        and node(0,4,0,1):find("canal_dike_",1,true)
    end,function()
      local water=node(0,0,1,1,0)
      local deck=node(0,0,0,0)
      local foot=node(-1,0,1,1,0)
      -- A low deck has no whole vertical room for a separate centre
      -- pier on the canal itself. Its foundation stays on the dry span.
      assert(deck:find("bridge_wood",1,true) and water:find("water",1,true))
      core.log("action",("NATIVE CANAL DIKES LAYERS %s | %s | %s | %s | %s | %s"):format(
        deck,node(0,0,1,0),node(0,0,0,1),water,foot,node(0,4,0,1)))
      finished()
    end,function()
      return ("Bridge, buoy, dike, water, depot/dike failed: %s %s %s %s %s %s"):format(
        node(0,0,0,0),node(0,0,1,0),node(0,0,0,1),node(0,0,1,1,0),node(0,4,0,0),node(0,4,0,1))
    end)
  end
  if reopen then
    facilities(function()core.log("action","PASS NATIVE CANAL DIKES REOPEN")end)
    return
  end
  local function canal(a,b,done)
    action({mode="ship",operation="waterwork",kind="canal",tile=a,last=b},done)
  end
  local function bridge()
    action({mode="ship",operation="build",kind="buoy",tile=id(0,0)},function()
      action({mode="road",operation="bridge",tile=id(-2,0),last=id(3,0),style=0},function(r)
        assert(r.value.deck==level+1,"Fixture expected a one-level deck")
        canal(id(0,4),id(1,5),function()
          action({mode="ship",operation="build",kind="depot",tile=id(0,4),axis=0},function()
            facilities(function()
              frame("bridge-and-buoy",function()
                player:set_pos({x=x*2-3.0,y=level+4,z=z*2+4*2-3.9})
                player:set_look_horizontal(math.atan2(-3.5,4.4))
                player:set_look_vertical(.51)
                frame("depot",function()core.log("action","PASS NATIVE CANAL DIKES")end)
              end)
            end)
          end)
        end)
      end)
    end)
  end
  local function build_witness()
    canal(id(0,0),id(1,1),function()
      with_mask(137,function()
        frame("joined",function()
          ask({kind="terrain_quote",request={operation="bulldoze",first=id(1,1)}},function(c)
            ask({kind="command",command={kind="terrain_commit",token=c.value.token,revision=c.revision}},function()
              with_mask(649,function()
                frame("corner",function()canal(id(1,1),id(1,1),function()
                  with_mask(137,bridge)
                end)end)
              end)
            end)
          end)
        end)
      end)
    end)
  end
  ask({kind="company"},function(q)
    ask({kind="command",command={kind="speed",speed=0,revision=q.revision}},function()
      ask({kind="terrain_quote",request={operation="bulldoze",first=id(-2,-1),last=id(3,5)}},function(c)
        ask({kind="command",command={kind="terrain_commit",token=c.value.token,revision=c.revision}},build_witness)
      end)
    end)
  end)
end
core.after(.25,begin)
