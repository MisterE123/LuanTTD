-- Exercise every tunnel travel direction and independent short/long bores.
local Worm=dofile("mods/bayline/road_bridge_motion.lua")
local Plan=dofile("mods/bayline/openttd/road_tunnel.lua")
local delta={[0]={-1,0},{0,1},{1,0},{0,-1}}
local slopes={[0]=12,6,3,9}
local hide={[0]=12,8,8,12}
local function id(x,z) if x>=0 and x<60 and z>=0 and z<60 then return x+z*60 end end
local function xy(i) return i%60,math.floor(i/60) end
for d=0,3 do
  for n=0,25 do
    local dx,dz=unpack(delta[d]);local tables={}
    local a=id(28,28)
    local goal=id(28+(n+1)*dx,28+(n+1)*dz)
    tables[a]={slope=slopes[d],base=0};tables[goal]={slope=15-slopes[d],base=0}
    for i=1,n do tables[id(28+i*dx,28+i*dz)]={slope=0,base=1} end
    local b={xy=xy,id=id,tile=function(i)return tables[i] end,clear=function() return 0 end}
    local p=assert(Plan.plan(b,a,{owner="A"}))
    assert(p["end"]==goal and p.head.inside_direction==d and #p.middle==n)
    local heads={
      [a]={kind="tunnel",id=a,other=goal,dir=d,plan=p,tunnel=1},
      [goal]={kind="tunnel",id=goal,other=a,dir=(d+2)%4,plan=p,tunnel=1},
    }
    b.tile_at=id;b.tile=function(i)return heads[i] end
    local flip=d==0 or d==3
    local f=flip and 15-hide[d] or hide[d]
    local px,pz=28*16+(d%2==0 and f or 5),28*16+(d%2==1 and f or 5)
    assert(Worm.enters(heads[a],2*d+1,px,pz))
    local steps=0
    local v={x=px,y=pz,state=Worm.WORMHOLE,direction=2*d+1}
    while true do
      local kind,x,z,to,frame=Worm.step(b,heads[a],v)
      assert(x==v.x+dx and z==v.y+dz)
      steps=steps+1
      v.x,v.y=x,z
      if kind=="exit" then
        assert(to==goal and frame==16-hide[(d+2)%4])
        assert(steps==(n+1)*16+frame-hide[d])
        break
      end
      assert(kind=="span" and steps<=443)
    end
  end
end
print("PASS: all tunnel axes and directions; exact entrance/exit frames for 104 bore fixtures")
