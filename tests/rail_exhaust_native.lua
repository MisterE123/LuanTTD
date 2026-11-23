-- Loaded only by the disposable graphical fixture. The actual game
-- worker owns the fresh generated world, builds, purchase and orders.
local function begin_steam()
  local viewer=core.get_player_by_name("OrdinaryWorker")
  if not (viewer and authority and authority.status()=="owned" and #world.hotbar_layout(viewer)>0) then
    core.after(.2,begin_steam);return
  end
  local owner=viewer:get_player_name()
  local x,z,h
  for v=4,Sim.H-5 do
    for u=4,Sim.W-22 do
      local base,flat
      for dx=0,18 do
        local id=Sim.id(u+dx,v)
        local t=S.tiles[id]
        local mask,level=api.terrain.tile(id)
        if mask~=0 or base and level~=base or t.terrain=="water" or t.wood or t.house or
            t.site or t.owner or t.stock_industry or t.stock_void or t.stock_landmark or t.build then flat=false;break end
        base,flat=level,true
      end
      if flat then x,z,h=u,v,base;break end
    end
    if x then break end
  end
  assert(x,"No flat site for the steam service")
  local function tile(o) return Sim.id(x+o,z) end
  viewer:set_pos({x=2*x+13.5,y=h+1.62,z=2*z-4.2})
  viewer:set_look_horizontal(0)
  viewer:set_look_vertical(.37)
  viewer:set_fov(61,false,0)
  viewer:hud_set_flags({hotbar=false,crosshair=false})
  local rail={tool="track_line",first=tile(1),last=tile(18),track=0}
  local stations={
    {tool="depot",first=tile(0),direction=2},
    {tool="station",first=tile(3),last=tile(5),axis=0,length=3,tracks=1},
    {tool="station",first=tile(14),last=tile(16),axis=0,length=3,tracks=1},
  }
  local send=core.add_particle
  local count,announced=0,false
  core.add_particle=function(p)
    send(p)
    local t=type(p.texture)=="table" and p.texture.name or ""
    if t=="bl_rail_steam.png" and p.playername==owner then
      local engine
      for _,ref in ipairs(core.get_objects_inside_radius(p.pos,1.4)) do
        local e=ref:get_luaentity()
        local pos=ref:get_pos()
        if e and pos and e.name=="luanttd_core:dispatch_steam" and
            p.pos.y-pos.y>.65 and p.pos.y-pos.y<.81 then engine=true;break end
      end
      assert(engine,"Steam puff did not originate at the native Kirby chimney")
      count=count+1
      if count>=2 and p.pos.x>2*x+11.5 and p.pos.x<2*x+15 and not announced then
        announced=true
        core.log("action",("PASS NATIVE RAIL EXHAUST: %d chimney pulses from worker-owned Kirby; staged inside the graphical view"):format(count))
      end
    end
  end
  local function ask(req,cb)
    req.player=owner
    assert(authority.query(req,function(r) assert(r.ok,r.why);cb(r) end))
  end
  local function command(c,done)
    ask({kind="company"},function(q)
      c.revision=q.revision
      ask({kind="command",command=c},done)
    end)
  end
  local function build(i)
    if i>#stations then
      ask({kind="transport_quote",request={mode="rail",operation="buy",depot=tile(0),parts={0,27}}},function(q)
        ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},function(p)
          command({kind="transport_start",mode="rail",vehicle=p.value.id,first=2,second=1},function()end)
        end)
      end)
      return
    end
    ask({kind="rail_quote",request=stations[i]},function(q)
      ask({kind="command",command={kind="rail_commit",token=q.value.token,revision=q.revision}},function() build(i+1) end)
    end)
  end
  ui.select_tool(viewer,"rail_autotrack")
  assert(ui.begin_autorail(viewer,rail.first,{x=2*(x+1)+.5,z=2*z+.5}))
  api.on_worker_build=function(name,ids)
    assert(name==owner and #ids==18)
    api.on_worker_build=nil
    build(1)
  end
  ui.end_autorail(viewer,rail.last,{x=2*(x+18)+.5,z=2*z+.5})
end
core.after(.3,begin_steam)
