local shows,maps,callbacks=0,{},{}
local M=dofile("mods/luanttd_core/campaign_projection_painter.lua")({
  use_worker_projection=function() shows=shows+1 end,
  place_projected=function(x,z,w,h,done)
    maps[#maps+1]={x=x,z=z,w=w,h=h};callbacks[#maps]=done
  end,
})
local function tile(x,scene)
  return {value={x=x,z=1,width=32,height=32,scene=scene,tiles={{}}}}
end
local function present(...) local rows={...};M.present({windows=function() return rows end}) end
present(tile(1,1),tile(33,2))
assert(M.step() and not M.step() and maps[1].x==1)
present(tile(1,1),tile(33,2)) -- fresh actor packets but unchanged surface
assert(shows==1)
callbacks[1](true)
assert(M.step() and maps[2].x==33)
present(tile(1,3)) -- old region leaves and original region changes
callbacks[2](true)
assert(M.step() and maps[3].x==1)
callbacks[3](true)
assert(not M.step())
present(tile(1,3),tile(33,2)) -- re-entry is rehydrated even with same scene
assert(M.step() and maps[4].x==33 and shows==3)
print("PASS one bounded engine paint at a time, no redraw on actor refresh, re-entry and stale repairs safe")
-- The first zone is continuously changing while it is rendered, like an
-- active town. It may get another pass, but not ahead of untouched sectors.
present(tile(1,4),tile(33,2),tile(65,3))
callbacks[4](true)
assert(M.step() and maps[5].x==1)
present(tile(1,5),tile(33,2),tile(65,4))
callbacks[5](true)
assert(M.step() and maps[6].x==65)
present(tile(1,6),tile(33,2),tile(65,4))
callbacks[6](true)
assert(M.step() and maps[7].x==1)
callbacks[7](false,"retry")
present(tile(1,7),tile(33,3),tile(65,4))
assert(M.step() and maps[8].x==1)
present(tile(1,8),tile(33,3),tile(65,4))
callbacks[8](false,"retry")
assert(M.step() and maps[9].x==33)
print("PASS continuous neighbor changes and failed paints cannot starve older waiting sectors")
