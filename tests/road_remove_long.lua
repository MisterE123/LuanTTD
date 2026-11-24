local root="mods/luanttd_core/openttd/"
local K=dofile(root.."road_remove_long.lua")
local S=dofile(root.."road_slope.lua")
local board={}
function board.xy(i) return (i-1)%16+1,math.floor((i-1)/16)+1 end
function board.next(i,axis) return i+(axis==0 and 1 or 16) end
local function pieces(q)
  local list={}
  for i,a in ipairs(q) do list[i]=("%d:%d"):format(a.tile,a.bits) end
  return table.concat(list,",")
end
assert(pieces(K.request(board,1,4,0,true,false))=="1:2,2:10,3:10,4:8")
assert(pieces(K.request(board,4,1,0,false,true))=="1:2,2:10,3:10,4:8")
assert(pieces(K.request(board,17,1,1,false,true))=="1:4,17:1")
assert(pieces(K.request(board,1,1,0,true,false))=="1:10")
assert(pieces(K.request(board,1,1,0,true,true))=="1:2")
assert(pieces(K.request(board,1,1,0,false,false))=="1:8")
assert(pieces(K.request(board,1,1,0,false,true))=="1:10")
assert(not K.request(board,1,18,0,false,true))
assert(not K.request(board,1,18,1,false,true))
local mixed=K.request(board,1,8,0,true,true)
local function quote(t,bits)
  if t==1 then return nil,"NO_ROAD" end
  if t==2 then return nil,"OWNED_BY" end
  if t==4 then return nil,"VEHICLE_IN_THE_WAY" end
  return {tile=t,pieces=bits,cost=40}
end
local preview=K.sweep(mixed,quote)
assert(preview.cost==200 and #preview.changes==5 and preview.changes[2].tile==5)
local changed={}
local actual=K.sweep(mixed,quote,true,95,function(e)changed[e.tile]=true end)
assert(actual.cost==80 and #actual.changes==2 and actual.first_unfunded==6)
assert(changed[3] and changed[5] and not changed[6])
local _,reason=K.sweep(mixed,function(t)return nil,t==4 and "TOWN_REFUSES" or "WRONG_SLOPE" end)
assert(reason=="TOWN_REFUSES")
local flat=S.remove(0,2,15,5,true)
assert(flat.removed==2 and flat.road_bits==13 and not flat.foundation)
assert(not S.remove(0,1,2,0,true))
local slope=S.remove(9,2,10,0,false)
assert(slope.removed==10 and slope.road_bits==0 and not slope.foundation)
print("PASS stock half endpoints in either drag direction, plain slope/other-way rules, skip holes, authority priority and affordable prefix")
