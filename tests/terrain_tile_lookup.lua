-- Same independent reads as the original GetTileSlopeZ host adapter;
-- verify direct row-major lookups, staged plans and all inclusive edge corners.
local root="mods/luanttd_core/openttd/"
local T=dofile(root.."terrain.lua")
local Slope=dofile(root.."slope.lua")
local function check(g,plan)
  for z=1,g.depth do for x=1,g.width do
    local n=T.corner(g,x,z,plan)
    local w=T.corner(g,x+1,z,plan)
    local e=T.corner(g,x,z+1,plan)
    local s=T.corner(g,x+1,z+1,plan)
    local expected,base=Slope.classify(n,w,e,s)
    local actual,ground,peak=T.tile(g,x,z,plan)
    assert(actual==expected and base==ground and peak==math.max(n,w,e,s))
  end end
  assert(T.tile(g,0,1,plan)==nil and T.tile(g,1,0,plan)==nil and T.tile(g,1.5,2,plan)==nil)
  assert(T.tile(g,g.width+1,1,plan)==nil and T.tile(g,1,g.depth+1,plan)==nil)
end
for _,measure in ipairs({{4,7},{64,32},{13,91}}) do
  local g=T.new(measure[1],measure[2],function(x,z) return 4+math.floor((x+z)/8) end)
  check(g)
  local plan=assert(T.plan(g,3,3,8,true,{freeform_edges=true}))
  check(g,plan)
  assert(T.apply(g,plan))
  check(g)
  -- Numeric zero is a valid override and must never fall back to the
  -- old corner height.
  local zero={levels={[1]=0}}
  check(g,zero)
end
-- The lookup only fast-accepts the exact recorded normalized corners.
-- Even malformed input keeps the old classifier fallback semantics.
local g=T.new(1,1)
for n=0,3 do for w=0,3 do for e=0,3 do for s=0,3 do
  g.levels[1],g.levels[2],g.levels[3],g.levels[4]=n,w,e,s
  local mask,base=T.tile(g,1,1)
  assert(T.matches(g,1,1,mask,base))
  assert(not T.matches(g,1,1,mask,base+1))
  assert(not T.matches(g,1,1,mask,tostring(base)))
  assert(not T.matches(g,1,1,(mask+1)%32,base))
end end end end
assert(not T.matches(g,0,1,0,0) and T.matches(g,0,1,nil,nil))
print("PASS direct stock terrain lookup agrees with independent corners, edges and staged writes")
