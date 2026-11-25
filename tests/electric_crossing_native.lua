-- Default generated worker, genuine layered construction, depot purchase,
-- and a moving electric train in an actual graphical Luanti client.
local owner="IndustryLayoutsQA"
local reload=core.deserialize(storage:get_string("electric_crossing_qa"),true)
local spot
local function vacant(x,z,h)
  local id=Sim.id(x,z)
  local t=id and S.tiles[id]
  if not t or t.stock_void or t.terrain=="water" or t.build or t.owner or t.house or t.site or t.wood
      or t.stock_landmark or t.stock_industry or (S.stock_farm_fields and S.stock_farm_fields[id]) then return end
  local slope,y=api.terrain.tile(id)
  return slope==0 and (h==nil or h==y) and y
end
for row=8,Sim.H-11 do
  for col=8,Sim.W-17 do
    local h=vacant(col,row)
    local good=h~=nil
    if good then
      for i=0,13 do if not vacant(col+i,row,h) then good=false;break end end
      for i=-3,4 do if not vacant(col+7,row+i,h) then good=false;break end end
      for i=-2,2 do if not vacant(col+5,row+i,h) then good=false;break end end
    end
    if good then spot={x=col,z=row,h=h};break end
  end
  if spot then break end
end
spot=reload and reload.spot or spot
assert(spot,"No ordinary naturally flat area for both approaches")
local function id(dx,dz) return assert(Sim.id(spot.x+dx,spot.z+(dz or 0))) end
local crossing=id(7)
local function query(q,on,expected)
  q.player=owner
  assert(authority.query(q,function(r)
    if expected~=nil then assert(r.ok==expected,tostring(r.why)) else assert(r.ok,r.why) end
    on(r)
  end))
end
local function command(c,f)
  query({kind="company"},function(r)
    c.revision=r.revision;query({kind="command",command=c},f)
  end)
end
local function build(domain,req,f)
  query({kind=domain.."_quote",request=req},function(r)
    query({kind="command",command={kind=domain.."_commit",revision=r.revision,request=req,
      token=r.value.token,quote=r.value}},f)
  end)
end
local function until_(label,p,f,n)
  local v=p()
  if v then f(v);return end
  n=n or 0
  assert(n<200,label)
  core.after(.23,function() until_(label,p,f,n+1) end)
end
local function live(viewer)
  viewer:set_pos({x=2*(spot.x+7)-5,y=spot.h+5,z=2*spot.z-8})
  local target={x=2*(spot.x+7)+.5,y=spot.h+.7,z=2*spot.z+.5}
  local p=viewer:get_pos()
  local dx,dy,dz=target.x-p.x,target.y-p.y-1.625,target.z-p.z
  viewer:set_look_horizontal(math.atan2(-dx,dz))
  viewer:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  if reload then
    until_("Reopened ELRL crossing lost its typed rail, mixed ways or live train",function()
      local state=assert(OwnerCheckpoint.read())
      local c=state.tiles[crossing].level_crossing
      local second=state.tiles[id(5)].level_crossing
      local x,z=Sim.xy(crossing)
      local wire=core.get_node_or_nil({x=2*x+1,y=spot.h+2,z=2*z})
      if not (c and c.railtype==1 and c.tramtype==1 and c.roadtype==0 and second and second.railtype==1 and wire
        and wire.name:match("^luanttd_core:electric_crossing_wire_1_")) then return end
      for _,ref in ipairs(core.get_objects_inside_radius(target,4)) do
        local ent=ref:get_luaentity()
        local pick=ent and ent.luanttd_vehicle
        if pick and pick.kind=="rail" and pick.id==reload.vehicle then return true end
      end
    end,function() core.log("action","PASS NATIVE ELECTRIC REOPEN: same stock ELRL train, mixed crossing, wire and independent road build") end)
    return
  end
  local task={}
  local function add(domain,args) task[#task+1]=function(done) build(domain,args,done) end end
  task[#task+1]=function(done) command({kind="road_build",first=id(7,-3),last=id(7,4)},done) end
  add("road",{tool="tram_lay",axis=1,first=id(7,-3),last=id(7,4)})
  add("rail",{tool="track",first=id(1),last=id(13),track=0,railtype=1})
  task[#task+1]=function(done) command({kind="road_build",first=id(5,-2),last=id(5,2)},done) end
  add("rail",{tool="depot",first=id(0),direction=2,railtype=1})
  add("rail",{tool="station",first=id(2),last=id(4),axis=0,length=3,tracks=1,railtype=1})
  add("rail",{tool="station",first=id(10),last=id(12),axis=0,length=3,tracks=1,railtype=1})
  local function run(i)
    if task[i] then task[i](function() run(i+1) end);return end
    local s=assert(OwnerCheckpoint.read())
    local c=s.tiles[crossing].level_crossing
    assert(c and c.railtype==1 and c.tramtype==1 and c.roadtype==0 and c.top==spot.h)
    local second=s.tiles[id(5)].level_crossing
    assert(second and second.railtype==1 and second.roadtype==0 and second.tramtype==nil)
    local request={mode="rail",operation="buy",depot=id(0),parts={23,27}}
    build("transport",request,function(r)
      local vehicle=r.value.id
      local a,b=s.tiles[id(2)].rail_station_id,s.tiles[id(10)].rail_station_id
      command({kind="transport_start",mode="rail",vehicle=vehicle,first=b,second=a},function()
        local seen={}
        until_("A real SH '30' never used both sides of the mixed crossing",function()
          local now=assert(OwnerCheckpoint.read())
          local tile=now.tiles[crossing].level_crossing
          local x,z=Sim.xy(crossing)
          local tram=core.get_node_or_nil({x=2*x,y=spot.h+2,z=2*z})
          local elrl=core.get_node_or_nil({x=2*x+1,y=spot.h+2,z=2*z})
          local gate=core.get_node_or_nil({x=2*x,y=spot.h+1,z=2*z})
          if not (tram and tram.name=="luanttd_core:tramway_crossing_1" and elrl
              and elrl.name:match("^luanttd_core:electric_crossing_wire_1_")) then return end
          if gate and gate.name=="luanttd_core:level_crossing_0_closed" then seen.closed=true end
          if gate and gate.name=="luanttd_core:level_crossing_0_open" then seen.open=true end
          for _,ref in ipairs(core.get_objects_inside_radius(target,3)) do
            local ent=ref:get_luaentity()
            local pick=ent and ent.luanttd_vehicle
            if pick and pick.kind=="rail" and pick.id==vehicle then
              local at=ref:get_pos()
              if at and at.x<target.x-.6 then seen.before=true end
              if at and at.x>target.x+.6 then seen.after=true end
            end
          end
          return tile.railtype==1 and seen.before and seen.after and seen.closed and seen.open
        end,function()
          storage:set_string("electric_crossing_qa",core.serialize({spot=spot,vehicle=vehicle}))
          core.log("action","NATIVE ELRL CROSSING FRAME electric-rail-and-tram")
          core.after(1.2,function()
            core.log("action","PASS NATIVE ELECTRIC CROSSING: actual SH '30' on mixed road/track, both wire layers and both gate states")
          end)
        end)
      end)
    end)
  end
  run(1)
end
until_("Normal generated interactive worker did not start",function()
  local player=core.get_player_by_name(owner)
  return player and authority and authority.status()=="owned" and #world.hotbar_layout(player)>0 and player
end,live)
