-- Safe placement without consuming the registered native slope node.
local registered={}
local base,top=1,2
local function architecture(name,asset,prefix)
  assert(name=="stock_"..asset and asset:match("^"..prefix))
  assert(not registered[name]);registered[name]=true
  local f=assert(io.open("mods/bayline/models/bl_"..asset..".obj"))
  local count,hi,lo=0,-9,9
  for line in f:lines() do
    local x,y,z=line:match("^v ([^ ]+) ([^ ]+) ([^ ]+)")
    if y then
      x,y,z=tonumber(x),tonumber(y),tonumber(z)
      assert(x>=-1 and x<=2 and z>=-2 and z<=1)
      count=count+1;hi=math.max(hi,y);lo=math.min(lo,y)
    end
  end
  f:close()
  if asset:match("_water$") then
    assert(count>=8 and hi==-.482 and lo==-2.55 and 1+lo<.5-2)
  else
    assert(count>=8 and hi==.5 and lo<.5-tonumber(asset:sub(-1)))
  end
  return name
end
local road={[0]="road_bridge_wood",[1]="road_bridge_concrete",[2]="road_bridge_girder"}
local slope=3
local terrain={tile=function(id)assert(id==9);return slope,base,top end}
local renderer=dofile("mods/bayline/bridge_pier_render.lua")
local road_foot=renderer(architecture,terrain,road)
local rail_foot=renderer(architecture,terrain,{"rail_bridge_wood"})
for axis=0,1 do for dep=1,2 do
  base,top=2-dep,2
  for d=1,3 do
    local span={axis=axis,deck=top+d}
    for style,prefix in pairs(road) do
      assert(road_foot(9,11,top,13,span,style)==("stock_%s_foot_%d_%d"):format(prefix,axis,dep))
      assert(not road_foot(9,10,top,12,span,style))
      assert(not road_foot(9,11,top+1,13,span,style))
    end
    assert(rail_foot(9,11,top,13,span,1)==("stock_rail_bridge_wood_foot_%d_%d"):format(axis,dep))
  end
end end
base=top
assert(not road_foot(9,11,top,13,{axis=0,deck=top+1},0),"same-level paved/water tile requires no footing")
assert(not rail_foot(9,11,top,13,nil,1))
local total=0
for _ in pairs(registered) do total=total+1 end
assert(total==24)
slope,base,top=0,0,0
for axis=0,1 do for _,deck in ipairs{1,2,4} do
  local span={axis=axis,deck=deck}
  for style,prefix in pairs(road) do
    local want=("stock_%s_foot_%d_water"):format(prefix,axis)
    assert(road_foot(9,11,1,13,span,style,true)==want)
    assert(not road_foot(9,10,1,12,span,style,true))
    assert(not road_foot(9,11,0,13,span,style,true))
    assert(not road_foot(9,11,1,13,span,style,false))
  end
  assert(rail_foot(9,11,1,13,span,1,true)==("stock_rail_bridge_wood_foot_%d_water"):format(axis))
end end
slope,base,top=3,0,1
assert(road_foot(9,11,1,13,{axis=0,deck=2},0,true)=="stock_road_bridge_wood_foot_0_1",
  "Keep the existing real grade footing on inclined water/land")
print("PASS: all road/rail pier families, two dry grades and submerged support; preserved water and occupied anchor")
