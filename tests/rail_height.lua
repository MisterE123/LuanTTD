local root="mods/luanttd_core/openttd/"
local Track=dofile(root.."rail_track.lua")
local Slope=dofile(root.."slope.lua")
local Raw=dofile(root.."rail_motion.lua")(Track)
local Height=dofile(root.."rail_height.lua")(Track,Slope)
local function close(a,b) assert(math.abs(a-b)<1e-12,tostring(a).." ~= "..tostring(b)) end
local cases={
  {0,1,"none",0,2},             -- flat ground
  {3,1,"none",3,2},             -- genuine N/E low to W/S high
  {12,1,"none",12,2},           -- mirrored X grade
  {6,2,"none",6,2},             -- both Y grade directions
  {9,2,"none",9,2},
  {2,1,"x",3,2},               -- fills the other corner to incline track
  {8,1,"x",12,2},
  {23,1,"x",3,3},              -- steep slope raises foundation base one level
  {29,2,"y",9,3},
  {13,1,"leveled",0,3},        -- rail top comes from stock foundation
  {8,12,"half",232,2},         -- pure integer query, not native runtime
  {30,48,"steep_both",164,3},
}
for _,q in ipairs(cases) do
  local p=assert(Height.profile({kind="rail",slope=q[1],trackbits=q[2]},2))
  assert(p.foundation==q[3] and p.surface==q[4] and p.base_level==q[5])
end
assert(not Height.profile({kind="rail",slope=15,trackbits=1},2))
assert(not Height.profile({kind="rail",slope=1,trackbits=3},2))
for _,kind in ipairs({"station","waypoint","depot","crossing"}) do
  local p=assert(Height.profile({kind=kind,slope=30,axis=1,dir=1},2))
  assert(Height.pixel(p,0,0)==32 and Height.pixel(p,15,15)==32)
  local mid,angle=Height.render(p,1,.5)
  assert(mid==4 and angle==0)
end
local no_mesh=assert(Height.profile({kind="rail",slope=8,trackbits=12},2))
assert(not Height.render(no_mesh,2,.5))

-- A real shared-corner X profile: low, up one level, high, down, low.
-- Traverse in both directions. Every train movement pixel matches stock
-- expected center height and parity; every native running surface meets
-- its neighbor's edge at exactly the same world level.
local corners={[2]=4,[3]=4,[4]=5,[5]=5,[6]=4,[7]=4}
local function raw(x)
  return Slope.classify(corners[x],corners[x+1],corners[x],corners[x+1])
end
local board={tile=function(id)
  if not corners[id] or not corners[id+1] then return end
  return {kind="rail",trackbits=1,slope=raw(id)}
end}
local z_at,profile=Height.bind(board,raw)
for _,td in ipairs({0,8}) do
  local sign=td==8 and 1 or -1
  local ix=td==8 and 2 or 6
  local start,finish=ix,td==8 and 6 or 2
  local p=assert(Raw.entry_trackdir(start,11,td))
  local state=Height.enter(assert(profile(ix)),p)
  local up_ticks,down_ticks,absolutes=0,0,0
  for _=1,79 do
    local tag,next_=Raw.step(p,td)
    local new_tile=tag=="enter"
    if new_tile then
      assert(next_.tx==ix+sign)
      local previous,old_pitch=Height.render(assert(profile(ix)),td,1)
      ix=next_.tx
      local next_level=Height.render(assert(profile(ix)),td,0)
      close(previous,next_level)
      assert(old_pitch==0 or math.abs(old_pitch)==math.atan(.5))
    end
    local sample=assert(profile(ix))
    local next_state,old_z=Height.advance(sample,next_,state,new_tile)
    assert(next_state and old_z==state.z and next_state.z==z_at(ix,next_.x,next_.y))
    if next_state.z>old_z then up_ticks=up_ticks+1 end
    if next_state.z<old_z then down_ticks=down_ticks+1 end
    if new_tile then absolutes=absolutes+1 end
    state,p=next_state,next_
  end
  assert(ix==finish and up_ticks==8 and down_ticks==8 and absolutes==4)
end
local p=profile(3)
local fwd,pos,dy=Height.render(p,8,.25)
local back,neg,drop=Height.render(p,0,.75)
close(fwd,back);close(pos,-neg);assert(dy==1 and drop==-1)
local lead=assert(Raw.entry_trackdir(3,11,8))
local flags=Height.enter(p,lead)
assert(flags.up and not flags.down and flags.z==32)
assert(Height.reverse(flags).down and Height.reverse(flags).z==32)
assert(not Height.advance(p,lead,{z=90,up=true,down=false},false))
print("PASS: shared-corner graded rail climbs and descends exactly eight pixels; native edge heights/pitch match, no fallback height")
