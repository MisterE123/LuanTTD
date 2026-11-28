-- River generation can leave trees before the ordinary industry phase.
-- This seed's first mill overlaps one such already mature pregame tree.
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local core={settings={get=function() return nil end},get_dir_list=function(path)
  local files={}
  local p=assert(io.popen("ls -1 "..path))
  for name in p:lines() do files[#files+1]=name end
  p:close()
  return files
end}
local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
  width=256,depth=256,seed=1,relief=3,sea=0,coast=0,rivers=3,towns=3,
})
local origin=62944+1
local tile=s.tiles[Sim.id(226,246)]
assert(tile.stock_industry and tile.stock_industry.kind=="sawmill" and tile.stock_industry.origin==origin)
assert(not tile.wood and not tile.stock_clear_ground)
local mill=s.stock_timber_industries[tile.stock_industry.id]
assert(mill.layout==0 and s.sites[mill.site].tile==origin)
print("PASS ordinary hill-world startup: sawmill clears the admitted river tree on its flat footprint")
