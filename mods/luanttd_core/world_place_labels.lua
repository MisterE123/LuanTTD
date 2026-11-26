-- Engine-independent anchors and bounded place-name observations.
local L={place_radius=384,stop_radius=52,max_places=64}
local roof={town=5.0,coal_mine=4.5,mine=4.5,farm=4.4,factory=4.4,
  steel_mill=4.5,oil_rig=10.5,oil_refinery=4.3,forest=4.5,
  sawmill=3.6,oil_well=4.3,iron_ore_mine=4.5,bank=4.8}
function L.surface(t,terrain_top)
  return math.max(t.h or 0,terrain_top or 0)
end
function L.site_height(site,t,terrain_top)
  local key=t.stock_industry and t.stock_industry.kind or site.kind
  return L.surface(t,terrain_top)+(roof[key] or 4.0)
end
function L.stop_height(t,terrain_top)
  return L.surface(t,terrain_top)+2.25
end
function L.within(x,z,u,v,range)
  return (x-u)^2+(z-v)^2<=range^2
end
local function positive(n)
  n=tonumber(n)
  return n and n>0 and n<math.huge and n or nil
end
-- The fog and the map stream may lower the effective drawing distance.
-- Remote client graphics settings are not exposed to server Lua.
function L.radius(view,fog,send)
  local d=positive(view) or 200
  d=math.min(d,positive(fog) or d,positive(send) or d)
  return math.max(1,math.min(L.place_radius,math.floor(d+math.max(4,math.min(16,d*.10))+.5)))
end
function L.viewer_range(engine,p)
  local settings=engine.settings
  local distance=settings and settings:get("viewing_range")
  local limit=settings and positive(settings:get("max_block_send_distance"))
  local sky=p.get_sky and p:get_sky(true)
  local fog=type(sky)=="table" and sky.fog and sky.fog.fog_distance
  return L.radius(distance,fog,limit and limit*16)
end
function L.visible(x,y,z,from,reach)
  return (x-from.x)^2+(y-from.y)^2+(z-from.z)^2<=reach^2
end
-- World-space label buckets are only an observation cache. The registry
-- appends new sites; closing a site leaves its slot in place. Name, population,
-- closure, and terrain height are always read live, never cached.
local width=128
function L.site_index(Sim,board)
  local registry,last,buckets
  local count=0
  local function add(id,site)
    if not site or not site.tile then return end
    local tx,tz=Sim.xy(site.tile)
    local x,z=tx*2+.5,tz*2+.5
    local gx,gz=math.floor(x/width),math.floor(z/width)
    local col=buckets[gx]
    if not col then col={};buckets[gx]=col end
    local bucket=col[gz]
    if not bucket then bucket={};col[gz]=bucket end
    bucket[#bucket+1]={id=id,x=x,z=z,tx=tx,tz=tz}
  end
  return function(x,z,range,visit)
    local sites=board.sites
    if not sites then return end
    local n=#sites
    if sites~=registry or n<count or (count>0 and sites[count]~=last) then
      registry,buckets=sites,{}
      for id,site in pairs(sites) do add(id,site) end
    elseif n>count then
      for id=count+1,n do add(id,sites[id]) end
    end
    count,last=n,sites[n]
    for gx=math.floor((x-range)/width),math.floor((x+range)/width) do
      local col=buckets[gx]
      if col then
        for gz=math.floor((z-range)/width),math.floor((z+range)/width) do
          local bucket=col[gz]
          if bucket then
            for _,entry in ipairs(bucket) do
              local site=sites[entry.id]
              if site then visit(entry.id,site,entry.tx,entry.tz,entry.x,entry.z) end
            end
          end
        end
      end
    end
  end
end
function L.describe(Sim,board,x,z,terrain_top,range,index)
  range=range or L.place_radius
  local distance2=range^2
  local result={}
  local function visit(id,site,tx,tz,u,v)
    local tile=site.tile
    if not site.closed and tile and type(site.name)=="string" then
      if not tx then tx,tz=Sim.xy(tile);u,v=tx*2+.5,tz*2+.5 end
      local dist=(u-x)^2+(v-z)^2
      local t=dist<=distance2 and board.tiles[tile]
      if t and not t.stock_void then
        result[#result+1]={id=site.id or id,tile=tile,kind=site.kind,name=site.name,
          population=site.population,y=L.site_height(site,t,terrain_top and terrain_top(tile,tx,tz)),dist=dist}
      end
    end
  end
  if index then index(x,z,range,visit)
  else for id,site in pairs(board.sites or {}) do visit(id,site) end end
  table.sort(result,function(a,b) return a.dist==b.dist and a.id<b.id or a.dist<b.dist end)
  for i=#result,L.max_places+1,-1 do result[i]=nil end
  for _,row in ipairs(result) do row.dist=nil end
  return result
end
return L
