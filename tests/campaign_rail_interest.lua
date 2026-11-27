local root="mods/luanttd_core/"
local baseline=arg and arg[1] and (arg[1]:gsub("/$","").."/")
local Sim=dofile(root.."sim.lua")
Sim.W,Sim.H=4096,4096
local s={tiles={},sites={},fleet={},day=7,speed=1}
local runs={}
for i=1,384 do
  local x,z=(i-1)%24*96+30,math.floor((i-1)/24)*98+45
  local parts={}
  for j=1,24 do
    local px,pz=x+j*.5,z
    local p=j~=7 and {x=px*2,y=1,z=pz*2} or nil
    parts[j]={index=j,pos=p}
  end
  runs[i]={id=i,fleet_id=i,owner="Rail QA",stock_engine=8,stock_wagon=31,consist={parts=parts}}
end
local rail={run={current=function() return {runs=runs} end},poses=function(r) return r.consist.parts end}
local function build(path)
  local project=dofile(path.."campaign_actor_projection.lua")
  local R={world=s,rail=rail}
  function R.actors(x,z,w,h,fraction,frame) return project(Sim,R,x,z,w,h,fraction,frame) end
  return dofile(path.."campaign_authority_endpoint.lua")(Sim,R),R.actors
end
local new,new_one=build(root)
local old,old_one
if baseline then old,old_one=build(baseline) end
local function same(a,b)
  if a==b then return true end
  if type(a)~="table" or type(b)~="table" then return false end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local nine={}
for z=1,65,32 do for x=1,65,32 do nine[#nine+1]={x=x,z=z,w=32,h=32} end end
local dense={{x=37,z=30,w=6,h=18},{x=20,z=36,w=12,h=15},{x=134,z=38,w=24,h=32},{x=245,z=32,w=25,h=22},
  {x=16,z=128,w=32,h=32},{x=124,z=132,w=24,h=32},{x=243,z=130,w=24,h=32},
  {x=2100,z=1120,w=32,h=32},{x=2130,z=1122,w=32,h=32}}
local single={{x=37,z=30,w=6,h=18}}
local far={{x=4020,z=4040,w=32,h=32},{x=3900,z=3930,w=32,h=32}}
local views={nine,dense,single,far}
for _,batch in ipairs(views) do
  local live=new.actor_frames(batch,.5,true)
  assert(live.ok)
  if old then assert(same(old.actor_frames(batch,.5,true),live)) end
  for _,packet in ipairs(live.value) do
    local seen={}
    for _,r in ipairs(packet.actors) do
      assert(not seen[r.id] and r.complete_parts and #r.parts==24)
      seen[r.id]=true
    end
  end
end
local row=new.actor_frames(single,.5,true).value[1].actors[1]
assert(row and row.id==1 and #row.parts==24 and row.complete_parts and row.parts[1].pos.x<74)
local clipped=new_one(37,30,6,18,.5)
assert(clipped[1] and #clipped[1].parts<24 and not clipped[1].complete_parts)
if old then assert(same(old_one(37,30,6,18,.5),clipped)) end
assert(new.actor_frames(single,.5,true).value[1].actors[1].parts[24].index==24)
assert(#new.actor_frames(far,.5,true).value[1].actors==0)
print("PASS rail buckets preserve clipped and whole trains, including a visible tail, boundary overlap and culling")
if not old then return end
local function measure(A,batch)
  collectgarbage("collect")
  local t=os.clock()
  for i=1,96 do assert(A.actor_frames(batch,.5,true).ok) end
  return 1000*(os.clock()-t)
end
for i=1,8 do
  local j=math.floor((i-1)/2)+1
  local a,b
  if i%2==1 then a,b=measure(old,views[j]),measure(new,views[j])
  else b,a=measure(new,views[j]),measure(old,views[j]) end
  print(("RAIL INTEREST batch=%d views=%d CPU=%.3f/%.3f ms"):format(i,#views[j],a,b))
end
