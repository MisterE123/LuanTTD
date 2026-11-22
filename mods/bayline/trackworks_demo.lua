-- Opt-in demonstration of one locomotive on the stock route, rather than
-- enabled train traffic. No fares, orders, wagons, meet or signal logic.
return function(api,Track,Motion,Speed,Slope)
  local Sim,S=api.Sim,api.s
  local Lab=api.trackworks
  local Course=dofile(core.get_modpath("bayline").."/rail_test_run.lua")(Track,Motion,Speed,Sim)
  local Pose=dofile(core.get_modpath("bayline").."/rail_pose.lua")(Track)
  local D={}
  local active={}
  local function remove(name)
    local run=active[name]
    if run then
      if run.object:get_pos() then run.object:remove() end
      active[name]=nil
    end
  end
  local function deck(id,x,z)
    local bits=S.tiles[id].rail_tracks
    local shape,base=0,S.tiles[id].h
    if api.terrain then shape,base=api.terrain.tile(id) end
    local grade,level,_,profile=Lab.surface(shape,base,bits)
    if not grade then return end
    return level+.612+(profile and Slope.surface((x+1)*.5,(z+1)*.5,profile) or 0),grade
  end
  local function position(run)
    local id,td,f=Course.at(run.pieces,run.at)
    local a,b=Sim.xy(id)
    local x,z,dx,dz=Pose.sample(td,f)
    local y,grade=deck(id,x,z)
    if not y then return end
    local gradients={{.5,0},{-.5,0},{0,.5},{0,-.5}}
    local g=gradients[grade]
    local pitch=g and -math.atan(g[1]*dx+g[2]*dz) or 0
    local yaw=math.pi-math.atan2(dx,dz)
    return {x=a*2+.5+x,y=y,z=b*2+.5+z},yaw,pitch
  end
  function D.is_clear() return next(active)==nil end
  function D.start(name,from,goal)
    for owner in pairs(active) do
      if owner~=name then return false,"A demonstration locomotive is already present." end
    end
    local path=Lab.plan(S,from,goal,name)
    if not path then return false,"Plan a route to an owned flat straight piece before starting the test." end
    local segments,length=Course.compile(path)
    if not segments then return false,"This test run cannot traverse that route yet." end
    remove(name)
    local run={pieces=segments,at=segments[1].span*.24,
      target=length-segments[#segments].span*.25,topology=S.topology}
    local p=position(run)
    if not p then return false,"Terrain projection for the track is unavailable." end
    run.object=core.add_entity(p,"bayline:vehicle_steam")
    if not run.object then return false,"The locomotive model could not be loaded." end
    active[name]=run
    return true,"Test locomotive is running along the surveyed route. It does not carry cargo or use signals."
  end
  function D.step(dt)
    for name,run in pairs(active) do
      if run.topology~=S.topology or not run.object:get_pos() then remove(name)
      elseif run.at<run.target then
        -- Demo rate only: source axial and corner advance distances determine
        -- relative progress. The full stock train power model is still separate.
        run.at=math.min(run.target,run.at+dt*3100)
        local p,yaw,pitch=position(run)
        if p then
          run.object:move_to(p,true)
          run.object:set_rotation({x=pitch,y=yaw,z=0})
        else remove(name) end
      end
    end
  end
  D.leave=remove
  return D
end
