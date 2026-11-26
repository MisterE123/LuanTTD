-- Deck collision and safe access points use the same dimensions as the
-- shipped railway meshes. Coordinates here follow the mesh's tile-centred
-- running (u) and cross-track (v) axes, with ground at height zero.
local P={}
local function profile(axis,deck)
  local q={boxes={},deck=deck}
  function q.box(u1,h1,v1,u2,h2,v2)
    if axis==1 then
      u1,v1,u2,v2=v1,-u2,v2,-u1
    end
    q.boxes[#q.boxes+1]={u1+.5,h1-.5,v1+.5,u2+.5,h2-.5,v2+.5}
  end
  function q.point(u,v)
    if axis==1 then u,v=v,-u end
    return {x=u+.5,y=deck-.5,z=v+.5}
  end
  return q
end
function P.stock(gfx)
  local q=profile(gfx%2,.276)
  for _,dir in ipairs({-1,1}) do
    local a,b=dir*.404,dir
    q.box(-1,0,math.min(a,b),1,.276,math.max(a,b))
  end
  if gfx==2 or gfx==3 then q.box(-.54,.276,-.94,.54,.842,-.595)
  elseif gfx>=4 then
    local side=gfx<6 and -.922 or .922
    for _,u in ipairs({-.815,.815}) do q.box(u-.04,.276,side-.04,u+.04,1.47,side+.04) end
  end
  q.landing={q.point(0,.62),q.point(-.64,-.64),q.point(.64,-.64)}
  return q
end
function P.ordinary(axis,gauge)
  local near,far,deck=.35,.922,.280
  if gauge==2 then near,far,deck=.284,.953,.428
  elseif gauge==3 then near,far,deck=.358,.953,.394 end
  local q=profile(axis,deck)
  q.box(-1,0,near,1,deck,far)
  q.landing={q.point(-.70,.63),q.point(.70,.63)}
  return q
end
function P.coal(axis,role)
  -- Coal stage art starts along Z, and turns +90 degrees for axis 0.
  -- Orient the authored outboard deck as (u,v)=(z,x) first.
  -- For axis 0 its model positions are (x,z)=(-u,v).
  local q=profile(axis,.282)
  local function box(u1,v1,u2,v2)
    if axis==0 then
      -- Actual x is -u and z is v; the ranges here are reflection symmetric.
      q.box(u1,0,v1,u2,.282,v2)
    else
      -- Actual x is v and z is u (swap, with no reflection).
      q.box(-u2,0,v1,-u1,.282,v2)
    end
  end
  if role=="unload" then
    box(-1,.358,-.620,.963);box(.620,.358,1,.963)
    box(-.620,.358,.620,.493);box(-.620,.921,.620,.963)
  else box(-1,.358,1,.963) end
  -- Avoid the loading tower and open receiving pit at the centre.
  q.landing={q.point(-.80,.62),q.point(.80,.62)}
  return q
end
function P.crossing(axis)
  -- Wide contiguous walking strip over the road plate. Gates and posts
  -- are visuals; their movement must never trap a pedestrian.
  local q=profile(axis,.108)
  local function height(v)
    local t=math.max(0,math.min(1,(.94-math.abs(v))/.57))
    return .002+(.108-.002)*t*t*(3-2*t)
  end
  q.box(-.3125,0,-.37,.3125,.108,.37)
  for _,sign in ipairs({-1,1}) do
    for j=0,3 do
      local a,b=(.37+j*.14)*sign,(.37+(j+1)*.14)*sign
      q.box(-.3125,0,math.min(a,b),.3125,height(b),math.max(a,b))
    end
  end
  return q.boxes
end
function P.ballast(bits)
  local q=profile(0,.036)
  if bits%2==1 then q.box(-1,0,-.25,1,.036,.25) end
  if math.floor(bits/2)%2==1 then q.box(-.25,0,-1,.25,.036,1) end
  if #q.boxes>0 then return q.boxes end
end
return P
