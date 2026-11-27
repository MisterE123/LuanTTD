local path="mods/luanttd_core/openttd/"
local Rail=dofile(path.."rail_track.lua")
local W=dofile(path.."ship_follow.lua")(Rail)
local width,height=1024,128
local corps={}
for x=2,1007 do corps[x+47*width]={kind="canal",slope=0} end
local R1=arg and arg[1] and dofile(arg[1])
local R2=dofile(path.."ship_regions.lua")
local size={width=width,height=height}
local function at(x,z)
  if x>=0 and x<width and z>=0 and z<height then return x+z*width end
end
local function xy(u) return u%width,math.floor(u/width) end
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local function board(read)
  return {xy=xy,tile_at=at,adjacent=function(id,k)
    local x,z=xy(id);return at(x+dx[k],z+dz[k])
  end,tile=read}
end
local function run(R)
  local n=0
  local b=board(function(id)n=n+1;return corps[id] end)
  local result,value,out
  collectgarbage("collect")
  local start=os.clock()
  for k=1,16 do
    result=R(Rail,W,b,size)
    local route,stat=result.find(at(2,47),{at(1007,47)},8)
    assert(#route==8 and route[8].x==7)
    value,out=route,stat
  end
  return 1000*(os.clock()-start),n,value,out
end
local function same(a,b)
 if a==b then return true end
 if type(a)~="table" or type(b)~="table" then return false end
 for k,v in pairs(a) do if not same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
-- Warming only the actual route must not hide a later navigable
-- branch across a previously closed sector edge.
local B=board(function(id) return corps[id] end)
local start,target,new=at(2,47),at(1007,47),at(20,48)
local network=R2(Rail,W,B,size)
assert(#network.find(start,{target},8)==8 and #network.find(start,{new},8)==0)
corps[new]={kind="canal",slope=0}
network.invalidate(new)
assert(#network.find(start,{new},8)==3)
corps[new]=nil
network.invalidate(new)
assert(#network.find(start,{new},8)==0)
print("PASS an initially dry neighbor becomes navigable after real boundary invalidation")
if not R1 then return end
for i=1,4 do
 local a,b,c,d,p,q,r,t
 if i%2==1 then a,c,p,r=run(R1);b,d,q,t=run(R2)
 else b,d,q,t=run(R2);a,c,p,r=run(R1) end
 assert(same(p,q) and same(r,t))
 print(("CANAL PATCH cold batch %d cpu=%.3f/%.3f ms reads=%d/%d"):format(i,a,b,c,d))
end
