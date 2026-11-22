-- Shared by the detached Lua and real Luanti worker tests; no test art or app.
return function(path)
  local function m(n) return dofile(path.."/"..n..".lua") end
  local Slope,Terrain=m("openttd/slope"),m("openttd/terrain")
  local TG=m("openttd/terragenesis")(Slope)
  local Rivers,Words=m("openttd/river_worldgen")(Slope),m("terrain_word")
  local seed=1751
  local base=TG.generate({width=128,depth=128,seed=seed,terrain_type=3,quantity_sea_lakes=0,
    rng_state=TG.startup_rng(seed)})
  local rivers,generated=Rivers.generate(base,TG.next_random,{
    original=false,terrain=Terrain,amount_of_rivers=1,min_river_length=16})
  assert(generated.rivers==2 and generated.terraform_committed==3 and generated.terraform_corner_edits==3)
  assert(rivers.river_tileloop_cursor==6090)
  local opts=Words.storage_options(rivers)
  return {raw=base,rivers=rivers,generated=generated,options=opts,words=Words,
    slope=Slope,terrain=Terrain,storage=m("world_storage"),stream=m("terrain_stream")(Slope),
    protocol=m("world_async_protocol")}
end
