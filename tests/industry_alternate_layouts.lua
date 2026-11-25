local mod="mods/luanttd_core/"
local function m(n) return dofile(mod..n..".lua") end
local Sim, Terrain=m("sim"),m("openttd/terrain")
local Coal=m("openttd/coal_industry")()
local Timber=Sim.timber_rules()
local CoalWorld=m("coal_industry_world")(Sim,Terrain,Coal)
local TimberWorld=m("timber_world")(Sim,Terrain,Timber)
local Art=m("industry_layout_art")
local Codec=m("packed_campaign")
local Projection=m("campaign_terrain_projection")
local assets={}
function assets.get_dir_list(path)
  local out={}
  local p=assert(io.popen("ls "..path))
  for file in p:lines() do out[#out+1]=file end
  p:close()
  return out
end
local visible=assert(Art.available(assets,mod:sub(1,-2)))
local Industry=m("openttd/industry_worldgen")(Coal,Timber,nil,nil,nil,visible)
Sim.W,Sim.H=64,64
local function new_map()
  local s=Sim.new(1751)
  s.tiles,s.sites={},{}
  s.corner_grid=Terrain.new(64,64,function() return 2 end,{freeform_edges=true})
  s.stock_generated_profile={width=64,depth=64}
  for i=1,64*64 do s.tiles[i]={terrain="grass",variant=1,h=2} end
  return s
end
local board={width=64,height=64,freeform=true,towns={{id=1,x=30,z=22}}}
function board.tile() return {kind="clear",slope=0,base=2,corner_height=2} end
local types={[0]={"coal_mine",{1,2,3}},[1]={"power_station",{1,2}},[2]={"sawmill",{1}}}
for id,desc in pairs(types) do
  for _,layout in ipairs(desc[2]) do
    local s=new_map()
    local name=desc[1]
    local plan,err=Industry.quote(board,id,15,19,layout,{terragenesis=false})
    assert(plan,err)
    local start=Sim.id(16,20)
    local mark=assert(Industry.record(plan,0,{year=1950}))
    local opts={record=mark,name="QA "..name}
    local place=id==2 and TimberWorld.place_generated or CoalWorld.place
    local record,cells,site=assert(place(s,name,start,opts))
    assert(record.layout==layout and record.x==15 and record.z==19 and site.tile)
    local check=assert(Codec.decode(Codec.encode(s)))
    local occupied={}
    for i,pos in ipairs(plan.cells) do
      local key=Sim.id(pos.x+1,pos.z+1)
      assert(cells[i].id==key and s.tiles[key].stock_industry.gfx==pos.gfx)
      local native=s.tiles[key].stock_industry
      assert(Art.alternate(native)==Art.asset(pos.gfx))
      assert(Projection.tile(check.tiles[key]).stock_industry.layout==layout)
      occupied[key]=true
    end
    assert(occupied[site.tile])
    for z=20,23 do for x=16,19 do
      local key=Sim.id(x,z)
      if not occupied[key] then assert(not s.tiles[key].stock_industry and not s.tiles[key].site) end
    end end
  end
end
print("PASS RC1 six alternate coal/power/sawmill layouts: source geometry, genuine media, empty origin holes, worker projection and checkpoint")
