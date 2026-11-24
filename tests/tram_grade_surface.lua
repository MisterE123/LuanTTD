local src="mods/luanttd_core/openttd/"
local Slope=dofile(src.."slope.lua")
local Road=dofile(src.."road_slope.lua")
local G=dofile(src.."tram_grade_surface.lua")(Road,Slope)
local Bridge=dofile(src.."road_bridge.lua")(Slope)
local Tram=dofile(src.."tram_construction.lua")(Road,Bridge.roadtypes)
local o={owner="QA",build_on_slopes=true,clear_quote=function()return 0 end}
local masks={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}
local count,shapes=0,{}
for _,mask in ipairs(masks) do
  for bits=1,15 do
    local p=Tram.lay({kind="clear",slope=mask,base=2},bits,1,o)
    if p then
      local q=assert(G.surface(mask,2,p.tram_bits,0))
      assert(q.foundation==p.foundation)
      local sourced,lift=Slope.foundation(mask,p.foundation)
      assert(q.grade==sourced and q.base==2+lift)
      assert(G.at(q,.5,.5)==2+lift+Slope.surface(.5,.5,sourced))
      shapes[q.grade]=true
      count=count+1
    end
  end
end
for _,shape in ipairs{0,3,6,9,12} do assert(shapes[shape],shape) end
local a=assert(G.surface(3,2,10))
local b=assert(G.surface(0,3,10))
assert(G.match(a,b,2))
assert(not G.match(a,b,4))
assert(not G.surface(1,2,10,5))
print(("PASS %d allowed RC1 tram layouts resolve to a source plateau/plane and meet neighboring edges"):format(count))
