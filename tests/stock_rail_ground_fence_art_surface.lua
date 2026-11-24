-- Exhaust the actual code's legal grade × stock fence art contract.
local root="mods/luanttd_core/"
local t=dofile(root.."openttd/rail_track.lua")
local slope=dofile(root.."openttd/slope.lua")
local ground=dofile(root.."openttd/rail_ground_temperate.lua")(t)
local works=dofile(root.."trackworks.lua")({},t,{},slope,{},{},function()end)
local supported={[0]={2,3,4,5,6,7,8,9,10,11},[3]={2,3,4},[12]={2,3,4},[6]={5,6,7},[9]={5,6,7}}
local seen={}
for _,mask in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}) do
  for bits=1,63 do
    local grade,base,foundation,profile=works.surface(mask,12,bits)
    if grade then
      profile=profile or 0
      if grade~=0 then assert((bits==1 and (profile==3 or profile==12)) or (bits==2 and (profile==6 or profile==9))) end
      for neighbors=0,15 do
        local state=ground.visit({owner=5,tracks=bits,plain=true,ground=1},function(d)
          if t.has(neighbors,d) then return {owner=3,kind="clear"} end
          return {owner=5,kind="clear"}
        end)
        if state~=1 then
          local matches=0
          for _,v in ipairs(assert(supported[profile],profile)) do if state==v then matches=matches+1 end end
          assert(matches==1,("unsupported fence state %d on profile %d (raw mask %d, track %d)"):format(state,profile,mask,bits))
          local key=state.."_"..profile
          if not seen[key] then
            local file=assert(io.open(root.."models/bl_rail_ground_fence_"..key..".obj","rb"))
            file:close()
          end
          seen[key]=true
        end
      end
    end
  end
end
local count=0
for _ in pairs(seen) do count=count+1 end
assert(count==22,count)
print("PASS exhaustive Trackworks grade and RC1 rail-ground state product: 22 reachable art mounts")
