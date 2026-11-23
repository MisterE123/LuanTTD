-- Appended only to the disposable test game. It does not inject plots,
-- place nodes or advance houses outside the ordinary campaign worker.
local Art=dofile(mod.."/stock_town_art.lua")
local C=dofile(mod.."/stock_town_construction_art.lua")(
  dofile(mod.."/openttd/stock_town_draw_rows.lua"),Art)
local front=dofile(mod.."/house_frontage.lua")
local set_visual_time=core.set_timeofday
core.set_timeofday=function()return set_visual_time(.33)end
local function wait_for(accept,next_,failure,n)
  if accept() then next_()
  elseif n<140 then core.after(.15,function()wait_for(accept,next_,failure,n+1)end)
  else error(failure()) end
end
local function verify_native(player)
  local view=assert(OwnerCheckpoint.read())
  assert(view.speed==0,"Native evidence must reflect one unchanging worker revision")
  local cases,keys={},{}
  for id,t in ipairs(view.tiles) do
    local h=t.source_house
    if h and t.house and h.root and not h.completed and front.road(Sim,view,id,t) then
      local x,z=Sim.xy(id)
      local key,_,upper,look=C.selection(h.id,x,z,h.stage)
      if key and not keys[key..h.id] then
        local dx,dz,f=front.placement(Sim,view,id,t,nil,h.render_parcel)
        local name=key=="complete" and Art.asset_name(h.id,look) or key
        local category
        if key=="complete" then category="ready"
        elseif key:find("_shell_",1,true) then category="shell"
        elseif upper==0 then category="bare"
        elseif h.id==0x06 or h.id==0x1a then category="cottage"
        else category="urban" end
        local rec={id=h.id,phase=h.stage,name=name,category=category,f=f,x=2*x+.5,z=2*z+.5,
          base={x=2*x+dx,y=t.h+1,z=2*z+dz}}
        cases[#cases+1]=rec;keys[key..h.id]=true
        core.log("action",("STOCK_CONSTRUCTION_GENERATED #%02x phase=%d look=%d key=%s kind=%s"):format(h.id,h.stage,look,name,category))
      end
    end
  end
  local take,distinct={},{}
  for _,kind in ipairs({"ready","shell","bare","cottage","urban"}) do
    local found
    -- Frame and urban cutaways are more informative than two pads;
    -- retain the stage-0 plot as the separately required bare case.
    for _,r in ipairs(cases) do
      if r.category==kind and (not found or r.phase>found.phase) then found=r end
    end
    assert(found,"Ordinary stock-generated test world had no stage category: "..kind)
    take[#take+1]=found;distinct[found.name]=true
  end
  for _,r in ipairs(cases) do
    if #take>=7 then break end
    if not distinct[r.name] and (r.phase==0 or r.category=="urban") then
      take[#take+1]=r;distinct[r.name]=true
    end
  end
  for _,r in ipairs(cases) do
    if #take>=7 then break end
    if not distinct[r.name] then take[#take+1]=r;distinct[r.name]=true end
  end
  assert(#take==7)
  local positions={{0,1},{1,0},{0,-1},{-1,0}}
  local function capture(i)
    local q=take[i]
    if not q then
      core.log("action","PASS NATIVE WORKER STOCK CONSTRUCTION: 7 live construction scenes covering 5 distinct native stock row behaviors")
      return
    end
    local d=positions[q.f+1]
    local vx,vz=d[1]*3.1+d[2]*1.54,d[2]*3.1-d[1]*1.54
    player:set_pos({x=q.x+vx,y=q.base.y+1.40,z=q.z+vz})
    player:set_look_horizontal(math.atan2(vx,-vz))
    player:set_look_vertical(.527)
    local tag="luanttd_core:"..q.name
    local function actual() return core.get_node(q.base) end
    wait_for(function()return actual().name==tag end,function()
      assert(actual().param2==q.f,("Wrong frontage at %s"):format(q.name))
      assert(core.registered_nodes[tag].mesh=="bl_"..q.name..".obj")
      core.log("action",("STOCK_CONSTRUCTION_VISIBLE_%02d: %s #%02x phase=%d facedir=%d (%s)")
        :format(i,q.name,q.id,q.phase,q.f,core.pos_to_string(q.base)))
      core.after(2.30,function() capture(i+1) end)
    end,function()
      return ("Worker projection expected %s at %s, had %s"):format(tag,core.pos_to_string(q.base),actual().name)
    end,1)
  end
  capture(1)
end
local function initialize()
  local name="StockConstructionQA"
  local p=core.get_player_by_name(name)
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.25,initialize);return
  end
  -- Same authenticated worker command as Pause in the normal finance UI.
  assert(authority.query({kind="company",player=name},function(reply)
    assert(reply.ok,reply.why)
    assert(authority.query({kind="command",player=name,
      command={kind="speed",speed=0,revision=reply.revision}},function(done)
      assert(done.ok,done.why)
      wait_for(function()local disk=OwnerCheckpoint.read();return disk and disk.speed==0 end,
        function()verify_native(p)end,function()return "Pause receipt did not reach durable owner" end,1)
    end))
  end))
end
core.after(.25,initialize)
