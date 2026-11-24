-- Appended only to a disposable ordinary campaign for graphical QA.
local ready=false
local slope_test=core.settings:get("luanttd_qa_rail_ground")=="2"
local function start()
  if ready then return end
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned") then core.after(.2,start);return end
  local name=p:get_player_name()
  local function free(id)
    local t=S.tiles[id]
    return t and t.terrain~="water" and not (t.build or t.wood or t.site or t.house or t.stock_industry
      or t.stock_landmark or t.stock_void or S.stock_farm_fields and S.stock_farm_fields[id])
  end
  local first,last,x,z,h
  local piece,grade,profile,count=0,0,0,5
  for v=7,Sim.H-7 do
    for u=7,Sim.W-9 do
      local one,other=Sim.id(u,v),Sim.id(u+4,v)
      local f,b=api.terrain.tile(one)
      if slope_test then
        if free(one) then
          for bit=0,1 do
            local g,level,_,shape=api.trackworks.surface(f,b,2^bit)
            if g and g>0 then
              first,last,x,z,h,piece,grade,profile,count=one,one,u,v,level,bit,g,shape,1
              break
            end
          end
        end
      else
        local fit=f==0
        for k=0,4 do
          local id=Sim.id(u+k,v)
          local shape,y=api.terrain.tile(id)
          if shape~=0 or y~=b or not free(id) then fit=false;break end
        end
        if fit then first,last,x,z,h=one,other,u,v,b end
      end
      if first then break end
    end
    if first then break end
  end
  assert(first,"No ordinary free strip for a fenced railway")
  ready=true
  local lookat={x=2*x+(slope_test and .5 or 4),y=h+.6,z=2*z+.55}
  local camera={x=lookat.x-3.8,y=h+(slope_test and 4.1 or 5.4),z=lookat.z+(slope_test and 5.6 or 9.25)}
  local function aim()
    p:set_pos(camera)
    local d={x=lookat.x-camera.x,y=lookat.y-camera.y-1.47,z=lookat.z-camera.z}
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  local function ask(query,cb)
    query.player=name
    assert(authority.query(query,function(r) assert(r.ok,tostring(r.why or r.value));cb(r) end))
  end
  local function watch()
    for k=0,count-1 do
      local here={x=2*(x+k)+1,y=h+1,z=2*z}
      local node=core.get_node(here)
      local cfg=core.registered_nodes[node.name]
      if not cfg or cfg.mesh~=string.format("bl_rail_ground_fence_%d_%d.obj",piece==0 and 4 or 7,profile) then
        core.after(.20,watch);return
      end
      assert(not cfg.walkable and not cfg.pointable and cfg.use_texture_alpha=="clip")
      local track=core.get_node({x=here.x-1,y=here.y+(slope_test and 1 or 0),z=here.z}).name
      local expected=slope_test and "luanttd_core:stock_rail_grade_"..grade or "luanttd_core:stock_rail_1"
      assert(track==expected,"Fence must preserve the rail")
    end
    aim()
    core.log("action",("PASS NATIVE STOCK RAIL GROUND: stock profile %d and both borders on %d built train tiles"):format(profile,count))
  end
  -- Settle initial spawn before placing the disposable QA camera and building
  -- through the same worker quote/commit used by ordinary hotbar track tools.
  core.after(5,function()
    aim()
    ask({kind="rail_quote",request={tool="track",first=first,last=last,track=piece}}, function(q)
      ask({kind="command",command={kind="rail_commit",revision=q.revision,token=q.value.token}},function()
        core.after(.2,watch)
      end)
    end)
  end)
end
core.after(.2,start)
