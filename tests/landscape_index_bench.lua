-- Optional rough Lua 5.1 measurement for the detached 4096-square path.
local p="mods/luanttd_core/openttd/"
local H=dofile(p.."town_passengers.lua")
local M=dofile(p.."landscape_index.lua")
local function mem() collectgarbage("collect");return collectgarbage("count") end
local function start() return H.new_clock(12,12,6090,253) end
local before=mem()
local t=os.clock()
local idx=M.new(12,12)
print(("4096² constructor %.3f ms, %.1f KiB heap"):format((os.clock()-t)*1000,mem()-before))
t=os.clock()
local anchor=idx.index(6090)
assert(idx.at(anchor)==6090)
print(("4096² first rank incl. index build %.3f ms, %.1f KiB total heap"):format((os.clock()-t)*1000,mem()-before))
local tiles={0}
for i=1,128 do tiles[#tiles+1]=(1749637*i+98765)%idx.period+1 end
t=os.clock()
local compiled=idx.compile(tiles)
print(("4096² 129 active IDs cold compile %.3f ms, %.1f KiB total heap"):format((os.clock()-t)*1000,mem()-before))
local s,n=start(),0
t=os.clock()
for _=1,100 do idx.advance_active(s,74,compiled,function() n=n+1 end) end
print(("4096² 100 resumed sparse days: %.3f ms total, %d visits, head %d"):format((os.clock()-t)*1000,n,s.head))
assert(s.head==idx.skip(start(),100*74).head and n==3729)
local one=start()
t=os.clock()
local visited=0
H.advance(one,74,function()visited=visited+1 end)
print(("4096² 1 full source Lua day: %.3f ms, %d visits"):format((os.clock()-t)*1000,visited))
assert(one.head==idx.skip(start(),74).head)
local stats=idx.stats()
print("4096² baby/giant/columns",stats.baby_steps,stats.giant_slots,stats.jump_columns)
