local M=dofile("mods/luanttd_core/sim.lua")
local layout=dofile("mods/luanttd_core/town_layout.lua")
local T=dofile("mods/luanttd_core/openttd/terrain.lua")
local seed_terrain=dofile("mods/luanttd_core/terrain_preview.lua")
for seed=1,60 do
  local s=M.new(seed)
  layout(M,s)
  s.corner_grid=seed_terrain(M,T,s)
  local held={}
  for id,t in ipairs(s.tiles) do
    if t.road_town and not held[t.road_town] then held[t.road_town]=id end
  end
  assert(held[1] and held[2])
  for _,origin in ipairs(held) do
    local town=s.tiles[origin].road_town
    local queue,seen={origin},{[origin]=true}
    local i=1
    while queue[i] do
      local id=queue[i];i=i+1
      for d=1,4 do
        if M.road_edge(s,id,d) then
          assert(M.road_connected(s,id,d),"broken edge in the authored street plan")
          local j=M.adjacent(id,d)
          assert(s.tiles[j].road_town==town)
          if not seen[j] then queue[#queue+1]=j;seen[j]=true end
        end
      end
    end
    for id,t in ipairs(s.tiles) do
      if t.road_town==town then assert(seen[id],"town should have one connected street network") end
    end
    assert(#queue>=15)
  end
  for x=9,18 do assert(not s.tiles[M.id(x,12)].road_town and not s.tiles[M.id(x,12)].house) end
  assert(not s.tiles[M.id(10,13)].road_town)
end
print("PASS: 60 seeds, connected town streets and clear starter right of way")
