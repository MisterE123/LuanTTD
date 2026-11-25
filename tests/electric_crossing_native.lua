-- Default generated worker, genuine layered construction, depot purchase,
-- and a moving electric train in an actual graphical Luanti client.
local owner="IndustryLayoutsQA"
local terraform=core.settings:get_bool("luanttd_qa_rail_station_autoslope",false)
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
    local good=type(h)=="number" and (not terraform or h>0 and vacant(col+2,row-1,h) and vacant(col+3,row-1,h)
      and vacant(col+8,row-1,h) and vacant(col+9,row-1,h))
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
  local function aim(at,pos)
    viewer:set_pos(pos)
    local dx,dy,dz=at.x-pos.x,at.y-pos.y-1.625,at.z-pos.z
    viewer:set_look_horizontal(math.atan2(-dx,dz))
    viewer:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  end
  local target={x=2*(spot.x+7)+.5,y=spot.h+.7,z=2*spot.z+.5}
  aim(target,{x=target.x-5.5,y=spot.h+5,z=target.z-8.5})
  local slope=dofile(mod.."/openttd/terrain.lua")
  local function held(state,offset)
    local x,z=Sim.xy(id(offset))
    local shape,base,top=slope.tile(state.corner_grid,x,z)
    return shape==7 and base==spot.h-1 and top==spot.h
  end
  if reload then
    until_("Reopened ELRL crossing lost its typed rail, mixed ways or live train",function()
      local state=assert(OwnerCheckpoint.read())
      local c=state.tiles[crossing].level_crossing
      local second=state.tiles[id(5)].level_crossing
      if terraform then
        assert(held(state,3) and held(state,9) and state.tiles[id(3)].rail_station_id
          and state.tiles[id(9)].rail_tracks==1)
      end
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
        local function watch()
        until_("A real SH '30' never used both sides of the mixed crossing",function()
          local now=assert(OwnerCheckpoint.read())
          local tile=now.tiles[crossing].level_crossing
          local x,z=Sim.xy(crossing)
          local tram=core.get_node_or_nil({x=2*x,y=spot.h+2,z=2*z})
          local elrl=core.get_node_or_nil({x=2*x+1,y=spot.h+2,z=2*z})
          local gate=core.get_node_or_nil({x=2*x,y=spot.h+1,z=2*z})
          if terraform then
            local u,v=Sim.xy(id(3))
            local incline=core.get_node_or_nil({x=2*u,y=spot.h,z=2*v})
            local platform=core.get_node_or_nil({x=2*u,y=spot.h+1,z=2*v})
            if not (incline and incline.name=="luanttd_core:road_retaining"
                and platform and platform.name=="luanttd_core:stock_rail_platform_1") then return end
          end
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
          if terraform then
            local u,v=Sim.xy(id(9))
            for _,ref in ipairs(core.get_objects_inside_radius({x=2*u+.5,y=spot.h+.5,z=2*v+.5},1.25)) do
              local ent=ref:get_luaentity()
              local pick=ent and ent.luanttd_vehicle
              local p=pick and pick.kind=="rail" and pick.id==vehicle and ref:get_pos()
              if p and math.abs(p.y-(spot.h+.5))<.36 then seen.foundation=true end
            end
          end
          return tile.railtype==1 and seen.before and seen.after and seen.closed and seen.open
            and (not terraform or seen.foundation)
        end,function()
          storage:set_string("electric_crossing_qa",core.serialize({spot=spot,vehicle=vehicle}))
          local function finish(frame)
            core.log("action","NATIVE ELRL CROSSING FRAME "..frame)
            core.after(1.2,function()
              core.log("action","PASS NATIVE ELECTRIC CROSSING: actual SH '30' on mixed road/track, both wire layers and both gate states")
            end)
          end
          if not terraform then finish("electric-rail-and-tram");return end
          local at={x=2*(spot.x+3),y=spot.h+.4,z=2*spot.z+.2}
          aim(at,{x=at.x-4.6,y=spot.h+2.6,z=at.z-5.3})
          core.after(1,function()
            until_("No train on the reshaped platform for the approved native frame",function()
              for _,ref in ipairs(core.get_objects_inside_radius(at,2.2)) do
                local ent=ref:get_luaentity()
                local pick=ent and ent.luanttd_vehicle
                if pick and pick.kind=="rail" and pick.id==vehicle then return true end
              end
            end,function() finish("rail-platform-autoslope") end)
          end)
        end)
        end
        if not terraform then watch();return end
        local function lower(offset,check,done)
          query({kind="terrain_quote",request={operation="lower",first=id(offset)}},function(q)
            assert(q.value.cost==750)
            query({kind="command",command={kind="terrain_commit",token=q.value.token,revision=q.revision}},function()
              local state=assert(OwnerCheckpoint.read())
              assert(held(state,offset))
              check(state);done()
            end)
          end)
        end
        lower(3,function(state)
          assert(state.tiles[id(3)].rail_station_id==a)
          core.log("action","NATIVE RAIL AUTOSLOPE: preserved both active platform tiles and approach height")
        end,function()
          lower(9,function(state)
            assert(state.tiles[id(9)].rail_tracks==1 and state.tiles[id(9)].owner==owner)
            core.log("action","NATIVE RAIL AUTOSLOPE: preserved both running-rail tiles and approach height")
          end,watch)
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
