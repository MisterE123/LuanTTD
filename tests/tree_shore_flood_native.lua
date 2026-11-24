-- Disposable ordinary generated campaign, exercising the production
-- coastal adapter and native renderer on a real stock coast.
local Terrain=dofile(mod.."/openttd/terrain.lua")
local Flood=dofile(mod.."/openttd/water_flood.lua")
local Coast=dofile(mod.."/water_flood_world.lua")(Sim,Terrain,Flood)
local id,x,z,base,slope,wet,done
local road=core.settings:get_bool("luanttd_coastal_road_trees_qa",false)
local function node(px,y,pz)
  return core.get_node({x=2*x+px,y=y,z=2*z+pz}).name
end
local function has_stem()
  for dz=0,1 do for dx=0,1 do
    local name=node(dx,base+2,dz)
    local def=core.registered_nodes[name]
    if def and (def.mesh or ""):match("^bl_stock_forest_3_") then return true end
  end end
end
local function run()
  local p=core.get_player_by_name("SteelReview")
  if not p then core.after(.2,run);return end
  S.speed=0
  if not id then
    local current=Coast.board(S)
    local from_x,from_z
    for i,t in ipairs(S.tiles) do
      if t.coastal_water and not (t.stock_water_rocks or t.wood or t.ship or t.build or t.stock_landmark or t.stock_industry) then
        local u,v=Sim.xy(i)
        local tile=current.tile(u,v)
        if tile and tile.kind=="coast" and tile.base==0 and tile.slope~=0 and not Flood.one_raised(tile.slope) then
          local B={tile=function(a,b)
            if a==u and b==v then return {kind="trees",slope=tile.slope,base=tile.base} end
            return current.tile(a,b)
          end}
          for d=0,7 do
            local a,b=Flood.offset(d)
            for _,q in ipairs(Flood.visit(B,u+a,v+b)) do
              if q.x==u and q.z==v then id,x,z,base,slope=i,u,v,tile.base,tile.slope;from_x,from_z=u+a,v+b;break end
            end
            if id then break end
          end
        end
        if id then break end
      end
    end
    assert(id,"No suitable ordinary Temperate coastline east/west")
    local t=S.tiles[id]
    t.terrain,t.coastal_water,t.water_class="grass",nil,nil
    t.wood={class=4,type=7,count=2,growth=3,ground=0,density=3}
    assert(Coast.visit(S,from_x,from_z)>0 and t.wood.ground==3)
    render.update(S.changed);S.changed=nil
    local focus={x=x*2+.5,y=base+.8,z=z*2+.5}
    local eye={x=focus.x-3.4,y=base+3.25,z=focus.z+4.3}
    p:set_pos(eye)
    local d={x=focus.x-eye.x,y=focus.y-eye.y-1.47,z=focus.z-eye.z}
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  local shore=("luanttd_core:stock_shore_%d_%d"):format(slope,S.tiles[id].variant)
  if road and not wet and node(0,base+1,0)==shore and has_stem() then
    wet=true
    local name=p:get_player_name()
    local cash=Sim.company(S,name).cash
    local C=dofile(mod.."/campaign_road_construction.lua")(Sim,S)
    local request={tool="drag",first=id,last=id,start_half=false,end_half=true}
    local q,why
    for axis=0,1 do
      request.axis=axis
      q,why=C.quote(name,request)
      if q then break end
    end
    assert(q,why)
    core.log("action","NATIVE COAST FOREST BEFORE")
    core.after(4,function()
      local ok,note,dirty=C.commit(name,request,q,true)
      assert(ok,note)
      assert(S.tiles[id].build=="road" and not S.tiles[id].wood and not S.tiles[id].coastal_water)
      assert(Sim.company(S,name).cash==cash-q.cost)
      render.update(dirty)
      core.after(1,function()
        assert(not has_stem() and node(0,base+1,0)~=shore)
        core.log("action","PASS NATIVE COAST ROAD TREES: priced construction replaces the woodland with pavement")
      end)
    end)
    return
  end
  if not wet and node(0,base+1,0)==shore and has_stem() then
    wet=true
    core.log("action","NATIVE SHORE GROVE WET: shore mesh and original stems present")
    core.after(5,function()
      local B=Coast.board(S)
      local changed={}
      for d=0,7 do
        local a,b=Flood.offset(d)
        local j=Sim.id(x+a,z+b)
        local t=j and S.tiles[j]
        if t and Flood.behaviour(B.tile(x+a,z+b))=="active" then
          assert(t.terrain=="water" and not t.ship and not t.stock_industry and not t.stock_void)
          t.terrain,t.coastal_water,t.water_class="grass",nil,nil
          t.stock_water_rocks=nil
          changed[#changed+1]=j
        end
      end
      assert(Coast.visit(S,x,z)==1 and S.tiles[id].wood.ground==0)
      for _,j in ipairs(S.changed) do changed[#changed+1]=j end
      render.update(changed);S.changed=nil;done=true
      run()
    end)
    return
  end
  if done and node(0,base+1,0)~=shore and has_stem() then
    core.log("action","PASS NATIVE SHORE GROVE: tide dried; same two living stems, dry terrain mesh")
    return
  end
  core.after(.25,run)
end
core.after(.3,run)
