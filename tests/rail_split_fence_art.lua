local m="mods/luanttd_core/"
local function load(n) return dofile(m..n..".lua") end
local Track,Slope=load("openttd/rail_track"),load("openttd/slope")
local Split=load("rail_split_profile")(Track,load("openttd/rail_height")(Track,Slope))
local Fence=load("rail_split_fence")(Slope)
local Ground=load("openttd/rail_ground_temperate")(Track)
local Half=load("openttd/rail_half_water")(Track,Slope)
local dry,wet,keys={},{},{}
local corner={[8]={1,0},[9]={0,1},[10]={0,0},[11]={1,1}}
local fmt="Expected the pinned ground state to resolve on shape %d with tracks %d"
local function check(p,g,bits,raw_base)
 local key,edge,h,q=Fence.design(p,g,bits,raw_base)
 assert(key,fmt:format(p.raw_shape,bits))
 local file=assert(io.open(m.."models/bl_rail_split_fence_"..key..".obj","rb"))
 file:close()
 keys[key]=true
 if g>=8 and g<=11 then
   local ref=corner[g]
   local source_datum=p.base_level-raw_base+Slope.surface(ref[1],ref[2],p.surface%32)
   for _,v in ipairs(h) do assert(math.abs(v/q-source_datum)<1e-6) end
 elseif g<=7 then
   for i,v in ipairs(h) do
     local x,z=edge[1]+(edge[3]-edge[1])*(i-1)/4,edge[2]+(edge[4]-edge[2])*(i-1)/4
     local expected=p.base_level-raw_base+Slope.surface((x+.5)/2,(z+.5)/2,p.surface)
     assert(math.abs(v/q-expected)<.001, "Fence toe must follow the actual 3D slope.")
   end
 end
 return key
end
for _,shape in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}) do
 for bits=1,63 do
  local p=Split.profile(shape,10,bits)
  if p then
   assert(Fence.design(p,0,bits,10)==nil and Fence.design(p,1,bits,10)==nil)
   for mask=0,15 do
    local g=Ground.visit({owner=1,tracks=bits,plain=true,ground=1},function(d)
      if Track.has(mask,d) then return {owner=1} end
    end)
    if g>1 then
      check(p,g,bits,10);dry[p.mesh_key..":"..g]=true
      if g>=8 and g<=11 and Half.dry_ground(bits)==g then
        assert(Fence.design(p,13,bits,10)==Fence.design(p,g,bits,10))
        wet[p.mesh_key..":"..g]=true
      end
    end
   end
  end
 end
end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
assert(count(dry)==108 and count(keys)==60 and count(wet)==36)
print("PASS all 108 reachable stock dry split fence forms; 60 unique meshes, inset cut-slope heights, and wet corner datum")
