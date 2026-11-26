local path="mods/luanttd_core/"
local Sim=dofile(path.."sim.lua")
local Rules=dofile(path.."openttd/industry_machinery_rc1.lua")
local Board=dofile(path.."industry_machinery_world.lua")(Sim,Rules,dofile(path.."oil_animation_registry.lua"))
local Projection=dofile(path.."campaign_terrain_projection.lua")
Sim.W,Sim.H=64,64
local a,b,c=Sim.id(6,8),Sim.id(8,12),Sim.id(56,55)
local function part(tile,gfx)
  local x,z=Sim.xy(tile)
  return {gfx=gfx,x=x-1,z=z-1,stage=3,completed=true}
end
local s={tiles={[a]={stock_industry={id=4}},[b]={stock_industry={id=6}},
  [c]={stock_industry={id=7,chain="oil"}}},stock_generated_profile={},
  passenger_house_clock={counter=0},stock_coal_industries={
    [4]={id=4,kind="coal_mine",tiles={part(a,0)}},
    [6]={id=6,kind="power_station",tiles={part(b,10)}}},
  stock_oil_industries={[7]={id=7,kind="oil_well",tiles={part(c,29)}}}}
local saved_random=Sim.stock_random_u32
local draws=0
Sim.stock_random_u32=function() draws=draws+1;return 0 end
local boot=Board.bind(s,true)
local unfinished=s.stock_coal_industries[4].tiles[1]
unfinished.completed,unfinished.stage,unfinished.construction_counter=false,2,3
assert(not boot.visit(a,0) and unfinished.completed and unfinished.stage==3 and draws==0)
assert(boot.visit(a,0) and boot.visit(b,0) and boot.visit(c,0) and draws==3)
assert(s.stock_oil_animated[c] and not s.stock_oil_industries[7].tiles[1].animated)
assert(not boot.visit(c,256) and not boot.visit(c,512) and s.stock_oil_animated[c] and draws==3,
  "A later pregame visit must not unregister an already activated pump")
local coal,power=s.stock_coal_industries[4].tiles[1],s.stock_coal_industries[6].tiles[1]
assert(coal.gfx==1 and coal.animation_frame==128 and power.animated)
local painted=Projection.registries(s,{{id=a},{id=b}})
assert(painted.stock_coal_industries[4].tiles[1].gfx==0)
assert(not painted.stock_coal_industries[4].tiles[1].animated)
local game=Board.bind(s)
game.animate(1024)
assert(coal.animation_frame==193 and power.animation_frame==1 and draws==3)
s.passenger_house_clock.counter=1025
local p=Sim.visible_machinery(s,1,1,12,12)
assert(p[a].gfx==1 and p[a].frame==193 and p[a].dir==1 and p[b].frame==1 and not p[c])
local far=Sim.visible_machinery(s,40,40,24,24)
assert(far[c].oil==0 and far[c].site==7 and not far[a] and not far[b])
local oil=s.stock_oil_industries[7].tiles[1]
oil.gfx,oil.animation_frame=32,3
assert(Sim.visible_machinery(s,40,40,24,24)[c].oil==11)
local static=Projection.registries(s,{{id=c}}).stock_oil_industries[7].tiles[1]
assert(static.gfx==29 and static.animation_frame==nil)
oil.gfx,oil.animation_frame=30,0
assert(not next(Sim.visible_machinery(s,20,20,12,12)))
for t=1025,1049 do game.animate(t) end
assert(not power.animated and power.animation_frame==0)
s.passenger_house_clock.counter=1544
assert(Sim.visible_machinery(s,1,1,12,12)[a].dir==-1)
game.animate(1544)
assert(coal.animation_frame<192)
assert(not game.visit(a,1824) and game.visit(a,2048) and draws==3)
assert(coal.gfx==0 and coal.stage==3 and not coal.animated)
assert(s.stock_oil_industries[7].tiles[1].gfx==30 and s.stock_oil_animated[c])
Sim.stock_random_u32=saved_random
print("PASS mounted stock machinery startup, game phases, rotating sheaves, timed sparks and sparse authoritative view")
