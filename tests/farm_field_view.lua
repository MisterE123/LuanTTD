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
