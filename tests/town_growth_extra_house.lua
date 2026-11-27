-- SPDX-License-Identifier: GPL-2.0-only
-- RC1 GrowTownInTile's Better Roads branch can build an extra house
-- independently of the primary roadside house.
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."town_growth.lua")
local B=dofile(p.."town_growth_build.lua")(G,{})
local function check(primary,extra,two)
  local t=G.new(1,8,8,{layout="better",growing=true,grow_counter=0})
  local clear={kind="clear",slope=0}
  local house={kind="house"}
  local cells={
    ["8:8"]={kind="road",road_bits=5},
    ["5:8"]=house,["6:7"]=house,["6:9"]=house,
    ["7:8"]=primary=="occupied" and house or clear,
  }
  local function tile(x,z) return cells[x..":"..z] or clear end
  local seen,received={},{}
  B.house=function(_,_,x,z)
    seen[#seen+1]=x..":"..z
    if x==6 or (x==7 and primary=="build") then return {kind="house",x=x,z=z} end
  end
  local opts={year=1950,allow_roads=true,extra_house=function(proposal)
    received[#received+1]=proposal.x
    if extra then
      cells["6:8"]=house
      G.house_added(t,{},2)
      return true
    end
  end}
  local draws=0
  local attempted,built=G.tick(t,function()
    local place,extra_built=B.grow(t,{tile=tile,distance_to_edge=function() return 1 end},opts,function()
      draws=draws+1
      assert(draws<=2,"resumed road walk after successful extra house")
      return 0
    end)
    if place then
      assert(two and place.x==7)
      G.house_added(t,{},2)
    end
    assert(not not extra_built==extra)
    return not not (place or extra_built)
  end)
  assert(attempted and built==(extra or two))
  assert(received[1]==6 and #received==1)
  assert(seen[1]=="6:8" and seen[2]==(primary~="occupied" and "7:8" or nil))
  assert(t.num_houses==(extra and 1 or 0)+(two and 1 or 0))
  assert(t.grow_counter==(built and t.growth_rate or G.TOWN_TICKS-1))
  return draws
end
assert(check("occupied",true,false)==1)
assert(check("blocked",true,false)==2)
assert(check("build",true,true)==2)
print("PASS extra-only and paired RC1 growth update the live countdown")
