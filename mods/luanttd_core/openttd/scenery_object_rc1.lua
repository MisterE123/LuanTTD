-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 (07b339c), OpenTTD contributors:
-- object_cmd.cpp TryBuildLighthouseNearTile through GenerateObjects,
-- tilearea_spiral.cpp, newgrf_object.cpp WasEverAvailable and
-- table/object_land.h. Only the two generated vanilla Temperate objects.
return function(Clear,Calendar)
  local M={}
  local floor,ceil,sqrt,abs=math.floor,math.ceil,math.sqrt,math.abs
  local CLEAR,TREES,WATER,VOID,OBJECT=0,4,6,7,10
  local TRANSMITTER,LIGHTHOUSE=0,1
  local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  local water_codes={sea=1,coast=2,river=3}
  local names={[0]="transmitter","lighthouse"}
  local u32=4294967296
  local function valid(t) return t and t.class~=VOID end
  local function buildable(t) return t and t.class==CLEAR and t.slope==0 and not t.bridge_above end
  local function copy(t)
    local out={}
    for k,v in pairs(t) do out[k]=v end
    return out
  end

  -- Translate the upstream iterator's initialized position and westward
  -- ring jump. Off-map entries are skipped (not clamped/repeated).
  local function spiral(w,h,x,z,radius,ew,eh,dir)
    local at=0
    local function start_side() return (dir%2==0 and ew or eh)+at*2+1 end
    local remaining=dir>=0 and start_side() or 0
    local function advance()
      if dir==-1 then
        x,z,dir=x+1,z-1,0
      else
        x,z=x+dx[dir],z+dz[dir]
        remaining=remaining-1
        if remaining>0 then return end
        dir=dir+1
        if dir==4 then x,z,at,dir=x+1,z-1,at+1,0 end
      end
      remaining=start_side()
    end
    return function()
      while at~=radius or dir==-1 do
        local x0,z0=x,z
        advance()
        if x0>=0 and x0<w and z0>=0 and z0<h then return x0+z0*w end
      end
    end
  end
  local function centered(w,h,i,diameter)
    local half=diameter%2
    return spiral(w,h,i%w+(1-half),floor(i/w),floor(diameter/2),half,half,half==1 and -1 or 0)
  end
  local function perimeter(w,h,i,radius,width,depth)
    return spiral(w,h,i%w+width+1,floor(i/w),radius,width,depth,0)
  end

  function M.generate(board,start,next_random,opts)
    opts=opts or {}
    local w,h=board.width,board.depth
    assert(w>=64 and h>=64 and type(board.tile)=="function","RC1 scenery needs a stock map board")
    local area,maxx,maxz=w*h,w-1,h-1
    local free=board.freeform~=false
    local date,capacity=opts.date or Calendar.BASE_DATE,opts.capacity or 0xFF0000
    assert(date>=0 and date<=Calendar.MAX_DATE and capacity>=0)
    local towns={}
    for i,t in ipairs(board.towns or {}) do
      assert(t.edge_radius_squared and t.edge_radius_squared>0,"RC1 scenery needs actual town edge radii")
      towns[i]=t
    end
    table.sort(towns,function(a,b) return a.id<b.id end)
    local state={start[1],start[2]}
    local stats={border_water=0,random_draws=0,placed={},targets={},attempts={},shortfall={},
      town_lighthouses=0,coast_lighthouses=0,rock_sites=0}
    local object_order,objects,rock_words,rock_order={},{},{},{}
    local function random()
      stats.random_draws=stats.random_draws+1
      return next_random(state)
    end
    local function xy(i) return i%w+1,floor(i/w)+1 end
    local function tile(i)
      if not i or i<0 or i>=area then return end
      local x,z=xy(i)
      return objects[i] or board.tile(x,z)
    end
    local function word(i)
      local t=tile(i)
      if not t then return end
      if t.class==OBJECT then return OBJECT end
      return rock_words[i] or (t.class+16*(water_codes[t.water] or 0)
        +256*(t.ground or 0)+(t.rocky and 4096 or 0))
    end
    local rocks=Clear.rock_walker(w,random,word,function(i,v)
      if not rock_words[i] then rock_order[#rock_order+1]=i end
      rock_words[i]=v
    end)
    local function nearby(i,diameter,id)
      for q in centered(w,h,i,diameter) do
        local t=tile(q)
        if t and t.class==OBJECT and t.object_type==id then return true end
      end
      return false
    end
    local function nearest(x,z)
      local id,dist
      for _,t in ipairs(towns) do
        local d=abs(x-t.x)+abs(z-t.z)
        if not dist or d<dist then id,dist=t.id,d end
      end
      return id -- existing native town association policy for Manhattan ties.
    end
    local function build(i,id,t)
      local x,z=xy(i)
      capacity=capacity-1
      local colour=random()%16
      local tile_random=random()%256
      objects[i]={class=OBJECT,kind=names[id],object_type=id,type=id,town=nearest(x,z),
        colour=colour,random_bits=tile_random,date=date,view=0,height=t.height,
        height_levels=id==TRANSMITTER and 10 or 8,width=1,depth=1}
      object_order[#object_order+1]=i
    end
    local function lighthouse_near(i)
      if capacity==0 then return false end
      local t=tile(i)
      if not valid(t) or t.class~=WATER or t.water~="coast" then return false end
      local _,_,_,rocky=Clear.describe(word(i))
      if rocky or nearby(i,33,LIGHTHOUSE) then return false end
      for q in centered(w,h,i,3) do
        local candidate=tile(q)
        if buildable(candidate) then
          build(q,LIGHTHOUSE,candidate)
          local r=random()
          for k in centered(w,h,i,3) do
            local n=tile(k)
            if n and (n.class==WATER and n.water=="coast" or n.class==TREES and n.water) then
              rocks(k,r%16+5)
              r=floor(r/16) -- ninth coast tile receives zero if all earlier visited
              stats.rock_sites=stats.rock_sites+1
            end
          end
          return true
        end
      end
      return false
    end
    local function town_lighthouse(town)
      local source=tile((town.z-1)*w+town.x-1)
      if not source or source.height>4 then return false end
      local radius=floor(sqrt(town.edge_radius_squared))
      radius=radius+floor(random()*radius/u32)
      local x,z=town.x-1-radius,town.z-1-radius
      if x<0 or z<0 or (free and (x==0 or z==0)) or x>=maxx or z>=maxz then return false end
      local i=x+z*w
      if not valid(tile(i)) then return false end
      for q in perimeter(w,h,i,1,2*radius,2*radius) do
        if lighthouse_near(q) then return true end
      end
      return false
    end
    local function coast_lighthouse()
      local r=random()
      local p=floor(r/65536)%(2*(maxx+maxz))-maxz
      local dir=0
      while p>0 do
        p=p-(dir%2==0 and maxx or maxz)
        dir=dir+1
      end
      local i
      if dir==0 then i=(maxx-1)+(r%maxz)*w
      elseif dir==1 then i=(r%maxx)+w
      elseif dir==2 then i=1+(r%maxz)*w
      else dir=3;i=(r%maxx)+(maxz-1)*w end
      while valid(tile(i)) do
        if lighthouse_near(i) then return true end
        i=i+dx[dir]+dz[dir]*w
      end
      return false
    end

    if free then
      local function count(i)
        local t=tile(i)
        if t and t.class==WATER then stats.border_water=stats.border_water+1 end
      end
      for x=0,maxx-1 do count(x+w);count(x+(maxz-1)*w) end
      for z=1,maxz-2 do count(1+z*w);count(maxx-1+z*w) end
    end
    local function by_size(n) return ceil(n*area/65536) end
    local function by_length(n) return ceil(n*(w+h)/512) end
    local targets=date>=Calendar.BASE_DATE and by_size(15) or 0
    local attempts,placed=0,0
    for _=1,by_size(1000) do
      if placed==targets or capacity==0 then break end
      attempts=attempts+1
      local i=random()%area
      local t=tile(i)
      if buildable(t) and t.height>=4 and not nearby(i,9,TRANSMITTER) then
        build(i,TRANSMITTER,t)
        placed=placed+1
      end
    end
    stats.targets.transmitter,stats.placed.transmitter,stats.attempts.transmitter=targets,placed,attempts
    stats.shortfall.transmitter=targets-placed
    local coast_target=free and floor(by_length(8*stats.border_water)/(2*maxz+2*maxx-6)) or by_length(8)
    -- WasEverAvailable is inclusive in RC1; lighthouses have date zero.
    for _,town in ipairs(towns) do
      if town_lighthouse(town) then stats.town_lighthouses=stats.town_lighthouses+1 end
    end
    for _=1,coast_target do
      if coast_lighthouse() then stats.coast_lighthouses=stats.coast_lighthouses+1 end
    end
    stats.targets.lighthouse,stats.placed.lighthouse,stats.attempts.lighthouse=#towns+coast_target,
      stats.town_lighthouses+stats.coast_lighthouses,#towns+coast_target
    stats.shortfall.lighthouse=stats.targets.lighthouse-stats.placed.lighthouse

    local O={width=w,depth=h,rng_after=state,stats=stats}
    function O.each(visitor)
      for _,i in ipairs(object_order) do
        local x,z=xy(i)
        visitor(x,z,copy(objects[i]))
      end
    end
    function O.each_rock(visitor)
      for _,i in ipairs(rock_order) do
        if not objects[i] then
          local x,z=xy(i)
          local class,_,ground,wet=Clear.describe(rock_words[i])
          visitor(x,z,class==CLEAR and ground or nil,wet or nil)
        end
      end
    end
    return O
  end
  return M
end
