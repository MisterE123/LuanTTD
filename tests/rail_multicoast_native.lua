-- Native graphical evidence for the automatically flooded multi-corner
-- shoreline. Runs in a private local replay of the ordinary seed.
local T=dofile(mod.."/openttd/rail_track.lua")
local Terrain=dofile(mod.."/openttd/terrain.lua")
local Flood=dofile(mod.."/openttd/water_flood.lua")
local R=dofile(mod.."/openttd/rail_half_water.lua")(T,api.slope)
local Coast=dofile(mod.."/water_flood_world.lua")(Sim,Terrain,Flood,T,api.slope,R)
local Fence=dofile(mod.."/rail_split_fence.lua")(api.slope)
local id,x,z,base,shape,bits,corner_profile
local wet,done
local build={{7,8},{11,16},{13,4},{14,32}}
local function native_node(dx,y)
  return core.get_node({x=2*x+dx,y=y,z=2*z}).name
end
local function paint_check(p)
  local n=native_node(1,base+1)
  local def=core.registered_nodes[n]
  local expect="bl_rail_foundation_split_"..corner_profile.mesh_key..(done and "" or "_wet")..".obj"
  if not def or def.mesh~=expect then return false end
  local ground=done and R.dry_ground(bits) or 13
  local key=assert(Fence.design(corner_profile,ground,bits,base))
  local f=core.registered_nodes[core.get_node({x=2*x+1,y=base+1,z=2*z+1}).name]
  if f.mesh~="bl_rail_split_fence_"..key..".obj" then return false end
  for h,pieces in pairs(corner_profile.groups) do
    local rail=core.registered_nodes[native_node(0,h+1)]
    if rail.mesh~="bl_rail_track_"..pieces..".obj" then return false end
  end
  return true
end
local function step()
  local p=core.get_player_by_name("SteelReview")
  if not p then core.after(.2,step);return end
  S.speed=0
  if not id then
    local B=Coast.board(S)
    local sx,sz
    local lookup={}
    for _,v in ipairs(build) do lookup[v[1]]=v[2] end
    for i,t in ipairs(S.tiles) do
      if t.coastal_water and not (t.stock_water_rocks or t.wood or t.ship or t.build or t.stock_landmark or t.stock_industry) then
        local a,b=Sim.xy(i)
        local box=B.tile(a,b)
        local rails=box and box.kind=="coast" and box.base==0 and lookup[box.slope]
        if rails then
          local F={tile=function(u,v)
            if a==u and b==v then return {kind="rail",slope=box.slope,base=0,tracks=rails,ground=1} end
            return B.tile(u,v)
          end,flood_rail=function(_,_,q) return R.flood(q.slope,q.tracks,q.ground,function() return false end) end}
          for d=0,7 do
            local u,v=Flood.offset(d)
            for _,q in ipairs(Flood.visit(F,a+u,b+v)) do
              if q.x==a and q.z==b then id,x,z,shape,bits,base,sx,sz=i,a,b,box.slope,rails,0,a+u,b+v;break end
            end
            if id then break end
          end
        end
        if id then break end
      end
    end
    assert(id,"No ordinary generated three-raised coastal slope")
    local t=S.tiles[id]
    t.terrain,t.water_class,t.coastal_water="grass",nil,nil
    t.rail_tracks,t.rail_ground,t.build,t.owner=bits,1,"stock_rail","SteelReview"
    corner_profile=assert(api.trackworks.split_surface(shape,base,bits))
    assert(Coast.visit(S,sx,sz)>0 and t.rail_ground==13)
    render.update(S.changed);S.changed=nil
    local target={x=2*x+.5,y=1,z=2*z+.5}
    local eye={x=target.x-2.9,y=3.15,z=target.z+4.5}
    p:set_pos(eye)
    local d={x=target.x-eye.x,y=target.y-eye.y-1.47,z=target.z-eye.z}
    p:set_look_horizontal(math.atan2(-d.x,d.z));p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  if not wet and paint_check(p) then
    wet=true
    core.log("action","NATIVE MULTICORNER RAIL WET")
    core.after(5,function()
      local changed={}
      local B=Coast.board(S)
      for d=0,7 do
        local a,b=Flood.offset(d)
        local i=Sim.id(x+a,z+b)
        local tile=i and S.tiles[i]
        if tile and Flood.behaviour(B.tile(x+a,z+b))=="active" then
          assert(tile.terrain=="water" and not tile.stock_void and not tile.ship)
          tile.terrain,tile.water_class,tile.coastal_water,tile.stock_water_rocks="grass",nil,nil,nil
          changed[#changed+1]=i
        end
      end
      assert(Coast.visit(S,x,z)==1 and S.tiles[id].rail_ground==R.dry_ground(bits))
      for _,i in ipairs(S.changed) do changed[#changed+1]=i end
      render.update(changed);S.changed=nil;done=true
      step()
    end)
    return
  end
  if done and paint_check(p) then
    core.log("action","PASS NATIVE MULTICORNER RAIL: same high curve and fence, coastal slope dried after losing sea exposure")
    return
  end
  core.after(.25,step)
end
core.after(.3,step)
