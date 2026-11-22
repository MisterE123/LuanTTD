-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. OpenTTD 14.1 table/airport_movement.h,
-- airport.h/airport.cpp and aircraft_cmd.cpp fixed-wing handlers.
-- Country Airfield AT_SMALL; movement and permission callbacks are external.
local A={W=4,H=3,TILE=16,hangar={x=3,z=0,dir=3,id=0},entries={[0]=16,15,18,17}}
local S={ALL=0,HANGAR=1,TERM1=2,TERM2=3,TAKEOFF=10,STARTTAKEOFF=11,ENDTAKEOFF=12,
  HELITAKEOFF=13,FLYING=14,LANDING=15,ENDLANDING=16,HELILANDING=17,HELIENDLANDING=18,TERMGROUP=255}
local B={TERM1=1,TERM2=2,BUSY=256,NOTHING=2^30}
local F={NOSPDCLAMP=1,TAKEOFF=2,SLOWTURN=4,LAND=8,EXACTPOS=16,BRAKE=32,HELI_RAISE=64,HELI_LOWER=128,HOLD=256}
A.state,A.block,A.flag=S,B,F
A.points={
  [0]={53,3,16,3},{53,27,0,0},{32,23,16,7},{10,23,16,7},{43,37,0,0},{24,37,0,0},
  {53,37,0,0},{61,40,16,1},{3,40,1,0},{-79,40,3,0},{177,40,5,0},{56,40,9,0},
  {3,40,33,0},{7,40,0,0},{53,40,0,0},{1,193,5,0},{1,1,5,0},{257,1,5,0},
  {273,47,5,0},{44,37,64,0},{44,40,5,0},{44,40,128,0},
}
A.layout={
  [0]={{S.HANGAR,B.NOTHING,1}},
  {{S.TERMGROUP,B.BUSY,0},{S.HANGAR,0,0},{S.TERM1,B.TERM1,2},{S.TERM2,0,4},{S.HELITAKEOFF,0,19},{S.ALL,0,6}},
  {{S.TERM1,B.TERM1,1}},
  {{S.TERM2,B.TERM2,5}},
  {{S.TERMGROUP,B.BUSY,0},{S.TERM2,0,5},{S.HANGAR,0,1},{S.TAKEOFF,0,6},{S.HELITAKEOFF,0,1}},
  {{S.TERMGROUP,B.BUSY,0},{S.TERM2,B.TERM2,3},{S.ALL,0,4}},
  {{S.ALL,B.BUSY,7}},
  {{S.TAKEOFF,B.BUSY,8}},
  {{S.STARTTAKEOFF,B.NOTHING,9}},
  {{S.ENDTAKEOFF,B.NOTHING,0}},
  {{S.FLYING,B.NOTHING,15},{S.LANDING,0,11},{S.HELILANDING,0,20}},
  {{S.LANDING,B.BUSY,12}},
  {{S.ALL,B.BUSY,13}},
  {{S.ENDLANDING,B.BUSY,14},{S.TERM2,0,5},{S.ALL,0,14}},
  {{S.ALL,B.BUSY,1}},
  {{S.ALL,B.NOTHING,16}},
  {{S.ALL,B.NOTHING,17}},
  {{S.ALL,B.NOTHING,18}},
  {{S.ALL,B.NOTHING,10}},
  {{S.HELITAKEOFF,B.NOTHING,0}},
  {{S.HELILANDING,B.BUSY,21}},
  {{S.HELIENDLANDING,B.BUSY,1}},
}

local floor,abs=math.floor,math.abs
local function has(flags,b) return floor(flags/b)%2==1 end
local function intersection(a,b)
  local r=0
  for _,bit in ipairs({B.TERM1,B.TERM2,B.BUSY,B.NOTHING}) do
    if has(a,bit) and has(b,bit) then r=r+bit end
  end
  return r
end
local function union(a,b) return a+b-intersection(a,b) end
local function remove(a,b) return a-intersection(a,b) end
A.has=has

-- World origin and dimensions are integer stock pixels/tiles. Uppercase
-- board headings use stock N=0, NE=1, E=2 ... NW=7. Width/height are
-- already rotated airport dims, as in RotateAirportMovingData.
function A.point(i,rotation,width,height)
  local p=A.points[i]
  if not p then return nil end
  local x,z,d=p[1],p[2],p[4]
  rotation=rotation or 0
  width=width or (rotation%4==0 and 4 or 3)
  height=height or (rotation%4==0 and 3 or 4)
  if rotation==2 then x,z=z,height*16-x-1
  elseif rotation==4 then x,z=width*16-x-1,height*16-z-1
  elseif rotation==6 then x,z=width*16-z-1,x
  elseif rotation~=0 then return nil end
  return x,z,p[3],(d+rotation)%8
end
function A.entry(x,z,origin_x,origin_z,rotation)
  x,z=x-origin_x,z-origin_z
  local side=abs(z)<abs(x) and (x<0 and 0 or 2) or (z<0 and 3 or 1)
  return A.entries[(side-floor((rotation or 0)/2))%4]
end

-- open flags are exact low source masks plus closed boolean (64th bit).
function A.has_block(a,v,at,row)
  local choices=A.layout[at]
  local cur=choices[row]
  local next=A.layout[cur[3]][1][2]
  if choices[1][2]~=next then
    local needed=next
    if cur~=A.layout[v.pos][1] and cur[2]~=B.NOTHING then needed=union(needed,cur[2]) end
    if intersection(a.flags,needed)~=0 then v.speed,v.subspeed=0,0;return true end
  end
  return false
end
function A.set_blocks(a,v,at,row)
  local choices=A.layout[at]
  local cur=choices[row]
  local next=A.layout[cur[3]][1][2]
  if intersection(choices[1][2],next)~=next then
    local needed=next
    local check=row
    if cur==A.layout[v.pos][1] then check=check+1 end
    for j=check,#choices do
      if choices[j][1]==cur[1] and choices[j][2]~=0 then needed=union(needed,choices[j][2]);break end
    end
    if cur[2]==next then needed=remove(needed,next) end
    if intersection(a.flags,needed)~=0 then v.speed,v.subspeed=0,0;return false end
    if next~=B.NOTHING then a.flags=union(a.flags,needed) end
  end
  return true
end
function A.clear_block(a,v)
  local from,to=A.layout[v.previous_pos][1][2],A.layout[v.pos][1][2]
  if from~=to then a.flags=remove(a.flags,from) end
end

function A.free_terminal(a,v)
  for i,bit in ipairs({B.TERM1,B.TERM2}) do
    if not has(a.flags,bit) then
      a.flags=union(a.flags,bit)
      v.state=i==1 and S.TERM1 or S.TERM2
      return true
    end
  end
  return false
end
local function ordinary(a,v)
  local choices=A.layout[v.pos]
  v.previous_pos=v.pos
  for i,c in ipairs(choices) do
    if #choices==1 or c[1]==v.state or c[1]==S.ALL then
      if A.set_blocks(a,v,v.pos,i) then v.pos=c[3];return "next" end
      return "blocked"
    end
  end
  return nil,"no_matching_transition"
end

local function set_airport(a,v)
  v.target=a.id
  v.pos=A.entry(v.x,v.z,a.x,a.z,a.rotation)
  v.previous_pos=v.pos
end
function A.inbound(a,v)
  v.state=S.FLYING
  set_airport(a,v)
  return v.pos
end
function A.new(a,opts)
  opts=opts or {}
  local x,z,_,d=A.point(0,a.rotation,a.width,a.height)
  return {pos=0,previous_pos=0,state=S.HANGAR,x=a.x+x,z=a.z+z,y=(a.ground or 0)+1,direction=d,
    owner=opts.owner,target=a.id,hidden=true,order=opts.order,speed=0,subspeed=0,progress=0,
    acceleration=opts.acceleration or 24,max_speed=opts.max_speed or 320}
end

-- Called only when the physical controller reaches the requested point.
-- Host owns cargo, servicing, crash-policy and cross-airport destination
-- selection. AIRPORT_CLOSED only affects arriving aircraft.
function A.arrive(a,v,h)
  h=h or {}
  if v.helicopter then return nil,"fixed_wing_only" end
  if v.loading then return "loading" end
  local row=A.layout[v.pos]
  if not row or not A.layout[v.previous_pos] then return nil,"invalid_position" end
  A.clear_block(a,v)
  local c=row[1]
  local from,old=v.pos,v.state
  if c[1]~=v.state then return ordinary(a,v) end
  local event
  local order=v.order or {}
  if old==S.HANGAR then
    if v.previous_pos~=v.pos then
      v.hidden,v.speed,v.subspeed,v.progress=true,0,0,0
      event="hangar"
    elseif v.wait_unbunch or (order.kind~="station" and order.kind~="depot") then
      event="wait_hangar"
    elseif order.kind=="depot" and order.id==a.id then
      if v.stopped then v.order=nil end
      event="wait_hangar"
    elseif A.has_block(a,v,v.pos,1) then
      event="blocked"
    else
      if order.id~=a.id or A.free_terminal(a,v) then
        if order.id~=a.id then v.state=S.TAKEOFF end
        v.direction=(A.hangar.dir+(a.rotation or 0))%8
        v.speed,v.subspeed,v.progress,v.hidden=0,0,0,nil
        event=ordinary(a,v)
      else
        event="wait_terminal"
      end
    end
  elseif old==S.TERM1 or old==S.TERM2 then
    if v.previous_pos~=v.pos then
      if order.kind~="depot" then v.loading=true;v.last_station=a.id end
      event="terminal"
    elseif order.kind==nil or order.kind=="nothing" or order.kind=="conditional" then
      event="wait_terminal"
    elseif A.has_block(a,v,v.pos,1) then
      event="blocked"
    else
      if order.kind=="depot" and order.id==a.id or (order.kind~="station" and order.kind~="depot") then
        v.state=S.HANGAR
        if order.kind~="depot" then v.order=nil end
      else
        v.state=S.TAKEOFF
      end
      event=ordinary(a,v)
    end
  elseif old==S.TAKEOFF then v.state=S.STARTTAKEOFF;event="takeoff"
  elseif old==S.STARTTAKEOFF then v.state=S.ENDTAKEOFF;event="liftoff"
  elseif old==S.ENDTAKEOFF then
    v.state=S.FLYING
    local next=h.next_airport and h.next_airport(v,a) or (h.airports and h.airports[order.id])
    if next then set_airport(next,v);return "departed",next end
    return "departed"
  elseif old==S.FLYING then
    local allowed=not a.closed and (a.owner==nil or a.owner==v.owner) and
      (not h.allowed or h.allowed(v,a))
    if allowed then
      for i=2,#row do
        local choice=row[i]
        if choice[1]==S.LANDING then
          local speed,sub=v.speed,v.subspeed
          if not A.has_block(a,v,from,i) then
            v.state,v.pos=S.LANDING,choice[3]
            a.flags=union(a.flags,A.layout[v.pos][1][2])
            v.previous_pos=from
            return "approach"
          end
          v.speed,v.subspeed=speed,sub
        end
      end
    end
    v.pos=c[3]
    return "hold"
  elseif old==S.LANDING then v.state=S.ENDLANDING;event="touchdown"
  elseif old==S.ENDLANDING then
    if A.has_block(a,v,v.pos,1) then event="blocked"
    elseif order.kind=="station" and A.free_terminal(a,v) then event="assigned_terminal"
    else v.state=S.HANGAR;event="to_hangar" end
  else
    return nil,"unsupported_state"
  end
  if v.state~=S.FLYING then v.previous_pos=from end
  return event
end
return A
