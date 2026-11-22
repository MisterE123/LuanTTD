-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, pinned 14.1: src/object_cmd.cpp GenerateObjects,
-- TryBuildTransmitter, TryBuildLightHouse, BuildObject; src/map.cpp circular
-- search; src/map_func.h map-size scaling; src/object_map.h MakeObject;
-- src/table/object_land.h original specs. See COPYING.OpenTTD.md.
-- Temperate vanilla world creation only. Does not modify the caller's map.
local O={}
local floor,ceil,abs=math.floor,math.ceil,math.abs
local CLEAR,WATER,VOID,OBJECT=0,6,7,10
local TRANSMITTER,LIGHTHOUSE=0,1
local specs={
  {id=TRANSMITTER,kind="transmitter",generate_amount=15,height_levels=10,width=1,depth=1},
  {id=LIGHTHOUSE,kind="lighthouse",generate_amount=8,height_levels=8,width=1,depth=1,scale_by_water=true},
}
O.transmitter,O.lighthouse,O.tile_class=TRANSMITTER,LIGHTHOUSE,OBJECT
local sizes={}
for p=6,12 do sizes[2^p]=true end
local function int(v,a,b)
  return type(v)=="number" and v>=a and v<=b and v==floor(v)
end
local function bits(v,start,count) return floor(v/2^start)%2^count end
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}

-- CircularTileSearch(size=9) probes center, then each radius-1..4 square.
-- Keep its initial TileAddByDir(DIR_N) linear wrap before the clipped
-- four-direction rings, including the unusual first-column edge case.
local function neighbor_transmitter(i,w,h,has)
  if has(i) then return true end
  local n=(i-w-1)%(w*h)
  local x,z=n%w+2,floor(n/w)
  for ring=0,3 do
    for d=0,3 do
      for _=1,2+ring*2 do
        if x>=0 and x<w and z>=0 and z<h and has(z*w+x) then return true end
        x,z=x+dx[d],z+dz[d]
      end
    end
    x,z=x+1,z-1 -- DIR_W
  end
  return false
end

local function nearest(towns,x,z)
  local id,dist
  for _,t in ipairs(towns) do
    local d=abs(x-t.x)+abs(z-t.z)
    if not dist or d<dist or d==dist and t.id<id then id,dist=t.id,d end
  end
  return id
end
local function copy(t)
  local out={}
  for k,v in pairs(t) do out[k]=v end
  return out
end

function O.generate(board,start,next_random,opts)
  assert(type(board)=="table" and sizes[board.width] and sizes[board.depth]
    and type(board.tile)=="function","Expected stock map dimensions (64–4096) and typed tile lookup")
  assert(type(start)=="table" and int(start[1],0,4294967295)
    and int(start[2],0,4294967295) and type(next_random)=="function","Expected explicit stock RNG state and advance")
  opts=opts or {}
  assert(opts.landscape==nil or opts.landscape=="temperate","Only vanilla temperate objects at world creation")
  assert(not opts.newgrf and not opts.editor,"Custom objects and editor placement are not supported")
  assert(board.freeform==nil or type(board.freeform)=="boolean","Invalid freeform edge flag")
  local w,h=board.width,board.depth
  local area,maxx,maxz=w*h,w-1,h-1
  local free=board.freeform~=false
  local date=opts.date or 1
  local capacity=opts.capacity or 0xFF0000
  assert(int(date,0,4294967295) and int(capacity,0,0xFF0000),"Invalid calendar date or free object slots")
  local towns=board.towns or {}
  assert(type(towns)=="table","Expected list of town records")
  if date>0 and capacity>0 then
    assert(#towns>0,"Stock scenery object generation requires an existing town")
  end
  local ids={}
  for _,t in ipairs(towns) do
    assert(int(t.id,0,65534) and int(t.x,1,w) and int(t.z,1,h) and not ids[t.id],"Invalid town record")
    ids[t.id]=true
  end
  local state={start[1],start[2]}
  local S={border_water=0,random_draws=0,attempts={},targets={},placed={},shortfall={}}
  local entries,placed={},{}
  local function random()
    S.random_draws=S.random_draws+1
    return next_random(state)
  end
  local function xy(i) return i%w+1,floor(i/w)+1 end
  local function inside(i) return i>=0 and i<area end
  local function tile(i)
    if not inside(i) then return nil end
    if placed[i] then return placed[i] end
    local x,z=xy(i)
    return board.tile(x,z)
  end
  local function is_water(i)
    local t=tile(i)
    return t and t.class==WATER
  end
  local function has_transmitter(i)
    local t=tile(i)
    return t and t.class==OBJECT and t.object_type==TRANSMITTER
  end
  local function valid(i)
    local t=tile(i)
    return t and int(t.class,0,10) and t.class~=VOID
  end
  local function buildable(t,lo,hi)
    return t and t.class==CLEAR and t.slope==0 and not t.bridge_above and int(t.height,lo,hi)
  end
  local function place(i,spec,t)
    local x,z=xy(i)
    local town=assert(nearest(towns,x,z),"A stock object requires a town")
    local colour=random()%16  -- BuildObject's unowned color, with original 1CC spec.
    local tile_random=random()%256  -- MakeObject tile's byte; even for one tile.
    local entry={class=OBJECT,kind=spec.kind,object_type=spec.id,type=spec.id,town=town,
      colour=colour,random_bits=tile_random,date=date,view=0,height=t.height,
      height_levels=spec.height_levels,width=spec.width,depth=spec.depth}
    placed[i]=entry
    entries[#entries+1]=i
  end
  local function transmitter(spec)
    local i=random()%area
    local t=tile(i)
    if not buildable(t,4,255) or neighbor_transmitter(i,w,h,has_transmitter) then return false end
    place(i,spec,t)
    return true
  end
  local function lighthouse(spec)
    local r=random()
    local p=bits(r,16,16)%(2*(maxx+maxz))-maxz
    local dir=0
    while p>0 do
      p=p-(dir%2==0 and maxx or maxz)
      dir=dir+1
    end
    local i
    if dir==0 then i=(maxx-1)+(r%maxz)*w
    elseif dir==1 then i=(r%maxx)+w
    elseif dir==2 then i=1+(r%maxz)*w
    else i=(r%maxx)+(maxz-1)*w end
    if not is_water(i) then return false end
    for _=1,19 do
      local t=tile(i)
      if buildable(t,0,2) then place(i,spec,t);return true end
      i=i+dx[dir]+dz[dir]*w
      if not valid(i) then return false end
    end
    return false
  end
  local function count_water(i) if is_water(i) then S.border_water=S.border_water+1 end end
  if free then
    -- Deliberate corner inclusion duplicates the upstream loops exactly,
    -- excluding x=maxx, y=maxz and the second horizontal row endpoint.
    for x=0,maxx-1 do
      count_water(x+w)
      count_water(x+(maxz-1)*w)
    end
    for z=1,maxz-2 do
      count_water(1+z*w)
      count_water(maxx-1+z*w)
    end
  end
  local function scale(n) return ceil(n*area/65536) end
  local function scale1d(n) return ceil(n*(w+h)/512) end
  local remaining=capacity
  local tries=scale(1000)
  for _,spec in ipairs(specs) do
    local amount=0
    -- Both original specs' introduction_date is 0 and generation uses
    -- WasEverAvailable(): a strict date > introduction check, no expiry.
    if date>0 then
      amount=spec.generate_amount
      if spec.scale_by_water then
        if free then amount=floor(scale1d(amount*S.border_water)/(2*maxz+2*maxx-6))
        else amount=scale1d(amount) end
      else amount=scale(amount) end
    end
    local attempt=spec.id==TRANSMITTER and transmitter or lighthouse
    local attempted,built=0,0
    while built<amount and remaining>0 and attempted<tries do
      attempted=attempted+1
      if attempt(spec) then
        built,remaining=built+1,remaining-1
      end
    end
    local k=spec.kind
    S.targets[k],S.placed[k],S.attempts[k],S.shortfall[k]=amount,built,attempted,amount-built
  end
  local V={width=w,depth=h,rng_after=state,stats=S}
  function V.object(x,z)
    if int(x,1,w) and int(z,1,h) then
      local v=placed[(z-1)*w+x-1]
      if v then return copy(v) end
    end
  end
  function V.each(visitor)
    for _,i in ipairs(entries) do
      local x,z=xy(i)
      visitor(x,z,copy(placed[i]))
    end
  end
  return V
end
return O
