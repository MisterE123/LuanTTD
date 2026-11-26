-- Real generated native map: mark two existing stock terrain records, then
-- verify their render-only overlays plus an untouched natural river slope.
return function(api)
  local S,Sim,T=api.s,api.Sim,api.terrain
  assert(api.generated_world and S.stock_coastal_flood and S.stock_generated_profile.river_stats)
  local function record(x,z)
    local id=Sim.id(x,z)
    local row=id and S.tiles[id]
    if not row then return end
    local mask,base=T.tile(id)
    return {id=id,x=x,z=z,mask=mask,base=base,tile=row}
  end
  local shore=record(10,15)
  assert(shore.tile.coastal_water and shore.mask~=0,"fixture's original stock shoreline")
  assert(not shore.tile.ship and not shore.tile.stock_industry and not shore.tile.build)
  local skerry,plain
  local variant=dofile(core.get_modpath("luanttd_core").."/rock_variation.lua")
  local function sea(q)
    local t=q and q.tile
    return t and q.mask==0 and t.terrain=="water" and t.water_class=="sea" and
      not (t.stock_void or t.coastal_water or t.ship or t.stock_industry or t.build)
  end
  for x=shore.x-1,2,-1 do
    local q=record(x,shore.z)
    local row=q.tile
    if q.mask==0 and row.terrain=="water" and row.water_class=="sea"
      and not row.stock_void and not row.coastal_water and not row.ship
      and not row.stock_industry and not row.build then
      if skerry then plain=q;break else skerry=q end
    end
  end
  assert(skerry and plain)
  local group
  for x=skerry.x,3,-1 do
    for z=shore.z-5,shore.z+5 do
      local cells={record(x,z),record(x-1,z),record(x,z+1),record(x-1,z+1)}
      if sea(cells[1]) and sea(cells[2]) and sea(cells[3]) and sea(cells[4]) and
          cells[1].id~=plain.id and cells[2].id~=plain.id and cells[3].id~=plain.id and cells[4].id~=plain.id then
        local shapes,turns={},{}
        for _,q in ipairs(cells) do
          local a,b=variant(q.x,q.z)
          shapes[a],turns[b]=true,true
        end
        local f=next(shapes)
        if next(shapes,f) and next(turns,next(turns)) then group=cells;break end
      end
    end
    if group then break end
  end
  assert(group,"need four adjacent native sea tile records")
  for _,q in ipairs(group) do q.tile.stock_water_rocks=true end
  shore.tile.stock_water_rocks,skerry.tile.stock_water_rocks=true,true
  plain.tile.stock_water_rocks=nil
  local rapid
  for id,tile in ipairs(S.tiles) do
    if tile.water_class=="river" and not tile.build and not tile.ship and not tile.stock_industry then
      local x,z=Sim.xy(id)
      local mask,base=T.tile(id)
      if mask==3 or mask==6 or mask==9 or mask==12 then
        local a,b
        if mask==3 or mask==12 then a,b=record(x,z-1),record(x,z+1)
        else a,b=record(x-1,z),record(x+1,z) end
        local function plain_bank(w)
          return w and w.tile.terrain~="water" and not w.tile.stock_industry and not w.tile.house
        end
        if plain_bank(a) and plain_bank(b) then
          rapid={id=id,x=x,z=z,mask=mask,base=base,banks={a,b}}
          break
        end
      end
    end
  end
  assert(rapid,"no natural graded river interval bounded by banks")
  local views={}
  local function viewpoint(key,q,dx,dz,h)
    local x,y,z=q.x*2+.5,q.base+.52,q.z*2+.5
    views[key]={from={x=x+dx,y=y+h,z=z+dz},at={x=x,y=y+.14,z=z}}
  end
  viewpoint("rocky-shore",shore,-4.4,-2.0,2.65)
  viewpoint("open-rocks",skerry,-3.7,2.1,3.2)
  views["underwater-rocks"]={from={x=skerry.x*2-.22,y=-.39,z=skerry.z*2-.85},
    at={x=skerry.x*2+.46,y=-.28,z=skerry.z*2+.5},eye_height=.25}
  viewpoint("scattered-skerries",{x=group[1].x-.5,z=group[1].z+.5,base=0},-6.0,-1.5,4.2)
  local flow=({[3]={-1,0},[6]={0,-1},[9]={0,1},[12]={1,0}})[rapid.mask]
  viewpoint("rapids",rapid,flow[1]*4.2-flow[2]*1.75,flow[2]*4.2+flow[1]*1.75,2.6)
  viewpoint("rapids-back",rapid,-flow[1]*4.3+flow[2]*1.65,-flow[2]*4.3-flow[1]*1.65,2.95)
  local original_spray=core.add_particlespawner
  local watched={}
  core.add_particlespawner=function(spec)
    if spec.playername=="ShoreQA" and type(spec.texture)=="table" then
      local kind=spec.texture.name:match("^bl_river_(%a+)%.png$")
      if kind=="spray" or kind=="wake" then
        local x,z=spec.pos.min.x, spec.pos.min.z
        if math.abs(x-(2*rapid.x+.5))<1 and math.abs(z-(2*rapid.z+.5))<1 and not watched[kind] then
          local mid=vector.multiply(vector.add(spec.vel.min,spec.vel.max),.5)
          local velocity=mid.x*flow[1]+mid.z*flow[2]
          assert(spec.time==0 and velocity>0 and spec.exptime.max<.75)
          assert((kind=="spray")==(mid.y>0))
          assert(spec.texture.alpha_tween[#spec.texture.alpha_tween]==0)
          watched[kind]=true
          if watched.spray and watched.wake then core.log("action","COAST_SHEET_RAPID_FOAM") end
        end
      end
    end
    return original_spray(spec)
  end
  local function aim(p,v)
    local eye=v.eye_height or 1.47
    p:set_properties({eye_height=eye})
    p:set_pos(v.from)
    local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+eye,z=v.from.z})
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  local function at(q,y,dx)
    local node=core.get_node({x=q.x*2+(dx or 0),y=q.base+y,z=q.z*2}).name
    return assert(core.registered_nodes[node]),node
  end
  local function check()
    local bed=at(shore,1)
    local block=at(skerry,1)
    local tide=at(skerry,0)
    local ordinary=at(plain,0)
    local _,_,style=variant(shore.x,shore.z)
    assert(bed.mesh=="bl_rocky_coastal_bank_"..shore.mask..(style==1 and "_1" or "")..".obj")
    local names={}
    local function check_rocks(q)
      local a,b=variant(q.x,q.z)
      local suffix=(a==0 and b==0) and "" or ("_"..a.."_"..b)
      local def=at(q,1)
      assert(def.mesh=="bl_rocky_water_flat"..suffix..".obj",(def.mesh or "?").." not expected")
      names[def.mesh]=true
    end
    check_rocks(skerry)
    for _,q in ipairs(group) do check_rocks(q) end
    assert(next(names,next(names)),"all four patches use the same model")
    core.log("action","COAST_SHEET_VARIANTS multiple sea forms and orientations")
    assert(tide.mesh:match("^bl_ocean_top_") and ordinary.mesh:match("^bl_ocean_top_"))
    assert(select(2,at(skerry,-1))=="luanttd_core:coastal_seabed" and select(2,at(plain,-1))=="luanttd_core:coastal_seabed")
    assert(tide.waving==3 and ordinary.waving==3,"rock mounting changed the ordinary ocean shader")
    assert(select(2,at(plain,1))=="air","ordinary ocean got a rocky overlay")
    assert(bed.walkable and #bed.collision_box.fixed>0 and not block.walkable and not bed.pointable and not block.pointable)
    local flowing=at(rapid,1)
    local foam=at(rapid,1,1)
    assert(flowing.mesh=="bl_land_"..rapid.mask..".obj")
    assert(flowing.waving==0 and flowing.tiles[1].animation
      and flowing.tiles[1].name:match("water_river"),
      "graded river must retain flowing texture with fixed geometry")
    assert(foam.mesh=="bl_river_rapid_rocks_"..rapid.mask..".obj" and not foam.pointable)
    for _,q in ipairs(rapid.banks) do
      local a=at(q,1)
      local b=at(q,1,1)
      assert(not (a.mesh or ""):match("rapid_rocks") and not (b.mesh or ""):match("rapid_rocks"))
    end
    local player=core.get_player_by_name("ShoreQA")
    if player then api.cinematic.toggle(player);aim(player,views["rocky-shore"]) end
    core.log("action",("COAST_SHEET_READY stock CoastRocks mask %d, ClearRocks, native flowing rapids mask %d"):format(shore.mask,rapid.mask))
  end
  core.register_on_joinplayer(function(p)
    S.speed=0
    core.set_timeofday(.41)
    p:set_physics_override({gravity=0})
    aim(p,views["rocky-shore"])
    local waiting=4
    for _,q in ipairs({shore,skerry,rapid,group[1]}) do
      local x,z=q.x*2,q.z*2
      core.emerge_area({x=x-12,y=q.base-3,z=z-12},{x=x+12,y=q.base+6,z=z+12},function(_,_,remaining)
        if remaining~=0 then return end
        waiting=waiting-1
        if waiting==0 then core.after(.30,check) end
      end)
    end
  end)
  local last
  core.register_globalstep(function()
    local f=io.open(core.get_worldpath().."/coastal-view.txt","r")
    if not f then return end
    local v=f:read("*l")
    f:close()
    if v==last or not views[v] then return end
    local p=core.get_player_by_name("ShoreQA")
    if not p then return end
    last=v
    aim(p,views[v])
    core.log("action","COAST_SHEET_VIEW "..v)
  end)
end
