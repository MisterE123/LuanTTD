local p="mods/luanttd_core/"
local function load(n) return dofile(p..n..".lua") end
local Track,Slope=load("openttd/rail_track"),load("openttd/slope")
local Split=load("rail_split_profile")(Track,load("openttd/rail_height")(Track,Slope))
local Fence=load("rail_split_fence")(Slope)
local G=load("openttd/rail_ground_temperate")(Track)
local lore={}
for _,shape in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}) do
  for bits=1,63 do
    local profile=Split.profile(shape,0,bits)
    if profile then
      for neighbor=0,15 do
        local g=G.visit({owner=1,tracks=bits,plain=true,ground=1},function(d)
          if Track.has(neighbor,d) then return {owner=1} end
        end)
        local key,edge,h,q=Fence.design(profile,g,bits,0)
        if key then lore[key]={edge,h,q} end
      end
      if profile.foundation=="half" or profile.foundation=="rail" or profile.foundation=="none" then
        -- And the stock dedicated upper-half wet fence, even if both
        -- neighboring road cells are owned by the same company.
        local key,edge,h,q=Fence.design(profile,13,bits,0)
        if key then lore[key]={edge,h,q} end
      end
    end
  end
end
local keys={}
for k in pairs(lore) do keys[#keys+1]=k end
table.sort(keys)
for _,k in ipairs(keys) do local v=lore[k]
  print(table.concat({k,table.concat(v[1],","),table.concat(v[2],","),v[3]},"\t"))
end
