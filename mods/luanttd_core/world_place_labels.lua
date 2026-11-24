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
function L.describe(Sim,board,x,z,terrain_top,range)
  local distance2=(range or L.place_radius)^2
  local result={}
  for id,site in pairs(board.sites or {}) do
    local tile=site.tile
    if not site.closed and tile and type(site.name)=="string" then
      local tx,tz=Sim.xy(tile)
      local u,v=tx*2+.5,tz*2+.5
      local dist=(u-x)^2+(v-z)^2
      local t=dist<=distance2 and board.tiles[tile]
      if t and not t.stock_void then
        result[#result+1]={id=site.id or id,tile=tile,kind=site.kind,name=site.name,
          population=site.population,y=L.site_height(site,t,terrain_top and terrain_top(tile,tx,tz)),dist=dist}
      end
    end
  end
  table.sort(result,function(a,b) return a.dist==b.dist and a.id<b.id or a.dist<b.dist end)
  for i=#result,L.max_places+1,-1 do result[i]=nil end
  for _,row in ipairs(result) do row.dist=nil end
  return result
end
return L
