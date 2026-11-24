-- Current stock movement kernel driven through the exact 16.0-RC1
-- Helidepot and Helistation tables. This is not a native build/readiness gate.
local src="mods/luanttd_core/openttd/"
local function m(n) return dofile(src..n..".lua") end
local A=m("airport_rotary_ground_profiles")
local M=m("airport_motion")(m("airport_small"))
local Rotor=m("airport_rotary_motion")(M)
local D={id=1,layout="helidepot",x=800,z=800,ground=0,flags=0,rotation=0,width=2,height=2}
local T={id=2,layout="helistation",x=1175,z=880,ground=0,flags=0,rotation=0,width=4,height=2}
local airports={[1]=D,[2]=T}
local visits,departures={},0
local ctx={rotary=Rotor,airports=airports,layout=function(a) return A[a.layout] end,
  ground_height=function() return 0 end,terrain_height=function() return 0 end,
  flight_terrain_height=function() return 0 end,slope_pixel_z=function() return 0 end,
  tile_at=function(x,z)return math.floor(x/16)+1000*math.floor(z/16) end}
local v=assert(A.helidepot.new(D,{helicopter=true,owner="Player",order={kind="station",id=T.id}}))
assert(v.hidden and v.x==824 and v.z==804)
local a=D
for _=1,20000 do
  local next,events,why=M.tick(a,v,ctx)
  assert(not why,why)
  a=next
  for _,e in ipairs(events) do
    if e=="terminal" then
      assert(v.y==1 and v.tile and v.loading)
      visits[a.id]=(visits[a.id] or 0)+1
      local pk=a==D and {{8,24}} or {{40,8},{56,8},{56,24}}
      local found=false
      for _,p in ipairs(pk) do if v.x==a.x+p[1] and v.z==a.z+p[2] then found=true end end
      assert(found,"wrong native pad terminal")
      v.loading=nil
      v.order={kind="station",id=3-a.id}
    elseif e=="departed" then departures=departures+1 end
  end
  if (visits[1] or 0)>=2 and (visits[2] or 0)>=2 then break end
end
assert(visits[1]==2 and visits[2]==2 and departures==4,"Failed complete two-way rotorcraft service")
assert(D.flags==64 and T.flags==0,"Remote helipad reservation leaked")
do
  local station={flags=0}
  local f=A.helistation
  for i=1,3 do
    local incoming={helicopter=true}
    assert(f.free_terminal(station,incoming))
    assert(incoming.state==f.terminal_states[i] and f.has(station.flags,f.terminal_bits[i]))
  end
  assert(not f.free_terminal(station,{helicopter=true}))
end
print("PASS RC1 ground rotor airports: ordinary pickup, stock pad reservations and repeated two-way flights")
