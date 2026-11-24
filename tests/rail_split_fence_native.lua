-- Real owned rail, adjacent purchased land, and the landscape tick.
-- Verifies bare dirt, a single cut-slope border, then the stock diagonal.
local Track=dofile(mod.."/openttd/rail_track.lua")
local Ground=dofile(mod.."/openttd/rail_ground_temperate.lua")(Track)
local Fence=dofile(mod.."/rail_split_fence.lua")(api.slope)
local owner="SteelReview"
local begun=false
local side_x,side_z={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local function step()
  local p=core.get_player_by_name(owner)
  if not (p and authority and authority.status()=="owned") then core.after(.20,step);return end
  local initial=assert(OwnerCheckpoint.read())
  if not initial.companies[owner] then core.after(.20,step);return end
  if begun then return end
  begun=true
  local id,x,z,h,profile,track,land,expected
  local function plain(t,k)
    return t and t.terrain~="water" and not (t.stock_void or t.stock_landmark or t.stock_industry or t.wood
      or t.build or t.house or t.owner or t.site or t.ship or t.tram or t.airfield or
      initial.stock_farm_fields and initial.stock_farm_fields[k])
  end
  for rz=5,Sim.H-5 do
    for rx=5,Sim.W-5 do
      local here=Sim.id(rx,rz)
      local t=initial.tiles[here]
      if plain(t,here) and t.h>=1 then
        local shape,base=api.terrain.tile(here)
        for bit=2,5 do
          local pp=api.trackworks.split_surface(shape,base,2^bit)
          if pp and pp.surface%32~=0 then
            for d=0,3 do
              local there=Sim.id(rx+side_x[d],rz+side_z[d])
              local g=Ground.visit({owner=owner,tracks=2^bit,plain=true,ground=1},function(k)
                if k==d then return {kind="object",owned_land=true,owner=owner} end
              end)
              if g>=2 and g<=6 and g~=4 and plain(initial.tiles[there],there) then
                id,x,z,h,profile,track,land,expected=here,rx,rz,base,pp,bit,there,g
                break
              end
            end
          end
          if id then break end
        end
      end
      if id then break end
    end
    if id then break end
  end
  assert(id,"No generated dry special foundation with an eligible adjacent land parcel")
  local function aim()
    local focus={x=2*x+.5,y=h+.60,z=2*z+.5}
    local cam={x=2*x-3.3,y=h+3.8,z=2*z+4.5}
    p:set_pos(cam)
    local d={x=focus.x-cam.x,y=focus.y-cam.y-1.47,z=focus.z-cam.z}
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  aim()
  local function ask(q,done)
    q.player=owner
    assert(authority.query(q,function(r) assert(r.ok,tostring(r.why));done(r) end))
  end
  local function speed(n,cb)
    ask({kind="company"},function(r)
      ask({kind="command",command={kind="speed",speed=n,revision=r.revision}},cb)
    end)
  end
  local function land_edit(op,callback)
    ask({kind="terrain_quote",request={first=land,operation=op}},function(r)
      ask({kind="command",command={kind="terrain_commit",revision=r.revision,token=r.value.token}},callback)
    end)
  end
  local function remount(node,x_shift,z_shift,y)
    return core.get_node({x=2*x+x_shift,y=y,z=2*z+z_shift}).name==node
  end
  local key=assert(Fence.design(profile,expected,2^track,h))
  local diag=Ground.visit({owner=owner,tracks=2^track,plain=true,ground=1},function() end)
  local diag_key=assert(Fence.design(profile,diag,2^track,h))
  local function diagonal()
    local s=assert(OwnerCheckpoint.read())
    if s.tiles[id].rail_ground~=diag or not remount("luanttd_core:rail_split_fence_"..diag_key,1,1,h+1) then
      core.after(.17,diagonal);return
    end
    assert(not s.tiles[land].owner and diag>=8 and diag<=11)
    aim()
    core.log("action","PASS NATIVE SPLIT FENCE: stock corner detail after selling the neighboring plot")
  end
  local function cardinal()
    local s=assert(OwnerCheckpoint.read())
    if s.tiles[id].rail_ground~=expected or not remount("luanttd_core:rail_split_fence_"..key,1,1,h+1) then
      core.after(.17,cardinal);return
    end
    assert(s.tiles[land].stock_object.kind=="owned_land")
    aim()
    core.log("action",("NATIVE SPLIT FENCE BORDER: original ground %d and shaped edge %s"):format(expected,key))
    core.after(4.0,function() land_edit("bulldoze",function() diagonal() end) end)
  end
  local function bare()
    local s=assert(OwnerCheckpoint.read())
    if s.tiles[id].rail_ground~=0 or not remount("luanttd_core:rail_foundation_split_"..profile.mesh_key.."_barren",1,0,h+1) then
      core.after(.17,bare);return
    end
    aim()
    core.log("action","NATIVE SPLIT FENCE BARREN: separate stock state before grass and fencing")
    core.after(2,function() speed(4,cardinal) end)
  end
  speed(0,function()
    land_edit("purchase_land",function()
      ask({kind="rail_quote",request={tool="track",first=id,last=id,track=track}},function(q)
        ask({kind="command",command={kind="rail_commit",revision=q.revision,token=q.value.token}},bare)
      end)
    end)
  end)
end
core.after(.2,step)
