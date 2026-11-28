-- Stage one pre-existing river tree on a real, flat sawmill footprint.
-- Test the stock quote and generated commit, not direct industry stamping.
local mod="mods/luanttd_core"
local load=dofile
local function m(n) return load(mod.."/"..n..".lua") end
local Sim=m("sim")
local core={settings={get=function() return nil end},get_dir_list=function(path)
  local files={}
  local p=assert(io.popen("ls -1 "..path))
  for name in p:lines() do files[#files+1]=name end
  p:close()
  return files
end}
local world,ink
dofile=function(path)
  local module=load(path)
  if path==mod.."/generated_campaign.lua" then
    local generate=module.industries
    module.industries=function(_,terrain,s,...)
      world=s
      return generate(Sim,terrain,s,...)
    end
  elseif path==mod.."/openttd/industry_worldgen.lua" then
    return function(...)
      local rules=module(...)
      local quote=rules.quote
      rules.quote=function(board,id,x,z,layout,...)
        local plan,why=quote(board,id,x,z,layout,...)
        if not ink and id==2 and plan and not plan.leveling then
          local bit=plan.cells[1]
          local tile=Sim.id(bit.x+1,bit.z+1)
          assert(board.tile(bit.x,bit.z).kind=="clear" and not world.tiles[tile].wood)
          world.tiles[tile].wood={count=1,stage=3}
          assert(board.tile(bit.x,bit.z).kind=="trees")
          ink={tile=tile,origin=Sim.id(x+1,z+1),layout=layout}
          plan=assert(quote(board,id,x,z,layout,...))
          assert(not plan.leveling)
        end
        return plan,why
      end
      return rules
    end
  end
  return module
end
local ok,s=pcall(function()
  return m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
    width=256,depth=256,seed=1,relief=3,sea=0,coast=0,rivers=3,towns=3,
  })
end)
dofile=load
assert(ok,s)
local tile=s.tiles[assert(ink,"No eligible flat sawmill footprint").tile]
assert(tile.stock_industry and tile.stock_industry.kind=="sawmill" and tile.stock_industry.origin==ink.origin)
assert(not tile.wood and not tile.stock_clear_ground)
local mill=s.stock_timber_industries[tile.stock_industry.id]
assert(mill.layout==ink.layout and s.sites[mill.site].tile==ink.origin)
print("PASS generated industry clears an admitted river tree on a flat sawmill footprint")
