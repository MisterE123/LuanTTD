local src="mods/luanttd_core/openttd/"
local T=dofile(src.."rail_track.lua")
local W=dofile(src.."ship_follow.lua")(T)
local D=dofile(src.."ship_facilities.lua")(T,W)
local delta={[0]=-1,20,1,-20}
local function id(x,z) return x+20*z end
local tiles={}
local B={tile=function(i)return tiles[i] end,
  xy=function(i)return i%20,math.floor(i/20) end,
  adjacent=function(i,d)return i+delta[d] end}
local function fails(reason,fn,...)
  local result,why=fn(...)
  assert(not result and why==reason,("expected %s, got %s"):format(reason,tostring(why)))
end
local slope={[0]=3,9,12,6}
for dir=0,3 do
  local land=id(7,7)
  local pier=land+delta[dir]
  local head=pier+delta[dir]
  tiles[land]={kind="clear",slope=slope[dir]}
  tiles[pier]={kind="sea",slope=0,clear_cost=600}
  tiles[head]={kind="river",slope=0}
  local got={}
  local plan=assert(D.dock(B,land,{
    clear=function(i,t,auto)
      assert(not auto)
      got[#got+1]=i
      return t.clear_cost or 0
    end,
    station=function(a) return a.w==1 or a.h==1 end,
  }))
  assert(plan.dir==dir and plan.cost==350 and plan.water==pier and plan.approach==head and plan.water_class=="sea")
  assert(got[1]==land and got[2]==pier and #got==2)
  assert(plan.station_area.w==(dir%2==0 and 2 or 1))
  tiles[head]={kind="sea",rocks=true,is_water_tile=false,slope=0}
  assert(D.dock(B,land).approach==head and W.at(B,head)==0)
  assert(#D.docking_neighbors(B,pier)==0)
  tiles[pier].rocks,tiles[pier].is_water_tile=true,false
  assert(D.dock(B,land).cost==950)
  tiles[pier].rocks,tiles[pier].is_water_tile=nil,nil
  tiles[head]={kind="river",slope=0}
  assert(plan.station_area.h==(dir%2==1 and 2 or 1))
  fails("NOT_ENOUGH_MONEY",D.dock,B,land,{budget=40})
  tiles[pier].overhead=true
  fails("BRIDGE_ABOVE",D.dock,B,land)
  tiles[pier].overhead=nil
  tiles[pier].kind="object";tiles[pier].water_ground=true;tiles[pier].water_class="canal"
  plan=assert(D.dock(B,land))
  assert(plan.cost==950 and plan.water_class=="canal")
  tiles[head].kind="coast";tiles[head].slope=1
  fails("SITE_UNSUITABLE",D.dock,B,land)
  tiles[head].kind="object";tiles[head].slope=0;tiles[head].water_ground=true
  fails("SITE_UNSUITABLE",D.dock,B,land)
  local side=B.adjacent(pier,(dir+1)%4)
  tiles[side]={kind="lock",part="middle",dir=(dir+1)%4,slope=0,water_class="river"}
  assert(#D.docking_neighbors(B,pier)==0)
  tiles[head]={kind="sea",docking=true}
  tiles[side].part="upper"
  assert(#D.docking_neighbors(B,pier)==2)
  tiles[pier]={kind="dock",station=5,water_part=true}
  assert(W.ship_destination(B,head,5) and not W.ship_destination(B,head,6))
  tiles[land].water_ground=true
  fails("SITE_UNSUITABLE",D.dock,B,land)
  tiles={}
end
for axis=0,1 do
  local a=id(10,10);local b=a+delta[axis==0 and 2 or 1]
  tiles[a]={kind="river",clear_cost=120}
  tiles[b]={kind="object",water_ground=true,water_class="canal",clear_cost=175}
  local v={}
  local plan=assert(D.depot(B,a,axis,{clear=function(i,t,automatic)
    assert(automatic);v[#v+1]=i
    return t.clear_cost
  end}))
  assert(v[1]==a and v[2]==b and plan.tiles[2]==b and plan.cost==875)
  assert(plan.water_classes[1]=="river" and plan.water_classes[2]=="canal")
  tiles[b].slope=9
  fails("SITE_UNSUITABLE",D.depot,B,a,axis)
  tiles[b].overhead=true
  fails("BRIDGE_ABOVE",D.depot,B,a,axis)
  tiles={}
end
for mask=0,31 do
  local d=D.direction(mask)
  if d~=nil then assert(slope[d]==mask) else
    for dir=0,3 do assert(slope[dir]~=mask) end
  end
end
print("PASS: source four dock slopes, three-tile checks, water classes/clear costs, legal berths, and both two-tile ship depot axes")
