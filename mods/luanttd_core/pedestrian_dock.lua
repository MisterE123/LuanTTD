-- Presentation collision for the original ship_facilities.blend models.
-- Canonical coordinates: +along goes from land to water; cross=.5 is centre.
-- Luanti mirrors OBJ X. The model's baked rotations are around (.5,.5).
local D={}
local function local_coords(dir,x,z)
  if dir==0 then return x,z
  elseif dir==1 then return z,x
  elseif dir==2 then return 1-x,1-z
  else return 1-z,1-x end
end
local function world_coords(dir,a,c)
  return local_coords(dir,a,c)
end

local function ramp(a)
  return .511-(a+.5)*.416
end

local function continuous(part,a,c)
  if part then
    if a>=-.5 and a<=1.413 and c>=.025 and c<=.975 then return -.320 end
  elseif a>=-.5 and a<=1.5 and c>=-.5 and c<=1.5 then
    local ground=.5-(a+.5)*.5
    if c>=.145 and c<=.855 then return math.max(ground,ramp(a)) end
    return ground
  end
end

local function build(part,dir)
  local floors,boxes={},{}
  local function add(a,c,b,d,lo,hi,floor)
    local x,z=world_coords(dir,a,c)
    local u,v=world_coords(dir,b,d)
    local box={math.min(x,u),lo,math.min(z,v),math.max(x,u),hi,math.max(z,v)}
    boxes[#boxes+1]=box
    if floor then floors[#floors+1]=box end
  end
  local function rail(a,b,c,lo,hi)
    add(a,c-.013,b,c+.013,lo,hi)
  end
  if part then
    add(-.5,.025,1.413,.975,-.376,-.320,true)
    for _,c in ipairs({.153,.847}) do rail(-.5,-.278,c,-.330,-.055) end
    -- Shelter's rear wall and bench. The central walk and boarding end
    -- are open; the bollards and piles do not form invisible side walls.
    add(-.05,.10,.315,.248,-.32,-.20)
    add(-.127,.063,.382,.105,-.131,.091)
  else
    for i=0,9 do
      local a,b=-.5+i*.2,-.5+(i+1)*.2
      local ground=.5-(b+.5)*.5
      local deck=ramp(b)
      add(a,-.5,b,1.5,ground-.11,ground,true)
      add(a,.145,b,.855,deck-.09,deck,true)
      for _,c in ipairs({.153,.847}) do
        rail(math.max(a,-.416),b,c,deck-.01,math.max(deck+.26,ramp(a)+.21))
      end
    end
  end
  return floors,boxes
end

local variants={[false]={},[true]={}}
for _,part in ipairs({false,true}) do
  for d=0,3 do
    local f,b=build(part,d)
    variants[part][d]={floors=f,boxes=b}
  end
end

function D.boxes(part,dir)
  return variants[part==true][dir].boxes
end
function D.surface(part,dir,x,z,ray)
  if ray then
    local a,c=local_coords(dir,x,z)
    return continuous(part,a,c)
  end
  local h
  for _,b in ipairs(variants[part==true][dir].floors) do
    if x>=b[1] and x<=b[4] and z>=b[3] and z<=b[6] then h=math.max(h or b[5],b[5]) end
  end
  return h
end
return D
