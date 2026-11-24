local m="mods/luanttd_core/openttd/"
local W=dofile(m.."rail_half_water.lua")(dofile(m.."rail_track.lua"),dofile(m.."slope.lua"))
local wet=W.HALF_TILE_WATER
local triple={{1,16,32,8},{2,8,4,11},{4,32,16,9},{8,4,8,10}}
local function fail() error("unexpected rail removal attempt") end
for _,c in ipairs(triple) do
  local shape,up,low,ground=unpack(c)
  assert(not W.flood(shape,up,wet,fail))
  local q=assert(W.flood(shape,up,1,fail))
  assert(q.kind=="rail" and q.tracks==up and q.ground==wet and not q.removed)
  assert(W.water_tracks(shape,up,wet)==low and W.water_tracks(shape,up,1)==0)
  assert(W.dry_ground(up)==ground)
  assert(not W.flood(shape,up+low,1,function(b) assert(b==low);return false end))
  q=assert(W.flood(shape,up+low,1,function(b) assert(b==low);return true end))
  assert(q.kind=="rail" and q.tracks==up and q.ground==wet and q.removed==low)
  q=assert(W.flood(shape,low,1,function(b) assert(b==low);return true end))
  assert(q.kind=="coast" and q.removed==low)
end
for _,v in ipairs({{7,8},{11,16},{13,4},{14,32},{23,8},{27,16},{29,4},{30,32}}) do
  local q=assert(W.flood(v[1],v[2],1,fail))
  assert(q.kind=="rail" and q.ground==wet and W.water_tracks(v[1],v[2],wet)==0)
end
assert(W.flood(3,8,1,fail).ground==wet) -- the special foundation creates a 3-corner slope
assert(not W.flood(0,1,1,fail))
assert(not W.flood(23,1,1,fail))
print("PASS RC1 railway flood rules: lower-track removal, partial coasts, water lane, dry fence and three-corner shore")
