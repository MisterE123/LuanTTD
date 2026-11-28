-- Bind the pinned Found Town command to the same town/road state used
-- during normal growth. No map edits occur until the command re-quotes.
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local function m(name) return dofile(path..name..".lua") end
return function(Sim,Terrain,G)
  local Worldgen=m("openttd/town_worldgen")(G,m("openttd/town_growth_build")(G,m("openttd/town_growth_houses")))
  local Rules=m("openttd/town_founding")(Worldgen)
  local Names=m("openttd/stock_town_name")
  local Campaign=m("generated_campaign")
  local M={}
  local function board(s,growth,cfg)
    local physical=growth.road_board(s,true)
    local B={width=Sim.W,height=Sim.H,policy=cfg.founding_policy or 0,
      default_layout=cfg.layout or "original",separation=cfg.separation,capacity=Worldgen.POOL_MAX,
      name=Names.generate,towns={}}
    function B.tile(x,z) return physical.tile(x+1,z+1) end
    for _,id in ipairs(s.stock_town_growth.order) do
      local town,site=s.stock_town_growth.towns[id],s.sites[id]
      B.towns[#B.towns+1]={x=town.x-1,z=town.z-1,name=site.name,custom_name=site.custom_name}
    end
    return B,physical
  end
  function M.quote(s,owner,growth,req)
    local cfg=s.stock_generated_profile and s.stock_generated_profile.town_settings
    if not cfg or not s.stock_town_growth or not growth or not s.companies[owner] then return nil,"TOWN_FOUNDING_FORBIDDEN" end
    if type(req)~="table" or type(req.tile)~="number" or req.tile%1~=0 or not s.tiles[req.tile] then
      return nil,"INVALID_TOWN_LOCATION"
    end
    local B,physical=board(s,growth,cfg)
    local x,z=Sim.xy(req.tile)
    local q,why=Rules.quote(B,{x=x-1,z=z-1,size=req.size,city=req.city,layout=req.layout,
      name=req.name,nameparts=req.nameparts,random_location=req.random_location})
    if not q then return nil,why end
    q.tile,q.affordable,q.resolved_layout=req.tile,s.companies[owner].cash>=q.cost,
      Worldgen.resolve_layout(q.x,q.z,q.layout)
    return q,nil,physical
  end
  function M.apply(s,owner,growth,req,cost)
    local q,why,physical=M.quote(s,owner,growth,req)
    if not q then return nil,why end
    if q.cost~=cost then return nil,"TOWN_FOUNDING_PRICE_CHANGED" end
    local can,why=Rules.can_execute(q,s.companies[owner].cash)
    if not can then return nil,why end
    local town=Campaign.found(Sim,Terrain,s,Worldgen,G,physical,
      s.stock_generated_profile.town_settings,q,function() return Sim.stock_random_u32(s) end)
    town.cost,town.tile=q.cost,q.tile
    return town
  end
  return M
end
