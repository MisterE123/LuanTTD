-- Exercise the ordinary worker's paid UI commands, not a direct map edit.
core.register_on_mods_loaded(function()
  assert(authority)
  local name="Coastal QA"
  local function open(t)
    return t and t.terrain=="water" and t.water_class=="sea" and not (t.wood or t.coastal_water or
      t.stock_void or t.build or t.ship or t.stock_industry or t.stock_water_rocks or t.rail_tracks)
  end
  local tile,x,z
  for v=16,Sim.H-16,3 do
    if tile then break end
    for u=16,Sim.W-16,3 do
      local valid=true
      for y=v-1,v+1 do for i=u-1,u+1 do if not open(S.tiles[Sim.id(i,y)]) then valid=false end end end
      if valid then tile,x,z=Sim.id(u,v),u,v;break end
    end
  end
  assert(tile,"Regression requires an actual patch of ordinary open sea")
  local function query(req,action)
    assert(type(req)=="table")
    local function attempt()
      if not authority.query(req,function(r) assert(r.ok,tostring(r.why));action(r) end) then core.after(.08,attempt) end
    end
    attempt()
  end
  local function command(revision,c,action)
    c.revision=revision
    query({kind="command",player=name,command=c},action)
  end
  local function view(action)
    query({kind="snapshot",x=x,z=z,w=1,h=1},function(r)
      assert(r.value.tiles[1].id==tile)
      action(r.value.tiles[1].ground,r.day)
    end)
  end
  local function wait_day(goal,action)
    query({kind="clock"},function(r)
      if r.day>=goal then action(r) else core.after(.15,function() wait_day(goal,action) end) end
    end)
  end
  core.after(.10,function()
    command(nil,{kind="company_open"},function(created)
      wait_day(created.day+7,function(warm)
        command(warm.revision,{kind="speed",speed=0},function(paused)
          view(function(ground)
            assert(ground=="water")
            query({kind="terrain_quote",player=name,request={operation="bulldoze",first=tile}},function(q)
              command(q.revision,{kind="terrain_commit",token=q.value.token},function(removed)
                local day=removed.day
                view(function(cleared)
                  assert(cleared=="grass","Paid bulldozer did not clear the selected water: "..tostring(cleared))
                  command(removed.revision,{kind="speed",speed=4},function(restarted)
                    wait_day(day+5,function()
                      view(function(flooded,end_day)
                        assert(flooded=="water","Open sea neighbor did not reflood after the paid clear")
                        core.log("action",("PASS LIVE OCEAN EDIT tile=%d warm=%d cleared=%d flooded=%d"):format(
                          tile,warm.day,day,end_day))
                        core.request_shutdown("Live sea edit proved",false,0)
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
