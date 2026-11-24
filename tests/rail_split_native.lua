-- Build a real paid two-height railway in an ordinary worker-owned world,
-- then inspect the meshes from a graphical Luanti client.
local started=false
local function start()
  if started then return end
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned" and api.trackworks) then core.after(.2,start);return end
  local n=p:get_player_name()
  local id,x,z,shape,h,first,second
  local parts={[1]={4,5},[2]={3,2},[4]={5,4},[8]={2,3}}
  for v=4,Sim.H-4 do
    for u=4,Sim.W-4 do
      local here=Sim.id(u,v)
      local t=S.tiles[here]
      local raw,base=api.terrain.tile(here)
      local tracks=parts[raw]
      if tracks and base>=1 and t.terrain~="water" and not (t.build or t.wood or t.site or t.house or t.stock_industry
          or t.stock_landmark or t.stock_void or S.stock_farm_fields and S.stock_farm_fields[here]) then
        id,x,z,shape,h,first,second=here,u,v,raw,base,tracks[1],tracks[2]
        break
      end
    end
    if id then break end
  end
  assert(id,"No usable dry natural single-corner slope")
  started=true
  local function aim()
    local focus={x=2*x+.5,y=h+.86,z=2*z+.5}
    local camera={x=2*x-3,y=h+3.3,z=2*z+5.2}
    p:set_pos(camera)
    local d={x=focus.x-camera.x,y=focus.y-camera.y-1.47,z=focus.z-camera.z}
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  local function ask(query,done)
    query.player=n
    assert(authority.query(query,function(r) assert(r.ok,tostring(r.why));done(r) end))
  end
  local fee=0
  local bought
  local function buy(track,done)
    ask({kind="rail_quote",request={tool="track",first=id,last=id,track=track}},function(q)
      fee=fee+q.value.cost
      ask({kind="command",command={kind="rail_commit",revision=q.revision,token=q.value.token}},done)
    end)
  end
  local function watch()
    local s=assert(OwnerCheckpoint.read())
    local t=s.tiles[id]
    if t.rail_tracks~=2^first+2^second then core.after(.18,watch);return end
    local profile=assert(api.trackworks.split_surface(shape,h,t.rail_tracks))
    assert(profile.groups[h]==2^second and profile.groups[h+1]==2^first)
    local function mesh(dx,y)
      return core.registered_nodes[core.get_node({x=2*x+dx,y=y,z=2*z}).name].mesh
    end
    if mesh(1,h+1)~="bl_rail_foundation_split_"..profile.mesh_key..".obj"
        or mesh(0,h+1)~="bl_rail_track_"..2^second..".obj"
        or mesh(0,h+2)~="bl_rail_track_"..2^first..".obj" then core.after(.18,watch);return end
    assert(s.companies[n].cash==bought-fee)
    aim()
    core.log("action",("PASS NATIVE SPLIT RAIL: paid $%d, separate level-%d and level-%d curves, stone foundation, raw slope %d"):format(fee,h,h+1,shape))
  end
  core.after(4,function()
    aim()
    bought=assert(OwnerCheckpoint.read()).companies[n].cash
    buy(first,function() buy(second,function() watch() end) end)
  end)
end
core.after(.2,start)
