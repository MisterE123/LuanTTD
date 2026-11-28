local O=dofile("mods/luanttd_core/openttd/station_stop_order.lua")
local function eq(expected,kind,destination,nonstop,manual,last,station)
  assert(O.should_stop(kind,destination,nonstop,manual,last,station)==expected,
    ("%s destination %s flags %d candidate %s"):format(kind,tostring(destination),nonstop,tostring(station)))
end
-- Stop at any station, skip intermediate, visit intermediates only, skip all.
for flags=0,3 do
  eq(flags<2,"goto_station",5,flags,false,nil,5)
  eq(flags%2==0,"goto_station",5,flags,false,nil,7)
  eq(false,"goto_station",5,flags,false,5,5)
  eq(false,"goto_station",5,flags,false,7,7)
  eq(false,"goto_depot",5,flags,false,nil,7)
  eq(flags%2==0,"goto_depot",5,flags,true,nil,7)
end
eq(true,"nothing",nil,0,false,nil,7)
eq(true,"loading",7,0,false,nil,8)
print("PASS RC1 station-stop order flags, previous station, manual and automatic depot paths")
