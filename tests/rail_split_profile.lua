local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Track,Slope=load("openttd/rail_track"),load("openttd/slope")
local Height=load("openttd/rail_height")(Track,Slope)
local P=load("rail_split_profile")(Track,Height)
local Pose=load("rail_pose")(Track)
local Motion=load("openttd/rail_motion")(Track)
local total=0
for _,shape in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}) do
  for bits=1,63 do
    local q=Height.profile({kind="rail",trackbits=bits},4,shape)
    if P.supported(q) then
      total=total+1
      assert(bits%4==0)
      for td=0,13 do
        if Track.valid_trackdir(td) and Track.has(bits,Track.track(td)) then
          local ground=assert(P.level(q,Track.track(td)))
          local raw=assert(Motion.entry_trackdir(10,10,td))
          local height=Height.enter(q,raw)
          assert(height.z==ground*8)
          for _=1,16 do
            local code,next_=Motion.step(raw)
            if code=="boundary" then break end
            assert(code=="move")
            height=assert(Height.advance(q,next_,height,false))
            assert(height.z==ground*8)
            raw=next_
          end
          for i=0,64 do
            local x,z=Pose.sample(td,i/64)
            local h=q.base_level+Slope.surface((x+1)/2,(z+1)/2,q.surface)
            assert(math.abs(h-ground)<1e-6)
          end
        end
      end
    end
  end
end
assert(total==44)
print("PASS 44 special rail foundation profiles: stock curved geometry stays on the same railhead from port to port")
