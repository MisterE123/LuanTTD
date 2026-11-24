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
  viewpoint("rapids",rapid,4.1,-3.0,3.35)
  local function aim(p,v)
    p:set_pos(v.from)
    local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
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
    assert(bed.mesh=="bl_rocky_coastal_bank_"..shore.mask..".obj")
    assert(block.mesh=="bl_rocky_water_flat.obj")
    assert(tide.mesh:match("^bl_ocean_top_") and ordinary.mesh:match("^bl_ocean_top_"))
    assert(tide.waving==3 and ordinary.waving==3,"rock mounting changed the ordinary ocean shader")
    assert(select(2,at(plain,1))=="air","ordinary ocean got a rocky overlay")
    assert(not bed.walkable and not block.walkable and not bed.pointable and not block.pointable)
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
    if player then aim(player,views["rocky-shore"]) end
    core.log("action",("COAST_SHEET_READY stock CoastRocks mask %d, ClearRocks, native flowing rapids mask %d"):format(shore.mask,rapid.mask))
  end
  core.register_on_joinplayer(function(p)
    S.speed=0
    core.set_timeofday(.41)
    p:set_physics_override({gravity=0})
    aim(p,views["rocky-shore"])
    local waiting=3
    for _,q in ipairs({shore,skerry,rapid}) do
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
