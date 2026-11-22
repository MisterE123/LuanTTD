local root="mods/luanttd_core/openttd/"
local Motion=dofile(root.."road_motion.lua")(dofile(root.."road_motion_data.lua"))
local M=dofile(root.."tram_motion.lua")(dofile(root.."tram_motion_data.lua"),Motion)
local F=dofile(root.."yapf_road_follow.lua")
local Travel={[0]={-1,0}, {0,1},{1,0},{0,-1}}
local function sim(dir,side,small)
  local state=M.reverse_trackdir[dir]
  local begin=small and M.SHORT_TURN or 0
  local _,x,y=M.sample(state,side,begin)
  local v={x=x+176,y=y+176,direction=2*dir+1,state=state,frame=begin}
  local n,m,hit=0,0,false
  for _=1,60 do
    local k,a,b,d,f=M.step(v,side)
    if k=="move" or k=="rotate" then
      if k=="rotate" then assert(a==v.x and b==v.y and f==v.frame);m=m+1
      else
        assert(math.abs(a-v.x)+math.abs(b-v.y)==1)
        n=n+1
      end
      v.x,v.y,v.direction,v.frame=a,b,d,f
    elseif k=="turned" then
      assert(not hit and a==F.reverse_direction(dir) and v.frame==19)
      hit=true
      local returned,frame=M.turned({kind="road"},small and 10 or 2^(dir%2),a,F.direction_trackdir(a))
      local event
      event,v.x,v.y,v.direction,v.frame=M.enter(v,11,11,returned,side,frame)
      assert(event=="enter" and frame==(small and 1 or 21))
      v.state=returned
    else
      assert(k=="next_tile" and a==F.reverse_direction(dir))
      local dx,dy=unpack(Travel[a])
      local _,rx,ry=M.sample(F.direction_trackdir(a),side,0)
      assert(math.abs(rx+dx*16-v.x%16)+math.abs(ry+dy*16-v.y%16)==1)
      assert(hit and (n==33 or n==17) and m>=3)
      return n,m
    end
  end
  error("tram never found outbound tile")
end
for d=0,3 do for side=0,1 do
  local long=sim(d,side,false)
  local short=sim(d,side,true)
  assert(long-short==16)
end end
assert(not M.sample(32,1,0) and not M.sample(79,1,99))
for _,td in ipairs({0,1,8,9}) do
  for i=0,16 do
    local a,b,c=M.sample(64+td,1,i)
    local x,y,z=M.sample(td,1,i)
    assert(a==x and b==y and c==z)
  end
end
print("PASS: both road sides make complete stock long and short reversals in every direction, with drive-through samples and no bay rows")
