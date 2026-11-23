-- Presentation test: run the real farm field entity placer. Use the
-- Luanti ObjectRef yaw rotation convention, not player look yaw.
local runs,refs={},{}
local core_mock={
  register_entity=function(name,def) refs[name]=def end,
  get_connected_players=function() return {{get_pos=function() return {x=20,z=20} end}} end,
  add_entity=function(pos,name)
    local r={pos=pos,name=name}
    function r:set_yaw(yaw) self.yaw=yaw end
    function r:get_pos() return self.pos end
    function r:remove() self.pos=nil end
    runs[#runs+1]=r;return r
  end,
}
core=core_mock
local create=dofile("mods/luanttd_core/farm_field_view.lua")
local edges={
  [0]={10,10,10,11},[1]={10,11,11,11},
  [2]={11,10,11,11},[3]={10,10,11,10},
}
local function near(a,b) assert(math.abs(a-b)<1e-8,("%g ~= %g"):format(a,b)) end
for side=0,3 do
  local edge=edges[side]
  local xa,za,xb,zb=unpack(edge)
  for _,heights in ipairs({{3,4},{4,3},{6,6},{6,8}}) do
    for style=1,6 do
      local lo,hi=unpack(heights)
      runs={}
      local grid={}
      function grid.corner(_,x,z)
        if x==xa and z==za then return lo end
        assert(x==xb and z==zb);return hi
      end
      local field={slope=1,base=0,fences={[side]=style}}
      local f=create({s={corner_grid=grid,stock_farm_fields={[1]=field}},
        farm_world={field=function()return field end},Sim={xy=function()return 10,10 end}},grid)
      f.step(.4)
      local rise=math.abs(lo-hi)
      if rise==2 then assert(#runs==0) else
        assert(#runs==1)
        local r=runs[1]
        assert(refs[r.name] and r.name:match(("_%d_%d$"):format(style,rise)))
        near(r.pos.x,xa+xb-.5);near(r.pos.z,za+zb-.5);near(r.pos.y,math.min(lo,hi)+.5)
        -- Luanti builtin vector.rotate for +X and yaw alone:
        -- x=cos(yaw), z=sin(yaw). The slope mesh goes uphill along +X.
        local sign=lo>hi and -1 or 1
        near(math.cos(r.yaw),(xb-xa)*sign)
        near(math.sin(r.yaw),(zb-za)*sign)
      end
    end
  end
end
print("PASS farm fence live placement: six mesh styles, four edges, both rise directions, level and steep refusal")

-- Drive all three production adapters with a cropped window: the view must
-- paint the projected sides (including corners at a window boundary), not
-- the frozen local world or an extra copy of a shared edge.
local base="mods/luanttd_core/"
local Terrain=dofile(base.."openttd/terrain.lua")
local Projection=dofile(base.."campaign_terrain_projection.lua")
local Sim={W=2,H=1,xy=function(id) return id,1 end}
local Farm=dofile(base.."farm_factory_world.lua")(Sim,Terrain)
local source={tiles={{terrain="grass"},{terrain="grass"}},stock_farm_fields={}}
source.corner_grid=Terrain.new(2,1,function(x,z) return x==2 and 4-z+1 or 4 end)
local function seed(id,variant,fences)
  local slope,height=Terrain.tile(source.corner_grid,id,1)
  source.stock_farm_fields[id]={variant=variant,slope=slope,base=height,fences=fences,counter=7,industry=33}
end
seed(1,0,{[2]=4})
seed(2,1,{[0]=6})
local visual=dofile(base.."campaign_visual_state.lua")(Sim,{})
local function accept(first,last)
  local windows={}
  if first then
    local rows={}
    for id=first,last do rows[#rows+1]={id=id,surface=Projection.tile(source.tiles[id])} end
    local regs=Projection.registries(source,rows)
    local field=regs.stock_farm_fields[first]
    assert(not field.counter and not field.industry and field.fences~=source.stock_farm_fields[first].fences)
    local width=last-first+1
    windows[1]={value={tiles=rows,corners=Projection.corners(Terrain,source.corner_grid,first,1,width,1),
      x=first,z=1,width=width,height=1,registries=regs}}
  end
  visual.accept({windows=function()return windows end})
end
local function stale() error("worker view consulted stale/local interest") end
local f=create({s={},farm_world=Farm,Sim=Sim,interest={near=stale,each_tile=stale}},Terrain)
f.use_worker_projection(visual.state)
local player={{x=2.5,z=2.5}}
runs={}
accept(1,1)
f.step(.4,player)
assert(#runs==1 and runs[1].name=="luanttd_core:farm_fence_4_1")
near(runs[1].pos.x,3.5);near(runs[1].pos.y,3.5);near(runs[1].pos.z,2.5)
near(math.sin(runs[1].yaw),-1)
accept(1,2)
f.step(.4,player)
assert(#runs==1 and runs[1].pos,"the shared edge duplicated or replaced the stock fence")
accept(2,2)
f.step(.4,player)
assert(#runs==2 and not runs[1].pos and runs[2].name=="luanttd_core:farm_fence_6_1")
source.tiles[2].build="road"
accept(2,2)
f.step(.4,player)
assert(#runs==2 and not runs[2].pos,"an occupied tile kept stale field props")
source.tiles[2].build=nil
accept(1,2)
f.step(.4,player)
assert(#runs==3 and runs[3].pos)
f.step(.4,{{x=90,z=90}})
assert(not runs[3].pos,"props were not culled beyond the admitted player radius")
f.step(.4,player)
assert(#runs==4 and runs[4].pos)
accept()
f.step(.4,player)
assert(#runs==4 and not runs[4].pos,"props survived the end of their projected window")
print("PASS worker farm fences: detached scene fields/corners, shared-edge identity, live occupation, distance and window culling")
