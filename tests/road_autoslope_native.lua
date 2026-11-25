-- Active bus route in a normal generated worker world, with exact native terrain
-- commands through the authority endpoint. No imported terrain or finance.
local owner="IndustryLayoutsQA"
local place
local function clear(x,z,h)
  local id=Sim.id(x,z)
  local t=id and S.tiles[id]
  if not t or t.stock_void or t.terrain=="water" or t.build or t.owner or t.house or t.site
      or t.stock_landmark or t.stock_industry or t.wood or (S.stock_farm_fields and S.stock_farm_fields[id]) then return end
  local slope,y=api.terrain.tile(id)
  return slope==0 and y>0 and (h==nil or h==y) and y
end
for z=8,Sim.H-9 do
  for x=8,Sim.W-16 do
    local h=clear(x,z)
    if h then
      local okay=true
      for dz=-1,1 do for dx=-1,9 do
        if not clear(x+dx,z+dz,h) then okay=false;break end
      end end
      if okay then place={x=x,z=z,h=h};break end
    end
  end
  if place then break end
end
assert(place,"No naturally high flat testing strip")
local function at(d,z) return Sim.id(place.x+d,place.z+(z or 0)) end
local function query(q,f)
  q.player=owner
  assert(authority.query(q,function(r) assert(r.ok,r.why);f(r) end))
end
local function command(c,f)
  query({kind="company"},function(r)
    c.revision=r.revision;query({kind="command",command=c},f)
  end)
end
local function build(request,f)
  query({kind="road_quote",request=request},function(q)
    query({kind="command",command={kind="road_commit",revision=q.revision,request=request,
      token=q.value.token,quote=q.value}},f)
  end)
end
local function until_(label,p,f,n)
  local v=p()
  if v then f(v);return end
  n=n or 0
  assert(n<220,label)
  core.after(.25,function() until_(label,p,f,n+1) end)
end
local function finance()
  local s=assert(OwnerCheckpoint.read())
  return s.companies[owner],s
end
local function lower(q,f)
  query({kind="terrain_quote",request={operation="lower",first=q}},function(r)
    assert(r.value.cost==750,"Two neighboring road foundations and one physical corner must be charged")
    query({kind="command",command={kind="terrain_commit",revision=r.revision,token=r.value.token}},f)
  end)
end
local use_waypoint=core.settings:get_bool("luanttd_qa_road_autoslope_waypoint",false)
local function run(viewer)
  viewer:set_pos({x=2*place.x+10,y=place.h+8,z=2*place.z-9})
  viewer:set_look_horizontal(0);viewer:set_look_vertical(.57)
  local tasks={}
  local vehicle,waypoint
  local function add(f) tasks[#tasks+1]=f end
  local function road(req) add(function(done) build(req,done) end) end
  local function lay(first,last)
    add(function(done) command({kind="road_build",first=first,last=last},done) end)
  end
  lay(at(1),at(9))
  -- Drive-through stops preserve the leaving vehicle's heading. Explicit
  -- turning loops beyond both platforms make a repeatable service, not
  -- just a one-way route whose first fare is also its last.
  for _,x in ipairs({1,8}) do
    lay(at(x),at(x,1))
    lay(at(x,1),at(x+1,1))
    lay(at(x+1,1),at(x+1))
  end
  road({tool="road_depot",first=at(0)})
  road({tool="road_station",first=at(3)})
  road({tool="road_station",first=at(7)})
  if use_waypoint then road({tool="road_waypoint",first=at(5),axis=0}) end
  add(function(done)
    query({kind="depot",mode="road",depot=at(0)},function(list)
      local buy
      for _,offer in ipairs(list.value.offers) do
        if offer.request.cargo=="passenger" then buy=offer.request;break end
      end
      assert(buy)
      command(buy,function(r) vehicle=r.value;done() end)
    end)
  end)
  if use_waypoint then add(function(done)
    local _,s=finance()
    waypoint=assert(s.tiles[at(5)].road_waypoint_id)
    query({kind="orders",mode="road",vehicle=vehicle},function(r)
      query({kind="command",command={kind="vehicle_order",mode="road",vehicle=vehicle,
        operation="append",tile=at(5),order_revision=r.value.revision,revision=r.revision}},done)
    end)
  end) end
  for _,site in ipairs({7,3}) do
    add(function(done)
      local _,s=finance()
      command({kind="road_order_add",vehicle=vehicle,station=assert(s.tiles[at(site)].station)},done)
    end)
  end
  add(function(done) command({kind="road_toggle",vehicle=vehicle},done) end)
  add(function(done) lower(at(5),done) end)
  local function road_painted()
    local _,s=finance()
    local shape,base=dofile(mod.."/openttd/terrain.lua").tile(s.corner_grid,place.x+5,place.z)
    local x,z=2*(place.x+5),2*place.z
    local physical=core.get_node_or_nil({x=x,y=place.h,z=z})
    if not (shape==7 and base==place.h-1 and physical and physical.name:find("foundation",1,true)) then return end
    if use_waypoint then
      local t=s.tiles[at(5)]
      assert(t.road_waypoint_id==waypoint and t.road_terminal_level==place.h)
      local marker=core.get_node_or_nil({x=x,y=place.h+1,z=z})
      if not marker or not marker.name:find("road_waypoint",1,true) then return end
    end
    return true
  end
  local function verify()
    until_("Road and its support were not repainted",road_painted,function()
      local deck={x=2*(place.x+5)+.5,y=place.h+.55,z=2*place.z+.5}
      until_("The bus never traversed the edited terrain and recorded its Go via order",function()
        if use_waypoint then
          local _,s=finance()
          local v=assert(s.fleet[vehicle])
          assert(v.orders[1].station=="waypoint:"..waypoint,"The original Go via order was lost")
          if v.last_road_waypoint~=waypoint then return end
        end
        for _,ref in ipairs(core.get_objects_inside_radius(deck,1.35)) do
          local obj=ref:get_luaentity()
          local pick=obj and obj.luanttd_vehicle
          local pos=pick and pick.kind=="road" and pick.id==vehicle and ref:get_pos()
          if pos and math.abs(pos.y-deck.y)<.24 then return pos end
        end
      end,function()
        core.log("action","NATIVE ROAD TERRAFORM FRAME "..(use_waypoint and "waypoint-autoslope-live" or "road-autoslope-live"))
        core.after(1.2,function()
          core.log("action","PASS NATIVE ROAD AUTOSLOPE: moving bus crossed above two paid foundations without moving its road or waypoint")
        end)
      end)
    end)
  end
  local function step(i)
    if tasks[i] then tasks[i](function()step(i+1)end) else verify() end
  end
  step(1)
end
until_("Ordinary worker client not ready",function()
  local viewer=core.get_player_by_name(owner)
  return viewer and authority and authority.status()=="owned" and #world.hotbar_layout(viewer)>0 and viewer
end,run)
