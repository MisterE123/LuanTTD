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
function L.describe(Sim,board,x,z,terrain_top)
  local result={}
  for id,site in pairs(board.sites or {}) do
    local tile=site.tile
    if not site.closed and tile and type(site.name)=="string" then
      local tx,tz=Sim.xy(tile)
      local u,v=tx*2+.5,tz*2+.5
      local dist=(u-x)^2+(v-z)^2
      local t=board.tiles[tile]
      if dist<=L.place_radius^2 and t and not t.stock_void then
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
