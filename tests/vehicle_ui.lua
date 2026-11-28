-- Shared frontend integration against mock Luanti ObjectRefs and player.
-- Transport simulation has separate runtime and native tests.
local open,fn,render
local hits,players={},{ }
local function copy(v) return {x=v.x,y=v.y,z=v.z} end
local function obj(pos)
  return {pos=copy(pos),get_pos=function(self) return self.pos end,
    remove=function(self) self.pos=nil end,
    set_properties=function(self,x) self.properties=x end,
    is_player=function() return false end,
    get_luaentity=function(self) return self.lua end,
    lua={},move_to=function(self,v) self.pos=copy(v) end}
end
core={
  formspec_escape=function(s) return tostring(s) end,
  register_entity=function(name,def) render=def;assert(name=="luanttd_core:vehicle_camera") end,
  add_entity=function(pos) return obj(pos) end,
  register_on_player_receive_fields=function(f) fn=f end,
  get_connected_players=function() return players end,
  show_formspec=function(n,form,b) open={n=n,key=form,b=b} end,
  close_formspec=function() open=nil end,
  explode_textlist_event=function(s) return {index=tonumber(s)} end,
  raycast=function()
    local i=0
    return function() i=i+1;return hits[i] end
  end,
}
local function player(n)
  local p=obj({x=12,y=15,z=11})
  p.get_player_name=function() return n end
  p.get_look_dir=function() return {x=0,y=-.5,z=.5} end
  p.get_properties=function() return {eye_height=2} end
  p.set_attach=function(self,o) self.parent=o end
  p.get_attach=function(self) return self.parent end
  p.set_detach=function(self) self.parent=nil end
  p.get_look_horizontal=function() return .75 end
  p.get_look_vertical=function() return .4 end
  p.set_look_horizontal=function(self,a) self.yaw=a end
  p.set_look_vertical=function(self,a) self.pitch=a end
  p.hud_add=function(self,def) self.label=def.text;return 3 end
  p.hud_remove=function(self,i) assert(i==3);self.label=nil end
  p.set_pos=p.move_to
  return p
end
local depot,visited,returned=27,0,0
local s={
  fleet={[1]={owner="E",id=1,home_depot=depot,name="Regal"},
    [88]={owner="Foreign",id=88,home_depot=depot,name="Other company's bus"}},
  stock_small_airports={[25]={origin=depot}},
  stock_owned_aircraft={owner="E",hangar=25,id=1,name="Sampson"},
  stock_ship_depots={[depot]={tiles={depot}}},
  stock_owned_ferry={owner="E",engine_id=207,depot=depot},
  stock_coal_ship={owner="E",depot=depot},
  tram_pilot={owner="E",depot=depot},
  tiles={[depot]={h=1}},
}
local rail={id=1,unit_number=1,owner="E",depot=depot}
local api={s=s,Sim={xy=function(i) assert(i==depot);return 3,4 end},
  rail_owned={get=function(_,name,id) if name=="E" and id==1 then return rail end end,
    list=function(_,name,id) return name=="E" and id==depot and {rail} or {} end},
  save=function() visited=visited+1 end}
local V=dofile("mods/luanttd_core/vehicle_ui.lua")(api)
local p,f=player("E"),player("Foreign")
players={p,f}
local edits=0
V.orders.road={
  read=function(name,id)
    assert(name=="E" and id==1)
    return {items={{id=2,label="West"},{id=3,label="East"}},targets={{id=5,label="Central"}},
      active=2,revision=edits}
  end,
  edit=function(n,id,rev,op,row,dest)
    assert(n=="E" and id==1 and rev==edits and op=="append" and row==2 and dest==5)
    edits=edits+1
    return true,"Added Central."
  end,
}
local function field(o,cmd) return o.b:match("(v%d+_"..cmd..");") end
local v=obj({x=5,y=2,z=7})
V.track("road",1,v.pos,v)
assert(v.properties.pointable and not render.initial_properties.pointable)
hits={{type="object",ref=v}}
assert(V.pick(p,90).kind=="road")
table.insert(hits,1,{type="node"});assert(not V.pick(p,90))
assert(not V.open(f,"road",1))
assert(V.open(p,"road",1))
local old=open
fn(p,old.key,{[field(old,"row")]="2"})
fn(p,old.key,{[field(old,"append")]=true})
assert(edits==1 and visited==1 and open.b:find("Added Central.",1,true))
fn(p,old.key,{[field(old,"append")]=true}) -- obsolete rendered form token
assert(edits==1)
local opts={{"road",1},{"rail",1},{"tram",1},{"ship","ferry"},{"ship","coal"},{"air",1}}
for _,a in ipairs(opts) do
  local pos={x=8,y=5,z=12}
  V.track(a[1],a[2],pos,obj(pos))
  assert(V.open(p,a[1],a[2]))
  fn(p,open.key,{[field(open,"follow")]=true})
  assert(p.label and math.abs(p.parent.pos.x-8-2.8*math.sin(.75))<.01 and p.parent.pos.y==8.6 and V.following(p))
  V.track(a[1],a[2],{x=10,y=6,z=13})
  V.step(.1)
  assert(math.abs(p.parent.pos.x-10-2.8*math.sin(.75))<.01 and p.parent.pos.y==9.6)
  V.step(1) -- hidden vehicle keeps the last observed camera, not its home depot
  assert(p.parent.pos.y==9.6)
  assert(V.exit(p) and not p.parent and not p.label)
  assert(p.pos.x==12 and p.pos.y==15 and p.yaw==.75 and p.pitch==.4)
end
local kinds={"road","rail","tram","ship","air"}
for _,kind in ipairs(kinds) do
  assert(V.depot(p,kind,kind=="air" and 25 or depot,function() returned=returned+1 end))
  assert(not open.b:find("Other company's bus",1,true))
  fn(p,open.key,{[field(open,"follow")]=true})
  assert(V.following(p))
  V.exit(p)
end
V.depot(p,"rail",depot,function() returned=returned+1 end)
fn(p,open.key,{[field(open,"open")]=true})
assert(open.b:find("Train 1",1,true))
fn(p,open.key,{[field(open,"depot")]=true})
fn(p,open.key,{[field(open,"return")]=true})
assert(returned==1)
V.follow(p,"road",1);s.fleet[1]=nil;V.step(.2)
assert(not V.following(p) and not p.parent)
local Cargo=dofile("mods/luanttd_core/openttd/rail_order_cargo.lua")
local configured,stop_policy
V.orders.rail={
  read=function()
    return {items={{id=1,label="Rail X",cargo={load=0,unload=0}},
      {id=2,label="Rail Y",cargo={load=configured or 0,unload=0,nonstop=stop_policy or 1}},
      {id=3,label="Rail Z · Automatic stop",automatic=true}},
      targets={},cargo_rules={load=Cargo.load,unload=Cargo.unload,nonstop=Cargo.stop_choices},revision=configured or 0}
  end,
  edit=function(n,id,revision,kind,row,value)
    assert(n=="E" and id==1 and row==2)
    if kind=="nonstop" then
      assert(revision==3 and value==0);stop_policy=value;return true,"Stops at intermediate stations."
    end
    assert(kind=="load" and revision==0 and value==3)
    configured=value;return true,"Full load any."
  end,
}
assert(V.open(p,"rail",1) and open.b:find("Cargo rules for selected order",1,true))
local before=open
fn(p,before.key,{[field(before,"row")]="2"})
assert(open~=before)
fn(p,open.key,{[field(open,"choose_load")]="3",[field(open,"apply_load")]=true})
assert(configured==3 and open.b:find("Full load any.",1,true))
assert(open.b:find("V_TOKEN",1,true)==nil and open.b:find("Stop at intermediate stations",1,true))
fn(p,open.key,{[field(open,"choose_nonstop")]="1",[field(open,"apply_nonstop")]=true})
assert(stop_policy==0 and open.b:find("Stops at intermediate stations.",1,true))
fn(p,open.key,{[field(open,"row")]="3"})
assert(open.b:find("Automatic stop",1,true) and not open.b:find("Cargo rules for selected order",1,true))
print("PASS vehicle selection and ownership, stale form rejection, six actor types, depot entry, smooth follow anchor, cleanup and exact builder restore")
-- Use the real worker proxy against the asynchronous transport contract.
s.fleet[1]={owner="E",id=1,home_depot=depot,name="Regal"}
local queued
local worker_proxy=dofile("mods/luanttd_core/campaign_authority_order_proxy.lua")({
  query=function(req,done)
    assert(not queued,"forms issued competing worker requests")
    queued={req,done}
    return true
  end,
},"road")
V.orders.road=worker_proxy
local function answer(kind,r)
  local req,done=unpack(assert(queued))
  assert(req.kind==kind and req.player=="E")
  queued=nil
  done(r)
  return req
end
local receipt={ok=true,revision=9,value={items={{id=2,label="West"}},
  targets={{id=5,label="Central"}},revision="2:normal"}}
local old_saves=visited
assert(V.open(p,"road",1) and open.b:find("Loading vehicle orders",1,true))
answer("orders",receipt)
assert(open.b:find("Central",1,true))
local optimistic=open
fn(p,open.key,{[field(open,"append")]=true})
fn(p,open.key,{[field(open,"append")]=true})
assert(optimistic==open and visited==old_saves)
local req=answer("command",{ok=true,revision=10,why="Added Central on worker."})
assert(req.command.revision==9 and req.command.order_revision=="2:normal" and req.command.destination==5)
assert(open.b:find("Loading vehicle orders",1,true))
answer("orders",{ok=true,revision=10,value={items={{id=2,label="West"},{id=5,label="Central"}},targets={},revision="2:normal/5:normal"}})
assert(open.b:find("Added Central on worker.",1,true) and visited==old_saves)
local active,finished
api.world={
  begin_order_selection=function(who,mode) assert(who==p and mode=="vehicle");active=true;return true end,
  end_order_selection=function(who) assert(who==p and active);active=nil;finished=true end,
}
api.render={
  host_tile=function(id) if id==44 then return {station=5} end end,
  host_record=function(reg,id)
    assert(reg=="stations" and id==5);return {owner="E",mode="road",name="Central"}
  end,
}
assert(V.open(p,"road",1))
receipt.value.target_count=1
answer("orders",receipt)
assert(open.b:find("Pick in world",1,true) and open.b:find("Add selected destination",1,true))
fn(p,open.key,{[field(open,"pick_world")]=true})
assert(active and not open)
assert(V.world_order_preview(p,44)=="Add stop: Central")
V.pick_world_order(p,44)
V.pick_world_order(p,44) -- double input while the first is in flight
local picked=answer("command",{ok=true,revision=10,value={order_revision="2:normal/5:normal",count=2}})
assert(picked.command.destination==nil and picked.command.tile==44 and picked.command.order_revision=="2:normal")
V.pick_world_order(p,45)
V.finish_world_orders(p) -- End only after the pending order reports back
assert(active and not open)
picked=answer("command",{ok=true,revision=11,value={order_revision="2:normal/5:normal/6:normal",count=3}})
assert(picked.command.tile==45 and picked.command.order_revision=="2:normal/5:normal" and picked.command.revision==10)
assert(not active and finished and open.b:find("Loading vehicle orders",1,true))
answer("orders",receipt)
print("PASS graphical order modal submits real tiles and serializes picks; Done preserves the current list and last committed order")
V.open(p,"road",1)
fn(p,open.key,{quit=true})
local closed_panel=open
answer("orders",receipt)
assert(open==closed_panel)
print("PASS existing vehicle form uses a worker receipt, ignores double submission and never reopens a closed panel")
V.install_worker({query=function(req,done) assert(not queued);queued={req,done};return true end})
assert(V.open(p,"road",42))
assert(open.b:find("Loading vehicle",1,true))
answer("vehicle",{ok=true,value={mode="road",id=42,owner="E",label="Remote bus",depot=depot}})
assert(open.b:find("Remote bus",1,true))
answer("orders",receipt)
fn(p,open.key,{[field(open,"follow")]=true})
local locate=answer("vehicle",{ok=true,value={mode="road",id=42,owner="E",label="Remote bus",depot=depot,position={x=110,y=6,z=100}}})
assert(locate.locate==true and V.following(p) and p.parent.pos.x>100)
V.step(.8)
assert(V.following(p))
V.leave(p)
assert(not p.parent and not V.following(p))
print("PASS a company can open and follow an out-of-view vehicle; the worker supplies its real starting position")

do
  local posts,launch,depot_returns=0,nil,0
  V.orders.ship={fetch=function(_,_,complete) complete(nil,"ORDERS_UNAVAILABLE");return true end}
  local endpoint={
    query=function(req,done)
      posts=posts+1
      assert(req.mode=="ship" or req.command.mode=="ship")
      if req.kind=="depot" then
        done({ok=true,revision=39,value={vehicles={{id="ferry"}},targets={{id=5,label="Western Dock"},{id=6,label="Eastern Dock"}}}})
      else
        launch=req.command
        done({ok=false,why="DESTINATION_TILE_CHANGED"})
      end
      return true
    end,
  }
  local back={depot=depot,return_=function(selection)
    assert(selection.first==5 and selection.second==6)
    depot_returns=depot_returns+1
  end}
  local route=dofile("mods/luanttd_core/initial_vehicle_route.lua")
  back.initial=route.context(endpoint,p,"ship",depot,{id="ferry"},
    {targets={{id=5,label="Western Dock"},{id=6,label="Eastern Dock"}}})
  V.install_worker({query=function(req,done)
    assert(req.kind=="vehicle" and req.vehicle=="ferry")
    done({ok=true,value={mode="ship",id="ferry",owner="E",label="Company ferry",depot=depot,depot_key=depot}})
    return true
  end})
  api.render={
    host_tile=function(id) return {ship={kind="dock",station=id-100}} end,
    host_record=function(_,id) return {owner=id==5 or id==6 and "E" or "Other"} end,
  }
  api.render.host_record=function(reg,id)
    assert(reg=="stock_ship_stations")
    return {owner=(id==5 or id==6) and "E" or "Other"}
  end
  assert(V.open(p,"ship","ferry",back))
  assert(open.b:find("first service",1,true) and open.b:find("dropdown",1,true))
  assert(not field(open,"initial_start") and not open.b:find("ORDERS_UNAVAILABLE",1,true))
  fn(p,open.key,{[field(open,"initial_world")]=true})
  assert(active and not open)
  assert(V.world_order_preview(p,105)=="Pick first: Western Dock")
  V.pick_world_order(p,105)
  V.pick_world_order(p,109) -- foreign dock
  assert(V.world_order_preview(p,105)=="Choose a different second destination.")
  V.pick_world_order(p,105)
  V.pick_world_order(p,106)
  assert(posts==0,"pointing is not an order submission or dispatch")
  V.finish_world_orders(p)
  assert(not active and open.b:find("Both destinations selected",1,true))
  fn(p,open.key,{[field(open,"initial_start")]=true})
  assert(posts==2 and launch.first_tile==105 and launch.second_tile==106 and launch.revision==39 and launch.vehicle=="ferry")
  assert(open.b:find("A selected stop changed",1,true))
  fn(p,open.key,{[field(open,"depot")]=true})
  assert(depot_returns==1)
  print("PASS staged world orders reject foreign or repeated docks, start explicitly at fresh revision, and return to the same depot")
end

do
  V.orders.rail=dofile("mods/luanttd_core/campaign_authority_order_proxy.lua")({
    query=function(req,done) assert(not queued);queued={req,done};return true end,
  },"rail")
  V.install_worker({query=function(req,done)
    assert(req.kind=="vehicle" and req.vehicle==1 and req.mode=="rail")
    done({ok=true,value={mode="rail",id=1,owner="E",label="Train 1",depot=depot}})
    return true
  end})
  local towns={{id=3,label="West"},{id=4,label="Central"},{id=5,label="East"}}
  local function render_parked(items,targets,page,count)
    return answer("orders",{ok=true,revision=32,value={items=items,targets=targets or towns,
      parked=true,depot=depot,can_start=#items>=2,can_insert=true,revision="rail-parked:"..#items,
      target_page=page or 1,target_count=count or #towns}})
  end
  V.open(p,"rail",1)
  render_parked({},nil,1,99)
  assert(not field(open,"start_draft") and field(open,"targets_next"))
  fn(p,open.key,{[field(open,"targets_next")]=true})
  assert(render_parked({},towns,2,99).page==2 and field(open,"targets_prev"))
  fn(p,open.key,{[field(open,"append")]=true})
  local change=answer("command",{ok=true,revision=33})
  assert(change.command.operation=="append" and change.command.destination==3 and change.command.order_revision=="rail-parked:0")
  assert(render_parked({towns[1]},towns,2,99).page==2 and not field(open,"start_draft"))
  api.render={
    host_tile=function(tile) return tile==50 and {rail_station_id=4} end,
    host_record=function(reg,id)
      assert(reg=="stock_rail_stations" and id==4)
      return {owner="E",name="Central"}
    end,
  }
  fn(p,open.key,{[field(open,"pick_world")]=true})
  assert(V.world_order_preview(p,50)=="Add stop: Central")
  V.pick_world_order(p,50)
  local live=answer("command",{ok=true,revision=34,value={order_revision="rail-parked:2",count=2}})
  assert(live.command.tile==50 and live.command.destination==nil)
  V.finish_world_orders(p)
  render_parked({towns[1],towns[2]},towns,2,99)
  assert(field(open,"start_draft"))
  fn(p,open.key,{[field(open,"start_draft")]=true})
  local dispatch=answer("command",{ok=true,revision=35})
  assert(dispatch.command.kind=="transport_start" and dispatch.command.start_draft and
    dispatch.command.depot==depot and dispatch.command.draft_revision=="rail-parked:2")
  answer("orders",{ok=true,revision=35,value={items={towns[1],towns[2]},targets=towns,active=1,revision=0}})
  assert(not field(open,"start_draft") and open.b:find("Service started.",1,true))
  print("PASS parked railway editor pages destinations, mixes the list with validated tile picks, and starts only on explicit click")
end
