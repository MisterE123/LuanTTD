-- Ordinary generated campaign: stock track, depot and station commands,
-- dates, real pair purchase, worker projection with two cab rotations.
local express_native_started=false
local function express_native_scene(p)
  local name=p:get_player_name()
  local x,z,h
  for j=3,Sim.H-4 do
    for i=3,Sim.W-21 do
      local ready,base=true,nil
      for dx=0,19 do
        local id=Sim.id(i+dx,j)
        local t=S.tiles[id]
        local slope,height=api.terrain.tile(id)
        if slope~=0 or base and height~=base or t.wood or t.house or t.site or t.owner or t.stock_industry or
            t.stock_landmark or t.stock_void or t.terrain=="water" or t.build then ready=false;break end
        base=height
      end
      if ready then x,z,h=i,j,base;break end
    end
    if x then break end
  end
  assert(x,"No generated flat corridor for express review")
  p:set_pos({x=2*x+19,y=h+11,z=2*z-12});p:set_look_horizontal(0);p:set_look_vertical(.66)
  local function tile(dx) return Sim.id(x+dx,z) end
  local function ask(value,cb)
    value.player=name
    local yes,why=authority.query(value,function(r)
      assert(r.ok,value.kind..": "..tostring(r.why)); cb(r)
    end)
    assert(yes,why)
  end
  local samples=0
  local function observe(train)
    local heads={}
    local coach
    for _,ref in ipairs(core.get_objects_inside_radius({x=2*x+19,y=h+1,z=2*z},28)) do
      local a=ref:get_luaentity()
      if a and a.name=="luanttd_core:dispatch_sh_125" then heads[#heads+1]=ref
      elseif a and a.name=="luanttd_core:dispatch_wagon" then coach=ref end
    end
    if #heads==2 and coach then
      local angle=(heads[1]:get_rotation().y-heads[2]:get_rotation().y)%(2*math.pi)
      assert(math.abs(angle-math.pi)<.04,"The two power car noses do not face opposite directions")
      local a,b,c=heads[1]:get_pos().x,heads[2]:get_pos().x,coach:get_pos().x
      assert(c>math.min(a,b) and c<math.max(a,b))
      samples=samples+1
      local left,right=math.abs(a-c),math.abs(c-b)
      core.log("action",("SH125 actual native spacing %.3f %.3f"):format(left,right))
      if math.abs(left-1)>.125 or math.abs(right-1)>.125 then
        error(("Native coupling separation %.3f %.3f"):format(left,right))
      end
      if samples<10 then core.after(.12,observe,train);return end
      local w=assert(OwnerCheckpoint.read())
      local r=assert(w.stock_rail_dispatch.runs[1])
      assert(r.fleet_id==train and r.stock_engine==22 and r.dual_head and r.passenger_coaches==1)
      core.log("action","PASS NATIVE SH125: real paid worker train has two outward power cars around an independently modeled coach")
      return
    end
    core.after(.12,observe,train)
  end
  local function buy()
    ask({kind="depot",mode="rail",depot=tile(0)},function(d)
      local offer
      for _,item in ipairs(d.value.offers) do if item.request.parts[1]==22 then offer=item;break end end
      assert(offer and offer.request.parts[2]==27)
      ask({kind="transport_quote",request=offer.request},function(q)
        ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},function(r)
          ask({kind="command",command={kind="transport_start",mode="rail",vehicle=r.value.id,first=2,second=1,
            revision=r.revision}},function() core.after(.2,observe,r.value.id) end)
        end)
      end)
    end)
  end
  local tasks={{tool="track",first=tile(1),last=tile(19),track=0},
    {tool="depot",first=tile(0),direction=2},
    {tool="station",first=tile(4),last=tile(6),axis=0,length=3,tracks=1},
    {tool="station",first=tile(15),last=tile(17),axis=0,length=3,tracks=1}}
  local function build(i)
    if not tasks[i] then buy();return end
    ask({kind="rail_quote",request=tasks[i]},function(q)
      ask({kind="command",command={kind="rail_commit",token=q.value.token,revision=q.revision}},function() build(i+1) end)
    end)
  end
  build(1)
end
local function express_native_begin()
  local p=core.get_player_by_name("ExpressReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
    if not express_native_started then express_native_started=true;express_native_scene(p) end
  else core.after(.22,express_native_begin) end
end
core.after(.22,express_native_begin)
