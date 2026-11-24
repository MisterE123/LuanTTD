-- Actual ordinary campaign worker and graphical client: buy an upper
-- shore curve, keep the navigable sea half, then restore the coast.
local Track=dofile(mod.."/openttd/rail_track.lua")
local Water=dofile(mod.."/openttd/ship_follow.lua")(Track)
local Tide=dofile(mod.."/openttd/rail_half_water.lua")(Track,api.slope)
local Net=dofile(mod.."/ship_network.lua")(Sim,dofile(mod.."/openttd/terrain.lua"),Water,{})
local running=false
local function run()
  local p=core.get_player_by_name("SteelReview")
  if running then return end
  if not (p and authority and authority.status()=="owned") then core.after(.2,run);return end
  running=true
  local n=p:get_player_name()
  local id,x,z,shape,track,variant
  local upper={[1]=4,[2]=3,[4]=5,[8]=2}
  for i,t in ipairs(S.tiles) do
    if t.terrain=="water" and t.coastal_water and not (t.wood or t.ship or t.build or t.stock_water_rocks) then
      local q,b=api.terrain.tile(i)
      if b==0 and upper[q] then
        id,shape,track,variant=i,q,upper[q],t.variant
        x,z=Sim.xy(i)
        break
      end
    end
  end
  assert(id,"No native single-corner shore tile")
  local function aim()
    local focus={x=2*x+.5,y=.83,z=2*z+.5}
    local camera={x=2*x-2.65,y=3.0,z=2*z+4.55}
    p:set_pos(camera)
    local d={x=focus.x-camera.x,y=focus.y-camera.y-1.47,z=focus.z-camera.z}
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  local function ask(query,done)
    query.player=n
    assert(authority.query(query,function(r) assert(r.ok,tostring(r.why));done(r) end))
  end
  local function change(remove,done)
    ask({kind="rail_quote",request={tool="track",first=id,last=id,track=track,remove=remove}},function(q)
      if not remove then assert(q.value.cost==390,q.value.cost) end
      ask({kind="command",command={kind="rail_commit",revision=q.revision,token=q.value.token}},done)
    end)
  end
  local profile=assert(api.trackworks.split_surface(shape,0,2^track))
  local function mesh(dx,y)
    return core.registered_nodes[core.get_node({x=2*x+dx,y=y,z=2*z}).name].mesh
  end
  local function checkpoint() return assert(OwnerCheckpoint.read()) end
  local function check_multicoast()
    local Price=dofile(mod.."/openttd/rail_construction.lua")(Track)
    local next_,tx,tz,option,proposal
    for i,t in ipairs(S.tiles) do
      if t.terrain=="water" and t.coastal_water and not (t.wood or t.ship or t.build) then
        local mask,base=api.terrain.tile(i)
        if base==0 and mask~=0 and not upper[mask] then
          for tr=2,5 do
            local q=Price.piece({slope=mask,kind="water",coast=true,base_level=0},tr,{owner=n})
            if q and not q.water_ground then
              next_,option,proposal=i,tr,q;tx,tz=Sim.xy(i);break
            end
          end
          if next_ then break end
        end
      end
    end
    assert(next_,"need one ordinary multi-corner coastal curve")
    local request={kind="rail_quote",request={tool="track",first=next_,last=next_,track=option}}
    local focus={x=2*tx+.5,y=1.25,z=2*tz+.5}
    local camera={x=focus.x-3.1,y=3.3,z=focus.z+4.75}
    p:set_pos(camera)
    local d={x=focus.x-camera.x,y=focus.y-camera.y-1.47,z=focus.z-camera.z}
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
    ask(request,function(q)
      assert(q.value.cost==proposal.cost)
      ask({kind="command",command={kind="rail_commit",revision=q.revision,token=q.value.token}},function()
        local function wait()
          local t=checkpoint().tiles[next_]
          local painted=false
          for y=0,3 do
            local node=core.get_node({x=2*tx,y=y,z=2*tz}).name
            if node:find("rail_",1,true) then painted=true;break end
          end
          if not t.rail_tracks or not painted then core.after(.22,wait);return end
          assert(t.build=="stock_rail" and t.rail_ground~=13 and not t.coastal_water and t.terrain=="grass")
          core.log("action","PASS NATIVE WET RAIL: upper rail restored coast; paid multi-corner shore curve clears to dry ground")
        end
        wait()
      end)
    end)
  end
  local function dry_watch()
    local state=checkpoint()
    local t=state.tiles[id]
    if t.rail_tracks or not t.coastal_water or mesh(0,1)~="bl_coastal_bank_"..shape..".obj" then core.after(.22,dry_watch);return end
    check_multicoast()
  end
  local function watch()
    local state=checkpoint()
    local t=state.tiles[id]
    if t.rail_ground~=13 or mesh(1,1)~="bl_rail_foundation_split_"..profile.mesh_key.."_wet.obj"
        or mesh(0,2)~="bl_rail_track_"..2^track..".obj" then core.after(.22,watch);return end
    assert(Water.at(Net.board(state),id)==Track.trackdirs(Tide.water_tracks(shape,2^track,13)))
    assert(Water.at(Net.board(state),id)~=0 and t.owner==n)
    assert(core.get_node({x=2*x,y=0,z=2*z}).name:find("ocean_top",1,true))
    aim()
    core.log("action","NATIVE WET RAIL BUILT: rail above a live lower-half ship lane")
    core.after(5,function() change(true,dry_watch) end)
  end
  core.after(4,function() aim();change(false,watch) end)
end
core.after(.2,run)
