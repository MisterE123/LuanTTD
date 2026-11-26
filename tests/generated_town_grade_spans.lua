-- Ordinary RC1 generation, not manually seeded streets or infrastructure.
local root="mods/luanttd_core/"
local function load(name) return dofile(root..name..".lua") end
local Sim,Terrain,Codec=load("sim"),load("openttd/terrain"),load("packed_campaign")
local Follow=load("openttd/yapf_road_follow")
local Read=load("road_yapf_board")
local Generation=load("campaign_generation")({settings={get=function() return nil end},
  get_dir_list=function(path)
    local names={}
    local p=assert(io.popen("ls -1 "..path))
    for n in p:lines() do names[#names+1]=n end
    p:close()
    return names
  end},root:gsub("/$",""),Sim,load("world_setup"))
local s=Generation.run({width=128,depth=128,seed=798,relief=3,sea=0,coast=0,rivers=2,towns=3})
assert(s.corner_grid.revision>0 and next(s.companies)==nil and s.chair==nil)
local slopes,settled=0,0
for id,t in ipairs(s.tiles) do
  if t.build=="road" and t.road_town and Sim.road_surface(s,id)~=0 then slopes=slopes+1 end
  if t.source_house and t.source_house.completed then settled=settled+1 end
  if t.stock_industry then assert(not (s.bridge_above and s.bridge_above[id])) end
end
assert(slopes>15 and settled>100)
local bridge_id,bridge=next(s.stock_road_bridges or {})
local tunnel_id,tunnel=next(s.stock_road_tunnels or {})
assert(bridge and tunnel,"The fixed seed must exercise both stock scouts, not just the fallback road")
local wet=0
for _,id in ipairs(bridge.middle) do
  assert(s.bridge_above[id]==bridge_id)
  if s.tiles[id].water_class=="river" then wet=wet+1 end
end
assert(wet>0)
for _,id in ipairs(tunnel.middle) do assert(s.tunnel_below[id]==tunnel_id and not s.tiles[id].road_tunnel_id) end
local function follow(w,span,kind)
  assert(w.sites[span.town].kind=="town")
  local board=Read(Sim,w,Follow)
  for _,id in ipairs({span.start,span["end"]}) do
    assert(w.tiles[id].road_town==span.town and Sim.mode_on(w,id,"road","Sample Bus Company"))
    local head=board.tile(id)
    local r=Follow.follow(board,{owner="Sample Bus Company"},id,Follow.direction_trackdir(head.dir))
    assert(r.ok and r.tile==head.other and r[kind] and r.skip==#span.middle)
  end
end
follow(s,bridge,"bridge");follow(s,tunnel,"tunnel")
local w=assert(Codec.decode(Codec.encode(s)))
follow(w,w.stock_road_bridges[bridge_id],"bridge")
follow(w,w.stock_road_tunnels[tunnel_id],"tunnel")
-- Failed-town sparse rollback cannot remove another town's structures,
-- and must not damage the water or surface terrain at span middles.
assert(not Sim.discard_generated_town_span(w,bridge.start,bridge.town+100))
assert(Sim.discard_generated_town_span(w,bridge.start,bridge.town))
assert(not w.stock_road_bridges[bridge_id] and not w.tiles[bridge["end"]].road_town)
for _,id in ipairs(bridge.middle) do
  assert(not w.bridge_above[id] and w.tiles[id].water_class==s.tiles[id].water_class)
end
assert(w.stock_road_tunnels[tunnel_id] and next(w.companies)==nil)
local owner="Sample Bus Company"
local company=Sim.company(s,owner)
company.stock_town_authority_ratings={}
for _,town in ipairs(s.sites) do company.stock_town_authority_ratings[town.id]=-100 end
local before=company.cash
assert(not Sim.remove_wood_bridge(s,owner,bridge.start,true))
assert(not Sim.remove_road_tunnel(s,owner,tunnel.start,true))
assert(company.cash==before and s.stock_road_bridges[bridge_id] and s.stock_road_tunnels[tunnel_id])
company.stock_town_authority_ratings={}
local ok,price=Sim.remove_wood_bridge(s,owner,bridge.start,true)
assert(ok and price>0 and company.cash==before)
assert(Sim.remove_wood_bridge(s,owner,bridge.start))
assert(company.cash==before-price and not s.stock_road_bridges[bridge_id])
before=company.cash
ok,price=Sim.remove_road_tunnel(s,owner,tunnel.start,true)
assert(ok and price==(#tunnel.middle+2)*110 and company.cash==before)
assert(Sim.remove_road_tunnel(s,owner,tunnel.start))
assert(company.cash==before-price and not s.stock_road_tunnels[tunnel_id])
print(("PASS RC1 seed 798: %d inclined streets, %d finished house parcels, %d river tiles under a public bridge, public bore, bidirectional route, exact save and council demolition")
  :format(slopes,settled,wet))
