-- Disposable visual fixture: inspect the actual worker-owned generated map,
-- not a staged voxel exhibit or commands that manufacture buildings.
local stock_art=dofile(mod.."/stock_town_art.lua")
local house_front=dofile(mod.."/house_frontage.lua")
local T=dofile(mod.."/openttd/terrain.lua")
local residential_ids={[0x06]=true,[0x0e]=true,[0x18]=true,[0x19]=true,[0x1a]=true}
local set_visual_time=core.set_timeofday
core.set_timeofday=function()return set_visual_time(.315)end
local function find_house_plots(disk)
  local groups,looks,fronts,founded={},{},{}
  for id,t in ipairs(disk.tiles) do
    local h=t.source_house
    if t.house and h and h.root and h.completed and residential_ids[h.id] then
      local road=house_front.road(Sim,disk,id,t)
      if road then
        local x,z=Sim.xy(id)
        local look=stock_art.look(h.id,x,z)
        local name=stock_art.asset_name(h.id,look)
        local dx,dz,f=house_front.placement(Sim,disk,id,t,false,h.render_parcel)
        local shape,base,deck=T.tile(disk.corner_grid,x,z)
        local record={id=h.id,base={x=2*x+dx,y=deck+1,z=2*z+dz},x=2*x+.5,z=2*z+.5,dir=f,name=name,look=look}
        if shape~=0 and base<deck and not founded then record.founded=true;founded=record end
        groups[h.id]=groups[h.id] or record
        looks[name]=looks[name] or record
        fronts[f]=fronts[f] or record
      end
    end
  end
  return groups,looks,fronts,founded
end
local function residential_native()
  local p=core.get_player_by_name("StockResidentialQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,residential_native);return
  end
  local disk=assert(OwnerCheckpoint.read())
  local groups,looks,fronts,founded=find_house_plots(disk)
  local take,used={},{}
  local function add(r)
    if r and not used[r.name] then
      take[#take+1],used[r.name]=r,true
    end
  end
  for _,id in ipairs({0x06,0x0e,0x18,0x19,0x1a}) do
    assert(groups[id],("No completed roadside house %02x in the worker test seed"):format(id))
    add(groups[id])
  end
  local alternates={}
  for name,r in pairs(looks) do if not used[name] then alternates[#alternates+1]=name end end
  table.sort(alternates)
  for _,name in ipairs(alternates) do add(looks[name]) end
  assert(#take==12,"The seeded worker town must expose all twelve dress variations")
  local directions={}
  for _,candidate in ipairs(take) do directions[candidate.dir]=true end
  -- The first example of a mesh need not cover every road direction.
  -- Keep one witness per dress variation, then add any missing fronts.
  for dir=0,3 do
    if not directions[dir] then take[#take+1]=assert(fronts[dir],"No houses faced direction "..dir) end
  end

  take[#take+1]=assert(founded,"No eligible completed hillside residential plot")

  local street_dirs={{0,1},{1,0},{0,-1},{-1,0}}
  local function verify(i)
    local show=take[i]
    if not show then
      core.log("action",("PASS NATIVE WORKER STOCK RESIDENTIAL: %d real completed meshes painted with stock look and road frontage, including a founded house"):format(#take))
      return
    end
    local dir=street_dirs[show.dir+1]
    local vx,vz=dir[1]*4.25+dir[2]*2.15,dir[2]*4.25-dir[1]*2.15
    p:set_pos({x=show.x+vx,y=show.base.y+1.26,z=show.z+vz})
    p:set_look_horizontal(math.atan2(vx,-vz))
    p:set_look_vertical(.405)
    local function ready(n)
      local tag="luanttd_core:"..show.name
      local actual=core.get_node(show.base)
      local support=not show.founded or core.get_node({x=show.base.x,y=show.base.y-1,z=show.base.z}).name=="luanttd_core:road_retaining"
      if actual.name==tag and support then
        assert(actual.param2==show.dir,"Worker painted the right mesh with the wrong roadside orientation")
        local registered=assert(core.registered_nodes[tag])
        assert(registered.mesh=="bl_"..show.name..".obj")
        core.log("action",("STOCK_RESIDENTIAL_VISIBLE_%02d: %s look=%d facedir=%d (%s)")
          :format(i,show.name,show.look,show.dir,core.pos_to_string(show.base)))
        core.after(1.55,function()verify(i+1)end)
      elseif n<85 then
        core.after(.18,function()ready(n+1)end)
      else
        error("Worker did not paint "..tag.."; got "..actual.name.." at "..core.pos_to_string(show.base))
      end
    end
    core.after(.3,function()ready(1)end)
  end
  verify(1)
end
core.after(.2,residential_native)
