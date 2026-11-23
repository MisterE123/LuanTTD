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
local configured
V.orders.rail={
  read=function()
    return {items={{id=1,label="Rail X",cargo={load=0,unload=0}},
      {id=2,label="Rail Y",cargo={load=configured or 0,unload=0}}},
      targets={},cargo_rules=Cargo,revision=configured or 0}
  end,
  edit=function(n,id,revision,kind,row,value)
    assert(n=="E" and id==1 and row==2 and kind=="load" and revision==0)
    assert(value==3);configured=value;return true,"Full load any."
  end,
}
assert(V.open(p,"rail",1) and open.b:find("Cargo rules for selected order",1,true))
local before=open
fn(p,before.key,{[field(before,"row")]="2"})
assert(open~=before)
fn(p,open.key,{[field(open,"choose_load")]="3",[field(open,"apply_load")]=true})
assert(configured==3 and open.b:find("Full load any.",1,true))
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
V.open(p,"road",1)
fn(p,open.key,{quit=true})
local closed_panel=open
answer("orders",receipt)
assert(open==closed_panel)
print("PASS existing vehicle form uses a worker receipt, ignores double submission and never reopens a closed panel")
