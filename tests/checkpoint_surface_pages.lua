local mod="mods/luanttd_core/"
local Page=dofile(mod.."checkpoint_pages.lua")
local S=dofile(mod.."checkpoint_surface_pages.lua")(Page,function(t)
  if t.rich then return end
  if t.wood then return string.rep(string.char(t.wood.id),13) end
  return string.rep(string.char(t.h),6)
end)
local function byte(k,n) return string.rep(string.char(k),n) end
local function plain(k) return byte(k,6)..byte(0,7) end
assert(not Page.from_pages(65,64,13,{[2]=byte(0,13)}))
assert(not Page.from_pages(65,64,13,{byte(0,64*13),byte(0,12)}))
local a,b,c={h=1,wood={id=7}},{h=2},{h=3,rich=true}
local slots,witness={a,b,c},{a,b,c}
local world={tiles=slots}
local surface=S.new(world,slots,witness,3,74)
local function copy(tick)
  local bytes,rich={},{}
  if surface.capture(tick,bytes,rich) then return table.concat(bytes),rich end
end
local wood=a.wood
local original=byte(7,13)..plain(2)..byte(0,13)
assert(not copy(100))
assert(surface.adopt(100,{"",original},64,{[3]=c},{[wood]=1}))
local prior,rich=copy(100)
assert(prior==original and rich[3]==c)
a.wood,b.wood=nil,wood
surface.touch(1);surface.touch(2);surface.touch(2)
assert(not copy(100) and surface.finish(174))
local moved=plain(1)..byte(7,13)..byte(0,13)
assert(copy(174)==moved and prior==original)
a.wood=wood;surface.touch(1)
assert(not surface.finish(248) and not copy(174),"shared wood requires the full graph")
a.wood=nil
local function adopt(tick)
  assert(surface.adopt(tick,{moved},64,{[3]=c},{[wood]=2}))
end
adopt(248)
slots[2]={h=4};surface.touch(2)
assert(not surface.finish(322) and not copy(248),"replaced tile requires full capture")
slots[2]=b;adopt(322)
surface.invalidate()
assert(not surface.finish(396) and not copy(322),"authority edit must discard the mirror")
adopt(396);surface.touch(0)
assert(not copy(396),"invalid receipt must discard the mirror")
adopt(470);c.rich=false;surface.touch(3)
assert(surface.finish(544))
local bytes,details=copy(544)
assert(bytes==plain(1)..byte(7,13)..plain(3) and details[3]==nil)
assert(not surface.finish(619) and not copy(544),"cannot reuse a mirror after a skipped stock day")
assert(not surface.adopt(618,{"truncated"},64,{},{}))
print("PASS checkpoint surfaces preserve immutable old pages and discard stale clocks, invalid receipts, aliases and slot replacement")
