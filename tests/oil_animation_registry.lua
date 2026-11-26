local M=dofile("mods/luanttd_core/oil_animation_registry.lua")
local Codec=dofile("mods/luanttd_core/packed_campaign.lua")
local s={}
-- Activation is source visit order, not sorted TileIndex order.
M.add(s,74)
M.add(s,9)
M.add(s,24)
M.add(s,74)
assert(table.concat(s.stock_oil_animation_order,",")=="74,9,24")
local tiles={[9]={id=9,gfx=30},[24]={id=24,gfx=31},[74]={id=74,gfx=32},[101]={id=101,gfx=29}}
local calls={}
local function animate(t,tick,rng)
  calls[#calls+1]={t.id,tick,rng()}
  if t.id==9 then t.gfx=29;return true,false end
  return true,true
end
local draws=0
local function random() draws=draws+1;return draws end
local register,step=M.bind(s,tiles,animate,random)
step(1025)
assert(#calls==0 and draws==0)
step(1032)
assert(#calls==3 and calls[1][1]==74 and calls[2][1]==9 and calls[3][1]==24)
assert(not s.stock_oil_animated[9] and s.stock_oil_animation_order[2]==9)
local checkpoint=Codec.decode(Codec.encode({motion=s,tile=tiles}))
s,tiles=checkpoint.motion,checkpoint.tile
register,step=M.bind(s,tiles,animate,random)
step(1033)
assert(#calls==3 and table.concat(s.stock_oil_animation_order,",")=="74,24")
tiles[101].gfx=30
register(101,true)
assert(table.concat(s.stock_oil_animation_order,",")=="74,24,101")
step(1040)
assert(calls[4][1]==74 and calls[5][1]==24 and calls[6][1]==101 and calls[6][3]==6)
register(24,false)
tiles[24].gfx=30;register(24,true)
step(1041)
assert(table.concat(s.stock_oil_animation_order,",")=="74,24,101","A reactivated deleted tile retains its slot")
local migrated={}
M.bind(migrated,tiles,animate,random)
assert(table.concat(migrated.stock_oil_animation_order,",")=="24,74,101")
print("PASS RC1 oil animated-tile admission order, deferred swap-removal, RNG order, checkpoint and state recovery")
